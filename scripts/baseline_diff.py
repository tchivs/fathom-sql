#!/usr/bin/env python3
"""D-08 baseline snapshot shape-diff reporter (Python stdlib only).

Usage:
  python3 scripts/baseline_diff.py --left parity-tests/__snapshot__ \\
      --right parity-tests/__snapshot__ \\
      --approve .planning/phases/09-dialect-boundary-and-neutral-naming/approved-changes.md

  --frozen and --current are self-documenting aliases for --left and --right
  (used by scripts/diff_parity.py's regenerated-comparison wrapper, D-03).

Walks both snapshot directories, compares every *.json file, and groups
differences into:

  (a) approved  — explained by the --approve register patterns
      (schema_version namespace values, FATHOM-* code prefixes, new
      dialect/profile/exact_release fields, export/source/serverInfo
      strings; D-08/D-09/D-10);
  (b) unexpected — everything else.

Exit codes: 0 when there are no unexpected diffs (approved diffs are
allowed), 1 when any unexpected diff exists. Mirrors the
corpus/tools/check_keywords.py loop shape: problems list, per-line
reporting, non-zero exit, trailing `ok: ...` success line.

Snapshot files may hold more than one JSON document (the LSP homomorph
files are two JSON documents, one per line); every non-empty line is
parsed independently.  Non-JSON content is compared byte-wise and any
difference is unexpected.
"""

import argparse
import json
import os
import sys
from collections import Counter

# ---------------------------------------------------------------------------
# Approve register parsing
# ---------------------------------------------------------------------------


def parse_approve(path):
    """Parse the machine-readable section of the register.

    Line forms:
      key:<key>: <old> -> <new>   exact value replacement under a JSON key
      prefix: <old> -> <new>      prefix replacement of any JSON string value
      field: <name>               key may appear where it was absent
    Blank lines, comments (#), and code fences (```) are ignored.
    """
    key_rules = {}
    prefix_rules = []
    fields = set()
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError as err:
        print("error: cannot read approve register %s: %s" % (path, err), file=sys.stderr)
        sys.exit(2)
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("```"):
            continue
        if line.startswith("field:"):
            name = line[len("field:"):].strip()
            if name:
                fields.add(name)
        elif line.startswith("key:"):
            rest = line[len("key:"):]
            key, _, mapping = rest.partition(":")
            old, _, new = mapping.partition("->")
            key = key.strip()
            old = old.strip()
            new = new.strip()
            if key and old and new:
                key_rules[(key, old)] = new
        elif line.startswith("prefix:"):
            rest = line[len("prefix:"):]
            old, _, new = rest.partition("->")
            old = old.strip()
            new = new.strip()
            if old and new:
                prefix_rules.append((old, new))
    return {"key": key_rules, "prefix": prefix_rules, "field": fields}


# ---------------------------------------------------------------------------
# Snapshot tree walking
# ---------------------------------------------------------------------------


def walk_json(value, path, pairs):
    """Collect every leaf (path, value) pair of a parsed JSON value."""
    if isinstance(value, dict):
        for key, child in value.items():
            walk_json(child, path + (key,), pairs)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            walk_json(child, path + ("[]", index), pairs)
    else:
        pairs.append((path, value))


def collect_pairs(text):
    """Parse a snapshot file into (path, value) leaf pairs.

    Returns None when no line parses as JSON (defensive: non-JSON content
    is compared byte-wise instead).
    """
    pairs = []
    parsed_any = False
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            doc = json.loads(line)
        except ValueError:
            if not parsed_any:
                return None
            continue
        parsed_any = True
        walk_json(doc, (), pairs)
    if not parsed_any:
        return None
    return pairs


def values_by_path(pairs):
    """path -> Counter of leaf values (duplicates are significant)."""
    grouped = {}
    for path, value in pairs:
        grouped.setdefault(path, Counter())[value] += 1
    return grouped


# ---------------------------------------------------------------------------
# Diff classification
# ---------------------------------------------------------------------------


def is_approved_value(old, new, path, rules):
    """True when an old->new value transition is pre-declared."""
    key = path[-1] if path and isinstance(path[-1], str) else None
    if key is not None and (key, old) in rules["key"]:
        if rules["key"][(key, old)] == new:
            return True
    for prefix_old, prefix_new in rules["prefix"]:
        if isinstance(old, str) and isinstance(new, str):
            if old.startswith(prefix_old) and new == prefix_new + old[len(prefix_old):]:
                return True
    return False


def classify(left_pairs, right_pairs, rules):
    """Group per-path leaf diffs into (approved, unexpected) lists."""
    left = values_by_path(left_pairs)
    right = values_by_path(right_pairs)
    approved = []
    unexpected = []
    for path in sorted(set(left) | set(right)):
        removed = left.get(path, Counter()) - right.get(path, Counter())
        added = right.get(path, Counter()) - left.get(path, Counter())
        # Pair removed values with added values at the same path via approved
        # transitions (e.g. a v1 schema namespace -> its neutral replacement). Keep
        # pairing while BOTH sides still hold values: multi-document snapshot
        # files (LSP homomorphs — a parse envelope plus a format envelope)
        # legitimately carry the same leaf value at the same path more than
        # once, and every occurrence must pair or the gate reports phantom
        # unexpected diffs (09-02 Rule 1 fix).
        for old in list(removed.keys()):
            for new in list(added.keys()):
                while removed.get(old, 0) > 0 and added.get(new, 0) > 0 and is_approved_value(old, new, path, rules):
                    approved.append((path, old, new, "approved change"))
                    removed[old] -= 1
                    added[new] -= 1
        for old, count in removed.items():
            for _ in range(count):
                unexpected.append((path, old, None, "removed value not explained"))
        for new, count in added.items():
            key = path[-1] if path and isinstance(path[-1], str) else None
            for _ in range(count):
                if key is not None and key in rules["field"]:
                    approved.append((path, None, new, "approved new field"))
                else:
                    unexpected.append((path, None, new, "new value not explained"))
    return approved, unexpected


def diff_file(left_text, right_text, rules):
    """Diff one snapshot file; returns (approved, unexpected)."""
    if left_text == right_text:
        return [], []
    left_pairs = collect_pairs(left_text)
    right_pairs = collect_pairs(right_text)
    if left_pairs is None or right_pairs is None:
        # Non-JSON content: any byte difference is unexpected.
        return [], [((), left_text[:80], right_text[:80], "non-JSON byte difference")]
    return classify(left_pairs, right_pairs, rules)


def format_path(path):
    if not path:
        return "<file>"
    return ".".join(str(part) for part in path)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main(argv):
    parser = argparse.ArgumentParser(
        description="Group baseline snapshot diffs into approved vs unexpected."
    )
    # --frozen/--current are self-documenting aliases used by the
    # scripts/diff_parity.py wrapper (D-03); --left/--right stay canonical.
    parser.add_argument("--left", "--frozen", dest="left", required=True,
                        help="left snapshot directory")
    parser.add_argument("--right", "--current", dest="right", required=True,
                        help="right snapshot directory")
    parser.add_argument("--approve", required=True, help="approved-change register")
    args = parser.parse_args(argv)

    rules = parse_approve(args.approve)
    left_names = set()
    right_names = set()
    for directory, target in ((args.left, left_names), (args.right, right_names)):
        if not os.path.isdir(directory):
            print("error: snapshot directory not found: %s" % directory, file=sys.stderr)
            return 2
        for name in os.listdir(directory):
            if name.endswith(".json"):
                target.add(name)

    all_names = sorted(left_names | right_names)
    total_approved = 0
    total_unexpected = 0
    for name in all_names:
        left_path = os.path.join(args.left, name)
        right_path = os.path.join(args.right, name)
        if name not in left_names or name not in right_names:
            side = "added" if name not in left_names else "removed"
            total_unexpected += 1
            print("error: %s: snapshot file %s on the %s side" % (name, side, side), file=sys.stderr)
            continue
        with open(left_path, encoding="utf-8") as fh:
            left_text = fh.read()
        with open(right_path, encoding="utf-8") as fh:
            right_text = fh.read()
        approved, unexpected = diff_file(left_text, right_text, rules)
        for path, old, new, kind in approved:
            total_approved += 1
            print(
                "approved: %s: %s: %r -> %r (%s)"
                % (name, format_path(path), old, new, kind)
            )
        for path, old, new, kind in unexpected:
            total_unexpected += 1
            print(
                "error: %s: unexpected diff at %s: %r -> %r (%s)"
                % (name, format_path(path), old, new, kind),
                file=sys.stderr,
            )

    print(
        "ok: %d snapshots, %d approved diffs, %d unexpected"
        % (len(all_names), total_approved, total_unexpected)
    )
    return 1 if total_unexpected > 0 else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
