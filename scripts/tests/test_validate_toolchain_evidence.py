"""Executable fail-closed proof for scripts/validate_toolchain_evidence.py.

Runs the validator as a subprocess against the deterministic fixtures in
scripts/tests/fixtures/toolchain-evidence/. Success case writes the aggregate;
every defect exits nonzero and leaves the output absent.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VALIDATOR = os.path.join(REPO, "scripts", "validate_toolchain_evidence.py")
FIXTURES = os.path.join(REPO, "scripts", "tests", "fixtures", "toolchain-evidence")
LOCK = os.path.join(FIXTURES, "lock.json")
CASES = ["missing", "duplicate", "unknown", "malformed",
         "requested-mismatch", "reported-mismatch", "digest-mismatch"]


class ValidateEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="evidence-")
        self.out = os.path.join(self.tmp, "manifest.json")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _run(self, case):
        evidence_dir = os.path.join(FIXTURES, case) if case else os.path.join(FIXTURES, "valid")
        return subprocess.run(
            [sys.executable, VALIDATOR, "--evidence-dir", evidence_dir,
             "--lock", LOCK, "--output", self.out],
            capture_output=True, text=True, timeout=60)

    def test_valid_writes_aggregate(self):
        proc = self._run("valid")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(os.path.exists(self.out))
        with open(self.out, encoding="utf-8") as f:
            agg = json.load(f)
        self.assertEqual(len(agg["platforms"]), 3)
        self.assertEqual([p["targetPlatform"] for p in agg["platforms"]],
                         ["linux-x86_64", "macos-aarch64", "windows-x86_64"])

    def test_defects_fail_closed(self):
        for case in CASES:
            with self.subTest(case=case):
                if os.path.exists(self.out):
                    os.remove(self.out)
                proc = self._run(case)
                self.assertNotEqual(proc.returncode, 0, f"{case}: expected nonzero")
                self.assertFalse(os.path.exists(self.out), f"{case}: output must stay absent")


if __name__ == "__main__":
    unittest.main()
