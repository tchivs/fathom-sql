/// Name resolution for SELECT bodies over the flat token-leaf CST (D-01).
///
/// `analyze` walks a parsed document's Statement children, re-parses each
/// SELECT body via select_parser.mbt, and resolves table/column references
/// against the injected catalog. Matching is parsing-time ASCII case-fold
/// (D-03); quoted identifiers go through the same Catalog::table case-fold
/// path and then a byte-exact re-check of the returned TableInfo.name —
/// StaticCatalog::lookup_exact is never called here (it is not a Catalog
/// trait method). Catalog metadata is untrusted and only consumed (T-02-42);
/// the syntax-only valid/diagnostic channel is never touched (ANLY-01).

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

/// Case-insensitive column lookup within a resolved table (D-03).
fn resolve_column(info : TableInfo, name : String) -> ColumnInfo? {
  for col in info.columns {
    if col.name.equal_ignore_ascii_case(name) {
      return Some(col)
    }
  }
  None
}

/// Resolves one FROM table reference. Quoted identifiers pass through the
/// case-fold Catalog::table lookup and then a byte-exact re-check of the
/// returned TableInfo.name against the quoted spelling (D-03).
fn[T : Catalog] resolve_table_ref(catalog : T, name_text : String, quoted : Bool) -> TableInfo? {
  match Catalog::table(catalog, name_text) {
    Some(info) =>
      if quoted {
        if info.name == name_text { Some(info) } else { None }
      } else {
        Some(info)
      }
    None => None
  }
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
  let core = match split_select_clauses(tokens) {
    Some(core) => core
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
  // FROM clause: resolve table references first.
  let resolved_tables : Array[TableInfo] = []
  for from_item in core.from {
    let name_text = identifier_text(from_item.name.bytes)
    let quoted = is_quoted(from_item.name.bytes)
    match resolve_table_ref(catalog, name_text, quoted) {
      Some(info) => {
        bindings.push({
          kind: BindingKind::Table,
          name: name_text,
          resolved_to: info.name,
          data_type: "",
          start_byte: from_item.name.start_byte,
          end_byte: from_item.name.end_byte,
        })
        resolved_tables.push(info)
      }
      None => {
        diagnostics.push({
          code: "unknown-table",
          message: "table not found in catalog: \{name_text}",
          start_byte: from_item.name.start_byte,
          end_byte: from_item.name.end_byte,
        })
      }
    }
  }
  // SELECT list: resolve bare column identifiers against the single resolved
  // table (D-04 binding types). Multi-table / alias resolution is 05-03.
  if resolved_tables.length() == 1 {
    let info = resolved_tables[0]
    for item in core.select_list {
      if item.tokens.length() == 1 {
        let token = item.tokens[0]
        let name_text = identifier_text(token.bytes)
        if is_identifier_token(token.bytes) {
          match resolve_column(info, name_text) {
            Some(col) => {
              bindings.push({
                kind: BindingKind::Column,
                name: name_text,
                resolved_to: col.name,
                data_type: col.data_type,
                start_byte: token.start_byte,
                end_byte: token.end_byte,
              })
            }
            None => ()
            // unknown-column diagnostics land with 05-03; the tracer only
            // resolves identifiers that exist in the catalog.
          }
        }
      }
    }
  }
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
