"""Executable installer contract tests (Phase 14-02).

Unix subset runs locally with a loopback HTTP server; Windows subset runs on a
native windows-2025 Actions job via scripts/run_phase14_installer_matrix.py.

Usage: python3 -m unittest scripts.tests.test_install_moonbit  (unix subset)
       python3 scripts/tests/test_install_moonbit.py --platform windows
"""

import argparse
import base64
import hashlib
import http.server
import io
import json
import os
import shutil
import socketserver
import subprocess
import sys
import tarfile
import tempfile
import threading
import unittest
import zipfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
UNIX_HELPER = os.path.join(REPO, ".github", "scripts", "install-moonbit.sh")
PS_HELPER = os.path.join(REPO, ".github", "scripts", "install-moonbit.ps1")

FAKE_VERSION = b"moon 0.1.20260807 (4da23f8 2026-08-07)\n\nFeature flags enabled: rr_moon_mod,rr_moon_pkg\n"
FAKE_MOON_SH = b"#!/usr/bin/env bash\necho 'moon 0.1.20260807 (4da23f8 2026-08-07)'\necho\necho 'Feature flags enabled: rr_moon_mod,rr_moon_pkg'\n"


def make_tar(entries, bad_traversal=False):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as tf:
        if bad_traversal:
            info = tarfile.TarInfo("../evil")
            tf.addfile(info, io.BytesIO(b"x"))
        for path, data, mode in entries:
            info = tarfile.TarInfo(path)
            info.size = len(data)
            info.mode = mode
            tf.addfile(info, io.BytesIO(data))
    return buf.getvalue()


def make_zip(entries):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        for path, data in entries:
            zf.writestr(path, data)
    return buf.getvalue()


class FixtureServer:
    def __init__(self, files):
        self.dir = tempfile.mkdtemp(prefix="installer-fixture-")
        for name, data in files.items():
            p = os.path.join(self.dir, name)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "wb") as f:
                f.write(data)
        handler = lambda *a, **kw: http.server.SimpleHTTPRequestHandler(*a, directory=self.dir, **kw)
        self.httpd = socketserver.TCPServer(("127.0.0.1", 0), handler)
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def url(self, name):
        return f"http://127.0.0.1:{self.port}/{name}"

    def close(self):
        self.httpd.shutdown()
        shutil.rmtree(self.dir, ignore_errors=True)


def build_fixture(server, bad_traversal=False, wrong_version=False, corrupt_sidecar=False, corrupt_archive=False):
    moon_data = b"#!/bin/sh\necho 'moon 0.1.20260807 (4da23f8 2026-08-07)'\necho\necho 'Feature flags enabled: rr_moon_mod,rr_moon_pkg'\n"
    if wrong_version:
        moon_data = b"#!/bin/sh\necho 'moon 0.1.OTHER'\n"
    bin_tar = make_tar([("bin/moon", moon_data, 0o755), ("bin/moonc", moon_data, 0o755), ("lib/x", b"x", 0o644)], bad_traversal)
    core_tar = make_tar([("core/a.mbt", b"a", 0o644)])
    bin_digest = hashlib.sha256(bin_tar).hexdigest()
    core_digest = hashlib.sha256(core_tar).hexdigest()
    served_bin = b"not-a-tar" if corrupt_archive else bin_tar
    with open(os.path.join(server.dir, "moonbit-linux-x86_64.tar.gz"), "wb") as f:
        f.write(served_bin)
    sidecar = f"{bin_digest}  moonbit-linux-x86_64.tar.gz\n"
    if corrupt_sidecar:
        sidecar = f"{'0' * 64}  moonbit-linux-x86_64.tar.gz\n"
    with open(os.path.join(server.dir, "moonbit-linux-x86_64.tar.gz.sha256"), "w") as f:
        f.write(sidecar)
    with open(os.path.join(server.dir, "core-latest.tar.gz"), "wb") as f:
        f.write(core_tar)
    return bin_digest, core_digest


def make_lock(server, bin_digest, core_digest, missing_core=False, extra_binary=False):
    archives = [
        {"role": "binary", "targetPlatform": "linux-x86_64", "filename": "moonbit-linux-x86_64.tar.gz",
         "url": server.url("moonbit-linux-x86_64.tar.gz"), "sha256": bin_digest,
         "sidecarDigest": bin_digest, "provenance": "official-sidecar"},
    ]
    if extra_binary:
        archives.append(dict(archives[0], targetPlatform="darwin-aarch64", sha256=bin_digest))
    if not missing_core:
        archives.append({"role": "core", "targetPlatform": "core-tar.gz", "filename": "core-latest.tar.gz",
                         "url": server.url("core-latest.tar.gz"), "sha256": core_digest,
                         "sidecarDigest": None, "provenance": "recorded-digest"})
    return {
        "schemaVersion": 1,
        "channelKey": "latest",
        "expectedMoonVersion": base64.b64encode(FAKE_VERSION).decode(),
        "archives": archives,
    }


def run_unix(lock_path, moon_home, target="auto", obs_path=None):
    env = dict(os.environ)
    env["LOCK_PATH"] = lock_path
    env["MOON_HOME"] = moon_home
    env["TARGET"] = target
    if obs_path:
        env["OBSERVATION_PATH"] = obs_path
    env.pop("GITHUB_PATH", None)
    return subprocess.run(["bash", UNIX_HELPER], capture_output=True, text=True, env=env, timeout=300)


@unittest.skipUnless(sys.platform.startswith("linux"), "unix subset")
class UnixInstallerTest(unittest.TestCase):
    def setUp(self):
        self.server = FixtureServer({})
        self.tmp = tempfile.mkdtemp(prefix="installer-test-")

    def tearDown(self):
        self.server.close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _valid_env(self):
        bin_digest, core_digest = build_fixture(self.server)
        return make_lock(self.server, bin_digest, core_digest), bin_digest

    def test_valid_install(self):
        lock, _ = self._valid_env()
        lock_path = os.path.join(self.tmp, "lock.json")
        json.dump(lock, open(lock_path, "w"))
        home = os.path.join(self.tmp, "home")
        obs = os.path.join(self.tmp, "obs.json")
        proc = run_unix(lock_path, home, obs_path=obs)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertTrue(os.path.exists(os.path.join(home, "bin", "moon")))
        self.assertTrue(os.path.exists(obs))
        obs_data = json.load(open(obs))
        self.assertEqual(obs_data["targetPlatform"], "linux-x86_64")
        self.assertIn("0.1.20260807", obs_data["reportedVersion"])

    def test_target_mismatch_fails(self):
        lock, _ = self._valid_env()
        lock_path = os.path.join(self.tmp, "lock.json")
        json.dump(lock, open(lock_path, "w"))
        proc = run_unix(lock_path, os.path.join(self.tmp, "h"), target="windows-x86_64")
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "obs.json")))

    def test_corrupt_sidecar_fails(self):
        bin_digest, core_digest = build_fixture(self.server, corrupt_sidecar=True)
        lock = make_lock(self.server, bin_digest, core_digest)
        lock_path = os.path.join(self.tmp, "lock.json")
        json.dump(lock, open(lock_path, "w"))
        proc = run_unix(lock_path, os.path.join(self.tmp, "h"))
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("sidecar", proc.stdout + proc.stderr)

    def test_corrupt_archive_fails(self):
        bin_digest, core_digest = build_fixture(self.server, corrupt_archive=True)
        lock = make_lock(self.server, bin_digest, core_digest)
        lock_path = os.path.join(self.tmp, "lock.json")
        json.dump(lock, open(lock_path, "w"))
        proc = run_unix(lock_path, os.path.join(self.tmp, "h"))
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("digest", proc.stdout + proc.stderr)

    def test_traversal_archive_fails(self):
        bin_digest, core_digest = build_fixture(self.server, bad_traversal=True)
        lock = make_lock(self.server, bin_digest, core_digest)
        lock_path = os.path.join(self.tmp, "lock.json")
        json.dump(lock, open(lock_path, "w"))
        proc = run_unix(lock_path, os.path.join(self.tmp, "h"))
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("unsafe", proc.stdout + proc.stderr)

    def test_wrong_version_fails(self):
        bin_digest, core_digest = build_fixture(self.server, wrong_version=True)
        lock = make_lock(self.server, bin_digest, core_digest)
        lock_path = os.path.join(self.tmp, "lock.json")
        json.dump(lock, open(lock_path, "w"))
        proc = run_unix(lock_path, os.path.join(self.tmp, "h"))
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("mismatch", proc.stdout + proc.stderr)

    def test_missing_core_record_fails(self):
        bin_digest, core_digest = build_fixture(self.server)
        lock = make_lock(self.server, bin_digest, core_digest, missing_core=True)
        lock_path = os.path.join(self.tmp, "lock.json")
        json.dump(lock, open(lock_path, "w"))
        proc = run_unix(lock_path, os.path.join(self.tmp, "h"))
        self.assertNotEqual(proc.returncode, 0)

    def test_no_observation_on_failure(self):
        bin_digest, core_digest = build_fixture(self.server, wrong_version=True)
        lock = make_lock(self.server, bin_digest, core_digest)
        lock_path = os.path.join(self.tmp, "lock.json")
        json.dump(lock, open(lock_path, "w"))
        obs = os.path.join(self.tmp, "obs.json")
        proc = run_unix(lock_path, os.path.join(self.tmp, "h"), obs_path=obs)
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(os.path.exists(obs))


def windows_subset():
    """Run on a native windows-2025 runner via the installer matrix driver."""
    server = FixtureServer({})
    try:
        bin_digest, core_digest = build_fixture(server)
        lock = make_lock(server, bin_digest, core_digest)
        tmp = tempfile.mkdtemp(prefix="win-installer-")
        lock_path = os.path.join(tmp, "lock.json")
        json.dump(lock, open(lock_path, "w"))
        obs_path = os.path.join(tmp, "obs.json")
        env = dict(os.environ)
        env["LOCK_PATH"] = lock_path
        env["MOON_HOME"] = os.path.join(tmp, "home")
        env["OBSERVATION_PATH"] = obs_path
        env.pop("GITHUB_PATH", None)
        proc = subprocess.run(["pwsh", "-NoProfile", "-File", PS_HELPER], capture_output=True, text=True, env=env, timeout=300)
        if proc.returncode != 0:
            print("VALID FAILED:", proc.stdout, proc.stderr)
            return 1
        if not os.path.exists(os.path.join(env["MOON_HOME"], "bin", "moon.exe")) or not os.path.exists(obs_path):
            print("VALID: missing artifacts")
            return 1
        # negative: corrupt sidecar
        bin_digest2, core_digest2 = build_fixture(server, corrupt_sidecar=True)
        lock2 = make_lock(server, bin_digest2, core_digest2)
        lock_path2 = os.path.join(tmp, "lock2.json")
        json.dump(lock2, open(lock_path2, "w"))
        env["LOCK_PATH"] = lock_path2
        env["OBSERVATION_PATH"] = os.path.join(tmp, "obs2.json")
        proc2 = subprocess.run(["pwsh", "-NoProfile", "-File", PS_HELPER], capture_output=True, text=True, env=env, timeout=300)
        if proc2.returncode == 0 or os.path.exists(env["OBSERVATION_PATH"]):
            print("CORRUPT-SIDECAR: did not fail closed")
            return 1
        # negative: wrong version
        bin_digest3, core_digest3 = build_fixture(server, wrong_version=True)
        lock3 = make_lock(server, bin_digest3, core_digest3)
        lock_path3 = os.path.join(tmp, "lock3.json")
        json.dump(lock3, open(lock_path3, "w"))
        env["LOCK_PATH"] = lock_path3
        env["OBSERVATION_PATH"] = os.path.join(tmp, "obs3.json")
        proc3 = subprocess.run(["pwsh", "-NoProfile", "-File", PS_HELPER], capture_output=True, text=True, env=env, timeout=300)
        if proc3.returncode == 0 or os.path.exists(env["OBSERVATION_PATH"]):
            print("WRONG-VERSION: did not fail closed")
            return 1
        print("WINDOWS-SUBSET PASS")
        return 0
    finally:
        server.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", default="unix")
    args = parser.parse_args()
    if args.platform == "windows":
        sys.exit(windows_subset())
    unittest.main()
