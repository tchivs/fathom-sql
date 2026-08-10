/// D-01 flink-format snapshot group (Phase 13 wave 1, 13-01): an independent
/// namespace under parity/__snapshot__/ that freezes the Flink canonical
/// formatting contract (refusal-first, D-33) for the covered statement
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
/// formatter.flink_statement_covered against the parser's emit set.

pub(all) struct FlinkFormatFixture {
  pub fixture_id : String
  pub profile : String
  pub raw : Bytes
  pub expected_refused : Bool
}

/// 13-01 fixtures. Task 1 (tracer) covers the shared families end to end:
/// select-basic (covered) and show-tables (an uncovered Flink family that must
/// refuse with exactly one FATHOM-FORMAT-001 and zero output). Task 2 expands
/// the covered set to the full 20-family D-01 list and flips show-tables to a
/// covered positive fixture.
let flink_format_fixtures : Array[FlinkFormatFixture] = [
  {
    fixture_id: "select-basic",
    profile: "flink-2.3.0",
    raw: b"SELECT 1",
    expected_refused: false,
  },
  {
    fixture_id: "show-tables-refused",
    profile: "flink-2.3.0",
    raw: b"SHOW TABLES",
    expected_refused: true,
  },
]

fn flink_format_fixture(id : String) -> FlinkFormatFixture {
  for fixture in flink_format_fixtures {
    if fixture.fixture_id == id { return fixture }
  }
  panic()
}

/// Serialized format-result envelope (the same wire shape the CLI/LSP emit)
/// frozen by the snapshot group.
fn flink_format_json(id : String) -> String {
  let fixture = flink_format_fixture(id)
  @utf8.decode_lossy(
    @binding.fathom_format_v1(
      fixture.raw, "flink", fixture.profile, "strict", "upper", 2, 100, "trailing", "follow", true,
    ),
  )
}

fn flink_format_snapshot_test(t : @test.Test, content : String, filename : String) -> Unit raise SnapshotError {
  t.write(content)
  t.snapshot(filename=filename)
}

fn contains_newline(raw : Bytes) -> Bool {
  let mut index = 0
  while index < raw.length() {
    if raw[index].to_int() == 10 { return true }
    index = index + 1
  }
  false
}

/// Oracle per row: positive fixtures hit the committed snapshot (via the
/// per-fixture snapshot tests), stay idempotent format(format(x)) == format(x)
/// (D-34), reparse with zero diagnostics (D-35), and keep every statement
/// offset inside the output; refusal fixtures refuse with accepted=false,
/// empty output, and exactly one FATHOM-FORMAT-001 (D-33, Pitfall 6 — never a
/// skipped test). Parse diagnostics are preserved/prepended, never masked
/// (T-03-01).
fn flink_format_oracle(fixture : FlinkFormatFixture) -> String {
  let options = @formatter.FormatOptions::default()
  let formatted = match @api.format_with_ids(fixture.raw, "flink", fixture.profile, "strict", options) {
    Ok(result) => result
    Err(_) => return fixture.fixture_id + ": api Err"
  }
  if fixture.expected_refused {
    if formatted.accepted || formatted.output.length() != 0 {
      return fixture.fixture_id + ": expected refusal but accepted or emitted output"
    }
    let mut refusal_count = 0
    for diagnostic in formatted.diagnostics {
      if diagnostic.code == "FATHOM-FORMAT-001" {
        refusal_count = refusal_count + 1
      }
    }
    if refusal_count != 1 {
      return fixture.fixture_id + ": expected exactly one FATHOM-FORMAT-001, got " + refusal_count.to_string()
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
    let again = match @api.format_with_ids(formatted.output, "flink", fixture.profile, "strict", options) {
      Ok(result) => result
      Err(_) => return fixture.fixture_id + ": idempotence api Err"
    }
    if again.output != formatted.output {
      return fixture.fixture_id + ": not idempotent"
    }
    let reparsed = match @api.parse_with_ids(formatted.output, "flink", fixture.profile, "strict") {
      Ok(result) => result
      Err(_) => return fixture.fixture_id + ": reparse api Err"
    }
    if !reparsed.valid || reparsed.diagnostics.length() != 0 {
      return fixture.fixture_id + ": reparse not clean"
    }
    ""
  }
}

test "flink_format_oracle_all_fixtures" {
  assert_eq(flink_format_fixtures.length(), 2)
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
// select-basic: the tracer covered path — a covered family formats end to end
// and its output is frozen byte-exact.
// ---------------------------------------------------------------------------
test "flink-format select-basic flink-2.3.0 strict" {
  let t = @test.Test("flink-format select-basic flink-2.3.0 strict")
  flink_format_snapshot_test(t, flink_format_json("select-basic"), "flink-format.select-basic.flink-2.3.0.strict.json")
}

/// Tracer covered-family probe: at this stage the shared families
/// (Select/Insert/Update/Delete/CreateTable/CreateView) are covered; the
/// Flink-only families (ShowStatement, UseStatement) are NOT yet in the
/// covered table, so the gate must refuse them. Task 2 expands this to the
/// full D-01 covered set.
test "flink-format tracer covered-family probe" {
  assert_true(@formatter.flink_statement_covered(@syntax.SyntaxKind::Select))
  assert_true(@formatter.flink_statement_covered(@syntax.SyntaxKind::Insert))
  assert_true(@formatter.flink_statement_covered(@syntax.SyntaxKind::Update))
  assert_true(@formatter.flink_statement_covered(@syntax.SyntaxKind::Delete))
  assert_true(@formatter.flink_statement_covered(@syntax.SyntaxKind::CreateTable))
  assert_true(@formatter.flink_statement_covered(@syntax.SyntaxKind::CreateView))
  assert_false(@formatter.flink_statement_covered(@syntax.SyntaxKind::ShowStatement))
  assert_false(@formatter.flink_statement_covered(@syntax.SyntaxKind::UseStatement))
}

/// The tracer refusal half: an uncovered Flink family refuses with
/// accepted=false, empty output, and exactly one FATHOM-FORMAT-001 — no
/// partial bytes, no silent single line (D-01, Pitfall 1).
test "flink-format uncovered family refuses end-to-end" {
  let result = match @api.format_with_ids(b"SHOW TABLES", "flink", "flink-2.3.0", "strict", @formatter.FormatOptions::default()) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_false(result.accepted)
  assert_eq(result.output, b"")
  assert_eq(result.diagnostics.length(), 1)
  assert_eq(result.diagnostics[0].code, "FATHOM-FORMAT-001")
}
