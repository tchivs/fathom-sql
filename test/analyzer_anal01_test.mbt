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
