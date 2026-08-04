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
