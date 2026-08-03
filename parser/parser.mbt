/// A bounded recursive-descent document parser with one Pratt expression path.
/// Recovery always either consumes input or creates an explicit zero-width node.
pub(all) enum ParseMode {
  Strict
  Editor
}

pub(all) enum ParserLimitError {
  MaxBytes(Int)
  MaxTokens(Int)
  MaxRecursionDepth(Int)
  MaxRecoverySteps(Int)
  MaxDiagnostics(Int)
}

fn nonnegative_limit(value : Int) -> Int {
  if value < 0 { 0 } else { value }
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
pub fn ParserLimits::validate(self : ParserLimits) -> Result[Unit, ParserLimitError] {
  if self.max_bytes < 0 {
    Err(ParserLimitError::MaxBytes(self.max_bytes))
  } else if self.max_tokens < 0 {
    Err(ParserLimitError::MaxTokens(self.max_tokens))
  } else if self.max_recursion_depth < 0 {
    Err(ParserLimitError::MaxRecursionDepth(self.max_recursion_depth))
  } else if self.max_recovery_steps < 0 {
    Err(ParserLimitError::MaxRecoverySteps(self.max_recovery_steps))
  } else if self.max_diagnostics < 0 {
    Err(ParserLimitError::MaxDiagnostics(self.max_diagnostics))
  } else {
    Ok(())
  }
}

pub fn ParserLimits::normalized(self : ParserLimits) -> ParserLimits {
  {
    max_bytes: nonnegative_limit(self.max_bytes),
    max_tokens: nonnegative_limit(self.max_tokens),
    max_recursion_depth: nonnegative_limit(self.max_recursion_depth),
    max_recovery_steps: nonnegative_limit(self.max_recovery_steps),
    max_diagnostics: nonnegative_limit(self.max_diagnostics),
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
  feature_events : Array[FeatureEvent]
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
    let limit = if state.limits.max_diagnostics <= 0 { 1 } else { state.limits.max_diagnostics }
    let diagnostic = {
      severity: "error",
      code: "DORIS-PARSE-004",
      message: "parser resource limit reached",
      expected_class: "resource",
      span: span,
      statement_id: statement_id,
    }
    if state.diagnostics.length() < limit {
      state.diagnostics.push(diagnostic)
    } else {
      state.diagnostics[limit - 1] = diagnostic
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
  if state.resource_emitted {
    ()
  } else if state.diagnostics.length() < limit {
    state.diagnostics.push({
      severity: "error",
      code: code,
      message: message,
      expected_class: expected_class,
      span: span,
      statement_id: statement_id,
    })
  } else {
    resource_diagnostic(state, span, statement_id)
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

fn peek_raw(cursor : Cursor, offset : Int) -> Bytes? {
  cursor.indices.get(cursor.position + offset).map(index => cursor.stream.raw(index)).flatten()
}

fn parenthesis_depth(cursor : Cursor) -> Int {
  let mut depth = 0
  let mut index = 0
  while index < cursor.position {
    match cursor.indices.get(index).map(i => cursor.stream.raw(i)).flatten() {
      Some(raw) if raw == b"(" => depth = depth + 1
      Some(raw) if raw == b")" && depth > 0 => depth = depth - 1
      _ => ()
    }
    index = index + 1
  }
  depth
}

fn depth_allowed(cursor : Cursor, state : RecoveryState, source : @source.SourceText, statement_id : Int) -> Bool {
  let depth = parenthesis_depth(cursor)
  if depth > state.limits.max_recursion_depth {
    let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    resource_diagnostic(state, at, statement_id)
    false
  } else {
    true
  }
}

fn precedence(cursor : Cursor) -> Int? {
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, b"OR") => Some(1)
    Some(raw) if bytes_equal_ci(raw, b"AND") => Some(2)
    Some(raw) if raw == b"=" || raw == b"<" || raw == b">" || raw == b"<=" ||
      raw == b">=" || raw == b"<>" || raw == b"!=" || raw == b"<=>" => Some(3)
    Some(raw) if raw == b"+" || raw == b"-" => Some(4)
    Some(raw) if raw == b"*" || raw == b"/" || raw == b"%" => Some(5)
    Some(raw) if raw == b"|" || raw == b"&" => Some(4)
    _ => None
  }
}

fn is_word_token(cursor : Cursor) -> Bool {
  match token_at(cursor) {
    Some(token) if token.kind is @token.TokenKind::Quoted => true
    Some(token) if token.kind is @token.TokenKind::Identifier => {
      match raw_at(cursor) {
        Some(raw) => @token.is_unquoted_identifier(raw)
        None => false
      }
    }
    _ => false
  }
}

fn consume_word(cursor : Cursor, word : Bytes) -> Bool {
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, word) => { advance(cursor); true }
    _ => false
  }
}

fn consume_symbol(cursor : Cursor, symbol : Bytes) -> Bool {
  match raw_at(cursor) {
    Some(raw) if raw == symbol => { advance(cursor); true }
    _ => false
  }
}

fn expect_word(
  cursor : Cursor,
  word : Bytes,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
  message : String,
) -> Bool {
  if consume_word(cursor, word) {
    true
  } else {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(state, "DORIS-PARSE-002", message, "keyword", make_span(source, at, at), statement_id)
    false
  }
}
fn expect_symbol(
  cursor : Cursor,
  symbol : Bytes,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
  message : String,
) -> Bool {
  if consume_symbol(cursor, symbol) {
    true
  } else {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(state, "DORIS-PARSE-002", message, "symbol", make_span(source, at, at), statement_id)
    false
  }
}


fn feature_allowed(profile : @token.DorisProfile, feature : @token.DorisFeature) -> Bool {
  profile.supports(feature)
}

priv struct FeatureEvent {
  span : @source.Span
}

fn record_feature_event(state : RecoveryState, span : @source.Span) -> Unit {
  state.feature_events.push({ span: span })
}

fn add_feature_diagnostic(
  state : RecoveryState,
  feature : @token.DorisFeature,
  span : @source.Span,
  statement_id : Int,
) -> Unit {
  record_feature_event(state, span)
  let metadata = feature.metadata()
  add_diagnostic(
    state,
    metadata.diagnostic_code,
    metadata.diagnostic_message,
    "released-version",
    span,
    statement_id,
  )
}

fn version_invalid_node(token : @token.Token) -> @syntax.SyntaxElement {
  @syntax.SyntaxElement::ChildNode(require_node(@syntax.SyntaxNode::error(
    token.span,
    [@syntax.SyntaxElement::Leaf(@syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceError, token.span))],
  )))
}
fn require_node(node : @syntax.SyntaxNode?) -> @syntax.SyntaxNode {
  match node {
    Some(value) => value
    None => panic()
  }
}


fn is_identifier_candidate(cursor : Cursor) -> Bool {
  match token_at(cursor) {
    Some(token) if token.kind is @token.TokenKind::Quoted => true
    Some(token) if token.kind is @token.TokenKind::Identifier => {
      match raw_at(cursor) {
        Some(raw) => @token.is_unquoted_identifier(raw)
        None => false
      }
    }
    _ => false
  }
}

fn is_expression_operand(cursor : Cursor, token : @token.Token) -> Bool {
  match token.kind {
    @token.TokenKind::Identifier | @token.TokenKind::Quoted => is_identifier_candidate(cursor)
    @token.TokenKind::StringLiteral | @token.TokenKind::Number => true
    _ => false
  }
}

fn parse_expression_list(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
  stop_on_close : Bool,
) -> Bool {
  parse_expression_list_context(cursor, state, source, statement_id, stop_on_close, false)
}

fn parse_expression_list_context(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
  stop_on_close : Bool,
  allow_wildcard : Bool,
) -> Bool {
  let mut any = false
  let mut saw_item = false
  let mut valid = true
  let mut done = false
  while !done {
    match raw_at(cursor) {
      None => done = true
      Some(raw) if raw == b")" && stop_on_close => done = true
      Some(raw) if raw == b"," => {
        saw_item = true
        let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        add_diagnostic(state, "DORIS-PARSE-002", "expected expression after comma", "expression", span, statement_id)
        valid = false
        advance(cursor)
      }
      Some(_) => {
        saw_item = true
        let before = cursor.position
        let expression_ok = parse_expression_context(cursor, 1, 1, state, source, statement_id, allow_wildcard)
        any = any || expression_ok
        valid = valid && expression_ok
        if cursor.position == before {
          recover_expression(cursor, state, source, statement_id)
          valid = false
        }
        if !consume_symbol(cursor, b",") {
          done = true
        } else if raw_at(cursor) is None || raw_at(cursor) is Some(b")") {
          let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
          add_diagnostic(state, "DORIS-PARSE-002", "expected expression after comma", "expression", make_span(source, at, at), statement_id)
          valid = false
          done = true
        }
      }
    }
  }
  if !saw_item {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "DORIS-PARSE-002", "expected expression", "expression", make_span(source, at, at), statement_id)
    valid = false
  }
  any && valid
}

fn expect_window_nulls_order(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  if consume_word(cursor, b"FIRST") || consume_word(cursor, b"LAST") {
    true
  } else {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "DORIS-PARSE-002", "expected FIRST or LAST after NULLS", "window-order", make_span(source, at, at), statement_id)
    false
  }
}

fn parse_window_frame_bound(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  if consume_word(cursor, b"CURRENT") {
    expect_word(cursor, b"ROW", state, source, statement_id, "expected ROW after CURRENT")
  } else {
    let value_ok = if consume_word(cursor, b"UNBOUNDED") {
      true
    } else {
      parse_expression(cursor, 4, 1, state, source, statement_id)
    }
    let qualifier_ok = consume_word(cursor, b"PRECEDING") || consume_word(cursor, b"FOLLOWING")
    if !qualifier_ok {
      let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
      add_diagnostic(state, "DORIS-PARSE-002", "expected PRECEDING or FOLLOWING in window frame", "window-frame", make_span(source, at, at), statement_id)
    }
    value_ok && qualifier_ok
  }
}

fn parse_window_spec(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  if !consume_symbol(cursor, b"(") {
    return expect_symbol(cursor, b"(", state, source, statement_id, "expected opening window specification parenthesis")
  }
  let mut valid = true
  if consume_word(cursor, b"PARTITION") {
    valid = expect_word(cursor, b"BY", state, source, statement_id, "expected BY after PARTITION") && valid
    valid = parse_expression_list(cursor, state, source, statement_id, true) && valid
  }
  if consume_word(cursor, b"ORDER") {
    valid = expect_word(cursor, b"BY", state, source, statement_id, "expected BY after ORDER") && valid
    valid = parse_expression_list(cursor, state, source, statement_id, true) && valid
    while consume_word(cursor, b"ASC") || consume_word(cursor, b"DESC") {}
    if consume_word(cursor, b"NULLS") {
      valid = expect_window_nulls_order(cursor, state, source, statement_id) && valid
    }
  }
  if consume_word(cursor, b"ROWS") || consume_word(cursor, b"RANGE") || consume_word(cursor, b"GROUPS") {
    if consume_word(cursor, b"BETWEEN") {
      valid = parse_window_frame_bound(cursor, state, source, statement_id) && valid
      valid = expect_word(cursor, b"AND", state, source, statement_id, "expected AND in window frame") && valid
      valid = parse_window_frame_bound(cursor, state, source, statement_id) && valid
    } else {
      valid = parse_window_frame_bound(cursor, state, source, statement_id) && valid
    }
  }
  valid = expect_word(cursor, b")", state, source, statement_id, "expected closing window parenthesis") && valid
  valid
}

fn parse_expression_postfix(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  let mut valid = true
  let mut keep_going = true
  while keep_going {
    if consume_symbol(cursor, b".") {
      let word_after_dot = is_word_token(cursor)
      if consume_symbol(cursor, b"*") || word_after_dot {
        if word_after_dot { advance(cursor) }
        ()
      } else {
        let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
        add_diagnostic(state, "DORIS-PARSE-002", "expected qualified identifier", "identifier", make_span(source, at, at), statement_id)
        valid = false
        keep_going = false
      }
    } else if consume_symbol(cursor, b"(") {
      if !consume_symbol(cursor, b")") {
        valid = parse_expression_list_context(cursor, state, source, statement_id, true, true) && valid
        valid = expect_word(cursor, b")", state, source, statement_id, "expected closing function parenthesis") && valid
      }
      ()
    } else if consume_word(cursor, b"OVER") {
      let has_spec = match raw_at(cursor) { Some(raw) => raw == b"("; None => false }
      let has_name = is_identifier_candidate(cursor)
      if has_spec { valid = parse_window_spec(cursor, state, source, statement_id) && valid }
      else if has_name { advance(cursor) }
      else {
        add_diagnostic(state, "DORIS-PARSE-002", "expected window name or specification", "window", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id)
        valid = false
      }
      ()
    } else if consume_word(cursor, b"IS") {
      ignore(consume_word(cursor, b"NOT"))
      if !(consume_word(cursor, b"NULL") || consume_word(cursor, b"TRUE") || consume_word(cursor, b"FALSE") || consume_word(cursor, b"UNKNOWN")) {
        add_diagnostic(state, "DORIS-PARSE-002", "expected NULL or boolean predicate", "predicate", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id)
        valid = false
      }
      ()
    } else if consume_word(cursor, b"NOT") {
      if consume_word(cursor, b"IN") || consume_word(cursor, b"LIKE") || consume_word(cursor, b"REGEXP") {
        valid = parse_predicate_rhs(cursor, state, source, statement_id) && valid
        ()
      } else {
        cursor.position = cursor.position - 1
        keep_going = false
      }
    } else if consume_word(cursor, b"IN") || consume_word(cursor, b"LIKE") || consume_word(cursor, b"REGEXP") {
      valid = parse_predicate_rhs(cursor, state, source, statement_id) && valid
      ()
    } else if consume_word(cursor, b"BETWEEN") {
      valid = parse_expression(cursor, 4, 1, state, source, statement_id) && valid
      valid = expect_word(cursor, b"AND", state, source, statement_id, "expected AND in BETWEEN predicate") && valid
      valid = parse_expression(cursor, 4, 1, state, source, statement_id) && valid
      ()
    } else {
      keep_going = false
    }
  }
  // A diagnosed required child invalidates the enclosing postfix chain.
  valid
}



fn parse_predicate_rhs(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  if consume_symbol(cursor, b"(") {
    let mut valid = true
    if is_query_start(cursor) { valid = parse_query(cursor, state, source, statement_id) }
    else { valid = parse_expression_list(cursor, state, source, statement_id, true) }
    valid = expect_word(cursor, b")", state, source, statement_id, "expected closing predicate parenthesis") && valid
    valid
  } else { parse_expression(cursor, 4, 1, state, source, statement_id) }
}

fn parse_expression(
  cursor : Cursor,
  minimum_precedence : Int,
  depth : Int,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  parse_expression_context(cursor, minimum_precedence, depth, state, source, statement_id, false)
}

fn parse_expression_context(
  cursor : Cursor,
  minimum_precedence : Int,
  depth : Int,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
  allow_wildcard : Bool,
) -> Bool {
  let current_span = match token_at(cursor) {
    Some(token) => token.span
    None => make_span(source, source.byte_length(), source.byte_length())
  }
  if depth > state.limits.max_recursion_depth || !depth_allowed(cursor, state, source, statement_id) {
    resource_diagnostic(state, current_span, statement_id)
    return false
  }
  let mut prefix_ok = false
  match token_at(cursor) {
    Some(token) if is_expression_operand(cursor, token) => { advance(cursor); prefix_ok = true }
    Some(token) if token.kind is @token.TokenKind::Symbol && (raw_at(cursor) is Some(b"(")) => {
      advance(cursor)
      if is_query_start(cursor) { prefix_ok = parse_query(cursor, state, source, statement_id) }
      else { prefix_ok = parse_expression_context(cursor, 1, depth + 1, state, source, statement_id, false) }
      prefix_ok = expect_word(cursor, b")", state, source, statement_id, "expected closing parenthesis") && prefix_ok
    }
    Some(_) if allow_wildcard && raw_at(cursor) is Some(b"*") => { advance(cursor); prefix_ok = true }
    Some(_) if raw_at(cursor) is Some(b"+") || raw_at(cursor) is Some(b"-") || bytes_equal_ci(match raw_at(cursor) { Some(raw) => raw; None => b"" }, b"NOT") => {
      advance(cursor)
      prefix_ok = parse_expression_context(cursor, 6, depth + 1, state, source, statement_id, false)
    }
    Some(token) => add_diagnostic(state, "DORIS-PARSE-002", "expected literal, identifier, or subquery expression", "expression", token.span, statement_id)
    None => add_diagnostic(state, "DORIS-PARSE-002", "expected expression", "expression", current_span, statement_id)
  }
  if !prefix_ok { false } else {
    let mut valid = parse_expression_postfix(cursor, state, source, statement_id)
    let mut keep_going = true
    while keep_going {
      match precedence(cursor) {
        Some(operator_precedence) if operator_precedence >= minimum_precedence => {
          advance(cursor)
          let rhs = parse_expression_context(cursor, operator_precedence + 1, depth + 1, state, source, statement_id, false)
          valid = rhs && valid
          if !rhs { keep_going = false }
        }
        _ => keep_going = false
      }
      if keep_going { valid = parse_expression_postfix(cursor, state, source, statement_id) && valid }
    }
    valid
  }
}
fn is_query_start(cursor : Cursor) -> Bool {
  match raw_at(cursor) { Some(raw) => bytes_equal_ci(raw, b"SELECT") || bytes_equal_ci(raw, b"WITH"); None => false }
}

fn parse_balanced_option(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
  option : String,
) -> Bool {
  if !consume_symbol(cursor, b"(") {
    add_diagnostic(state, "DORIS-PARSE-002", "expected parenthesized " + option + " option", "option", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id)
    return false
  }
  let mut depth = 1
  let mut closed = true
  while depth > 0 {
    match raw_at(cursor) {
      None => {
        add_diagnostic(state, "DORIS-PARSE-002", "unterminated " + option + " option", "option", make_span(source, source.byte_length(), source.byte_length()), statement_id)
        closed = false
        depth = 0
      }
      Some(raw) if raw == b"(" => { depth = depth + 1; advance(cursor) }
      Some(raw) if raw == b")" => { depth = depth - 1; advance(cursor) }
      Some(_) => advance(cursor)
    }
  }
  closed
}

fn parse_table_ref(
  cursor : Cursor,
  profile : @token.DorisProfile,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  let mut valid = true
  if consume_symbol(cursor, b"(") {
    valid = parse_query(cursor, state, source, statement_id)
    valid = expect_word(cursor, b")", state, source, statement_id, "expected closing subquery parenthesis") && valid
  } else {
    let mut name_parts = 0
    while is_identifier_candidate(cursor) {
      advance(cursor)
      name_parts = name_parts + 1
      if consume_symbol(cursor, b".") {
        if !is_identifier_candidate(cursor) {
          let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
          add_diagnostic(state, "DORIS-PARSE-002", "expected table identifier after dot", "identifier", make_span(source, at, at), statement_id)
          valid = false
          break
        }
      } else { break }
    }
    if name_parts == 0 {
      let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
      add_diagnostic(state, "DORIS-PARSE-002", "expected table reference", "table", make_span(source, at, at), statement_id)
      valid = false
    }
  }
  let mut option_done = false
  while !option_done {
    let option_name = if consume_word(cursor, b"PARTITION") { "PARTITION" }
    else if raw_at(cursor) is Some(raw) && is_keyword(raw, @token.DorisFeature::Tablet.metadata().keyword) && peek_raw(cursor, 1) is Some(b"(") {
      let feature = @token.DorisFeature::Tablet
      let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      advance(cursor)
      if !feature_allowed(profile, feature) {
        add_feature_diagnostic(state, feature, span, statement_id)
        valid = false
      }
      "TABLET"
    }
    else if consume_word(cursor, b"SAMPLE") { "SAMPLE" }
    else if consume_word(cursor, b"TABLESAMPLE") { "TABLESAMPLE" }
    else { option_done = true; "" }
    if !option_done { valid = parse_balanced_option(cursor, state, source, statement_id, option_name) && valid }
  }
  if consume_word(cursor, b"AS") {
    let alias_ok = is_identifier_candidate(cursor)
    if !alias_ok { add_diagnostic(state, "DORIS-PARSE-002", "expected table alias", "identifier", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id); valid = false }
    else { advance(cursor) }
  } else {
    let alias_ok = is_identifier_candidate(cursor)
    if alias_ok { advance(cursor) }
  }
  valid
}

fn parse_from(
  cursor : Cursor,
  profile : @token.DorisProfile,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  let mut valid = parse_table_ref(cursor, profile, state, source, statement_id)
  let mut done = false
  while !done {
    if consume_symbol(cursor, b",") {
      valid = parse_table_ref(cursor, profile, state, source, statement_id) && valid
    } else {
      let modifier : String? = if consume_word(cursor, b"INNER") { ignore(consume_word(cursor, b"OUTER")); Some("INNER") }
      else if consume_word(cursor, b"LEFT") { ignore(consume_word(cursor, b"OUTER")); Some("LEFT") }
      else if consume_word(cursor, b"RIGHT") { ignore(consume_word(cursor, b"OUTER")); Some("RIGHT") }
      else if consume_word(cursor, b"FULL") { ignore(consume_word(cursor, b"OUTER")); Some("FULL") }
      else if consume_word(cursor, b"CROSS") { Some("CROSS") }
      else if consume_word(cursor, b"NATURAL") {
        if consume_word(cursor, b"LEFT") {
          ignore(consume_word(cursor, b"OUTER"))
          Some("NATURAL_LEFT")
        } else if consume_word(cursor, b"RIGHT") {
          ignore(consume_word(cursor, b"OUTER"))
          Some("NATURAL_RIGHT")
        } else {
          ignore(consume_word(cursor, b"OUTER"))
          Some("NATURAL")
        }
      } else { None }
      let has_join = consume_word(cursor, b"JOIN")
      if !has_join {
        match modifier {
          Some(_) => {
            let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
            add_diagnostic(state, "DORIS-PARSE-002", "expected JOIN after join modifier", "join", make_span(source, at, at), statement_id)
            valid = false
          }
          None => done = true
        }
      } else {
        valid = parse_table_ref(cursor, profile, state, source, statement_id) && valid
        let requires_condition = match modifier {
          Some(name) => name != "CROSS" && name != "NATURAL" && name != "NATURAL_LEFT" && name != "NATURAL_RIGHT"
          None => true
        }
        if consume_word(cursor, b"ON") {
          valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
        } else if consume_word(cursor, b"USING") {
          valid = parse_balanced_option(cursor, state, source, statement_id, "USING") && valid
        } else if requires_condition {
          let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
          add_diagnostic(state, "DORIS-PARSE-002", "expected ON or USING after JOIN", "join-condition", make_span(source, at, at), statement_id)
          valid = false
        }
      }
    }
  }
  valid
}

fn parse_grouping_arguments(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
  name : String,
) -> Bool {
  if !consume_symbol(cursor, b"(") {
    add_diagnostic(state, "DORIS-PARSE-002", "expected opening " + name + " parenthesis", "grouping", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id)
    return false
  }
  if raw_at(cursor) is Some(b")") {
    let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "DORIS-PARSE-002", "expected expression in " + name + "", "grouping", span, statement_id)
    advance(cursor)
    false
  } else {
    let valid = parse_expression_list(cursor, state, source, statement_id, true)
    let closed = expect_word(cursor, b")", state, source, statement_id, "expected closing grouping parenthesis")
    closed && valid
  }
}

fn parse_group_by(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  let mut valid = expect_word(cursor, b"BY", state, source, statement_id, "expected BY after GROUP")
  if !valid { return false }
  if consume_word(cursor, b"GROUPING") {
    valid = expect_word(cursor, b"SETS", state, source, statement_id, "expected SETS after GROUPING") && valid
    if !valid { return false }
    valid = expect_symbol(cursor, b"(", state, source, statement_id, "expected opening GROUPING SETS parenthesis") && valid
    if !valid { return false }
    if raw_at(cursor) is Some(b")") {
      let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "DORIS-PARSE-002", "expected grouping set in GROUPING SETS", "grouping", span, statement_id)
      advance(cursor)
      false
    } else {
      while raw_at(cursor) is Some(_) && !(raw_at(cursor) is Some(b")")) {
        if consume_symbol(cursor, b"(") {
          valid = parse_expression_list(cursor, state, source, statement_id, true) && valid
          valid = expect_word(cursor, b")", state, source, statement_id, "expected grouping set parenthesis") && valid
        } else {
          valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
        }
        if !consume_symbol(cursor, b",") { break }
      }
      valid = expect_word(cursor, b")", state, source, statement_id, "expected grouping sets parenthesis") && valid
      valid
    }
  } else if consume_word(cursor, b"ROLLUP") {
    parse_grouping_arguments(cursor, state, source, statement_id, "ROLLUP")
  } else if consume_word(cursor, b"CUBE") {
    parse_grouping_arguments(cursor, state, source, statement_id, "CUBE")
  } else {
    parse_expression_list(cursor, state, source, statement_id, true)
  }
}

fn parse_order_by(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  let mut valid = expect_word(cursor, b"BY", state, source, statement_id, "expected BY after ORDER")
  valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
  while consume_word(cursor, b"ASC") || consume_word(cursor, b"DESC") { () }
  while consume_symbol(cursor, b",") {
    valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
    while consume_word(cursor, b"ASC") || consume_word(cursor, b"DESC") { () }
  }
  valid
}

fn parse_limit(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  let mut valid = parse_expression(cursor, 1, 1, state, source, statement_id)
  if consume_symbol(cursor, b",") || consume_word(cursor, b"OFFSET") { valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid }
  valid
}

fn parse_select_core(
  cursor : Cursor,
  profile : @token.DorisProfile,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  if !expect_word(cursor, b"SELECT", state, source, statement_id, "expected SELECT statement") { return false }
  let mut valid = true
  let mut has_except = false
  if consume_word(cursor, b"DISTINCT") || consume_word(cursor, b"DISTINCTROW") || consume_word(cursor, b"ALL") {
    if consume_word(cursor, b"EXCEPT") {
      has_except = true
      valid = parse_balanced_option(cursor, state, source, statement_id, "ALL EXCEPT") && valid
    }
  }
  if has_except && raw_at(cursor) is Some(raw) && is_keyword(raw, b"FROM") {
    valid = true && valid
  } else {
    valid = parse_expression_list_until_clause(cursor, state, source, statement_id) && valid
  }
  if consume_word(cursor, b"FROM") { valid = parse_from(cursor, profile, state, source, statement_id) && valid }
  if consume_word(cursor, b"WHERE") { valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid }
  if consume_word(cursor, b"GROUP") { valid = parse_group_by(cursor, state, source, statement_id) && valid }
  if consume_word(cursor, b"HAVING") { valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid }
  if consume_word(cursor, b"WINDOW") {
    while is_word_token(cursor) {
      advance(cursor)
      valid = expect_word(cursor, b"AS", state, source, statement_id, "expected AS in WINDOW definition") && valid
      valid = parse_window_spec(cursor, state, source, statement_id) && valid
      if !consume_symbol(cursor, b",") { break }
    }
  }
  let qualify_span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
  if consume_word(cursor, b"QUALIFY") {
    let feature = @token.DorisFeature::Qualify
    if !feature_allowed(profile, feature) {
      add_feature_diagnostic(state, feature, qualify_span, statement_id)
      valid = false
    }
    valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
  }
  if consume_word(cursor, b"ORDER") { valid = parse_order_by(cursor, state, source, statement_id) && valid }
  if consume_word(cursor, b"LIMIT") { valid = parse_limit(cursor, state, source, statement_id) && valid }
  if consume_word(cursor, b"INTO") {
    valid = expect_word(cursor, b"OUTFILE", state, source, statement_id, "expected OUTFILE after INTO") && valid
    let is_string = match token_at(cursor) { Some(token) => token.kind is @token.TokenKind::StringLiteral; None => false }
    if !is_string { add_diagnostic(state, "DORIS-PARSE-002", "expected outfile string", "string", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id); valid = false }
    else { advance(cursor) }
  }
  valid
}
fn is_projection_boundary(raw : Bytes) -> Bool {
  @token.is_clause_keyword(raw) || raw == b";" || raw == b")"
}
fn is_projection_alias_candidate(cursor : Cursor) -> Bool {
  if !is_identifier_candidate(cursor) { false }
  else {
    match raw_at(cursor) {
      Some(raw) if bytes_equal_ci(raw, b"AS") || bytes_equal_ci(raw, b"OVER") => false
      Some(_) => match peek_raw(cursor, 1) {
        None => true
        Some(next) => next == b"," || is_projection_boundary(next)
      }
      None => false
    }
  }
}

fn parse_projection_alias(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  if consume_word(cursor, b"AS") {
    let alias_token = is_identifier_candidate(cursor)
    if alias_token {
      advance(cursor)
      true
    } else {
      add_diagnostic(state, "DORIS-PARSE-002", "expected projection alias", "identifier", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id)
      false
    }
  } else if is_projection_alias_candidate(cursor) {
    advance(cursor)
    true
  } else {
    true
  }
}


fn parse_expression_list_until_clause(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  let mut any = false
  let mut valid = true
  let mut done = false
  while !done {
    match raw_at(cursor) {
      None => done = true
      Some(raw) if is_projection_boundary(raw) => done = true
      Some(_) => {
        let before = cursor.position
        let item = parse_expression_context(cursor, 1, 1, state, source, statement_id, true)
        any = any || item
        valid = valid && item
        valid = parse_projection_alias(cursor, state, source, statement_id) && valid
        if cursor.position == before { recover_expression(cursor, state, source, statement_id); valid = false }
        if consume_symbol(cursor, b",") {
          match raw_at(cursor) {
            None => {
              add_diagnostic(state, "DORIS-PARSE-002", "expected expression after projection comma", "expression", make_span(source, source.byte_length(), source.byte_length()), statement_id)
              valid = false
              done = true
            }
            Some(raw) if is_projection_boundary(raw) => {
              let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
              add_diagnostic(state, "DORIS-PARSE-002", "expected expression after projection comma", "expression", make_span(source, at, at), statement_id)
              valid = false
              done = true
            }
            Some(_) => ()
          }
        } else {
          done = true
        }
      }
    }
  }
  if !any {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "DORIS-PARSE-002", "expected expression after SELECT", "expression", make_span(source, at, at), statement_id)
  }
  any && valid
}

fn parse_query(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let profile = cursor.stream.profile
  let mut valid = true
  if consume_word(cursor, b"WITH") {
    ignore(consume_word(cursor, b"RECURSIVE"))
    let mut cte_done = false
    while !cte_done {
      let cte_name = is_identifier_candidate(cursor)
      if !cte_name {
        add_diagnostic(state, "DORIS-PARSE-002", "expected CTE name", "identifier", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id)
        valid = false
        break
      }
      advance(cursor)
      if consume_symbol(cursor, b"(") {
        while raw_at(cursor) is Some(_) && !(raw_at(cursor) is Some(b")")) { advance(cursor) }
      }
      valid = expect_word(cursor, b"AS", state, source, statement_id, "expected AS in CTE") && valid
      if !consume_symbol(cursor, b"(") {
        add_diagnostic(state, "DORIS-PARSE-002", "expected CTE query parenthesis", "subquery", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id)
        valid = false
      } else {
        valid = parse_query(cursor, state, source, statement_id) && valid
        valid = expect_word(cursor, b")", state, source, statement_id, "expected closing CTE parenthesis") && valid
      }
      if !consume_symbol(cursor, b",") { cte_done = true }
    }
  }
  valid = parse_select_core(cursor, profile, state, source, statement_id) && valid
  while consume_word(cursor, b"UNION") {
    ignore(consume_word(cursor, b"ALL"))
    ignore(consume_word(cursor, b"DISTINCT"))
    valid = parse_select_core(cursor, profile, state, source, statement_id) && valid
  }
  valid
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

fn has_statement_content(stream : @token.TokenStream, start_index : Int, end_index : Int) -> Bool {
  let indices = significant_indices(stream, start_index, end_index)
  for index in indices {
    match stream.raw(index) {
      Some(raw) if raw == b";" => ()
      Some(_) => return true
      None => ()
    }
  }
  false
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

fn segment_statement_id_for_span(stream : @token.TokenStream, span : @source.Span) -> Int {
  let mut statement_id = 0
  let mut segment_start = 0
  for index in 0..<stream.length() {
    match stream.at(index) {
      Some(token) if token.span.start_byte >= span.start_byte => break
      Some(token) => {
        match stream.source.slice(token.span) {
          Some(raw) if raw == b";" => {
            let segment_end = index + 1
            if has_statement_content(stream, segment_start, segment_end) {
              statement_id = statement_id + 1
            }
            segment_start = segment_end
          }
          _ => ()
        }
      }
      None => ()
    }
  }
  statement_id
}

fn segment_children_for_profile(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
) -> Array[@syntax.SyntaxElement] {
  segment_children(stream, start_index, end_index)
}

fn has_feature_event(events : Array[FeatureEvent], span : @source.Span) -> Bool {
  for event in events {
    if event.span.start_byte == span.start_byte && event.span.end_byte == span.end_byte {
      return true
    }
  }
  false
}

fn segment_children_for_events(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
  events : Array[FeatureEvent],
) -> Array[@syntax.SyntaxElement] {
  let children : Array[@syntax.SyntaxElement] = []
  let mut index = start_index
  while index < end_index {
    match stream.at(index) {
      Some(token) if has_feature_event(events, token.span) => children.push(version_invalid_node(token))
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
      match stream.at(start_index) { Some(token) => token.span.start_byte; None => stream.source.byte_length() }
    } else { stream.source.byte_length() }
    make_span(stream.source, at, at)
  } else {
    let start = match stream.at(start_index) { Some(token) => token.span.start_byte; None => stream.source.byte_length() }
    let end = match stream.at(end_index - 1) { Some(token) => token.span.end_byte; None => start }
    make_span(stream.source, start, end)
  }
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
      Some(raw) if raw == b")" || raw == b"," || raw == b";" || @token.is_clause_keyword(raw) => done = true
      Some(_) => {
        let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        if consume_recovery_step(state, span, statement_id) { advance(cursor); consumed = true } else { done = true }
      }
    }
  }
  if !consumed && raw_at(cursor) is Some(_) {
    match raw_at(cursor) { Some(raw) if raw == b")" || raw == b"," || raw == b";" || @token.is_clause_keyword(raw) => (); _ => advance(cursor) }
  }
}

fn parse_segment(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
  statement_id : Int,
  state : RecoveryState,
) -> @syntax.SyntaxNode {
  let span = segment_span(stream, start_index, end_index)
  let indices = significant_indices(stream, start_index, end_index)
  let selected = match indices.get(0) {
    Some(first_index) => match stream.raw(first_index) {
      Some(raw) if bytes_equal_ci(raw, b"SELECT") || bytes_equal_ci(raw, b"WITH") => true
      Some(_) => { add_diagnostic(state, "DORIS-PARSE-001", "expected SELECT statement", "statement", span, statement_id); false }
      None => false
    }
    None => false
  }
  if selected {
    let cursor = { stream: stream, indices: indices, position: 0 }
    let parsed = parse_query(cursor, state, stream.source, statement_id)
    let mut trailing = false
    while cursor.position < cursor.indices.length() {
      match raw_at(cursor) {
        Some(raw) if raw == b";" => advance(cursor)
        Some(_) => {
          let before = cursor.position
          trailing = true
          recover_expression(cursor, state, stream.source, statement_id)
          if cursor.position == before { advance(cursor) }
        }
        None => cursor.position = cursor.indices.length()
      }
    }
    if trailing { add_diagnostic(state, "DORIS-PARSE-001", "unexpected tokens after SELECT query", "statement", span, statement_id) }
    let children = segment_children_for_events(stream, start_index, end_index, state.feature_events)
    if !parsed || trailing { children.push(@syntax.SyntaxElement::ChildNode(require_node(@syntax.SyntaxNode::missing(span.end_byte, stream.source.byte_length())))) }
    let select = require_node(@syntax.SyntaxNode::new(@syntax.SyntaxKind::Select, span, children))
    require_node(@syntax.SyntaxNode::new(@syntax.SyntaxKind::Statement, span, [@syntax.SyntaxElement::ChildNode(select)]))
  } else {
    let children = segment_children_for_profile(stream, start_index, end_index)
    let error = require_node(@syntax.SyntaxNode::new(@syntax.SyntaxKind::Error, span, children))
    require_node(@syntax.SyntaxNode::new(@syntax.SyntaxKind::Statement, span, [@syntax.SyntaxElement::ChildNode(error)]))
  }
}


fn append_skipped(
  root_children : Array[@syntax.SyntaxElement],
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
) -> Unit {
  if start_index < end_index {
    let span = segment_span(stream, start_index, end_index)
    let node = require_node(@syntax.SyntaxNode::new(
      @syntax.SyntaxKind::Skipped,
      span,
      segment_children(stream, start_index, end_index),
    ))
    root_children.push(@syntax.SyntaxElement::ChildNode(node))
  } else if start_index == 0 && stream.source.byte_length() > 0 {
    let span = make_span(stream.source, 0, stream.source.byte_length())
    let node = require_node(@syntax.SyntaxNode::new(
      @syntax.SyntaxKind::Skipped,
      span,
      segment_children(stream, 0, end_index),
    ))
    root_children.push(@syntax.SyntaxElement::ChildNode(node))
  }
}

fn append_skipped_span(
  root_children : Array[@syntax.SyntaxElement],
  source : @source.SourceText,
  start_byte : Int,
) -> Unit {
  if start_byte < source.byte_length() {
    let span = make_span(source, start_byte, source.byte_length())
    let node = require_node(@syntax.SyntaxNode::skipped(
      span,
      [@syntax.SyntaxElement::Leaf(@syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceSkipped, span))],
    ))
    root_children.push(@syntax.SyntaxElement::ChildNode(node))
  }
}

fn append_trivia_segment(
  root_children : Array[@syntax.SyntaxElement],
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
) -> Unit {
  let mut index = start_index
  while index < end_index {
    match stream.at(index) {
      Some(token) => root_children.push(leaf_for_token(token))
      None => ()
    }
    index = index + 1
  }
}

pub fn parse_with_limits(
  source : @source.SourceText,
  profile : @token.DorisProfile,
  mode : ParseMode,
  limits : ParserLimits,
) -> ParsedDocument {
  let limits = limits.normalized()
  let stream = @lexer.lex_with_limit(source, profile, limits.max_tokens)
  let root_span = make_span(source, 0, source.byte_length())
  let state = RecoveryState::{
    diagnostics: [],
    limits: limits,
    feature_events: [],
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
    let cap_span = make_span(source, if cut_index < stream.length() { match stream.at(cut_index) { Some(token) => token.span.start_byte; None => limits.max_bytes } } else { limits.max_bytes }, source.byte_length())
    resource_diagnostic(state, cap_span, segment_statement_id_for_span(stream, cap_span))
  }
  let mut segment_start = 0
  let mut statement_id = 0
  let mut index = 0
  while index < parse_end {
    let is_semicolon = match stream.raw(index) { Some(raw) => raw == b";"; None => false }
    if is_semicolon {
      let segment_end = index + 1
      if has_statement_content(stream, segment_start, segment_end) {
        let segment = parse_segment(stream, segment_start, segment_end, statement_id, state)
        if segment.span().length() > 0 {
          root_children.push(@syntax.SyntaxElement::ChildNode(segment))
          statement_id = statement_id + 1
        }
      } else {
        append_trivia_segment(root_children, stream, segment_start, segment_end)
      }
      segment_start = segment_end
    }
    index = index + 1
  }
  if segment_start < parse_end {
    let indices = significant_indices(stream, segment_start, parse_end)
    if indices.length() == 0 {
      append_trivia_segment(root_children, stream, segment_start, parse_end)
    } else {
      let segment = parse_segment(stream, segment_start, parse_end, statement_id, state)
      if segment.span().length() > 0 {
        root_children.push(@syntax.SyntaxElement::ChildNode(segment))
        statement_id = statement_id + 1
      }
    }
  }
  if cut_index < stream.length() {
    append_skipped(root_children, stream, cut_index, stream.length())
  }
  match stream.truncated_at {
    Some(at) => {
      resource_diagnostic(state, make_span(source, at, source.byte_length()), segment_statement_id_for_span(stream, make_span(source, at, at)))
      append_skipped_span(root_children, source, at)
    }
    None => ()
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
        segment_statement_id_for_span(stream, token.span),
      )
    }
  }
  let valid = state.diagnostics.length() == 0
  {
    source: source,
    profile: profile,
    mode: mode,
    root: require_node(@syntax.SyntaxNode::new(@syntax.SyntaxKind::Document, root_span, root_children)),
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

test "parser_low_level_negative_limits_normalize_without_panic" {
  let empty_source = match @source.SourceText::new(b"") {
    Ok(source) => source
    Err(_) => panic()
  }
  let empty = parse_with_limits(
    empty_source,
    @token.DorisProfile::V4_X,
    ParseMode::Strict,
    ParserLimits::new(-1, -1, -1, -1, -1),
  )
  assert_true(empty.root.is_valid(0))
  assert_true(empty.valid)

  let nonempty_source = match @source.SourceText::new(b"SELECT 1") {
    Ok(source) => source
    Err(_) => panic()
  }
  let nonempty = parse_with_limits(
    nonempty_source,
    @token.DorisProfile::V4_X,
    ParseMode::Editor,
    ParserLimits::new(-1, -1, -1, -1, -1),
  )
  assert_true(!nonempty.valid)
  assert_true(nonempty.diagnostics.any(d => d.expected_class == "resource"))
  assert_true(nonempty.root.is_valid(nonempty_source.byte_length()))
  assert_true(nonempty.diagnostics.all(d => d.span.start_byte >= 0 && d.span.end_byte <= nonempty_source.byte_length()))
}

test "parser_limit_validation_reports_each_negative_boundary" {
  assert_true(ParserLimits::new(-1, 1, 1, 1, 1).validate() is Err(ParserLimitError::MaxBytes(-1)))
  assert_true(ParserLimits::new(1, -1, 1, 1, 1).validate() is Err(ParserLimitError::MaxTokens(-1)))
  assert_true(ParserLimits::new(1, 1, -1, 1, 1).validate() is Err(ParserLimitError::MaxRecursionDepth(-1)))
  assert_true(ParserLimits::new(1, 1, 1, -1, 1).validate() is Err(ParserLimitError::MaxRecoverySteps(-1)))
  assert_true(ParserLimits::new(1, 1, 1, 1, -1).validate() is Err(ParserLimitError::MaxDiagnostics(-1)))
}
