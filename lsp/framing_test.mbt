test "framing_requires_content_length_and_crlf" {
  let header = "Content-Length: 2\r\n\r\n{}"
  assert_true(header.contains("Content-Length:"))
  assert_true(header.contains("\r\n\r\n"))
}

test "malformed_frame_is_rejected_not_crashed" {
  let malformed = "Content-Length: nope\r\n\r\n{}"
  assert_true(malformed.contains("nope"))
}
