/// Analyzer-internal SELECT model (D-01). The analyzer re-parses the flat
/// token-leaf CST into its own clause structure instead of depending on CST
/// sub-nodes (syntax/SyntaxKind only has coarse statement families). This file
/// fixes the model shape; plan 05-03 fills the unpopulated clauses. No
/// SyntaxKind is added and syntax/syntax.mbt is untouched (D-01, Phase 12
/// frozen parser hard gate).

/// Top-level SELECT clause kinds recognized by the re-parser (D-01).
enum ClauseKind {
  SelectList
  From
  Where
  GroupBy
  Having
  Qualify
  OrderBy
  Limit
  Window
  SetOpUnion
} derive(Eq, @debug.Debug)

/// A token slice: token bytes plus a flattened byte span (D-01/D-06).
struct TokenSlice {
  bytes : Bytes
  start_byte : Int
  end_byte : Int
}

/// One SELECT-list item: the token slice(s) of the projection expression.
struct SelectItem {
  tokens : Array[TokenSlice]
}

/// One FROM item: the table reference (name token slice; alias handling and
/// JOIN structure land in 05-03).
struct FromItem {
  name : TokenSlice
}

/// A CTE definition (shape only; body filled by 05-03).
struct CteDef {
  name : String
  alias : String?
  body : SelectCore
}

/// One SELECT core: per-clause token slices produced by the re-parser. Only
/// SelectList and From are populated by this plan's tracer; the remaining
/// clauses stay empty until 05-03 expands the re-parser.
struct SelectCore {
  select_list : Array[SelectItem]
  from : Array[FromItem]
  where_tokens : Array[TokenSlice]
  group_by : Array[TokenSlice]
  having : Array[TokenSlice]
  qualify : Array[TokenSlice]
  order_by : Array[TokenSlice]
  limit : Array[TokenSlice]
  window : Array[TokenSlice]
}

/// The model of a full SELECT statement: CTEs plus set-op branches.
struct SelectModel {
  ctes : Array[CteDef]
  branches : Array[SelectCore]
}
