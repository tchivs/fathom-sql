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

// Multi-character comparison operators are single symbols: <=, >=, <>, !=,
// and the three-character <=>. Other symbols remain single-byte tokens.
fn symbol_width(bytes : Bytes, index : Int) -> Int {
  let length = bytes.length()
  if index + 1 < length {
    let first = bytes[index].to_int()
    let second = bytes[index + 1].to_int()
    if (first == 60 && second == 61) || (first == 62 && second == 61) ||
      (first == 60 && second == 62) || (first == 33 && second == 61) {
      if first == 60 && second == 61 && index + 2 < length && bytes[index + 2].to_int() == 62 {
        3
      } else {
        2
      }
    } else {
      1
    }
  } else {
    1
  }
}

fn scan_number(bytes : Bytes, start : Int) -> (Int, Bool) {  let length = bytes.length()
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
  context : @dialect.DialectContext,
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
    context: context,
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
  context : @dialect.DialectContext,
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
        push_token(tokens, source_length, context, kind, segment_start, cursor, None)
      }
      let invalid_end = invalid_run_end(bytes, cursor, end_byte)
      if max_tokens >= 0 && tokens.length() >= max_tokens { return Some(cursor) }
      push_token(tokens, source_length, context, @token.TokenKind::Error, cursor, invalid_end, Some("LEX_INVALID_UTF8"))
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
    push_token(tokens, source_length, context, kind, segment_start, end_byte, diagnostic_code)
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

// ---------------------------------------------------------------------------
// Flink lexical scanners (D-03, grounded in 10-RESEARCH.md §9). The Flink arms
// never reuse the Doris backslash-escaping policy: QUOTED_STRING doubles `''`
// with NO backslash escape (Parser-calcite-1.36.0.jj:8715), BTID double-backticks
// with no backslash escape and no embedded newline (:8951-8962), and
// C_STYLE_ESCAPED_STRING_LITERAL allows backslash escapes (:8721 / 1.34.0:8469).
// ---------------------------------------------------------------------------

/// Flink `'...'`: `''` doubling only, no backslash escape, newlines allowed
/// (`<QUOTED_STRING: <QUOTE> ( (~["'"]) | ("''"))* <QUOTE>>`).
fn scan_flink_string(bytes : Bytes, start : Int) -> (Int, String?) {
  let length = bytes.length()
  let mut index = start + 1
  while index < length {
    let byte = bytes[index].to_int()
    if byte == 39 {
      if index + 1 < length && bytes[index + 1].to_int() == 39 {
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

/// Flink `E'...'`: C_STYLE_ESCAPED_STRING_LITERAL — `''` doubling AND backslash
/// escapes (`"E" <QUOTE> ( (~["'", "\\"]) | ("\\" ~[]) | "''")* <QUOTE>`).
fn scan_flink_escaped_string(bytes : Bytes, start : Int) -> (Int, String?) {
  let length = bytes.length()
  let mut index = start + 1
  while index < length {
    let byte = bytes[index].to_int()
    if byte == 92 {
      index = if index + 1 < length { index + 2 } else { length }
    } else if byte == 39 {
      if index + 1 < length && bytes[index + 1].to_int() == 39 {
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

/// Flink backtick identifier: BTID state — double-backtick escape, no backslash
/// escape, and a raw newline/CR terminates the identifier (unterminated), so
/// spans stay source-backed and bounded exactly like the shared scanner.
fn scan_flink_backtick(bytes : Bytes, start : Int) -> (Int, String?) {
  let length = bytes.length()
  let mut index = start + 1
  while index < length {
    let byte = bytes[index].to_int()
    if byte == 96 {
      if index + 1 < length && bytes[index + 1].to_int() == 96 {
        index = index + 2
      } else {
        return (index + 1, None)
      }
    } else if byte == 10 || byte == 13 {
      return (index, Some("LEX_UNTERMINATED_LITERAL"))
    } else {
      index = index + 1
    }
  }
  (length, Some("LEX_UNTERMINATED_LITERAL"))
}

/// The E-literal availability gate reads the selected FlinkProfile
/// (flink-2.3.0/2.1.3 allow, flink-1.20.5 denies — T-10-08).
fn flink_supports_escape_literal(context : @dialect.DialectContext) -> Bool {
  match @dialect.FlinkProfile::from_id(context.profile_id) {
    Some(profile) => profile.supports_escape_literal()
    None => false
  }
}

/// Flink literal-prefix detection at an identifier boundary (D-03): X/U&/N/E
/// followed by `'` consume the whole prefixed literal as ONE StringLiteral
/// token. `B` is deliberately absent — no BIT_STRING_LITERAL token exists in
/// any pinned release (10-RESEARCH.md §9), so `B'..'` stays Identifier+String.
fn flink_prefixed_literal(
  bytes : Bytes,
  start : Int,
  id_end : Int,
  context : @dialect.DialectContext,
) -> (Int, String?)? {
  let length = bytes.length()
  if id_end >= length {
    return None
  }
  // U&'..' UNICODE_STRING_LITERAL: "U" "&" <QUOTED_STRING> (Parser.jj:8719).
  if id_end + 1 < length && id_end - start == 1 && bytes[start].to_int() == 85 &&
    bytes[id_end].to_int() == 38 && bytes[id_end + 1].to_int() == 39 {
    let (end, code) = scan_flink_string(bytes, id_end + 1)
    return Some((end, code))
  }
  // Single-character prefix followed by `'`.
  let quote = bytes[id_end].to_int() == 39
  if !quote || id_end - start != 1 {
    return None
  }
  let first = bytes[start].to_int()
  // X'..' BINARY_STRING_LITERAL: ["x","X"] <QUOTE> ... (:8708).
  if first == 88 || first == 120 {
    let (end, code) = scan_flink_string(bytes, id_end)
    return Some((end, code))
  }
  // N'..' PREFIXED_STRING_LITERAL: ("_" <CHARSETNAME> | "N") <QUOTED_STRING> (:8717).
  if first == 78 {
    let (end, code) = scan_flink_string(bytes, id_end)
    return Some((end, code))
  }
  // E'..' C_STYLE_ESCAPED_STRING_LITERAL, gated by the pinned Calcite version
  // (1.36.0/1.34.0 yes, 1.32.0 no — :8721/8469/absent).
  if first == 69 && flink_supports_escape_literal(context) {
    let (end, code) = scan_flink_escaped_string(bytes, id_end)
    return Some((end, code))
  }
  None
}

/// Flink symbol width: adds CONCAT `||`, NAMED_ARGUMENT_ASSIGNMENT `=>`, and
/// DOUBLE_PERIOD `..` (Parser-calcite-1.36.0.jj:8793-8795) on top of the shared
/// comparison operators; the Doris width is unchanged for the Doris arm.
fn symbol_width_flink(bytes : Bytes, index : Int) -> Int {
  let length = bytes.length()
  if index + 1 < length {
    let first = bytes[index].to_int()
    let second = bytes[index + 1].to_int()
    if (first == 124 && second == 124) || (first == 61 && second == 62) ||
      (first == 46 && second == 46) {
      return 2
    }
  }
  symbol_width(bytes, index)
}

pub fn lex_with_limit(source : @source.SourceText, context : @dialect.DialectContext, max_tokens : Int) -> @token.TokenStream {
  let bytes = source.bytes()
  let source_length = bytes.length()
  let tokens : Array[@token.Token] = []
  let mut index = 0
  let mut truncated_at : Int? = None
  while index < source_length && (max_tokens < 0 || tokens.length() < max_tokens) {
    let byte = bytes[index].to_int()
    if index + 2 < source_length && byte == 239 && bytes[index + 1].to_int() == 187 &&
      bytes[index + 2].to_int() == 191 {
      push_token(tokens, source_length, context, @token.TokenKind::Bom, index, index + 3, None)
      index = index + 3
    } else if byte == 10 || byte == 13 {
      let end = if byte == 13 && index + 1 < source_length && bytes[index + 1].to_int() == 10 {
        index + 2
      } else {
        index + 1
      }
      push_token(tokens, source_length, context, @token.TokenKind::Newline, index, end, None)
      index = end
    } else if is_space(byte) {
      let start = index
      index = index + 1
      while index < source_length && is_space(bytes[index].to_int()) {
        index = index + 1
      }
      push_token(tokens, source_length, context, @token.TokenKind::Whitespace, start, index, None)
    } else if (byte == 45 && index + 1 < source_length && bytes[index + 1].to_int() == 45) || byte == 35 {
      if byte == 35 && context.dialect is @dialect.Dialect::Flink {
        // Flink (D-06, D-03): `#` is NOT a Calcite token (Parser-calcite-*.jj
        // has no `#` in any comment/symbol token set) — a lexical error token
        // whose diagnostic surfaces as FATHOM-PARSE-003 through the parser.
        // Doris keeps `#` as a line comment byte-identically (below).
        push_token(
          tokens,
          source_length,
          context,
          @token.TokenKind::Error,
          index,
          index + 1,
          Some("LEX_INVALID_CHARACTER"),
        )
        index = index + 1
      } else {
        let start = index
        let (end, code) = scan_comment(bytes, if byte == 35 { index } else { index + 1 })
        match push_scanned_with_invalid(tokens, bytes, source_length, context, @token.TokenKind::Comment, start, end, code, max_tokens) {
          Some(at) => if truncated_at is None { truncated_at = Some(at) }
          None => ()
        }
        index = end
      }
    } else if byte == 47 && index + 1 < source_length && bytes[index + 1].to_int() == 47 &&
      context.dialect is @dialect.Dialect::Flink {
      // Flink SINGLE_LINE_COMMENT `//` (Parser-calcite-1.36.0.jj:8901 — the
      // same token accepts "//" and "--"). The Doris arm keeps `//` as two
      // SLASH symbols byte-identically (below, symbol branch).
      let start = index
      let (end, code) = scan_comment(bytes, index)
      match push_scanned_with_invalid(tokens, bytes, source_length, context, @token.TokenKind::Comment, start, end, code, max_tokens) {
        Some(at) => if truncated_at is None { truncated_at = Some(at) }
        None => ()
      }
      index = end
    } else if byte == 47 && index + 1 < source_length && bytes[index + 1].to_int() == 42 {
      let (end, code) = scan_comment(bytes, index)
      match push_scanned_with_invalid(tokens, bytes, source_length, context, @token.TokenKind::Comment, index, end, code, max_tokens) {
        Some(at) => if truncated_at is None { truncated_at = Some(at) }
        None => ()
      }
      index = end
    } else if byte == 39 {
      let start = index
      // Flink `'...'` uses QUOTED_STRING doubling with NO backslash escape
      // (Parser-calcite-1.36.0.jj:8715); the Doris arm keeps backslash escape.
      let (end, code) = if context.dialect is @dialect.Dialect::Flink {
        scan_flink_string(bytes, index)
      } else {
        scan_quoted(bytes, index, byte)
      }
      match push_scanned_with_invalid(tokens, bytes, source_length, context, @token.TokenKind::StringLiteral, start, end, code, max_tokens) {
        Some(at) => if truncated_at is None { truncated_at = Some(at) }
        None => ()
      }
      index = end
    } else if byte == 96 && context.dialect is @dialect.Dialect::Flink {
      // Flink backtick identifier per BTID (double-backtick escape, no
      // backslash escape, no raw newline) — Parser-calcite-1.36.0.jj:8951-8962.
      let start = index
      let (end, code) = scan_flink_backtick(bytes, index)
      match push_scanned_with_invalid(tokens, bytes, source_length, context, @token.TokenKind::Quoted, start, end, code, max_tokens) {
        Some(at) => if truncated_at is None { truncated_at = Some(at) }
        None => ()
      }
      index = end
    } else if byte == 34 && context.dialect is @dialect.Dialect::Flink {
      // Flink DOUBLE_QUOTE symbol (Parser-calcite-1.36.0.jj:8797): no consuming
      // production — at the lexical layer `"` is a Symbol, the parse-level
      // error is Phase 11 grammar's concern. Doris keeps `"` as Quoted below.
      push_token(tokens, source_length, context, @token.TokenKind::Symbol, index, index + 1, None)
      index = index + 1
    } else if byte == 34 || byte == 96 {
      let start = index
      let (end, code) = scan_quoted(bytes, index, byte)
      match push_scanned_with_invalid(tokens, bytes, source_length, context, @token.TokenKind::Quoted, start, end, code, max_tokens) {
        Some(at) => if truncated_at is None { truncated_at = Some(at) }
        None => ()
      }
      index = end
    } else if byte >= 48 && byte <= 57 {
      let start = index
      let (end, valid) = scan_number(bytes, start)
      index = end
      if valid {
        push_token(tokens, source_length, context, @token.TokenKind::Number, start, end, None)
      } else {
        push_token(tokens, source_length, context, @token.TokenKind::Error, start, end, Some("LEX_INVALID_NUMBER"))
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
      let id_end = index
      if context.dialect is @dialect.Dialect::Flink {
        // Flink literal prefixes (X/U&/N/E'..') are ONE literal token — D-03.
        match flink_prefixed_literal(bytes, start, id_end, context) {
          Some((literal_end, code)) => {
            match push_scanned_with_invalid(tokens, bytes, source_length, context, @token.TokenKind::StringLiteral, start, literal_end, code, max_tokens) {
              Some(at) => if truncated_at is None { truncated_at = Some(at) }
              None => ()
            }
            index = literal_end
          }
          None => {
            push_token(tokens, source_length, context, @token.TokenKind::Identifier, start, id_end, None)
          }
        }
      } else {
        push_token(tokens, source_length, context, @token.TokenKind::Identifier, start, id_end, None)
      }
    } else {
      match utf8_width(bytes, index) {
        Some(width) if byte >= 128 => {
          push_token(tokens, source_length, context, @token.TokenKind::Unknown, index, index + width, None)
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
            context,
            @token.TokenKind::Error,
            start,
            index,
            Some("LEX_INVALID_UTF8"),
          )
        }
        _ => {
          let width = if context.dialect is @dialect.Dialect::Flink {
            symbol_width_flink(bytes, index)
          } else {
            symbol_width(bytes, index)
          }
          push_token(tokens, source_length, context, @token.TokenKind::Symbol, index, index + width, None)
          index = index + width
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
    context: context,
    tokens: tokens,
    truncated_at: final_truncated_at,
  }
}

pub fn lex(source : @source.SourceText, context : @dialect.DialectContext) -> @token.TokenStream {
  lex_with_limit(source, context, 1_000_000)
}

test "lexer_preserves_trivia_literals_and_invalid_bytes" {
  let source = match @source.SourceText::new(b"\xef\xbb\xbfSELECT /*x*/ 'a''b' -- c\r\n\xff\xfe") {
    Ok(source) => source
    Err(_) => panic()
  }
  let stream = lex(source, test_doris_context("4.x"))
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
  let stream = lex(source, test_doris_context("4.x"))
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
  let stream = lex(source, test_doris_context("2.1"))
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
  let stream = lex(source, test_doris_context("3.x"))
  let mut replay = b""
  for token in stream.tokens {
    let token_bytes = match token.raw(source) {
      Some(bytes) => bytes
      None => panic()
    }
    replay = replay + token_bytes
    assert_eq(token.context, test_doris_context("3.x"))
  }
  assert_eq(replay, raw)
}

test "lexer_retains_unterminated_quote_and_progresses" {
  let source = match @source.SourceText::new(b"'unterminated") {
    Ok(source) => source
    Err(_) => panic()
  }
  let stream = lex(source, test_doris_context("2.1"))
  assert_eq(stream.length(), 1)
  let token = match stream.at(0) {
    Some(token) => token
    None => panic()
  }
  assert_true(token.kind is @token.TokenKind::StringLiteral)
  assert_eq(token.diagnostic_code, Some("LEX_UNTERMINATED_LITERAL"))
  assert_eq(token.raw(source), Some(b"'unterminated"))
}

fn test_doris_context(profile_id : String) -> @dialect.DialectContext {
  { dialect: @dialect.Dialect::Doris, profile_id: profile_id, exact_release: profile_id, feature_introduction: "" }
}

fn test_flink_context(profile_id : String) -> @dialect.DialectContext {
  { dialect: @dialect.Dialect::Flink, profile_id: profile_id, exact_release: profile_id, feature_introduction: "" }
}

test "lexer_routes_hash_comment_by_dialect_flink_error_doris_comment" {
  let raw = b"a # comment"
  let doris_source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let flink_source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  // Doris: `#` is a line comment (byte-identical v1 behavior).
  let doris_stream = lex(doris_source, test_doris_context("4.x"))
  let doris_hash = match doris_stream.at(2) {
    Some(token) => token
    None => panic()
  }
  assert_true(doris_hash.kind is @token.TokenKind::Comment)
  assert_eq(doris_hash.raw(doris_source), Some(b"# comment"))
  // Flink: `#` is not a Calcite token — a single-byte Error token with a
  // lexical diagnostic code (FATHOM-PARSE-003 surfaces through the parser).
  let flink_stream = lex(flink_source, test_flink_context("flink-2.3.0"))
  let flink_hash = match flink_stream.at(2) {
    Some(token) => token
    None => panic()
  }
  assert_true(flink_hash.kind is @token.TokenKind::Error)
  assert_eq(flink_hash.diagnostic_code, Some("LEX_INVALID_CHARACTER"))
  assert_eq(flink_hash.raw(flink_source), Some(b"#"))
  // Replay both dialects byte-identically (DIALECT-02: span/trivia preserved).
  let mut doris_replay = b""
  for token in doris_stream.tokens {
    let token_bytes = match token.raw(doris_source) {
      Some(bytes) => bytes
      None => b""
    }
    doris_replay = doris_replay + token_bytes
  }
  let mut flink_replay = b""
  for token in flink_stream.tokens {
    let token_bytes = match token.raw(flink_source) {
      Some(bytes) => bytes
      None => b""
    }
    flink_replay = flink_replay + token_bytes
  }
  assert_eq(doris_replay, raw)
  assert_eq(flink_replay, raw)
}

test "lexer_calls_are_reentrant_without_shared_state" {
  let source = match @source.SourceText::new(b"SELECT 1") {
    Ok(source) => source
    Err(_) => panic()
  }
  let first = lex(source, test_doris_context("2.1"))
  let second = lex(source, test_doris_context("4.x"))
  assert_eq(first.length(), second.length())
  assert_eq(first.context, test_doris_context("2.1"))
  assert_eq(second.context, test_doris_context("4.x"))
  assert_eq(first.raw(0), second.raw(0))
}

test "lexer_accepts_decimal_and_scientific_numbers_but_rejects_repeated_dots" {
  let raw = b"1 1.2 1e3 1.2E-3 1..2 1.2.3"
  let source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let stream = lex(source, test_doris_context("4.x"))
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
    let stream = lex_with_limit(source, test_doris_context("4.x"), 3)
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

// ---------------------------------------------------------------------------
// Flink dialect lexical branches (10-02 Task 1, D-03/D-06). Each behavior case
// is grounded in the pinned release grammar evidence (10-RESEARCH.md §9):
// SINGLE_LINE_COMMENT "//"|"--" (Parser-calcite-1.36.0.jj:8901),
// DOUBLE_QUOTE (Parser-calcite-1.36.0.jj:8797), BTID backtick
// (Parser-calcite-1.36.0.jj:8951-8962), BINARY_STRING_LITERAL (:8708),
// UNICODE_STRING_LITERAL (:8719), PREFIXED_STRING_LITERAL (:8717),
// C_STYLE_ESCAPED_STRING_LITERAL (:8721 / 1.34.0:8469 / absent in 1.32.0),
// and CONCAT/NAMED_ARGUMENT_ASSIGNMENT/DOUBLE_PERIOD (:8793-8795).
// ---------------------------------------------------------------------------

test "flink_lexer_slash_comment_routes_by_dialect" {
  let raw = b"a // comment"
  // Flink: `//` is SINGLE_LINE_COMMENT — ONE Comment token.
  let flink_source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let flink_stream = lex(flink_source, test_flink_context("flink-2.3.0"))
  let flink_comment = match flink_stream.at(2) {
    Some(token) => token
    None => panic()
  }
  assert_true(flink_comment.kind is @token.TokenKind::Comment)
  assert_eq(flink_comment.raw(flink_source), Some(b"// comment"))
  assert_eq(flink_comment.span.start_byte, 2)
  assert_eq(flink_comment.span.end_byte, 12)
  // Doris: `//` stays two SLASH symbols (byte-identical v1).
  let doris_source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let doris_stream = lex(doris_source, test_doris_context("4.x"))
  let slash1 = match doris_stream.at(2) {
    Some(token) => token
    None => panic()
  }
  let slash2 = match doris_stream.at(3) {
    Some(token) => token
    None => panic()
  }
  assert_true(slash1.kind is @token.TokenKind::Symbol)
  assert_true(slash2.kind is @token.TokenKind::Symbol)
  assert_eq(slash1.raw(doris_source), Some(b"/"))
  assert_eq(slash2.raw(doris_source), Some(b"/"))
  // Both dialects keep `--` as a line comment (shared SINGLE_LINE_COMMENT family).
  let dash_raw = b"a -- comment"
  let dash_source = match @source.SourceText::new(dash_raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let dash_stream = lex(dash_source, test_flink_context("flink-2.3.0"))
  let dash_comment = match dash_stream.at(2) {
    Some(token) => token
    None => panic()
  }
  assert_true(dash_comment.kind is @token.TokenKind::Comment)
  assert_eq(dash_comment.raw(dash_source), Some(b"-- comment"))
}

test "flink_lexer_double_quote_routes_by_dialect" {
  let raw = b"a \"x\""
  // Flink: `"` is DOUBLE_QUOTE symbol (no consuming production at the lexical
  // layer — Symbol token, not Quoted).
  let flink_source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let flink_stream = lex(flink_source, test_flink_context("flink-2.3.0"))
  let dq_open = match flink_stream.at(2) {
    Some(token) => token
    None => panic()
  }
  assert_true(dq_open.kind is @token.TokenKind::Symbol)
  assert_eq(dq_open.raw(flink_source), Some(b"\""))
  assert_eq(dq_open.span.start_byte, 2)
  assert_eq(dq_open.span.end_byte, 3)
  let ident = match flink_stream.at(3) {
    Some(token) => token
    None => panic()
  }
  assert_true(ident.kind is @token.TokenKind::Identifier)
  assert_eq(ident.raw(flink_source), Some(b"x"))
  let dq_close = match flink_stream.at(4) {
    Some(token) => token
    None => panic()
  }
  assert_true(dq_close.kind is @token.TokenKind::Symbol)
  assert_eq(dq_close.raw(flink_source), Some(b"\""))
  assert_eq(dq_close.span.start_byte, 4)
  assert_eq(dq_close.span.end_byte, 5)
  // Doris: `"x"` is ONE Quoted token (byte-identical v1).
  let doris_source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let doris_stream = lex(doris_source, test_doris_context("4.x"))
  let quoted = match doris_stream.at(2) {
    Some(token) => token
    None => panic()
  }
  assert_true(quoted.kind is @token.TokenKind::Quoted)
  assert_eq(quoted.raw(doris_source), Some(b"\"x\""))
  assert_eq(quoted.span.start_byte, 2)
  assert_eq(quoted.span.end_byte, 5)
}

test "flink_lexer_backtick_btid_escaping" {
  // `` `a``b` `` is ONE Quoted token: double-backtick escape per BTID.
  let raw = b"`a``b`"
  let source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let stream = lex(source, test_flink_context("flink-2.3.0"))
  assert_eq(stream.length(), 1)
  let token = match stream.at(0) {
    Some(token) => token
    None => panic()
  }
  assert_true(token.kind is @token.TokenKind::Quoted)
  assert_eq(token.raw(source), Some(b"`a``b`"))
  assert_eq(token.span.start_byte, 0)
  assert_eq(token.span.end_byte, 6)
  // BTID has no backslash escape: `\` inside a backtick is a literal char, so
  // `` `x\` `` closes at the final backtick (not unterminated like the Doris
  // backslash-escaping scanner).
  let bs_raw = b"`x\\`"
  let bs_source = match @source.SourceText::new(bs_raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let bs_stream = lex(bs_source, test_flink_context("flink-2.3.0"))
  assert_eq(bs_stream.length(), 1)
  let bs_token = match bs_stream.at(0) {
    Some(token) => token
    None => panic()
  }
  assert_true(bs_token.kind is @token.TokenKind::Quoted)
  assert_eq(bs_token.diagnostic_code, None)
  assert_eq(bs_token.raw(bs_source), Some(b"`x\\`"))
  // A lone backtick is the unterminated-literal error path (FATHOM-PARSE-003).
  let lone_source = match @source.SourceText::new(b"`") {
    Ok(source) => source
    Err(_) => panic()
  }
  let lone_stream = lex(lone_source, test_flink_context("flink-2.3.0"))
  assert_eq(lone_stream.length(), 1)
  let lone = match lone_stream.at(0) {
    Some(token) => token
    None => panic()
  }
  assert_true(lone.kind is @token.TokenKind::Quoted)
  assert_eq(lone.diagnostic_code, Some("LEX_UNTERMINATED_LITERAL"))
}

test "flink_lexer_e_literal_is_profile_gated" {
  // E'..' is C_STYLE_ESCAPED_STRING_LITERAL in Calcite 1.36.0 (Parser.jj:8721)
  // and 1.34.0 (:8469) but ABSENT in 1.32.0 (flink-1.20.5).
  let raw = b"E'\\n'"
  for profile in ["flink-2.3.0", "flink-2.1.3"] {
    let source = match @source.SourceText::new(raw) {
      Ok(source) => source
      Err(_) => panic()
    }
    let stream = lex(source, test_flink_context(profile))
    assert_eq(stream.length(), 1)
    let token = match stream.at(0) {
      Some(token) => token
      None => panic()
    }
    assert_true(token.kind is @token.TokenKind::StringLiteral)
    assert_eq(token.raw(source), Some(b"E'\\n'"))
    assert_eq(token.span.start_byte, 0)
    assert_eq(token.span.end_byte, 5)
  }
  // flink-1.20.5: Identifier `E` + StringLiteral `'\n'`.
  let v1_source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let v1_stream = lex(v1_source, test_flink_context("flink-1.20.5"))
  assert_eq(v1_stream.length(), 2)
  let e = match v1_stream.at(0) {
    Some(token) => token
    None => panic()
  }
  let str = match v1_stream.at(1) {
    Some(token) => token
    None => panic()
  }
  assert_true(e.kind is @token.TokenKind::Identifier)
  assert_eq(e.raw(v1_source), Some(b"E"))
  assert_true(str.kind is @token.TokenKind::StringLiteral)
  assert_eq(str.raw(v1_source), Some(b"'\\n'"))
}

test "flink_lexer_prefixed_literals_and_b_not_prefix" {
  // X'AB' -> ONE literal token (BINARY_STRING_LITERAL, Parser-calcite-1.36.0.jj:8708).
  let x_source = match @source.SourceText::new(b"X'AB'") {
    Ok(source) => source
    Err(_) => panic()
  }
  let x_stream = lex(x_source, test_flink_context("flink-2.3.0"))
  assert_eq(x_stream.length(), 1)
  let x_tok = match x_stream.at(0) {
    Some(token) => token
    None => panic()
  }
  assert_true(x_tok.kind is @token.TokenKind::StringLiteral)
  assert_eq(x_tok.raw(x_source), Some(b"X'AB'"))
  assert_eq(x_tok.span.start_byte, 0)
  assert_eq(x_tok.span.end_byte, 5)
  // U&'d\0061t' -> ONE literal token (UNICODE_STRING_LITERAL, :8719).
  let u_source = match @source.SourceText::new(b"U&'d\\0061t'") {
    Ok(source) => source
    Err(_) => panic()
  }
  let u_stream = lex(u_source, test_flink_context("flink-2.3.0"))
  assert_eq(u_stream.length(), 1)
  let u_tok = match u_stream.at(0) {
    Some(token) => token
    None => panic()
  }
  assert_true(u_tok.kind is @token.TokenKind::StringLiteral)
  assert_eq(u_tok.raw(u_source), Some(b"U&'d\\0061t'"))
  // N'name' -> ONE literal token (PREFIXED_STRING_LITERAL, :8717).
  let n_source = match @source.SourceText::new(b"N'name'") {
    Ok(source) => source
    Err(_) => panic()
  }
  let n_stream = lex(n_source, test_flink_context("flink-2.3.0"))
  assert_eq(n_stream.length(), 1)
  let n_tok = match n_stream.at(0) {
    Some(token) => token
    None => panic()
  }
  assert_true(n_tok.kind is @token.TokenKind::StringLiteral)
  assert_eq(n_tok.raw(n_source), Some(b"N'name'"))
  // B'101' -> Identifier `B` + StringLiteral `'101'` (NO BIT_STRING_LITERAL
  // token in any pinned release — `B` is not a literal prefix).
  let b_source = match @source.SourceText::new(b"B'101'") {
    Ok(source) => source
    Err(_) => panic()
  }
  let b_stream = lex(b_source, test_flink_context("flink-2.3.0"))
  assert_eq(b_stream.length(), 2)
  let b_id = match b_stream.at(0) {
    Some(token) => token
    None => panic()
  }
  let b_str = match b_stream.at(1) {
    Some(token) => token
    None => panic()
  }
  assert_true(b_id.kind is @token.TokenKind::Identifier)
  assert_eq(b_id.raw(b_source), Some(b"B"))
  assert_true(b_str.kind is @token.TokenKind::StringLiteral)
  assert_eq(b_str.raw(b_source), Some(b"'101'"))
}

test "flink_lexer_operator_symbols_single_tokens" {
  // || CONCAT (Parser-calcite-1.36.0.jj:8793).
  let concat_source = match @source.SourceText::new(b"a || b") {
    Ok(source) => source
    Err(_) => panic()
  }
  let concat_stream = lex(concat_source, test_flink_context("flink-2.3.0"))
  let concat = match concat_stream.at(2) {
    Some(token) => token
    None => panic()
  }
  assert_true(concat.kind is @token.TokenKind::Symbol)
  assert_eq(concat.raw(concat_source), Some(b"||"))
  assert_eq(concat.span.start_byte, 2)
  assert_eq(concat.span.end_byte, 4)
  // => NAMED_ARGUMENT_ASSIGNMENT (:8794).
  let arrow_source = match @source.SourceText::new(b"f(x => 1)") {
    Ok(source) => source
    Err(_) => panic()
  }
  let arrow_stream = lex(arrow_source, test_flink_context("flink-2.3.0"))
  let arrow = match arrow_stream.at(4) {
    Some(token) => token
    None => panic()
  }
  assert_true(arrow.kind is @token.TokenKind::Symbol)
  assert_eq(arrow.raw(arrow_source), Some(b"=>"))
  assert_eq(arrow.span.start_byte, 4)
  assert_eq(arrow.span.end_byte, 6)
  // .. DOUBLE_PERIOD (:8795).
  let period_source = match @source.SourceText::new(b"t..c") {
    Ok(source) => source
    Err(_) => panic()
  }
  let period_stream = lex(period_source, test_flink_context("flink-2.3.0"))
  let period = match period_stream.at(1) {
    Some(token) => token
    None => panic()
  }
  assert_true(period.kind is @token.TokenKind::Symbol)
  assert_eq(period.raw(period_source), Some(b".."))
  assert_eq(period.span.start_byte, 1)
  assert_eq(period.span.end_byte, 3)
}

test "flink_lexer_comparison_operators_remain_single_symbols_both_dialects" {
  // The Doris multi-char comparison ops (<=, >=, <>, !=, <=>) stay single
  // symbols under BOTH dialects (Pitfall 1: Doris byte-identical; Flink uses
  // the same Calcite LE/GE/NE/NE2 tokens, Parser-calcite-1.36.0.jj:8792-8793).
  for raw in [b"a <= b", b"a >= b", b"a <> b", b"a != b", b"a <=> b"] {
    let expected_width = if raw.length() == 7 { 3 } else { 2 }
    let flink_source = match @source.SourceText::new(raw) {
      Ok(source) => source
      Err(_) => panic()
    }
    let flink_stream = lex(flink_source, test_flink_context("flink-2.3.0"))
    let flink_op = match flink_stream.at(2) {
      Some(token) => token
      None => panic()
    }
    assert_true(flink_op.kind is @token.TokenKind::Symbol)
    assert_eq(flink_op.span.end_byte - flink_op.span.start_byte, expected_width)
    let doris_source = match @source.SourceText::new(raw) {
      Ok(source) => source
      Err(_) => panic()
    }
    let doris_stream = lex(doris_source, test_doris_context("4.x"))
    let doris_op = match doris_stream.at(2) {
      Some(token) => token
      None => panic()
    }
    assert_true(doris_op.kind is @token.TokenKind::Symbol)
    assert_eq(doris_op.span.end_byte - doris_op.span.start_byte, expected_width)
  }
}
