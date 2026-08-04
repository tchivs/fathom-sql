/// Convert authoritative UTF-8 byte offsets to LSP UTF-16 positions.
/// Newlines are obtained from SourceText::line_index, which treats CRLF as one
/// line break. Invalid UTF-8 is counted conservatively one unit per byte; the
/// Native JSON boundary rejects invalid UTF-8 before this adapter is called.

pub(all) struct Position {
  pub line : Int
  pub character : Int
}

pub(all) struct Range {
  pub start : Position
  pub end : Position
}

pub enum CoordinateError {
  InvalidOffset(offset~ : Int)
  ReversedRange(start_byte~ : Int, end_byte~ : Int)
} derive(Eq, @debug.Debug)

fn is_continuation(byte : Int) -> Bool {
  byte >= 0x80 && byte < 0xC0
}

fn utf16_units_before(bytes : Bytes, end_byte : Int) -> Int {
  let mut index = 0
  let mut units = 0
  while index < end_byte {
    let first = bytes[index].to_int()
    if first < 0x80 {
      index = index + 1
      units = units + 1
    } else if first >= 0xC0 && first < 0xE0 && index + 1 < end_byte && is_continuation(bytes[index + 1].to_int()) {
      index = index + 2
      units = units + 1
    } else if first >= 0xE0 && first < 0xF0 && index + 2 < end_byte && is_continuation(bytes[index + 1].to_int()) && is_continuation(bytes[index + 2].to_int()) {
      index = index + 3
      units = units + 1
    } else if first >= 0xF0 && first < 0xF8 && index + 3 < end_byte && is_continuation(bytes[index + 1].to_int()) && is_continuation(bytes[index + 2].to_int()) && is_continuation(bytes[index + 3].to_int()) {
      index = index + 4
      units = units + 2
    } else {
      index = index + 1
      units = units + 1
    }
  }
  units
}

pub fn byte_to_position(source : @source.SourceText, byte_offset : Int) -> Result[Position, CoordinateError] {
  guard let (line, byte_column) = source.line_index().line_col(byte_offset) else {
    return Err(InvalidOffset(offset=byte_offset))
  }
  let line_start = source.line_index().line_starts()[line]
  let bytes = source.bytes()
  let character = utf16_units_before(bytes[line_start:line_start + byte_column].to_owned(), byte_column)
  Ok({ line: line, character: character })
}

pub fn span_to_range(source : @source.SourceText, start_byte : Int, end_byte : Int) -> Result[Range, CoordinateError] {
  if start_byte > end_byte {
    return Err(ReversedRange(start_byte~, end_byte~))
  }
  let start = match byte_to_position(source, start_byte) {
    Ok(position) => position
    Err(error) => return Err(error)
  }
  let end = match byte_to_position(source, end_byte) {
    Ok(position) => position
    Err(error) => return Err(error)
  }
  Ok({ start: start, end: end })
}
