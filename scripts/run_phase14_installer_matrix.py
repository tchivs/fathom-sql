#!/usr/bin/env python3
"""Phase 14-02 Windows installer matrix driver.

Single command that proves the PowerShell installer on a native windows-2025
runner: creates a temporary branch-restricted push workflow from an
implementation commit, uniquely selects the exact run, downloads the nested
evidence artifact, validates identity, and only then removes the remote branch.

Usage: python3 scripts/run_phase14_installer_matrix.py --implementation-sha SHA --output-dir PATH
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REMOTE = "https://github.com/tchivs/fathom-sql.git"


def sh(*args, cwd=None, env=None):
    return subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True, timeout=600)


def gh(*args):
    return sh("gh", *args)


def fail(msg):
    print(f"DRIVER-FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def require(cond, msg):
    if not cond:
        fail(msg)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--implementation-sha", required=True)
    p.add_argument("--output-dir", required=True)
    args = p.parse_args()

    sha = args.implementation_sha
    out_dir = os.path.abspath(args.output_dir)
    require(not os.path.exists(out_dir) or not os.listdir(out_dir), f"output dir must be absent/empty: {out_dir}")
    os.makedirs(out_dir, exist_ok=True)

    # implementation commit must carry the planned files
    ls = sh("git", "-C", REPO, "ls-tree", "--name-only", sha)
    require(ls.returncode == 0, f"cannot resolve implementation sha {sha}")
    for path in (".github/scripts/install-moonbit.sh", ".github/scripts/install-moonbit.ps1",
                 "scripts/tests/test_install_moonbit.py", "scripts/run_phase14_installer_matrix.py"):
        require(path in ls.stdout.splitlines(), f"implementation sha lacks {path}")

    nonce = f"{time.strftime('%Y%m%d%H%M%S')}-{uuid.uuid4().hex[:8]}"
    branch = f"phase14-installer-tests-{nonce}"
    wf_name = f"Phase 14 Installer Tests {nonce}"
    wf_path = ".github/workflows/phase14-installer-tests.yml"

    workflow = f"""name: {wf_name}
on:
  push:
    branches: ["{branch}"]
permissions:
  contents: read
jobs:
  installer:
    runs-on: windows-2025
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-python@v6
        with:
          python-version: '3.11'
      - name: PowerShell fixture subset
        shell: bash
        run: python3 scripts/tests/test_install_moonbit.py --platform windows
      - name: Real lock-driven install
        shell: pwsh
        env:
          OBSERVATION_PATH: windows-installer-real.json
        run: .github/scripts/install-moonbit.ps1
      - name: Aggregate result
        shell: bash
        run: |
          python3 - <<'EOF'
          import json, os
          res = {{"testExit": 0, "realInstall": {{}}}}
          try:
              with open("windows-installer-real.json", encoding="utf-8") as f:
                  res["realInstall"] = json.load(f)
          except Exception as e:
              res["testExit"] = 1
              res["error"] = str(e)
          with open("windows-installer-result.json", "w", encoding="utf-8") as f:
              json.dump(res, f, indent=2, sort_keys=True)
              f.write("\\n")
          EOF
          ls -la windows-installer-result.json
      - uses: actions/upload-artifact@v7
        with:
          name: windows-installer-result
          path: windows-installer-result.json
          if-no-files-found: error
"""
    wf_bytes = workflow.encode()

    worktree = tempfile.mkdtemp(prefix="phase14-installer-matrix-")
    try:
        r = sh("git", "-C", REPO, "clone", "--no-checkout", "-q", ".", worktree)
        require(r.returncode == 0, f"clone failed: {r.stderr[:300]}")
        # re-point origin to the GitHub remote (local clone origin is a local path)
        sh("git", "-C", worktree, "remote", "set-url", "origin", REMOTE)
        r = sh("git", "-C", worktree, "checkout", "-q", "-b", branch, sha)
        require(r.returncode == 0, f"cannot create branch: {r.stderr[:300]}")
        wf_abs = os.path.join(worktree, wf_path)
        os.makedirs(os.path.dirname(wf_abs), exist_ok=True)
        with open(wf_abs, "wb") as f:
            f.write(wf_bytes)
        r = sh("git", "-C", worktree, "add", wf_path)
        require(r.returncode == 0, "git add failed")
        r = sh("git", "-C", worktree, "commit", "-q", "-m",
               f"chore(14): temporary installer matrix workflow {nonce}")
        require(r.returncode == 0, f"commit failed: {r.stderr[:300]}")
        probe = sh("git", "-C", worktree, "rev-parse", "HEAD").stdout.strip()
        r = sh("git", "-C", worktree, "push", "-q", "origin", f"HEAD:refs/heads/{branch}")
        require(r.returncode == 0, f"push failed: {r.stderr[:300]}")

        run_id = None
        deadline = time.time() + 120
        while time.time() < deadline:
            q = gh("api", "repos/tchivs/fathom-sql/actions/runs",
                   "-f", "event=push", "-f", "per_page=100")
            require(q.returncode == 0, f"runs query failed: {q.stderr[:300]}")
            rows = json.loads(q.stdout).get("workflow_runs", [])
            cands = [r for r in rows
                     if r["head_branch"] == branch and r["path"] == wf_path
                     and r["head_sha"] == probe and r["event"] == "push"
                     and r["name"] == wf_name]
            if len(cands) == 1:
                run_id = cands[0]["id"]
                break
            time.sleep(5)
        require(run_id is not None, f"expected exactly one matching run for {branch}@{probe}")

        w = gh("run", "watch", str(run_id), "--exit-status", "-R", "tchivs/fathom-sql")
        require(w.returncode == 0, f"run {run_id} failed: {w.stdout[-500:]} {w.stderr[-500:]}")

        d = gh("run", "download", str(run_id), "-R", "tchivs/fathom-sql",
               "--dir", os.path.join(out_dir, "artifacts"))
        require(d.returncode == 0, f"artifact download failed: {d.stderr[:300]}")

        found = []
        for root, _dirs, files in os.walk(os.path.join(out_dir, "artifacts")):
            for fn in files:
                if fn == "windows-installer-result.json":
                    found.append(os.path.join(root, fn))
        require(len(found) == 1, f"expected exactly one windows-installer-result.json, got {found}")
        with open(found[0], encoding="utf-8") as f:
            result = json.load(f)
        require(result.get("testExit") == 0, f"windows fixture subset failed: {result}")
        ri = result.get("realInstall", {})
        require(ri.get("targetPlatform") == "windows-x86_64", f"bad real-install record: {ri}")
        require(ri.get("provenance") == "official-sidecar", f"bad provenance: {ri}")
        require(ri.get("requestedVersion") == "latest", f"bad requested version: {ri}")
        # validated evidence is durable; only now remove the temporary branch
        dl = gh("api", "-X", "DELETE", f"repos/tchivs/fathom-sql/git/refs/heads/{branch}")
        require(dl.returncode == 0, f"failed to delete temporary branch {branch}")
        time.sleep(2)
        refs = gh("api", f"repos/tchivs/fathom-sql/branches/{branch}")
        require(refs.returncode != 0, f"temporary branch still exists after deletion: {branch}")
        print(json.dumps({"runId": run_id, "branch": branch, "probeSha": probe,
                          "result": result}, indent=2, sort_keys=True))
        print(f"RESULT-PATH {found[0]}")
    finally:
        shutil.rmtree(worktree, ignore_errors=True)


if __name__ == "__main__":
    main()
