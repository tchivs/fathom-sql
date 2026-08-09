# Phase 11 Approved Baseline Changes (D-08 register)

This register pre-declares every intentional byte/behavior change the Phase 11
waves (11-01..11-05) are allowed to make to the frozen v1 baseline
(`parity/__snapshot__`, D-07/D-08) and to the stable diagnostic-code contract
(D-04). Phase 11 lands the real Flink statement grammar (D-06) over the Phase
10 lexical core; the register is the approval path's whitelist for the
flink-grammar snapshot group and the registered flink-lexical re-generation.

**Rule:** `moon test --update --package parity` is NEVER run without a
matching entry in this register already committed (single-use approval path —
research Pitfall 3/7). Any diff NOT in this register is a regression and must
be fixed, not absorbed. **Doris 213-snapshot zero-drift is a HARD gate:** any
shared parser/CST change keeps the Doris 213 snapshots byte-identical; the
only snapshot changes this phase may make are the new `flink-grammar.*` group
and the registered `flink-lexical.*` re-generation (D-05/D-08, Pitfall 1/7).

## 1. FATHOM-PARSE-008 retirement (D-06, one-way)

Phase 10 minted `FATHOM-PARSE-008` ("flink grammar is not yet implemented in
this release") for the `parse_flink_segment` not-implemented route. Phase 11
replaces that route with the real Flink grammar (D-04/D-06). The code is
**retired and stays vacant — never reused** (the same vacancy convention as
`DORIS-PARSE-005`). Consumers that observed 008 in Phase 9/10 must expect the
real-grammar behavior from Phase 11 onward:

| Retired code | Disposition |
|--------------|-------------|
| `FATHOM-PARSE-008` | Vacant. No valid Flink statement produces it; the code is never reused. The Phase 10 flink-lexical assertions/snapshots that froze the not-implemented route are re-generated to the real-grammar expectations (item 4). Genuinely-unsupported whole statements route through `FATHOM-PARSE-007` (`unsupported_statement`); the phase-11 parser test, api flink entry, export smoke tests, formatter test, and LSP selection tests are updated in the same commit. |

## 2. FATHOM-PARSE-009 minting (D-04, one-way)

The bidirectional dialect-negative gate (SC4): Flink-only constructs in Doris
mode and Doris-only constructs in Flink mode are rejected with a
construct-level diagnostic. `FATHOM-PARSE-007` ("unsupported statement in the
selected profile") stays reserved for whole-statement unsupported; the new code
is for a clause/construct that is valid only in the other dialect:

| New code | Message | Meaning |
|----------|---------|---------|
| `FATHOM-PARSE-009` | "syntax is not supported in the selected dialect" | Construct-level dialect-gate rejection (D-04). Dialect identity rides in the parse envelope metadata (D-10), never in the code prefix. |

The `add_dialect_gate_diagnostic` helper emits 009 at every Doris-only
construct point in the Flink SELECT path (INTO OUTFILE, QUALIFY,
PARTITION/TABLET/SAMPLE/TABLESAMPLE/REPEATABLE table options) and every
Flink-only construct point in the Doris path (WATERMARK, computed/metadata
columns, PRIMARY KEY NOT ENFORCED, DISTRIBUTED ... INTO n BUCKETS,
PARTITIONED BY, WITH connector options, LIKE/AS, INSERT OVERWRITE/UPSERT/
ON CONFLICT, MATCH_RECOGNIZE, Window TVF — as each lands in 11-02..05).

## 3. flink-grammar snapshot group (D-05, Pitfall 7)

Phase 11 mints an **independent** snapshot namespace under
`parity/__snapshot__/` with the filename shape
`flink-grammar.{fixture}.{profile}.{strict,editor}.json`. The group is
disjoint from the Doris 213-snapshot baseline AND from the flink-lexical
group: a flink-grammar file can never collide with either.

Wave 1 (11-01) mints the FLINK-02 core-query fixtures (positive SELECT with
CTE+JOIN+aggregation, incomplete SELECT recovery, and the set-operation
positives UNION [ALL] / INTERSECT / EXCEPT, both strict and editor modes):

| New snapshot file | Meaning |
|-------------------|---------|
| `flink-grammar.select-cte-join-agg.flink-2.3.0.{strict,editor}.json` | `WITH o AS (...) SELECT u.name, SUM(o.amount) AS total FROM o JOIN users u ON ... GROUP BY u.name` under flink-2.3.0: real Select CST, valid=true |
| `flink-grammar.select-incomplete.flink-2.3.0.{strict,editor}.json` | `SELECT a, b FROM t WHERE` under flink-2.3.0: bounded Missing/Error node, print_lossless round-trip |
| `flink-grammar.set-union-all.flink-2.3.0.{strict,editor}.json` | `SELECT a FROM t1 UNION ALL SELECT a FROM t2` (CompoundQuery, Parser-calcite-1.36.0.jj:3395) |
| `flink-grammar.set-intersect.flink-2.3.0.{strict,editor}.json` | `SELECT a FROM t1 INTERSECT SELECT a FROM t2` |
| `flink-grammar.set-except.flink-2.3.0.{strict,editor}.json` | `SELECT a FROM t1 EXCEPT SELECT a FROM t2` |
| `flink-grammar.set-intersect-all.flink-2.3.0.{strict,editor}.json` | `SELECT a FROM t1 INTERSECT ALL SELECT a FROM t2` |
| `flink-grammar.set-except-all.flink-2.3.0.{strict,editor}.json` | `SELECT a FROM t1 EXCEPT ALL SELECT a FROM t2` |

Wave 2 (11-02) mints the FLINK-02 DML + auxiliary fixtures — INSERT/UPSERT
(RichSqlInsert, parserImpls.ftl:2306-2379), UPDATE/DELETE (Calcite SqlUpdate
:1794-1832 / SqlDelete :1768-1789), EXPLAIN/SHOW/DESCRIBE/ANALYZE (SqlRichExplain
:3079-3117, SqlShow* family, SqlRichDescribeTable :867-880, SqlAnalyzeTable
:3413-3443), USE/SET/RESET, and the Flink expression/type breadth (`=>`
NAMED_ARGUMENT_ASSIGNMENT Parser-calcite-1.36.0.jj:8794, CAST with
parse_flink_data_type mapping dataTypeParserMethods Parser.tdd:759-765, ROW/ARRAY
constructors) — each in strict and editor modes:

| New snapshot file | Meaning |
|-------------------|---------|
| `flink-grammar.insert-into-select.flink-2.3.0.{strict,editor}.json` | `INSERT INTO t SELECT * FROM s` (RichSqlInsert INTO + query source) |
| `flink-grammar.insert-overwrite-partition.flink-2.3.0.{strict,editor}.json` | `INSERT OVERWRITE t PARTITION (dt='1') SELECT * FROM s` (OVERWRITE + PARTITION spec) |
| `flink-grammar.upsert-into-values.flink-2.3.0.{strict,editor}.json` | `UPSERT INTO t VALUES (1, 2)` (Flink-only UPSERT) |
| `flink-grammar.insert-columns-on-conflict.flink-2.3.0.{strict,editor}.json` | `INSERT INTO t (a, b) VALUES (1, 2) ON CONFLICT DO NOTHING` (column list + ON CONFLICT tail) |
| `flink-grammar.insert-distributed.flink-2.3.0.{strict,editor}.json` | `INSERT INTO t DISTRIBUTED BY HASH(k) BUCKETS 10` under flink — FATHOM-PARSE-009 (Doris-only distribution form) |
| `flink-grammar.insert-incomplete.flink-2.3.0.{strict,editor}.json` | `INSERT INTO t (a,` — bounded Missing node, lossless replay |
| `flink-grammar.insert-recovery.flink-2.3.0.{strict,editor}.json` | `INSERT INTO t (a, b; SELECT 2` — recovers at `;`, trailing SELECT is its own statement |
| `flink-grammar.update-where.flink-2.3.0.{strict,editor}.json` | `UPDATE t SET a = 1 WHERE id = 5` (SqlUpdate Flink-safe subset) |
| `flink-grammar.delete-where.flink-2.3.0.{strict,editor}.json` | `DELETE FROM t WHERE id = 5` (SqlDelete Flink-safe subset) |
| `flink-grammar.update-comment.flink-2.3.0.{strict,editor}.json` | `UPDATE t SET a = 1 COMMENT 'x'` — FATHOM-PARSE-009 (Doris-only COMMENT) |
| `flink-grammar.delete-partition.flink-2.3.0.{strict,editor}.json` | `DELETE FROM t PARTITION (p1)` — FATHOM-PARSE-009 (Doris-only PARTITION) |
| `flink-grammar.update-incomplete.flink-2.3.0.{strict,editor}.json` | `UPDATE t SET` — bounded Missing/Error nodes, lossless replay |
| `flink-grammar.delete-incomplete.flink-2.3.0.{strict,editor}.json` | `DELETE FROM t WHERE` — bounded Missing/Error nodes, lossless replay |
| `flink-grammar.update-recovery.flink-2.3.0.{strict,editor}.json` | `UPDATE t SET a = 1 WHERE id = 5; SELECT 1` — trailing SELECT its own statement |
| `flink-grammar.explain-plan-for.flink-2.3.0.{strict,editor}.json` | `EXPLAIN PLAN FOR SELECT * FROM t` (SqlRichExplain) |
| `flink-grammar.show-tables-from-like.flink-2.3.0.{strict,editor}.json` | `SHOW TABLES FROM db1 LIKE '%'` (SqlShowTables) |
| `flink-grammar.show-catalogs.flink-2.3.0.{strict,editor}.json` | `SHOW CATALOGS` (SqlShowCatalogs) |
| `flink-grammar.show-negative.flink-2.3.0.{strict,editor}.json` | `SHOW TABLES db1` — localized FATHOM-PARSE-002 at the offending `db1` token |
| `flink-grammar.describe-table.flink-2.3.0.{strict,editor}.json` | `DESCRIBE TABLE t` (SqlRichDescribeTable) |
| `flink-grammar.describe-extended-database.flink-2.3.0.{strict,editor}.json` | `DESCRIBE EXTENDED DATABASE db` |
| `flink-grammar.analyze-table.flink-2.3.0.{strict,editor}.json` | `ANALYZE TABLE t` (SqlAnalyzeTable) |
| `flink-grammar.analyze-buckets.flink-2.3.0.{strict,editor}.json` | `ANALYZE TABLE t BUCKETS 10` — FATHOM-PARSE-009 (Doris-only BUCKETS) |
| `flink-grammar.use-catalog.flink-2.3.0.{strict,editor}.json` | `USE CATALOG c` (SqlUseCatalog) |
| `flink-grammar.set-option.flink-2.3.0.{strict,editor}.json` | `SET 'k' = 'v'` (SqlSetOption) |
| `flink-grammar.reset-option.flink-2.3.0.{strict,editor}.json` | `RESET 'k'` (SqlReset) |
| `flink-grammar.named-arg.flink-2.3.0.{strict,editor}.json` | `SELECT f(a => 1)` (NAMED_ARGUMENT_ASSIGNMENT Parser-calcite-1.36.0.jj:8794) |
| `flink-grammar.cast-timestamp-ltz.flink-2.3.0.{strict,editor}.json` | `SELECT CAST(x AS TIMESTAMP_LTZ(3))` (parse_flink_data_type) |
| `flink-grammar.cast-map-type.flink-2.3.0.{strict,editor}.json` | `SELECT CAST(a AS MAP<STRING, INT>)` (generic type) |
| `flink-grammar.row-ctor.flink-2.3.0.{strict,editor}.json` | `SELECT ROW(1, 'a')` (SqlRow constructor) |
| `flink-grammar.array-ctor.flink-2.3.0.{strict,editor}.json` | `SELECT ARRAY[1, 2]` (collection literal) |

The bidirectional dialect-gate assertions for the DML/aux surface are in
`parity/flink_grammar_test.mbt` (Flink-only DML rejected under Doris with
FATHOM-PARSE-007/001/009 as the frozen baseline provides; Doris-only DML/aux
rejected under Flink with FATHOM-PARSE-009; SHOW/DESCRIBE/ANALYZE whole
statements rejected under Doris with FATHOM-PARSE-007).

Wave 3 (11-03) mints the FLINK-03 DDL + FLINK-04 CREATE TABLE fixtures —
CREATE/ALTER/DROP CATALOG, DATABASE, TABLE, VIEW, FUNCTION (SqlCreateExtended/
SqlDropExtended parserImpls.ftl:2850-2920 + SqlAlter* Parser.tdd:651-727) and
the SqlCreateTable complex forms (SqlCreateTable :1585-1712, TableColumn
:1103-1145, SqlDistribution :1560-1600, Properties :1506-1556, SqlTableLike
:1714-1790, AS query :1650-1690) — each in strict and editor modes:

| New snapshot file | Meaning |
|-------------------|---------|
| `flink-grammar.create-catalog.flink-2.3.0.{strict,editor}.json` | `CREATE CATALOG c WITH ('type'='generic_in_memory')` (SqlCreateCatalog :142-188, create_catalog kind) |
| `flink-grammar.create-database.flink-2.3.0.{strict,editor}.json` | `CREATE DATABASE db COMMENT 'sales db' WITH ('k'='v')` (SqlCreateDatabase :301-372) |
| `flink-grammar.drop-catalog.flink-2.3.0.{strict,editor}.json` | `DROP CATALOG IF EXISTS c` (SqlDropCatalog :173-188) |
| `flink-grammar.drop-database.flink-2.3.0.{strict,editor}.json` | `DROP DATABASE db CASCADE` (SqlDropDatabase :351-372) |
| `flink-grammar.alter-catalog.flink-2.3.0.{strict,editor}.json` | `ALTER CATALOG c SET ('k'='v')` (SqlAlterCatalog Parser.tdd:659, alter_table kind) |
| `flink-grammar.create-catalog-incomplete.flink-2.3.0.{strict,editor}.json` | `CREATE CATALOG c WITH (` — bounded Missing/Error, lossless replay |
| `flink-grammar.drop-database-incomplete.flink-2.3.0.{strict,editor}.json` | `DROP DATABASE` (missing name) — bounded Missing/Error, lossless replay |
| `flink-grammar.create-view.flink-2.3.0.{strict,editor}.json` | `CREATE VIEW v AS SELECT * FROM t` (SqlCreateView :2414-2439, create_view kind) |
| `flink-grammar.create-function.flink-2.3.0.{strict,editor}.json` | `CREATE TEMPORARY FUNCTION f AS 'com.example.UDF' LANGUAGE JAVA` (SqlCreateFunction :390-480, create_function kind) |
| `flink-grammar.create-function-python.flink-2.3.0.{strict,editor}.json` | `CREATE TEMPORARY SYSTEM FUNCTION f AS 'x' LANGUAGE PYTHON` (all three LANGUAGE values accepted) |
| `flink-grammar.create-view-field-list.flink-2.3.0.{strict,editor}.json` | `CREATE VIEW v (a, b) AS SELECT a, b FROM t` (field list preserved) |
| `flink-grammar.drop-view.flink-2.3.0.{strict,editor}.json` | `DROP VIEW IF EXISTS v` (drop_view kind) |
| `flink-grammar.drop-function.flink-2.3.0.{strict,editor}.json` | `DROP FUNCTION IF EXISTS f` (drop_function kind) |
| `flink-grammar.alter-view-rename.flink-2.3.0.{strict,editor}.json` | `ALTER VIEW v RENAME TO v2` |
| `flink-grammar.alter-view-as.flink-2.3.0.{strict,editor}.json` | `ALTER VIEW v AS SELECT 1` |
| `flink-grammar.alter-function.flink-2.3.0.{strict,editor}.json` | `ALTER FUNCTION f AS 'com.example.UDF' LANGUAGE SCALA` |
| `flink-grammar.create-view-incomplete.flink-2.3.0.{strict,editor}.json` | `CREATE VIEW v AS` — bounded Missing/Error, lossless replay |
| `flink-grammar.create-function-incomplete.flink-2.3.0.{strict,editor}.json` | `CREATE FUNCTION f AS` — bounded Missing/Error, lossless replay |
| `flink-grammar.view-recovery.flink-2.3.0.{strict,editor}.json` | `CREATE VIEW v AS SELECT * FROM t; SELECT 2` — trailing SELECT independent statement |
| `flink-grammar.create-table-columns.flink-2.3.0.{strict,editor}.json` | `CREATE TABLE t (log_ts TIMESTAMP_LTZ(3), proc AS PROCTIME(), x STRING METADATA FROM 'x' VIRTUAL, PRIMARY KEY (id) NOT ENFORCED, WATERMARK FOR log_ts AS log_ts - INTERVAL '5' SECOND)` — four column kinds + Watermark + PK |
| `flink-grammar.create-table-typed-column.flink-2.3.0.{strict,editor}.json` | `CREATE TABLE t (a INT, b STRING)` — typed physical columns |
| `flink-grammar.create-table-watermark-second.flink-2.3.0.{strict,editor}.json` | second `WATERMARK FOR` — localized multipleWatermarksUnsupported error (valid=false) |
| `flink-grammar.create-table-pk-enforced.flink-2.3.0.{strict,editor}.json` | `PRIMARY KEY (id) ENFORCED` — localized error (valid=false) |
| `flink-grammar.create-table-trailing-comma.flink-2.3.0.{strict,editor}.json` | `CREATE TABLE t (a INT,)` — trailing-comma error, lossless replay |
| `flink-grammar.create-table-incomplete-wm.flink-2.3.0.{strict,editor}.json` | `CREATE TABLE t (WATERMARK FOR ts AS)` — bounded Missing/Error |
| `flink-grammar.create-table-incomplete-col.flink-2.3.0.{strict,editor}.json` | `CREATE TABLE t (a INT, b` — recovers at clause boundary, lossless |
| `flink-grammar.create-table-full-clauses.flink-2.3.0.{strict,editor}.json` | `CREATE TABLE t (a INT) COMMENT 'x' DISTRIBUTED BY HASH(a) INTO 6 BUCKETS PARTITIONED BY (dt) WITH ('connector'='kafka')` — pinned clause order |
| `flink-grammar.create-table-like.flink-2.3.0.{strict,editor}.json` | `CREATE TABLE t2 LIKE t1 (INCLUDING ALL)` (SqlTableLike :1714-1790) |
| `flink-grammar.create-table-as.flink-2.3.0.{strict,editor}.json` | `CREATE TABLE t3 AS SELECT * FROM src` (SqlCreateTableAs :1650-1690) |
| `flink-grammar.create-table-with-as.flink-2.3.0.{strict,editor}.json` | `CREATE TABLE t4 WITH ('k'='v') AS SELECT a FROM src` |
| `flink-grammar.create-table-random-distribution.flink-2.3.0.{strict,editor}.json` | `CREATE TABLE t DISTRIBUTED BY RANDOM` — localized error (testCreateTableWithRandomDistribution .fails) |
| `flink-grammar.create-table-negative-buckets.flink-2.3.0.{strict,editor}.json` | `CREATE TABLE t DISTRIBUTED INTO -3 BUCKETS` — localized error at the offending `-` token |
| `flink-grammar.create-table-doris-key.flink-2.3.0.{strict,editor}.json` | `CREATE TABLE t (id INT) DUPLICATE KEY (id)` under flink — FATHOM-PARSE-009 (Doris-only KEY) |
| `flink-grammar.create-table-doris-engine.flink-2.3.0.{strict,editor}.json` | `CREATE TABLE t (id INT) ENGINE = OLAP` — FATHOM-PARSE-009 |
| `flink-grammar.create-table-doris-properties.flink-2.3.0.{strict,editor}.json` | `CREATE TABLE t (id INT) PROPERTIES ("k"="v")` — FATHOM-PARSE-009 |

The bidirectional dialect-gate assertions for the DDL surface are in
`parity/flink_grammar_test.mbt`: the Catalog/DATABASE/VIEW/FUNCTION whole
statements reject under Doris with FATHOM-PARSE-007 (unsupported_statement);
the Doris-only CREATE TABLE sub-forms (DUPLICATE/UNIQUE/AGGREGATE KEY,
ENGINE =, AUTO_INCREMENT, ROLLUP, AUTO PARTITION BY, PROPERTIES, DISTRIBUTED
BY ... BUCKETS) reject under Flink with FATHOM-PARSE-009; the Flink-only
CREATE TABLE sub-forms (WATERMARK, computed/metadata columns, PRIMARY KEY NOT
ENFORCED, DISTRIBUTED INTO, PARTITIONED BY, WITH, LIKE, AS-query) reject under
Doris with FATHOM-PARSE-009 (the unchanged Doris parser never produces them).
The same Flink-only inputs under flink are valid — no double-valid (Pitfall 2).

Wave 4 (11-04) mints the FLINK-05 Window TVF fixtures first (Task 1), then
the FLINK-06 MATCH_RECOGNIZE fixtures (Task 2). Window TVF rides the generic
table-function-call path (TableFunctionCall, Parser.jj:2443-2460 /
Parser-calcite-1.36.0.jj:2391); TUMBLE/HOP/SESSION/DESCRIPTOR are non-reserved
(Parser.tdd:587/:384/:509/:351), CUMULATE has no keyword token. MATCH_RECOGNIZE
is the syntax-level nested sub-language (MatchRecognize, Parser.jj:3062-3346 /
Parser-calcite-1.36.0.jj:3020) with PATTERN/DEFINE/MEASURES/skip/variables/
quantifiers; SUBSET/PERMUTE/{- -} parse structurally and are classified
known-limitation. Both are Flink-only — rejected under Doris with
FATHOM-PARSE-009 at the table-ref point (T-11-22/T-11-23) — and neither
claims planner/execution equivalence (FLINK-05/06, T-11-26). Each in strict
and editor modes:

| New snapshot file | Meaning |
|-------------------|---------|
| `flink-grammar.tvf-tumble-day.flink-2.3.0.{strict,editor}.json` | `SELECT window_start, window_end FROM TUMBLE(TABLE T1, DESCRIPTOR(rowtime), INTERVAL '1' DAY) GROUP BY window_start, window_end` — TUMBLE TVF + window output columns (WindowAggregateITCase.scala:228-263) |
| `flink-grammar.tvf-hop-four-arg.flink-2.3.0.{strict,editor}.json` | `HOP(TABLE T1, DESCRIPTOR(rowtime), INTERVAL '30' SECONDS, INTERVAL '15' SECONDS)` — four-argument slide+size |
| `flink-grammar.tvf-cumulate.flink-2.3.0.{strict,editor}.json` | `CUMULATE(TABLE T1, DESCRIPTOR(rowtime), INTERVAL '1' MINUTE, INTERVAL '1' HOUR)` — no keyword token (A2) |
| `flink-grammar.tvf-session.flink-2.3.0.{strict,editor}.json` | `SESSION(TABLE T1, DESCRIPTOR(rowtime), INTERVAL '1' HOUR)` — non-reserved (Parser.tdd:509) |
| `flink-grammar.tvf-table-wrapper.flink-2.3.0.{strict,editor}.json` | `FROM TABLE(TUMBLE(TABLE T1, DESCRIPTOR(rowtime), INTERVAL '3' SECOND))` — explicit wrapper (MatchRecognizeTest.scala:141-148) |
| `flink-grammar.tvf-offset-interval.flink-2.3.0.{strict,editor}.json` | `TUMBLE(..., INTERVAL '1' DAY, INTERVAL '-8' HOUR)` — negative offset known-limitation |
| `flink-grammar.tvf-named-arg.flink-2.3.0.{strict,editor}.json` | `TUMBLE(data => TABLE T1, timecol => DESCRIPTOR(rowtime), size => INTERVAL '1' DAY)` — named args (Parser.jj:8794) |
| `flink-grammar.tvf-missing-table.flink-2.3.0.{strict,editor}.json` | `TUMBLE(DESCRIPTOR(rowtime), INTERVAL '1' DAY)` — localized 002 (first arg not TABLE) |
| `flink-grammar.tvf-missing-descriptor-size.flink-2.3.0.{strict,editor}.json` | `TUMBLE(TABLE T1)` — localized 002 (too short) |
| `flink-grammar.tvf-incomplete-interval.flink-2.3.0.{strict,editor}.json` | `TUMBLE(TABLE T1, DESCRIPTOR(rowtime), INTERVAL)` — bounded Missing, lossless |
| `flink-grammar.tvf-recovery.flink-2.3.0.{strict,editor}.json` | unclosed TVF + `; SELECT 2` — trailing SELECT its own statement |

The TVF-under-Doris negative-gate assertion is in `parity/flink_grammar_test.mbt`
(`flink_grammar_tvf_is_dialect_gated`): the same TVF input is valid under
flink-2.3.0 and FATHOM-PARSE-009 under doris-4.x — no double-valid (Pitfall 2).

Wave 4 (11-04) then mints the FLINK-06 MATCH_RECOGNIZE fixtures (Task 2) —
the syntax-level nested sub-language (MatchRecognize, Parser.jj:3062-3346 /
Parser-calcite-1.36.0.jj:3020). PATTERN (anchors/ALTER/concatenation/
quantifiers), DEFINE, MEASURES (MATCH_NUMBER()/MATCH_ROWTIME()/MATCH_PROCTIME()
as ordinary calls), rows-per-match, AFTER MATCH SKIP, WITHIN INTERVAL are
fully implemented; SUBSET/PERMUTE/{- -} parse structurally and are classified
known-limitation (RESEARCH §8.2). No pattern-variable column-scope/type
validation (Pitfall 6, FLINK-06 — an undeclared variable is never rejected).
Each in strict and editor modes:

| New snapshot file | Meaning |
|-------------------|---------|
| `flink-grammar.match-recognize-full.flink-2.3.0.{strict,editor}.json` | `FROM Ticker MATCH_RECOGNIZE (PARTITION BY symbol ORDER BY ts MEASURES MATCH_NUMBER() AS n, A.price AS p ONE ROW PER MATCH AFTER MATCH SKIP TO NEXT ROW PATTERN (A B+ C{2,3}?) DEFINE A AS A.price > 0) AS T` (MatchRecognizeTest.scala:60-163) |
| `flink-grammar.match-recognize-anchors.flink-2.3.0.{strict,editor}.json` | `PATTERN (^ A $)` strict-start/end anchors |
| `flink-grammar.match-recognize-within-interval.flink-2.3.0.{strict,editor}.json` | `PATTERN (A) WITHIN INTERVAL '1' MINUTE` |
| `flink-grammar.match-recognize-all-rows.flink-2.3.0.{strict,editor}.json` | `ALL ROWS PER MATCH AFTER MATCH SKIP TO FIRST A` |
| `flink-grammar.match-recognize-measures-time.flink-2.3.0.{strict,editor}.json` | `MEASURES MATCH_ROWTIME() AS rt, MATCH_PROCTIME() AS pt` |
| `flink-grammar.match-recognize-skip-last.flink-2.3.0.{strict,editor}.json` | `AFTER MATCH SKIP PAST LAST ROW` |
| `flink-grammar.match-recognize-subset.flink-2.3.0.{strict,editor}.json` | `SUBSET U = (A, B)` — known-limitation (structural) |
| `flink-grammar.match-recognize-permute.flink-2.3.0.{strict,editor}.json` | `PATTERN (PERMUTE(A, B))` — known-limitation (structural) |
| `flink-grammar.match-recognize-exclude.flink-2.3.0.{strict,editor}.json` | `PATTERN ({- A -} B)` — PatternExclude known-limitation |
| `flink-grammar.match-recognize-empty-pattern.flink-2.3.0.{strict,editor}.json` | `PATTERN ()` — localized 002 (empty pattern) |
| `flink-grammar.match-recognize-missing-define-expr.flink-2.3.0.{strict,editor}.json` | `DEFINE A AS` — localized 002 (missing expr) |
| `flink-grammar.match-recognize-missing-define.flink-2.3.0.{strict,editor}.json` | `PATTERN (A)` — localized 002 (missing DEFINE) |
| `flink-grammar.match-recognize-incomplete.flink-2.3.0.{strict,editor}.json` | `MATCH_RECOGNIZE (PATTERN (A` — bounded Missing, lossless |
| `flink-grammar.match-recognize-recovery.flink-2.3.0.{strict,editor}.json` | unclosed MATCH_RECOGNIZE + `; SELECT 2` — trailing SELECT its own statement (T-11-24) |

The MATCH_RECOGNIZE-under-Doris negative-gate assertions are in
`parity/flink_grammar_test.mbt` (`flink_grammar_match_recognize_is_dialect_gated`):
valid under flink-2.3.0, FATHOM-PARSE-009 under doris-4.x — no double-valid
(Pitfall 2); `flink_grammar_match_recognize_undeclared_variable_is_accepted`
freezes the no-column-scope-validation behavior (Pitfall 6).

**Rule 1 fix (Task 3):** `scripts/extract_flink_grammar.py` `validate_manifest`
accepted only `Parser-calcite-{v}.jj:{line}` grammar_path rows, so the 11-02/
11-03 rows that legitimately reference `parserImpls.ftl:{line}` /
`Parser.tdd:{line}` / `D-04 gate:` provenance (D-05 — the pinned release's own
codegen templates and the in-repo dialect-gate) failed the validator. The
validator now verifies Parser-calcite rows against the pinned files and accepts
the template/gate provenance sources the manifest records (13 production refs +
2 Calcite-base reserved rows + 97 manifest rows verified; exit 0).

The fixtures live under `parity/fixtures/flink-grammar/` with a provenance
`manifest.tsv` recording the pinned release archive (url/sha512/tag/commit)
and the grammar production line references (RESEARCH §5, D-05 — never
folklore).

## 4. flink-lexical snapshot re-generation (D-06, registered)

The Phase 10 flink-lexical group froze the FATHOM-PARSE-008 not-implemented
route for the flink rows. Phase 11 replaces that route with the real grammar,
so the flink-side flink-lexical snapshots that carried 008 are re-generated to
the real-grammar expectations in the same approved-change. The Doris-side rows
of the flink-lexical group are byte-identical (Doris unchanged):

| Changed file group | Meaning |
|--------------------|---------|
| `flink-lexical.hash-comment.flink-2.3.0.{strict,editor}.json` | `a # comment` now routes to FATHOM-PARSE-007 (unsupported statement) + FATHOM-PARSE-003 (`#` lexical error) — no 008 |
| `flink-lexical.double-quote.flink-2.3.0.{strict,editor}.json` | `SELECT "a" FROM t` now parses to a select node with a FATHOM-PARSE-002 expression error on the DOUBLE_QUOTE symbol — no 008 |
| `flink-lexical.slash-comment.flink-2.3.0.{strict,editor}.json` | `SELECT a // comment` is now valid=true (real SELECT + SINGLE_LINE_COMMENT trivia) — no 008 |
| `flink-lexical.e-literal.flink-2.3.0.{strict,editor}.json` / `.flink-2.1.3.` / `.flink-1.20.5.` | E-literal SELECT rows now parse to real select nodes (2.3.0/2.1.3 valid; 1.20.5 has the E-identifier + string error) — no 008 |
| `flink-lexical.backtick-escape.flink-2.3.0.{strict,editor}.json` | `` SELECT `a``b` `` is now valid=true (BTID quoted identifier) — no 008 |
| `flink-lexical.unknown-profile.flink-4x.{strict,editor}.json` | UNCHANGED — the FATHOM-SCHEMA-003 selection rejection envelope never reaches the parser |

## 6. Doris 213-snapshot zero-drift confirmation

The Doris 213 baseline snapshots are byte-identical after every Phase 11 wave.
Any shared parser/CST change is re-run against `moon test --package parity`
(no `--update`) BEFORE landing; `git diff --name-only -- parity/__snapshot__`
shows only `flink-grammar.*` and the registered `flink-lexical.*` re-generation
after the approved `--update`, never a doris-named file.

## 7. MERGE-INTO under Flink — [ASSUMED] A1 fixture outcome (11-02)

The FLINK-02 MERGE probe ([ASSUMED] A1) is resolved by fixture: `MERGE INTO t
USING s ...` under flink-2.3.0 routes to the Flink dispatch's unsupported path
(FATHOM-PARSE-007, source-backed Error node) — no `parse_flink_merge` arm is
added in 11-02. Calcite base has a SqlMerge production
(Parser-calcite-1.36.0.jj:1837) but Flink's planner does not support MERGE; a
later plan may add `parse_flink_merge` if the pinned grammar's syntactic
acceptance needs freezing.

## 8. Phase 11 code-review-fix snapshot re-freeze (review 2026-08-09)

The 11-REVIEW.md fix pass narrows/extends Flink grammar behavior and rewrites
one fixture to standard clause order. The only frozen snapshot bytes that
change are the `match-recognize-subset` goldens, whose fixture SQL is rewritten
from the non-standard pre-PATTERN `SUBSET ... PATTERN ...` position to the
standard `PATTERN ... SUBSET ... DEFINE` order (Parser.jj:3182). All other
gates narrowed in the fix pass (WATERMARK FOR-only, CONSTRAINT form-only,
INTERVAL value-only; ROW types; WITH [LOCAL] TIME ZONE; AT TIME ZONE; fixed
MATCH_RECOGNIZE pre-PATTERN clause order) have no existing snapshot coverage —
the existing flink-grammar and Doris 213 snapshots are byte-identical after the
fixes. Verified by `moon test --target native --package parity` (no `--update`)
failing ONLY on the two `match-recognize-subset` snapshots, then passing after
the single approved `--update` re-freeze.

| Changed snapshot file | Meaning |
|-----------------------|---------|
| `flink-grammar.match-recognize-subset.flink-2.3.0.{strict,editor}.json` | Fixture rewritten to standard clause order `PATTERN (A B) SUBSET U = (A, B) DEFINE ...` (MJ-02); snapshot re-frozen |

Machine-readable patterns (baseline_diff.py `--approve`):

```
field: dialect-gate
code: FATHOM-PARSE-009
```
