fn main {
  let source = b"select /* js parity */ 1"
  let parsed = @binding.fathom_parse_v1(source, "doris", "4.x", "editor")
  let formatted = @binding.fathom_format_v1(
    source, "doris", "4.x", "strict", "upper", 2, 100, "trailing", "follow", true,
  )
  // Exercise the completion export on the JS target so the A4
  // (raw, dialect, profile, cursor_byte : Int) ABI is exercised end-to-end
  // (TOOL-05, D-04; A6 Int ABI probe on linear-Wasm covered in run_wasm.mbt).
  let completed = @binding.fathom_complete_v1(b"SELECT FRO", "flink", "flink-2.3.0", 9)
  ignore(parsed)
  ignore(formatted)
  ignore(completed)
  ignore(@binding.fathom_capabilities_v1())
}
