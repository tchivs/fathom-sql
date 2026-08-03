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

fn is_word_token(token : @token.Token) -> Bool {
  match token.kind {
    @token.TokenKind::Identifier | @token.TokenKind::Quoted => true
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

fn feature_allowed(profile : @token.DorisProfile, introduced : Bytes) -> Bool {
  match profile {
    @token.DorisProfile::V2_1 => introduced == b"2.1"
    @token.DorisProfile::V3_X => introduced == b"2.1" || introduced == b"3.x"
    @token.DorisProfile::V4_X => true
  }
}

fn version_diagnostic(
  cursor : Cursor,
  profile : @token.DorisProfile,
  introduced : Bytes,
  feature : String,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Unit {
  if !feature_allowed(profile, introduced) {
    let span = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state,
      "DORIS-PARSE-006",
      "feature " + feature + " is unavailable in the selected released profile",
      "released-version",
      span,
      statement_id,
    )
  }
}

fn is_expression_operand(token : @token.Token) -> Bool {
  match token.kind {
    @token.TokenKind::Identifier | @token.TokenKind::Quoted |
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
  let mut any = false
  let mut valid = true
  let mut done = false
  while !done {
    match raw_at(cursor) {
      None => done = true
      Some(raw) if raw == b")" && stop_on_close => done = true
      Some(raw) if raw == b"," => {
        let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        add_diagnostic(state, "DORIS-PARSE-002", "expected expression after comma", "expression", span, statement_id)
        valid = false
        advance(cursor)
      }
      Some(_) => {
        let before = cursor.position
        let expression_ok = parse_expression(cursor, 1, 1, state, source, statement_id)
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
  any && valid
}

fn parse_window_spec(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  if !consume_symbol(cursor, b"(") { return true }
  if consume_word(cursor, b"PARTITION") {
    ignore(expect_word(cursor, b"BY", state, source, statement_id, "expected BY after PARTITION"))
    ignore(parse_expression_list(cursor, state, source, statement_id, true))
  }
  if consume_word(cursor, b"ORDER") {
    ignore(expect_word(cursor, b"BY", state, source, statement_id, "expected BY after ORDER"))
    ignore(parse_expression_list(cursor, state, source, statement_id, true))
    while consume_word(cursor, b"ASC") || consume_word(cursor, b"DESC") || consume_word(cursor, b"NULLS") {
      if raw_at(cursor) is Some(b"FIRST") || raw_at(cursor) is Some(b"LAST") { advance(cursor) }
    }
  }
  if consume_word(cursor, b"ROWS") || consume_word(cursor, b"RANGE") || consume_word(cursor, b"GROUPS") {
    if consume_word(cursor, b"BETWEEN") {
      ignore(parse_expression(cursor, 4, 1, state, source, statement_id))
      ignore(consume_word(cursor, b"PRECEDING"))
      ignore(consume_word(cursor, b"FOLLOWING"))
      ignore(consume_word(cursor, b"CURRENT"))
      ignore(consume_word(cursor, b"ROW"))
      ignore(expect_word(cursor, b"AND", state, source, statement_id, "expected AND in window frame"))
      ignore(parse_expression(cursor, 4, 1, state, source, statement_id))
      ignore(consume_word(cursor, b"PRECEDING"))
      ignore(consume_word(cursor, b"FOLLOWING"))
      ignore(consume_word(cursor, b"CURRENT"))
      ignore(consume_word(cursor, b"ROW"))
    } else {
      ignore(parse_expression(cursor, 4, 1, state, source, statement_id))
      ignore(consume_word(cursor, b"PRECEDING"))
      ignore(consume_word(cursor, b"FOLLOWING"))
      ignore(consume_word(cursor, b"CURRENT"))
      ignore(consume_word(cursor, b"ROW"))
    }
  }
  ignore(expect_word(cursor, b")", state, source, statement_id, "expected closing window parenthesis"))
  true
}

fn parse_expression_postfix(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  let mut consumed = false
  let mut keep_going = true
  while keep_going {
    if consume_symbol(cursor, b".") {
      let word_after_dot = match token_at(cursor) { Some(token) => is_word_token(token); None => false }
      if consume_symbol(cursor, b"*") || word_after_dot {
        if word_after_dot { advance(cursor) }
        consumed = true
      } else {
        let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
        add_diagnostic(state, "DORIS-PARSE-002", "expected qualified identifier", "identifier", make_span(source, at, at), statement_id)
        keep_going = false
      }
    } else if consume_symbol(cursor, b"(") {
      if !consume_symbol(cursor, b")") {
        ignore(parse_expression_list(cursor, state, source, statement_id, true))
        ignore(expect_word(cursor, b")", state, source, statement_id, "expected closing function parenthesis"))
      }
      consumed = true
    } else if consume_word(cursor, b"OVER") {
      let has_spec = match raw_at(cursor) { Some(raw) => raw == b"("; None => false }
      let has_name = match token_at(cursor) { Some(token) => is_word_token(token); None => false }
      if has_spec { ignore(parse_window_spec(cursor, state, source, statement_id)) }
      else if has_name { advance(cursor) }
      else { add_diagnostic(state, "DORIS-PARSE-002", "expected window name or specification", "window", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id) }
      consumed = true
    } else if consume_word(cursor, b"IS") {
      ignore(consume_word(cursor, b"NOT"))
      if !(consume_word(cursor, b"NULL") || consume_word(cursor, b"TRUE") || consume_word(cursor, b"FALSE") || consume_word(cursor, b"UNKNOWN")) {
        add_diagnostic(state, "DORIS-PARSE-002", "expected NULL or boolean predicate", "predicate", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id)
      }
      consumed = true
    } else if consume_word(cursor, b"NOT") {
      if consume_word(cursor, b"IN") || consume_word(cursor, b"LIKE") || consume_word(cursor, b"REGEXP") {
        ignore(parse_predicate_rhs(cursor, state, source, statement_id))
        consumed = true
      } else {
        cursor.position = cursor.position - 1
        keep_going = false
      }
    } else if consume_word(cursor, b"IN") || consume_word(cursor, b"LIKE") || consume_word(cursor, b"REGEXP") {
      ignore(parse_predicate_rhs(cursor, state, source, statement_id))
      consumed = true
    } else if consume_word(cursor, b"BETWEEN") {
      ignore(parse_expression(cursor, 4, 1, state, source, statement_id))
      ignore(expect_word(cursor, b"AND", state, source, statement_id, "expected AND in BETWEEN predicate"))
      ignore(parse_expression(cursor, 4, 1, state, source, statement_id))
      consumed = true
    } else {
      keep_going = false
    }
  }
  consumed
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
    Some(token) if is_expression_operand(token) => { advance(cursor); prefix_ok = true }
    Some(token) if token.kind is @token.TokenKind::Symbol && (raw_at(cursor) is Some(b"(")) => {
      advance(cursor)
      if is_query_start(cursor) { prefix_ok = parse_query(cursor, state, source, statement_id) }
      else { prefix_ok = parse_expression(cursor, 1, depth + 1, state, source, statement_id) }
      prefix_ok = expect_word(cursor, b")", state, source, statement_id, "expected closing parenthesis") && prefix_ok
    }
    Some(_) if raw_at(cursor) is Some(b"*") => { advance(cursor); prefix_ok = true }
    Some(_) if raw_at(cursor) is Some(b"+") || raw_at(cursor) is Some(b"-") || bytes_equal_ci(match raw_at(cursor) { Some(raw) => raw; None => b"" }, b"NOT") => {
      advance(cursor)
      prefix_ok = parse_expression(cursor, 6, depth + 1, state, source, statement_id)
    }
    Some(token) => add_diagnostic(state, "DORIS-PARSE-002", "expected literal, identifier, or subquery expression", "expression", token.span, statement_id)
    None => add_diagnostic(state, "DORIS-PARSE-002", "expected expression", "expression", current_span, statement_id)
  }
  if !prefix_ok { false } else {
    ignore(parse_expression_postfix(cursor, state, source, statement_id))
    let mut keep_going = true
    while keep_going {
      match precedence(cursor) {
        Some(operator_precedence) if operator_precedence >= minimum_precedence => {
          advance(cursor)
          let rhs = parse_expression(cursor, operator_precedence + 1, depth + 1, state, source, statement_id)
          if !rhs { keep_going = false }
        }
        _ => keep_going = false
      }
      if keep_going { ignore(parse_expression_postfix(cursor, state, source, statement_id)) }
    }
    true
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
  while depth > 0 {
    match raw_at(cursor) {
      None => { add_diagnostic(state, "DORIS-PARSE-002", "unterminated " + option + " option", "option", make_span(source, source.byte_length(), source.byte_length()), statement_id); depth = 0 }
      Some(raw) if raw == b"(" => { depth = depth + 1; advance(cursor) }
      Some(raw) if raw == b")" => { depth = depth - 1; advance(cursor) }
      Some(_) => advance(cursor)
    }
  }
  true
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
    while (match token_at(cursor) { Some(token) => is_word_token(token); None => false }) {
      advance(cursor)
      name_parts = name_parts + 1
      if !consume_symbol(cursor, b".") { break }
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
    else if consume_word(cursor, b"TABLET") { version_diagnostic(cursor, profile, b"3.x", "TABLET table option", state, source, statement_id); "TABLET" }
    else if consume_word(cursor, b"SAMPLE") { "SAMPLE" }
    else if consume_word(cursor, b"TABLESAMPLE") { "TABLESAMPLE" }
    else { option_done = true; "" }
    if !option_done { valid = parse_balanced_option(cursor, state, source, statement_id, option_name) && valid }
  }
  if consume_word(cursor, b"AS") {
    let alias = match token_at(cursor) { Some(token) => is_word_token(token); None => false }
    if !alias { add_diagnostic(state, "DORIS-PARSE-002", "expected table alias", "identifier", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id); valid = false }
    else { advance(cursor) }
  } else {
    let alias = match token_at(cursor) { Some(token) => is_word_token(token); None => false }
    let raw = match raw_at(cursor) { Some(raw) => raw; None => b"" }
    if alias && !is_clause_keyword(raw) { advance(cursor) }
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
      let modifier : String? = if consume_word(cursor, b"INNER") { Some("INNER") }
      else if consume_word(cursor, b"LEFT") { Some("LEFT") }
      else if consume_word(cursor, b"RIGHT") { Some("RIGHT") }
      else if consume_word(cursor, b"FULL") { Some("FULL") }
      else if consume_word(cursor, b"CROSS") { Some("CROSS") }
      else if consume_word(cursor, b"NATURAL") { Some("NATURAL") }
      else { None }
      if modifier is Some(_) { ignore(consume_word(cursor, b"OUTER")) }
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
          Some(name) => name != "CROSS" && name != "NATURAL"
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

fn parse_group_by(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  ignore(expect_word(cursor, b"BY", state, source, statement_id, "expected BY after GROUP"))
  if consume_word(cursor, b"GROUPING") {
    ignore(expect_word(cursor, b"SETS", state, source, statement_id, "expected SETS after GROUPING"))
    if !consume_symbol(cursor, b"(") { return false }
    let mut valid = true
    while raw_at(cursor) is Some(_) && !(raw_at(cursor) is Some(b")")) {
      if consume_symbol(cursor, b"(") {
        valid = parse_expression_list(cursor, state, source, statement_id, true) && valid
        ignore(expect_word(cursor, b")", state, source, statement_id, "expected grouping set parenthesis"))
      } else { valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid }
      if !consume_symbol(cursor, b",") { break }
    }
    ignore(expect_word(cursor, b")", state, source, statement_id, "expected grouping sets parenthesis"))
    valid
  } else { parse_expression_list(cursor, state, source, statement_id, true) }
}

fn parse_order_by(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : Int,
) -> Bool {
  ignore(expect_word(cursor, b"BY", state, source, statement_id, "expected BY after ORDER"))
  let mut valid = parse_expression(cursor, 1, 1, state, source, statement_id)
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
  if has_except && raw_at(cursor) is Some(b"FROM") {
    valid = true && valid
  } else {
    valid = parse_expression_list_until_clause(cursor, state, source, statement_id) && valid
  }
  if consume_word(cursor, b"FROM") { valid = parse_from(cursor, profile, state, source, statement_id) && valid }
  if consume_word(cursor, b"WHERE") { valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid }
  if consume_word(cursor, b"GROUP") { valid = parse_group_by(cursor, state, source, statement_id) && valid }
  if consume_word(cursor, b"HAVING") { valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid }
  if consume_word(cursor, b"WINDOW") {
    while (match token_at(cursor) { Some(token) => is_word_token(token); None => false }) {
      advance(cursor)
      ignore(expect_word(cursor, b"AS", state, source, statement_id, "expected AS in WINDOW definition"))
      ignore(parse_window_spec(cursor, state, source, statement_id))
      if !consume_symbol(cursor, b",") { break }
    }
  }
  if consume_word(cursor, b"QUALIFY") {
    version_diagnostic(cursor, profile, b"3.x", "QUALIFY", state, source, statement_id)
    valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
  }
  if consume_word(cursor, b"ORDER") { valid = parse_order_by(cursor, state, source, statement_id) && valid }
  if consume_word(cursor, b"LIMIT") { valid = parse_limit(cursor, state, source, statement_id) && valid }
  if consume_word(cursor, b"INTO") {
    ignore(expect_word(cursor, b"OUTFILE", state, source, statement_id, "expected OUTFILE after INTO"))
    let is_string = match token_at(cursor) { Some(token) => token.kind is @token.TokenKind::StringLiteral; None => false }
    if !is_string { add_diagnostic(state, "DORIS-PARSE-002", "expected outfile string", "string", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id); valid = false }
    else { advance(cursor) }
  }
  valid
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
      Some(raw) if raw == b"FROM" || raw == b"WHERE" || raw == b"GROUP" || raw == b"HAVING" || raw == b"WINDOW" || raw == b"QUALIFY" || raw == b"ORDER" || raw == b"LIMIT" || raw == b"INTO" || raw == b"UNION" || raw == b";" || raw == b")" => done = true
      Some(_) => {
        let before = cursor.position
        let item = parse_expression(cursor, 1, 1, state, source, statement_id)
        any = any || item
        valid = valid && item
        if consume_word(cursor, b"AS") {
          let alias_token = match token_at(cursor) { Some(token) => is_word_token(token); None => false }
          if alias_token { advance(cursor) }
          else { add_diagnostic(state, "DORIS-PARSE-002", "expected projection alias", "identifier", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id); valid = false }
        }
        if cursor.position == before { recover_expression(cursor, state, source, statement_id); valid = false }
        if !consume_symbol(cursor, b",") { done = true }
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
      let cte_name = match token_at(cursor) { Some(token) => is_word_token(token); None => false }
      if !cte_name {
        add_diagnostic(state, "DORIS-PARSE-002", "expected CTE name", "identifier", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id)
        valid = false
        break
      }
      advance(cursor)
      if consume_symbol(cursor, b"(") {
        while raw_at(cursor) is Some(_) && !(raw_at(cursor) is Some(b")")) { advance(cursor) }
      }
      ignore(expect_word(cursor, b"AS", state, source, statement_id, "expected AS in CTE"))
      if !consume_symbol(cursor, b"(") {
        add_diagnostic(state, "DORIS-PARSE-002", "expected CTE query parenthesis", "subquery", match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }, statement_id)
        valid = false
      } else {
        valid = parse_query(cursor, state, source, statement_id) && valid
        ignore(expect_word(cursor, b")", state, source, statement_id, "expected closing CTE parenthesis"))
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

fn is_clause_keyword(raw : Bytes) -> Bool {
  bytes_equal_ci(raw, b"FROM") || bytes_equal_ci(raw, b"WHERE") ||
    bytes_equal_ci(raw, b"GROUP") || bytes_equal_ci(raw, b"HAVING") ||
    bytes_equal_ci(raw, b"ORDER") || bytes_equal_ci(raw, b"LIMIT") ||
    bytes_equal_ci(raw, b"JOIN") || bytes_equal_ci(raw, b"UNION") ||
    bytes_equal_ci(raw, b"QUALIFY") || bytes_equal_ci(raw, b"WINDOW") ||
    bytes_equal_ci(raw, b"INTO") || bytes_equal_ci(raw, b"INNER") ||
    bytes_equal_ci(raw, b"LEFT") || bytes_equal_ci(raw, b"RIGHT") ||
    bytes_equal_ci(raw, b"FULL") || bytes_equal_ci(raw, b"CROSS") ||
    bytes_equal_ci(raw, b"NATURAL") || bytes_equal_ci(raw, b"OUTER") ||
    bytes_equal_ci(raw, b"ON") || bytes_equal_ci(raw, b"USING")
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
      Some(raw) if raw == b")" || raw == b"," || raw == b";" || is_clause_keyword(raw) => done = true
      Some(_) => {
        let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        if consume_recovery_step(state, span, statement_id) { advance(cursor); consumed = true } else { done = true }
      }
    }
  }
  if !consumed && raw_at(cursor) is Some(_) {
    match raw_at(cursor) { Some(raw) if raw == b")" || raw == b"," || raw == b";" || is_clause_keyword(raw) => (); _ => advance(cursor) }
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
  let children = segment_children(stream, start_index, end_index)
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
    if !parsed || trailing { children.push(@syntax.SyntaxElement::ChildNode(@syntax.SyntaxNode::missing(span.end_byte))) }
    @syntax.SyntaxNode::new(@syntax.SyntaxKind::Statement, span, [@syntax.SyntaxElement::ChildNode(@syntax.SyntaxNode::new(@syntax.SyntaxKind::Select, span, children))])
  } else {
    let error = @syntax.SyntaxNode::new(@syntax.SyntaxKind::Error, span, children)
    @syntax.SyntaxNode::new(@syntax.SyntaxKind::Statement, span, [@syntax.SyntaxElement::ChildNode(error)])
  }
}

fn statement_id_for_span(stream : @token.TokenStream, span : @source.Span) -> Int {
  let mut statement_id = 0
  for token in stream.tokens {
    if token.span.start_byte >= span.start_byte { break }
    match stream.source.slice(token.span) { Some(raw) if raw == b";" => statement_id = statement_id + 1; _ => () }
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

fn append_skipped_span(
  root_children : Array[@syntax.SyntaxElement],
  source : @source.SourceText,
  start_byte : Int,
) -> Unit {
  if start_byte < source.byte_length() {
    let span = make_span(source, start_byte, source.byte_length())
    root_children.push(@syntax.SyntaxElement::ChildNode(@syntax.SyntaxNode::skipped(
      span,
      [@syntax.SyntaxElement::Leaf(@syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceSkipped, span))],
    )))
  }
}

pub fn parse_with_limits(
  source : @source.SourceText,
  profile : @token.DorisProfile,
  mode : ParseMode,
  limits : ParserLimits,
) -> ParsedDocument {
  let stream = @lexer.lex_with_limit(source, profile, limits.max_tokens)
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
  match stream.truncated_at {
    Some(at) => {
      resource_diagnostic(state, make_span(source, at, source.byte_length()), statement_id_for_span(stream, make_span(source, at, at)))
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
