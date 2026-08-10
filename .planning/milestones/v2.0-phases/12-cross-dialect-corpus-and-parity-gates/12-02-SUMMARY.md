---
phase: 12-cross-dialect-corpus-and-parity-gates
plan: 02
subsystem: corpus-parity-gates
tags: [doris, frozen-baseline, diff-harness, parity, approved-changes, python-stdlib, PARITY-01]

# Dependency graph
requires:
  - phase: 09-dialect-boundary-and-neutral-naming
    provides: Doris baseline freeze (213 snapshots) + approved-changes register + baseline_diff engine (D-07/D-08)
  - phase: 11-flink-grammar-and-recoverable-cst
    provides: flink-grammar/flink-lexical snapshot groups + zero-drift discipline precedent
  - phase: 12-cross-dialect-corpus-and-parity-gates (12-01)
    provides: unified Flink corpus manifest (data-only under parity/fixtures/flink/, snapshot surface untouched)
provides:
  - scripts/diff_parity.py — frozen-vs-current regeneration diff harness (stdlib): --frozen-only CI mode (temp moon test --update regeneration + byte/path dual-channel compare + FAIL exit 1 on ANY difference, register NOT consulted), --approve <register> local mode (readable report, approved/unexpected classification, exit 1 when unexpected > 0), directory-missing exit 2, restore-on-failure guarantee (SIGTERM/SIGINT safe, T-12-02-04)
  - scripts/baseline_diff.py — minimal --frozen/--current aliases for --left/--right (engine reused unchanged)
  - .planning/phases/12-cross-dialect-corpus-and-parity-gates/approved-changes.md — Phase 12 D-08 register: single-use approval rule + Doris 213 zero-drift HARD gate + pre-declared snapshot-surface expectations + machine-readable row skeleton
affects:
  - 12-03 (CI wiring of diff_parity.py --frozen-only into parity-gate; verify_corpus.py --check; js runtime parity)
  - 13-toolchain-and-editor-packaging (release parity contract)

# Actuals (#2632) — pairs with the plan's `estimate` (30000 tokens) to calibrate future estimates.
# Same estimateTokens scale (chars/4 over the realized diff), never a harness token count.
actuals:
  tokens: 4709
  tasks: 3
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "regenerated-comparison proof (D-03): frozen = copy of the committed tree; current = temp `moon test --update --package parity` via move/restore lifecycle with zero working-tree residue — replaces the vacuous left==right self-check as the frozenness proof"
    - "wrapper over the proven engine: diff_parity.py imports scripts/baseline_diff.py (parse_approve / diff_file / format_path / exit-0/1/2 contract) unchanged; only the temp regeneration lifecycle and the two mode entry points are new"
    - "restore-on-failure lifecycle: snapshot moved aside -> regenerate -> move back; any failure or interruption (SIGTERM/SIGINT) returns parity/__snapshot__ to the committed bytes before exiting 2"

key-files:
  created:
    - scripts/diff_parity.py
    - .planning/phases/12-cross-dialect-corpus-and-parity-gates/approved-changes.md
  modified:
    - scripts/baseline_diff.py

key-decisions:
  - "Task 1 (D-03 one-way door, auto-selected option-a): wrapper diff_parity.py reusing the baseline_diff approved-vs-unexpected engine, per the RESEARCH recommendation — --frozen-only upgrades the CI proof from self-comparison to regeneration, --approve gives maintainers a readable local report, zero behavior change to the classification engine."
  - "--frozen-only compares the FULL regenerated tree vs the committed tree (all 433 snapshots including flink groups) and FAILS on ANY difference; the register is never consulted so an empty/forged register cannot mask drift (non-vacuous proof, T-12-02-02/05)."
  - "Lifecycle robustness: shutil.move (not os.rename) so the temp dir can live on a different filesystem from the repo; a no-snapshot guard after `moon test --update` catches moon's warn-only behavior for a nonexistent package (it exits 0 with 0 tests)."
  - "Phase 12 register pre-declares NO active snapshot rows: 12-01 migration is data-only, 12-02 harness and 12-03 CI wiring change zero snapshot bytes; the machine-readable skeleton is #-commented so it documents the format without classifying anything as approved."

requirements-completed: [PARITY-01]

coverage:
  - id: D1
    description: "scripts/diff_parity.py --frozen-only regenerates the current snapshot tree from the committed baseline via a temp `moon test --update --package parity` (move/restore lifecycle, zero working-tree residue) and FAILS (exit 1) on ANY difference, consulting NO register — the frozen Doris baseline is proven by regeneration, not by a vacuous left==right self-comparison (PARITY-01, D-03)."
    requirement: PARITY-01
    verification:
      - kind: integration
        ref: "python3 scripts/diff_parity.py --frozen-only on the clean tree -> ok: 433 snapshots, 0 frozen-vs-current differences, exit 0; git status --short parity/__snapshot__ empty after the run"
        status: pass
      - kind: integration
        ref: "injected real drift (schema_version leaf) into a committed doris snapshot -> --frozen-only exit 1 with 'error: 2.1-boundary-single.2.1.strict.json: snapshot differs (frozen vs current)'; working tree restored afterwards, moon test --package parity 570/570"
        status: pass
  - id: D2
    description: "Doris 2.1/3.x/4.x snapshot behavior stays equal to the frozen baseline after the harness work: moon test --package parity (no --update) passes and git diff --name-only -- parity/__snapshot__ shows no doris-named snapshot changed (PARITY-01, D-04)."
    requirement: PARITY-01
    verification:
      - kind: integration
        ref: "moon test --package parity -> 570/570 after every harness run; git diff --name-only -- parity/__snapshot__ empty; git status --short parity/__snapshot__ empty"
        status: pass
    human_judgment: false
  - id: D3
    description: "Register-based approval flow: a deliberate snapshot change registered via a key:/prefix:/field: row makes --approve <register> exit 0 with the diff listed approved, while the same unregistered change makes --approve exit 1 with the diff listed unexpected (single-use approval path, D-07, Pitfall 1)."
    requirement: PARITY-01
    verification:
      - kind: integration
        ref: "throwaway register + --left/--right trees: key:/prefix:/field: rows each classify approved (exit 0); empty register classifies the same drift unexpected (exit 1, diff at schema_version / new_field)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Restore guarantee: killing the harness mid-regeneration or a failed move leaves parity/__snapshot__ identical to the committed tree (restore-on-failure, T-12-02-04, Research §6.2/A9)."
    requirement: PARITY-01
    verification:
      - kind: integration
        ref: "failed regeneration (nonexistent package, moon warns-and-exits-0 with no snapshot) -> exit 2 + committed tree restored; SIGTERM mid-regeneration with a fake slow moon -> exit 2, 'restored committed snapshot tree after interruption', git status empty, moon test 570/570"
        status: pass
    human_judgment: false
  - id: D5
    description: "docs-vs-parser and release-fact-vs-docs conflicts surface explicitly as unexpected rows routed to the human-adjudication register (approved-changes.md), never silently resolved by bulk snapshot updates (D-07). The Phase 12 register pre-declares no snapshot-surface changes and documents the conflict adjudication entry point."
    requirement: PARITY-01
    verification:
      - kind: integration
        ref: "diff_parity.py --approve <12 register> on the clean tree -> ok: 433 snapshots, 0 approved diffs, 0 unexpected, exit 0 (register parses via baseline_diff engine, zero-drift confirmed)"
        status: pass
    human_judgment: false

# Metrics
duration: 4min
completed: 2026-08-09
status: complete
---

# Phase 12 Plan 02: Doris Frozen Diff Harness Summary

**`scripts/diff_parity.py` formalizes the Phase 9 Doris baseline gate as a regenerated frozen-vs-current diff harness: `--frozen-only` (CI) proves the 213-snapshot baseline by regenerating current output in a temp `moon test --update` lifecycle and failing on ANY difference with no register consulted; `--approve <register>` (local) classifies diffs as approved/unexpected via the reused baseline_diff engine — docs-vs-parser conflicts surface as unexpected rows, never silently bulk-updated.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-08-09T12:37:00Z
- **Completed:** 2026-08-09T12:40:49Z
- **Tasks:** 3 (1 auto-selected decision + 2 executed)
- **Files modified:** 3 (2 created, 1 modified)

## Accomplishments
- **`scripts/diff_parity.py`** (362 lines, Python stdlib) — the D-03 frozen-vs-current harness:
  - `--frozen-only` CI mode: copies the committed `parity/__snapshot__` tree to a temp `frozen` dir, moves the working tree aside, runs `moon test --update --package parity` so the regenerated tree lands at the canonical path, moves the regenerated tree to a temp `current` dir, restores the committed tree (zero working-tree residue), then byte + path dual-channel compares — exit 1 on ANY difference, register NOT consulted (an empty/forged register cannot mask drift).
  - `--approve <register>` local mode: same regeneration, then classifies each diff as approved (key:/prefix:/field: rows) vs unexpected via the unchanged `scripts/baseline_diff.py` engine; readable per-path report; exit 1 when unexpected > 0.
  - Exit contract: 0 clean / 1 differences or unexpected / 2 directory-missing or lifecycle failure. Restore-on-failure path returns the committed tree on any failure or SIGTERM/SIGINT interruption (T-12-02-04).
  - Optional `--left/--right` bypass the lifecycle for tests and manual tree-to-tree inspection.
- **`scripts/baseline_diff.py`** — minimal `--frozen`/`--current` aliases for `--left`/`--right`; the existing engine (`parse_approve`/`classify`/`diff_file`/exit gate) and the existing CI `--left/--right` invocation are reused unchanged.
- **Phase 12 `approved-changes.md` register** — D-08 whitelist: single-use approval rule (`--update` NEVER without a committed entry), Doris 213 zero-drift HARD gate, NEVER `--update` in CI (Pitfall 1), pre-declared Phase 12 snapshot-surface expectations (12-01 migration data-only / 12-02 harness / 12-03 CI wiring change zero snapshot bytes), the D-07 conflict-adjudication entry point, and the machine-readable row skeleton with no active rows.

## Task Commits

Each task was committed atomically:

1. **Task 1: Confirm the frozen-vs-current diff harness contract (D-03 one-way door)** — auto-selected option-a (wrapper `diff_parity.py` reusing the `baseline_diff` engine) under `_auto_chain_active=true` / `mode=yolo` (no commit — decision only).
2. **Task 2: Implement scripts/diff_parity.py — frozen-vs-current regeneration harness** — `5829f88` (feat(12-02): frozen-vs-current diff harness (diff_parity.py))
3. **Task 3: Phase 12 approved-changes register + local frozen-vs-current validation** — `cdb9867` (docs(12-02): Phase 12 D-08 approved-changes register)

## Files Created/Modified
- `scripts/diff_parity.py` - Frozen-vs-current regeneration diff harness (`--frozen-only` / `--approve` / `--left`/`--right`; exit 0/1/2; restore-on-failure)
- `scripts/baseline_diff.py` - `--frozen`/`--current` aliases for `--left`/`--right` (minimal extension; engine unchanged)
- `.planning/phases/12-cross-dialect-corpus-and-parity-gates/approved-changes.md` - Phase 12 D-08 register (rule text + pre-declared expectations + row skeleton)

## Decisions Made
- **Task 1 (auto-selected option-a):** wrapper `diff_parity.py` reusing the `baseline_diff` engine, per the RESEARCH recommendation — reuses the proven approved-vs-unexpected classification, upgrades the CI proof from self-comparison to regeneration, keeps a single engine to maintain.
- **Full-tree `--frozen-only`:** compares all 433 regenerated snapshots (Doris 213 + flink groups) against the committed tree and fails on ANY difference — strictly stronger than a Doris-only filter and consistent with "FAILS on ANY difference" (D-03).
- **Lifecycle robustness:** `shutil.move` instead of `os.rename` for cross-device temp dirs; a post-`--update` `parity/__snapshot__` existence guard catches moon's warn-only exit-0 for a nonexistent package (exit 2 + restore).
- **Phase 12 register:** no active approval rows by design — the phase pre-declares zero snapshot-surface changes; the machine-readable skeleton is `#`-commented so it documents the format without approving anything.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Cross-device `os.rename` failure when the temp dir lives on a different filesystem**
- **Found during:** Task 2 (first `--frozen-only` run)
- **Issue:** `pathlib.Path.rename` uses `os.rename`, which raises `OSError: [Errno 18] Invalid cross-device link` when moving `parity/__snapshot__` to `/tmp/diff-parity-*/` (repo and `/tmp` are different mounts).
- **Fix:** replaced every lifecycle `rename` (move-aside, move-regenerated, restore) with `shutil.move`, which copies across devices and deletes the source; the restore path also uses `shutil.move`.
- **Files modified:** `scripts/diff_parity.py`
- **Commit:** `5829f88` (Task 2 commit)

**2. [Rule 1 - Bug] `moon test --update` exits 0 with zero tests for a nonexistent package (warn-only)**
- **Found during:** Task 2 (restore-guarantee test of the failure path)
- **Issue:** `moon test --update --package definitely-not-a-package` prints a warning and `Total tests: 0` with exit 0 — the `returncode != 0` failure branch would never fire, so the harness needed a second guard.
- **Fix:** added a `snap.is_dir()` check after the regeneration: if `moon` produced no `parity/__snapshot__`, restore the committed tree and exit 2 with an explicit error.
- **Files modified:** `scripts/diff_parity.py`
- **Commit:** `5829f88` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 bugs in the harness lifecycle)
**Impact on plan:** Both fixes were necessary for the harness to run in this environment (cross-device temp) and to fail closed when regeneration produces no tree. No scope creep.

## Issues Encountered
- **`cp` interactive overwrite alias:** during the non-vacuity drift test, `cp /tmp/drift-backup.json <snapshot>` prompted an interactive `overwrite?` (cp alias) and did not restore the file, leaving moon test 569/570. Resolved with a targeted `git checkout -- <file>` to restore the committed snapshot; tree green afterwards.
- **Pretty-printed JSON broke JSON-lines parse:** an early classification test rewrote a single-line snapshot with `json.dump(indent=2)`, making `collect_pairs` treat the file as non-JSON (byte-difference path). Re-done with a byte-level replace preserving the single-line formatting.

## Threat Surface Scan

No new network endpoints, auth paths, file-access patterns, or trust-boundary schema changes were introduced beyond the plan's `<threat_model>`. The harness reads/writes only `parity/__snapshot__` (restored after every run) and temp dirs, invokes the existing `moon` CLI, and reads the register — all documented in the threat model (T-12-02-01..05; SC: zero new runtime dependencies, Python stdlib).

## Known Stubs

None — the plan delivered no placeholders; `--frozen-only` / `--approve` are fully functional and the register is complete.

## Next Phase Readiness
- **12-03 (cross-backend parity + offline CI gates)** can wire `python3 scripts/diff_parity.py --frozen-only` into the `parity-gate` job (the D-03 one-way contract), `verify_corpus.py --check`, and the js runtime parity matrix; `compare_backends.py` remains the 12-03 deliverable.
- **Deferred/known gaps:** `extract_flink_*` need `/tmp/flink-research/` (local maintainer tools only, per 12-01 D-06 option-a); the Doris 213-snapshot zero-drift gate now has a provable regeneration proof ready for CI.

---
*Phase: 12-cross-dialect-corpus-and-parity-gates*
*Completed: 2026-08-09*

## Self-Check: PASSED

All 4 created files exist (diff_parity.py, baseline_diff.py, approved-changes.md, 12-02-SUMMARY.md) and both task commits (5829f88, cdb9867) are present in git history.
