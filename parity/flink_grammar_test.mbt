/// D-05 flink-grammar snapshot group (Phase 11 wave 1, 11-01): an independent
/// namespace under parity/__snapshot__/ that freezes the FLINK-02 core-query
/// surface — SELECT/CTE/JOIN/aggregation plus the Calcite set-operation
/// mechanism (UNION/INTERSECT/EXCEPT + ALL/DISTINCT, CompoundQuery via
/// QueryOrExpr, Parser-calcite-1.36.0.jj:3395) — in strict and editor modes.
/// Every positive and recovery fixture asserts byte-exact lossless replay
/// (print_lossless(parse(x)) == x, CST-01).
///
/// The group is an INDEPENDENT namespace (Pitfall 7): filenames are
/// `flink-grammar.{fixture}.flink-2.3.0.{strict,editor}.json` and never overlap
/// the Doris 213-snapshot baseline or the flink-lexical group.
///
/// Generation: `moon test --update --package parity` after the approved-changes
/// register entry is committed (D-08 single-use approval path). CI runs
/// `moon test --package parity` WITHOUT --update so any byte drift fails.
///
/// Provenance: parity/fixtures/flink-grammar/manifest.tsv records the pinned
/// release archive (url/sha512/tag/commit) and the grammar production line
/// references (RESEARCH §5, D-05 — never folklore); scripts/
/// extract_flink_grammar.py validates the line references against the pinned
/// Parser-calcite files.

pub(all) struct FlinkGrammarFixture {
  pub fixture_id : String
  pub profile : String
  pub category : String
  pub raw : Bytes
}

/// FLINK-02 core-query fixtures (positive + incomplete-recovery). The
/// provenance manifest rows carry the production line refs
/// (Parser-calcite-1.36.0.jj:3395 QueryOrExpr / :3485 WithList / :1322
/// SqlSelect); scripts/extract_flink_grammar.py validates them.
let flink_grammar_fixtures : Array[FlinkGrammarFixture] = [
  {
    fixture_id: "select-cte-join-agg",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"WITH o AS (SELECT user_id, amount FROM t1) SELECT u.name, SUM(o.amount) AS total FROM o JOIN users u ON o.user_id = u.id GROUP BY u.name",
  },
  {
    fixture_id: "select-incomplete",
    profile: "flink-2.3.0",
    category: "incomplete",
    raw: b"SELECT a, b FROM t WHERE",
  },
  {
    fixture_id: "set-union-all",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"SELECT a FROM t1 UNION ALL SELECT a FROM t2",
  },
  {
    fixture_id: "set-intersect",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"SELECT a FROM t1 INTERSECT SELECT a FROM t2",
  },
  {
    fixture_id: "set-except",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"SELECT a FROM t1 EXCEPT SELECT a FROM t2",
  },
  {
    fixture_id: "set-intersect-all",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"SELECT a FROM t1 INTERSECT ALL SELECT a FROM t2",
  },
  {
    fixture_id: "set-except-all",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"SELECT a FROM t1 EXCEPT ALL SELECT a FROM t2",
  },
  // ---- FLINK-02 DML (11-02): RichSqlInsert (parserImpls.ftl:2306-2379),
  // SqlUpdate (Parser-calcite-1.36.0.jj:1794-1832), SqlDelete (:1768-1789).
  {
    fixture_id: "insert-into-select",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"INSERT INTO t SELECT * FROM s",
  },
  {
    fixture_id: "insert-overwrite-partition",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"INSERT OVERWRITE t PARTITION (dt='1') SELECT * FROM s",
  },
  {
    fixture_id: "upsert-into-values",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"UPSERT INTO t VALUES (1, 2)",
  },
  {
    fixture_id: "insert-columns-on-conflict",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"INSERT INTO t (a, b) VALUES (1, 2) ON CONFLICT DO NOTHING",
  },
  {
    fixture_id: "insert-distributed",
    profile: "flink-2.3.0",
    category: "negative",
    raw: b"INSERT INTO t DISTRIBUTED BY HASH(k) BUCKETS 10",
  },
  {
    fixture_id: "insert-incomplete",
    profile: "flink-2.3.0",
    category: "incomplete",
    raw: b"INSERT INTO t (a,",
  },
  {
    fixture_id: "insert-recovery",
    profile: "flink-2.3.0",
    category: "recovery",
    raw: b"INSERT INTO t (a, b; SELECT 2",
  },
  {
    fixture_id: "update-where",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"UPDATE t SET a = 1 WHERE id = 5",
  },
  {
    fixture_id: "delete-where",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"DELETE FROM t WHERE id = 5",
  },
  {
    fixture_id: "update-comment",
    profile: "flink-2.3.0",
    category: "negative",
    raw: b"UPDATE t SET a = 1 COMMENT 'x'",
  },
  {
    fixture_id: "delete-partition",
    profile: "flink-2.3.0",
    category: "negative",
    raw: b"DELETE FROM t PARTITION (p1)",
  },
  {
    fixture_id: "update-incomplete",
    profile: "flink-2.3.0",
    category: "incomplete",
    raw: b"UPDATE t SET",
  },
  {
    fixture_id: "delete-incomplete",
    profile: "flink-2.3.0",
    category: "incomplete",
    raw: b"DELETE FROM t WHERE",
  },
  {
    fixture_id: "update-recovery",
    profile: "flink-2.3.0",
    category: "recovery",
    raw: b"UPDATE t SET a = 1 WHERE id = 5; SELECT 1",
  },
  // ---- FLINK-02 auxiliary statements (11-02): EXPLAIN/SHOW/DESCRIBE/ANALYZE
  // + USE/SET/RESET + expression/type breadth.
  {
    fixture_id: "explain-plan-for",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"EXPLAIN PLAN FOR SELECT * FROM t",
  },
  {
    fixture_id: "show-tables-from-like",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"SHOW TABLES FROM db1 LIKE '%'",
  },
  {
    fixture_id: "show-catalogs",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"SHOW CATALOGS",
  },
  {
    fixture_id: "show-negative",
    profile: "flink-2.3.0",
    category: "negative",
    raw: b"SHOW TABLES db1",
  },
  {
    fixture_id: "describe-table",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"DESCRIBE TABLE t",
  },
  {
    fixture_id: "describe-extended-database",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"DESCRIBE EXTENDED DATABASE db",
  },
  {
    fixture_id: "analyze-table",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"ANALYZE TABLE t",
  },
  {
    fixture_id: "analyze-buckets",
    profile: "flink-2.3.0",
    category: "negative",
    raw: b"ANALYZE TABLE t BUCKETS 10",
  },
  {
    fixture_id: "use-catalog",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"USE CATALOG c",
  },
  {
    fixture_id: "set-option",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"SET 'k' = 'v'",
  },
  {
    fixture_id: "reset-option",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"RESET 'k'",
  },
  {
    fixture_id: "named-arg",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"SELECT f(a => 1)",
  },
  {
    fixture_id: "cast-timestamp-ltz",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"SELECT CAST(x AS TIMESTAMP_LTZ(3))",
  },
  {
    fixture_id: "cast-map-type",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"SELECT CAST(a AS MAP<STRING, INT>)",
  },
  {
    fixture_id: "row-ctor",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"SELECT ROW(1, 'a')",
  },
  {
    fixture_id: "array-ctor",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"SELECT ARRAY[1, 2]",
  },
  // ---- FLINK-03 Catalog/DATABASE DDL (11-03, wave 3): SqlCreateCatalog
  // (parserImpls.ftl:142-188), SqlCreateDatabase (:301-372), SqlDropCatalog
  // (:173-188), SqlDropDatabase (:351-372), SqlAlterCatalog (Parser.tdd:659),
  // SqlAlterDatabase (Parser.tdd:664).
  {
    fixture_id: "create-catalog",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"CREATE CATALOG c WITH ('type'='generic_in_memory')",
  },
  {
    fixture_id: "create-database",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"CREATE DATABASE db COMMENT 'sales db' WITH ('k'='v')",
  },
  {
    fixture_id: "drop-catalog",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"DROP CATALOG IF EXISTS c",
  },
  {
    fixture_id: "drop-database",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"DROP DATABASE db CASCADE",
  },
  {
    fixture_id: "alter-catalog",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"ALTER CATALOG c SET ('k'='v')",
  },
  {
    fixture_id: "create-catalog-incomplete",
    profile: "flink-2.3.0",
    category: "incomplete",
    raw: b"CREATE CATALOG c WITH (",
  },
  {
    fixture_id: "drop-database-incomplete",
    profile: "flink-2.3.0",
    category: "incomplete",
    raw: b"DROP DATABASE",
  },
  // ---- FLINK-03 VIEW + FUNCTION DDL (11-03, wave 3): SqlCreateView
  // (parserImpls.ftl:2414-2439), SqlCreateFunction (:390-480), SqlDropView/
  // SqlDropFunction, SqlAlterView (Parser.tdd:692), SqlAlterFunction
  // (Parser.tdd:665).
  {
    fixture_id: "create-view",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"CREATE VIEW v AS SELECT * FROM t",
  },
  {
    fixture_id: "create-view-field-list",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"CREATE VIEW v (a, b) AS SELECT a, b FROM t",
  },
  {
    fixture_id: "create-function",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"CREATE TEMPORARY FUNCTION f AS 'com.example.UDF' LANGUAGE JAVA",
  },
  {
    fixture_id: "create-function-python",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"CREATE TEMPORARY SYSTEM FUNCTION f AS 'x' LANGUAGE PYTHON",
  },
  {
    fixture_id: "drop-view",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"DROP VIEW IF EXISTS v",
  },
  {
    fixture_id: "drop-function",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"DROP FUNCTION IF EXISTS f",
  },
  {
    fixture_id: "alter-view-rename",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"ALTER VIEW v RENAME TO v2",
  },
  {
    fixture_id: "alter-view-as",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"ALTER VIEW v AS SELECT 1",
  },
  {
    fixture_id: "alter-function",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"ALTER FUNCTION f AS 'com.example.UDF' LANGUAGE SCALA",
  },
  {
    fixture_id: "create-view-incomplete",
    profile: "flink-2.3.0",
    category: "incomplete",
    raw: b"CREATE VIEW v AS",
  },
  {
    fixture_id: "create-function-incomplete",
    profile: "flink-2.3.0",
    category: "incomplete",
    raw: b"CREATE FUNCTION f AS",
  },
  {
    fixture_id: "view-recovery",
    profile: "flink-2.3.0",
    category: "recovery",
    raw: b"CREATE VIEW v AS SELECT * FROM t; SELECT 2",
  },
  // ---- FLINK-04 CREATE TABLE column body (11-03, wave 3): TableColumn
  // four-way dispatch (parserImpls.ftl:1103-1145), Watermark (:1121-1140),
  // UniqueSpec (:1432-1504), ComputedColumn (:1150-1176), MetadataColumn
  // (:1176-1210), TypedColumn (:1146-1130).
  {
    fixture_id: "create-table-columns",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"CREATE TABLE t (log_ts TIMESTAMP_LTZ(3), proc AS PROCTIME(), x STRING METADATA FROM 'x' VIRTUAL, PRIMARY KEY (id) NOT ENFORCED, WATERMARK FOR log_ts AS log_ts - INTERVAL '5' SECOND)",
  },
  {
    fixture_id: "create-table-typed-column",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"CREATE TABLE t (a INT, b STRING)",
  },
  {
    fixture_id: "create-table-watermark-second",
    profile: "flink-2.3.0",
    category: "negative",
    raw: b"CREATE TABLE t (a INT, WATERMARK FOR a AS a, WATERMARK FOR b AS b)",
  },
  {
    fixture_id: "create-table-pk-enforced",
    profile: "flink-2.3.0",
    category: "negative",
    raw: b"CREATE TABLE t (id INT, PRIMARY KEY (id) ENFORCED)",
  },
  {
    fixture_id: "create-table-trailing-comma",
    profile: "flink-2.3.0",
    category: "negative",
    raw: b"CREATE TABLE t (a INT,)",
  },
  {
    fixture_id: "create-table-incomplete-wm",
    profile: "flink-2.3.0",
    category: "incomplete",
    raw: b"CREATE TABLE t (WATERMARK FOR ts AS)",
  },
  {
    fixture_id: "create-table-incomplete-col",
    profile: "flink-2.3.0",
    category: "incomplete",
    raw: b"CREATE TABLE t (a INT, b",
  },
]

fn flink_grammar_fixture(id : String) -> FlinkGrammarFixture {
  for fixture in flink_grammar_fixtures {
    if fixture.fixture_id == id { return fixture }
  }
  panic()
}

fn flink_grammar_parse_json(id : String, mode : String) -> String {
  let fixture = flink_grammar_fixture(id)
  @utf8.decode_lossy(@binding.fathom_parse_v1(fixture.raw, "flink", fixture.profile, mode)[:])
}

/// CST-01 lossless replay: print_lossless(parse(x)) == x under the Flink
/// profile in the given mode — byte-exact for every positive and recovery
/// fixture (RESEARCH §6.4).
fn flink_grammar_lossless(id : String, mode : @parser.ParseMode) -> Bool {
  let fixture = flink_grammar_fixture(id)
  let source = match @source.SourceText::new(fixture.raw) {
    Ok(source) => source
    Err(_) => return false
  }
  let context : @dialect.DialectContext = {
    dialect: @dialect.Dialect::Flink,
    profile_id: fixture.profile,
    exact_release: fixture.profile,
    feature_introduction: "",
  }
  let parsed = @parser.parse(source, context, mode)
  @printer.print_lossless(parsed.root, source) == fixture.raw
}

fn flink_grammar_snapshot_test(t : @test.Test, content : String, filename : String) -> Unit raise SnapshotError {
  t.write(content)
  t.snapshot(filename=filename)
}

// ---------------------------------------------------------------------------
// select-cte-join-agg: the tracer SQL — CTE + JOIN + aggregation through the
// real Flink SELECT path (valid=true, no FATHOM-PARSE-008).
// ---------------------------------------------------------------------------
test "flink-grammar select-cte-join-agg flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar select-cte-join-agg flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("select-cte-join-agg", "strict"), "flink-grammar.select-cte-join-agg.flink-2.3.0.strict.json")
}

test "flink-grammar select-cte-join-agg flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar select-cte-join-agg flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("select-cte-join-agg", "editor"), "flink-grammar.select-cte-join-agg.flink-2.3.0.editor.json")
}

test "flink_grammar_select_cte_join_agg_lossless" {
  assert_true(flink_grammar_lossless("select-cte-join-agg", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("select-cte-join-agg", @parser.ParseMode::Editor))
}

// ---------------------------------------------------------------------------
// select-incomplete: incomplete SELECT recovery — bounded Missing/Error node,
// still round-trips byte-exactly (CST-01, D-03).
// ---------------------------------------------------------------------------
test "flink-grammar select-incomplete flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar select-incomplete flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("select-incomplete", "strict"), "flink-grammar.select-incomplete.flink-2.3.0.strict.json")
}

test "flink-grammar select-incomplete flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar select-incomplete flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("select-incomplete", "editor"), "flink-grammar.select-incomplete.flink-2.3.0.editor.json")
}

test "flink_grammar_select_incomplete_lossless" {
  assert_true(flink_grammar_lossless("select-incomplete", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("select-incomplete", @parser.ParseMode::Editor))
}

// ---------------------------------------------------------------------------
// set-union-all: CompoundQuery set operation, valid=true under flink-2.3.0.
// ---------------------------------------------------------------------------
test "flink-grammar set-union-all flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar set-union-all flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("set-union-all", "strict"), "flink-grammar.set-union-all.flink-2.3.0.strict.json")
}

test "flink-grammar set-union-all flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar set-union-all flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("set-union-all", "editor"), "flink-grammar.set-union-all.flink-2.3.0.editor.json")
}

test "flink_grammar_set_union_all_lossless" {
  assert_true(flink_grammar_lossless("set-union-all", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("set-union-all", @parser.ParseMode::Editor))
}

// ---------------------------------------------------------------------------
// set-intersect: INTERSECT set operation (shared CompoundQuery path).
// ---------------------------------------------------------------------------
test "flink-grammar set-intersect flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar set-intersect flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("set-intersect", "strict"), "flink-grammar.set-intersect.flink-2.3.0.strict.json")
}

test "flink-grammar set-intersect flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar set-intersect flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("set-intersect", "editor"), "flink-grammar.set-intersect.flink-2.3.0.editor.json")
}

test "flink_grammar_set_intersect_lossless" {
  assert_true(flink_grammar_lossless("set-intersect", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("set-intersect", @parser.ParseMode::Editor))
}

// ---------------------------------------------------------------------------
// set-except: EXCEPT set operation (shared CompoundQuery path; under Flink the
// EXCEPT projection-modifier arm is gated to Doris, so the set-op consumes it).
// ---------------------------------------------------------------------------
test "flink-grammar set-except flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar set-except flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("set-except", "strict"), "flink-grammar.set-except.flink-2.3.0.strict.json")
}

test "flink-grammar set-except flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar set-except flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("set-except", "editor"), "flink-grammar.set-except.flink-2.3.0.editor.json")
}

test "flink_grammar_set_except_lossless" {
  assert_true(flink_grammar_lossless("set-except", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("set-except", @parser.ParseMode::Editor))
}

// ---------------------------------------------------------------------------
// set-intersect-all / set-except-all: ALL variants where the pinned grammar
// supports them (INTERSECT ALL / EXCEPT ALL, CompoundQuery).
// ---------------------------------------------------------------------------
test "flink-grammar set-intersect-all flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar set-intersect-all flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("set-intersect-all", "strict"), "flink-grammar.set-intersect-all.flink-2.3.0.strict.json")
}

test "flink-grammar set-intersect-all flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar set-intersect-all flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("set-intersect-all", "editor"), "flink-grammar.set-intersect-all.flink-2.3.0.editor.json")
}

test "flink_grammar_set_intersect_all_lossless" {
  assert_true(flink_grammar_lossless("set-intersect-all", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("set-intersect-all", @parser.ParseMode::Editor))
}

test "flink-grammar set-except-all flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar set-except-all flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("set-except-all", "strict"), "flink-grammar.set-except-all.flink-2.3.0.strict.json")
}

test "flink-grammar set-except-all flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar set-except-all flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("set-except-all", "editor"), "flink-grammar.set-except-all.flink-2.3.0.editor.json")
}

test "flink_grammar_set_except_all_lossless" {
  assert_true(flink_grammar_lossless("set-except-all", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("set-except-all", @parser.ParseMode::Editor))
}

// ===========================================================================
// FLINK-02 DML + auxiliary fixtures (11-02, wave 2)
// ===========================================================================

/// Bidirectional dialect-gate helper (D-04): asserts the flink-2.3.0 strict
/// parse of `raw` contains `flink_code` (when non-empty) and the doris-4.x
/// strict parse contains `doris_code` (when non-empty). The named-arg and
/// negative fixtures use this to freeze the FATHOM-PARSE-009 / 007 gates.
fn flink_grammar_bidirectional(raw : Bytes, flink_code : String, doris_code : String) -> Bool {
  let flink = @utf8.decode_lossy(@binding.fathom_parse_v1(raw, "flink", "flink-2.3.0", "strict")[:])
  let doris = @utf8.decode_lossy(@binding.fathom_parse_v1(raw, "doris", "4.x", "strict")[:])
  (flink_code == "" || flink.contains(flink_code)) && (doris_code == "" || doris.contains(doris_code))
}

// ---------------------------------------------------------------------------
// insert-into-select: RichSqlInsert INTO + query source (valid=true).
// ---------------------------------------------------------------------------
test "flink-grammar insert-into-select flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar insert-into-select flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("insert-into-select", "strict"), "flink-grammar.insert-into-select.flink-2.3.0.strict.json")
}

test "flink-grammar insert-into-select flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar insert-into-select flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("insert-into-select", "editor"), "flink-grammar.insert-into-select.flink-2.3.0.editor.json")
}

test "flink_grammar_insert_into_select_lossless" {
  assert_true(flink_grammar_lossless("insert-into-select", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("insert-into-select", @parser.ParseMode::Editor))
}

// ---------------------------------------------------------------------------
// insert-overwrite-partition: INSERT OVERWRITE + PARTITION (dt='1') + query.
// ---------------------------------------------------------------------------
test "flink-grammar insert-overwrite-partition flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar insert-overwrite-partition flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("insert-overwrite-partition", "strict"), "flink-grammar.insert-overwrite-partition.flink-2.3.0.strict.json")
}

test "flink-grammar insert-overwrite-partition flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar insert-overwrite-partition flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("insert-overwrite-partition", "editor"), "flink-grammar.insert-overwrite-partition.flink-2.3.0.editor.json")
}

test "flink_grammar_insert_overwrite_partition_lossless" {
  assert_true(flink_grammar_lossless("insert-overwrite-partition", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("insert-overwrite-partition", @parser.ParseMode::Editor))
}

// ---------------------------------------------------------------------------
// upsert-into-values: UPSERT INTO + VALUES source (Flink-only UPSERT).
// ---------------------------------------------------------------------------
test "flink-grammar upsert-into-values flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar upsert-into-values flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("upsert-into-values", "strict"), "flink-grammar.upsert-into-values.flink-2.3.0.strict.json")
}

test "flink-grammar upsert-into-values flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar upsert-into-values flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("upsert-into-values", "editor"), "flink-grammar.upsert-into-values.flink-2.3.0.editor.json")
}

test "flink_grammar_upsert_into_values_lossless" {
  assert_true(flink_grammar_lossless("upsert-into-values", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("upsert-into-values", @parser.ParseMode::Editor))
}

// UPSERT is a Flink-only INSERT form (RichSqlInsert); under Doris it routes to
// the unsupported-statement path (FATHOM-PARSE-007) — never silently accepted.
test "flink_grammar_upsert_is_dialect_gated" {
  assert_true(flink_grammar_bidirectional(b"UPSERT INTO t VALUES (1, 2)", "\"valid\":true", "FATHOM-PARSE-007"))
}

// ---------------------------------------------------------------------------
// insert-columns-on-conflict: column list + VALUES + ON CONFLICT DO NOTHING.
// ---------------------------------------------------------------------------
test "flink-grammar insert-columns-on-conflict flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar insert-columns-on-conflict flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("insert-columns-on-conflict", "strict"), "flink-grammar.insert-columns-on-conflict.flink-2.3.0.strict.json")
}

test "flink-grammar insert-columns-on-conflict flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar insert-columns-on-conflict flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("insert-columns-on-conflict", "editor"), "flink-grammar.insert-columns-on-conflict.flink-2.3.0.editor.json")
}

test "flink_grammar_insert_columns_on_conflict_lossless" {
  assert_true(flink_grammar_lossless("insert-columns-on-conflict", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("insert-columns-on-conflict", @parser.ParseMode::Editor))
}

// ON CONFLICT DO is Flink-only; under Doris the trailing tail is rejected
// (never silently accepted).
test "flink_grammar_insert_on_conflict_is_dialect_gated" {
  assert_true(flink_grammar_bidirectional(b"INSERT INTO t (a, b) VALUES (1, 2) ON CONFLICT DO NOTHING", "\"valid\":true", "FATHOM-PARSE-001"))
}

// ---------------------------------------------------------------------------
// insert-distributed: Doris-only DISTRIBUTED ... BUCKETS under Flink → 009.
// ---------------------------------------------------------------------------
test "flink-grammar insert-distributed flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar insert-distributed flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("insert-distributed", "strict"), "flink-grammar.insert-distributed.flink-2.3.0.strict.json")
}

test "flink-grammar insert-distributed flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar insert-distributed flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("insert-distributed", "editor"), "flink-grammar.insert-distributed.flink-2.3.0.editor.json")
}

test "flink_grammar_insert_distributed_is_dialect_gated" {
  // The Doris distribution form is 009 under Flink; the same SQL under Doris
  // is rejected by the frozen baseline (never silently accepted).
  assert_true(flink_grammar_bidirectional(b"INSERT INTO t DISTRIBUTED BY HASH(k) BUCKETS 10", "FATHOM-PARSE-009", ""))
}

// ---------------------------------------------------------------------------
// insert-incomplete: unclosed column list — bounded Missing node + lossless.
// ---------------------------------------------------------------------------
test "flink-grammar insert-incomplete flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar insert-incomplete flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("insert-incomplete", "strict"), "flink-grammar.insert-incomplete.flink-2.3.0.strict.json")
}

test "flink-grammar insert-incomplete flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar insert-incomplete flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("insert-incomplete", "editor"), "flink-grammar.insert-incomplete.flink-2.3.0.editor.json")
}

test "flink_grammar_insert_incomplete_lossless" {
  assert_true(flink_grammar_lossless("insert-incomplete", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("insert-incomplete", @parser.ParseMode::Editor))
}

// ---------------------------------------------------------------------------
// insert-recovery: unclosed column list recovers at `;` so the trailing
// SELECT parses as its own statement (no cross-statement token swallowing).
// ---------------------------------------------------------------------------
test "flink-grammar insert-recovery flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar insert-recovery flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("insert-recovery", "strict"), "flink-grammar.insert-recovery.flink-2.3.0.strict.json")
}

test "flink-grammar insert-recovery flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar insert-recovery flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("insert-recovery", "editor"), "flink-grammar.insert-recovery.flink-2.3.0.editor.json")
}

test "flink_grammar_insert_recovery_lossless_and_independent_statements" {
  assert_true(flink_grammar_lossless("insert-recovery", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("insert-recovery", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"INSERT INTO t (a, b; SELECT 2", "flink", "flink-2.3.0", "strict")[:])
  // Two statement nodes: the incomplete INSERT and the independent SELECT.
  assert_true(strict.contains("\"kind\":\"insert\""))
  assert_true(strict.contains("\"kind\":\"select\""))
}

// ---------------------------------------------------------------------------
// update-where / delete-where: Flink-safe UPDATE/DELETE (valid=true).
// ---------------------------------------------------------------------------
test "flink-grammar update-where flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar update-where flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("update-where", "strict"), "flink-grammar.update-where.flink-2.3.0.strict.json")
}

test "flink-grammar update-where flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar update-where flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("update-where", "editor"), "flink-grammar.update-where.flink-2.3.0.editor.json")
}

test "flink_grammar_update_where_lossless" {
  assert_true(flink_grammar_lossless("update-where", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("update-where", @parser.ParseMode::Editor))
}

test "flink-grammar delete-where flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar delete-where flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("delete-where", "strict"), "flink-grammar.delete-where.flink-2.3.0.strict.json")
}

test "flink-grammar delete-where flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar delete-where flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("delete-where", "editor"), "flink-grammar.delete-where.flink-2.3.0.editor.json")
}

test "flink_grammar_delete_where_lossless" {
  assert_true(flink_grammar_lossless("delete-where", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("delete-where", @parser.ParseMode::Editor))
}

// ---------------------------------------------------------------------------
// update-comment / delete-partition: Doris-only clauses → FATHOM-PARSE-009.
// ---------------------------------------------------------------------------
test "flink-grammar update-comment flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar update-comment flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("update-comment", "strict"), "flink-grammar.update-comment.flink-2.3.0.strict.json")
}

test "flink-grammar update-comment flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar update-comment flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("update-comment", "editor"), "flink-grammar.update-comment.flink-2.3.0.editor.json")
}

test "flink_grammar_update_comment_is_dialect_gated" {
  assert_true(flink_grammar_bidirectional(b"UPDATE t SET a = 1 COMMENT 'x'", "FATHOM-PARSE-009", ""))
}

test "flink-grammar delete-partition flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar delete-partition flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("delete-partition", "strict"), "flink-grammar.delete-partition.flink-2.3.0.strict.json")
}

test "flink-grammar delete-partition flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar delete-partition flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("delete-partition", "editor"), "flink-grammar.delete-partition.flink-2.3.0.editor.json")
}

test "flink_grammar_delete_partition_is_dialect_gated" {
  assert_true(flink_grammar_bidirectional(b"DELETE FROM t PARTITION (p1)", "FATHOM-PARSE-009", ""))
}

// ---------------------------------------------------------------------------
// update-incomplete / delete-incomplete / update-recovery.
// ---------------------------------------------------------------------------
test "flink-grammar update-incomplete flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar update-incomplete flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("update-incomplete", "strict"), "flink-grammar.update-incomplete.flink-2.3.0.strict.json")
}

test "flink-grammar update-incomplete flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar update-incomplete flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("update-incomplete", "editor"), "flink-grammar.update-incomplete.flink-2.3.0.editor.json")
}

test "flink_grammar_update_incomplete_lossless" {
  assert_true(flink_grammar_lossless("update-incomplete", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("update-incomplete", @parser.ParseMode::Editor))
}

test "flink-grammar delete-incomplete flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar delete-incomplete flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("delete-incomplete", "strict"), "flink-grammar.delete-incomplete.flink-2.3.0.strict.json")
}

test "flink-grammar delete-incomplete flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar delete-incomplete flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("delete-incomplete", "editor"), "flink-grammar.delete-incomplete.flink-2.3.0.editor.json")
}

test "flink_grammar_delete_incomplete_lossless" {
  assert_true(flink_grammar_lossless("delete-incomplete", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("delete-incomplete", @parser.ParseMode::Editor))
}

test "flink-grammar update-recovery flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar update-recovery flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("update-recovery", "strict"), "flink-grammar.update-recovery.flink-2.3.0.strict.json")
}

test "flink-grammar update-recovery flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar update-recovery flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("update-recovery", "editor"), "flink-grammar.update-recovery.flink-2.3.0.editor.json")
}

test "flink_grammar_update_recovery_lossless_and_independent_statements" {
  assert_true(flink_grammar_lossless("update-recovery", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("update-recovery", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"UPDATE t SET a = 1 WHERE id = 5; SELECT 1", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"kind\":\"update\""))
  assert_true(strict.contains("\"kind\":\"select\""))
}

// ---------------------------------------------------------------------------
// explain-plan-for: EXPLAIN PLAN FOR query → explain_statement.
// ---------------------------------------------------------------------------
test "flink-grammar explain-plan-for flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar explain-plan-for flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("explain-plan-for", "strict"), "flink-grammar.explain-plan-for.flink-2.3.0.strict.json")
}

test "flink-grammar explain-plan-for flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar explain-plan-for flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("explain-plan-for", "editor"), "flink-grammar.explain-plan-for.flink-2.3.0.editor.json")
}

test "flink_grammar_explain_plan_for_lossless" {
  assert_true(flink_grammar_lossless("explain-plan-for", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("explain-plan-for", @parser.ParseMode::Editor))
}

// ---------------------------------------------------------------------------
// show-tables-from-like / show-catalogs (SqlShow* family).
// ---------------------------------------------------------------------------
test "flink-grammar show-tables-from-like flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar show-tables-from-like flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("show-tables-from-like", "strict"), "flink-grammar.show-tables-from-like.flink-2.3.0.strict.json")
}

test "flink-grammar show-tables-from-like flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar show-tables-from-like flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("show-tables-from-like", "editor"), "flink-grammar.show-tables-from-like.flink-2.3.0.editor.json")
}

test "flink_grammar_show_tables_from_like_lossless" {
  assert_true(flink_grammar_lossless("show-tables-from-like", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("show-tables-from-like", @parser.ParseMode::Editor))
}

test "flink-grammar show-catalogs flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar show-catalogs flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("show-catalogs", "strict"), "flink-grammar.show-catalogs.flink-2.3.0.strict.json")
}

test "flink-grammar show-catalogs flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar show-catalogs flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("show-catalogs", "editor"), "flink-grammar.show-catalogs.flink-2.3.0.editor.json")
}

test "flink_grammar_show_catalogs_lossless" {
  assert_true(flink_grammar_lossless("show-catalogs", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("show-catalogs", @parser.ParseMode::Editor))
}

// The SHOW family is whole-statement unsupported under Doris → FATHOM-PARSE-007.
test "flink_grammar_show_is_unsupported_under_doris" {
  assert_true(flink_grammar_bidirectional(b"SHOW TABLES FROM db1 LIKE '%'", "\"valid\":true", "FATHOM-PARSE-007"))
}

// ---------------------------------------------------------------------------
// show-negative: SHOW TABLES db1 (missing FROM/IN) — localized error at the
// offending token.
// ---------------------------------------------------------------------------
test "flink-grammar show-negative flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar show-negative flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("show-negative", "strict"), "flink-grammar.show-negative.flink-2.3.0.strict.json")
}

test "flink-grammar show-negative flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar show-negative flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("show-negative", "editor"), "flink-grammar.show-negative.flink-2.3.0.editor.json")
}

test "flink_grammar_show_negative_errors_at_offending_token" {
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"SHOW TABLES db1", "flink", "flink-2.3.0", "strict")[:])
  // The localized error spans the offending `db1` token (bytes 12-15).
  assert_true(strict.contains("FATHOM-PARSE-002"))
  assert_true(strict.contains("\"start_byte\":12,\"end_byte\":15"))
}

// ---------------------------------------------------------------------------
// describe-table / describe-extended-database (SqlRichDescribeTable).
// ---------------------------------------------------------------------------
test "flink-grammar describe-table flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar describe-table flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("describe-table", "strict"), "flink-grammar.describe-table.flink-2.3.0.strict.json")
}

test "flink-grammar describe-table flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar describe-table flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("describe-table", "editor"), "flink-grammar.describe-table.flink-2.3.0.editor.json")
}

test "flink_grammar_describe_table_lossless" {
  assert_true(flink_grammar_lossless("describe-table", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("describe-table", @parser.ParseMode::Editor))
}

test "flink-grammar describe-extended-database flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar describe-extended-database flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("describe-extended-database", "strict"), "flink-grammar.describe-extended-database.flink-2.3.0.strict.json")
}

test "flink-grammar describe-extended-database flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar describe-extended-database flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("describe-extended-database", "editor"), "flink-grammar.describe-extended-database.flink-2.3.0.editor.json")
}

test "flink_grammar_describe_extended_database_lossless" {
  assert_true(flink_grammar_lossless("describe-extended-database", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("describe-extended-database", @parser.ParseMode::Editor))
}

test "flink_grammar_describe_is_unsupported_under_doris" {
  assert_true(flink_grammar_bidirectional(b"DESCRIBE TABLE t", "\"valid\":true", "FATHOM-PARSE-007"))
}

// ---------------------------------------------------------------------------
// analyze-table (positive) / analyze-buckets (Doris-only BUCKETS → 009).
// ---------------------------------------------------------------------------
test "flink-grammar analyze-table flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar analyze-table flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("analyze-table", "strict"), "flink-grammar.analyze-table.flink-2.3.0.strict.json")
}

test "flink-grammar analyze-table flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar analyze-table flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("analyze-table", "editor"), "flink-grammar.analyze-table.flink-2.3.0.editor.json")
}

test "flink_grammar_analyze_table_lossless" {
  assert_true(flink_grammar_lossless("analyze-table", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("analyze-table", @parser.ParseMode::Editor))
}

test "flink-grammar analyze-buckets flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar analyze-buckets flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("analyze-buckets", "strict"), "flink-grammar.analyze-buckets.flink-2.3.0.strict.json")
}

test "flink-grammar analyze-buckets flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar analyze-buckets flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("analyze-buckets", "editor"), "flink-grammar.analyze-buckets.flink-2.3.0.editor.json")
}

test "flink_grammar_analyze_buckets_is_dialect_gated" {
  assert_true(flink_grammar_bidirectional(b"ANALYZE TABLE t BUCKETS 10", "FATHOM-PARSE-009", ""))
}

test "flink_grammar_analyze_is_unsupported_under_doris" {
  assert_true(flink_grammar_bidirectional(b"ANALYZE TABLE t", "\"valid\":true", "FATHOM-PARSE-007"))
}

// ---------------------------------------------------------------------------
// use-catalog / set-option / reset-option.
// ---------------------------------------------------------------------------
test "flink-grammar use-catalog flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar use-catalog flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("use-catalog", "strict"), "flink-grammar.use-catalog.flink-2.3.0.strict.json")
}

test "flink-grammar use-catalog flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar use-catalog flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("use-catalog", "editor"), "flink-grammar.use-catalog.flink-2.3.0.editor.json")
}

test "flink_grammar_use_catalog_lossless" {
  assert_true(flink_grammar_lossless("use-catalog", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("use-catalog", @parser.ParseMode::Editor))
}

test "flink-grammar set-option flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar set-option flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("set-option", "strict"), "flink-grammar.set-option.flink-2.3.0.strict.json")
}

test "flink-grammar set-option flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar set-option flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("set-option", "editor"), "flink-grammar.set-option.flink-2.3.0.editor.json")
}

test "flink_grammar_set_option_lossless" {
  assert_true(flink_grammar_lossless("set-option", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("set-option", @parser.ParseMode::Editor))
}

test "flink-grammar reset-option flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar reset-option flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("reset-option", "strict"), "flink-grammar.reset-option.flink-2.3.0.strict.json")
}

test "flink-grammar reset-option flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar reset-option flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("reset-option", "editor"), "flink-grammar.reset-option.flink-2.3.0.editor.json")
}

test "flink_grammar_reset_option_lossless" {
  assert_true(flink_grammar_lossless("reset-option", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("reset-option", @parser.ParseMode::Editor))
}

// ---------------------------------------------------------------------------
// named-arg: Flink NAMED_ARGUMENT_ASSIGNMENT `=>` (Parser.jj:8794) — valid
// under flink-2.3.0, FATHOM-PARSE-009 under Doris.
// ---------------------------------------------------------------------------
test "flink-grammar named-arg flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar named-arg flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("named-arg", "strict"), "flink-grammar.named-arg.flink-2.3.0.strict.json")
}

test "flink-grammar named-arg flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar named-arg flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("named-arg", "editor"), "flink-grammar.named-arg.flink-2.3.0.editor.json")
}

test "flink_grammar_named_arg_lossless" {
  assert_true(flink_grammar_lossless("named-arg", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("named-arg", @parser.ParseMode::Editor))
}

test "flink_grammar_named_arg_is_dialect_gated" {
  // `name => expr` is Flink-only (NAMED_ARGUMENT_ASSIGNMENT Parser.jj:8794):
  // valid under flink-2.3.0, FATHOM-PARSE-009 under Doris.
  assert_true(flink_grammar_bidirectional(b"SELECT f(a => 1)", "\"valid\":true", "FATHOM-PARSE-009"))
}

// ---------------------------------------------------------------------------
// cast-timestamp-ltz / cast-map-type / row-ctor / array-ctor: Flink expression
// and data-type breadth (dataTypeParserMethods Parser.tdd:759-765).
// ---------------------------------------------------------------------------
test "flink-grammar cast-timestamp-ltz flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar cast-timestamp-ltz flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("cast-timestamp-ltz", "strict"), "flink-grammar.cast-timestamp-ltz.flink-2.3.0.strict.json")
}

test "flink-grammar cast-timestamp-ltz flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar cast-timestamp-ltz flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("cast-timestamp-ltz", "editor"), "flink-grammar.cast-timestamp-ltz.flink-2.3.0.editor.json")
}

test "flink_grammar_cast_timestamp_ltz_lossless" {
  assert_true(flink_grammar_lossless("cast-timestamp-ltz", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("cast-timestamp-ltz", @parser.ParseMode::Editor))
}

test "flink-grammar cast-map-type flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar cast-map-type flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("cast-map-type", "strict"), "flink-grammar.cast-map-type.flink-2.3.0.strict.json")
}

test "flink-grammar cast-map-type flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar cast-map-type flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("cast-map-type", "editor"), "flink-grammar.cast-map-type.flink-2.3.0.editor.json")
}

test "flink_grammar_cast_map_type_lossless" {
  assert_true(flink_grammar_lossless("cast-map-type", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("cast-map-type", @parser.ParseMode::Editor))
}

test "flink-grammar row-ctor flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar row-ctor flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("row-ctor", "strict"), "flink-grammar.row-ctor.flink-2.3.0.strict.json")
}

test "flink-grammar row-ctor flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar row-ctor flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("row-ctor", "editor"), "flink-grammar.row-ctor.flink-2.3.0.editor.json")
}

test "flink_grammar_row_ctor_lossless" {
  assert_true(flink_grammar_lossless("row-ctor", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("row-ctor", @parser.ParseMode::Editor))
}

test "flink-grammar array-ctor flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar array-ctor flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("array-ctor", "strict"), "flink-grammar.array-ctor.flink-2.3.0.strict.json")
}

test "flink-grammar array-ctor flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar array-ctor flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("array-ctor", "editor"), "flink-grammar.array-ctor.flink-2.3.0.editor.json")
}

test "flink_grammar_array_ctor_lossless" {
  assert_true(flink_grammar_lossless("array-ctor", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("array-ctor", @parser.ParseMode::Editor))
}

// ===========================================================================
// FLINK-03 Catalog/DATABASE DDL fixtures (11-03, wave 3)
// ===========================================================================

// ---------------------------------------------------------------------------
// create-catalog: SqlCreateCatalog WITH Properties() (valid=true, lossless).
// ---------------------------------------------------------------------------
test "flink-grammar create-catalog flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar create-catalog flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-catalog", "strict"), "flink-grammar.create-catalog.flink-2.3.0.strict.json")
}

test "flink-grammar create-catalog flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar create-catalog flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-catalog", "editor"), "flink-grammar.create-catalog.flink-2.3.0.editor.json")
}

test "flink_grammar_create_catalog_lossless" {
  assert_true(flink_grammar_lossless("create-catalog", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("create-catalog", @parser.ParseMode::Editor))
  // The statement-family kind is create_catalog (D-02 wire string).
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"CREATE CATALOG c WITH ('type'='generic_in_memory')", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"kind\":\"create_catalog\""))
}

// The Catalog family is whole-statement unsupported under Doris (no CREATE
// CATALOG production) → FATHOM-PARSE-007 (D-04, §9 matrix).
test "flink_grammar_create_catalog_is_unsupported_under_doris" {
  assert_true(flink_grammar_bidirectional(b"CREATE CATALOG c WITH ('type'='generic_in_memory')", "\"valid\":true", "FATHOM-PARSE-007"))
}

// ---------------------------------------------------------------------------
// create-database: SqlCreateDatabase COMMENT + WITH Properties().
// ---------------------------------------------------------------------------
test "flink-grammar create-database flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar create-database flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-database", "strict"), "flink-grammar.create-database.flink-2.3.0.strict.json")
}

test "flink-grammar create-database flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar create-database flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-database", "editor"), "flink-grammar.create-database.flink-2.3.0.editor.json")
}

test "flink_grammar_create_database_lossless" {
  assert_true(flink_grammar_lossless("create-database", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("create-database", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"CREATE DATABASE db COMMENT 'sales db' WITH ('k'='v')", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"kind\":\"create_database\""))
}

// ---------------------------------------------------------------------------
// drop-catalog / drop-database: SqlDropCatalog / SqlDropDatabase with the
// CASCADE tail (valid=true, lossless).
// ---------------------------------------------------------------------------
test "flink-grammar drop-catalog flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar drop-catalog flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("drop-catalog", "strict"), "flink-grammar.drop-catalog.flink-2.3.0.strict.json")
}

test "flink-grammar drop-catalog flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar drop-catalog flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("drop-catalog", "editor"), "flink-grammar.drop-catalog.flink-2.3.0.editor.json")
}

test "flink_grammar_drop_catalog_lossless" {
  assert_true(flink_grammar_lossless("drop-catalog", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("drop-catalog", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"DROP CATALOG IF EXISTS c", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"kind\":\"drop_catalog\""))
}

test "flink-grammar drop-database flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar drop-database flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("drop-database", "strict"), "flink-grammar.drop-database.flink-2.3.0.strict.json")
}

test "flink-grammar drop-database flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar drop-database flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("drop-database", "editor"), "flink-grammar.drop-database.flink-2.3.0.editor.json")
}

test "flink_grammar_drop_database_lossless" {
  assert_true(flink_grammar_lossless("drop-database", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("drop-database", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"DROP DATABASE db CASCADE", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"kind\":\"drop_database\""))
}

// ---------------------------------------------------------------------------
// alter-catalog: SqlAlterCatalog SET (...) (valid=true, lossless).
// ---------------------------------------------------------------------------
test "flink-grammar alter-catalog flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar alter-catalog flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("alter-catalog", "strict"), "flink-grammar.alter-catalog.flink-2.3.0.strict.json")
}

test "flink-grammar alter-catalog flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar alter-catalog flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("alter-catalog", "editor"), "flink-grammar.alter-catalog.flink-2.3.0.editor.json")
}

test "flink_grammar_alter_catalog_lossless" {
  assert_true(flink_grammar_lossless("alter-catalog", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("alter-catalog", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"ALTER CATALOG c SET ('k'='v')", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"kind\":\"alter_table\""))
}

// ---------------------------------------------------------------------------
// create-catalog-incomplete: unclosed WITH ( — bounded Missing/Error nodes,
// lossless replay (D-03, CST-01).
// ---------------------------------------------------------------------------
test "flink-grammar create-catalog-incomplete flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar create-catalog-incomplete flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-catalog-incomplete", "strict"), "flink-grammar.create-catalog-incomplete.flink-2.3.0.strict.json")
}

test "flink-grammar create-catalog-incomplete flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar create-catalog-incomplete flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-catalog-incomplete", "editor"), "flink-grammar.create-catalog-incomplete.flink-2.3.0.editor.json")
}

test "flink_grammar_create_catalog_incomplete_lossless" {
  assert_true(flink_grammar_lossless("create-catalog-incomplete", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("create-catalog-incomplete", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"CREATE CATALOG c WITH (", "flink", "flink-2.3.0", "strict")[:])
  // Incomplete statement: valid=false with bounded missing/error diagnostics.
  assert_true(strict.contains("\"valid\":false"))
  assert_true(strict.contains("FATHOM-PARSE-002"))
}

// ---------------------------------------------------------------------------
// drop-database-incomplete: DROP DATABASE with no name — bounded Missing
// node (the missing-name error at EOF), lossless replay.
// ---------------------------------------------------------------------------
test "flink-grammar drop-database-incomplete flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar drop-database-incomplete flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("drop-database-incomplete", "strict"), "flink-grammar.drop-database-incomplete.flink-2.3.0.strict.json")
}

test "flink-grammar drop-database-incomplete flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar drop-database-incomplete flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("drop-database-incomplete", "editor"), "flink-grammar.drop-database-incomplete.flink-2.3.0.editor.json")
}

test "flink_grammar_drop_database_incomplete_lossless" {
  assert_true(flink_grammar_lossless("drop-database-incomplete", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("drop-database-incomplete", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"DROP DATABASE", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"valid\":false"))
  assert_true(strict.contains("FATHOM-PARSE-002"))
}

// ===========================================================================
// FLINK-03 VIEW + FUNCTION DDL fixtures (11-03, wave 3)
// ===========================================================================

// ---------------------------------------------------------------------------
// create-view: SqlCreateView AS query (valid=true, create_view kind).
// ---------------------------------------------------------------------------
test "flink-grammar create-view flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar create-view flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-view", "strict"), "flink-grammar.create-view.flink-2.3.0.strict.json")
}

test "flink-grammar create-view flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar create-view flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-view", "editor"), "flink-grammar.create-view.flink-2.3.0.editor.json")
}

test "flink_grammar_create_view_lossless" {
  assert_true(flink_grammar_lossless("create-view", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("create-view", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"CREATE VIEW v AS SELECT * FROM t", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"kind\":\"create_view\""))
}

// CREATE VIEW is shared syntax (Doris also supports CREATE VIEW AS query), so
// no Doris-side 007 gate fires — the form parses valid under both dialects.
test "flink_grammar_create_view_is_shared_with_doris" {
  assert_true(flink_grammar_bidirectional(b"CREATE VIEW v AS SELECT * FROM t", "\"valid\":true", "\"valid\":true"))
}

// ---------------------------------------------------------------------------
// create-view-field-list: the optional ( a, b ) field list is preserved.
// ---------------------------------------------------------------------------
test "flink-grammar create-view-field-list flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar create-view-field-list flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-view-field-list", "strict"), "flink-grammar.create-view-field-list.flink-2.3.0.strict.json")
}

test "flink-grammar create-view-field-list flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar create-view-field-list flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-view-field-list", "editor"), "flink-grammar.create-view-field-list.flink-2.3.0.editor.json")
}

test "flink_grammar_create_view_field_list_lossless" {
  assert_true(flink_grammar_lossless("create-view-field-list", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("create-view-field-list", @parser.ParseMode::Editor))
}

// ---------------------------------------------------------------------------
// create-function / create-function-python: CREATE [TEMPORARY [SYSTEM]]
// FUNCTION ... AS 'class' [LANGUAGE JAVA|SCALA|PYTHON] (create_function kind).
// ---------------------------------------------------------------------------
test "flink-grammar create-function flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar create-function flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-function", "strict"), "flink-grammar.create-function.flink-2.3.0.strict.json")
}

test "flink-grammar create-function flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar create-function flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-function", "editor"), "flink-grammar.create-function.flink-2.3.0.editor.json")
}

test "flink_grammar_create_function_lossless" {
  assert_true(flink_grammar_lossless("create-function", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("create-function", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"CREATE TEMPORARY FUNCTION f AS 'com.example.UDF' LANGUAGE JAVA", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"kind\":\"create_function\""))
}

test "flink-grammar create-function-python flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar create-function-python flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-function-python", "strict"), "flink-grammar.create-function-python.flink-2.3.0.strict.json")
}

test "flink-grammar create-function-python flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar create-function-python flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-function-python", "editor"), "flink-grammar.create-function-python.flink-2.3.0.editor.json")
}

test "flink_grammar_create_function_python_lossless" {
  assert_true(flink_grammar_lossless("create-function-python", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("create-function-python", @parser.ParseMode::Editor))
}

// The FUNCTION family is whole-statement unsupported under Doris (no CREATE
// FUNCTION production) → FATHOM-PARSE-007 (D-04, §9 matrix).
test "flink_grammar_create_function_is_unsupported_under_doris" {
  assert_true(flink_grammar_bidirectional(b"CREATE FUNCTION f AS 'com.example.UDF' LANGUAGE JAVA", "\"valid\":true", "FATHOM-PARSE-007"))
}

// ---------------------------------------------------------------------------
// drop-view / drop-function: SqlDropView/SqlDropFunction [IF EXISTS] name.
// ---------------------------------------------------------------------------
test "flink-grammar drop-view flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar drop-view flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("drop-view", "strict"), "flink-grammar.drop-view.flink-2.3.0.strict.json")
}

test "flink-grammar drop-view flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar drop-view flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("drop-view", "editor"), "flink-grammar.drop-view.flink-2.3.0.editor.json")
}

test "flink_grammar_drop_view_lossless" {
  assert_true(flink_grammar_lossless("drop-view", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("drop-view", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"DROP VIEW IF EXISTS v", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"kind\":\"drop_view\""))
}

test "flink-grammar drop-function flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar drop-function flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("drop-function", "strict"), "flink-grammar.drop-function.flink-2.3.0.strict.json")
}

test "flink-grammar drop-function flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar drop-function flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("drop-function", "editor"), "flink-grammar.drop-function.flink-2.3.0.editor.json")
}

test "flink_grammar_drop_function_lossless" {
  assert_true(flink_grammar_lossless("drop-function", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("drop-function", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"DROP FUNCTION IF EXISTS f", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"kind\":\"drop_function\""))
}

// DROP has no Doris dispatch arm → whole-statement FATHOM-PARSE-007.
test "flink_grammar_drop_view_is_unsupported_under_doris" {
  assert_true(flink_grammar_bidirectional(b"DROP VIEW IF EXISTS v", "\"valid\":true", "FATHOM-PARSE-007"))
}

// ---------------------------------------------------------------------------
// alter-view-rename / alter-view-as / alter-function: SqlAlterView /
// SqlAlterFunction (alter_table kind for the whole ALTER family, D-02).
// ---------------------------------------------------------------------------
test "flink-grammar alter-view-rename flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar alter-view-rename flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("alter-view-rename", "strict"), "flink-grammar.alter-view-rename.flink-2.3.0.strict.json")
}

test "flink-grammar alter-view-rename flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar alter-view-rename flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("alter-view-rename", "editor"), "flink-grammar.alter-view-rename.flink-2.3.0.editor.json")
}

test "flink_grammar_alter_view_rename_lossless" {
  assert_true(flink_grammar_lossless("alter-view-rename", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("alter-view-rename", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"ALTER VIEW v RENAME TO v2", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"kind\":\"alter_table\""))
}

test "flink-grammar alter-view-as flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar alter-view-as flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("alter-view-as", "strict"), "flink-grammar.alter-view-as.flink-2.3.0.strict.json")
}

test "flink-grammar alter-view-as flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar alter-view-as flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("alter-view-as", "editor"), "flink-grammar.alter-view-as.flink-2.3.0.editor.json")
}

test "flink_grammar_alter_view_as_lossless" {
  assert_true(flink_grammar_lossless("alter-view-as", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("alter-view-as", @parser.ParseMode::Editor))
}

test "flink-grammar alter-function flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar alter-function flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("alter-function", "strict"), "flink-grammar.alter-function.flink-2.3.0.strict.json")
}

test "flink-grammar alter-function flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar alter-function flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("alter-function", "editor"), "flink-grammar.alter-function.flink-2.3.0.editor.json")
}

test "flink_grammar_alter_function_lossless" {
  assert_true(flink_grammar_lossless("alter-function", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("alter-function", @parser.ParseMode::Editor))
}

// ALTER has no Doris dispatch arm → whole-statement FATHOM-PARSE-007.
test "flink_grammar_alter_is_unsupported_under_doris" {
  assert_true(flink_grammar_bidirectional(b"ALTER VIEW v AS SELECT 1", "\"valid\":true", "FATHOM-PARSE-007"))
}

// ---------------------------------------------------------------------------
// create-view-incomplete / create-function-incomplete: missing AS-query /
// class string → bounded Missing/Error nodes, lossless replay.
// ---------------------------------------------------------------------------
test "flink-grammar create-view-incomplete flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar create-view-incomplete flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-view-incomplete", "strict"), "flink-grammar.create-view-incomplete.flink-2.3.0.strict.json")
}

test "flink-grammar create-view-incomplete flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar create-view-incomplete flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-view-incomplete", "editor"), "flink-grammar.create-view-incomplete.flink-2.3.0.editor.json")
}

test "flink_grammar_create_view_incomplete_lossless" {
  assert_true(flink_grammar_lossless("create-view-incomplete", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("create-view-incomplete", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"CREATE VIEW v AS", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"valid\":false"))
  assert_true(strict.contains("FATHOM-PARSE-002"))
}

test "flink-grammar create-function-incomplete flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar create-function-incomplete flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-function-incomplete", "strict"), "flink-grammar.create-function-incomplete.flink-2.3.0.strict.json")
}

test "flink-grammar create-function-incomplete flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar create-function-incomplete flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-function-incomplete", "editor"), "flink-grammar.create-function-incomplete.flink-2.3.0.editor.json")
}

test "flink_grammar_create_function_incomplete_lossless" {
  assert_true(flink_grammar_lossless("create-function-incomplete", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("create-function-incomplete", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"CREATE FUNCTION f AS", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"valid\":false"))
  assert_true(strict.contains("FATHOM-PARSE-002"))
}

// ---------------------------------------------------------------------------
// view-recovery: the trailing SELECT after `;` is its own statement (no
// cross-statement token swallowing, CST-01).
// ---------------------------------------------------------------------------
test "flink-grammar view-recovery flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar view-recovery flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("view-recovery", "strict"), "flink-grammar.view-recovery.flink-2.3.0.strict.json")
}

test "flink-grammar view-recovery flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar view-recovery flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("view-recovery", "editor"), "flink-grammar.view-recovery.flink-2.3.0.editor.json")
}

test "flink_grammar_view_recovery_lossless_and_independent_statements" {
  assert_true(flink_grammar_lossless("view-recovery", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("view-recovery", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"CREATE VIEW v AS SELECT * FROM t; SELECT 2", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"kind\":\"create_view\""))
  assert_true(strict.contains("\"kind\":\"select\""))
}

// ===========================================================================
// FLINK-04 CREATE TABLE column body (11-03, wave 3)
// ===========================================================================

// ---------------------------------------------------------------------------
// create-table-columns: the four column kinds + table constraint + WATERMARK
// in one body (valid=true, create_table kind, lossless replay).
// ---------------------------------------------------------------------------
test "flink-grammar create-table-columns flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar create-table-columns flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-table-columns", "strict"), "flink-grammar.create-table-columns.flink-2.3.0.strict.json")
}

test "flink-grammar create-table-columns flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar create-table-columns flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-table-columns", "editor"), "flink-grammar.create-table-columns.flink-2.3.0.editor.json")
}

test "flink_grammar_create_table_columns_lossless" {
  assert_true(flink_grammar_lossless("create-table-columns", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("create-table-columns", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"CREATE TABLE t (log_ts TIMESTAMP_LTZ(3), proc AS PROCTIME(), x STRING METADATA FROM 'x' VIRTUAL, PRIMARY KEY (id) NOT ENFORCED, WATERMARK FOR log_ts AS log_ts - INTERVAL '5' SECOND)", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"kind\":\"create_table\""))
  assert_true(strict.contains("\"valid\":true"))
}

// ---------------------------------------------------------------------------
// create-table-typed-column: physical typed columns (a INT, b STRING).
// ---------------------------------------------------------------------------
test "flink-grammar create-table-typed-column flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar create-table-typed-column flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-table-typed-column", "strict"), "flink-grammar.create-table-typed-column.flink-2.3.0.strict.json")
}

test "flink-grammar create-table-typed-column flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar create-table-typed-column flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-table-typed-column", "editor"), "flink-grammar.create-table-typed-column.flink-2.3.0.editor.json")
}

test "flink_grammar_create_table_typed_column_lossless" {
  assert_true(flink_grammar_lossless("create-table-typed-column", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("create-table-typed-column", @parser.ParseMode::Editor))
}

// ---------------------------------------------------------------------------
// create-table-watermark-second: a second WATERMARK is a localized
// multipleWatermarksUnsupported error — never a silent overwrite (T-11-17).
// ---------------------------------------------------------------------------
test "flink-grammar create-table-watermark-second flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar create-table-watermark-second flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-table-watermark-second", "strict"), "flink-grammar.create-table-watermark-second.flink-2.3.0.strict.json")
}

test "flink-grammar create-table-watermark-second flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar create-table-watermark-second flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-table-watermark-second", "editor"), "flink-grammar.create-table-watermark-second.flink-2.3.0.editor.json")
}

test "flink_grammar_create_table_watermark_second_errors" {
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"CREATE TABLE t (a INT, WATERMARK FOR a AS a, WATERMARK FOR b AS b)", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"valid\":false"))
  assert_true(strict.contains("multiple WATERMARK clauses are not supported"))
}

// ---------------------------------------------------------------------------
// create-table-pk-enforced: bare ENFORCED is a localized error (Flink has no
// enforced primary-key support in the SDK subset).
// ---------------------------------------------------------------------------
test "flink-grammar create-table-pk-enforced flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar create-table-pk-enforced flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-table-pk-enforced", "strict"), "flink-grammar.create-table-pk-enforced.flink-2.3.0.strict.json")
}

test "flink-grammar create-table-pk-enforced flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar create-table-pk-enforced flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-table-pk-enforced", "editor"), "flink-grammar.create-table-pk-enforced.flink-2.3.0.editor.json")
}

test "flink_grammar_create_table_pk_enforced_errors" {
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"CREATE TABLE t (id INT, PRIMARY KEY (id) ENFORCED)", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"valid\":false"))
  assert_true(strict.contains("expected NOT ENFORCED after PRIMARY KEY"))
}

// ---------------------------------------------------------------------------
// create-table-trailing-comma: `(a INT,)` is a bounded trailing-comma error.
// ---------------------------------------------------------------------------
test "flink-grammar create-table-trailing-comma flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar create-table-trailing-comma flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-table-trailing-comma", "strict"), "flink-grammar.create-table-trailing-comma.flink-2.3.0.strict.json")
}

test "flink-grammar create-table-trailing-comma flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar create-table-trailing-comma flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-table-trailing-comma", "editor"), "flink-grammar.create-table-trailing-comma.flink-2.3.0.editor.json")
}

test "flink_grammar_create_table_trailing_comma_lossless_and_errors" {
  assert_true(flink_grammar_lossless("create-table-trailing-comma", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("create-table-trailing-comma", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"CREATE TABLE t (a INT,)", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"valid\":false"))
  assert_true(strict.contains("expected column definition after comma"))
}

// ---------------------------------------------------------------------------
// create-table-incomplete-wm / create-table-incomplete-col: bounded
// Missing/Error nodes with lossless replay, recovering at the clause boundary
// rather than swallowing the statement (is_flink_create_table_clause_boundary).
// ---------------------------------------------------------------------------
test "flink-grammar create-table-incomplete-wm flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar create-table-incomplete-wm flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-table-incomplete-wm", "strict"), "flink-grammar.create-table-incomplete-wm.flink-2.3.0.strict.json")
}

test "flink-grammar create-table-incomplete-wm flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar create-table-incomplete-wm flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-table-incomplete-wm", "editor"), "flink-grammar.create-table-incomplete-wm.flink-2.3.0.editor.json")
}

test "flink_grammar_create_table_incomplete_wm_lossless" {
  assert_true(flink_grammar_lossless("create-table-incomplete-wm", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("create-table-incomplete-wm", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"CREATE TABLE t (WATERMARK FOR ts AS)", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"valid\":false"))
  assert_true(strict.contains("FATHOM-PARSE-002"))
}

test "flink-grammar create-table-incomplete-col flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar create-table-incomplete-col flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-table-incomplete-col", "strict"), "flink-grammar.create-table-incomplete-col.flink-2.3.0.strict.json")
}

test "flink-grammar create-table-incomplete-col flink-2.3.0 editor" {
  let t = @test.Test("flink-grammar create-table-incomplete-col flink-2.3.0 editor")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("create-table-incomplete-col", "editor"), "flink-grammar.create-table-incomplete-col.flink-2.3.0.editor.json")
}

test "flink_grammar_create_table_incomplete_col_lossless" {
  assert_true(flink_grammar_lossless("create-table-incomplete-col", @parser.ParseMode::Strict))
  assert_true(flink_grammar_lossless("create-table-incomplete-col", @parser.ParseMode::Editor))
  let strict = @utf8.decode_lossy(@binding.fathom_parse_v1(b"CREATE TABLE t (a INT, b", "flink", "flink-2.3.0", "strict")[:])
  assert_true(strict.contains("\"valid\":false"))
  assert_true(strict.contains("FATHOM-PARSE-002"))
}
