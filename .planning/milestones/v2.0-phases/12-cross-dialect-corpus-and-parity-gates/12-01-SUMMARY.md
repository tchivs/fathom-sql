---
phase: 12-cross-dialect-corpus-and-parity-gates
plan: 01
subsystem: corpus-parity-gates
tags: [flink, corpus, manifest, offline-verifier, coverage, provenance, python-stdlib, parity]

# Dependency graph
requires:
  - phase: 10-flink-release-profiles-and-lexical-core
    provides: flink-lexical fixtures + release-pinned lexical manifest (Calcite pins, parser config, archive sha512)
  - phase: 11-flink-grammar-and-recoverable-cst
    provides: flink-grammar fixtures + per-fixture production-line manifest + 194 flink-grammar snapshots
provides:
  - Unified release-pinned Flink corpus manifest (parity/fixtures/flink/manifest.tsv, 110 rows, 19 columns, 6-category enum)
  - Committed .sql fixture files (110) hash-pinned by fixture_sha256 (embedded-raw provenance from the .mbt b"..." literals)
  - scripts/verify_corpus.py — offline stdlib manifest/hash/snapshot verifier (--check; D-06)
  - corpus/flink-coverage.tsv + generate_corpus_report.py extension — semantic-distinction coverage report (parser acceptance vs engine prerequisite)
  - extract_flink_grammar.py / extract_flink_lexical.py extensions — embedded-raw byte-compare + 6-category enum validation (local maintainer tools)
affects:
  - 12-02 (diff_parity harness consumes the frozen flink manifest/snapshot contract)
  - 12-03 (CI wiring of verify_corpus.py + report --check; compare_backends.py)
  - 13-toolchain-and-editor-packaging (Flink corpus as the coverage authority)

# Actuals (#2632) — pairs with the plan's `estimate` (52000 tokens) to calibrate future estimates.
# Same estimateTokens scale (chars/4 over the realized diff), never a harness token count.
actuals:
  tokens: 41063
  tasks: 3
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "offline gate script shape: problems list + error lines + non-zero exit + single ok: line (mirrors check_keywords.py / extract_flink_*.py)"
    - "embedded-raw provenance: committed .sql files byte-match the MoonBit b\"...\" literals; extractor byte-compares (D-08)"
    - "archive present-verify / absent-archive-not-present: research fixtures never fail CI, never fabricated"

key-files:
  created:
    - parity/fixtures/flink/manifest.tsv
    - parity/fixtures/flink/{flink-2.3.0,flink-2.1.3,flink-1.20.5,doris-4.x}/{fixture_id}.sql (110)
    - scripts/verify_corpus.py
    - corpus/flink-coverage.tsv
  modified:
    - corpus/tools/generate_corpus_report.py
    - corpus/CORPUS-REPORT.md
    - scripts/extract_flink_grammar.py
    - scripts/extract_flink_lexical.py
    - .gitignore

key-decisions:
  - "D-06 offline gate form (Task 1 checkpoint, auto-selected option-a): single-entry python3 scripts/verify_corpus.py --check with fixture_sha256 as the resident CI-checkable hash; extract_flink_* stay local maintainer tools (need /tmp/flink-research/, never wired to CI)."
  - "6-category semantics frozen at fixture level (D-01): generic SQL acceptance != Flink engine support; catalog-prerequisite / planner-prerequisite / known-limitation rows are reported as prerequisite with engine-supported=0 by construction."
  - "Expected_status mapping: positive->valid, negative->error, recovery->recovered, known-limitation/catalog-prerequisite/planner-prerequisite->valid (Pitfall 2/7)."
  - "Snapshot segment rule (dialect-correct): flink rows {fixture_id}.{profile}.{mode}.json, doris rows {fixture_id}.doris-{profile}.{mode}.json, unknown-profile slot {fixture_id}.flink-4x.{mode}.json."
  - "D-02 additive migration: old per-area manifests (flink-grammar/manifest.tsv, flink-lexical/manifest.tsv) kept in place; unified manifest only adds columns/rows, never renames fixture_id or snapshot filenames (Pitfall 6)."

patterns-established:
  - "Resident hash discipline: fixture_sha256 over committed .sql bytes is the CI-checkable hash; release archive sha512 is verified locally when present and reported archive-not-present when absent."
  - "Coverage prerequisite hard rule: generate_corpus_report.py --check cross-checks flink coverage aggregation against the unified manifest and refuses any prerequisite row counted as engine-supported."

requirements-completed: [CORPUS-01, PARITY-03]

coverage:
  - id: D1
    description: "Unified release-pinned Flink corpus manifest — 110 fixture rows, 19 columns (fixture_id, dialect, profile, exact_release, calcite_version, parser_config, source_archive_url, sha512, git_tag, git_commit, source_url, heading, retrieval_date, category, expected_status, fixture_sha256, grammar_path, line_range, mode), category exactly one of the 6 values (positive|negative|recovery|known-limitation|catalog-prerequisite|planner-prerequisite)."
    requirement: CORPUS-01
    verification:
      - kind: integration
        ref: "python3 scripts/verify_corpus.py --check (110 rows verified offline)"
        status: pass
      - kind: integration
        ref: "python3 scripts/extract_flink_grammar.py (110 unified rows pass 6-category enum + expected_status + fixture_sha256)"
        status: pass
      - kind: integration
        ref: "python3 scripts/extract_flink_lexical.py (13 unified lexical rows pass 6-category + token-source + fixture_sha256)"
        status: pass
    human_judgment: false
  - id: D2
    description: "110 committed .sql fixture files under parity/fixtures/flink/{profile}/ byte-match the embedded b\"...\" literals in flink_grammar_test.mbt / flink_lexical_test.mbt (embedded-raw provenance, D-08) and are hash-pinned by the manifest fixture_sha256 column."
    requirement: CORPUS-01
    verification:
      - kind: integration
        ref: "python3 scripts/extract_flink_grammar.py (97 embedded b\"...\" literals byte-match committed .sql files)"
        status: pass
      - kind: integration
        ref: "python3 scripts/extract_flink_lexical.py (13 embedded b\"...\" literals byte-match committed .sql files)"
        status: pass
    human_judgment: false
  - id: D3
    description: "scripts/verify_corpus.py — offline stdlib manifest/hash/snapshot verifier. --check exits 0 only when header matches, pins match dialect/flink.mbt, category is in the 6-value enum, expected_status is consistent, fixture_sha256 matches committed bytes, archive sha512 present-verifies / absent-archive-not-present, and strict+editor snapshots exist per row (dialect-correct segment); non-empty guard; path-traversal guard."
    requirement: PARITY-03
    verification:
      - kind: integration
        ref: "python3 scripts/verify_corpus.py --check (exit 0, 110 rows; exit 1 on relabeled expected_status and on missing snapshot)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Semantic-distinction coverage report — corpus/flink-coverage.tsv + generate_corpus_report.py extension render parser-accepted vs engine-prerequisite as distinct totals; catalog/planner/known-limitation never counted as engine-supported (engine-supported=49 positive-only, prerequisite=19); --check staleness byte-compare and prerequisite hard rule."
    requirement: PARITY-03
    verification:
      - kind: integration
        ref: "python3 corpus/tools/generate_corpus_report.py --check (exit 0; exit 1 on prerequisite row relabeled as positive via manifest cross-check)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Zero fixture loss in the D-02 migration — every flink-grammar manifest fixture (97) and every flink-lexical fixture entry (13) is present in the unified manifest; parity/__snapshot__ namespace untouched; moon test --package parity still 570/570."
    requirement: PARITY-03
    verification:
      - kind: integration
        ref: "set comparison (97 grammar + 13 lexical ids all present in unified); git diff --name-only -- parity/__snapshot__ empty; moon test --package parity 570/570"
        status: pass
    human_judgment: false

# Metrics
duration: 22min
completed: 2026-08-09
status: complete
---

# Phase 12 Plan 01: Unified Flink Corpus + Offline Verifier Summary

**110-fixture release-pinned Flink corpus manifest (19 columns, 6-category enum) with a stdlib offline verifier, embedded-raw .sql provenance, and a semantic-distinction coverage report — generic SQL acceptance is never reported as Flink engine support.**

## Performance

- **Duration:** 22 min
- **Started:** 2026-08-09T11:57:15Z
- **Completed:** 2026-08-09T12:19:00Z
- **Tasks:** 3 (1 auto-selected decision + 2 executed)
- **Files modified:** 118 changed in git history (110 .sql + manifest + 4 scripts + report + .gitignore)

## Accomplishments
- Unified `parity/fixtures/flink/manifest.tsv` (110 rows, 19 columns) covering all 97 flink-grammar + 13 flink-lexical fixtures with the 6-category enum, expected-status consistency, and `fixture_sha256` pins.
- `scripts/verify_corpus.py` — offline D-06 gate: header match, PINS vs `dialect/flink.mbt`, 6-category enum, expected_status consistency, fixture sha256, archive sha512 present-verify / absent-archive-not-present, strict+editor snapshot completeness, non-empty guard, path-traversal guard. Exits 0 on the full 110-row corpus.
- 110 `.sql` fixture files committed under `parity/fixtures/flink/{flink-2.3.0,flink-2.1.3,flink-1.20.5,doris-4.x}/` byte-matching the embedded `b"..."` literals (D-08 embedded-raw provenance), verified by the extended extractors.
- Semantic-distinction coverage report: `corpus/flink-coverage.tsv` + `generate_corpus_report.py` render parser-accepted (68) vs engine-prerequisite (19) as distinct totals; engine-supported (49) counts positive rows only; `--check` enforces the prerequisite hard rule and manifest aggregation cross-check.
- Zero fixture loss: every grammar (97) and lexical (13) fixture present in the unified manifest; `parity/__snapshot__` untouched; Doris baseline 570/570 parity green.

## Task Commits

Each task was committed atomically:

1. **Task 1: Confirm the offline corpus verifier contract form (D-06 one-way door)** - auto-selected option-a (single-entry `verify_corpus.py --check` with resident `fixture_sha256`; `extract_*` stay local) under `_auto_chain_active=true` (no commit — decision only).
2. **Task 2: End-to-end offline corpus verification on an all-6-category seed set** - `d595381` (feat(12-01): tracer — unified Flink corpus seed + offline verifier + coverage report)
3. **Task 3: Full D-02 migration — all 110 fixtures into the unified manifest + extractor provenance + full coverage** - `2e0872a` (feat(12-01): full D-02 migration — unified 110-row Flink corpus + extractor provenance)

**Plan metadata:** docs-only planning commits `f607dd3`/`d45d468` (pre-execution).

## Files Created/Modified
- `parity/fixtures/flink/manifest.tsv` - Unified 19-column release-pinned manifest (110 fixture rows)
- `parity/fixtures/flink/{flink-2.3.0,flink-2.1.3,flink-1.20.5,doris-4.x}/*.sql` - 110 raw-SQL fixtures extracted from embedded `b"..."` literals
- `scripts/verify_corpus.py` - Offline stdlib manifest/hash/snapshot verifier (`--check`)
- `corpus/flink-coverage.tsv` - Semantic-distinction coverage matrix
- `corpus/tools/generate_corpus_report.py` - Extended to read flink coverage, render cross-dialect section, enforce prerequisite hard rule + staleness byte-compare
- `corpus/CORPUS-REPORT.md` - Regenerated with the Flink cross-dialect section
- `scripts/extract_flink_grammar.py` - Extended: b"..." literal parser, .sql byte-compare, 6-category enum validation
- `scripts/extract_flink_lexical.py` - Extended: 13-row lexical expansion validation, token-source + 6-category
- `.gitignore` - Added `__pycache__/` and `*.pyc`

## Decisions Made
- **Task 1 (auto-selected option-a):** single-entry `verify_corpus.py --check` with `fixture_sha256` as the resident CI-checkable hash; `extract_flink_*` remain local maintainer tools (they read `/tmp/flink-research/`, never wired to CI) — per RESEARCH Open Question 4.
- **Snapshot segment rule** encodes the dialect-correct naming: flink rows `{fixture_id}.{profile}.{mode}.json`, doris rows `{fixture_id}.doris-{profile}.{mode}.json`, unknown-profile slot `{fixture_id}.flink-4x.{mode}.json` (the `unknown-profile` fixture exercises a Doris-shaped `4.x` profile under the flink dialect).
- **`.sql` directory rule:** profile `4.x` rows (doris control rows + unknown-profile slot) live under `doris-4.x/`; flink-release rows under their own profile dirs.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Regex parser missed a fixture with a multi-line comment between fields**
- **Found during:** Task 2 (fixture extraction from `flink_grammar_test.mbt`)
- **Issue:** The `match-recognize-subset` block carries a two-line `//` comment between `category` and `raw`; the initial extraction regex (single optional comment line) only found 96 of 97 grammar fixtures.
- **Fix:** Changed the fixture-block regex to allow zero-or-more comment lines (`(?://[^\n]*\n\s*)*`) before `raw:`; re-verified 97/97 grammar + 13/13 lexical fixtures parse.
- **Files modified:** `/tmp/gen_flink_corpus.py` (generator, not committed) and the committed extractor regex in `scripts/extract_flink_grammar.py` / `extract_flink_lexical.py`
- **Verification:** `python3 scripts/extract_flink_grammar.py` reports 97 embedded literals byte-matching; `extract_flink_lexical.py` reports 13.
- **Committed in:** `2e0872a` (Task 3 commit)

**2. [Rule 2 - Missing Critical] Manifest/coverage aggregation cross-check added to the report --check**
- **Found during:** Task 3 (coverage report prerequisite hard rule)
- **Issue:** The initial prerequisite hard rule caught a prerequisite row relabeled as `positive` only via a duplicate-row collision; a relabel that also removed the original positive row would slip through.
- **Fix:** Added a manifest aggregation cross-check to `check_flink_invariants`: every manifest (snapshot-segment, category) group must have exactly one coverage row whose `fixture_count` matches. A prerequisite row relabeled as positive now fails with "manifest group has N fixtures but 0/2 coverage rows".
- **Files modified:** `corpus/tools/generate_corpus_report.py`
- **Verification:** relabeled `catalog-prerequisite` row as `positive` → `generate_corpus_report.py --check` exits 1 with the cross-check problem; clean corpus exits 0.
- **Committed in:** `2e0872a` (Task 3 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 missing-critical)
**Impact on plan:** Both auto-fixes were necessary for correctness of the extraction and the coverage gate. No scope creep — the cross-check is the same prerequisite hard rule the plan requires, strengthened.

## Issues Encountered
- **`/tmp` restore overwrite prompts:** during ad-hoc negative-path testing (`cp`/`mv` of manifest/coverage backups), a `mv: overwrite` prompt interrupted a restore leaving the corpus momentarily stale. Resolved by regenerating from the deterministic generator (`/tmp/gen_flink_corpus.py full`) and re-running all gates. The generator is the single source of truth for the corpus data, so regeneration is byte-deterministic.
- **`__pycache__` untracked:** Python runs created `scripts/__pycache__/` and `corpus/tools/__pycache__/`; added `__pycache__/` + `*.pyc` to `.gitignore`.

## User Setup Required
None - no external service configuration required. All gates are local stdlib + the pinned research cache `/tmp/flink-research/` (absent archives degrade to `archive-not-present`, not failure).

## Next Phase Readiness
- **12-02 (Doris frozen diff harness)** can consume the unified flink manifest as the corpus contract; the flink snapshot namespace is verified untouched (`git diff --name-only -- parity/__snapshot__` empty).
- **12-03 (cross-backend parity + offline CI gates)** can wire `verify_corpus.py --check`, `generate_corpus_report.py --check`, and the extended extractors into CI; `compare_backends.py` remains the 12-03 deliverable.
- **Deferred/known gaps:** `extract_flink_*` need `/tmp/flink-research/` (local maintainer tools only, per D-06 option-a); the coverage report engine-supported totals are parser-acceptance-based (positive only) and never claim Flink engine/planner execution.

---
*Phase: 12-cross-dialect-corpus-and-parity-gates*
*Completed: 2026-08-09*
