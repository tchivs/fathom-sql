// White-box tests for the chunked header reader internals. These mirror the
// byte-at-a-time detection semantics of the original reader while exercising
// the pure scan helpers without a real pipe.

///|
test "first_terminator_end_finds_the_first_terminator" {
  assert_eq(first_terminator_end(b"Content-Length: 2\r\n\r\n"), Some(21))
  assert_eq(first_terminator_end(b"Content-Length: 2"), None)
  assert_eq(first_terminator_end(b"abc\r\n\r"), None)
  assert_eq(first_terminator_end(b"abc\r\n\r\n"), Some(7))
}

///|
test "header_end_in_detects_terminators_at_read_boundaries" {
  // Fully inside the chunk.
  assert_eq(header_end_in(b"Content-Length: 2", b"\r\n\r\n{}"), Some(21))
  // Straddling the boundary: head ends with \r\n\r, chunk starts with \n.
  assert_eq(header_end_in(b"Content-Length: 2\r\n\r", b"\n{}"), Some(21))
  // Split two-and-two across the boundary.
  assert_eq(header_end_in(b"Content-Length: 2\r\n", b"\r\n{}"), Some(21))
  // Not complete yet.
  assert_eq(header_end_in(b"Content-Length:", b" 2\r\n\r"), None)
  assert_eq(header_end_in(b"", b"Content-Length: 2"), None)
  // A body that contains \r\n\r\n after the real terminator is not mistaken
  // for a second header end: the first terminator wins.
  assert_eq(
    header_end_in(b"Content-Length: 2", b"\r\n\r\n{\"a\":\"x\r\n\r\ny\"}"),
    Some(21),
  )
}

///|
test "near_limit_header_is_detected_within_the_16kb_cap" {
  // Header content just under MAX_HEADER_BYTES (16 KB) parses end-to-end.
  let filler = Bytes::make(16380 - 17, 88) // 88 = 'X'
  let header = @utf8.encode("Content-Length: 2\r\n") + filler + b"\r\n\r\n"
  assert_eq(first_terminator_end(header), Some(header.length()))
  assert_true(header.length() - 4 <= MAX_HEADER_BYTES)
  // The near-limit header still yields a valid Content-Length value.
  let separator = header.length() - 4
  assert_eq(content_length(header[0:separator].to_owned()), Ok(2))
  // The straddle check also works at scale (head ends \r\n\r).
  assert_eq(
    header_end_in(header[0:header.length() - 1].to_owned(), b"\nbody"),
    Some(header.length()),
  )
  // A header whose content exceeds the cap is still detected by the scanner;
  // the read loop enforces the cap by returning InvalidHeader.
  let over = header + Bytes::make(5, 88)
  assert_eq(first_terminator_end(over), Some(header.length()))
  assert_true(over.length() - 4 > MAX_HEADER_BYTES)
}

///|
test "content_length_is_overflow_safe_at_the_frame_limit" {
  assert_eq(
    content_length(@utf8.encode("Content-Length: 8388608\r\n")),
    Ok(MAX_FRAME_BYTES),
  )
  // One past the limit parses arithmetically but the frame-level check
  // rejects it (FrameTooLarge) before any allocation.
  assert_eq(
    content_length(@utf8.encode("Content-Length: 8388609\r\n")),
    Ok(8388609),
  )
  assert_true(
    decode_frame(b"Content-Length: 8388609\r\n\r\n") is Err(FrameTooLarge(_)),
  )
  // Values that would overflow the bounded decimal parser are rejected
  // as InvalidContentLength (the Content-Length header was found but its
  // value is not a valid bounded decimal).
  assert_eq(
    content_length(@utf8.encode("Content-Length: 999999999\r\n")),
    Err(InvalidContentLength),
  )
  assert_true(decode_frame(b"Content-Length: 999999999\r\n\r\n") is Err(_))
  assert_eq(
    content_length(@utf8.encode("content-length: 2\r\n")),
    Err(MissingContentLength),
  )
}
