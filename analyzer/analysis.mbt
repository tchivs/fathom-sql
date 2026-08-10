/// Analyzer result and catalog model records (D-05/D-06).
///
/// All span values are flattened `start_byte`/`end_byte` Ints (never
/// `@source.Span`), so this package keeps its D-21 import contract (only
/// `fathom/sql/syntax`) while staying serialization-friendly — mirroring
/// `api.PrimitiveDiagnostic` (api.mbt:305-313). Catalog metadata is
/// caller-injected and untrusted (T-02-42); it is consumed only by the
/// analyzer and never reaches the syntax-only valid/diagnostic channel
/// (ANLY-01).

/// One catalog function signature (D-05). `min_arity` supports arity checks:
/// an argument count below `min_arity` or above `param_types.length()` is a
/// mismatch. `param_types` and `return_type` are opaque type strings (D-04).
pub(all) struct FunctionInfo {
  name : String
  param_types : Array[String]
  return_type : String
  min_arity : Int
} derive(Eq, @debug.Debug)

/// The kind of a resolved name binding (D-06).
pub(all) enum BindingKind {
  Table
  Column
  Function
  Cte
  Alias
} derive(Eq, @debug.Debug)

/// One resolved name binding. `name` preserves the source spelling (D-03);
/// `resolved_to` is the author's display name from the catalog/scope;
/// `data_type` carries the column/function type (D-04) and is empty for
/// Table/Cte/Alias. Spans are flattened byte offsets (D-01/D-06).
pub(all) struct Binding {
  kind : BindingKind
  name : String
  resolved_to : String
  data_type : String
  start_byte : Int
  end_byte : Int
} derive(Eq, @debug.Debug)

/// A catalog/scope diagnostic on the analyzer's own channel (D-04): it never
/// enters the syntax-only valid/diagnostic channel (ANLY-01). Codes are
/// analyzer-internal stable strings ("unknown-table", "requires-complete-parse"),
/// not FATHOM-* public codes (D-06).
pub(all) struct AnalysisDiagnostic {
  code : String
  message : String
  start_byte : Int
  end_byte : Int
} derive(Eq, @debug.Debug)

/// The result of analyzing one parsed document: resolved bindings plus
/// analyzer-channel diagnostics (D-06).
pub(all) struct AnalysisResult {
  bindings : Array[Binding]
  diagnostics : Array[AnalysisDiagnostic]
} derive(Eq, @debug.Debug)
