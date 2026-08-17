# Lock-driven verified MoonBit installer for Windows (Phase 14-02).
# Contract (D-02/D-03): consumes .github/moonbit-toolchain.json only; no
# version/channel/default args; verifies official sidecar digest, archive
# safety, core digest and byte-identical `moon version` before publishing
# PATH; any failure exits nonzero before PATH/observation publication.
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$LockPath = if ($env:LOCK_PATH) { $env:LOCK_PATH } else { Join-Path $RepoRoot ".github\moonbit-toolchain.json" }
$MoonHome = if ($env:MOON_HOME) { $env:MOON_HOME } else { Join-Path $env:USERPROFILE ".moon" }
$ObservationPath = if ($env:OBSERVATION_PATH) { $env:OBSERVATION_PATH } else { "moon-toolchain.json" }

if (-not (Test-Path $LockPath)) {
    Write-Error "lock not found: $LockPath"
    exit 1
}

$env:PHASE14_LOCK_PATH = $LockPath
$env:PHASE14_MOON_HOME = $MoonHome

$py = @"
import base64, hashlib, io, json, os, shutil, subprocess, sys, zipfile, urllib.request

lock_path = os.environ["PHASE14_LOCK_PATH"]
moon_home = os.environ["PHASE14_MOON_HOME"]
target = "windows-x86_64"
lock = json.load(open(lock_path))
binary = next((a for a in lock["archives"] if a["role"] == "binary" and a["targetPlatform"] == target), None)
core = next((a for a in lock["archives"] if a["role"] == "core" and a["targetPlatform"] == "core-zip"), None)
if binary is None or core is None:
    print("error: lock lacks records for " + target, file=sys.stderr); sys.exit(1)


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "fathom-phase14-installer"})
    with urllib.request.urlopen(req, timeout=180) as resp:
        return resp.read()


def safe_extract(data, dest):
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        for info in zf.infolist():
            name = info.filename.replace("\\\\", "/")
            norm = os.path.normpath(name)
            if norm.startswith("..") or norm.startswith("/") or ":" in name.split("/")[0]:
                print("error: unsafe member " + name, file=sys.stderr); sys.exit(1)
            if info.is_dir():
                continue
            out = os.path.join(dest, *norm.split("/"))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out, "wb") as f:
                f.write(zf.read(info))


data = fetch(binary["url"])
if hashlib.sha256(data).hexdigest() != binary["sha256"]:
    print("error: binary digest does not match lock", file=sys.stderr); sys.exit(1)
sidecar = fetch(binary["url"] + ".sha256").decode("utf-8", "replace").split()[0].lower()
if sidecar != binary["sha256"]:
    print("error: official sidecar mismatch " + sidecar, file=sys.stderr); sys.exit(1)
core_data = fetch(core["url"])
if hashlib.sha256(core_data).hexdigest() != core["sha256"]:
    print("error: core digest does not match lock", file=sys.stderr); sys.exit(1)

if os.path.exists(moon_home):
    shutil.rmtree(moon_home)
os.makedirs(moon_home)
safe_extract(data, moon_home)
bin_dir = os.path.join(moon_home, "bin")
exe = os.path.join(bin_dir, "moon.exe")
env = dict(os.environ)
env["MOON_HOME"] = moon_home
proc = subprocess.run([exe, "version"], capture_output=True, timeout=180, env=env)
if proc.returncode != 0:
    print("error: moon version failed", proc.stderr.decode("utf-8", "replace")[:200], file=sys.stderr); sys.exit(1)
expected = base64.b64decode(lock["expectedMoonVersion"])
if proc.stdout != expected:
    print("error: moon version bytes mismatch", file=sys.stderr); sys.exit(1)
print("VERIFIED moon " + proc.stdout.decode("utf-8", "replace").splitlines()[0] + " at " + bin_dir)
print("BIN_DIR=" + bin_dir)
"@

$out = python3 -c $py 2>&1
if ($LASTEXITCODE -ne 0) {
    $out | Write-Error
    exit 1
}
$binDir = ($out | Where-Object { $_ -like "BIN_DIR=*" } | Select-Object -First 1) -replace "^BIN_DIR=", ""
if (-not $binDir -or -not (Test-Path (Join-Path $binDir "moon.exe"))) {
    $out | Write-Error
    exit 1
}

if ($env:GITHUB_PATH) {
    Add-Content -Path $env:GITHUB_PATH -Value $binDir
} else {
    $env:Path = "$binDir;$env:Path"
}

$pyObs = @"
import base64, json, os, platform, sys
lock_path = os.environ["PHASE14_LOCK_PATH"]
obs_path = os.environ.get("PHASE14_OBSERVATION_PATH", "moon-toolchain.json")
target = "windows-x86_64"
lock = json.load(open(lock_path))
binary = next(a for a in lock["archives"] if a["role"] == "binary" and a["targetPlatform"] == target)
core = next(a for a in lock["archives"] if a["role"] == "core" and a["targetPlatform"] == "core-zip")
raw = base64.b64decode(lock["expectedMoonVersion"]).decode("utf-8", "replace")
obs = {
    "schemaVersion": 1,
    "requestedVersion": lock["channelKey"],
    "reportedVersion": raw,
    "runnerOS": platform.system(),
    "runnerArch": platform.machine().lower(),
    "targetPlatform": target,
    "binarySha256": binary["sha256"],
    "binaryUrl": binary["url"],
    "coreSha256": core["sha256"],
    "coreUrl": core["url"],
    "provenance": binary["provenance"],
}
with open(obs_path, "w", encoding="utf-8") as f:
    json.dump(obs, f, indent=2, sort_keys=True)
    f.write("\n")
print("observation written: " + obs_path)
"@
$env:PHASE14_OBSERVATION_PATH = $ObservationPath
$obsOut = python3 -c $pyObs 2>&1
if ($LASTEXITCODE -ne 0) {
    $obsOut | Write-Error
    exit 1
}

Write-Output "moonbit installed (lock-driven): $binDir"
