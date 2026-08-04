test "line_index_tracks_lf_crlf_and_byte_spans" {
  let raw = b"ab\r\n\xe5\x88\x97\xf0\x9f\x98\x80\nz"
  let source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let index = source.line_index()
  assert_eq(index.line_starts(), [0, 4, 12])
  assert_eq(index.line_count(), 3)
  assert_eq(index.line_col(4), Some((1, 0)))
  assert_eq(index.line_col(7), Some((1, 3)))
  assert_eq(index.line_col(12), Some((2, 0)))
  let span = match source.span(4, 11) {
    Ok(span) => span
    Err(_) => panic()
  }
  assert_eq(span.length(), 7)
  assert_eq(source.slice(span), Some(b"\xe5\x88\x97\xf0\x9f\x98\x80"))
}

test "utf8_byte_offsets_convert_nontrivially_to_utf16_units" {
  let raw = b"a\xf0\x9f\x98\x80b"
  let source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let first = match @binding.byte_to_position(source, 1) {
    Ok(position) => position
    Err(_) => panic()
  }
  let after_emoji = match @binding.byte_to_position(source, 5) {
    Ok(position) => position
    Err(_) => panic()
  }
  let eof = match @binding.byte_to_position(source, 6) {
    Ok(position) => position
    Err(_) => panic()
  }
  assert_eq(first.line, 0)
  assert_eq(first.character, 1)
  assert_eq(after_emoji.character, 3)
  assert_eq(eof.character, 4)
}

test "utf16_conversion_treats_crlf_as_one_line" {
  let raw = b"ab\r\n\xe5\x88\x97\xf0\x9f\x98\x80\n"
  let source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let line_start = match @binding.byte_to_position(source, 4) {
    Ok(position) => position
    Err(_) => panic()
  }
  let line_end = match @binding.byte_to_position(source, 11) {
    Ok(position) => position
    Err(_) => panic()
  }
  assert_eq(line_start.line, 1)
  assert_eq(line_start.character, 0)
  assert_eq(line_end.line, 1)
  assert_eq(line_end.character, 3)
}

test "utf16_positions_round_trip_to_source_bytes" {
  let raw = b"a\xf0\x9f\x98\x80b\r\nSELECT"
  let source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let emoji_end = match @binding.position_to_byte(source, { line: 0, character: 3 }) {
    Ok(offset) => offset
    Err(_) => panic()
  }
  assert_eq(emoji_end, 5)
  let second_line = match @binding.position_to_byte(source, { line: 1, character: 6 }) {
    Ok(offset) => offset
    Err(_) => panic()
  }
  assert_eq(second_line, raw.length())
}
