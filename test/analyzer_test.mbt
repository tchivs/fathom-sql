// Analyzer boundary tests (02-05, ANLY-01 / D-21..D-24).
//
// The analyzer package must be a standalone library consuming only syntax
// read views; the parser core must never import it (D-21, Pitfall 7), and the
// syntax-only valid/diagnostic channel must be byte-identical with and without
// a catalog (ANLY-01).

/// Trait-dispatch helper: resolves `table` through the Catalog trait itself so
/// the trait object path (used by resolve_table_references) is exercised.
fn catalog_lookup[T : @analyzer.Catalog](catalog : T, name : String) -> @analyzer.TableInfo? {
  @analyzer.Catalog::table(catalog, name)
}

test "analyzer_catalog_lookup_hits_and_misses" {
  let catalog = @analyzer.StaticCatalog::new([
    {
      name: "t",
      columns: [{ name: "id", data_type: "INT" }, { name: "v", data_type: "VARCHAR(10)" }],
    },
  ])
  let hit = @analyzer.StaticCatalog::lookup(catalog, "t")
  match hit {
    Some(table) => {
      assert_eq(table.name, "t")
      assert_eq(table.columns.length(), 2)
      assert_eq(table.columns[0].name, "id")
      assert_eq(table.columns[0].data_type, "INT")
      assert_eq(table.columns[1].name, "v")
    }
    None => panic()
  }
  assert_true(@analyzer.StaticCatalog::lookup(catalog, "missing") is None)
  // Keys are case-sensitive for now (documented): "T" is not "t".
  assert_true(@analyzer.StaticCatalog::lookup(catalog, "T") is None)
}

test "analyzer_empty_catalog_lookup_returns_none" {
  let empty = @analyzer.StaticCatalog::new([])
  assert_true(@analyzer.StaticCatalog::lookup(empty, "t") is None)
  let single = @analyzer.StaticCatalog::new([{ name: "e", columns: [] }])
  assert_true(@analyzer.StaticCatalog::lookup(single, "e") is Some(_))
  assert_true(@analyzer.StaticCatalog::lookup(single, "t") is None)
}

test "analyzer_catalog_trait_dispatches_to_static_catalog" {
  let catalog = @analyzer.StaticCatalog::new([{ name: "t", columns: [] }])
  assert_true(catalog_lookup(catalog, "t") is Some(_))
  assert_true(catalog_lookup(catalog, "nope") is None)
}

test "analyzer_syntax_only_path_is_unchanged_by_catalog" {
  let raw = b"INSERT INTO t VALUES (1); SELECT * FROM t"
  let first = match @api.parse_with_ids(raw, "doris", "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  // Building a catalog and looking tables up must never touch the parser.
  let catalog = @analyzer.StaticCatalog::new([{ name: "t", columns: [{ name: "id", data_type: "INT" }] }])
  assert_true(@analyzer.StaticCatalog::lookup(catalog, "t") is Some(_))
  let second = match @api.parse_with_ids(raw, "doris", "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(first.valid)
  assert_eq(first.valid, second.valid)
  assert_eq(first.diagnostics.length(), second.diagnostics.length())
  assert_eq(first.diagnostics.map(d => d.code), second.diagnostics.map(d => d.code))
  assert_eq(first.root.kind, second.root.kind)
  assert_eq(first.root.text_len, second.root.text_len)
  assert_eq(first.diagnostics.length(), 0)
}

// ---------------------------------------------------------------------------
// D-23 statement-level accessors on ParseResult
// ---------------------------------------------------------------------------

test "analyzer_statement_accessors_isolate_nodes_and_diagnostics_by_id" {
  let result = match @api.parse_with_ids(b"INSERT INTO t VALUES (1); bad; SELECT b", "doris", "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  // Each returned node is the Statement wrapper with the statement body child.
  match result.statement(0U) {
    Some(node) => {
      assert_eq(node.kind, "statement")
      assert_eq(node.children.length(), 1)
      assert_eq(node.children[0].kind, "insert")
    }
    None => panic()
  }
  match result.statement(1U) {
    Some(node) => {
      assert_eq(node.kind, "statement")
      assert_eq(node.children[0].kind, "error")
    }
    None => panic()
  }
  match result.statement(2U) {
    Some(node) => {
      assert_eq(node.kind, "statement")
      assert_eq(node.children[0].kind, "select")
    }
    None => panic()
  }
  assert_true(result.statement(3U) is None)
  // The bad statement's diagnostic is isolated by id (FATHOM-PARSE-007).
  let bad_diagnostics = result.statement_diagnostics(1U)
  assert_eq(bad_diagnostics.length(), 1)
  assert_eq(bad_diagnostics[0].code, "FATHOM-PARSE-007")
  assert_eq(bad_diagnostics[0].statement_id, 1U)
  assert_eq(result.statement_diagnostics(0U).length(), 0)
  assert_eq(result.statement_diagnostics(2U).length(), 0)
}

test "analyzer_statement_accessors_on_empty_document" {
  let result = match @api.parse_with_ids(b"", "doris", "2.1", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(result.statement(0U) is None)
  assert_eq(result.statement_diagnostics(0U).length(), 0)
}

test "analyzer_statement_diagnostics_stay_ordered_by_source_position" {
  // "SELECT 1 +" yields two FATHOM-PARSE-002 diagnostics at the statement end
  // (existing parser behavior); each "bad" statement yields exactly one
  // FATHOM-PARSE-007. Per-statement slices must keep emission/source order and
  // stay monotonic across statement ids.
  let result = match @api.parse_with_ids(b"SELECT 1 +; bad; bad2", "doris", "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  let stmt0 = result.statement_diagnostics(0U)
  let stmt1 = result.statement_diagnostics(1U)
  let stmt2 = result.statement_diagnostics(2U)
  assert_eq(stmt0.length(), 2)
  assert_eq(stmt1.length(), 1)
  assert_eq(stmt2.length(), 1)
  assert_eq(stmt0[0].code, "FATHOM-PARSE-002")
  assert_eq(stmt0[1].code, "FATHOM-PARSE-002")
  assert_eq(stmt1[0].code, "FATHOM-PARSE-007")
  assert_eq(stmt2[0].code, "FATHOM-PARSE-007")
  assert_true(stmt0[0].start_byte <= stmt0[1].start_byte)
  assert_true(stmt0[1].start_byte < stmt1[0].start_byte)
  assert_true(stmt1[0].start_byte < stmt2[0].start_byte)
}

// ---------------------------------------------------------------------------
// resolve_table_references over syntax read views with an injected catalog
// ---------------------------------------------------------------------------

test "analyzer_resolve_table_references_against_injected_catalog" {
  // All five DML/DDL kinds shipped by 02-01/02-02: Insert, Update, Delete,
  // Merge (4.x), CreateTable. Catalog holds t, t4, t5; t2 and t3 are absent.
  let raw = b"INSERT INTO t VALUES (1); UPDATE t2 SET a = 1; DELETE FROM t4 WHERE a = 1; MERGE INTO t5 USING src ON t5.id = src.id WHEN MATCHED THEN UPDATE SET t5.v = src.v; CREATE TABLE t3 (a INT)"
  let source = match @source.SourceText::new_with_limit(raw, 8 * 1024 * 1024) {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = @parser.parse_with_limits(
    source,
    doris_context("4.x"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  assert_true(parsed.valid)
  assert_eq(parsed.diagnostics.length(), 0)
  let catalog = @analyzer.StaticCatalog::new([
    { name: "t", columns: [{ name: "id", data_type: "INT" }] },
    { name: "t4", columns: [{ name: "a", data_type: "INT" }] },
    { name: "t5", columns: [{ name: "id", data_type: "INT" }, { name: "v", data_type: "INT" }] },
  ])
  let resolved = @analyzer.resolve_table_references(parsed.root, source.bytes(), catalog)
  assert_eq(resolved, ["t", "t4", "t5"])
  // t2/t3 are absent: missing tables are simply absent from the result.
  assert_true(!resolved.contains("t2"))
  assert_true(!resolved.contains("t3"))
  // Parsing the same bytes without any catalog yields identical syntax
  // results — the analyzer consumes, never modifies, and is never required.
  let parsed_again = @parser.parse_with_limits(
    source,
    doris_context("4.x"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  assert_eq(parsed_again.valid, parsed.valid)
  assert_eq(parsed_again.diagnostics.length(), parsed.diagnostics.length())
  assert_eq(parsed_again.root.kind(), parsed.root.kind())
  assert_eq(parsed_again.root.text_len(), parsed.root.text_len())
}

test "analyzer_resolve_table_references_empty_catalog_and_no_statements" {
  // A catalog with no entries resolves nothing.
  let raw = b"INSERT INTO t VALUES (1); SELECT * FROM t"
  let source = match @source.SourceText::new_with_limit(raw, 8 * 1024 * 1024) {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = @parser.parse_with_limits(
    source,
    doris_context("4.x"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  let empty_catalog = @analyzer.StaticCatalog::new([])
  assert_eq(
    @analyzer.resolve_table_references(parsed.root, source.bytes(), empty_catalog),
    [],
  )
  // An empty document has no Statement children to resolve.
  let empty_source = match @source.SourceText::new_with_limit(b"", 8 * 1024 * 1024) {
    Ok(source) => source
    Err(_) => panic()
  }
  let empty_parsed = @parser.parse_with_limits(
    empty_source,
    doris_context("4.x"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  assert_eq(
    @analyzer.resolve_table_references(empty_parsed.root, empty_source.bytes(), empty_catalog),
    [],
  )
}

// ---------------------------------------------------------------------------
// Flink analyzer (13-03, D-03): resolve_table_references extended in place to
// the Flink statement families — Insert (incl. UPSERT INTO / INSERT OVERWRITE
// ... PARTITION), Update, Delete, CreateTable, CreateView — table-level only
// (D-22/D-24). The D-21 boundary holds: the analyzer consumes only
// @syntax.SyntaxNode + caller source bytes, never re-entering the parser
// (ANLY-01).
// ---------------------------------------------------------------------------

/// Flink DialectContext for @parser.parse_with_limits (mirrors doris_context
/// in recovery_test.mbt; uses the pinned FlinkProfile metadata).
fn flink_context(profile_id : String) -> @dialect.DialectContext {
  let profile = match @dialect.FlinkProfile::from_id(profile_id) {
    Some(profile) => profile
    None => panic()
  }
  let metadata = profile.metadata()
  {
    dialect: @dialect.Dialect::Flink,
    profile_id: profile_id,
    exact_release: metadata.exact_release,
    feature_introduction: metadata.feature_introduction,
  }
}

test "flink_analyzer_upsert_into_resolves_target" {
  // UPSERT INTO is a Flink RichSqlInsert form; the Flink parser maps UPSERT to
  // SyntaxKind::Insert (parser.mbt:4196), so the Insert leading-prefix arm
  // must recognize the UPSERT keyword before the table name.
  let raw = b"UPSERT INTO t VALUES (1)"
  let source = match @source.SourceText::new_with_limit(raw, 8 * 1024 * 1024) {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = @parser.parse_with_limits(
    source,
    flink_context("flink-2.3.0"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  assert_true(parsed.valid)
  assert_eq(parsed.diagnostics.length(), 0)
  let catalog = @analyzer.StaticCatalog::new([{ name: "t", columns: [{ name: "id", data_type: "INT" }] }])
  let resolved = @analyzer.resolve_table_references(parsed.root, source.bytes(), catalog)
  assert_eq(resolved, ["t"])
}

test "flink_analyzer_create_view_resolves_target" {
  // CREATE VIEW is the Flink CreateView family (shared syntax with Doris);
  // the CreateView leading-prefix arm lands on the view name. The query body
  // (t) is NOT walked — table-level only, target-table boundary (D-24).
  let raw = b"CREATE VIEW v AS SELECT * FROM t"
  let source = match @source.SourceText::new_with_limit(raw, 8 * 1024 * 1024) {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = @parser.parse_with_limits(
    source,
    flink_context("flink-2.3.0"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  assert_true(parsed.valid)
  assert_eq(parsed.diagnostics.length(), 0)
  let catalog = @analyzer.StaticCatalog::new([{ name: "v", columns: [] }])
  let resolved = @analyzer.resolve_table_references(parsed.root, source.bytes(), catalog)
  assert_eq(resolved, ["v"])
}

test "flink_analyzer_no_catalog_empty_and_byte_identical_parse" {
  // A Flink document analyzed with no catalog resolves nothing, and the
  // syntax-only parse result is identical whether or not resolution is called
  // — the analyzer never re-enters the parser (ANLY-01).
  let raw = b"UPSERT INTO t VALUES (1); CREATE VIEW v AS SELECT * FROM t"
  let source = match @source.SourceText::new_with_limit(raw, 8 * 1024 * 1024) {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = @parser.parse_with_limits(
    source,
    flink_context("flink-2.3.0"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  assert_true(parsed.valid)
  let empty_catalog = @analyzer.StaticCatalog::new([])
  assert_eq(
    @analyzer.resolve_table_references(parsed.root, source.bytes(), empty_catalog),
    [],
  )
  // Building a catalog and resolving must never change parser validity.
  let catalog = @analyzer.StaticCatalog::new([{ name: "t", columns: [] }])
  ignore(@analyzer.resolve_table_references(parsed.root, source.bytes(), catalog))
  let parsed_again = @parser.parse_with_limits(
    source,
    flink_context("flink-2.3.0"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  assert_eq(parsed_again.valid, parsed.valid)
  assert_eq(parsed_again.diagnostics.length(), parsed.diagnostics.length())
  assert_eq(parsed_again.diagnostics.map(d => d.code), parsed.diagnostics.map(d => d.code))
  assert_eq(parsed_again.root.kind(), parsed.root.kind())
  assert_eq(parsed_again.root.text_len(), parsed.root.text_len())
}

test "flink_analyzer_family_matrix_source_order" {
  // Full Flink target-table family matrix in one script: Insert (UPSERT),
  // Update, Delete, CreateTable, CreateView — resolved in source order; absent
  // tables omitted.
  let raw = b"UPSERT INTO t1 VALUES (1); UPDATE t2 SET a = 1 WHERE id = 1; DELETE FROM t3 WHERE id = 1; CREATE TABLE t4 (a INT); CREATE VIEW v5 AS SELECT * FROM t1"
  let source = match @source.SourceText::new_with_limit(raw, 8 * 1024 * 1024) {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = @parser.parse_with_limits(
    source,
    flink_context("flink-2.3.0"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  assert_true(parsed.valid)
  assert_eq(parsed.diagnostics.length(), 0)
  let catalog = @analyzer.StaticCatalog::new([
    { name: "t1", columns: [] },
    { name: "t2", columns: [] },
    { name: "t3", columns: [] },
    { name: "t4", columns: [] },
    { name: "v5", columns: [] },
  ])
  let resolved = @analyzer.resolve_table_references(parsed.root, source.bytes(), catalog)
  assert_eq(resolved, ["t1", "t2", "t3", "t4", "v5"])
}

test "flink_analyzer_empty_document_returns_empty" {
  let raw = b""
  let source = match @source.SourceText::new_with_limit(raw, 8 * 1024 * 1024) {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = @parser.parse_with_limits(
    source,
    flink_context("flink-2.3.0"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  let empty_catalog = @analyzer.StaticCatalog::new([])
  assert_eq(
    @analyzer.resolve_table_references(parsed.root, source.bytes(), empty_catalog),
    [],
  )
}

test "flink_analyzer_insert_select_resolves_only_target" {
  // The INSERT ... SELECT boundary: only the INSERT target resolves; the
  // SELECT source table is outside the target-table-only scope (D-24).
  let raw = b"INSERT INTO dst SELECT * FROM src"
  let source = match @source.SourceText::new_with_limit(raw, 8 * 1024 * 1024) {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = @parser.parse_with_limits(
    source,
    flink_context("flink-2.3.0"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  assert_true(parsed.valid)
  assert_eq(parsed.diagnostics.length(), 0)
  let catalog = @analyzer.StaticCatalog::new([
    { name: "dst", columns: [] },
    { name: "src", columns: [] },
  ])
  let resolved = @analyzer.resolve_table_references(parsed.root, source.bytes(), catalog)
  assert_eq(resolved, ["dst"])
}

test "flink_analyzer_insert_overwrite_partition_resolves_target" {
  // INSERT OVERWRITE ... PARTITION (k=v): the Flink parser places the table
  // name BEFORE the PARTITION spec (parse_flink_insert consumes the qualified
  // name first), so the existing INSERT OVERWRITE arm already lands on t.
  let raw = b"INSERT OVERWRITE t PARTITION (dt='2024') VALUES (1)"
  let source = match @source.SourceText::new_with_limit(raw, 8 * 1024 * 1024) {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = @parser.parse_with_limits(
    source,
    flink_context("flink-2.3.0"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  assert_true(parsed.valid)
  assert_eq(parsed.diagnostics.length(), 0)
  let catalog = @analyzer.StaticCatalog::new([{ name: "t", columns: [] }])
  let resolved = @analyzer.resolve_table_references(parsed.root, source.bytes(), catalog)
  assert_eq(resolved, ["t"])
}

test "doris_analyzer_behavior_unchanged" {
  // The D-03 extension is additive: Doris DML/DDL target-table resolution is
  // unchanged (existing leading-prefix arms untouched), and Doris CREATE VIEW
  // is newly covered by the shared CreateView arm (documented one-way change).
  let raw = b"INSERT INTO t VALUES (1); UPDATE t2 SET a = 1; DELETE FROM t4 WHERE a = 1; CREATE TABLE t3 (a INT); CREATE VIEW v AS SELECT a FROM t"
  let source = match @source.SourceText::new_with_limit(raw, 8 * 1024 * 1024) {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = @parser.parse_with_limits(
    source,
    doris_context("4.x"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  assert_true(parsed.valid)
  let catalog = @analyzer.StaticCatalog::new([
    { name: "t", columns: [] },
    { name: "t4", columns: [] },
    { name: "v", columns: [] },
  ])
  let resolved = @analyzer.resolve_table_references(parsed.root, source.bytes(), catalog)
  // t (Insert), t4 (Delete), v (CreateView) are in the catalog; t2/t3 are
  // absent and omitted. The Doris leading-prefix arms behave as before.
  assert_eq(resolved, ["t", "t4", "v"])
}
