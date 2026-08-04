test "exports_are_primitive_and_versioned" {
  let exports = ["doris_parse_v1", "doris_format_v1"]
  let expected = ["doris_parse_v1", "doris_format_v1"]
  assert_eq(exports.length(), 2)
  assert_eq(exports, expected)
  assert_eq(exports[0], "doris_parse_v1")
  assert_eq(exports[1], "doris_format_v1")
  assert_true(exports[0].contains("v1"))
  assert_true(exports[1].contains("v1"))
}
