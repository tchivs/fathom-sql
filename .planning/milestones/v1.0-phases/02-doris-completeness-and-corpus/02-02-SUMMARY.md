---
phase: 02-doris-completeness-and-corpus
plan: 02
subsystem: parser
tags: [moonbit, doris, ddl, create-table, create-view, create-index, materialized-view, lossless-cst, version-gates, keyword-dispatch]

requires:
  - phase: 02-01
    provides: keyword-first statement dispatch (INSERT/UPDATE/DELETE/MERGE), DORIS-PARSE-007 unsupported-statement diagnostic, per-family DML sync predicates
provides:
  - CREATE arm in the keyword-first dispatch (create_form_kind + parse_create)
  - parse_create_table (full 4.x body: columns, indexes, ENGINE, key types + gated ORDER BY, partitions incl. AUTO PARTITION BY and one-partition variants, DISTRIBUTED BY + gated BUCKETS AUTO, ROLLUP, PROPERTIES, LIKE and CTAS variants)
  - parse_create_view (column definitions, optional AS, query/CTE bodies), parse_create_index, parse_create_materialized_view (restricted sync body with localized JOIN/HAVING/LIMIT/LATERAL/subquery rejection)
  - DorisFeature rows OrderByClause (4.x, since 4.1.0), BucketsAuto (assumed 3.x, FLAGGED), AutoPartitionBy (assumed 2.1, FLAGGED) with DORIS-PARSE-006 gates
  - SyntaxKind CreateTable/CreateView/CreateIndex/CreateMaterializedView/ColumnDefinition/KeyClause/DistributionClause/PartitionClause/PropertyList + kind_id arms
  - per-family sync predicates is_create_table_clause_boundary / is_mv_clause_boundary (shared clause/reserved sets untouched)
  - test/ddl_test.mbt executable DDL battery (24 tests)
affects: [02-03 keyword classification, 02-04 corpus wave (verifies FLAGGED gates A2/A3/A4, Open Q1), verifier, ship]

actuals:
  tokens: 18012   # chars/4 over realized diff (72048 diff chars / 4)
  tasks: 3
  commits: 4

tech-stack:
  added: []
  patterns:
    - "Per-family DDL sync predicates (is_create_table_clause_boundary, is_mv_clause_boundary) inside parser.mbt; shared is_clause_keyword never extended"
    - "Version gates via DorisFeature + feature-event version_invalid_node substitution (ORDER BY / BUCKETS AUTO / AUTO PARTITION BY, async MV)"
    - "Flat statement-node CST: family node wraps full segment leaves via finish_statement (same as 02-01 DML); clause kinds exist in SyntaxKind + kind_id for the wire contract"

key-files:
  created:
    - test/ddl_test.mbt
  modified:
    - parser/parser.mbt
    - token/token.mbt
    - syntax/syntax.mbt
    - api/api.mbt
    - test/dml_test.mbt

key-decisions:
  - "ORDER stays in the shared reserved set (Phase 1 ORDER BY contract + official reserved list verified this session); `order` requires backticks as an identifier — bucket/comment/value remain unquoted-usable"
  - "BUCKETS AUTO gate at introduced_profile 3.x and AUTO PARTITION BY at 2.1 are wired per research A3 and remain FLAGGED for 02-04 verification"
  - "CREATE ASYNC MATERIALIZED VIEW is an explicit DORIS-PARSE-007 unsupported statement with a source-backed error node (FLAGGED-A2) until 02-04 Task 2 closes the decision"
  - "Sync MV body is a plain qualified base table (no alias/options parsing) so JOIN/LATERAL VIEW stay visible to the localized forbidden-clause gate"
  - "Double-quoted strings lex as Quoted tokens (not StringLiteral) — COMMENT/property values accept both token kinds"

patterns-established:
  - "DDL dispatch: CREATE [TEMPORARY|EXTERNAL|ASYNC] <verb> resolved by create_form_kind before parse_create dispatches per family"
  - "Column-vs-index disambiguation inside the table body via is_index_definition_start (INDEX name ( lookahead with a documented column-type word list)"
  - "MV body constraint enforcement: allowed clauses parsed, forbidden words (JOIN/HAVING/LIMIT/LATERAL) checked last with expected_class \"sync materialized view body\""

requirements-completed: [DORIS-02]

coverage:
  - id: D1
    description: "Full CREATE TABLE body (columns with KEY/aggregate/generated/NULL/AUTO_INCREMENT/DEFAULT/ON UPDATE/COMMENT, INDEX defs, ENGINE, DUPLICATE/UNIQUE/AGGREGATE KEY + ORDER BY, partitions incl. AUTO PARTITION BY and VALUES LESS THAN/IN/range/INTERVAL variants, DISTRIBUTED BY HASH/RANDOM + BUCKETS, ROLLUP, PROPERTIES) parses with byte-exact replay and span-valid CST"
    requirement: DORIS-02
    verification:
      - kind: unit
        ref: "test/ddl_test.mbt#create_table_full_body_parses_with_byte_exact_replay"
        status: pass
      - kind: unit
        ref: "test/ddl_test.mbt#create_table_partition_variants_parse_with_replay"
        status: pass
      - kind: unit
        ref: "test/ddl_test.mbt#create_table_modifier_and_qualified_name_forms"
        status: pass
    human_judgment: false
  - id: D2
    description: "Version gates: ORDER BY emits DORIS-PARSE-006 under 2.1/3.x (docs since 4.1.0); BUCKETS AUTO gated below 3.x (assumed, FLAGGED); AUTO PARTITION BY accepted by all released profiles (assumed 2.1, FLAGGED); source-backed version_invalid_node leaves"
    requirement: DORIS-02
    verification:
      - kind: unit
        ref: "test/ddl_test.mbt#create_table_order_by_is_gated_below_4x"
        status: pass
      - kind: unit
        ref: "test/ddl_test.mbt#create_table_buckets_auto_is_gated_below_3x"
        status: pass
      - kind: unit
        ref: "test/ddl_test.mbt#create_table_auto_partition_by_is_accepted_by_all_released_profiles"
        status: pass
    human_judgment: false
  - id: D3
    description: "Non-reserved DDL grammar words (bucket, comment, value) usable as unquoted column identifiers while the shared clause/reserved sets stay unchanged; reserved `order` usable quoted"
    requirement: DORIS-02
    verification:
      - kind: unit
        ref: "test/ddl_test.mbt#create_table_non_reserved_grammar_words_work_as_column_names"
        status: pass
      - kind: unit
        ref: "test/ddl_test.mbt#ddl_grammar_words_stay_out_of_shared_reserved_set"
        status: pass
    human_judgment: false
  - id: D4
    description: "CREATE VIEW (plain, column-defined, IF NOT EXISTS, CTE-bodied), CTAS composing the table-body clause stack, and CREATE TABLE LIKE parse with lossless replay"
    requirement: DORIS-02
    verification:
      - kind: unit
        ref: "test/ddl_test.mbt#create_view_parses_plain_column_defined_and_if_not_exists_forms"
        status: pass
      - kind: unit
        ref: "test/ddl_test.mbt#create_view_cte_bodied_query_parses"
        status: pass
      - kind: unit
        ref: "test/ddl_test.mbt#create_table_as_select_composes_the_clause_stack"
        status: pass
      - kind: unit
        ref: "test/ddl_test.mbt#create_table_like_parses_with_and_without_rollup"
        status: pass
    human_judgment: false
  - id: D5
    description: "CREATE INDEX documented forms (INVERTED, NGRAM_BF with PROPERTIES, ANN) and sync CREATE MATERIALIZED VIEW restricted body; JOIN/HAVING/LIMIT/LATERAL VIEW/subquery bodies rejected with a localized DORIS-PARSE-002 expected_class \"sync materialized view body\" while preserving bytes"
    requirement: DORIS-02
    verification:
      - kind: unit
        ref: "test/ddl_test.mbt#create_index_parses_documented_forms"
        status: pass
      - kind: unit
        ref: "test/ddl_test.mbt#create_sync_materialized_view_parses_restricted_body"
        status: pass
      - kind: unit
        ref: "test/ddl_test.mbt#create_materialized_view_rejects_forbidden_clauses_with_localized_diagnostic"
        status: pass
    human_judgment: false
  - id: D6
    description: "DORIS-03 statement-boundary recovery: unclosed CREATE TABLE paren and mixed DDL/DML/SELECT scripts keep all statements as distinct Statement nodes with byte-exact replay and bounded recovery on adversarial inputs"
    requirement: DORIS-02
    verification:
      - kind: unit
        ref: "test/ddl_test.mbt#doris03_unclosed_create_table_keeps_later_statements"
        status: pass
      - kind: unit
        ref: "test/ddl_test.mbt#doris03_mixed_ddl_dml_select_script_keeps_statement_ids"
        status: pass
      - kind: unit
        ref: "test/ddl_test.mbt#create_table_deep_parens_stay_bounded"
        status: pass
      - kind: unit
        ref: "test/ddl_test.mbt#create_table_property_flood_parses_losslessly"
        status: pass
    human_judgment: false

duration: 9min
completed: 2026-08-04
status: complete
---

# Phase 02 Plan 02: CREATE TABLE / VIEW / INDEX / sync MV DDL Summary

**Full 4.x CREATE TABLE body (columns, keys + gated ORDER BY, partitions incl. AUTO PARTITION BY, distribution + BUCKETS AUTO, ROLLUP, PROPERTIES), CREATE VIEW, CTAS, CREATE TABLE LIKE, CREATE INDEX, and sync CREATE MATERIALIZED VIEW parse through the keyword-first dispatch with byte-exact lossless replay and introduced_profile-style version gates (D-10/D-15).**

## Performance

- **Duration:** 9 min (commits 04:15:38Z–04:23:14Z, 2026-08-04)
- **Started:** 2026-08-04T04:10:00Z (approx., context load + planning)
- **Completed:** 2026-08-04T04:23:46Z
- **Tasks:** 3 (tracer + 2 auto)
- **Files modified:** 6 (5 modified, 1 created)

## Accomplishments
- CREATE arm in the keyword-first dispatch (create_form_kind → parse_create → TABLE/VIEW/INDEX/MATERIALIZED VIEW families); CREATE no longer falls through to the 02-01 unsupported path
- Full CREATE TABLE per the verbatim 4.x grammar: column definitions (KEY, AGGREGATE-model types, generated columns, NULL, AUTO_INCREMENT, DEFAULT, ON UPDATE, COMMENT), in-body INDEX definitions, ENGINE, key types with 4.x-gated ORDER BY (docs: since 4.1.0), partitions (AUTO PARTITION BY RANGE/LIST gated at assumed 2.1, PARTITION BY RANGE/LIST with VALUES LESS THAN / VALUES IN / half-open range / FROM..TO INTERVAL variants), DISTRIBUTED BY HASH/RANDOM with 3.x-gated BUCKETS AUTO, ROLLUP, PROPERTIES, LIKE (with WITH ROLLUP) and CTAS (optional AS + query)
- CREATE VIEW with optional column definitions and query/CTE bodies; CREATE INDEX with USING INVERTED/NGRAM_BF/ANN and PROPERTIES; sync CREATE MATERIALIZED VIEW with the restricted single-table body and localized rejection of JOIN/HAVING/LIMIT/LATERAL VIEW/subquery (expected_class "sync materialized view body")
- Version gates wired per D-15 with source-backed version_invalid_node leaves: ORDER BY (DORIS-PARSE-006 below 4.x), BUCKETS AUTO (below 3.x, assumed), AUTO PARTITION BY (accepted everywhere, assumed 2.1); CREATE ASYNC MATERIALIZED VIEW is an explicit DORIS-PARSE-007 unsupported statement (FLAGGED-A2)
- Shared token clause/reserved sets untouched (DORIS-04 groundwork); bucket/comment/value stay unquoted-usable identifiers; all 142 tests green (118 baseline + 24 DDL)

## Task Commits

Each task was committed atomically:

1. **Task 1 (tracer): CREATE TABLE full-body vertical slice** - `92548ac` (feat)
2. **Task 2: CREATE VIEW, CTAS, and CREATE TABLE LIKE** - `e8b55ac` (feat)
3. **Task 3: CREATE INDEX and sync CREATE MATERIALIZED VIEW** - `e437cea` (feat)
4. **Follow-up (FLAGGED-A2): explicit DORIS-PARSE-007 for async MVs** - `98ffa0e` (feat)

**Plan metadata:** (final docs commit captures SUMMARY/STATE/ROADMAP)

## Files Created/Modified
- `parser/parser.mbt` - CREATE dispatch (create_form_kind + parse_create with TABLE/VIEW/INDEX/MATERIALIZED arms), parse_create_table (+ column/type/partition/distribution/rollup/property parsers), parse_create_view, parse_create_index, parse_create_materialized_view (restricted sync body), is_create_table_clause_boundary, is_mv_clause_boundary, async-MV DORIS-PARSE-007 gate
- `token/token.mbt` - DorisFeature::OrderByClause / BucketsAuto / AutoPartitionBy + FeatureMetadata rows
- `syntax/syntax.mbt` - SyntaxKind::CreateTable, CreateView, CreateIndex, CreateMaterializedView, ColumnDefinition, KeyClause, DistributionClause, PartitionClause, PropertyList
- `api/api.mbt` - kind_id arms for the nine new kinds
- `test/ddl_test.mbt` (new) - 24 DDL tests: full-body replay, gate negatives per profile, non-reserved identifiers, partition variants, VIEW/CTAS/LIKE/INDEX/MV, DORIS-03 scripts, adversarial bounds
- `test/dml_test.mbt` - removed CREATE TABLE from the 02-01 unsupported-starters list (superseded by this plan's dispatch)

## Decisions Made
- ORDER/ROLLUP stay in the shared reserved set: ORDER is on the official reserved-keywords list (verified against the 4.x docs page this session) and both are Phase 1 SELECT clause words; `order` is tested as a backticked identifier
- BUCKETS AUTO (assumed 3.x) and AUTO PARTITION BY (assumed 2.1) gates wired per research A3 and remain FLAGGED for 02-04 verification against the 2.1/3.x CREATE TABLE pages
- CREATE ASYNC MATERIALIZED VIEW: explicit DORIS-PARSE-007 with a feature-event error node on the ASYNC token; decision to support (BUILD/REFRESH) closes in 02-04 Task 2 (FLAGGED-A2)
- Sync MV base table parsed as a plain qualified name so JOIN/LATERAL VIEW cannot hide in alias/option parsing; MV clause sync set is per-family (is_mv_clause_boundary)
- Comment/property string checks accept both StringLiteral (`'...'`) and Quoted (`"..."`) token kinds because the lexer classifies double-quoted strings as Quoted

## Deviations from Plan

### Plan Clarifications / Required Adjustments

**1. [Plan clarification] `order` is reserved, not an unquoted-identifier example**
- **Found during:** Task 1 (identifier acceptance test)
- **Issue:** The Task-1 acceptance parenthetical listed `order` among grammar words usable as unquoted column identifiers. ORDER is in the official Doris reserved-keywords list (verified against the 4.x docs page) AND in the shared Phase 1 clause/reserved set (ORDER BY), and the plan also mandates "the shared token clause/reserved sets are unchanged".
- **Fix:** bucket/comment/value are tested as unquoted column identifiers; `order` is tested via backticks. The shared sets are untouched. Documented in test comments and this summary.
- **Files modified:** test/ddl_test.mbt
- **Verification:** moon test 142/142
- **Committed in:** 92548ac

**2. [Plan sequencing] CTAS/LIKE grammar implemented in Task 1, validated in Task 2**
- **Found during:** Task 1 (parse_create_table)
- **Issue:** The plan splits "TABLE body" (Task 1) from "VIEW + CTAS/LIKE" (Task 2); a single parse_create_table is the coherent unit.
- **Fix:** LIKE and CTAS-AS branches live in parse_create_table (Task 1 commit); Task 2 added the validation tests for them.
- **Files modified:** parser/parser.mbt, test/ddl_test.mbt
- **Verification:** moon test 142/142
- **Committed in:** 92548ac (grammar), e8b55ac (tests)

**3. [Required test update] 02-01 unsupported-starters test listed CREATE TABLE**
- **Found during:** Task 1 (dispatch)
- **Issue:** dml_test.mbt `unsupported_statement_starters_emit_one_007_each` asserted `CREATE TABLE t (a INT)` emits DORIS-PARSE-007 — the exact behavior this plan replaces ("do not let CREATE fall through to the unsupported path").
- **Fix:** removed the CREATE TABLE entry from that list; the new `create_dispatch_replaces_the_unsupported_path` test asserts CREATE parses without DORIS-PARSE-007.
- **Files modified:** test/dml_test.mbt, test/ddl_test.mbt
- **Verification:** moon test 142/142
- **Committed in:** 92548ac

**4. [FLAGGED-A2 compliance] Async MV as explicit DORIS-PARSE-007**
- **Found during:** post-Task-3 verification
- **Issue:** The flagged assumption requires async MV to remain an explicit DORIS-PARSE-007 unsupported statement; the initial implementation produced a generic DORIS-PARSE-002 and (first attempt) placed the ASYNC check after VIEW instead of after CREATE.
- **Fix:** CREATE-level ASYNC consumption with record_feature_event + DORIS-PARSE-007 so the ASYNC token becomes a source-backed error leaf; create_form_kind routes CREATE ASYNC MATERIALIZED VIEW to the CreateMaterializedView kind; dedicated test.
- **Files modified:** parser/parser.mbt, test/ddl_test.mbt
- **Verification:** moon test 142/142
- **Committed in:** 98ffa0e

---

**Total deviations:** 4 (2 plan clarifications, 1 required test update, 1 flagged-assumption compliance)
**Impact on plan:** All adjustments honor locked constraints (shared sets unchanged, D-12 explicit unsupported nodes, D-15 gates) or the plan's own flagged assumptions. No scope creep; no feature added beyond the plan surface.

## Issues Encountered
- `LATERAL VIEW` was silently consumed as a table alias by parse_table_ref, escaping the MV forbidden-clause gate — fixed by parsing the MV base table as a plain qualified name (also matches the docs' single-base-table restriction).
- Qualified MV names (`db.mv`) initially failed because the name was parsed as a single identifier — switched to parse_qualified_name.
- Double-quoted strings lex as Quoted tokens (not StringLiteral) — COMMENT and PROPERTIES value checks accept both kinds; fixtures use both quote styles.
- `CREATE ASYNC MATERIALIZED VIEW` put ASYNC after CREATE (not after VIEW); the first fix attempt targeted the wrong position and produced a 2-diagnostic cascade — resolved at the CREATE level with a feature-event error node.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- DORIS-02 DDL surface is executable end-to-end with byte-exact replay; 02-03 (keyword classification TSV, D-16) can build the auditable table over the words this plan already classifies implicitly (non-reserved DDL words vs shared reserved set).
- 02-04 corpus wave MUST verify the FLAGGED gates: BUCKETS AUTO (assumed 3.x), AUTO PARTITION BY (assumed 2.1), per-type introductions (A4), and close the async-MV decision (A2); the docs site was reachable this session (reserved-keywords page re-read).
- Known-gap rows for 02-04: undocumented WITH view-attribute usage (Open Q1), async MV support decision (A2).

---
*Phase: 02-doris-completeness-and-corpus*
*Completed: 2026-08-04*

## Self-Check: PASSED

- SUMMARY.md exists: `.planning/phases/02-doris-completeness-and-corpus/02-02-SUMMARY.md`
- test/ddl_test.mbt exists
- Commits verified: 92548ac (Task 1 tracer), e8b55ac (Task 2), e437cea (Task 3), 98ffa0e (async-MV follow-up)
- moon test: 142/142 passed at completion