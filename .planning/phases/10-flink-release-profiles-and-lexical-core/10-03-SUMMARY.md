---
phase: 10-flink-release-profiles-and-lexical-core
plan: 03
subsystem: api
tags: [flink, calcite, keyword-classification, dialect, moonbit, python, provenance, release-profiles]

# Dependency graph
requires:
  - phase: 10-flink-release-profiles-and-lexical-core
    provides: "10-01 FlinkProfile closed enum + FlinkProfileMetadata (calcite_version/parser_config from pinned releases) + flink-lexical manifest/extractor scaffold; 10-02 Flink lexical core (quoting/literals/operators/identifiers) + conflict-matrix snapshots"
provides:
  - "flink_classification_rows: 142 production/conflict KeywordEntry rows across the three pinned releases (flink-1.20.5 baseline 99 rows = 84 reserved + 15 nonreserved; flink-2.1.3 delta 20 rows = 18 reserved + 2 nonreserved; flink-2.3.0 delta 23 rows = 13 reserved + 10 nonreserved), each with release-grammar source (path + token line) and per-release introduced_profile"
  - "Profile-aware Flink row selection: classification_rows_for filters Flink rows by introduced_profile <= selected profile in release order flink-1.20.5 < flink-2.1.3 < flink-2.3.0; VARIANT/QUALIFY (introduced flink-2.1.3) are Reserved under 2.3.0/2.1.3 and ABSENT under 1.20.5; 2.3.0-introduced words (SAFE_CAST/NOTHING/etc.) are ABSENT under 2.1.3/1.20.5"
  - "Six full per-release keyword list attachments (443/334, 430/324, 412/323) with provenance headers, regenerable/validatable by scripts/extract_flink_lexical.py"
  - "scripts/extract_flink_lexical.py keyword validation: counts, release deltas (+13/+18 reserved, +10 nonreserved), reserved∩nonreserved overlap report, inlined-row presence checks (wrong word -> exit 1), Parser.tdd/Parser.jj VARIANT-token cross-check"
affects: [11-flink-grammar-and-recoverable-cst, 12-cross-dialect-corpus-and-parity-gates]

# Actuals (#2632) — pairs with the plan's `estimate` (36000 tokens, chars/4).
actuals:
  tokens: 20538
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "KeywordEntry row table with release-grammar provenance (path + token line) per row, never docs URLs (D-02, Pitfall 3)"
    - "Profile-aware dialect row selection: Doris dialect-only, Flink additionally filtered by introduced_profile <= selected profile (release-order rank helper)"
    - "Python-stdlib validation loop (problems list + per-line report + non-zero exit + ok line) mirroring corpus/tools/check_keywords.py"

key-files:
  created:
    - parity/fixtures/flink-lexical/flink-{2.3.0,2.1.3,1.20.5}-{reserved,nonreserved}.txt (six full keyword lists)
  modified:
    - dialect/flink.mbt (flink_classification_rows populated, audit tests)
    - dialect/classification.mbt (profile-aware selection, independence test)
    - scripts/extract_flink_lexical.py (keyword validation)

key-decisions:
  - "flink_classification_rows scoped to production/conflict words (142 rows), NOT the full 443/430/412-word lists — those are committed as the six attachment files and validated by the extract script (RESEARCH Open Question 3 RESOLVED)"
  - "VARIANT and QUALIFY carry introduced_profile flink-2.1.3 (the 2.1.3-delta list, W-1), so both are ABSENT under flink-1.20.5 via the profile-aware filter"
  - "Source columns reference the pinned release grammar (Parser-calcite-{v}.jj:line, Parser-release-{v}.tdd:line, codegen/templates/Parser.jj:line for VARIANT), never docs URLs (D-02, Pitfall 3, T-10-14)"

patterns-established:
  - "Profile-aware classification gate: flink_release_rank maps profile_id -> release order rank; flink_row_visible gates each row by introduced_profile <= selected profile"
  - "Provenance attachments + extractor validation: the full keyword lists are committed under parity/fixtures/flink-lexical/ with headers and mechanically validated against the pinned release grammar inputs"

requirements-completed: [FLINK-01]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "flink_classification_rows populated per release with release-grammar provenance and per-release introduced_profile (VARIANT/QUALIFY introduced at flink-2.1.3); Doris 116-row table byte-identical"
    requirement: FLINK-01
    verification:
      - kind: unit
        ref: "dialect/classification.mbt#classification_is_dialect_independent_and_release_aware"
        status: pass
      - kind: unit
        ref: "dialect/flink.mbt#flink_classification_rows_source_references_release_grammar"
        status: pass
    human_judgment: false
  - id: D2
    description: "Profile-aware Flink row selection in release order: VARIANT/QUALIFY Reserved under 2.3.0/2.1.3 and ABSENT under flink-1.20.5; 2.3.0-introduced words ABSENT under 2.1.3/1.20.5; Doris selection stays dialect-only"
    requirement: FLINK-01
    verification:
      - kind: unit
        ref: "dialect/classification.mbt#classification_is_dialect_independent_and_release_aware"
        status: pass
    human_judgment: false
  - id: D3
    description: "Six full per-release keyword list attachments (443/334, 430/324, 412/323) with provenance headers; extract script validates counts, deltas, overlap report, inlined-row presence, and Parser.tdd/Parser.jj cross-check"
    requirement: FLINK-01
    verification:
      - kind: unit
        ref: "python3 scripts/extract_flink_lexical.py"
        status: pass
      - kind: unit
        ref: "dialect/flink.mbt#flink_classification_rows_per_profile_are_non_empty"
        status: pass
    human_judgment: false

# Metrics
duration: 75min
completed: 2026-08-07
status: complete
---

# Phase 10 Plan 03: Release Keyword Classification Summary

**Release-accurate Flink keyword classification (142 inlined rows across flink-1.20.5/2.1.3/2.3.0 with release-grammar provenance), profile-aware row selection making VARIANT/QUALIFY ABSENT under 1.20.5, and six committed full per-release keyword lists validated by the extended extract script — all with Doris classification byte-identical**

## Performance

- **Duration:** 75 min
- **Started:** 2026-08-07T19:30:00Z
- **Completed:** 2026-08-07T20:45:00Z
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments
- Populated `flink_classification_rows` with 142 production/conflict KeywordEntry rows: flink-1.20.5 baseline (84 reserved + 15 nonreserved), flink-2.1.3 delta (18 reserved + 2 nonreserved, incl. VARIANT/QUALIFY), flink-2.3.0 delta (13 reserved + 10 nonreserved)
- Every row carries a release-grammar source (Parser-calcite-{v}.jj:line, Parser-release-{v}.tdd:line, or codegen/templates/Parser.jj:line) — never a docs URL or Calcite folklore (D-02, Pitfall 3)
- Made Flink row selection profile-aware in release order (flink-1.20.5 < flink-2.1.3 < flink-2.3.0): VARIANT/QUALIFY classify Reserved under 2.3.0/2.1.3 and are ABSENT (None) under flink-1.20.5; SAFE_CAST/NOTHING etc. are ABSENT under 2.1.3/1.20.5
- Rewrote the classification independence gate as `classification_is_dialect_independent_and_release_aware` — asserts the 1.20.5 absence, baseline visibility under all profiles, and Doris 116-row byte-identity (no union leakage)
- Committed the six full per-release reserved/nonreserved list files (443/334, 430/324, 412/323) as provenance attachments with release tag/commit/sha512/URL headers
- Extended `scripts/extract_flink_lexical.py` with keyword counts + release-delta validation, inlined-row presence checks (a deliberately wrong word exits 1), a reserved∩nonreserved overlap report, and a Parser.tdd/Parser.jj VARIANT-token cross-check against the pinned archive
- Doris classification stays byte-identical: `classification_entries(doris) == 116`, parity gate 260/260 with zero drift

## Task Commits

Each task was committed atomically:

1. **Task 1: Populate flink_classification_rows per release + rewrite the classification independence gate** - `cfd623c` (feat)
2. **Task 2: Make Flink classification row selection profile-aware (introduced_profile <= selected profile)** - `de93ee5` (feat)
3. **Task 3: Release keyword provenance: full lists committed + extract-script keyword validation + audit test** - `5bdaa52` (feat)

**Plan metadata:** pending (docs: complete plan)

## Files Created/Modified
- `dialect/flink.mbt` - flink_classification_rows populated (142 rows), VARIANT/QUALIFY introduced at flink-2.1.3, audit tests
- `dialect/classification.mbt` - profile-aware classification_rows_for (flink_release_rank/flink_row_visible), rewritten independence + version-sensitivity test
- `scripts/extract_flink_lexical.py` - keyword counts/deltas/overlap/inlined-row validation + Parser.tdd/Parser.jj cross-check
- `parity/fixtures/flink-lexical/flink-2.3.0-reserved.txt` - full 2.3.0 reserved list (443 words) with provenance header
- `parity/fixtures/flink-lexical/flink-2.1.3-reserved.txt` - full 2.1.3 reserved list (430 words) with provenance header
- `parity/fixtures/flink-lexical/flink-1.20.5-reserved.txt` - full 1.20.5 reserved list (412 words) with provenance header
- `parity/fixtures/flink-lexical/flink-2.3.0-nonreserved.txt` - full 2.3.0 nonreserved list (334 words) with provenance header
- `parity/fixtures/flink-lexical/flink-2.1.3-nonreserved.txt` - full 2.1.3 nonreserved list (324 words) with provenance header
- `parity/fixtures/flink-lexical/flink-1.20.5-nonreserved.txt` - full 1.20.5 nonreserved list (323 words) with provenance header

## Decisions Made
- Scoped flink_classification_rows to the words the parser/lexer consume plus the D-06 conflict words (142 rows), per RESEARCH Open Question 3 RESOLVED — the full 443/430/412-word lists ship as the six attachment files instead
- VARIANT/QUALIFY introduced_profile = flink-2.1.3 (W-1 2.1.3-delta list), making both ABSENT under flink-1.20.5 through the profile-aware filter
- Source columns use the pinned release grammar path + token line (e.g. `flink-sql-parser codegen/templates/Parser.jj:8374 (VARIANT)`) — never docs URLs (D-02, Pitfall 3, T-10-14)
- Overlap words (reserved ∩ nonreserved) are reported by the extract script, not silently resolved — the committed lists have no overlap per release, so the report shows "(none)"

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- MoonBit compiler treated `let mut rows : Array[KeywordEntry] = []` as an error (`unused_mut` warning-as-error) because array `push` does not require a mutable binding — fixed by removing `mut`. No behavior impact.
- The VARIANT audit test initially asserted the 2.3.0 Parser.jj line (8640) but the row's source correctly references the introducing release's line (2.1.3:8374) — corrected the assertion to match the introduced-profile source.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 11 (Flink Grammar) can consume `classification_of`/`is_reserved_word`/`is_unquoted_identifier` as the identifier-acceptance gate under the selected Flink profile (D-13/D-14)
- The profile-aware Flink rows mean a 2.1.3-introduced word (VARIANT/QUALIFY) is correctly ABSENT under flink-1.20.5 before any grammar lands
- The six committed keyword lists + extract-script validation give Phase 12 (cross-dialect corpus/parity) a regenerable provenance source

## Self-Check: PASSED
- SUMMARY.md written at .planning/phases/10-flink-release-profiles-and-lexical-core/10-03-SUMMARY.md
- Six committed keyword lists present (spot: flink-2.3.0-reserved.txt, flink-1.20.5-nonreserved.txt)
- Task commits present: cfd623c (Task 1), de93ee5 (Task 2), 5bdaa52 (Task 3)
- dialect 8/8, parity 260/260, extract script exit 0 with ok-line

---
*Phase: 10-flink-release-profiles-and-lexical-core*
*Completed: 2026-08-07*
