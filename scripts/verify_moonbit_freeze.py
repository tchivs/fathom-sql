#!/usr/bin/env python3
"""Phase 14 freeze verifier: exact-set, identity, attestation and atomic lock.

stdlib only. Fail-closed: on any defect exits nonzero and never creates or
retains the requested lock output.

Usage:
  verify_moonbit_freeze.py --evidence EV.json --attestations ATT.jsonl --output LOCK.json
"""

import argparse
import base64
import json
import os
import sys

SCHEMA_VERSION = 1
BINARY_TARGETS = ["linux-x86_64", "macos-aarch64", "windows-x86_64"]  # runner target names
BINARY_ARCHIVE_TARGETS = ["linux-x86_64", "darwin-aarch64", "windows-x86_64"]  # archive record names
CORE_ROLES = ["core-tar.gz", "core-zip"]
ALL_ARCHIVE_ROLES = BINARY_ARCHIVE_TARGETS + CORE_ROLES
ARCHIVE_FOR_RUNNER = {"linux-x86_64": "linux-x86_64", "macos-aarch64": "darwin-aarch64", "windows-x86_64": "windows-x86_64"}
EXPECTED_ARCH = {"linux-x86_64": "x86_64", "macos-aarch64": "arm64", "windows-x86_64": "x86_64"}
HEX64 = set("0123456789abcdef")


def fail(msg):
    print(f"VERIFY-FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def is_hex64(s):
    return isinstance(s, str) and len(s) == 64 and all(ch in HEX64 for ch in s)


def check(cond, msg):
    if not cond:
        fail(msg)


def validate_archives(archives):
    check(isinstance(archives, list) and len(archives) == 5, "need exactly 5 archive records")
    roles = [a.get("targetPlatform") for a in archives]
    check(sorted(roles) == sorted(ALL_ARCHIVE_ROLES), f"archive roles not exact set: {roles}")
    for a in archives:
        role = a["targetPlatform"]
        check(a.get("role") in ("binary", "core"), f"{role}: bad role")
        check(a.get("layoutOk") is True, f"{role}: layout not verified")
        check(isinstance(a.get("memberCount"), int) and a["memberCount"] > 0, f"{role}: no members")
        check(is_hex64(a.get("computedSha256", "")), f"{role}: bad computed digest")
        url = a.get("url", "")
        check(url.startswith("https://cli.moonbitlang.com/"), f"{role}: non-official URL {url}")
        if a["role"] == "binary":
            check(a.get("provenance") == "official-sidecar", f"{role}: must use official sidecar")
            check(is_hex64(a.get("sidecarDigest", "")), f"{role}: bad sidecar digest")
            check(a["sidecarDigest"] == a["computedSha256"], f"{role}: sidecar != computed")
        else:
            check(a.get("provenance") == "recorded-digest", f"{role}: core must be recorded-digest")
            check(a.get("officialChecksumAvailable") is False, f"{role}: core official checksum must be documented absent")


def validate_runners(runners, archives):
    check(isinstance(runners, list) and len(runners) == 3, f"need exactly 3 runner records, got {len(runners)}")
    targets = sorted(r.get("targetPlatform") for r in runners)
    check(targets == sorted(BINARY_TARGETS), f"runner targets not exact set: {targets}")
    raw_versions = set()
    for r in runners:
        t = r["targetPlatform"]
        check(r.get("exitCode") == 0, f"{t}: nonzero moon version exit")
        check(r.get("hostArch") == EXPECTED_ARCH[t], f"{t}: host arch {r.get('hostArch')} != {EXPECTED_ARCH[t]}")
        check(r.get("execArch") == EXPECTED_ARCH[t], f"{t}: exec arch {r.get('execArch')} != {EXPECTED_ARCH[t]}")
        raw = r.get("rawVersionBase64")
        check(isinstance(raw, str) and raw, f"{t}: missing raw version")
        try:
            decoded = base64.b64decode(raw, validate=True)
        except Exception:
            fail(f"{t}: raw version not valid base64")
        check(decoded.strip(), f"{t}: empty raw version")
        raw_versions.add(decoded)
        arch = next((a for a in archives if a["targetPlatform"] == ARCHIVE_FOR_RUNNER.get(t)), None)
        check(arch is not None and r.get("archiveSha256") == arch["computedSha256"],
              f"{t}: runner archive digest does not match lock record")
    check(len(raw_versions) == 1, f"raw moon version not byte-identical across runners: {len(raw_versions)} variants")
    return next(iter(raw_versions))


def validate_attestations(attestations, runners, evidence):
    lines = [ln for ln in attestations.splitlines() if ln.strip()]
    check(len(lines) == 3, f"need 3 attestation lines, got {len(lines)}")
    by_subject = []
    for ln in lines:
        try:
            obj = json.loads(ln)
        except json.JSONDecodeError:
            fail("malformed attestation JSONL line")
        subj = obj.get("subjectDigest", "").lower()
        check(is_hex64(subj), "bad attestation subject digest")
        check(obj.get("verified") is True, f"attestation not verified for {obj.get('recordPath')}")
        check(isinstance(obj.get("recordPath"), str) and obj["recordPath"].startswith("records/"),
              f"bad attestation recordPath: {obj.get('recordPath')}")
        by_subject.append(subj)
    check(len(by_subject) == 3, f"attestation subject count mismatch: {len(by_subject)}")
    check(len(set(by_subject)) == 3, "attestation subjects must be distinct")
    for r in runners:
        rec = r.get("recordPath")
        check(isinstance(rec, str) and rec.startswith("records/"), f"{r['targetPlatform']}: bad recordPath")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--evidence", required=True)
    p.add_argument("--attestations", required=True)
    p.add_argument("--output", required=True)
    args = p.parse_args()

    with open(args.evidence, encoding="utf-8") as f:
        evidence = json.load(f)
    with open(args.attestations, encoding="utf-8") as f:
        attestations = f.read()

    check(evidence.get("schemaVersion") == SCHEMA_VERSION, "evidence schema mismatch")
    check(evidence.get("channelKey") in ("latest",), f"channel key not content-lockable: {evidence.get('channelKey')}")
    for key in ("repository", "sourceCommit", "probeCommit", "runId", "runAttempt", "tempBranch", "candidateSha256"):
        check(evidence.get(key), f"evidence missing {key}")
    check(is_hex64(evidence["candidateSha256"]), "bad candidate digest")

    archives = evidence.get("archives")
    runners = evidence.get("runners")
    validate_archives(archives)
    expected_version = validate_runners(runners, archives)
    validate_attestations(attestations, runners, evidence)

    # candidate identity: candidateSha256 must match the committed candidate JSON digest
    cand_path = evidence.get("candidatePath")
    if cand_path and os.path.exists(cand_path):
        import hashlib
        with open(cand_path, "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()
        check(digest == evidence["candidateSha256"], "candidate digest does not match evidence")

    lock = {
        "schemaVersion": SCHEMA_VERSION,
        "channelKey": evidence["channelKey"],
        "expectedMoonVersion": base64.b64encode(expected_version).decode(),
        "archives": [
            {
                "role": a["role"],
                "targetPlatform": a["targetPlatform"],
                "filename": a["filename"],
                "url": a["url"],
                "sha256": a["computedSha256"],
                "sidecarDigest": a.get("sidecarDigest"),
                "provenance": a["provenance"],
            }
            for a in sorted(archives, key=lambda x: x["targetPlatform"])
        ],
        "provenance": "official channel content-locked snapshot (D-01/D-03 revision 2026-08-14); core digests recorded, official checksum absent",
    }

    out = os.path.abspath(args.output)
    d = os.path.dirname(out)
    os.makedirs(d, exist_ok=True)
    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(json.dumps(lock, indent=2, sort_keys=True) + "\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, out)
    print(f"LOCK-WRITTEN {out}")
    print(json.dumps({"expectedMoonVersion": lock["expectedMoonVersion"], "archiveRoles": [a["targetPlatform"] for a in lock["archives"]]}, sort_keys=True))


if __name__ == "__main__":
    main()
