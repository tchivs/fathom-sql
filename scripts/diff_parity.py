#!/usr/bin/env python3
"""D-03 frozen-vs-current Doris snapshot diff harness (Python stdlib only).

Usage:
  python3 scripts/diff_parity.py --frozen-only
  python3 scripts/diff_parity.py --approve <register> [--package parity-tests]
  python3 scripts/diff_parity.py --frozen-only --left <frozen> --right <current>
  python3 scripts/diff_parity.py --approve <register> --left <frozen> --right <current>

The committed snapshot tree at parity-tests/__snapshot__ is the frozen baseline.
"Current" output is REGENERATED in a temp directory by running
`moon test --update --package parity-tests` with the working snapshot tree moved
aside and restored afterwards (zero working-tree residue), so the proof of
frozenness is a REGENERATED comparison — not the vacuous left==right
self-check that a committed-tree invocation of scripts/baseline_diff.py
performs (D-03, RESEARCH §6.2).

Modes:
  --frozen-only            CI mode. Regenerates the current tree and FAILS
                           (exit 1) on ANY difference between the committed
                           tree and the regenerated tree (byte + path dual
                           channel). The approved-changes register is NOT
                           consulted, so an empty or forged register cannot
                           mask drift.
  --approve <register>     Local mode. Regenerates the current tree, then
                           groups each diff into approved (explained by the
                           register's key:/prefix:/field: rows) vs unexpected
                           via the scripts/baseline_diff.py engine; exits 1
                           when any unexpected diff exists.

Optional --left/--right bypass the regeneration lifecycle and compare two
existing snapshot trees directly (used by the harness tests and by manual
tree-to-tree inspection).

Exit codes: 0 = clean / no unexpected diffs; 1 = any frozen-vs-current
difference (--frozen-only) or any unexpected diff (--approve); 2 = snapshot
tree missing, a lifecycle step failed (the restore path already returned the
committed tree), or CLI misuse.
"""

import argparse
import os
import pathlib
import shutil
import signal
import subprocess
import sys
import tempfile

# Make the sibling scripts/ package importable when run as
# `python3 scripts/diff_parity.py` (sys.path[0] is the script's directory).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# Reuse the proven approved-vs-unexpected engine unchanged (D-08):
# parse_approve / diff_file / format_path / the exit-0/1/2 contract.
import baseline_diff  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[1]

# ---------------------------------------------------------------------------
# Interruption handling
# ---------------------------------------------------------------------------


def _sigterm_handler(signum, frame):
    # SIGTERM is not catchable by try/finally alone; raising here lets the
    # lifecycle's finally block restore the committed snapshot tree (T-12-02-04).
    raise SystemExit(2)


# ---------------------------------------------------------------------------
# Regeneration lifecycle
# ---------------------------------------------------------------------------


def _snapshot_tree_is_dirty(repo_root):
    """True when parity-tests/__snapshot__ has uncommitted changes; None if unknown."""
    try:
        proc = subprocess.run(
            ["git", "status", "--porcelain", "--", "parity-tests/__snapshot__"],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None
    if proc.returncode != 0:
        return None
    return bool(proc.stdout.strip())


def _restore_committed(snap, hold):
    """Return the committed snapshot tree to parity-tests/__snapshot__."""
    if snap.exists():
        shutil.rmtree(snap)
    shutil.move(str(hold), str(snap))


def regenerate_current(package, repo_root):
    """Regenerate the current snapshot tree in a temp directory.

    Returns (frozen_dir, current_dir, tmp_root, exit_code). On any lifecycle
    failure or interruption the committed parity-tests/__snapshot__ tree is restored
    before returning (the restore-on-failure path, RESEARCH §6.2 / A9), and
    exit_code is 2.
    """
    snap = repo_root / "parity-tests" / "__snapshot__"
    if not snap.is_dir():
        print("error: frozen snapshot tree not found: %s" % snap, file=sys.stderr)
        return None, None, None, 2

    dirty = _snapshot_tree_is_dirty(repo_root)
    if dirty:
        print(
            "warning: parity-tests/__snapshot__ has uncommitted changes — the frozen "
            "baseline below is the working tree, not HEAD",
            file=sys.stderr,
        )

    tmp_root = pathlib.Path(tempfile.mkdtemp(prefix="diff-parity-"))
    frozen = tmp_root / "frozen"
    current = tmp_root / "current"
    hold = tmp_root / "snapshot-hold"

    shutil.copytree(snap, frozen)  # frozen = copy of the committed tree
    restored = False
    try:
        # Move the working tree aside so the regenerated tree lands at the
        # canonical parity-tests/__snapshot__ path; the committed bytes are never
        # written in place (zero working-tree residue).
        shutil.move(str(snap), str(hold))  # working tree -> temp hold dir
        cmd = ["moon", "test", "--update", "--package", package]
        print("diff-parity: regenerating snapshot tree: %s" % " ".join(cmd))
        proc = subprocess.run(cmd, cwd=str(repo_root))
        if proc.returncode != 0:
            print(
                "error: %s failed (exit %d); committed snapshot tree restored"
                % (" ".join(cmd), proc.returncode),
                file=sys.stderr,
            )
            _restore_committed(snap, hold)
            restored = True
            return frozen, current, tmp_root, 2
        if not snap.is_dir():
            print(
                "error: %s produced no parity-tests/__snapshot__; committed tree restored"
                % " ".join(cmd),
                file=sys.stderr,
            )
            _restore_committed(snap, hold)
            restored = True
            return frozen, current, tmp_root, 2
        shutil.move(str(snap), str(current))  # regenerated tree -> temp current dir
        _restore_committed(snap, hold)  # committed tree -> back in the working tree
        restored = True
        return frozen, current, tmp_root, 0
    finally:
        if not restored and hold.exists():
            # Interruption / crash path (SIGTERM/SIGINT handled): restore the
            # committed bytes before propagating.
            _restore_committed(snap, hold)
            print(
                "diff-parity: restored committed snapshot tree after interruption",
                file=sys.stderr,
            )


# ---------------------------------------------------------------------------
# Comparison
# ---------------------------------------------------------------------------


def _snapshot_names(directory):
    return {name for name in os.listdir(directory) if name.endswith(".json")}


def compare_trees(frozen_dir, current_dir):
    """Byte + path dual-channel compare of two snapshot trees.

    Returns (all_names, differences) where differences is a list of
    (name, kind) with kind in {"added", "removed", "modified"}.
    """
    frozen_names = _snapshot_names(frozen_dir)
    current_names = _snapshot_names(current_dir)
    all_names = sorted(frozen_names | current_names)
    diffs = []
    for name in all_names:
        if name not in frozen_names:
            diffs.append((name, "added"))
        elif name not in current_names:
            diffs.append((name, "removed"))
        else:
            left_path = os.path.join(frozen_dir, name)
            right_path = os.path.join(current_dir, name)
            with open(left_path, "rb") as fh:
                left_bytes = fh.read()
            with open(right_path, "rb") as fh:
                right_bytes = fh.read()
            if left_bytes != right_bytes:
                diffs.append((name, "modified"))
    return all_names, diffs


# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------


def run_frozen_only(frozen_dir, current_dir):
    """CI mode: FAIL on ANY difference; the approved-changes register is never
    consulted (an empty register cannot mask drift — T-12-02-02/05)."""
    all_names, diffs = compare_trees(frozen_dir, current_dir)
    for name, kind in diffs:
        if kind == "added":
            print(
                "error: %s: snapshot file only on the current side" % name,
                file=sys.stderr,
            )
        elif kind == "removed":
            print(
                "error: %s: snapshot file only on the frozen side" % name,
                file=sys.stderr,
            )
        else:
            print(
                "error: %s: snapshot differs (frozen vs current)" % name,
                file=sys.stderr,
            )
    print(
        "ok: %d snapshots, %d frozen-vs-current differences"
        % (len(all_names), len(diffs))
    )
    return 1 if diffs else 0


def run_approve(frozen_dir, current_dir, register):
    """Local mode: classify diffs as approved vs unexpected via the baseline_diff
    engine; exit 1 when any unexpected diff exists (D-07 — unexpected diffs
    route to human adjudication, never silently absorbed)."""
    rules = baseline_diff.parse_approve(register)
    frozen_names = _snapshot_names(frozen_dir)
    current_names = _snapshot_names(current_dir)
    all_names = sorted(frozen_names | current_names)
    total_approved = 0
    total_unexpected = 0
    for name in all_names:
        left_path = os.path.join(frozen_dir, name)
        right_path = os.path.join(current_dir, name)
        if name not in frozen_names or name not in current_names:
            side = "added" if name not in frozen_names else "removed"
            total_unexpected += 1
            print(
                "error: %s: snapshot file %s on the %s side" % (name, side, side),
                file=sys.stderr,
            )
            continue
        with open(left_path, encoding="utf-8") as fh:
            left_text = fh.read()
        with open(right_path, encoding="utf-8") as fh:
            right_text = fh.read()
        approved, unexpected = baseline_diff.diff_file(left_text, right_text, rules)
        for path, old, new, kind in approved:
            total_approved += 1
            print(
                "approved: %s: %s: %r -> %r (%s)"
                % (name, baseline_diff.format_path(path), old, new, kind)
            )
        for path, old, new, kind in unexpected:
            total_unexpected += 1
            print(
                "error: %s: unexpected diff at %s: %r -> %r (%s)"
                % (name, baseline_diff.format_path(path), old, new, kind),
                file=sys.stderr,
            )

    print(
        "ok: %d snapshots, %d approved diffs, %d unexpected"
        % (len(all_names), total_approved, total_unexpected)
    )
    return 1 if total_unexpected > 0 else 0


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main(argv):
    parser = argparse.ArgumentParser(
        description="Prove Doris frozen-snapshot parity by regenerated comparison."
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--frozen-only",
        action="store_true",
        help="CI mode: regenerate the current tree and FAIL on ANY difference "
        "(approved-changes register NOT consulted).",
    )
    mode.add_argument(
        "--approve",
        metavar="REGISTER",
        help="local mode: regenerate the current tree and classify diffs as "
        "approved (register) vs unexpected; exit 1 when unexpected > 0.",
    )
    parser.add_argument(
        "--package",
        default="parity",
        help="moon package whose snapshot tree is regenerated (default: parity).",
    )
    parser.add_argument(
        "--left",
        help="override the frozen snapshot tree (skips regeneration).",
    )
    parser.add_argument(
        "--right",
        help="override the current snapshot tree (skips regeneration).",
    )
    parser.add_argument(
        "--keep-temp",
        action="store_true",
        help="keep the temp frozen/current trees for inspection.",
    )
    args = parser.parse_args(argv)

    if (args.left is None) != (args.right is None):
        print("error: --left and --right must be provided together", file=sys.stderr)
        return 2

    tmp_root = None
    if args.left is not None:
        frozen = pathlib.Path(args.left)
        current = pathlib.Path(args.right)
        for directory in (frozen, current):
            if not directory.is_dir():
                print(
                    "error: snapshot directory not found: %s" % directory,
                    file=sys.stderr,
                )
                return 2
    else:
        signal.signal(signal.SIGTERM, _sigterm_handler)
        frozen, current, tmp_root, rc = regenerate_current(args.package, ROOT)
        if rc != 0:
            if tmp_root is not None and not args.keep_temp:
                shutil.rmtree(tmp_root, ignore_errors=True)
            return rc

    try:
        if args.frozen_only:
            return run_frozen_only(frozen, current)
        return run_approve(frozen, current, args.approve)
    finally:
        if args.keep_temp and tmp_root is not None:
            print("diff-parity: kept temp trees at %s" % tmp_root)
        elif tmp_root is not None:
            shutil.rmtree(tmp_root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
