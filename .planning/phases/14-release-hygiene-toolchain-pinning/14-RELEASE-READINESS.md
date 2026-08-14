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

**Status: BLOCKED** (fail-closed; 14-01..14-03 not executed)

- Authoritative text: release pipeline must build with one exact static MoonBit version (no `latest`) and record exact toolchain version into release artifacts; the freeze must be proven acquirable on all four target platforms (D-01..D-03, D-07..D-09).
- D-ID coverage: D-01, D-02, D-03, D-07, D-08, D-09.
- Committed paths / commit IDs: none — no freeze/installer/aggregation plan was executed (14-01/14-02/14-03 BLOCKED by the official-channel evidence below per the user-approved 2026-08-14 split; HYG track proceeded because it is file-disjoint).
- Executed evidence (official-channel probes, verified 2026-08-14):
  - Official MoonBit channel, verified 2026-08-14: `binaries/latest/moonbit-darwin-x86_64.tar.gz` and its `.sha256` -> HTTP 403 (no Intel-macOS artifact; official unix installer maps only darwin-aarch64/linux-x86_64/linux-aarch64); `cores/core-latest.tar.gz.sha256` and `cores/core-latest.zip.sha256` -> 403 (S3 AccessDenied); versioned paths `binaries/0.1.20240520%2Bb1f30d5e1|0.1.20260807|0.1.20260807%2B4da23f8/moonbit-*` and `cores/core-<key>.*.sha256` -> all 403 (no static channel key); S3 bucket listing denied; `moonbitlang/moon` and `moonbitlang/core` GitHub Releases = 0 releases; official setup actions accept only `latest`/`nightly`. Available official sidecars: linux-x86_64=36f5e7cf..., darwin-aarch64=b4781a1e..., windows-x86_64=c659625f.... Per D-01/D-03 fail-closed, freeze is blocked; 14-01..14-03 not executed.
  - Local provenance only (not a release pin): `moon version` reports `moon 0.1.20260724 (5f1406a 2026-07-24)`; that archive is documented as unavailable from the official installer and is ineligible as a release pin.
- Failure contract: acquiring the exact version, verifying official sidecars, and recording `moon-toolchain.json` per platform (D-07) are prerequisites; any missing platform artifact, missing/incorrect sidecar, or requested/reported version mismatch blocks the release (D-03/D-09). TC-01 cannot be marked complete while the official channel lacks the darwin-x86_64 artifact, any static version channel, and core checksums.

### TC-02 — Full release gate matrix before publishing

**Status: BLOCKED** (fail-closed; 14-03 not executed)

- Authoritative text: release CI must run native/js/linear-wasm parity, `diff_parity --frozen-only`, `check_naming`, corpus `--check` (full nine-command set) before publishing; any failure blocks the release (D-04..D-06).
- D-ID coverage: D-04, D-05, D-06.
- Committed paths / commit IDs: none — the `release-gates` job wiring (14-03) was not executed.
- Executed evidence:
  - Official MoonBit channel, verified 2026-08-14: `binaries/latest/moonbit-darwin-x86_64.tar.gz` and its `.sha256` -> HTTP 403 (no Intel-macOS artifact; official unix installer maps only darwin-aarch64/linux-x86_64/linux-aarch64); `cores/core-latest.tar.gz.sha256` and `cores/core-latest.zip.sha256` -> 403 (S3 AccessDenied); versioned paths `binaries/0.1.20240520%2Bb1f30d5e1|0.1.20260807|0.1.20260807%2B4da23f8/moonbit-*` and `cores/core-<key>.*.sha256` -> all 403 (no static channel key); S3 bucket listing denied; `moonbitlang/moon` and `moonbitlang/core` GitHub Releases = 0 releases; official setup actions accept only `latest`/`nightly`. Available official sidecars: linux-x86_64=36f5e7cf..., darwin-aarch64=b4781a1e..., windows-x86_64=c659625f.... Per D-01/D-03 fail-closed, freeze is blocked; 14-01..14-03 not executed.
  - The gate command set exists and was partially exercised offline during discussion (110 Flink corpus rows verified, 104 archive SHA-512 values reverified, `CORPUS-REPORT.md` current, 655 product files passed naming scan) — this is discussion evidence, **not** a release-gates run and does not satisfy TC-02.
- Failure contract: `release` must explicitly `needs` `build` + `release-gates` with no `always()`/bypass input (D-04/D-06); the nine commands must run with real fail-closed semantics (`--frozen-only`, `--check`, no `--update`, no `continue-on-error`, no empty-result tolerance) and gate publication (D-05). TC-02 cannot be marked complete without an actual successful `release-gates` job run in CI.

## Decision Coverage Mapping (D-01..D-14)

| Decision | Requirement | Status | Evidence |
|----------|-------------|--------|----------|
| D-01 | TC-01 | BLOCKED | no static official channel / no darwin-x86_64 artifact (probes above) |
| D-02 | TC-01 | BLOCKED | unified installer entry cannot be pinned without D-01 |
| D-03 | TC-01 | BLOCKED | no official core sidecars; checksum verification impossible |
| D-04 | TC-02 | BLOCKED | `release-gates` job not wired (14-03 not executed) |
| D-05 | TC-02 | BLOCKED | nine-command gate run not executed |
| D-06 | TC-02 | BLOCKED | tag/dispatch gate parity not implemented |
| D-07 | TC-01 | BLOCKED | per-platform `moon-toolchain.json` not creatable without a pin |
| D-08 | TC-01 | BLOCKED | aggregate manifest not creatable without per-platform records |
| D-09 | TC-01 | BLOCKED | missing/inconsistent record failure semantics not exercised |
| D-10 | HYG-02 | COMPLETE | `.gitignore` `pkg.generated.mbti` rule — `ff966c1`; `check-ignore -v` provenance |
| D-11 | HYG-03 | COMPLETE | `.planning/research/.cache/` deleted+ignored (`ff966c1`); duplicate quick `PLAN.md` deleted with digest-preserved summaries (14-05 Task 1) |
| D-12 | HYG-03 | COMPLETE | five-file `v1.0-research` archive committed exactly — `e63eec5`; all references resolve |
| D-13 | HYG-03 | COMPLETE | runtime `.omp-*` state allowlisted via snapshot; fail-closed porcelain classifier |
| D-14 | HYG-01 | COMPLETE | action-only JetBrains delta — `8cc3f9d` (byte-transform proof) |

## Final Status Evidence

- Pre-matrix-commit classification (`python3 scripts/classify_release_status.py classify --mode pre-matrix-commit --snapshot "$TMP_DIR/phase14-runtime-status.json" --porcelain-command 'git status --porcelain=v1 -z --untracked-files=all'`): **PASS** — allowlisted the two runtime paths (` M`) and the two task transients present at that time (`scripts/classify_release_status.py`, `scripts/tests/test_classify_release_status.py`). This matrix was created after that classification, so it was permitted-by-mode but absent from the observed allowlist.
- Post-matrix-commit classification (same snapshot path, same `porcelain=v1 -z` command): **PASS** — only the two pre-existing runtime paths remain modified; no task transient and no other path present.
- Final porcelain (`git status --porcelain=v1 -z --untracked-files=all` after close-out): only ` M .planning/.omp-next-action.json` and ` M .planning/.omp-task-results.json` (runtime state per D-13).
- Matrix checks supplement but never replace the executed freeze/installer/aggregate/release-gates/status evidence named above.

---
*Phase: 14-release-hygiene-toolchain-pinning*
*Matrix compiled: 2026-08-14*
