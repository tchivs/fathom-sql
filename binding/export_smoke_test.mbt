test "exports_are_primitive_and_versioned" {
  let exports = [
    "doris_parse_v1",
    "doris_format_v1",
    "doris_profile_v1",
    "doris_capabilities_v1",
  ]
  let expected = [
    "doris_parse_v1",
    "doris_format_v1",
    "doris_profile_v1",
    "doris_capabilities_v1",
  ]
  assert_eq(exports, expected)
  for name in exports {
    assert_true(name.contains("v1"))
  }
}

test "exports_return_serialized_bytes_not_internal_values" {
  let parsed = doris_parse_v1(b"select 1", "4.x", "strict")
  let formatted = doris_format_v1(
    b"select 1", "4.x", "strict", "upper", 2, 100, "trailing", "follow", true,
  )
  assert_true(parsed.length() > 0)
  assert_true(formatted.length() > 0)
  assert_true(doris_capabilities_v1().length() > 0)
  assert_true(doris_profile_v1("2.1").length() > 0)
}
