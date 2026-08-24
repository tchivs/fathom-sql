#!/usr/bin/env python3
"""Three-target byte-parity aggregate reporter (Phase 12, D-05; stdlib only).

Runs the identical parity suite on native / js / linear-wasm and proves
cross-target byte identity with two channels:

  1. per-target `moon test --target {t} --package parity` exit code — the
     MoonBit @test.T::snapshot mechanism compares each target against the SAME
     committed parity-tests/__snapshot__ files, so any serialized-result /
     diagnostic / span / lossless-replay byte divergence fails that target;
  2. a deterministic sha256 tree digest over the committed snapshot tree — the
     cross-target comparison object (linear-wasm cannot stdout-dump,
     parity/run_wasm.mbt "No println/env/host IO"), so rc + digest is the
     byte-parity proof (RESEARCH §7.2, A8; D-05, Pitfall 4).

The script is read-only: it never writes parity-tests/__snapshot__ and verifies the
tree digest is unchanged before/after the run (a target that wrote snapshots is
a read-only violation and fails the run). Failing fixtures are NAMED by
matching the snapshot-diff expected bytes (the '-' side of each moon Diff
block) against a content->filename index of the committed tree — moon does not
print snapshot filenames, so the content hash is the honest mapping, with the
failed-test label as a fallback identifier.

Exits 0 only when every target passed AND the snapshot tree is non-empty AND
the digest is identical across targets (one shared committed tree). Any
skipped/failed target, an empty or missing tree, or a tree change during the
run exits 1 (Pitfall 8 non-empty guard; T-12-03-01 skipped-target guard).

Usage:
  python3 scripts/compare_backends.py
  python3 scripts/compare_backends.py --targets native,js
  python3 scripts/compare_backends.py --snapshot-dir /tmp/empty-tree
"""

import argparse
import hashlib
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = "parity-tests"
DEFAULT_TARGETS = ("native", "js", "wasm")
VALID_TARGETS = set(DEFAULT_TARGETS)
DEFAULT_SNAPSHOT_DIR = ROOT / "parity-tests" / "__snapshot__"

# moon prints failed-test lines of the form:
#   [fathom/sql] test parity-tests/baseline_test.mbt:1440 ("<label>") failed
_FAILED_TEST_RE = re.compile(r'\]\s*test\s+\S+\s+\(["\']([^"\']+)["\']\)\s+failed')
# moon prints a final stats line:
#   Total tests: 570, passed: 569, failed: 1.
_STATS_RE = re.compile(
    r"Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)"
)


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def snapshot_tree_digest(directory: pathlib.Path):
    """Deterministic sha256 tree digest over every file under `directory`.

    Returns (digest, file_count). The digest is a sha256 over the sorted
    (relative_path, per-file sha256) pairs, so it is a pure function of the
    tree contents — re-running on the same tree yields the same digest.
    Returns ("", 0) for an empty/missing directory.
    """
    entries = []
    if directory.is_dir():
        for root, dirs, files in os.walk(directory):
            dirs.sort()
            for name in sorted(files):
                full = pathlib.Path(root) / name
                rel = full.relative_to(directory).as_posix()
                with full.open("rb") as fh:
                    data = fh.read()
                entries.append((rel, _sha256(data)))
    if not entries:
        return "", 0
    h = hashlib.sha256()
    for rel, digest in entries:
        h.update(rel.encode("utf-8"))
        h.update(b"\x00")
        h.update(digest.encode("ascii"))
        h.update(b"\x00")
    return h.hexdigest(), len(entries)


def build_content_index(directory: pathlib.Path):
    """{sha256(content): [relative filenames]} over every file in the tree.

    Used to map a moon snapshot-diff expected byte string back to the snapshot
    filename that produced it (moon prints content, not filenames).
    """
    index = {}
    if not directory.is_dir():
        return index
    for root, dirs, files in os.walk(directory):
        dirs.sort()
        for name in sorted(files):
            full = pathlib.Path(root) / name
            rel = full.relative_to(directory).as_posix()
            with full.open("rb") as fh:
                data = fh.read()
            index.setdefault(_sha256(data), []).append(rel)
    return index


def extract_failures(output_text: str, index):
    """Name failing snapshot fixtures from moon output.

    Returns (named, labels): `named` is the sorted list of snapshot filenames
    matched by content hash (the '-' side of each Diff block is byte-identical
    to the committed snapshot file); `labels` is the list of failed-test labels
    as fallback identifiers.
    """
    named = set()
    labels = [m.group(1) for m in _FAILED_TEST_RE.finditer(output_text)]
    lines = output_text.splitlines()
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if line.startswith("-") and not line.startswith(("----", "- ", "- expected", "---")):
            body = line[1:]
            if body.lstrip().startswith("{"):
                # Collect consecutive '-' expected-content lines: a multi-document
                # snapshot (e.g. lsp_json) prints each JSON doc on its own line.
                run = [body]
                j = i + 1
                while j < n:
                    nxt = lines[j]
                    if not nxt.startswith("-"):
                        break
                    if nxt.startswith(("----", "- ", "- expected", "---")):
                        break
                    nxt_body = nxt[1:]
                    if not nxt_body.lstrip().startswith("{"):
                        break
                    run.append(nxt_body)
                    j += 1
                content = "\n".join(run).encode("utf-8")
                for filename in index.get(_sha256(content), []):
                    named.add(filename)
                i = j
                continue
        i += 1
    return sorted(named), labels


def _extract_stats(output_text: str):
    m = _STATS_RE.search(output_text)
    if not m:
        return None
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)))


def run_target(target: str, index, moon: str = "moon"):
    """Run `moon test --target {t} --package parity`; capture rc + failures."""
    cmd = [moon, "test", "--target", target, "--package", PACKAGE]
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd=str(ROOT),
        )
    except OSError as exc:
        return {
            "target": target,
            "skipped": True,
            "rc": None,
            "output": str(exc),
            "failures": [],
            "labels": [],
            "stats": None,
        }
    output = proc.stdout + "\n" + proc.stderr
    named, labels = extract_failures(output, index)
    return {
        "target": target,
        "skipped": False,
        "rc": proc.returncode,
        "output": output,
        "failures": named,
        "labels": labels,
        "stats": _extract_stats(output),
    }


def main(argv):
    parser = argparse.ArgumentParser(
        description="Three-target (native/js/wasm) byte-parity aggregate report."
    )
    parser.add_argument(
        "--targets",
        default=",".join(DEFAULT_TARGETS),
        help="comma-separated target list (default: %s)" % ",".join(DEFAULT_TARGETS),
    )
    parser.add_argument(
        "--snapshot-dir",
        default=None,
        help="override the committed snapshot tree (default: parity-tests/__snapshot__); "
        "used to prove the empty/missing-tree non-empty guard.",
    )
    args = parser.parse_args(argv)

    targets = [t.strip() for t in args.targets.split(",") if t.strip()]
    for t in targets:
        if t not in VALID_TARGETS:
            print(
                "error: unknown target %r (expected %s)"
                % (t, "|".join(sorted(VALID_TARGETS))),
                file=sys.stderr,
            )
            return 1
    if not targets:
        print("error: no targets selected (--targets is empty)", file=sys.stderr)
        return 1

    snapshot_dir = (
        pathlib.Path(args.snapshot_dir) if args.snapshot_dir else DEFAULT_SNAPSHOT_DIR
    )
    if not snapshot_dir.is_dir():
        print(
            "error: snapshot tree not found: %s (non-empty guard, Pitfall 8)"
            % snapshot_dir,
            file=sys.stderr,
        )
        return 1
    digest, file_count = snapshot_tree_digest(snapshot_dir)
    if file_count == 0:
        print(
            "error: snapshot tree is empty: %s (non-empty guard, Pitfall 8)"
            % snapshot_dir,
            file=sys.stderr,
        )
        return 1

    index = build_content_index(snapshot_dir)
    results = [run_target(t, index) for t in targets]

    digest_after, file_count_after = snapshot_tree_digest(snapshot_dir)
    if digest_after != digest or file_count_after != file_count:
        print(
            "error: snapshot tree changed during the run (%d -> %d files) — "
            "compare_backends.py must be read-only over the committed tree"
            % (file_count, file_count_after),
            file=sys.stderr,
        )
        return 1

    # Per-target report.
    print(
        "compare-backends: three-target byte-parity aggregate (%s)"
        % ", ".join(targets)
    )
    print("  snapshot tree: %s (%d files)" % (snapshot_dir, file_count))
    all_pass = True
    for r in results:
        if r["skipped"]:
            status = "SKIP"
        elif r["rc"] == 0:
            status = "PASS"
        else:
            status = "FAIL"
        if status != "PASS":
            all_pass = False
        line = "  %-6s %s  rc=%s digest=%s" % (
            r["target"],
            status,
            r["rc"] if r["rc"] is not None else "n/a",
            digest,
        )
        if r["stats"]:
            total, passed, failed = r["stats"]
            line += " (tests=%d passed=%d failed=%d)" % (total, passed, failed)
        print(line)
        if status != "PASS":
            for fname in r["failures"]:
                print("    failing fixture: %s" % fname)
            for label in r["labels"]:
                print("    failing test: %r" % label)
            if not r["failures"] and not r["labels"]:
                print("    (no failing fixture/test named in moon output)")

    if not all_pass:
        print(
            "error: one or more targets failed or were skipped — the three-target "
            "matrix must all pass (T-12-03-01, Pitfall 8)",
            file=sys.stderr,
        )
        return 1

    print(
        "ok: %d targets passed, snapshot-tree sha256 digest identical across "
        "targets (%s)" % (len(targets), digest)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
