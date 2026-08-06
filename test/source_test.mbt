fn parse_editor(raw : Bytes) -> @api.ParseResult {
  match @api.parse_with_ids(raw, "doris", "4.x", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
}

test "source_replay_preserves_line_endings_bom_unicode_and_invalid_bytes" {
  let inputs = [
    b"",
    b"\n",
    b"\r\n",
    b"a\r\nb\nc\r",
    b"\xef\xbb\xbfSELECT \xf0\x9f\x98\x80\r\n",
    b"SELECT \xff\xfe",
  ]
  for raw in inputs {
    let result = parse_editor(raw)
    assert_eq(@printer.print_result(result), raw)
    assert_eq(result.source_byte_length, raw.length())
    assert_true(result.all_spans_in_bounds())
  }
}

test "empty_input_has_no_diagnostic_and_trailing_newline_replays" {
  let empty = parse_editor(b"")
  assert_true(empty.valid)
  assert_eq(empty.diagnostics.length(), 0)
  let trailing = parse_editor(b"SELECT 1\n")
  assert_eq(@printer.print_result(trailing), b"SELECT 1\n")
}
