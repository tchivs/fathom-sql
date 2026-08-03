/// A bounded recursive-descent document parser with one Pratt expression path.
/// Recovery always either consumes input or creates an explicit zero-width node.
pub(all) enum ParseMode {
  Strict
  Editor
}

pub struct ParserLimits {
  pub max_bytes : Int
  pub max_tokens : Int
  pub max_recursion_depth : Int
  pub max_recovery_steps : Int
  pub max_diagnostics : Int
}

pub fn ParserLimits::default() -> ParserLimits {
  {
    max_bytes: 8 * 1024 * 1024,
    max_tokens: 1_000_000,
    max_recursion_depth: 128,
    max_recovery_steps: 10_000,
    max_diagnostics: 100,
  }
}
pub fn ParserLimits::new(
  max_bytes : Int,
  max_tokens : Int,
  max_recursion_depth : Int,
  max_recovery_steps : Int,
  max_diagnostics : Int,
) -> ParserLimits {
  {
    max_bytes: max_bytes,
    max_tokens: max_tokens,
    max_recursion_depth: max_recursion_depth,
    max_recovery_steps: max_recovery_steps,
    max_diagnostics: max_diagnostics,
  }
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

struct RecoveryState {
  diagnostics : Array[ParserDiagnostic]
  limits : ParserLimits
  mut recovery_steps : Int
  mut resource_emitted : Bool
}

fn token_at(cursor : Cursor) -> @token.Token? {
  cursor.indices.get(cursor.position).map(index => cursor.stream.at(index)).flatten()
}

fn raw_at(cursor : Cursor) -> Bytes? {
  cursor.indices.get(cursor.position).map(index => cursor.stream.raw(index)).flatten()
}

fn advance(cursor : Cursor) -> Unit {
  if cursor.position < cursor.indices.length() {
    cursor.position = cursor.position + 1
  }
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

fn resource_diagnostic(state : RecoveryState, span : @source.Span, statement_id : Int) -> Unit {
  if !state.resource_emitted {
    state.resource_emitted = true
    // A resource diagnostic is allowed to occupy the final diagnostic slot.
    let limit = if state.limits.max_diagnostics <= 0 { 1 } else { state.limits.max_diagnostics }
    if state.diagnostics.length() >= limit {
      if limit == 1 {
        state.diagnostics[0] = {
          severity: "error",
          code: "DORIS-PARSE-004",
          message: "parser resource limit reached",
          expected_class: "resource",
          span: span,
          statement_id: statement_id,
        }
      }
    } else {
      state.diagnostics.push({
        severity: "error",
        code: "DORIS-PARSE-004",
        message: "parser resource limit reached",
        expected_class: "resource",
        span: span,
        statement_id: statement_id,
      })
    }
  }
}

fn add_diagnostic(
  state : RecoveryState,
  code : String,
  message : String,
  expected_class : String,
  span : @source.Span,
  statement_id : Int,
) -> Unit {
  let limit = if state.limits.max_diagnostics <= 0 { 1 } else { state.limits.max_diagnostics }
  // Reserve the last slot for one deterministic resource diagnostic when a
  // diagnostic cap is reached. This keeps output finite and predictable.
  if state.diagnostics.length() + 1 >= limit {
    resource_diagnostic(state, span, statement_id)
  } else {
    state.diagnostics.push({
      severity: "error",
      code: code,
      message: message,
      expected_class: expected_class,
      span: span,
      statement_id: statement_id,
    })
  }
}

fn consume_recovery_step(
  state : RecoveryState,
  span : @source.Span,
  statement_id : Int,
) -> Bool {
  if state.recovery_steps >= state.limits.max_recovery_steps {
    resource_diagnostic(state, span, statement_id)
    false
  } else {
    state.recovery_steps = state.recovery_steps + 1
    true
  }
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
  depth : Int,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  let current_span = match token_at(cursor) {
    Some(token) => token.span
    None => make_span(source, source.byte_length(), source.byte_length())
  }
  if depth > state.limits.max_recursion_depth {
    resource_diagnostic(state, current_span, statement_id)
    return false
  }
  let prefix_ok = match token_at(cursor) {
    Some(token) if is_expression_operand(token) => {
      advance(cursor)
      true
    }
    Some(token) if token.kind is @token.TokenKind::Symbol => match raw_at(cursor) {
      Some(raw) if raw == b"(" => {
        advance(cursor)
        let nested = parse_expression(
          cursor,
          1,
          depth + 1,
          state,
          source,
          statement_id,
        )
        match raw_at(cursor) {
          Some(close) if close == b")" => advance(cursor)
          _ => {
            add_diagnostic(
              state,
              "DORIS-PARSE-002",
              "expected closing parenthesis",
              "expression delimiter",
              token.span,
              statement_id,
            )
          }
        }
        nested
      }
      _ => {
        add_diagnostic(
          state,
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
        state,
        "DORIS-PARSE-002",
        "expected literal or identifier expression",
        "expression",
        token.span,
        statement_id,
      )
      false
    }
    None => {
      add_diagnostic(
        state,
        "DORIS-PARSE-002",
        "expected literal or identifier expression",
        "expression",
        current_span,
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
          let before = cursor.position
          advance(cursor)
          let rhs = parse_expression(
            cursor,
            operator_precedence + 1,
            depth + 1,
            state,
            source,
            statement_id,
          )
          if !rhs && cursor.position == before + 1 {
            // The operator was consumed but its operand was not. The caller
            // will add a zero-width MISSING node and synchronize.
            keep_going = false
          } else if !rhs {
            keep_going = false
          }
        }
        _ => keep_going = false
      }
    }
    true
  }
}

fn significant_indices(stream : @token.TokenStream, start_index : Int, end_index : Int) -> Array[Int] {
  let indices : Array[Int] = []
  let mut index = start_index
  while index < end_index {
    match stream.at(index) {
      Some(token) if token.is_trivia() || token.kind is @token.TokenKind::Bom => ()
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

fn is_clause_keyword(raw : Bytes) -> Bool {
  bytes_equal_ci(raw, b"FROM") || bytes_equal_ci(raw, b"WHERE") ||
    bytes_equal_ci(raw, b"GROUP") || bytes_equal_ci(raw, b"HAVING") ||
    bytes_equal_ci(raw, b"ORDER") || bytes_equal_ci(raw, b"LIMIT") ||
    bytes_equal_ci(raw, b"JOIN") || bytes_equal_ci(raw, b"UNION") ||
    bytes_equal_ci(raw, b"QUALIFY") || bytes_equal_ci(raw, b"WINDOW")
}

fn recover_expression(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Unit {
  let mut consumed = false
  let mut done = false
  while !done {
    match raw_at(cursor) {
      None => done = true
      Some(raw) if raw == b")" || raw == b"," || raw == b";" || is_clause_keyword(raw) => done = true
      Some(_) => {
        let span = match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        if consume_recovery_step(state, span, statement_id) {
          advance(cursor)
          consumed = true
        } else {
          done = true
        }
      }
    }
  }
  // Ensure a malformed rule never leaves a non-delimiter token untouched.
  if !consumed && raw_at(cursor) is Some(_) {
    match raw_at(cursor) {
      Some(raw) if raw == b")" || raw == b"," || raw == b";" || is_clause_keyword(raw) => ()
      _ => advance(cursor)
    }
    }
}

fn validate_clause_tail(
  cursor : Cursor,
  expression_ok : Bool,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  let mut valid = expression_ok
  match raw_at(cursor) {
    Some(raw) if raw == b"," => {
      let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "DORIS-PARSE-002", "expected expression after comma", "expression", span, statement_id)
      valid = false
    }
    Some(raw) if is_clause_keyword(raw) => {
      // The first clause keyword may be followed by an operand. Detect a
      // missing operand without consuming the next statement.
      let before = cursor.position
      advance(cursor)
      if raw == b"FROM" || raw == b"WHERE" || raw == b"HAVING" || raw == b"LIMIT" {
        if raw_at(cursor) is None || raw_at(cursor) is Some(b";") {
          let at = if before < cursor.indices.length() { match cursor.stream.at(cursor.indices[before]) { Some(token) => token.span.end_byte; None => source.byte_length() } } else { source.byte_length() }
          add_diagnostic(state, "DORIS-PARSE-005", "expected clause expression", "clause", make_span(source, at, at), statement_id)
          valid = false
        }
      }
      // Clause synchronization is deliberately shallow in this slice; later
      // grammar plans own the clause productions.
    }
    Some(raw) if raw == b")" => {
      add_diagnostic(state, "DORIS-PARSE-002", "unexpected closing parenthesis", "expression delimiter", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id)
      valid = false
    }
    _ => ()
  }
  valid
}

fn parse_segment(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
  statement_id : Int,
  state : RecoveryState,
) -> @syntax.SyntaxNode {
  let span = segment_span(stream, start_index, end_index)
  let children = segment_children(stream, start_index, end_index)
  let indices = significant_indices(stream, start_index, end_index)
  let selected = match indices.get(0) {
    Some(first_index) => match stream.raw(first_index) {
      Some(raw) if is_keyword(raw, b"SELECT") => true
      Some(_) => {
        add_diagnostic(state, "DORIS-PARSE-001", "expected SELECT statement", "statement", span, statement_id)
        false
      }
      None => false
    }
    None => false
  }
  let statement_children : Array[@syntax.SyntaxElement] = []
  if selected {
    let cursor = { stream: stream, indices: indices, position: 1 }
    let expression_start = cursor.position
    let expression_ok = match token_at(cursor) {
      Some(_) => parse_expression(cursor, 1, 1, state, stream.source, statement_id)
      None => {
        let at = span.end_byte
        add_diagnostic(state, "DORIS-PARSE-002", "expected expression after SELECT", "expression", make_span(stream.source, at, at), statement_id)
        false
      }
    }
    let mut valid_tail = validate_clause_tail(cursor, expression_ok, state, stream.source, statement_id)
    if !expression_ok || cursor.position == expression_start {
      recover_expression(cursor, state, stream.source, statement_id)
      valid_tail = false
    }
    if !valid_tail {
      // Missing nodes are zero-width and therefore cannot change replay.
      let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => span.end_byte }
      children.push(@syntax.SyntaxElement::ChildNode(@syntax.SyntaxNode::missing(at)))
    }
    let select = @syntax.SyntaxNode::new(@syntax.SyntaxKind::Select, span, children)
    statement_children.push(@syntax.SyntaxElement::ChildNode(select))
  } else {
    let error = @syntax.SyntaxNode::new(@syntax.SyntaxKind::Error, span, children)
    statement_children.push(@syntax.SyntaxElement::ChildNode(error))
  }
  @syntax.SyntaxNode::new(@syntax.SyntaxKind::Statement, span, statement_children)
}

fn statement_id_for_span(stream : @token.TokenStream, span : @source.Span) -> Int {
  let mut statement_id = 0
  for token in stream.tokens {
    if token.span.start_byte >= span.start_byte {
      break
    }
    match stream.source.slice(token.span) {
      Some(raw) if raw == b";" => statement_id = statement_id + 1
      _ => ()
    }
  }
  statement_id
}

fn append_skipped(
  root_children : Array[@syntax.SyntaxElement],
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
) -> Unit {
  if start_index < end_index {
    let span = segment_span(stream, start_index, end_index)
    let node = @syntax.SyntaxNode::new(
      @syntax.SyntaxKind::Skipped,
      span,
      segment_children(stream, start_index, end_index),
    )
    root_children.push(@syntax.SyntaxElement::ChildNode(node))
  } else if start_index == 0 && stream.source.byte_length() > 0 {
    let span = make_span(stream.source, 0, stream.source.byte_length())
    root_children.push(@syntax.SyntaxElement::ChildNode(@syntax.SyntaxNode::new(
      @syntax.SyntaxKind::Skipped,
      span,
      segment_children(stream, 0, end_index),
    )))
  }
}

pub fn parse_with_limits(
  source : @source.SourceText,
  profile : @token.DorisProfile,
  mode : ParseMode,
  limits : ParserLimits,
) -> ParsedDocument {
  let stream = @lexer.lex(source, profile)
  let root_span = make_span(source, 0, source.byte_length())
  let state = RecoveryState::{
    diagnostics: [],
    limits: limits,
    recovery_steps: 0,
    resource_emitted: false,
  }
  let root_children : Array[@syntax.SyntaxElement] = []
  let mut parse_end = stream.length()
  let mut cut_index = stream.length()
  if source.byte_length() > limits.max_bytes {
    let mut index = 0
    while index < stream.length() {
      match stream.at(index) {
        Some(token) if token.span.end_byte > limits.max_bytes => { cut_index = index; break }
        _ => index = index + 1
      }
    }
    parse_end = cut_index
    resource_diagnostic(state, make_span(source, if cut_index < stream.length() { match stream.at(cut_index) { Some(token) => token.span.start_byte; None => limits.max_bytes } } else { limits.max_bytes }, source.byte_length()), 0)
  }
  if stream.length() > limits.max_tokens && parse_end > limits.max_tokens {
    parse_end = limits.max_tokens
    cut_index = limits.max_tokens
    let at = if cut_index < stream.length() { match stream.at(cut_index) { Some(token) => token.span.start_byte; None => source.byte_length() } } else { source.byte_length() }
    resource_diagnostic(state, make_span(source, at, source.byte_length()), 0)
  }
  let mut segment_start = 0
  let mut statement_id = 0
  let mut index = 0
  while index < parse_end {
    let is_semicolon = match stream.raw(index) { Some(raw) => raw == b";"; None => false }
    if is_semicolon {
      let segment_end = index + 1
      let segment = parse_segment(stream, segment_start, segment_end, statement_id, state)
      if segment.span().length() > 0 {
        root_children.push(@syntax.SyntaxElement::ChildNode(segment))
        statement_id = statement_id + 1
      }
      segment_start = segment_end
    }
    index = index + 1
  }
  if segment_start < parse_end {
    let segment = parse_segment(stream, segment_start, parse_end, statement_id, state)
    if segment.span().length() > 0 {
      root_children.push(@syntax.SyntaxElement::ChildNode(segment))
      statement_id = statement_id + 1
    }
  }
  if cut_index < stream.length() {
    append_skipped(root_children, stream, cut_index, stream.length())
  }
  // Lexical errors are retained in source-backed ERROR leaves and receive a
  // stable encoding/lexical diagnostic independent of editor recovery mode.
  for token in stream.tokens {
    if token.is_error() || token.diagnostic_code is Some(_) {
      add_diagnostic(
        state,
        "DORIS-PARSE-003",
        "invalid source encoding or unterminated lexical material",
        "lexical material",
        token.span,
        statement_id_for_span(stream, token.span),
      )
    }
  }
  let valid = state.diagnostics.length() == 0
  {
    source: source,
    profile: profile,
    mode: mode,
    root: @syntax.SyntaxNode::new(@syntax.SyntaxKind::Document, root_span, root_children),
    diagnostics: state.diagnostics,
    valid: valid,
    recovered: !valid && mode is ParseMode::Editor,
  }
}

pub fn parse(
  source : @source.SourceText,
  profile : @token.DorisProfile,
  mode : ParseMode,
) -> ParsedDocument {
  parse_with_limits(source, profile, mode, ParserLimits::default())
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

test "parser_statement_and_select_spans_are_source_ordered" {
  let source = match @source.SourceText::new(b"SELECT 1; SELECT x") {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = parse(source, @token.DorisProfile::V3_X, ParseMode::Strict)
  let statements = parsed.root.children()
  assert_eq(statements.length(), 2)
  assert_true(statements[0].span().end_byte <= statements[1].span().start_byte)
  assert_true(statements[0].text_len() > 0)
  assert_true(statements[1].text_len() > 0)
}

test "parser_unknown_and_invalid_material_remains_source_backed" {
  let raw = b"SELECT @ \xff"
  let source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = parse(source, @token.DorisProfile::V4_X, ParseMode::Editor)
  assert_true(!parsed.valid)
  assert_true(parsed.recovered)
  assert_true(parsed.root.span().end_byte == raw.length())
  assert_true(parsed.diagnostics.length() >= 1)
  assert_true(parsed.diagnostics[0].span.end_byte <= raw.length())
}

test "parser_lexical_diagnostic_keeps_statement_identity" {
  let source = match @source.SourceText::new(b"SELECT 1; SELECT \xff") {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = parse(source, @token.DorisProfile::V4_X, ParseMode::Editor)
  let mut found_second_statement = false
  for diagnostic in parsed.diagnostics {
    if diagnostic.code == "DORIS-PARSE-003" {
      assert_eq(diagnostic.statement_id, 1)
      found_second_statement = true
    }
  }
  assert_true(found_second_statement)
}

test "parser_limits_retain_a_source_backed_skipped_remainder" {
  let source = match @source.SourceText::new(b"SELECT 1; SELECT 2; SELECT 3") {
    Ok(source) => source
    Err(_) => panic()
  }
  let defaults = ParserLimits::default()
  let limits = {
    max_bytes: defaults.max_bytes,
    max_tokens: 3,
    max_recursion_depth: defaults.max_recursion_depth,
    max_recovery_steps: defaults.max_recovery_steps,
    max_diagnostics: defaults.max_diagnostics,
  }
  let parsed = parse_with_limits(source, @token.DorisProfile::V4_X, ParseMode::Editor, limits)
  assert_true(!parsed.valid)
  assert_true(parsed.recovered)
  assert_true(parsed.diagnostics.length() > 0)
  assert_true(parsed.root.children().length() > 0)
}
