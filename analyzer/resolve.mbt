/// Name resolution for SELECT bodies over the flat token-leaf CST (D-01).
///
/// `analyze` walks a parsed document's Statement children, re-parses each
/// SELECT body via select_parser.mbt into a `SelectModel`, and resolves
/// table/column/CTE/alias/function references against the injected catalog
/// with a scope stack (D-02/D-04/D-05):
/// - Entering a CTE body or subquery pushes a fresh scope frame; leaving pops
///   it (Pitfall 4). CTE names are visible and take precedence over catalog
///   tables; same-name entries resolve inner-first.
/// - Table aliases take precedence over catalog table names; qualified names
///   resolve their first segment as alias → table (default db) → db
///   (Pitfall 3), so `db.table.col` (3 parts), `alias.col`/`db.table`
///   (2 parts) and `col`/`table` (1 part) all resolve.
/// - `*`/`table.*` star expansion happens only over already-resolved
///   tables/aliases (D-05); unresolved tables emit unknown-table diagnostics.
/// - Matching is parsing-time ASCII case-fold (D-03); quoted identifiers go
///   through the same case-fold Catalog path and then a byte-exact re-check of
///   the returned TableInfo.name — StaticCatalog::lookup_exact is never called
///   here (it is not a Catalog trait method). Bindings always preserve source
///   spelling plus flattened start_byte/end_byte spans.
///
/// Catalog metadata is untrusted and only consumed (T-02-42); the syntax-only
/// valid/diagnostic channel is never touched (ANLY-01).

/// Scope frame kinds for name resolution.
enum ScopeKind {
  Table
  Cte
  Subquery
} derive(Eq)

/// One visible name in the current scope: the lookup key (alias if present,
/// else the table/CTE name as spelled), the effective columns, and display
/// metadata for bindings.
struct ScopeEntry {
  key : String
  kind : ScopeKind
  columns : Array[ColumnInfo]
  display : String
  is_quoted : Bool
}

/// Identifier text for resolution: quoted identifiers (backtick/`"`) return
/// the inner text; unquoted identifiers return the whole text. Case is
/// preserved (D-03).
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

/// True when a whole token is a quoted identifier (backtick or double quote).
fn is_quoted(bytes : Bytes) -> Bool {
  bytes.length() > 0 && (bytes[0].to_int() == 96 || bytes[0].to_int() == 34)
}

/// True when the subtree contains Error/Missing material (Pitfall 7): mirrors
/// the formatter's first_unsafe_element scan (D-33 refusal philosophy).
fn has_error_missing(node : @syntax.SyntaxNode) -> Bool {
  if node.kind() is @syntax.SyntaxKind::Error || node.kind() is @syntax.SyntaxKind::Missing {
    return true
  }
  for element in node.children() {
    match element {
      @syntax.SyntaxElement::ChildNode(child) => {
        if has_error_missing(child) {
          return true
        }
      }
      @syntax.SyntaxElement::Leaf(leaf) => {
        if leaf.kind is @syntax.LeafKind::SourceError || leaf.kind is @syntax.LeafKind::SourceSkipped {
          return true
        }
      }
    }
  }
  false
}

/// Column lookup within a column list. Quoted references match byte-exactly
/// (D-03); unquoted references fold ASCII case.
fn find_column_in(columns : Array[ColumnInfo], name : String, quoted : Bool) -> ColumnInfo? {
  for col in columns {
    if quoted {
      if col.name == name {
        return Some(col)
      }
    } else {
      if col.name.equal_ignore_ascii_case(name) {
        return Some(col)
      }
    }
  }
  None
}

/// Scope lookup by key, innermost first. Quoted keys match exactly; unquoted
/// keys fold ASCII case. Anonymous subquery entries (empty key) are skipped
/// for qualified lookup.
fn find_scope_entry(scope : Array[ScopeEntry], key : String, quoted : Bool) -> ScopeEntry? {
  let mut i = scope.length()
  while i > 0 {
    let entry = scope[i - 1]
    if quoted {
      if entry.key == key {
        return Some(entry)
      }
    } else {
      if entry.key != "" && entry.key.equal_ignore_ascii_case(key) {
        return Some(entry)
      }
    }
    i = i - 1
  }
  None
}

/// Scope lookup restricted to one frame kind (used for CTE precedence over
/// catalog tables — Pitfall 4), innermost first.
fn find_scope_entry_kind(
  scope : Array[ScopeEntry],
  key : String,
  quoted : Bool,
  kind : ScopeKind,
) -> ScopeEntry? {
  let mut i = scope.length()
  while i > 0 {
    let entry = scope[i - 1]
    if entry.kind == kind {
      let hit = if quoted {
        entry.key == key
      } else {
        entry.key != "" && entry.key.equal_ignore_ascii_case(key)
      }
      if hit {
        return Some(entry)
      }
    }
    i = i - 1
  }
  None
}

/// Resolves a plain (default-db) table with D-03 quoted re-check.
fn[T : Catalog] resolve_table_with_quoted(
  catalog : T,
  name_text : String,
  quoted : Bool,
) -> TableInfo? {
  match Catalog::table(catalog, name_text) {
    Some(info) =>
      if quoted {
        if info.name == name_text {
          Some(info)
        } else {
          None
        }
      } else {
        Some(info)
      }
    None => None
  }
}

/// Resolves a table name reference (1..3 dotted parts) against the catalog.
/// Returns (info, quoted) where `quoted` is whether the trailing table part
/// was quoted. 2+ parts use `table_in_db` (D-05); the trailing table part is
/// byte-re-checked when quoted (D-03).
fn[T : Catalog] resolve_table_name_ref(
  ref : NameRef,
  catalog : T,
) -> (TableInfo, Bool)? {
  let parts = ref.parts
  let n = parts.length()
  if n == 0 {
    return None
  }
  let texts : Array[String] = []
  for p in parts {
    texts.push(identifier_text(p.bytes))
  }
  if n == 1 {
    let quoted = is_quoted(parts[0].bytes)
    match resolve_table_with_quoted(catalog, texts[0], quoted) {
      Some(info) => Some((info, quoted))
      None => None
    }
  } else {
    // 2+ parts: db.table (or catalog.db.table — the analyzer's two-level
    // model uses the last two parts as db.table).
    let db_text = texts[n - 2]
    let table_text = texts[n - 1]
    let table_quoted = is_quoted(parts[n - 1].bytes)
    match Catalog::table_in_db(catalog, db_text, table_text) {
      Some(info) => {
        if table_quoted && info.name != table_text {
          None
        } else {
          Some((info, table_quoted))
        }
      }
      None => None
    }
  }
}

/// Resolves a scope entry from a FROM item: catalog tables (with alias
/// precedence), CTE references, and subquery aliases. Appends bindings and
/// scope entries; emits unknown-table diagnostics for unresolved names.
fn[T : Catalog] resolve_from_item(
  item : FromItem,
  catalog : T,
  scope : Array[ScopeEntry],
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
) -> Unit {
  if item.is_subquery {
    let model = match item.subquery {
      Some(model) => model
      None => return
    }
    let columns = resolve_model(model, catalog, scope, bindings, diagnostics)
    match item.alias {
      Some(alias) => {
        let start = match item.alias_slice { Some(s) => s.start_byte; None => 0 }
        let end = match item.alias_slice { Some(s) => s.end_byte; None => 0 }
        bindings.push({
          kind: BindingKind::Alias,
          name: alias,
          resolved_to: alias,
          data_type: "",
          start_byte: start,
          end_byte: end,
        })
        scope.push({
          key: alias,
          kind: ScopeKind::Subquery,
          columns: columns,
          display: alias,
          is_quoted: false,
        })
      }
      None => {
        // Anonymous subquery: columns visible for unqualified refs only.
        scope.push({
          key: "",
          kind: ScopeKind::Subquery,
          columns: columns,
          display: "",
          is_quoted: false,
        })
      }
    }
    return
  }
  let name_ref = match item.name {
    Some(name_ref) => name_ref
    None => return
  }
  let parts = name_ref.parts
  let texts : Array[String] = []
  for p in parts {
    texts.push(identifier_text(p.bytes))
  }
  let name_text = join_strings(texts, ".")
  // CTE precedence for single-part names (D-02, Pitfall 4): `FROM c` where c
  // is a WITH cte resolves to the CTE, never to a same-named catalog table.
  // The CTE scope entry is already visible (pushed by resolve_model), so no
  // duplicate entry is added — duplicating it would make unqualified columns
  // ambiguous.
  if parts.length() == 1 {
    let quoted = is_quoted(parts[0].bytes)
    match find_scope_entry_kind(scope, texts[0], quoted, ScopeKind::Cte) {
      Some(entry) => {
        bindings.push({
          kind: BindingKind::Cte,
          name: texts[0],
          resolved_to: entry.display,
          data_type: "",
          start_byte: name_ref.start_byte,
          end_byte: name_ref.end_byte,
        })
        return
      }
      None => ()
    }
  }
  match resolve_table_name_ref(name_ref, catalog) {
    Some((info, quoted)) => {
      let display = info.name
      bindings.push({
        kind: BindingKind::Table,
        name: name_text,
        resolved_to: display,
        data_type: "",
        start_byte: name_ref.start_byte,
        end_byte: name_ref.end_byte,
      })
      match item.alias {
        Some(alias) => {
          let start = match item.alias_slice { Some(s) => s.start_byte; None => name_ref.end_byte }
          let end = match item.alias_slice { Some(s) => s.end_byte; None => name_ref.end_byte }
          bindings.push({
            kind: BindingKind::Alias,
            name: alias,
            resolved_to: display,
            data_type: "",
            start_byte: start,
            end_byte: end,
          })
          scope.push({
            key: alias,
            kind: ScopeKind::Table,
            columns: info.columns,
            display: display,
            is_quoted: quoted,
          })
        }
        None => {
          // Effective scope key is the table name as spelled (last part).
          let last_part = if parts.length() == 0 {
            name_text
          } else {
            identifier_text(parts[parts.length() - 1].bytes)
          }
          scope.push({
            key: last_part,
            kind: ScopeKind::Table,
            columns: info.columns,
            display: display,
            is_quoted: quoted,
          })
        }
      }
    }
    None => {
      diagnostics.push({
        code: "unknown-table",
        message: "table not found in catalog: \{name_text}",
        start_byte: name_ref.start_byte,
        end_byte: name_ref.end_byte,
      })
    }
  }
}

/// Emits Column bindings for every column of `entry` within `[start, end)`.
fn emit_star_columns(
  entry : ScopeEntry,
  start : Int,
  end : Int,
  bindings : Array[Binding],
  out : Array[ColumnInfo],
) -> Unit {
  for col in entry.columns {
    bindings.push({
      kind: BindingKind::Column,
      name: col.name,
      resolved_to: col.name,
      data_type: col.data_type,
      start_byte: start,
      end_byte: end,
    })
    out.push(col)
  }
}

/// Expands a star projection (D-05): bare `*` expands every scope entry's
/// columns; `t.*`/`db.t.*` expand the named table's columns. `star_start`/
/// `star_end` carry the span of the `*` (or its qualified ref) for bindings.
fn[T : Catalog] expand_star(
  qualifier : NameRef?,
  star_start : Int,
  star_end : Int,
  scope : Array[ScopeEntry],
  catalog : T,
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
) -> Array[ColumnInfo] {
  let out : Array[ColumnInfo] = []
  match qualifier {
    None => {
      for entry in scope {
        if entry.key != "" {
          emit_star_columns(entry, star_start, star_end, bindings, out)
        }
      }
    }
    Some(ref) => {
      let n = ref.parts.length()
      if n == 1 {
        let name_text = identifier_text(ref.parts[0].bytes)
        let quoted = is_quoted(ref.parts[0].bytes)
        match find_scope_entry(scope, name_text, quoted) {
          Some(entry) => emit_star_columns(entry, star_start, star_end, bindings, out)
          None => {
            match resolve_table_with_quoted(catalog, name_text, quoted) {
              Some(info) => {
                emit_star_columns({
                  key: name_text,
                  kind: ScopeKind::Table,
                  columns: info.columns,
                  display: info.name,
                  is_quoted: quoted,
                }, star_start, star_end, bindings, out)
              }
              None => diagnostics.push({
                code: "unknown-table",
                message: "table not found in catalog: \{name_text}",
                start_byte: ref.start_byte,
                end_byte: ref.end_byte,
              })
            }
          }
        }
      } else if n >= 2 {
        let db_text = identifier_text(ref.parts[0].bytes)
        let table_text = identifier_text(ref.parts[1].bytes)
        match Catalog::table_in_db(catalog, db_text, table_text) {
          Some(info) => {
            emit_star_columns({
              key: table_text,
              kind: ScopeKind::Table,
              columns: info.columns,
              display: info.name,
              is_quoted: is_quoted(ref.parts[1].bytes),
            }, star_start, star_end, bindings, out)
          }
          None => diagnostics.push({
            code: "unknown-table",
            message: "table not found in catalog: \{db_text}.\{table_text}",
            start_byte: ref.start_byte,
            end_byte: ref.end_byte,
          })
        }
      }
    }
  }
  out
}

/// Resolves one name reference against the scope and catalog (D-03/D-04):
/// function calls, star expansion, unqualified columns, and qualified
/// `alias.col`/`table.col` (2 parts) or `db.table.col` (3+ parts). Returns the
/// resolved ColumnInfo for a plain column ref, None otherwise.
fn[T : Catalog] resolve_ref(
  ref : NameRef,
  scope : Array[ScopeEntry],
  catalog : T,
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
) -> ColumnInfo? {
  if ref.is_call {
    if ref.parts.length() == 1 {
      let name_text = identifier_text(ref.parts[0].bytes)
      match Catalog::function(catalog, name_text) {
        Some(fn_info) => {
          bindings.push({
            kind: BindingKind::Function,
            name: name_text,
            resolved_to: fn_info.name,
            data_type: fn_info.return_type,
            start_byte: ref.start_byte,
            end_byte: ref.end_byte,
          })
          return None
        }
        None => return None
      }
    }
    return None
  }
  if ref.star {
    ignore(expand_star(Some(ref), ref.start_byte, ref.end_byte, scope, catalog, bindings, diagnostics))
    return None
  }
  let parts = ref.parts
  let n = parts.length()
  if n == 1 {
    // Unqualified column search across all scope entries (innermost first).
    let name_text = identifier_text(parts[0].bytes)
    let quoted = is_quoted(parts[0].bytes)
    let found : Array[(ScopeEntry, ColumnInfo)] = []
    let mut i = scope.length()
    while i > 0 {
      let entry = scope[i - 1]
      match find_column_in(entry.columns, name_text, quoted) {
        Some(col) => found.push((entry, col))
        None => ()
      }
      i = i - 1
    }
    if found.length() == 1 {
      let col = found[0].1
      bindings.push({
        kind: BindingKind::Column,
        name: name_text,
        resolved_to: col.name,
        data_type: col.data_type,
        start_byte: ref.start_byte,
        end_byte: ref.end_byte,
      })
      return Some(col)
    } else if found.length() > 1 {
      diagnostics.push({
        code: "ambiguous-reference",
        message: "ambiguous reference: \{name_text}",
        start_byte: ref.start_byte,
        end_byte: ref.end_byte,
      })
      return None
    }
    return None
  } else if n == 2 {
    // alias.col or table.col: first segment resolves in scope, then column.
    let first_text = identifier_text(parts[0].bytes)
    let first_quoted = is_quoted(parts[0].bytes)
    let second_text = identifier_text(parts[1].bytes)
    let second_quoted = is_quoted(parts[1].bytes)
    match find_scope_entry(scope, first_text, first_quoted) {
      Some(entry) => {
        match find_column_in(entry.columns, second_text, second_quoted) {
          Some(col) => {
            bindings.push({
              kind: BindingKind::Column,
              name: second_text,
              resolved_to: col.name,
              data_type: col.data_type,
              start_byte: ref.start_byte,
              end_byte: ref.end_byte,
            })
            return Some(col)
          }
          None => return None
        }
      }
      None => {
        // Fall back to a default-db table.
        match resolve_table_with_quoted(catalog, first_text, first_quoted) {
          Some(info) => {
            match find_column_in(info.columns, second_text, second_quoted) {
              Some(col) => {
                bindings.push({
                  kind: BindingKind::Column,
                  name: second_text,
                  resolved_to: col.name,
                  data_type: col.data_type,
                  start_byte: ref.start_byte,
                  end_byte: ref.end_byte,
                })
                return Some(col)
              }
              None => return None
            }
          }
          None => return None
        }
      }
    }
  } else {
    // n >= 3: db.table.col via table_in_db (D-05).
    let db_text = identifier_text(parts[0].bytes)
    let table_text = identifier_text(parts[1].bytes)
    let col_text = identifier_text(parts[2].bytes)
    let col_quoted = is_quoted(parts[2].bytes)
    let table_quoted = is_quoted(parts[1].bytes)
    match Catalog::table_in_db(catalog, db_text, table_text) {
      Some(info) => {
        if table_quoted && info.name != table_text {
          return None
        }
        match find_column_in(info.columns, col_text, col_quoted) {
          Some(col) => {
            bindings.push({
              kind: BindingKind::Column,
              name: col_text,
              resolved_to: col.name,
              data_type: col.data_type,
              start_byte: ref.start_byte,
              end_byte: ref.end_byte,
            })
            return Some(col)
          }
          None => return None
        }
      }
      None => return None
    }
  }
}

/// Resolves one SELECT-list item: star expansion or expression refs, plus the
/// projection alias binding and the item's output column (for CTE/subquery
/// column derivation).
fn[T : Catalog] resolve_select_item(
  item : SelectItem,
  scope : Array[ScopeEntry],
  catalog : T,
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
  output : Array[ColumnInfo],
) -> Unit {
  if item.star {
    let start = if item.tokens.length() > 0 {
      item.tokens[item.tokens.length() - 1].start_byte
    } else {
      0
    }
    let end = if item.tokens.length() > 0 {
      item.tokens[item.tokens.length() - 1].end_byte
    } else {
      0
    }
    let columns = expand_star(item.star_qualifier, start, end, scope, catalog, bindings, diagnostics)
    for col in columns {
      output.push(col)
    }
    return
  }
  let resolved_refs : Array[ColumnInfo] = []
  for ref in item.refs {
    match resolve_ref(ref, scope, catalog, bindings, diagnostics) {
      Some(col) => resolved_refs.push(col)
      None => ()
    }
  }
  match item.alias {
    Some(alias) => {
      let start = match item.alias_slice { Some(s) => s.start_byte; None => 0 }
      let end = match item.alias_slice { Some(s) => s.end_byte; None => 0 }
      let resolved_to = if resolved_refs.length() > 0 {
        resolved_refs[0].name
      } else {
        alias
      }
      bindings.push({
        kind: BindingKind::Alias,
        name: alias,
        resolved_to: resolved_to,
        data_type: "",
        start_byte: start,
        end_byte: end,
      })
      let data_type = if resolved_refs.length() > 0 { resolved_refs[0].data_type } else { "" }
      output.push({ name: alias, data_type: data_type })
    }
    None => {
      if resolved_refs.length() == 1 && item.refs.length() == 1 {
        output.push(resolved_refs[0])
      }
    }
  }
}

/// Applies a CTE column-name alias list (`WITH c(x,y) AS ...`) over the body's
/// output columns by position.
fn apply_cte_aliases(cte : CteDef, columns : Array[ColumnInfo]) -> Array[ColumnInfo] {
  match cte.alias {
    None => columns
    Some(list) => {
      let names = split_comma(list)
      let out : Array[ColumnInfo] = []
      let mut i = 0
      while i < columns.length() {
        if i < names.length() {
          out.push({ name: names[i], data_type: columns[i].data_type })
        } else {
          out.push(columns[i])
        }
        i = i + 1
      }
      out
    }
  }
}

/// Splits a comma-separated string (avoids core `split` dependency).
fn split_comma(s : String) -> Array[String] {
  let parts : Array[String] = []
  let mut current = ""
  for ch in s.iter() {
    if ch == ',' {
      parts.push(current)
      current = ""
    } else {
      current = current + ch.to_string()
    }
  }
  parts.push(current)
  parts
}

/// Resolves one SELECT core, returning its output columns (first SELECT's
/// projections — the source of subquery/CTE column names).
fn[T : Catalog] resolve_core(
  core : SelectCore,
  catalog : T,
  outer : Array[ScopeEntry],
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
) -> Array[ColumnInfo] {
  let scope = outer.copy()
  for item in core.from {
    resolve_from_item(item, catalog, scope, bindings, diagnostics)
  }
  for item in core.joins {
    resolve_from_item(item, catalog, scope, bindings, diagnostics)
  }
  let output : Array[ColumnInfo] = []
  for item in core.select_list {
    resolve_select_item(item, scope, catalog, bindings, diagnostics, output)
  }
  for ref in core.where_refs {
    ignore(resolve_ref(ref, scope, catalog, bindings, diagnostics))
  }
  for ref in core.group_by {
    ignore(resolve_ref(ref, scope, catalog, bindings, diagnostics))
  }
  for ref in core.having {
    ignore(resolve_ref(ref, scope, catalog, bindings, diagnostics))
  }
  for ref in core.qualify {
    ignore(resolve_ref(ref, scope, catalog, bindings, diagnostics))
  }
  for ref in core.order_by {
    ignore(resolve_ref(ref, scope, catalog, bindings, diagnostics))
  }
  output
}

/// Resolves a full SELECT model: CTE bodies first (each CTE frame visible to
/// later CTEs and to all branches), then each branch in order. Returns the
/// first branch's output columns.
fn[T : Catalog] resolve_model(
  model : SelectModel,
  catalog : T,
  outer : Array[ScopeEntry],
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
) -> Array[ColumnInfo] {
  let scope = outer.copy()
  for cte in model.ctes {
    let columns = apply_cte_aliases(cte, resolve_core(cte.body, catalog, scope, bindings, diagnostics))
    scope.push({
      key: cte.name,
      kind: ScopeKind::Cte,
      columns: columns,
      display: cte.name,
      is_quoted: false,
    })
  }
  let mut output : Array[ColumnInfo] = []
  let mut first = true
  for branch in model.branches {
    let cols = resolve_core(branch, catalog, scope, bindings, diagnostics)
    if first {
      output = cols
      first = false
    }
  }
  output
}

/// Analyzes one SELECT body node, appending bindings and diagnostics.
fn[T : Catalog] analyze_select_body(
  body : @syntax.SyntaxNode,
  source_bytes : Bytes,
  catalog : T,
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
) -> Unit {
  match body.kind() {
    @syntax.SyntaxKind::Select => ()
    _ => return
  }
  // Error/Missing material => empty bindings + one requires-complete-parse
  // diagnostic (D-33 refusal philosophy, Pitfall 7); never panic.
  if body.is_error() || body.is_missing() || has_error_missing(body) {
    diagnostics.push({
      code: "requires-complete-parse",
      message: "refusing to analyze a SELECT with error/missing material",
      start_byte: body.span().start_byte,
      end_byte: body.span().end_byte,
    })
    return
  }
  let tokens = source_tokens(body, source_bytes)
  let model = match split_select_model(tokens) {
    Some(model) => model
    None => {
      diagnostics.push({
        code: "requires-complete-parse",
        message: "SELECT exceeds the analyzer's paren-depth limit",
        start_byte: body.span().start_byte,
        end_byte: body.span().end_byte,
      })
      return
    }
  }
  let scope : Array[ScopeEntry] = []
  ignore(resolve_model(model, catalog, scope, bindings, diagnostics))
}

/// Analyzes a parsed document's statements against the injected catalog,
/// returning resolved bindings and analyzer-channel diagnostics (D-06). The
/// syntax-only valid channel is never touched: the same parse without a
/// catalog yields byte-identical syntax results (ANLY-01).
pub fn[T : Catalog] analyze(
  node : @syntax.SyntaxNode,
  source_bytes : Bytes,
  catalog : T,
) -> AnalysisResult {
  let bindings : Array[Binding] = []
  let diagnostics : Array[AnalysisDiagnostic] = []
  for element in node.children() {
    match element {
      @syntax.SyntaxElement::ChildNode(statement_node) => {
        if statement_node.kind() is @syntax.SyntaxKind::Statement {
          for inner in statement_node.children() {
            match inner {
              @syntax.SyntaxElement::ChildNode(body) => {
                analyze_select_body(body, source_bytes, catalog, bindings, diagnostics)
              }
              @syntax.SyntaxElement::Leaf(_) => ()
            }
          }
        }
      }
      @syntax.SyntaxElement::Leaf(_) => ()
    }
  }
  { bindings: bindings, diagnostics: diagnostics }
}
