"""Executable negative proof for scripts/verify_moonbit_freeze.py.

Runs the verifier as a subprocess against synthesized evidence/attestation
fixtures. Every defect must exit nonzero and leave no output lock.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VERIFIER = os.path.join(REPO, "scripts", "verify_moonbit_freeze.py")

RAW_VERSION = b"moon 0.1.20260807 (4da23f8 2026-08-07)\n"
HEX64 = "a" * 64
HEX64_B = "b" * 64
HEX64_C = "c" * 64


def make_archives(mutate=None):
    recs = [
        {"role": "binary", "targetPlatform": "linux-x86_64", "filename": "moonbit-linux-x86_64.tar.gz",
         "url": "https://cli.moonbitlang.com/binaries/latest/moonbit-linux-x86_64.tar.gz",
         "sidecarUrl": "https://cli.moonbitlang.com/binaries/latest/moonbit-linux-x86_64.tar.gz.sha256",
         "sidecarDigest": HEX64, "computedSha256": HEX64, "provenance": "official-sidecar",
         "memberCount": 4, "layoutOk": True},
        {"role": "binary", "targetPlatform": "darwin-aarch64", "filename": "moonbit-darwin-aarch64.tar.gz",
         "url": "https://cli.moonbitlang.com/binaries/latest/moonbit-darwin-aarch64.tar.gz",
         "sidecarUrl": "https://cli.moonbitlang.com/binaries/latest/moonbit-darwin-aarch64.tar.gz.sha256",
         "sidecarDigest": HEX64_B, "computedSha256": HEX64_B, "provenance": "official-sidecar",
         "memberCount": 4, "layoutOk": True},
        {"role": "binary", "targetPlatform": "windows-x86_64", "filename": "moonbit-windows-x86_64.zip",
         "url": "https://cli.moonbitlang.com/binaries/latest/moonbit-windows-x86_64.zip",
         "sidecarUrl": "https://cli.moonbitlang.com/binaries/latest/moonbit-windows-x86_64.zip.sha256",
         "sidecarDigest": HEX64_C, "computedSha256": HEX64_C, "provenance": "official-sidecar",
         "memberCount": 4, "layoutOk": True},
        {"role": "core", "targetPlatform": "core-tar.gz", "filename": "core-latest.tar.gz",
         "url": "https://cli.moonbitlang.com/cores/core-latest.tar.gz",
         "sidecarUrl": None, "sidecarDigest": None, "computedSha256": "d" * 64,
         "provenance": "recorded-digest", "officialChecksumAvailable": False,
         "memberCount": 2, "layoutOk": True},
        {"role": "core", "targetPlatform": "core-zip", "filename": "core-latest.zip",
         "url": "https://cli.moonbitlang.com/cores/core-latest.zip",
         "sidecarUrl": None, "sidecarDigest": None, "computedSha256": "e" * 64,
         "provenance": "recorded-digest", "officialChecksumAvailable": False,
         "memberCount": 2, "layoutOk": True},
    ]
    if mutate:
        res = mutate(recs)
        return res if res is not None else recs
    return recs


def make_runners(raw=None, mutate=None):
    raw = raw or RAW_VERSION
    recs = [
        {"targetPlatform": "linux-x86_64", "hostArch": "x86_64", "execArch": "x86_64", "exitCode": 0,
         "rawVersionBase64": __import__("base64").b64encode(raw).decode(),
         "archiveSha256": HEX64, "recordPath": "records/linux-x86_64/moon-toolchain-runner.json"},
        {"targetPlatform": "macos-aarch64", "hostArch": "arm64", "execArch": "arm64", "exitCode": 0,
         "rawVersionBase64": __import__("base64").b64encode(raw).decode(),
         "archiveSha256": HEX64_B, "recordPath": "records/macos-aarch64/moon-toolchain-runner.json"},
        {"targetPlatform": "windows-x86_64", "hostArch": "x86_64", "execArch": "x86_64", "exitCode": 0,
         "rawVersionBase64": __import__("base64").b64encode(raw).decode(),
         "archiveSha256": HEX64_C, "recordPath": "records/windows-x86_64/moon-toolchain-runner.json"},
    ]
    if mutate:
        res = mutate(recs)
        return res if res is not None else recs
    return recs


def make_evidence(mutate_archives=None, mutate_runners=None, mutate_evidence=None):
    ev = {
        "schemaVersion": 1,
        "channelKey": "latest",
        "repository": "tchivs/fathom-sql",
        "sourceCommit": "1" * 40,
        "probeCommit": "2" * 40,
        "runId": 123456789,
        "runAttempt": 1,
        "tempBranch": "phase14-freeze-20260814-000000-deadbeef",
        "candidateSha256": "f" * 64,
        "workflowBaselines": {
            ".github/workflows/ci.yml": "0" * 64,
            ".github/workflows/fathom-native-release.yml": "0" * 64,
        },
        "archives": make_archives(mutate_archives),
        "runners": make_runners(mutate=mutate_runners),
    }
    if mutate_evidence:
        mutate_evidence(ev)
    return ev


def make_attestations(runners=None, mutate=None):
    lines = []
    for i, r in enumerate((runners or make_runners())):
        lines.append(json.dumps({
            "recordPath": r["recordPath"],
            "subjectDigest": f"{i + 1:064d}",
            "signerWorkflow": "tchivs/fathom-sql/.github/workflows/phase14-freeze-probe.yml",
            "repo": "tchivs/fathom-sql",
            "verified": True,
        }, sort_keys=True))
    if mutate:
        lines = mutate(lines)
    return "\n".join(lines) + "\n"


class VerifyFreezeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="freeze-verify-")
        self.ev_path = os.path.join(self.tmp, "evidence.json")
        self.att_path = os.path.join(self.tmp, "attestations.jsonl")
        self.out_path = os.path.join(self.tmp, "moon-toolchain.json")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _run(self, evidence, attestations):
        with open(self.ev_path, "w", encoding="utf-8") as f:
            json.dump(evidence, f, sort_keys=True)
        with open(self.att_path, "w", encoding="utf-8") as f:
            f.write(attestations)
        if os.path.exists(self.out_path):
            os.remove(self.out_path)
        proc = subprocess.run(
            [sys.executable, VERIFIER, "--evidence", self.ev_path,
             "--attestations", self.att_path, "--output", self.out_path],
            capture_output=True, text=True, timeout=60)
        return proc

    def _assert_fail(self, proc, label):
        self.assertNotEqual(proc.returncode, 0, f"{label}: expected nonzero exit\n{proc.stdout}\n{proc.stderr}")
        self.assertFalse(os.path.exists(self.out_path), f"{label}: lock must stay absent")

    def test_valid_produces_lock(self):
        proc = self._run(make_evidence(), make_attestations())
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(os.path.exists(self.out_path), "lock missing on success")
        with open(self.out_path, encoding="utf-8") as f:
            lock = json.load(f)
        self.assertEqual(len(lock["archives"]), 5)
        self.assertIn("expectedMoonVersion", lock)

    def test_missing_runner(self):
        proc = self._run(make_evidence(mutate_runners=lambda rs: rs[:2]), make_attestations())
        self._assert_fail(proc, "missing runner")

    def test_duplicate_runner(self):
        def dup(rs):
            rs.append(dict(rs[0], targetPlatform="windows-x86_64"))
            return rs
        proc = self._run(make_evidence(mutate_runners=dup), make_attestations())
        self._assert_fail(proc, "duplicate runner")

    def test_unknown_runner_platform(self):
        def unk(rs):
            rs[0]["targetPlatform"] = "macos-x86_64"
            return rs
        proc = self._run(make_evidence(mutate_runners=unk), make_attestations())
        self._assert_fail(proc, "unknown platform")

    def test_missing_archive(self):
        proc = self._run(make_evidence(mutate_archives=lambda rs: rs[:4]), make_attestations())
        self._assert_fail(proc, "missing archive")

    def test_malformed_evidence_json(self):
        with open(self.ev_path, "w", encoding="utf-8") as f:
            f.write("{not json")
        with open(self.att_path, "w", encoding="utf-8") as f:
            f.write(make_attestations())
        proc = subprocess.run(
            [sys.executable, VERIFIER, "--evidence", self.ev_path,
             "--attestations", self.att_path, "--output", self.out_path],
            capture_output=True, text=True, timeout=60)
        self._assert_fail(proc, "malformed evidence")

    def test_tampered_binary_digest(self):
        def tamper(rs):
            rs[0]["computedSha256"] = "9" * 64  # diverges from sidecarDigest
            return rs
        proc = self._run(make_evidence(mutate_archives=tamper), make_attestations())
        self._assert_fail(proc, "tampered binary digest")

    def test_runner_archive_mismatch(self):
        proc = self._run(make_evidence(mutate_runners=lambda rs: (
            [dict(rs[0], archiveSha256="9" * 64)] + rs[1:])), make_attestations())
        self._assert_fail(proc, "runner archive digest mismatch")

    def test_wrong_arch(self):
        def arch(rs):
            rs[1]["execArch"] = "x86_64"
            return rs
        proc = self._run(make_evidence(mutate_runners=arch), make_attestations())
        self._assert_fail(proc, "wrong exec arch")

    def test_nonzero_exit(self):
        def rc(rs):
            rs[2]["exitCode"] = 1
            return rs
        proc = self._run(make_evidence(mutate_runners=rc), make_attestations())
        self._assert_fail(proc, "nonzero exit")

    def test_raw_version_mismatch(self):
        proc = self._run(
            make_evidence(mutate_runners=lambda rs: (
                [dict(rs[0], rawVersionBase64=__import__("base64").b64encode(b"moon 0.1.OTHER\n").decode())] + rs[1:])),
            make_attestations())
        self._assert_fail(proc, "raw version mismatch")

    def test_unverified_attestation(self):
        def unver(lines):
            obj = json.loads(lines[0])
            obj["verified"] = False
            return [json.dumps(obj, sort_keys=True)] + lines[1:]
        proc = self._run(make_evidence(), make_attestations(mutate=unver))
        self._assert_fail(proc, "unverified attestation")

    def test_attestation_count_mismatch(self):
        proc = self._run(make_evidence(), make_attestations() + json.dumps({}, sort_keys=True) + "\n")
        self._assert_fail(proc, "attestation count")

    def test_core_with_official_checksum_claim(self):
        def core(rs):
            rs[3]["officialChecksumAvailable"] = True
            return rs
        proc = self._run(make_evidence(mutate_archives=core), make_attestations())
        self._assert_fail(proc, "core official checksum claim")

    def test_non_official_url(self):
        def url(rs):
            rs[1]["url"] = "https://evil.example/moonbit-darwin-aarch64.tar.gz"
            return rs
        proc = self._run(make_evidence(mutate_archives=url), make_attestations())
        self._assert_fail(proc, "non-official URL")


if __name__ == "__main__":
    unittest.main()
