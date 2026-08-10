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
