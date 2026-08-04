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
