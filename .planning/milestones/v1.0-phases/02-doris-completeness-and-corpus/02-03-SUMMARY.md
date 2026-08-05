---
phase: 02-doris-completeness-and-corpus
plan: 03
subsystem: parser-core (token metadata)
tags: [keyword-classification, doris-04, token, version-gates, corpus, tsv]

# Dependency graph
requires:
  - phase: 02-doris-completeness-and-corpus
    provides: keyword-first DML/DDL dispatch and parsers (02-01/02-02) whose production words are classified here
provides:
  - Data-driven three-layer keyword classification table (ClassificationKind, ClassificationEntry, classification_of, table-backed is_reserved_word/is_unquoted_identifier)
  - Phase 1 classification behavior preserved byte-for-byte; is_clause_keyword untouched (recovery set)
  - corpus/keywords.tsv audit mirror (D-16) with an embedded correspondence test pinning the report to the runtime table
  - DML/DDL production-word rows with introduced_profile/source metadata (D-13/D-15)
  - DORIS-PARSE-006 version-gate tests (MERGE 4.x, QUALIFY/TABLET 3.x) and word-level-vs-feature-level gate documentation
  - Cross-profile full-table audit and corpus/tools/check_keywords.py integrity check
affects: [02-04-corpus-wave, parser-identifier-acceptance, verify-work]

actuals:
  tokens: 18115
  tasks: 3
  commits: 4

tech-stack:
  added: [python3 stdlib integrity checker (corpus/tools/check_keywords.py)]
  patterns:
    - "data-driven classification table as the single source of truth for identifier acceptance"
    - "embedded TSV correspondence test keeps the audit artifact drift-free (T-02-23)"
    - "word-level classification gate vs DorisFeature production gate documented as distinct layers"

key-files:
  created:
    - corpus/keywords.tsv
    - corpus/tools/check_keywords.py
    - test/keyword_test.mbt
  modified:
    - token/token.mbt
    - parser/parser.mbt

key-decisions:
  - "Phase 1 words absent from the official reserved list (QUALIFY, WINDOW, RECURSIVE, GROUPING, ROLLUP, DISTINCTROW, SAMPLE, OVER, NULLS, FIRST, LAST, GROUPS, OFFSET) stay Reserved to preserve byte-for-byte Phase 1 classification answers, with source notes documenting absence from the official list"
  - "TABLET stays Contextual per Phase 1 behavior and D-14 although listed in the official reserved keywords"
  - "DEFAULT is Reserved (official list) and also a value-expression operand (is_expression_operand), so documented VALUES (1, DEFAULT) and SET c = DEFAULT keep parsing (02-01 tests green)"
  - "DISTRIBUTED/OVERWRITE classified Reserved per official-list authority (D-13) despite the plan text's loose non-reserved parenthetical"
  - "MERGE is Reserved with introduced_profile 4.x per D-09 (4.x-doc-only statement); word-level introduced_profile is audit metadata — only DorisFeature gates reject version-invalid syntax (D-15)"
  - "VIEW classified NonReserved (absent from the official reserved list per D-13 authority)"

patterns-established:
  - "classification table + keywords.tsv mirror + embedded correspondence test keeps the audit artifact drift-free"
  - "reserved value-expression keywords (NULL/TRUE/FALSE/DEFAULT) remain expression operands while staying reserved as identifiers"

requirements-completed: [DORIS-04]

coverage:
  - id: D1
    description: "Data-driven three-layer classification table in token.mbt (ClassificationKind, ClassificationEntry, classification_of, table-backed is_reserved_word/is_unquoted_identifier) preserving Phase 1 answers exactly"
    requirement: DORIS-04
    verification:
      - kind: unit
        ref: "test/keyword_test.mbt#phase1_reserved_answers_are_preserved_by_the_table"
        status: pass
      - kind: unit
        ref: "test/keyword_test.mbt#classification_of_is_case_insensitive_and_returns_metadata"
        status: pass
    human_judgment: false
  - id: D2
    description: "corpus/keywords.tsv audit report (D-16) mirroring the runtime table exactly, enforced by an embedded correspondence test and the Python integrity checker"
    requirement: DORIS-04
    verification:
      - kind: unit
        ref: "test/keyword_test.mbt#classification_table_mirrors_embedded_tsv_rows"
        status: pass
      - kind: other
        ref: "python3 corpus/tools/check_keywords.py corpus/keywords.tsv"
        status: pass
    human_judgment: false
  - id: D3
    description: "DML/DDL production-word classification (105 rows) with introduced_profile and source per row; non-reserved words usable as unquoted identifiers/aliases/property keys, reserved words require backticks"
    requirement: DORIS-04
    verification:
      - kind: unit
        ref: "test/keyword_test.mbt#non_reserved_and_contextual_dml_ddl_words_are_usable_identifiers"
        status: pass
      - kind: unit
        ref: "test/keyword_test.mbt#reserved_dml_ddl_words_require_backticks_as_identifiers"
        status: pass
      - kind: unit
        ref: "test/keyword_test.mbt#grammar_words_still_work_in_clause_position"
        status: pass
    human_judgment: false
  - id: D4
    description: "Version gates: version-invalid keyword use (MERGE under 2.1/3.x, QUALIFY/TABLET under 2.1) emits DORIS-PARSE-006 via the DorisFeature gate path; word-level gate and feature-level gate documented as distinct layers"
    requirement: DORIS-04
    verification:
      - kind: unit
        ref: "test/keyword_test.mbt#version_invalid_keyword_use_emits_006_through_feature_gates"
        status: pass
    human_judgment: false
  - id: D5
    description: "Cross-profile full-table audit: identifier acceptance, backtick requirement, property-key use, and gate behavior asserted per word across 2.1/3.x/4.x"
    requirement: DORIS-04
    verification:
      - kind: unit
        ref: "test/keyword_test.mbt#full_classification_table_audit_across_profiles"
        status: pass
    human_judgment: false

# Metrics
duration: 11min
completed: 2026-08-04
status: complete
---

# Phase 2 Plan 3: Data-Driven Three-Layer Keyword Classification Summary

**Data-driven, versioned, auditable keyword classification (DORIS-04): 105-row classification table in token.mbt with per-row introduced_profile/source, table-backed is_reserved_word preserving Phase 1 answers exactly, a corpus/keywords.tsv audit mirror with embedded correspondence test, DORIS-PARSE-006 version-gate tests, and a Python TSV integrity checker**

## Performance

- **Duration:** 11 min
- **Started:** 2026-08-04T04:34:14Z
- **Completed:** 2026-08-04T04:45:00Z
- **Tasks:** 3
- **Files modified:** 5 (917 insertions, 27 deletions)

## Accomplishments
- ClassificationKind (Reserved/NonReserved/Contextual) + ClassificationEntry and a 105-row data-driven table; `classification_of` case-insensitive lookup and table-backed `is_reserved_word`/`is_unquoted_identifier` with Phase 1 answers byte-for-byte preserved (existing classification tests pass unchanged).
- The shared `is_clause_keyword` recovery set is untouched; DML/DDL words verified absent from it (research Pitfall 3).
- All DML/DDL production words classified per the official reserved-keyword list (re-read from the 4.x docs page, identical across versions per D-13), with MERGE reserved at 4.x per D-09 and TABLET/QUALIFY contextual/reserved metadata at 3.x.
- corpus/keywords.tsv (D-16) mirrors the runtime table exactly; the embedded correspondence test and `corpus/tools/check_keywords.py` (header, tabs, uniqueness, classification/profile values, 51-word production inventory coverage) keep the audit honest.
- Version-invalid keyword use emits DORIS-PARSE-006 through the existing DorisFeature gate path (MERGE under 2.1/3.x; QUALIFY/TABLET under 2.1); the word-level classification gate and the DorisFeature production gate are documented as distinct layers in token.mbt.
- A full-table cross-profile audit (2.1/3.x/4.x) asserts identifier acceptance, backtick requirement, property-key use, and gate behavior per word.

## Task Commits

Each task was committed atomically:

1. **Task 1: Data-driven three-layer classification table with Phase 1 words** - `7c6f701` (feat)
2. **Task 2: DML/DDL grammar-word classification with introduced_profile gates** - `2af65d7` (feat)
3. **Task 3: Cross-profile audit tests and TSV integrity check** - `d3406af` (feat)

**Plan metadata:** `docs(02-03): complete data-driven keyword classification plan`

## Files Created/Modified
- `token/token.mbt` - ClassificationKind/ClassificationEntry, 105-row classification table, `classification_of`/`classification_entry_count`/`classification_entry_at`, table-backed `is_reserved_word`; word-level-vs-feature-level gate comment; `is_clause_keyword` and `is_unquoted_identifier` unchanged
- `parser/parser.mbt` - `is_expression_operand` accepts DEFAULT as a value-expression keyword (Rule 1 fix; NULL/TRUE/FALSE precedent)
- `corpus/keywords.tsv` - 105-row D-16 audit mirror (word, classification, introduced_profile, source)
- `corpus/tools/check_keywords.py` - stdlib TSV integrity checker (exact header, tab-delimited, unique words, valid classification/profile values, production-word coverage)
- `test/keyword_test.mbt` - embedded TSV correspondence, Phase 1 preservation, DML-not-in-clause-set, per-word identifier/alias/property-key/backtick tests, 006 gate tests, clause-position smoke tests, and the full-table cross-profile audit

## Decisions Made
- Phase 1 words absent from the official reserved list stay Reserved so `is_reserved_word`/`is_unquoted_identifier` answers are identical to Phase 1 (acceptance criterion); sources record their absence from the official list.
- TABLET stays Contextual (Phase 1 behavior, D-14) although the official list contains it; the TABLET clause remains 3.x-gated via DorisFeature::Tablet.
- DEFAULT is Reserved per the official list AND a value-expression operand, so documented `VALUES (1, DEFAULT)` / `SET c = DEFAULT` keep parsing (02-01 tests unchanged).
- DISTRIBUTED/OVERWRITE are Reserved per official-list authority; the plan text's non-reserved parenthetical was superseded by the re-read list (D-13).
- MERGE is Reserved with introduced_profile "4.x" (D-09, 4.x-doc-only) plus the existing DorisFeature::MergeInto gate.
- Word-level `introduced_profile` is audit metadata; only DorisFeature gates reject version-invalid syntax — documented as distinct layers.
- VIEW is NonReserved (absent from the official reserved list).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] DEFAULT became Reserved and broke documented VALUES (DEFAULT) syntax**
- **Found during:** Task 2 (per-word classification tests)
- **Issue:** Classifying DEFAULT as Reserved (official list) made `INSERT INTO t VALUES (1, DEFAULT)` and `UPDATE t SET c = DEFAULT` invalid: `parse_values_rows` routes row items through `parse_expression`, whose operand gate `is_expression_operand` only special-cased NULL/TRUE/FALSE and otherwise required an unquoted identifier.
- **Fix:** Added DEFAULT to the value-expression keyword special-case in `is_expression_operand` (with a comment explaining the reserved-but-operand split), mirroring the NULL/TRUE/FALSE precedent.
- **Files modified:** parser/parser.mbt
- **Verification:** moon test 150/150 (02-01/02-02 DEFAULT fixtures green; new per-word tests green)
- **Committed in:** 2af65d7 (Task 2 commit)

**2. [Rule 1 - Bug] Duplicate RANGE row in the DML/DDL additions**
- **Found during:** Task 3 (check_keywords.py first run flagged line 85 duplicate)
- **Issue:** RANGE was added again in the DML/DDL block although it already exists as a Phase 1 window-frame word; the runtime table and TSV held two identical rows.
- **Fix:** Removed the duplicate row from token.mbt, corpus/keywords.tsv, and the test's embedded rows (Phase 1 row retained).
- **Files modified:** token/token.mbt, corpus/keywords.tsv, test/keyword_test.mbt
- **Verification:** check_keywords.py `ok: 105 keyword rows, 51 production words covered`; moon test 151/151
- **Committed in:** d3406af (Task 3 commit)

---

**Total deviations:** 2 auto-fixed (2 Rule 1 bugs)
**Impact on plan:** Both fixes were required for the reserved classification to land without breaking documented syntax or the audit integrity check. No scope creep.

## Issues Encountered
- MoonBit array literals require explicit commas between elements (newline separation is a parse error) — the table/test rows were corrected during Task 1.
- `String.to_lowercase` is not available in the pinned moonbitlang/core; the audit's case-insensitivity check uses a small `to_lower_bytes` helper (`Int.to_byte` + `Bytes::from_array`).
- `alias` is a reserved word in MoonBit (future use warning) — test locals renamed to `alias_result`.
- The official reserved-keyword page was reachable and re-read at execution time (4.x, last updated Dec 22, 2025), so flagged assumption A8 did not trigger.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- DORIS-04 is executable: classification is data-driven, versioned, auditable via keywords.tsv, and enforced by tests across all three profiles.
- D-13..D-16 are implemented; the word-level gate and the DorisFeature production gate are documented as distinct layers.
- Phase 1 / 02-01 / 02-02 behavior is preserved (151/151 tests, including `is_clause_keyword` unchanged).
- Ready for 02-04 (corpus wave): keywords.tsv is the auditable D-16 deliverable; the corpus wave can extend manifest/fixtures and verify FLAGGED gates (BUCKETS AUTO 3.x, AUTO PARTITION BY 2.1) against the 2.1/3.x CREATE TABLE pages.

---
*Phase: 02-doris-completeness-and-corpus*
*Completed: 2026-08-04*

## Self-Check: PASSED

- Files verified on disk: token/token.mbt, corpus/keywords.tsv, corpus/tools/check_keywords.py, test/keyword_test.mbt, parser/parser.mbt, 02-03-SUMMARY.md
- Commits verified: 7c6f701 (Task 1), 2af65d7 (Task 2), d3406af (Task 3)
- Plan-level verification: `moon test` 151/151 passed; `python3 corpus/tools/check_keywords.py corpus/keywords.tsv` ok (105 rows, 51 production words)
