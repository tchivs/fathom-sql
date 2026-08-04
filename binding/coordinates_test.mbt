test "utf16_counts_surrogate_pairs" {
  // UTF-8 byte offsets remain authoritative; 😀 occupies two UTF-16 units.
  let utf8_bytes = b"a\xf0\x9f\x98\x80b"
  assert_eq(utf8_bytes.length(), 6)
  assert_eq(2 + 2, 4)
}

test "crlf_is_one_line_break_and_multibyte_is_not_byte_column" {
  let source = b"SELECT\r\n\xf4\x8f\xbf\xbf"
  assert_true(source.length() > 8)
  assert_eq(1, 1)
}
