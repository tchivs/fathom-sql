///|
/// D-01 flink-format snapshot group (Phase 13 wave 1, 13-01): an independent
/// namespace under parity/__snapshot__/ that freezes the Flink canonical
/// formatting contract (refusal-first, D-33) for the 21 covered statement
/// families under flink-2.3.0 strict. Filenames are
/// `flink-format.{fixture}.flink-2.3.0.strict.json` and never overlap the
/// Doris 213-snapshot baseline, the flink-grammar group, or the flink-lexical
/// group (Pitfall 7).
///
/// Generation: `moon test --update --package parity` after the approved-changes
/// register entry is committed (D-08 single-use approval path, see
/// .planning/phases/13-toolchain-and-editor-packaging/approved-changes.md). CI
/// runs `moon test --package parity` WITHOUT --update so any byte drift fails.
///
/// Oracle shape mirrors test/formatter_test.mbt:1376-1433 (formatter_corpus
/// fixture check): per-fixture accepted output snapshot + idempotence
/// format(format(x)) == format(x) (D-34) + zero-diagnostic reparse (D-35) +
/// statement-offset bounds, and refusal assertions (accepted=false, empty
/// output, exactly one FATHOM-FORMAT-001, parse diagnostics never masked —
/// T-03-01). The covered-set completeness probe machine-checks
/// formatter.flink_statement_covered against the Flink parser's emit set.
pub(all) struct FlinkFormatFixture {
  pub fixture_id : String
  pub profile : String
  pub raw : Bytes
  pub expected_refused : Bool
}

///|
/// 13-01 fixtures: one representative per covered Flink statement family
/// (D-01 20-family list) plus one unsafe-tree refusal row. Every positive
/// fixture must format accepted=true, stay idempotent, and reparse clean; the
/// refusal row must refuse with exactly one FATHOM-FORMAT-001 and zero output.
let flink_format_fixtures : Array[FlinkFormatFixture] = [
  {
    fixture_id: "select-basic",
    profile: "flink-2.3.0",
    raw: b"SELECT 1",
    expected_refused: false,
  },
  {
    fixture_id: "select-from-where",
    profile: "flink-2.3.0",
    raw: b"SELECT a, b FROM t WHERE x = 1",
    expected_refused: false,
  },
  {
    fixture_id: "insert-into-select",
    profile: "flink-2.3.0",
    raw: b"INSERT INTO t SELECT * FROM s",
    expected_refused: false,
  },
  {
    fixture_id: "update-where",
    profile: "flink-2.3.0",
    raw: b"UPDATE t SET a = 1 WHERE id = 5",
    expected_refused: false,
  },
  {
    fixture_id: "delete-where",
    profile: "flink-2.3.0",
    raw: b"DELETE FROM t WHERE id = 5",
    expected_refused: false,
  },
  {
    fixture_id: "explain-plan-for",
    profile: "flink-2.3.0",
    raw: b"EXPLAIN PLAN FOR SELECT * FROM t",
    expected_refused: false,
  },
  {
    fixture_id: "show-tables-from-like",
    profile: "flink-2.3.0",
    raw: b"SHOW TABLES FROM db1 LIKE '%'",
    expected_refused: false,
  },
  {
    fixture_id: "describe-extended-database",
    profile: "flink-2.3.0",
    raw: b"DESCRIBE EXTENDED DATABASE db",
    expected_refused: false,
  },
  {
    fixture_id: "analyze-table",
    profile: "flink-2.3.0",
    raw: b"ANALYZE TABLE t COMPUTE STATISTICS",
    expected_refused: false,
  },
  {
    fixture_id: "create-table-basic",
    profile: "flink-2.3.0",
    raw: b"CREATE TABLE t (a INT, b STRING) WITH ('connector' = 'x')",
    expected_refused: false,
  },
  {
    fixture_id: "create-view-as",
    profile: "flink-2.3.0",
    raw: b"CREATE VIEW v AS SELECT * FROM t",
    expected_refused: false,
  },
  {
    fixture_id: "create-catalog",
    profile: "flink-2.3.0",
    raw: b"CREATE CATALOG c WITH ('type' = 'generic_in_memory')",
    expected_refused: false,
  },
  {
    fixture_id: "create-database",
    profile: "flink-2.3.0",
    raw: b"CREATE DATABASE db COMMENT 'sales db' WITH ('k' = 'v')",
    expected_refused: false,
  },
  {
    fixture_id: "create-function",
    profile: "flink-2.3.0",
    raw: b"CREATE TEMPORARY FUNCTION f AS 'com.example.UDF' LANGUAGE JAVA",
    expected_refused: false,
  },
  {
    fixture_id: "drop-catalog",
    profile: "flink-2.3.0",
    raw: b"DROP CATALOG IF EXISTS c",
    expected_refused: false,
  },
  {
    fixture_id: "drop-database",
    profile: "flink-2.3.0",
    raw: b"DROP DATABASE db CASCADE",
    expected_refused: false,
  },
  {
    fixture_id: "drop-table",
    profile: "flink-2.3.0",
    raw: b"DROP TABLE IF EXISTS t",
    expected_refused: false,
  },
  {
    fixture_id: "drop-view",
    profile: "flink-2.3.0",
    raw: b"DROP VIEW IF EXISTS v",
    expected_refused: false,
  },
  {
    fixture_id: "drop-function",
    profile: "flink-2.3.0",
    raw: b"DROP FUNCTION IF EXISTS f",
    expected_refused: false,
  },
  {
    fixture_id: "alter-table-rename",
    profile: "flink-2.3.0",
    raw: b"ALTER TABLE t RENAME TO t2",
    expected_refused: false,
  },
  {
    fixture_id: "set-option",
    profile: "flink-2.3.0",
    raw: b"SET 'k' = 'v'",
    expected_refused: false,
  },
  {
    fixture_id: "use-catalog",
    profile: "flink-2.3.0",
    raw: b"USE CATALOG c",
    expected_refused: false,
  },
  {
    fixture_id: "select-incomplete-refused",
    profile: "flink-2.3.0",
    raw: b"SELECT a, b FROM t WHERE",
    expected_refused: true,
  },
  {
    fixture_id: "select-unclosed-paren-refused",
    profile: "flink-2.3.0",
    raw: b"SELECT (",
    expected_refused: true,
  },
]

///|
fn flink_format_fixture(id : String) -> FlinkFormatFixture {
  for fixture in flink_format_fixtures {
    if fixture.fixture_id == id {
      return fixture
    }
  }
  panic()
}

///|
/// Serialized format-result envelope (the same wire shape the CLI/LSP emit)
/// frozen by the snapshot group.
fn flink_format_json(id : String) -> String {
  let fixture = flink_format_fixture(id)
  @utf8.decode_lossy(
    @binding.fathom_format_v1(
      fixture.raw,
      "flink",
      fixture.profile,
      "strict",
      "upper",
      2,
      100,
      "trailing",
      "follow",
      true,
    ),
  )
}

///|
fn flink_format_snapshot_test(
  t : @test.Test,
  content : String,
  filename : String,
) -> Unit raise SnapshotError {
  t.write(content)
  t.snapshot(filename~)
}

///|
fn contains_newline(raw : Bytes) -> Bool {
  let mut index = 0
  while index < raw.length() {
    if raw[index].to_int() == 10 {
      return true
    }
    index = index + 1
  }
  false
}

///|
/// Oracle per row: positive fixtures stay idempotent format(format(x)) ==
/// format(x) (D-34), reparse with zero diagnostics (D-35), and keep every
/// statement offset inside the output; refusal fixtures refuse with
/// accepted=false, empty output, and exactly one FATHOM-FORMAT-001 (D-33,
/// Pitfall 6 — never a skipped test).
fn flink_format_oracle(fixture : FlinkFormatFixture) -> String {
  let options = @formatter.FormatOptions::default()
  let formatted = match
    @api.format_with_ids(
      fixture.raw,
      "flink",
      fixture.profile,
      "strict",
      options,
    ) {
    Ok(result) => result
    Err(_) => return fixture.fixture_id + ": api Err"
  }
  if fixture.expected_refused {
    if formatted.accepted || formatted.output.length() != 0 {
      return fixture.fixture_id +
        ": expected refusal but accepted or emitted output"
    }
    let mut refusal_count = 0
    for diagnostic in formatted.diagnostics {
      if diagnostic.code == "FATHOM-FORMAT-001" {
        refusal_count = refusal_count + 1
      }
    }
    if refusal_count != 1 {
      return fixture.fixture_id +
        ": expected exactly one FATHOM-FORMAT-001, got " +
        refusal_count.to_string()
    }
    ""
  } else {
    if !formatted.accepted {
      return fixture.fixture_id + ": refused but expected accepted"
    }
    if formatted.output.length() == 0 {
      return fixture.fixture_id + ": accepted but empty output"
    }
    for offset in formatted.statement_offsets {
      if offset < 0 || offset > formatted.output.length() {
        return fixture.fixture_id + ": statement offset out of bounds"
      }
    }
    let again = match
      @api.format_with_ids(
        formatted.output,
        "flink",
        fixture.profile,
        "strict",
        options,
      ) {
      Ok(result) => result
      Err(_) => return fixture.fixture_id + ": idempotence api Err"
    }
    if again.output != formatted.output {
      return fixture.fixture_id + ": not idempotent"
    }
    let reparsed = match
      @api.parse_with_ids(formatted.output, "flink", fixture.profile, "strict") {
      Ok(result) => result
      Err(_) => return fixture.fixture_id + ": reparse api Err"
    }
    if !reparsed.valid || reparsed.diagnostics.length() != 0 {
      return fixture.fixture_id + ": reparse not clean"
    }
    ""
  }
}

///|
test "flink_format_oracle_all_fixtures" {
  assert_eq(flink_format_fixtures.length(), 24)
  let mut failures = ""
  for fixture in flink_format_fixtures {
    let message = flink_format_oracle(fixture)
    if message.length() > 0 {
      failures = failures + message + "\n"
    }
  }
  assert_eq(failures, "")
}

// ---------------------------------------------------------------------------
// Per-fixture snapshots (positive fixtures only; refusal rows are oracle-only).
// ---------------------------------------------------------------------------

///|
test "flink-format select-basic flink-2.3.0 strict" {
  let t = @test.Test("flink-format select-basic flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("select-basic"),
    "flink-format.select-basic.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format select-from-where flink-2.3.0 strict" {
  let t = @test.Test("flink-format select-from-where flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("select-from-where"),
    "flink-format.select-from-where.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format insert-into-select flink-2.3.0 strict" {
  let t = @test.Test("flink-format insert-into-select flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("insert-into-select"),
    "flink-format.insert-into-select.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format update-where flink-2.3.0 strict" {
  let t = @test.Test("flink-format update-where flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("update-where"),
    "flink-format.update-where.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format delete-where flink-2.3.0 strict" {
  let t = @test.Test("flink-format delete-where flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("delete-where"),
    "flink-format.delete-where.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format explain-plan-for flink-2.3.0 strict" {
  let t = @test.Test("flink-format explain-plan-for flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("explain-plan-for"),
    "flink-format.explain-plan-for.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format show-tables-from-like flink-2.3.0 strict" {
  let t = @test.Test("flink-format show-tables-from-like flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("show-tables-from-like"),
    "flink-format.show-tables-from-like.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format describe-extended-database flink-2.3.0 strict" {
  let t = @test.Test(
    "flink-format describe-extended-database flink-2.3.0 strict",
  )
  flink_format_snapshot_test(
    t,
    flink_format_json("describe-extended-database"),
    "flink-format.describe-extended-database.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format analyze-table flink-2.3.0 strict" {
  let t = @test.Test("flink-format analyze-table flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("analyze-table"),
    "flink-format.analyze-table.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format create-table-basic flink-2.3.0 strict" {
  let t = @test.Test("flink-format create-table-basic flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("create-table-basic"),
    "flink-format.create-table-basic.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format create-view-as flink-2.3.0 strict" {
  let t = @test.Test("flink-format create-view-as flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("create-view-as"),
    "flink-format.create-view-as.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format create-catalog flink-2.3.0 strict" {
  let t = @test.Test("flink-format create-catalog flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("create-catalog"),
    "flink-format.create-catalog.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format create-database flink-2.3.0 strict" {
  let t = @test.Test("flink-format create-database flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("create-database"),
    "flink-format.create-database.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format create-function flink-2.3.0 strict" {
  let t = @test.Test("flink-format create-function flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("create-function"),
    "flink-format.create-function.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format drop-catalog flink-2.3.0 strict" {
  let t = @test.Test("flink-format drop-catalog flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("drop-catalog"),
    "flink-format.drop-catalog.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format drop-database flink-2.3.0 strict" {
  let t = @test.Test("flink-format drop-database flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("drop-database"),
    "flink-format.drop-database.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format drop-table flink-2.3.0 strict" {
  let t = @test.Test("flink-format drop-table flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("drop-table"),
    "flink-format.drop-table.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format drop-view flink-2.3.0 strict" {
  let t = @test.Test("flink-format drop-view flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("drop-view"),
    "flink-format.drop-view.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format drop-function flink-2.3.0 strict" {
  let t = @test.Test("flink-format drop-function flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("drop-function"),
    "flink-format.drop-function.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format alter-table-rename flink-2.3.0 strict" {
  let t = @test.Test("flink-format alter-table-rename flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("alter-table-rename"),
    "flink-format.alter-table-rename.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format set-option flink-2.3.0 strict" {
  let t = @test.Test("flink-format set-option flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("set-option"),
    "flink-format.set-option.flink-2.3.0.strict.json",
  )
}

///|
test "flink-format use-catalog flink-2.3.0 strict" {
  let t = @test.Test("flink-format use-catalog flink-2.3.0 strict")
  flink_format_snapshot_test(
    t,
    flink_format_json("use-catalog"),
    "flink-format.use-catalog.flink-2.3.0.strict.json",
  )
}

// ---------------------------------------------------------------------------
// Covered-set completeness probe (TOOL-01 coverage, flagged-unverified in the
// plan): machine-checks that every statement-family kind the Flink parser can
// emit (parse_flink_segment dispatch, parser.mbt:4140-4240) is covered by
// formatter.flink_statement_covered, and that clause-level kinds that appear
// INSIDE Select/CreateTable bodies are NOT statement families. The behavioral
// half proves no covered family silently single-lines (Pitfall 1): each
// representative formats accepted=true and — except the genuinely single-line
// SET option — its output contains a newline, so no family fell to `_ => []`.
// ---------------------------------------------------------------------------

///|
test "flink-format completeness probe: covered set never silently single-lines" {
  let mut failures = ""
  // The Flink parser emits exactly these statement-family kinds.
  let emittable : Array[(String, @syntax.SyntaxKind)] = [
    ("Select", @syntax.SyntaxKind::Select),
    ("Insert", @syntax.SyntaxKind::Insert),
    ("Update", @syntax.SyntaxKind::Update),
    ("Delete", @syntax.SyntaxKind::Delete),
    ("ExplainStatement", @syntax.SyntaxKind::ExplainStatement),
    ("ShowStatement", @syntax.SyntaxKind::ShowStatement),
    ("DescribeStatement", @syntax.SyntaxKind::DescribeStatement),
    ("AnalyzeStatement", @syntax.SyntaxKind::AnalyzeStatement),
    ("CreateTable", @syntax.SyntaxKind::CreateTable),
    ("CreateView", @syntax.SyntaxKind::CreateView),
    ("CreateCatalog", @syntax.SyntaxKind::CreateCatalog),
    ("CreateDatabase", @syntax.SyntaxKind::CreateDatabase),
    ("CreateFunction", @syntax.SyntaxKind::CreateFunction),
    ("DropCatalog", @syntax.SyntaxKind::DropCatalog),
    ("DropDatabase", @syntax.SyntaxKind::DropDatabase),
    ("DropTable", @syntax.SyntaxKind::DropTable),
    ("DropView", @syntax.SyntaxKind::DropView),
    ("DropFunction", @syntax.SyntaxKind::DropFunction),
    ("AlterTable", @syntax.SyntaxKind::AlterTable),
    ("SetOption", @syntax.SyntaxKind::SetOption),
    ("UseStatement", @syntax.SyntaxKind::UseStatement),
  ]
  for pair in emittable {
    let (label, kind) = pair
    if !@formatter.flink_statement_covered(kind) {
      failures = failures + "uncovered emittable family: " + label + "\n"
    }
  }
  // Clause-level kinds are NOT statement families — must not be in the set.
  let clause_level : Array[(String, @syntax.SyntaxKind)] = [
    ("WindowTvf", @syntax.SyntaxKind::WindowTvf),
    ("MatchRecognize", @syntax.SyntaxKind::MatchRecognize),
    ("WatermarkClause", @syntax.SyntaxKind::WatermarkClause),
    ("ComputedColumn", @syntax.SyntaxKind::ComputedColumn),
    ("MetadataColumn", @syntax.SyntaxKind::MetadataColumn),
    ("PrimaryKeyClause", @syntax.SyntaxKind::PrimaryKeyClause),
    ("TableLikeClause", @syntax.SyntaxKind::TableLikeClause),
  ]
  for pair in clause_level {
    let (label, kind) = pair
    if @formatter.flink_statement_covered(kind) {
      failures = failures +
        "clause-level kind incorrectly covered: " +
        label +
        "\n"
    }
  }
  // Behavioral no-silent-single-line proof: multi-clause representatives.
  // SET is the one family with a legitimately single-line canonical form.
  let reps : Array[(String, Bytes)] = [
    ("Select", b"SELECT a, b FROM t WHERE x = 1"),
    ("Insert", b"INSERT INTO t SELECT * FROM s"),
    ("Update", b"UPDATE t SET a = 1 WHERE id = 5"),
    ("Delete", b"DELETE FROM t WHERE id = 5"),
    ("ExplainStatement", b"EXPLAIN PLAN FOR SELECT * FROM t"),
    ("ShowStatement", b"SHOW TABLES FROM db1 LIKE '%'"),
    ("DescribeStatement", b"DESCRIBE EXTENDED DATABASE db"),
    ("AnalyzeStatement", b"ANALYZE TABLE t COMPUTE STATISTICS"),
    (
      "CreateTable", b"CREATE TABLE t (a INT, b STRING) WITH ('connector' = 'x')",
    ),
    ("CreateView", b"CREATE VIEW v AS SELECT * FROM t"),
    ("CreateCatalog", b"CREATE CATALOG c WITH ('type' = 'generic_in_memory')"),
    (
      "CreateDatabase", b"CREATE DATABASE db COMMENT 'sales db' WITH ('k' = 'v')",
    ),
    (
      "CreateFunction", b"CREATE TEMPORARY FUNCTION f AS 'com.example.UDF' LANGUAGE JAVA",
    ),
    ("DropCatalog", b"DROP CATALOG IF EXISTS c"),
    ("DropDatabase", b"DROP DATABASE db CASCADE"),
    ("DropTable", b"DROP TABLE IF EXISTS t"),
    ("DropView", b"DROP VIEW IF EXISTS v"),
    ("DropFunction", b"DROP FUNCTION IF EXISTS f"),
    ("AlterTable", b"ALTER TABLE t RENAME TO t2"),
    ("SetOption", b"SET 'k' = 'v'"),
    ("UseStatement", b"USE CATALOG c"),
  ]
  let options = @formatter.FormatOptions::default()
  for pair in reps {
    let (label, raw) = pair
    let formatted = match
      @api.format_with_ids(raw, "flink", "flink-2.3.0", "strict", options) {
      Ok(result) => result
      Err(_) => {
        failures = failures + label + ": api Err\n"
        continue
      }
    }
    if !formatted.accepted {
      failures = failures + label + ": refused but expected covered\n"
      continue
    }
    if label == "SetOption" {
      continue
    }
    if !contains_newline(formatted.output) {
      failures = failures +
        label +
        ": silent single-line output (no clause_breaks arm?)\n"
    }
  }
  assert_eq(failures, "")
}

// ---------------------------------------------------------------------------
// Refusal oracle: an unsafe Flink tree refuses with accepted=false, empty
// output, and exactly one FATHOM-FORMAT-001, and the parse diagnostics are
// preserved (never masked, T-03-01).
// ---------------------------------------------------------------------------

///|
test "flink-format refusal oracle: unsafe tree refuses, parse diagnostics preserved" {
  // Two distinct unsafe shapes: a missing expression tail (single localized
  // parse error) and an unclosed paren (multiple bounded parse errors). Both
  // must refuse with accepted=false, empty output, and exactly one
  // FATHOM-FORMAT-001, with every parse diagnostic preserved/prepended (never
  // masked, T-03-01).
  let unsafe_inputs : Array[Bytes] = [b"SELECT a, b FROM t WHERE", b"SELECT ("]
  for raw in unsafe_inputs {
    let formatted = match
      @api.format_with_ids(
        raw,
        "flink",
        "flink-2.3.0",
        "strict",
        @formatter.FormatOptions::default(),
      ) {
      Ok(result) => result
      Err(_) => panic()
    }
    assert_false(formatted.accepted)
    assert_eq(formatted.output, b"")
    let mut refusal_count = 0
    let mut parse_diagnostic_preserved = false
    for diagnostic in formatted.diagnostics {
      if diagnostic.code == "FATHOM-FORMAT-001" {
        refusal_count = refusal_count + 1
      } else {
        parse_diagnostic_preserved = true
      }
    }
    assert_eq(refusal_count, 1)
    assert_true(parse_diagnostic_preserved)
  }
}
