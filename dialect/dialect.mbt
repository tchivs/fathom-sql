/// Explicit dialect identity and selection context (DIALECT-01/02/04). The
/// dialect layer is the low-level policy authority: `Dialect`, `DialectContext`
/// and the per-dialect keyword rows live here and nowhere else. source/syntax
/// never depend on it; token/lexer/parser/api consume the context downward
/// (09-RESEARCH.md §4.1).

/// Closed dialect enum: the only selection values (D-01, D-11). Flink is a
/// legal selection value through every public boundary from Phase 9 on, but
/// Flink profiles are rejected until Phase 10 and every Flink parse is an
/// explicit FATHOM-PARSE-008 not-implemented rejection (A1/OQ1) — never a
/// fallback to Doris grammar (DIALECT-03).
pub(all) enum Dialect {
  Doris
  Flink
} derive(Eq, @debug.Debug)

/// Immutable selection context threaded through token/lexer/parser/api: the
/// dialect plus the validated profile/metadata strings identifying the exact
/// released product surface. Field shapes follow the ProfileMetadata pub-field
/// convention (09-PATTERNS.md). `pub(all)` so validated selection strings can
/// be materialized into a context at every public boundary (api ParseOptions,
/// tests, hosts) — cross-package record construction requires pub(all) on the
/// struct (moon 0.1.20260724).
pub(all) struct DialectContext {
  pub dialect : Dialect
  pub profile_id : String
  pub exact_release : String
  pub feature_introduction : String
} derive(Eq, @debug.Debug)
