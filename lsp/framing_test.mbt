test "framing_requires_content_length_and_crlf" {
  let header = frame(b"{}")
  assert_eq(header, @utf8.encode("Content-Length: 2\r\n\r\n{}"))
  let decoded = match decode_frame(header) {
    Ok(body) => body
    Err(_) => panic()
  }
  assert_eq(decoded, b"{}")
}

test "write_all_resumes_partial_writes_at_the_correct_offset" {
  let output = frame(b"{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"exit\"}")
  let collected = @buffer.Buffer::Buffer(size_hint=output.length())
  // Simulate a slow consumer that accepts at most 7 bytes per write; the
  // retry must resume at the exact resume offset, never resend the prefix.
  write_all(output, fn(bytes, count) {
    let take = if count > 7 { 7 } else { count }
    collected.write_bytes(bytes[0:take])
    take
  })
  assert_eq(collected.to_bytes(), output)
}

test "write_all_stops_when_the_stream_reports_an_error" {
  let output = frame(b"{}")
  let mut calls = 0
  write_all(output, fn(_bytes, _count) {
    calls = calls + 1
    if calls == 2 { -1 } else { 1 }
  })
  assert_eq(calls, 2)
}

test "malformed_frame_is_rejected_not_crashed" {
  let malformed = b"Content-Length: nope\r\n\r\n{}"
  assert_true(decode_frame(malformed) is Err(_))
  assert_true(decode_frame(b"Content-Length: 999999999\r\n\r\n") is Err(_))
}
test "malformed_frame_error_is_single_valid_outer_frame" {
  let request = match parse_message(@utf8.encode("{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"initialize\"}")) {
    Ok(message) => message
    Err(_) => panic()
  }
  let id = match request.id {
    Some(id) => id
    None => panic()
  }
  let body = error_response(id, -32700, "malformed Content-Length frame")
  let outer = frame(body)
  let decoded = match decode_frame(outer) {
    Ok(value) => value
    Err(_) => panic()
  }
  let json = try {
    @json.parse(@utf8.decode(decoded))
  } catch {
    _ => panic()
  }
  assert_true(json.stringify().contains("malformed Content-Length frame"))
  assert_true(json.stringify().contains("-32700"))
}
