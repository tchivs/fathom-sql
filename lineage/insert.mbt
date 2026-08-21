/// INSERT positional column mapping (D-04 / Pattern 3).
///
/// `INSERT INTO t(c1,c2) SELECT a,b FROM u` maps the trailing SELECT output
/// column i to the target column-list entry i by position. The trailing body
/// is re-parsed through the public `split_select_model` with an independent
/// empty scope (Open Question 4) — the analyzer's `analyze_dml_body` does not
/// analyze the trailing SELECT, so the source column names come from the
/// re-parsed model refs (source spelling) when no analyzer binding is
/// available at the name_ref span.
///
/// VALUES rows produce no edges (row literals carry no column references); an
/// INSERT without a column list whose target table has no catalog columns
/// produces a single requires-catalog gap at the target-table span via the
/// unknown-table diagnostic mapping (Open Question 3). A trailing `WITH LABEL`
/// prefix is part of the INSERT prefix, not the query body, and is skipped.

///|
/// The INSERT statement's leading-keyword prefix end (mirror of
/// `insert_body_location`'s first half).
fn insert_prefix_end(tokens : Array[(Bytes, Int, Int)]) -> Int {
  let mut prefix = 0
  if prefix < tokens.length() &&
    (
      bytes_equal_ci(tokens[prefix].0, b"INSERT") ||
      bytes_equal_ci(tokens[prefix].0, b"UPSERT")
    ) {
    prefix = prefix + 1
  }
  if prefix < tokens.length() && bytes_equal_ci(tokens[prefix].0, b"OVERWRITE") {
    prefix = prefix + 1
    if prefix < tokens.length() && bytes_equal_ci(tokens[prefix].0, b"TABLE") {
      prefix = prefix + 1
    }
  } else if prefix < tokens.length() &&
    bytes_equal_ci(tokens[prefix].0, b"INTO") {
    prefix = prefix + 1
  }
  prefix
}

///|
/// True when the trailing body begins with a WITH LABEL prefix (part of the
/// INSERT prefix, not the query body).
fn starts_with_label(tokens : Array[(Bytes, Int, Int)]) -> Bool {
  tokens.length() >= 2 &&
  bytes_equal_ci(tokens[0].0, b"WITH") &&
  bytes_equal_ci(tokens[1].0, b"LABEL")
}

///|
/// Strips a WITH LABEL <label> prefix so the remaining tokens are the actual
/// VALUES/SELECT/WITH body.
fn strip_label_prefix(
  tokens : Array[(Bytes, Int, Int)],
) -> Array[(Bytes, Int, Int)] {
  if !starts_with_label(tokens) {
    return tokens
  }
  let mut i = 2
  if i < tokens.length() {
    i = i + 1 // skip the label identifier
  }
  sub_tokens(tokens, i, tokens.length())
}

///|
/// Target column names from an INSERT column-list token range, qualified with
/// the target table name (D-04 positional mapping): `(c1, c2)` -> t.c1, t.c2.
fn col_list_targets(
  target_table : String,
  tokens : Array[(Bytes, Int, Int)],
  start : Int,
  end : Int,
) -> Array[(String, Int, Int)] {
  let out : Array[(String, Int, Int)] = []
  let slices = @analyzer.slice_tokens(tokens, start, end)
  let refs = @analyzer.collect_refs(slices)
  for name_ref in refs {
    if name_ref.parts.length() > 0 {
      let p = name_ref.parts[0]
      out.push(
        (
          target_table + "." + identifier_text(p.bytes),
          p.start_byte,
          p.end_byte,
        ),
      )
    }
  }
  out
}

///|
/// True when a whole token is a quoted identifier (backtick or double quote),
/// mirroring the analyzer's D-03 quoted byte-exact rule.
fn is_quoted(bytes : Bytes) -> Bool {
  bytes.length() > 0 && (bytes[0].to_int() == 96 || bytes[0].to_int() == 34)
}

///|
/// Resolves the target table's column list via the catalog (default-db or
/// db-qualified), or None when the table is absent (D-04 column-order path).
/// Quoted target tables apply the D-03 byte-exact re-check against the
/// returned `TableInfo.name` (WR-02 / Pitfall V1): `INSERT INTO \`T\`` never
/// resolves case-insensitively to a catalog table named `t`.
fn[T : @analyzer.Catalog] resolve_insert_target_columns(
  catalog : T,
  name_ref : @analyzer.NameRef,
) -> Array[@analyzer.ColumnInfo]? {
  let n = name_ref.parts.length()
  if n == 0 {
    return None
  }
  if n == 1 {
    let name = identifier_text(name_ref.parts[0].bytes)
    let quoted = is_quoted(name_ref.parts[0].bytes)
    match @analyzer.Catalog::table(catalog, name) {
      Some(info) =>
        if quoted && info.name != name {
          None
        } else {
          Some(info.columns)
        }
      None => None
    }
  } else {
    let db = identifier_text(name_ref.parts[n - 2].bytes)
    let t = identifier_text(name_ref.parts[n - 1].bytes)
    let table_quoted = is_quoted(name_ref.parts[n - 1].bytes)
    match @analyzer.Catalog::table_in_db(catalog, db, t) {
      Some(info) =>
        if table_quoted && info.name != t {
          None
        } else {
          Some(info.columns)
        }
      None => None
    }
  }
}

///|
/// True when `name` is in the resolved-source set (ASCII case-insensitive).
fn source_resolved(resolved : Array[String], name : String) -> Bool {
  for r in resolved {
    if r.equal_ignore_ascii_case(name) {
      return true
    }
  }
  false
}

///|
/// Resolves one FROM/JOIN table reference of the trailing INSERT source
/// against the catalog. A resolved table is recorded by its last identifier
/// segment; an unresolved table emits exactly one honest gap at the table-name_ref
/// span (requires-catalog when no catalog was injected, unresolved-reference
/// otherwise) so lineage never fabricates a source edge for it (CR-01 / SC2).
fn[T : @analyzer.Catalog] resolve_from_source(
  item : @analyzer.FromItem,
  catalog_none : Bool,
  catalog : T,
  resolved : Array[String],
  gaps : Array[LineageGap],
) -> Unit {
  if item.is_subquery {
    return
  }
  let name_ref = match item.name {
    Some(name_ref) => name_ref
    None => return
  }
  let n = name_ref.parts.length()
  if n == 0 {
    return
  }
  let texts : Array[String] = []
  for p in name_ref.parts {
    texts.push(identifier_text(p.bytes))
  }
  let hit = if n == 1 {
    match @analyzer.Catalog::table(catalog, texts[0]) {
      Some(_) => true
      None => false
    }
  } else {
    match @analyzer.Catalog::table_in_db(catalog, texts[n - 2], texts[n - 1]) {
      Some(_) => true
      None => false
    }
  }
  if hit {
    resolved.push(texts[n - 1])
  } else {
    gaps.push({
      code: if catalog_none {
        GAP_REQUIRES_CATALOG
      } else {
        GAP_UNRESOLVED_REFERENCE
      },
      message: "source table not found in catalog: " + join_strings(texts, "."),
      start_byte: name_ref.start_byte,
      end_byte: name_ref.end_byte,
    })
  }
}

///|
/// Resolves every non-subquery FROM/JOIN table of the trailing SELECT model
/// against the catalog, recording resolved tables and emitting one honest gap
/// per unresolved table (CR-01 / SC2).
fn[T : @analyzer.Catalog] resolve_insert_source_tables(
  model : @analyzer.SelectModel,
  catalog_none : Bool,
  catalog : T,
  gaps : Array[LineageGap],
) -> Array[String] {
  let resolved : Array[String] = []
  for branch in model.branches {
    for item in branch.from {
      resolve_from_source(item, catalog_none, catalog, resolved, gaps)
    }
    for item in branch.joins {
      resolve_from_source(item, catalog_none, catalog, resolved, gaps)
    }
  }
  resolved
}

///|
/// True when at least one non-subquery FROM/JOIN table of the branch resolved
/// (an unqualified source column reference may come from any of them).
fn branch_has_resolved_from(
  branch : @analyzer.SelectCore,
  resolved : Array[String],
) -> Bool {
  for item in branch.from {
    if !item.is_subquery {
      let name_ref = match item.name {
        Some(r) => r
        None => continue
      }
      let n = name_ref.parts.length()
      if n > 0 &&
        source_resolved(resolved, identifier_text(name_ref.parts[n - 1].bytes)) {
        return true
      }
    }
  }
  for item in branch.joins {
    if !item.is_subquery {
      let name_ref = match item.name {
        Some(r) => r
        None => continue
      }
      let n = name_ref.parts.length()
      if n > 0 &&
        source_resolved(resolved, identifier_text(name_ref.parts[n - 1].bytes)) {
        return true
      }
    }
  }
  false
}

///|
/// True when a source reference's table resolved against the catalog.
/// Qualified refs use the table segment (last two parts as db.table, matching
/// the analyzer's two-level model); unqualified refs require at least one
/// resolved FROM/JOIN table in the branch.
fn source_ref_resolved(
  branch : @analyzer.SelectCore,
  name_ref : @analyzer.NameRef,
  resolved : Array[String],
) -> Bool {
  let n = name_ref.parts.length()
  if n >= 2 {
    source_resolved(resolved, identifier_text(name_ref.parts[n - 2].bytes))
  } else {
    branch_has_resolved_from(branch, resolved)
  }
}

///|
/// Positionally maps a trailing INSERT SELECT model's output columns to the
/// INSERT target columns (D-04). Source edges are emitted ONLY for references
/// whose source table resolved against the catalog; references from an
/// unresolved table are suppressed (the table-level gap was already reported
/// by `resolve_insert_source_tables`) so lineage never fabricates an edge for
/// an unresolved provenance (CR-01 / SC2). A trailing star cannot be expanded
/// (the analyzer does not bind the trailing body) and reports an honest
/// requires-catalog gap; after an unexpanded star, positional alignment is
/// unknowable, so no further source edges are mapped in that branch (WR-01).
fn[T : @analyzer.Catalog] derive_insert_source_edges(
  model : @analyzer.SelectModel,
  target_table : String,
  target_table_start : Int,
  target_table_end : Int,
  target_cols : Array[(String, Int, Int)],
  bindings : Array[@analyzer.Binding],
  catalog_none : Bool,
  catalog : T,
  edges : Array[LineageEdge],
  gaps : Array[LineageGap],
) -> Unit {
  let resolved = resolve_insert_source_tables(
    model, catalog_none, catalog, gaps,
  )
  for branch in model.branches {
    let mut pos = 0
    let mut star_seen = false
    for item in branch.select_list {
      if star_seen {
        continue
      }
      if item.star {
        let (ss, se) = star_span(item)
        if column_bindings_at(bindings, ss, se).length() == 0 {
          gaps.push({
            code: GAP_REQUIRES_CATALOG,
            message: "star projection in INSERT source cannot be expanded without catalog column metadata",
            start_byte: ss,
            end_byte: se,
          })
          star_seen = true
        }
      } else {
        for name_ref in item.refs {
          if !source_ref_resolved(branch, name_ref, resolved) {
            continue
          }
          let binding = column_binding_at(
            bindings,
            name_ref.start_byte,
            name_ref.end_byte,
          )
          let source_name = match binding {
            Some(b) => b.name
            None => ref_last_part(name_ref)
          }
          let source_resolved = match binding {
            Some(b) => b.resolved_to
            None => ref_last_part(name_ref)
          }
          let target = if pos < target_cols.length() {
            target_cols[pos]
          } else {
            (target_table, target_table_start, target_table_end)
          }
          edges.push({
            source_name,
            source_resolved_to: source_resolved,
            source_start_byte: name_ref.start_byte,
            source_end_byte: name_ref.end_byte,
            target_name: target.0,
            target_start_byte: target.1,
            target_end_byte: target.2,
          })
        }
        pos = pos + 1
      }
    }
  }
}

///|
/// One INSERT body's lineage contribution (D-04 / Pattern 3).
fn[T : @analyzer.Catalog] derive_insert_body(
  tokens : Array[(Bytes, Int, Int)],
  bindings : Array[@analyzer.Binding],
  diagnostics : Array[@analyzer.AnalysisDiagnostic],
  catalog_none : Bool,
  catalog : T,
  body_start : Int,
  body_end : Int,
  has_error : Bool,
) -> (Array[LineageEdge], Array[LineageGap]) {
  let edges : Array[LineageEdge] = []
  let gaps : Array[LineageGap] = []
  if has_error {
    let message = match
      first_diag_with_code(diagnostics, "requires-complete-parse") {
      Some(d) => d.message
      None =>
        "refusing to derive lineage for a statement with error/missing material"
    }
    gaps.push({
      code: GAP_REQUIRES_COMPLETE_PARSE,
      message,
      start_byte: body_start,
      end_byte: body_end,
    })
    return (edges, gaps)
  }
  let prefix = insert_prefix_end(tokens)
  if prefix >= tokens.length() {
    return (edges, gaps)
  }
  let target_ref = match @analyzer.qualified_ref_at(tokens, prefix) {
    Some((name_ref, _)) => name_ref
    None => return (edges, gaps)
  }
  let target_table = dotted_name(target_ref)
  let target_start = target_ref.start_byte
  let target_end = target_ref.end_byte
  let loc = @analyzer.insert_body_location(tokens)
  let has_col_list = match loc {
    Some((Some(_), _)) => true
    _ => false
  }
  // Target columns: the explicit column list, or the catalog table's columns
  // by position when no list is present (D-04). No list + no catalog columns
  // -> empty; the unknown-table diagnostic mapped below reports
  // requires-catalog at the target-table span (Open Question 3).
  let target_cols : Array[(String, Int, Int)] = match loc {
    Some((Some((cs, ce)), _)) => col_list_targets(target_table, tokens, cs, ce)
    _ =>
      match resolve_insert_target_columns(catalog, target_ref) {
        Some(cols) => {
          let out : Array[(String, Int, Int)] = []
          for col in cols {
            out.push((target_table + "." + col.name, target_start, target_end))
          }
          out
        }
        None => []
      }
  }
  match loc {
    Some((_, body_start_idx)) =>
      if body_start_idx < tokens.length() {
        let body_tokens = strip_label_prefix(
          sub_tokens(tokens, body_start_idx, tokens.length()),
        )
        if body_tokens.length() > 0 &&
          bytes_equal_ci(body_tokens[0].0, b"VALUES") {
          // VALUES rows carry no column references -> no edges.
        } else {
          match @analyzer.split_select_model(body_tokens) {
            Some(model) =>
              derive_insert_source_edges(
                model, target_table, target_start, target_end, target_cols, bindings,
                catalog_none, catalog, edges, gaps,
              )
            None =>
              gaps.push({
                code: GAP_REQUIRES_COMPLETE_PARSE,
                message: "INSERT source body could not be re-parsed",
                start_byte: body_start,
                end_byte: body_end,
              })
          }
        }
      }
    None => ()
  }
  // Diagnostic mapping for the INSERT body: an unknown target table produces
  // requires-catalog only when there is NO column list — a column list names
  // the targets without catalog metadata, so no gap is needed (Task 3 Test 5).
  let mapped = map_diagnostic_gaps(diagnostics, catalog_none, has_col_list)
  for gap in mapped {
    gaps.push(gap)
  }
  (edges, gaps)
}
