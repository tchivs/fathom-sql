/// Formatter tracer tests (plan 03-01): embedded fixtures mirroring the Phase 2
/// EmbeddedManifestFixture convention (test/parser_test.mbt:463-505). Runtime
/// tests never load the disk — raw bytes and goldens are embedded (STATE.md).
///
/// Contracts under test:
/// - byte-exact idempotence format(format(x)) == format(x) (D-34, Pitfall 6:
///   full Bytes equality, no trimming);
/// - zero-diagnostic reparse of accepted output (D-35);
/// - absolute refusal with DORIS-FORMAT-001 on error trees (D-33);
/// - CRLF byte-for-byte preservation (flagged assumption A2);
/// - empty input formats to empty output.

struct FormatterFixture {
  fixture_id : String
  profile : String
  mode : String
  raw : Bytes
  expected_valid : Bool
  expected_golden : Bytes
}

fn formatter_fixture_ok(fixture : FormatterFixture) -> Bool {
  let options = @formatter.FormatOptions::default()
  let formatted = match @api.format_with_ids(fixture.raw, fixture.profile, fixture.mode, options) {
    Ok(result) => result
    Err(_) => return false
  }
  if fixture.expected_valid {
    if !formatted.accepted || formatted.output != fixture.expected_golden {
      return false
    }
    // D-34: idempotence — formatting the formatted output is byte-identical.
    let again = match @api.format_with_ids(formatted.output, fixture.profile, fixture.mode, options) {
      Ok(result) => result
      Err(_) => return false
    }
    if again.output != formatted.output {
      return false
    }
    // D-35: the formatted output reparses cleanly with zero diagnostics.
    let reparsed = match @api.parse_with_ids(formatted.output, fixture.profile, fixture.mode) {
      Ok(result) => result
      Err(_) => return false
    }
    if !reparsed.valid || reparsed.diagnostics.length() != 0 {
      return false
    }
    true
  } else {
    // D-33: refusal — no partial output is ever emitted.
    if formatted.accepted || formatted.output.length() != 0 {
      return false
    }
    let mut found = false
    for diagnostic in formatted.diagnostics {
      if diagnostic.code.has_prefix("DORIS-FORMAT-") {
        found = true
      }
    }
    found
  }
}

test "formatter_tracer_fixtures_hit_goldens_and_oracles" {
  let fixtures = [
    // 4.x SELECT with lowercase keywords, a hint block, an inline block
    // comment, and a line comment: hint/comment bytes verbatim (D-36),
    // keywords uppercased via the classification table (D-28/D-29), trailing
    // newline exactly one (D-32).
    {
      fixture_id: "4.x-select-comments-hint",
      profile: "4.x",
      mode: "strict",
      raw: b"select /*+ SET_VAR(enable_vectorized_engine=true) */ a, /* keep */ b -- trailing\nfrom t",
      expected_valid: true,
      expected_golden: b"SELECT /*+ SET_VAR(enable_vectorized_engine=true) */ a, /* keep */ b -- trailing\nFROM t\n",
    },
    // 3.x multi-clause SELECT (FROM/WHERE/GROUP BY/ORDER BY) whose select list
    // exceeds line_width 100: measure-then-break puts one item per line at
    // indent+1 (Pattern 2), clause keywords break at column 0 (Pattern 1).
    {
      fixture_id: "3.x-select-multiclause-long-list",
      profile: "3.x",
      mode: "strict",
      raw: b"select user_id, user_name, user_email, user_phone, user_address, user_status, user_created_at, user_updated_at from user_profile where user_status = 'active' group by user_id order by user_created_at",
      expected_valid: true,
      expected_golden: b"SELECT\n  user_id,\n  user_name,\n  user_email,\n  user_phone,\n  user_address,\n  user_status,\n  user_created_at,\n  user_updated_at\nFROM user_profile\nWHERE user_status = 'active'\nGROUP BY user_id\nORDER BY user_created_at\n",
    },
    // Error tree (unsupported statement): absolute refusal, empty output.
    {
      fixture_id: "4.x-error-tree-refusal",
      profile: "4.x",
      mode: "strict",
      raw: b"drop table x",
      expected_valid: false,
      expected_golden: b"",
    },
    // Version-invalid 2.1 MERGE (SourceError leaf): refusal with DORIS-FORMAT-001.
    {
      fixture_id: "2.1-merge-version-invalid-refusal",
      profile: "2.1",
      mode: "strict",
      raw: b"MERGE INTO t USING s ON a=b WHEN MATCHED THEN UPDATE SET x=1",
      expected_valid: false,
      expected_golden: b"",
    },
    // Empty input: accepted, empty output, no diagnostics.
    {
      fixture_id: "4.x-empty",
      profile: "4.x",
      mode: "strict",
      raw: b"",
      expected_valid: true,
      expected_golden: b"",
    },
    // CRLF input: \r\n preserved byte-for-byte (flagged assumption A2).
    {
      fixture_id: "4.x-crlf",
      profile: "4.x",
      mode: "strict",
      raw: b"select a\r\nfrom t",
      expected_valid: true,
      expected_golden: b"SELECT a\r\nFROM t\r\n",
    },
  ]
  for fixture in fixtures {
    assert_true(formatter_fixture_ok(fixture))
  }
}

test "formatter_options_default_and_validation" {
  let defaults = @formatter.FormatOptions::default()
  assert_true(defaults.keyword_case() is @formatter.KeywordCase::Upper)
  assert_eq(defaults.indent(), 2)
  assert_eq(defaults.line_width(), 100)
  assert_true(defaults.comma_style() is @formatter.CommaStyle::Trailing)
  assert_true(defaults.newline_style() is @formatter.NewlineStyle::FollowInput)
  assert_true(defaults.trailing_newline())
  // ASVS V5: invalid config fails construction, never reaches layout.
  let bad_indent = @formatter.FormatOptions::new(
    @formatter.KeywordCase::Upper,
    -1,
    100,
    @formatter.CommaStyle::Trailing,
    @formatter.NewlineStyle::FollowInput,
    true,
  )
  assert_true(bad_indent is Err(@formatter.FormatError::InvalidIndent(value=-1)))
  let bad_width = @formatter.FormatOptions::new(
    @formatter.KeywordCase::Upper,
    2,
    0,
    @formatter.CommaStyle::Trailing,
    @formatter.NewlineStyle::FollowInput,
    true,
  )
  assert_true(bad_width is Err(@formatter.FormatError::InvalidLineWidth(value=0)))
}

test "formatter_refusal_never_masks_parse_diagnostics" {
  // Threat T-03-01: format_text converts DORIS-PARSE-* diagnostics and
  // prepends them so DORIS-FORMAT-001 never masks parse errors.
  let raw = b"MERGE INTO t USING s ON a=b WHEN MATCHED THEN UPDATE SET x=1"
  let options = @formatter.FormatOptions::default()
  let parse_options = match @api.ParseOptions::new("2.1", "strict") {
    Ok(options) => options
    Err(_) => panic()
  }
  let result = match @api.format_text(raw, parse_options, options) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!result.accepted)
  assert_eq(result.output.length(), 0)
  assert_true(result.diagnostics.length() >= 2)
  assert_true(result.diagnostics[0].code.has_prefix("DORIS-PARSE-"))
  assert_true(result.diagnostics[0].code == "DORIS-PARSE-006")
  // Exactly one DORIS-FORMAT-001, and it comes after the parse diagnostics.
  let mut format_count = 0
  for diagnostic in result.diagnostics {
    if diagnostic.code == "DORIS-FORMAT-001" {
      format_count = format_count + 1
    }
  }
  assert_eq(format_count, 1)
  assert_eq(result.diagnostics[result.diagnostics.length() - 1].code, "DORIS-FORMAT-001")
  // The diagnostic shape mirrors PrimitiveDiagnostic fields.
  let refusal = result.diagnostics[result.diagnostics.length() - 1]
  assert_eq(refusal.severity, "error")
  assert_eq(refusal.expected_class, "format")
  assert_true(refusal.start_byte <= refusal.end_byte)
  assert_eq(refusal.statement_id, 0U)
}
