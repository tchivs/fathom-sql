/// In-memory view registry and catalog wrapper (D-03 / Pattern 2).
///
/// The registry maps each in-document CREATE VIEW's output column names to the
/// view name. `ViewCatalog[T]` wraps an injected catalog so `FROM v` resolves
/// to the view's columns before delegating to the inner catalog — a same-name
/// view shadows a catalog table (Pitfall 4). Views live only in the default-db
/// namespace (A3): `table_in_db`/`function` delegate to the inner catalog.
///
/// Registry build: each CREATE VIEW body is located via the analyzer's public
/// `view_body_location`, re-parsed with `split_select_model`, and its first
/// branch's output columns are computed (alias -> single-ref column name ->
/// star-expanded bindings from a pass-1 analysis). View chains whose bodies
/// reference earlier views resolve through the accumulating registry at
/// analysis time; a star-over-view in a registry build (pass 1 uses only the
/// inner catalog) is a documented limitation — such a view reports zero output
/// columns and a referencing `SELECT *` yields a requires-catalog gap.

/// Token index just past the CREATE VIEW leading-keyword prefix (mirror of
/// the analyzer's `view_body_location` prefix scan; needed to recover the
/// view name itself).
fn view_prefix_end(tokens : Array[(Bytes, Int, Int)]) -> Int {
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
  prefix
}

/// The dotted name of a CREATE VIEW statement, or None when unrecoverable.
fn view_name(tokens : Array[(Bytes, Int, Int)]) -> String? {
  let prefix = view_prefix_end(tokens)
  match @analyzer.qualified_ref_at(tokens, prefix) {
    Some((ref, _)) => Some(dotted_name(ref))
    None => None
  }
}

/// Output columns of a view body's first branch (D-03): alias first, else the
/// single-ref column name, else star-expanded Column bindings (from the
/// pass-1 analysis). `data_type` is "" where unknown.
fn view_output_columns(
  model : @analyzer.SelectModel,
  bindings : Array[@analyzer.Binding],
) -> Array[@analyzer.ColumnInfo] {
  let out : Array[@analyzer.ColumnInfo] = []
  if model.branches.length() == 0 {
    return out
  }
  let core = model.branches[0]
  for item in core.select_list {
    if item.star {
      let (ss, se) = star_span(item)
      for col in column_bindings_at(bindings, ss, se) {
        out.push({ name: col.resolved_to, data_type: col.data_type })
      }
    } else {
      let (name, _, _) = item_target(item, bindings)
      if name != "" {
        out.push({ name: name, data_type: "" })
      }
    }
  }
  out
}

/// Builds the in-document view registry: walks CreateView bodies in document
/// order and maps each view name to its output columns (D-03).
fn build_view_registry(
  root : @syntax.SyntaxNode,
  source_bytes : Bytes,
  bindings : Array[@analyzer.Binding],
) -> Map[String, Array[@analyzer.ColumnInfo]] {
  let registry : Map[String, Array[@analyzer.ColumnInfo]] = Map([])
  for element in root.children() {
    match element {
      @syntax.SyntaxElement::ChildNode(statement_node) => {
        if statement_node.kind() is @syntax.SyntaxKind::Statement {
          for inner in statement_node.children() {
            match inner {
              @syntax.SyntaxElement::ChildNode(body) => {
                if body.kind() is @syntax.SyntaxKind::CreateView {
                  let tokens = @analyzer.source_tokens(body, source_bytes)
                  match view_name(tokens) {
                    Some(name) => {
                      let query_start = @analyzer.view_body_location(tokens)
                      let body_tokens = sub_tokens(tokens, query_start, tokens.length())
                      match @analyzer.split_select_model(body_tokens) {
                        Some(model) => {
                          registry.set(name, view_output_columns(model, bindings))
                        }
                        None => ()
                      }
                    }
                    None => ()
                  }
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
  registry
}

/// Case-insensitive view-registry lookup returning the stored (author-casing)
/// key alongside the columns, so the resolve layer's quoted byte-recheck
/// compares against the stored view name (D-03, Pitfall 4).
fn view_lookup(
  m : Map[String, Array[@analyzer.ColumnInfo]],
  name : String,
) -> (String, Array[@analyzer.ColumnInfo])? {
  for kv in m.to_array() {
    if kv.0.equal_ignore_ascii_case(name) {
      return Some((kv.0, kv.1))
    }
  }
  None
}

/// View registry + inner catalog wrapper (D-03 / Pattern 2). `views` maps a
/// view name (author casing preserved) to its output columns; lookup is
/// parsing-time ASCII case-fold with the resolve layer's quoted byte-recheck
/// against the returned `TableInfo.name`.
pub struct ViewCatalog[T] {
  pub views : Map[String, Array[@analyzer.ColumnInfo]]
  pub inner : T
}

/// `table` consults the view registry first (case-fold hit -> view output
/// columns as a TableInfo), then delegates to the inner catalog. A same-name
/// view shadows a catalog table (Pitfall 4).
pub impl[T : @analyzer.Catalog] @analyzer.Catalog for ViewCatalog[T] with table(self, name) {
  match view_lookup(self.views, name) {
    Some((key, cols)) => Some({ name: key, columns: cols })
    None => self.inner.table(name)
  }
}

/// Views live only in the default-db namespace (A3): db-qualified lookups
/// delegate to the inner catalog.
pub impl[T : @analyzer.Catalog] @analyzer.Catalog for ViewCatalog[T] with table_in_db(self, db, name) {
  self.inner.table_in_db(db, name)
}

/// Function lookups delegate to the inner catalog (views carry no functions).
pub impl[T : @analyzer.Catalog] @analyzer.Catalog for ViewCatalog[T] with function(self, name) {
  self.inner.function(name)
}
