/// Name resolution for SELECT bodies over the flat token-leaf CST (D-01).
///
/// `analyze` walks a parsed document's Statement children, re-parses each
/// SELECT body via select_parser.mbt into a `SelectModel`, and resolves
/// table/column/CTE/alias_name/function references against the injected catalog
/// with a scope stack (D-02/D-04/D-05):
/// - Entering a CTE body or subquery pushes a fresh scope frame; leaving pops
///   it (Pitfall 4). CTE names are visible and take precedence over catalog
///   tables; same-name entries resolve inner-first.
/// - Table aliases take precedence over catalog table names; qualified names
///   resolve their first segment as alias_name → table (default db) → db
///   (Pitfall 3), so `db.table.col` (3 parts), `alias_name.col`/`db.table`
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

///|
/// Scope frame kinds for name resolution.
enum ScopeKind {
  Table
  Cte
  Subquery
  Alias
} derive(Eq)

///|
/// One visible name in the current scope: the lookup key (alias_name if present,
/// else the table/CTE name as spelled), the effective columns, and display
/// metadata for bindings. `block` is the query-block sequence number (the
/// scope length when the owning core began resolving) used to keep correlated
/// subquery scoping correct (WR-04): unqualified columns resolve against the
/// current block first and only fall back to outer blocks.
priv struct ScopeEntry {
  key : String
  kind : ScopeKind
  columns : Array[ColumnInfo]
  display : String
  is_quoted : Bool
  block : Int
}

///|
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

///|
/// True when a whole token is a quoted identifier (backtick or double quote).
fn is_quoted(bytes : Bytes) -> Bool {
  bytes.length() > 0 && (bytes[0].to_int() == 96 || bytes[0].to_int() == 34)
}

///|
/// True when the subtree contains Error/Missing material (Pitfall 7): mirrors
/// the formatter's first_unsafe_element scan (D-33 refusal philosophy).
pub fn has_error_missing(node : @syntax.SyntaxNode) -> Bool {
  if node.kind() is @syntax.SyntaxKind::Error ||
    node.kind() is @syntax.SyntaxKind::Missing {
    return true
  }
  for element in node.children() {
    match element {
      @syntax.SyntaxElement::ChildNode(child) =>
        if has_error_missing(child) {
          return true
        }
      @syntax.SyntaxElement::Leaf(leaf) =>
        if leaf.kind is @syntax.LeafKind::SourceError ||
          leaf.kind is @syntax.LeafKind::SourceSkipped {
          return true
        }
    }
  }
  false
}

///|
/// Column lookup within a column list. Quoted references match byte-exactly
/// (D-03); unquoted references fold ASCII case.
fn find_column_in(
  columns : Array[ColumnInfo],
  name : String,
  quoted : Bool,
) -> ColumnInfo? {
  for col in columns {
    if quoted {
      if col.name == name {
        return Some(col)
      }
    } else if col.name.equal_ignore_ascii_case(name) {
      return Some(col)
    }
  }
  None
}

///|
/// Scope lookup by key, innermost first. Quoted keys match exactly; unquoted
/// keys fold ASCII case. Anonymous subquery entries (empty key) are skipped
/// for qualified lookup.
fn find_scope_entry(
  scope : Array[ScopeEntry],
  key : String,
  quoted : Bool,
) -> ScopeEntry? {
  let mut i = scope.length()
  while i > 0 {
    let entry = scope[i - 1]
    if quoted {
      if entry.key == key {
        return Some(entry)
      }
    } else if entry.key != "" && entry.key.equal_ignore_ascii_case(key) {
      return Some(entry)
    }
    i = i - 1
  }
  None
}

///|
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

///|
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

///|
/// Resolves a table name reference (1..3 dotted parts) against the catalog.
/// Returns (info, quoted) where `quoted` is whether the trailing table part
/// was quoted. 2+ parts use `table_in_db` (D-05); the trailing table part is
/// byte-re-checked when quoted (D-03).
fn[T : Catalog] resolve_table_name_ref(
  name_ref : NameRef,
  catalog : T,
) -> (TableInfo, Bool)? {
  let parts = name_ref.parts
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
      Some(info) =>
        if table_quoted && info.name != table_text {
          None
        } else {
          Some((info, table_quoted))
        }
      None => None
    }
  }
}

///|
/// Resolves a scope entry from a FROM item: catalog tables (with alias_name
/// precedence), CTE references, and subquery aliases. Appends bindings and
/// scope entries; emits unknown-table diagnostics for unresolved names.
/// `block` is this query core's block number (WR-04): every entry pushed by
/// this core carries it so unqualified columns resolve block-locally first.
fn[T : Catalog] resolve_from_item(
  item : FromItem,
  catalog : T,
  scope : Array[ScopeEntry],
  block : Int,
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
) -> Unit {
  if item.is_subquery {
    let model = match item.subquery {
      Some(model) => model
      None => return
    }
    let columns = resolve_model(model, catalog, scope, bindings, diagnostics)
    match item.alias_name {
      Some(alias_name) => {
        let start = match item.alias_slice {
          Some(s) => s.start_byte
          None => 0
        }
        let end = match item.alias_slice {
          Some(s) => s.end_byte
          None => 0
        }
        bindings.push({
          kind: BindingKind::Alias,
          name: alias_name,
          resolved_to: alias_name,
          data_type: "",
          start_byte: start,
          end_byte: end,
        })
        scope.push({
          key: alias_name,
          kind: ScopeKind::Subquery,
          columns,
          display: alias_name,
          is_quoted: false,
          block,
        })
      }
      None =>
        // Anonymous subquery: columns visible for unqualified refs only.
        scope.push({
          key: "",
          kind: ScopeKind::Subquery,
          columns,
          display: "",
          is_quoted: false,
          block,
        })
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
      match item.alias_name {
        Some(alias_name) => {
          let start = match item.alias_slice {
            Some(s) => s.start_byte
            None => name_ref.end_byte
          }
          let end = match item.alias_slice {
            Some(s) => s.end_byte
            None => name_ref.end_byte
          }
          bindings.push({
            kind: BindingKind::Alias,
            name: alias_name,
            resolved_to: display,
            data_type: "",
            start_byte: start,
            end_byte: end,
          })
          scope.push({
            key: alias_name,
            kind: ScopeKind::Table,
            columns: info.columns,
            display,
            is_quoted: quoted,
            block,
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
            display,
            is_quoted: quoted,
            block,
          })
        }
      }
    }
    None =>
      diagnostics.push({
        code: "unknown-table",
        message: "table not found in catalog: \{name_text}",
        start_byte: name_ref.start_byte,
        end_byte: name_ref.end_byte,
      })
  }
}

///|
/// True when `col_name` is excluded by an `EXCEPT (cols)` slice list (D-03):
/// unquoted slices fold ASCII case; quoted slices match byte-exact. Mirrors
/// `find_column_in` semantics so the exclusion is a single source of truth.
fn is_excepted(except_cols : Array[TokenSlice], col_name : String) -> Bool {
  for slice in except_cols {
    let quoted = is_quoted(slice.bytes)
    let name = identifier_text(slice.bytes)
    if quoted {
      if col_name == name {
        return true
      }
    } else if col_name.equal_ignore_ascii_case(name) {
      return true
    }
  }
  false
}

///|
/// Emits Column bindings for every column of `entry` within `[start, end)`,
/// skipping columns named in `except_cols` (`* EXCEPT (cols)`, D-03).
fn emit_star_columns(
  entry : ScopeEntry,
  start : Int,
  end : Int,
  bindings : Array[Binding],
  out : Array[ColumnInfo],
  except_cols : Array[TokenSlice],
) -> Unit {
  for col in entry.columns {
    if is_excepted(except_cols, col.name) {
      continue
    }
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

///|
/// Expands a star projection (D-05): bare `*` expands every scope entry's
/// columns; `t.*`/`db.t.*` expand the named table's columns. `star_start`/
/// `star_end` carry the span of the `*` (or its qualified name_ref) for bindings.
/// `except_cols` carries the `* EXCEPT (cols)` exclusion list (D-03): excluded
/// columns produce no binding — the analyzer never fabricates an edge for a
/// column the projection explicitly removes.
fn[T : Catalog] expand_star(
  qualifier : NameRef?,
  star_start : Int,
  star_end : Int,
  scope : Array[ScopeEntry],
  catalog : T,
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
  except_cols : Array[TokenSlice],
) -> Array[ColumnInfo] {
  let out : Array[ColumnInfo] = []
  match qualifier {
    None =>
      for entry in scope {
        // WR-05: anonymous subqueries (key == "") participate in bare `*`
        // expansion — `SELECT * FROM (SELECT a FROM t)` must emit the
        // subquery's columns. Only qualified/alias_name lookups skip empty keys.
        emit_star_columns(
          entry, star_start, star_end, bindings, out, except_cols,
        )
      }
    Some(name_ref) => {
      let n = name_ref.parts.length()
      if n == 1 {
        let name_text = identifier_text(name_ref.parts[0].bytes)
        let quoted = is_quoted(name_ref.parts[0].bytes)
        match find_scope_entry(scope, name_text, quoted) {
          Some(entry) =>
            emit_star_columns(
              entry, star_start, star_end, bindings, out, except_cols,
            )
          None =>
            match resolve_table_with_quoted(catalog, name_text, quoted) {
              Some(info) =>
                emit_star_columns(
                  {
                    key: name_text,
                    kind: ScopeKind::Table,
                    columns: info.columns,
                    display: info.name,
                    is_quoted: quoted,
                    block: 0,
                  },
                  star_start,
                  star_end,
                  bindings,
                  out,
                  except_cols,
                )
              None =>
                diagnostics.push({
                  code: "unknown-table",
                  message: "table not found in catalog: \{name_text}",
                  start_byte: name_ref.start_byte,
                  end_byte: name_ref.end_byte,
                })
            }
        }
      } else if n >= 2 {
        let db_text = identifier_text(name_ref.parts[0].bytes)
        let table_text = identifier_text(name_ref.parts[1].bytes)
        let table_quoted = is_quoted(name_ref.parts[1].bytes)
        match Catalog::table_in_db(catalog, db_text, table_text) {
          Some(info) =>
            // WR-01: D-03 quoted byte re-check on the trailing table segment,
            // mirroring resolve_table_name_ref — `db.\`T\`.*` must not match a
            // catalog table named `t` (case-fold hit + byte-exact re-check).
            if table_quoted && info.name != table_text {
              diagnostics.push({
                code: "unknown-table",
                message: "table not found in catalog: \{db_text}.\{table_text}",
                start_byte: name_ref.start_byte,
                end_byte: name_ref.end_byte,
              })
            } else {
              emit_star_columns(
                {
                  key: table_text,
                  kind: ScopeKind::Table,
                  columns: info.columns,
                  display: info.name,
                  is_quoted: table_quoted,
                  block: 0,
                },
                star_start,
                star_end,
                bindings,
                out,
                except_cols,
              )
            }
          None =>
            diagnostics.push({
              code: "unknown-table",
              message: "table not found in catalog: \{db_text}.\{table_text}",
              start_byte: name_ref.start_byte,
              end_byte: name_ref.end_byte,
            })
        }
      }
    }
  }
  out
}

///|
/// Number of depth-0 comma-separated arguments in a call's argument token
/// slice (D-04): `f(a)` -> 1, `f(a, b)` -> 2, `f()` -> 0, `f((a, b))` -> 1.
/// Nested parens suppress inner commas; string/quoted tokens never unbalance
/// the counter (whole-token bytes only, Pitfall 1).
fn count_call_args(args : Array[TokenSlice]) -> Int {
  if args.length() == 0 {
    return 0
  }
  let mut count = 1
  let mut depth = 0
  for i in 0..<args.length() {
    let bytes = args[i].bytes
    if bytes == b"(" {
      depth = depth + 1
    } else if bytes == b")" {
      if depth > 0 {
        depth = depth - 1
      }
    } else if depth == 0 && bytes == b"," {
      count = count + 1
    }
  }
  count
}

///|
/// True when the scope has at least one named entry exposing columns — the
/// signal that an unresolvable unqualified name is a column reference (and so
/// earns an unknown-column diagnostic), rather than a bare select against no
/// column-bearing table (D-04).
fn scope_has_visible_columns(scope : Array[ScopeEntry]) -> Bool {
  for entry in scope {
    if entry.key != "" && entry.columns.length() > 0 {
      return true
    }
  }
  false
}

///|
/// Resolves one name reference against the scope and catalog (D-03/D-04):
/// function calls, star expansion, unqualified columns, and qualified
/// `alias_name.col`/`table.col` (2 parts) or `db.table.col` (3+ parts). Returns the
/// resolved ColumnInfo for a plain column name_ref, None otherwise. `current_block`
/// is the caller's query-block number (WR-04): unqualified columns resolve
/// against the current block's entries first, then fall back to outer blocks.
fn[T : Catalog] resolve_ref(
  name_ref : NameRef,
  scope : Array[ScopeEntry],
  catalog : T,
  current_block : Int,
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
) -> ColumnInfo? {
  if name_ref.is_call {
    if name_ref.parts.length() == 1 {
      let name_text = identifier_text(name_ref.parts[0].bytes)
      match Catalog::function(catalog, name_text) {
        Some(fn_info) => {
          // D-04: arity check — an argument count below min_arity or above
          // param_types.length() is a function-arity diagnostic. The Function
          // binding is still emitted (the name resolved); no expression-level
          // type unification or literal propagation (ANAL-02 out of scope).
          let arg_count = count_call_args(name_ref.call_args)
          if arg_count < fn_info.min_arity ||
            arg_count > fn_info.param_types.length() {
            diagnostics.push({
              code: "function-arity",
              message: "function \{name_text} expects between \{fn_info.min_arity} and \{fn_info.param_types.length()} arguments, got \{arg_count}",
              start_byte: name_ref.start_byte,
              end_byte: name_ref.end_byte,
            })
          }
          bindings.push({
            kind: BindingKind::Function,
            name: name_text,
            resolved_to: fn_info.name,
            data_type: fn_info.return_type,
            start_byte: name_ref.start_byte,
            end_byte: name_ref.end_byte,
          })
          return None
        }
        None => {
          diagnostics.push({
            code: "unknown-function",
            message: "function not found in catalog: \{name_text}",
            start_byte: name_ref.start_byte,
            end_byte: name_ref.end_byte,
          })
          return None
        }
      }
    }
    return None
  }
  if name_ref.star {
    ignore(
      expand_star(
        Some(name_ref),
        name_ref.start_byte,
        name_ref.end_byte,
        scope,
        catalog,
        bindings,
        diagnostics,
        [],
      ),
    )
    return None
  }
  let parts = name_ref.parts
  let n = parts.length()
  if n == 1 {
    let name_text = identifier_text(parts[0].bytes)
    let quoted = is_quoted(parts[0].bytes)
    // WR-06: projection aliases take precedence over table columns —
    // `SELECT a AS x FROM t ORDER BY x` must resolve x to the output alias_name.
    // Innermost alias_name wins; a projection alias_name shadows same-named columns.
    let mut a = scope.length()
    while a > 0 {
      let entry = scope[a - 1]
      if entry.kind == ScopeKind::Alias {
        match find_column_in(entry.columns, name_text, quoted) {
          Some(col) => {
            bindings.push({
              kind: BindingKind::Column,
              name: name_text,
              resolved_to: col.name,
              data_type: col.data_type,
              start_byte: name_ref.start_byte,
              end_byte: name_ref.end_byte,
            })
            return Some(col)
          }
          None => ()
        }
      }
      a = a - 1
    }
    // WR-04: unqualified columns resolve against the CURRENT block first
    // (the query core's own FROM entries), so a correlated subquery's column
    // never collides with a same-named column in an outer block. Ambiguity is
    // judged only within the current block; a miss falls back to outer blocks.
    let found_current : Array[(ScopeEntry, ColumnInfo)] = []
    let mut i = scope.length()
    while i > 0 {
      let entry = scope[i - 1]
      if entry.block == current_block {
        match find_column_in(entry.columns, name_text, quoted) {
          Some(col) => found_current.push((entry, col))
          None => ()
        }
      }
      i = i - 1
    }
    if found_current.length() == 1 {
      let col = found_current[0].1
      bindings.push({
        kind: BindingKind::Column,
        name: name_text,
        resolved_to: col.name,
        data_type: col.data_type,
        start_byte: name_ref.start_byte,
        end_byte: name_ref.end_byte,
      })
      return Some(col)
    } else if found_current.length() > 1 {
      diagnostics.push({
        code: "ambiguous-reference",
        message: "ambiguous reference: \{name_text}",
        start_byte: name_ref.start_byte,
        end_byte: name_ref.end_byte,
      })
      return None
    }
    // Correlated fallback: outer blocks, innermost-first. The scope layout is
    // [outer blocks ..., current block], so walk the prefix from the end,
    // processing one block at a time; the first outer block with a match wins
    // (exactly one -> resolved, more than one -> ambiguous in that block).
    let mut k = scope.length()
    while k > 0 && scope[k - 1].block == current_block {
      k = k - 1
    }
    while k > 0 {
      let outer_block = scope[k - 1].block
      let found_outer : Array[(ScopeEntry, ColumnInfo)] = []
      while k > 0 && scope[k - 1].block == outer_block {
        let entry = scope[k - 1]
        match find_column_in(entry.columns, name_text, quoted) {
          Some(col) => found_outer.push((entry, col))
          None => ()
        }
        k = k - 1
      }
      if found_outer.length() == 1 {
        let col = found_outer[0].1
        bindings.push({
          kind: BindingKind::Column,
          name: name_text,
          resolved_to: col.name,
          data_type: col.data_type,
          start_byte: name_ref.start_byte,
          end_byte: name_ref.end_byte,
        })
        return Some(col)
      } else if found_outer.length() > 1 {
        diagnostics.push({
          code: "ambiguous-reference",
          message: "ambiguous reference: \{name_text}",
          start_byte: name_ref.start_byte,
          end_byte: name_ref.end_byte,
        })
        return None
      }
    }
    // Not found: unknown-column only when visible tables actually expose
    // columns (avoids flagging bare `SELECT x` with no column-bearing scope,
    // and quoted-exact tests against an empty column list — D-03/D-04).
    if scope_has_visible_columns(scope) {
      diagnostics.push({
        code: "unknown-column",
        message: "column not found in any visible table: \{name_text}",
        start_byte: name_ref.start_byte,
        end_byte: name_ref.end_byte,
      })
    }
    return None
  } else if n == 2 {
    // alias_name.col or table.col: first segment resolves in scope, then column.
    let first_text = identifier_text(parts[0].bytes)
    let first_quoted = is_quoted(parts[0].bytes)
    let second_text = identifier_text(parts[1].bytes)
    let second_quoted = is_quoted(parts[1].bytes)
    match find_scope_entry(scope, first_text, first_quoted) {
      Some(entry) =>
        match find_column_in(entry.columns, second_text, second_quoted) {
          Some(col) => {
            bindings.push({
              kind: BindingKind::Column,
              name: second_text,
              resolved_to: col.name,
              data_type: col.data_type,
              start_byte: name_ref.start_byte,
              end_byte: name_ref.end_byte,
            })
            return Some(col)
          }
          None => {
            diagnostics.push({
              code: "unknown-column",
              message: "column not found in \{first_text}.\{second_text}",
              start_byte: name_ref.start_byte,
              end_byte: name_ref.end_byte,
            })
            return None
          }
        }
      None =>
        // Fall back to a default-db table.
        match resolve_table_with_quoted(catalog, first_text, first_quoted) {
          Some(info) =>
            match find_column_in(info.columns, second_text, second_quoted) {
              Some(col) => {
                bindings.push({
                  kind: BindingKind::Column,
                  name: second_text,
                  resolved_to: col.name,
                  data_type: col.data_type,
                  start_byte: name_ref.start_byte,
                  end_byte: name_ref.end_byte,
                })
                return Some(col)
              }
              None => {
                diagnostics.push({
                  code: "unknown-column",
                  message: "column not found in \{first_text}.\{second_text}",
                  start_byte: name_ref.start_byte,
                  end_byte: name_ref.end_byte,
                })
                return None
              }
            }
          None => return None
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
              start_byte: name_ref.start_byte,
              end_byte: name_ref.end_byte,
            })
            return Some(col)
          }
          None => {
            diagnostics.push({
              code: "unknown-column",
              message: "column not found in \{db_text}.\{table_text}.\{col_text}",
              start_byte: name_ref.start_byte,
              end_byte: name_ref.end_byte,
            })
            return None
          }
        }
      }
      None => return None
    }
  }
}

///|
/// Resolves one SELECT-list item: star expansion or expression refs, plus the
/// projection alias_name binding and the item's output column (for CTE/subquery
/// column derivation). `alias_entries` collects projection-alias_name scope entries
/// (WR-06) so the caller can expose them to later clauses after the whole
/// select list has been resolved.
fn[T : Catalog] resolve_select_item(
  item : SelectItem,
  scope : Array[ScopeEntry],
  catalog : T,
  current_block : Int,
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
  output : Array[ColumnInfo],
  alias_entries : Array[ScopeEntry],
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
    let columns = expand_star(
      item.star_qualifier,
      start,
      end,
      scope,
      catalog,
      bindings,
      diagnostics,
      item.except_cols,
    )
    for col in columns {
      output.push(col)
    }
    return
  }
  let resolved_refs : Array[ColumnInfo] = []
  for name_ref in item.refs {
    match
      resolve_ref(
        name_ref, scope, catalog, current_block, bindings, diagnostics,
      ) {
      Some(col) => resolved_refs.push(col)
      None => ()
    }
  }
  match item.alias_name {
    Some(alias_name) => {
      let start = match item.alias_slice {
        Some(s) => s.start_byte
        None => 0
      }
      let end = match item.alias_slice {
        Some(s) => s.end_byte
        None => 0
      }
      let resolved_to = if resolved_refs.length() > 0 {
        resolved_refs[0].name
      } else {
        alias_name
      }
      bindings.push({
        kind: BindingKind::Alias,
        name: alias_name,
        resolved_to,
        data_type: "",
        start_byte: start,
        end_byte: end,
      })
      let data_type = if resolved_refs.length() > 0 {
        resolved_refs[0].data_type
      } else {
        ""
      }
      output.push({ name: alias_name, data_type })
      // WR-06: expose the projection alias_name to later clauses (ORDER BY /
      // HAVING / QUALIFY / GROUP BY) as an Alias-kind scope entry.
      alias_entries.push({
        key: alias_name,
        kind: ScopeKind::Alias,
        columns: [{ name: alias_name, data_type }],
        display: alias_name,
        is_quoted: false,
        block: current_block,
      })
    }
    None =>
      if resolved_refs.length() == 1 && item.refs.length() == 1 {
        output.push(resolved_refs[0])
      }
  }
}

///|
/// Applies a CTE column-name alias_name list (`WITH c(x,y) AS ...`) over the body's
/// output columns by position.
fn apply_cte_aliases(
  cte : CteDef,
  columns : Array[ColumnInfo],
) -> Array[ColumnInfo] {
  match cte.alias_name {
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

///|
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

///|
/// Resolves one SELECT core, returning its output columns (first SELECT's
/// projections — the source of subquery/CTE column names). `block` is this
/// core's query-block number (WR-04): the scope length at entry, which every
/// FROM entry pushed here carries so unqualified columns resolve block-locally.
fn[T : Catalog] resolve_core(
  core : SelectCore,
  catalog : T,
  outer : Array[ScopeEntry],
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
) -> Array[ColumnInfo] {
  let scope = outer.copy()
  let block = outer.length()
  for item in core.from {
    resolve_from_item(item, catalog, scope, block, bindings, diagnostics)
  }
  for item in core.joins {
    resolve_from_item(item, catalog, scope, block, bindings, diagnostics)
  }
  let output : Array[ColumnInfo] = []
  let alias_entries : Array[ScopeEntry] = []
  for item in core.select_list {
    resolve_select_item(
      item, scope, catalog, block, bindings, diagnostics, output, alias_entries,
    )
  }
  // WR-06: expose projection aliases to the remaining clauses (GROUP BY /
  // HAVING / QUALIFY / ORDER BY / WHERE) only after the whole select list has
  // been resolved, so select-list items never see each other's aliases.
  for entry in alias_entries {
    scope.push(entry)
  }
  for name_ref in core.where_refs {
    ignore(resolve_ref(name_ref, scope, catalog, block, bindings, diagnostics))
  }
  for name_ref in core.group_by {
    ignore(resolve_ref(name_ref, scope, catalog, block, bindings, diagnostics))
  }
  for name_ref in core.having {
    ignore(resolve_ref(name_ref, scope, catalog, block, bindings, diagnostics))
  }
  for name_ref in core.qualify {
    ignore(resolve_ref(name_ref, scope, catalog, block, bindings, diagnostics))
  }
  for name_ref in core.order_by {
    ignore(resolve_ref(name_ref, scope, catalog, block, bindings, diagnostics))
  }
  output
}

///|
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
  let block = outer.length()
  for cte in model.ctes {
    let columns = apply_cte_aliases(
      cte,
      resolve_core(cte.body, catalog, scope, bindings, diagnostics),
    )
    scope.push({
      key: cte.name,
      kind: ScopeKind::Cte,
      columns,
      display: cte.name,
      is_quoted: false,
      block,
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

///|
/// Runs the existing SELECT re-parse + resolve pipeline over a token slice
/// (D-01). Shared by SELECT bodies and CREATE VIEW query bodies (D-02).
/// `fail_start`/`fail_end` carry the span for a paren-depth-limit diagnostic.
fn[T : Catalog] analyze_select_tokens(
  tokens : Array[(Bytes, Int, Int)],
  fail_start : Int,
  fail_end : Int,
  catalog : T,
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
) -> Unit {
  let model = match split_select_model(tokens) {
    Some(model) => model
    None => {
      diagnostics.push({
        code: "requires-complete-parse",
        message: "SELECT exceeds the analyzer's paren-depth limit",
        start_byte: fail_start,
        end_byte: fail_end,
      })
      return
    }
  }
  let scope : Array[ScopeEntry] = []
  ignore(resolve_model(model, catalog, scope, bindings, diagnostics))
}

///|
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
  analyze_select_tokens(
    tokens,
    body.span().start_byte,
    body.span().end_byte,
    catalog,
    bindings,
    diagnostics,
  )
}

///|
/// Collects a dotted qualified name reference starting at `index`, returning
/// the NameRef and the index just past it (D-02, DML target tables).
pub fn qualified_ref_at(
  tokens : Array[(Bytes, Int, Int)],
  index : Int,
) -> (NameRef, Int)? {
  if index >= tokens.length() || !is_identifier_token(tokens[index].0) {
    return None
  }
  let parts : Array[TokenSlice] = []
  let mut after = index
  while after < tokens.length() && is_identifier_token(tokens[after].0) {
    parts.push({
      bytes: tokens[after].0,
      start_byte: tokens[after].1,
      end_byte: tokens[after].2,
    })
    after = after + 1
    if after < tokens.length() && tokens[after].0 == b"." {
      after = after + 1
      if after >= tokens.length() || !is_identifier_token(tokens[after].0) {
        break
      }
    } else {
      break
    }
  }
  if parts.length() == 0 {
    return None
  }
  Some(
    (
      {
        parts,
        star: false,
        is_call: false,
        call_args: [],
        start_byte: parts[0].start_byte,
        end_byte: parts[parts.length() - 1].end_byte,
      },
      after,
    ),
  )
}

///|
/// Index of the first `word` token at paren depth 0 in `[start, end)`, or -1
/// when absent. Strings/quoted identifiers never match (whole-token bytes).
pub fn find_word_at_depth0(
  tokens : Array[(Bytes, Int, Int)],
  start : Int,
  end : Int,
  word : Bytes,
) -> Int {
  let mut depth = 0
  let mut i = start
  while i < end {
    let bytes = tokens[i].0
    if bytes == b"(" {
      depth = depth + 1
    } else if bytes == b")" {
      if depth > 0 {
        depth = depth - 1
      }
    } else if depth == 0 && bytes_equal_ci(bytes, word) {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// Converts a token-index range into TokenSlice values (byte level, D-01).
pub fn slice_tokens(
  tokens : Array[(Bytes, Int, Int)],
  start : Int,
  end : Int,
) -> Array[TokenSlice] {
  let out : Array[TokenSlice] = []
  let mut i = start
  while i < end && i < tokens.length() {
    let (b, s, e) = tokens[i]
    out.push({ bytes: b, start_byte: s, end_byte: e })
    i = i + 1
  }
  out
}

///|
/// Thin public wrapper (D-01, Wave 0): token index where a CREATE VIEW body's
/// query starts — just past the view name, optional column-name list, and
/// optional AS. Behavior mirrors `analyze_create_view_body`'s location logic
/// (zero semantic change); returns `tokens.length()` when the query start
/// cannot be recovered. lineage/ (07-02) re-parses the body slice from here.
pub fn view_body_location(tokens : Array[(Bytes, Int, Int)]) -> Int {
  // CREATE [TEMPORARY] VIEW [IF NOT EXISTS] name — leading-keyword prefix
  // (mirrors `leading_prefix_end` for SyntaxKind::CreateView).
  let mut prefix = 0
  if prefix < tokens.length() && bytes_equal_ci(tokens[prefix].0, b"CREATE") {
    prefix = prefix + 1
  }
  if prefix < tokens.length() && bytes_equal_ci(tokens[prefix].0, b"TEMPORARY") {
    prefix = prefix + 1
  }
  if prefix < tokens.length() && bytes_equal_ci(tokens[prefix].0, b"VIEW") {
    prefix = prefix + 1
  }
  if prefix < tokens.length() && bytes_equal_ci(tokens[prefix].0, b"IF") {
    prefix = prefix + 1
  }
  if prefix < tokens.length() && bytes_equal_ci(tokens[prefix].0, b"NOT") {
    prefix = prefix + 1
  }
  if prefix < tokens.length() && bytes_equal_ci(tokens[prefix].0, b"EXISTS") {
    prefix = prefix + 1
  }
  match qualified_ref_at(tokens, prefix) {
    Some((_, after_name)) => {
      let mut query_start = after_name
      // Optional view column list `(a, b)` between the name and AS.
      if query_start < tokens.length() && tokens[query_start].0 == b"(" {
        let close = matching_paren(tokens, query_start)
        if close >= tokens.length() {
          return tokens.length()
        }
        query_start = close + 1
      }
      // Optional AS.
      if query_start < tokens.length() &&
        bytes_equal_ci(tokens[query_start].0, b"AS") {
        query_start = query_start + 1
      }
      query_start
    }
    None => tokens.length()
  }
}

///|
/// Thin public wrapper (D-01, Wave 0): locates the target column-name list and
/// query body of an INSERT statement token stream. Returns the token range
/// (inclusive-exclusive) of the parenthesized target column list — or None —
/// plus the token index where the VALUES/SELECT/WITH body begins
/// (`tokens.length()` when no body keyword is found). Mirrors
/// `analyze_dml_body`'s Insert-arm location logic plus the Research Pattern 3
/// body-location helper (zero semantic change to analyze_dml_body); returns
/// None when the target table name cannot be recovered. lineage/ (07-02)
/// re-parses the body slice from `body_start` and position-maps columns.
pub fn insert_body_location(
  tokens : Array[(Bytes, Int, Int)],
) -> ((Int, Int)?, Int)? {
  // (INSERT | UPSERT) ( OVERWRITE [TABLE] | INTO ) name — leading-keyword
  // prefix (mirrors `leading_prefix_end` for SyntaxKind::Insert).
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
  match qualified_ref_at(tokens, prefix) {
    Some((_, after_table)) => {
      let mut after_col = after_table
      let col_list : (Int, Int)? = if after_table < tokens.length() &&
        tokens[after_table].0 == b"(" {
        let close = matching_paren(tokens, after_table)
        if close >= tokens.length() {
          None
        } else {
          after_col = close + 1
          Some((after_table + 1, close))
        }
      } else {
        None
      }
      // Query body: VALUES | SELECT | WITH — whichever appears first at depth 0.
      let values = find_word_at_depth0(
        tokens,
        after_col,
        tokens.length(),
        b"VALUES",
      )
      let select = find_word_at_depth0(
        tokens,
        after_col,
        tokens.length(),
        b"SELECT",
      )
      let with_word = find_word_at_depth0(
        tokens,
        after_col,
        tokens.length(),
        b"WITH",
      )
      let mut body_start = tokens.length()
      if values >= 0 && values < body_start {
        body_start = values
      }
      if select >= 0 && select < body_start {
        body_start = select
      }
      if with_word >= 0 && with_word < body_start {
        body_start = with_word
      }
      Some((col_list, body_start))
    }
    None => None
  }
}

///|
/// Resolves every name reference in a token slice against `scope` (D-02),
/// reusing resolve_ref for bindings and analyzer-channel diagnostics.
fn[T : Catalog] resolve_token_refs(
  slices : Array[TokenSlice],
  scope : Array[ScopeEntry],
  catalog : T,
  current_block : Int,
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
) -> Unit {
  let refs = collect_refs(slices)
  for name_ref in refs {
    ignore(
      resolve_ref(
        name_ref, scope, catalog, current_block, bindings, diagnostics,
      ),
    )
  }
}

///|
/// Resolves a DML target-table reference: emits a Table binding and pushes a
/// scope entry carrying the table's columns so SET/WHERE/VALUES column refs
/// resolve against it (D-02). Missing targets emit unknown-table.
fn[T : Catalog] resolve_dml_target(
  table_ref : NameRef,
  catalog : T,
  scope : Array[ScopeEntry],
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
) -> Unit {
  let parts = table_ref.parts
  let texts : Array[String] = []
  for p in parts {
    texts.push(identifier_text(p.bytes))
  }
  let name_text = join_strings(texts, ".")
  match resolve_table_name_ref(table_ref, catalog) {
    Some((info, quoted)) => {
      bindings.push({
        kind: BindingKind::Table,
        name: name_text,
        resolved_to: info.name,
        data_type: "",
        start_byte: table_ref.start_byte,
        end_byte: table_ref.end_byte,
      })
      let last_part = if parts.length() == 0 {
        name_text
      } else {
        identifier_text(parts[parts.length() - 1].bytes)
      }
      scope.push({
        key: last_part,
        kind: ScopeKind::Table,
        columns: info.columns,
        display: info.name,
        is_quoted: quoted,
        block: 0,
      })
    }
    None =>
      diagnostics.push({
        code: "unknown-table",
        message: "table not found in catalog: \{name_text}",
        start_byte: table_ref.start_byte,
        end_byte: table_ref.end_byte,
      })
  }
}

///|
/// Analyzes one DML body node (Insert/Update/Delete/Merge): resolves the
/// target table and the column-level references in UPDATE SET/WHERE, DELETE
/// WHERE, INSERT column lists, and MERGE SET (D-02). `resolve_table_references`
/// behavior is untouched (D-05).
fn[T : Catalog] analyze_dml_body(
  body : @syntax.SyntaxNode,
  source_bytes : Bytes,
  catalog : T,
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
) -> Unit {
  if body.is_error() || body.is_missing() || has_error_missing(body) {
    diagnostics.push({
      code: "requires-complete-parse",
      message: "refusing to analyze a DML statement with error/missing material",
      start_byte: body.span().start_byte,
      end_byte: body.span().end_byte,
    })
    return
  }
  let tokens = source_tokens(body, source_bytes)
  let words : Array[Bytes] = []
  for t in tokens {
    words.push(t.0)
  }
  let prefix = leading_prefix_end(body.kind(), words)
  if prefix >= tokens.length() {
    return
  }
  let scope : Array[ScopeEntry] = []
  match qualified_ref_at(tokens, prefix) {
    Some((table_ref, next)) => {
      resolve_dml_target(table_ref, catalog, scope, bindings, diagnostics)
      match body.kind() {
        @syntax.SyntaxKind::Update => {
          let set_index = find_word_at_depth0(
            tokens,
            next,
            tokens.length(),
            b"SET",
          )
          if set_index >= 0 {
            let where_index = find_word_at_depth0(
              tokens,
              set_index + 1,
              tokens.length(),
              b"WHERE",
            )
            let set_end = if where_index >= 0 {
              where_index
            } else {
              tokens.length()
            }
            resolve_token_refs(
              slice_tokens(tokens, set_index + 1, set_end),
              scope,
              catalog,
              0,
              bindings,
              diagnostics,
            )
            if where_index >= 0 {
              resolve_token_refs(
                slice_tokens(tokens, where_index + 1, tokens.length()),
                scope,
                catalog,
                0,
                bindings,
                diagnostics,
              )
            }
          }
        }
        @syntax.SyntaxKind::Delete => {
          let where_index = find_word_at_depth0(
            tokens,
            next,
            tokens.length(),
            b"WHERE",
          )
          if where_index >= 0 {
            resolve_token_refs(
              slice_tokens(tokens, where_index + 1, tokens.length()),
              scope,
              catalog,
              0,
              bindings,
              diagnostics,
            )
          }
        }
        @syntax.SyntaxKind::Insert =>
          if next < tokens.length() && tokens[next].0 == b"(" {
            let close = matching_paren(tokens, next)
            if close < tokens.length() {
              resolve_token_refs(
                slice_tokens(tokens, next + 1, close),
                scope,
                catalog,
                0,
                bindings,
                diagnostics,
              )
            }
          }
        @syntax.SyntaxKind::Merge => {
          let set_index = find_word_at_depth0(
            tokens,
            next,
            tokens.length(),
            b"SET",
          )
          if set_index >= 0 {
            resolve_token_refs(
              slice_tokens(tokens, set_index + 1, tokens.length()),
              scope,
              catalog,
              0,
              bindings,
              diagnostics,
            )
          }
        }
        _ => ()
      }
    }
    None => ()
  }
}

///|
/// Analyzes one CREATE VIEW body node: the query body after the optional
/// column list / AS is re-parsed through the existing SELECT analysis, so the
/// body's table and column references bind (D-02). The view name itself is a
/// target table, not a reference, and is not resolved here.
fn[T : Catalog] analyze_create_view_body(
  body : @syntax.SyntaxNode,
  source_bytes : Bytes,
  catalog : T,
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
) -> Unit {
  if body.is_error() || body.is_missing() || has_error_missing(body) {
    diagnostics.push({
      code: "requires-complete-parse",
      message: "refusing to analyze a CREATE VIEW with error/missing material",
      start_byte: body.span().start_byte,
      end_byte: body.span().end_byte,
    })
    return
  }
  let tokens = source_tokens(body, source_bytes)
  let words : Array[Bytes] = []
  for t in tokens {
    words.push(t.0)
  }
  let prefix = leading_prefix_end(body.kind(), words)
  if prefix >= tokens.length() {
    return
  }
  match qualified_ref_at(tokens, prefix) {
    Some((_, after_name)) => {
      let mut query_start = after_name
      // Optional view column list `(a, b)` between the name and AS.
      if query_start < tokens.length() && tokens[query_start].0 == b"(" {
        let close = matching_paren(tokens, query_start)
        if close >= tokens.length() {
          return
        }
        query_start = close + 1
      }
      // Optional AS.
      if query_start < tokens.length() &&
        bytes_equal_ci(tokens[query_start].0, b"AS") {
        query_start = query_start + 1
      }
      if query_start < tokens.length() {
        let body_tokens : Array[(Bytes, Int, Int)] = []
        for i in query_start..<tokens.length() {
          body_tokens.push(tokens[i])
        }
        analyze_select_tokens(
          body_tokens,
          tokens[query_start].1,
          tokens[tokens.length() - 1].2,
          catalog,
          bindings,
          diagnostics,
        )
      }
    }
    None => ()
  }
}

///|
/// Dispatches one statement body node to the SELECT / DML / CREATE VIEW
/// analysis path (D-02). Other statement families are not analyzed.
fn[T : Catalog] analyze_body(
  body : @syntax.SyntaxNode,
  source_bytes : Bytes,
  catalog : T,
  bindings : Array[Binding],
  diagnostics : Array[AnalysisDiagnostic],
) -> Unit {
  match body.kind() {
    @syntax.SyntaxKind::Select =>
      analyze_select_body(body, source_bytes, catalog, bindings, diagnostics)
    @syntax.SyntaxKind::Insert
    | @syntax.SyntaxKind::Update
    | @syntax.SyntaxKind::Delete
    | @syntax.SyntaxKind::Merge =>
      analyze_dml_body(body, source_bytes, catalog, bindings, diagnostics)
    @syntax.SyntaxKind::CreateView =>
      analyze_create_view_body(
        body, source_bytes, catalog, bindings, diagnostics,
      )
    _ => ()
  }
}

///|
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
      @syntax.SyntaxElement::ChildNode(statement_node) =>
        if statement_node.kind() is @syntax.SyntaxKind::Statement {
          for inner in statement_node.children() {
            match inner {
              @syntax.SyntaxElement::ChildNode(body) =>
                analyze_body(body, source_bytes, catalog, bindings, diagnostics)
              @syntax.SyntaxElement::Leaf(_) => ()
            }
          }
        }
      @syntax.SyntaxElement::Leaf(_) => ()
    }
  }
  { bindings, diagnostics }
}
