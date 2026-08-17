# Phase 14 Release Readiness Matrix

**Phase:** 14 — Release Hygiene & Toolchain Pinning
**Plan:** 14-05 (final readiness classification)
**Compiled:** 2026-08-14
**Scope:** Single final evidence/status matrix for HYG-01/02/03 and TC-01/02 plus decision coverage D-01..D-14.

> **Status check disclaimer:** matrix prose is **not** the status check. The
> executable status gate is `scripts/classify_release_status.py`, run against
> real `git status --porcelain=v1 -z --untracked-files=all` output with a
> NUL-safe porcelain-v1 parser, an explicit runtime-state snapshot, and
> fail-closed allowlists (`pre-matrix-commit` / `post-matrix-commit` modes).
> Every COMPLETE row below is backed by an executed command (exact command,
> observed exit/result) and/or a committed artifact; BLOCKED rows cite the
> official-channel evidence that fail-closed the work (D-01/D-03).

## Requirement Status

### HYG-01 — Uncommitted CI changes committed; clean release tree

**Status: COMPLETE**

- Authoritative text: `jetbrains-plugin.yml` action bumps (checkout v4→v7, setup-java v4→v5, upload-artifact v4→v7) committed as the only byte delta; working tree audited clean of uncommitted CI changes by the final status classifier.
- D-ID coverage: D-14 (action-only JetBrains delta).
- Committed paths / commit IDs: `.github/workflows/jetbrains-plugin.yml` — `8cc3f9d` ("ci(14): bump JetBrains actions to checkout@v7, setup-java@v5, upload-artifact@v7"). Provenance: 14-04-SUMMARY.md byte-transform proof (parent blob + exactly three action replacements == committed bytes; `git diff-tree --name-only -r HEAD` single path).
- Executed evidence:
  - `git show --stat 8cc3f9d` — one path, 1195→1195 bytes, 3-line delta (recorded in 14-04-SUMMARY).
  - `git status --porcelain=v1 -z --untracked-files=all` via `python3 scripts/classify_release_status.py classify --mode post-matrix-commit` — PASS after 14-05 close-out (only `.planning/.omp-next-action.json` and `.planning/.omp-task-results.json` remain as allowlisted runtime state).
- Failure contract: any modified product/planning path or untracked generated/cache/duplicate path fails the classifier; HYG-01 is not satisfied by prose alone.

### HYG-02 — Generated-file policy: `pkg.generated.mbti` covered by `.gitignore`

**Status: COMPLETE**

- Authoritative text: repository-wide `pkg.generated.mbti` basename rule and `.planning/research/.cache/` rule added to `.gitignore`; no `moon info` generated interface remains untracked in the tree.
- D-ID coverage: D-10 (repo-level generated-interface rule), D-11 (research-cache deletion + ignore).
- Committed paths / commit IDs: `.gitignore` — `ff966c1` ("chore(14): ignore generated MoonBit interfaces and research cache").
- Executed evidence:
  - `git check-ignore -v --no-index probe/pkg.generated.mbti` → `.gitignore:15:pkg.generated.mbti` (provenance proven).
  - `git check-ignore -v --no-index .planning/research/.cache/probe.json` → `.gitignore:18:.planning/research/.cache/`.
  - Negatives: handwritten `probe/handwritten.mbti` and `.planning/.omp-*.json` unignored (recorded in 14-04-SUMMARY).
  - `test ! -e fathom-sql/pkg.generated.mbti && test ! -e .planning/research/.cache/` — removed as local hygiene (post `ff966c1`).
- Failure contract: any untracked `*pkg.generated.mbti` or `.planning/research/.cache/*` path appearing in porcelain fails the final classifier (`test_untracked_generated_cache_duplicate_paths` in `scripts/tests/test_classify_release_status.py`).

### HYG-03 — `.planning` strays cleaned or archived; excluded from release commits

**Status: COMPLETE**

- Authoritative text: regenerable cache deleted and ignored; untracked duplicate quick `PLAN.md` files removed with digest-preserved canonical summaries; the `v1.0-research` milestone archive committed exactly; session/runtime state excluded from release commits via explicit allowlist.
- D-ID coverage: D-11 (cache/duplicate deletion + summary retention), D-12 (exact formal archive), D-13 (preserve named runtime/user state).
- Committed paths / commit IDs:
  - `.planning/milestones/v1.0-research/{ARCHITECTURE,FEATURES,PITFALLS,STACK,SUMMARY}.md` — `e63eec5` ("docs(14-05): commit exact five-file v1.0-research milestone archive"); verified `git diff-tree --no-commit-id --name-only -r HEAD` == exactly those five paths; every member tracked (`git ls-files --error-unmatch`) and nonempty (40,014 / 32,898 / 46,785 / 31,033 / 31,325 bytes); all 50 tracked references containing `v1.0-research/` resolve within the five-file set.
  - `scripts/classify_release_status.py`, `scripts/tests/test_classify_release_status.py`, this matrix — committed by 14-05 Task 3 (hash recorded in `14-05-SUMMARY.md`).
- Executed evidence:
  - Quick-summary digest preservation (14-05 Task 1): `python3 -c '<sha256 digest writer>' "$TMP_DIR/quick-summary-pre.sha256" <both SUMMARY paths>`; deletion of only the two untracked duplicate `PLAN.md` paths; post-deletion re-hash equality + `git diff --quiet HEAD -- <SUMMARY>` rc=0. Digests:
    - `c7f5930bbda7297aeb50a2832feac3f395959c868bd6e572f15162021cb070c8  .planning/quick/260805-df9-add-a-kotlin-gradle-jetbrains-intellij-p/SUMMARY.md`
    - `813639ae7488fec9a0af3dbb0e08cbae77b88fbd8564fc5abb2bc993207d3926  .planning/quick/260805-e28-align-the-jetbrains-plugin-wrapper-and-d/SUMMARY.md`
  - Runtime-state exclusion (14-05 Task 3): `python3 scripts/classify_release_status.py snapshot --output "$TMP_DIR/phase14-runtime-status.json"` records only `.planning/.omp-next-action.json` (` M`) and `.planning/.omp-task-results.json` (` M`); pre- and post-matrix-commit classifications PASS with real `git status --porcelain=v1 -z --untracked-files=all`; `.planning/.omp-checkpoint.json` has no scoped status row and is not allowlisted (any later modification fails — D-13/T-14-29).
  - Unit tests: `python3 -m unittest scripts.tests.test_classify_release_status -v` — 23 tests OK (clean status, allowed runtime paths, matrix transient only in pre-mode, forbidden product edit, generated/cache/duplicate untracked paths, unknown `.omp-*`, rename two-path records, spaces/newlines in names, status-class drift, post-commit matrix drift).
- Failure contract: any sixth archive member, unresolved `v1.0-research/` reference, unexpected staged path, or non-allowlisted porcelain entry fails its respective check; no `git clean`/reset/stash is ever used to absorb unknown user work (D-13).

### TC-01 — Pinned MoonBit toolchain + per-platform toolchain evidence in release artifacts

**Status: COMPLETE** (three-platform content lock; D-01/D-03 revised 2026-08-14, user-approved)

- Authoritative text: release pipeline must build with one exact static MoonBit version (no `latest`) and record exact toolchain version into release artifacts; the freeze must be proven acquirable on all four target platforms (D-01..D-03, D-07..D-09).
- D-ID coverage: D-01, D-02, D-03, D-07, D-08, D-09.
- Committed paths / commit IDs:
  - `.github/moonbit-toolchain.json` — `eb77525` (freeze, 14-01): 5 archive records (linux-x86_64=`36f5e7cf…`, darwin-aarch64=`b4781a1e…`, windows-x86_64=`c659625f…` official sidecars; core-tar.gz=`06922d35…`, core-zip=`bdf280aa…` recorded) + expected `moon 0.1.20260807 (4da23f8 2026-08-07)`; 3 Sigstore attestations verified (run 31993236748)
  - `.github/scripts/install-moonbit.sh` / `.ps1` — `2948bc1` (14-02): lock-driven verified installers; native windows-2025 proof run 31994107232 (real install, byte-identical version)
  - `scripts/validate_toolchain_evidence.py` + fixtures — `dcc8942` (14-03): 1 valid + 7 defect aggregate cases
  - `scripts/run_phase14_release_dry_run.py` + workflow — `cf286ba`/`2e8faa61` (14-03): dry-run driver
- Executed evidence (2026-08-17):
  - Freeze (14-01): `gh run 31993236748` success — 3 native runners (ubuntu-24.04 / macos-14 / windows-2025) with exact arch + byte-identical version; 3 `gh attestation verify` rc=0; verifier atomic lock; temp branch deleted
  - Installers (14-02): 8 Unix behavior tests + windows-2025 fixture subset + real install (run 31994107232) — sidecar/digest/layout/version fail-closed verified
  - Aggregate (14-03): dry-run run 31995140506 — evidence aggregation against the committed lock produced `moon-toolchain-manifest.json` with exactly 3 platform records
- Local provenance only (not a release pin): historical `moon 0.1.20260724 (5f1406a 2026-07-24)` is documented as unavailable from the official installer and was never used as a pin.
- Failure contract: acquiring the exact version, verifying official sidecars, and recording `moon-toolchain.json` per platform (D-07) are prerequisites; any missing platform artifact, missing/incorrect sidecar, or requested/reported version mismatch blocks the release (D-03/D-09). TC-01 is COMPLETE with executed freeze/installer/aggregate evidence above; macOS Intel was removed from the release target by the user-approved D-01/D-03 revision (2026-08-14).

### TC-02 — Full release gate matrix before publishing

**Status: COMPLETE** (pre-merge dry-run run 31995140506, 5/5 jobs success)

- Authoritative text: release CI must run native/js/linear-wasm parity, `diff_parity --frozen-only`, `check_naming`, corpus `--check` (full nine-command set) before publishing; any failure blocks the release (D-04..D-06).
- D-ID coverage: D-04, D-05, D-06.
- Committed paths / commit IDs: `.github/workflows/fathom-native-release.yml` — `cf286ba` (+`2e8faa61`): 3-platform build matrix with per-platform `moon-toolchain.json` evidence, independent `release-gates` job, `release` job with `needs: [build, release-gates]` and `contents: write` only there; `scripts/validate_toolchain_evidence.py` — `dcc8942`; dry-run driver — `cf286ba`/`2e8faa61`.
- Executed evidence (2026-08-17):
  - Pre-merge dry-run `gh run 31995140506` — 5/5 jobs success: Build linux-x86_64, Build macos-aarch64, Build windows-x86_64, Release qualification gates, Publish GitHub Release
  - Nine gate steps all success (exact commands): Native parity, JavaScript parity, linear-Wasm parity, compare_backends, diff_parity (--frozen-only), check_naming, verify_corpus (--check), corpus report (--check), keywords; no `--update`/`continue-on-error`
  - Release job validated aggregate evidence, generated `fathom-lsp-manifest.json` + `moon-toolchain-manifest.json`; `gh release view phase14-dry-run` 404 — publication correctly skipped under `dry_run=true`
  - Temp branch deleted after validated evidence; no GitHub Release created
- Failure contract: `release` must explicitly `needs` `build` + `release-gates` with no `always()`/bypass input (D-04/D-06); the nine commands must run with real fail-closed semantics (`--frozen-only`, `--check`, no `--update`, no `continue-on-error`, no empty-result tolerance) and gate publication (D-05). TC-02 is COMPLETE with the actual successful `release-gates` job run in CI (dry-run run 31995140506, 9/9 steps success, publication absent).

## Decision Coverage Mapping (D-01..D-14)

| Decision | Requirement | Status | Evidence |
|----------|-------------|--------|----------|
| D-01 | TC-01 | COMPLETE | three-platform content lock (revised 2026-08-14); official sidecars + recorded core digests — `eb77525` |
| D-02 | TC-01 | COMPLETE | shared lock-driven installers + ordinary CI single entry — `2948bc1` |
| D-03 | TC-01 | COMPLETE | binary official sidecar verification + core recorded-digest with documented absence (revision) — verified at freeze/install/dry-run |
| D-04 | TC-02 | COMPLETE | `release-gates` job wired; `release.needs: [build, release-gates]` — `cf286ba`, dry-run 31995140506 |
| D-05 | TC-02 | COMPLETE | nine-command gate run executed once with success (9/9 steps) — run 31995140506 |
| D-06 | TC-02 | COMPLETE | tag + workflow_dispatch share the DAG; no skip input; dry_run only skips final Release steps — `cf286ba` |
| D-07 | TC-01 | COMPLETE | per-platform `moon-toolchain.json` beside binaries in build artifacts — dry-run artifacts validated |
| D-08 | TC-01 | COMPLETE | aggregate `moon-toolchain-manifest.json` written by validator after exact-set success — run 31995140506 |
| D-09 | TC-01 | COMPLETE | validator + fixtures prove every mismatch blocks with no output (7 defect cases) |
| D-10 | HYG-02 | COMPLETE | `.gitignore` `pkg.generated.mbti` rule — `ff966c1`; `check-ignore -v` provenance |
| D-11 | HYG-03 | COMPLETE | `.planning/research/.cache/` deleted+ignored (`ff966c1`); duplicate quick `PLAN.md` deleted with digest-preserved summaries (14-05 Task 1) |
| D-12 | HYG-03 | COMPLETE | five-file `v1.0-research` archive committed exactly — `e63eec5`; all references resolve |
| D-13 | HYG-03 | COMPLETE | runtime `.omp-*` state allowlisted via snapshot; fail-closed porcelain classifier |
| D-14 | HYG-01 | COMPLETE | action-only JetBrains delta — `8cc3f9d` (byte-transform proof) |

## Final Status Evidence

- Freeze evidence (14-01): `gh run 31993236748` success; 3 records; 3 attestations verified; lock `eb77525`; temp branch removed; workflows byte-unchanged (verify-cleanup PASS).
- Installer evidence (14-02): 8 Unix tests + native windows-2025 subset + real install (run 31994107232); ci.yml 5/5 shared-helper call sites; nine gate commands intact.
- Release gate evidence (14-03): dry-run run 31995140506, 5/5 jobs success, nine gate steps success, aggregate manifest written, `gh release view phase14-dry-run` 404, temp branch removed.
- Pre-matrix-commit classification (14-05): PASS. Post-matrix-commit classification: PASS — only the two pre-existing runtime paths remain modified; no task transient and no other path present.
- Final porcelain (`git status --porcelain=v1 -z --untracked-files=all` after close-out): only ` M .planning/.omp-next-action.json` and ` M .planning/.omp-task-results.json` (runtime state per D-13).
- Matrix checks supplement but never replace the executed freeze/installer/aggregate/release-gates/status evidence named above.

---
*Phase: 14-release-hygiene-toolchain-pinning*
*Matrix compiled: 2026-08-14*
