/// Versioned primitive parse boundary. Source bytes are owned once by ParseResult.
pub(all) enum ParseMode {
  Strict
  Editor
}

pub struct ParseLimits {
  pub max_bytes : Int
  pub max_tokens : Int
  pub max_recursion_depth : Int
  pub max_recovery_steps : Int
  pub max_diagnostics : Int
}

pub fn ParseLimits::default() -> ParseLimits {
  let limits = @parser.ParserLimits::default()
  {
    max_bytes: limits.max_bytes,
    max_tokens: limits.max_tokens,
    max_recursion_depth: limits.max_recursion_depth,
    max_recovery_steps: limits.max_recovery_steps,
    max_diagnostics: limits.max_diagnostics,
  }
}

pub fn ParseLimits::new(
  max_bytes : Int,
  max_tokens : Int,
  max_recursion_depth : Int,
  max_recovery_steps : Int,
  max_diagnostics : Int,
) -> ParseLimits {
  {
    max_bytes: max_bytes,
    max_tokens: max_tokens,
    max_recursion_depth: max_recursion_depth,
    max_recovery_steps: max_recovery_steps,
    max_diagnostics: max_diagnostics,
  }
}

pub struct ParseOptions {
  profile : @token.DorisProfile
  mode : ParseMode
  limits : ParseLimits
}

pub enum ParseError {
  UnknownProfile(profile_id~ : String)
  UnknownMode(mode_id~ : String)
  InputTooLarge(requested_bytes~ : Int, max_bytes~ : Int)
} derive(Eq, @debug.Debug)

pub fn ParseOptions::new(profile_id : String, mode_id : String) -> Result[ParseOptions, ParseError] {
  let profile = match @token.DorisProfile::from_id(profile_id) {
    Some(profile) => profile
    None => return Err(UnknownProfile(profile_id~))
  }
  let mode = match mode_id {
    "strict" => ParseMode::Strict
    "editor" => ParseMode::Editor
    _ => return Err(UnknownMode(mode_id~))
  }
  Ok({ profile: profile, mode: mode, limits: ParseLimits::default() })
}

pub fn ParseOptions::for_profile(
  profile : @token.DorisProfile,
  mode : ParseMode,
) -> ParseOptions {
  { profile: profile, mode: mode, limits: ParseLimits::default() }
}
pub fn ParseOptions::for_profile_with_limits(
  profile : @token.DorisProfile,
  mode : ParseMode,
  limits : ParseLimits,
) -> ParseOptions {
  { profile: profile, mode: mode, limits: limits }
}

pub fn ParseOptions::profile(self : ParseOptions) -> @token.DorisProfile {
  self.profile
}

pub fn ParseOptions::mode(self : ParseOptions) -> ParseMode {
  self.mode
}

pub fn ParseOptions::limits(self : ParseOptions) -> ParseLimits {
  self.limits
}
pub struct PrimitiveNode {
  pub kind : String
  pub start_byte : Int
  pub end_byte : Int
  pub text_len : Int
  pub children : Array[PrimitiveNode]
}

pub struct PrimitiveDiagnostic {
  pub severity : String
  pub code : String
  pub message : String
  pub expected_class : String
  pub start_byte : Int
  pub end_byte : Int
  pub statement_id : Int
}

pub struct ParseResult {
  pub schema_version : String
  pub source_transport : String
  pub profile : String
  pub mode : String
  pub valid : Bool
  pub recovered : Bool
  pub source_bytes : Bytes
  pub source_byte_length : Int
  pub root : PrimitiveNode
  pub diagnostics : Array[PrimitiveDiagnostic]
}

fn kind_id(kind : @syntax.SyntaxKind) -> String {
  match kind {
    @syntax.SyntaxKind::Document => "document"
    @syntax.SyntaxKind::Statement => "statement"
    @syntax.SyntaxKind::Select => "select"
    @syntax.SyntaxKind::Expression => "expression"
    @syntax.SyntaxKind::Token => "token"
    @syntax.SyntaxKind::Trivia => "trivia"
    @syntax.SyntaxKind::Error => "error"
    @syntax.SyntaxKind::Skipped => "skipped"
    @syntax.SyntaxKind::Missing => "missing"
  }
}

fn primitive_node(node : @syntax.SyntaxNode) -> PrimitiveNode {
  let children : Array[PrimitiveNode] = []
  for child in node.children() {
    match child {
      @syntax.SyntaxElement::ChildNode(child_node) => children.push(primitive_node(child_node))
      @syntax.SyntaxElement::Leaf(leaf) => {
        let kind = match leaf.kind {
          @syntax.LeafKind::SourceToken => "token"
          @syntax.LeafKind::SourceTrivia => "trivia"
          @syntax.LeafKind::SourceError => "error"
          @syntax.LeafKind::SourceSkipped => "skipped"
        }
        children.push({
          kind: kind,
          start_byte: leaf.span.start_byte,
          end_byte: leaf.span.end_byte,
          text_len: leaf.text_len,
          children: [],
        })
      }
    }
  }
  {
    kind: kind_id(node.kind()),
    start_byte: node.span().start_byte,
    end_byte: node.span().end_byte,
    text_len: node.text_len(),
    children: children,
  }
}

fn primitive_diagnostic(diagnostic : @parser.ParserDiagnostic) -> PrimitiveDiagnostic {
  {
    severity: diagnostic.severity,
    code: diagnostic.code,
    message: diagnostic.message,
    expected_class: diagnostic.expected_class,
    start_byte: diagnostic.span.start_byte,
    end_byte: diagnostic.span.end_byte,
    statement_id: diagnostic.statement_id,
  }
}

fn mode_id(mode : ParseMode) -> String {
  match mode {
    ParseMode::Strict => "strict"
    ParseMode::Editor => "editor"
  }
}

pub fn parse(raw : Bytes, options : ParseOptions) -> Result[ParseResult, ParseError] {
  let source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(@source.SourceError::InputTooLarge(requested_bytes~, max_bytes~)) => {
      return Err(InputTooLarge(requested_bytes~, max_bytes~))
    }
  }
  let parser_mode = match options.mode {
    ParseMode::Strict => @parser.ParseMode::Strict
    ParseMode::Editor => @parser.ParseMode::Editor
  }
  let limits = options.limits
  let parser_limits = @parser.ParserLimits::new(
    limits.max_bytes,
    limits.max_tokens,
    limits.max_recursion_depth,
    limits.max_recovery_steps,
    limits.max_diagnostics,
  )
  let parsed = @parser.parse_with_limits(source, options.profile, parser_mode, parser_limits)
  let diagnostics : Array[PrimitiveDiagnostic] = []
  for diagnostic in parsed.diagnostics {
    diagnostics.push(primitive_diagnostic(diagnostic))
  }
  Ok({
    schema_version: "doris.parse.v1",
    source_transport: "inline-root-v1",
    profile: options.profile.id(),
    mode: mode_id(options.mode),
    valid: parsed.valid,
    recovered: parsed.recovered,
    source_bytes: source.bytes(),
    source_byte_length: source.byte_length(),
    root: primitive_node(parsed.root),
    diagnostics: diagnostics,
  })
}

pub fn parse_with_ids(
  raw : Bytes,
  profile_id : String,
  mode_id_value : String,
) -> Result[ParseResult, ParseError] {
  let options = match ParseOptions::new(profile_id, mode_id_value) {
    Ok(options) => options
    Err(error) => return Err(error)
  }
  parse(raw, options)
}

pub fn ParseResult::has_root_only_source(self : ParseResult) -> Bool {
  self.source_byte_length == self.source_bytes.length()
}

pub fn ParseResult::all_spans_in_bounds(self : ParseResult) -> Bool {
  fn check(node : PrimitiveNode, length : Int) -> Bool {
    if node.start_byte < 0 || node.start_byte > node.end_byte || node.end_byte > length {
      false
    } else {
      let mut result = true
      for child in node.children {
        if !check(child, length) {
          result = false
        }
      }
      result
    }
  }
  check(self.root, self.source_byte_length)
}

test "api_requires_explicit_profile_and_mode" {
  assert_true(ParseOptions::new("mysql", "strict") is Err(UnknownProfile(..)))
  assert_true(ParseOptions::new("4.x", "unknown") is Err(UnknownMode(..)))
  let options = match ParseOptions::new("2.1", "editor") {
    Ok(options) => options
    Err(_) => panic()
  }
  assert_eq(options.profile().id(), "2.1")
  assert_true(options.mode() is ParseMode::Editor)
}

test "api_result_owns_source_once_and_has_bounded_descendant_spans" {
  let result = match parse_with_ids(b"SELECT x\r\n", "3.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(result.source_byte_length, 10)
  assert_true(result.has_root_only_source())
  assert_true(result.all_spans_in_bounds())
  assert_eq(result.diagnostics.length(), 0)
}

test "api_diagnostics_have_stable_namespace_and_snapshot_local_ids" {
  let first = match parse_with_ids(b"bad", "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  let second = match parse_with_ids(b"bad", "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(first.diagnostics[0].code.starts_with("DORIS-PARSE-"))
  assert_eq(first.diagnostics[0].statement_id, 0)
  assert_eq(second.diagnostics[0].statement_id, 0)
}

test "api_empty_input_has_no_synthetic_diagnostic_and_modes_share_shape" {
  let empty = match parse_with_ids(b"", "2.1", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(empty.source_byte_length, 0)
  assert_eq(empty.root.start_byte, 0)
  assert_eq(empty.root.end_byte, 0)
  assert_eq(empty.diagnostics.length(), 0)
  let strict = match parse_with_ids(b"SELECT", "3.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  let editor = match parse_with_ids(b"SELECT", "3.x", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(strict.root.kind, editor.root.kind)
  assert_eq(strict.root.text_len, editor.root.text_len)
  assert_true(!strict.recovered)
  assert_true(editor.recovered)
}

test "api_diagnostic_statement_ids_are_monotonic_per_snapshot" {
  let result = match parse_with_ids(b"bad; bad", "4.x", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(result.diagnostics.length(), 2)
  assert_eq(result.diagnostics[0].statement_id, 0)
  assert_eq(result.diagnostics[1].statement_id, 1)
  assert_true(result.diagnostics[0].code.has_prefix("DORIS-PARSE-"))
  assert_true(result.diagnostics[1].code.has_prefix("DORIS-PARSE-"))
}
