/// Optional name-resolution-level analyzer package (D-21..D-24).
///
/// Boundary contract:
/// - This package consumes ONLY syntax read views (`@syntax.SyntaxNode`) plus
///   caller-provided source bytes. It never imports parser, token, lexer, api,
///   or source — and the parser package must never import this package
///   (D-21, research Pitfall 7; enforced by a negative gate on parser/moon.pkg).
/// - Catalog metadata is caller-injected and untrusted (T-02-42). It is
///   consumed only by this package and NEVER reaches the parser or the
///   syntax-only valid/diagnostic channel: parsing a document without a
///   catalog yields byte-identical syntax results (ANLY-01).
/// - This phase delivers the interface, documentation, and a minimal
///   implementation only: a table -> column-name lookup (D-22) and
///   statement-level target-table resolution for the DML/DDL kinds shipped in
///   02-01/02-02. No type inference, no FE execution semantics (D-24).
/// - Full ANAL-01 name resolution and type diagnostics are v2, not promised
///   here; catalog diagnostics are a separate caller-side result channel.

/// One catalog column: name plus a Doris type string (metadata only — the
/// analyzer performs no type inference or type checking this phase).
/// `pub(all)` so catalog consumers can construct entries from their own
/// metadata (repo precedent: `pub(all) struct Token` in token/token.mbt).
pub(all) struct ColumnInfo {
  name : String
  data_type : String
}

/// One catalog table: name plus its column list. The record field set is
/// deliberately minimal (D-22); the planner/executor may extend it in v2
/// alongside full ANAL-01 resolution.
pub(all) struct TableInfo {
  name : String
  columns : Array[ColumnInfo]
}

/// Name-resolution contract (D-22 extended by D-05). Implementors answer
/// whether a table/function exists and what its columns/signature are; they
/// never influence syntax parsing or the syntax-only valid channel. `open` so
/// consumers can implement it for their own metadata sources.
///
/// The method set is a one-way public contract (D-05): adding a method breaks
/// external implementors, so the full set is frozen at once — the plain table
/// lookup, the db-qualified path, and the function registry.
pub(open) trait Catalog {
  table(Self, String) -> TableInfo?
  table_in_db(Self, db : String, name : String) -> TableInfo?
  function(Self, String) -> FunctionInfo?
}

/// Concrete in-memory catalog backed by name-keyed maps. Lookup matches with
/// parsing-time ASCII case-fold (D-03): `lookup("T")` hits a key "t"; quoted
/// identifiers match exactly (byte-for-byte) instead.
pub struct StaticCatalog {
  tables : Map[String, TableInfo]
  db_tables : Map[String, Map[String, TableInfo]]
  functions : Map[String, FunctionInfo]
}

/// Builds a catalog from the given entries; later entries with the same name
/// overwrite earlier ones (last-wins, documented).
pub fn StaticCatalog::new(entries : Array[TableInfo]) -> StaticCatalog {
  let tables : Map[String, TableInfo] = Map([])
  for entry in entries {
    tables.set(entry.name, entry)
  }
  { tables: tables, db_tables: Map([]), functions: Map([]) }
}

/// Returns a copy of this catalog with `table` additionally registered under
/// the named database scope (D-05). Keys keep author casing; resolution folds
/// ASCII case at lookup time (D-03).
pub fn StaticCatalog::with_db(
  self : StaticCatalog,
  db : String,
  name : String,
  table : TableInfo,
) -> StaticCatalog {
  let db_tables = self.db_tables.copy()
  let scope = match db_tables.get(db) {
    Some(scope) => scope.copy()
    None => Map([])
  }
  scope.set(name, table)
  db_tables.set(db, scope)
  { tables: self.tables, db_tables: db_tables, functions: self.functions }
}

/// Returns a copy of this catalog with `info` registered in the function
/// registry (D-05).
pub fn StaticCatalog::with_function(
  self : StaticCatalog,
  name : String,
  info : FunctionInfo,
) -> StaticCatalog {
  let functions = self.functions.copy()
  functions.set(name, info)
  { tables: self.tables, db_tables: self.db_tables, functions: functions }
}

/// Case-insensitive scan of a String-keyed map (parsing-time ASCII case-fold,
/// D-03): the first key that folds equal to `name` wins.
fn[V] case_insensitive_get(m : Map[String, V], name : String) -> V? {
  let mut result : V? = None
  for kv in m.to_array() {
    if kv.0.equal_ignore_ascii_case(name) {
      result = Some(kv.1)
      break
    }
  }
  result
}

/// Direct map lookup with parsing-time ASCII case-fold (D-03): `lookup("T")`
/// hits a catalog entry keyed "t". Quoted identifiers never use this path —
/// they resolve via the case-fold hit plus a byte-exact re-check on
/// `TableInfo.name` at the resolve layer.
pub fn StaticCatalog::lookup(self : StaticCatalog, name : String) -> TableInfo? {
  case_insensitive_get(self.tables, name)
}

/// Byte-exact (case-sensitive) lookup: the only path that does not fold ASCII
/// case. Exists for direct unit-testing of quoted-identifier semantics (D-03)
/// and is NOT a Catalog trait method, so the generic resolve path can never
/// call it.
pub fn StaticCatalog::lookup_exact(self : StaticCatalog, name : String) -> TableInfo? {
  self.tables.get(name)
}

/// Case-insensitive lookup within a named database scope (D-05). Returns None
/// when the database or table is absent.
pub fn StaticCatalog::lookup_in_db(self : StaticCatalog, db : String, name : String) -> TableInfo? {
  match self.db_tables.get(db) {
    Some(scope) => case_insensitive_get(scope, name)
    None => None
  }
}

/// Case-insensitive function-registry lookup (D-05).
pub fn StaticCatalog::lookup_function(self : StaticCatalog, name : String) -> FunctionInfo? {
  case_insensitive_get(self.functions, name)
}

pub impl Catalog for StaticCatalog with table(self, name) {
  self.lookup(name)
}

pub impl Catalog for StaticCatalog with table_in_db(self, db, name) {
  self.lookup_in_db(db, name)
}

pub impl Catalog for StaticCatalog with function(self, name) {
  self.lookup_function(name)
}

// ---------------------------------------------------------------------------
// Statement-level target-table resolution over syntax read views (D-22)
// ---------------------------------------------------------------------------
//
// resolve_table_references walks the Statement children of a parsed document
// root and, for each DML/DDL statement kind shipped by 02-01/02-02 (Insert,
// Update, Delete, Merge, CreateTable) plus the Flink CreateView family
// (D-03), collects the target table-name token text and returns only the
// names whose catalog lookup succeeds. Missing tables are simply absent from
// the result — name-resolution level only, no diagnostics, no type inference
// (D-22/D-24).
//
// The CST never owns source bytes (syntax/syntax.mbt invariant), so the
// caller supplies the source bytes alongside the syntax root; leaf text is
// recovered via the source slice. The walk is read-only and consumes only
// `@syntax.SyntaxNode` read views; the parser is never involved.

/// Case-folded byte comparison (ASCII), mirroring parser.mbt `bytes_equal_ci`.
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

/// UTF-8 decode of a byte slice into a String (lossy: malformed bytes become
/// U+FFFD). The analyzer package deliberately keeps its import list to syntax
/// read views only (D-21), so this small decoder replaces the @encoding/utf8
/// core package for identifier text extraction.
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

/// Source-token leaf texts of a node in source order (trivia, error, and
/// skipped leaves are ignored; only SourceToken leaves carry grammar tokens).
fn source_token_texts(node : @syntax.SyntaxNode, source_bytes : Bytes) -> Array[Bytes] {
  let texts : Array[Bytes] = []
  for element in node.children() {
    match element {
      @syntax.SyntaxElement::Leaf(leaf) => {
        if leaf.kind is @syntax.LeafKind::SourceToken {
          let start = leaf.span.start_byte
          let end = leaf.span.end_byte
          if start >= 0 && start <= end && end <= source_bytes.length() {
            texts.push(source_bytes[start:end].to_owned())
          }
        }
      }
      @syntax.SyntaxElement::ChildNode(_) => ()
    }
  }
  texts
}

/// Returns the token index just past the statement-specific leading keyword
/// sequence (case-insensitive). Optional words (INSERT OVERWRITE TABLE,
/// UPSERT INTO, CREATE TEMPORARY/EXTERNAL TABLE, CREATE [TEMPORARY] VIEW,
/// IF NOT EXISTS) are consumed when present. Flink leading-prefix shapes
/// (UPSERT INTO, CREATE [TEMPORARY] VIEW) share these arms with Doris (D-03).
fn leading_prefix_end(kind : @syntax.SyntaxKind, tokens : Array[Bytes]) -> Int {
  let length = tokens.length()
  let mut position = 0
  match kind {
    @syntax.SyntaxKind::Insert => {
      // ( INSERT | UPSERT ) ( OVERWRITE [TABLE] | INTO ) name
      // UPSERT is the Flink RichSqlInsert form; the Flink parser maps UPSERT
      // to SyntaxKind::Insert (parser.mbt:4196), so the Insert arm must
      // recognize the UPSERT leading keyword too. Doris forms unchanged.
      if position < length && (bytes_equal_ci(tokens[position], b"INSERT") ||
        bytes_equal_ci(tokens[position], b"UPSERT")) {
        position = position + 1
      }
      if position < length && bytes_equal_ci(tokens[position], b"OVERWRITE") {
        position = position + 1
        if position < length && bytes_equal_ci(tokens[position], b"TABLE") {
          position = position + 1
        }
      } else {
        if position < length && bytes_equal_ci(tokens[position], b"INTO") {
          position = position + 1
        }
      }
    }
    @syntax.SyntaxKind::Update => {
      if position < length && bytes_equal_ci(tokens[position], b"UPDATE") {
        position = position + 1
      }
    }
    @syntax.SyntaxKind::Delete => {
      if position < length && bytes_equal_ci(tokens[position], b"DELETE") {
        position = position + 1
      }
      if position < length && bytes_equal_ci(tokens[position], b"FROM") {
        position = position + 1
      }
    }
    @syntax.SyntaxKind::Merge => {
      if position < length && bytes_equal_ci(tokens[position], b"MERGE") {
        position = position + 1
      }
      if position < length && bytes_equal_ci(tokens[position], b"INTO") {
        position = position + 1
      }
    }
    @syntax.SyntaxKind::CreateTable => {
      if position < length && bytes_equal_ci(tokens[position], b"CREATE") {
        position = position + 1
      }
      if position < length && bytes_equal_ci(tokens[position], b"TEMPORARY") {
        position = position + 1
      }
      if position < length && bytes_equal_ci(tokens[position], b"EXTERNAL") {
        position = position + 1
      }
      if position < length && bytes_equal_ci(tokens[position], b"TABLE") {
        position = position + 1
      }
      if position < length && bytes_equal_ci(tokens[position], b"IF") {
        position = position + 1
      }
      if position < length && bytes_equal_ci(tokens[position], b"NOT") {
        position = position + 1
      }
      if position < length && bytes_equal_ci(tokens[position], b"EXISTS") {
        position = position + 1
      }
    }
    @syntax.SyntaxKind::CreateView => {
      // CREATE [TEMPORARY] VIEW [IF NOT EXISTS] name (Flink SqlCreateView).
      // The Flink parser resolves CREATE [TEMPORARY] VIEW to
      // SyntaxKind::CreateView via flink_create_form_kind (parser.mbt:4065).
      if position < length && bytes_equal_ci(tokens[position], b"CREATE") {
        position = position + 1
      }
      if position < length && bytes_equal_ci(tokens[position], b"TEMPORARY") {
        position = position + 1
      }
      if position < length && bytes_equal_ci(tokens[position], b"VIEW") {
        position = position + 1
      }
      if position < length && bytes_equal_ci(tokens[position], b"IF") {
        position = position + 1
      }
      if position < length && bytes_equal_ci(tokens[position], b"NOT") {
        position = position + 1
      }
      if position < length && bytes_equal_ci(tokens[position], b"EXISTS") {
        position = position + 1
      }
    }
    _ => ()
  }
  position
}

/// Target table name of one DML/DDL statement node: the qualified name
/// (identifier [ "." identifier ]*) immediately following the leading
/// keywords. Returns None when the name cannot be recovered (e.g. an
/// incomplete statement with no name token).
fn target_table_name(node : @syntax.SyntaxNode, source_bytes : Bytes) -> String? {
  let tokens = source_token_texts(node, source_bytes)
  let length = tokens.length()
  let mut position = leading_prefix_end(node.kind(), tokens)
  if position >= length {
    return None
  }
  let mut name = tokens[position]
  position = position + 1
  while position + 1 < length && tokens[position] == b"." {
    name = name + b"." + tokens[position + 1]
    position = position + 2
  }
  Some(utf8_to_string(name))
}

/// Resolves the target tables of a parsed document's DML/DDL statements
/// against the injected catalog, returning only the names present in the
/// catalog (missing tables are simply absent — name-resolution level only).
/// Supported statement families: Insert (including the Flink UPSERT INTO
/// form), Update, Delete, Merge, CreateTable, and CreateView (D-03).
/// Statements of other kinds (SELECT, CREATE INDEX/MATERIALIZED VIEW,
/// Error nodes) are ignored. The syntax-only parse path is never consulted:
/// the same parse with no catalog yields identical results (ANLY-01).
pub fn[T : Catalog] resolve_table_references(
  node : @syntax.SyntaxNode,
  source_bytes : Bytes,
  catalog : T,
) -> Array[String] {
  let resolved : Array[String] = []
  for element in node.children() {
    match element {
      @syntax.SyntaxElement::ChildNode(statement_node) => {
        if statement_node.kind() is @syntax.SyntaxKind::Statement {
          for inner in statement_node.children() {
            match inner {
              @syntax.SyntaxElement::ChildNode(body) => {
                match body.kind() {
                  @syntax.SyntaxKind::Insert | @syntax.SyntaxKind::Update |
                  @syntax.SyntaxKind::Delete | @syntax.SyntaxKind::Merge |
                  @syntax.SyntaxKind::CreateTable |
                  @syntax.SyntaxKind::CreateView => {
                    match target_table_name(body, source_bytes) {
                      Some(name) => {
                        match Catalog::table(catalog, name) {
                          Some(_) => resolved.push(name)
                          None => ()
                        }
                      }
                      None => ()
                    }
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
  resolved
}
