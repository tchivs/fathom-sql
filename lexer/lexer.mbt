/// A synchronous, source-backed lexer. Every branch either consumes bytes or terminates.

fn is_ascii_letter(byte : Int) -> Bool {
  (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 95
}

fn is_ascii_identifier_continue(byte : Int) -> Bool {
  is_ascii_letter(byte) || (byte >= 48 && byte <= 57) || byte == 36
}

fn is_continuation(byte : Int) -> Bool {
  byte >= 128 && byte <= 191
}

fn utf8_width(bytes : Bytes, index : Int) -> Int? {
  let length = bytes.length()
  let first = bytes[index].to_int()
  if first < 128 {
    Some(1)
  } else if first >= 194 && first <= 223 {
    if index + 1 < length && is_continuation(bytes[index + 1].to_int()) {
      Some(2)
    } else {
      None
    }
  } else if first >= 224 && first <= 239 {
    if index + 2 < length {
      let second = bytes[index + 1].to_int()
      let third = bytes[index + 2].to_int()
      if is_continuation(third) && is_continuation(second) &&
        (first != 224 || second >= 160) && (first != 237 || second <= 159) {
        Some(3)
      } else {
        None
      }
    } else {
      None
    }
  } else if first >= 240 && first <= 244 {
    if index + 3 < length {
      let second = bytes[index + 1].to_int()
      let third = bytes[index + 2].to_int()
      let fourth = bytes[index + 3].to_int()
      if is_continuation(third) && is_continuation(fourth) &&
        is_continuation(second) && (first != 240 || second >= 144) &&
        (first != 244 || second <= 143) {
        Some(4)
      } else {
        None
      }
    } else {
      None
    }
  } else {
    None
  }
}

fn starts_identifier(bytes : Bytes, index : Int) -> Bool {
  let byte = bytes[index].to_int()
  if is_ascii_letter(byte) {
    true
  } else if byte >= 128 {
    match utf8_width(bytes, index) {
      Some(_) => true
      None => false
    }
  } else {
    false
  }
}

fn is_space(byte : Int) -> Bool {
  byte == 32 || byte == 9 || byte == 11 || byte == 12
}

fn is_ascii_digit(byte : Int) -> Bool {
  byte >= 48 && byte <= 57
}

fn scan_number(bytes : Bytes, start : Int) -> (Int, Bool) {
  let length = bytes.length()
  let mut index = start
  while index < length && is_ascii_digit(bytes[index].to_int()) { index = index + 1 }
  let mut valid = true
  if index < length && bytes[index].to_int() == 46 {
    index = index + 1
    if index >= length || !is_ascii_digit(bytes[index].to_int()) { valid = false }
    while index < length && is_ascii_digit(bytes[index].to_int()) { index = index + 1 }
  }
  if index < length && (bytes[index].to_int() == 101 || bytes[index].to_int() == 69) {
    index = index + 1
    if index < length && (bytes[index].to_int() == 43 || bytes[index].to_int() == 45) { index = index + 1 }
    if index >= length || !is_ascii_digit(bytes[index].to_int()) { valid = false }
    while index < length && is_ascii_digit(bytes[index].to_int()) { index = index + 1 }
  }
  if index < length && bytes[index].to_int() == 46 {
    valid = false
  }
  if !valid {
    while index < length {
      let next = bytes[index].to_int()
      if is_ascii_digit(next) || next == 46 || next == 101 || next == 69 || next == 43 || next == 45 {
        index = index + 1
      } else {
        break
      }
    }
  }
  (index, valid)
}

fn push_token(
  tokens : Array[@token.Token],
  source_length : Int,
  profile : @token.DorisProfile,
  kind : @token.TokenKind,
  start_byte : Int,
  end_byte : Int,
  diagnostic_code : String?,
) -> Unit {
  let span = match @source.Span::checked(start_byte, end_byte, source_length) {
    Ok(span) => span
    Err(_) => panic()
  }
  tokens.push({
    kind: kind,
    span: span,
    profile: profile,
    diagnostic_code: diagnostic_code,
  })
}
fn invalid_run_end(bytes : Bytes, start : Int, end : Int) -> Int {
  let mut index = start + 1
  while index < end {
    let byte = bytes[index].to_int()
    if byte < 128 || utf8_width(bytes, index) is Some(_) {
      break
    }
    index = index + 1
  }
  index
}


fn push_scanned_with_invalid(
  tokens : Array[@token.Token],
  bytes : Bytes,
  source_length : Int,
  profile : @token.DorisProfile,
  kind : @token.TokenKind,
  start_byte : Int,
  end_byte : Int,
  diagnostic_code : String?,
  max_tokens : Int,
) -> Int? {
  let mut cursor = start_byte
  let mut segment_start = start_byte
  while cursor < end_byte {
    let byte = bytes[cursor].to_int()
    let invalid = byte >= 128 && utf8_width(bytes, cursor) is None
    if invalid {
      if segment_start < cursor {
        if max_tokens >= 0 && tokens.length() >= max_tokens { return Some(segment_start) }
        push_token(tokens, source_length, profile, kind, segment_start, cursor, None)
      }
      let invalid_end = invalid_run_end(bytes, cursor, end_byte)
      if max_tokens >= 0 && tokens.length() >= max_tokens { return Some(cursor) }
      push_token(tokens, source_length, profile, @token.TokenKind::Error, cursor, invalid_end, Some("LEX_INVALID_UTF8"))
      cursor = invalid_end
      segment_start = cursor
    } else {
      let width = if byte < 128 { 1 } else {
        match utf8_width(bytes, cursor) { Some(width) => width; None => 1 }
      }
      cursor = cursor + width
    }
  }
  if segment_start < end_byte {
    if max_tokens >= 0 && tokens.length() >= max_tokens { return Some(segment_start) }
    push_token(tokens, source_length, profile, kind, segment_start, end_byte, diagnostic_code)
  }
  None
}


fn scan_comment(bytes : Bytes, start : Int) -> (Int, String?) {
  let length = bytes.length()
  if start + 1 < length && bytes[start].to_int() == 47 && bytes[start + 1].to_int() == 42 {
    let mut index = start + 2
    while index + 1 < length &&
      !(bytes[index].to_int() == 42 && bytes[index + 1].to_int() == 47) {
      index = index + 1
    }
    if index + 1 < length {
      (index + 2, None)
    } else {
      (length, Some("LEX_UNTERMINATED_COMMENT"))
    }
  } else {
    let mut index = start
    while index < length && bytes[index].to_int() != 10 && bytes[index].to_int() != 13 {
      index = index + 1
    }
    (index, None)
  }
}

fn scan_quoted(bytes : Bytes, start : Int, quote : Int) -> (Int, String?) {
  let length = bytes.length()
  let mut index = start + 1
  while index < length {
    let byte = bytes[index].to_int()
    if byte == 92 {
      index = if index + 1 < length { index + 2 } else { length }
    } else if byte == quote {
      if index + 1 < length && bytes[index + 1].to_int() == quote {
        index = index + 2
      } else {
        return (index + 1, None)
      }
    } else {
      index = index + 1
    }
  }
  (length, Some("LEX_UNTERMINATED_LITERAL"))
}

pub fn lex_with_limit(source : @source.SourceText, profile : @token.DorisProfile, max_tokens : Int) -> @token.TokenStream {
  let bytes = source.bytes()
  let source_length = bytes.length()
  let tokens : Array[@token.Token] = []
  let mut index = 0
  let mut truncated_at : Int? = None
  while index < source_length && (max_tokens < 0 || tokens.length() < max_tokens) {
    let byte = bytes[index].to_int()
    if index + 2 < source_length && byte == 239 && bytes[index + 1].to_int() == 187 &&
      bytes[index + 2].to_int() == 191 {
      push_token(tokens, source_length, profile, @token.TokenKind::Bom, index, index + 3, None)
      index = index + 3
    } else if byte == 10 || byte == 13 {
      let end = if byte == 13 && index + 1 < source_length && bytes[index + 1].to_int() == 10 {
        index + 2
      } else {
        index + 1
      }
      push_token(tokens, source_length, profile, @token.TokenKind::Newline, index, end, None)
      index = end
    } else if is_space(byte) {
      let start = index
      index = index + 1
      while index < source_length && is_space(bytes[index].to_int()) {
        index = index + 1
      }
      push_token(tokens, source_length, profile, @token.TokenKind::Whitespace, start, index, None)
    } else if (byte == 45 && index + 1 < source_length && bytes[index + 1].to_int() == 45) || byte == 35 {
      let start = index
      let (end, code) = scan_comment(bytes, if byte == 35 { index } else { index + 1 })
      match push_scanned_with_invalid(tokens, bytes, source_length, profile, @token.TokenKind::Comment, start, end, code, max_tokens) {
        Some(at) => if truncated_at is None { truncated_at = Some(at) }
        None => ()
      }
      index = end
    } else if byte == 47 && index + 1 < source_length && bytes[index + 1].to_int() == 42 {
      let (end, code) = scan_comment(bytes, index)
      match push_scanned_with_invalid(tokens, bytes, source_length, profile, @token.TokenKind::Comment, index, end, code, max_tokens) {
        Some(at) => if truncated_at is None { truncated_at = Some(at) }
        None => ()
      }
      index = end
    } else if byte == 39 {
      let start = index
      let (end, code) = scan_quoted(bytes, index, byte)
      match push_scanned_with_invalid(tokens, bytes, source_length, profile, @token.TokenKind::StringLiteral, start, end, code, max_tokens) {
        Some(at) => if truncated_at is None { truncated_at = Some(at) }
        None => ()
      }
      index = end
    } else if byte == 34 || byte == 96 {
      let start = index
      let (end, code) = scan_quoted(bytes, index, byte)
      match push_scanned_with_invalid(tokens, bytes, source_length, profile, @token.TokenKind::Quoted, start, end, code, max_tokens) {
        Some(at) => if truncated_at is None { truncated_at = Some(at) }
        None => ()
      }
      index = end
    } else if byte >= 48 && byte <= 57 {
      let start = index
      let (end, valid) = scan_number(bytes, start)
      index = end
      if valid {
        push_token(tokens, source_length, profile, @token.TokenKind::Number, start, end, None)
      } else {
        push_token(tokens, source_length, profile, @token.TokenKind::Error, start, end, Some("LEX_INVALID_NUMBER"))
      }
    } else if starts_identifier(bytes, index) {
      let start = index
      let width = match utf8_width(bytes, index) {
        Some(width) => width
        None => 1
      }
      index = index + width
      while index < source_length {
        let next = bytes[index].to_int()
        if is_ascii_identifier_continue(next) {
          index = index + 1
        } else {
          match utf8_width(bytes, index) {
            Some(width) if next >= 128 => index = index + width
            _ => break
          }
        }
      }
      push_token(tokens, source_length, profile, @token.TokenKind::Identifier, start, index, None)
    } else {
      match utf8_width(bytes, index) {
        Some(width) if byte >= 128 => {
          push_token(tokens, source_length, profile, @token.TokenKind::Unknown, index, index + width, None)
          index = index + width
        }
        None if byte >= 128 => {
          let start = index
          index = index + 1
          while index < source_length && bytes[index].to_int() >= 128 && utf8_width(bytes, index) is None {
            index = index + 1
          }
          push_token(
            tokens,
            source_length,
            profile,
            @token.TokenKind::Error,
            start,
            index,
            Some("LEX_INVALID_UTF8"),
          )
        }
        _ => {
          push_token(tokens, source_length, profile, @token.TokenKind::Symbol, index, index + 1, None)
          index = index + 1
        }
      }
    }
  }
  let final_truncated_at = match truncated_at {
    Some(at) => Some(at)
    None => if index < source_length { Some(index) } else { None }
  }
  {
    source: source,
    profile: profile,
    tokens: tokens,
    truncated_at: final_truncated_at,
  }
}

pub fn lex(source : @source.SourceText, profile : @token.DorisProfile) -> @token.TokenStream {
  lex_with_limit(source, profile, 1_000_000)
}

test "lexer_preserves_trivia_literals_and_invalid_bytes" {
  let source = match @source.SourceText::new(b"\xef\xbb\xbfSELECT /*x*/ 'a''b' -- c\r\n\xff\xfe") {
    Ok(source) => source
    Err(_) => panic()
  }
  let stream = lex(source, @token.DorisProfile::V4_X)
  assert_true(stream.length() > 6)
  assert_eq(stream.raw(0), Some(b"\xef\xbb\xbf"))
  assert_eq(stream.raw(stream.length() - 1), Some(b"\xff\xfe"))
  let last = match stream.at(stream.length() - 1) {
    Some(token) => token
    None => panic()
  }
  assert_true(last.kind is @token.TokenKind::Error)
  assert_eq(last.diagnostic_code, Some("LEX_INVALID_UTF8"))
  for token in stream.tokens {
    assert_true(token.span.start_byte <= token.span.end_byte)
    assert_true(token.span.end_byte <= source.byte_length())
    assert_eq(token.raw(source), source.slice(token.span))
  }
}

test "lexer_splits_invalid_utf8_inside_closed_literals_identifiers_and_comments" {
  let raw = b"SELECT '\xff' `bad\xfe` /*\xfd*/ 1"
  let source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let stream = lex(source, @token.DorisProfile::V4_X)
  let mut invalid_count = 0
  let mut replay = b""
  for token in stream.tokens {
    let token_bytes = match token.raw(source) {
      Some(bytes) => bytes
      None => b""
    }
    replay = replay + token_bytes
    if token.kind is @token.TokenKind::Error {
      assert_eq(token.diagnostic_code, Some("LEX_INVALID_UTF8"))
      invalid_count = invalid_count + 1
    }
  }
  assert_eq(invalid_count, 3)
  assert_eq(replay, raw)
}

test "lexer_terminates_unterminated_material" {
  let source = match @source.SourceText::new(b"/* never closes 'also never closes") {
    Ok(source) => source
    Err(_) => panic()
  }
  let stream = lex(source, @token.DorisProfile::V2_1)
  assert_eq(stream.length(), 1)
  assert_eq(stream.raw(0), Some(source.bytes()))
  let token = match stream.at(0) {
    Some(token) => token
    None => panic()
  }
  assert_eq(token.diagnostic_code, Some("LEX_UNTERMINATED_COMMENT"))
}
test "lexer_replays_every_source_byte_and_keeps_unicode" {
  let raw = b"\xef\xbb\xbf列\xf0\x9f\x98\x80 /* c */\r\n42"
  let source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let stream = lex(source, @token.DorisProfile::V3_X)
  let mut replay = b""
  for token in stream.tokens {
    let token_bytes = match token.raw(source) {
      Some(bytes) => bytes
      None => panic()
    }
    replay = replay + token_bytes
    assert_eq(token.profile, @token.DorisProfile::V3_X)
  }
  assert_eq(replay, raw)
}

test "lexer_retains_unterminated_quote_and_progresses" {
  let source = match @source.SourceText::new(b"'unterminated") {
    Ok(source) => source
    Err(_) => panic()
  }
  let stream = lex(source, @token.DorisProfile::V2_1)
  assert_eq(stream.length(), 1)
  let token = match stream.at(0) {
    Some(token) => token
    None => panic()
  }
  assert_true(token.kind is @token.TokenKind::StringLiteral)
  assert_eq(token.diagnostic_code, Some("LEX_UNTERMINATED_LITERAL"))
  assert_eq(token.raw(source), Some(b"'unterminated"))
}

test "lexer_calls_are_reentrant_without_shared_state" {
  let source = match @source.SourceText::new(b"SELECT 1") {
    Ok(source) => source
    Err(_) => panic()
  }
  let first = lex(source, @token.DorisProfile::V2_1)
  let second = lex(source, @token.DorisProfile::V4_X)
  assert_eq(first.length(), second.length())
  assert_eq(first.profile, @token.DorisProfile::V2_1)
  assert_eq(second.profile, @token.DorisProfile::V4_X)
  assert_eq(first.raw(0), second.raw(0))
}

test "lexer_accepts_decimal_and_scientific_numbers_but_rejects_repeated_dots" {
  let raw = b"1 1.2 1e3 1.2E-3 1..2 1.2.3"
  let source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let stream = lex(source, @token.DorisProfile::V4_X)
  assert_eq(stream.raw(0), Some(b"1"))
  assert_eq(stream.raw(2), Some(b"1.2"))
  assert_eq(stream.raw(4), Some(b"1e3"))
  assert_eq(stream.raw(6), Some(b"1.2E-3"))
  let mut errors = 0
  let mut replay = b""
  for token in stream.tokens {
    let token_bytes = match token.raw(source) {
      Some(bytes) => bytes
      None => b""
    }
    replay = replay + token_bytes
    if token.kind is @token.TokenKind::Error {
      errors = errors + 1
      assert_eq(token.diagnostic_code, Some("LEX_INVALID_NUMBER"))
      assert_true(token.span.start_byte < token.span.end_byte)
    }
  }
  assert_eq(errors, 2)
  assert_eq(replay, raw)
}
test "lexer_bounds_invalid_split_tokens_and_reports_source_truncation" {
  for raw in [b"SELECT 'ok\xfftail'", b"SELECT /*ok\xfe tail*/ 1"] {
    let source = match @source.SourceText::new(raw) {
      Ok(source) => source
      Err(_) => panic()
    }
    let stream = lex_with_limit(source, @token.DorisProfile::V4_X, 3)
    assert_true(stream.length() <= 3)
    match stream.truncated_at {
      Some(at) => assert_true(at < raw.length())
      None => panic()
    }
    for token in stream.tokens {
      assert_true(token.span.end_byte <= raw.length())
      assert_eq(token.raw(source), source.slice(token.span))
    }
  }
}
