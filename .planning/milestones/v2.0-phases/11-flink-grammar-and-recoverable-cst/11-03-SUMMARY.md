---
phase: 11-flink-grammar-and-recoverable-cst
plan: 03
subsystem: parser
tags: [flink, sql, parser, recoverable-cst, ddl, create-table, dialect-gate, moonbit]

# Dependency graph
requires:
  - phase: 11-flink-grammar-and-recoverable-cst (11-02)
    provides: Flink DML/aux dispatch (parse_flink_segment INSERT/UPDATE/DELETE/EXPLAIN/SHOW/DESCRIBE/ANALYZE/USE/SET/RESET), parse_flink_data_type (Flink type path), FATHOM-PARSE-009 minting, D-02 SyntaxKind surface (CreateCatalog/CreateDatabase/CreateFunction/Drop*/AlterTable/WatermarkClause/ComputedColumn/MetadataColumn/PrimaryKeyClause/TableLikeClause), flink-grammar snapshot harness
provides:
  - Flink CREATE/ALTER/DROP dispatch (parse_flink_create/alter/drop, parserImpls.ftl:2850-2920) with second-word kind resolvers, and the CATALOG/DATABASE/VIEW/FUNCTION DDL families (SqlCreateCatalog :142-188, SqlCreateDatabase :301-372, SqlCreateView :2414-2439, SqlCreateFunction :390-480, SqlDrop*/SqlAlter*)
  - parse_flink_create_table (SqlCreateTable :1585-1712) with the four-way TableColumn column body (:1103-1145): typed physical, computed `name AS expr`, metadata `name type METADATA [FROM 'alias'] [VIRTUAL]`, PRIMARY KEY (cols) NOT ENFORCED / UNIQUE; single-instance WATERMARK (multipleWatermarksUnsupported); the pinned table-level clause order [COMMENT][DISTRIBUTED][PARTITIONED BY][WITH][LIKE|AS] with positive-integer bucket counts and RANDOM rejection; LIKE feature list and AS-query CTAS
  - is_flink_create_table_clause_boundary recovery predicate for bounded unclosed-body recovery (CST-01, D-03)
  - Bidirectional DDL negative-gate matrix frozen as fixtures: Doris-only sub-forms (DUPLICATE/UNIQUE/AGGREGATE KEY, ENGINE =, ROLLUP, PROPERTIES, AUTO PARTITION BY, PARTITION BY, DISTRIBUTED BY ... BUCKETS, AUTO_INCREMENT) → FATHOM-PARSE-009 under Flink; Flink-only sub-forms (WATERMARK, computed/metadata columns, PRIMARY KEY NOT ENFORCED, DISTRIBUTED INTO, PARTITIONED BY, WITH, LIKE feature list) → FATHOM-PARSE-009 under Doris; CATALOG/DATABASE/FUNCTION whole statements → FATHOM-PARSE-007 under Doris
  - Flink INTERVAL literal parsing (`INTERVAL '5' SECOND`, Parser-calcite-1.36.0.jj:4943-4990) in the shared expression prefix layer, gated to Flink so Doris expression behavior stays byte-identical
  - flink-grammar DDL/CREATE TABLE snapshot group (70 goldens) with the Doris baseline byte-identical
affects: [11-04 (Window TVF), 11-05 (MATCH_RECOGNIZE), 11-06, Phase 13 tooling, verifier]

# Actuals (#2632) — pairs with the plan's `estimate` (54000 tokens).
actuals:
  tokens: 71000    # chars/4 over the realized diff (authored code/tests/manifest/register + 70 snapshot goldens)
  tasks: 4
  commits: 8

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Flink DDL statement productions in parser/flink_grammar.mbt (same package as parser.mbt) reusing shared recovery/span/lossless mechanisms; Doris CREATE TABLE bodies never reused for Flink (Pitfall 1/2/7)"
    - "construct-level dialect gates via add_dialect_gate_diagnostic (FATHOM-PARSE-009) on both sides: Flink rejects Doris-only sub-forms, Doris rejects Flink-only sub-forms; whole-statement unsupported stays FATHOM-PARSE-007"
    - "consume_body_element_remainder consumes a gated column-body element up to the depth-0 `,`/`)` (paren-depth tracked) so the gate is the primary diagnostic and the body close-paren stays intact"
    - "Flink INTERVAL literal prefix in the shared expression parser gated to Flink (is_flink_interval_literal / parse_flink_interval_literal) so Doris expression prefix behavior stays byte-identical (Pitfall 7, A4)"

key-files:
  created: []
  modified:
    - parser/parser.mbt
    - parser/flink_grammar.mbt
    - parity/flink_grammar_test.mbt
    - parity/fixtures/flink-grammar/manifest.tsv
    - parity/__snapshot__/flink-grammar.*.flink-2.3.0.{strict,editor}.json (70 new)
    - .planning/phases/11-flink-grammar-and-recoverable-cst/approved-changes.md

key-decisions:
  - "Implemented the four 11-03 tasks as four per-task vertical slices, each committed as two atomic commits (implementation + register + manifest, then the generated snapshots) — the register must be committed before the single --update per D-08, and the snapshot goldens are generated separately."
  - "The Doris-side 009 gates for Flink-only CREATE TABLE forms (T-11-16) required surgical edits to the frozen Doris parser (parse_create_table_body / parse_column_definition / parse_create_table / parse_distribution_clause). The plan's 'Doris parser untouched' language and its Task-4 acceptance/verify that Flink-only forms produce FATHOM-PARSE-009 under Doris conflict; the concrete verify requirement was honored, and each gate fires only on Flink-only shapes (WATERMARK, PRIMARY KEY, UNIQUE constraint, computed AS-without-paren, METADATA, PARTITIONED BY, WITH options, DISTRIBUTED INTO, LIKE feature list) so the frozen 213-snapshot baseline stays byte-identical (verified: zero doris-named snapshot diffs)."
  - "CREATE CATALOG/DATABASE/FUNCTION under Doris route to FATHOM-PARSE-007 via a new is_doris_create_form gate in parse_doris_segment's CREATE arm (whole-statement unsupported, D-04 §9) — the frozen parser previously emitted a spurious FATHOM-PARSE-002 'malformed CREATE' for these; no frozen snapshot covered them (zero-drift)."
  - "CREATE VIEW is shared syntax (Doris supports CREATE VIEW AS query), and plain CREATE TABLE LIKE / AS SELECT are shared too — the plan's acceptance listed them as Flink-only 009-under-Doris forms, but the frozen Doris parser accepts them. Only the genuinely Flink-only variants (FUNCTION/DROP/ALTER families → 007; LIKE feature list, WITH-before-AS CTAS → 009) are gated; the shared forms stay valid under both dialects (no double-valid)."
  - "Flink INTERVAL literal parsing was added to the shared expression prefix layer (gated to Flink) because the WATERMARK strategy expression `log_ts - INTERVAL '5' SECOND` and the Window TVF sizes need it; the shared Pratt did not handle INTERVAL literals before."

patterns-established:
  - "Pattern: Flink second-word DDL dispatch (flink_create/alter/drop_form_kind) mirrors the Doris create_form_kind shape but resolves the D-02 per-family kinds (CreateCatalog/CreateDatabase/CreateFunction/Drop*/AlterTable/CreateTable/CreateView)."
  - "Pattern: parse_flink_create_table is a fully independent production (never Doris parse_create_table/parse_column_definition/parse_distribution_clause reuse) implementing the four-way TableColumn dispatch, single-instance WATERMARK, the [COMMENT][DISTRIBUTED][PARTITIONED BY][WITH][LIKE|AS] clause order, and is_flink_create_table_clause_boundary recovery."
  - "Pattern: is_flink_interval_literal / parse_flink_interval_literal add Flink interval literals to the shared expression prefix, keeping the Doris expression path byte-identical (Pitfall 7)."
  - "Pattern: consume_body_element_remainder tracks paren depth so a gated Flink element (e.g. `proc AS PROCTIME()` or `PRIMARY KEY (a) NOT ENFORCED`) is consumed up to the body element boundary without a spurious trailing-token diagnostic."

requirements-completed: [FLINK-03, FLINK-04]

coverage:
  - id: D1
    description: "Flink CREATE/ALTER/DROP CATALOG, DATABASE, TABLE, VIEW, FUNCTION parse into recoverable CST statement families under flink-2.3.0 with bounded recovery; CATALOG/DATABASE/FUNCTION are whole-statement FATHOM-PARSE-007 under Doris."
    requirement: FLINK-03
  - id: D2
    description: "Flink CREATE TABLE physical/metadata/computed columns, WATERMARK (single-instance), PRIMARY KEY NOT ENFORCED / UNIQUE, PARTITIONED BY, DISTRIBUTED INTO n BUCKETS (positive integer, RANDOM rejected), WITH connector options, LIKE feature list, and AS-query CTAS parse losslessly in the pinned clause order."
    requirement: FLINK-04
  - id: D3
    description: "The bidirectional DDL negative-gate matrix is frozen: Doris-only CREATE TABLE sub-forms reject under Flink with FATHOM-PARSE-009, Flink-only sub-forms reject under Doris with FATHOM-PARSE-009, whole-statement DDL (CATALOG/DATABASE/FUNCTION) rejects under Doris with FATHOM-PARSE-007."
    requirement: FLINK-03
  - id: D4
    description: "FLINK-03 and FLINK-04 complete with lossless-replay fixtures, strict/editor snapshots (70 goldens), and the Doris 213-snapshot baseline byte-identical (verified after every Doris-side gate)."
    requirement: FLINK-04
---

# Phase 11 Plan 3: Flink Catalog/DDL + CREATE TABLE complex forms Summary

Flink Catalog/DDL (CREATE/ALTER/DROP CATALOG, DATABASE, TABLE, VIEW, FUNCTION) and the full
CREATE TABLE complex forms (physical/metadata/computed columns, WATERMARK, PRIMARY KEY NOT
ENFORCED, PARTITIONED BY, distribution, WITH connector options, LIKE, AS) landed into lossless,
recoverable, source-backed CST statement families under flink-2.3.0, with the bidirectional
DDL negative-gate matrix frozen (FATHOM-PARSE-009 both directions, FATHOM-PARSE-007 for
whole-statement DDL under Doris) and the Doris 213-snapshot baseline byte-identical.

## One-liner

Flink DDL statement families (Catalog/DATABASE/VIEW/FUNCTION) plus the independent
`parse_flink_create_table` (four-column body + single-instance WATERMARK + pinned clause order
[COMMENT][DISTRIBUTED][PARTITIONED BY][WITH][LIKE|AS]) into recoverable CST with bidirectional
FATHOM-PARSE-009/007 gates and 70 frozen flink-grammar snapshots; Doris baseline zero-drift.

## Tasks Executed

| Task | Name | Commits | Key files |
| ---- | ---- | ------- | --------- |
| 1 | parse_flink_create/alter/drop dispatch + CATALOG + DATABASE families | 784320b (feat), dbc520d (test) | parser/parser.mbt, parser/flink_grammar.mbt, parity/flink_grammar_test.mbt, manifest.tsv, approved-changes.md, 14 snapshots |
| 2 | CREATE/ALTER/DROP VIEW + FUNCTION families | b500a9a (feat), 713a7b0 (test) | parser/flink_grammar.mbt, parity/flink_grammar_test.mbt, manifest.tsv, 24 snapshots |
| 3 | CREATE TABLE column body: four-way dispatch + WATERMARK + constraints | f2e8f4d (feat), 7e3df24 (test) | parser/parser.mbt, parser/flink_grammar.mbt, parity/flink_grammar_test.mbt, manifest.tsv, 14 snapshots |
| 4 | Table-level clauses + LIKE/AS + DDL negative-gate matrix + snapshots | cd65356 (feat), ea8e40d (test) | parser/parser.mbt, parser/flink_grammar.mbt, parity/flink_grammar_test.mbt, manifest.tsv, approved-changes.md, 18 snapshots |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1/2 - Correctness] Doris-side FATHOM-PARSE-009 gates for Flink-only CREATE TABLE forms**
- **Found during:** Task 4
- **Issue:** The plan's T-11-16 mitigation says "Doris parser untouched", but the Task 4 acceptance
  criteria and the automated verify require Flink-only CREATE TABLE forms (WATERMARK, computed/
  metadata columns, PRIMARY KEY NOT ENFORCED, DISTRIBUTED INTO, PARTITIONED BY, WITH, LIKE feature
  list) to produce FATHOM-PARSE-009 under Doris. The frozen Doris parser emitted FATHOM-PARSE-002/001
  (malformed/trailing) for these, not 009.
- **Fix:** Added surgical construct-level 009 gates to the Doris path that fire ONLY on Flink-only
  shapes: `is_flink_only_column_start` (WATERMARK/PRIMARY KEY/UNIQUE) in `parse_create_table_body`,
  computed-`AS`-without-paren and `METADATA` gates in `parse_column_definition`, `PARTITIONED`/`WITH`
  gates in `parse_create_table`, and `DISTRIBUTED ... INTO` gate in `parse_distribution_clause`, plus
  the LIKE-feature-list gate. `consume_body_element_remainder` (paren-depth tracked) keeps each gate
  a single primary diagnostic. Verified: `moon test --package parity` (no --update) passes and zero
  doris-named snapshots change (D-05/D-08 hard gate).
- **Files modified:** parser/parser.mbt, parser/flink_grammar.mbt
- **Commit:** cd65356

**2. [Rule 1 - Correctness] CREATE CATALOG/DATABASE/FUNCTION under Doris produced 002 instead of 007**
- **Found during:** Task 1
- **Issue:** The plan requires whole-statement FATHOM-PARSE-007 under Doris for the CATALOG/DATABASE/
  FUNCTION families, but the frozen Doris `parse_create` emitted FATHOM-PARSE-002 ("expected TABLE,
  VIEW, INDEX, or MATERIALIZED VIEW after CREATE").
- **Fix:** Added `is_doris_create_form` and routed non-Doris CREATE forms in `parse_doris_segment`'s
  CREATE arm to `unsupported_statement` (007). No frozen snapshot covers `CREATE <unknown>`, so the
  213-snapshot baseline stays byte-identical.
- **Files modified:** parser/parser.mbt
- **Commit:** 784320b

**3. [Rule 1 - Correctness] Flink INTERVAL literal missing from the shared expression parser**
- **Found during:** Task 3
- **Issue:** The WATERMARK strategy fixture `log_ts - INTERVAL '5' SECOND` and the Window TVF sizes
  need Flink interval literals, but the shared Pratt parsed `INTERVAL` as a bare identifier and left
  `'5' SECOND` as trailing tokens (FATHOM-PARSE-001).
- **Fix:** Added `is_flink_interval_literal` / `parse_flink_interval_literal` as a Flink-gated prefix
  in `parse_expression_context` (`INTERVAL <value> <unit> [TO <unit>]`, Parser-calcite-1.36.0.jj:
  4943-4990). Gated to Flink so Doris expression behavior stays byte-identical (Pitfall 7, A4).
- **Files modified:** parser/parser.mbt
- **Commit:** f2e8f4d

### Plan-Expectation Deviations (test assertions adjusted to the frozen baseline)

**4. CREATE VIEW is shared syntax, not Flink-only**
- The Task 2 acceptance "Under doris-4.x these starters produce FATHOM-PARSE-007" is wrong for
  CREATE VIEW: the frozen Doris parser accepts `CREATE VIEW v AS SELECT * FROM t` (valid=true). The
  genuinely-Doris-unsupported starters (FUNCTION, DROP *, ALTER *) are asserted 007; CREATE VIEW is
  asserted as shared (valid under both dialects).

**5. Plain CREATE TABLE LIKE / AS SELECT are shared syntax, not Flink-only**
- The Task 4 acceptance listed "LIKE, AS-query" as Flink-only forms producing 009 under Doris, but
  the frozen Doris parser accepts `CREATE TABLE t2 LIKE t1` and `CREATE TABLE t3 AS SELECT * FROM
  src` (valid=true). Only the genuinely Flink-only variants are gated: the LIKE feature list
  `(INCLUDING ALL)` → 009 under Doris, and the `WITH (...) AS` CTAS form (the WITH part) → 009.
  Plain LIKE/AS stay valid under both dialects (no double-valid for shared syntax).

### Notes
- The four plan tasks were committed as four vertical slices, each with two atomic commits
  (implementation+register+manifest, then generated snapshots) following the wave-2 precedent —
  the register entry must be committed before `--update` per D-08.
- The plan's `[probe FLINK-03/FLINK-04 idempotency/concurrency]` truths stay flagged-unverified but
  are pinned by the DDL/CREATE TABLE snapshots (deterministic single-pass parse; per-parse
  RecoveryState means concurrent parses cannot interleave — no shared mutable parser state added).

## Threat Surface Scan

The only new security-relevant surface is the widening of the parse entry point (more Flink DDL
statement starters) and the new Doris-side 009 gates. No new network endpoints, auth paths, file
access patterns, or trust-boundary schema changes were introduced. All new surface is syntax-level
parsing (FLINK-03/04 prohibitions: no connector/catalog/function registration, no planner claims).
The threat-register mitigations T-11-15..T-11-21 are all applied (see the Threats table above).
No threat flags required.

## Verification

- `moon test --target native --package parser` — 9/9 pass after each task.
- `moon test --target native --package parity` (no `--update`) — 496/496 pass; zero doris-named
  snapshot diffs after every Doris-side change (D-05/D-08 hard gate).
- CLI smoke checks (plan verify commands, Task 1-4):
  - `CREATE CATALOG c WITH ('type'='generic_in_memory')` / `DROP DATABASE db CASCADE` /
    `ALTER CATALOG c SET ('k'='v')` valid=true under flink-2.3.0; `CREATE CATALOG` → 007 under Doris.
  - `CREATE FUNCTION f AS 'com.example.UDF' LANGUAGE JAVA`, `CREATE VIEW v AS SELECT * FROM t`,
    `DROP VIEW IF EXISTS v`, `ALTER VIEW v AS SELECT 1` valid=true.
  - `CREATE TABLE t (a INT, b STRING)` valid=true; second `WATERMARK` → multipleWatermarksUnsupported.
  - `CREATE TABLE t (id INT) DUPLICATE KEY (id)` → 009 under Flink; `CREATE TABLE t (a INT,
    WATERMARK FOR a AS a)` → 009 under Doris.
- `print_lossless(parse(x)) == x` asserted for every positive/recovery fixture in strict and editor
  mode (CST-01).

## Self-Check: PASSED

The SUMMARY.md exists on disk and the eight implementation commits (784320b, dbc520d, b500a9a,
713a7b0, f2e8f4d, 7e3df24, cd65356, ea8e40d) are all present in git history (verified via
`git log`).
