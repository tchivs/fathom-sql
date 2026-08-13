---
phase: 06-lint-and-fingerprint
plan: 02
subsystem: api
tags: [lint, sqlfluff, registry, autofix, cst-walk]

requires:
  - phase: 06
    plan: 01
    provides: schema v2 constants, formatter-safe refusal pattern, CST read views
provides:
  - lint/ library: SQLFluff-style 8-rule registry + CST engine + safe autofix
  - FATHOM-LINT-001..008 stable rule codes
  - FATHOM-LINT-000 engine-level refusal diagnostic (D-33)
  - analyzer-enhanced rules 004-007 gated on injected AnalysisResult (ANLY-01)
affects: [06-03 api lint_text/fix_text, 06-04 CLI, docs]

actuals:
  tokens: 8500
  tasks: 3
  commits: 1

tech-stack:
  added: []
  patterns:
    - "SQLFluff-style rule registry with stable codes and per-rule severity overrides"
    - "CST token-scan rule judgments consuming @dialect.classification_of only (D-28)"
    - "Minimal span edits + D-33 absolute refusal for safe lossless autofix"

key-files:
  created:
    - lint/moon.pkg
    - lint/rules.mbt
    - lint/registry.mbt
    - lint/engine.mbt
    - lint/fixes.mbt
    - lint/lint_test.mbt
  modified: []

key-decisions:
  - "Rule 001 is NARROW scope (projection item first position only, Open Question 6 fallback); table-name position explicitly deferred"
  - "ORDER/GROUP only end the SELECT projection when followed by BY (ORDER BY / GROUP BY) so `SELECT order` lints as an unquoted reserved word"
  - "Rule 008 seeded with CLUSTER BY (repo-grounded corpus known-gap); table is corpus-driven and grows"
  - "Rule 002 seeded with MERGE (DorisFeature::MergeInto introduced 4.x)"
  - "Analyzer findings mapped by code with span preservation; statement id derived by span containment"

patterns-established:
  - "lint/ imports syntax/dialect/source/formatter/analyzer, never parser (D-01/D-21)"
  - "Autofix safety reuses formatter/refuse.mbt first_unsafe_element (D-33) — never rewritten"
  - "Findings sorted by start_byte then code, deterministic across runs"

requirements-completed: [LINT-01]

coverage:
  - id: D1
    description: "SQLFluff-style registry with 8 stable FATHOM-LINT-0xx codes and per-rule severity/enable overrides"
    requirement: LINT-01
    verification:
      - kind: unit
        ref: "lint/registry.mbt#default_registry_has_eight_stable_codes"
        status: pass
      - kind: unit
        ref: "lint/registry.mbt#lint_options_validates_unknown_rule"
        status: pass
    human_judgment: false
  - id: D2
    description: "CST engine with rules 001/002/003/008 and analyzer mapping 004-007 (ANLY-01 skip without catalog)"
    requirement: LINT-01
    verification:
      - kind: unit
        ref: "lint/lint_test.mbt#rule_003_select_star_without_limit_positive"
        status: pass
      - kind: unit
        ref: "lint/lint_test.mbt#rule_001_unquoted_reserved_word_narrow_scope"
        status: pass
      - kind: unit
        ref: "lint/lint_test.mbt#rule_002_version_gated_merge_advisory"
        status: pass
      - kind: unit
        ref: "lint/lint_test.mbt#rule_008_deprecated_cluster_by"
        status: pass
      - kind: unit
        ref: "lint/lint_test.mbt#analyzer_mapping_004_007_and_anly01_skip"
        status: pass
    human_judgment: false
  - id: D3
    description: "Safe autofix — minimal span edits, overlap skip, D-33 absolute refusal with FATHOM-LINT-000"
    requirement: LINT-01
    verification:
      - kind: unit
        ref: "lint/lint_test.mbt#apply_fixes_refuses_error_tree_d33"
        status: pass
      - kind: unit
        ref: "lint/lint_test.mbt#apply_fixes_wraps_reserved_word_and_preserves_untouched_bytes"
        status: pass
      - kind: unit
        ref: "lint/lint_test.mbt#apply_edits_skips_overlap_applies_adjacent"
        status: pass
    human_judgment: false

duration: 90min
completed: 2026-08-10
status: complete
---

# Phase 6: Lint and Fingerprint - Plan 02 Summary

**lint/ library: SQLFluff-style 8-rule registry with stable FATHOM-LINT-0xx codes, CST-walk engine (001/002/003/008 + analyzer-mapped 004-007), and safe lossless autofix with D-33 absolute refusal**

## Performance

- **Tasks:** 3 (implemented as one cohesive change)
- **Commits:** 1
- **Files created:** 6

## Accomplishments
- `lint/rules.mbt` — LintSeverity/LintRule/LintFinding/LintEdit types + `LintSeverity::from_id`
- `lint/registry.mbt` — `default_registry()` with 8 stable codes, `LintOptions::new` override validation
- `lint/engine.mbt` — `run_rules` with statement-family dispatch, token-scan rules, analyzer mapping
- `lint/fixes.mbt` — `apply_fixes` minimal span edits + `first_unsafe_element` D-33 gate + FATHOM-LINT-000
- 22 white-box tests covering rule positives/negatives, ANLY-01 skip, refusal, round-trip, overlap

## Task Commits

1. **lint library (Tasks 1-3 together)** - `aa1ae50` (feat)

## Files Created/Modified
- `lint/moon.pkg` - library importing syntax/dialect/source/formatter/analyzer (no parser)
- `lint/rules.mbt` - severity/rule/finding/edit types
- `lint/registry.mbt` - default 8-rule registry + LintOptions overrides
- `lint/engine.mbt` - run_rules + rule judgments
- `lint/fixes.mbt` - apply_fixes autofix
- `lint/lint_test.mbt` - 22 white-box tests

## Decisions Made
- Rule 001 narrow scope (projection item first position only), table-name position deferred per Open Question 6
- ORDER/GROUP end projection only when followed by BY — fixes the `SELECT order` vs `ORDER BY` ambiguity
- Rule 008 seeded with `CLUSTER BY` (repo-grounded corpus known-gap); 002 seeded with `MERGE` (introduced 4.x)

## Deviations from Plan

### Auto-fixed Issues

**1. `is_clause_keyword` includes ORDER/GROUP, so `SELECT order FROM t` mis-scoped**
- **Found during:** Task 1 (rule 001 test)
- **Issue:** `ORDER` is both a reserved word and a clause keyword; the projection scanner treated the `order` column ref as the ORDER clause boundary, so rule 001 never fired on it.
- **Fix:** Added `projection_end` with lookahead — ORDER/GROUP only end the projection when followed by BY.
- **Files modified:** lint/engine.mbt
- **Verification:** 22/22 lint tests pass.
- **Committed in:** aa1ae50

**2. Test expected values for overlap edits were miscalculated**
- **Found during:** Task 3 (overlap test)
- **Issue:** Expected `aXXcdef` for a [1,3)-replace edit; the edit replaces bytes 1-2, so the correct output is `aXXdef`.
- **Fix:** Corrected the expected bytes for overlap and out-of-bounds cases.
- **Files modified:** lint/lint_test.mbt
- **Verification:** 22/22 pass.
- **Committed in:** aa1ae50

---

**Total deviations:** 2 auto-fixed (1 engine correctness, 1 test arithmetic)
**Impact on plan:** No scope creep; both fixes were necessary for correct rule behavior.

## Next Phase Readiness
- 06-03 can wire `api.lint_text`/`api.fix_text` over `@lint.run_rules`/`@lint.apply_fixes` + `fathom_lint_v1`
- 06-04 can add `fathom-sql lint` CLI on the api entry points

---
*Phase: 06-lint-and-fingerprint*
*Completed: 2026-08-10*
