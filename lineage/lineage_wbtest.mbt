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
type ACteDef = @analyzer.CteDef
type ADiagnostic = @analyzer.AnalysisDiagnostic
type ANameRef = @analyzer.NameRef
type ASelectItem = @analyzer.SelectItem
type ASelectCore = @analyzer.SelectCore
type ASelectModel = @analyzer.SelectModel
type ATokenSlice = @analyzer.TokenSlice

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

/// A SelectItem with the given refs, alias, and alias slice span.
fn t_item(
  refs : Array[ANameRef],
  alias : String?,
  alias_start : Int,
  alias_end : Int,
) -> ASelectItem {
  let alias_slice : ATokenSlice? = match alias {
    Some(_) => Some({ bytes: b"x", start_byte: alias_start, end_byte: alias_end })
    None => None
  }
  {
    tokens: [],
    alias: alias,
    alias_slice: alias_slice,
    star: false,
    star_qualifier: None,
    refs: refs,
    except_cols: [],
  }
}

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

/// A single-core SelectModel with one branch.
fn t_model(select_list : Array[ASelectItem]) -> ASelectModel {
  {
    ctes: [],
    branches: [{ select_list: select_list, from: [], joins: [], where_refs: [], group_by: [], having: [], qualify: [], order_by: [], limit: [], window: [], set_op: None }],
  }
}

/// A Column binding at `[start, end)`.
fn t_col_binding(name : String, resolved : String, start : Int, end : Int) -> ABinding {
  {
    kind: @analyzer.BindingKind::Column,
    name: name,
    resolved_to: resolved,
    data_type: "INT",
    start_byte: start,
    end_byte: end,
  }
}

/// A Function binding at `[start, end)`.
fn t_fn_binding(name : String, start : Int, end : Int) -> ABinding {
  {
    kind: @analyzer.BindingKind::Function,
    name: name,
    resolved_to: name,
    data_type: "INT",
    start_byte: start,
    end_byte: end,
  }
}

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
    model,
    has_error,
    0,
    100,
    bindings,
    diagnostics,
    catalog_none,
    body_has_table_binding,
    qualifier,
  )
  for edge in e {
    out_edges.push(edge)
  }
  for gap in g {
    out_gaps.push(gap)
  }
}

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

test "lineage D-01 single ref and function argument" {
  // Test 2a: `SELECT a AS x` -> 1 edge t.a->x.
  let item_a = t_item([t_ref(7, 8)], Some("x"), 15, 16)
  let model_a = t_model([item_a])
  let bindings_a : Array[ABinding] = [t_col_binding("a", "a", 7, 8)]
  let edges_a : Array[LineageEdge] = []
  let gaps_a : Array[LineageGap] = []
  run_body(Some(model_a), false, bindings_a, [], false, true, None, edges_a, gaps_a)
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
  run_body(Some(model_u), false, bindings_u, [], false, true, None, edges_u, gaps_u)
  assert_eq(edges_u.length(), 1)
  assert_eq(edges_u[0].source_name, "c")
  assert_eq(edges_u[0].source_resolved_to, "c")
  assert_eq(edges_u[0].source_start_byte, 13)
  assert_eq(edges_u[0].source_end_byte, 14)
  assert_eq(edges_u[0].target_name, "u")
}

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
  run_body(Some(union_model), false, union_bindings, [], false, true, None, union_edges, union_gaps)
  assert_eq(union_edges.length(), 2)
  assert_eq(union_edges[0].target_name, "a")
  assert_eq(union_edges[1].target_name, "a")
  assert_eq(union_edges[1].source_name, "b")
  assert_eq(union_edges[1].source_start_byte, 15)
  assert_eq(union_edges[1].source_end_byte, 16)
}

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
