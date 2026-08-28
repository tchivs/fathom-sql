#!/usr/bin/env python3
"""Phase 14 freeze probe: official static acquisition + native runner records.

stdlib only. Fail-closed: every defect exits nonzero; the lock is never
touched here (verify_moonbit_freeze.py owns lock publication).

Subcommands:
  static --candidate-out PATH     official archive/sidecar acquisition + safety checks
  runner --candidate PATH --target TARGET --output PATH
                                  run on a native GitHub runner: re-download, verify,
                                  extract safely, execute `moon version`, emit record
  verify-cleanup --evidence PATH --workflows WF...   post-freeze remote-branch + baseline proof
"""

import argparse
import base64
import hashlib
import io
import json
import os
import platform
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
import zipfile

CLI_MOONBIT = "https://cli.moonbitlang.com"
CHANNEL = "latest"
SCHEMA_VERSION = 1
BIN_ROOTS = {"bin", "lib", "include", "share"}
CORE_ROOT = {"core"}
BINARIES = {
    "linux-x86_64": "moonbit-linux-x86_64.tar.gz",
    "darwin-aarch64": "moonbit-darwin-aarch64.tar.gz",
    "windows-x86_64": "moonbit-windows-x86_64.zip",
}
CORES = {
    "core-tar.gz": "cores/core-latest.tar.gz",
    "core-zip": "cores/core-latest.zip",
}


def fail(msg):
    print(f"PROBE-FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def http_get(url, max_bytes=None, cache=False):
    if cache:
        key = hashlib.sha256(url.encode()).hexdigest()
        cpath = os.path.join(os.environ.get("PHASE14_CACHE", "/tmp/phase14-cache"), key)
        if os.path.exists(cpath):
            with open(cpath, "rb") as f:
                data = f.read()
            if max_bytes is None or len(data) <= max_bytes:
                return url, data
    req = urllib.request.Request(url, headers={"User-Agent": "fathom-phase14-freeze"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        final = resp.geturl()
        data = resp.read()
    if max_bytes is not None and len(data) > max_bytes:
        fail(f"oversized body {len(data)} from {url}")
    if cache:
        os.makedirs(os.path.dirname(cpath), exist_ok=True)
        tmp = cpath + ".tmp"
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, cpath)
    return final, data


def check_safe_tar(data, expected_root):
    members = []
    seen = set()
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as tf:
        for m in tf.getmembers():
            name = m.name.replace("\\", "/")
            norm = os.path.normpath(name)
            if norm == ".":
                continue  # benign archive root directory entry
            if norm.startswith("..") or norm.startswith("/") or ":" in name.split("/")[0]:
                fail(f"unsafe tar member: {m.name}")
            if name in seen:
                fail(f"duplicate tar member: {name}")
            seen.add(name)
            if m.issym():
                tgt = m.linkname.replace("\\", "/")
                if tgt.startswith("/"):
                    fail(f"absolute link member: {m.name} -> {m.linkname}")
                resolved = os.path.normpath(os.path.join(os.path.dirname(norm), tgt))
                if resolved.startswith(".."):
                    fail(f"escaping link member: {m.name} -> {m.linkname}")
                continue  # intra-archive relative link is safe
            if m.islnk():
                fail(f"hardlink member in archive: {name}")
            members.append(norm)
    top = {m.split("/", 1)[0] for m in members if "/" in m}
    if not (expected_root & top):
        fail(f"unexpected tar roots {sorted(top)}; expected under {sorted(expected_root)}")
    return members


def check_safe_zip(data, expected_root):
    members = []
    seen = set()
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        for info in zf.infolist():
            name = info.filename.replace("\\", "/")
            norm = os.path.normpath(name)
            if norm.startswith("..") or norm.startswith("/"):
                fail(f"unsafe zip member: {info.filename}")
            if name in seen:
                fail(f"duplicate zip member: {name}")
            seen.add(name)
            if info.is_dir():
                continue
            members.append(norm)
    top = {m.split("/", 1)[0] for m in members if "/" in m}
    if not (expected_root & top):
        fail(f"unexpected zip roots {sorted(top)}; expected under {sorted(expected_root)}")
    return members


def acquire_binary(target, filename):
    url = f"{CLI_MOONBIT}/binaries/{CHANNEL}/{filename}"
    sidecar_url = f"{url}.sha256"
    final, data = http_get(url, cache=True)
    if not final.startswith(CLI_MOONBIT):
        fail(f"redirect drifted off official host: {final}")
    if len(data) == 0:
        fail(f"empty binary body: {url}")
    _, sidecar = http_get(sidecar_url)
    line = sidecar.decode("utf-8", "replace").strip().splitlines()[0].strip()
    parts = line.split()
    if len(parts) != 2 or not parts[0].lower().startswith("sha256"):
        # official form: "<64hex>  <basename>"
        if len(parts) != 2 or len(parts[0]) != 64:
            fail(f"malformed sidecar {sidecar_url}: {line!r}")
    digest = parts[0].lower()
    if parts[1] != filename:
        fail(f"sidecar filename mismatch: {parts[1]!r} != {filename!r}")
    computed = sha256_bytes(data)
    if computed != digest:
        fail(f"binary digest mismatch for {filename}: {computed} != {digest}")
    members = check_safe_tar(data, BIN_ROOTS) if filename.endswith(".tar.gz") else check_safe_zip(data, BIN_ROOTS)
    return {
        "role": "binary",
        "targetPlatform": target,
        "filename": filename,
        "url": final,
        "sidecarUrl": sidecar_url,
        "sidecarDigest": digest,
        "computedSha256": computed,
        "provenance": "official-sidecar",
        "memberCount": len(members),
        "layoutOk": True,
    }


def acquire_core(role, path):
    url = f"{CLI_MOONBIT}/{path}"
    final, data = http_get(url, cache=True)
    if not final.startswith(CLI_MOONBIT):
        fail(f"redirect drifted off official host: {final}")
    if len(data) == 0:
        fail(f"empty core body: {url}")
    computed = sha256_bytes(data)
    members = check_safe_tar(data, CORE_ROOT) if path.endswith(".tar.gz") else check_safe_zip(data, CORE_ROOT)
    return {
        "role": "core",
        "targetPlatform": role,
        "filename": path.rsplit("/", 1)[-1],
        "url": final,
        "sidecarUrl": None,
        "sidecarDigest": None,
        "computedSha256": computed,
        "provenance": "recorded-digest",
        "officialChecksumAvailable": False,
        "memberCount": len(members),
        "layoutOk": True,
    }


def cmd_static(args):
    records = [acquire_binary(t, f) for t, f in BINARIES.items()]
    records += [acquire_core(role, path) for role, path in CORES.items()]
    if len(records) != 5:
        fail(f"expected 5 archive records, got {len(records)}")
    candidate = {
        "schemaVersion": SCHEMA_VERSION,
        "channelKey": CHANNEL,
        "archives": records,
        "expectedMoonVersion": None,  # filled by verifier from runner records
    }
    out = os.path.abspath(args.candidate_out)
    if os.path.exists(out):
        fail(f"candidate output already exists: {out}")
    d = os.path.dirname(out)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".candidate-", suffix=".json")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(candidate, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, out)
    print(json.dumps({k: v for k, v in candidate.items() if k != "archives"}, sort_keys=True))
    print(f"candidate written: {out}")


def target_platform():
    sysname = platform.system()
    machine = platform.machine().lower()
    if sysname == "Linux" and machine in ("x86_64", "amd64"):
        return "linux-x86_64"
    if sysname == "Darwin" and machine in ("arm64", "aarch64"):
        return "macos-aarch64"
    if sysname == "Windows" and machine in ("x86_64", "amd64"):
        return "windows-x86_64"
    fail(f"unsupported runner platform: {sysname} {machine}")


# runner target name -> archive record targetPlatform
ARCHIVE_TARGET = {
    "linux-x86_64": "linux-x86_64",
    "macos-aarch64": "darwin-aarch64",
    "windows-x86_64": "windows-x86_64",
}


def host_arch():
    m = platform.machine().lower()
    return {"amd64": "x86_64", "aarch64": "arm64"}.get(m, m)


def exec_arch(path):
    if sys.platform == "win32":
        with open(path, "rb") as f:
            head = f.read(4096)
        # PE header machine field at offset 0x3C -> PE header -> machine
        import struct
        pe_off = struct.unpack_from("<I", head, 0x3C)[0]
        machine = struct.unpack_from("<H", head, pe_off + 4)[0]
        return {0x8664: "x86_64", 0xAA64: "arm64", 0x14C: "x86_32"}.get(machine, f"pe-0x{machine:x}")
    out = subprocess.run(["file", "-b", path], capture_output=True, text=True)
    low = out.stdout.lower()
    if "arm64" in low or "aarch64" in low:
        return "arm64"
    if "x86-64" in low or "x86_64" in low:
        return "x86_64"
    return low.strip()[:32]


def extract_safely(record, data, dest):
    if record["filename"].endswith(".tar.gz"):
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as tf:
            for m in tf.getmembers():
                name = m.name.replace("\\", "/")
                norm = os.path.normpath(name)
                if norm.startswith("..") or norm.startswith("/") or m.issym() or m.islnk():
                    fail(f"unsafe member during extraction: {name}")
                target = os.path.join(dest, *norm.split("/"))
                os.makedirs(os.path.dirname(target), exist_ok=True)
                if m.isdir():
                    os.makedirs(target, exist_ok=True)
                else:
                    src = tf.extractfile(m)
                    with open(target, "wb") as f:
                        f.write(src.read() if src else b"")
                    if sys.platform != "win32":
                        os.chmod(target, m.mode & 0o777)
    else:
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            for info in zf.infolist():
                name = info.filename.replace("\\", "/")
                norm = os.path.normpath(name)
                if norm.startswith("..") or norm.startswith("/"):
                    fail(f"unsafe member during extraction: {name}")
                target = os.path.join(dest, *norm.split("/"))
                if info.is_dir():
                    os.makedirs(target, exist_ok=True)
                else:
                    os.makedirs(os.path.dirname(target), exist_ok=True)
                    with open(target, "wb") as f:
                        f.write(zf.read(info))


def cmd_runner(args):
    with open(args.candidate, encoding="utf-8") as f:
        candidate = json.load(f)
    if candidate.get("schemaVersion") != SCHEMA_VERSION:
        fail(f"candidate schema mismatch: {candidate.get('schemaVersion')}")
    target = args.target
    archive_target = ARCHIVE_TARGET.get(target)
    if archive_target is None:
        fail(f"unknown runner target {target}")
    record = next((a for a in candidate["archives"] if a["targetPlatform"] == archive_target and a["role"] == "binary"), None)
    if record is None:
        fail(f"no binary record for target {target}")
    core_tar = next((a for a in candidate["archives"] if a["targetPlatform"] == "core-tar.gz"), None)
    if core_tar is None:
        fail("no core-tar.gz record")
    url, data = http_get(record["url"])
    if url != record["url"]:
        fail(f"URL drifted: {url}")
    if sha256_bytes(data) != record["computedSha256"]:
        fail(f"binary digest changed since probe for {target}")
    core_url, core_data = http_get(core_tar["url"])
    if sha256_bytes(core_data) != core_tar["computedSha256"]:
        fail("core digest changed since probe")
    if target_platform() != target:
        fail(f"runner platform mismatch: expected {target}, observed {target_platform()}")
    with tempfile.TemporaryDirectory() as tmp:
        bindir = os.path.join(tmp, "moonbin")
        extract_safely(record, data, bindir)
        if sys.platform != "win32":
            for root, _dirs, files in os.walk(bindir):
                for fn in files:
                    os.chmod(os.path.join(root, fn), 0o755)
        exe = os.path.join(bindir, "bin", "moon.exe" if sys.platform == "win32" else "moon")
        if not os.path.exists(exe):
            fail(f"moon executable missing after extraction: {exe}")
        if sys.platform != "win32":
            os.chmod(exe, 0o755)
        env = dict(os.environ)
        env["PATH"] = os.path.join(bindir, "bin") + os.pathsep + env.get("PATH", "")
        env["MOON_HOME"] = tmp
        proc = subprocess.run([exe, "version"], capture_output=True, timeout=120, env=env)
        raw = proc.stdout
        if proc.returncode != 0:
            fail(f"moon version failed rc={proc.returncode}: {proc.stderr.decode('utf-8','replace')[:200]}")
        if not raw.strip():
            fail("moon version produced empty stdout")
        record_out = {
            "schemaVersion": SCHEMA_VERSION,
            "targetPlatform": target,
            "runnerLabel": os.environ.get("RUNNER_LABEL", ""),
            "hostArch": host_arch(),
            "execArch": exec_arch(exe),
            "exitCode": proc.returncode,
            "rawVersionBase64": base64.b64encode(raw).decode(),
            "archiveSha256": record["computedSha256"],
            "coreSha256": core_tar["computedSha256"],
            "recordPath": f"records/{target}/moon-toolchain-runner.json",
        }
        expected_arch = {"linux-x86_64": "x86_64", "macos-aarch64": "arm64", "windows-x86_64": "x86_64"}[target]
        if record_out["execArch"] != expected_arch:
            fail(f"executable arch mismatch: {record_out['execArch']} != {expected_arch}")
        os.makedirs(f"records/{target}", exist_ok=True)
        with open(record_out["recordPath"], "w", encoding="utf-8") as f:
            json.dump(record_out, f, indent=2, sort_keys=True)
            f.write("\n")
        print(json.dumps(record_out, sort_keys=True))


def cmd_verify_cleanup(args):
    with open(args.evidence, encoding="utf-8") as f:
        evidence = json.load(f)
    temp_branch = evidence.get("tempBranch")
    if not temp_branch:
        fail("evidence missing tempBranch")
    remote = evidence.get("repository", "tchivs/fathom-sql")
    ls = subprocess.run(["git", "ls-remote", "--heads", f"https://github.com/{remote}.git", temp_branch],
                        capture_output=True, text=True, timeout=60)
    if ls.returncode != 0:
        fail(f"ls-remote failed: {ls.stderr[:200]}")
    if ls.stdout.strip():
        fail(f"temporary remote branch still exists: {temp_branch}")
    for wf in args.workflows:
        with open(wf, "rb") as f:
            digest = sha256_bytes(f.read())
        baseline = evidence.get("workflowBaselines", {}).get(wf)
        if baseline is None:
            fail(f"no baseline recorded for {wf}")
        if digest != baseline:
            fail(f"persistent workflow changed during freeze: {wf} {digest} != {baseline}")
        print(f"baseline OK {wf} {digest}")
    print("CLEANUP-VERIFIED: temp branch absent, persistent workflows unchanged")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("static")
    s.add_argument("--candidate-out", required=True)
    r = sub.add_parser("runner")
    r.add_argument("--candidate", required=True)
    r.add_argument("--target", required=True)
    r.add_argument("--output", required=True)
    c = sub.add_parser("verify-cleanup")
    c.add_argument("--evidence", required=True)
    c.add_argument("--workflows", nargs="+", required=True)
    args = p.parse_args()
    if args.cmd == "static":
        cmd_static(args)
    elif args.cmd == "runner":
        cmd_runner(args)
    elif args.cmd == "verify-cleanup":
        cmd_verify_cleanup(args)


if __name__ == "__main__":
    main()
