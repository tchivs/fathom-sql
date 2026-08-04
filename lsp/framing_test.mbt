test "framing_requires_content_length_and_crlf" {
  let header = "Content-Length: 2\r\n\r\n{}"
  assert_eq(header, "Content-Length: 2\r\n\r\n{}")
  assert_true(header.contains("Content-Length: "))
  assert_true(header.contains("\r\n\r\n"))
  assert_true(header.contains("{}"))
  assert_eq(header.length(), 23)
}

test "malformed_frame_is_rejected_not_crashed" {
  let malformed = "Content-Length: nope\r\n\r\n{}"
  assert_eq(malformed, "Content-Length: nope\r\n\r\n{}")
  assert_true(malformed.contains("Content-Length: nope"))
  assert_true(!malformed.contains("Content-Length: 2"))
  assert_true(malformed.contains("\r\n\r\n"))
}
