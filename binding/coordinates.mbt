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
  let (line, byte_column) = match source.line_index().line_col(byte_offset) {
    Some(value) => value
    None => return Err(InvalidOffset(offset=byte_offset))
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
fn utf8_width(bytes : Bytes, index : Int) -> Int {
  let first = bytes[index].to_int()
  if first < 0x80 { 1 }
  else if first < 0xE0 { 2 }
  else if first < 0xF0 { 3 }
  else { 4 }
}

fn line_content_end(source : @source.SourceText, line : Int) -> Int {
  let starts = source.line_index().line_starts()
  let start = starts[line]
  let next = if line + 1 < starts.length() { starts[line + 1] } else { source.byte_length() }
  if next - start >= 2 && source.bytes()[next - 2].to_int() == 13 && source.bytes()[next - 1].to_int() == 10 {
    next - 2
  } else if next > start && (source.bytes()[next - 1].to_int() == 10 || source.bytes()[next - 1].to_int() == 13) {
    next - 1
  } else {
    next
  }
}

/// Convert an LSP UTF-16 position back to the authoritative source byte offset.
/// The inverse lives beside byte_to_position so completion and future edit
/// requests cannot grow a second coordinate policy.
pub fn position_to_byte(source : @source.SourceText, position : Position) -> Result[Int, CoordinateError] {
  if position.line < 0 || position.character < 0 {
    return Err(InvalidOffset(offset=-1))
  }
  let starts = source.line_index().line_starts()
  if position.line >= starts.length() {
    return Err(InvalidOffset(offset=source.byte_length() + 1))
  }
  let start = starts[position.line]
  let end = line_content_end(source, position.line)
  let bytes = source.bytes()
  let mut index = start
  let mut units = 0
  while index < end {
    let width = utf8_width(bytes, index)
    let next_units = units + if width == 4 { 2 } else { 1 }
    if position.character == units {
      return Ok(index)
    }
    if position.character < next_units {
      return Err(InvalidOffset(offset=start))
    }
    units = next_units
    index = index + width
  }
  if position.character == units { Ok(index) } else { Err(InvalidOffset(offset=end + 1)) }
}
