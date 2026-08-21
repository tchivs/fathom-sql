///|
/// One immutable source snapshot and the byte coordinate primitives shared by the core.
pub const DEFAULT_MAX_BYTES : Int = 8 * 1024 * 1024

///|
pub struct Span {
  start_byte : Int
  end_byte : Int
}

///|
pub enum SpanError {
  OutOfBounds(start_byte~ : Int, end_byte~ : Int, source_length~ : Int)
  Reversed(start_byte~ : Int, end_byte~ : Int)
}

///|
pub fn Span::checked(
  start_byte : Int,
  end_byte : Int,
  source_length : Int,
) -> Result[Span, SpanError] {
  if start_byte < 0 || end_byte < start_byte || end_byte > source_length {
    if end_byte < start_byte {
      Err(Reversed(start_byte~, end_byte~))
    } else {
      Err(OutOfBounds(start_byte~, end_byte~, source_length~))
    }
  } else {
    Ok({ start_byte, end_byte })
  }
}

///|
pub fn Span::length(self : Span) -> Int {
  self.end_byte - self.start_byte
}

///|
pub enum SourceError {
  InputTooLarge(requested_bytes~ : Int, max_bytes~ : Int)
}

///|
pub struct LineIndex {
  starts : Array[Int]
  source_length : Int
}

///|
fn build_line_index(bytes : Bytes) -> LineIndex {
  let starts : Array[Int] = [0]
  let length = bytes.length()
  let mut index = 0
  while index < length {
    let byte = bytes[index].to_int()
    if byte == 13 {
      if index + 1 < length && bytes[index + 1].to_int() == 10 {
        index = index + 1
      }
      starts.push(index + 1)
    } else if byte == 10 {
      starts.push(index + 1)
    }
    index = index + 1
  }
  { starts, source_length: length }
}

///|
pub fn LineIndex::line_starts(self : LineIndex) -> Array[Int] {
  self.starts.copy()
}

///|
pub fn LineIndex::line_count(self : LineIndex) -> Int {
  self.starts.length()
}

///|
pub fn LineIndex::line_col(self : LineIndex, byte_offset : Int) -> (Int, Int)? {
  if byte_offset < 0 || byte_offset > self.source_length {
    None
  } else {
    let count = self.starts.length()
    if count == 0 || byte_offset < self.starts[0] {
      None
    } else {
      let mut line = 0
      let mut index = 1
      while index < count && self.starts[index] <= byte_offset {
        line = index
        index = index + 1
      }
      Some((line, byte_offset - self.starts[line]))
    }
  }
}

///|
pub struct SourceText {
  bytes : Bytes
  lines : LineIndex
}

///|
pub fn SourceText::new(raw : Bytes) -> Result[SourceText, SourceError] {
  SourceText::new_with_limit(raw, DEFAULT_MAX_BYTES)
}

///|
pub fn SourceText::new_with_limit(
  raw : Bytes,
  max_bytes : Int,
) -> Result[SourceText, SourceError] {
  let requested_bytes = raw.length()
  let limit = if max_bytes < 0 { 0 } else { max_bytes }
  // This check intentionally precedes construction of LineIndex or any snapshot view.
  if requested_bytes > limit {
    Err(InputTooLarge(requested_bytes~, max_bytes=limit))
  } else {
    Ok({ bytes: raw, lines: build_line_index(raw) })
  }
}

///|
pub fn SourceText::byte_length(self : SourceText) -> Int {
  self.bytes.length()
}

///|
pub fn SourceText::bytes(self : SourceText) -> Bytes {
  self.bytes
}

///|
pub fn SourceText::line_index(self : SourceText) -> LineIndex {
  self.lines
}

///|
pub fn SourceText::span(
  self : SourceText,
  start_byte : Int,
  end_byte : Int,
) -> Result[Span, SpanError] {
  Span::checked(start_byte, end_byte, self.byte_length())
}

///|
pub fn SourceText::slice(self : SourceText, span : Span) -> Bytes? {
  if span.start_byte < 0 ||
    span.start_byte > span.end_byte ||
    span.end_byte > self.byte_length() {
    None
  } else {
    Some(self.bytes[span.start_byte:span.end_byte].to_owned())
  }
}

///|
pub fn SourceText::same_bytes(self : SourceText, other : Bytes) -> Bool {
  self.bytes == other
}

///|
test "source_rejects_before_snapshot_and_checks_spans" {
  let raw = b"abcd"
  let rejected = SourceText::new_with_limit(raw, 3)
  assert_true(rejected is Err(InputTooLarge(requested_bytes=4, max_bytes=3)))
  let source = match SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let span = match source.span(1, 3) {
    Ok(span) => span
    Err(_) => panic()
  }
  assert_eq(source.slice(span), Some(b"bc"))
  assert_true(source.span(3, 2) is Err(Reversed(..)))
  assert_true(source.span(0, 5) is Err(OutOfBounds(..)))
}

///|
test "line_index_handles_lf_crlf_mixed_and_bom" {
  let source = match SourceText::new(b"\xef\xbb\xbfa\r\nb\nc\r") {
    Ok(source) => source
    Err(_) => panic()
  }
  assert_eq(source.line_index().line_starts(), [0, 6, 8, 10])
  assert_eq(source.line_index().line_col(6), Some((1, 0)))
  assert_eq(source.line_index().line_col(9), Some((2, 1)))
  assert_eq(source.line_index().line_count(), 4)
}

///|
test "empty_source_has_stable_zero_width_line" {
  let source = match SourceText::new(b"") {
    Ok(source) => source
    Err(_) => panic()
  }
  assert_eq(source.byte_length(), 0)
  assert_eq(source.line_index().line_starts(), [0])
  assert_eq(source.line_index().line_col(0), Some((0, 0)))
}

///|
test "source_limits_and_adjacent_empty_spans" {
  assert_eq(DEFAULT_MAX_BYTES, 8 * 1024 * 1024)
  let exact = SourceText::new_with_limit(b"1234", 4)
  assert_true(exact is Ok(_))
  let over = SourceText::new_with_limit(b"12345", 4)
  assert_true(over is Err(InputTooLarge(requested_bytes=5, max_bytes=4)))
  let source = match exact {
    Ok(source) => source
    Err(_) => panic()
  }
  let first = match source.span(0, 2) {
    Ok(span) => span
    Err(_) => panic()
  }
  let second = match source.span(2, 4) {
    Ok(span) => span
    Err(_) => panic()
  }
  let empty = match source.span(2, 2) {
    Ok(span) => span
    Err(_) => panic()
  }
  assert_eq(source.slice(first), Some(b"12"))
  assert_eq(source.slice(second), Some(b"34"))
  assert_eq(empty.length(), 0)
  assert_eq(source.slice(empty), Some(b""))
}

///|
test "source_keeps_unicode_and_emoji_bytes" {
  let raw = b"列\xf0\x9f\x98\x80\n"
  let source = match SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  assert_true(source.same_bytes(raw))
  assert_eq(source.line_index().line_starts(), [0, 8])
  assert_eq(source.line_index().line_col(8), Some((1, 0)))
}

///|
test "line_index_rejects_offsets_past_source_eof" {
  let source = match SourceText::new(b"abc") {
    Ok(source) => source
    Err(_) => panic()
  }
  assert_eq(source.line_index().line_col(3), Some((0, 3)))
  assert_eq(source.line_index().line_col(4), None)
  assert_eq(source.line_index().line_col(999), None)
}
