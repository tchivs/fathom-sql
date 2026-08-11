---
phase: 07-column-lineage
plan: 01
subsystem: analysis
tags: [moonbit, analyzer, lineage, public-surface, except, select-model]

# Dependency graph
requires: []
provides:
  - "Analyzer lineage-facing public surface: pub(all) SelectModel/SelectCore/SelectItem/FromItem/CteDef/NameRef/TokenSlice/ClauseKind"
  - "Public re-parser/body-location entry points: source_tokens / split_select_model / matching_paren / collect_refs / qualified_ref_at / find_word_at_depth0 / slice_tokens / has_error_missing / view_body_location / insert_body_location"
  - "`* EXCEPT (cols)` honest star expansion via SelectItem.except_cols (excluded columns produce no binding/edge, SC2)"
affects: [07-02, 07-03, 07-04, 07-05]

# Actuals (#2632) — pairs with the plan's estimate (62000 estimateTokens) to calibrate.
actuals:
  tokens: 7600     # chars/4 over the realized diff (~30,375 diff chars / 4)
  tasks: 2
  commits: 2       # task commits; the SUMMARY/metadata commit is tracked separately by the orchestrator

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "pub(all) cross-package select-model types — the Binding/TableInfo precedent confirmed by a first-task probe (no field-level pub required on moon 0.1.20260724)"
    - "Thin public wrappers extract location logic (view_body_location / insert_body_location) with zero semantic change to analyze_dml_body / analyze_create_view_body"
    - "D-03 exclusion matching single-sourced via find_column_in semantics (unquoted ASCII case-fold, quoted byte-exact)"

key-files:
  created:
    - test/analyzer_public_surface_test.mbt
  modified:
    - analyzer/select_model.mbt
    - analyzer/select_parser.mbt
    - analyzer/resolve.mbt
    - analyzer/analyzer_wbtest.mbt

key-decisions:
  - "pub(all) on the 8 select-model types suffices for cross-package read access (probe-verified on moon 0.1.20260724); no field-level pub needed — flagged assumption LINE-01 adjacency RESOLVED"
  - "split_select_model returns Some empty model (branches=[]) for an empty token stream — total function, no panic, no fabricated content — flagged assumption LINE-01 empty RESOLVED"
  - "Pitfall 3 option (a): SelectItem.except_cols captures `* EXCEPT (...)` slices; expand_star skips excluded columns (D-03 matching) so excluded columns never fabricate an edge (SC2)"
  - "insert_body_location returns a plain tuple ((Int, Int)?, Int)? because named-tuple type syntax `(col_list: ..., body_start: Int)?` is not accepted by moon 0.1.20260724 (parse error) — field semantics documented in the doc comment"

patterns-established:
  - "Wave 0 lineage-facing public surface: pub(all) models + pub fn re-parser/location helpers — lineage/ (07-02) consumes structured SELECT models with zero re-parsing"

requirements-completed: [LINE-01]

coverage:
  - id: D1
    description: "Analyzer lineage-facing public surface: 8 select-model types pub(all), 7 re-parser/body-location helpers pub, has_error_missing pub, thin view_body_location/insert_body_location wrappers — cross-package readable and end-to-end locked"
    requirement: LINE-01
    verification:
      - kind: integration
        ref: "test/analyzer_public_surface_test.mbt#public-surface select-model end-to-end"
        status: pass
      - kind: integration
        ref: "test/analyzer_public_surface_test.mbt#public-surface empty token stream empty model"
        status: pass
      - kind: integration
        ref: "test/analyzer_public_surface_test.mbt#public-surface has_error_missing positive negative"
        status: pass
    human_judgment: false
  - id: D2
    description: "`* EXCEPT (cols)` honest star expansion: SelectItem.except_cols captures exclusion slices; expand_star produces no binding for excluded columns (D-03 unquoted case-fold / quoted byte-exact)"
    requirement: LINE-01
    verification:
      - kind: unit
        ref: "analyzer/analyzer_wbtest.mbt#wb build_select_item except cols captured"
        status: pass
      - kind: unit
        ref: "analyzer/analyzer_wbtest.mbt#wb expand_star except exclusion"
        status: pass
      - kind: unit
        ref: "analyzer/analyzer_wbtest.mbt#wb expand_star except quote byte recheck"
        status: pass
      - kind: integration
        ref: "test/analyzer_public_surface_test.mbt#public-surface except cols end-to-end"
        status: pass
    human_judgment: false

# Metrics
duration: 42min
completed: 2026-08-11
status: complete
---

# Phase 07 Plan 01: Analyzer lineage-facing public surface + `* EXCEPT` honest expansion

**Wave 0 foundation for column lineage: 8 select-model types made pub(all), 7 re-parser/body-location helpers made public plus two thin view/INSERT body-location wrappers, and `* EXCEPT (cols)` captured in SelectItem.except_cols so expand_star never fabricates a binding for an excluded column (SC2).**

## Performance

- **Duration:** 42 min
- **Started:** 2026-08-11T07:10:00Z
- **Completed:** 2026-08-11T07:52:00Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- **Analyzer public surface opened** (`pub(all)` on ClauseKind/TokenSlice/NameRef/SelectItem/FromItem/CteDef/SelectCore/SelectModel; `pub fn` on source_tokens/matching_paren/collect_refs/split_select_model/qualified_ref_at/find_word_at_depth0/slice_tokens/has_error_missing) — probe-verified cross-package field read access on `moon 0.1.20260724`, so `lineage/` (07-02) can consume structured SELECT models with zero re-parsing.
- **Empty-document total function**: `split_select_model` returns `Some` empty model (`branches=[]`) for an empty token stream — no panic, no fabricated content (flagged assumption RESOLVED).
- **Two thin public wrappers**: `view_body_location(tokens)` and `insert_body_location(tokens)` extract the CREATE VIEW / INSERT body-location logic with zero semantic change to `analyze_create_view_body` / `analyze_dml_body` (their integration tests stay green).
- **`* EXCEPT (cols)` honest expansion** (Pitfall 3 option a): `SelectItem.except_cols : Array[TokenSlice]` captures the exclusion slices in `build_select_item`; `expand_star` applies the exclusion with D-03 matching (unquoted ASCII case-fold, quoted byte-exact) so the excluded column produces no Column binding / lineage edge.
- **Cross-package end-to-end tests** in `test/analyzer_public_surface_test.mbt` lock the public surface (SelectModel structure, empty stream, has_error_missing) and the EXCEPT pipeline (`SELECT * EXCEPT (b) FROM t` → a/c bindings only).

## Task Commits

Each task was committed atomically:

1. **Task 1: Open select-model public surface + re-parser/body-location entry points** - `c39b621` (feat)
2. **Task 2: SelectItem.except_cols + expand_star EXCEPT exclusion** - `ce52c7c` (feat)

**Plan metadata:** `docs(07-01): complete 07-01 plan` (separate metadata commit)

## Files Created/Modified
- `analyzer/select_model.mbt` - `pub(all)` on the 8 select-model types; `SelectItem` gains `except_cols : Array[TokenSlice]`
- `analyzer/select_parser.mbt` - `source_tokens`/`matching_paren`/`collect_refs`/`split_select_model` → `pub fn`; `split_select_model` empty-input guard; `build_select_item` captures EXCEPT exclusion slices
- `analyzer/resolve.mbt` - `has_error_missing`/`qualified_ref_at`/`find_word_at_depth0`/`slice_tokens` → `pub fn`; thin `view_body_location`/`insert_body_location` wrappers; `is_excepted` + `expand_star`/`emit_star_columns` apply the exclusion
- `analyzer/analyzer_wbtest.mbt` - white-box tests: build_select_item EXCEPT capture, expand_star exclusion (a/c no b), quote/case byte recheck
- `test/analyzer_public_surface_test.mbt` (new) - end-to-end public-surface tests + EXCEPT pipeline integration test

## Decisions Made
- **pub(all) suffices for cross-package reads** — the first-task probe (`moon check --target native`) confirmed the Binding/TableInfo precedent: no field-level `pub` is needed on the select-model fields lineage reads. Flagged assumption (LINE-01 adjacency) RESOLVED.
- **Empty token stream → Some empty model** — `split_select_model` is now total on empty input (flagged assumption LINE-01 empty RESOLVED); no existing path feeds it an empty stream in practice (SELECT bodies always carry at least the SELECT keyword), so zero drift.
- **Pitfall 3 option (a)** — `* EXCEPT` is expanded honestly in the analyzer (single point `expand_star`), not delegated to a requires-catalog gap; excluded columns never fabricate a binding/edge (SC2).
- **D-03 matching single-sourced** — `is_excepted` reuses `find_column_in` semantics (unquoted ASCII case-fold, quoted byte-exact) so exclusion and resolution share one rule.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] insert_body_location return type: named-tuple syntax unsupported**
- **Found during:** Task 1 (`moon check --target native` probe)
- **Issue:** The plan's signature `-> (col_list: (Int, Int)?, body_start: Int)?` (named tuple type) is a parse error on `moon 0.1.20260724` ("unexpected token `:`, you may expect `,` or `)`"), which cascaded into body parse failures.
- **Fix:** Return a plain tuple `((Int, Int)?, Int)?`; the field semantics (`col_list` token range, `body_start` index) are documented in the doc comment. Behavior is identical to the intended signature.
- **Files modified:** analyzer/resolve.mbt
- **Verification:** `moon check --target native` passes; analyzer + test suites green.
- **Committed in:** c39b621 (Task 1)

### Interpreted per the plan's own D-03 mandate

**2. Test 3 quote/case semantics** (Task 2)
- **Plan literal text:** "`SELECT * EXCEPT (b)` 对 catalog 列 "B" 不排除（ASCII case-fold 只对未引号）" — the "不排除" (not excluded) clause contradicts the plan's own repeated D-03 mandate ("expand_star 应用排除（ASCII case-fold，引号字节复核）", must_haves truth #3, and threat T-07-01-02) and `find_column_in`.
- **Implementation:** unquoted slices fold ASCII case (so unquoted `b` excludes catalog column "B"), quoted slices match byte-exact (so `("B")` excludes only exact "B", not "b"). The wb test `wb expand_star except quote byte recheck` locks the full matrix (quoted byte-exact positive + negative, unquoted case-fold positive).
- **Files modified:** analyzer/resolve.mbt (is_excepted), analyzer/analyzer_wbtest.mbt
- **Verification:** analyzer + test suites green.
- **Committed in:** ce52c7c (Task 2)

### Scope addition (documented)

**3. End-to-end EXCEPT integration test** (Task 2)
- **Found during:** Task 2 verification
- **Issue:** The Task 2 `<files>` list did not include `test/analyzer_public_surface_test.mbt`, but the acceptance criterion ("`SELECT * EXCEPT (b) FROM t` Column 绑定数量 = catalog 列数 - 排除列数") is end-to-end observable only through the frozen Doris parser accepting the projection modifier.
- **Fix:** Added `public-surface except cols end-to-end` to `test/analyzer_public_surface_test.mbt`, asserting the frozen parser accepts the syntax, `split_select_model` exposes `except_cols`, and `analyze` yields a/c Column bindings only (no fabricated b edge).
- **Verification:** `moon test --target native --package test` green (192/192).
- **Committed in:** ce52c7c (Task 2)

---

**Total deviations:** 1 auto-fixed (Rule 3), 1 semantic interpretation, 1 documented scope addition
**Impact on plan:** All changes were necessary for the deliverable to compile on the pinned toolchain and to satisfy the plan's own D-03/SC2 contracts. No scope creep beyond locking the new behavior end-to-end.

## Issues Encountered
- Named-tuple type syntax (`(col_list: A, body_start: B)`) is not supported by `moon 0.1.20260724` — resolved with a plain tuple (documented above). No other toolchain surprises: the `pub(all)` cross-package probe passed on the first check.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `lineage/` (07-02) can now call `@analyzer.source_tokens` / `@analyzer.split_select_model` / `@analyzer.has_error_missing` / `@analyzer.view_body_location` / `@analyzer.insert_body_location` cross-package and read `SelectModel`/`SelectCore`/`SelectItem`/`FromItem`/`CteDef`/`NameRef`/`TokenSlice`/`ClauseKind` fields read-only.
- `SelectItem.except_cols` is populated by `build_select_item` and consumed by `expand_star`, so lineage edge derivation (07-02) consumes the exclusion result directly and never re-implements EXCEPT logic.
- Both flagged assumptions (pub(all) field access; empty-document total function) are RESOLVED with probe/test evidence.

---
*Phase: 07-column-lineage*
*Completed: 2026-08-11*

## Self-Check: PASSED
- Files verified on disk: analyzer/select_model.mbt, analyzer/select_parser.mbt, analyzer/resolve.mbt, analyzer/analyzer_wbtest.mbt, test/analyzer_public_surface_test.mbt, .planning/phases/07-column-lineage/07-01-SUMMARY.md
- Commits verified in git log: c39b621 (Task 1), ce52c7c (Task 2)
- Test runs: `moon check --target native` RC=0; `moon test --target native --package analyzer` 16/16; `moon test --target native --package test` 192/192
- `parser/` untouched (git diff --stat parser/ empty)
