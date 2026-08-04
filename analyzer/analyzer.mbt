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

/// Minimal table -> columns lookup contract (D-22). Implementors answer
/// whether a table exists and what its columns are; they never influence
/// syntax parsing or the syntax-only valid channel. `open` so consumers can
/// implement it for their own metadata sources.
pub(open) trait Catalog {
  table(Self, String) -> TableInfo?
}

/// Concrete in-memory catalog backed by a name-keyed map. Keys are
/// case-sensitive for now (documented): "t" and "T" are distinct tables.
pub struct StaticCatalog {
  tables : Map[String, TableInfo]
}

/// Builds a catalog from the given entries; later entries with the same name
/// overwrite earlier ones (last-wins, documented).
pub fn StaticCatalog::new(entries : Array[TableInfo]) -> StaticCatalog {
  let tables : Map[String, TableInfo] = Map([])
  for entry in entries {
    tables.set(entry.name, entry)
  }
  { tables: tables }
}

/// Direct map lookup: returns the entry for `name` or None when absent.
pub fn StaticCatalog::lookup(self : StaticCatalog, name : String) -> TableInfo? {
  self.tables.get(name)
}

pub impl Catalog for StaticCatalog with table(self, name) {
  self.lookup(name)
}

// ---------------------------------------------------------------------------
// Statement-level target-table resolution over syntax read views (D-22)
// ---------------------------------------------------------------------------
//
// resolve_table_references walks the Statement children of a parsed document
// root and, for each DML/DDL statement kind shipped by 02-01/02-02 (Insert,
// Update, Delete, Merge, CreateTable), collects the target table-name token
// text and returns only the names whose catalog lookup succeeds. Missing
// tables are simply absent from the result — name-resolution level only, no
// diagnostics, no type inference (D-22/D-24).
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
/// CREATE TEMPORARY/EXTERNAL TABLE, IF NOT EXISTS) are consumed when present.
fn leading_prefix_end(kind : @syntax.SyntaxKind, tokens : Array[Bytes]) -> Int {
  let length = tokens.length()
  let mut position = 0
  match kind {
    @syntax.SyntaxKind::Insert => {
      // INSERT ( OVERWRITE TABLE | INTO ) name
      if position < length && bytes_equal_ci(tokens[position], b"INSERT") {
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
/// Statements of other kinds (SELECT, CREATE VIEW/INDEX/MATERIALIZED VIEW,
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
                  @syntax.SyntaxKind::CreateTable => {
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
