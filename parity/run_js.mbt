///|
fn main {
  let source = b"select /* js parity */ 1"
  let parsed = @binding.fathom_parse_v1(source, "doris", "4.x", "editor")
  let formatted = @binding.fathom_format_v1(
    source, "doris", "4.x", "strict", "upper", 2, 100, "trailing", "follow", true,
  )
  // Exercise the completion export on the JS target so the A4
  // (raw, dialect, profile, cursor_byte : Int) ABI is exercised end-to-end
  // (TOOL-05, D-04; A6 Int ABI probe on linear-Wasm covered in run_wasm.mbt).
  let completed = @binding.fathom_complete_v1(
    b"SELECT FRO", "flink", "flink-2.3.0", 9,
  )
  // LINT-01 / FING-01 wire exports (06-03/06-01): smoke the Bytes+Int ABI so
  // the JS target confirms fathom_lint_v1 / fathom_fingerprint_v1 symbols
  // exist and accept their parameters (Pitfall 8).
  let linted = @binding.fathom_lint_v1(
    b"SELECT 1", "doris", "4.x", "strict", b"[]", false,
  )
  let fingerprinted = @binding.fathom_fingerprint_v1(
    b"SELECT 1", "doris", "4.x", "strict",
  )
  // LINE-01 wire export (07-04): smoke the Bytes+String+Int ABI so the JS
  // target confirms fathom_lineage_v1 exists and accepts its parameters
  // (catalog_json empty bytes = no catalog; Pitfall 8).
  let lineaged = @binding.fathom_lineage_v1(
    b"SELECT a FROM t", "doris", "4.x", "strict", b"",
  )
  ignore(parsed)
  ignore(formatted)
  ignore(completed)
  ignore(linted)
  ignore(fingerprinted)
  ignore(lineaged)
  ignore(@binding.fathom_capabilities_v1())
}
