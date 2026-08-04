/// DDL statement, version-gate, recovery, replay, and DORIS-03 script tests.
/// The shared `has_kind` tree probe and `parse_with_limits` helper live in
/// recovery_test.mbt (same package).

fn parse_ddl(raw : Bytes, profile : String, mode : String) -> @api.ParseResult {
  match @api.parse_with_ids(raw, profile, mode) {
    Ok(result) => result
    Err(_) => panic()
  }
}

test "create_table_full_body_parses_with_byte_exact_replay" {
  let raw = b"CREATE TABLE example_table (k1 TINYINT, k2 DECIMAL(10, 2) DEFAULT \"10.5\", k3 CHAR(10) COMMENT \"string column\", k4 INT NOT NULL DEFAULT \"1\" COMMENT \"int column\", v1 BIGINT SUM DEFAULT \"0\" COMMENT \"aggregate value\", INDEX idx_k1 (k1) USING BITMAP COMMENT \"index comment\") ENGINE=OLAP UNIQUE KEY(k1, k2) ORDER BY(k1) COMMENT \"my table\" PARTITION BY RANGE(k1) (PARTITION p1 VALUES LESS THAN (\"2021-01-01\"), PARTITION p2 VALUES LESS THAN (\"2022-01-01\")) DISTRIBUTED BY HASH(k1) BUCKETS 32 ROLLUP (r1 (k1) DUPLICATE KEY (k1)) PROPERTIES (\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\")"
  // ORDER BY is a 4.x-gated clause (D-15), so the full body is asserted under
  // the 4.x profile only; 2.1/3.x gate behavior has its own test below.
  for mode in ["strict", "editor"] {
    let result = parse_ddl(raw, "4.x", mode)
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
    assert_eq(@printer.print_result(result), raw)
    assert_true(result.all_spans_in_bounds())
    assert_true(has_kind(result.root, "create_table"))
  }
}

test "create_table_order_by_is_gated_below_4x" {
  let raw = b"CREATE TABLE t (k1 INT) UNIQUE KEY (k1) ORDER BY (k1) DISTRIBUTED BY HASH (k1) BUCKETS 10"
  for profile in ["2.1", "3.x"] {
    for mode in ["strict", "editor"] {
      let result = parse_ddl(raw, profile, mode)
      assert_true(!result.valid)
      assert_true(result.diagnostics.any(d => d.code == "DORIS-PARSE-006"))
      assert_true(has_kind(result.root, "error"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
      if mode == "editor" { assert_true(result.recovered) }
    }
  }
  for mode in ["strict", "editor"] {
    let result = parse_ddl(raw, "4.x", mode)
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
    assert_eq(@printer.print_result(result), raw)
    assert_true(result.all_spans_in_bounds())
  }
}

test "create_table_buckets_auto_is_gated_below_3x" {
  let raw = b"CREATE TABLE t (k1 INT) DISTRIBUTED BY HASH (k1) BUCKETS AUTO"
  for mode in ["strict", "editor"] {
    let old = parse_ddl(raw, "2.1", mode)
    assert_true(!old.valid)
    assert_true(old.diagnostics.any(d => d.code == "DORIS-PARSE-006"))
    assert_true(has_kind(old.root, "error"))
    assert_eq(@printer.print_result(old), raw)
    assert_true(old.all_spans_in_bounds())
  }
  for profile in ["3.x", "4.x"] {
    let result = parse_ddl(raw, profile, "strict")
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
    assert_eq(@printer.print_result(result), raw)
    assert_true(result.all_spans_in_bounds())
  }
}

test "create_table_auto_partition_by_is_accepted_by_all_released_profiles" {
  let raws = [
    b"CREATE TABLE t (k1 DATE, k2 INT) AUTO PARTITION BY RANGE (TO_DAYS(k1)) () DISTRIBUTED BY HASH (k2) BUCKETS 3",
    b"CREATE TABLE t (k1 INT, k2 INT) AUTO PARTITION BY LIST (k1) () DISTRIBUTED BY HASH (k2) BUCKETS 3",
  ]
  for raw in raws {
    for profile in ["2.1", "3.x", "4.x"] {
      let result = parse_ddl(raw, profile, "strict")
      assert_true(result.valid)
      assert_eq(result.diagnostics.length(), 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
    }
  }
}

test "create_table_non_reserved_grammar_words_work_as_column_names" {
  // bucket / comment / value are absent from the official reserved list and
  // stay unquoted-usable (Pitfall 2). `order` IS reserved (official list and
  // the shared Phase 1 clause set), so it requires backticks here.
  let raw = b"CREATE TABLE t (bucket INT, comment VARCHAR(10), value DECIMAL(10, 2), `order` INT) DISTRIBUTED BY HASH (bucket) BUCKETS 10"
  for profile in ["2.1", "3.x", "4.x"] {
    let result = parse_ddl(raw, profile, "strict")
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
    assert_eq(@printer.print_result(result), raw)
    assert_true(result.all_spans_in_bounds())
  }
}

test "ddl_grammar_words_stay_out_of_shared_reserved_set" {
  for raw in [b"BUCKETS", b"PROPERTIES", b"COMMENT", b"AGGREGATE", b"ENGINE"] {
    assert_true(!@token.is_reserved_word(raw))
    assert_true(@token.is_unquoted_identifier(raw))
  }
  // ORDER and ROLLUP are in the shared clause/reserved set (Phase 1 SELECT
  // contract: ORDER BY / GROUPING SETS), so they require backticks as
  // identifiers — the shared set is untouched by this plan.
  assert_true(@token.is_reserved_word(b"ORDER"))
  assert_true(@token.is_reserved_word(b"ROLLUP"))
}

test "create_table_partition_variants_parse_with_replay" {
  let raws = [
    b"CREATE TABLE t (k1 DATE) PARTITION BY RANGE (k1) (PARTITION p1 VALUES LESS THAN ('2021-01-01'), PARTITION p2 VALUES LESS THAN (MAXVALUE))",
    b"CREATE TABLE t (k1 INT) PARTITION BY LIST (k1) (PARTITION p1 VALUES IN (1, 2), PARTITION p2 VALUES IN (3))",
    b"CREATE TABLE t (k1 DATE) PARTITION BY RANGE (k1) (PARTITION p1 VALUES [ '2021-01-01', '2022-01-01' ))",
    b"CREATE TABLE t (k1 DATE) PARTITION BY RANGE (k1) (FROM '2021-01-01' TO '2022-01-01' INTERVAL 1 DAY)",
    b"CREATE TABLE t (k1 DATE) PARTITION BY RANGE (k1) ()",
  ]
  for raw in raws {
    for profile in ["2.1", "3.x", "4.x"] {
      let result = parse_ddl(raw, profile, "strict")
      assert_true(result.valid)
      assert_eq(result.diagnostics.length(), 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
      assert_true(has_kind(result.root, "create_table"))
    }
  }
}

test "create_table_modifier_and_qualified_name_forms" {
  let raws = [
    b"CREATE TEMPORARY TABLE t (a INT)",
    b"CREATE EXTERNAL TABLE t (a INT)",
    b"CREATE TABLE IF NOT EXISTS t (a INT)",
    b"CREATE TABLE IF NOT EXISTS db.t (a INT)",
    b"CREATE TABLE t (c1 INT AUTO_INCREMENT(1) COMMENT 'id', c2 VARCHAR(50) NOT NULL, c3 DATETIME DEFAULT CURRENT_TIMESTAMP, c4 INT ON UPDATE CURRENT_TIMESTAMP(3), c5 BIGINT AS (c1 * 2), c6 ARRAY<INT>, c7 MAP<STRING, INT>, c8 STRUCT<a INT, b STRING>)",
  ]
  for raw in raws {
    for profile in ["2.1", "3.x", "4.x"] {
      for mode in ["strict", "editor"] {
        let result = parse_ddl(raw, profile, mode)
        assert_true(result.valid)
        assert_eq(result.diagnostics.length(), 0)
        assert_eq(@printer.print_result(result), raw)
        assert_true(result.all_spans_in_bounds())
        assert_true(has_kind(result.root, "create_table"))
      }
    }
  }
}

test "create_dispatch_replaces_the_unsupported_path" {
  let result = parse_ddl(b"CREATE TABLE t (a INT)", "4.x", "strict")
  assert_true(result.valid)
  assert_true(!result.diagnostics.any(d => d.code == "DORIS-PARSE-007"))
  assert_true(has_kind(result.root, "create_table"))
}

test "doris03_unclosed_create_table_keeps_later_statements" {
  let raw = b"CREATE TABLE t (a INT; INSERT INTO t VALUES (1); SELECT * FROM t"
  let result = parse_ddl(raw, "4.x", "strict")
  assert_eq(@printer.print_result(result), raw)
  assert_eq(result.root.children.length(), 3)
  assert_true(!result.valid)
  let bad = result.diagnostics[0]
  assert_eq(bad.statement_id, 0U)
  assert_true(bad.code.has_prefix("DORIS-PARSE-"))
  assert_true(result.all_spans_in_bounds())
}

test "malformed_create_table_recovers_losslessly" {
  let raws = [
    b"CREATE TABLE t (a INT",
    b"CREATE TABLE t",
    b"CREATE TABLE t (a)",
    b"CREATE TABLE t (a INT) ENGINE",
    b"CREATE TABLE t (a INT) UNIQUE KEY (a) DISTRIBUTED BY",
    b"CREATE TABLE t (a INT,)",
  ]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = parse_ddl(raw, "4.x", mode)
      assert_true(!result.valid)
      assert_true(result.diagnostics.length() > 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
      assert_true(has_kind(result.root, "missing") || has_kind(result.root, "error"))
    }
  }
}

test "create_table_deep_parens_stay_bounded" {
  let mut deep_expr : Bytes = b"1"
  let mut depth = 0
  while depth < 140 {
    deep_expr = b"(" + deep_expr + b")"
    depth = depth + 1
  }
  let deep_raw = b"CREATE TABLE t (c1 INT AS " + deep_expr + b")"
  let limits = @api.ParseLimits::new(8 * 1024 * 1024, 1000, 128, 4, 8)
  let options = @api.ParseOptions::for_profile_with_limits(
    @token.DorisProfile::V4_X,
    @api.ParseMode::Editor,
    limits,
  )
  let result = match @api.parse(deep_raw, options) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!result.valid)
  assert_eq(@printer.print_result(result), deep_raw)
  assert_true(result.diagnostics.length() <= 8)
  assert_true(result.all_spans_in_bounds())
}

test "create_table_property_flood_parses_losslessly" {
  let mut props : Bytes = b""
  let mut index = 0
  while index < 300 {
    if index > 0 { props = props + b", " }
    props = props + b"\"k" + index.to_string().to_bytes() + b"\" = \"v" + index.to_string().to_bytes() + b"\""
    index = index + 1
  }
  let raw = b"CREATE TABLE t (a INT) DISTRIBUTED BY HASH (a) BUCKETS 10 PROPERTIES (" + props + b")"
  let result = parse_ddl(raw, "4.x", "strict")
  assert_true(result.valid)
  assert_eq(result.diagnostics.length(), 0)
  assert_eq(@printer.print_result(result), raw)
  assert_true(result.all_spans_in_bounds())
}

test "create_view_parses_plain_column_defined_and_if_not_exists_forms" {
  let raws = [
    b"CREATE VIEW v AS SELECT a, b FROM t",
    b"CREATE VIEW v (a, b) AS SELECT a, b FROM t",
    b"CREATE VIEW IF NOT EXISTS db.v (a COMMENT 'col a') AS SELECT x AS a FROM t",
    b"CREATE VIEW v SELECT a FROM t",
    b"CREATE VIEW v AS SELECT a FROM t UNION ALL SELECT a FROM u",
  ]
  for raw in raws {
    for profile in ["2.1", "3.x", "4.x"] {
      for mode in ["strict", "editor"] {
        let result = parse_ddl(raw, profile, mode)
        assert_true(result.valid)
        assert_eq(result.diagnostics.length(), 0)
        assert_eq(@printer.print_result(result), raw)
        assert_true(result.all_spans_in_bounds())
        assert_true(has_kind(result.root, "create_view"))
      }
    }
  }
}

test "create_view_cte_bodied_query_parses" {
  // A CTE-bodied view is a query and parses via parse_query (flagged Open Q1).
  let raw = b"CREATE VIEW v AS WITH cte AS (SELECT 1) SELECT * FROM cte"
  for profile in ["2.1", "3.x", "4.x"] {
    let result = parse_ddl(raw, profile, "strict")
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
    assert_eq(@printer.print_result(result), raw)
    assert_true(result.all_spans_in_bounds())
  }
}

test "create_table_like_parses_with_and_without_rollup" {
  let raws = [
    b"CREATE TABLE new_t LIKE existing_t",
    b"CREATE TABLE new_t LIKE existing_t WITH ROLLUP (r1, r2)",
    b"CREATE TABLE db.new_t LIKE db.existing_t",
  ]
  for raw in raws {
    for profile in ["2.1", "3.x", "4.x"] {
      let result = parse_ddl(raw, profile, "strict")
      assert_true(result.valid)
      assert_eq(result.diagnostics.length(), 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
      assert_true(has_kind(result.root, "create_table"))
    }
  }
}

test "create_table_as_select_composes_the_clause_stack" {
  let raws = [
    b"CREATE TABLE t AS SELECT a, b FROM src",
    b"CREATE TABLE t (a INT) DISTRIBUTED BY HASH (a) BUCKETS 10 AS SELECT a FROM src",
    b"CREATE EXTERNAL TABLE t PROPERTIES (\"type\" = \"hive\") AS SELECT 1",
    b"CREATE TABLE t (a INT, INDEX idx (a)) ENGINE=OLAP COMMENT \"ctas\" AS SELECT a FROM src",
  ]
  for raw in raws {
    for profile in ["2.1", "3.x", "4.x"] {
      for mode in ["strict", "editor"] {
        let result = parse_ddl(raw, profile, mode)
        assert_true(result.valid)
        assert_eq(result.diagnostics.length(), 0)
        assert_eq(@printer.print_result(result), raw)
        assert_true(result.all_spans_in_bounds())
        assert_true(has_kind(result.root, "create_table"))
      }
    }
  }
}

test "malformed_create_view_recovers_losslessly" {
  let raws = [
    b"CREATE VIEW",
    b"CREATE VIEW v",
    b"CREATE VIEW v AS",
    b"CREATE VIEW v (a) AS SELECT",
    b"CREATE VIEW v (a) AS FROM t",
  ]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = parse_ddl(raw, "4.x", mode)
      assert_true(!result.valid)
      assert_true(result.diagnostics.length() > 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
      assert_true(has_kind(result.root, "missing") || has_kind(result.root, "error"))
    }
  }
}

test "create_index_parses_documented_forms" {
  let raws = [
    b"CREATE INDEX index1 ON table1 (col1) USING INVERTED",
    b"CREATE INDEX index2 ON table1 (col1) USING NGRAM_BF PROPERTIES (\"gram_size\" = \"3\", \"bf_size\" = \"1024\")",
    b"CREATE INDEX idx ON db.table1 (col1, col2) USING ANN PROPERTIES (\"index_type\" = \"hnsw\", \"metric_type\" = \"l2_distance\", \"dim\" = \"128\")",
    b"CREATE INDEX IF NOT EXISTS idx ON t (c) COMMENT 'index comment'",
    b"CREATE INDEX idx ON t (c)",
  ]
  for raw in raws {
    for profile in ["2.1", "3.x", "4.x"] {
      for mode in ["strict", "editor"] {
        let result = parse_ddl(raw, profile, mode)
        assert_true(result.valid)
        assert_eq(result.diagnostics.length(), 0)
        assert_eq(@printer.print_result(result), raw)
        assert_true(result.all_spans_in_bounds())
        assert_true(has_kind(result.root, "create_index"))
      }
    }
  }
}

test "create_sync_materialized_view_parses_restricted_body" {
  let raws = [
    b"CREATE MATERIALIZED VIEW mv AS SELECT k, SUM(v) FROM t GROUP BY k",
    b"CREATE MATERIALIZED VIEW mv AS SELECT k FROM t WHERE k > 1",
    b"CREATE MATERIALIZED VIEW mv SELECT a, b FROM t ORDER BY a",
    b"CREATE MATERIALIZED VIEW db.mv AS SELECT SUM(v) FROM t",
    b"CREATE MATERIALIZED VIEW mv AS SELECT k, SUM(v) FROM t WHERE k > 0 GROUP BY k ORDER BY k",
  ]
  for raw in raws {
    for profile in ["2.1", "3.x", "4.x"] {
      for mode in ["strict", "editor"] {
        let result = parse_ddl(raw, profile, mode)
        assert_true(result.valid)
        assert_eq(result.diagnostics.length(), 0)
        assert_eq(@printer.print_result(result), raw)
        assert_true(result.all_spans_in_bounds())
        assert_true(has_kind(result.root, "create_materialized_view"))
      }
    }
  }
}

test "create_materialized_view_rejects_forbidden_clauses_with_localized_diagnostic" {
  let raws = [
    b"CREATE MATERIALIZED VIEW mv AS SELECT a FROM t JOIN u ON t.id = u.id",
    b"CREATE MATERIALIZED VIEW mv AS SELECT a, SUM(b) FROM t GROUP BY a HAVING SUM(b) > 1",
    b"CREATE MATERIALIZED VIEW mv AS SELECT a FROM t LIMIT 10",
    b"CREATE MATERIALIZED VIEW mv AS SELECT a FROM t LATERAL VIEW explode(x) e",
    b"CREATE MATERIALIZED VIEW mv AS SELECT a FROM (SELECT 1) t",
  ]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = parse_ddl(raw, "4.x", mode)
      assert_true(!result.valid)
      assert_true(result.diagnostics.any(d => d.expected_class == "sync materialized view body"))
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
      assert_true(has_kind(result.root, "missing") || has_kind(result.root, "error"))
    }
  }
}

test "malformed_create_index_recovers_losslessly" {
  let raws = [
    b"CREATE INDEX idx",
    b"CREATE INDEX idx ON",
    b"CREATE INDEX idx ON t",
    b"CREATE INDEX idx ON t (c) USING",
  ]
  for raw in raws {
    for mode in ["strict", "editor"] {
      let result = parse_ddl(raw, "4.x", mode)
      assert_true(!result.valid)
      assert_true(result.diagnostics.length() > 0)
      assert_eq(@printer.print_result(result), raw)
      assert_true(result.all_spans_in_bounds())
      assert_true(has_kind(result.root, "missing") || has_kind(result.root, "error"))
    }
  }
}

test "doris03_mixed_ddl_dml_select_script_keeps_statement_ids" {
  let raws = [
    b"CREATE TABLE t (a INT); INSERT INTO t VALUES (1); SELECT * FROM t",
    b"CREATE VIEW v AS SELECT a FROM t; INSERT INTO t VALUES (1); SELECT b",
  ]
  for raw in raws {
    let result = parse_ddl(raw, "4.x", "strict")
    assert_eq(@printer.print_result(result), raw)
    assert_eq(result.root.children.length(), 3)
    assert_true(result.valid)
    let mut statement_count = 0
    for child in result.root.children {
      if child.kind == "statement" { statement_count = statement_count + 1 }
    }
    assert_eq(statement_count, 3)
    assert_true(result.all_spans_in_bounds())
  }
}
