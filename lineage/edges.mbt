/// Edge derivation for column lineage (LINE-01, D-01 expression passthrough).
///
/// The public entry `derive_lineage` walks a parsed document's statements,
/// re-parses each SELECT-family body via the analyzer's public
/// `split_select_model`, associates the analyzer's resolved Column bindings to
/// model NameRefs by flattened byte span (D-02), and emits one edge per
/// resolved column reference to its output column. It never re-implements
/// name resolution (Pitfall: reuse analyze bindings + split_select_model).
///
/// Ordering contract (Pattern 6): document statement order -> SelectModel
/// branch/CTE order -> SelectItem order -> refs order; star expansion follows
/// scope-entry order x catalog column order. Deterministic across targets.

/// UTF-8 decode of a byte slice into a String (lossy: malformed bytes become
/// U+FFFD). Local decoder keeps this package's D-21 import list to
/// analyzer + syntax only (mirrors analyzer/analyzer.mbt utf8_to_string).
fn utf8_to_string(bytes : Bytes) -> String {
  let chars : Array[Char] = []
  let len = bytes.length()
  let mut i = 0
  while i < len {
    let first = bytes[i].to_int()
    if first < 0x80 {
      chars.push(Char::from_int(first))
      i = i + 1
    } else if first >= 0xC2 && first < 0xE0 && i + 1 < len {
      let second = bytes[i + 1].to_int()
      chars.push(Char::from_int(((first & 0x1F) << 6) | (second & 0x3F)))
      i = i + 2
    } else if first >= 0xE0 && first < 0xF0 && i + 2 < len {
      let second = bytes[i + 1].to_int()
      let third = bytes[i + 2].to_int()
      chars.push(Char::from_int(((first & 0x0F) << 12) | ((second & 0x3F) << 6) | (third & 0x3F)))
      i = i + 3
    } else if first >= 0xF0 && first < 0xF8 && i + 3 < len {
      let second = bytes[i + 1].to_int()
      let third = bytes[i + 2].to_int()
      let fourth = bytes[i + 3].to_int()
      chars.push(
        Char::from_int(((first & 0x07) << 18) | ((second & 0x3F) << 12) | ((third & 0x3F) << 6) | (fourth & 0x3F)),
      )
      i = i + 4
    } else {
      chars.push(Char::from_int(0xFFFD))
      i = i + 1
    }
  }
  String::from_iter(chars.iter())
}

/// Identifier text for resolution: quoted identifiers (backtick/`"`) return
/// the inner text; unquoted identifiers return the whole text (D-03).
fn identifier_text(bytes : Bytes) -> String {
  let len = bytes.length()
  if len >= 2 &&
    (bytes[0].to_int() == 96 || bytes[0].to_int() == 34) &&
    (bytes[len - 1].to_int() == 96 || bytes[len - 1].to_int() == 34) {
    utf8_to_string(bytes[1:len - 1].to_owned())
  } else {
    utf8_to_string(bytes)
  }
}

/// ASCII case-insensitive byte compare (mirror of parser/analyzer helpers).
fn bytes_equal_ci(actual : Bytes, expected : Bytes) -> Bool {
  if actual.length() != expected.length() {
    false
  } else {
    let mut index = 0
    let mut equal = true
    while index < actual.length() {
      let left = actual[index].to_int()
      let right = expected[index].to_int()
      let folded_left = if left >= 97 && left <= 122 { left - 32 } else { left }
      let folded_right = if right >= 97 && right <= 122 { right - 32 } else { right }
      if folded_left != folded_right {
        equal = false
      }
      index = index + 1
    }
    equal
  }
}

/// Joins an array of strings with a separator.
fn join_strings(parts : Array[String], sep : String) -> String {
  let mut out = ""
  let mut first = true
  for part in parts {
    if first {
      out = out + part
      first = false
    } else {
      out = out + sep + part
    }
  }
  out
}

/// Dotted display name of a NameRef (identifier segments joined by `.`).
fn dotted_name(ref : @analyzer.NameRef) -> String {
  let parts : Array[String] = []
  for p in ref.parts {
    parts.push(identifier_text(p.bytes))
  }
  join_strings(parts, ".")
}

/// Last identifier segment of a NameRef (the column name for `t.c`).
fn ref_last_part(ref : @analyzer.NameRef) -> String {
  let n = ref.parts.length()
  if n == 0 {
    ""
  } else {
    identifier_text(ref.parts[n - 1].bytes)
  }
}

/// The first Column-kind binding at the exact span, or None. A regular NameRef
/// span is unique per token run; star expansion emits one binding per column
/// sharing the star span (see `column_bindings_at`).
fn column_binding_at(
  bindings : Array[@analyzer.Binding],
  start : Int,
  end : Int,
) -> @analyzer.Binding? {
  for binding in bindings {
    if binding.kind is @analyzer.BindingKind::Column &&
      binding.start_byte == start && binding.end_byte == end {
      return Some(binding)
    }
  }
  None
}

/// All Column-kind bindings at the exact span (star expansion: one per
/// expanded column, all sharing the star span).
fn column_bindings_at(
  bindings : Array[@analyzer.Binding],
  start : Int,
  end : Int,
) -> Array[@analyzer.Binding] {
  let out : Array[@analyzer.Binding] = []
  for binding in bindings {
    if binding.kind is @analyzer.BindingKind::Column &&
      binding.start_byte == start && binding.end_byte == end {
      out.push(binding)
    }
  }
  out
}

/// True when any Table-kind binding falls within `[start, end)` — the signal
/// that a star in the same body has a resolvable table (so a zero-column star
/// is an all-excluded/empty expansion, not a catalog miss).
fn has_table_binding_in(bindings : Array[@analyzer.Binding], start : Int, end : Int) -> Bool {
  for binding in bindings {
    if binding.kind is @analyzer.BindingKind::Table &&
      binding.start_byte >= start && binding.end_byte <= end {
      return true
    }
  }
  false
}

/// Diagnostics whose span falls within `[start, end)`.
fn diagnostics_in(
  diagnostics : Array[@analyzer.AnalysisDiagnostic],
  start : Int,
  end : Int,
) -> Array[@analyzer.AnalysisDiagnostic] {
  let out : Array[@analyzer.AnalysisDiagnostic] = []
  for d in diagnostics {
    if d.start_byte >= start && d.end_byte <= end {
      out.push(d)
    }
  }
  out
}

/// Token sub-range `[start, end)` (loop-based to avoid a core slice API).
fn sub_tokens(
  tokens : Array[(Bytes, Int, Int)],
  start : Int,
  end : Int,
) -> Array[(Bytes, Int, Int)] {
  let out : Array[(Bytes, Int, Int)] = []
  let mut i = start
  while i < end && i < tokens.length() {
    out.push(tokens[i])
    i = i + 1
  }
  out
}

/// The star token span of a star SelectItem (the last token of the item's
/// token list — the `*`, or the trailing `*` of `t.*`/`db.t.*`).
fn star_span(item : @analyzer.SelectItem) -> (Int, Int) {
  let n = item.tokens.length()
  if n == 0 {
    (0, 0)
  } else {
    (item.tokens[n - 1].start_byte, item.tokens[n - 1].end_byte)
  }
}

/// The first resolved Column binding among an item's refs (the analyzer's
/// `resolved_refs[0]` equivalent), or None.
fn first_resolved_column(
  item : @analyzer.SelectItem,
  bindings : Array[@analyzer.Binding],
) -> (String, Int, Int)? {
  for ref in item.refs {
    match column_binding_at(bindings, ref.start_byte, ref.end_byte) {
      Some(binding) => return Some((binding.resolved_to, ref.start_byte, ref.end_byte))
      None => ()
    }
  }
  None
}

/// The output column (name, start, end) of one non-star SelectItem, matching
/// the analyzer's own output-column derivation (Pattern 1 / A4): alias ->
/// alias slice; single ref -> resolved column (ref span); multi-ref -> first
/// resolved ref with the item expression span; no resolved column -> first
/// ref's last part (source spelling).
fn item_target(
  item : @analyzer.SelectItem,
  bindings : Array[@analyzer.Binding],
) -> (String, Int, Int) {
  match item.alias {
    Some(alias) => {
      match item.alias_slice {
        Some(slice) => (alias, slice.start_byte, slice.end_byte)
        None => (alias, 0, 0)
      }
    }
    None => {
      if item.star {
        let (s, e) = star_span(item)
        ("", s, e)
      } else {
        match first_resolved_column(item, bindings) {
          Some((name, s, e)) => {
            if item.refs.length() == 1 {
              (name, s, e)
            } else {
              let start = if item.tokens.length() > 0 {
                item.tokens[0].start_byte
              } else {
                s
              }
              let end = if item.tokens.length() > 0 {
                item.tokens[item.tokens.length() - 1].end_byte
              } else {
                e
              }
              (name, start, end)
            }
          }
          None => {
            if item.refs.length() > 0 {
              let ref = item.refs[0]
              (ref_last_part(ref), ref.start_byte, ref.end_byte)
            } else {
              ("", 0, 0)
            }
          }
        }
      }
    }
  }
}

/// Number of output columns one SelectItem produces (star items produce one
/// per expanded column binding at the star span).
fn output_count(item : @analyzer.SelectItem, bindings : Array[@analyzer.Binding]) -> Int {
  if item.star {
    let (s, e) = star_span(item)
    column_bindings_at(bindings, s, e).length()
  } else {
    1
  }
}

/// Output column NAMES of one SELECT core (star items expand to one name per
/// expanded column). Used as the positional map for UNION branches.
fn output_names(
  core : @analyzer.SelectCore,
  bindings : Array[@analyzer.Binding],
) -> Array[String] {
  let names : Array[String] = []
  for item in core.select_list {
    if item.star {
      let (s, e) = star_span(item)
      for col in column_bindings_at(bindings, s, e) {
        names.push(col.resolved_to)
      }
    } else {
      let (name, _, _) = item_target(item, bindings)
      names.push(name)
    }
  }
  names
}

/// Qualifies an output column name with a nested-body qualifier (CTE name,
/// view name, or subquery alias): `c.a` / `v.a` / `s.a`. None returns the
/// plain name.
fn qualify(name : String, qualifier : String?) -> String {
  match qualifier {
    Some(q) => q + "." + name
    None => name
  }
}

/// Derives edges + star gaps for one SELECT-list item at flat position `pos`
/// (UNION positional mapping via `union_names`). Returns whether an
/// unexpanded-star requires-catalog gap was emitted.
fn derive_item(
  item : @analyzer.SelectItem,
  bindings : Array[@analyzer.Binding],
  qualifier : String?,
  union_names : Array[String],
  body_has_table_binding : Bool,
  pos : Int,
  out_edges : Array[LineageEdge],
  out_gaps : Array[LineageGap],
) -> Bool {
  if item.star {
    let (ss, se) = star_span(item)
    let cols = column_bindings_at(bindings, ss, se)
    if cols.length() == 0 {
      // Star self-check (SC2 / D-06): expand_star silently yields zero
      // columns without catalog column metadata (resolve.mbt expand_star) —
      // lineage must detect it and report an honest requires-catalog gap.
      // The only legitimate zero-column expansion is a `* EXCEPT (...)`
      // projection that deliberately excluded every column of a resolved
      // table (WR-04); a table resolved with an empty column array, or a
      // star over an unresolvable table inside a body where another table
      // resolved, is still a catalog-metadata gap.
      if !(item.except_cols.length() > 0 && body_has_table_binding) {
        out_gaps.push({
          code: GAP_REQUIRES_CATALOG,
          message: "star projection cannot be expanded without catalog column metadata",
          start_byte: ss,
          end_byte: se,
        })
        return true
      }
      return false
    }
    let mut idx = 0
    for col in cols {
      let name = if pos + idx < union_names.length() {
        union_names[pos + idx]
      } else {
        col.resolved_to
      }
      out_edges.push({
        source_name: col.name,
        source_resolved_to: col.resolved_to,
        source_start_byte: col.start_byte,
        source_end_byte: col.end_byte,
        target_name: qualify(name, qualifier),
        target_start_byte: ss,
        target_end_byte: se,
      })
      idx = idx + 1
    }
    false
  } else {
    let (own_name, ts, te) = item_target(item, bindings)
    let target_name = if pos < union_names.length() {
      union_names[pos]
    } else {
      own_name
    }
    let final_name = qualify(target_name, qualifier)
    // D-01 expression passthrough: every resolved column reference in the
    // output-column expression contributes one edge to that output column.
    for ref in item.refs {
      match column_binding_at(bindings, ref.start_byte, ref.end_byte) {
        Some(binding) => {
          out_edges.push({
            source_name: binding.name,
            source_resolved_to: binding.resolved_to,
            source_start_byte: binding.start_byte,
            source_end_byte: binding.end_byte,
            target_name: final_name,
            target_start_byte: ts,
            target_end_byte: te,
          })
        }
        None => ()
      }
    }
    false
  }
}

/// Derives edges + star gaps for one SELECT core (subquery bodies first, then
/// select-list items). Returns whether any unexpanded-star gap fired.
fn derive_core(
  core : @analyzer.SelectCore,
  bindings : Array[@analyzer.Binding],
  catalog_none : Bool,
  qualifier : String?,
  union_names : Array[String],
  body_has_table_binding : Bool,
  out_edges : Array[LineageEdge],
  out_gaps : Array[LineageGap],
) -> Bool {
  let mut star_fired = false
  for item in core.from {
    if item.is_subquery {
      match item.subquery {
        Some(model) => {
          if derive_model(
            model,
            bindings,
            catalog_none,
            item.alias,
            body_has_table_binding,
            out_edges,
            out_gaps,
          ) {
            star_fired = true
          }
        }
        None => ()
      }
    }
  }
  for item in core.joins {
    if item.is_subquery {
      match item.subquery {
        Some(model) => {
          if derive_model(
            model,
            bindings,
            catalog_none,
            item.alias,
            body_has_table_binding,
            out_edges,
            out_gaps,
          ) {
            star_fired = true
          }
        }
        None => ()
      }
    }
  }
  let mut pos = 0
  for item in core.select_list {
    if derive_item(item, bindings, qualifier, union_names, body_has_table_binding, pos, out_edges, out_gaps) {
      star_fired = true
    }
    pos = pos + output_count(item, bindings)
  }
  star_fired
}

/// Derives edges + star gaps for a full SELECT model: CTE bodies first (each
/// qualified by its CTE name), then UNION branches positionally mapped to the
/// first branch's output column names (D-04). Returns whether any
/// unexpanded-star gap fired.
fn derive_model(
  model : @analyzer.SelectModel,
  bindings : Array[@analyzer.Binding],
  catalog_none : Bool,
  qualifier : String?,
  body_has_table_binding : Bool,
  out_edges : Array[LineageEdge],
  out_gaps : Array[LineageGap],
) -> Bool {
  let mut star_fired = false
  for cte in model.ctes {
    let names = output_names(cte.body, bindings)
    if derive_core(
      cte.body,
      bindings,
      catalog_none,
      Some(cte.name),
      names,
      body_has_table_binding,
      out_edges,
      out_gaps,
    ) {
      star_fired = true
    }
  }
  let union_names = if model.branches.length() > 0 {
    output_names(model.branches[0], bindings)
  } else {
    []
  }
  for branch in model.branches {
    if derive_core(
      branch,
      bindings,
      catalog_none,
      qualifier,
      union_names,
      body_has_table_binding,
      out_edges,
      out_gaps,
    ) {
      star_fired = true
    }
  }
  star_fired
}

/// The first diagnostic with the given code, or None.
fn first_diag_with_code(
  diagnostics : Array[@analyzer.AnalysisDiagnostic],
  code : String,
) -> @analyzer.AnalysisDiagnostic? {
  for d in diagnostics {
    if d.code == code {
      return Some(d)
    }
  }
  None
}

/// One SELECT-family body's lineage contribution (shared by top-level SELECT
/// bodies and CREATE VIEW query bodies — the latter pass the view name as
/// `qualifier`). `model` is None when the body re-parse failed (a
/// requires-complete-parse diagnostic is then expected from the analyzer).
fn derive_select_body(
  model : @analyzer.SelectModel?,
  has_error : Bool,
  body_start : Int,
  body_end : Int,
  bindings : Array[@analyzer.Binding],
  diagnostics : Array[@analyzer.AnalysisDiagnostic],
  catalog_none : Bool,
  body_has_table_binding : Bool,
  qualifier : String?,
) -> (Array[LineageEdge], Array[LineageGap]) {
  let edges : Array[LineageEdge] = []
  let gaps : Array[LineageGap] = []
  if has_error {
    let message = match first_diag_with_code(diagnostics, "requires-complete-parse") {
      Some(d) => d.message
      None => "refusing to derive lineage for a statement with error/missing material"
    }
    gaps.push({
      code: GAP_REQUIRES_COMPLETE_PARSE,
      message: message,
      start_byte: body_start,
      end_byte: body_end,
    })
    return (edges, gaps)
  }
  // Star self-check gaps are emitted inside derive_model (returns whether an
  // unexpanded-star requires-catalog gap fired, used to suppress redundant
  // unknown-table -> requires-catalog gaps in the same body — gaps.mbt).
  let mut star_fired = false
  match model {
    Some(m) => {
      if derive_model(m, bindings, catalog_none, qualifier, body_has_table_binding, edges, gaps) {
        star_fired = true
      }
    }
    None => ()
  }
  let mapped = map_diagnostic_gaps(diagnostics, catalog_none, star_fired)
  for gap in mapped {
    gaps.push(gap)
  }
  (edges, gaps)
}

/// Appends edge/gap batches to the accumulators.
fn append_edges_gaps(
  edges : Array[LineageEdge],
  gaps : Array[LineageGap],
  e : Array[LineageEdge],
  g : Array[LineageGap],
) -> Unit {
  for edge in e {
    edges.push(edge)
  }
  for gap in g {
    gaps.push(gap)
  }
}

/// Walks one parsed document's statement bodies and derives lineage edges +
/// gaps: SELECT bodies, CREATE VIEW bodies (edges into the view's output
/// columns), and INSERT bodies (D-04 positional mapping).
fn[T : @analyzer.Catalog] derive_lineage_inner(
  root : @syntax.SyntaxNode,
  source_bytes : Bytes,
  catalog : T,
  catalog_none : Bool,
) -> LineageResult {
  // Pass 1: analyze with the inner catalog so stars inside CREATE VIEW bodies
  // expand over base tables, feeding the view registry (D-03).
  let analysis_inner = @analyzer.analyze(root, source_bytes, catalog)
  let registry = build_view_registry(root, source_bytes, analysis_inner.bindings)
  let view_catalog = ViewCatalog::{ views: registry, inner: catalog }
  // Pass 2: analyze with the view catalog so `FROM v` resolves to view columns.
  let analysis = @analyzer.analyze(root, source_bytes, view_catalog)
  let edges : Array[LineageEdge] = []
  let gaps : Array[LineageGap] = []
  for element in root.children() {
    match element {
      @syntax.SyntaxElement::ChildNode(statement_node) => {
        if statement_node.kind() is @syntax.SyntaxKind::Statement {
          for inner in statement_node.children() {
            match inner {
              @syntax.SyntaxElement::ChildNode(body) => {
                let body_start = body.span().start_byte
                let body_end = body.span().end_byte
                let body_diagnostics = diagnostics_in(analysis.diagnostics, body_start, body_end)
                let body_has_table_binding = has_table_binding_in(analysis.bindings, body_start, body_end)
                let has_error = body.is_error() || body.is_missing() || @analyzer.has_error_missing(body)
                match body.kind() {
                  @syntax.SyntaxKind::Select => {
                    let tokens = @analyzer.source_tokens(body, source_bytes)
                    let model = @analyzer.split_select_model(tokens)
                    let (e, g) = derive_select_body(
                      model,
                      has_error,
                      body_start,
                      body_end,
                      analysis.bindings,
                      body_diagnostics,
                      catalog_none,
                      body_has_table_binding,
                      None,
                    )
                    append_edges_gaps(edges, gaps, e, g)
                  }
                  @syntax.SyntaxKind::CreateView => {
                    if has_error {
                      let (e, g) = derive_select_body(
                        None,
                        true,
                        body_start,
                        body_end,
                        analysis.bindings,
                        body_diagnostics,
                        catalog_none,
                        body_has_table_binding,
                        None,
                      )
                      append_edges_gaps(edges, gaps, e, g)
                    } else {
                      let tokens = @analyzer.source_tokens(body, source_bytes)
                      let name = view_name(tokens)
                      let query_start = @analyzer.view_body_location(tokens)
                      let body_tokens = sub_tokens(tokens, query_start, tokens.length())
                      let model = @analyzer.split_select_model(body_tokens)
                      let (e, g) = derive_select_body(
                        model,
                        false,
                        body_start,
                        body_end,
                        analysis.bindings,
                        body_diagnostics,
                        catalog_none,
                        body_has_table_binding,
                        name,
                      )
                      append_edges_gaps(edges, gaps, e, g)
                    }
                  }
                  @syntax.SyntaxKind::Insert => {
                    let tokens = @analyzer.source_tokens(body, source_bytes)
                    let (e, g) = derive_insert_body(
                      tokens,
                      analysis.bindings,
                      body_diagnostics,
                      catalog_none,
                      view_catalog,
                      body_start,
                      body_end,
                      has_error,
                    )
                    append_edges_gaps(edges, gaps, e, g)
                  }
                  _ => ()
                }
              }
              @syntax.SyntaxElement::Leaf(_) => ()
            }
          }
        }
      }
      @syntax.SyntaxElement::Leaf(_) => ()
    }
  }
  { edges: edges, gaps: gaps }
}

/// Derives column lineage for a parsed document (LINE-01).
///
/// - `root`: the parsed document root (`@syntax.SyntaxNode`).
/// - `source_bytes`: the original source bytes (spans are byte offsets into
///   this buffer).
/// - `catalog`: caller-injected catalog metadata (T-02-42). To derive without
///   any metadata (every star/`table.*` and every external view reports a
///   `requires-catalog` gap), use `derive_lineage_without_catalog`.
///
/// Pure function: same input yields byte-identical edges/gaps; the catalog
/// and CST are never mutated.
pub fn[T : @analyzer.Catalog] derive_lineage(
  root : @syntax.SyntaxNode,
  source_bytes : Bytes,
  catalog : T,
) -> LineageResult {
  derive_lineage_inner(root, source_bytes, catalog, false)
}

/// Derives column lineage with no catalog metadata: every star/`table.*`
/// projection and every external view reports a `requires-catalog` gap —
/// lineage never fabricates edges (SC2 / D-05).
///
/// NOTE: `moon 0.1.20260724` does not support trait objects (a trait cannot
/// be used as a type), so the plan's `catalog : @analyzer.Catalog?` optional
/// parameter cannot be spelled on this toolchain. `derive_lineage` is generic
/// over the catalog (mirroring `@analyzer.analyze`); the no-catalog case is
/// this dedicated entry, which passes an empty catalog and the no-catalog
/// flag so unknown tables map to `requires-catalog` gaps (deviation, Rule 3).
pub fn derive_lineage_without_catalog(
  root : @syntax.SyntaxNode,
  source_bytes : Bytes,
) -> LineageResult {
  derive_lineage_inner(root, source_bytes, @analyzer.StaticCatalog::new([]), true)
}
