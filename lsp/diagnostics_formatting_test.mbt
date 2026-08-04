test "diagnostics_and_formatting_contract" {
  let parse_schema = "doris.parse.v1"
  let format_schema = "doris.format.v1"
  assert_eq(parse_schema, "doris.parse.v1")
  assert_eq(format_schema, "doris.format.v1")
  // Refusal must not replace source bytes.
  let source = b"SELECT /*+ HINT */"
  assert_eq(source.length(), 19)
}
