/// Column-lineage result model (LINE-01, D-01/D-06).
///
/// All spans are flattened byte offsets (never `@source.Span`), mirroring the
/// analyzer's Binding/AnalysisDiagnostic discipline (D-06) and keeping this
/// package's D-21 import contract (only analyzer + syntax).
///
/// Edge/gap ordering is a public contract (Pattern 6): document statement
/// order -> SelectModel branch/CTE order -> SelectItem order -> refs order;
/// star expansion follows scope-entry order x catalog column order
/// (LinkedHashMap determinism). `gaps` and `edges` are strictly separate
/// lists (D-06): a gap is never a tagged edge.

/// One source->target column lineage edge (D-01 expression passthrough).
/// `source_name` is the source spelling of the referenced column;
/// `source_resolved_to` is the canonical column name from the resolved
/// binding; the target is the output column of the SELECT-list item that
/// contains the reference (alias, single-ref name, or star-expanded column).
pub(all) struct LineageEdge {
  pub source_name : String
  pub source_resolved_to : String
  pub source_start_byte : Int
  pub source_end_byte : Int
  pub target_name : String
  pub target_start_byte : Int
  pub target_end_byte : Int
} derive(Eq, @debug.Debug)

/// One honest gap (D-06). `code` is one of `GAP_REQUIRES_CATALOG`,
/// `GAP_UNRESOLVED_REFERENCE`, or `GAP_REQUIRES_COMPLETE_PARSE`.
pub(all) struct LineageGap {
  pub code : String
  pub message : String
  pub start_byte : Int
  pub end_byte : Int
} derive(Eq, @debug.Debug)

/// The result of one `derive_lineage` call: resolved edges plus honest gaps.
pub(all) struct LineageResult {
  pub edges : Array[LineageEdge]
  pub gaps : Array[LineageGap]
} derive(Eq, @debug.Debug)

/// Gap code: a star/`table.*` projection could not be expanded because the
/// catalog does not provide column metadata for its table(s), or an external
/// view has no metadata (D-06 / SC2).
pub const GAP_REQUIRES_CATALOG : String = "requires-catalog"

/// Gap code: a name reference could not be resolved (unknown table/column/
/// function, or an ambiguous reference — merged per Open Question 2).
pub const GAP_UNRESOLVED_REFERENCE : String = "unresolved-reference"

/// Gap code: the statement body carries error/missing material and lineage
/// derivation refuses to analyze it (D-33 refusal philosophy).
pub const GAP_REQUIRES_COMPLETE_PARSE : String = "requires-complete-parse"
