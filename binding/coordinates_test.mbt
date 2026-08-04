fn utf16_units_before(bytes : Bytes, end_byte : Int) -> Int {
  let mut index = 0
  let mut units = 0
  while index < end_byte {
    let first = bytes[index].to_int()
    if first < 0x80 {
      index = index + 1
      units = units + 1
    } else if first < 0xE0 {
      index = index + 2
      units = units + 1
    } else if first < 0xF0 {
      index = index + 3
      units = units + 1
    } else {
      index = index + 4
      units = units + 2
    }
  }
  units
}

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
  assert_eq(raw.length(), 6)
  assert_eq(utf16_units_before(raw, 1), 1)
  assert_eq(utf16_units_before(raw, 5), 3)
  assert_eq(utf16_units_before(raw, 6), 4)
}
