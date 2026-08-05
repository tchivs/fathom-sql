---
phase: 02-doris-completeness-and-corpus
plan: 01
subsystem: parser
tags: [moonbit, doris-sql, dml, insert, update, delete, merge, lossless-cst, version-gate, recovery]

# Dependency graph
requires:
  - phase: 01-core-kernel
    provides: lossless CST (syntax), profile/feature gates (token), parse_segment with statement-level panic-mode (parser), ParseLimits resource bounds, statement_id and primitive boundary (api)
provides:
  - Keyword-first statement dispatch (SELECT/WITH/INSERT/UPDATE/DELETE/MERGE + explicit unsupported) replacing the SELECT-only gate
  - parse_insert (VALUES/query sources, OVERWRITE legacy table form, PARTITION list and PARTITION (*), WITH LABEL, hints), parse_update, parse_delete (both documented forms), 4.x-gated parse_merge
  - DORIS-PARSE-007 unsupported-statement diagnostic with explicit Error nodes (D-12); 008+ reserved
  - DorisFeature::PartitionStar and DorisFeature::MergeInto introduced_profile gates (D-15)
  - Multi-char comparison operators (<=, >=, <>, !=, <=>) as single lexer symbols
affects: [02-02 ddl-create, 02-04 corpus fixtures, 02-05 analyzer statement accessors]

# Actuals (#2632) — pairs with the plan's `estimate` (40000) to calibrate future estimates.
actuals:
  tokens: 13754    # chars/4 over the realized diff (55014 diff chars)
  tasks: 3         # tasks completed
  commits: 3       # commits made

tech-stack:
  added: []
  patterns:
    - "Keyword-first dispatch via first significant raw token plus with_prefix_verb CTE lookahead"
    - "Per-family clause sync predicates; shared is_clause_keyword untouched"
    - "DorisFeature introduced_profile gates with version_invalid_node leaf substitution"

key-files:
  created:
    - test/dml_test.mbt
  modified:
    - parser/parser.mbt
    - token/token.mbt
    - syntax/syntax.mbt
    - api/api.mbt
    - lexer/lexer.mbt
    - test/recovery_test.mbt

key-decisions:
  - "Unknown statement starters move from DORIS-PARSE-001 to the new DORIS-PARSE-007; 001 remains only for trailing tokens inside recognized statements"
  - "DML sync words live in per-family predicates (is_update/is_delete/is_merge_clause_boundary), never in the shared is_clause_keyword set (research Pitfall 3)"
  - "ValueList SyntaxKind and its wire arm are registered for the VALUES clause; the CST stays flat per the plan directive (only dispatch and parse calls change), so construction lands with deeper CST work in later plans"
  - "Multi-char comparison operators are fixed at the lexer (single symbols) so DELETE form-1 op lists and SELECT comparisons actually parse"

patterns-established:
  - "Statement families share finish_statement (trailing ';' loop, Missing push, Statement wrapper) and parse_cte_prefix"

requirements-completed: [DORIS-01, DORIS-03]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "Keyword-first statement dispatch with explicit unsupported-statement nodes (DORIS-PARSE-007) for unknown starters"
    requirement: DORIS-01
    verification:
      - kind: unit
        ref: "test/dml_test.mbt#unknown_statement_starters_are_explicit_unsupported_nodes"
        status: pass
      - kind: unit
        ref: "test/dml_test.mbt#unsupported_statement_starters_emit_one_007_each"
        status: pass
      - kind: unit
        ref: "test/recovery_test.mbt#diagnostic_caps_preserve_first_error_and_emit_one_resource"
        status: pass
    human_judgment: false
  - id: D2
    description: "INSERT parser: VALUES rows (expression/DEFAULT, multi-row), INSERT ... SELECT, OVERWRITE legacy table form, PARTITION list and PARTITION (*) gate, WITH LABEL, hint trivia — byte-exact replay and span-valid CST"
    requirement: DORIS-01
    verification:
      - kind: unit
        ref: "test/dml_test.mbt#insert_values_rows_parse_with_default_and_multirow"
        status: pass
      - kind: unit
        ref: "test/dml_test.mbt#insert_overwrite_partition_star_is_accepted_by_all_released_profiles"
        status: pass
      - kind: unit
        ref: "test/dml_test.mbt#insert_partition_label_and_hint_forms_replay_exactly"
        status: pass
    human_judgment: false
  - id: D3
    description: "UPDATE and DELETE parsers with per-family clause-boundary recovery, CTE prefixes, aliases, SET/FROM/WHERE/ORDER BY (NULLS)/LIMIT, both DELETE syntaxes, PARTITION/PARTITIONS, USING"
    requirement: DORIS-01
    verification:
      - kind: unit
        ref: "test/dml_test.mbt#update_parses_cte_alias_set_from_where_order_limit"
        status: pass
      - kind: unit
        ref: "test/dml_test.mbt#delete_parses_both_documented_forms"
        status: pass
      - kind: unit
        ref: "test/dml_test.mbt#update_malformed_recovers_at_clause_boundaries"
        status: pass
    human_judgment: false
  - id: D4
    description: "4.x-gated MERGE with full clause forms under 4.x and DORIS-PARSE-006 negatives with source-backed version_invalid_node under 2.1/3.x"
    requirement: DORIS-01
    verification:
      - kind: unit
        ref: "test/dml_test.mbt#merge_into_parses_under_4x_with_all_clause_forms"
        status: pass
      - kind: unit
        ref: "test/dml_test.mbt#merge_is_gated_to_4x_released_profiles"
        status: pass
      - kind: unit
        ref: "test/dml_test.mbt#merge_malformed_recovers_losslessly"
        status: pass
    human_judgment: false
  - id: D5
    description: "DORIS-03 statement boundaries: an invalid DML statement localizes its diagnostic with a distinct statement_id while later statements parse independently; byte-exact replay on every script"
    requirement: DORIS-03
    verification:
      - kind: unit
        ref: "test/dml_test.mbt#doris03_insert_script_localizes_bad_statement"
        status: pass
      - kind: unit
        ref: "test/dml_test.mbt#doris03_dml_script_localizes_bad_statement"
        status: pass
      - kind: unit
        ref: "test/dml_test.mbt#doris03_merge_and_unsupported_keep_later_statements"
        status: pass
      - kind: unit
        ref: "test/dml_test.mbt#dml_recovery_never_swallows_later_statements"
        status: pass
    human_judgment: false

# Metrics
duration: 9min
completed: 2026-08-04
status: complete
---

# Phase 02 Plan 01: Keyword-first DML dispatch Summary

**Keyword-first statement dispatch with INSERT/UPDATE/DELETE and 4.x-gated MERGE parsers, explicit DORIS-PARSE-007 unsupported nodes, and byte-exact lossless replay across semicolon-separated scripts**

## Performance

- **Duration:** 9 min
- **Started:** 2026-08-04T03:46:41Z
- **Completed:** 2026-08-04T03:55:40Z
- **Tasks:** 3 (1 tracer, 2 auto)
- **Files modified:** 7 (1 created, 6 modified)

## Accomplishments

- **Keyword-first dispatch (D-11):** `parse_segment` now routes by the first significant raw token — SELECT → `parse_query`, WITH → `with_prefix_verb` CTE lookahead (SELECT/UPDATE/DELETE/MERGE), INSERT → `parse_insert`, UPDATE/DELETE/MERGE → family parsers, everything else → explicit unsupported-statement nodes. The trailing `;`/recovery loop, Statement wrapper, feature-event leaf substitution, and monotonic `statement_id` are preserved exactly.
- **INSERT (DORIS-01, first in D-09 order):** VALUES rows with expression/DEFAULT and multi-row lists, INSERT ... SELECT with qualified targets, INSERT OVERWRITE with the legacy literal `table` form, PARTITION lists, `PARTITION (*)` under the new `DorisFeature::PartitionStar` gate (accepted by all released profiles per its 2.1 introduction), WITH LABEL, and `/*+ hint */` blocks (lexer trivia, preserved as leaves) — all with byte-exact replay and span-valid CST.
- **UPDATE and DELETE (D-09 order):** `parse_update` per the documented 4.x grammar (CTE prefix, target alias, SET assignment list, FROM joins, WHERE, ORDER BY with per-item NULLS FIRST/LAST, LIMIT); `parse_delete` covers both documented forms (PARTITION/PARTITIONS clauses, USING, WHERE predicate chains, ORDER BY, LIMIT, CTE prefix). Malformed input recovers at clause boundaries via the new per-family sync predicates (`is_update_clause_boundary`, `is_delete_clause_boundary`) with bounded recovery steps — later statements are never swallowed (DORIS-03, D-04).
- **4.x-gated MERGE (D-09 last, D-15):** `DorisFeature::MergeInto` with `introduced_profile "4.x"`; under 2.1/3.x the MERGE keyword becomes a source-backed `version_invalid_node` with DORIS-PARSE-006 and the remainder is consumed losslessly; under 4.x the full grammar parses (WITH prefix, MERGE INTO target, USING source, ON join expression, `WHEN MATCHED [AND predicate] THEN UPDATE SET/DELETE` and `WHEN NOT MATCHED [AND predicate] THEN INSERT [(cols)] VALUES (...)`).
- **Unsupported statements (D-12):** ALTER/DROP/GRANT/SHOW/EXPLAIN/LOAD/TRUNCATE/CREATE and other unknown starters each yield exactly one DORIS-PARSE-007 diagnostic with an explicit Error node and byte-exact replay — never silent acceptance or identifier consumption. DORIS-PARSE-008+ remain reserved.
- **Lexer fix:** multi-character comparison operators (`<=`, `>=`, `<>`, `!=`, `<=>`) now scan as single symbols; previously the lexer emitted one-byte symbols so `precedence()`'s multi-char operator entries were dead code — DELETE form-1's documented op list required this.
- **Test suite:** 93 Phase 1 tests + 25 new DML/DORIS-03 tests = 118, all green; `moon check --target native` clean. Shared `is_clause_keyword` is unchanged (asserted), Phase 1 SELECT/recovery fixtures all still pass.

## Task Commits

Each task was committed atomically:

1. **Task 1: Keyword-first statement dispatch with INSERT vertical slice** - `cb64d94` (feat)
2. **Task 2: UPDATE and DELETE statement parsers with per-family recovery** - `50b77a6` (feat)
3. **Task 3: 4.x-gated MERGE and full unsupported-statement coverage** - `79a8249` (feat)

**Plan metadata:** `docs(02-01): complete keyword-first DML dispatch plan` (committed with STATE/ROADMAP/REQUIREMENTS)

## Files Created/Modified

- `parser/parser.mbt` - keyword-first dispatch in `parse_segment`; `with_prefix_verb`, `parse_cte_prefix`, `finish_statement`, `unsupported_statement`, `parse_qualified_name`, `parse_insert`, `parse_values_rows`, `parse_update`, `parse_delete`, `parse_merge`, `parse_assignment_list`, `recover_to_clause_boundary`, and the three per-family sync predicates; `parse_order_by` extended with NULLS FIRST/LAST
- `token/token.mbt` - `DorisFeature::PartitionStar` (introduced 2.1) and `DorisFeature::MergeInto` (introduced 4.x) with FeatureMetadata rows
- `syntax/syntax.mbt` - `SyntaxKind::Insert/Update/Delete/Merge/ValueList` variants
- `api/api.mbt` - exhaustive `kind_id` arms: insert, update, delete, merge, value_list
- `lexer/lexer.mbt` - `symbol_width` helper so comparison operators scan as single symbols (Rule 3 deviation)
- `test/dml_test.mbt` (new) - DML statement families, version gates, recovery, replay, and DORIS-03 script tests
- `test/recovery_test.mbt` - diagnostic-cap assertion updated to DORIS-PARSE-007 for unknown starters
- `.gitignore` - `_build/` (moon build output) added to ignore

## Decisions Made

- Unknown starters emit DORIS-PARSE-007 ("unsupported statement in the selected profile", expected_class "statement"); DORIS-PARSE-001 stays reserved for trailing tokens inside recognized statements (research Open Question 3 resolution).
- DML sync words live in per-family predicates only; the shared `is_clause_keyword` set is untouched so SELECT recovery semantics are unchanged (research Pitfall 3).
- `ValueList` is registered as a SyntaxKind with its wire arm (plan artifact list); the CST stays flat per the plan directive ("only the selected match and the per-family parse calls change"), so no clause-level nodes are constructed yet — deeper CST structure is future work.
- `DorisFeature::PartitionStar` uses `introduced_profile "2.1"` (docs note "since 2.1.3" at sub-release granularity the profiles do not model), so all released profiles accept `PARTITION (*)`; the gate machinery itself is proven firing by `MergeInto`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Multi-char comparison operators missing from the lexer**
- **Found during:** Task 2 (delete form-1 op list fixtures)
- **Issue:** The lexer emitted one-byte symbols only, so `>=`/`<=`/`!=`/`<>` never tokenized as single operators and `precedence()`'s multi-char entries were dead code. DELETE form-1's documented op list (`=, >, <, >=, <=, !=, in, not in`) made this load-bearing; it also silently affected SELECT comparisons (latent Phase 1 gap).
- **Fix:** Added `symbol_width` to the lexer symbol branch: `<=`, `>=`, `<>`, `!=` scan as 2-byte symbols and `<=>` as 3-byte. Single-byte behavior for all other symbols is unchanged.
- **Files modified:** `lexer/lexer.mbt`
- **Verification:** `moon test` (118/118) including DELETE form-1 op-list fixtures and all Phase 1 lexer/parser tests
- **Committed in:** `50b77a6` (Task 2 commit)

**2. [Rule 3 - Plan omission] Task 3 file list omitted syntax.mbt/api.mbt**
- **Found during:** Task 3 (MERGE wiring)
- **Issue:** The plan's Task 3 `<files>` listed only parser.mbt, token/token.mbt, and test/dml_test.mbt, but `SyntaxKind::Merge` and the api `kind_id` arm "merge" are required by the artifacts section and by compilation (the kind_id match is exhaustive; the Merge statement node needs its kind).
- **Fix:** Added `SyntaxKind::Merge` and the "merge" wire arm alongside the parser/token changes.
- **Files modified:** `syntax/syntax.mbt`, `api/api.mbt`
- **Verification:** `moon test` (118/118), `moon check --target native` (0 errors)
- **Committed in:** `79a8249` (Task 3 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking lexer gap, 1 plan file-list omission)
**Impact on plan:** Both were required for the plan's acceptance criteria to hold; no scope creep, no architectural changes.

## Issues Encountered

- `#` starts a line comment in the lexer (MySQL/Doris behavior). The planned malformed-UPDATE fixtures used `@#$%` as garbage tokens, which silently commented out the rest of the input; fixtures now use `@^%`. No production-code impact.
- MoonBit's `loop {}` functional-loop syntax requires explicit `break`/`continue`; `with_prefix_verb` uses `while true` with early returns instead.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **02-02 (DDL):** the dispatcher can add CREATE arms next to the DML arms; `parse_cte_prefix`, per-family sync predicates, `finish_statement`, and the lexer's multi-char operators are reusable; the unsupported path currently emits DORIS-PARSE-007 for CREATE until then.
- **02-04 (corpus):** DML fixtures can assert `print_result == raw` / `all_spans_in_bounds` and per-version gates; manifest feature_introduction validation extension (research Pattern 3 warning) is still pending for DML/DDL fixture rows.
- **02-05 (analyzer):** statement_ids are already emitted per DML statement; the statement-level accessors build on the existing primitive boundary unchanged.

## Self-Check: PASSED
