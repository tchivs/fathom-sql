---
phase: 14-release-hygiene-toolchain-pinning
plan: 05
subsystem: infra
tags: [hygiene, porcelain, archive, classifier, readiness]

# Dependency graph
requires:
  - phase: 14-04
    provides: JetBrains action-only delta (8cc3f9d), .gitignore generated-interface/cache rules (ff966c1)
provides:
  - local quick-duplicate deletion evidence with digest-preserved canonical summaries
  - exact five-file .planning/milestones/v1.0-research/ archive commit
  - NUL-safe porcelain-v1/-z status classifier + unit tests + sole readiness matrix
affects: release hygiene audit, v4.0 release readiness, ship gate

# Actuals (#2632) — pairs with the plan's `estimate` (48000 tokens, low confidence).
# estimateTokens scale = chars/4 over the files actually changed (full bytes for
# created files, delta bytes for modified files) — never a harness token count.
actuals:
  tokens: 60548
  tasks: 3
  commits: 7

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Path-explicit hygiene commits: stage/commit only owned paths; never git add -A / clean / reset / stash (D-11..D-13)"
    - "Fail-closed status gating: porcelain-v1 -z NUL records parsed without quoting; snapshot-then-classify allowlist; deterministic JSON success output"
    - "Audit artifact accuracy: matrix records only observed allowlists; corrections land as their own commit"

key-files:
  created:
    - scripts/classify_release_status.py
    - scripts/tests/test_classify_release_status.py
    - .planning/phases/14-release-hygiene-toolchain-pinning/14-RELEASE-READINESS.md
    - .planning/phases/14-release-hygiene-toolchain-pinning/14-05-SUMMARY.md
  modified:
    - .planning/STATE.md
    - .planning/ROADMAP.md

key-decisions:
  - "Executed per the user-approved 2026-08-14 split: HYG-01/02/03 track completes now; TC-01/TC-02 are fail-closed BLOCKED because the official MoonBit channel lacks darwin-x86_64 artifacts, any static version channel, and core checksums (all HTTP 403 verified 2026-08-14). TC success is not fabricated."
  - "Plan Task-1 verify one-liner had an inverted digest parse (dict(hash,path) vs path->hash lookups); verified with the correct path->hash semantics and recorded as a deviation."
  - "Readiness matrix correction (commit 4bb92fd): pre-matrix observation fixed to state the matrix was permitted-by-mode but absent at pre-commit classification time."

requirements-completed: [HYG-01, HYG-02, HYG-03]
# NOTE: TC-01/TC-02 intentionally NOT marked complete — BLOCKED per D-01/D-03
# fail-closed (official MoonBit channel evidence embedded in the matrix).

coverage:
  - id: D1
    description: "Two untracked duplicate quick PLAN.md files deleted with byte-identical pre/post SHA-256 digests for the canonical SUMMARY.md files (quick summaries remain tracked and equal to HEAD)"
    requirement: HYG-03
    verification:
      - kind: other
        ref: "python3 '<sha256 writer>' $TMP_DIR/quick-summary-pre.sha256 <both SUMMARY paths>; deletion of only the two PLAN.md paths; post-deletion hash equality + git diff --quiet HEAD rc=0; digests c7f5930b... / 813639ae..."
        status: pass
    human_judgment: false
  - id: D2
    description: "Exact five-file .planning/milestones/v1.0-research/ archive committed (e63eec5) with all 50 tracked references resolving within the set"
    requirement: HYG-03
    verification:
      - kind: other
        ref: "git diff-tree --no-commit-id --name-only -r HEAD == exactly 5 paths; git ls-files --error-unmatch each member; nonempty blobs 40014/32898/46785/31033/31325 bytes; reference regex over all tracked .planning files"
        status: pass
    human_judgment: false
  - id: D3
    description: "scripts/classify_release_status.py NUL-safe porcelain-v1/-z parser (rename two-path records) with snapshot/pre-matrix/post-matrix fail-closed modes"
    requirement: HYG-03
    verification:
      - kind: unit
        ref: "python3 -m unittest scripts.tests.test_classify_release_status -v — 23 tests OK (clean, each allowed runtime path, matrix transient only in pre-mode, forbidden product edit, generated/cache/duplicate untracked, unknown .omp-*, rename, spaces/newlines, status-class drift, post-commit matrix drift)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Sole 14-RELEASE-READINESS.md matrix with HYG-01/02/03 COMPLETE rows, TC-01/02 BLOCKED rows (verbatim official-channel evidence), D-01..D-14 coverage mapping, and explicit statement that prose is not the status check"
    requirement: HYG-01
    verification:
      - kind: other
        ref: "python3 scripts/classify_release_status.py classify --mode post-matrix-commit --snapshot $TMP_DIR/phase14-runtime-status.json --porcelain-command 'git status --porcelain=v1 -z --untracked-files=all' → PASS; matrix literal assert (HYG-01..03, TC-01/02, D-01..D-14, 'porcelain=v1 -z') OK"
        status: pass
    human_judgment: false
  - id: D5
    description: "TC-01 (pinned toolchain + artifact evidence) recorded as BLOCKED with official-channel evidence; not executed because D-01/D-03 fail-closed"
    requirement: TC-01
    verification: []
    human_judgment: true
    rationale: "Blocked by external official-channel facts (403 probes, zero GitHub Releases, installer target map). No freeze/installer/aggregation work was executed; the requirement can only be re-verified by a human once the official MoonBit channel provides the missing artifacts."
  - id: D6
    description: "TC-02 (nine release gates block publish) recorded as BLOCKED with official-channel evidence; 14-03 not executed"
    requirement: TC-02
    verification: []
    human_judgment: true
    rationale: "Blocked as a downstream of TC-01; the release-gates job was never wired or run. Requires a human to unblock the toolchain channel and execute the real gate run."

# Metrics
duration: 55min
completed: 2026-08-14
status: complete
---

# Phase 14 Plan 05: Quick/Archive Preservation and Final Porcelain Readiness Classifier Summary

**Quick duplicate PLAN deletion with digest-preserved summaries, exact five-file v1.0-research archive commit, NUL-safe porcelain-v1/-z release status classifier, and the sole HYG/TC readiness matrix (TC-01/02 fail-closed BLOCKED)**

## Performance

- **Duration:** 55 min
- **Started:** 2026-08-14T07:38:53Z
- **Completed:** 2026-08-14T08:36:00Z
- **Tasks:** 3
- **Files modified:** 11 (2 quick deletions + 5 archive + 3 Task-3 files + SUMMARY/STATE/ROADMAP)

## Accomplishments

- Deleted the two untracked duplicate quick `PLAN.md` files as local hygiene evidence (no Git deletion commit — inputs were untracked); the canonical `SUMMARY.md` files are byte-identical pre/post with exact SHA-256 digests and remain tracked and equal to `HEAD`.
- Committed the exact five-file `.planning/milestones/v1.0-research/` archive (`e63eec5`); `git diff-tree` shows exactly those five paths, every member is tracked and nonempty, and all 50 tracked references containing `v1.0-research/` resolve within the set.
- Implemented `scripts/classify_release_status.py` — NUL-safe `porcelain=v1 -z` parser including rename two-path records; `snapshot` records only the currently-present pre-existing `.planning/.omp-*` runtime statuses; `classify --mode pre-matrix-commit` allows runtime paths + task transients, `post-matrix-commit` allows runtime paths only; deterministic JSON on success, diagnostics on failure. 23 unit tests pass.
- Created the sole `14-RELEASE-READINESS.md`: HYG-01/02/03 COMPLETE (commits `8cc3f9d`/`ff966c1`/`e63eec5` + classifier evidence), TC-01/TC-02 BLOCKED with verbatim official-channel evidence, D-01..D-14 coverage mapping, and the explicit statement that matrix prose is not the status check.
- Pre- and post-matrix-commit classifications PASS against the same snapshot with real porcelain; final tree shows only the two allowlisted `.omp-*` runtime files modified (D-13).

## Task Commits

1. **Task 1: Delete only duplicate quick plans with digest-preserved summaries** — no commit (untracked inputs; local hygiene evidence only, per D-11)
2. **Task 2: Commit and reference-check the exact five-file research archive** - `e63eec5` (docs)
3. **Task 3: Execute the final porcelain classifier and commit the sole readiness matrix** - `899ae20` (feat: classifier + tests + matrix)
4. **Task 3 correction: matrix observation accuracy fix** - `4bb92fd` (docs)

**Plan metadata:** close-out commit `cf359c6` (docs: complete 14-05 plan) — see final commit list below.

## Files Created/Modified

- `scripts/classify_release_status.py` - NUL-safe porcelain-v1/-z parser (rename two-path records), snapshot/pre-matrix/post-matrix fail-closed classification, deterministic JSON
- `scripts/tests/test_classify_release_status.py` - 23 temp-repo/subprocess tests covering the plan's case list
- `.planning/phases/14-release-hygiene-toolchain-pinning/14-RELEASE-READINESS.md` - sole five-requirement matrix + D-01..D-14 mapping
- `.planning/milestones/v1.0-research/{ARCHITECTURE,FEATURES,PITFALLS,STACK,SUMMARY}.md` - committed as canonical archive (e63eec5)
- `.planning/STATE.md`, `.planning/ROADMAP.md` - phase state/progress updates

## Evidence

### Quick summary digests (Task 1; pre == post, byte-identical to HEAD)

```
c7f5930bbda7297aeb50a2832feac3f395959c868bd6e572f15162021cb070c8  .planning/quick/260805-df9-add-a-kotlin-gradle-jetbrains-intellij-p/SUMMARY.md
813639ae7488fec9a0af3dbb0e08cbae77b88fbd8564fc5abb2bc993207d3926  .planning/quick/260805-e28-align-the-jetbrains-plugin-wrapper-and-d/SUMMARY.md
```

Deletion was `/bin/rm` on exactly the two untracked duplicate `PLAN.md` paths (the shell aliases `rm` to `rm -i`); `git diff --quiet HEAD -- <SUMMARY>` rc=0 for both; `git ls-files .planning/quick/` still lists both summaries.

### Archive commit (Task 2)

- Commit `e63eec5` — `git diff-tree --no-commit-id --name-only -r HEAD` == exactly the five paths; `git ls-files --error-unmatch` accepts each; blobs nonempty (40,014 / 32,898 / 46,785 / 31,033 / 31,325 bytes); 50 references (SUMMARY.md×14, STACK.md×16, ARCHITECTURE.md×8, PITFALLS.md×7, FEATURES.md×5) resolve within the set.

### Classifier runs (Task 3; same snapshot path for both)

- Snapshot JSON (`snapshot --output $TMP_DIR/phase14-runtime-status.json`):
  `{"command":"snapshot","runtimePaths":[{"path":".planning/.omp-next-action.json","status":" M"},{"path":".planning/.omp-task-results.json","status":" M"}],"schemaVersion":1}`
- Pre-matrix-commit classification (`--porcelain-command 'git status --porcelain=v1 -z --untracked-files=all'`): **PASS** — allowlisted the two runtime paths and the two task transients present then (classifier, test); matrix was created after this run.
- Post-matrix-commit classification (same snapshot): **PASS** — allowlisted only the two runtime paths; no task transient, no other path.
- Unit tests: `python3 -m unittest scripts.tests.test_classify_release_status -v` — Ran 23 tests, OK.
- Post-close-out porcelain: only ` M .planning/.omp-next-action.json` and ` M .planning/.omp-task-results.json`.

### TC-01/TC-02 blocked evidence (verbatim, embedded in the matrix TC rows)

Official MoonBit channel, verified 2026-08-14: `binaries/latest/moonbit-darwin-x86_64.tar.gz` and its `.sha256` -> HTTP 403 (no Intel-macOS artifact; official unix installer maps only darwin-aarch64/linux-x86_64/linux-aarch64); `cores/core-latest.tar.gz.sha256` and `cores/core-latest.zip.sha256` -> 403 (S3 AccessDenied); versioned paths `binaries/0.1.20240520%2Bb1f30d5e1|0.1.20260807|0.1.20260807%2B4da23f8/moonbit-*` and `cores/core-<key>.*.sha256` -> all 403 (no static channel key); S3 bucket listing denied; `moonbitlang/moon` and `moonbitlang/core` GitHub Releases = 0 releases; official setup actions accept only `latest`/`nightly`. Available official sidecars: linux-x86_64=36f5e7cf..., darwin-aarch64=b4781a1e..., windows-x86_64=c659625f.... Per D-01/D-03 fail-closed, freeze is blocked; 14-01..14-03 not executed.

## Decisions Made

- Followed the user-approved 2026-08-14 orchestration split: HYG track executes now; TC-01/TC-02 remain fail-closed BLOCKED and are recorded, not fabricated.
- `requirements.mark-complete` was NOT run: TC-01/TC-02 must stay unchecked (blocked), and the orchestrator scoped the close-out commit to SUMMARY+STATE+ROADMAP only. HYG-01/02/03 traceability is carried by this SUMMARY's coverage block and ROADMAP progress.
- `scripts/tests/__init__.py` was not needed: Python 3.9 namespace packages make `python3 -m unittest scripts.tests.test_classify_release_status` resolve without it (verified by the passing run), so no deviation file was created.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Task-1 verify one-liner had an inverted digest parse**
- **Found during:** Task 1 (digest verification)
- **Issue:** The plan's verify snippet built `dict(line.split("  ", 1))` — mapping SHA-256 hash -> path — then asserted `sorted(recorded)==sorted(paths)` (hash keys vs path names, always false) and looked up `recorded[path]` (KeyError). The digest file format itself (`<64 hex>  <path>`, sorted by pathname) was correct.
- **Fix:** Verified with the correct path->hash parse (`dict((p,h) for h,p in (line.split("  ",1) ...))`); all checks pass: sorted pathname equality, 64-hex lengths, live hash equality, `git diff --quiet HEAD` rc=0, duplicates absent.
- **Files modified:** none (verification command only)
- **Verification:** Task 1 check chain PASS (digests above)
- **Committed in:** n/a (local evidence)

**2. [Rule 1 - Bug] Readiness matrix recorded an unobserved allowlist entry**
- **Found during:** Task 3 (post-commit review of matrix)
- **Issue:** The matrix's pre-matrix row claimed `this matrix` was allowlisted at pre-commit classification, but the matrix was created after that classification (permitted-by-mode, absent from the observed allowlist).
- **Fix:** Corrected the row wording; re-ran the post-matrix-commit classification with the same snapshot — PASS.
- **Files modified:** `.planning/phases/14-release-hygiene-toolchain-pinning/14-RELEASE-READINESS.md`
- **Verification:** post-classify PASS after the correction commit
- **Committed in:** `4bb92fd`

---

**Total deviations:** 2 auto-fixed (Rule 1: 2)
**Impact on plan:** Both are accuracy fixes to verification/audit artifacts; no scope creep, no behavioral change to the shipped classifier.

## Issues Encountered

- The shell aliases `rm` to `rm -i`, which prompted interactively and refused deletion on EOF; used `/bin/rm` for the exact two owned paths.
- Test scaffolding: empty temp repos had nothing to commit; `make_repo` now seeds a base commit and `commit_all` tolerates no-op commits.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Working tree audited by the executable classifier: only the two pre-existing `.planning/.omp-*` runtime files remain modified; no product/planning/generated/cache/duplicate drift.
- Phase 14 HYG-01/02/03 complete; TC-01/TC-02 remain blocked on the official MoonBit channel (darwin-x86_64 artifact, static version channel, core checksums) — the readiness matrix and this SUMMARY carry the full evidence for the ship gate.
- Phase 15 (versioning) can proceed; TC unblocking requires the official channel to publish the missing artifacts, then 14-01..14-03 execution.

## Self-Check

- `scripts/classify_release_status.py`, `scripts/tests/test_classify_release_status.py`, `14-RELEASE-READINESS.md`, `14-05-SUMMARY.md` exist.
- Commits `e63eec5`, `899ae20`, `4bb92fd`, `cf359c6` exist in history (verified via git log).
- `python3 -m unittest scripts.tests.test_classify_release_status -v` — 23 tests OK; post-matrix classification PASS with the same snapshot; post-close-out porcelain shows only the two `.omp-*` runtime files.

## Self-Check: PASSED

## Revision (2026-08-17): TC-01/02 COMPLETE

- User-approved D-01/D-03 three-platform revision (14-CONTEXT.md) unblocked the TC track.
- 14-01 freeze (commit `eb77525`): 3-platform content lock, run 31993236748, 3 attestations verified.
- 14-02 installers (commit `2948bc1`): shared lock-driven helpers + ci.yml migration + windows-2025 proof (run 31994107232).
- 14-03 release gates (commits `cf286ba`/`2e8faa61`/`dcc8942`): dry-run run 31995140506 — 5/5 jobs, 9/9 gate steps success, aggregate validated, publication absent.
- `14-RELEASE-READINESS.md` updated: TC-01/TC-02 and D-01..D-09 now COMPLETE with executed evidence; this revision supersedes the BLOCKED rows.

---
*Phase: 14-release-hygiene-toolchain-pinning*
*Completed: 2026-08-17*
