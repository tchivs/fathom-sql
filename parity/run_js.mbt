fn main {
  let source = b"select /* js parity */ 1"
  let parsed = @binding.doris_parse_v1(source, "4.x", "editor")
  let formatted = @binding.doris_format_v1(
    source, "4.x", "strict", "upper", 2, 100, "trailing", "follow", true,
  )
  ignore(parsed)
  ignore(formatted)
  ignore(@binding.doris_capabilities_v1())
}
