/// api.lint_text / api.fix_text integration tests (LINT-01, 06-03 Task 1).
/// Run through the real parser behind @api — proves the raw -> parse -> lint
/// -> (fix) pipeline and the D-33 refusal path.

fn lint_options() -> @api.ParseOptions {
  match @api.ParseOptions::new("doris", "4.x", "strict") {
    Ok(options) => options
    Err(_) => panic()
  }
}

test "lint_text_reports_select_star_without_limit" {
  let result = match @api.lint_text(b"SELECT * FROM t", lint_options(), @api.LintOptions::default()) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(result.accepted, true)
  let mut found_003 = false
  for finding in result.findings {
    if finding.code == "FATHOM-LINT-003" {
      found_003 = true
    }
  }
  assert_true(found_003)
}

test "lint_text_reports_unquoted_reserved_word_on_recoverable_tree" {
  // `order` is reserved; the parser emits a recoverable tree (missing node)
  // but run_rules still scans the tokens and flags the reserved word as an
  // unquoted identifier (rule 001, narrow projection scope).
  let result = match @api.lint_text(b"SELECT order FROM t", lint_options(), @api.LintOptions::default()) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(result.accepted, true)
  let mut found_001 = false
  for finding in result.findings {
    if finding.code == "FATHOM-LINT-001" {
      found_001 = true
    }
  }
  assert_true(found_001)
}

test "lint_text_empty_input_zero_findings" {
  let result = match @api.lint_text(b"", lint_options(), @api.LintOptions::default()) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(result.accepted, true)
  assert_eq(result.findings.length(), 0)
}

test "fix_text_valid_input_no_fixable_findings_returns_unchanged" {
  // Valid input with no fixable findings: accepted=true, output unchanged.
  let result = match @api.fix_text(b"SELECT * FROM t", lint_options(), @api.LintOptions::default()) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(result.accepted, true)
  assert_eq(result.output, b"SELECT * FROM t")
}

test "fix_text_refuses_tree_with_unsafe_material_d33" {
  // `SELECT order FROM t` parses to a recoverable tree containing a `missing`
  // node (reserved word not accepted as identifier) -> D-33 refusal:
  // accepted=false, empty output, exactly one FATHOM-LINT-000.
  let result = match @api.fix_text(b"SELECT order FROM t", lint_options(), @api.LintOptions::default()) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(result.accepted, false)
  assert_eq(result.output, b"")
  assert_eq(result.diagnostics.length(), 1)
  assert_eq(result.diagnostics[0].code, "FATHOM-LINT-000")
}

test "lint_text_propagates_selection_errors" {
  // Unknown dialect -> structured error (no fallback) at ParseOptions::new.
  match @api.ParseOptions::new("bogus", "4.x", "strict") {
    Err(@api.ParseError::UnknownDialect(dialect_id~)) => assert_eq(dialect_id, "bogus")
    _ => assert_true(false)
  }
}
