// LINE-01 end-to-end integration tests (plan 07-03): parse -> lineage over the
// real Doris parser and the api facade `@api.lineage_text`, asserting edge/gap
// structure with flattened byte spans and freezing the deterministic
// edges/gaps ordering via snapshot goldens (moon test --update is the only
// write path).
//
// lineage/ cannot import the parser (D-21), so these integration tests live in
// the test package (analyzer_anal01_test.mbt precedent), which already imports
// parser/source/dialect/api. Parsing uses @parser.parse_with_limits; lineage is
// derived through the api facade `@api.lineage_text` so the library surface
// (D-07) is exercised exactly as binding/CLI consumers will call it.

///|
/// Deterministic JSON rendering of a LineageResult for the snapshot golden.
/// Edge/gap order is the document order contract (Pattern 6): statement order
/// -> model branch/CTE order -> item order -> refs order; star expansion
/// follows scope-entry order x catalog column order.
fn lineage_result_to_json(result : @api.LineageResult) -> String {
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
  let mut out = "{\n  \"edges\": ["
  let mut first_edge = true
  for edge in result.edges {
    if first_edge {
      first_edge = false
    } else {
      out = out + ","
    }
    out = out +
      "\n    {\"source_name\":" +
      json_string(edge.source_name) +
      ",\"source_resolved_to\":" +
      json_string(edge.source_resolved_to) +
      ",\"source_start_byte\":" +
      edge.source_start_byte.to_string() +
      ",\"source_end_byte\":" +
      edge.source_end_byte.to_string() +
      ",\"target_name\":" +
      json_string(edge.target_name) +
      ",\"target_start_byte\":" +
      edge.target_start_byte.to_string() +
      ",\"target_end_byte\":" +
      edge.target_end_byte.to_string() +
      "}"
  }
  out = out + "\n  ],\n  \"gaps\": ["
  let mut first_gap = true
  for gap in result.gaps {
    if first_gap {
      first_gap = false
    } else {
      out = out + ","
    }
    out = out +
      "\n    {\"code\":" +
      json_string(gap.code) +
      ",\"message\":" +
      json_string(gap.message) +
      ",\"start_byte\":" +
      gap.start_byte.to_string() +
      ",\"end_byte\":" +
      gap.end_byte.to_string() +
      "}"
  }
  out + "\n  ]\n}"
}

///|
/// Parses `raw` as a Doris 4.x strict document (sanity: must parse cleanly),
/// then derives lineage through the api facade `@api.lineage_text` with the
/// optional catalog. Panics on a parse or lineage ParseError — integration
/// cases here are expected to derive.
fn lineage_sql(
  raw : Bytes,
  catalog : @analyzer.StaticCatalog?,
) -> @api.LineageResult {
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
  let options = match @api.ParseOptions::new("doris", "4.x", "strict") {
    Ok(options) => options
    Err(_) => panic()
  }
  match @api.lineage_text(raw, options, catalog) {
    Ok(result) => result
    Err(_) => panic()
  }
}

///|
/// Snapshot helper (analyzer_anal01_test.mbt:86-90): `moon test --update` is
/// the only write path. The snapshot is written BEFORE the field assertions so
/// a wrong prediction still freezes the observed edges/gaps for inspection.
fn lineage_snapshot_test(
  t : @mtest.Test,
  content : String,
  filename : String,
) -> Unit raise SnapshotError {
  t.write(content)
  t.snapshot(filename~)
}

///|
test "lineage expression passthrough doris-4.x" {
  // D-01: `SELECT a + b AS x FROM t` -> two edges t.a->x and t.b->x, both
  // targeting the alias span; no gaps (Pitfall 1: expression passthrough).
  let t = @mtest.Test("lineage expression passthrough doris-4.x")
  let raw = b"SELECT a + b AS x FROM t"
  let catalog = @analyzer.StaticCatalog::new([
    {
      name: "t",
      columns: [
        { name: "a", data_type: "INT" },
        { name: "b", data_type: "INT" },
      ],
    },
  ])
  let result = lineage_sql(raw, Some(catalog))
  lineage_snapshot_test(
    t,
    lineage_result_to_json(result),
    "lineage.expression-passthrough.doris-4.x.json",
  )
  assert_eq(result.edges.length(), 2)
  assert_eq(result.gaps.length(), 0)
  assert_eq(result.edges[0].source_name, "a")
  assert_eq(result.edges[0].source_resolved_to, "a")
  assert_eq(result.edges[0].target_name, "x")
  assert_eq(result.edges[1].source_name, "b")
  assert_eq(result.edges[1].target_name, "x")
}

///|
test "lineage star no catalog doris-4.x" {
  // SC2 / D-05: `SELECT * FROM t` with no catalog -> zero edges and one
  // requires-catalog gap at the star span; never a fabricated edge.
  let t = @mtest.Test("lineage star no catalog doris-4.x")
  let raw = b"SELECT * FROM t"
  let result = lineage_sql(raw, None)
  lineage_snapshot_test(
    t,
    lineage_result_to_json(result),
    "lineage.star-no-catalog.doris-4.x.json",
  )
  assert_eq(result.edges.length(), 0)
  assert_eq(result.gaps.length(), 1)
  assert_eq(result.gaps[0].code, "requires-catalog")
  assert_eq(result.gaps[0].start_byte, 7)
  assert_eq(result.gaps[0].end_byte, 8)
}

///|
test "lineage star with catalog doris-4.x" {
  // D-05: `SELECT * FROM t` with a catalog expands the star to real
  // passthrough edges (a->a, b->b) in catalog column order; no gaps.
  let t = @mtest.Test("lineage star with catalog doris-4.x")
  let raw = b"SELECT * FROM t"
  let catalog = @analyzer.StaticCatalog::new([
    {
      name: "t",
      columns: [
        { name: "a", data_type: "INT" },
        { name: "b", data_type: "VARCHAR(10)" },
      ],
    },
  ])
  let result = lineage_sql(raw, Some(catalog))
  lineage_snapshot_test(
    t,
    lineage_result_to_json(result),
    "lineage.star-with-catalog.doris-4.x.json",
  )
  assert_eq(result.edges.length(), 2)
  assert_eq(result.gaps.length(), 0)
  assert_eq(result.edges[0].source_name, "a")
  assert_eq(result.edges[0].target_name, "a")
  assert_eq(result.edges[1].source_name, "b")
  assert_eq(result.edges[1].target_name, "b")
}

///|
test "lineage cte union positional doris-4.x" {
  // D-02/D-04 (Pitfall 2): WITH c AS (SELECT a FROM t) SELECT a FROM c
  // UNION SELECT b FROM u -> CTE body edge t.a->c.a, outer branch a->a,
  // and the UNION second branch maps positionally to the first branch's
  // column name (b->a).
  let t = @mtest.Test("lineage cte union positional doris-4.x")
  let raw = b"WITH c AS (SELECT a FROM t) SELECT a FROM c UNION SELECT b FROM u"
  let catalog = @analyzer.StaticCatalog::new([
    { name: "t", columns: [{ name: "a", data_type: "INT" }] },
    { name: "u", columns: [{ name: "b", data_type: "INT" }] },
  ])
  let result = lineage_sql(raw, Some(catalog))
  lineage_snapshot_test(
    t,
    lineage_result_to_json(result),
    "lineage.cte-union-positional.doris-4.x.json",
  )
  assert_eq(result.gaps.length(), 0)
  assert_eq(result.edges.length(), 3)
  assert_eq(result.edges[0].source_name, "a")
  assert_eq(result.edges[0].target_name, "c.a")
  assert_eq(result.edges[1].source_name, "a")
  assert_eq(result.edges[1].target_name, "a")
  assert_eq(result.edges[2].source_name, "b")
  assert_eq(result.edges[2].target_name, "a")
}

///|
test "lineage insert positional doris-4.x" {
  // D-04: INSERT INTO t(c1,c2) SELECT a,b FROM u maps the trailing SELECT
  // output columns positionally to the column list: u.a->t.c1, u.b->t.c2.
  // The column list names targets without catalog metadata, so the
  // unknown-table gap for t is suppressed.
  let t = @mtest.Test("lineage insert positional doris-4.x")
  let raw = b"INSERT INTO t(c1,c2) SELECT a,b FROM u"
  let catalog = @analyzer.StaticCatalog::new([
    {
      name: "u",
      columns: [
        { name: "a", data_type: "INT" },
        { name: "b", data_type: "INT" },
      ],
    },
  ])
  let result = lineage_sql(raw, Some(catalog))
  lineage_snapshot_test(
    t,
    lineage_result_to_json(result),
    "lineage.insert-positional.doris-4.x.json",
  )
  assert_eq(result.edges.length(), 2)
  assert_eq(result.gaps.length(), 0)
  assert_eq(result.edges[0].source_name, "a")
  assert_eq(result.edges[0].target_name, "t.c1")
  assert_eq(result.edges[1].source_name, "b")
  assert_eq(result.edges[1].target_name, "t.c2")
}

///|
test "lineage star except honest expansion doris-4.x" {
  // Pitfall 3 option (a): `SELECT * EXCEPT (b) FROM t` expands honestly — the
  // excluded column b produces no binding/edge; only a->a remains (SC2).
  let t = @mtest.Test("lineage star except honest expansion doris-4.x")
  let raw = b"SELECT * EXCEPT (b) FROM t"
  let catalog = @analyzer.StaticCatalog::new([
    {
      name: "t",
      columns: [
        { name: "a", data_type: "INT" },
        { name: "b", data_type: "INT" },
      ],
    },
  ])
  let result = lineage_sql(raw, Some(catalog))
  lineage_snapshot_test(
    t,
    lineage_result_to_json(result),
    "lineage.star-except-honest.doris-4.x.json",
  )
  assert_eq(result.edges.length(), 1)
  assert_eq(result.gaps.length(), 0)
  assert_eq(result.edges[0].source_name, "a")
  assert_eq(result.edges[0].target_name, "a")
}

///|
test "lineage view registry expansion doris-4.x" {
  // D-03: CREATE VIEW v AS SELECT a FROM t; SELECT * FROM v -> the view body
  // edge t.a->v.a plus the outer star over the registered view expanding to a
  // real passthrough edge a->a; no requires-catalog gap (view registry).
  let t = @mtest.Test("lineage view registry expansion doris-4.x")
  let raw = b"CREATE VIEW v AS SELECT a FROM t; SELECT * FROM v"
  let catalog = @analyzer.StaticCatalog::new([
    { name: "t", columns: [{ name: "a", data_type: "INT" }] },
  ])
  let result = lineage_sql(raw, Some(catalog))
  lineage_snapshot_test(
    t,
    lineage_result_to_json(result),
    "lineage.view-registry-expansion.doris-4.x.json",
  )
  assert_eq(result.gaps.length(), 0)
  assert_eq(result.edges.length(), 2)
  assert_eq(result.edges[0].source_name, "a")
  assert_eq(result.edges[0].target_name, "v.a")
  assert_eq(result.edges[1].source_name, "a")
  assert_eq(result.edges[1].target_name, "a")
}

///|
test "lineage api facade matches lib entry no catalog" {
  // D-07 consistency: the api facade (lineage_text with None catalog) must
  // match the lineage library entry (derive_lineage_without_catalog)
  // byte-for-byte for the no-catalog path — the facade is a thin parse+derive
  // passthrough, not a second implementation.
  let raw = b"SELECT a, b FROM t"
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
  let via_api = lineage_sql(raw, None)
  let via_lib = @lineage.derive_lineage_without_catalog(
    parsed.root,
    source.bytes(),
  )
  assert_eq(lineage_result_to_json(via_api), lineage_result_to_json(via_lib))
}
