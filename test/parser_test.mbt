fn parse_strict(raw : Bytes) -> @api.ParseResult {
  match @api.parse_with_ids(raw, "3.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
}

fn parse_editor_parser(raw : Bytes) -> @api.ParseResult {
  match @api.parse_with_ids(raw, "3.x", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
}

test "select_and_later_statement_keep_source_order_and_ids" {
  let result = parse_strict(b"SELECT a + 1; bad; SELECT b")
  assert_eq(@printer.print_result(result), b"SELECT a + 1; bad; SELECT b")
  assert_eq(result.root.children.length(), 3)
  assert_true(!result.valid)
  assert_true(result.diagnostics.length() >= 1)
  let bad = result.diagnostics[0]
  assert_true(bad.start_byte <= bad.end_byte)
  assert_eq(bad.statement_id, 1)
}

test "strict_and_editor_share_shape_but_not_validity" {
  let strict = parse_strict(b"SELECT 1 +")
  let editor = parse_editor_parser(b"SELECT 1 +")
  assert_eq(strict.root.kind, editor.root.kind)
  assert_eq(strict.root.text_len, editor.root.text_len)
  assert_true(!strict.valid)
  assert_true(!editor.valid)
  assert_true(editor.recovered)
  assert_eq(strict.diagnostics.length(), editor.diagnostics.length())
}

test "diagnostic_identity_resets_for_each_snapshot" {
  let first = parse_strict(b"bad; bad")
  let second = parse_strict(b"bad; bad")
  assert_eq(first.diagnostics[0].statement_id, 0)
  assert_eq(first.diagnostics[1].statement_id, 1)
  assert_eq(second.diagnostics[0].statement_id, 0)
  assert_eq(second.diagnostics[1].statement_id, 1)
}

test "join_modifiers_require_join_and_condition" {
  let malformed = [b"SELECT a FROM t LEFT", b"SELECT a FROM t LEFT JOIN u", b"SELECT a FROM t INNER JOIN u"]
  for raw in malformed {
    let result = match @api.parse_with_ids(raw, "4.x", "strict") {
      Ok(result) => result
      Err(_) => panic()
    }
    assert_true(!result.valid)
    assert_true(result.diagnostics.length() > 0)
    assert_eq(@printer.print_result(result), raw)
  }
  for raw in [b"SELECT a FROM t CROSS JOIN u", b"SELECT a FROM t NATURAL JOIN u"] {
    let result = match @api.parse_with_ids(raw, "4.x", "strict") {
      Ok(result) => result
      Err(_) => panic()
    }
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
  }
}

test "projection_aliases_support_implicit_explicit_and_quoted_forms" {
  let raws = [
    b"SELECT k total FROM t",
    b"SeLeCt k ToTaL, v AS amount FrOm t",
    b"SELECT k total, v `MiXeD` FROM t",
  ]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "4.x", mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(result.valid)
      assert_eq(result.diagnostics.length(), 0)
      assert_eq(@printer.print_result(result), raw)
    }
  }
}

test "natural_directional_joins_are_conditionless_and_case_insensitive" {
  let raws = [
    b"SELECT a FROM t NATURAL LEFT JOIN u",
    b"SELECT a FROM t NATURAL RIGHT OUTER JOIN u",
    b"SeLeCt a FrOm t NaTuRaL rIgHt oUtEr JoIn u",
  ]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "4.x", mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(result.valid)
      assert_eq(result.diagnostics.length(), 0)
      assert_eq(@printer.print_result(result), raw)
    }
  }
}



test "projection_trailing_comma_is_explicitly_missing" {
  for raw in [b"SELECT a, FROM t", b"SELECT a, UNION SELECT b", b"SELECT a,)"] {
    let result = match @api.parse_with_ids(raw, "4.x", "editor") {
      Ok(result) => result
      Err(_) => panic()
    }
    assert_true(!result.valid)
    assert_true(result.diagnostics.length() > 0)
    assert_eq(@printer.print_result(result), raw)
    assert_true(has_kind(result.root, "missing"))
  }
}

test "empty_grouping_productions_are_rejected" {
  for raw in [b"SELECT a FROM t GROUP BY GROUPING SETS ()", b"SELECT a FROM t GROUP BY ROLLUP ()", b"SELECT a FROM t GROUP BY CUBE ()"] {
    let result = match @api.parse_with_ids(raw, "4.x", "editor") {
      Ok(result) => result
      Err(_) => panic()
    }
    assert_true(!result.valid)
    assert_true(result.diagnostics.length() > 0)
    assert_eq(@printer.print_result(result), raw)
  }
}

test "industrial_select_covers_cte_join_window_grouping_and_union" {
  let raw = b"WITH recent AS (SELECT /*+ SET_VAR(exec_mem_limit=1G) */ DISTINCT f.k, SUM(f.v) OVER (PARTITION BY f.k ORDER BY f.ts ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS total FROM fact PARTITION(p0) SAMPLE(10) f LEFT OUTER JOIN dim d ON f.k = d.k WHERE f.v IN (1, 2) AND d.active IS NOT NULL GROUP BY GROUPING SETS ((f.k), (f.k, d.kind)) HAVING SUM(f.v) > 0) SELECT k, total FROM recent ORDER BY total DESC LIMIT 10 UNION ALL SELECT k, total FROM recent"
  let result = match @api.parse_with_ids(raw, "3.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(result.valid)
  assert_eq(result.diagnostics.length(), 0)
  assert_eq(@printer.print_result(result), raw)
  assert_true(result.root.children.length() == 1)
  assert_true(result.root.children[0].children.length() > 0)
}

test "released_profiles_gate_qualify_without_generic_fallback" {
  let raw = b"SELECT row_number() OVER (ORDER BY k) AS rn FROM t QUALIFY rn = 1"
  let old = match @api.parse_with_ids(raw, "2.1", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  let released = match @api.parse_with_ids(raw, "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!old.valid)
  assert_true(old.diagnostics.length() > 0)
  assert_eq(old.diagnostics[0].code, "DORIS-PARSE-006")
  assert_eq(old.diagnostics[0].statement_id, 0)
  assert_eq(old.diagnostics[0].end_byte - old.diagnostics[0].start_byte, 7)
  let editor = match @api.parse_with_ids(raw, "2.1", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!editor.valid)
  assert_true(editor.recovered)
  assert_true(has_kind(editor.root, "error"))
  assert_true(released.valid)
  assert_eq(@printer.print_result(old), raw)
  assert_eq(@printer.print_result(released), raw)
}

test "version_gate_diagnostic_spans_offending_tablet_keyword" {
  let raw = b"SELECT k FROM t TABLET (1)"
  let result = match @api.parse_with_ids(raw, "2.1", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!result.valid)
  let mut found = false
  for diagnostic in result.diagnostics {
    if diagnostic.code == "DORIS-PARSE-006" {
      found = true
      assert_eq(diagnostic.end_byte - diagnostic.start_byte, 6)
    }
  }
  assert_true(found)
}
test "version_invalid_features_share_metadata_gate_and_editor_shape" {
  let raw = b"SELECT k FROM t TABLET (1)"
  let strict = match @api.parse_with_ids(raw, "2.1", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  let editor = match @api.parse_with_ids(raw, "2.1", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!strict.valid)
  assert_true(!editor.valid)
  assert_true(editor.recovered)
  assert_eq(strict.diagnostics.length(), editor.diagnostics.length())
  assert_eq(strict.diagnostics[0].code, @token.DorisFeature::Tablet.metadata().diagnostic_code)
  assert_eq(strict.diagnostics[0].start_byte, editor.diagnostics[0].start_byte)
  assert_eq(strict.diagnostics[0].end_byte, editor.diagnostics[0].end_byte)
  assert_eq(strict.diagnostics[0].statement_id, editor.diagnostics[0].statement_id)
  assert_true(has_kind(editor.root, "error"))
  assert_eq(@printer.print_result(editor), raw)
}

test "gated_feature_spellings_are_contextual_outside_productions" {
  let raws = [b"SELECT tablet FROM t", b"SELECT k AS tablet FROM t"]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "2.1", mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(result.valid)
      assert_eq(result.diagnostics.length(), 0)
      assert_true(!has_kind(result.root, "error"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
}

test "mixed_case_gated_productions_keep_invalid_events_source_backed" {
  let raws = [
    b"SeLeCt k FrOm t TaBlEt (1)",
    b"SeLeCt k FrOm t QuAlIfY k = 1",
  ]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "2.1", mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(!result.valid)
      assert_true(result.diagnostics.any(d => d.code == "DORIS-PARSE-006"))
      assert_true(has_kind(result.root, "error"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
}


test "projection_clause_boundary_is_case_insensitive" {
  let malformed = match @api.parse_with_ids(b"SELECT a, from", "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!malformed.valid)
  assert_true(malformed.diagnostics.any(d => d.code == "DORIS-PARSE-002"))
  assert_true(has_kind(malformed.root, "missing"))
  assert_eq(@printer.print_result(malformed), b"SELECT a, from")
  let mixed = match @api.parse_with_ids(b"SELECT a, FrOm", "4.x", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!mixed.valid)
  assert_true(mixed.recovered)
  assert_true(mixed.diagnostics.any(d => d.code == "DORIS-PARSE-002"))
  assert_true(has_kind(mixed.root, "missing"))
  assert_eq(@printer.print_result(mixed), b"SELECT a, FrOm")
  let valid = match @api.parse_with_ids(b"select a from t where b = 1", "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(valid.valid)
  assert_eq(valid.diagnostics.length(), 0)
  assert_eq(@printer.print_result(valid), b"select a from t where b = 1")
}

test "industrial_boundary_set_chains_and_contextual_identifiers" {
  let raw = b"SELECT 1 UNION SELECT 2 UNION ALL SELECT 3; SELECT `group`, `window` FROM `table`"
  let result = match @api.parse_with_ids(raw, "2.1", "editor") {

    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(result.valid)
  assert_eq(result.diagnostics.length(), 0)
  assert_eq(@printer.print_result(result), raw)
  assert_eq(result.root.children.length(), 2)
}
test "trailing_trivia_after_semicolon_is_not_a_statement" {
  let raw = b"SELECT 1; -- trailing\n  "
  let result = match @api.parse_with_ids(raw, "4.x", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(result.root.children.length() > 1)
  let mut statement_count = 0
  for child in result.root.children {
    if child.kind == "statement" { statement_count = statement_count + 1 }
  }
  assert_eq(statement_count, 1)
  assert_true(result.valid)
  assert_eq(@printer.print_result(result), raw)
}
test "semicolon_trivia_segments_do_not_create_error_statements" {
  let raws = [
    b"SELECT 1; -- trailing\n; SELECT 2",
    b"SELECT 1;; SELECT 2",
    b"SELECT 1; /* middle */\n; SELECT 2",
  ]
  for raw in raws {
    let result = match @api.parse_with_ids(raw, "4.x", "editor") {
      Ok(result) => result
      Err(_) => panic()
    }
    let mut statement_count = 0
    for child in result.root.children {
      if child.kind == "statement" { statement_count = statement_count + 1 }
      assert_true(child.kind != "error")
    }
    assert_eq(statement_count, 2)
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
    assert_eq(@printer.print_result(result), raw)
  }
}
test "semicolon_trivia_preserves_following_statement_identity" {
  let raw = b"SELECT 1;; -- middle\n; bad"
  let result = match @api.parse_with_ids(raw, "4.x", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!result.valid)
  assert_eq(@printer.print_result(result), raw)
  assert_true(result.diagnostics.any(d => d.statement_id == 1))
  let mut statement_count = 0
  for child in result.root.children {
    if child.kind == "statement" { statement_count = statement_count + 1 }
    assert_true(child.kind != "error" || child.start_byte > 0)
  }
  assert_eq(statement_count, 2)
}
fn fixture_replay_ok(raw : Bytes, profile : String, mode : String, expected_valid : Bool) -> Bool {
  let result = match @api.parse_with_ids(raw, profile, mode) {
    Ok(result) => result
    Err(_) => return false
  }
  if @printer.print_result(result) != raw || result.valid != expected_valid || !result.all_spans_in_bounds() { return false }
  for diagnostic in result.diagnostics {
    if !diagnostic.code.has_prefix("DORIS-PARSE-") || diagnostic.start_byte > diagnostic.end_byte || diagnostic.statement_id < 0 { return false }
  }
  true
}

test "released_manifest_schema_contract_records_loader_gap" {
  // MoonBit's current core test package has no filesystem API. The Git-tracked
  // TSV therefore cannot be opened here; this test is a schema/linkage check,
  // not a claim that the runtime loader is manifest-driven.
  let filesystem_loader_available = false
  assert_true(!filesystem_loader_available)
  let manifest_header = "fixture_id\\tprofile\\texact_release\\tfeature_introduction\\tofficial_url\\tretrieval_date\\tpinned_source_revision\\tpage_heading\\tcode_fence\\tcategory\\tsupport_status\\tparse_mode\\tclassification\\tprovenance_status"
  assert_eq(manifest_header.split("\\t").length(), 14)
  let rows : Array[Array[String]] = [
    ["2.1-industrial", "2.1", "2.1", "2.1 baseline SELECT", "https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-query/SELECT/", "2026-08-03", "unavailable-offline", "SELECT", "grammar:sql", "industrial-select", "supported", "strict", "parse-only", "known-gap"],
    ["3.x-industrial", "3.x", "3.x", "2.1 baseline; 3.x window and QUALIFY", "https://doris.apache.org/docs/3.x/sql-manual/sql-statements/data-query/SELECT/", "2026-08-03", "unavailable-offline", "SELECT", "grammar:sql", "industrial-select", "supported", "strict", "parse-only", "known-gap"],
    ["4.x-industrial", "4.x", "4.x", "2.1 baseline; 4.x released SELECT", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/", "2026-08-03", "unavailable-offline", "SELECT", "grammar:sql", "industrial-select", "supported", "strict", "parse-only", "known-gap"],
    ["2.1-invalid-encoding", "2.1", "2.1", "2.1 baseline SELECT", "https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-query/SELECT/", "2026-08-03", "unavailable-offline", "SELECT", "grammar:sql", "invalid-encoding", "expected-error", "editor", "expected-error", "known-gap"],
    ["3.x-unsupported-profile", "2.1", "2.1", "3.x QUALIFY", "https://doris.apache.org/docs/3.x/sql-manual/sql-statements/data-query/SELECT/", "2026-08-03", "unavailable-offline", "SELECT", "grammar:sql", "unsupported-version", "expected-error", "strict", "expected-error", "known-gap"],
  ]
  assert_eq(rows.length(), 5)
  for row in rows {
    assert_eq(row.length(), 14)
    assert_true(row[1] == "2.1" || row[1] == "3.x" || row[1] == "4.x")
    assert_true(row[2] == row[1] || row[0] == "3.x-unsupported-profile")
    assert_true(row[4].has_prefix("https://doris.apache.org/docs/"))
    assert_eq(row[5], "2026-08-03")
    assert_true(row[6].length() > 0)
    assert_eq(row[7], "SELECT")
    assert_true(row[8].has_prefix("grammar:"))
    assert_true(row[10] == "supported" || row[10] == "expected-error")
    assert_true(row[11] == "strict" || row[11] == "editor")
    assert_true(row[12] == "parse-only" || row[12] == "expected-error")
    assert_eq(row[13], "known-gap")
  }
  assert_true(fixture_replay_ok(b"SELECT 1", "2.1", "strict", true))
  assert_true(fixture_replay_ok(b"WITH c AS (SELECT k FROM t) SELECT k FROM c UNION ALL SELECT k FROM t2", "3.x", "editor", true))
  assert_true(fixture_replay_ok(b"SELECT (((1)))", "4.x", "strict", true))
  assert_true(fixture_replay_ok(b"SELECT k +", "4.x", "editor", false))
  assert_true(fixture_replay_ok(b"SELECT \xff", "2.1", "editor", false))
}

test "projection_modifiers_accept_all_except_and_distinctrow" {
  let raws = [b"SELECT ALL EXCEPT (secret) FROM fact", b"SELECT DISTINCTROW k FROM fact"]
  for raw in raws {
    let result = match @api.parse_with_ids(raw, "2.1", "strict") {
      Ok(result) => result
      Err(_) => panic()
    }
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
    assert_eq(@printer.print_result(result), raw)
  }
}