test "exports_are_primitive_and_versioned" {
  let parsed = @binding.doris_parse_v1(b"select 1", "4.x", "strict")
  let formatted = @binding.doris_format_v1(
    b"select 1", "4.x", "strict", "upper", 2, 100, "trailing", "follow", true,
  )
  let profile = @binding.doris_profile_v1("2.1")
  let capabilities = @binding.doris_capabilities_v1()
  assert_true(parsed.length() > 0)
  assert_true(formatted.length() > 0)
  assert_true(profile.length() > 0)
  assert_true(capabilities.length() > 0)
  let parsed_text = @utf8.decode_lossy(parsed[:])
  let formatted_text = @utf8.decode_lossy(formatted[:])
  let profile_text = @utf8.decode_lossy(profile[:])
  let capabilities_text = @utf8.decode_lossy(capabilities[:])
  assert_true(parsed_text.contains("doris.parse.v1"))
  assert_true(parsed_text.contains("\"source_bytes\":[115,101,108,101,99,116,32,49]"))
  assert_true(!parsed_text.contains("ParseResult"))
  assert_true(formatted_text.contains("doris.format.v1"))
  assert_true(formatted_text.contains("\"source_bytes\":"))
  assert_true(!formatted_text.contains("FormatResult"))
  assert_true(profile_text.contains("doris.profile.v1"))
  assert_true(capabilities_text.contains("doris.capabilities.v1"))
}
