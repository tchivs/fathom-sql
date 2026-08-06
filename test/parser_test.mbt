fn parse_strict(raw : Bytes) -> @api.ParseResult {
  match @api.parse_with_ids(raw, "doris", "3.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
}

fn parse_editor_parser(raw : Bytes) -> @api.ParseResult {
  match @api.parse_with_ids(raw, "doris", "3.x", "editor") {
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
  assert_eq(bad.statement_id, 1U)
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

test "malformed_expression_and_window_create_explicit_recovery_nodes" {
  let raws = [b"SELECT 1 +", b"SELECT SUM(x) OVER ("]
  for raw in raws {
    let strict = match @api.parse_with_ids(raw, "doris", "4.x", "strict") {
      Ok(result) => result
      Err(_) => panic()
    }
    let editor = match @api.parse_with_ids(raw, "doris", "4.x", "editor") {
      Ok(result) => result
      Err(_) => panic()
    }
    for result in [strict, editor] {
      assert_true(!result.valid)
      assert_true(result.diagnostics.length() > 0)
      assert_eq(result.diagnostics[0].code, "FATHOM-PARSE-002")
      assert_eq(result.diagnostics[0].statement_id, 0U)
      assert_eq(result.diagnostics[0].start_byte, raw.length())
      assert_eq(result.diagnostics[0].end_byte, raw.length())
      assert_true(has_kind(result.root, "missing") || has_kind(result.root, "error"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
    assert_eq(strict.root.kind, editor.root.kind)
    assert_eq(strict.root.text_len, editor.root.text_len)
  }
}

test "diagnostic_identity_resets_for_each_snapshot" {
  let first = parse_strict(b"bad; bad")
  let second = parse_strict(b"bad; bad")
  assert_eq(first.diagnostics[0].statement_id, 0U)
  assert_eq(first.diagnostics[1].statement_id, 1U)
  assert_eq(second.diagnostics[0].statement_id, 0U)
  assert_eq(second.diagnostics[1].statement_id, 1U)
}

test "join_modifiers_require_join_and_condition" {
  let malformed = [b"SELECT a FROM t LEFT", b"SELECT a FROM t LEFT JOIN u", b"SELECT a FROM t INNER JOIN u"]
  for raw in malformed {
    let result = match @api.parse_with_ids(raw, "doris", "4.x", "strict") {
      Ok(result) => result
      Err(_) => panic()
    }
    assert_true(!result.valid)
    assert_true(result.diagnostics.length() > 0)
    assert_eq(@printer.print_result(result), raw)
  }
  for raw in [b"SELECT a FROM t CROSS JOIN u", b"SELECT a FROM t NATURAL JOIN u"] {
    let result = match @api.parse_with_ids(raw, "doris", "4.x", "strict") {
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
      let result = match @api.parse_with_ids(raw, "doris", "4.x", mode) {
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
      let result = match @api.parse_with_ids(raw, "doris", "4.x", mode) {
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
    let result = match @api.parse_with_ids(raw, "doris", "4.x", "editor") {
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
    let result = match @api.parse_with_ids(raw, "doris", "4.x", "editor") {
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
  let result = match @api.parse_with_ids(raw, "doris", "3.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(result.valid)
  assert_eq(result.diagnostics.length(), 0)
  assert_eq(@printer.print_result(result), raw)
  assert_true(result.root.children.length() == 1)
  assert_true(result.root.children[0].children.length() > 0)
}

test "released_tablet_tablesample_repeatable_forms_keep_profile_gate" {
  let raws = [
    b"SELECT * FROM t1 TABLET(10001) TABLESAMPLE(1000 ROWS) REPEATABLE 2 LIMIT 1000",
    b"SELECT * FROM t1 TABLET (10001) TABLESAMPLE (10 PERCENT) REPEATABLE (2) LIMIT 1000",
  ]
  for raw in raws {
    for profile in ["2.1", "3.x", "4.x"] {
      for mode in ["strict", "editor"] {
        let result = match @api.parse_with_ids(raw, "doris", profile, mode) {
          Ok(result) => result
          Err(_) => panic()
        }
        if profile == "2.1" {
          assert_true(!result.valid)
          assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-006"))
          if mode == "editor" { assert_true(result.recovered) }
        } else {
          assert_true(result.valid)
          assert_eq(result.diagnostics.length(), 0)
        }
        assert_eq(@printer.print_result(result), raw)
        assert_true(result.all_spans_in_bounds())
      }
    }
  }
}

test "released_profiles_gate_qualify_without_generic_fallback" {
  let raw = b"SELECT row_number() OVER (ORDER BY k) AS rn FROM t QUALIFY rn = 1"
  let old = match @api.parse_with_ids(raw, "doris", "2.1", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  let released = match @api.parse_with_ids(raw, "doris", "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!old.valid)
  assert_true(old.diagnostics.length() > 0)
  assert_eq(old.diagnostics[0].code, "FATHOM-PARSE-006")
  assert_eq(old.diagnostics[0].statement_id, 0U)
  assert_eq(old.diagnostics[0].end_byte - old.diagnostics[0].start_byte, 7)
  let editor = match @api.parse_with_ids(raw, "doris", "2.1", "editor") {
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

test "released_projection_star_except_is_explicit_and_lossless" {
  let raw = b"SELECT * EXCEPT(age) FROM student"
  for profile in ["2.1", "3.x", "4.x"] {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "doris", profile, mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(result.valid)
      assert_eq(result.diagnostics.length(), 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
  for raw in [b"SELECT * EXCEPT () FROM student", b"SELECT * EXCEPT (age,) FROM student"] {
    let strict = parse_strict(raw)
    let editor = parse_editor_parser(raw)
    for result in [strict, editor] {
      assert_true(!result.valid)
      assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-002"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
    assert_eq(strict.diagnostics.length(), editor.diagnostics.length())
  }
}

test "version_gate_diagnostic_spans_offending_tablet_keyword" {
  let raw = b"SELECT k FROM t TABLET (1)"
  let result = match @api.parse_with_ids(raw, "doris", "2.1", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!result.valid)
  let mut found = false
  for diagnostic in result.diagnostics {
    if diagnostic.code == "FATHOM-PARSE-006" {
      found = true
      assert_eq(diagnostic.end_byte - diagnostic.start_byte, 6)
    }
  }
  assert_true(found)
}
test "version_invalid_features_share_metadata_gate_and_editor_shape" {
  let raw = b"SELECT k FROM t TABLET (1)"
  let strict = match @api.parse_with_ids(raw, "doris", "2.1", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  let editor = match @api.parse_with_ids(raw, "doris", "2.1", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!strict.valid)
  assert_true(!editor.valid)
  assert_true(editor.recovered)
  assert_eq(strict.diagnostics.length(), editor.diagnostics.length())
  assert_eq(strict.diagnostics[0].code, @dialect.DorisFeature::Tablet.metadata().diagnostic_code)
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
      let result = match @api.parse_with_ids(raw, "doris", "2.1", mode) {
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

test "tablet_table_alias_is_contextual_without_option_parenthesis" {
  let aliases = [b"SELECT a FROM t tablet", b"SELECT a FROM t AS TaBlEt"]
  for raw in aliases {
    for profile in ["2.1", "3.x", "4.x"] {
      for mode in ["strict", "editor"] {
        let result = match @api.parse_with_ids(raw, "doris", profile, mode) {
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
}

test "tablet_option_parenthesis_retains_profile_gate" {
  let raw = b"SELECT a FROM t TaBlEt (1)"
  for profile in ["2.1", "3.x", "4.x"] {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "doris", profile, mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      if profile == "2.1" {
        assert_true(!result.valid)
        assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-006"))
        if mode == "editor" { assert_true(has_kind(result.root, "error")) }
      } else {
        assert_true(result.valid)
        assert_eq(result.diagnostics.length(), 0)
      }
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
      let result = match @api.parse_with_ids(raw, "doris", "2.1", mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(!result.valid)
      assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-006"))
      assert_true(has_kind(result.root, "error"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
}


test "projection_clause_boundary_is_case_insensitive" {
  let malformed = match @api.parse_with_ids(b"SELECT a, from", "doris", "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!malformed.valid)
  assert_true(malformed.diagnostics.any(d => d.code == "FATHOM-PARSE-002"))
  assert_true(has_kind(malformed.root, "missing"))
  assert_eq(@printer.print_result(malformed), b"SELECT a, from")
  let mixed = match @api.parse_with_ids(b"SELECT a, FrOm", "doris", "4.x", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!mixed.valid)
  assert_true(mixed.recovered)
  assert_true(mixed.diagnostics.any(d => d.code == "FATHOM-PARSE-002"))
  assert_true(has_kind(mixed.root, "missing"))
  assert_eq(@printer.print_result(mixed), b"SELECT a, FrOm")
  let valid = match @api.parse_with_ids(b"select a from t where b = 1", "doris", "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(valid.valid)
  assert_eq(valid.diagnostics.length(), 0)
  assert_eq(@printer.print_result(valid), b"select a from t where b = 1")
}

test "industrial_boundary_set_chains_and_contextual_identifiers" {
  let raw = b"SELECT 1 UNION SELECT 2 UNION ALL SELECT 3; SELECT `group`, `window` FROM `table`"
  let result = match @api.parse_with_ids(raw, "doris", "2.1", "editor") {

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
  let result = match @api.parse_with_ids(raw, "doris", "4.x", "editor") {
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
    let result = match @api.parse_with_ids(raw, "doris", "4.x", "editor") {
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
  let result = match @api.parse_with_ids(raw, "doris", "4.x", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!result.valid)
  assert_eq(@printer.print_result(result), raw)
  assert_true(result.diagnostics.any(d => d.statement_id == 1U))
  let mut statement_count = 0
  for child in result.root.children {
    if child.kind == "statement" { statement_count = statement_count + 1 }
    assert_true(child.kind != "error" || child.start_byte > 0)
  }
  assert_eq(statement_count, 2)
}
struct EmbeddedManifestFixture {
  fixture_id : String
  profile : String
  exact_release : String
  feature_introduction : String
  raw : Bytes
  mode : String
  expected_valid : Bool
}

fn metadata_fixture_replay_ok(fixture : EmbeddedManifestFixture) -> Bool {
  let result = match @api.parse_with_metadata(
    fixture.raw,
    "doris",
    fixture.profile,
    fixture.exact_release,
    fixture.feature_introduction,
    fixture.mode,
  ) {
    Ok(result) => result
    Err(_) => return false
  }
  if @printer.print_result(result) != fixture.raw || result.valid != fixture.expected_valid ||
    !result.all_spans_in_bounds() || result.profile != fixture.profile ||
    result.exact_release != fixture.exact_release ||
    result.feature_introduction != fixture.feature_introduction {
    return false
  }
  for diagnostic in result.diagnostics {
    if !diagnostic.code.has_prefix("FATHOM-PARSE-") || diagnostic.start_byte > diagnostic.end_byte {
      return false
    }
  }
  true
}

test "released_manifest_metadata_drives_deterministic_parse_replay" {
  let fixtures = [
    {
      fixture_id: "2.1-industrial",
      profile: "2.1",
      exact_release: "2.1",
      feature_introduction: "2.1 baseline SELECT; DML/DDL released",
      raw: b"SELECT 1",
      mode: "strict",
      expected_valid: true,
    },
    {
      fixture_id: "3.x-industrial",
      profile: "3.x",
      exact_release: "3.x",
      feature_introduction: "2.1 baseline SELECT; DML/DDL released; 3.x window and QUALIFY",
      raw: b"WITH c AS (SELECT k FROM t) SELECT k FROM c UNION ALL SELECT k FROM t2",
      mode: "editor",
      expected_valid: true,
    },
    {
      fixture_id: "4.x-industrial",
      profile: "4.x",
      exact_release: "4.x",
      feature_introduction: "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT",
      raw: b"SELECT (((1)))",
      mode: "strict",
      expected_valid: true,
    },
    {
      fixture_id: "2.1-invalid-encoding",
      profile: "2.1",
      exact_release: "2.1",
      feature_introduction: "2.1 baseline SELECT; DML/DDL released",
      raw: b"SELECT \xff",
      mode: "editor",
      expected_valid: false,
    },
    {
      fixture_id: "4.x-recovery",
      profile: "4.x",
      exact_release: "4.x",
      feature_introduction: "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT",
      raw: b"SELECT k +",
      mode: "editor",
      expected_valid: false,
    },
  ]
  assert_eq(fixtures.length(), 5)
  for fixture in fixtures {
    assert_true(fixture.fixture_id.length() > 0)
    assert_true(metadata_fixture_replay_ok(fixture))
  }
}

test "metadata_mismatch_unknown_and_unsupported_rows_are_rejected_before_parse" {
  assert_true(@api.parse_with_metadata(
    b"SELECT 1", "doris", "2.1", "2.0", "2.1 baseline SELECT; DML/DDL released", "strict",
  ) is Err(@api.ParseError::ProfileMetadataMismatch(..)))
  assert_true(@api.parse_with_metadata(
    b"SELECT 1", "doris", "2.1", "2.1", "3.x QUALIFY", "strict",
  ) is Err(@api.ParseError::UnsupportedFeatureIntroduction(..)))
  assert_true(@api.parse_with_metadata(
    b"SELECT 1", "doris", "2.1", "2.1", "2.1 baseline SELECT; DML/DDL released; 3.x window and QUALIFY", "strict",
  ) is Err(@api.ParseError::ProfileMetadataMismatch(..)))
  assert_true(@api.parse_with_metadata(
    b"SELECT 1", "doris", "5.x", "5.x", "5.x released SELECT", "strict",
  ) is Err(@api.ParseError::UnknownProfile(..)))
  let canonical = @dialect.DorisProfile::V3_X.metadata()
  let options = match @api.ParseOptions::for_profile_with_metadata(
    @dialect.DorisProfile::V3_X,
    canonical,
    @api.ParseMode::Strict,
  ) {
    Ok(options) => options
    Err(_) => panic()
  }
  assert_eq(options.profile_metadata().exact_release, "3.x")
  assert_eq(options.profile_metadata().feature_introduction, "2.1 baseline SELECT; DML/DDL released; 3.x window and QUALIFY")
}

test "projection_modifiers_accept_all_except_and_distinctrow" {
  let raws = [b"SELECT ALL EXCEPT (secret) FROM fact", b"SELECT DISTINCTROW k FROM fact"]
  for raw in raws {
    let result = match @api.parse_with_ids(raw, "doris", "2.1", "strict") {
      Ok(result) => result
      Err(_) => panic()
    }
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
    assert_eq(@printer.print_result(result), raw)
  }
}

test "wildcards_are_scoped_to_projection_and_count_argument_contexts" {
  let malformed = [
    b"SELECT 1 + * FROM t",
    b"SELECT * + 1 FROM t",
    b"SELECT t.* + 1 FROM t",
    b"SELECT a FROM t WHERE *",
    b"SELECT a FROM t WHERE t.*",
    b"SELECT SUM(*) FROM t",
    b"SELECT COALESCE(*) FROM t",
    b"SELECT COUNT(t.*) FROM t",
    b"SELECT COUNT(*, x) FROM t",
    b"SELECT COUNT(*, x, y) FROM t",
  ]
  for raw in malformed {
    let strict = parse_strict(raw)
    let editor = parse_editor_parser(raw)
    for result in [strict, editor] {
      assert_true(!result.valid)
      assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-002"))
      assert_true(result.diagnostics.any(d => d.start_byte < d.end_byte))
      assert_true(has_kind(result.root, "missing") || has_kind(result.root, "error"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
    assert_true(editor.recovered)
    assert_eq(strict.diagnostics.length(), editor.diagnostics.length())
  }
  let valid = [
    b"SELECT * FROM t",
    b"SELECT t.* FROM t",
    b"SELECT COUNT(*) FROM t",
    b"SELECT COUNT(x) FROM t",
    b"SELECT COUNT(x, y) FROM t",
    b"SELECT SUM(x, y), COALESCE(x, y) FROM t",
    b"SELECT * AS all_cols, t.* qualified FROM t",
  ]
  for raw in valid {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "doris", "4.x", mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(result.valid)
      assert_eq(result.diagnostics.length(), 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
}


test "balanced_options_require_nonempty_payloads" {
  let malformed = [
    b"SELECT ALL EXCEPT () FROM t",
    b"SELECT * FROM t PARTITION ()",
    b"SELECT * FROM t TABLET ()",
    b"SELECT * FROM t SAMPLE ()",
    b"SELECT * FROM t TABLESAMPLE ()",
    b"SELECT a FROM t JOIN u USING ()",
    b"SELECT ALL EXCEPT (a,) FROM t",
    b"SELECT a FROM t JOIN u USING (k,)",
  ]
  for raw in malformed {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "doris", "4.x", mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(!result.valid)
      assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-002"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
  let valid = [
    b"SELECT ALL EXCEPT (secret) FROM t",
    b"SELECT * FROM t PARTITION (p0, p1)",
    b"SELECT * FROM t TABLET (1001)",
    b"SELECT * FROM t TABLESAMPLE (10)",
    b"SELECT a FROM t JOIN u USING (k, v)",
  ]
  for raw in valid {
    let result = match @api.parse_with_ids(raw, "doris", "4.x", "strict") {
      Ok(result) => result
      Err(_) => panic()
    }
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
    assert_eq(@printer.print_result(result), raw)
  }
}
test "released_reserved_words_are_rejected_but_quoted_words_remain_identifiers" {
  let malformed = [
    b"SELECT a AS SELECT",
    b"SELECT a FROM SELECT",
    b"SELECT a FROM t WHERE AND",
    b"sElEcT a As SeLeCt",
  ]
  for raw in malformed {
    let strict = parse_strict(raw)
    let editor = parse_editor_parser(raw)
    for result in [strict, editor] {
      assert_true(!result.valid)
      assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-002"))
      assert_true(has_kind(result.root, "missing") || has_kind(result.root, "error"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
    assert_eq(strict.diagnostics.length(), editor.diagnostics.length())
  }
  let quoted = [
    b"SELECT a AS `select` FROM `with` WHERE `and`",
    b"SELECT `or` FROM `select`",
  ]
  for raw in quoted {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "doris", "4.x", mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(result.valid)
      assert_eq(result.diagnostics.length(), 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
}

test "table_reference_dot_requires_following_identifier" {
  let malformed = [
    b"SELECT a FROM t.",
    b"SELECT a FROM t..x",
    b"SELECT a FROM t.x.",
    b"SELECT a FROM `db`.",
  ]
  for raw in malformed {
    let strict = parse_strict(raw)
    let editor = parse_editor_parser(raw)
    for result in [strict, editor] {
      assert_true(!result.valid)
      assert_true(result.diagnostics.length() > 0)
      assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-002"))
      assert_true(has_kind(result.root, "missing") || has_kind(result.root, "error"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
    assert_eq(strict.root.kind, editor.root.kind)
    assert_eq(strict.root.text_len, editor.root.text_len)
    assert_eq(strict.diagnostics.length(), editor.diagnostics.length())
  }
  let valid = [
    b"SELECT a FROM db.t",
    b"SELECT a FROM `db`.`t`",
    b"SELECT a FROM db.`from`",
  ]
  for raw in valid {
    let result = parse_strict(raw)
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
    assert_eq(@printer.print_result(result), raw)
  }
}

test "window_required_nulls_and_frame_tokens_propagate_failure" {
  let malformed = [
    b"SELECT SUM(x) OVER (ORDER BY x NULLS)",
    b"SELECT SUM(x) OVER (ORDER BY x ROWS BETWEEN 1 AND 2)",
    b"SELECT SUM(x) OVER (ORDER BY x ROWS BETWEEN 1 PRECEDING AND 2)",

    b"SELECT SUM(x) OVER (ORDER BY x RANGE CURRENT)",
    b"SELECT SUM(x) OVER (ORDER BY x ROWS 1)",
  ]
  for raw in malformed {
    let strict = parse_strict(raw)
    let editor = parse_editor_parser(raw)
    for result in [strict, editor] {
      assert_true(!result.valid)
      assert_true(result.diagnostics.length() > 0)
      assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-002"))
      assert_true(has_kind(result.root, "missing") || has_kind(result.root, "error"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
    assert_eq(strict.root.kind, editor.root.kind)
    assert_eq(strict.root.text_len, editor.root.text_len)
    assert_eq(strict.diagnostics.length(), editor.diagnostics.length())
  }
  let valid = [
    b"SELECT SUM(x) OVER (ORDER BY x NULLS LAST)",
    b"SELECT SUM(x) OVER (ORDER BY x ROWS BETWEEN 1 PRECEDING AND CURRENT ROW)",
    b"SELECT SUM(x) OVER (ORDER BY x RANGE UNBOUNDED PRECEDING)",
    b"SELECT SUM(x) OVER (ORDER BY x ROWS CURRENT ROW)",
  ]
  for raw in valid {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "doris", "4.x", mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(result.valid)
      assert_eq(result.diagnostics.length(), 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
}
test "window_order_items_consume_direction_and_nulls_per_item" {
  let valid = [
    b"SELECT SUM(v) OVER (ORDER BY a ASC, b DESC) FROM t",
    b"SELECT SUM(v) OVER (ORDER BY a ASC NULLS FIRST, b DESC NULLS LAST) FROM t",
  ]
  for raw in valid {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "doris", "4.x", mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(result.valid)
      assert_eq(result.diagnostics.length(), 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
  for raw in [b"SELECT SUM(v) OVER (ORDER BY a ASC,)", b"SELECT SUM(v) OVER (ORDER BY a NULLS, b)"] {
    let strict = parse_strict(raw)
    let editor = parse_editor_parser(raw)
    for result in [strict, editor] {
      assert_true(!result.valid)
      assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-002"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
    assert_eq(strict.diagnostics.length(), editor.diagnostics.length())
  }
}

test "required_expression_and_window_productions_diagnose_and_recover" {
  let malformed = [
    b"SELECT SUM(x) OVER (ORDER BY)",
    b"SELECT x IN ()",
    b"SELECT a FROM t GROUP BY GROUPING SETS",
    b"SELECT a FROM t WINDOW w AS",
  ]
  for raw in malformed {
    let strict = parse_strict(raw)
    let editor = parse_editor_parser(raw)
    for result in [strict, editor] {
      assert_true(!result.valid)
      assert_true(result.diagnostics.length() > 0)
      assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-002"))
      assert_true(has_kind(result.root, "missing") || has_kind(result.root, "error"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
    assert_eq(strict.root.kind, editor.root.kind)
    assert_eq(strict.root.text_len, editor.root.text_len)
    assert_eq(strict.diagnostics.length(), editor.diagnostics.length())
  }
}

test "malformed_numeric_literals_are_lexically_diagnosed_and_replayed" {
  let malformed = [b"SELECT 1..2", b"SELECT 1.2.3"]
  for raw in malformed {
    let strict = parse_strict(raw)
    let editor = parse_editor_parser(raw)
    for result in [strict, editor] {
      assert_true(!result.valid)
      assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-003"))
      assert_true(result.diagnostics.any(d => d.start_byte < d.end_byte))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
    assert_eq(strict.root.text_len, editor.root.text_len)
    assert_eq(strict.diagnostics.length(), editor.diagnostics.length())
  }
  for raw in [b"SELECT 1", b"SELECT 1.2", b"SELECT 1e3", b"SELECT 1.2E-3"] {
    let result = parse_strict(raw)
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
    assert_eq(@printer.print_result(result), raw)
  }
}
test "reserved_boolean_and_null_literals_are_expression_operands" {
  let raws = [
    b"SELECT NULL",
    b"SELECT TRUE WHERE TRUE",
    b"SELECT NULL FROM t WHERE x = TRUE",
    b"SELECT NULL FROM t WHERE x IN (NULL)",
    b"SELECT NULL FROM t ORDER BY NULL",
    b"SELECT SUM(NULL) FROM t",
  ]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "doris", "4.x", mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(result.valid)
      assert_eq(result.diagnostics.length(), 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
}
test "window_definition_trailing_comma_is_recovered_and_invalid" {
  let raws = [
    b"SELECT x FROM t WINDOW w AS (ORDER BY x),",
    b"SELECT x FROM t WINDOW w AS (ORDER BY x), ORDER BY x",
  ]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "doris", "4.x", mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(!result.valid)
      assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-002"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
}
test "grouping_sets_trailing_comma_is_recovered_and_invalid" {
  let raws = [
    b"SELECT a FROM t GROUP BY GROUPING SETS ((a),)",
    b"SELECT a FROM t GROUP BY GROUPING SETS ((a),) ORDER BY a",
  ]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "doris", "4.x", mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(!result.valid)
      assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-002"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
}
test "with_recursive_is_invalid_but_ordinary_cte_remains_valid" {
  let recursive_raw = b"WITH RECURSIVE cte AS (SELECT 1) SELECT 1"
  for mode in ["strict", "editor"] {
    let result = match @api.parse_with_ids(recursive_raw, "doris", "4.x", mode) {
      Ok(result) => result
      Err(_) => panic()
    }
    assert_true(!result.valid)
    assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-006"))
    assert_eq(@printer.print_result(result), recursive_raw)
    assert_true(result.all_spans_in_bounds())
  }
  for mode in ["strict", "editor"] {
    let result = match @api.parse_with_ids(b"WITH cte AS (SELECT 1) SELECT 1", "doris", "4.x", mode) {
      Ok(result) => result
      Err(_) => panic()
    }
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
  }
}
test "except_requires_all_and_preserves_star_exception" {
  for raw in [b"SELECT DISTINCT EXCEPT (secret) FROM t", b"SELECT DISTINCTROW EXCEPT (secret) FROM t"] {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "doris", "4.x", mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(!result.valid)
      assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-002"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
  for raw in [b"SELECT ALL EXCEPT (secret) FROM t", b"SELECT * EXCEPT (secret) FROM t"] {
    let result = parse_strict(raw)
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
    assert_eq(@printer.print_result(result), raw)
  }
}
test "sample_options_are_single_value_but_tablet_accepts_list" {
  for raw in [b"SELECT * FROM t TABLET(1, 2)", b"SELECT * FROM t SAMPLE(10 ROWS) REPEATABLE(2)", b"SELECT * FROM t TABLESAMPLE(10 PERCENT) REPEATABLE 2"] {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "doris", "4.x", mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(result.valid)
      assert_eq(result.diagnostics.length(), 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
  for raw in [b"SELECT * FROM t SAMPLE(10, 20)", b"SELECT * FROM t TABLESAMPLE(10 ROWS, 20 ROWS)"] {
    for mode in ["strict", "editor"] {
      let result = match @api.parse_with_ids(raw, "doris", "4.x", mode) {
        Ok(result) => result
        Err(_) => panic()
      }
      assert_true(!result.valid)
      assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-002"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
}