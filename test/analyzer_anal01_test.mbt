// ANAL-01 end-to-end tracer tests (plan 05-02): parse -> analyze over the real
// Doris parser, asserting bindings with flattened byte spans, the independent
// analyzer diagnostic channel (ANLY-01), and D-03 quoted/exact matching. A
// snapshot golden freezes the select-basic AnalysisResult (D-06).
//
// The analyzer package cannot import the parser (D-21), so these integration
// tests live in the test package, which already imports parser/source/dialect
// (analyzer_test.mbt precedent). Parsing uses @parser.parse_with_limits (the
// api facade's PrimitiveNode is not an @syntax.SyntaxNode).

/// Deterministic JSON rendering of an AnalysisResult for the snapshot golden.
fn analysis_result_to_json(result : @analyzer.AnalysisResult) -> String {
  fn kind_id(kind : @analyzer.BindingKind) -> String {
    match kind {
      @analyzer.BindingKind::Table => "table"
      @analyzer.BindingKind::Column => "column"
      @analyzer.BindingKind::Function => "function"
      @analyzer.BindingKind::Cte => "cte"
      @analyzer.BindingKind::Alias => "alias"
    }
  }
  fn json_string(s : String) -> String {
    let mut out = "\""
    for ch in s.iter() {
      if ch == '"' {
        out = out + "\\\""
      } else if ch == '\\' {
        out = out + "\\\\"
      } else {
        out = out + ch.to_string()
      }
    }
    out + "\""
  }
  let mut out = "{\n  \"bindings\": ["
  let mut first_binding = true
  for binding in result.bindings {
    if first_binding {
      first_binding = false
    } else {
      out = out + ","
    }
    out = out + "\n    {\"kind\":" + json_string(kind_id(binding.kind)) +
      ",\"name\":" + json_string(binding.name) +
      ",\"resolved_to\":" + json_string(binding.resolved_to) +
      ",\"data_type\":" + json_string(binding.data_type) +
      ",\"start_byte\":" + binding.start_byte.to_string() +
      ",\"end_byte\":" + binding.end_byte.to_string() + "}"
  }
  out = out + "\n  ],\n  \"diagnostics\": ["
  let mut first_diag = true
  for diagnostic in result.diagnostics {
    if first_diag {
      first_diag = false
    } else {
      out = out + ","
    }
    out = out + "\n    {\"code\":" + json_string(diagnostic.code) +
      ",\"message\":" + json_string(diagnostic.message) +
      ",\"start_byte\":" + diagnostic.start_byte.to_string() +
      ",\"end_byte\":" + diagnostic.end_byte.to_string() + "}"
  }
  out + "\n  ]\n}"
}

/// Parses `raw` as a Doris 4.x strict document and analyzes it with `catalog`.
/// Uses the parser-level entry (root is an @syntax.SyntaxNode), matching the
/// analyzer_test.mbt integration setup.
fn analyze_sql(raw : Bytes, catalog : @analyzer.StaticCatalog) -> @analyzer.AnalysisResult {
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
  if !parsed.valid {
    panic()
  }
  @analyzer.analyze(parsed.root, source.bytes(), catalog)
}

/// Snapshot helper (parity/flink_grammar_test.mbt:677-680): `moon test
/// --update` is the only write path.
fn analyzer_snapshot_test(t : @mtest.Test, content : String, filename : String) -> Unit raise SnapshotError {
  t.write(content)
  t.snapshot(filename=filename)
}

test "analyzer-anal01 select-basic doris-4.x" {
  let t = @mtest.Test("analyzer-anal01 select-basic doris-4.x")
  let raw = b"SELECT a, b FROM t"
  // byte offsets: SELECT[0,6) space[6] a[7,8) ,[8] space[9] b[10,11) space[11]
  // FROM[12,16) space[16] t[17,18)
  let catalog = @analyzer.StaticCatalog::new([
    {
      name: "t",
      columns: [
        { name: "a", data_type: "INT" },
        { name: "b", data_type: "VARCHAR(10)" },
      ],
    },
  ])
  let result = analyze_sql(raw, catalog)
  assert_eq(result.bindings.length(), 3)
  let table = result.bindings[0]
  assert_eq(table.kind, @analyzer.BindingKind::Table)
  assert_eq(table.name, "t")
  assert_eq(table.resolved_to, "t")
  assert_eq(table.data_type, "")
  assert_eq(table.start_byte, 17)
  assert_eq(table.end_byte, 18)
  let a = result.bindings[1]
  assert_eq(a.kind, @analyzer.BindingKind::Column)
  assert_eq(a.name, "a")
  assert_eq(a.resolved_to, "a")
  assert_eq(a.data_type, "INT")
  assert_eq(a.start_byte, 7)
  assert_eq(a.end_byte, 8)
  let b = result.bindings[2]
  assert_eq(b.kind, @analyzer.BindingKind::Column)
  assert_eq(b.name, "b")
  assert_eq(b.resolved_to, "b")
  assert_eq(b.data_type, "VARCHAR(10)")
  assert_eq(b.start_byte, 10)
  assert_eq(b.end_byte, 11)
  assert_eq(result.diagnostics.length(), 0)
  analyzer_snapshot_test(t, analysis_result_to_json(result), "analyzer.select-basic.doris-4.x.json")
}

test "analyzer-anal01 unknown-table diagnostic" {
  // A missing table produces an unknown-table diagnostic on the analyzer's own
  // channel; the syntax valid flag stays true (ANLY-01 — analyzer diagnostics
  // never enter the parser's valid/diagnostic channel).
  let raw = b"SELECT a FROM missing"
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
  let catalog = @analyzer.StaticCatalog::new([{ name: "t", columns: [{ name: "a", data_type: "INT" }] }])
  let result = @analyzer.analyze(parsed.root, source.bytes(), catalog)
  assert_eq(result.bindings.length(), 0)
  assert_eq(result.diagnostics.length(), 1)
  assert_eq(result.diagnostics[0].code, "unknown-table")
  assert_eq(result.diagnostics[0].message, "table not found in catalog: missing")
  // Re-parsing the same bytes yields the identical syntax result.
  let parsed_again = @parser.parse_with_limits(
    source,
    doris_context("4.x"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  assert_eq(parsed_again.valid, parsed.valid)
  assert_eq(parsed_again.diagnostics.length(), parsed.diagnostics.length())
  assert_eq(parsed_again.root.kind(), parsed.root.kind())
}

test "analyzer-anal01 quoted-exact generic" {
  // D-03: quoted identifiers resolve through Catalog::table (case-fold) and a
  // byte-exact re-check of the returned TableInfo.name. StaticCatalog
  // lookup_exact is never called on this generic path.
  let raw = b"SELECT `T` FROM `T`"
  // Catalog has exactly "T": case-fold hit + byte re-check passes.
  let catalog_exact = @analyzer.StaticCatalog::new([{ name: "T", columns: [] }])
  let result_exact = analyze_sql(raw, catalog_exact)
  assert_eq(result_exact.bindings.length(), 1)
  assert_eq(result_exact.bindings[0].kind, @analyzer.BindingKind::Table)
  assert_eq(result_exact.bindings[0].name, "T")
  assert_eq(result_exact.bindings[0].resolved_to, "T")
  assert_eq(result_exact.diagnostics.length(), 0)
  // Catalog has only "t": the case-fold hit returns TableInfo.name "t", which
  // fails the byte re-check against the quoted spelling "T" -> unknown-table.
  let catalog_lower = @analyzer.StaticCatalog::new([{ name: "t", columns: [] }])
  let result_miss = analyze_sql(raw, catalog_lower)
  assert_eq(result_miss.bindings.length(), 0)
  assert_eq(result_miss.diagnostics.length(), 1)
  assert_eq(result_miss.diagnostics[0].code, "unknown-table")
  // Unquoted `t` against a catalog keyed "T": direct case-fold hit, no byte
  // re-check (D-03).
  let raw_unquoted = b"SELECT a FROM t"
  let catalog_up = @analyzer.StaticCatalog::new([{ name: "T", columns: [{ name: "a", data_type: "INT" }] }])
  let result_unquoted = analyze_sql(raw_unquoted, catalog_up)
  assert_eq(result_unquoted.bindings.length(), 2)
  assert_eq(result_unquoted.bindings[0].kind, @analyzer.BindingKind::Table)
  assert_eq(result_unquoted.bindings[0].name, "t")
  assert_eq(result_unquoted.bindings[0].resolved_to, "T")
  assert_eq(result_unquoted.bindings[1].kind, @analyzer.BindingKind::Column)
  assert_eq(result_unquoted.bindings[1].name, "a")
  assert_eq(result_unquoted.bindings[1].resolved_to, "a")
  assert_eq(result_unquoted.bindings[1].data_type, "INT")
  assert_eq(result_unquoted.diagnostics.length(), 0)
}

test "analyzer-anal01 cte-scope doris-4.x" {
  // D-02 / Pitfall 4: WITH c AS (SELECT a FROM t) SELECT a FROM c — the FROM c
  // reference resolves to the CTE (Cte binding), not to a catalog table, and
  // the CTE body's `a` resolves to t's column. Byte offsets:
  // WITH[0,4) c[5,6) AS[7,9) ([10,26) SELECT[11,17) a[18,19) FROM[20,24)
  // t[25,26) )[26,27) SELECT[28,34) a[35,36) FROM[37,41) c[42,43)
  let t = @mtest.Test("analyzer-anal01 cte-scope doris-4.x")
  let raw = b"WITH c AS (SELECT a FROM t) SELECT a FROM c"
  let catalog = @analyzer.StaticCatalog::new([
    { name: "t", columns: [{ name: "a", data_type: "INT" }] },
  ])
  let result = analyze_sql(raw, catalog)
  assert_eq(result.bindings.length(), 4)
  let table = result.bindings[0]
  assert_eq(table.kind, @analyzer.BindingKind::Table)
  assert_eq(table.name, "t")
  assert_eq(table.resolved_to, "t")
  assert_eq(table.start_byte, 25)
  assert_eq(table.end_byte, 26)
  let body_col = result.bindings[1]
  assert_eq(body_col.kind, @analyzer.BindingKind::Column)
  assert_eq(body_col.name, "a")
  assert_eq(body_col.resolved_to, "a")
  assert_eq(body_col.data_type, "INT")
  assert_eq(body_col.start_byte, 18)
  assert_eq(body_col.end_byte, 19)
  let cte = result.bindings[2]
  assert_eq(cte.kind, @analyzer.BindingKind::Cte)
  assert_eq(cte.name, "c")
  assert_eq(cte.resolved_to, "c")
  assert_eq(cte.start_byte, 42)
  assert_eq(cte.end_byte, 43)
  let main_col = result.bindings[3]
  assert_eq(main_col.kind, @analyzer.BindingKind::Column)
  assert_eq(main_col.name, "a")
  assert_eq(main_col.resolved_to, "a")
  assert_eq(main_col.data_type, "INT")
  assert_eq(main_col.start_byte, 35)
  assert_eq(main_col.end_byte, 36)
  assert_eq(result.diagnostics.length(), 0)
  analyzer_snapshot_test(t, analysis_result_to_json(result), "analyzer.cte-scope.doris-4.x.json")
}

test "analyzer-anal01 subquery-alias doris-4.x" {
  // D-02 / Pitfall 4: SELECT x.a FROM (SELECT a FROM t) x — the subquery alias
  // x shadows any outer table; the inner a resolves inside the subquery and
  // x.a resolves against the subquery's output column. Byte offsets:
  // SELECT[0,6) x[7,8) .[8] a[9,10) FROM[11,15) ([16,32) SELECT[17,23)
  // a[24,25) FROM[26,30) t[31,32) )[32,33) x[34,35)
  let t = @mtest.Test("analyzer-anal01 subquery-alias doris-4.x")
  let raw = b"SELECT x.a FROM (SELECT a FROM t) x"
  let catalog = @analyzer.StaticCatalog::new([
    { name: "t", columns: [{ name: "a", data_type: "INT" }] },
  ])
  let result = analyze_sql(raw, catalog)
  assert_eq(result.bindings.length(), 4)
  let inner_table = result.bindings[0]
  assert_eq(inner_table.kind, @analyzer.BindingKind::Table)
  assert_eq(inner_table.name, "t")
  assert_eq(inner_table.start_byte, 31)
  assert_eq(inner_table.end_byte, 32)
  let inner_col = result.bindings[1]
  assert_eq(inner_col.kind, @analyzer.BindingKind::Column)
  assert_eq(inner_col.name, "a")
  assert_eq(inner_col.data_type, "INT")
  assert_eq(inner_col.start_byte, 24)
  assert_eq(inner_col.end_byte, 25)
  let alias = result.bindings[2]
  assert_eq(alias.kind, @analyzer.BindingKind::Alias)
  assert_eq(alias.name, "x")
  assert_eq(alias.resolved_to, "x")
  assert_eq(alias.start_byte, 34)
  assert_eq(alias.end_byte, 35)
  let outer_col = result.bindings[3]
  assert_eq(outer_col.kind, @analyzer.BindingKind::Column)
  assert_eq(outer_col.name, "a")
  assert_eq(outer_col.resolved_to, "a")
  assert_eq(outer_col.data_type, "INT")
  assert_eq(outer_col.start_byte, 7)
  assert_eq(outer_col.end_byte, 10)
  assert_eq(result.diagnostics.length(), 0)
  analyzer_snapshot_test(t, analysis_result_to_json(result), "analyzer.subquery-alias.doris-4.x.json")
}

test "analyzer-anal01 union-chain doris-4.x" {
  // D-02 / Pitfall 2: UNION chain — each branch resolves independently.
  // SELECT[0,6) a[7,8) FROM[9,13) t[14,15) UNION[16,21) SELECT[22,28)
  // b[29,30) FROM[31,35) t2[36,38)
  let t = @mtest.Test("analyzer-anal01 union-chain doris-4.x")
  let raw = b"SELECT a FROM t UNION SELECT b FROM t2"
  let catalog = @analyzer.StaticCatalog::new([
    { name: "t", columns: [{ name: "a", data_type: "INT" }] },
    { name: "t2", columns: [{ name: "b", data_type: "VARCHAR(5)" }] },
  ])
  let result = analyze_sql(raw, catalog)
  assert_eq(result.bindings.length(), 4)
  let t1 = result.bindings[0]
  assert_eq(t1.kind, @analyzer.BindingKind::Table)
  assert_eq(t1.name, "t")
  assert_eq(t1.start_byte, 14)
  assert_eq(t1.end_byte, 15)
  let a = result.bindings[1]
  assert_eq(a.kind, @analyzer.BindingKind::Column)
  assert_eq(a.name, "a")
  assert_eq(a.data_type, "INT")
  assert_eq(a.start_byte, 7)
  assert_eq(a.end_byte, 8)
  let t2 = result.bindings[2]
  assert_eq(t2.kind, @analyzer.BindingKind::Table)
  assert_eq(t2.name, "t2")
  assert_eq(t2.start_byte, 36)
  assert_eq(t2.end_byte, 38)
  let b = result.bindings[3]
  assert_eq(b.kind, @analyzer.BindingKind::Column)
  assert_eq(b.name, "b")
  assert_eq(b.data_type, "VARCHAR(5)")
  assert_eq(b.start_byte, 29)
  assert_eq(b.end_byte, 30)
  assert_eq(result.diagnostics.length(), 0)
  analyzer_snapshot_test(t, analysis_result_to_json(result), "analyzer.union-chain.doris-4.x.json")
}

test "analyzer-anal01 as-alias doris-4.x" {
  // D-02: AS aliases on both a projection and a table ref. SELECT[0,6)
  // a[7,8) AS[9,11) x[12,13) FROM[14,18) t[19,20) AS[21,23) y[24,25)
  let t = @mtest.Test("analyzer-anal01 as-alias doris-4.x")
  let raw = b"SELECT a AS x FROM t AS y"
  let catalog = @analyzer.StaticCatalog::new([
    { name: "t", columns: [{ name: "a", data_type: "INT" }] },
  ])
  let result = analyze_sql(raw, catalog)
  assert_eq(result.bindings.length(), 4)
  let table = result.bindings[0]
  assert_eq(table.kind, @analyzer.BindingKind::Table)
  assert_eq(table.name, "t")
  assert_eq(table.resolved_to, "t")
  assert_eq(table.start_byte, 19)
  assert_eq(table.end_byte, 20)
  let table_alias = result.bindings[1]
  assert_eq(table_alias.kind, @analyzer.BindingKind::Alias)
  assert_eq(table_alias.name, "y")
  assert_eq(table_alias.resolved_to, "t")
  assert_eq(table_alias.start_byte, 24)
  assert_eq(table_alias.end_byte, 25)
  let col = result.bindings[2]
  assert_eq(col.kind, @analyzer.BindingKind::Column)
  assert_eq(col.name, "a")
  assert_eq(col.resolved_to, "a")
  assert_eq(col.data_type, "INT")
  assert_eq(col.start_byte, 7)
  assert_eq(col.end_byte, 8)
  let proj_alias = result.bindings[3]
  assert_eq(proj_alias.kind, @analyzer.BindingKind::Alias)
  assert_eq(proj_alias.name, "x")
  assert_eq(proj_alias.resolved_to, "a")
  assert_eq(proj_alias.start_byte, 12)
  assert_eq(proj_alias.end_byte, 13)
  assert_eq(result.diagnostics.length(), 0)
  analyzer_snapshot_test(t, analysis_result_to_json(result), "analyzer.as-alias.doris-4.x.json")
}

test "analyzer-anal01 qualified-name doris-4.x" {
  // D-05 / Pitfall 3: db.table.col (3 parts) resolves via table_in_db while
  // alias.col (2 parts) resolves through the scope. SELECT[0,6) t[7,8) .[8]
  // a[9,10) ,[10] db[12,14) .[14] t[15,16) .[16] b[17,18) FROM[19,23)
  // db[24,26) .[26] t[27,28)
  let t = @mtest.Test("analyzer-anal01 qualified-name doris-4.x")
  let raw = b"SELECT t.a, db.t.b FROM db.t"
  let catalog = @analyzer.StaticCatalog::new([
    { name: "t", columns: [{ name: "a", data_type: "INT" }] },
  ]).with_db(
    "db",
    "t",
    { name: "t", columns: [{ name: "a", data_type: "INT" }, { name: "b", data_type: "VARCHAR(20)" }] },
  )
  let result = analyze_sql(raw, catalog)
  assert_eq(result.bindings.length(), 3)
  let table = result.bindings[0]
  assert_eq(table.kind, @analyzer.BindingKind::Table)
  assert_eq(table.name, "db.t")
  assert_eq(table.resolved_to, "t")
  assert_eq(table.start_byte, 24)
  assert_eq(table.end_byte, 28)
  let a = result.bindings[1]
  assert_eq(a.kind, @analyzer.BindingKind::Column)
  assert_eq(a.name, "a")
  assert_eq(a.resolved_to, "a")
  assert_eq(a.data_type, "INT")
  assert_eq(a.start_byte, 7)
  assert_eq(a.end_byte, 10)
  let b = result.bindings[2]
  assert_eq(b.kind, @analyzer.BindingKind::Column)
  assert_eq(b.name, "b")
  assert_eq(b.resolved_to, "b")
  assert_eq(b.data_type, "VARCHAR(20)")
  assert_eq(b.start_byte, 12)
  assert_eq(b.end_byte, 18)
  assert_eq(result.diagnostics.length(), 0)
  analyzer_snapshot_test(t, analysis_result_to_json(result), "analyzer.qualified-name.doris-4.x.json")
}

test "analyzer-anal01 star-expansion doris-4.x" {
  // D-05: table.* star expansion over the resolved FROM table.
  // SELECT[0,6) t[7,8) .[8] *[9,10) FROM[11,15) t[16,17)
  let t = @mtest.Test("analyzer-anal01 star-expansion doris-4.x")
  let raw = b"SELECT t.* FROM t"
  let catalog = @analyzer.StaticCatalog::new([
    { name: "t", columns: [{ name: "a", data_type: "INT" }, { name: "b", data_type: "VARCHAR(10)" }] },
  ])
  let result = analyze_sql(raw, catalog)
  assert_eq(result.bindings.length(), 3)
  let table = result.bindings[0]
  assert_eq(table.kind, @analyzer.BindingKind::Table)
  assert_eq(table.name, "t")
  assert_eq(table.start_byte, 16)
  assert_eq(table.end_byte, 17)
  let a = result.bindings[1]
  assert_eq(a.kind, @analyzer.BindingKind::Column)
  assert_eq(a.name, "a")
  assert_eq(a.resolved_to, "a")
  assert_eq(a.data_type, "INT")
  assert_eq(a.start_byte, 9)
  assert_eq(a.end_byte, 10)
  let b = result.bindings[2]
  assert_eq(b.kind, @analyzer.BindingKind::Column)
  assert_eq(b.name, "b")
  assert_eq(b.resolved_to, "b")
  assert_eq(b.data_type, "VARCHAR(10)")
  assert_eq(b.start_byte, 9)
  assert_eq(b.end_byte, 10)
  assert_eq(result.diagnostics.length(), 0)
  analyzer_snapshot_test(t, analysis_result_to_json(result), "analyzer.star-expansion.doris-4.x.json")
}
