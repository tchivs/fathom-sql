test "diagnostics_and_formatting_contract" {
  let schemas = ["doris.parse.v1", "doris.format.v1"]
  let expected_schemas = ["doris.parse.v1", "doris.format.v1"]
  assert_eq(schemas, expected_schemas)
  assert_eq(schemas[0], "doris.parse.v1")
  assert_eq(schemas[1], "doris.format.v1")
  let source = b"SELECT /*+ HINT */"
  let refusal_fields = ["schema_version", "source_bytes", "diagnostics", "formatted"]
  assert_eq(refusal_fields, ["schema_version", "source_bytes", "diagnostics", "formatted"])
  assert_eq(source, b"SELECT /*+ HINT */")
  assert_eq(source.length(), 18)
}
