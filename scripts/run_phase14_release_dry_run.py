#!/usr/bin/env python3
"""Phase 14-03 pre-merge release dry-run driver.

Executes the exact proposed Fathom release workflow bytes against the currently
registered workflow database ID at its registered legacy path, on a
validation-only temporary branch. Validates run identity, real artifacts,
evidence aggregation, nine-gate success and publication absence, then removes
both temporary refs.

Usage:
  run_phase14_release_dry_run.py --implementation-sha SHA --output-dir PATH --workflow-id 328270211
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
RELEASE_ARTIFACTS = {"fathom-lsp-linux-x86_64", "fathom-lsp-macos-aarch64", "fathom-lsp-windows-x86_64"}
MANIFEST_ARTIFACTS = {"fathom-release-manifests"}


def sh(*args, cwd=None, env=None):
    return subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True, timeout=1200)


def gh(*args):
    return sh("gh", *args)


def fail(msg):
    print(f"DRYRUN-FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def require(cond, msg):
    if not cond:
        fail(msg)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--implementation-sha", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--workflow-id", required=True, type=int)
    args = p.parse_args()

    sha = args.implementation_sha
    wf_id = args.workflow_id
    out_dir = os.path.abspath(args.output_dir)
    require(not os.path.exists(out_dir) or not os.listdir(out_dir), f"output dir must be absent/empty: {out_dir}")
    os.makedirs(out_dir, exist_ok=True)

    # implementation commit: new Fathom path present, legacy path absent
    ls = sh("git", "-C", REPO, "ls-tree", "-r", "--name-only", sha)
    require(ls.returncode == 0, f"cannot resolve implementation sha {sha}")
    files = ls.stdout.splitlines()
    require(".github/workflows/fathom-native-release.yml" in files, "implementation sha lacks new Fathom workflow")
    require(".github/workflows/doris-native-release.yml" not in files, "implementation sha must not carry legacy path")
    proposed = sh("git", "-C", REPO, "show", f"{sha}:.github/workflows/fathom-native-release.yml").stdout.encode()
    require(len(proposed) > 0, "proposed workflow bytes empty")

    # registration preflight: numeric ID bound to the legacy default-branch path
    reg = gh("api", f"repos/tchivs/fathom-sql/actions/workflows/{wf_id}",
             "--jq", "{id,path,name,state}")
    require(reg.returncode == 0, f"workflow query failed: {reg.stderr[:300]}")
    regj = json.loads(reg.stdout)
    require(regj["id"] == wf_id, f"workflow id mismatch: {regj['id']}")
    require(regj["state"] == "active", f"workflow not active: {regj['state']}")
    require(regj["path"] == ".github/workflows/doris-native-release.yml",
            f"workflow not registered at legacy path: {regj['path']}")

    nonce = f"{time.strftime('%Y%m%d%H%M%S')}-{uuid.uuid4().hex[:8]}"
    branch = f"phase14-release-dry-run-{nonce}"

    worktree = tempfile.mkdtemp(prefix="phase14-dryrun-")
    try:
        r = sh("git", "-C", REPO, "clone", "--no-checkout", "-q", ".", worktree)
        require(r.returncode == 0, f"clone failed: {r.stderr[:300]}")
        sh("git", "-C", worktree, "remote", "set-url", "origin", REMOTE)
        r = sh("git", "-C", worktree, "checkout", "-q", "-b", branch, sha)
        require(r.returncode == 0, f"cannot create branch: {r.stderr[:300]}")
        legacy = os.path.join(worktree, ".github/workflows/doris-native-release.yml")
        newp = os.path.join(worktree, ".github/workflows/fathom-native-release.yml")
        os.makedirs(os.path.dirname(legacy), exist_ok=True)
        with open(legacy, "wb") as f:
            f.write(proposed)
        os.remove(newp)
        # exactly one triggerable release workflow copy, bytes equal proposed
        copies = []
        for root, _dirs, files in os.walk(os.path.join(worktree, ".github/workflows")):
            for fn in files:
                if fn in ("doris-native-release.yml", "fathom-native-release.yml"):
                    copies.append(os.path.join(root, fn))
        require(len(copies) == 1 and os.path.basename(copies[0]) == "doris-native-release.yml",
                f"expected exactly one legacy-path release workflow copy, got {copies}")
        with open(copies[0], "rb") as f:
            require(f.read() == proposed, "temporary workflow bytes differ from proposed implementation")
        r = sh("git", "-C", worktree, "add", "-A", "--",
               ".github/workflows/doris-native-release.yml",
               ".github/workflows/fathom-native-release.yml")
        require(r.returncode == 0, f"git add failed: {r.stderr[:300]}")
        r = sh("git", "-C", worktree, "commit", "-q", "-m",
               f"chore(14): temporary same-path release dry-run mapping {nonce}")
        require(r.returncode == 0, f"commit failed: {r.stderr[:300]}")
        temp_head = sh("git", "-C", worktree, "rev-parse", "HEAD").stdout.strip()
        r = sh("git", "-C", worktree, "push", "-q", "origin", f"HEAD:refs/heads/{branch}")
        require(r.returncode == 0, f"push failed: {r.stderr[:300]}")

        d = gh("workflow", "run", str(wf_id), "-R", "tchivs/fathom-sql",
               "--ref", branch, "-f", "tag=v1.0.0", "-f", "dry_run=true")
        require(d.returncode == 0, f"dispatch failed: {d.stderr[:300]}")

        run_id = None
        deadline = time.time() + 120
        while time.time() < deadline:
            q = gh("api", "repos/tchivs/fathom-sql/actions/runs?event=workflow_dispatch&per_page=100")
            require(q.returncode == 0, f"runs query failed: {q.stderr[:300]}")
            rows = json.loads(q.stdout).get("workflow_runs", [])
            cands = [r for r in rows
                     if r["head_branch"] == branch and r["path"] == ".github/workflows/doris-native-release.yml"
                     and r["workflow_id"] == wf_id and r["head_sha"] == temp_head
                     and r["name"] == "Fathom Native Release"]
            if len(cands) == 1:
                run_id = cands[0]["id"]
                break
            time.sleep(5)
        require(run_id is not None, f"expected exactly one dispatch run for {branch}@{temp_head}")

        w = gh("run", "watch", str(run_id), "--exit-status", "-R", "tchivs/fathom-sql")
        require(w.returncode == 0, f"dry-run {run_id} failed: {w.stdout[-600:]} {w.stderr[-300:]}")

        rv = gh("run", "view", str(run_id), "-R", "tchivs/fathom-sql",
                "--json", "event,headBranch,headSha,conclusion,jobs,workflowName")
        require(rv.returncode == 0, "run view failed")
        runj = json.loads(rv.stdout)
        require(runj["event"] == "workflow_dispatch" and runj["headBranch"] == branch
                and runj["headSha"] == temp_head and runj["conclusion"] == "success",
                f"run identity/conclusion mismatch: {runj}")
        require(runj.get("workflowName") in ("Fathom Native Release", "Doris Native Release"),
                f"unexpected workflow name: {runj.get('workflowName')}")
        step_names = [s["name"] for j in runj.get("jobs", []) for s in j.get("steps", [])]
        require("Validate toolchain evidence and write aggregate manifest" in step_names
                and "keywords" in step_names and "Native parity" in step_names,
                "run did not execute the proposed Fathom workflow content")
        job_names = {j["name"] for j in runj.get("jobs", [])}
        require(all(j["conclusion"] == "success" for j in runj["jobs"]), "not all jobs succeeded")
        with open(os.path.join(out_dir, "run.json"), "w", encoding="utf-8") as f:
            json.dump(runj, f, indent=2, sort_keys=True)

        dl = gh("run", "download", str(run_id), "-R", "tchivs/fathom-sql",
                "--dir", os.path.join(out_dir, "artifacts"))
        require(dl.returncode == 0, f"artifact download failed: {dl.stderr[:300]}")
        art_root = os.path.join(out_dir, "artifacts")
        dirs = {d for d in os.listdir(art_root) if os.path.isdir(os.path.join(art_root, d))}
        require(dirs == (RELEASE_ARTIFACTS | MANIFEST_ARTIFACTS),
                f"artifact set mismatch: {dirs}")
        for plat in RELEASE_ARTIFACTS:
            sub = os.path.join(art_root, plat)
            names = os.listdir(sub)
            require("moon-toolchain.json" in names, f"{plat}: missing moon-toolchain.json")
            require(any(n.startswith("fathom-lsp-") for n in names), f"{plat}: missing native binary")
        man = os.path.join(art_root, "fathom-release-manifests")
        man_names = os.listdir(man)
        require("moon-toolchain-manifest.json" in man_names and "fathom-lsp-manifest.json" in man_names,
                f"manifest artifact incomplete: {man_names}")

        # aggregate evidence validation with the committed lock
        ev_dir = os.path.join(out_dir, "evidence")
        for plat in RELEASE_ARTIFACTS:
            os.makedirs(os.path.join(ev_dir, plat), exist_ok=True)
            shutil.copy(os.path.join(art_root, plat, "moon-toolchain.json"),
                        os.path.join(ev_dir, plat, "moon-toolchain.json"))
        agg = sh("python3", os.path.join(REPO, "scripts", "validate_toolchain_evidence.py"),
                 "--evidence-dir", ev_dir,
                 "--lock", os.path.join(REPO, ".github", "moonbit-toolchain.json"),
                 "--output", os.path.join(out_dir, "moon-toolchain-manifest.json"))
        require(agg.returncode == 0, f"aggregate validation failed: {agg.stdout} {agg.stderr}")
        with open(os.path.join(out_dir, "moon-toolchain-manifest.json"), encoding="utf-8") as f:
            manifest = json.load(f)
        require(len(manifest["platforms"]) == 3, "aggregate must retain three platform records")

        # publication absence: no GitHub Release for the dispatched tag
        rel = gh("release", "view", "v1.0.0", "-R", "tchivs/fathom-sql")
        require(rel.returncode != 0, "dry run must not create a GitHub Release")

        # cleanup: delete temporary remote + local branch and verify absence
        dl2 = gh("api", "-X", "DELETE", f"repos/tchivs/fathom-sql/git/refs/heads/{branch}")
        require(dl2.returncode == 0, f"failed to delete remote branch {branch}")
        time.sleep(2)
        refs = gh("api", f"repos/tchivs/fathom-sql/branches/{branch}")
        require(refs.returncode != 0, f"remote branch still exists: {branch}")
        sh("git", "-C", worktree, "branch", "-D", branch)
        print(json.dumps({"runId": run_id, "branch": branch, "tempHeadSha": temp_head,
                          "implementationSha": sha, "jobs": sorted(job_names)}, indent=2, sort_keys=True))
        print(f"DRYRUN-PASS: evidence validated, publication absent, temp refs removed")
    except SystemExit:
        print(f"RECOVERY: branch retained at {branch}; inspect run artifacts under {out_dir}; "
              f"delete with: gh api -X DELETE repos/tchivs/fathom-sql/git/refs/heads/{branch}", file=sys.stderr)
        raise
    finally:
        shutil.rmtree(worktree, ignore_errors=True)


if __name__ == "__main__":
    main()
