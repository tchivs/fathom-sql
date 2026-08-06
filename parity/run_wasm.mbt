// No println/env/host IO: linear-Wasm remains portable and primitive-only.
fn main {
  let source = b"select /* wasm parity */ 1"
  let parsed = @binding.fathom_parse_v1(source, "doris", "4.x", "editor")
  let formatted = @binding.fathom_format_v1(
    source, "doris", "4.x", "strict", "upper", 2, 100, "trailing", "follow", true,
  )
  ignore(parsed)
  ignore(formatted)
  ignore(@binding.doris_capabilities_v1())
}
