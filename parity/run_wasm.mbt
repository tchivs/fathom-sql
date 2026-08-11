// No println/env/host IO: linear-Wasm remains portable and primitive-only.
fn main {
  let source = b"select /* wasm parity */ 1"
  let parsed = @binding.fathom_parse_v1(source, "doris", "4.x", "editor")
  let formatted = @binding.fathom_format_v1(
    source, "doris", "4.x", "strict", "upper", 2, 100, "trailing", "follow", true,
  )
  // Exercise the completion export on linear-Wasm so the cursor_byte : Int
  // parameter ABI is confirmed (TOOL-05, D-04; A6 probe). Three-target byte
  // identity is proven by the parity suite + compare_backends.py (PARITY-02).
  let completed = @binding.fathom_complete_v1(b"SELECT FRO", "flink", "flink-2.3.0", 9)
  // LINT-01 / FING-01 wire exports (06-03/06-01): smoke the Bytes+Int ABI on
  // linear-Wasm so fathom_lint_v1 / fathom_fingerprint_v1 symbols exist and
  // accept their parameters (Pitfall 8).
  let linted = @binding.fathom_lint_v1(b"SELECT 1", "doris", "4.x", "strict", b"[]", false)
  let fingerprinted = @binding.fathom_fingerprint_v1(b"SELECT 1", "doris", "4.x", "strict")
  ignore(parsed)
  ignore(formatted)
  ignore(completed)
  ignore(linted)
  ignore(fingerprinted)
  ignore(@binding.fathom_capabilities_v1())
}
