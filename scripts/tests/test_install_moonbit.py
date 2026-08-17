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


def build_fixture(server, platform="unix", exe_bytes=None, bad_traversal=False, wrong_version=False,
                  corrupt_sidecar=False, corrupt_archive=False):
    if platform == "windows":
        assert exe_bytes is not None
        bin_zip = make_zip([("bin/moon.exe", exe_bytes), ("bin/moonc.exe", exe_bytes), ("lib/x", b"x")])
        core_zip = make_zip([("core/a.mbt", b"a")])
        bin_name = "moonbit-windows-x86_64.zip"
        core_name = "core-latest.zip"
        bin_digest = hashlib.sha256(bin_zip).hexdigest()
        core_digest = hashlib.sha256(core_zip).hexdigest()
        served_bin = b"not-a-zip" if corrupt_archive else bin_zip
        with open(os.path.join(server.dir, bin_name), "wb") as f:
            f.write(served_bin)
        sidecar = f"{bin_digest}  {bin_name}\n"
        if corrupt_sidecar:
            sidecar = f"{'0' * 64}  {bin_name}\n"
        with open(os.path.join(server.dir, bin_name + ".sha256"), "w") as f:
            f.write(sidecar)
        with open(os.path.join(server.dir, core_name), "wb") as f:
            f.write(core_zip)
        return bin_digest, core_digest
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


def make_lock(server, bin_digest, core_digest, platform="unix", missing_core=False, extra_binary=False):
    if platform == "windows":
        bin_rec = {"role": "binary", "targetPlatform": "windows-x86_64", "filename": "moonbit-windows-x86_64.zip",
                   "url": server.url("moonbit-windows-x86_64.zip"), "sha256": bin_digest,
                   "sidecarDigest": bin_digest, "provenance": "official-sidecar"}
        core_rec = {"role": "core", "targetPlatform": "core-zip", "filename": "core-latest.zip",
                    "url": server.url("core-latest.zip"), "sha256": core_digest,
                    "sidecarDigest": None, "provenance": "recorded-digest"}
    else:
        bin_rec = {"role": "binary", "targetPlatform": "linux-x86_64", "filename": "moonbit-linux-x86_64.tar.gz",
                   "url": server.url("moonbit-linux-x86_64.tar.gz"), "sha256": bin_digest,
                   "sidecarDigest": bin_digest, "provenance": "official-sidecar"}
        core_rec = {"role": "core", "targetPlatform": "core-tar.gz", "filename": "core-latest.tar.gz",
                    "url": server.url("core-latest.tar.gz"), "sha256": core_digest,
                    "sidecarDigest": None, "provenance": "recorded-digest"}
    archives = [bin_rec]
    if extra_binary:
        archives.append(dict(bin_rec, targetPlatform="darwin-aarch64" if platform != "windows" else "linux-x86_64"))
    if not missing_core:
        archives.append(core_rec)
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


CS_OK = r"""using System;
class P { static void Main() {
  Console.WriteLine("moon 0.1.20260807 (4da23f8 2026-08-07)");
  Console.WriteLine();
  Console.WriteLine("Feature flags enabled: rr_moon_mod,rr_moon_pkg");
} }"""
CS_BAD = r"""using System;
class P { static void Main() { Console.WriteLine("moon 0.1.OTHER"); } }"""


def compile_exe(exe_path, cs_source_path):
    ps = (f"& \"$env:WINDIR\\Microsoft.NET\\Framework64\\v4.0.30319\\csc.exe\" "
          f"/nologo /out:'{exe_path}' '{cs_source_path}'")
    return subprocess.run(["pwsh", "-NoProfile", "-Command", ps], capture_output=True, text=True, timeout=300)


def windows_subset():
    """Run on a native windows-2025 runner via the installer matrix driver."""
    server = FixtureServer({})
    try:
        tmp = tempfile.mkdtemp(prefix="win-installer-")
        cs_ok = os.path.join(tmp, "ok.cs")
        cs_bad = os.path.join(tmp, "bad.cs")
        exe_ok = os.path.join(tmp, "moon-ok.exe")
        exe_bad = os.path.join(tmp, "moon-bad.exe")
        with open(cs_ok, "w") as f:
            f.write(CS_OK)
        with open(cs_bad, "w") as f:
            f.write(CS_BAD)
        r = compile_exe(exe_ok, cs_ok)
        if r.returncode != 0:
            print("COMPILE-OK FAILED:", r.stdout, r.stderr)
            return 1
        r = compile_exe(exe_bad, cs_bad)
        if r.returncode != 0:
            print("COMPILE-BAD FAILED:", r.stdout, r.stderr)
            return 1
        ok_bytes = open(exe_ok, "rb").read()
        bad_bytes = open(exe_bad, "rb").read()

        def run_ps1(lock, obs_name, home_name):
            lock_path = os.path.join(tmp, f"lock-{obs_name}.json")
            with open(lock_path, "w", encoding="utf-8") as f:
                json.dump(lock, f)
            env = dict(os.environ)
            env["LOCK_PATH"] = lock_path
            env["MOON_HOME"] = os.path.join(tmp, home_name)
            env["OBSERVATION_PATH"] = os.path.join(tmp, obs_name)
            env.pop("GITHUB_PATH", None)
            return subprocess.run(["pwsh", "-NoProfile", "-File", PS_HELPER],
                                  capture_output=True, text=True, env=env, timeout=300), env

        # valid install
        bd, cd = build_fixture(server, platform="windows", exe_bytes=ok_bytes)
        proc, env = run_ps1(make_lock(server, bd, cd, platform="windows"), "obs.json", "home")
        if proc.returncode != 0 or not os.path.exists(os.path.join(env["MOON_HOME"], "bin", "moon.exe")) \
                or not os.path.exists(env["OBSERVATION_PATH"]):
            print("VALID FAILED:", proc.stdout, proc.stderr)
            return 1
        # corrupt sidecar
        bd2, cd2 = build_fixture(server, platform="windows", exe_bytes=ok_bytes, corrupt_sidecar=True)
        proc2, env2 = run_ps1(make_lock(server, bd2, cd2, platform="windows"), "obs2.json", "home2")
        if proc2.returncode == 0 or os.path.exists(env2["OBSERVATION_PATH"]):
            print("CORRUPT-SIDECAR: did not fail closed")
            return 1
        # corrupt archive
        bd3, cd3 = build_fixture(server, platform="windows", exe_bytes=ok_bytes, corrupt_archive=True)
        proc3, env3 = run_ps1(make_lock(server, bd3, cd3, platform="windows"), "obs3.json", "home3")
        if proc3.returncode == 0 or os.path.exists(env3["OBSERVATION_PATH"]):
            print("CORRUPT-ARCHIVE: did not fail closed")
            return 1
        # traversal zip
        evil_zip = make_zip([("../evil", b"x")])
        evil_digest = hashlib.sha256(evil_zip).hexdigest()
        with open(os.path.join(server.dir, "moonbit-windows-x86_64.zip"), "wb") as f:
            f.write(evil_zip)
        with open(os.path.join(server.dir, "moonbit-windows-x86_64.zip.sha256"), "w") as f:
            f.write(f"{evil_digest}  moonbit-windows-x86_64.zip\n")
        lock_evil = make_lock(server, evil_digest, hashlib.sha256(make_zip([("core/a.mbt", b"a")])).hexdigest(), platform="windows")
        proc4, env4 = run_ps1(lock_evil, "obs4.json", "home4")
        if proc4.returncode == 0 or os.path.exists(env4["OBSERVATION_PATH"]):
            print("TRAVERSAL: did not fail closed")
            return 1
        # wrong version
        bd5, cd5 = build_fixture(server, platform="windows", exe_bytes=bad_bytes)
        proc5, env5 = run_ps1(make_lock(server, bd5, cd5, platform="windows"), "obs5.json", "home5")
        if proc5.returncode == 0 or os.path.exists(env5["OBSERVATION_PATH"]):
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
