---
phase: 02-doris-completeness-and-corpus
plan: 06
subsystem: corpus
tags: [sqlglot, differential, fe-nereids, python, bash, corpus, advisory-only]

requires:
  - phase: 02-04
    provides: extended corpus/manifest.tsv (44 DML/DDL + SELECT fixture rows), coverage.tsv, CORPUS-REPORT.md, generate_corpus_report.py --check
provides:
  - corpus/tools/sqlglot_diff.py - local, pinned SQLGlot differential runner (read='doris', error_level=RAISE) over every manifest fixture
  - corpus/requirements.txt - sqlglot==30.14.0 dev-tooling pin
  - corpus/differential.tsv - one advisory row per manifest fixture (sqlglot_version, sqlglot_observation, version-specific resolution, advisory_only=true)
  - corpus/tools/fe_nereids_diff.sh - documented manual-only FE/Nereids differential script (never CI, D-20)
  - corpus/tools/README.md - run instructions, pins, fallbacks, released-docs-authority policy
affects: [verification, future corpus/gap analysis, ship review (differential evidence), any plan re-running differential]

actuals:
  tokens: 8847    # chars/4 over the realized diff (35,389 diff bytes), plan estimate 14000
  tasks: 2
  commits: 2

tech-stack:
  added:
    - "sqlglot==30.14.0 (pip, dev/differential tooling only; pinned per RESEARCH.md PyPI audit; never a parser-core or runtime dependency)"
  patterns:
    - "Advisory differential harness: every observation row carries public_contract=released-docs + advisory_only=true; disagreements recorded with version-specific resolutions; coverage report never consumes differential rows (D-07/D-20)"

key-files:
  created:
    - corpus/tools/sqlglot_diff.py
    - corpus/requirements.txt
    - corpus/tools/fe_nereids_diff.sh
    - corpus/tools/README.md
  modified:
    - corpus/differential.tsv (rewritten: 44 per-fixture rows, superseding the 7 Phase 1 rows)

key-decisions:
  - "differential.tsv is regenerated deterministically by sqlglot_diff.py: one row per manifest fixture in manifest order; existing fe_nereids_observation values are preserved by fixture_id so manual FE runs are never clobbered"
  - "sqlglot acceptance uses error_level=ErrorLevel.RAISE: any ParseError is a rejection; a Command-fallback acceptance is still 'accepted' but the fallback is recorded in the resolution so parse quality stays honest"
  - "manifest rows without a corpus SQL file (boundary/recovery/encoding negatives, 2.1/3.x-merge, unsupported-profile) are recorded not-run-offline with an explicit reason; observations are never fabricated (A8/T-02-54)"
  - "FE script records fe_nereids_observation by merge (update-by-fixture_id, append only for unknown ids) instead of blind row appends, preventing duplicate rows while preserving the advisory-only contract"
  - "FE script is parser-only (NereidsParser.parseSQL), never connects to a cluster (T-02-53), and documents FE_VERSION pin + Java build prerequisite per D-20"

patterns-established:
  - "Differential harness (research Pattern 6): sqlglot local/pinned with per-run version recording; FE manual-only; advisory rows never widen acceptance"
  - "Fixture path resolution shared by both tools: corpus/doris-<profile>/<category>.sql with Phase 1 override industrial-select -> select-industrial.sql"

requirements-completed: [CORP-04]

coverage:
  - id: D1
    description: "Locally runnable SQLGlot differential runner (pinned 30.14.0) that parses every manifest fixture with read='doris' and writes one advisory row per fixture with sqlglot_version, sqlglot_observation, and version-specific resolutions"
    requirement: CORP-04
    verification:
      - kind: integration
        ref: "python3 corpus/tools/sqlglot_diff.py (44 rows: 21 accepted, 11 rejected, 12 not-run-offline; sqlglot 30.14.0)"
        status: pass
      - kind: integration
        ref: "python3 corpus/tools/generate_corpus_report.py --check"
        status: pass
    human_judgment: false
  - id: D2
    description: "Documented manual FE/Nereids differential script (fe_nereids_diff.sh: FE_VERSION pin, Java build prerequisite, NereidsParser.parseSQL acceptance loop, advisory row updates) plus corpus/tools/README.md documenting both paths, pins, fallbacks, and the released-docs-authority policy"
    requirement: CORP-04
    verification:
      - kind: other
        ref: "bash -n corpus/tools/fe_nereids_diff.sh"
        status: pass
      - kind: integration
        ref: "moon test (163/163 passed)"
        status: pass
    human_judgment: true
    rationale: "The FE script itself requires a built Apache Doris FE (Java) that is offline-unavailable (D-20): it was written, syntax-checked, and its merge/append logic unit-probed, but deliberately never executed in this phase. A maintainer with a built FE should run it once to confirm the Java probe against the real NereidsParser."

duration: 35min
completed: 2026-08-04
status: complete
---

# Phase 02 Plan 06: SQLGlot + FE/Nereids Differential Harness Summary

**Locally runnable pinned-SQLGlot differential runner plus a documented manual FE/Nereids script, populating corpus/differential.tsv with 44 advisory-only rows (21 accepted, 11 rejected, 12 not-run-offline) that record version-specific disagreements without ever becoming the public contract**

## Performance

- **Duration:** 35 min
- **Started:** 2026-08-04T06:10:00Z (approx.)
- **Completed:** 2026-08-04
- **Tasks:** 2 (2 committed)
- **Files modified:** 5 (4 created, 1 rewritten)

## Accomplishments

- CORP-04 executable: `corpus/tools/sqlglot_diff.py` parses every disk-backed manifest fixture with `sqlglot.parse(sql, read="doris")` under the pinned 30.14.0 (installed from PyPI this session) and records `accepted`/`rejected`/`not-run-offline` per fixture.
- `corpus/differential.tsv` now carries one row per manifest fixture (44 rows) with `sqlglot_version=30.14.0`, version-specific resolutions, and `advisory_only=true` on every row; `public_contract=released-docs` everywhere (D-07).
- `corpus/tools/fe_nereids_diff.sh` ships as a complete, documented MANUAL script (FE_VERSION pin default 4.1, Java build prerequisite, `NereidsParser.parseSQL` parser-only acceptance loop referencing the official `fe/fe-core/.../nereids/parser` path, merge-by-fixture_id row updates) — never executed in this phase, never CI-wired (D-20).
- `corpus/tools/README.md` documents both differential paths, the sqlglot pin and fallbacks, the FE manual flow, and the released-docs-authority resolution policy.
- Disagreements recorded with versions (e.g. sqlglot rejects the 4.x SELECT fixture's `TABLET (1001)` window/RANGE form and the `INSERT ... PARTITION (...) WITH LABEL` form; accepts CREATE INDEX only via generic Command fallback) — all advisory only.

## Task Commits

Each task was committed atomically:

1. **Task 1: SQLGlot differential runner with pinned version** - `7981418` (feat)
2. **Task 2: FE/Nereids manual script and differential documentation** - `2db2e1c` (feat)

**Plan metadata:** pending (final commit)

## Files Created/Modified

- `corpus/tools/sqlglot_diff.py` - Local SQLGlot differential runner: lazy sqlglot import (A8 fallback), manifest-driven fixture resolution, `read='doris'` parse with `ErrorLevel.RAISE`, deterministic rewrite of differential.tsv with version + resolution per row, preserves existing fe_nereids_observation values.
- `corpus/requirements.txt` - `sqlglot==30.14.0` dev-tooling pin (RESEARCH.md PyPI audit OK).
- `corpus/differential.tsv` - Rewritten: 44 per-fixture rows (21 accepted / 11 rejected / 12 not-run-offline), replacing the stale Phase 1 7-row file (incl. its now-false "SQLGlot differential execution unavailable offline" aggregate row).
- `corpus/tools/fe_nereids_diff.sh` - Manual-only FE/Nereids differential (D-20): FE_VERSION/DORIS_SRC/FE_CLASSPATH/OUTPUT_TSV envs, Java probe generation, parser-only acceptance loop, advisory row merge.
- `corpus/tools/README.md` - Both differential paths, pins, fallbacks, disagreement-resolution policy.

## Decisions Made

- differential.tsv is the sqlglot script's deterministic output (regenerated in full each run); FE observations merge in by fixture_id and survive re-runs.
- `accepted` = parse raised no error and returned complete expressions; sqlglot's generic `Command` fallback (unsupported-syntax warning) still counts as accepted but is flagged in the resolution for honesty.
- Fixtures whose SQL lives only in MoonBit test embedding (boundary/recovery/encoding negatives, 2.1/3.x-merge, unsupported-profile) have no corpus SQL file -> honest `not-run-offline` rows, never fabricated (A8/T-02-54).

## Deviations from Plan

### Auto-fixed Issues

None — no bugs found; both tasks executed as planned.

### Documented Implementation Adjustments

1. **differential.tsv regeneration replaced stale rows** - The 02-06 contract requires one row per manifest fixture; the Phase 1 file had 7 rows including an aggregate `all` row asserting differential was "unavailable offline". The script regenerates the file deterministically (44 rows), superseding the obsolete aggregate row. Plan-owned file (`files_modified`), documented in the commit message.
2. **FE script records observations by merge, not blind append** - The plan's "append rows" wording would duplicate fixture rows on the already-populated file; the script updates `fe_nereids_observation` by fixture_id (appending only unknown ids), preserving the advisory-only contract and TSV integrity. Documented in the script header.
3. **sqlglot logger suppressed** - sqlglot's "unsupported syntax / falling back to Command" warnings are logged to stderr by sqlglot itself; they are suppressed in the script because the fallback fact is already captured per row in the resolution column.

**Total deviations:** 0 auto-fixed; 3 documented adjustments, all within the plan's stated contracts (CORP-04, D-07/D-20, A8).
**Impact on plan:** None — adjustments keep the deliverable honest, deterministic, and advisory-only.

## What Was Actually Run vs Documented

- **Actually run:** `python3 corpus/tools/sqlglot_diff.py` (sqlglot 30.14.0 installed via pip from PyPI this session — PyPI reachable as researched; 44 rows written), `python3 corpus/tools/generate_corpus_report.py --check` (pass), `bash -n corpus/tools/fe_nereids_diff.sh` (pass), `moon test` (163/163 pass), plus a standalone probe of the FE script's awk merge/append logic.
- **Documented, not run:** `corpus/tools/fe_nereids_diff.sh` itself — requires a built Apache Doris FE (Java), offline-unavailable; deliberately never executed in this phase and never CI-wired (D-20). Its row-update logic was unit-probed in isolation; the Java acceptance loop is documented for a maintainer with a built FE.

## Issues Encountered

- sqlglot 30.14.0's `parse()` rejects the `raise_errors` kwarg (API difference vs older docs); resolved by passing `error_level=ErrorLevel.RAISE` (verified against the installed parser signature).
- sqlglot raises ParseError for DDL fixtures with `ENGINE=OLAP ... DISTRIBUTED BY ...` while accepting CREATE INDEX only via Command fallback — these are the expected, version-specific disagreements the differential exists to record; no action needed.
- `sqlglot.exp.dialect` import path does not exist in 30.14.0; dialect presence verified via `Dialect.get_or_raise('doris')` instead.

## User Setup Required

None — no external service configuration. (Optional: `python3 -m venv .venv && pip install -r corpus/requirements.txt` for isolated dev tooling, documented in README.)

## Next Phase Readiness

- Differential evidence (CORP-04) is available for ship review and future gap analysis; disagreements with sqlglot 30.14.0 are recorded per fixture with versions.
- A maintainer with a built Doris FE can execute `fe_nereids_diff.sh` to fill `fe_nereids_observation` (manual step, D-20).
- Released-docs manifest remains the sole acceptance authority (D-07); no differential row can widen acceptance.

---
*Phase: 02-doris-completeness-and-corpus*
*Completed: 2026-08-04*
