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
    raw: b"WITH o AS (SELECT user_id, amount FROM t1) SELECT u.name, SUM(o.amount) AS total FROM o JOIN users u ON o.user_id = u.id GROUP BY u.name",
  },
  {
    fixture_id: "select-incomplete",
    profile: "flink-2.3.0",
    raw: b"SELECT a, b FROM t WHERE",
  },
  {
    fixture_id: "set-union-all",
    profile: "flink-2.3.0",
    raw: b"SELECT a FROM t1 UNION ALL SELECT a FROM t2",
  },
  {
    fixture_id: "set-intersect",
    profile: "flink-2.3.0",
    raw: b"SELECT a FROM t1 INTERSECT SELECT a FROM t2",
  },
  {
    fixture_id: "set-except",
    profile: "flink-2.3.0",
    raw: b"SELECT a FROM t1 EXCEPT SELECT a FROM t2",
  },
  {
    fixture_id: "set-intersect-all",
    profile: "flink-2.3.0",
    raw: b"SELECT a FROM t1 INTERSECT ALL SELECT a FROM t2",
  },
  {
    fixture_id: "set-except-all",
    profile: "flink-2.3.0",
    raw: b"SELECT a FROM t1 EXCEPT ALL SELECT a FROM t2",
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
