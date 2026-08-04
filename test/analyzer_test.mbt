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
  let first = match @api.parse_with_ids(raw, "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  // Building a catalog and looking tables up must never touch the parser.
  let catalog = @analyzer.StaticCatalog::new([{ name: "t", columns: [{ name: "id", data_type: "INT" }] }])
  assert_true(@analyzer.StaticCatalog::lookup(catalog, "t") is Some(_))
  let second = match @api.parse_with_ids(raw, "4.x", "strict") {
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
  let result = match @api.parse_with_ids(b"INSERT INTO t VALUES (1); bad; SELECT b", "4.x", "strict") {
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
  // The bad statement's diagnostic is isolated by id (DORIS-PARSE-007).
  let bad_diagnostics = result.statement_diagnostics(1U)
  assert_eq(bad_diagnostics.length(), 1)
  assert_eq(bad_diagnostics[0].code, "DORIS-PARSE-007")
  assert_eq(bad_diagnostics[0].statement_id, 1U)
  assert_eq(result.statement_diagnostics(0U).length(), 0)
  assert_eq(result.statement_diagnostics(2U).length(), 0)
}

test "analyzer_statement_accessors_on_empty_document" {
  let result = match @api.parse_with_ids(b"", "2.1", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(result.statement(0U) is None)
  assert_eq(result.statement_diagnostics(0U).length(), 0)
}

test "analyzer_statement_diagnostics_stay_ordered_by_source_position" {
  // "SELECT 1 +" yields two DORIS-PARSE-002 diagnostics at the statement end
  // (existing parser behavior); each "bad" statement yields exactly one
  // DORIS-PARSE-007. Per-statement slices must keep emission/source order and
  // stay monotonic across statement ids.
  let result = match @api.parse_with_ids(b"SELECT 1 +; bad; bad2", "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  let stmt0 = result.statement_diagnostics(0U)
  let stmt1 = result.statement_diagnostics(1U)
  let stmt2 = result.statement_diagnostics(2U)
  assert_eq(stmt0.length(), 2)
  assert_eq(stmt1.length(), 1)
  assert_eq(stmt2.length(), 1)
  assert_eq(stmt0[0].code, "DORIS-PARSE-002")
  assert_eq(stmt0[1].code, "DORIS-PARSE-002")
  assert_eq(stmt1[0].code, "DORIS-PARSE-007")
  assert_eq(stmt2[0].code, "DORIS-PARSE-007")
  assert_true(stmt0[0].start_byte <= stmt0[1].start_byte)
  assert_true(stmt0[1].start_byte < stmt1[0].start_byte)
  assert_true(stmt1[0].start_byte < stmt2[0].start_byte)
}
