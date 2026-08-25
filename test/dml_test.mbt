///|
/// DML statement, version-gate, recovery, replay, and DORIS-03 script tests.
/// The shared `has_kind` tree probe lives in recovery_test.mbt (same package).
fn parse_dml(raw : Bytes, profile : String, mode : String) -> @api.ParseResult {
  match @api.parse_with_ids(raw, "doris", profile, mode) {
    Ok(result) => result
    Err(_) => panic()
  }
}

///|
test "insert_values_rows_parse_with_default_and_multirow" {
  let raws = [
    b"INSERT INTO test VALUES (1, 2)", b"INSERT INTO test (c1, c2) VALUES (1, DEFAULT)",
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

///|
test "insert_select_query_and_qualified_target" {
  let raws = [
    b"INSERT INTO test SELECT * FROM test2", b"INSERT INTO db.test (c1) SELECT c1 FROM test2",
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

///|
test "insert_overwrite_legacy_table_form_and_partition_list" {
  let raws = [
    b"INSERT OVERWRITE table test VALUES (1, 2)", b"INSERT OVERWRITE table test PARTITION (p1, p2) SELECT * FROM test2",
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

///|
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

///|
test "insert_partition_label_and_hint_forms_replay_exactly" {
  let raws = [
    b"INSERT INTO test PARTITION(p1) WITH LABEL label1 SELECT * FROM test2", b"INSERT INTO test /*+ STREAMING */ VALUES (1, 2)",
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

///|
test "insert_dispatch_is_case_insensitive" {
  let raw = b"insert into test values (1)"
  for profile in ["2.1", "3.x", "4.x"] {
    let result = parse_dml(raw, profile, "strict")
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
    assert_eq(@printer.print_result(result), raw)
  }
}

///|
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
  assert_eq(bad.code, "FATHOM-PARSE-007")
  assert_true(result.all_spans_in_bounds())
}

///|
test "unknown_statement_starters_are_explicit_unsupported_nodes" {
  let raws = [b"bad"]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = parse_dml(raw, "4.x", mode)
      assert_true(!result.valid)
      assert_eq(result.diagnostics.length(), 1)
      assert_eq(result.diagnostics[0].code, "FATHOM-PARSE-007")
      assert_eq(result.diagnostics[0].statement_id, 0U)
      assert_true(has_kind(result.root, "error"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
}

///|
test "with_prefixed_dml_statements_route_to_family_parsers" {
  let raws = [
    b"WITH c AS (SELECT 1) UPDATE t SET x = 1", b"WITH c AS (SELECT 1) DELETE FROM t WHERE id = 1",
  ]
  for raw in raws {
    let result = parse_dml(raw, "4.x", "strict")
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
    assert_eq(@printer.print_result(result), raw)
    assert_true(result.all_spans_in_bounds())
  }
}

///|
test "update_parses_cte_alias_set_from_where_order_limit" {
  let raws = [
    b"UPDATE t1 SET c1 = 1", b"UPDATE t1 SET c1 = 1, c2 = DEFAULT WHERE id = 1",
    b"UPDATE t1 SET t1.c1 = t2.c1 FROM t2 INNER JOIN t3 ON t2.id = t3.id WHERE t1.id = t2.id",
    b"UPDATE t1 SET c1 = c1 + 1 ORDER BY c1 DESC NULLS LAST LIMIT 10", b"UPDATE t1 SET c1 = 1 ORDER BY c1 ASC, c2 DESC LIMIT 5, 10",
    b"WITH cte AS (SELECT id FROM t2) UPDATE t1 SET c1 = 1 WHERE id IN (SELECT id FROM cte)",
    b"UPDATE t1 alias SET c1 = 1",
  ]
  for raw in raws {
    for profile in ["2.1", "3.x", "4.x"] {
      for mode in ["strict", "editor"] {
        let result = parse_dml(raw, profile, mode)
        assert_true(result.valid)
        assert_eq(result.diagnostics.length(), 0)
        assert_eq(@printer.print_result(result), raw)
        assert_true(result.all_spans_in_bounds())
        assert_true(has_kind(result.root, "update"))
      }
    }
  }
}

///|
test "update_malformed_recovers_at_clause_boundaries" {
  let raws = [
    b"UPDATE t SET", b"UPDATE t SET x =", b"UPDATE t WHERE id = 1", b"UPDATE t SET @^% WHERE id = 1",
    b"UPDATE t SET x = 1 WHERE", b"UPDATE t SET x = 1 LIMIT",
  ]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = parse_dml(raw, "4.x", mode)
      assert_true(!result.valid)
      assert_true(result.diagnostics.length() > 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
      assert_true(
        has_kind(result.root, "missing") || has_kind(result.root, "error"),
      )
    }
  }
}

///|
test "delete_parses_both_documented_forms" {
  let raws = [
    b"DELETE FROM t WHERE id = 1", b"DELETE FROM t PARTITION p1 WHERE id = 1 AND name = 'a'",
    b"DELETE FROM t PARTITIONS (p1, p2) WHERE id IN (1, 2, 3)", b"DELETE FROM t WHERE c1 > 1 AND c2 < 2 AND c3 >= 3 AND c4 != 4",
    b"WITH cte AS (SELECT id FROM t2) DELETE FROM t USING t2 WHERE t.id = t2.id",
    b"DELETE FROM t WHERE id = 1 ORDER BY id LIMIT 10", b"DELETE FROM t WHERE id = 1 ORDER BY id ASC NULLS FIRST, name DESC NULLS LAST LIMIT 5, 10",
  ]
  for raw in raws {
    for profile in ["2.1", "3.x", "4.x"] {
      for mode in ["strict", "editor"] {
        let result = parse_dml(raw, profile, mode)
        assert_true(result.valid)
        assert_eq(result.diagnostics.length(), 0)
        assert_eq(@printer.print_result(result), raw)
        assert_true(result.all_spans_in_bounds())
        assert_true(has_kind(result.root, "delete"))
      }
    }
  }
}

///|
test "delete_malformed_recovers_losslessly" {
  let raws = [
    b"DELETE t WHERE id = 1", b"DELETE FROM t PARTITION WHERE id = 1", b"DELETE FROM t WHERE",
    b"DELETE FROM t USING t2 WHERE t.id =", b"DELETE FROM t WHERE id = 1 ORDER BY",
  ]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = parse_dml(raw, "4.x", mode)
      assert_true(!result.valid)
      assert_true(result.diagnostics.length() > 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
      assert_true(
        has_kind(result.root, "missing") || has_kind(result.root, "error"),
      )
    }
  }
}

///|
test "doris03_dml_script_localizes_bad_statement" {
  let raw = b"UPDATE t SET x = 1; bad; SELECT b"
  let result = parse_dml(raw, "4.x", "strict")
  assert_eq(@printer.print_result(result), raw)
  assert_eq(result.root.children.length(), 3)
  assert_true(!result.valid)
  let bad = result.diagnostics[0]
  assert_eq(bad.statement_id, 1U)
  assert_eq(bad.code, "FATHOM-PARSE-007")
  assert_true(result.all_spans_in_bounds())
}

///|
test "dml_recovery_never_swallows_later_statements" {
  let raws = [
    b"UPDATE t SET @^% WHERE id = 1; SELECT b", b"DELETE FROM t WHERE; SELECT b",
  ]
  for raw in raws {
    let result = parse_dml(raw, "4.x", "editor")
    assert_eq(@printer.print_result(result), raw)
    assert_true(result.all_spans_in_bounds())
    let mut statement_count = 0
    for child in result.root.children {
      if child.kind == "statement" {
        statement_count = statement_count + 1
      }
    }
    assert_eq(statement_count, 2)
    assert_true(!result.valid)
  }
}

///|
test "malformed_insert_recovers_losslessly" {
  let raws = [
    b"INSERT INTO t VALUES (1", b"INSERT INTO t VALUES", b"INSERT INTO t", b"INSERT INTO t VALUES (1, 2),",
  ]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = parse_dml(raw, "4.x", mode)
      assert_true(!result.valid)
      assert_true(result.diagnostics.length() > 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
      assert_true(
        has_kind(result.root, "missing") || has_kind(result.root, "error"),
      )
    }
  }
}

///|
test "unclosed_paren_dml_recovery_is_bounded_by_recovery_steps" {
  let limits = @api.ParseLimits::new(8 * 1024 * 1024, 1000, 128, 4, 8)
  let options = @api.ParseOptions::for_profile_with_limits(
    @dialect.DorisProfile::V4_X,
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

///|
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
    if child.kind == "statement" {
      statement_count = statement_count + 1
    }
  }
  assert_eq(statement_count, 50)
}

///|
test "dml_keywords_do_not_leak_into_shared_clause_set" {
  for
    raw in [
      b"VALUES", b"SET", b"WHEN", b"INSERT", b"UPDATE", b"DELETE", b"MERGE",
    ] {
    assert_true(!@dialect.is_clause_keyword(doris_context("4.x"), raw))
  }
}

///|
test "merge_feature_metadata_marks_4x_introduction" {
  let metadata = @dialect.DorisFeature::MergeInto.metadata()
  assert_eq(metadata.name, "MERGE")
  assert_eq(metadata.keyword, b"MERGE")
  assert_eq(metadata.introduced_profile, "4.x")
  assert_eq(metadata.diagnostic_code, "FATHOM-PARSE-006")
  assert_true(
    !@dialect.DorisProfile::V2_1.supports(@dialect.DorisFeature::MergeInto),
  )
  assert_true(
    !@dialect.DorisProfile::V3_X.supports(@dialect.DorisFeature::MergeInto),
  )
  assert_true(
    @dialect.DorisProfile::V4_X.supports(@dialect.DorisFeature::MergeInto),
  )
}

///|
test "merge_into_parses_under_4x_with_all_clause_forms" {
  let raws = [
    b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.v = s.v",
    b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN DELETE", b"MERGE INTO t USING s ON t.id = s.id WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.v)",
    b"MERGE INTO t USING s ON t.id = s.id WHEN NOT MATCHED THEN INSERT (id, v) VALUES (s.id, s.v)",
    b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED AND t.v < s.v THEN UPDATE SET t.v = s.v WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.v)",
    b"WITH tmp AS (SELECT * FROM s) MERGE INTO t USING tmp ON t.id = tmp.id WHEN MATCHED THEN UPDATE SET t.v = tmp.v",
  ]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = parse_dml(raw, "4.x", mode)
      assert_true(result.valid)
      assert_eq(result.diagnostics.length(), 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
      assert_true(has_kind(result.root, "merge"))
    }
  }
}

///|
test "merge_is_gated_to_4x_released_profiles" {
  let raw = b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.v = s.v"
  for profile in ["2.1", "3.x"] {
    for mode in ["strict", "editor"] {
      let result = parse_dml(raw, profile, mode)
      assert_true(!result.valid)
      assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-006"))
      assert_true(has_kind(result.root, "error"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
      if mode == "editor" {
        assert_true(result.recovered)
      }
    }
  }
}

///|
test "merge_malformed_recovers_losslessly" {
  let raws = [
    b"MERGE INTO t USING s WHEN MATCHED THEN UPDATE SET t.v = s.v", b"MERGE INTO t USING s ON t.id = s.id",
    b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN", b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE",
    b"MERGE INTO t USING s ON t.id = s.id WHEN NOT MATCHED THEN INSERT VALUES",
  ]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = parse_dml(raw, "4.x", mode)
      assert_true(!result.valid)
      assert_true(result.diagnostics.length() > 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
      assert_true(
        has_kind(result.root, "missing") || has_kind(result.root, "error"),
      )
    }
  }
}

///|
test "unsupported_statement_starters_emit_one_007_each" {
  let raws = [b"BENCHMARK SELECT 1"]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = parse_dml(raw, "4.x", mode)
      assert_true(!result.valid)
      assert_eq(result.diagnostics.length(), 1)
      assert_eq(result.diagnostics[0].code, "FATHOM-PARSE-007")
      assert_eq(result.diagnostics[0].statement_id, 0U)
      assert_true(has_kind(result.root, "error"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
}

///|
test "doris03_merge_and_unsupported_keep_later_statements" {
  let merge_raw = b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.v = s.v; SELECT b"
  let merge_result = parse_dml(merge_raw, "4.x", "strict")
  assert_eq(@printer.print_result(merge_result), merge_raw)
  assert_eq(merge_result.root.children.length(), 2)
  assert_true(merge_result.valid)
  assert_true(merge_result.all_spans_in_bounds())

  let alter_raw = b"ALTER TABLE t ADD COLUMN c INT; INSERT INTO t VALUES (1); SELECT b"
  let alter_result = parse_dml(alter_raw, "4.x", "strict")
  assert_eq(@printer.print_result(alter_result), alter_raw)
  assert_eq(alter_result.root.children.length(), 3)
  assert_true(alter_result.valid)
  assert_true(alter_result.all_spans_in_bounds())

  let script_raw = b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN DELETE; bad; SELECT b"
  let script_result = parse_dml(script_raw, "4.x", "strict")
  assert_eq(@printer.print_result(script_result), script_raw)
  assert_eq(script_result.root.children.length(), 3)
  assert_true(!script_result.valid)
  assert_eq(script_result.diagnostics[0].statement_id, 1U)
  assert_eq(script_result.diagnostics[0].code, "FATHOM-PARSE-007")
  assert_true(script_result.all_spans_in_bounds())
}
