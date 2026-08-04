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
  profile_context : @token.ValidatedProfileContext
  mode : ParseMode
  limits : ParseLimits
}

pub enum ParseError {
  UnknownProfile(profile_id~ : String)
  UnknownMode(mode_id~ : String)
  ProfileMetadataMismatch(
    profile_id~ : String,
    expected_release~ : String,
    actual_release~ : String,
    expected_feature_introduction~ : String,
    actual_feature_introduction~ : String,
  )
  UnsupportedFeatureIntroduction(feature_introduction~ : String)
  InputTooLarge(requested_bytes~ : Int, max_bytes~ : Int)
  InvalidLimit(limit_name~ : String, value~ : Int)
  InvalidSyntaxTree
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
  Ok({ profile_context: @token.ValidatedProfileContext::canonical(profile), mode: mode, limits: ParseLimits::default() })
}

pub fn ParseOptions::for_profile_with_metadata(
  profile : @token.DorisProfile,
  metadata : @token.ProfileMetadata,
  mode : ParseMode,
) -> Result[ParseOptions, ParseError] {
  let context = match profile.validate_metadata(metadata) {
    Ok(context) => context
    Err(@token.ProfileMetadataError::ProfileMetadataMismatch(profile_id~, expected_release~, actual_release~, expected_feature_introduction~, actual_feature_introduction~)) => {
      return Err(ProfileMetadataMismatch(profile_id~, expected_release~, actual_release~, expected_feature_introduction~, actual_feature_introduction~))
    }
    Err(@token.ProfileMetadataError::UnsupportedFeatureIntroduction(feature_introduction~)) => return Err(UnsupportedFeatureIntroduction(feature_introduction~))
    Err(@token.ProfileMetadataError::UnknownProfile(profile_id~)) => return Err(UnknownProfile(profile_id~))
  }
  Ok({ profile_context: context, mode: mode, limits: ParseLimits::default() })
}

pub fn ParseOptions::from_manifest(
  profile_id : String,
  exact_release : String,
  feature_introduction : String,
  mode_id : String,
) -> Result[ParseOptions, ParseError] {
  let mode = match mode_id {
    "strict" => ParseMode::Strict
    "editor" => ParseMode::Editor
    _ => return Err(UnknownMode(mode_id~))
  }
  let context = match @token.ProfileMetadata::for_manifest(profile_id, exact_release, feature_introduction) {
    Ok(context) => context
    Err(@token.ProfileMetadataError::UnknownProfile(profile_id~)) => return Err(UnknownProfile(profile_id~))
    Err(@token.ProfileMetadataError::ProfileMetadataMismatch(profile_id~, expected_release~, actual_release~, expected_feature_introduction~, actual_feature_introduction~)) => {
      return Err(ProfileMetadataMismatch(profile_id~, expected_release~, actual_release~, expected_feature_introduction~, actual_feature_introduction~))
    }
    Err(@token.ProfileMetadataError::UnsupportedFeatureIntroduction(feature_introduction~)) => return Err(UnsupportedFeatureIntroduction(feature_introduction~))
  }
  Ok({ profile_context: context, mode: mode, limits: ParseLimits::default() })
}

pub fn ParseOptions::for_profile(
  profile : @token.DorisProfile,
  mode : ParseMode,
) -> ParseOptions {
  { profile_context: @token.ValidatedProfileContext::canonical(profile), mode: mode, limits: ParseLimits::default() }
}
pub fn ParseOptions::for_profile_with_limits(
  profile : @token.DorisProfile,
  mode : ParseMode,
  limits : ParseLimits,
) -> ParseOptions {
  { profile_context: @token.ValidatedProfileContext::canonical(profile), mode: mode, limits: limits }
}

pub fn ParseOptions::profile(self : ParseOptions) -> @token.DorisProfile {
  self.profile_context.profile()
}

pub fn ParseOptions::profile_metadata(self : ParseOptions) -> @token.ProfileMetadata {
  self.profile_context.metadata()
}

pub fn ParseOptions::mode(self : ParseOptions) -> ParseMode {
  self.mode
}

pub fn ParseOptions::limits(self : ParseOptions) -> ParseLimits {
  self.limits
}

fn validate_limits(limits : ParseLimits) -> Result[Unit, ParseError] {
  let parser_limits = @parser.ParserLimits::new(
    limits.max_bytes,
    limits.max_tokens,
    limits.max_recursion_depth,
    limits.max_recovery_steps,
    limits.max_diagnostics,
  )
  match parser_limits.validate() {
    Ok(_) => Ok(())
    Err(@parser.ParserLimitError::MaxBytes(value)) => Err(InvalidLimit(limit_name="max_bytes", value=value))
    Err(@parser.ParserLimitError::MaxTokens(value)) => Err(InvalidLimit(limit_name="max_tokens", value=value))
    Err(@parser.ParserLimitError::MaxRecursionDepth(value)) => Err(InvalidLimit(limit_name="max_recursion_depth", value=value))
    Err(@parser.ParserLimitError::MaxRecoverySteps(value)) => Err(InvalidLimit(limit_name="max_recovery_steps", value=value))
    Err(@parser.ParserLimitError::MaxDiagnostics(value)) => Err(InvalidLimit(limit_name="max_diagnostics", value=value))
  }
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
  pub statement_id : UInt
}

pub struct ParseResult {
  pub schema_version : String
  pub source_transport : String
  pub profile : String
  pub exact_release : String
  pub feature_introduction : String
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
    @syntax.SyntaxKind::Insert => "insert"
    @syntax.SyntaxKind::Update => "update"
    @syntax.SyntaxKind::Delete => "delete"
    @syntax.SyntaxKind::Merge => "merge"
    @syntax.SyntaxKind::ValueList => "value_list"
    @syntax.SyntaxKind::CreateTable => "create_table"
    @syntax.SyntaxKind::CreateView => "create_view"
    @syntax.SyntaxKind::CreateIndex => "create_index"
    @syntax.SyntaxKind::CreateMaterializedView => "create_materialized_view"
    @syntax.SyntaxKind::ColumnDefinition => "column_definition"
    @syntax.SyntaxKind::KeyClause => "key_clause"
    @syntax.SyntaxKind::DistributionClause => "distribution_clause"
    @syntax.SyntaxKind::PartitionClause => "partition_clause"
    @syntax.SyntaxKind::PropertyList => "property_list"
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
  let limits = options.limits
  match validate_limits(limits) { Ok(_) => (); Err(error) => return Err(error) }
  let source = match @source.SourceText::new_with_limit(raw, limits.max_bytes) {
    Ok(source) => source
    Err(@source.SourceError::InputTooLarge(requested_bytes~, max_bytes~)) => return Err(InputTooLarge(requested_bytes~, max_bytes~))
  }
  let parser_mode = match options.mode {
    ParseMode::Strict => @parser.ParseMode::Strict
    ParseMode::Editor => @parser.ParseMode::Editor
  }
  let parser_limits = @parser.ParserLimits::new(
    limits.max_bytes,
    limits.max_tokens,
    limits.max_recursion_depth,
    limits.max_recovery_steps,
    limits.max_diagnostics,
  )
  let parsed = @parser.parse_with_limits_context(source, options.profile_context, parser_mode, parser_limits)
  if !parsed.root.is_valid(source.byte_length()) { return Err(InvalidSyntaxTree) }
  let diagnostics : Array[PrimitiveDiagnostic] = []
  for diagnostic in parsed.diagnostics {
    diagnostics.push(primitive_diagnostic(diagnostic))
  }
  Ok({
    schema_version: "doris.parse.v1",
    source_transport: "inline-root-v1",
    profile: options.profile().id(),
    exact_release: options.profile_metadata().exact_release,
    feature_introduction: options.profile_metadata().feature_introduction,
    mode: mode_id(options.mode),
    valid: parsed.valid,
    recovered: parsed.recovered,
    source_bytes: source.bytes(),
    source_byte_length: source.byte_length(),
    root: primitive_node(parsed.root),
    diagnostics: diagnostics,
  })
}

pub fn parse_with_metadata(
  raw : Bytes,
  profile_id : String,
  exact_release : String,
  feature_introduction : String,
  mode_id_value : String,
) -> Result[ParseResult, ParseError] {
  let options = match ParseOptions::from_manifest(profile_id, exact_release, feature_introduction, mode_id_value) {
    Ok(options) => options
    Err(error) => return Err(error)
  }
  parse(raw, options)
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

/// Statement-level entry (D-23): statement ids are assigned in source order to
/// content segments, so the id-th Statement node in `root.children` is the
/// requested statement. Children that are not Statement nodes (trivia-only
/// segments between semicolons, skipped resource tails) never consume an id.
/// Returns None when `statement_id` does not exist (including empty documents).
pub fn ParseResult::statement(self : ParseResult, statement_id : UInt) -> PrimitiveNode? {
  let mut seen : UInt = 0U
  for child in self.root.children {
    if child.kind == "statement" {
      if seen == statement_id {
        return Some(child)
      }
      seen = seen + 1U
    }
  }
  None
}

/// Statement-level diagnostics (D-23): the diagnostics of one statement,
/// filtered by `statement_id` in source/emission order — the DORIS-03 path
/// ("invalid statement does not discard later statements") is directly
/// consumable per statement.
pub fn ParseResult::statement_diagnostics(self : ParseResult, statement_id : UInt) -> Array[PrimitiveDiagnostic] {
  let out : Array[PrimitiveDiagnostic] = []
  for diagnostic in self.diagnostics {
    if diagnostic.statement_id == statement_id {
      out.push(diagnostic)
    }
  }
  out
}

pub fn ParseResult::all_spans_in_bounds(self : ParseResult) -> Bool {
  fn check(node : PrimitiveNode, length : Int, parent_start : Int, parent_end : Int) -> Bool {
    if node.text_len < 0 || node.text_len != node.end_byte - node.start_byte || node.start_byte < 0 || node.start_byte > node.end_byte || node.end_byte > length || node.start_byte < parent_start || node.end_byte > parent_end {
      false
    } else {
      let mut valid = true
      let mut previous_end = node.start_byte
      for child in node.children {
        if child.start_byte < previous_end || !check(child, length, node.start_byte, node.end_byte) {
          valid = false
        }
        previous_end = child.end_byte
      }
      valid
    }
  }
  check(self.root, self.source_byte_length, 0, self.source_byte_length)
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
  assert_eq(first.diagnostics[0].statement_id, 0U)
  assert_eq(second.diagnostics[0].statement_id, 0U)
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
  assert_eq(result.diagnostics[0].statement_id, 0U)
  assert_eq(result.diagnostics[1].statement_id, 1U)
  assert_true(result.diagnostics[0].code.has_prefix("DORIS-PARSE-"))
  assert_true(result.diagnostics[1].code.has_prefix("DORIS-PARSE-"))
}
