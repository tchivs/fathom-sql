/// A small recursive-descent document parser with one Pratt expression path.
pub(all) enum ParseMode {
  Strict
  Editor
}

pub struct ParserDiagnostic {
  pub severity : String
  pub code : String
  pub message : String
  pub expected_class : String
  pub span : @source.Span
  pub statement_id : Int
}

pub struct ParsedDocument {
  pub source : @source.SourceText
  pub profile : @token.DorisProfile
  pub mode : ParseMode
  pub root : @syntax.SyntaxNode
  pub diagnostics : Array[ParserDiagnostic]
  pub valid : Bool
  pub recovered : Bool
}

struct Cursor {
  stream : @token.TokenStream
  indices : Array[Int]
  mut position : Int
}

fn token_at(cursor : Cursor) -> @token.Token? {
  match cursor.indices.get(cursor.position) {
    Some(index) => cursor.stream.at(index)
    None => None
  }
}

fn raw_at(cursor : Cursor) -> Bytes? {
  match cursor.indices.get(cursor.position) {
    Some(index) => cursor.stream.raw(index)
    None => None
  }
}

fn advance(cursor : Cursor) -> Unit {
  cursor.position = cursor.position + 1
}

fn bytes_equal_ci(actual : Bytes, expected : Bytes) -> Bool {
  if actual.length() != expected.length() {
    false
  } else {
    let mut index = 0
    let mut equal = true
    while index < actual.length() {
      let left = actual[index].to_int()
      let right = expected[index].to_int()
      let folded_left = if left >= 97 && left <= 122 { left - 32 } else { left }
      let folded_right = if right >= 97 && right <= 122 { right - 32 } else { right }
      if folded_left != folded_right {
        equal = false
      }
      index = index + 1
    }
    equal
  }
}

fn is_keyword(bytes : Bytes, word : Bytes) -> Bool {
  bytes_equal_ci(bytes, word)
}

fn make_span(source : @source.SourceText, start_byte : Int, end_byte : Int) -> @source.Span {
  match source.span(start_byte, end_byte) {
    Ok(span) => span
    Err(_) => panic()
  }
}

fn add_diagnostic(
  diagnostics : Array[ParserDiagnostic],
  code : String,
  message : String,
  expected_class : String,
  span : @source.Span,
  statement_id : Int,
) -> Unit {
  diagnostics.push({
    severity: "error",
    code: code,
    message: message,
    expected_class: expected_class,
    span: span,
    statement_id: statement_id,
  })
}

fn precedence(cursor : Cursor) -> Int? {
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, b"OR") => Some(1)
    Some(raw) if bytes_equal_ci(raw, b"AND") => Some(2)
    Some(raw) if raw == b"=" || raw == b"<" || raw == b">" || raw == b"<=" ||
      raw == b">=" || raw == b"<>" || raw == b"!=" => Some(3)
    Some(raw) if raw == b"+" || raw == b"-" => Some(4)
    Some(raw) if raw == b"*" || raw == b"/" || raw == b"%" => Some(5)
    _ => None
  }
}

fn is_expression_operand(token : @token.Token) -> Bool {
  match token.kind {
    @token.TokenKind::Identifier | @token.TokenKind::Quoted |
    @token.TokenKind::StringLiteral | @token.TokenKind::Number => true
    _ => false
  }
}

fn parse_expression(
  cursor : Cursor,
  minimum_precedence : Int,
  diagnostics : Array[ParserDiagnostic],
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  let prefix_ok = match token_at(cursor) {
    Some(token) if is_expression_operand(token) => {
      advance(cursor)
      true
    }
    Some(token) if token.kind is @token.TokenKind::Symbol => match raw_at(cursor) {
      Some(raw) if raw == b"(" => {
        advance(cursor)
        let nested = parse_expression(cursor, 1, diagnostics, source, statement_id)
        match raw_at(cursor) {
          Some(raw) if raw == b")" => advance(cursor)
          _ => add_diagnostic(
            diagnostics,
            "DORIS-PARSE-002",
            "expected closing parenthesis",
            "expression delimiter",
            token.span,
            statement_id,
          )
        }
        nested
      }
      _ => {
        add_diagnostic(
          diagnostics,
          "DORIS-PARSE-002",
          "expected literal or identifier expression",
          "expression",
          token.span,
          statement_id,
        )
        false
      }
    }
    Some(token) => {
      add_diagnostic(
        diagnostics,
        "DORIS-PARSE-002",
        "expected literal or identifier expression",
        "expression",
        token.span,
        statement_id,
      )
      false
    }
    None => {
      let at = source.byte_length()
      add_diagnostic(
        diagnostics,
        "DORIS-PARSE-002",
        "expected literal or identifier expression",
        "expression",
        make_span(source, at, at),
        statement_id,
      )
      false
    }
  }
  if !prefix_ok {
    false
  } else {
    let mut keep_going = true
    while keep_going {
      match precedence(cursor) {
        Some(operator_precedence) if operator_precedence >= minimum_precedence => {
          advance(cursor)
          let rhs = parse_expression(
            cursor,
            operator_precedence + 1,
            diagnostics,
            source,
            statement_id,
          )
          if !rhs {
            keep_going = false
          }
        }
        _ => keep_going = false
      }
    }
    true
  }
}

fn significant_indices(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
) -> Array[Int] {
  let indices : Array[Int] = []
  let mut index = start_index
  while index < end_index {
    match stream.at(index) {
      Some(token) if token.is_trivia() => ()
      Some(_) => indices.push(index)
      None => ()
    }
    index = index + 1
  }
  indices
}

fn leaf_for_token(token : @token.Token) -> @syntax.SyntaxElement {
  let kind = match token.kind {
    @token.TokenKind::Whitespace | @token.TokenKind::Newline |
    @token.TokenKind::Comment | @token.TokenKind::Bom => @syntax.LeafKind::SourceTrivia
    @token.TokenKind::Error => @syntax.LeafKind::SourceError
    @token.TokenKind::Unknown => @syntax.LeafKind::SourceSkipped
    _ => @syntax.LeafKind::SourceToken
  }
  @syntax.SyntaxElement::Leaf(@syntax.SyntaxLeaf::new(kind, token.span))
}

fn segment_children(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
) -> Array[@syntax.SyntaxElement] {
  let children : Array[@syntax.SyntaxElement] = []
  let mut index = start_index
  while index < end_index {
    match stream.at(index) {
      Some(token) => children.push(leaf_for_token(token))
      None => ()
    }
    index = index + 1
  }
  children
}

fn segment_span(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
) -> @source.Span {
  if start_index >= end_index {
    let at = if start_index < stream.length() {
      match stream.at(start_index) {
        Some(token) => token.span.start_byte
        None => stream.source.byte_length()
      }
    } else {
      stream.source.byte_length()
    }
    make_span(stream.source, at, at)
  } else {
    let start = match stream.at(start_index) {
      Some(token) => token.span.start_byte
      None => stream.source.byte_length()
    }
    let end = match stream.at(end_index - 1) {
      Some(token) => token.span.end_byte
      None => start
    }
    make_span(stream.source, start, end)
  }
}

fn parse_segment(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
  statement_id : Int,
  diagnostics : Array[ParserDiagnostic],
) -> @syntax.SyntaxNode {
  let span = segment_span(stream, start_index, end_index)
  let children = segment_children(stream, start_index, end_index)
  let indices = significant_indices(stream, start_index, end_index)
  let selected = match indices.get(0) {
    Some(first_index) => match stream.raw(first_index) {
      Some(raw) if is_keyword(raw, b"SELECT") => true
      Some(_) => {
        add_diagnostic(
          diagnostics,
          "DORIS-PARSE-001",
          "expected SELECT statement",
          "statement",
          span,
          statement_id,
        )
        false
      }
      None => false
    }
    None => false
  }
  let statement_children : Array[@syntax.SyntaxElement] = []
  if selected {
    let cursor = { stream: stream, indices: indices, position: 1 }
    let has_expression = match token_at(cursor) {
      Some(_) => parse_expression(cursor, 1, diagnostics, stream.source, statement_id)
      None => {
        let at = span.end_byte
        add_diagnostic(
          diagnostics,
          "DORIS-PARSE-002",
          "expected expression after SELECT",
          "expression",
          make_span(stream.source, at, at),
          statement_id,
        )
        false
      }
    }
    if !has_expression {
      children.push(@syntax.SyntaxElement::ChildNode(@syntax.SyntaxNode::missing(span.end_byte)))
    }
    let select = @syntax.SyntaxNode::new(@syntax.SyntaxKind::Select, span, children)
    statement_children.push(@syntax.SyntaxElement::ChildNode(select))
  } else {
    let error = @syntax.SyntaxNode::new(@syntax.SyntaxKind::Error, span, children)
    statement_children.push(@syntax.SyntaxElement::ChildNode(error))
  }
  @syntax.SyntaxNode::new(@syntax.SyntaxKind::Statement, span, statement_children)
}

pub fn parse(
  source : @source.SourceText,
  profile : @token.DorisProfile,
  mode : ParseMode,
) -> ParsedDocument {
  let stream = @lexer.lex(source, profile)
  let root_span = make_span(source, 0, source.byte_length())
  let diagnostics : Array[ParserDiagnostic] = []
  let root_children : Array[@syntax.SyntaxElement] = []
  let mut segment_start = 0
  let mut statement_id = 0
  let mut index = 0
  while index < stream.length() {
    let is_semicolon = match stream.raw(index) {
      Some(raw) => raw == b";"
      None => false
    }
    if is_semicolon {
      let segment_end = index + 1
      let segment = parse_segment(
        stream,
        segment_start,
        segment_end,
        statement_id,
        diagnostics,
      )
      if segment.span().length() > 0 {
        root_children.push(@syntax.SyntaxElement::ChildNode(segment))
        statement_id = statement_id + 1
      }
      segment_start = segment_end
    }
    index = index + 1
  }
  if segment_start < stream.length() {
    let segment = parse_segment(
      stream,
      segment_start,
      stream.length(),
      statement_id,
      diagnostics,
    )
    if segment.span().length() > 0 {
      root_children.push(@syntax.SyntaxElement::ChildNode(segment))
    }
  }
  // Lexical errors are retained in the CST and become parser diagnostics.
  for token in stream.tokens {
    if token.is_error() {
      add_diagnostic(
        diagnostics,
        "DORIS-PARSE-003",
        "invalid source encoding or unterminated lexical material",
        "lexical material",
        token.span,
        0,
      )
    }
  }
  let valid = diagnostics.length() == 0
  {
    source: source,
    profile: profile,
    mode: mode,
    root: @syntax.SyntaxNode::new(@syntax.SyntaxKind::Document, root_span, root_children),
    diagnostics: diagnostics,
    valid: valid,
    recovered: !valid && mode is ParseMode::Editor,
  }
}

test "parser_select_pratt_and_statement_identity" {
  let source = match @source.SourceText::new(b"SELECT a + 1; SELECT b") {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = parse(source, @token.DorisProfile::V4_X, ParseMode::Strict)
  assert_true(parsed.root.kind() is @syntax.SyntaxKind::Document)
  assert_eq(parsed.root.children().length(), 2)
  assert_true(parsed.valid)
  assert_eq(parsed.diagnostics.length(), 0)
}

test "parser_reports_incomplete_without_losing_source" {
  let source = match @source.SourceText::new(b"SELECT") {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = parse(source, @token.DorisProfile::V2_1, ParseMode::Editor)
  assert_true(!parsed.valid)
  assert_true(parsed.recovered)
  assert_eq(parsed.diagnostics[0].code, "DORIS-PARSE-002")
  assert_eq(parsed.diagnostics[0].statement_id, 0)
  assert_true(parsed.root.leaf_count() > 0)
}
