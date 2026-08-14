"""Unit tests for the Phase 14 porcelain status classifier.

Covers the NUL-safe porcelain-v1 parser (rename two-path records, unusual
names) and the fail-closed allowlist classification (clean status, each
allowed runtime path, matrix transient only in pre-mode, forbidden product
edit, generated/cache/duplicate untracked paths, unknown ``.omp-*``, rename,
spaces/newlines, status-class drift, post-commit matrix drift). Temp repos
mirror the real repository layout so the hard-coded allowlists apply.
"""

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "classify_release_status.py"

# A repository-relative path that contains both a space and a newline, which
# only NUL-delimited porcelain can carry without quoting.
WEIRD_NAME = ".planning/odd name\nfile.md"


def _load_module():
    spec = importlib.util.spec_from_file_location("classify_release_status", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


crs = _load_module()


class TempRepoMixin:
    def make_repo(self):
        root = tempfile.mkdtemp(prefix="classify-test-")
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", root], check=True))
        subprocess.run(["git", "init", "-q", root], check=True)
        subprocess.run(["git", "-C", root, "config", "user.email", "t@t"], check=True)
        subprocess.run(["git", "-C", root, "config", "user.name", "t"], check=True)
        pathlib.Path(root, "README.md").write_text("base\n", encoding="utf-8")
        self.commit_all(root)
        return root

    def commit_all(self, root, message="base"):
        subprocess.run(["git", "-C", root, "add", "-A"], check=True)
        staged = subprocess.check_output(
            ["git", "-C", root, "diff", "--cached", "--name-only"]
        ).strip()
        if not staged:
            return
        subprocess.run(["git", "-C", root, "commit", "-qm", message], check=True)

    def write(self, root, path, content="x"):
        target = pathlib.Path(root, path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def porcelain(self, root):
        out = subprocess.check_output(
            ["git", "-C", root, "status", "--porcelain=v1", "-z", "--untracked-files=all"]
        )
        return out

    def snapshot_for(self, root):
        entries = crs.parse_porcelain(self.porcelain(root))
        problems, runtime_paths = crs.snapshot_runtime_paths(entries)
        self.assertEqual(problems, [])
        return {"schemaVersion": 1, "command": "snapshot", "runtimePaths": runtime_paths}

    def classify(self, root, mode, snapshot=None, entries=None):
        if entries is None:
            entries = crs.parse_porcelain(self.porcelain(root))
        if snapshot is None:
            snapshot = {"schemaVersion": 1, "command": "snapshot", "runtimePaths": []}
        return crs.classify_entries(entries, mode, snapshot)


class ParsePorcelainTests(unittest.TestCase):
    def test_parse_porcelain_clean(self):
        self.assertEqual(crs.parse_porcelain(b""), [])

    def test_parse_porcelain_modified_and_untracked(self):
        data = b" M .planning/.omp-next-action.json\0?? scripts/x.py\0"
        entries = crs.parse_porcelain(data)
        self.assertEqual(
            entries,
            [
                {"status": " M", "path": ".planning/.omp-next-action.json", "orig_path": None},
                {"status": "??", "path": "scripts/x.py", "orig_path": None},
            ],
        )

    def test_parse_porcelain_rename_two_path_records(self):
        data = b"R  new.txt\0old.txt\0"
        entries = crs.parse_porcelain(data)
        self.assertEqual(
            entries,
            [{"status": "R ", "path": "new.txt", "orig_path": "old.txt"}],
        )

    def test_parse_porcelain_rename_missing_source_fails(self):
        with self.assertRaises(ValueError):
            crs.parse_porcelain(b"R  new.txt\0")

    def test_parse_porcelain_bare_record_fails(self):
        with self.assertRaises(ValueError):
            crs.parse_porcelain(b"not a status record\0")

    def test_parse_porcelain_path_with_space_and_newline_via_git(self):
        root = tempfile.mkdtemp(prefix="classify-test-")
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", root], check=True))
        subprocess.run(["git", "init", "-q", root], check=True)
        target = pathlib.Path(root, WEIRD_NAME)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("x", encoding="utf-8")
        out = subprocess.check_output(
            ["git", "-C", root, "status", "--porcelain=v1", "-z", "--untracked-files=all"]
        )
        entries = crs.parse_porcelain(out)
        self.assertEqual(
            entries, [{"status": "??", "path": WEIRD_NAME, "orig_path": None}]
        )


class SnapshotTests(TempRepoMixin, unittest.TestCase):
    def test_snapshot_records_only_present_runtime_paths(self):
        root = self.make_repo()
        for path in crs.RUNTIME_PATHS:
            self.write(root, path)
        self.commit_all(root)
        self.write(root, ".planning/.omp-next-action.json", "changed-1")
        self.write(root, ".planning/.omp-task-results.json", "changed-2")
        snapshot = self.snapshot_for(root)
        self.assertEqual(
            snapshot["runtimePaths"],
            [
                {"path": ".planning/.omp-next-action.json", "status": " M"},
                {"path": ".planning/.omp-task-results.json", "status": " M"},
            ],
        )

    def test_snapshot_fails_on_unknown_omp_path(self):
        root = self.make_repo()
        self.write(root, ".planning/.omp-sneaky.json")
        self.commit_all(root)
        self.write(root, ".planning/.omp-sneaky.json", "changed")
        entries = crs.parse_porcelain(self.porcelain(root))
        problems, _ = crs.snapshot_runtime_paths(entries)
        self.assertTrue(any("unknown .omp-*" in p for p in problems))

    def test_cli_snapshot_requires_output(self):
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), "snapshot"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 2)
        self.assertIn("--output", proc.stderr)

    def test_cli_snapshot_writes_deterministic_json(self):
        root = self.make_repo()
        for path in crs.RUNTIME_PATHS:
            self.write(root, path)
        self.commit_all(root)
        self.write(root, ".planning/.omp-next-action.json", "changed")
        with tempfile.TemporaryDirectory(prefix="classify-snap-") as tmp:
            snap_path = pathlib.Path(tmp, "snapshot.json")
            proc = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "snapshot",
                    "--output",
                    str(snap_path),
                    "--porcelain-command",
                    "git status --porcelain=v1 -z --untracked-files=all",
                ],
                capture_output=True,
                text=True,
                cwd=root,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            payload = json.loads(snap_path.read_text(encoding="utf-8"))
            self.assertEqual(
                payload["runtimePaths"],
                [{"path": ".planning/.omp-next-action.json", "status": " M"}],
            )
            self.assertEqual(
                proc.stdout,
                json.dumps(payload, sort_keys=True, indent=2) + "\n",
            )


class ClassifyTests(TempRepoMixin, unittest.TestCase):
    def base_repo_with_runtime(self):
        root = self.make_repo()
        for path in crs.RUNTIME_PATHS:
            self.write(root, path)
        self.commit_all(root)
        self.write(root, ".planning/.omp-next-action.json", "changed-1")
        self.write(root, ".planning/.omp-task-results.json", "changed-2")
        return root

    def test_clean_status_passes_post(self):
        root = self.make_repo()
        self.write(root, "README.md")
        self.commit_all(root)
        problems, allowlisted = self.classify(root, "post-matrix-commit")
        self.assertEqual(problems, [])
        self.assertEqual(allowlisted, [])

    def test_each_allowed_runtime_path_passes(self):
        root = self.make_repo()
        for path in crs.RUNTIME_PATHS:
            self.write(root, path)
        self.commit_all(root)
        # .omp-checkpoint.json is committed clean and never modified: it must
        # not appear in porcelain and therefore must not be allowlisted.
        self.write(root, ".planning/.omp-next-action.json", "changed-1")
        snapshot = self.snapshot_for(root)
        for mode in crs.VALID_MODES:
            problems, allowlisted = self.classify(
                root, mode, snapshot=snapshot
            )
            self.assertEqual(problems, [], mode)
            self.assertEqual(
                [a["path"] for a in allowlisted],
                [".planning/.omp-next-action.json"],
            )
            self.assertEqual(allowlisted[0]["kind"], "runtime")

    def test_matrix_transient_only_in_pre_mode(self):
        root = self.make_repo()
        self.commit_all(root)
        matrix = ".planning/phases/14-release-hygiene-toolchain-pinning/14-RELEASE-READINESS.md"
        self.write(root, matrix)
        problems, allowlisted = self.classify(root, "pre-matrix-commit")
        self.assertEqual(problems, [])
        self.assertEqual(
            allowlisted,
            [{"path": matrix, "status": "??", "kind": "task-transient"}],
        )
        problems, _ = self.classify(root, "post-matrix-commit")
        self.assertTrue(any("unexpected" in p for p in problems))

    def test_forbidden_product_edit(self):
        root = self.make_repo()
        self.write(root, ".planning/ROADMAP.md")
        self.commit_all(root)
        self.write(root, ".planning/ROADMAP.md", "edited")
        for mode in crs.VALID_MODES:
            problems, _ = self.classify(root, mode)
            self.assertTrue(any("unexpected" in p for p in problems), mode)

    def test_untracked_generated_cache_duplicate_paths(self):
        root = self.make_repo()
        self.commit_all(root)
        for stray in (
            "fathom-sql/pkg.generated.mbti",
            ".planning/research/.cache/regenerable.json",
            ".planning/quick/260805-dup/PLAN.md",
        ):
            self.write(root, stray)
        for mode in crs.VALID_MODES:
            problems, _ = self.classify(root, mode)
            self.assertTrue(any("unexpected" in p for p in problems), mode)

    def test_unknown_omp_path_fails(self):
        root = self.make_repo()
        self.write(root, ".planning/.omp-unknown-state.json")
        self.commit_all(root)
        self.write(root, ".planning/.omp-unknown-state.json", "changed")
        for mode in crs.VALID_MODES:
            problems, _ = self.classify(root, mode)
            self.assertTrue(any("unknown .omp-*" in p for p in problems), mode)

    def test_rename_fails_classification(self):
        root = self.make_repo()
        self.write(root, "src/product.mbt")
        self.commit_all(root)
        subprocess.run(["git", "-C", root, "mv", "src/product.mbt", "src/renamed.mbt"], check=True)
        entries = crs.parse_porcelain(self.porcelain(root))
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["status"], "R ")
        self.assertEqual(entries[0]["path"], "src/renamed.mbt")
        self.assertEqual(entries[0]["orig_path"], "src/product.mbt")
        for mode in crs.VALID_MODES:
            problems, _ = self.classify(root, mode, entries=entries)
            self.assertTrue(any("unexpected" in p for p in problems), mode)

    def test_unusual_name_fails_classification(self):
        root = self.make_repo()
        self.commit_all(root)
        self.write(root, WEIRD_NAME)
        for mode in crs.VALID_MODES:
            problems, _ = self.classify(root, mode)
            self.assertTrue(any("unexpected" in p for p in problems), mode)

    def test_status_class_change_fails(self):
        root = self.base_repo_with_runtime()
        snapshot = self.snapshot_for(root)
        subprocess.run(
            ["git", "-C", root, "add", ".planning/.omp-next-action.json"], check=True
        )
        problems, _ = self.classify(root, "post-matrix-commit", snapshot=snapshot)
        self.assertTrue(any("status class changed" in p for p in problems))

    def test_runtime_path_no_longer_present_fails(self):
        root = self.base_repo_with_runtime()
        snapshot = self.snapshot_for(root)
        self.commit_all(root, "sweep runtime files away")
        problems, _ = self.classify(root, "post-matrix-commit", snapshot=snapshot)
        self.assertTrue(any("no longer present" in p for p in problems))

    def test_post_commit_matrix_drift_fails(self):
        root = self.make_repo()
        self.commit_all(root)
        matrix = ".planning/phases/14-release-hygiene-toolchain-pinning/14-RELEASE-READINESS.md"
        self.write(root, matrix)
        self.commit_all(root, "matrix committed")
        self.write(root, matrix, "drift after commit")
        problems, _ = self.classify(root, "post-matrix-commit")
        self.assertTrue(any("unexpected" in p for p in problems))

    def test_cli_classify_end_to_end(self):
        root = self.base_repo_with_runtime()
        snapshot = self.snapshot_for(root)
        with tempfile.TemporaryDirectory(prefix="classify-snap-") as tmp:
            snap_path = pathlib.Path(tmp, "snapshot.json")
            snap_path.write_text(
                json.dumps(snapshot, sort_keys=True), encoding="utf-8"
            )
            command = "git status --porcelain=v1 -z --untracked-files=all"
            ok = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "classify",
                    "--mode",
                    "post-matrix-commit",
                    "--snapshot",
                    str(snap_path),
                    "--porcelain-command",
                    command,
                ],
                capture_output=True,
                text=True,
                cwd=root,
            )
            self.assertEqual(ok.returncode, 0, ok.stderr)
            payload = json.loads(ok.stdout)
            self.assertEqual(payload["verdict"], "PASS")
            self.assertEqual(payload["mode"], "post-matrix-commit")
            self.assertEqual(payload["porcelainCommand"], command)

            # Forbidden product edit -> nonzero, diagnostics on stderr, no JSON.
            self.write(root, ".planning/ROADMAP.md", "edited")
            bad = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "classify",
                    "--mode",
                    "post-matrix-commit",
                    "--snapshot",
                    str(snap_path),
                    "--porcelain-command",
                    command,
                ],
                capture_output=True,
                text=True,
                cwd=root,
            )
            self.assertEqual(bad.returncode, 1)
            self.assertEqual(bad.stdout, "")
            self.assertIn("unexpected", bad.stderr)

    def test_cli_classify_missing_snapshot(self):
        root = self.make_repo()
        proc = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "classify",
                "--mode",
                "post-matrix-commit",
                "--snapshot",
                "/nonexistent/snapshot.json",
            ],
            capture_output=True,
            text=True,
            cwd=root,
        )
        self.assertEqual(proc.returncode, 2)
        self.assertIn("not found", proc.stderr)


if __name__ == "__main__":
    unittest.main()
