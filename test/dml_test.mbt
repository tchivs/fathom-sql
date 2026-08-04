/// DML statement, version-gate, recovery, replay, and DORIS-03 script tests.
/// The shared `has_kind` tree probe lives in recovery_test.mbt (same package).

fn parse_dml(raw : Bytes, profile : String, mode : String) -> @api.ParseResult {
  match @api.parse_with_ids(raw, profile, mode) {
    Ok(result) => result
    Err(_) => panic()
  }
}

test "insert_values_rows_parse_with_default_and_multirow" {
  let raws = [
    b"INSERT INTO test VALUES (1, 2)",
    b"INSERT INTO test (c1, c2) VALUES (1, DEFAULT)",
    b"INSERT INTO test VALUES (1, 2), (3, 4), (5, DEFAULT)",
  ]
  for raw in raws {
    for profile in ["2.1", "3.x", "4.x"] {
      for mode in ["strict", "editor"] {
        let result = parse_dml(raw, profile, mode)
        assert_true(result.valid)
        assert_eq(result.diagnostics.length(), 0)
        assert_eq(@printer.print_result(result), raw)
        assert_true(result.all_spans_in_bounds())
        assert_true(has_kind(result.root, "insert"))
      }
    }
  }
}

test "insert_select_query_and_qualified_target" {
  let raws = [
    b"INSERT INTO test SELECT * FROM test2",
    b"INSERT INTO db.test (c1) SELECT c1 FROM test2",
  ]
  for raw in raws {
    for profile in ["2.1", "3.x", "4.x"] {
      let result = parse_dml(raw, profile, "strict")
      assert_true(result.valid)
      assert_eq(result.diagnostics.length(), 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
}

test "insert_overwrite_legacy_table_form_and_partition_list" {
  let raws = [
    b"INSERT OVERWRITE table test VALUES (1, 2)",
    b"INSERT OVERWRITE table test PARTITION (p1, p2) SELECT * FROM test2",
  ]
  for raw in raws {
    for profile in ["2.1", "3.x", "4.x"] {
      for mode in ["strict", "editor"] {
        let result = parse_dml(raw, profile, mode)
        assert_true(result.valid)
        assert_eq(result.diagnostics.length(), 0)
        assert_eq(@printer.print_result(result), raw)
        assert_true(result.all_spans_in_bounds())
      }
    }
  }
}

test "insert_overwrite_partition_star_is_accepted_by_all_released_profiles" {
  let raw = b"INSERT OVERWRITE table test PARTITION (*) SELECT * FROM test2"
  for profile in ["2.1", "3.x", "4.x"] {
    for mode in ["strict", "editor"] {
      let result = parse_dml(raw, profile, mode)
      assert_true(result.valid)
      assert_eq(result.diagnostics.length(), 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
}

test "insert_partition_label_and_hint_forms_replay_exactly" {
  let raws = [
    b"INSERT INTO test PARTITION(p1) WITH LABEL label1 SELECT * FROM test2",
    b"INSERT INTO test /*+ STREAMING */ VALUES (1, 2)",
    b"INSERT INTO test WITH LABEL `label1` VALUES (1, 2)",
  ]
  for raw in raws {
    for profile in ["2.1", "3.x", "4.x"] {
      for mode in ["strict", "editor"] {
        let result = parse_dml(raw, profile, mode)
        assert_true(result.valid)
        assert_eq(result.diagnostics.length(), 0)
        assert_eq(@printer.print_result(result), raw)
        assert_true(result.all_spans_in_bounds())
      }
    }
  }
}

test "insert_dispatch_is_case_insensitive" {
  let raw = b"insert into test values (1)"
  for profile in ["2.1", "3.x", "4.x"] {
    let result = parse_dml(raw, profile, "strict")
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
    assert_eq(@printer.print_result(result), raw)
  }
}

test "doris03_insert_script_localizes_bad_statement" {
  let raw = b"INSERT INTO t VALUES (1); bad; SELECT b"
  let result = parse_dml(raw, "4.x", "strict")
  assert_eq(@printer.print_result(result), raw)
  assert_eq(result.root.children.length(), 3)
  assert_true(!result.valid)
  assert_true(result.diagnostics.length() >= 1)
  let bad = result.diagnostics[0]
  assert_true(bad.start_byte <= bad.end_byte)
  assert_eq(bad.statement_id, 1U)
  assert_eq(bad.code, "DORIS-PARSE-007")
  assert_true(result.all_spans_in_bounds())
}

test "unknown_statement_starters_are_explicit_unsupported_nodes" {
  let raws = [b"bad", b"ALTER TABLE t ADD COLUMN c INT", b"DROP TABLE t"]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = parse_dml(raw, "4.x", mode)
      assert_true(!result.valid)
      assert_eq(result.diagnostics.length(), 1)
      assert_eq(result.diagnostics[0].code, "DORIS-PARSE-007")
      assert_eq(result.diagnostics[0].statement_id, 0U)
      assert_true(has_kind(result.root, "error"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
}

test "with_prefixed_update_routes_to_unsupported_until_update_lands" {
  let raw = b"WITH c AS (SELECT 1) UPDATE t SET x = 1"
  let result = parse_dml(raw, "4.x", "strict")
  assert_true(!result.valid)
  assert_eq(result.diagnostics[0].code, "DORIS-PARSE-007")
  assert_eq(@printer.print_result(result), raw)
}

test "malformed_insert_recovers_losslessly" {
  let raws = [
    b"INSERT INTO t VALUES (1",
    b"INSERT INTO t VALUES",
    b"INSERT INTO t",
    b"INSERT INTO t VALUES (1, 2),",
  ]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = parse_dml(raw, "4.x", mode)
      assert_true(!result.valid)
      assert_true(result.diagnostics.length() > 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
      assert_true(has_kind(result.root, "missing") || has_kind(result.root, "error"))
    }
  }
}

test "unclosed_paren_dml_recovery_is_bounded_by_recovery_steps" {
  let limits = @api.ParseLimits::new(8 * 1024 * 1024, 1000, 128, 4, 8)
  let options = @api.ParseOptions::for_profile_with_limits(
    @token.DorisProfile::V4_X,
    @api.ParseMode::Editor,
    limits,
  )
  let result = match @api.parse(b"INSERT INTO t VALUES (1, (2, (3", options) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!result.valid)
  assert_eq(@printer.print_result(result), b"INSERT INTO t VALUES (1, (2, (3")
  assert_true(result.diagnostics.length() <= 8)
  assert_true(result.all_spans_in_bounds())
}

test "insert_statement_flood_stays_bounded_and_replays" {
  let mut raw : Bytes = b""
  let mut index = 0
  while index < 50 {
    raw = raw + b"INSERT INTO t VALUES (1); "
    index = index + 1
  }
  let result = parse_dml(raw, "4.x", "editor")
  assert_true(result.valid)
  assert_eq(result.diagnostics.length(), 0)
  assert_eq(@printer.print_result(result), raw)
  let mut statement_count = 0
  for child in result.root.children {
    if child.kind == "statement" { statement_count = statement_count + 1 }
  }
  assert_eq(statement_count, 50)
}

test "dml_keywords_do_not_leak_into_shared_clause_set" {
  for raw in [b"VALUES", b"SET", b"WHEN", b"INSERT", b"UPDATE", b"DELETE", b"MERGE"] {
    assert_true(!@token.is_clause_keyword(raw))
  }
}
