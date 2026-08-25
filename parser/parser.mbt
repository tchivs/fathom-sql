///|
/// A bounded recursive-descent document parser with one Pratt expression path.
/// Recovery always either consumes input or creates an explicit zero-width node.
pub(all) enum ParseMode {
  Strict
  Editor
}

///|
priv enum ExpressionContext {
  Ordinary
  ProjectionItem
  CountArgument
}

///|
priv struct ExpressionPostfixResult {
  valid : Bool
  wildcard_complete : Bool
}

///|
pub(all) enum ParserLimitError {
  MaxBytes(Int)
  MaxTokens(Int)
  MaxRecursionDepth(Int)
  MaxRecoverySteps(Int)
  MaxDiagnostics(Int)
}

///|
fn nonnegative_limit(value : Int) -> Int {
  if value < 0 {
    0
  } else {
    value
  }
}

///|
pub struct ParserLimits {
  max_bytes : Int
  max_tokens : Int
  max_recursion_depth : Int
  max_recovery_steps : Int
  max_diagnostics : Int
}

///|
pub fn ParserLimits::default() -> ParserLimits {
  {
    max_bytes: 8 * 1024 * 1024,
    max_tokens: 1_000_000,
    max_recursion_depth: 128,
    max_recovery_steps: 10_000,
    max_diagnostics: 100,
  }
}

///|
pub fn ParserLimits::new(
  max_bytes : Int,
  max_tokens : Int,
  max_recursion_depth : Int,
  max_recovery_steps : Int,
  max_diagnostics : Int,
) -> ParserLimits {
  {
    max_bytes,
    max_tokens,
    max_recursion_depth,
    max_recovery_steps,
    max_diagnostics,
  }
}

///|
pub fn ParserLimits::validate(
  self : ParserLimits,
) -> Result[Unit, ParserLimitError] {
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

///|
pub fn ParserLimits::normalized(self : ParserLimits) -> ParserLimits {
  {
    max_bytes: nonnegative_limit(self.max_bytes),
    max_tokens: nonnegative_limit(self.max_tokens),
    max_recursion_depth: nonnegative_limit(self.max_recursion_depth),
    max_recovery_steps: nonnegative_limit(self.max_recovery_steps),
    max_diagnostics: nonnegative_limit(self.max_diagnostics),
  }
}

///|
pub struct ParserDiagnostic {
  severity : String
  code : String
  message : String
  expected_class : String
  span : @source.Span
  statement_id : UInt
}

///|
pub struct ParsedDocument {
  source : @source.SourceText
  mode : ParseMode
  root : @syntax.SyntaxNode
  diagnostics : Array[ParserDiagnostic]
  valid : Bool
  recovered : Bool
}

///|
priv struct Cursor {
  stream : @token.TokenStream
  indices : Array[Int]
  mut position : Int
  // WR-03: paren nesting depth at the current position, maintained
  // incrementally by advance — O(1) per expression context instead of the
  // former 0..position rescan (O(n) per expression, O(n²) per statement).
  mut depth : Int
}

///|
priv struct RecoveryState {
  diagnostics : Array[ParserDiagnostic]
  limits : ParserLimits
  context : @dialect.DialectContext
  feature_events : Array[FeatureEvent]
  mut recovery_steps : Int
  mut resource_emitted : Bool
}

///|
fn token_at(cursor : Cursor) -> @token.Token? {
  cursor.indices
  .get(cursor.position)
  .map(index => cursor.stream.at(index))
  .bind(x => x)
}

///|
fn raw_at(cursor : Cursor) -> Bytes? {
  cursor.indices
  .get(cursor.position)
  .map(index => cursor.stream.raw(index))
  .bind(x => x)
}

///|
/// Advance one token, maintaining paren depth incrementally (WR-03): the
/// token at the current position is consumed, so its depth effect applies
/// now. Rules mirror the former parenthesis_depth rescan exactly — `(`
/// always increments; `)` decrements only above zero (unmatched closing
/// parens clamp at 0). The only direct position mutation outside this
/// function rewinds past "NOT" (a keyword, never a paren), so the
/// incremental depth stays equal to the rescan at every position.
fn advance(cursor : Cursor) -> Unit {
  if cursor.position < cursor.indices.length() {
    match cursor.stream.raw(cursor.indices[cursor.position]) {
      Some(raw) if raw == b"(" => cursor.depth = cursor.depth + 1
      Some(raw) if raw == b")" && cursor.depth > 0 =>
        cursor.depth = cursor.depth - 1
      _ => ()
    }
    cursor.position = cursor.position + 1
  }
}

///|
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
      let folded_right = if right >= 97 && right <= 122 {
        right - 32
      } else {
        right
      }
      if folded_left != folded_right {
        equal = false
      }
      index = index + 1
    }
    equal
  }
}

///|
fn is_keyword(bytes : Bytes, word : Bytes) -> Bool {
  bytes_equal_ci(bytes, word)
}

///|
fn make_span(
  source : @source.SourceText,
  start_byte : Int,
  end_byte : Int,
) -> @source.Span {
  match source.span(start_byte, end_byte) {
    Ok(span) => span
    Err(_) => panic()
  }
}

///|
fn resource_diagnostic(
  state : RecoveryState,
  span : @source.Span,
  statement_id : UInt,
) -> Unit {
  if !state.resource_emitted {
    state.resource_emitted = true
    let limit = if state.limits.max_diagnostics <= 0 {
      1
    } else {
      state.limits.max_diagnostics
    }
    let diagnostic = {
      severity: "error",
      code: "FATHOM-PARSE-004",
      message: "parser resource limit reached",
      expected_class: "resource",
      span,
      statement_id,
    }
    if state.diagnostics.length() < limit {
      state.diagnostics.push(diagnostic)
    } else {
      state.diagnostics[limit - 1] = diagnostic
    }
  }
}

///|
fn add_diagnostic(
  state : RecoveryState,
  code : String,
  message : String,
  expected_class : String,
  span : @source.Span,
  statement_id : UInt,
) -> Unit {
  let limit = if state.limits.max_diagnostics <= 0 {
    1
  } else {
    state.limits.max_diagnostics
  }
  if state.resource_emitted {
    ()
  } else if state.diagnostics.length() < limit {
    state.diagnostics.push({
      severity: "error",
      code,
      message,
      expected_class,
      span,
      statement_id,
    })
  } else {
    resource_diagnostic(state, span, statement_id)
  }
}

///|
fn consume_recovery_step(
  state : RecoveryState,
  span : @source.Span,
  statement_id : UInt,
) -> Bool {
  if state.recovery_steps >= state.limits.max_recovery_steps {
    resource_diagnostic(state, span, statement_id)
    false
  } else {
    state.recovery_steps = state.recovery_steps + 1
    true
  }
}

///|
fn peek_raw(cursor : Cursor, offset : Int) -> Bytes? {
  cursor.indices
  .get(cursor.position + offset)
  .map(index => cursor.stream.raw(index))
  .bind(x => x)
}

///|
/// Paren nesting depth at the current position (WR-03): maintained
/// incrementally by advance, so this is O(1) instead of rescaming tokens
/// 0..position on every expression context (which made end-to-end format
/// O(n²) on comma-heavy input).
fn parenthesis_depth(cursor : Cursor) -> Int {
  cursor.depth
}

///|
fn depth_allowed(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let depth = parenthesis_depth(cursor)
  if depth > state.limits.max_recursion_depth {
    let at = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    resource_diagnostic(state, at, statement_id)
    false
  } else {
    true
  }
}

///|
/// Dialect-aware expression precedence (Phase 11, Pattern 4): the Doris arm
/// returns the frozen v1 table byte-identically (Pitfall 7 — shared-table
/// edits would alter Doris acceptance); the Flink arm layers the Flink-only
/// operators on top.
fn precedence(context : @dialect.DialectContext, cursor : Cursor) -> Int? {
  match context.dialect {
    @dialect.Dialect::Doris => precedence_doris(cursor)
    @dialect.Dialect::Flink => precedence_flink(cursor)
  }
}

///|
/// Doris expression precedence — the v1 table verbatim (frozen baseline).
fn precedence_doris(cursor : Cursor) -> Int? {
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, b"OR") => Some(1)
    Some(raw) if bytes_equal_ci(raw, b"AND") => Some(2)
    Some(raw) if raw == b"=" ||
      raw == b"<" ||
      raw == b">" ||
      raw == b"<=" ||
      raw == b">=" ||
      raw == b"<>" ||
      raw == b"!=" ||
      raw == b"<=>" => Some(3)
    Some(raw) if raw == b"+" || raw == b"-" => Some(4)
    Some(raw) if raw == b"*" || raw == b"/" || raw == b"%" => Some(5)
    Some(raw) if raw == b"|" || raw == b"&" => Some(4)
    _ => None
  }
}

///|
/// Flink expression precedence: the Doris table plus the Flink-only CONCAT
/// operator `||` (Parser-calcite-1.36.0.jj:8793). `||` lexes as ONE token only
/// under Flink (lexer symbol_width_flink), so the Doris arm stays byte-identical
/// (DIALECT-02, Pitfall 7). CONCAT precedence sits between comparison and
/// arithmetic (A3), matching Calcite SqlStdOperatorTable.CONCAT. `=>`
/// (NAMED_ARGUMENT_ASSIGNMENT, :8794) is consumed at the function-call
/// argument layer — not as a binary operator (RESEARCH §7.1, deferred to 11-02).
fn precedence_flink(cursor : Cursor) -> Int? {
  match precedence_doris(cursor) {
    Some(precedence) => Some(precedence)
    None =>
      match raw_at(cursor) {
        Some(raw) if raw == b"||" => Some(3)
        // MJ-04: AT TIME ZONE (SqlStdOperatorTable.AT_TIME_ZONE) sits at the
        // same level as comparison/CONCAT (A3); the binary-operator loop
        // consumes the TIME ZONE qualifier before parsing the RHS operand.
        Some(raw) if bytes_equal_ci(raw, b"AT") => Some(3)
        _ => None
      }
  }
}

///|
fn is_word_token(cursor : Cursor) -> Bool {
  match token_at(cursor) {
    Some(token) if token.kind is @token.TokenKind::Quoted => true
    Some(token) if token.kind is @token.TokenKind::Identifier =>
      match raw_at(cursor) {
        Some(raw) => @dialect.is_unquoted_identifier(cursor.stream.context, raw)
        None => false
      }
    _ => false
  }
}

///|
fn consume_word(cursor : Cursor, word : Bytes) -> Bool {
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, word) => {
      advance(cursor)
      true
    }
    _ => false
  }
}

///|
fn consume_symbol(cursor : Cursor, symbol : Bytes) -> Bool {
  match raw_at(cursor) {
    Some(raw) if raw == symbol => {
      advance(cursor)
      true
    }
    _ => false
  }
}

///|
fn expect_word(
  cursor : Cursor,
  word : Bytes,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  message : String,
) -> Bool {
  if consume_word(cursor, word) {
    true
  } else {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      message,
      "keyword",
      make_span(source, at, at),
      statement_id,
    )
    false
  }
}

///|
fn expect_symbol(
  cursor : Cursor,
  symbol : Bytes,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  message : String,
) -> Bool {
  if consume_symbol(cursor, symbol) {
    true
  } else {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      message,
      "symbol",
      make_span(source, at, at),
      statement_id,
    )
    false
  }
}

///|
fn feature_allowed(
  state : RecoveryState,
  feature : @dialect.DorisFeature,
) -> Bool {
  // Feature gates are Doris production availability (D-15): derive the
  // DorisProfile from the validated context. A context whose profile_id is not
  // a Doris profile (Flink contexts, which are rejected at the api boundary)
  // allows nothing — never a silent Doris fallback.
  match @dialect.DorisProfile::from_id(state.context.profile_id) {
    Some(profile) => profile.supports(feature)
    None => false
  }
}

///|
priv struct FeatureEvent {
  span : @source.Span
}

///|
fn record_feature_event(state : RecoveryState, span : @source.Span) -> Unit {
  state.feature_events.push({ span, })
}

///|
fn add_feature_diagnostic(
  state : RecoveryState,
  feature : @dialect.DorisFeature,
  span : @source.Span,
  statement_id : UInt,
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

///|
/// Construct-level dialect negative gate (D-04, FATHOM-PARSE-009): rejects a
/// clause/construct that is valid only in the other dialect — never silently
/// accepted (DIALECT-03). The dialect rides in the parse envelope metadata
/// (D-10), never in the code prefix. Whole-statement unsupported stays on
/// FATHOM-PARSE-007 (unsupported_statement).
fn add_dialect_gate_diagnostic(
  state : RecoveryState,
  span : @source.Span,
  statement_id : UInt,
) -> Unit {
  add_diagnostic(
    state, "FATHOM-PARSE-009", "syntax is not supported in the selected dialect",
    "dialect-gate", span, statement_id,
  )
}

///|
fn version_invalid_node(token : @token.Token) -> @syntax.SyntaxElement {
  @syntax.SyntaxElement::ChildNode(
    require_node(
      @syntax.SyntaxNode::error(token.span, [
        @syntax.SyntaxElement::Leaf(
          @syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceError, token.span),
        ),
      ]),
    ),
  )
}

///|
fn require_node(node : @syntax.SyntaxNode?) -> @syntax.SyntaxNode {
  match node {
    Some(value) => value
    None => panic()
  }
}

///|
fn is_identifier_candidate(cursor : Cursor) -> Bool {
  match token_at(cursor) {
    Some(token) if token.kind is @token.TokenKind::Quoted => true
    Some(token) if token.kind is @token.TokenKind::Identifier =>
      match raw_at(cursor) {
        Some(raw) => @dialect.is_unquoted_identifier(cursor.stream.context, raw)
        None => false
      }
    _ => false
  }
}

///|
fn is_expression_operand(cursor : Cursor, token : @token.Token) -> Bool {
  match token.kind {
    @token.TokenKind::Identifier =>
      match raw_at(cursor) {
        // NULL/TRUE/FALSE and DEFAULT are reserved words that double as
        // value-expression keywords (docs: VALUES (expression | DEFAULT),
        // UPDATE ... SET col = DEFAULT). They stay reserved for identifier
        // acceptance (backticks required as names) while remaining valid
        // expression operands.
        Some(raw) if bytes_equal_ci(raw, b"NULL") ||
          bytes_equal_ci(raw, b"TRUE") ||
          bytes_equal_ci(raw, b"FALSE") ||
          bytes_equal_ci(raw, b"DEFAULT") => true
        _ => is_identifier_candidate(cursor)
      }
    @token.TokenKind::Quoted => true
    @token.TokenKind::StringLiteral | @token.TokenKind::Number => true
    _ => false
  }
}

///|
fn parse_expression_list(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  stop_on_close : Bool,
) -> Bool {
  parse_expression_list_context(
    cursor,
    state,
    source,
    statement_id,
    stop_on_close,
    ExpressionContext::Ordinary,
  )
}

///|
fn parse_expression_list_context(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  stop_on_close : Bool,
  context : ExpressionContext,
) -> Bool {
  let mut any = false
  let mut saw_item = false
  let mut count_star = false
  let mut valid = true
  let mut done = false
  while !done {
    match raw_at(cursor) {
      None => done = true
      Some(raw) if raw == b")" && stop_on_close => done = true
      Some(raw) if raw == b"," => {
        saw_item = true
        let span = match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        add_diagnostic(
          state, "FATHOM-PARSE-002", "expected expression after comma", "expression",
          span, statement_id,
        )
        valid = false
        advance(cursor)
      }
      Some(_) => {
        saw_item = true
        let before = cursor.position
        let item_is_count_star = match context {
          ExpressionContext::CountArgument if !any =>
            raw_at(cursor) is Some(b"*")
          _ => false
        }
        let item_context = match context {
          ExpressionContext::CountArgument if any => ExpressionContext::Ordinary
          _ => context
        }
        let expression_ok = parse_expression_context(
          cursor, 1, 1, state, source, statement_id, item_context,
        )
        any = any || expression_ok
        if item_is_count_star {
          count_star = true
        }
        valid = valid && expression_ok
        if cursor.position == before {
          recover_expression(cursor, state, source, statement_id)
          valid = false
        }
        let comma_span = match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        if !consume_symbol(cursor, b",") {
          done = true
        } else if count_star {
          add_diagnostic(
            state, "FATHOM-PARSE-002", "COUNT(*) accepts exactly one argument", "expression",
            comma_span, statement_id,
          )
          valid = false
          recover_expression(cursor, state, source, statement_id)
          while consume_symbol(cursor, b",") {
            recover_expression(cursor, state, source, statement_id)
          }
          done = true
        } else if raw_at(cursor) is None || raw_at(cursor) is Some(b")") {
          let at = match token_at(cursor) {
            Some(token) => token.span.start_byte
            None => source.byte_length()
          }
          add_diagnostic(
            state,
            "FATHOM-PARSE-002",
            "expected expression after comma",
            "expression",
            make_span(source, at, at),
            statement_id,
          )
          valid = false
          done = true
        }
      }
    }
  }
  if !saw_item {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected expression",
      "expression",
      make_span(source, at, at),
      statement_id,
    )
    valid = false
  }
  any && valid
}

///|
fn expect_window_nulls_order(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if consume_word(cursor, b"FIRST") || consume_word(cursor, b"LAST") {
    true
  } else {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected FIRST or LAST after NULLS",
      "window-order",
      make_span(source, at, at),
      statement_id,
    )
    false
  }
}

///|
fn parse_window_frame_bound(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if consume_word(cursor, b"CURRENT") {
    expect_word(
      cursor, b"ROW", state, source, statement_id, "expected ROW after CURRENT",
    )
  } else {
    let value_ok = if consume_word(cursor, b"UNBOUNDED") {
      true
    } else {
      parse_expression(cursor, 4, 1, state, source, statement_id)
    }
    let qualifier_ok = consume_word(cursor, b"PRECEDING") ||
      consume_word(cursor, b"FOLLOWING")
    if !qualifier_ok {
      let at = match token_at(cursor) {
        Some(token) => token.span.start_byte
        None => source.byte_length()
      }
      add_diagnostic(
        state,
        "FATHOM-PARSE-002",
        "expected PRECEDING or FOLLOWING in window frame",
        "window-frame",
        make_span(source, at, at),
        statement_id,
      )
    }
    value_ok && qualifier_ok
  }
}

///|
fn parse_window_spec(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !consume_symbol(cursor, b"(") {
    return expect_symbol(
      cursor, b"(", state, source, statement_id, "expected opening window specification parenthesis",
    )
  }
  let mut valid = true
  if consume_word(cursor, b"PARTITION") {
    valid = expect_word(
        cursor, b"BY", state, source, statement_id, "expected BY after PARTITION",
      ) &&
      valid
    valid = parse_expression_list(cursor, state, source, statement_id, true) &&
      valid
  }
  if consume_word(cursor, b"ORDER") {
    valid = expect_word(
        cursor, b"BY", state, source, statement_id, "expected BY after ORDER",
      ) &&
      valid
    let mut done = false
    while !done {
      valid = parse_expression(cursor, 1, 1, state, source, statement_id) &&
        valid
      ignore(consume_word(cursor, b"ASC") || consume_word(cursor, b"DESC"))
      if consume_word(cursor, b"NULLS") {
        valid = expect_window_nulls_order(cursor, state, source, statement_id) &&
          valid
      }
      if !consume_symbol(cursor, b",") {
        done = true
      }
    }
  }
  if consume_word(cursor, b"ROWS") ||
    consume_word(cursor, b"RANGE") ||
    consume_word(cursor, b"GROUPS") {
    if consume_word(cursor, b"BETWEEN") {
      valid = parse_window_frame_bound(cursor, state, source, statement_id) &&
        valid
      valid = expect_word(
          cursor, b"AND", state, source, statement_id, "expected AND in window frame",
        ) &&
        valid
      valid = parse_window_frame_bound(cursor, state, source, statement_id) &&
        valid
    } else {
      valid = parse_window_frame_bound(cursor, state, source, statement_id) &&
        valid
    }
  }
  valid = expect_word(
      cursor, b")", state, source, statement_id, "expected closing window parenthesis",
    ) &&
    valid
  valid
}

///|
/// Raw bytes of the significant token before the cursor (used by the
/// function-call argument layer to identify the callable name, e.g. CAST).
fn previous_raw(cursor : Cursor) -> Bytes? {
  if cursor.position > 0 {
    cursor.indices
    .get(cursor.position - 1)
    .map(index => cursor.stream.raw(index))
    .bind(x => x)
  } else {
    None
  }
}

///|
/// Flink reserved words that still start an expression: CAST (:7359) and ROW
/// (:7779) constructors (RESEARCH §7.3). Gated to Flink so the Doris
/// expression-prefix behavior stays byte-identical (Pitfall 7). ARRAY/MAP/
/// MULTISET are not in the flink classification rows, so they already parse as
/// identifier prefixes (the `[` postfix branch below consumes the collection
/// literal).
fn is_flink_expression_prefix(cursor : Cursor) -> Bool {
  if !(cursor.stream.context.dialect is @dialect.Dialect::Flink) {
    return false
  }
  match raw_at(cursor) {
    Some(raw) => bytes_equal_ci(raw, b"CAST") || bytes_equal_ci(raw, b"ROW")
    None => false
  }
}

///|
/// True when the cursor sits on a Flink INTERVAL literal start (`INTERVAL`).
/// Gated to Flink: under Doris INTERVAL stays a plain identifier operand
/// (used as a function argument in DATE_ADD etc.), so the Doris expression
/// prefix path stays byte-identical (Pitfall 7).
fn is_flink_interval_literal(cursor : Cursor) -> Bool {
  if !(cursor.stream.context.dialect is @dialect.Dialect::Flink) {
    return false
  }
  match raw_at(cursor) {
    // MJ-03: INTERVAL is a valid non-reserved column name in Flink. It is an
    // interval literal only when the next token is a string literal or a
    // number (the interval value); otherwise it falls through to the ordinary
    // identifier operand path (`SELECT interval FROM t`).
    Some(raw) if bytes_equal_ci(raw, b"INTERVAL") =>
      match peek_raw(cursor, 1) {
        Some(next) if next.length() > 0 => {
          let c = next[0].to_int()
          // 39 = single quote (string literal), 48-57 = decimal digits.
          c == 39 || (c >= 48 && c <= 57)
        }
        _ => false
      }
    _ => false
  }
}

///|
/// Flink INTERVAL literal: `INTERVAL <value> <unit> [TO <unit>]` where
/// <value> is a string literal or (optionally signed) number and <unit> is an
/// identifier (SECOND/MINUTE/HOUR/DAY/...). Syntax-level only — no interval
/// semantics (the WATERMARK strategy and Window TVF sizes use it as a plain
/// literal; IntervalLiteral, Parser-calcite-1.36.0.jj:4943-4990).
fn parse_flink_interval_literal(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = expect_word(
    cursor, b"INTERVAL", state, source, statement_id, "expected INTERVAL",
  )
  let value_ok = match token_at(cursor) {
    Some(token) if token.kind is @token.TokenKind::StringLiteral ||
      token.kind is @token.TokenKind::Number => {
      advance(cursor)
      true
    }
    Some(_) if raw_at(cursor) is Some(b"+") || raw_at(cursor) is Some(b"-") => {
      advance(cursor)
      match token_at(cursor) {
        Some(token) if token.kind is @token.TokenKind::Number => {
          advance(cursor)
          true
        }
        _ => {
          let at = match token_at(cursor) {
            Some(token) => token.span
            None =>
              make_span(source, source.byte_length(), source.byte_length())
          }
          add_diagnostic(
            state, "FATHOM-PARSE-002", "expected number after sign in INTERVAL value",
            "interval", at, statement_id,
          )
          false
        }
      }
    }
    _ => {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected interval value after INTERVAL", "interval",
        at, statement_id,
      )
      false
    }
  }
  valid = value_ok && valid
  if is_identifier_candidate(cursor) {
    advance(cursor)
  } else {
    let at = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state, "FATHOM-PARSE-002", "expected interval unit after INTERVAL value", "interval-unit",
      at, statement_id,
    )
    valid = false
  }
  if consume_word(cursor, b"TO") {
    if is_identifier_candidate(cursor) {
      advance(cursor)
    } else {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected interval unit after TO", "interval-unit",
        at, statement_id,
      )
      valid = false
    }
  }
  valid
}

///|
/// True when the cursor sits on an identifier followed by the
/// NAMED_ARGUMENT_ASSIGNMENT `=>` arrow (Parser-calcite-1.36.0.jj:8794). Under
/// Flink the arrow is a single `=>` symbol token (lexer symbol_width_flink);
/// under Doris it lexes as the two-token `=` `>` sequence, which this predicate
/// also detects so the Doris argument layer can reject it with FATHOM-PARSE-009
/// (D-04 bidirectional gate — a plain `a = b` comparison never matches because
/// the token after `=` is not `>`).
fn is_named_argument_arrow(cursor : Cursor) -> Bool {
  if !is_identifier_candidate(cursor) {
    return false
  }
  match peek_raw(cursor, 1) {
    Some(raw) if raw == b"=>" => true
    _ =>
      match (peek_raw(cursor, 1), peek_raw(cursor, 2)) {
        (Some(raw), Some(next)) if raw == b"=" && next == b">" => true
        _ => false
      }
  }
}

///|
/// Scans the current function-call argument list (up to the matching `)`) for
/// a named-argument arrow. Returns true when a `=>` (Flink) or `= >` (Doris)
/// sequence appears at the argument-list depth. The shared argument-list path
/// stays byte-identical for arrow-free lists; only arrow lists route through
/// parse_named_argument_list (D-04).
fn argument_list_has_arrow(cursor : Cursor) -> Bool {
  let mut index = cursor.position
  let mut depth = 0
  while index < cursor.indices.length() {
    match cursor.stream.raw(cursor.indices[index]) {
      Some(raw) if raw == b"(" => depth = depth + 1
      Some(raw) if raw == b")" && depth == 0 => return false
      Some(raw) if raw == b")" => depth = depth - 1
      Some(raw) if depth == 0 && raw == b"=>" => return true
      Some(raw) if depth == 0 && raw == b"=" =>
        if index + 1 < cursor.indices.length() {
          match cursor.stream.raw(cursor.indices[index + 1]) {
            Some(next) if next == b">" => return true
            _ => ()
          }
        }
      _ => ()
    }
    index = index + 1
  }
  false
}

///|
/// Function-call argument list with Flink NAMED_ARGUMENT_ASSIGNMENT `=>`
/// (`name => expr`, Parser-calcite-1.36.0.jj:8794). Entered only when the
/// list contains an arrow (argument_list_has_arrow). Under Flink the named
/// argument parses as the name identifier, the arrow, and the value
/// expression; under Doris the two-token `= >` arrow is a construct-level
/// dialect-gate rejection (FATHOM-PARSE-009, D-04). Non-arrow items keep the
/// shared item behavior so arrow-free Doris lists remain byte-identical.
fn parse_named_argument_list(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  context : ExpressionContext,
) -> Bool {
  let mut any = false
  let mut valid = true
  let mut done = false
  while !done {
    match raw_at(cursor) {
      None => done = true
      Some(raw) if raw == b")" => done = true
      Some(raw) if raw == b"," => {
        let span = match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        add_diagnostic(
          state, "FATHOM-PARSE-002", "expected expression after comma", "expression",
          span, statement_id,
        )
        valid = false
        advance(cursor)
      }
      Some(_) => {
        any = true
        let before = cursor.position
        if is_named_argument_arrow(cursor) {
          // Consume the argument name.
          advance(cursor)
          // Consume the arrow: a single `=>` under Flink, or `= >` under Doris.
          match raw_at(cursor) {
            Some(raw) if raw == b"=>" => advance(cursor)
            Some(raw) if raw == b"=" => {
              let span = match token_at(cursor) {
                Some(token) => token.span
                None =>
                  make_span(source, source.byte_length(), source.byte_length())
              }
              if cursor.stream.context.dialect is @dialect.Dialect::Doris {
                // Flink-only NAMED_ARGUMENT_ASSIGNMENT under Doris: D-04 gate.
                add_dialect_gate_diagnostic(state, span, statement_id)
                valid = false
              }
              advance(cursor)
              ignore(consume_symbol(cursor, b">"))
            }
            _ => {
              let span = match token_at(cursor) {
                Some(token) => token.span
                None =>
                  make_span(source, source.byte_length(), source.byte_length())
              }
              add_diagnostic(
                state, "FATHOM-PARSE-002", "expected => after named argument name",
                "named-argument", span, statement_id,
              )
              valid = false
            }
          }
          let value_ok = parse_expression_context(
            cursor,
            1,
            1,
            state,
            source,
            statement_id,
            ExpressionContext::Ordinary,
          )
          valid = value_ok && valid
          if cursor.position == before {
            recover_expression(cursor, state, source, statement_id)
            valid = false
          }
        } else {
          let item_ok = parse_expression_context(
            cursor, 1, 1, state, source, statement_id, context,
          )
          valid = item_ok && valid
          if cursor.position == before {
            recover_expression(cursor, state, source, statement_id)
            valid = false
          }
        }
        if !consume_symbol(cursor, b",") {
          done = true
        } else if raw_at(cursor) is None || raw_at(cursor) is Some(b")") {
          let at = match token_at(cursor) {
            Some(token) => token.span.start_byte
            None => source.byte_length()
          }
          add_diagnostic(
            state,
            "FATHOM-PARSE-002",
            "expected expression after comma",
            "expression",
            make_span(source, at, at),
            statement_id,
          )
          valid = false
          done = true
        }
      }
    }
  }
  if !any {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected expression",
      "expression",
      make_span(source, at, at),
      statement_id,
    )
    valid = false
  }
  any && valid
}

///|
/// Flink-only CAST(x AS type) arguments: the value expression, AS, and the
/// Flink data type (RESEARCH §7.3, dataTypeParserMethods Parser.tdd:759-765).
/// Gated to Flink so the Doris CAST path stays byte-identical.
fn parse_flink_cast_arguments(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  let before = cursor.position
  let expr_ok = parse_expression_context(
    cursor,
    1,
    1,
    state,
    source,
    statement_id,
    ExpressionContext::Ordinary,
  )
  valid = expr_ok && valid
  if cursor.position == before {
    recover_expression(cursor, state, source, statement_id)
    valid = false
  }
  if consume_word(cursor, b"AS") {
    valid = parse_flink_data_type(cursor, state, source, statement_id, 0) &&
      valid
  } else {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected AS in CAST expression",
      "cast",
      make_span(source, at, at),
      statement_id,
    )
    valid = false
  }
  valid
}

///|
fn parse_expression_postfix(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  context : ExpressionContext,
  function_star_allowed : Bool,
) -> ExpressionPostfixResult {
  let mut valid = true
  let mut wildcard_complete = false
  let mut keep_going = true
  while keep_going {
    if consume_symbol(cursor, b".") {
      let star_span = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      let word_after_dot = is_word_token(cursor)
      if consume_symbol(cursor, b"*") {
        match context {
          ExpressionContext::ProjectionItem => {
            wildcard_complete = true
            keep_going = false
          }
          _ => {
            add_diagnostic(
              state, "FATHOM-PARSE-002", "wildcard is only valid as a projection item or COUNT(*) argument",
              "expression", star_span, statement_id,
            )
            valid = false
            keep_going = false
          }
        }
      } else if word_after_dot {
        advance(cursor)
      } else {
        let at = match token_at(cursor) {
          Some(token) => token.span.start_byte
          None => source.byte_length()
        }
        add_diagnostic(
          state,
          "FATHOM-PARSE-002",
          "expected qualified identifier",
          "identifier",
          make_span(source, at, at),
          statement_id,
        )
        valid = false
        keep_going = false
      }
    } else if raw_at(cursor) is Some(b"(") {
      let callable = previous_raw(cursor)
      advance(cursor)
      if !consume_symbol(cursor, b")") {
        let argument_context = if function_star_allowed {
          ExpressionContext::CountArgument
        } else {
          ExpressionContext::Ordinary
        }
        let is_cast = match callable {
          Some(raw) => bytes_equal_ci(raw, b"CAST")
          None => false
        }
        if cursor.stream.context.dialect is @dialect.Dialect::Flink && is_cast {
          // Flink-only CAST(x AS type): the AS-type argument (RESEARCH §7.3).
          valid = parse_flink_cast_arguments(
              cursor, state, source, statement_id,
            ) &&
            valid
        } else if argument_list_has_arrow(cursor) {
          // Flink-only NAMED_ARGUMENT_ASSIGNMENT `=>` (:8794) in the argument
          // layer; under Doris the `= >` two-token arrow is a 009 gate.
          valid = parse_named_argument_list(
              cursor, state, source, statement_id, argument_context,
            ) &&
            valid
        } else {
          valid = parse_expression_list_context(
              cursor, state, source, statement_id, true, argument_context,
            ) &&
            valid
        }
        valid = expect_word(
            cursor, b")", state, source, statement_id, "expected closing function parenthesis",
          ) &&
          valid
      }
      ()
    } else if raw_at(cursor) is Some(b"[") &&
      cursor.stream.context.dialect is @dialect.Dialect::Flink {
      // Flink collection literal `[ ... ]` (ARRAY/MAP constructors — Calcite
      // Collection/Map, Parser-calcite-1.36.0.jj). Gated to Flink so Doris
      // never sees a `[` postfix.
      advance(cursor)
      if !consume_symbol(cursor, b"]") {
        let mut array_valid = true
        let mut array_done = false
        while !array_done {
          let before = cursor.position
          let item_ok = parse_expression_context(
            cursor,
            1,
            1,
            state,
            source,
            statement_id,
            ExpressionContext::Ordinary,
          )
          array_valid = item_ok && array_valid
          if cursor.position == before {
            recover_expression(cursor, state, source, statement_id)
            array_valid = false
          }
          if consume_symbol(cursor, b",") {
            if raw_at(cursor) is Some(b"]") || raw_at(cursor) is None {
              let at = match token_at(cursor) {
                Some(token) => token.span.start_byte
                None => source.byte_length()
              }
              add_diagnostic(
                state,
                "FATHOM-PARSE-002",
                "expected expression after comma in collection literal",
                "expression",
                make_span(source, at, at),
                statement_id,
              )
              array_valid = false
              array_done = true
            }
          } else {
            array_done = true
          }
        }
        valid = expect_symbol(
            cursor, b"]", state, source, statement_id, "expected closing collection bracket",
          ) &&
          valid &&
          array_valid
      }
      ()
    } else if consume_word(cursor, b"OVER") {
      let has_spec = match raw_at(cursor) {
        Some(raw) => raw == b"("
        None => false
      }
      let has_name = is_identifier_candidate(cursor)
      if has_spec {
        valid = parse_window_spec(cursor, state, source, statement_id) && valid
      } else if has_name {
        advance(cursor)
      } else {
        add_diagnostic(
          state,
          "FATHOM-PARSE-002",
          "expected window name or specification",
          "window",
          match token_at(cursor) {
            Some(token) => token.span
            None =>
              make_span(source, source.byte_length(), source.byte_length())
          },
          statement_id,
        )
        valid = false
      }
      ()
    } else if consume_word(cursor, b"IS") {
      ignore(consume_word(cursor, b"NOT"))
      if !(consume_word(cursor, b"NULL") ||
        consume_word(cursor, b"TRUE") ||
        consume_word(cursor, b"FALSE") ||
        consume_word(cursor, b"UNKNOWN")) {
        add_diagnostic(
          state,
          "FATHOM-PARSE-002",
          "expected NULL or boolean predicate",
          "predicate",
          match token_at(cursor) {
            Some(token) => token.span
            None =>
              make_span(source, source.byte_length(), source.byte_length())
          },
          statement_id,
        )
        valid = false
      }
      ()
    } else if consume_word(cursor, b"NOT") {
      if consume_word(cursor, b"IN") ||
        consume_word(cursor, b"LIKE") ||
        consume_word(cursor, b"REGEXP") {
        valid = parse_predicate_rhs(cursor, state, source, statement_id) &&
          valid
        ()
      } else {
        cursor.position = cursor.position - 1
        keep_going = false
      }
    } else if consume_word(cursor, b"IN") ||
      consume_word(cursor, b"LIKE") ||
      consume_word(cursor, b"REGEXP") {
      valid = parse_predicate_rhs(cursor, state, source, statement_id) && valid
      ()
    } else if consume_word(cursor, b"BETWEEN") {
      valid = parse_expression(cursor, 4, 1, state, source, statement_id) &&
        valid
      valid = expect_word(
          cursor, b"AND", state, source, statement_id, "expected AND in BETWEEN predicate",
        ) &&
        valid
      valid = parse_expression(cursor, 4, 1, state, source, statement_id) &&
        valid
      ()
    } else {
      keep_going = false
    }
  }
  { valid, wildcard_complete }
}

///|
fn parse_predicate_rhs(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if consume_symbol(cursor, b"(") {
    let mut valid = true
    if is_query_start(cursor) {
      valid = parse_query(cursor, state, source, statement_id)
    } else {
      valid = parse_expression_list(cursor, state, source, statement_id, true)
    }
    valid = expect_word(
        cursor, b")", state, source, statement_id, "expected closing predicate parenthesis",
      ) &&
      valid
    valid
  } else {
    parse_expression(cursor, 4, 1, state, source, statement_id)
  }
}

///|
fn wildcard_has_invalid_continuation(cursor : Cursor) -> Bool {
  let operator = match precedence(cursor.stream.context, cursor) {
    Some(_) => true
    None => false
  }
  let continuation = match raw_at(cursor) {
    Some(raw) if raw == b"." || raw == b"(" => true
    Some(raw) if bytes_equal_ci(raw, b"IS") ||
      bytes_equal_ci(raw, b"NOT") ||
      bytes_equal_ci(raw, b"IN") ||
      bytes_equal_ci(raw, b"LIKE") ||
      bytes_equal_ci(raw, b"REGEXP") ||
      bytes_equal_ci(raw, b"BETWEEN") ||
      bytes_equal_ci(raw, b"OVER") => true
    _ => false
  }
  operator || continuation
}

///|
fn parse_expression(
  cursor : Cursor,
  minimum_precedence : Int,
  depth : Int,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  parse_expression_context(
    cursor,
    minimum_precedence,
    depth,
    state,
    source,
    statement_id,
    ExpressionContext::Ordinary,
  )
}

///|
fn parse_expression_context(
  cursor : Cursor,
  minimum_precedence : Int,
  depth : Int,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  context : ExpressionContext,
) -> Bool {
  let current_span = match token_at(cursor) {
    Some(token) => token.span
    None => make_span(source, source.byte_length(), source.byte_length())
  }
  if depth > state.limits.max_recursion_depth ||
    !depth_allowed(cursor, state, source, statement_id) {
    resource_diagnostic(state, current_span, statement_id)
    return false
  }
  let mut prefix_ok = false
  let mut wildcard_prefix = false
  let mut function_star_allowed = false
  match token_at(cursor) {
    Some(_token) if is_flink_interval_literal(cursor) =>
      // Flink INTERVAL literal `INTERVAL '5' SECOND` (IntervalLiteral,
      // Parser-calcite-1.36.0.jj:4943-4990). Gated to Flink so the Doris
      // expression-prefix path stays byte-identical (Pitfall 7, A4).
      prefix_ok = parse_flink_interval_literal(
        cursor, state, source, statement_id,
      )
    Some(token) if is_expression_operand(cursor, token) => {
      function_star_allowed = if token.kind is @token.TokenKind::Identifier {
        match raw_at(cursor) {
          Some(raw) => bytes_equal_ci(raw, b"COUNT")
          None => false
        }
      } else {
        false
      }
      advance(cursor)
      prefix_ok = true
    }
    Some(token) if token.kind is @token.TokenKind::Symbol &&
      raw_at(cursor) is Some(b"(") => {
      advance(cursor)
      if is_query_start(cursor) {
        prefix_ok = parse_query(cursor, state, source, statement_id)
      } else {
        prefix_ok = parse_expression_context(
          cursor,
          1,
          depth + 1,
          state,
          source,
          statement_id,
          ExpressionContext::Ordinary,
        )
      }
      prefix_ok = expect_word(
          cursor, b")", state, source, statement_id, "expected closing parenthesis",
        ) &&
        prefix_ok
    }
    Some(_) if raw_at(cursor) is Some(b"*") =>
      match context {
        ExpressionContext::ProjectionItem | ExpressionContext::CountArgument => {
          advance(cursor)
          wildcard_prefix = true
          prefix_ok = true
        }
        ExpressionContext::Ordinary =>
          add_diagnostic(
            state, "FATHOM-PARSE-002", "wildcard is only valid as a projection item or COUNT(*) argument",
            "expression", current_span, statement_id,
          )
      }
    Some(_) if raw_at(cursor) is Some(b"+") ||
      raw_at(cursor) is Some(b"-") ||
      bytes_equal_ci(
        match raw_at(cursor) {
          Some(raw) => raw
          None => b""
        },
        b"NOT",
      ) => {
      advance(cursor)
      prefix_ok = parse_expression_context(
        cursor,
        6,
        depth + 1,
        state,
        source,
        statement_id,
        ExpressionContext::Ordinary,
      )
    }
    Some(_token) if is_flink_expression_prefix(cursor) => {
      // Flink-only reserved-word expression starts: CAST/ROW constructors
      // (RESEARCH §7.3). Gated to Flink; Doris prefix behavior unchanged.
      advance(cursor)
      prefix_ok = true
    }
    Some(token) =>
      add_diagnostic(
        state,
        "FATHOM-PARSE-002",
        "expected literal, identifier, or subquery expression",
        "expression",
        token.span,
        statement_id,
      )
    None =>
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected expression", "expression", current_span,
        statement_id,
      )
  }
  if !prefix_ok {
    false
  } else {
    let postfix = if wildcard_prefix {
      { valid: true, wildcard_complete: true }
    } else {
      parse_expression_postfix(
        cursor, state, source, statement_id, context, function_star_allowed,
      )
    }
    let mut valid = postfix.valid
    let mut wildcard_complete = wildcard_prefix || postfix.wildcard_complete
    if wildcard_complete && wildcard_has_invalid_continuation(cursor) {
      let span = match token_at(cursor) {
        Some(token) => token.span
        None => current_span
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "wildcard must be a complete projection item or COUNT(*) argument",
        "expression", span, statement_id,
      )
      recover_expression(cursor, state, source, statement_id)
      valid = false
      wildcard_complete = false
    }
    let mut keep_going = true
    while keep_going {
      match precedence(cursor.stream.context, cursor) {
        Some(operator_precedence) if operator_precedence >= minimum_precedence => {
          // MJ-04: AT TIME ZONE is a Flink-only binary operator whose RHS is
          // prefixed by the TIME ZONE qualifier (SqlStdOperatorTable
          // .AT_TIME_ZONE). The operator is consumed first, then the
          // qualifier, then the RHS operand. Under Doris `AT` has no
          // precedence entry, so this branch never fires there.
          let operator_raw = match raw_at(cursor) {
            Some(raw) => raw
            None => b""
          }
          advance(cursor)
          if bytes_equal_ci(operator_raw, b"AT") &&
            cursor.stream.context.dialect is @dialect.Dialect::Flink {
            valid = expect_word(
                cursor, b"TIME", state, source, statement_id, "expected TIME after AT in AT TIME ZONE",
              ) &&
              valid
            valid = expect_word(
                cursor, b"ZONE", state, source, statement_id, "expected ZONE after AT TIME in AT TIME ZONE",
              ) &&
              valid
          }
          let rhs = parse_expression_context(
            cursor,
            operator_precedence + 1,
            depth + 1,
            state,
            source,
            statement_id,
            ExpressionContext::Ordinary,
          )
          valid = rhs && valid
          if !rhs {
            keep_going = false
          }
        }
        _ => keep_going = false
      }
      if keep_going {
        let next_postfix = parse_expression_postfix(
          cursor,
          state,
          source,
          statement_id,
          ExpressionContext::Ordinary,
          false,
        )
        valid = next_postfix.valid && valid
      }
    }
    valid
  }
}

///|
fn is_query_start(cursor : Cursor) -> Bool {
  match raw_at(cursor) {
    Some(raw) => bytes_equal_ci(raw, b"SELECT") || bytes_equal_ci(raw, b"WITH")
    None => false
  }
}

///|
fn parse_identifier_option(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  option : String,
) -> Bool {
  if !consume_symbol(cursor, b"(") {
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected parenthesized " + option + " option",
      "option",
      match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      },
      statement_id,
    )
    return false
  }
  parse_identifier_list_after_open(cursor, state, source, statement_id, option)
}

// Assumes the opening parenthesis has already been consumed; parses the
// comma-separated identifier list through the closing parenthesis.

///|
fn parse_identifier_list_after_open(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  option : String,
) -> Bool {
  if raw_at(cursor) is Some(b")") {
    let span = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected non-empty " + option + " list",
      "option",
      span,
      statement_id,
    )
    advance(cursor)
    return false
  }
  let mut valid = true
  let mut any = false
  let mut done = false
  while !done {
    if is_identifier_candidate(cursor) {
      any = true
      advance(cursor)
    } else {
      let span = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state,
        "FATHOM-PARSE-002",
        "expected identifier in " + option + " list",
        "identifier",
        span,
        statement_id,
      )
      valid = false
      if raw_at(cursor) is Some(b")") {
        done = true
      } else {
        advance(cursor)
      }
    }
    if !done {
      if consume_symbol(cursor, b",") {
        if raw_at(cursor) is Some(b")") {
          let span = match token_at(cursor) {
            Some(token) => token.span
            None =>
              make_span(source, source.byte_length(), source.byte_length())
          }
          add_diagnostic(
            state,
            "FATHOM-PARSE-002",
            "expected identifier after comma in " + option + " list",
            "identifier",
            span,
            statement_id,
          )
          valid = false
          done = true
        }
      } else {
        done = true
      }
    }
  }
  let closed = expect_symbol(
    cursor,
    b")",
    state,
    source,
    statement_id,
    "expected closing " + option + " parenthesis",
  )
  any && valid && closed
}

///|
fn parse_table_value_option(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  option : String,
  allow_unit : Bool,
  allow_multiple : Bool,
) -> Bool {
  if !consume_symbol(cursor, b"(") {
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected parenthesized " + option + " option",
      "option",
      match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      },
      statement_id,
    )
    return false
  }
  if raw_at(cursor) is Some(b")") {
    let span = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected non-empty " + option + " value",
      "option",
      span,
      statement_id,
    )
    advance(cursor)
    return false
  }
  let mut valid = true
  let mut done = false
  while !done {
    valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
    if consume_symbol(cursor, b",") {
      if !allow_multiple {
        let span = match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        add_diagnostic(
          state,
          "FATHOM-PARSE-002",
          option + " accepts a single value",
          "option",
          span,
          statement_id,
        )
        valid = false
      }
      if raw_at(cursor) is Some(b")") {
        let span = match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        add_diagnostic(
          state,
          "FATHOM-PARSE-002",
          "expected value after comma in " + option,
          "option",
          span,
          statement_id,
        )
        valid = false
        done = true
      }
    } else {
      done = true
    }
  }
  if allow_unit {
    ignore(consume_word(cursor, b"ROWS") || consume_word(cursor, b"PERCENT"))
  }
  expect_symbol(
    cursor,
    b")",
    state,
    source,
    statement_id,
    "expected closing " + option + " parenthesis",
  ) &&
  valid
}

///|
/// Doris-only table options that the Flink SELECT path must reject with
/// FATHOM-PARSE-009 (D-04, RESEARCH §9 matrix): PARTITION/TABLET/SAMPLE/
/// TABLESAMPLE/REPEATABLE (parser.mbt :917-975).
fn is_doris_only_table_option(cursor : Cursor) -> Bool {
  match raw_at(cursor) {
    Some(raw) =>
      bytes_equal_ci(raw, b"PARTITION") ||
      bytes_equal_ci(raw, b"TABLET") ||
      bytes_equal_ci(raw, b"SAMPLE") ||
      bytes_equal_ci(raw, b"TABLESAMPLE") ||
      bytes_equal_ci(raw, b"REPEATABLE")
    None => false
  }
}

///|
/// True when the cursor sits on a Flink Window TVF starter (FLINK-05): a
/// TUMBLE/HOP/CUMULATE/SESSION identifier or the TABLE(...) wrapper followed
/// by `(`. TUMBLE/HOP/SESSION/DESCRIPTOR are non-reserved words (Parser.tdd:
/// 587/:384/:509/:351) and CUMULATE has no keyword token at all (RESEARCH A2),
/// so the TVF call rides the generic table-function-call path
/// (TableFunctionCall, Parser.jj:2443-2460). Dialect-neutral — the branch in
/// parse_table_ref decides parse (Flink) vs FATHOM-PARSE-009 gate (Doris,
/// T-11-23).
fn is_flink_tvf_starter(cursor : Cursor) -> Bool {
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, b"TABLE") =>
      peek_raw(cursor, 1) is Some(b"(")
    Some(raw) if bytes_equal_ci(raw, b"TUMBLE") ||
      bytes_equal_ci(raw, b"HOP") ||
      bytes_equal_ci(raw, b"CUMULATE") ||
      bytes_equal_ci(raw, b"SESSION") => peek_raw(cursor, 1) is Some(b"(")
    _ => false
  }
}

///|
/// True when the cursor sits on a MATCH_RECOGNIZE suffix: the reserved
/// MATCH_RECOGNIZE word followed by `(` (MatchRecognize(SqlNode tableRef),
/// Parser.jj:3062-3183). Dialect-neutral — the branch in parse_table_ref
/// decides parse (Flink) vs FATHOM-PARSE-009 gate (Doris, T-11-22).
fn is_match_recognize_suffix(cursor : Cursor) -> Bool {
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, b"MATCH_RECOGNIZE") =>
      peek_raw(cursor, 1) is Some(b"(")
    _ => false
  }
}

///|
fn parse_table_ref(
  cursor : Cursor,
  context : @dialect.DialectContext,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  // FLINK-05 Window TVF table-function calls: TUMBLE/HOP/CUMULATE/SESSION or
  // the TABLE(...) wrapper parse through parse_flink_tvf_call (flink_grammar.
  // mbt) under Flink; under Doris the same shape is a Flink-only construct →
  // FATHOM-PARSE-009 at the table-ref point (D-04, T-11-23).
  if is_flink_tvf_starter(cursor) {
    if context.dialect is @dialect.Dialect::Flink {
      valid = parse_flink_tvf_call(cursor, state, source, statement_id) && valid
    } else {
      let span = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_dialect_gate_diagnostic(state, span, statement_id)
      valid = false
      consume_gated_remainder(cursor, state, source, statement_id)
      return valid
    }
  } else if consume_symbol(cursor, b"(") {
    valid = parse_query(cursor, state, source, statement_id)
    valid = expect_word(
        cursor, b")", state, source, statement_id, "expected closing subquery parenthesis",
      ) &&
      valid
  } else {
    let mut name_parts = 0
    while is_identifier_candidate(cursor) {
      advance(cursor)
      name_parts = name_parts + 1
      if consume_symbol(cursor, b".") {
        if !is_identifier_candidate(cursor) {
          let at = match token_at(cursor) {
            Some(token) => token.span.start_byte
            None => source.byte_length()
          }
          add_diagnostic(
            state,
            "FATHOM-PARSE-002",
            "expected table identifier after dot",
            "identifier",
            make_span(source, at, at),
            statement_id,
          )
          valid = false
          break
        }
      } else {
        break
      }
    }
    if name_parts == 0 {
      let at = match token_at(cursor) {
        Some(token) => token.span.start_byte
        None => source.byte_length()
      }
      add_diagnostic(
        state,
        "FATHOM-PARSE-002",
        "expected table reference",
        "table",
        make_span(source, at, at),
        statement_id,
      )
      valid = false
    }
  }
  let mut option_done = false
  while !option_done {
    // D-04 bidirectional negative gate: PARTITION/TABLET/SAMPLE/TABLESAMPLE/
    // REPEATABLE are Doris-only table options (parser.mbt :917-975). Under
    // Flink they are rejected with FATHOM-PARSE-009, never parsed.
    if context.dialect is @dialect.Dialect::Flink &&
      is_doris_only_table_option(cursor) {
      let span = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_dialect_gate_diagnostic(state, span, statement_id)
      valid = false
      option_done = true
    } else if consume_word(cursor, b"PARTITION") {
      valid = parse_identifier_option(
          cursor, state, source, statement_id, "PARTITION",
        ) &&
        valid
    } else if raw_at(cursor) is Some(raw) &&
      is_keyword(raw, @dialect.DorisFeature::Tablet.metadata().keyword) &&
      peek_raw(cursor, 1) is Some(b"(") {
      let feature = @dialect.DorisFeature::Tablet
      let span = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      advance(cursor)
      if !feature_allowed(state, feature) {
        add_feature_diagnostic(state, feature, span, statement_id)
        valid = false
      }
      valid = parse_table_value_option(
          cursor, state, source, statement_id, "TABLET", false, true,
        ) &&
        valid
    } else if consume_word(cursor, b"SAMPLE") {
      valid = parse_table_value_option(
          cursor, state, source, statement_id, "SAMPLE", true, false,
        ) &&
        valid
      if consume_word(cursor, b"REPEATABLE") {
        if consume_symbol(cursor, b"(") {
          valid = parse_expression(cursor, 1, 1, state, source, statement_id) &&
            valid
          valid = expect_symbol(
              cursor, b")", state, source, statement_id, "expected closing REPEATABLE parenthesis",
            ) &&
            valid
        } else {
          valid = parse_expression(cursor, 1, 1, state, source, statement_id) &&
            valid
        }
      }
    } else if consume_word(cursor, b"TABLESAMPLE") {
      valid = parse_table_value_option(
          cursor, state, source, statement_id, "TABLESAMPLE", true, false,
        ) &&
        valid
      if consume_word(cursor, b"REPEATABLE") {
        if consume_symbol(cursor, b"(") {
          valid = parse_expression(cursor, 1, 1, state, source, statement_id) &&
            valid
          valid = expect_symbol(
              cursor, b")", state, source, statement_id, "expected closing REPEATABLE parenthesis",
            ) &&
            valid
        } else {
          valid = parse_expression(cursor, 1, 1, state, source, statement_id) &&
            valid
        }
      }
    } else {
      option_done = true
    }
  }
  // FLINK-06 MATCH_RECOGNIZE suffix on the table reference (MatchRecognize
  // (SqlNode tableRef), Parser.jj:3062-3183): under Flink the reserved
  // MATCH_RECOGNIZE word + `(` routes to parse_match_recognize (flink_grammar.
  // mbt); under Doris it is a Flink-only construct → FATHOM-PARSE-009
  // (T-11-22), never misparsed as a table alias.
  if is_match_recognize_suffix(cursor) {
    if context.dialect is @dialect.Dialect::Flink {
      valid = parse_match_recognize(cursor, state, source, statement_id) &&
        valid
    } else {
      let span = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_dialect_gate_diagnostic(state, span, statement_id)
      valid = false
      consume_gated_remainder(cursor, state, source, statement_id)
      return valid
    }
  }
  if consume_word(cursor, b"AS") {
    let alias_ok = is_identifier_candidate(cursor)
    if !alias_ok {
      add_diagnostic(
        state,
        "FATHOM-PARSE-002",
        "expected table alias",
        "identifier",
        match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        },
        statement_id,
      )
      valid = false
    } else {
      advance(cursor)
    }
  } else {
    let alias_ok = is_identifier_candidate(cursor)
    if alias_ok {
      advance(cursor)
    }
  }
  valid
}

///|
fn parse_from(
  cursor : Cursor,
  context : @dialect.DialectContext,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = parse_table_ref(cursor, context, state, source, statement_id)
  let mut done = false
  while !done {
    if consume_symbol(cursor, b",") {
      valid = parse_table_ref(cursor, context, state, source, statement_id) &&
        valid
    } else {
      let modifier : String? = if consume_word(cursor, b"INNER") {
        ignore(consume_word(cursor, b"OUTER"))
        Some("INNER")
      } else if consume_word(cursor, b"LEFT") {
        ignore(consume_word(cursor, b"OUTER"))
        Some("LEFT")
      } else if consume_word(cursor, b"RIGHT") {
        ignore(consume_word(cursor, b"OUTER"))
        Some("RIGHT")
      } else if consume_word(cursor, b"FULL") {
        ignore(consume_word(cursor, b"OUTER"))
        Some("FULL")
      } else if consume_word(cursor, b"CROSS") {
        Some("CROSS")
      } else if consume_word(cursor, b"NATURAL") {
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
      } else {
        None
      }
      let has_join = consume_word(cursor, b"JOIN")
      if !has_join {
        match modifier {
          Some(_) => {
            let at = match token_at(cursor) {
              Some(token) => token.span.start_byte
              None => source.byte_length()
            }
            add_diagnostic(
              state,
              "FATHOM-PARSE-002",
              "expected JOIN after join modifier",
              "join",
              make_span(source, at, at),
              statement_id,
            )
            valid = false
          }
          None => done = true
        }
      } else {
        valid = parse_table_ref(cursor, context, state, source, statement_id) &&
          valid
        let requires_condition = match modifier {
          Some(name) =>
            name != "CROSS" &&
            name != "NATURAL" &&
            name != "NATURAL_LEFT" &&
            name != "NATURAL_RIGHT"
          None => true
        }
        if consume_word(cursor, b"ON") {
          valid = parse_expression(cursor, 1, 1, state, source, statement_id) &&
            valid
        } else if consume_word(cursor, b"USING") {
          valid = parse_identifier_option(
              cursor, state, source, statement_id, "USING",
            ) &&
            valid
        } else if requires_condition {
          let at = match token_at(cursor) {
            Some(token) => token.span.start_byte
            None => source.byte_length()
          }
          add_diagnostic(
            state,
            "FATHOM-PARSE-002",
            "expected ON or USING after JOIN",
            "join-condition",
            make_span(source, at, at),
            statement_id,
          )
          valid = false
        }
      }
    }
  }
  valid
}

///|
fn parse_grouping_arguments(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  name : String,
) -> Bool {
  if !consume_symbol(cursor, b"(") {
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected opening " + name + " parenthesis",
      "grouping",
      match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      },
      statement_id,
    )
    return false
  }
  if raw_at(cursor) is Some(b")") {
    let span = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected expression in " + name + "",
      "grouping",
      span,
      statement_id,
    )
    advance(cursor)
    false
  } else {
    let valid = parse_expression_list(cursor, state, source, statement_id, true)
    let closed = expect_word(
      cursor, b")", state, source, statement_id, "expected closing grouping parenthesis",
    )
    closed && valid
  }
}

///|
fn parse_group_by(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = expect_word(
    cursor, b"BY", state, source, statement_id, "expected BY after GROUP",
  )
  if !valid {
    return false
  }
  if consume_word(cursor, b"GROUPING") {
    valid = expect_word(
        cursor, b"SETS", state, source, statement_id, "expected SETS after GROUPING",
      ) &&
      valid
    if !valid {
      return false
    }
    valid = expect_symbol(
        cursor, b"(", state, source, statement_id, "expected opening GROUPING SETS parenthesis",
      ) &&
      valid
    if !valid {
      return false
    }
    if raw_at(cursor) is Some(b")") {
      let span = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected grouping set in GROUPING SETS", "grouping",
        span, statement_id,
      )
      advance(cursor)
      false
    } else {
      while raw_at(cursor) is Some(_) && !(raw_at(cursor) is Some(b")")) {
        if consume_symbol(cursor, b"(") {
          valid = parse_expression_list(
              cursor, state, source, statement_id, true,
            ) &&
            valid
          valid = expect_word(
              cursor, b")", state, source, statement_id, "expected grouping set parenthesis",
            ) &&
            valid
        } else {
          valid = parse_expression(cursor, 1, 1, state, source, statement_id) &&
            valid
        }
        if consume_symbol(cursor, b",") {
          if raw_at(cursor) is Some(b")") {
            let span = match token_at(cursor) {
              Some(token) => token.span
              None =>
                make_span(source, source.byte_length(), source.byte_length())
            }
            add_diagnostic(
              state, "FATHOM-PARSE-002", "expected grouping set after comma", "grouping",
              span, statement_id,
            )
            valid = false
            break
          }
        } else {
          break
        }
      }
      valid = expect_word(
          cursor, b")", state, source, statement_id, "expected grouping sets parenthesis",
        ) &&
        valid
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

///|
fn parse_order_by(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = expect_word(
    cursor, b"BY", state, source, statement_id, "expected BY after ORDER",
  )
  valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
  while consume_word(cursor, b"ASC") || consume_word(cursor, b"DESC") {
    ()
  }
  if consume_word(cursor, b"NULLS") {
    valid = expect_window_nulls_order(cursor, state, source, statement_id) &&
      valid
  }
  while consume_symbol(cursor, b",") {
    valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
    while consume_word(cursor, b"ASC") || consume_word(cursor, b"DESC") {
      ()
    }
    if consume_word(cursor, b"NULLS") {
      valid = expect_window_nulls_order(cursor, state, source, statement_id) &&
        valid
    }
  }
  valid
}

///|
fn parse_limit(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = parse_expression(cursor, 1, 1, state, source, statement_id)
  if consume_symbol(cursor, b",") || consume_word(cursor, b"OFFSET") {
    valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
  }
  valid
}

///|
fn parse_select_core(
  cursor : Cursor,
  context : @dialect.DialectContext,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !expect_word(
      cursor, b"SELECT", state, source, statement_id, "expected SELECT statement",
    ) {
    return false
  }
  let mut valid = true
  let mut has_except = false
  let modifier : String? = if consume_word(cursor, b"DISTINCT") {
    Some("DISTINCT")
  } else if consume_word(cursor, b"DISTINCTROW") {
    Some("DISTINCTROW")
  } else if consume_word(cursor, b"ALL") {
    Some("ALL")
  } else {
    None
  }
  let except_span = match token_at(cursor) {
    Some(token) => token.span
    None => make_span(source, source.byte_length(), source.byte_length())
  }
  // The EXCEPT projection modifier is Doris-only (:1174-1183); under Flink
  // EXCEPT is a set-operation keyword handled by parse_flink_query's
  // CompoundQuery loop (Parser-calcite-1.36.0.jj:3395), so the modifier arm
  // stays gated to Doris (D-04, RESEARCH §6.2).
  if context.dialect is @dialect.Dialect::Doris &&
    consume_word(cursor, b"EXCEPT") {
    has_except = true
    if modifier is Some("ALL") {
      valid = parse_identifier_option(
          cursor, state, source, statement_id, "ALL EXCEPT",
        ) &&
        valid
    } else {
      add_diagnostic(
        state, "FATHOM-PARSE-002", "EXCEPT requires the ALL projection modifier",
        "projection", except_span, statement_id,
      )
      valid = parse_identifier_option(
          cursor, state, source, statement_id, "EXCEPT",
        ) &&
        valid
      valid = false
    }
  }
  if has_except && raw_at(cursor) is Some(raw) && is_keyword(raw, b"FROM") {
    valid = true && valid
  } else {
    valid = parse_expression_list_until_clause(
        cursor, state, source, statement_id,
      ) &&
      valid
  }
  if consume_word(cursor, b"FROM") {
    valid = parse_from(cursor, context, state, source, statement_id) && valid
  }
  if consume_word(cursor, b"WHERE") {
    valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
  }
  if consume_word(cursor, b"GROUP") {
    valid = parse_group_by(cursor, state, source, statement_id) && valid
  }
  if consume_word(cursor, b"HAVING") {
    valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
  }
  if consume_word(cursor, b"WINDOW") {
    while is_word_token(cursor) {
      advance(cursor)
      valid = expect_word(
          cursor, b"AS", state, source, statement_id, "expected AS in WINDOW definition",
        ) &&
        valid
      valid = parse_window_spec(cursor, state, source, statement_id) && valid
      if consume_symbol(cursor, b",") {
        if !is_word_token(cursor) {
          let span = match token_at(cursor) {
            Some(token) => token.span
            None =>
              make_span(source, source.byte_length(), source.byte_length())
          }
          add_diagnostic(
            state, "FATHOM-PARSE-002", "expected window name after comma", "identifier",
            span, statement_id,
          )
          valid = false
          break
        }
      } else {
        break
      }
    }
  }
  let qualify_span = match token_at(cursor) {
    Some(token) => token.span
    None => make_span(source, source.byte_length(), source.byte_length())
  }
  if consume_word(cursor, b"QUALIFY") {
    match context.dialect {
      @dialect.Dialect::Doris => {
        let feature = @dialect.DorisFeature::Qualify
        if !feature_allowed(state, feature) {
          add_feature_diagnostic(state, feature, qualify_span, statement_id)
          valid = false
        }
        valid = parse_expression(cursor, 1, 1, state, source, statement_id) &&
          valid
      }
      @dialect.Dialect::Flink => {
        // Doris-only QUALIFY clause (D-04): construct-level negative gate.
        add_dialect_gate_diagnostic(state, qualify_span, statement_id)
        valid = false
      }
    }
  }
  if consume_word(cursor, b"ORDER") {
    valid = parse_order_by(cursor, state, source, statement_id) && valid
  }
  if consume_word(cursor, b"LIMIT") {
    valid = parse_limit(cursor, state, source, statement_id) && valid
  }
  let into_span = match token_at(cursor) {
    Some(token) => token.span
    None => make_span(source, source.byte_length(), source.byte_length())
  }
  if consume_word(cursor, b"INTO") {
    match context.dialect {
      @dialect.Dialect::Doris => {
        valid = expect_word(
            cursor, b"OUTFILE", state, source, statement_id, "expected OUTFILE after INTO",
          ) &&
          valid
        let is_string = match token_at(cursor) {
          Some(token) => token.kind is @token.TokenKind::StringLiteral
          None => false
        }
        if !is_string {
          add_diagnostic(
            state,
            "FATHOM-PARSE-002",
            "expected outfile string",
            "string",
            match token_at(cursor) {
              Some(token) => token.span
              None =>
                make_span(source, source.byte_length(), source.byte_length())
            },
            statement_id,
          )
          valid = false
        } else {
          advance(cursor)
        }
      }
      @dialect.Dialect::Flink => {
        // Doris-only INTO OUTFILE (D-04): construct-level negative gate.
        add_dialect_gate_diagnostic(state, into_span, statement_id)
        valid = false
      }
    }
  }
  valid
}

///|
fn is_projection_boundary(
  context : @dialect.DialectContext,
  raw : Bytes,
) -> Bool {
  @dialect.is_clause_keyword(context, raw) || raw == b";" || raw == b")"
}

///|
fn is_projection_alias_candidate(cursor : Cursor) -> Bool {
  if !is_identifier_candidate(cursor) {
    false
  } else {
    match raw_at(cursor) {
      Some(raw) if bytes_equal_ci(raw, b"AS") || bytes_equal_ci(raw, b"OVER") =>
        false
      Some(_) =>
        match peek_raw(cursor, 1) {
          None => true
          Some(next) =>
            next == b"," || is_projection_boundary(cursor.stream.context, next)
        }
      None => false
    }
  }
}

///|
fn parse_projection_alias(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if consume_word(cursor, b"AS") {
    let alias_token = is_identifier_candidate(cursor)
    if alias_token {
      advance(cursor)
      true
    } else {
      add_diagnostic(
        state,
        "FATHOM-PARSE-002",
        "expected projection alias",
        "identifier",
        match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        },
        statement_id,
      )
      false
    }
  } else if is_projection_alias_candidate(cursor) {
    advance(cursor)
    true
  } else {
    true
  }
}

///|
fn parse_expression_list_until_clause(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut any = false
  let mut valid = true
  let mut done = false
  while !done {
    match raw_at(cursor) {
      None => done = true
      Some(raw) if is_projection_boundary(cursor.stream.context, raw) =>
        done = true
      Some(_) => {
        let before = cursor.position
        let item = if raw_at(cursor) is Some(b"*") &&
          peek_raw(cursor, 1) is Some(raw) &&
          is_keyword(raw, b"EXCEPT") {
          advance(cursor)
          ignore(consume_word(cursor, b"EXCEPT"))
          parse_identifier_option(
            cursor, state, source, statement_id, "projection EXCEPT",
          )
        } else {
          parse_expression_context(
            cursor,
            1,
            1,
            state,
            source,
            statement_id,
            ExpressionContext::ProjectionItem,
          )
        }
        any = any || item
        valid = valid && item
        valid = parse_projection_alias(cursor, state, source, statement_id) &&
          valid
        if cursor.position == before {
          recover_expression(cursor, state, source, statement_id)
          valid = false
        }
        if consume_symbol(cursor, b",") {
          match raw_at(cursor) {
            None => {
              add_diagnostic(
                state,
                "FATHOM-PARSE-002",
                "expected expression after projection comma",
                "expression",
                make_span(source, source.byte_length(), source.byte_length()),
                statement_id,
              )
              valid = false
              done = true
            }
            Some(raw) if is_projection_boundary(cursor.stream.context, raw) => {
              let at = match token_at(cursor) {
                Some(token) => token.span.start_byte
                None => source.byte_length()
              }
              add_diagnostic(
                state,
                "FATHOM-PARSE-002",
                "expected expression after projection comma",
                "expression",
                make_span(source, at, at),
                statement_id,
              )
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
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected expression after SELECT",
      "expression",
      make_span(source, at, at),
      statement_id,
    )
  }
  any && valid
}

// Consumes a WITH CTE prefix shared by SELECT, UPDATE, DELETE, and MERGE.

///|
fn parse_cte_prefix(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !consume_word(cursor, b"WITH") {
    return false
  }
  let mut valid = true
  let recursive_span = match token_at(cursor) {
    Some(token) => token.span
    None => make_span(source, source.byte_length(), source.byte_length())
  }
  if consume_word(cursor, b"RECURSIVE") {
    // Calcite base WithList accepts WITH RECURSIVE (Flink); only Doris gates
    // it with FATHOM-PARSE-006. The shared diagnostic stays Doris-only so the
    // Flink arm parses recursive CTEs syntactically (D-04, RESEARCH §6.2).
    if cursor.stream.context.dialect is @dialect.Dialect::Doris {
      add_diagnostic(
        state, "FATHOM-PARSE-006", "feature WITH RECURSIVE is unsupported", "feature",
        recursive_span, statement_id,
      )
      valid = false
    }
  }
  let mut cte_done = false
  while !cte_done {
    let cte_name = is_identifier_candidate(cursor)
    if !cte_name {
      add_diagnostic(
        state,
        "FATHOM-PARSE-002",
        "expected CTE name",
        "identifier",
        match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        },
        statement_id,
      )
      valid = false
      break
    }
    advance(cursor)
    if consume_symbol(cursor, b"(") {
      while raw_at(cursor) is Some(_) && !(raw_at(cursor) is Some(b")")) {
        advance(cursor)
      }
    }
    valid = expect_word(
        cursor, b"AS", state, source, statement_id, "expected AS in CTE",
      ) &&
      valid
    if !consume_symbol(cursor, b"(") {
      add_diagnostic(
        state,
        "FATHOM-PARSE-002",
        "expected CTE query parenthesis",
        "subquery",
        match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        },
        statement_id,
      )
      valid = false
    } else {
      valid = parse_query(cursor, state, source, statement_id) && valid
      valid = expect_word(
          cursor, b")", state, source, statement_id, "expected closing CTE parenthesis",
        ) &&
        valid
    }
    if !consume_symbol(cursor, b",") {
      cte_done = true
    }
  }
  valid
}

///|
fn parse_query(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) {
    return false
  }
  let context = cursor.stream.context
  let mut valid = true
  if raw_at(cursor) is Some(raw) && bytes_equal_ci(raw, b"WITH") {
    valid = parse_cte_prefix(cursor, state, source, statement_id) && valid
  }
  valid = parse_select_core(cursor, context, state, source, statement_id) &&
    valid
  while consume_word(cursor, b"UNION") {
    ignore(consume_word(cursor, b"ALL"))
    ignore(consume_word(cursor, b"DISTINCT"))
    valid = parse_select_core(cursor, context, state, source, statement_id) &&
      valid
  }
  valid
}

///|
fn parse_qualified_name(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  message : String,
) -> Bool {
  let mut parts = 0
  let mut valid = true
  while is_identifier_candidate(cursor) {
    advance(cursor)
    parts = parts + 1
    if consume_symbol(cursor, b".") {
      if !is_identifier_candidate(cursor) {
        let at = match token_at(cursor) {
          Some(token) => token.span.start_byte
          None => source.byte_length()
        }
        add_diagnostic(
          state,
          "FATHOM-PARSE-002",
          "expected identifier after dot in " + message,
          "identifier",
          make_span(source, at, at),
          statement_id,
        )
        valid = false
        break
      }
    } else {
      break
    }
  }
  if parts == 0 {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected " + message,
      "identifier",
      make_span(source, at, at),
      statement_id,
    )
    valid = false
  }
  valid
}

// Token-scans a WITH CTE prefix and returns the first significant token after
// the last CTE close (the statement verb), so the keyword-first dispatcher can
// route WITH-prefixed statements (WITH c AS (...) SELECT/UPDATE/...).

///|
fn with_prefix_verb(
  stream : @token.TokenStream,
  indices : Array[Int],
  start_index : Int,
) -> Bytes? {
  let mut i = start_index + 1
  let length = indices.length()
  if i >= length {
    return None
  }
  let recursive = match stream.raw(indices[i]) {
    Some(raw) => bytes_equal_ci(raw, b"RECURSIVE")
    None => false
  }
  if recursive {
    i = i + 1
  }
  while true {
    if i >= length {
      return None
    }
    // CTE name (single token)
    i = i + 1
    // CR-04: the loop skips the CTE name without re-checking the bound — a
    // `WITH t` input (two significant tokens, no AS/statement tail) leaves
    // i == length and `stream.raw(indices[i])` aborted with an out-of-bounds
    // Array::at panic (SIGABRT, EXIT 134). Bail with None before any read.
    if i >= length {
      return None
    }
    // Optional ( column list ): consume to the matching close parenthesis.
    // The former `Some(raw) if i < length` guard was dead — its scrutinee
    // was evaluated before the guard — and is removed (IN-03); the bound is
    // enforced by the check above and the guarded `.get(i)` read.
    let has_column_list = match
      indices.get(i).bind(index => stream.raw(index)) {
      Some(raw) => raw == b"("
      None => false
    }
    if has_column_list {
      i = i + 1
      let mut depth = 1
      while i < length && depth > 0 {
        match stream.raw(indices[i]) {
          Some(raw) if raw == b"(" => depth = depth + 1
          Some(raw) if raw == b")" => depth = depth - 1
          _ => ()
        }
        i = i + 1
      }
    }
    if i >= length {
      return None
    }
    let has_as = match stream.raw(indices[i]) {
      Some(raw) => bytes_equal_ci(raw, b"AS")
      None => false
    }
    if !has_as {
      return stream.raw(indices[i])
    }
    i = i + 1
    if i >= length {
      return None
    }
    if !(stream.raw(indices[i]) is Some(b"(")) {
      return stream.raw(indices[i])
    }
    i = i + 1
    let mut depth = 1
    while i < length && depth > 0 {
      match stream.raw(indices[i]) {
        Some(raw) if raw == b"(" => depth = depth + 1
        Some(raw) if raw == b")" => depth = depth - 1
        _ => ()
      }
      i = i + 1
    }
    if i >= length {
      return None
    }
    if stream.raw(indices[i]) is Some(b",") {
      i = i + 1
    } else {
      return stream.raw(indices[i])
    }
  }
  None
}

///|
fn parse_values_rows(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  let mut done = false
  while !done {
    if !consume_symbol(cursor, b"(") {
      valid = expect_symbol(
          cursor, b"(", state, source, statement_id, "expected VALUES row parenthesis",
        ) &&
        valid
      done = true
    } else {
      valid = parse_expression_list(cursor, state, source, statement_id, true) &&
        valid
      valid = expect_symbol(
          cursor, b")", state, source, statement_id, "expected closing VALUES row parenthesis",
        ) &&
        valid
      if !consume_symbol(cursor, b",") {
        done = true
      }
    }
  }
  valid
}

///|
fn parse_insert(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) {
    return false
  }
  let mut valid = expect_word(
    cursor, b"INSERT", state, source, statement_id, "expected INSERT statement",
  )
  if consume_word(cursor, b"OVERWRITE") {
    valid = expect_word(
        cursor, b"table", state, source, statement_id, "expected table after INSERT OVERWRITE",
      ) &&
      valid
  } else {
    valid = expect_word(
        cursor, b"INTO", state, source, statement_id, "expected INTO after INSERT",
      ) &&
      valid
  }
  valid = parse_qualified_name(
      cursor, state, source, statement_id, "table name",
    ) &&
    valid
  if consume_word(cursor, b"PARTITION") {
    if !consume_symbol(cursor, b"(") {
      valid = expect_symbol(
          cursor, b"(", state, source, statement_id, "expected opening PARTITION parenthesis",
        ) &&
        valid
    } else if raw_at(cursor) is Some(b"*") {
      let star_span = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      let feature = @dialect.DorisFeature::PartitionStar
      if !feature_allowed(state, feature) {
        add_feature_diagnostic(state, feature, star_span, statement_id)
        valid = false
      }
      advance(cursor)
      valid = expect_symbol(
          cursor, b")", state, source, statement_id, "expected closing PARTITION parenthesis",
        ) &&
        valid
    } else {
      valid = parse_identifier_list_after_open(
          cursor, state, source, statement_id, "PARTITION",
        ) &&
        valid
    }
  }
  if consume_word(cursor, b"WITH") {
    valid = expect_word(
        cursor, b"LABEL", state, source, statement_id, "expected LABEL after WITH in INSERT",
      ) &&
      valid
    if is_identifier_candidate(cursor) {
      advance(cursor)
    } else {
      let at = match token_at(cursor) {
        Some(token) => token.span.start_byte
        None => source.byte_length()
      }
      add_diagnostic(
        state,
        "FATHOM-PARSE-002",
        "expected label after WITH LABEL",
        "identifier",
        make_span(source, at, at),
        statement_id,
      )
      valid = false
    }
  }
  if raw_at(cursor) is Some(b"(") {
    valid = parse_identifier_option(
        cursor, state, source, statement_id, "column",
      ) &&
      valid
  }
  // Hint blocks are lexer comments (trivia) and are preserved as leaves
  // automatically; no explicit consumption is required.
  if consume_word(cursor, b"VALUES") {
    valid = parse_values_rows(cursor, state, source, statement_id) && valid
  } else if is_query_start(cursor) {
    valid = parse_query(cursor, state, source, statement_id) && valid
  } else {
    let at = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state, "FATHOM-PARSE-002", "expected VALUES or query after INSERT", "insert-source",
      at, statement_id,
    )
    valid = false
  }
  valid
}

// Per-family clause sync predicates (research Pattern 2, Pitfall 3): the
// shared is_clause_keyword set is never extended with DML words.

///|
fn is_update_clause_boundary(raw : Bytes) -> Bool {
  bytes_equal_ci(raw, b"SET") ||
  bytes_equal_ci(raw, b"FROM") ||
  bytes_equal_ci(raw, b"WHERE") ||
  bytes_equal_ci(raw, b"ORDER") ||
  bytes_equal_ci(raw, b"LIMIT")
}

///|
fn is_delete_clause_boundary(raw : Bytes) -> Bool {
  bytes_equal_ci(raw, b"PARTITION") ||
  bytes_equal_ci(raw, b"PARTITIONS") ||
  bytes_equal_ci(raw, b"USING") ||
  bytes_equal_ci(raw, b"WHERE") ||
  bytes_equal_ci(raw, b"ORDER") ||
  bytes_equal_ci(raw, b"LIMIT")
}

///|
fn is_merge_clause_boundary(raw : Bytes) -> Bool {
  bytes_equal_ci(raw, b"USING") ||
  bytes_equal_ci(raw, b"ON") ||
  bytes_equal_ci(raw, b"WHEN") ||
  bytes_equal_ci(raw, b"MATCHED") ||
  bytes_equal_ci(raw, b"AND") ||
  bytes_equal_ci(raw, b"THEN") ||
  bytes_equal_ci(raw, b"UPDATE") ||
  bytes_equal_ci(raw, b"DELETE") ||
  bytes_equal_ci(raw, b"INSERT")
}

///|
/// Flink RichSqlInsert recovery boundary (parserImpls.ftl:2306-2379, D-03):
/// an unclosed PARTITION/column list recovers to the next insert clause —
/// PARTITION, ON CONFLICT, the source (SELECT/VALUES), or the closing
/// parenthesis — rather than swallowing the statement (CST-01, T-11-12).
fn is_flink_insert_boundary(raw : Bytes) -> Bool {
  bytes_equal_ci(raw, b"PARTITION") ||
  bytes_equal_ci(raw, b"ON") ||
  bytes_equal_ci(raw, b"CONFLICT") ||
  bytes_equal_ci(raw, b"SELECT") ||
  bytes_equal_ci(raw, b"VALUES") ||
  raw == b")"
}

///|
/// Flink CREATE TABLE recovery boundary (SqlCreateTable, parserImpls.ftl:
/// 1585-1712, D-03): the table-level clause sequence in the pinned order
/// [COMMENT][DISTRIBUTED][PARTITIONED BY][WITH][LIKE|AS]. An unclosed column
/// body / incomplete clause recovers at the next table-level clause keyword
/// (or the LIKE/AS tail) instead of swallowing the statement (CST-01,
/// T-11-18 — bounded best-effort recovery).
fn is_flink_create_table_clause_boundary(raw : Bytes) -> Bool {
  bytes_equal_ci(raw, b"COMMENT") ||
  bytes_equal_ci(raw, b"DISTRIBUTED") ||
  bytes_equal_ci(raw, b"PARTITIONED") ||
  bytes_equal_ci(raw, b"WITH") ||
  bytes_equal_ci(raw, b"LIKE") ||
  bytes_equal_ci(raw, b"AS") ||
  bytes_equal_ci(raw, b"PRIMARY") ||
  bytes_equal_ci(raw, b"UNIQUE") ||
  bytes_equal_ci(raw, b"WATERMARK")
}

///|
/// Flink MATCH_RECOGNIZE sub-language recovery boundary (MatchRecognize,
/// Parser.jj:3062-3346, D-03): the independent sub-language sync points —
/// PARTITION/ORDER/MEASURES/ONE ROW/ALL ROWS/AFTER MATCH/PATTERN/WITHIN/
/// DEFINE and the closing `)`. An unclosed PATTERN or DEFINE recovers at the
/// next sub-language clause or `;` under the shared recovery budget — no
/// infinite push (Pitfall 4/8, CST-01, T-11-24).
fn is_flink_match_recognize_boundary(raw : Bytes) -> Bool {
  bytes_equal_ci(raw, b"PARTITION") ||
  bytes_equal_ci(raw, b"ORDER") ||
  bytes_equal_ci(raw, b"MEASURES") ||
  bytes_equal_ci(raw, b"ONE") ||
  bytes_equal_ci(raw, b"ALL") ||
  bytes_equal_ci(raw, b"AFTER") ||
  bytes_equal_ci(raw, b"PATTERN") ||
  bytes_equal_ci(raw, b"WITHIN") ||
  bytes_equal_ci(raw, b"DEFINE") ||
  raw == b")"
}

// Bounded best-effort recovery to the next per-family clause keyword; the
// statement-level ';' panic-mode and recovery-step cap are unchanged.

///|
fn recover_to_clause_boundary(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  boundary : (Bytes) -> Bool,
) -> Unit {
  let mut consumed = false
  let mut done = false
  while !done {
    match raw_at(cursor) {
      None => done = true
      Some(raw) if raw == b";" || boundary(raw) => done = true
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
  if !consumed && raw_at(cursor) is Some(_) {
    match raw_at(cursor) {
      Some(raw) if raw == b";" || boundary(raw) => ()
      _ => advance(cursor)
    }
  }
}

///|
fn parse_assignment_list(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  let mut done = false
  while !done {
    valid = parse_qualified_name(
        cursor, state, source, statement_id, "column name",
      ) &&
      valid
    valid = expect_symbol(
        cursor, b"=", state, source, statement_id, "expected = in SET assignment",
      ) &&
      valid
    valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
    if !consume_symbol(cursor, b",") {
      done = true
    }
  }
  valid
}

///|
fn parse_update(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) {
    return false
  }
  let mut valid = true
  if raw_at(cursor) is Some(raw) && bytes_equal_ci(raw, b"WITH") {
    valid = parse_cte_prefix(cursor, state, source, statement_id) && valid
  }
  valid = expect_word(
      cursor, b"UPDATE", state, source, statement_id, "expected UPDATE statement",
    ) &&
    valid
  valid = parse_qualified_name(
      cursor, state, source, statement_id, "target table",
    ) &&
    valid
  // Optional table alias; a family clause keyword is never consumed as an alias.
  if is_identifier_candidate(cursor) {
    match raw_at(cursor) {
      Some(raw) if is_update_clause_boundary(raw) => ()
      _ => advance(cursor)
    }
  }
  if consume_word(cursor, b"SET") {
    let set_ok = parse_assignment_list(cursor, state, source, statement_id)
    if !set_ok {
      recover_to_clause_boundary(
        cursor, state, source, statement_id, is_update_clause_boundary,
      )
    }
    valid = set_ok && valid
  } else {
    let at = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state, "FATHOM-PARSE-002", "expected SET clause in UPDATE", "clause", at, statement_id,
    )
    valid = false
    recover_to_clause_boundary(
      cursor, state, source, statement_id, is_update_clause_boundary,
    )
  }
  if consume_word(cursor, b"FROM") {
    let from_ok = parse_from(
      cursor,
      cursor.stream.context,
      state,
      source,
      statement_id,
    )
    if !from_ok {
      recover_to_clause_boundary(
        cursor, state, source, statement_id, is_update_clause_boundary,
      )
    }
    valid = from_ok && valid
  }
  if consume_word(cursor, b"WHERE") {
    let where_ok = parse_expression(cursor, 1, 1, state, source, statement_id)
    if !where_ok {
      recover_to_clause_boundary(
        cursor, state, source, statement_id, is_update_clause_boundary,
      )
    }
    valid = where_ok && valid
  }
  if consume_word(cursor, b"ORDER") {
    let order_ok = parse_order_by(cursor, state, source, statement_id)
    if !order_ok {
      recover_to_clause_boundary(
        cursor, state, source, statement_id, is_update_clause_boundary,
      )
    }
    valid = order_ok && valid
  }
  if consume_word(cursor, b"LIMIT") {
    let limit_ok = parse_limit(cursor, state, source, statement_id)
    if !limit_ok {
      recover_to_clause_boundary(
        cursor, state, source, statement_id, is_update_clause_boundary,
      )
    }
    valid = limit_ok && valid
  }
  valid
}

///|
fn parse_delete(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) {
    return false
  }
  let mut valid = true
  if raw_at(cursor) is Some(raw) && bytes_equal_ci(raw, b"WITH") {
    valid = parse_cte_prefix(cursor, state, source, statement_id) && valid
  }
  valid = expect_word(
      cursor, b"DELETE", state, source, statement_id, "expected DELETE statement",
    ) &&
    valid
  valid = expect_word(
      cursor, b"FROM", state, source, statement_id, "expected FROM after DELETE",
    ) &&
    valid
  valid = parse_qualified_name(
      cursor, state, source, statement_id, "table name",
    ) &&
    valid
  let has_partition = match raw_at(cursor) {
    Some(raw) =>
      bytes_equal_ci(raw, b"PARTITION") || bytes_equal_ci(raw, b"PARTITIONS")
    None => false
  }
  if has_partition {
    let is_partitions = match raw_at(cursor) {
      Some(raw) => bytes_equal_ci(raw, b"PARTITIONS")
      None => false
    }
    advance(cursor)
    if is_partitions {
      let partitions_ok = parse_identifier_option(
        cursor, state, source, statement_id, "PARTITIONS",
      )
      if !partitions_ok {
        recover_to_clause_boundary(
          cursor, state, source, statement_id, is_delete_clause_boundary,
        )
      }
      valid = partitions_ok && valid
    } else if is_identifier_candidate(cursor) {
      advance(cursor)
    } else {
      let at = match token_at(cursor) {
        Some(token) => token.span.start_byte
        None => source.byte_length()
      }
      add_diagnostic(
        state,
        "FATHOM-PARSE-002",
        "expected partition name after PARTITION",
        "identifier",
        make_span(source, at, at),
        statement_id,
      )
      valid = false
    }
  }
  if consume_word(cursor, b"USING") {
    let using_ok = parse_from(
      cursor,
      cursor.stream.context,
      state,
      source,
      statement_id,
    )
    if !using_ok {
      recover_to_clause_boundary(
        cursor, state, source, statement_id, is_delete_clause_boundary,
      )
    }
    valid = using_ok && valid
  }
  if consume_word(cursor, b"WHERE") {
    let where_ok = parse_expression(cursor, 1, 1, state, source, statement_id)
    if !where_ok {
      recover_to_clause_boundary(
        cursor, state, source, statement_id, is_delete_clause_boundary,
      )
    }
    valid = where_ok && valid
  }
  if consume_word(cursor, b"ORDER") {
    let order_ok = parse_order_by(cursor, state, source, statement_id)
    if !order_ok {
      recover_to_clause_boundary(
        cursor, state, source, statement_id, is_delete_clause_boundary,
      )
    }
    valid = order_ok && valid
  }
  if consume_word(cursor, b"LIMIT") {
    let limit_ok = parse_limit(cursor, state, source, statement_id)
    if !limit_ok {
      recover_to_clause_boundary(
        cursor, state, source, statement_id, is_delete_clause_boundary,
      )
    }
    valid = limit_ok && valid
  }
  valid
}

///|
fn parse_merge(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) {
    return false
  }
  let mut valid = true
  if raw_at(cursor) is Some(raw) && bytes_equal_ci(raw, b"WITH") {
    valid = parse_cte_prefix(cursor, state, source, statement_id) && valid
  }
  let merge_span = match token_at(cursor) {
    Some(token) => token.span
    None => make_span(source, source.byte_length(), source.byte_length())
  }
  if !consume_word(cursor, b"MERGE") {
    return valid
  }
  let feature = @dialect.DorisFeature::MergeInto
  if !feature_allowed(state, feature) {
    add_feature_diagnostic(state, feature, merge_span, statement_id)
    // Consume the remainder losslessly; the version_invalid_node leaf
    // substitution (segment_children_for_events) keeps the source intact.
    let mut gate_done = false
    while !gate_done {
      match raw_at(cursor) {
        None => gate_done = true
        Some(raw) if raw == b";" => gate_done = true
        Some(_) => {
          let at_span = match token_at(cursor) {
            Some(token) => token.span
            None =>
              make_span(source, source.byte_length(), source.byte_length())
          }
          if consume_recovery_step(state, at_span, statement_id) {
            advance(cursor)
          } else {
            gate_done = true
          }
        }
      }
    }
    return false
  }
  valid = expect_word(
      cursor, b"INTO", state, source, statement_id, "expected INTO after MERGE",
    ) &&
    valid
  valid = parse_qualified_name(
      cursor, state, source, statement_id, "target table",
    ) &&
    valid
  if consume_word(cursor, b"USING") {
    let using_ok = parse_table_ref(
      cursor,
      cursor.stream.context,
      state,
      source,
      statement_id,
    )
    if !using_ok {
      recover_to_clause_boundary(
        cursor, state, source, statement_id, is_merge_clause_boundary,
      )
    }
    valid = using_ok && valid
  } else {
    valid = expect_word(
        cursor, b"USING", state, source, statement_id, "expected USING in MERGE",
      ) &&
      valid
  }
  if consume_word(cursor, b"ON") {
    let on_ok = parse_expression(cursor, 1, 1, state, source, statement_id)
    if !on_ok {
      recover_to_clause_boundary(
        cursor, state, source, statement_id, is_merge_clause_boundary,
      )
    }
    valid = on_ok && valid
  } else {
    valid = expect_word(
        cursor, b"ON", state, source, statement_id, "expected ON in MERGE",
      ) &&
      valid
  }
  let mut when_count = 0
  let mut when_done = false
  while !when_done {
    if !consume_word(cursor, b"WHEN") {
      when_done = true
    } else {
      when_count = when_count + 1
      if consume_word(cursor, b"NOT") {
        valid = expect_word(
            cursor, b"MATCHED", state, source, statement_id, "expected MATCHED after WHEN NOT",
          ) &&
          valid
      } else {
        valid = expect_word(
            cursor, b"MATCHED", state, source, statement_id, "expected MATCHED after WHEN",
          ) &&
          valid
      }
      if consume_word(cursor, b"AND") {
        let case_ok = parse_expression(
          cursor, 1, 1, state, source, statement_id,
        )
        if !case_ok {
          recover_to_clause_boundary(
            cursor, state, source, statement_id, is_merge_clause_boundary,
          )
        }
        valid = case_ok && valid
      }
      valid = expect_word(
          cursor, b"THEN", state, source, statement_id, "expected THEN in MERGE clause",
        ) &&
        valid
      if consume_word(cursor, b"UPDATE") {
        valid = expect_word(
            cursor, b"SET", state, source, statement_id, "expected SET after THEN UPDATE",
          ) &&
          valid
        let set_ok = parse_assignment_list(cursor, state, source, statement_id)
        if !set_ok {
          recover_to_clause_boundary(
            cursor, state, source, statement_id, is_merge_clause_boundary,
          )
        }
        valid = set_ok && valid
      } else if consume_word(cursor, b"DELETE") {
        ()
      } else if consume_word(cursor, b"INSERT") {
        if raw_at(cursor) is Some(b"(") {
          valid = parse_identifier_option(
              cursor, state, source, statement_id, "column",
            ) &&
            valid
        }
        valid = expect_word(
            cursor, b"VALUES", state, source, statement_id, "expected VALUES after THEN INSERT",
          ) &&
          valid
        if !consume_symbol(cursor, b"(") {
          valid = expect_symbol(
              cursor, b"(", state, source, statement_id, "expected VALUES row parenthesis",
            ) &&
            valid
        } else {
          valid = parse_expression_list(
              cursor, state, source, statement_id, true,
            ) &&
            valid
          valid = expect_symbol(
              cursor, b")", state, source, statement_id, "expected closing VALUES row parenthesis",
            ) &&
            valid
        }
      } else {
        let at = match token_at(cursor) {
          Some(token) => token.span.start_byte
          None => source.byte_length()
        }
        add_diagnostic(
          state,
          "FATHOM-PARSE-002",
          "expected UPDATE, DELETE, or INSERT after THEN",
          "merge-action",
          make_span(source, at, at),
          statement_id,
        )
        valid = false
        recover_to_clause_boundary(
          cursor, state, source, statement_id, is_merge_clause_boundary,
        )
      }
    }
  }
  if when_count == 0 {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected WHEN MATCHED or WHEN NOT MATCHED clause in MERGE",
      "merge-clause",
      make_span(source, at, at),
      statement_id,
    )
    valid = false
  }
  valid
}

// ---------------------------------------------------------------
// DDL: CREATE TABLE / VIEW / INDEX / MATERIALIZED VIEW (02-02)
// ---------------------------------------------------------------
// Grammar authority is the verbatim 4.x grammars in 02-RESEARCH.md
// (sections 6-9). Per-family sync predicates only; the shared
// is_clause_keyword set is never extended with DDL words (Pitfall 3).

// CREATE [TEMPORARY|EXTERNAL] <verb> — resolves the statement kind for the
// keyword-first dispatcher without consuming the cursor.

///|
fn create_form_kind(
  stream : @token.TokenStream,
  indices : Array[Int],
  start_index : Int,
) -> @syntax.SyntaxKind {
  let mut i = start_index + 1
  let length = indices.length()
  if i >= length {
    return @syntax.SyntaxKind::CreateTable
  }
  let modifier = match stream.raw(indices[i]) {
    Some(raw) =>
      bytes_equal_ci(raw, b"TEMPORARY") ||
      bytes_equal_ci(raw, b"EXTERNAL") ||
      bytes_equal_ci(raw, b"ASYNC")
    None => false
  }
  if modifier {
    i = i + 1
  }
  if i >= length {
    return @syntax.SyntaxKind::CreateTable
  }
  match stream.raw(indices[i]) {
    Some(raw) if bytes_equal_ci(raw, b"TABLE") =>
      @syntax.SyntaxKind::CreateTable
    Some(raw) if bytes_equal_ci(raw, b"VIEW") => @syntax.SyntaxKind::CreateView
    Some(raw) if bytes_equal_ci(raw, b"INDEX") =>
      @syntax.SyntaxKind::CreateIndex
    Some(raw) if bytes_equal_ci(raw, b"MATERIALIZED") =>
      @syntax.SyntaxKind::CreateMaterializedView
    _ => @syntax.SyntaxKind::CreateTable
  }
}

///|
/// True when the CREATE statement's form word (after the optional
/// TEMPORARY/EXTERNAL/ASYNC modifier) is a form the Doris parser actually
/// implements — TABLE/VIEW/INDEX/MATERIALIZED. Any other second word
/// (CATALOG/DATABASE/FUNCTION/USER/ROLE/...) means the whole statement is
/// unsupported under Doris and routes to FATHOM-PARSE-007 (D-04 whole-
/// statement gate in parse_doris_segment's CREATE arm).
fn is_doris_create_form(
  stream : @token.TokenStream,
  indices : Array[Int],
  start_index : Int,
) -> Bool {
  let mut i = start_index + 1
  let length = indices.length()
  // No form word (bare CREATE / CREATE TEMPORARY / CREATE EXTERNAL at EOF):
  // this is a Doris incomplete-statement case, NOT a non-Doris form — route
  // to parse_create so it emits the WR-01 FATHOM-PARSE-002 + missing node.
  if i >= length {
    return true
  }
  let modifier = match stream.raw(indices[i]) {
    Some(raw) =>
      bytes_equal_ci(raw, b"TEMPORARY") ||
      bytes_equal_ci(raw, b"EXTERNAL") ||
      bytes_equal_ci(raw, b"ASYNC")
    None => false
  }
  if modifier {
    i = i + 1
  }
  // Same rule after an optional modifier: no form word => Doris bare-create.
  if i >= length {
    return true
  }
  match stream.raw(indices[i]) {
    Some(raw) if bytes_equal_ci(raw, b"TABLE") ||
      bytes_equal_ci(raw, b"VIEW") ||
      bytes_equal_ci(raw, b"INDEX") ||
      bytes_equal_ci(raw, b"MATERIALIZED") => true
    _ => false
  }
}

///|
fn parse_create(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) {
    return false
  }
  let mut valid = expect_word(
    cursor, b"CREATE", state, source, statement_id, "expected CREATE statement",
  )
  ignore(consume_word(cursor, b"TEMPORARY"))
  ignore(consume_word(cursor, b"EXTERNAL"))
  // A2 decision (02-04 Task 2): the released 2.1/3.x/4.x docs document the
  // async materialized view family (page title "CREATE ASYNC MATERIALIZED
  // VIEW"; syntax CREATE MATERIALIZED VIEW with BUILD/REFRESH clauses), so
  // the ASYNC prefix selects the async form instead of FATHOM-PARSE-007.
  let mut async_mv = false
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, b"ASYNC") =>
      match peek_raw(cursor, 1) {
        Some(next) if bytes_equal_ci(next, b"MATERIALIZED") => {
          advance(cursor)
          async_mv = true
        }
        _ => ()
      }
    _ => ()
  }
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, b"TABLE") =>
      valid = parse_create_table(cursor, state, source, statement_id) && valid
    Some(raw) if bytes_equal_ci(raw, b"VIEW") =>
      valid = parse_create_view(cursor, state, source, statement_id) && valid
    Some(raw) if bytes_equal_ci(raw, b"INDEX") =>
      valid = parse_create_index(cursor, state, source, statement_id) && valid
    Some(raw) if bytes_equal_ci(raw, b"MATERIALIZED") =>
      valid = parse_create_materialized_view(
          cursor, state, source, statement_id, async_mv,
        ) &&
        valid
    Some(_) => {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected TABLE, VIEW, INDEX, or MATERIALIZED VIEW after CREATE",
        "create-form", at, statement_id,
      )
      valid = false
    }
    // WR-01: a bare CREATE / CREATE TEMPORARY / CREATE EXTERNAL at EOF must
    // not pass the valid gate silently — every other statement family reports
    // the incomplete-statement diagnostic (FATHOM-PARSE-002) and finish_statement
    // pushes the Missing node because valid is false.
    None => {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected TABLE, VIEW, INDEX, or MATERIALIZED VIEW after CREATE",
        "create-form", at, statement_id,
      )
      valid = false
    }
  }
  valid
}

// CREATE INDEX [ IF NOT EXISTS ] index_name ON table_name ( col list )
//   [ USING { INVERTED | NGRAM_BF | ANN } ] [ PROPERTIES ( "key" = "value" , ... ) ] [ COMMENT '...' ]

///|
fn parse_create_index(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) {
    return false
  }
  let mut valid = expect_word(
    cursor, b"INDEX", state, source, statement_id, "expected INDEX after CREATE",
  )
  if consume_word(cursor, b"IF") {
    valid = expect_word(
        cursor, b"NOT", state, source, statement_id, "expected NOT after IF",
      ) &&
      valid
    valid = expect_word(
        cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF NOT",
      ) &&
      valid
  }
  if !is_identifier_candidate(cursor) {
    let at = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state, "FATHOM-PARSE-002", "expected index name", "identifier", at, statement_id,
    )
    valid = false
  } else {
    advance(cursor)
  }
  valid = expect_word(
      cursor, b"ON", state, source, statement_id, "expected ON after index name",
    ) &&
    valid
  valid = parse_qualified_name(
      cursor, state, source, statement_id, "table name",
    ) &&
    valid
  valid = parse_identifier_option(cursor, state, source, statement_id, "INDEX") &&
    valid
  if consume_word(cursor, b"USING") {
    if is_identifier_candidate(cursor) {
      advance(cursor)
    } else {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected index type after USING", "identifier",
        at, statement_id,
      )
      valid = false
    }
  }
  if consume_word(cursor, b"PROPERTIES") {
    valid = parse_properties_clause(
        cursor, state, source, statement_id, "INDEX PROPERTIES",
      ) &&
      valid
  }
  if consume_word(cursor, b"COMMENT") {
    let is_stringish = match token_at(cursor) {
      Some(token) =>
        token.kind is @token.TokenKind::StringLiteral ||
        token.kind is @token.TokenKind::Quoted
      None => false
    }
    if !is_stringish {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected index comment string after COMMENT",
        "string", at, statement_id,
      )
      valid = false
    } else {
      advance(cursor)
    }
  }
  valid
}

// Sync materialized view body clause boundaries: the docs restrict the query
// to a single base table with no JOIN/HAVING/LIMIT/LATERAL VIEW.

///|
fn is_mv_clause_boundary(raw : Bytes) -> Bool {
  bytes_equal_ci(raw, b"WHERE") ||
  bytes_equal_ci(raw, b"GROUP") ||
  bytes_equal_ci(raw, b"ORDER") ||
  bytes_equal_ci(raw, b"HAVING") ||
  bytes_equal_ci(raw, b"LIMIT") ||
  bytes_equal_ci(raw, b"JOIN") ||
  bytes_equal_ci(raw, b"LATERAL")
}

// CREATE MATERIALIZED VIEW (sync or async form).
//
// Sync form (02-02): CREATE MATERIALIZED VIEW <name> [ AS ] <restricted
//   query> — single base table, no JOIN/HAVING/LIMIT/LATERAL VIEW (docs sync
//   page, research section 9).
//
// Async form (02-04 A2 closure): the docs pages titled "CREATE ASYNC
//   MATERIALIZED VIEW" (2.1/3.x/4.x trees, identical syntax) document
//   CREATE MATERIALIZED VIEW [ IF NOT EXISTS ] <name>
//     [ (<col> [COMMENT '...'] [, ...]) ]
//     [ BUILD IMMEDIATE | DEFERRED ]
//     [ REFRESH COMPLETE | AUTO [ ON MANUAL | ON SCHEDULE EVERY <int> <unit>
//         [ STARTS '<start_time>'] | ON COMMIT ] ]
//     [ [DUPLICATE] KEY (<cols>) ]
//     [ COMMENT '<comment>' ]
//     [ PARTITION BY ( <col> | DATE_TRUNC(<col>, '<unit>') ) ]
//     [ DISTRIBUTED BY { HASH (<cols>) | RANDOM } [ BUCKETS { n | AUTO } ] ]
//     [ PROPERTIES (...) ]
//     AS <query>
// with an unrestricted query body. The bare `CREATE MATERIALIZED VIEW
// <name> [ AS ] query` spelling keeps the sync page's restricted body; the
// async form is selected by the ASYNC prefix, IF NOT EXISTS, or any async
// clause (column list, BUILD, REFRESH, KEY, COMMENT, PARTITION, DISTRIBUTED,
// PROPERTIES) before the query.

///|
fn parse_create_materialized_view(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  async_mv : Bool,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) {
    return false
  }
  let mut valid = expect_word(
    cursor, b"MATERIALIZED", state, source, statement_id, "expected MATERIALIZED after CREATE",
  )
  valid = expect_word(
      cursor, b"VIEW", state, source, statement_id, "expected VIEW after MATERIALIZED",
    ) &&
    valid
  let mut async_form = async_mv
  if consume_word(cursor, b"IF") {
    valid = expect_word(
        cursor, b"NOT", state, source, statement_id, "expected NOT after IF",
      ) &&
      valid
    valid = expect_word(
        cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF NOT",
      ) &&
      valid
    async_form = true
  }
  valid = parse_qualified_name(
      cursor, state, source, statement_id, "materialized view name",
    ) &&
    valid
  if !async_form {
    async_form = match raw_at(cursor) {
      Some(raw) =>
        bytes_equal_ci(raw, b"(") ||
        bytes_equal_ci(raw, b"BUILD") ||
        bytes_equal_ci(raw, b"REFRESH") ||
        bytes_equal_ci(raw, b"KEY") ||
        bytes_equal_ci(raw, b"DUPLICATE") ||
        bytes_equal_ci(raw, b"COMMENT") ||
        bytes_equal_ci(raw, b"PARTITION") ||
        bytes_equal_ci(raw, b"DISTRIBUTED") ||
        bytes_equal_ci(raw, b"PROPERTIES")
      None => false
    }
  }
  if async_form {
    valid = parse_async_mv_clauses(cursor, state, source, statement_id) && valid
  } else {
    ignore(consume_word(cursor, b"AS"))
    valid = parse_mv_query(cursor, state, source, statement_id) && valid
  }
  valid
}

// The async materialized view clause stack, in documented order, ending with
// the mandatory AS <query> (any SELECT, including joins/subqueries/CTEs).

///|
fn parse_async_mv_clauses(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  if raw_at(cursor) is Some(b"(") {
    // columns_definition: <col_name> [ COMMENT '<comment>' ] [ , ... ]
    advance(cursor)
    valid = parse_view_columns(cursor, state, source, statement_id) && valid
    valid = expect_symbol(
        cursor, b")", state, source, statement_id, "expected closing materialized view column parenthesis",
      ) &&
      valid
  }
  if consume_word(cursor, b"BUILD") {
    // BUILD IMMEDIATE | DEFERRED
    if is_identifier_candidate(cursor) {
      advance(cursor)
    } else {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected IMMEDIATE or DEFERRED after BUILD",
        "build-mode", at, statement_id,
      )
      valid = false
    }
  }
  if consume_word(cursor, b"REFRESH") {
    // REFRESH COMPLETE | AUTO [ refresh_trigger ] — AUTO is a reserved word
    // (official reserved list), so match the method spellings explicitly.
    let is_method = match raw_at(cursor) {
      Some(raw) =>
        bytes_equal_ci(raw, b"COMPLETE") || bytes_equal_ci(raw, b"AUTO")
      None => false
    }
    if is_method {
      advance(cursor)
    } else {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected COMPLETE or AUTO after REFRESH", "refresh-method",
        at, statement_id,
      )
      valid = false
    }
    if consume_word(cursor, b"ON") {
      if consume_word(cursor, b"MANUAL") {
        ()
      } else if consume_word(cursor, b"SCHEDULE") {
        // ON SCHEDULE EVERY <int_value> <refresh_unit> [ STARTS '<start_time>' ]
        valid = expect_word(
            cursor, b"EVERY", state, source, statement_id, "expected EVERY after ON SCHEDULE",
          ) &&
          valid
        let is_number = match token_at(cursor) {
          Some(token) => token.kind is @token.TokenKind::Number
          None => false
        }
        if !is_number {
          let at = match token_at(cursor) {
            Some(token) => token.span
            None =>
              make_span(source, source.byte_length(), source.byte_length())
          }
          add_diagnostic(
            state, "FATHOM-PARSE-002", "expected refresh interval number after EVERY",
            "number", at, statement_id,
          )
          valid = false
        } else {
          advance(cursor)
        }
        if !is_identifier_candidate(cursor) {
          let at = match token_at(cursor) {
            Some(token) => token.span
            None =>
              make_span(source, source.byte_length(), source.byte_length())
          }
          add_diagnostic(
            state, "FATHOM-PARSE-002", "expected refresh unit (MINUTE/HOUR/DAY/WEEK) after interval",
            "refresh-unit", at, statement_id,
          )
          valid = false
        } else {
          advance(cursor)
        }
        if consume_word(cursor, b"STARTS") {
          let is_stringish = match token_at(cursor) {
            Some(token) =>
              token.kind is @token.TokenKind::StringLiteral ||
              token.kind is @token.TokenKind::Quoted
            None => false
          }
          if !is_stringish {
            let at = match token_at(cursor) {
              Some(token) => token.span
              None =>
                make_span(source, source.byte_length(), source.byte_length())
            }
            add_diagnostic(
              state, "FATHOM-PARSE-002", "expected start time string after STARTS",
              "string", at, statement_id,
            )
            valid = false
          } else {
            advance(cursor)
          }
        }
      } else if consume_word(cursor, b"COMMIT") {
        ()
      } else {
        let at = match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        add_diagnostic(
          state, "FATHOM-PARSE-002", "expected MANUAL, SCHEDULE, or COMMIT after ON",
          "refresh-trigger", at, statement_id,
        )
        valid = false
      }
    }
  }
  if consume_word(cursor, b"DUPLICATE") {
    valid = expect_word(
        cursor, b"KEY", state, source, statement_id, "expected KEY after DUPLICATE",
      ) &&
      valid
    valid = parse_identifier_option(cursor, state, source, statement_id, "KEY") &&
      valid
  } else if consume_word(cursor, b"KEY") {
    valid = parse_identifier_option(cursor, state, source, statement_id, "KEY") &&
      valid
  }
  if consume_word(cursor, b"COMMENT") {
    let is_stringish = match token_at(cursor) {
      Some(token) =>
        token.kind is @token.TokenKind::StringLiteral ||
        token.kind is @token.TokenKind::Quoted
      None => false
    }
    if !is_stringish {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected materialized view comment string after COMMENT",
        "string", at, statement_id,
      )
      valid = false
    } else {
      advance(cursor)
    }
  }
  if consume_word(cursor, b"PARTITION") {
    valid = expect_word(
        cursor, b"BY", state, source, statement_id, "expected BY after PARTITION",
      ) &&
      valid
    valid = parse_parenthesized_expression(
        cursor, state, source, statement_id, "materialized view PARTITION BY",
      ) &&
      valid
  }
  if consume_word(cursor, b"DISTRIBUTED") {
    valid = parse_distribution_clause(cursor, state, source, statement_id) &&
      valid
  }
  if consume_word(cursor, b"PROPERTIES") {
    valid = parse_properties_clause(
        cursor, state, source, statement_id, "PROPERTIES",
      ) &&
      valid
  }
  if consume_word(cursor, b"AS") {
    if !is_query_start(cursor) {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected query after AS in materialized view",
        "query", at, statement_id,
      )
      valid = false
    } else {
      valid = parse_query(cursor, state, source, statement_id) && valid
    }
  } else {
    let at = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state, "FATHOM-PARSE-002", "expected AS query in materialized view", "query",
      at, statement_id,
    )
    valid = false
    if is_query_start(cursor) {
      valid = parse_query(cursor, state, source, statement_id) && valid
    }
  }
  valid
}

///|
fn parse_mv_query(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) {
    return false
  }
  let mut valid = expect_word(
    cursor, b"SELECT", state, source, statement_id, "expected SELECT in materialized view body",
  )
  valid = parse_expression_list_until_clause(
      cursor, state, source, statement_id,
    ) &&
    valid
  valid = expect_word(
      cursor, b"FROM", state, source, statement_id, "expected FROM in materialized view body",
    ) &&
    valid
  if raw_at(cursor) is Some(b"(") {
    // Docs constraint: single base table, no subquery.
    let at = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state, "FATHOM-PARSE-002", "materialized view body requires a single base table (no subquery)",
      "sync materialized view body", at, statement_id,
    )
    valid = false
  } else {
    // Plain qualified name only: a JOIN/LATERAL VIEW after the name must stay
    // visible to the forbidden-clause check below, so no alias/option parsing.
    valid = parse_qualified_name(
        cursor, state, source, statement_id, "base table",
      ) &&
      valid
  }
  if consume_word(cursor, b"WHERE") {
    valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
  }
  if consume_word(cursor, b"GROUP") {
    valid = expect_word(
        cursor, b"BY", state, source, statement_id, "expected BY after GROUP",
      ) &&
      valid
    valid = parse_mv_column_list(
        cursor, state, source, statement_id, "GROUP BY",
      ) &&
      valid
  }
  if consume_word(cursor, b"ORDER") {
    valid = expect_word(
        cursor, b"BY", state, source, statement_id, "expected BY after ORDER",
      ) &&
      valid
    valid = parse_mv_column_list(
        cursor, state, source, statement_id, "ORDER BY",
      ) &&
      valid
  }
  if raw_at(cursor) is Some(raw) &&
    (
      bytes_equal_ci(raw, b"JOIN") ||
      bytes_equal_ci(raw, b"HAVING") ||
      bytes_equal_ci(raw, b"LIMIT") ||
      bytes_equal_ci(raw, b"LATERAL")
    ) {
    let at = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state, "FATHOM-PARSE-002", "JOIN, HAVING, LIMIT, and LATERAL VIEW are not supported in a sync materialized view body",
      "sync materialized view body", at, statement_id,
    )
    valid = false
  }
  valid
}

// <column_name> [ , ... ] — terminates at the per-family MV clause boundary.

///|
fn parse_mv_column_list(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  what : String,
) -> Bool {
  let mut valid = true
  let mut any = false
  let mut done = false
  while !done {
    match raw_at(cursor) {
      None => done = true
      Some(raw) if is_mv_clause_boundary(raw) => done = true
      Some(_) if is_identifier_candidate(cursor) => {
        any = true
        advance(cursor)
        if consume_symbol(cursor, b",") {
          if raw_at(cursor) is None || raw_at(cursor) is Some(b";") {
            let at = match token_at(cursor) {
              Some(token) => token.span.start_byte
              None => source.byte_length()
            }
            add_diagnostic(
              state,
              "FATHOM-PARSE-002",
              "expected column name after comma in " + what,
              "identifier",
              make_span(source, at, at),
              statement_id,
            )
            valid = false
            done = true
          }
        } else {
          done = true
        }
      }
      Some(_) => {
        let at = match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        add_diagnostic(
          state,
          "FATHOM-PARSE-002",
          "expected column name in " + what,
          "identifier",
          at,
          statement_id,
        )
        valid = false
        done = true
      }
    }
  }
  if !any {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected at least one column in " + what,
      "identifier",
      make_span(source, at, at),
      statement_id,
    )
    valid = false
  }
  valid
}

// CREATE VIEW [ IF NOT EXISTS ] [ db. ] view_name [ ( column_definition list ) ] [ AS ] query_stmt

///|
fn parse_create_view(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) {
    return false
  }
  let mut valid = expect_word(
    cursor, b"VIEW", state, source, statement_id, "expected VIEW after CREATE",
  )
  if consume_word(cursor, b"IF") {
    valid = expect_word(
        cursor, b"NOT", state, source, statement_id, "expected NOT after IF",
      ) &&
      valid
    valid = expect_word(
        cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF NOT",
      ) &&
      valid
  }
  valid = parse_qualified_name(cursor, state, source, statement_id, "view name") &&
    valid
  if raw_at(cursor) is Some(b"(") {
    advance(cursor)
    valid = parse_view_columns(cursor, state, source, statement_id) && valid
    valid = expect_symbol(
        cursor, b")", state, source, statement_id, "expected closing view column parenthesis",
      ) &&
      valid
  }
  ignore(consume_word(cursor, b"AS"))
  if !is_query_start(cursor) {
    let at = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state, "FATHOM-PARSE-002", "expected query after CREATE VIEW", "query", at,
      statement_id,
    )
    valid = false
  } else {
    valid = parse_query(cursor, state, source, statement_id) && valid
  }
  valid
}

// column_definition: <column_name> [ COMMENT '<comment>' ] [ , ... ]

///|
fn parse_view_columns(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  let mut any = false
  let mut done = false
  while !done {
    if raw_at(cursor) is Some(b")") {
      done = true
    } else {
      any = true
      if !is_identifier_candidate(cursor) {
        let at = match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        add_diagnostic(
          state, "FATHOM-PARSE-002", "expected view column name", "identifier", at,
          statement_id,
        )
        valid = false
      } else {
        advance(cursor)
      }
      if consume_word(cursor, b"COMMENT") {
        let is_stringish = match token_at(cursor) {
          Some(token) =>
            token.kind is @token.TokenKind::StringLiteral ||
            token.kind is @token.TokenKind::Quoted
          None => false
        }
        if !is_stringish {
          let at = match token_at(cursor) {
            Some(token) => token.span
            None =>
              make_span(source, source.byte_length(), source.byte_length())
          }
          add_diagnostic(
            state, "FATHOM-PARSE-002", "expected view column comment string after COMMENT",
            "string", at, statement_id,
          )
          valid = false
        } else {
          advance(cursor)
        }
      }
      if consume_symbol(cursor, b",") {
        if raw_at(cursor) is Some(b")") {
          done = true
        }
      } else {
        done = true
      }
    }
  }
  if !any {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected at least one view column",
      "view-column",
      make_span(source, at, at),
      statement_id,
    )
    valid = false
  }
  valid
}

// Per-family clause sync predicate for CREATE TABLE recovery (Pattern 2).

///|
fn is_create_table_clause_boundary(raw : Bytes) -> Bool {
  bytes_equal_ci(raw, b"ENGINE") ||
  bytes_equal_ci(raw, b"KEY") ||
  bytes_equal_ci(raw, b"ORDER") ||
  bytes_equal_ci(raw, b"BY") ||
  bytes_equal_ci(raw, b"COMMENT") ||
  bytes_equal_ci(raw, b"PARTITION") ||
  bytes_equal_ci(raw, b"AUTO") ||
  bytes_equal_ci(raw, b"DISTRIBUTED") ||
  bytes_equal_ci(raw, b"BUCKETS") ||
  bytes_equal_ci(raw, b"ROLLUP") ||
  bytes_equal_ci(raw, b"PROPERTIES") ||
  bytes_equal_ci(raw, b"AS") ||
  bytes_equal_ci(raw, b"LIKE") ||
  bytes_equal_ci(raw, b"DUPLICATE") ||
  bytes_equal_ci(raw, b"UNIQUE") ||
  bytes_equal_ci(raw, b"AGGREGATE") ||
  bytes_equal_ci(raw, b"IF") ||
  bytes_equal_ci(raw, b"NOT")
}

///|
fn is_key_type(cursor : Cursor) -> Bool {
  match raw_at(cursor) {
    Some(raw) =>
      bytes_equal_ci(raw, b"DUPLICATE") ||
      bytes_equal_ci(raw, b"UNIQUE") ||
      bytes_equal_ci(raw, b"AGGREGATE")
    None => false
  }
}

// Documented aggregate functions for AGGREGATE-model value columns.

///|
fn is_aggregate_type(cursor : Cursor) -> Bool {
  match raw_at(cursor) {
    Some(raw) =>
      bytes_equal_ci(raw, b"SUM") ||
      bytes_equal_ci(raw, b"MIN") ||
      bytes_equal_ci(raw, b"MAX") ||
      bytes_equal_ci(raw, b"REPLACE") ||
      bytes_equal_ci(raw, b"HLL_UNION") ||
      bytes_equal_ci(raw, b"BITMAP_UNION") ||
      bytes_equal_ci(raw, b"REPLACE_IF_NOT_NULL") ||
      bytes_equal_ci(raw, b"QUANTILE_UNION")
    None => false
  }
}

// Documented column-type family names (research section 6 type list); used to
// disambiguate an INDEX definition from a column literally named `index`.

///|
fn is_column_type_word(raw : Bytes) -> Bool {
  bytes_equal_ci(raw, b"BOOLEAN") ||
  bytes_equal_ci(raw, b"TINYINT") ||
  bytes_equal_ci(raw, b"SMALLINT") ||
  bytes_equal_ci(raw, b"INT") ||
  bytes_equal_ci(raw, b"BIGINT") ||
  bytes_equal_ci(raw, b"LARGEINT") ||
  bytes_equal_ci(raw, b"FLOAT") ||
  bytes_equal_ci(raw, b"DOUBLE") ||
  bytes_equal_ci(raw, b"DECIMAL") ||
  bytes_equal_ci(raw, b"DATE") ||
  bytes_equal_ci(raw, b"TIME") ||
  bytes_equal_ci(raw, b"DATETIME") ||
  bytes_equal_ci(raw, b"TIMESTAMPTZ") ||
  bytes_equal_ci(raw, b"CHAR") ||
  bytes_equal_ci(raw, b"VARCHAR") ||
  bytes_equal_ci(raw, b"STRING") ||
  bytes_equal_ci(raw, b"VARBINARY") ||
  bytes_equal_ci(raw, b"ARRAY") ||
  bytes_equal_ci(raw, b"MAP") ||
  bytes_equal_ci(raw, b"STRUCT") ||
  bytes_equal_ci(raw, b"VARIANT") ||
  bytes_equal_ci(raw, b"JSON") ||
  bytes_equal_ci(raw, b"BITMAP") ||
  bytes_equal_ci(raw, b"HLL") ||
  bytes_equal_ci(raw, b"QUANTILE_STATE") ||
  bytes_equal_ci(raw, b"AGG_STATE") ||
  bytes_equal_ci(raw, b"IPv4") ||
  bytes_equal_ci(raw, b"IPv6")
}

///|
fn is_word_bytes(raw : Bytes) -> Bool {
  if raw.length() == 0 {
    false
  } else {
    let first = raw[0].to_int()
    (first >= 65 && first <= 90) ||
    (first >= 97 && first <= 122) ||
    first == 95 ||
    first == 96
  }
}

// INDEX [ IF NOT EXISTS ] name ( cols ) ... inside the table body: true only
// when the word after INDEX is IF or a non-type name followed by '(' — so a
// column literally named `index` (index <type>) still parses as a column
// (Pitfall 2).

///|
fn is_index_definition_start(cursor : Cursor) -> Bool {
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, b"INDEX") =>
      match peek_raw(cursor, 1) {
        Some(next) if bytes_equal_ci(next, b"IF") => true
        Some(next) if is_word_bytes(next) && !is_column_type_word(next) =>
          peek_raw(cursor, 2) is Some(b"(")
        _ => false
      }
    _ => false
  }
}

///|
fn parse_create_table(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) {
    return false
  }
  let mut valid = expect_word(
    cursor, b"TABLE", state, source, statement_id, "expected TABLE after CREATE",
  )
  if consume_word(cursor, b"IF") {
    valid = expect_word(
        cursor, b"NOT", state, source, statement_id, "expected NOT after IF",
      ) &&
      valid
    valid = expect_word(
        cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF NOT",
      ) &&
      valid
  }
  valid = parse_qualified_name(
      cursor, state, source, statement_id, "table name",
    ) &&
    valid
  // LIKE variant: CREATE TABLE new LIKE existing [ WITH ROLLUP ( list ) ].
  if consume_word(cursor, b"LIKE") {
    valid = parse_qualified_name(
        cursor, state, source, statement_id, "existing table name",
      ) &&
      valid
    if raw_at(cursor) is Some(b"(") {
      // D-04 gate: the Flink LIKE feature list `(INCLUDING|EXCLUDING|
      // OVERWRITING <feature> ...)` (SqlTableLike, parserImpls.ftl:1714-1790)
      // is construct-level FATHOM-PARSE-009 under Doris (Doris LIKE has no
      // parenthesized feature list).
      let span = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_dialect_gate_diagnostic(state, span, statement_id)
      valid = false
      consume_gated_remainder(cursor, state, source, statement_id)
      return valid
    }
    if consume_word(cursor, b"WITH") {
      valid = expect_word(
          cursor, b"ROLLUP", state, source, statement_id, "expected ROLLUP after WITH in LIKE",
        ) &&
        valid
      valid = parse_identifier_option(
          cursor, state, source, statement_id, "LIKE ROLLUP",
        ) &&
        valid
    }
    return valid
  }
  let mut has_body = false
  if raw_at(cursor) is Some(b"(") {
    advance(cursor)
    has_body = true
    valid = parse_create_table_body(cursor, state, source, statement_id) &&
      valid
    let closed = expect_symbol(
      cursor, b")", state, source, statement_id, "expected closing table body parenthesis",
    )
    if !closed {
      recover_to_clause_boundary(
        cursor, state, source, statement_id, is_create_table_clause_boundary,
      )
    }
    valid = closed && valid
  }
  if consume_word(cursor, b"ENGINE") {
    valid = expect_symbol(
        cursor, b"=", state, source, statement_id, "expected = after ENGINE",
      ) &&
      valid
    if is_identifier_candidate(cursor) {
      advance(cursor)
    } else {
      let at = match token_at(cursor) {
        Some(token) => token.span.start_byte
        None => source.byte_length()
      }
      add_diagnostic(
        state,
        "FATHOM-PARSE-002",
        "expected engine type after ENGINE =",
        "identifier",
        make_span(source, at, at),
        statement_id,
      )
      valid = false
    }
  }
  if is_key_type(cursor) {
    advance(cursor)
    valid = expect_word(
        cursor, b"KEY", state, source, statement_id, "expected KEY after key type",
      ) &&
      valid
    valid = parse_identifier_option(cursor, state, source, statement_id, "KEY") &&
      valid
    let order_token = token_at(cursor)
    if consume_word(cursor, b"ORDER") {
      let order_span = match order_token {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      let feature = @dialect.DorisFeature::OrderByClause
      if !feature_allowed(state, feature) {
        add_feature_diagnostic(state, feature, order_span, statement_id)
        valid = false
      }
      valid = expect_word(
          cursor, b"BY", state, source, statement_id, "expected BY after ORDER",
        ) &&
        valid
      valid = parse_identifier_option(
          cursor, state, source, statement_id, "ORDER BY",
        ) &&
        valid
    }
  }
  if consume_word(cursor, b"COMMENT") {
    let is_stringish = match token_at(cursor) {
      Some(token) =>
        token.kind is @token.TokenKind::StringLiteral ||
        token.kind is @token.TokenKind::Quoted
      None => false
    }
    if !is_stringish {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected table comment string after COMMENT",
        "string", at, statement_id,
      )
      valid = false
    } else {
      advance(cursor)
    }
  }
  if raw_at(cursor) is Some(raw) &&
    (bytes_equal_ci(raw, b"PARTITIONED") || bytes_equal_ci(raw, b"WITH")) {
    // D-04 bidirectional negative gate (T-11-16, §9 matrix): the Flink-only
    // `PARTITIONED BY (cols)` and `WITH (connector options)` table-level
    // clauses are construct-level FATHOM-PARSE-009 under Doris (Doris uses
    // `PARTITION BY RANGE/LIST (...)` and `PROPERTIES (...)`).
    let span = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_dialect_gate_diagnostic(state, span, statement_id)
    valid = false
    consume_gated_remainder(cursor, state, source, statement_id)
  } else if raw_at(cursor) is Some(raw) &&
    (bytes_equal_ci(raw, b"AUTO") || bytes_equal_ci(raw, b"PARTITION")) {
    valid = parse_partitions_definition(cursor, state, source, statement_id) &&
      valid
  }
  if consume_word(cursor, b"DISTRIBUTED") {
    valid = parse_distribution_clause(cursor, state, source, statement_id) &&
      valid
  }
  if consume_word(cursor, b"ROLLUP") {
    valid = parse_rollup_definition(cursor, state, source, statement_id) &&
      valid
  }
  if consume_word(cursor, b"PROPERTIES") {
    valid = parse_properties_clause(
        cursor, state, source, statement_id, "PROPERTIES",
      ) &&
      valid
  }
  // CTAS: optional AS marker followed by a query body.
  if consume_word(cursor, b"AS") {
    if !is_query_start(cursor) {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected query after AS in CREATE TABLE", "query",
        at, statement_id,
      )
      valid = false
    } else {
      valid = parse_query(cursor, state, source, statement_id) && valid
    }
  } else if is_query_start(cursor) {
    valid = parse_query(cursor, state, source, statement_id) && valid
  } else if !has_body {
    let at = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state, "FATHOM-PARSE-002", "expected table body, LIKE, or query after CREATE TABLE",
      "table-body", at, statement_id,
    )
    valid = false
  }
  valid
}

// Comma-separated column definitions followed by optional INDEX definitions,

///|
/// True when the cursor sits on a Flink-only column-body form under Doris —
/// WATERMARK, PRIMARY KEY, or a UNIQUE constraint — which must be a
/// construct-level FATHOM-PARSE-009 gate (T-11-16, §9 matrix). A Doris column
/// legitimately named `unique`/`primary` (not followed by KEY/`(`) is not
/// gated.
fn is_flink_only_column_start(cursor : Cursor) -> Bool {
  match raw_at(cursor) {
    // CR-03/MJ-03: WATERMARK is a valid Doris column name (not a Doris
    // reserved word). The Flink-only gate fires only for the sub-clause form
    // WATERMARK FOR ... — a bare `watermark` column parses as an identifier.
    Some(raw) if bytes_equal_ci(raw, b"WATERMARK") =>
      peek_raw(cursor, 1) is Some(next) && bytes_equal_ci(next, b"FOR")
    Some(raw) if bytes_equal_ci(raw, b"PRIMARY") =>
      peek_raw(cursor, 1) is Some(next) && bytes_equal_ci(next, b"KEY")
    Some(raw) if bytes_equal_ci(raw, b"UNIQUE") =>
      match peek_raw(cursor, 1) {
        Some(next) => bytes_equal_ci(next, b"KEY") || next == b"("
        None => false
      }
    _ => false
  }
}

// inside the table body parenthesis (columns first, then indexes).

///|
fn parse_create_table_body(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  let mut any = false
  let mut done = false
  while !done {
    if raw_at(cursor) is Some(b")") {
      done = true
    } else {
      any = true
      if is_index_definition_start(cursor) {
        valid = parse_create_table_index(cursor, state, source, statement_id) &&
          valid
      } else if is_flink_only_column_start(cursor) {
        // D-04 bidirectional negative gate (T-11-16, §9 matrix): Flink-only
        // column-body forms — WATERMARK, PRIMARY KEY NOT ENFORCED, UNIQUE
        // constraint — are construct-level FATHOM-PARSE-009 under Doris. The
        // remainder of the Flink element is consumed losslessly so the gate
        // is the primary diagnostic.
        let span = match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        add_dialect_gate_diagnostic(state, span, statement_id)
        valid = false
        consume_body_element_remainder(cursor, state, source, statement_id)
      } else {
        valid = parse_column_definition(cursor, state, source, statement_id) &&
          valid
      }
      if consume_symbol(cursor, b",") {
        if raw_at(cursor) is Some(b")") {
          let at = match token_at(cursor) {
            Some(token) => token.span.start_byte
            None => source.byte_length()
          }
          add_diagnostic(
            state,
            "FATHOM-PARSE-002",
            "expected column or index after comma",
            "table-body",
            make_span(source, at, at),
            statement_id,
          )
          valid = false
          done = true
        }
      } else {
        done = true
      }
    }
  }
  if !any {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected at least one column definition",
      "table-body",
      make_span(source, at, at),
      statement_id,
    )
    valid = false
  }
  valid
}

///|
fn parse_column_definition(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  if !is_identifier_candidate(cursor) {
    let at = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state, "FATHOM-PARSE-002", "expected column name", "identifier", at, statement_id,
    )
    return false
  }
  advance(cursor)
  // D-04 bidirectional negative gate (T-11-16, §9 matrix): a Flink computed
  // column `name AS expr` (no type, AS without a following `(`) is
  // construct-level FATHOM-PARSE-009 under Doris. Doris generated columns use
  // `name type AS (expr)` / `GENERATED ALWAYS AS (expr)` (parenthesized), so
  // `AS (` is not gated and the Doris path stays byte-identical.
  if raw_at(cursor) is Some(raw) &&
    bytes_equal_ci(raw, b"AS") &&
    peek_raw(cursor, 1) is Some(next) &&
    !(next == b"(") {
    let span = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_dialect_gate_diagnostic(state, span, statement_id)
    valid = false
    consume_body_element_remainder(cursor, state, source, statement_id)
    return valid
  }
  valid = parse_column_type(cursor, state, source, statement_id) && valid
  // D-04 gate: a Flink metadata column `name type METADATA [FROM 'alias']
  // [VIRTUAL]` is construct-level FATHOM-PARSE-009 under Doris.
  if raw_at(cursor) is Some(raw) && bytes_equal_ci(raw, b"METADATA") {
    let span = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_dialect_gate_diagnostic(state, span, statement_id)
    valid = false
    consume_body_element_remainder(cursor, state, source, statement_id)
    return valid
  }
  if consume_word(cursor, b"KEY") {
    ()
  }
  if is_aggregate_type(cursor) {
    advance(cursor)
  }
  if consume_word(cursor, b"GENERATED") {
    valid = expect_word(
        cursor, b"ALWAYS", state, source, statement_id, "expected ALWAYS after GENERATED",
      ) &&
      valid
    valid = expect_word(
        cursor, b"AS", state, source, statement_id, "expected AS after GENERATED ALWAYS",
      ) &&
      valid
    valid = parse_parenthesized_expression(
        cursor, state, source, statement_id, "generated column",
      ) &&
      valid
  } else if consume_word(cursor, b"AS") {
    valid = parse_parenthesized_expression(
        cursor, state, source, statement_id, "generated column",
      ) &&
      valid
  }
  if consume_word(cursor, b"NOT") {
    valid = expect_word(
        cursor, b"NULL", state, source, statement_id, "expected NULL after NOT",
      ) &&
      valid
  } else if consume_word(cursor, b"NULL") {
    ()
  }
  if consume_word(cursor, b"AUTO_INCREMENT") {
    if !consume_symbol(cursor, b"(") {
      valid = expect_symbol(
          cursor, b"(", state, source, statement_id, "expected AUTO_INCREMENT parenthesis",
        ) &&
        valid
    } else {
      let is_start = match token_at(cursor) {
        Some(token) =>
          token.kind is @token.TokenKind::Number ||
          is_identifier_candidate(cursor)
        None => false
      }
      if !is_start {
        let at = match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        add_diagnostic(
          state, "FATHOM-PARSE-002", "expected AUTO_INCREMENT start value", "number",
          at, statement_id,
        )
        valid = false
      } else {
        advance(cursor)
      }
      valid = expect_symbol(
          cursor, b")", state, source, statement_id, "expected closing AUTO_INCREMENT parenthesis",
        ) &&
        valid
    }
  }
  if consume_word(cursor, b"DEFAULT") {
    valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
  }
  if consume_word(cursor, b"ON") {
    valid = expect_word(
        cursor, b"UPDATE", state, source, statement_id, "expected UPDATE after ON",
      ) &&
      valid
    valid = expect_word(
        cursor, b"CURRENT_TIMESTAMP", state, source, statement_id, "expected CURRENT_TIMESTAMP after ON UPDATE",
      ) &&
      valid
    if consume_symbol(cursor, b"(") {
      let is_precision = match token_at(cursor) {
        Some(token) => token.kind is @token.TokenKind::Number
        None => false
      }
      if !is_precision {
        let at = match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        add_diagnostic(
          state, "FATHOM-PARSE-002", "expected precision after ON UPDATE CURRENT_TIMESTAMP (",
          "number", at, statement_id,
        )
        valid = false
      } else {
        advance(cursor)
      }
      valid = expect_symbol(
          cursor, b")", state, source, statement_id, "expected closing precision parenthesis",
        ) &&
        valid
    }
  }
  if consume_word(cursor, b"COMMENT") {
    let is_stringish = match token_at(cursor) {
      Some(token) =>
        token.kind is @token.TokenKind::StringLiteral ||
        token.kind is @token.TokenKind::Quoted
      None => false
    }
    if !is_stringish {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected column comment string after COMMENT",
        "string", at, statement_id,
      )
      valid = false
    } else {
      advance(cursor)
    }
  }
  valid
}

// col_type := identifier [ ( params ) ] [ < params > ]; params items are
// numbers, strings, or identifiers (with optional nested params/generics and
// an optional STRUCT-style field type).

///|
fn parse_column_type(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !is_identifier_candidate(cursor) {
    let at = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state, "FATHOM-PARSE-002", "expected column type", "type", at, statement_id,
    )
    return false
  }
  // Capture the enclosing type name before advancing so < ... > params can
  // decide whether STRUCT-style field types are allowed (WR-02).
  let type_name = raw_at(cursor)
  advance(cursor)
  let struct_style = match type_name {
    Some(raw) => bytes_equal_ci(raw, b"STRUCT")
    None => false
  }
  let mut valid = true
  if consume_symbol(cursor, b"(") {
    valid = parse_type_params(cursor, state, source, statement_id, 0, false) &&
      valid
    valid = expect_symbol(
        cursor, b")", state, source, statement_id, "expected closing type parameter parenthesis",
      ) &&
      valid
  }
  if raw_at(cursor) is Some(b"<") {
    advance(cursor)
    valid = parse_type_params(
        cursor, state, source, statement_id, 0, struct_style,
      ) &&
      valid
    valid = expect_symbol(
        cursor, b">", state, source, statement_id, "expected closing type generic bracket",
      ) &&
      valid
  }
  valid
}

///|
fn parse_type_params(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  depth : Int,
  struct_style : Bool,
) -> Bool {
  // CR-01: generic < > brackets never register in parenthesis_depth, so
  // nested type-param recursion is bounded here with an explicit depth
  // counter mirroring parse_expression_context. Without this guard an
  // adversarial ARRAY<ARRAY<...>> chain (well within max_bytes/max_tokens)
  // overflows the native stack instead of failing with a resource
  // diagnostic.
  if depth > state.limits.max_recursion_depth {
    let current_span = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    resource_diagnostic(state, current_span, statement_id)
    return false
  }
  let mut valid = true
  let mut any = false
  let mut done = false
  while !done {
    match token_at(cursor) {
      None => done = true
      Some(token) if token.kind is @token.TokenKind::Number ||
        token.kind is @token.TokenKind::StringLiteral => {
        any = true
        advance(cursor)
      }
      Some(_) if is_identifier_candidate(cursor) => {
        any = true
        // Capture the just-consumed name so a nested < ... > can decide
        // whether STRUCT-style field types are allowed inside it (WR-02).
        let nested_name = raw_at(cursor)
        advance(cursor)
        if consume_symbol(cursor, b"(") {
          valid = parse_type_params(
              cursor,
              state,
              source,
              statement_id,
              depth + 1,
              false,
            ) &&
            valid
          valid = expect_symbol(
              cursor, b")", state, source, statement_id, "expected closing nested type parenthesis",
            ) &&
            valid
        }
        if raw_at(cursor) is Some(b"<") {
          advance(cursor)
          let nested_struct = match nested_name {
            Some(raw) => bytes_equal_ci(raw, b"STRUCT")
            None => false
          }
          valid = parse_type_params(
              cursor,
              state,
              source,
              statement_id,
              depth + 1,
              nested_struct,
            ) &&
            valid
          valid = expect_symbol(
              cursor, b">", state, source, statement_id, "expected closing nested type generic bracket",
            ) &&
            valid
        }
        // STRUCT-style field type: a name followed by an optional type word
        // is consumed only inside STRUCT params (WR-02); anywhere else a
        // second identifier is trailing garbage and must not be silently
        // accepted as a valid type.
        if struct_style &&
          is_identifier_candidate(cursor) &&
          !(raw_at(cursor) is Some(b"(")) &&
          !(raw_at(cursor) is Some(b"<")) {
          advance(cursor)
        }
      }
      Some(_) => {
        let span = match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        add_diagnostic(
          state, "FATHOM-PARSE-002", "expected type parameter", "type-parameter",
          span, statement_id,
        )
        valid = false
        done = true
      }
    }
    if !done {
      if consume_symbol(cursor, b",") {
        if raw_at(cursor) is Some(b")") || raw_at(cursor) is Some(b">") {
          done = true
        }
      } else {
        done = true
      }
    }
  }
  if !any {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected type parameter",
      "type-parameter",
      make_span(source, at, at),
      statement_id,
    )
    valid = false
  }
  valid
}

///|
fn parse_parenthesized_expression(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  what : String,
) -> Bool {
  if !consume_symbol(cursor, b"(") {
    let at = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected ( for " + what,
      "symbol",
      at,
      statement_id,
    )
    return false
  }
  let mut valid = parse_expression(cursor, 1, 1, state, source, statement_id)
  valid = expect_symbol(
      cursor,
      b")",
      state,
      source,
      statement_id,
      "expected closing " + what + " parenthesis",
    ) &&
    valid
  valid
}

// INDEX [ IF NOT EXISTS ] name ( col list ) [ USING type ] [ PROPERTIES ( ... ) ] [ COMMENT '...' ]

///|
fn parse_create_table_index(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = expect_word(
    cursor, b"INDEX", state, source, statement_id, "expected INDEX definition",
  )
  if consume_word(cursor, b"IF") {
    valid = expect_word(
        cursor, b"NOT", state, source, statement_id, "expected NOT after IF",
      ) &&
      valid
    valid = expect_word(
        cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF NOT",
      ) &&
      valid
  }
  if !is_identifier_candidate(cursor) {
    let at = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state, "FATHOM-PARSE-002", "expected index name", "identifier", at, statement_id,
    )
    valid = false
  } else {
    advance(cursor)
  }
  valid = parse_identifier_option(cursor, state, source, statement_id, "INDEX") &&
    valid
  if consume_word(cursor, b"USING") {
    if is_identifier_candidate(cursor) {
      advance(cursor)
    } else {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected index type after USING", "identifier",
        at, statement_id,
      )
      valid = false
    }
  }
  if consume_word(cursor, b"PROPERTIES") {
    valid = parse_properties_clause(
        cursor, state, source, statement_id, "INDEX PROPERTIES",
      ) &&
      valid
  }
  if consume_word(cursor, b"COMMENT") {
    let is_stringish = match token_at(cursor) {
      Some(token) =>
        token.kind is @token.TokenKind::StringLiteral ||
        token.kind is @token.TokenKind::Quoted
      None => false
    }
    if !is_stringish {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected index comment string after COMMENT",
        "string", at, statement_id,
      )
      valid = false
    } else {
      advance(cursor)
    }
  }
  valid
}

///|
fn parse_partitions_definition(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  let auto_token = token_at(cursor)
  if consume_word(cursor, b"AUTO") {
    let auto_span = match auto_token {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    let feature = @dialect.DorisFeature::AutoPartitionBy
    if !feature_allowed(state, feature) {
      add_feature_diagnostic(state, feature, auto_span, statement_id)
      valid = false
    }
    valid = expect_word(
        cursor, b"PARTITION", state, source, statement_id, "expected PARTITION after AUTO",
      ) &&
      valid
    valid = expect_word(
        cursor, b"BY", state, source, statement_id, "expected BY after AUTO PARTITION",
      ) &&
      valid
    if consume_word(cursor, b"RANGE") {
      valid = parse_parenthesized_expression(
          cursor, state, source, statement_id, "AUTO PARTITION BY RANGE",
        ) &&
        valid
    } else if consume_word(cursor, b"LIST") {
      valid = parse_identifier_option(
          cursor, state, source, statement_id, "AUTO PARTITION BY LIST",
        ) &&
        valid
    } else {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected RANGE or LIST after AUTO PARTITION BY",
        "partition-type", at, statement_id,
      )
      valid = false
    }
    valid = parse_origin_partitions(cursor, state, source, statement_id) &&
      valid
  } else if consume_word(cursor, b"PARTITION") {
    valid = expect_word(
        cursor, b"BY", state, source, statement_id, "expected BY after PARTITION",
      ) &&
      valid
    if consume_word(cursor, b"RANGE") {
      ()
    } else if consume_word(cursor, b"LIST") {
      ()
    } else {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected RANGE or LIST after PARTITION BY", "partition-type",
        at, statement_id,
      )
      valid = false
    }
    valid = parse_identifier_option(
        cursor, state, source, statement_id, "PARTITION BY",
      ) &&
      valid
    valid = parse_origin_partitions(cursor, state, source, statement_id) &&
      valid
  } else {
    valid = false
  }
  valid
}

// ( <one_partition_definition> [ , ... ] ) — the list may be empty.

///|
fn parse_origin_partitions(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = expect_symbol(
    cursor, b"(", state, source, statement_id, "expected ( for partition definitions",
  )
  let mut done = false
  while !done {
    if raw_at(cursor) is Some(b")") {
      done = true
    } else {
      valid = parse_one_partition_definition(
          cursor, state, source, statement_id,
        ) &&
        valid
      if consume_symbol(cursor, b",") {
        if raw_at(cursor) is Some(b")") {
          done = true
        }
      } else {
        done = true
      }
    }
  }
  valid = expect_symbol(
      cursor, b")", state, source, statement_id, "expected closing partition definitions parenthesis",
    ) &&
    valid
  valid
}

///|
fn parse_one_partition_definition(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  if consume_word(cursor, b"PARTITION") {
    if consume_word(cursor, b"IF") {
      valid = expect_word(
          cursor, b"NOT", state, source, statement_id, "expected NOT after IF",
        ) &&
        valid
      valid = expect_word(
          cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF NOT",
        ) &&
        valid
    }
    if !is_identifier_candidate(cursor) {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected partition name", "identifier", at, statement_id,
      )
      valid = false
    } else {
      advance(cursor)
    }
    if consume_word(cursor, b"VALUES") {
      if consume_word(cursor, b"LESS") {
        valid = expect_word(
            cursor, b"THAN", state, source, statement_id, "expected THAN after VALUES LESS",
          ) &&
          valid
        if !consume_symbol(cursor, b"(") {
          valid = expect_symbol(
              cursor, b"(", state, source, statement_id, "expected VALUES LESS THAN parenthesis",
            ) &&
            valid
        } else {
          valid = parse_expression_list(
              cursor, state, source, statement_id, true,
            ) &&
            valid
          valid = expect_symbol(
              cursor, b")", state, source, statement_id, "expected closing VALUES LESS THAN parenthesis",
            ) &&
            valid
        }
      } else if consume_word(cursor, b"IN") {
        if !consume_symbol(cursor, b"(") {
          valid = expect_symbol(
              cursor, b"(", state, source, statement_id, "expected VALUES IN parenthesis",
            ) &&
            valid
        } else {
          valid = parse_expression_list(
              cursor, state, source, statement_id, true,
            ) &&
            valid
          valid = expect_symbol(
              cursor, b")", state, source, statement_id, "expected closing VALUES IN parenthesis",
            ) &&
            valid
        }
      } else if consume_symbol(cursor, b"{") {
        if consume_symbol(cursor, b"(") {
          valid = parse_expression_list(
              cursor, state, source, statement_id, true,
            ) &&
            valid
          valid = expect_symbol(
              cursor, b")", state, source, statement_id, "expected closing VALUES IN parenthesis",
            ) &&
            valid
        } else {
          valid = parse_expression(cursor, 1, 1, state, source, statement_id) &&
            valid
        }
        valid = expect_symbol(
            cursor, b"}", state, source, statement_id, "expected closing VALUES IN brace",
          ) &&
          valid
      } else if consume_symbol(cursor, b"[") {
        // VALUES [ <lower>, <upper> ) — half-open range.
        valid = parse_expression(cursor, 1, 1, state, source, statement_id) &&
          valid
        valid = expect_symbol(
            cursor, b",", state, source, statement_id, "expected comma in VALUES range",
          ) &&
          valid
        valid = parse_expression(cursor, 1, 1, state, source, statement_id) &&
          valid
        valid = expect_symbol(
            cursor, b")", state, source, statement_id, "expected closing VALUES range parenthesis",
          ) &&
          valid
      } else {
        let at = match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        add_diagnostic(
          state, "FATHOM-PARSE-002", "expected LESS THAN, IN, or range after VALUES",
          "partition-values", at, statement_id,
        )
        valid = false
      }
    } else {
      let at = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      add_diagnostic(
        state, "FATHOM-PARSE-002", "expected VALUES after partition name", "partition-values",
        at, statement_id,
      )
      valid = false
    }
  } else if consume_word(cursor, b"FROM") {
    // FROM <lower> TO <upper> INTERVAL <n> [ <datetime_unit> ]
    valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
    valid = expect_word(
        cursor, b"TO", state, source, statement_id, "expected TO in partition range",
      ) &&
      valid
    valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
    valid = expect_word(
        cursor, b"INTERVAL", state, source, statement_id, "expected INTERVAL in partition range",
      ) &&
      valid
    valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
    if is_identifier_candidate(cursor) {
      advance(cursor)
    }
  } else {
    let at = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state, "FATHOM-PARSE-002", "expected PARTITION or FROM in partition definition",
      "partition", at, statement_id,
    )
    valid = false
  }
  valid
}

// DISTRIBUTED BY { HASH ( cols ) | RANDOM } [ BUCKETS { count | AUTO } ]

///|
fn parse_distribution_clause(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = expect_word(
    cursor, b"BY", state, source, statement_id, "expected BY after DISTRIBUTED",
  )
  if consume_word(cursor, b"HASH") {
    valid = parse_identifier_option(cursor, state, source, statement_id, "HASH") &&
      valid
  } else if consume_word(cursor, b"RANDOM") {
    ()
  } else {
    let at = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_diagnostic(
      state, "FATHOM-PARSE-002", "expected HASH or RANDOM after DISTRIBUTED BY",
      "distribution", at, statement_id,
    )
    valid = false
  }
  // D-04 bidirectional negative gate (T-11-16, §9 matrix): the Flink-only
  // `DISTRIBUTED ... INTO n BUCKETS` form (SqlDistribution, parserImpls.ftl:
  // 1556-1570) is construct-level FATHOM-PARSE-009 under Doris — the Doris
  // distribution form is `DISTRIBUTED BY ... BUCKETS n|AUTO`.
  if raw_at(cursor) is Some(raw) && bytes_equal_ci(raw, b"INTO") {
    let span = match token_at(cursor) {
      Some(token) => token.span
      None => make_span(source, source.byte_length(), source.byte_length())
    }
    add_dialect_gate_diagnostic(state, span, statement_id)
    valid = false
    consume_gated_remainder(cursor, state, source, statement_id)
  } else if consume_word(cursor, b"BUCKETS") {
    let auto_token = token_at(cursor)
    match auto_token {
      Some(token) if token.kind is @token.TokenKind::Number => advance(cursor)
      Some(token) => {
        let is_auto = match raw_at(cursor) {
          Some(raw) => bytes_equal_ci(raw, b"AUTO")
          None => false
        }
        if is_auto {
          let feature = @dialect.DorisFeature::BucketsAuto
          if !feature_allowed(state, feature) {
            add_feature_diagnostic(state, feature, token.span, statement_id)
            valid = false
          }
          advance(cursor)
        } else {
          let at = match token_at(cursor) {
            Some(t) => t.span
            None =>
              make_span(source, source.byte_length(), source.byte_length())
          }
          add_diagnostic(
            state, "FATHOM-PARSE-002", "expected bucket count or AUTO after BUCKETS",
            "bucket-count", at, statement_id,
          )
          valid = false
        }
      }
      None => {
        let at = match token_at(cursor) {
          Some(t) => t.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        add_diagnostic(
          state, "FATHOM-PARSE-002", "expected bucket count or AUTO after BUCKETS",
          "bucket-count", at, statement_id,
        )
        valid = false
      }
    }
  }
  valid
}

// ROLLUP ( name ( cols ) [ DUPLICATE KEY ( cols ) ] [ , ... ] )

///|
fn parse_rollup_definition(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = expect_symbol(
    cursor, b"(", state, source, statement_id, "expected ( after ROLLUP",
  )
  let mut done = false
  while !done {
    if raw_at(cursor) is Some(b")") {
      done = true
    } else {
      if !is_identifier_candidate(cursor) {
        let at = match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        add_diagnostic(
          state, "FATHOM-PARSE-002", "expected rollup name", "identifier", at, statement_id,
        )
        valid = false
      } else {
        advance(cursor)
      }
      valid = parse_identifier_option(
          cursor, state, source, statement_id, "ROLLUP",
        ) &&
        valid
      if consume_word(cursor, b"DUPLICATE") {
        valid = expect_word(
            cursor, b"KEY", state, source, statement_id, "expected KEY after DUPLICATE",
          ) &&
          valid
        valid = parse_identifier_option(
            cursor, state, source, statement_id, "DUPLICATE KEY",
          ) &&
          valid
      }
      if consume_symbol(cursor, b",") {
        if raw_at(cursor) is Some(b")") {
          done = true
        }
      } else {
        done = true
      }
    }
  }
  valid = expect_symbol(
      cursor, b")", state, source, statement_id, "expected closing ROLLUP parenthesis",
    ) &&
    valid
  valid
}

// PROPERTIES ( key = value [ , ... ] ) — keys/values may be strings, quoted
// names, numbers, or identifiers (docs examples use quoted strings).

///|
fn parse_properties_clause(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  what : String,
) -> Bool {
  let mut valid = expect_symbol(
    cursor,
    b"(",
    state,
    source,
    statement_id,
    "expected ( after " + what,
  )
  let mut any = false
  let mut done = false
  while !done {
    let is_value = match token_at(cursor) {
      Some(token) =>
        token.kind is @token.TokenKind::StringLiteral ||
        token.kind is @token.TokenKind::Number ||
        is_identifier_candidate(cursor)
      None => false
    }
    if !is_value {
      let span = match token_at(cursor) {
        Some(token) => token.span
        None => make_span(source, source.byte_length(), source.byte_length())
      }
      if raw_at(cursor) is Some(b")") {
        done = true
      } else {
        add_diagnostic(
          state,
          "FATHOM-PARSE-002",
          "expected property key in " + what,
          "property-key",
          span,
          statement_id,
        )
        valid = false
        done = true
      }
    } else {
      any = true
      advance(cursor)
      valid = expect_symbol(
          cursor,
          b"=",
          state,
          source,
          statement_id,
          "expected = in " + what + " pair",
        ) &&
        valid
      let is_value2 = match token_at(cursor) {
        Some(token) =>
          token.kind is @token.TokenKind::StringLiteral ||
          token.kind is @token.TokenKind::Number ||
          is_identifier_candidate(cursor)
        None => false
      }
      if !is_value2 {
        let at = match token_at(cursor) {
          Some(token) => token.span
          None => make_span(source, source.byte_length(), source.byte_length())
        }
        add_diagnostic(
          state,
          "FATHOM-PARSE-002",
          "expected property value in " + what,
          "property-value",
          at,
          statement_id,
        )
        valid = false
      } else {
        advance(cursor)
      }
      if consume_symbol(cursor, b",") {
        if raw_at(cursor) is Some(b")") {
          done = true
        }
      } else {
        done = true
      }
    }
  }
  if !any {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected at least one property in " + what,
      "property",
      make_span(source, at, at),
      statement_id,
    )
    valid = false
  }
  valid = expect_symbol(
      cursor,
      b")",
      state,
      source,
      statement_id,
      "expected closing " + what + " parenthesis",
    ) &&
    valid
  valid
}

// Runs the shared trailing-token recovery loop and builds the family statement
// node with the Statement wrapper, preserving Phase 1 semantics exactly.

///|
fn finish_statement(
  stream : @token.TokenStream,
  cursor : Cursor,
  start_index : Int,
  end_index : Int,
  span : @source.Span,
  parsed : Bool,
  state : RecoveryState,
  statement_id : UInt,
  kind : @syntax.SyntaxKind,
  trailing_message : String,
) -> @syntax.SyntaxNode {
  let mut trailing = false
  while cursor.position < cursor.indices.length() {
    match raw_at(cursor) {
      Some(raw) if raw == b";" => advance(cursor)
      Some(_) => {
        let before = cursor.position
        trailing = true
        recover_expression(cursor, state, stream.source, statement_id)
        if cursor.position == before {
          advance(cursor)
        }
      }
      None => cursor.position = cursor.indices.length()
    }
  }
  if trailing {
    add_diagnostic(
      state, "FATHOM-PARSE-001", trailing_message, "statement", span, statement_id,
    )
  }
  let children = segment_children_for_events(
    stream,
    start_index,
    end_index,
    state.feature_events,
  )
  if !parsed || trailing {
    children.push(
      @syntax.SyntaxElement::ChildNode(
        require_node(
          @syntax.SyntaxNode::missing(
            span.end_byte,
            stream.source.byte_length(),
          ),
        ),
      ),
    )
  }
  let statement_node = require_node(
    @syntax.SyntaxNode::new(kind, span, children),
  )
  require_node(
    @syntax.SyntaxNode::new(@syntax.SyntaxKind::Statement, span, [
      @syntax.SyntaxElement::ChildNode(statement_node),
    ]),
  )
}

// D-12: statements outside the supported profile become explicit Error nodes
// with the stable FATHOM-PARSE-007 diagnostic; never silent acceptance.

///|
fn unsupported_statement(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
  span : @source.Span,
  state : RecoveryState,
  statement_id : UInt,
) -> @syntax.SyntaxNode {
  add_diagnostic(
    state, "FATHOM-PARSE-007", "unsupported statement in the selected profile", "statement",
    span, statement_id,
  )
  let children = segment_children_for_profile(stream, start_index, end_index)
  let error = require_node(
    @syntax.SyntaxNode::new(@syntax.SyntaxKind::Error, span, children),
  )
  require_node(
    @syntax.SyntaxNode::new(@syntax.SyntaxKind::Statement, span, [
      @syntax.SyntaxElement::ChildNode(error),
    ]),
  )
}

///|
fn significant_indices(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
) -> Array[Int] {
  let indices : Array[Int] = []
  let mut index = start_index
  while index < end_index {
    match stream.at(index) {
      Some(token) if token.is_trivia() || token.kind is @token.TokenKind::Bom =>
        ()
      Some(_) => indices.push(index)
      None => ()
    }
    index = index + 1
  }
  indices
}

///|
fn has_statement_content(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
) -> Bool {
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

///|
fn leaf_for_token(token : @token.Token) -> @syntax.SyntaxElement {
  let kind = match token.kind {
    @token.TokenKind::Whitespace
    | @token.TokenKind::Newline
    | @token.TokenKind::Comment
    | @token.TokenKind::Bom => @syntax.LeafKind::SourceTrivia
    @token.TokenKind::Error => @syntax.LeafKind::SourceError
    @token.TokenKind::Unknown => @syntax.LeafKind::SourceSkipped
    _ => @syntax.LeafKind::SourceToken
  }
  @syntax.SyntaxElement::Leaf(@syntax.SyntaxLeaf::new(kind, token.span))
}

///|
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

///|
fn segment_statement_id_for_span(
  stream : @token.TokenStream,
  span : @source.Span,
) -> UInt {
  let mut statement_id : UInt = 0U
  let mut segment_start = 0
  for index in 0..<stream.length() {
    match stream.at(index) {
      Some(token) if token.span.start_byte >= span.start_byte => break
      Some(token) =>
        match stream.source.slice(token.span) {
          Some(raw) if raw == b";" => {
            let segment_end = index + 1
            if has_statement_content(stream, segment_start, segment_end) {
              statement_id = statement_id + 1U
            }
            segment_start = segment_end
          }
          _ => ()
        }
      None => ()
    }
  }
  statement_id
}

///|
fn segment_children_for_profile(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
) -> Array[@syntax.SyntaxElement] {
  segment_children(stream, start_index, end_index)
}

///|
fn has_feature_event(events : Array[FeatureEvent], span : @source.Span) -> Bool {
  for event in events {
    if event.span.start_byte == span.start_byte &&
      event.span.end_byte == span.end_byte {
      return true
    }
  }
  false
}

///|
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
      Some(token) if has_feature_event(events, token.span) =>
        children.push(version_invalid_node(token))
      Some(token) => children.push(leaf_for_token(token))
      None => ()
    }
    index = index + 1
  }
  children
}

///|
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

///|
fn recover_expression(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Unit {
  let mut consumed = false
  let mut done = false
  while !done {
    match raw_at(cursor) {
      None => done = true
      Some(raw) if raw == b")" ||
        raw == b"," ||
        raw == b";" ||
        @dialect.is_clause_keyword(cursor.stream.context, raw) => done = true
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
  if !consumed && raw_at(cursor) is Some(_) {
    match raw_at(cursor) {
      Some(raw) if raw == b")" ||
        raw == b"," ||
        raw == b";" ||
        @dialect.is_clause_keyword(cursor.stream.context, raw) => ()
      _ => advance(cursor)
    }
  }
}

///|
/// Statement-level dialect router (DIALECT-03, Pitfall 2): the ONLY place in
/// parser/ that branches on dialect. Doris runs the frozen v1 grammar
/// byte-identically (baseline gate); Flink is an explicit not-implemented
/// rejection for any input — never a fallback to Doris.
fn parse_segment(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
  statement_id : UInt,
  state : RecoveryState,
  context : @dialect.DialectContext,
) -> @syntax.SyntaxNode {
  match context.dialect {
    @dialect.Dialect::Doris =>
      parse_doris_segment(
        stream, start_index, end_index, statement_id, state, context,
      )
    @dialect.Dialect::Flink =>
      parse_flink_segment(
        stream, start_index, end_index, statement_id, state, context,
      )
  }
}

///|
/// Doris statement grammar: the v1 parse_segment body verbatim (keyword-first

///|
/// Doris DROP second-word dispatch: TABLE, VIEW, INDEX. Falls back to
/// DropTable for unknown forms (D-02 coarse per-family kind).
fn doris_drop_form_kind(
  stream : @token.TokenStream,
  indices : Array[Int],
  start_index : Int,
) -> @syntax.SyntaxKind {
  match indices.get(start_index + 1) {
    Some(i) =>
      match stream.raw(i) {
        Some(raw) if bytes_equal_ci(raw, b"TABLE") =>
          @syntax.SyntaxKind::DropTable
        Some(raw) if bytes_equal_ci(raw, b"VIEW") =>
          @syntax.SyntaxKind::DropView
        Some(raw) if bytes_equal_ci(raw, b"INDEX") =>
          @syntax.SyntaxKind::DropIndex
        _ => @syntax.SyntaxKind::DropTable
      }
    None => @syntax.SyntaxKind::DropTable
  }
}

///|
/// Doris ALTER TABLE: consume ALTER TABLE [IF EXISTS] <name> and then one or
/// more comma-separated alter actions (ADD COLUMN, DROP COLUMN, RENAME,
/// MODIFY COLUMN, ADD INDEX, etc.). Each action is consumed token-by-token
/// through the end of the statement; the CST preserves the raw children for
/// round-trip. The parser validates only the structural prefix (ALTER TABLE
/// <identifier>); the action body is accepted as-is under editor recovery.

///|
/// Doris ALTER second-word dispatch: TABLE, VIEW, DATABASE. Falls back to
/// AlterTable for unknown forms (coarse per-family kind, D-02).
fn doris_alter_form_kind(
  stream : @token.TokenStream,
  indices : Array[Int],
  start_index : Int,
) -> @syntax.SyntaxKind {
  match indices.get(start_index + 1) {
    Some(i) =>
      match stream.raw(i) {
        Some(raw) if bytes_equal_ci(raw, b"VIEW") =>
          @syntax.SyntaxKind::AlterTable
        Some(raw) if bytes_equal_ci(raw, b"DATABASE") =>
          @syntax.SyntaxKind::AlterTable
        _ => @syntax.SyntaxKind::AlterTable
      }
    None => @syntax.SyntaxKind::AlterTable
  }
}

///|
/// Consume a qualified identifier: <name> or <db>.<name>
fn consume_qualified_name(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if is_identifier_candidate(cursor) {
    advance(cursor)
    if consume_symbol(cursor, b".") && is_identifier_candidate(cursor) {
      advance(cursor)
    }
    true
  } else {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected identifier",
      "identifier",
      make_span(source, at, at),
      statement_id,
    )
    false
  }
}

///|
/// Consume a parenthesized group `(...)` — advance past matching parens.
fn consume_paren_group(cursor : Cursor) -> Unit {
  if consume_symbol(cursor, b"(") {
    let mut depth = 1
    while depth > 0 {
      match token_at(cursor) {
        Some(_) => {
          if raw_at(cursor) is Some(b"(") {
            depth = depth + 1
          }
          if raw_at(cursor) is Some(b")") {
            depth = depth - 1
          }
          if depth > 0 || !(raw_at(cursor) is Some(b")")) {
            advance(cursor)
          }
        }
        None => break
      }
    }
    // consume the closing )
    if raw_at(cursor) is Some(b")") {
      advance(cursor)
    }
  }
}

///|
/// Doris ALTER TABLE [IF EXISTS] <name> <actions...>
/// Structured sub-action dispatch: ADD COLUMN/INDEX, DROP COLUMN/INDEX,
/// MODIFY COLUMN, RENAME, REPLACE, ADD/DROP PARTITION, SET, etc.
fn parse_doris_alter(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  // ALTER
  valid = expect_word(
      cursor, b"ALTER", state, source, statement_id, "expected ALTER",
    ) &&
    valid
  // TABLE (or VIEW/DATABASE — all route here; the second word is consumed)
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, b"TABLE") ||
      bytes_equal_ci(raw, b"VIEW") ||
      bytes_equal_ci(raw, b"DATABASE") => advance(cursor)
    _ =>
      valid = expect_word(
          cursor, b"TABLE", state, source, statement_id, "expected TABLE/VIEW/DATABASE after ALTER",
        ) &&
        valid
  }
  // optional IF EXISTS
  if consume_word(cursor, b"IF") {
    ignore(consume_word(cursor, b"EXISTS"))
  }
  // object name
  valid = consume_qualified_name(cursor, state, source, statement_id) && valid
  // Process one or more comma-separated alter actions
  let mut first_action = true
  while token_at(cursor) is Some(_) {
    if !first_action {
      // Consume comma separator between actions
      if !consume_symbol(cursor, b",") {
        break
      }
    }
    first_action = false
    match raw_at(cursor) {
      Some(raw) if bytes_equal_ci(raw, b"ADD") => {
        advance(cursor) // ADD
        // ADD COLUMN <name> <type> [...] | ADD INDEX <name> (...) [...] |
        // ADD PARTITION (...) | ADD ROLLUP ...
        match raw_at(cursor) {
          Some(r) if bytes_equal_ci(r, b"COLUMN") => {
            advance(cursor) // COLUMN
            valid = consume_qualified_name(cursor, state, source, statement_id) &&
              valid
            // Consume column definition body (type, DEFAULT, COMMENT, etc.)
            consume_alter_action_body(cursor)
          }
          Some(r) if bytes_equal_ci(r, b"INDEX") => {
            advance(cursor) // INDEX
            // index name
            if is_identifier_candidate(cursor) {
              advance(cursor)
            }
            // (col1, col2, ...)
            consume_paren_group(cursor)
            consume_alter_action_body(cursor)
          }
          Some(r) if bytes_equal_ci(r, b"PARTITION") => {
            advance(cursor) // PARTITION
            consume_paren_group(cursor)
            consume_alter_action_body(cursor)
          }
          Some(r) if bytes_equal_ci(r, b"ROLLUP") => {
            advance(cursor) // ROLLUP
            consume_alter_action_body(cursor)
          }
          _ => consume_alter_action_body(cursor)
        }
      }
      Some(raw) if bytes_equal_ci(raw, b"DROP") => {
        advance(cursor) // DROP
        match raw_at(cursor) {
          Some(r) if bytes_equal_ci(r, b"COLUMN") => {
            advance(cursor) // COLUMN
            valid = consume_qualified_name(cursor, state, source, statement_id) &&
              valid
          }
          Some(r) if bytes_equal_ci(r, b"PARTITION") => {
            advance(cursor) // PARTITION
            if is_identifier_candidate(cursor) {
              advance(cursor)
            }
            consume_alter_action_body(cursor)
          }
          Some(r) if bytes_equal_ci(r, b"INDEX") => {
            advance(cursor) // INDEX
            if is_identifier_candidate(cursor) {
              advance(cursor)
            }
            consume_alter_action_body(cursor)
          }
          _ => consume_alter_action_body(cursor)
        }
      }
      Some(raw) if bytes_equal_ci(raw, b"MODIFY") => {
        advance(cursor) // MODIFY
        match raw_at(cursor) {
          Some(r) if bytes_equal_ci(r, b"COLUMN") => {
            advance(cursor) // COLUMN
            valid = consume_qualified_name(cursor, state, source, statement_id) &&
              valid
            consume_alter_action_body(cursor)
          }
          Some(r) if bytes_equal_ci(r, b"PARTITION") => {
            advance(cursor) // PARTITION
            consume_paren_group(cursor)
            consume_alter_action_body(cursor)
          }
          _ => consume_alter_action_body(cursor)
        }
      }
      Some(raw) if bytes_equal_ci(raw, b"RENAME") => {
        advance(cursor) // RENAME
        // RENAME COLUMN <old> <new> | RENAME <old> <new>
        ignore(consume_word(cursor, b"COLUMN"))
        if is_identifier_candidate(cursor) {
          advance(cursor)
        }
        if is_identifier_candidate(cursor) {
          advance(cursor)
        }
        consume_alter_action_body(cursor)
      }
      Some(raw) if bytes_equal_ci(raw, b"REPLACE") => {
        advance(cursor) // REPLACE
        // REPLACE COLUMNS (...) WITH (...) ...
        ignore(consume_word(cursor, b"COLUMNS"))
        consume_paren_group(cursor)
        ignore(consume_word(cursor, b"WITH"))
        consume_paren_group(cursor)
        consume_alter_action_body(cursor)
      }
      Some(raw) if bytes_equal_ci(raw, b"SET") => {
        advance(cursor) // SET
        // SET (key = value, ...) or SET DEFAULT...
        consume_paren_group(cursor)
        consume_alter_action_body(cursor)
      }
      _ =>
        // Unknown action — consume remaining tokens for round-trip safety
        consume_alter_action_body(cursor)
    }
  }
  valid
}

///|
/// Consume remaining tokens in an alter action body (until comma at depth 0
/// or end of statement). This handles DEFAULT, COMMENT, USING, PROPERTIES,
/// and other clause keywords that appear after the action verb+object.
fn consume_alter_action_body(cursor : Cursor) -> Unit {
  let mut depth = 0
  while token_at(cursor) is Some(_) {
    match raw_at(cursor) {
      Some(b"(") => depth = depth + 1
      Some(b")") =>
        if depth > 0 {
          depth = depth - 1
        } else {
          // Closing paren at depth 0 — belongs to the outer context, stop
          break
        }
      Some(b",") if depth == 0 =>
        // Comma at depth 0 — separator between alter actions, stop
        break
      _ => ()
    }
    advance(cursor)
  }
}

///|
/// Doris DROP TABLE/VIEW/INDEX [IF EXISTS] <name> [,<name>...]
fn parse_doris_drop(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  valid = expect_word(
      cursor, b"DROP", state, source, statement_id, "expected DROP",
    ) &&
    valid
  // TABLE | VIEW | INDEX
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, b"TABLE") ||
      bytes_equal_ci(raw, b"VIEW") ||
      bytes_equal_ci(raw, b"INDEX") => advance(cursor)
    _ => {
      let at = match token_at(cursor) {
        Some(token) => token.span.start_byte
        None => source.byte_length()
      }
      add_diagnostic(
        state,
        "FATHOM-PARSE-002",
        "expected TABLE, VIEW, or INDEX after DROP",
        "drop",
        make_span(source, at, at),
        statement_id,
      )
      valid = false
    }
  }
  // optional IF EXISTS
  if consume_word(cursor, b"IF") {
    ignore(consume_word(cursor, b"EXISTS"))
  }
  // object name(s) — comma-separated
  if is_identifier_candidate(cursor) {
    advance(cursor)
    if consume_symbol(cursor, b".") && is_identifier_candidate(cursor) {
      advance(cursor)
    }
  } else {
    valid = false
  }
  while consume_symbol(cursor, b",") {
    if is_identifier_candidate(cursor) {
      advance(cursor)
      if consume_symbol(cursor, b".") && is_identifier_candidate(cursor) {
        advance(cursor)
      }
    } else {
      valid = false
    }
  }
  // Consume any remaining tokens
  while token_at(cursor) is Some(_) {
    advance(cursor)
  }
  valid
}

///|
/// Doris TRUNCATE [TABLE] [IF EXISTS] <name>
fn parse_doris_truncate(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  valid = expect_word(
      cursor, b"TRUNCATE", state, source, statement_id, "expected TRUNCATE",
    ) &&
    valid
  // optional TABLE keyword
  ignore(consume_word(cursor, b"TABLE"))
  // optional IF EXISTS
  if consume_word(cursor, b"IF") {
    ignore(consume_word(cursor, b"EXISTS"))
  }
  // table name
  if is_identifier_candidate(cursor) {
    advance(cursor)
    if consume_symbol(cursor, b".") && is_identifier_candidate(cursor) {
      advance(cursor)
    }
  } else {
    valid = false
  }
  while token_at(cursor) is Some(_) {
    advance(cursor)
  }
  valid
}

///|
/// Doris LOAD DATA INFILE 'path' INTO TABLE <name> [PARTITION(...)] [PROPERTIES(...)]
fn parse_doris_load(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  valid = expect_word(
      cursor, b"LOAD", state, source, statement_id, "expected LOAD",
    ) &&
    valid
  valid = expect_word(
      cursor, b"DATA", state, source, statement_id, "expected DATA after LOAD",
    ) &&
    valid
  // Doris uses both INFILE (standard) and INPATH (Doris-specific).
  if !consume_word(cursor, b"INFILE") && !consume_word(cursor, b"INPATH") {
    let at = match token_at(cursor) {
      Some(token) => token.span.start_byte
      None => source.byte_length()
    }
    add_diagnostic(
      state,
      "FATHOM-PARSE-002",
      "expected INFILE or INPATH",
      "keyword",
      make_span(source, at, at),
      statement_id,
    )
    valid = false
  }
  if token_at(cursor) is Some(_) {
    advance(cursor)
  }
  valid = expect_word(
      cursor, b"INTO", state, source, statement_id, "expected INTO",
    ) &&
    valid
  valid = expect_word(
      cursor, b"TABLE", state, source, statement_id, "expected TABLE",
    ) &&
    valid
  if is_identifier_candidate(cursor) {
    advance(cursor)
    if consume_symbol(cursor, b".") && is_identifier_candidate(cursor) {
      advance(cursor)
    }
  } else {
    valid = false
  }
  while token_at(cursor) is Some(_) {
    advance(cursor)
  }
  valid
}

///|
/// Doris EXPORT TABLE <name> TO 'path' [PROPERTIES(...)]
fn parse_doris_export(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  valid = expect_word(
      cursor, b"EXPORT", state, source, statement_id, "expected EXPORT",
    ) &&
    valid
  valid = expect_word(
      cursor, b"TABLE", state, source, statement_id, "expected TABLE",
    ) &&
    valid
  if is_identifier_candidate(cursor) {
    advance(cursor)
    if consume_symbol(cursor, b".") && is_identifier_candidate(cursor) {
      advance(cursor)
    }
  } else {
    valid = false
  }
  valid = expect_word(cursor, b"TO", state, source, statement_id, "expected TO") &&
    valid
  if token_at(cursor) is Some(_) {
    advance(cursor)
  }
  while token_at(cursor) is Some(_) {
    advance(cursor)
  }
  valid
}

///|
/// Doris GRANT <priv> ON <resource> TO <user>
fn parse_doris_grant(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  valid = expect_word(
      cursor, b"GRANT", state, source, statement_id, "expected GRANT",
    ) &&
    valid
  while token_at(cursor) is Some(_) {
    advance(cursor)
  }
  valid
}

///|
/// Doris REVOKE <priv> ON <resource> FROM <user>
fn parse_doris_revoke(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  valid = expect_word(
      cursor, b"REVOKE", state, source, statement_id, "expected REVOKE",
    ) &&
    valid
  while token_at(cursor) is Some(_) {
    advance(cursor)
  }
  valid
}

///|
/// dispatch on the first significant raw token). `context` is carried for
/// signature symmetry; Doris policy state (feature gates) is read from
/// RecoveryState.context.
fn parse_doris_segment(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
  statement_id : UInt,
  state : RecoveryState,
  _context : @dialect.DialectContext,
) -> @syntax.SyntaxNode {
  let span = segment_span(stream, start_index, end_index)
  let indices = significant_indices(stream, start_index, end_index)
  let cursor = { stream, indices, position: 0, depth: 0 }
  let verb = match indices.get(0) {
    Some(first_index) => stream.raw(first_index)
    None => None
  }
  match verb {
    Some(raw) if bytes_equal_ci(raw, b"SELECT") =>
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_query(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        @syntax.SyntaxKind::Select,
        "unexpected tokens after SELECT query",
      )
    Some(raw) if bytes_equal_ci(raw, b"WITH") =>
      match with_prefix_verb(stream, indices, 0) {
        Some(next) if bytes_equal_ci(next, b"SELECT") =>
          finish_statement(
            stream,
            cursor,
            start_index,
            end_index,
            span,
            parse_query(cursor, state, stream.source, statement_id),
            state,
            statement_id,
            @syntax.SyntaxKind::Select,
            "unexpected tokens after SELECT query",
          )
        Some(next) if bytes_equal_ci(next, b"UPDATE") =>
          finish_statement(
            stream,
            cursor,
            start_index,
            end_index,
            span,
            parse_update(cursor, state, stream.source, statement_id),
            state,
            statement_id,
            @syntax.SyntaxKind::Update,
            "unexpected tokens after UPDATE statement",
          )
        Some(next) if bytes_equal_ci(next, b"DELETE") =>
          finish_statement(
            stream,
            cursor,
            start_index,
            end_index,
            span,
            parse_delete(cursor, state, stream.source, statement_id),
            state,
            statement_id,
            @syntax.SyntaxKind::Delete,
            "unexpected tokens after DELETE statement",
          )
        Some(next) if bytes_equal_ci(next, b"MERGE") =>
          finish_statement(
            stream,
            cursor,
            start_index,
            end_index,
            span,
            parse_merge(cursor, state, stream.source, statement_id),
            state,
            statement_id,
            @syntax.SyntaxKind::Merge,
            "unexpected tokens after MERGE statement",
          )
        _ =>
          unsupported_statement(
            stream, start_index, end_index, span, state, statement_id,
          )
      }
    Some(raw) if bytes_equal_ci(raw, b"INSERT") =>
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_insert(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        @syntax.SyntaxKind::Insert,
        "unexpected tokens after INSERT statement",
      )
    Some(raw) if bytes_equal_ci(raw, b"UPDATE") =>
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_update(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        @syntax.SyntaxKind::Update,
        "unexpected tokens after UPDATE statement",
      )
    Some(raw) if bytes_equal_ci(raw, b"DELETE") =>
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_delete(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        @syntax.SyntaxKind::Delete,
        "unexpected tokens after DELETE statement",
      )
    Some(raw) if bytes_equal_ci(raw, b"MERGE") =>
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_merge(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        @syntax.SyntaxKind::Merge,
        "unexpected tokens after MERGE statement",
      )
    Some(raw) if bytes_equal_ci(raw, b"CREATE") => {
      let kind = create_form_kind(stream, indices, 0)
      // D-04 whole-statement gate: Doris has no CREATE CATALOG/DATABASE/
      // FUNCTION/USER/ROLE production (parse_create only knows TABLE/VIEW/
      // INDEX/MATERIALIZED). A statement Doris simply does not support routes
      // to FATHOM-PARSE-007 (unsupported_statement) — never a spurious 002
      // "malformed CREATE" error. This preserves the frozen 213-snapshot
      // baseline (no snapshot covers a non-Doris CREATE form).
      if is_doris_create_form(stream, indices, 0) {
        finish_statement(
          stream,
          cursor,
          start_index,
          end_index,
          span,
          parse_create(cursor, state, stream.source, statement_id),
          state,
          statement_id,
          kind,
          "unexpected tokens after CREATE statement",
        )
      } else {
        unsupported_statement(
          stream, start_index, end_index, span, state, statement_id,
        )
      }
    }
    Some(raw) if bytes_equal_ci(raw, b"ALTER") => {
      let kind = doris_alter_form_kind(stream, indices, 0)
      let valid = parse_doris_alter(cursor, state, stream.source, statement_id)
      finish_statement(
        stream, cursor, start_index, end_index, span, valid, state, statement_id,
        kind, "unexpected tokens after ALTER statement",
      )
    }
    Some(raw) if bytes_equal_ci(raw, b"DROP") => {
      let kind = doris_drop_form_kind(stream, indices, 0)
      let valid = parse_doris_drop(cursor, state, stream.source, statement_id)
      finish_statement(
        stream, cursor, start_index, end_index, span, valid, state, statement_id,
        kind, "unexpected tokens after DROP statement",
      )
    }
    Some(raw) if bytes_equal_ci(raw, b"TRUNCATE") => {
      let valid = parse_doris_truncate(
        cursor,
        state,
        stream.source,
        statement_id,
      )
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        valid,
        state,
        statement_id,
        @syntax.SyntaxKind::TruncateTable,
        "unexpected tokens after TRUNCATE statement",
      )
    }
    Some(raw) if bytes_equal_ci(raw, b"LOAD") => {
      let valid = parse_doris_load(cursor, state, stream.source, statement_id)
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        valid,
        state,
        statement_id,
        @syntax.SyntaxKind::LoadStatement,
        "unexpected tokens after LOAD statement",
      )
    }
    Some(raw) if bytes_equal_ci(raw, b"EXPORT") => {
      let valid = parse_doris_export(cursor, state, stream.source, statement_id)
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        valid,
        state,
        statement_id,
        @syntax.SyntaxKind::ExportStatement,
        "unexpected tokens after EXPORT statement",
      )
    }
    Some(raw) if bytes_equal_ci(raw, b"GRANT") => {
      let valid = parse_doris_grant(cursor, state, stream.source, statement_id)
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        valid,
        state,
        statement_id,
        @syntax.SyntaxKind::GrantStatement,
        "unexpected tokens after GRANT statement",
      )
    }
    Some(raw) if bytes_equal_ci(raw, b"REVOKE") => {
      let valid = parse_doris_revoke(cursor, state, stream.source, statement_id)
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        valid,
        state,
        statement_id,
        @syntax.SyntaxKind::RevokeStatement,
        "unexpected tokens after REVOKE statement",
      )
    }
    // Doris utility statements — consume all tokens, map to existing kinds.
    Some(raw) if bytes_equal_ci(raw, b"SHOW") => {
      while token_at(cursor) is Some(_) {
        advance(cursor)
      }
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        true,
        state,
        statement_id,
        @syntax.SyntaxKind::ShowStatement,
        "unexpected tokens after SHOW statement",
      )
    }
    Some(raw) if bytes_equal_ci(raw, b"DESCRIBE") ||
      bytes_equal_ci(raw, b"DESC") => {
      while token_at(cursor) is Some(_) {
        advance(cursor)
      }
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        true,
        state,
        statement_id,
        @syntax.SyntaxKind::DescribeStatement,
        "unexpected tokens after DESCRIBE statement",
      )
    }
    Some(raw) if bytes_equal_ci(raw, b"EXPLAIN") => {
      while token_at(cursor) is Some(_) {
        advance(cursor)
      }
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        true,
        state,
        statement_id,
        @syntax.SyntaxKind::ExplainStatement,
        "unexpected tokens after EXPLAIN statement",
      )
    }
    Some(raw) if bytes_equal_ci(raw, b"ANALYZE") => {
      while token_at(cursor) is Some(_) {
        advance(cursor)
      }
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        true,
        state,
        statement_id,
        @syntax.SyntaxKind::AnalyzeStatement,
        "unexpected tokens after ANALYZE statement",
      )
    }
    Some(raw) if bytes_equal_ci(raw, b"SET") => {
      while token_at(cursor) is Some(_) {
        advance(cursor)
      }
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        true,
        state,
        statement_id,
        @syntax.SyntaxKind::SetOption,
        "unexpected tokens after SET statement",
      )
    }
    Some(raw) if bytes_equal_ci(raw, b"USE") => {
      while token_at(cursor) is Some(_) {
        advance(cursor)
      }
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        true,
        state,
        statement_id,
        @syntax.SyntaxKind::UseStatement,
        "unexpected tokens after USE statement",
      )
    }
    _ =>
      unsupported_statement(
        stream, start_index, end_index, span, state, statement_id,
      )
  }
}

///|
/// Flink CREATE second-word dispatch (SqlCreateExtended, parserImpls.ftl:
/// 2850-2920): resolves the statement-family kind without consuming the cursor
/// — CATALOG/DATABASE/TABLE/VIEW/FUNCTION, with the optional [TEMPORARY
/// [SYSTEM]] prefix before TABLE/FUNCTION (CREATE TEMPORARY TABLE,
/// CREATE TEMPORARY [SYSTEM] FUNCTION). Copy of the Doris create_form_kind
/// shape (:2184-2206) but for the Flink families.
fn flink_create_form_kind(
  stream : @token.TokenStream,
  indices : Array[Int],
  start_index : Int,
) -> @syntax.SyntaxKind {
  let mut i = start_index + 1
  let length = indices.length()
  if i >= length {
    return @syntax.SyntaxKind::CreateTable
  }
  let modifier = match stream.raw(indices[i]) {
    Some(raw) => bytes_equal_ci(raw, b"TEMPORARY")
    None => false
  }
  if modifier {
    i = i + 1
  }
  if i >= length {
    return @syntax.SyntaxKind::CreateTable
  }
  if modifier {
    // CREATE TEMPORARY [SYSTEM] (FUNCTION) | CREATE TEMPORARY (TABLE): skip
    // an optional SYSTEM before the FUNCTION/TABLE family word.
    let system = match stream.raw(indices[i]) {
      Some(raw) => bytes_equal_ci(raw, b"SYSTEM")
      None => false
    }
    if system {
      i = i + 1
    }
    if i >= length {
      return @syntax.SyntaxKind::CreateTable
    }
  }
  match stream.raw(indices[i]) {
    Some(raw) if bytes_equal_ci(raw, b"CATALOG") =>
      @syntax.SyntaxKind::CreateCatalog
    Some(raw) if bytes_equal_ci(raw, b"DATABASE") =>
      @syntax.SyntaxKind::CreateDatabase
    Some(raw) if bytes_equal_ci(raw, b"TABLE") =>
      @syntax.SyntaxKind::CreateTable
    Some(raw) if bytes_equal_ci(raw, b"VIEW") => @syntax.SyntaxKind::CreateView
    Some(raw) if bytes_equal_ci(raw, b"FUNCTION") =>
      @syntax.SyntaxKind::CreateFunction
    _ => @syntax.SyntaxKind::CreateTable
  }
}

///|
/// Flink ALTER second-word dispatch: every family (CATALOG/DATABASE/TABLE/
/// VIEW/FUNCTION) resolves to the coarse per-family AlterTable kind (D-02 —
/// statement sub-type rides in node metadata/span, not extra kinds).
fn flink_alter_form_kind(
  stream : @token.TokenStream,
  indices : Array[Int],
  start_index : Int,
) -> @syntax.SyntaxKind {
  match indices.get(start_index + 1) {
    Some(i) =>
      match stream.raw(i) {
        Some(raw) if bytes_equal_ci(raw, b"CATALOG") ||
          bytes_equal_ci(raw, b"DATABASE") ||
          bytes_equal_ci(raw, b"TABLE") ||
          bytes_equal_ci(raw, b"VIEW") ||
          bytes_equal_ci(raw, b"FUNCTION") => @syntax.SyntaxKind::AlterTable
        _ => @syntax.SyntaxKind::AlterTable
      }
    None => @syntax.SyntaxKind::AlterTable
  }
}

///|
/// Flink DROP second-word dispatch (SqlDropExtended, parserImpls.ftl:2850-
/// 2920): CATALOG/DATABASE/TABLE/VIEW/FUNCTION each resolve to their own
/// per-family Drop kind.
fn flink_drop_form_kind(
  stream : @token.TokenStream,
  indices : Array[Int],
  start_index : Int,
) -> @syntax.SyntaxKind {
  match indices.get(start_index + 1) {
    Some(i) =>
      match stream.raw(i) {
        Some(raw) if bytes_equal_ci(raw, b"CATALOG") =>
          @syntax.SyntaxKind::DropCatalog
        Some(raw) if bytes_equal_ci(raw, b"DATABASE") =>
          @syntax.SyntaxKind::DropDatabase
        Some(raw) if bytes_equal_ci(raw, b"TABLE") =>
          @syntax.SyntaxKind::DropTable
        Some(raw) if bytes_equal_ci(raw, b"VIEW") =>
          @syntax.SyntaxKind::DropView
        Some(raw) if bytes_equal_ci(raw, b"FUNCTION") =>
          @syntax.SyntaxKind::DropFunction
        _ => @syntax.SyntaxKind::DropTable
      }
    None => @syntax.SyntaxKind::DropTable
  }
}

///|
/// Flink statement grammar (Phase 11, D-04/D-06): keyword-first dispatch
/// copying the parse_doris_segment skeleton. SELECT/WITH route through the
/// shared query skeleton's Flink-safe subset (parse_flink_query in
/// flink_grammar.mbt); unknown starters fall through to
/// unsupported_statement (FATHOM-PARSE-007). FATHOM-PARSE-008 is retired
/// (D-06): the code stays vacant and is never reused; genuinely-unsupported
/// whole statements route through 007.
fn parse_flink_segment(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
  statement_id : UInt,
  state : RecoveryState,
  _context : @dialect.DialectContext,
) -> @syntax.SyntaxNode {
  let span = segment_span(stream, start_index, end_index)
  let indices = significant_indices(stream, start_index, end_index)
  let cursor = { stream, indices, position: 0, depth: 0 }
  let verb = match indices.get(0) {
    Some(first_index) => stream.raw(first_index)
    None => None
  }
  match verb {
    Some(raw) if bytes_equal_ci(raw, b"SELECT") =>
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_flink_query(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        @syntax.SyntaxKind::Select,
        "unexpected tokens after SELECT query",
      )
    Some(raw) if bytes_equal_ci(raw, b"WITH") =>
      match with_prefix_verb(stream, indices, 0) {
        Some(next) if bytes_equal_ci(next, b"SELECT") =>
          finish_statement(
            stream,
            cursor,
            start_index,
            end_index,
            span,
            parse_flink_query(cursor, state, stream.source, statement_id),
            state,
            statement_id,
            @syntax.SyntaxKind::Select,
            "unexpected tokens after SELECT query",
          )
        Some(next) if bytes_equal_ci(next, b"UPDATE") =>
          finish_statement(
            stream,
            cursor,
            start_index,
            end_index,
            span,
            parse_flink_update(cursor, state, stream.source, statement_id),
            state,
            statement_id,
            @syntax.SyntaxKind::Update,
            "unexpected tokens after UPDATE statement",
          )
        Some(next) if bytes_equal_ci(next, b"DELETE") =>
          finish_statement(
            stream,
            cursor,
            start_index,
            end_index,
            span,
            parse_flink_delete(cursor, state, stream.source, statement_id),
            state,
            statement_id,
            @syntax.SyntaxKind::Delete,
            "unexpected tokens after DELETE statement",
          )
        _ =>
          unsupported_statement(
            stream, start_index, end_index, span, state, statement_id,
          )
      }
    // FLINK-02 DML: RichSqlInsert (parserImpls.ftl:2306-2379) — INSERT/UPSERT
    // with INTO/OVERWRITE/PARTITION/columns/source/ON CONFLICT.
    Some(raw) if bytes_equal_ci(raw, b"INSERT") ||
      bytes_equal_ci(raw, b"UPSERT") =>
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_flink_insert(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        @syntax.SyntaxKind::Insert,
        "unexpected tokens after INSERT statement",
      )
    // FLINK-02 DML: Calcite base SqlUpdate (Parser-calcite-1.36.0.jj:1794-1832).
    Some(raw) if bytes_equal_ci(raw, b"UPDATE") =>
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_flink_update(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        @syntax.SyntaxKind::Update,
        "unexpected tokens after UPDATE statement",
      )
    // FLINK-02 DML: Calcite base SqlDelete (:1768-1789).
    Some(raw) if bytes_equal_ci(raw, b"DELETE") =>
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_flink_delete(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        @syntax.SyntaxKind::Delete,
        "unexpected tokens after DELETE statement",
      )
    // FLINK-02 auxiliary statements (D-02 kinds locked in 11-01).
    Some(raw) if bytes_equal_ci(raw, b"EXPLAIN") =>
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_flink_explain(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        @syntax.SyntaxKind::ExplainStatement,
        "unexpected tokens after EXPLAIN statement",
      )
    Some(raw) if bytes_equal_ci(raw, b"SHOW") =>
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_flink_show(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        @syntax.SyntaxKind::ShowStatement,
        "unexpected tokens after SHOW statement",
      )
    Some(raw) if bytes_equal_ci(raw, b"DESCRIBE") ||
      bytes_equal_ci(raw, b"DESC") =>
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_flink_describe(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        @syntax.SyntaxKind::DescribeStatement,
        "unexpected tokens after DESCRIBE statement",
      )
    Some(raw) if bytes_equal_ci(raw, b"ANALYZE") =>
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_flink_analyze(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        @syntax.SyntaxKind::AnalyzeStatement,
        "unexpected tokens after ANALYZE statement",
      )
    Some(raw) if bytes_equal_ci(raw, b"USE") =>
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_flink_use(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        @syntax.SyntaxKind::UseStatement,
        "unexpected tokens after USE statement",
      )
    Some(raw) if bytes_equal_ci(raw, b"SET") || bytes_equal_ci(raw, b"RESET") =>
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_flink_set_reset(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        @syntax.SyntaxKind::SetOption,
        "unexpected tokens after SET/RESET statement",
      )
    // FLINK-03 DDL (SqlCreateExtended/SqlDropExtended/SqlAlter*
    // parserImpls.ftl:2850-2920 + statementParserMethods Parser.tdd:651-727):
    // the second-word dispatch resolves the per-family statement kind, then
    // parse_flink_create/alter/drop (flink_grammar.mbt) consume the body.
    Some(raw) if bytes_equal_ci(raw, b"CREATE") => {
      let kind = flink_create_form_kind(stream, indices, 0)
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_flink_create(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        kind,
        "unexpected tokens after CREATE statement",
      )
    }
    Some(raw) if bytes_equal_ci(raw, b"ALTER") => {
      let kind = flink_alter_form_kind(stream, indices, 0)
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_flink_alter(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        kind,
        "unexpected tokens after ALTER statement",
      )
    }
    Some(raw) if bytes_equal_ci(raw, b"DROP") => {
      let kind = flink_drop_form_kind(stream, indices, 0)
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        parse_flink_drop(cursor, state, stream.source, statement_id),
        state,
        statement_id,
        kind,
        "unexpected tokens after DROP statement",
      )
    }
    Some(raw) if bytes_equal_ci(raw, b"BEGIN") ||
      bytes_equal_ci(raw, b"START") ||
      bytes_equal_ci(raw, b"COMMIT") ||
      bytes_equal_ci(raw, b"ROLLBACK") => {
      // Flink transaction control: BEGIN / START TRANSACTION / COMMIT / ROLLBACK.
      // All map to BeginTransaction; consume all tokens as the body.
      while token_at(cursor) is Some(_) {
        advance(cursor)
      }
      finish_statement(
        stream,
        cursor,
        start_index,
        end_index,
        span,
        true,
        state,
        statement_id,
        @syntax.SyntaxKind::BeginTransaction,
        "unexpected tokens after transaction statement",
      )
    }
    _ =>
      unsupported_statement(
        stream, start_index, end_index, span, state, statement_id,
      )
  }
}

///|
fn append_skipped(
  root_children : Array[@syntax.SyntaxElement],
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
) -> Unit {
  if start_index < end_index {
    let span = segment_span(stream, start_index, end_index)
    let node = require_node(
      @syntax.SyntaxNode::new(
        @syntax.SyntaxKind::Skipped,
        span,
        segment_children(stream, start_index, end_index),
      ),
    )
    root_children.push(@syntax.SyntaxElement::ChildNode(node))
  } else if start_index == 0 && stream.source.byte_length() > 0 {
    let span = make_span(stream.source, 0, stream.source.byte_length())
    let node = require_node(
      @syntax.SyntaxNode::new(
        @syntax.SyntaxKind::Skipped,
        span,
        segment_children(stream, 0, end_index),
      ),
    )
    root_children.push(@syntax.SyntaxElement::ChildNode(node))
  }
}

///|
fn append_skipped_span(
  root_children : Array[@syntax.SyntaxElement],
  source : @source.SourceText,
  start_byte : Int,
) -> Unit {
  if start_byte < source.byte_length() {
    let span = make_span(source, start_byte, source.byte_length())
    let node = require_node(
      @syntax.SyntaxNode::skipped(span, [
        @syntax.SyntaxElement::Leaf(
          @syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceSkipped, span),
        ),
      ]),
    )
    root_children.push(@syntax.SyntaxElement::ChildNode(node))
  }
}

///|
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

///|
pub fn parse_with_limits_context(
  source : @source.SourceText,
  context : @dialect.DialectContext,
  mode : ParseMode,
  limits : ParserLimits,
) -> ParsedDocument {
  let limits = limits.normalized()
  let stream = @lexer.lex_with_limit(source, context, limits.max_tokens)
  let root_span = make_span(source, 0, source.byte_length())
  let state = RecoveryState::{
    diagnostics: [],
    limits,
    context,
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
        Some(token) if token.span.end_byte > limits.max_bytes => {
          cut_index = index
          break
        }
        _ => index = index + 1
      }
    }
    parse_end = cut_index
    let cap_span = make_span(
      source,
      if cut_index < stream.length() {
        match stream.at(cut_index) {
          Some(token) => token.span.start_byte
          None => limits.max_bytes
        }
      } else {
        limits.max_bytes
      },
      source.byte_length(),
    )
    resource_diagnostic(
      state,
      cap_span,
      segment_statement_id_for_span(stream, cap_span),
    )
  }
  let mut segment_start = 0
  let mut statement_id : UInt = 0U
  let mut index = 0
  while index < parse_end {
    let is_semicolon = match stream.raw(index) {
      Some(raw) => raw == b";"
      None => false
    }
    if is_semicolon {
      let segment_end = index + 1
      if has_statement_content(stream, segment_start, segment_end) {
        let segment = parse_segment(
          stream, segment_start, segment_end, statement_id, state, context,
        )
        if segment.span().length() > 0 {
          root_children.push(@syntax.SyntaxElement::ChildNode(segment))
          statement_id = statement_id + 1U
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
      let segment = parse_segment(
        stream, segment_start, parse_end, statement_id, state, context,
      )
      if segment.span().length() > 0 {
        root_children.push(@syntax.SyntaxElement::ChildNode(segment))
        statement_id = statement_id + 1U
      }
    }
  }
  if cut_index < stream.length() {
    append_skipped(root_children, stream, cut_index, stream.length())
  }
  match stream.truncated_at {
    Some(at) => {
      resource_diagnostic(
        state,
        make_span(source, at, source.byte_length()),
        segment_statement_id_for_span(stream, make_span(source, at, at)),
      )
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
        "FATHOM-PARSE-003",
        "invalid source encoding or unterminated lexical material",
        "lexical material",
        token.span,
        segment_statement_id_for_span(stream, token.span),
      )
    }
  }
  let valid = state.diagnostics.length() == 0
  {
    source,
    mode,
    root: require_node(
      @syntax.SyntaxNode::new(
        @syntax.SyntaxKind::Document,
        root_span,
        root_children,
      ),
    ),
    diagnostics: state.diagnostics,
    valid,
    recovered: !valid && mode is ParseMode::Editor,
  }
}

///|
pub fn parse_with_limits(
  source : @source.SourceText,
  context : @dialect.DialectContext,
  mode : ParseMode,
  limits : ParserLimits,
) -> ParsedDocument {
  parse_with_limits_context(source, context, mode, limits)
}

///|
pub fn parse(
  source : @source.SourceText,
  context : @dialect.DialectContext,
  mode : ParseMode,
) -> ParsedDocument {
  parse_with_limits_context(source, context, mode, ParserLimits::default())
}

///|
/// Doris test context helper: profile ids are the validated surface; the
/// metadata strings are only audit metadata for classification/feature gates.
fn test_doris_context(profile_id : String) -> @dialect.DialectContext {
  {
    dialect: @dialect.Dialect::Doris,
    profile_id,
    exact_release: profile_id,
    feature_introduction: "",
  }
}

///|
test "parser_flink_context_parses_select" {
  // D-06 (Phase 11): the Flink branch now runs the real grammar. A valid Flink
  // SELECT parses valid=true with no diagnostics and no FATHOM-PARSE-008
  // (the code is retired and never reused).
  let source = match @source.SourceText::new(b"SELECT 1") {
    Ok(source) => source
    Err(_) => panic()
  }
  let context : @dialect.DialectContext = {
    dialect: @dialect.Dialect::Flink,
    profile_id: "flink-2.3.0",
    exact_release: "flink-2.3.0",
    feature_introduction: "",
  }
  let parsed = parse(source, context, ParseMode::Strict)
  assert_true(parsed.valid)
  assert_eq(parsed.diagnostics.length(), 0)
  assert_true(parsed.root.children().length() >= 1)
  let statements = parsed.root.children()
  assert_true(statements[0].span().start_byte == 0)
  assert_true(statements[0].span().end_byte == source.byte_length())
}

///|
test "parser_select_pratt_and_statement_identity" {
  let source = match @source.SourceText::new(b"SELECT a + 1; SELECT b") {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = parse(source, test_doris_context("4.x"), ParseMode::Strict)
  assert_true(parsed.root.kind() is @syntax.SyntaxKind::Document)
  assert_eq(parsed.root.children().length(), 2)
  assert_true(parsed.valid)
  assert_eq(parsed.diagnostics.length(), 0)
}

///|
test "parser_reports_incomplete_without_losing_source" {
  let source = match @source.SourceText::new(b"SELECT") {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = parse(source, test_doris_context("2.1"), ParseMode::Editor)
  assert_true(!parsed.valid)
  assert_true(parsed.recovered)
  assert_eq(parsed.diagnostics[0].code, "FATHOM-PARSE-002")
  assert_eq(parsed.diagnostics[0].statement_id, 0U)
  assert_true(parsed.root.leaf_count() > 0)
}

///|
test "parser_statement_and_select_spans_are_source_ordered" {
  let source = match @source.SourceText::new(b"SELECT 1; SELECT x") {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = parse(source, test_doris_context("3.x"), ParseMode::Strict)
  let statements = parsed.root.children()
  assert_eq(statements.length(), 2)
  assert_true(statements[0].span().end_byte <= statements[1].span().start_byte)
  assert_true(statements[0].text_len() > 0)
  assert_true(statements[1].text_len() > 0)
}

///|
test "parser_unknown_and_invalid_material_remains_source_backed" {
  let raw = b"SELECT @ \xff"
  let source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = parse(source, test_doris_context("4.x"), ParseMode::Editor)
  assert_true(!parsed.valid)
  assert_true(parsed.recovered)
  assert_true(parsed.root.span().end_byte == raw.length())
  assert_true(parsed.diagnostics.length() >= 1)
  assert_true(parsed.diagnostics[0].span.end_byte <= raw.length())
}

///|
test "parser_lexical_diagnostic_keeps_statement_identity" {
  let source = match @source.SourceText::new(b"SELECT 1; SELECT \xff") {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = parse(source, test_doris_context("4.x"), ParseMode::Editor)
  let mut found_second_statement = false
  for diagnostic in parsed.diagnostics {
    if diagnostic.code == "FATHOM-PARSE-003" {
      assert_eq(diagnostic.statement_id, 1)
      found_second_statement = true
    }
  }
  assert_true(found_second_statement)
}

///|
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
  let parsed = parse_with_limits(
    source,
    test_doris_context("4.x"),
    ParseMode::Editor,
    limits,
  )
  assert_true(!parsed.valid)
  assert_true(parsed.recovered)
  assert_true(parsed.diagnostics.length() > 0)
  assert_true(parsed.root.children().length() > 0)
}

///|
test "parser_low_level_negative_limits_normalize_without_panic" {
  let empty_source = match @source.SourceText::new(b"") {
    Ok(source) => source
    Err(_) => panic()
  }
  let empty = parse_with_limits(
    empty_source,
    test_doris_context("4.x"),
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
    test_doris_context("4.x"),
    ParseMode::Editor,
    ParserLimits::new(-1, -1, -1, -1, -1),
  )
  assert_true(!nonempty.valid)
  assert_true(nonempty.diagnostics.any(d => d.expected_class == "resource"))
  assert_true(nonempty.root.is_valid(nonempty_source.byte_length()))
  assert_true(
    nonempty.diagnostics.all(d => {
      d.span.start_byte >= 0 && d.span.end_byte <= nonempty_source.byte_length()
    }),
  )
}

///|
test "parser_limit_validation_reports_each_negative_boundary" {
  assert_true(
    ParserLimits::new(-1, 1, 1, 1, 1).validate()
    is Err(ParserLimitError::MaxBytes(-1)),
  )
  assert_true(
    ParserLimits::new(1, -1, 1, 1, 1).validate()
    is Err(ParserLimitError::MaxTokens(-1)),
  )
  assert_true(
    ParserLimits::new(1, 1, -1, 1, 1).validate()
    is Err(ParserLimitError::MaxRecursionDepth(-1)),
  )
  assert_true(
    ParserLimits::new(1, 1, 1, -1, 1).validate()
    is Err(ParserLimitError::MaxRecoverySteps(-1)),
  )
  assert_true(
    ParserLimits::new(1, 1, 1, 1, -1).validate()
    is Err(ParserLimitError::MaxDiagnostics(-1)),
  )
}
