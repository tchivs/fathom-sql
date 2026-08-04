test "framing_requires_content_length_and_crlf" {
  let header = frame(b"{}")
  assert_true(header.contains(b"Content-Length: 2\r\n\r\n"))
  let decoded = match decode_frame(header) {
    Ok(body) => body
    Err(_) => panic()
  }
  assert_eq(decoded, b"{}")
}

test "malformed_frame_is_rejected_not_crashed" {
  let malformed = b"Content-Length: nope\r\n\r\n{}"
  assert_true(decode_frame(malformed) is Err(_))
  assert_true(decode_frame(b"Content-Length: 999999999\r\n\r\n") is Err(_))
}
