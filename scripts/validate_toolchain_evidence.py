#!/usr/bin/env python3
"""Phase 14-03 aggregate toolchain evidence validator/writer.

Consumes the per-platform `moon-toolchain.json` observation records produced by
the shared installers, validates exact three-record set, schema, requested/
reported/lock identity and digests, and on total success writes a deterministic
aggregate manifest. Any defect exits nonzero and leaves no output.

Usage:
  validate_toolchain_evidence.py --evidence-dir DIR --lock LOCK.json --output OUT.json
"""

import argparse
import base64
import json
import os
import sys

ALLOWED = ["linux-x86_64", "macos-aarch64", "windows-x86_64"]
ARCHIVE_FOR_RUNNER = {"linux-x86_64": "linux-x86_64", "macos-aarch64": "darwin-aarch64",
                      "windows-x86_64": "windows-x86_64"}
CORE_ROLES = {"core-tar.gz", "core-zip"}


def fail(msg):
    print(f"EVIDENCE-FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def check(cond, msg):
    if not cond:
        fail(msg)


def collect_records(evidence_dir):
    records = {}
    for root, _dirs, files in os.walk(evidence_dir):
        for fn in files:
            if fn != "moon-toolchain.json":
                continue
            path = os.path.join(root, fn)
            with open(path, encoding="utf-8") as f:
                try:
                    rec = json.load(f)
                except json.JSONDecodeError:
                    fail(f"malformed evidence JSON: {path}")
            target = rec.get("targetPlatform")
            check(isinstance(target, str) and target in ALLOWED,
                  f"unknown/absent targetPlatform in {path}: {target!r}")
            check(target not in records, f"duplicate evidence for {target} (first at {records.get(target)})")
            records[target] = rec
    check(len(records) == 3, f"expected exactly 3 platform records, got {len(records)}: {sorted(records)}")
    return records


def validate_record(rec, lock, target):
    check(rec.get("schemaVersion") == 1, f"{target}: bad schemaVersion")
    check(rec.get("requestedVersion") == lock.get("channelKey"), f"{target}: requested/lock mismatch")
    reported = rec.get("reportedVersion")
    check(isinstance(reported, str) and reported, f"{target}: empty reportedVersion")
    expected = base64.b64decode(lock["expectedMoonVersion"]).decode("utf-8", "replace")
    check(reported == expected, f"{target}: reportedVersion does not match lock")
    check(rec.get("runnerOS") and rec.get("runnerArch"), f"{target}: missing runner facts")
    check(rec.get("targetPlatform") == target, f"{target}: targetPlatform inconsistency")
    lock_binary = next((a for a in lock["archives"] if a["role"] == "binary"
                        and a["targetPlatform"] == ARCHIVE_FOR_RUNNER[target]), None)
    lock_core = next((a for a in lock["archives"] if a["role"] == "core" and a.get("url") == rec.get("coreUrl")), None)
    if lock_core is None:
        lock_core = next((a for a in lock["archives"] if a["role"] == "core" and a["targetPlatform"] == "core-tar.gz"), None)
    check(lock_binary is not None, f"{target}: lock lacks binary record")
    check(lock_core is not None, f"{target}: lock lacks core record")
    check(rec.get("binarySha256") == lock_binary["sha256"], f"{target}: binarySha256/lock mismatch")
    check(rec.get("binaryUrl") == lock_binary["url"], f"{target}: binaryUrl/lock mismatch")
    check(rec.get("coreSha256") == lock_core["sha256"], f"{target}: coreSha256/lock mismatch")
    check(rec.get("provenance") == lock_binary["provenance"], f"{target}: provenance mismatch")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--evidence-dir", required=True)
    p.add_argument("--lock", required=True)
    p.add_argument("--output", required=True)
    args = p.parse_args()

    with open(args.lock, encoding="utf-8") as f:
        lock = json.load(f)
    records = collect_records(args.evidence_dir)
    errors = []
    for target in ALLOWED:
        try:
            validate_record(records[target], lock, target)
        except SystemExit:
            errors.append(target)
    if errors:
        fail(f"failed targets: {errors}")

    aggregate = {
        "schemaVersion": 1,
        "channelKey": lock["channelKey"],
        "expectedMoonVersion": lock["expectedMoonVersion"],
        "platforms": [records[t] for t in ALLOWED],
        "lock": {
            "schemaVersion": lock["schemaVersion"],
            "provenance": lock.get("provenance", ""),
        },
    }
    out = os.path.abspath(args.output)
    d = os.path.dirname(out)
    os.makedirs(d, exist_ok=True)
    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(json.dumps(aggregate, indent=2, sort_keys=True) + "\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, out)
    print(f"AGGREGATE-WRITTEN {out}")
    print(f"platforms: {', '.join(ALLOWED)}")


if __name__ == "__main__":
    main()
