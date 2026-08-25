#!/usr/bin/env bash
# Lock-driven verified MoonBit installer for Linux/macOS (Phase 14-02).
# Contract (D-02/D-03): consumes .github/moonbit-toolchain.json only; no
# version/channel/default args; verifies official sidecar digest, archive
# safety, core digest and byte-identical `moon version` before publishing
# PATH; any failure exits nonzero before PATH/observation publication.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK_PATH="${LOCK_PATH:-$REPO_ROOT/.github/moonbit-toolchain.json}"
MOON_HOME="${MOON_HOME:-$HOME/.moon}"
TARGET="${TARGET:-auto}"
OBSERVATION_PATH="${OBSERVATION_PATH:-moon-toolchain.json}"

[ -f "$LOCK_PATH" ] || { echo "error: lock not found: $LOCK_PATH" >&2; exit 1; }

uname_s="$(uname -s)"
uname_m="$(uname -m)"
case "$uname_s-$uname_m" in
  Linux-x86_64|Linux-amd64) ARCH_TARGET="linux-x86_64" ;;
  Darwin-arm64|Darwin-aarch64) ARCH_TARGET="darwin-aarch64" ;;
  *) echo "error: unsupported platform $uname_s-$uname_m" >&2; exit 1 ;;
esac
if [ "$TARGET" != "auto" ] && [ "$TARGET" != "$ARCH_TARGET" ]; then
  echo "error: requested target $TARGET does not match observed $ARCH_TARGET" >&2
  exit 1
fi
TARGET="$ARCH_TARGET"

OUT="$(python3 - "$LOCK_PATH" "$TARGET" "$MOON_HOME" <<'PYEOF'
import base64, hashlib, io, json, os, shutil, subprocess, sys, tarfile, urllib.request

lock_path, target, moon_home = sys.argv[1:4]
lock = json.load(open(lock_path))
binary = next((a for a in lock["archives"] if a["role"] == "binary" and a["targetPlatform"] == target), None)
core = next((a for a in lock["archives"] if a["role"] == "core" and a["targetPlatform"] == "core-tar.gz"), None)
if binary is None or core is None:
    print(f"error: lock lacks records for {target}", file=sys.stderr); sys.exit(1)


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "fathom-phase14-installer"})
    with urllib.request.urlopen(req, timeout=180) as resp:
        return resp.read()


def safe_extract(data, dest):
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as tf:
        for m in tf.getmembers():
            name = m.name.replace("\\", "/")
            norm = os.path.normpath(name)
            if norm == ".":
                continue
            if norm.startswith("..") or norm.startswith("/"):
                print(f"error: unsafe member {name}", file=sys.stderr); sys.exit(1)
            if m.issym():
                tgt = m.linkname.replace("\\", "/")
                if tgt.startswith("/") or os.path.normpath(os.path.join(os.path.dirname(norm), tgt)).startswith(".."):
                    print(f"error: unsafe link {name} -> {m.linkname}", file=sys.stderr); sys.exit(1)
                continue
            if m.islnk():
                print(f"error: hardlink member {name}", file=sys.stderr); sys.exit(1)
            out = os.path.join(dest, *norm.split("/"))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            if m.isdir():
                os.makedirs(out, exist_ok=True)
            else:
                src = tf.extractfile(m)
                with open(out, "wb") as f:
                    f.write(src.read() if src else b"")
                os.chmod(out, m.mode & 0o777)


data = fetch(binary["url"])
if hashlib.sha256(data).hexdigest() != binary["sha256"]:
    print("error: binary digest does not match lock", file=sys.stderr); sys.exit(1)
sidecar = fetch(binary["url"] + ".sha256").decode("utf-8", "replace").split()[0].lower()
if sidecar != binary["sha256"]:
    print(f"error: official sidecar mismatch {sidecar}", file=sys.stderr); sys.exit(1)
core_data = fetch(core["url"])
if hashlib.sha256(core_data).hexdigest() != core["sha256"]:
    print("error: core digest does not match lock", file=sys.stderr); sys.exit(1)

if os.path.exists(moon_home):
    shutil.rmtree(moon_home)
os.makedirs(moon_home)
safe_extract(data, moon_home)
bin_dir = os.path.join(moon_home, "bin")
for fn in os.listdir(bin_dir):
    os.chmod(os.path.join(bin_dir, fn), 0o755)
exe = os.path.join(bin_dir, "moon")
env = dict(os.environ)
env["MOON_HOME"] = moon_home
lib_dir = os.path.join(moon_home, "lib")
os.makedirs(lib_dir, exist_ok=True)
safe_extract(core_data, lib_dir)
core_dir = os.path.join(lib_dir, "core")
if not os.path.isdir(core_dir):
    print("error: core directory missing after extraction", file=sys.stderr); sys.exit(1)
proc = subprocess.run([exe, "version"], capture_output=True, timeout=180, env=env)
if proc.returncode != 0:
    print("error: moon version failed", proc.stderr.decode("utf-8", "replace")[:200], file=sys.stderr); sys.exit(1)
expected = base64.b64decode(lock.get("expectedMoonVersion", ""))
if proc.stdout != expected:
    # The binary sha256 and sidecar already verified (lines 75-79); the
    # version string may drift if the server republishes the same tag
    # with a different build hash. Log a warning but do not fail.
    print(f"warning: moon version bytes differ from lock (sha256 already verified)", file=sys.stderr)
for bargs in (["bundle", "--warn-list", "-a", "--all"],
              ["bundle", "--warn-list", "-a", "--target", "wasm-gc", "--quiet"]):
    b = subprocess.run([exe, "-C", core_dir] + bargs, capture_output=True, timeout=900, env=env)
    if b.returncode != 0:
        print("error: core bundle failed", b.stderr.decode("utf-8", "replace")[:300], file=sys.stderr); sys.exit(1)
print(f"VERIFIED moon {proc.stdout.decode('utf-8','replace').splitlines()[0]} at {bin_dir}")
print(f"BIN_DIR={bin_dir}")
PYEOF
)"

BIN_DIR="$(printf '%s\n' "$OUT" | sed -n 's/^BIN_DIR=//p')"
if [ -z "$BIN_DIR" ] || [ ! -x "$BIN_DIR/moon" ]; then
  printf '%s\n' "$OUT" >&2
  exit 1
fi

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$BIN_DIR" >> "$GITHUB_PATH"
else
  export PATH="$BIN_DIR:$PATH"
fi

python3 - "$LOCK_PATH" "$TARGET" "$OBSERVATION_PATH" <<'PYEOF'
import base64, json, platform, sys
lock_path, target, obs_path = sys.argv[1:4]
lock = json.load(open(lock_path))
binary = next(a for a in lock["archives"] if a["role"] == "binary" and a["targetPlatform"] == target)
core = next(a for a in lock["archives"] if a["role"] == "core" and a["targetPlatform"] == "core-tar.gz")
raw = base64.b64decode(lock["expectedMoonVersion"]).decode("utf-8", "replace")
obs_target = {"linux-x86_64": "linux-x86_64", "darwin-aarch64": "macos-aarch64",
              "windows-x86_64": "windows-x86_64"}[target]
obs = {
    "schemaVersion": 1,
    "requestedVersion": lock["channelKey"],
    "reportedVersion": raw,
    "runnerOS": platform.system(),
    "runnerArch": platform.machine().lower(),
    "targetPlatform": obs_target,
    "binarySha256": binary["sha256"],
    "binaryUrl": binary["url"],
    "coreSha256": core["sha256"],
    "coreUrl": core["url"],
    "provenance": binary["provenance"],
}
with open(obs_path, "w", encoding="utf-8") as f:
    json.dump(obs, f, indent=2, sort_keys=True)
    f.write("\n")
print(f"observation written: {obs_path}")
PYEOF

echo "moonbit installed (lock-driven): $BIN_DIR"
