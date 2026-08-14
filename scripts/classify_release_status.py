#!/usr/bin/env python3
"""Fail-closed git working-tree status classifier for Phase 14 release readiness.

Parses ``git status --porcelain=v1 -z --untracked-files=all`` output
NUL-safely (including rename two-path records) and validates the working tree
against an exact allowlist so that phase commits never absorb session/runtime
drift or untracked generated/cache/duplicate paths (Phase 14 decisions
D-11..D-13, threat register T-14-27/T-14-29).

Commands
--------
snapshot --output PATH
    Records the porcelain status class of each currently-present pre-existing
    runtime path among the three named ``.planning/.omp-*`` paths into a
    deterministic JSON file. Requires ``--output PATH``. Fails if an unknown
    ``.planning/.omp-*`` path appears in the porcelain output (T-14-29).

classify --mode {pre-matrix-commit,post-matrix-commit} --snapshot PATH
         [--porcelain-command CMD]
    Validates the real porcelain output against the recorded snapshot:

      * runtime paths recorded by the snapshot must keep their exact recorded
        status class and may not broaden to another path;
      * ``pre-matrix-commit`` additionally permits the readiness-matrix
        transient and the classifier/test paths committed by this task;
      * ``post-matrix-commit`` permits no task transient.

    Every other modified/deleted/renamed product or planning path, and every
    untracked generated/cache/duplicate path, fails the classification.

Exit codes: 0 = PASS with deterministic JSON on stdout; 1 = classification
failure with diagnostics on stderr; 2 = usage error.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys

RUNTIME_PATHS = (
    ".planning/.omp-next-action.json",
    ".planning/.omp-task-results.json",
    ".planning/.omp-checkpoint.json",
)

# Paths owned by the Phase 14 plan 05 Task 3 commit. Permitted only in
# pre-matrix-commit mode (the matrix transient is created after the pre-commit
# classification and is forbidden once the matrix commit has landed).
TASK_TRANSIENT_PATHS = (
    ".planning/phases/14-release-hygiene-toolchain-pinning/14-RELEASE-READINESS.md",
    "scripts/classify_release_status.py",
    "scripts/tests/test_classify_release_status.py",
    "scripts/tests/__init__.py",
)

DEFAULT_PORCELAIN_COMMAND = "git status --porcelain=v1 -z --untracked-files=all"

VALID_MODES = ("pre-matrix-commit", "post-matrix-commit")

SCHEMA_VERSION = 1

# porcelain-v1 -z record: two status chars + space + path. Paths may contain
# any bytes except NUL; a path that itself looks like a status header is an
# inherent ambiguity of the format, so we only treat records whose leading
# two chars come from the porcelain status alphabet as headers.
_STATUS_RE = re.compile(rb"^([ MDARCU?!])([ MDARCU?!]) (.*)$", re.DOTALL)


def _decode(data: bytes) -> str:
    return data.decode("utf-8", "surrogateescape")


def _display(path: str) -> str:
    return path.encode("utf-8", "surrogateescape").decode("utf-8", "backslashreplace")


def parse_porcelain(data: bytes) -> list[dict]:
    """Parse NUL-delimited porcelain-v1 output into status entries.

    Rename/copy records consume the following bare source-path record, so a
    record's ``orig_path`` is populated only for ``R``/``C`` entries. Raises
    ValueError on malformed input (fail-closed: never guess).
    """
    records = data.split(b"\0")
    entries = []
    i = 0
    n = len(records)
    while i < n:
        rec = records[i]
        i += 1
        if not rec:
            continue
        m = _STATUS_RE.match(rec)
        if m is None:
            raise ValueError(
                "malformed porcelain record without a status header: %r"
                % _display(_decode(rec))
            )
        status = (m.group(1) + m.group(2)).decode("ascii")
        path = _decode(m.group(3))
        orig_path = None
        if m.group(1) in (b"R", b"C"):
            if i >= n or not records[i]:
                raise ValueError(
                    "rename/copy record missing source path for %r" % _display(path)
                )
            orig_path = _decode(records[i])
            i += 1
        entries.append(
            {"status": status, "path": path, "orig_path": orig_path}
        )
    return entries


def run_porcelain(command: str) -> list[dict]:
    proc = subprocess.run(command, shell=True, capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError(
            "porcelain command failed (rc=%d): %s\n%s"
            % (proc.returncode, command, proc.stderr.decode("utf-8", "replace"))
        )
    return parse_porcelain(proc.stdout)


def snapshot_runtime_paths(entries: list[dict]) -> tuple[list[str], list[dict]]:
    """Extract the recorded status class of each present named runtime path.

    Returns (problems, runtime_paths) where runtime_paths is sorted by path
    and each entry is {"path": ..., "status": ...}. An unknown
    ``.planning/.omp-*`` path in the porcelain output is a hard failure
    (T-14-29); other entries are not the snapshot's concern.
    """
    problems = []
    present: dict[str, str] = {}
    for entry in entries:
        path = entry["path"]
        if path.startswith(".planning/.omp-"):
            if path in RUNTIME_PATHS:
                present[path] = entry["status"]
            else:
                problems.append(
                    "unknown .omp-* runtime path present: %r (%s)"
                    % (_display(path), entry["status"])
                )
    runtime_paths = [
        {"path": path, "status": present[path]} for path in sorted(present)
    ]
    return problems, runtime_paths


def classify_entries(
    entries: list[dict], mode: str, snapshot: dict
) -> tuple[list[str], list[dict]]:
    """Classify porcelain entries against the snapshot allowlist.

    Returns (problems, allowlisted). Runtime paths recorded in the snapshot
    must be present with their exact recorded status class; the same path may
    not broaden to another path (a rename changes the path and therefore
    fails). In pre-matrix-commit mode the task-transient paths are permitted.
    """
    if mode not in VALID_MODES:
        return ["invalid mode: %r" % mode], []
    problems = []
    allowlisted = []
    snapshot_paths = {
        item["path"]: item["status"]
        for item in snapshot.get("runtimePaths", [])
    }
    seen_runtime = set()
    for entry in entries:
        path = entry["path"]
        if path in RUNTIME_PATHS:
            if path not in snapshot_paths:
                problems.append(
                    "runtime path %r present but not recorded in snapshot (%s)"
                    % (_display(path), entry["status"])
                )
            elif entry["status"] != snapshot_paths[path]:
                problems.append(
                    "runtime path %r status class changed: recorded %r, "
                    "observed %r"
                    % (_display(path), snapshot_paths[path], entry["status"])
                )
            else:
                allowlisted.append(
                    {"path": path, "status": entry["status"], "kind": "runtime"}
                )
            seen_runtime.add(path)
        elif path.startswith(".planning/.omp-"):
            problems.append(
                "unknown .omp-* runtime path present: %r (%s)"
                % (_display(path), entry["status"])
            )
        elif mode == "pre-matrix-commit" and path in TASK_TRANSIENT_PATHS:
            allowlisted.append(
                {"path": path, "status": entry["status"], "kind": "task-transient"}
            )
        else:
            suffix = (
                " (renamed from %r)" % _display(entry["orig_path"])
                if entry["orig_path"]
                else ""
            )
            problems.append(
                "unexpected %s entry: %r%s"
                % (entry["status"], _display(path), suffix)
            )
    for path, status in snapshot_paths.items():
        if path not in seen_runtime:
            problems.append(
                "runtime path %r no longer present (recorded status %r)"
                % (_display(path), status)
            )
    allowlisted.sort(key=lambda item: item["path"])
    return problems, allowlisted


def _run_snapshot(output: str, porcelain_command: str) -> int:
    if not output:
        print("classify_release_status: snapshot requires --output PATH", file=sys.stderr)
        return 2
    try:
        entries = run_porcelain(porcelain_command)
    except (RuntimeError, ValueError) as exc:
        print("classify_release_status: snapshot FAIL: %s" % exc, file=sys.stderr)
        return 1
    problems, runtime_paths = snapshot_runtime_paths(entries)
    if problems:
        for problem in problems:
            print("classify_release_status: snapshot FAIL: %s" % problem, file=sys.stderr)
        return 1
    payload = {
        "schemaVersion": SCHEMA_VERSION,
        "command": "snapshot",
        "runtimePaths": runtime_paths,
    }
    print(json.dumps(payload, sort_keys=True, indent=2))
    with open(output, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, sort_keys=True, indent=2)
        handle.write("\n")
    return 0


def _load_snapshot(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError("snapshot file %r is not a JSON object" % path)
    runtime_paths = payload.get("runtimePaths", [])
    if not isinstance(runtime_paths, list):
        raise ValueError("snapshot file %r has non-list runtimePaths" % path)
    for item in runtime_paths:
        if not isinstance(item, dict) or "path" not in item or "status" not in item:
            raise ValueError("snapshot file %r has malformed runtimePaths entry" % path)
    return payload


def _run_classify(
    mode: str, snapshot_path: str, porcelain_command: str
) -> int:
    if mode not in VALID_MODES:
        print(
            "classify_release_status: classify requires --mode "
            "{%s}" % ",".join(VALID_MODES),
            file=sys.stderr,
        )
        return 2
    if not snapshot_path:
        print("classify_release_status: classify requires --snapshot PATH", file=sys.stderr)
        return 2
    try:
        snapshot = _load_snapshot(snapshot_path)
        entries = run_porcelain(porcelain_command)
    except FileNotFoundError:
        print(
            "classify_release_status: classify FAIL: snapshot file not found: %r"
            % snapshot_path,
            file=sys.stderr,
        )
        return 2
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print("classify_release_status: classify FAIL: %s" % exc, file=sys.stderr)
        return 1
    except RuntimeError as exc:
        print("classify_release_status: classify FAIL: %s" % exc, file=sys.stderr)
        return 1
    problems, allowlisted = classify_entries(entries, mode, snapshot)
    if problems:
        for problem in problems:
            print("classify_release_status: classify FAIL: %s" % problem, file=sys.stderr)
        return 1
    payload = {
        "schemaVersion": SCHEMA_VERSION,
        "command": "classify",
        "mode": mode,
        "verdict": "PASS",
        "porcelainCommand": porcelain_command,
        "allowlisted": allowlisted,
    }
    print(json.dumps(payload, sort_keys=True, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="classify_release_status.py",
        description="Fail-closed porcelain-v1/-z working-tree status classifier.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    snapshot = subparsers.add_parser(
        "snapshot", help="record present .omp-* runtime statuses to a JSON file"
    )
    snapshot.add_argument("--output", required=True, help="snapshot JSON output path")
    snapshot.add_argument(
        "--porcelain-command",
        default=DEFAULT_PORCELAIN_COMMAND,
        help="command producing porcelain-v1 -z status (default: %(default)s)",
    )

    classify = subparsers.add_parser(
        "classify", help="classify the working tree against a snapshot allowlist"
    )
    classify.add_argument(
        "--mode", required=True, choices=VALID_MODES, help="classification mode"
    )
    classify.add_argument("--snapshot", required=True, help="snapshot JSON path")
    classify.add_argument(
        "--porcelain-command",
        default=DEFAULT_PORCELAIN_COMMAND,
        help="command producing porcelain-v1 -z status (default: %(default)s)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "snapshot":
        return _run_snapshot(args.output, args.porcelain_command)
    if args.command == "classify":
        return _run_classify(args.mode, args.snapshot, args.porcelain_command)
    parser.print_usage(sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
