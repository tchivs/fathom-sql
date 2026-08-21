///|
/// White-box tests for lineage edge derivation (plan 07-02, Task 1 tracer).
///
/// These construct `@analyzer.SelectModel`/`Binding` values directly and
/// exercise the package-private pure derivation functions — no parser import
/// (D-21). The full `derive_lineage(root, ...)` document walk needs a parsed
/// `@syntax.SyntaxNode`, which the test package exercises (07-03 integration);
/// here we lock the derivation semantics per plan task.
///
/// NOTE: this is `_wbtest.mbt` (white-box) because `_test.mbt` files on
/// moon 0.1.20260724 are black-box (they cannot see package-private
/// functions). Local type aliases avoid a parser quirk with `@pkg.Type]`
/// inside generic type arguments in test files.
type ABinding = @analyzer.Binding

///|
type ACteDef = @analyzer.CteDef

///|
type ADiagnostic = @analyzer.AnalysisDiagnostic

///|
type ANameRef = @analyzer.NameRef

///|
type ASelectItem = @analyzer.SelectItem

///|
type ASelectCore = @analyzer.SelectCore

///|
type ASelectModel = @analyzer.SelectModel

///|
type ATokenSlice = @analyzer.TokenSlice

///|
/// A single-part NameRef at `[start, end)`.
fn t_ref(start : Int, end : Int) -> ANameRef {
  {
    parts: [{ bytes: b"x", start_byte: start, end_byte: end }],
    star: false,
    is_call: false,
    call_args: [],
    start_byte: start,
    end_byte: end,
  }
}

///|
/// A function-call NameRef at `[start, end)` with one captured arg token.
fn t_call_ref(start : Int, end : Int) -> ANameRef {
  {
    parts: [{ bytes: b"f", start_byte: start, end_byte: start + 1 }],
    star: false,
    is_call: true,
    call_args: [{ bytes: b"c", start_byte: start + 1, end_byte: end }],
    start_byte: start,
    end_byte: end,
  }
}

///|
/// A SelectItem with the given refs, alias, and alias slice span.
fn t_item(
  refs : Array[ANameRef],
  alias : String?,
  alias_start : Int,
  alias_end : Int,
) -> ASelectItem {
  let alias_slice : ATokenSlice? = match alias {
    Some(_) =>
      Some({ bytes: b"x", start_byte: alias_start, end_byte: alias_end })
    None => None
  }
  {
    tokens: [],
    alias,
    alias_slice,
    star: false,
    star_qualifier: None,
    refs,
    except_cols: [],
  }
}

///|
/// A star SelectItem whose star token is at `[start, end)`.
fn t_star_item(start : Int, end : Int) -> ASelectItem {
  {
    tokens: [{ bytes: b"*", start_byte: start, end_byte: end }],
    alias: None,
    alias_slice: None,
    star: true,
    star_qualifier: None,
    refs: [],
    except_cols: [],
  }
}

///|
/// A single-core SelectModel with one branch.
fn t_model(select_list : Array[ASelectItem]) -> ASelectModel {
  {
    ctes: [],
    branches: [
      {
        select_list,
        from: [],
        joins: [],
        where_refs: [],
        group_by: [],
        having: [],
        qualify: [],
        order_by: [],
        limit: [],
        window: [],
        set_op: None,
      },
    ],
  }
}

///|
/// A Column binding at `[start, end)`.
fn t_col_binding(
  name : String,
  resolved : String,
  start : Int,
  end : Int,
) -> ABinding {
  {
    kind: @analyzer.BindingKind::Column,
    name,
    resolved_to: resolved,
    data_type: "INT",
    start_byte: start,
    end_byte: end,
  }
}

///|
/// A Function binding at `[start, end)`.
fn t_fn_binding(name : String, start : Int, end : Int) -> ABinding {
  {
    kind: @analyzer.BindingKind::Function,
    name,
    resolved_to: name,
    data_type: "INT",
    start_byte: start,
    end_byte: end,
  }
}

///|
/// Builds a (bytes, span) token array from bare word bytes with monotonically
/// increasing synthetic byte offsets (mirror of the analyzer's wb_tokens).
fn t_tokens(words : Array[Bytes]) -> Array[(Bytes, Int, Int)] {
  let out : Array[(Bytes, Int, Int)] = []
  let mut offset = 0
  for word in words {
    out.push((word, offset, offset + word.length()))
    offset = offset + word.length() + 1
  }
  out
}

///|
/// Runs the SELECT-family body derivation, appending edges/gaps to the given
/// output arrays (out-params instead of a tuple return to keep the test file
/// clear of the moon 0.1.20260724 tuple-return parse quirk).
fn run_body(
  model : ASelectModel?,
  has_error : Bool,
  bindings : Array[ABinding],
  diagnostics : Array[ADiagnostic],
  catalog_none : Bool,
  body_has_table_binding : Bool,
  qualifier : String?,
  out_edges : Array[LineageEdge],
  out_gaps : Array[LineageGap],
) -> Unit {
  let (e, g) = derive_select_body(
    model, has_error, 0, 100, bindings, diagnostics, catalog_none, body_has_table_binding,
    qualifier,
  )
  for edge in e {
    out_edges.push(edge)
  }
  for gap in g {
    out_gaps.push(gap)
  }
}

///|
test "lineage D-01 expression passthrough a + b as x" {
  // Test 1: `SELECT a + b AS x` over catalog t:[a,b] -> 2 edges: t.a->x and
  // t.b->x, target span = the alias slice span (D-01 expression passthrough).
  let item = t_item([t_ref(7, 8), t_ref(10, 11)], Some("x"), 15, 16)
  let model = t_model([item])
  let bindings : Array[ABinding] = [
    t_col_binding("a", "a", 7, 8),
    t_col_binding("b", "b", 10, 11),
  ]
  let edges : Array[LineageEdge] = []
  let gaps : Array[LineageGap] = []
  run_body(Some(model), false, bindings, [], false, true, None, edges, gaps)
  assert_eq(edges.length(), 2)
  assert_eq(gaps.length(), 0)
  assert_eq(edges[0].source_name, "a")
  assert_eq(edges[0].source_resolved_to, "a")
  assert_eq(edges[0].source_start_byte, 7)
  assert_eq(edges[0].source_end_byte, 8)
  assert_eq(edges[0].target_name, "x")
  assert_eq(edges[0].target_start_byte, 15)
  assert_eq(edges[0].target_end_byte, 16)
  assert_eq(edges[1].source_name, "b")
  assert_eq(edges[1].source_start_byte, 10)
  assert_eq(edges[1].source_end_byte, 11)
  assert_eq(edges[1].target_name, "x")
}

///|
test "lineage D-01 single ref and function argument" {
  // Test 2a: `SELECT a AS x` -> 1 edge t.a->x.
  let item_a = t_item([t_ref(7, 8)], Some("x"), 15, 16)
  let model_a = t_model([item_a])
  let bindings_a : Array[ABinding] = [t_col_binding("a", "a", 7, 8)]
  let edges_a : Array[LineageEdge] = []
  let gaps_a : Array[LineageGap] = []
  run_body(
    Some(model_a),
    false,
    bindings_a,
    [],
    false,
    true,
    None,
    edges_a,
    gaps_a,
  )
  assert_eq(edges_a.length(), 1)
  assert_eq(edges_a[0].source_name, "a")
  assert_eq(edges_a[0].target_name, "x")

  // Test 2b: `SELECT upper(c) AS u` -> the is_call ref itself resolves to a
  // Function binding (no edge); the argument ref c resolves to a Column
  // binding -> 1 edge t.c->u.
  let item_u = t_item([t_call_ref(7, 12), t_ref(13, 14)], Some("u"), 16, 17)
  let model_u = t_model([item_u])
  let bindings_u : Array[ABinding] = [
    t_fn_binding("upper", 7, 12),
    t_col_binding("c", "c", 13, 14),
  ]
  let edges_u : Array[LineageEdge] = []
  let gaps_u : Array[LineageGap] = []
  run_body(
    Some(model_u),
    false,
    bindings_u,
    [],
    false,
    true,
    None,
    edges_u,
    gaps_u,
  )
  assert_eq(edges_u.length(), 1)
  assert_eq(edges_u[0].source_name, "c")
  assert_eq(edges_u[0].source_resolved_to, "c")
  assert_eq(edges_u[0].source_start_byte, 13)
  assert_eq(edges_u[0].source_end_byte, 14)
  assert_eq(edges_u[0].target_name, "u")
}

///|
test "lineage CTE body qualified edge and UNION positional mapping" {
  // Test 3a: WITH c AS (SELECT a FROM t) SELECT a FROM c -> CTE body edge
  // t.a->c.a (CTE-qualified target) plus the outer ref edge a->a.
  let cte_body = t_model([t_item([t_ref(7, 8)], None, 0, 0)])
  let cte : ACteDef = { name: "c", alias: None, body: cte_body.branches[0] }
  let outer_core : ASelectCore = {
    select_list: [t_item([t_ref(25, 26)], None, 0, 0)],
    from: [],
    joins: [],
    where_refs: [],
    group_by: [],
    having: [],
    qualify: [],
    order_by: [],
    limit: [],
    window: [],
    set_op: None,
  }
  let model : ASelectModel = { ctes: [cte], branches: [outer_core] }
  let bindings : Array[ABinding] = [
    t_col_binding("a", "a", 7, 8),
    t_col_binding("a", "a", 25, 26),
  ]
  let edges : Array[LineageEdge] = []
  let gaps : Array[LineageGap] = []
  run_body(Some(model), false, bindings, [], false, true, None, edges, gaps)
  assert_eq(edges.length(), 2)
  assert_eq(edges[0].target_name, "c.a")
  assert_eq(edges[0].source_start_byte, 7)
  assert_eq(edges[0].source_end_byte, 8)
  assert_eq(edges[1].target_name, "a")
  assert_eq(edges[1].source_start_byte, 25)
  assert_eq(edges[1].source_end_byte, 26)

  // Test 3b: UNION branches map positionally to the first branch's column
  // names: `SELECT a FROM t UNION SELECT b FROM u` -> edges a->a, b->a.
  let b1 = t_model([t_item([t_ref(7, 8)], None, 0, 0)])
  let b2_item = t_item([t_ref(15, 16)], None, 0, 0)
  let b2 : ASelectCore = {
    select_list: [b2_item],
    from: [],
    joins: [],
    where_refs: [],
    group_by: [],
    having: [],
    qualify: [],
    order_by: [],
    limit: [],
    window: [],
    set_op: None,
  }
  let union_model : ASelectModel = { ctes: [], branches: [b1.branches[0], b2] }
  let union_bindings : Array[ABinding] = [
    t_col_binding("a", "a", 7, 8),
    t_col_binding("b", "b", 15, 16),
  ]
  let union_edges : Array[LineageEdge] = []
  let union_gaps : Array[LineageGap] = []
  run_body(
    Some(union_model),
    false,
    union_bindings,
    [],
    false,
    true,
    None,
    union_edges,
    union_gaps,
  )
  assert_eq(union_edges.length(), 2)
  assert_eq(union_edges[0].target_name, "a")
  assert_eq(union_edges[1].target_name, "a")
  assert_eq(union_edges[1].source_name, "b")
  assert_eq(union_edges[1].source_start_byte, 15)
  assert_eq(union_edges[1].source_end_byte, 16)
}

///|
test "lineage star no catalog zero edges with requires-catalog gap" {
  // Test 4: `SELECT * FROM t` with no catalog -> 0 edges and one
  // requires-catalog gap at the star span (SC2: never fabricate edges).
  let model = t_model([t_star_item(7, 8)])
  let bindings : Array[ABinding] = []
  let edges : Array[LineageEdge] = []
  let gaps : Array[LineageGap] = []
  run_body(Some(model), false, bindings, [], true, false, None, edges, gaps)
  assert_eq(edges.length(), 0)
  assert_eq(gaps.length(), 1)
  assert_eq(gaps[0].code, GAP_REQUIRES_CATALOG)
  assert_eq(gaps[0].start_byte, 7)
  assert_eq(gaps[0].end_byte, 8)
}

///|
test "lineage star with catalog expands to real edges" {
  // Task 2 Test 2: `SELECT * FROM t` with catalog {t:[a,b]} -> the star span
  // carries two Column bindings -> 2 passthrough edges t.a->a, t.b->b, no gaps.
  let model = t_model([t_star_item(7, 8)])
  let bindings : Array[ABinding] = [
    t_col_binding("a", "a", 7, 8),
    t_col_binding("b", "b", 7, 8),
  ]
  let edges : Array[LineageEdge] = []
  let gaps : Array[LineageGap] = []
  run_body(Some(model), false, bindings, [], false, true, None, edges, gaps)
  assert_eq(edges.length(), 2)
  assert_eq(gaps.length(), 0)
  assert_eq(edges[0].source_name, "a")
  assert_eq(edges[0].source_resolved_to, "a")
  assert_eq(edges[0].target_name, "a")
  assert_eq(edges[0].target_start_byte, 7)
  assert_eq(edges[1].source_name, "b")
  assert_eq(edges[1].target_name, "b")
}

///|
test "lineage unresolved reference maps to gap" {
  // Task 2 Test 3: `SELECT nope FROM t` -> unknown-column diagnostic at the
  // ref span -> unresolved-reference gap, message preserved, no edge.
  let item = t_item([t_ref(7, 11)], Some("x"), 15, 16)
  let model = t_model([item])
  let bindings : Array[ABinding] = []
  let diagnostics : Array[ADiagnostic] = [
    {
      code: "unknown-column",
      message: "column not found in any visible table: nope",
      start_byte: 7,
      end_byte: 11,
    },
  ]
  let edges : Array[LineageEdge] = []
  let gaps : Array[LineageGap] = []
  run_body(
    Some(model),
    false,
    bindings,
    diagnostics,
    false,
    true,
    None,
    edges,
    gaps,
  )
  assert_eq(edges.length(), 0)
  assert_eq(gaps.length(), 1)
  assert_eq(gaps[0].code, GAP_UNRESOLVED_REFERENCE)
  assert_eq(gaps[0].message, "column not found in any visible table: nope")
  assert_eq(gaps[0].start_byte, 7)
  assert_eq(gaps[0].end_byte, 11)
}

///|
test "lineage unknown-table no catalog is requires-catalog" {
  // Task 2 Test 3: `SELECT a FROM missing_t` without a catalog -> the
  // unknown-table diagnostic maps to requires-catalog (can't distinguish a
  // missing table from an external view, A1).
  let item = t_item([t_ref(7, 8)], None, 0, 0)
  let model = t_model([item])
  let bindings : Array[ABinding] = []
  let diagnostics : Array[ADiagnostic] = [
    {
      code: "unknown-table",
      message: "table not found in catalog: missing_t",
      start_byte: 15,
      end_byte: 24,
    },
  ]
  let edges : Array[LineageEdge] = []
  let gaps : Array[LineageGap] = []
  run_body(
    Some(model),
    false,
    bindings,
    diagnostics,
    true,
    false,
    None,
    edges,
    gaps,
  )
  assert_eq(gaps.length(), 1)
  assert_eq(gaps[0].code, GAP_REQUIRES_CATALOG)
  assert_eq(gaps[0].message, "table not found in catalog: missing_t")
}

///|
test "lineage ambiguous reference merges to unresolved-reference" {
  // Task 2 Test 5: ambiguous-reference diagnostic -> unresolved-reference gap
  // (Open Question 2 merge), message preserved.
  let item = t_item([t_ref(7, 8)], Some("x"), 15, 16)
  let model = t_model([item])
  let bindings : Array[ABinding] = []
  let diagnostics : Array[ADiagnostic] = [
    {
      code: "ambiguous-reference",
      message: "ambiguous reference: a",
      start_byte: 7,
      end_byte: 8,
    },
  ]
  let edges : Array[LineageEdge] = []
  let gaps : Array[LineageGap] = []
  run_body(
    Some(model),
    false,
    bindings,
    diagnostics,
    false,
    true,
    None,
    edges,
    gaps,
  )
  assert_eq(edges.length(), 0)
  assert_eq(gaps.length(), 1)
  assert_eq(gaps[0].code, GAP_UNRESOLVED_REFERENCE)
  assert_eq(gaps[0].message, "ambiguous reference: a")
}

///|
test "lineage error body reports requires-complete-parse" {
  // Task 2 Test 4: a body carrying error/missing material -> a single
  // requires-complete-parse gap at the body span (D-33 refusal), no edges.
  let diagnostics : Array[ADiagnostic] = [
    {
      code: "requires-complete-parse",
      message: "refusing to analyze a SELECT with error/missing material",
      start_byte: 0,
      end_byte: 100,
    },
  ]
  let edges : Array[LineageEdge] = []
  let gaps : Array[LineageGap] = []
  run_body(None, true, [], diagnostics, false, false, None, edges, gaps)
  assert_eq(edges.length(), 0)
  assert_eq(gaps.length(), 1)
  assert_eq(gaps[0].code, GAP_REQUIRES_COMPLETE_PARSE)
  assert_eq(gaps[0].start_byte, 0)
  assert_eq(gaps[0].end_byte, 100)
}

///|
test "lineage view registry and ViewCatalog shadow" {
  // Task 3 Test 1 (registry + ViewCatalog): `CREATE VIEW v AS SELECT a FROM t`
  // yields v's output column a; ViewCatalog.table resolves the registry view
  // before the inner catalog, so a same-name view shadows a catalog table
  // (Pitfall 4); names outside the registry delegate to the inner catalog.
  let model = t_model([t_item([t_ref(7, 8)], None, 0, 0)])
  let bindings : Array[ABinding] = [t_col_binding("a", "a", 7, 8)]
  let cols = view_output_columns(model, bindings, None)
  assert_eq(cols.length(), 1)
  assert_eq(cols[0].name, "a")
  let catalog = @analyzer.StaticCatalog::new([
    { name: "t", columns: [{ name: "a", data_type: "INT" }] },
  ])
  let vc = ViewCatalog::{
    views: Map([("v", cols), ("t", cols)]),
    inner: catalog,
  }
  // Registry hit: FROM v resolves to the view's output columns.
  let tv = match @analyzer.Catalog::table(vc, "v") {
    Some(i) => i
    None => panic()
  }
  assert_eq(tv.name, "v")
  assert_eq(tv.columns.length(), 1)
  assert_eq(tv.columns[0].name, "a")
  // Same-name view shadows the catalog table t (Pitfall 4).
  let shadow = match @analyzer.Catalog::table(vc, "t") {
    Some(i) => i
    None => panic()
  }
  assert_eq(shadow.name, "t")
  assert_eq(shadow.columns[0].name, "a")
  // Delegate: a name in the inner catalog but not a view resolves normally.
  let catalog2 = @analyzer.StaticCatalog::new([
    { name: "u", columns: [{ name: "x", data_type: "INT" }] },
  ])
  let vc2 = ViewCatalog::{ views: Map([("v", cols)]), inner: catalog2 }
  let tu = match @analyzer.Catalog::table(vc2, "u") {
    Some(i) => i
    None => panic()
  }
  assert_eq(tu.name, "u")
  assert_eq(tu.columns[0].name, "x")
  // External view (Task 3 Test 2): neither registry nor catalog -> None.
  match @analyzer.Catalog::table(vc2, "nope") {
    None => ()
    Some(_) => panic()
  }
}

///|
test "lineage view body edge to view output column" {
  // Task 3 Test 1 (view expansion edge): the CREATE VIEW body's select item
  // derives an edge t.a -> v.a (view-qualified target, D-03).
  let model = t_model([t_item([t_ref(7, 8)], None, 0, 0)])
  let bindings : Array[ABinding] = [t_col_binding("a", "a", 7, 8)]
  let edges : Array[LineageEdge] = []
  let gaps : Array[LineageGap] = []
  run_body(
    Some(model),
    false,
    bindings,
    [],
    false,
    true,
    Some("v"),
    edges,
    gaps,
  )
  assert_eq(edges.length(), 1)
  assert_eq(gaps.length(), 0)
  assert_eq(edges[0].source_name, "a")
  assert_eq(edges[0].source_resolved_to, "a")
  assert_eq(edges[0].source_start_byte, 7)
  assert_eq(edges[0].source_end_byte, 8)
  assert_eq(edges[0].target_name, "v.a")
}

///|
test "lineage external view star without metadata is requires-catalog" {
  // Task 3 Test 2: `SELECT * FROM v` where v is an external view with no
  // metadata (not in the document, not in the catalog) -> the unexpanded star
  // reports a requires-catalog gap and zero edges (SC2).
  let model = t_model([t_star_item(7, 8)])
  let bindings : Array[ABinding] = []
  let edges : Array[LineageEdge] = []
  let gaps : Array[LineageGap] = []
  run_body(Some(model), false, bindings, [], true, false, None, edges, gaps)
  assert_eq(edges.length(), 0)
  assert_eq(gaps.length(), 1)
  assert_eq(gaps[0].code, GAP_REQUIRES_CATALOG)
  assert_eq(gaps[0].start_byte, 7)
  assert_eq(gaps[0].end_byte, 8)
}

///|
test "lineage star over resolved empty-columns table is requires-catalog" {
  // WR-04: `SELECT * FROM t` where catalog t resolves but carries NO column
  // metadata (empty columns array) -> the star expands to zero bindings; even
  // with a body-wide Table binding, the star is a catalog-metadata gap
  // (no except list explains an all-excluded expansion).
  let model = t_model([t_star_item(7, 8)])
  let bindings : Array[ABinding] = [
    {
      kind: @analyzer.BindingKind::Table,
      name: "t",
      resolved_to: "t",
      data_type: "",
      start_byte: 14,
      end_byte: 15,
    },
  ]
  let edges : Array[LineageEdge] = []
  let gaps : Array[LineageGap] = []
  run_body(Some(model), false, bindings, [], true, true, None, edges, gaps)
  assert_eq(edges.length(), 0)
  assert_eq(gaps.length(), 1)
  assert_eq(gaps[0].code, GAP_REQUIRES_CATALOG)
  assert_eq(gaps[0].start_byte, 7)
  assert_eq(gaps[0].end_byte, 8)
}

///|
test "lineage star all-excluded except list is not a catalog gap" {
  // WR-04: `SELECT * EXCEPT (a,b) FROM t` where every column was excluded ->
  // zero Column bindings at the star span, but the except list explains the
  // all-excluded expansion -> NO requires-catalog gap.
  let item : ASelectItem = {
    tokens: [{ bytes: b"*", start_byte: 7, end_byte: 8 }],
    alias: None,
    alias_slice: None,
    star: true,
    star_qualifier: None,
    refs: [],
    except_cols: [
      { bytes: b"a", start_byte: 16, end_byte: 17 },
      { bytes: b"b", start_byte: 19, end_byte: 20 },
    ],
  }
  let model = t_model([item])
  let bindings : Array[ABinding] = [
    {
      kind: @analyzer.BindingKind::Table,
      name: "t",
      resolved_to: "t",
      data_type: "",
      start_byte: 14,
      end_byte: 15,
    },
  ]
  let edges : Array[LineageEdge] = []
  let gaps : Array[LineageGap] = []
  run_body(Some(model), false, bindings, [], true, true, None, edges, gaps)
  assert_eq(edges.length(), 0)
  assert_eq(gaps.length(), 0)
}

///|
test "lineage view column list extraction" {
  // WR-03: `CREATE VIEW v (x, y) AS SELECT a, b FROM t` -> view_column_list
  // returns the explicit output column names [x, y].
  let tokens = t_tokens([
    b"CREATE", b"VIEW", b"v", b"(", b"x", b",", b"y", b")", b"AS", b"SELECT", b"a",
    b",", b"b", b"FROM", b"t",
  ])
  let names = view_column_list(tokens)
  match names {
    Some(list) => {
      assert_eq(list.length(), 2)
      assert_eq(list[0], "x")
      assert_eq(list[1], "y")
    }
    None => assert_true(false)
  }
}

///|
test "lineage INSERT positional mapping with catalog" {
  // Task 3 Test 3: `INSERT INTO t(c1,c2) SELECT a,b FROM u` with a catalog
  // that resolves the source table `u` -> the trailing SELECT output columns
  // map positionally to the column list: u.a->t.c1 and u.b->t.c2
  // (independent empty-scope re-parse, Open Question 4). Edges are only
  // emitted when the source table resolves (CR-01 / SC2).
  let tokens = t_tokens([
    b"INSERT", b"INTO", b"t", b"(", b"c1", b",", b"c2", b")", b"SELECT", b"a", b",",
    b"b", b"FROM", b"u",
  ])
  let catalog = @analyzer.StaticCatalog::new([
    {
      name: "u",
      columns: [
        { name: "a", data_type: "INT" },
        { name: "b", data_type: "INT" },
      ],
    },
  ])
  let (edges, gaps) = derive_insert_body(
    tokens,
    [],
    [],
    false,
    catalog,
    0,
    100,
    false,
  )
  assert_eq(edges.length(), 2)
  assert_eq(gaps.length(), 0)
  assert_eq(edges[0].source_name, "a")
  assert_eq(edges[0].source_resolved_to, "a")
  assert_eq(edges[0].target_name, "t.c1")
  assert_eq(edges[1].source_name, "b")
  assert_eq(edges[1].target_name, "t.c2")
}

///|
test "lineage INSERT source unresolved no fabricated edges" {
  // CR-01 / SC2: `INSERT INTO t(c1,c2) SELECT a,b FROM u` with no catalog ->
  // the source table `u` is unresolved, so NO source edges are fabricated; one
  // honest requires-catalog gap is emitted at the source table-ref span.
  let tokens = t_tokens([
    b"INSERT", b"INTO", b"t", b"(", b"c1", b",", b"c2", b")", b"SELECT", b"a", b",",
    b"b", b"FROM", b"u",
  ])
  let catalog = @analyzer.StaticCatalog::new([])
  let (edges, gaps) = derive_insert_body(
    tokens,
    [],
    [],
    true,
    catalog,
    0,
    100,
    false,
  )
  assert_eq(edges.length(), 0)
  assert_eq(gaps.length(), 1)
  assert_eq(gaps[0].code, GAP_REQUIRES_CATALOG)
  assert_eq(gaps[0].message, "source table not found in catalog: u")
}

///|
test "lineage INSERT without column list no catalog honest gaps" {
  // Task 3 Test 4 + CR-01: `INSERT INTO t SELECT a FROM u` (no column list,
  // no catalog) -> requires-catalog gaps for BOTH the unresolved target table
  // `t` (no column order) and the unresolved source table `u`; the source
  // edge for `a` is suppressed (SC2: never fabricate an edge for unresolved
  // provenance).
  let tokens = t_tokens([
    b"INSERT", b"INTO", b"t", b"SELECT", b"a", b"FROM", b"u",
  ])
  let catalog = @analyzer.StaticCatalog::new([])
  let diagnostics : Array[ADiagnostic] = [
    {
      code: "unknown-table",
      message: "table not found in catalog: t",
      start_byte: 2,
      end_byte: 3,
    },
  ]
  let (edges, gaps) = derive_insert_body(
    tokens,
    [],
    diagnostics,
    true,
    catalog,
    0,
    100,
    false,
  )
  assert_eq(edges.length(), 0)
  assert_eq(gaps.length(), 2)
  let mut found_target = false
  let mut found_source = false
  for gap in gaps {
    assert_eq(gap.code, GAP_REQUIRES_CATALOG)
    if gap.message == "table not found in catalog: t" {
      found_target = true
    }
    if gap.message == "source table not found in catalog: u" {
      found_source = true
    }
  }
  assert_true(found_target)
  assert_true(found_source)
}

///|
test "lineage INSERT VALUES produces no edges" {
  // Task 3 Test 5: `INSERT INTO t(c1) VALUES (1)` -> no edges, no gaps (row
  // literals carry no column references; the column list names targets even
  // without catalog metadata, so the unknown-table gap is suppressed).
  let tokens = t_tokens([
    b"INSERT", b"INTO", b"t", b"(", b"c1", b")", b"VALUES", b"(", b"1", b")",
  ])
  let catalog = @analyzer.StaticCatalog::new([])
  let diagnostics : Array[ADiagnostic] = [
    {
      code: "unknown-table",
      message: "table not found in catalog: t",
      start_byte: 12,
      end_byte: 13,
    },
  ]
  let (edges, gaps) = derive_insert_body(
    tokens,
    [],
    diagnostics,
    true,
    catalog,
    0,
    100,
    false,
  )
  assert_eq(edges.length(), 0)
  assert_eq(gaps.length(), 0)
}
