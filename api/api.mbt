///|
/// Versioned primitive parse boundary. Source bytes are owned once by ParseResult.
pub(all) enum ParseMode {
  Strict
  Editor
}

///|
pub struct ParseLimits {
  max_bytes : Int
  max_tokens : Int
  max_recursion_depth : Int
  max_recovery_steps : Int
  max_diagnostics : Int
}

///|
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

///|
pub fn ParseLimits::new(
  max_bytes : Int,
  max_tokens : Int,
  max_recursion_depth : Int,
  max_recovery_steps : Int,
  max_diagnostics : Int,
) -> ParseLimits {
  {
    max_bytes,
    max_tokens,
    max_recursion_depth,
    max_recovery_steps,
    max_diagnostics,
  }
}

///|
pub struct ParseOptions {
  dialect_context : @dialect.DialectContext
  mode : ParseMode
  limits : ParseLimits
}

///|
pub enum ParseError {
  UnknownDialect(dialect_id~ : String)
  UnknownProfile(profile_id~ : String)
  UnknownMode(mode_id~ : String)
  ProfileMetadataMismatch(
    profile_id~ : String,
    expected_release~ : String,
    actual_release~ : String,
    expected_feature_introduction~ : String,
    actual_feature_introduction~ : String
  )
  UnsupportedFeatureIntroduction(feature_introduction~ : String)
  ConflictingSelection(selection_a~ : String, selection_b~ : String)
  InputTooLarge(requested_bytes~ : Int, max_bytes~ : Int)
  InvalidLimit(limit_name~ : String, value~ : Int)
  InvalidSyntaxTree
} derive(Eq, @debug.Debug)

///|
/// Validate the dialect FIRST, then the profile for that dialect (Pitfall 6,
/// T-09-05): unknown dialects are rejected before any profile lookup, and
/// flink is a legal dialect whose profiles are ALL rejected until Phase 10
/// (A1/OQ1). Missing/unknown/conflicting selections are structured errors —
/// never a silent default (D-01/D-02).
fn dialect_from_id(dialect_id : String) -> Result[@dialect.Dialect, ParseError] {
  match dialect_id {
    "doris" => Ok(@dialect.Dialect::Doris)
    "flink" => Ok(@dialect.Dialect::Flink)
    _ => Err(UnknownDialect(dialect_id~))
  }
}

///|
pub fn ParseOptions::new(
  dialect_id : String,
  profile_id : String,
  mode_id : String,
) -> Result[ParseOptions, ParseError] {
  let dialect = match dialect_from_id(dialect_id) {
    Ok(dialect) => dialect
    Err(error) => return Err(error)
  }
  let dialect_context : @dialect.DialectContext = match dialect {
    @dialect.Dialect::Doris => {
      let profile = match @dialect.DorisProfile::from_id(profile_id) {
        Some(profile) => profile
        None => return Err(UnknownProfile(profile_id~))
      }
      let metadata = profile.metadata()
      {
        dialect,
        profile_id,
        exact_release: metadata.exact_release,
        feature_introduction: metadata.feature_introduction,
      }
    }
    @dialect.Dialect::Flink => {
      let profile = match @dialect.FlinkProfile::from_id(profile_id) {
        Some(profile) => profile
        None => return Err(UnknownProfile(profile_id~))
      }
      let metadata = profile.metadata()
      {
        dialect,
        profile_id,
        exact_release: metadata.exact_release,
        feature_introduction: metadata.feature_introduction,
      }
    }
  }
  let mode = match mode_id {
    "strict" => ParseMode::Strict
    "editor" => ParseMode::Editor
    _ => return Err(UnknownMode(mode_id~))
  }
  Ok({ dialect_context, mode, limits: ParseLimits::default() })
}

///|
pub fn ParseOptions::for_profile_with_metadata(
  profile : @dialect.DorisProfile,
  metadata : @dialect.ProfileMetadata,
  mode : ParseMode,
) -> Result[ParseOptions, ParseError] {
  let context = match profile.validate_metadata(metadata) {
    Ok(context) => context
    Err(
      @dialect.ProfileMetadataError::ProfileMetadataMismatch(
        profile_id~,
        expected_release~,
        actual_release~,
        expected_feature_introduction~,
        actual_feature_introduction~
      )
    ) =>
      return Err(
        ProfileMetadataMismatch(
          profile_id~,
          expected_release~,
          actual_release~,
          expected_feature_introduction~,
          actual_feature_introduction~,
        ),
      )
    Err(
      @dialect.ProfileMetadataError::UnsupportedFeatureIntroduction(
        feature_introduction~
      )
    ) => return Err(UnsupportedFeatureIntroduction(feature_introduction~))
    Err(@dialect.ProfileMetadataError::UnknownProfile(profile_id~)) =>
      return Err(UnknownProfile(profile_id~))
  }
  Ok({
    dialect_context: (
      {
        dialect: @dialect.Dialect::Doris,
        profile_id: context.profile().id(),
        exact_release: context.metadata().exact_release,
        feature_introduction: context.metadata().feature_introduction,
      } : @dialect.DialectContext),
    mode,
    limits: ParseLimits::default(),
  })
}

///|
pub fn ParseOptions::from_manifest(
  dialect_id : String,
  profile_id : String,
  exact_release : String,
  feature_introduction : String,
  mode_id : String,
) -> Result[ParseOptions, ParseError] {
  let dialect = match dialect_from_id(dialect_id) {
    Ok(dialect) => dialect
    Err(error) => return Err(error)
  }
  let mode = match mode_id {
    "strict" => ParseMode::Strict
    "editor" => ParseMode::Editor
    _ => return Err(UnknownMode(mode_id~))
  }
  let dialect_context : @dialect.DialectContext = match dialect {
    @dialect.Dialect::Doris =>
      match
        @dialect.ProfileMetadata::for_manifest(
          profile_id, exact_release, feature_introduction,
        ) {
        Ok(_) => { dialect, profile_id, exact_release, feature_introduction }
        Err(@dialect.ProfileMetadataError::UnknownProfile(profile_id~)) =>
          return Err(UnknownProfile(profile_id~))
        Err(
          @dialect.ProfileMetadataError::ProfileMetadataMismatch(
            profile_id~,
            expected_release~,
            actual_release~,
            expected_feature_introduction~,
            actual_feature_introduction~
          )
        ) =>
          return Err(
            ProfileMetadataMismatch(
              profile_id~,
              expected_release~,
              actual_release~,
              expected_feature_introduction~,
              actual_feature_introduction~,
            ),
          )
        Err(
          @dialect.ProfileMetadataError::UnsupportedFeatureIntroduction(
            feature_introduction~
          )
        ) => return Err(UnsupportedFeatureIntroduction(feature_introduction~))
      }
    @dialect.Dialect::Flink =>
      return Err(
        ConflictingSelection(
          selection_a="doris manifest",
          selection_b="flink dialect",
        ),
      )
  }
  Ok({ dialect_context, mode, limits: ParseLimits::default() })
}

///|
pub fn ParseOptions::for_profile(
  profile : @dialect.DorisProfile,
  mode : ParseMode,
) -> ParseOptions {
  let metadata = profile.metadata()
  {
    dialect_context: {
      dialect: @dialect.Dialect::Doris,
      profile_id: profile.id(),
      exact_release: metadata.exact_release,
      feature_introduction: metadata.feature_introduction,
    },
    mode,
    limits: ParseLimits::default(),
  }
}

///|
pub fn ParseOptions::for_profile_with_limits(
  profile : @dialect.DorisProfile,
  mode : ParseMode,
  limits : ParseLimits,
) -> ParseOptions {
  let metadata = profile.metadata()
  {
    dialect_context: {
      dialect: @dialect.Dialect::Doris,
      profile_id: profile.id(),
      exact_release: metadata.exact_release,
      feature_introduction: metadata.feature_introduction,
    },
    mode,
    limits,
  }
}

///|
/// The Doris profile this context resolves to, or None when the context is
/// not a Doris context (flink) or its profile_id does not resolve — never a
/// silently fabricated default (D-01, MI-01). All public constructors
/// validate a Doris profile for Doris contexts, so None is reachable only
/// through an externally-constructed pub(all) DialectContext.
pub fn ParseOptions::profile(self : ParseOptions) -> @dialect.DorisProfile? {
  @dialect.DorisProfile::from_id(self.dialect_context.profile_id)
}

///|
/// Profile metadata for the Doris context. Panics on a context without a
/// resolvable Doris profile — the explicit failure replaces the removed
/// silent V4_X fabrication (MI-01); unreachable through public constructors.
pub fn ParseOptions::profile_metadata(
  self : ParseOptions,
) -> @dialect.ProfileMetadata {
  match self.profile() {
    Some(profile) => profile.metadata()
    None => panic()
  }
}

///|
/// The Flink profile this context resolves to, or None when the context is
/// not a Flink context (doris) or its profile_id does not resolve — never a
/// silently fabricated default (D-01, T-10-01). All public constructors
/// validate a Flink profile for Flink contexts, so None is reachable only
/// through an externally-constructed pub(all) DialectContext.
pub fn ParseOptions::flink_profile(
  self : ParseOptions,
) -> @dialect.FlinkProfile? {
  @dialect.FlinkProfile::from_id(self.dialect_context.profile_id)
}

///|
/// FlinkProfileMetadata for the Flink context (D-01/D-02). Panics on a
/// context without a resolvable Flink profile — the explicit failure mirrors
/// profile_metadata; unreachable through public constructors. The wire
/// (fathom.dialect.v1 / fathom.capabilities.v1) reads calcite_version and
/// parser_config only through this accessor (T-09-18 provenance discipline —
/// nothing fabricated).
pub fn ParseOptions::flink_profile_metadata(
  self : ParseOptions,
) -> @dialect.FlinkProfileMetadata {
  match self.flink_profile() {
    Some(profile) => profile.metadata()
    None => panic()
  }
}

///|
/// The dialect selection's exact release string (DIALECT-04, D-09): taken
/// from the validated DialectContext, dialect-agnostic — the same source the
/// parse envelope's exact_release field uses. Replaces the Doris-only
/// profile_metadata().exact_release path on the format wire so a Flink
/// selection never panics profile_metadata (T-10-05).
pub fn ParseOptions::exact_release(self : ParseOptions) -> String {
  self.dialect_context.exact_release
}

///|
/// The dialect selection's canonical id ("doris" | "flink") — the wire
/// identity carried by ParseResult.dialect (DIALECT-04, D-09).
pub fn ParseOptions::dialect_id(self : ParseOptions) -> String {
  match self.dialect_context.dialect {
    @dialect.Dialect::Doris => "doris"
    @dialect.Dialect::Flink => "flink"
  }
}

///|
pub fn ParseOptions::mode(self : ParseOptions) -> ParseMode {
  self.mode
}

///|
pub fn ParseOptions::limits(self : ParseOptions) -> ParseLimits {
  self.limits
}

///|
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
    Err(@parser.ParserLimitError::MaxBytes(value)) =>
      Err(InvalidLimit(limit_name="max_bytes", value~))
    Err(@parser.ParserLimitError::MaxTokens(value)) =>
      Err(InvalidLimit(limit_name="max_tokens", value~))
    Err(@parser.ParserLimitError::MaxRecursionDepth(value)) =>
      Err(InvalidLimit(limit_name="max_recursion_depth", value~))
    Err(@parser.ParserLimitError::MaxRecoverySteps(value)) =>
      Err(InvalidLimit(limit_name="max_recovery_steps", value~))
    Err(@parser.ParserLimitError::MaxDiagnostics(value)) =>
      Err(InvalidLimit(limit_name="max_diagnostics", value~))
  }
}

///|
pub struct PrimitiveNode {
  kind : String
  start_byte : Int
  end_byte : Int
  text_len : Int
  children : Array[PrimitiveNode]
}

///|
pub struct PrimitiveDiagnostic {
  severity : String
  code : String
  message : String
  expected_class : String
  start_byte : Int
  end_byte : Int
  statement_id : UInt
}

///|
pub struct ParseResult {
  schema_version : String
  source_transport : String
  dialect : String
  profile : String
  exact_release : String
  feature_introduction : String
  mode : String
  valid : Bool
  recovered : Bool
  source_bytes : Bytes
  source_byte_length : Int
  root : PrimitiveNode
  diagnostics : Array[PrimitiveDiagnostic]
}

///|
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
    @syntax.SyntaxKind::ShowStatement => "show_statement"
    @syntax.SyntaxKind::DescribeStatement => "describe_statement"
    @syntax.SyntaxKind::ExplainStatement => "explain_statement"
    @syntax.SyntaxKind::AnalyzeStatement => "analyze_statement"
    @syntax.SyntaxKind::CreateCatalog => "create_catalog"
    @syntax.SyntaxKind::CreateDatabase => "create_database"
    @syntax.SyntaxKind::CreateFunction => "create_function"
    @syntax.SyntaxKind::DropCatalog => "drop_catalog"
    @syntax.SyntaxKind::DropDatabase => "drop_database"
    @syntax.SyntaxKind::DropTable => "drop_table"
    @syntax.SyntaxKind::DropView => "drop_view"
    @syntax.SyntaxKind::DropFunction => "drop_function"
    @syntax.SyntaxKind::AlterTable => "alter_table"
    @syntax.SyntaxKind::WatermarkClause => "watermark_clause"
    @syntax.SyntaxKind::ComputedColumn => "computed_column"
    @syntax.SyntaxKind::MetadataColumn => "metadata_column"
    @syntax.SyntaxKind::PrimaryKeyClause => "primary_key_clause"
    @syntax.SyntaxKind::TableLikeClause => "table_like_clause"
    @syntax.SyntaxKind::WindowTvf => "window_tvf"
    @syntax.SyntaxKind::MatchRecognize => "match_recognize"
    @syntax.SyntaxKind::SetOption => "set_option"
    @syntax.SyntaxKind::UseStatement => "use_statement"
    @syntax.SyntaxKind::TruncateTable => "truncate_table"
    @syntax.SyntaxKind::DropIndex => "drop_index"
    @syntax.SyntaxKind::LoadStatement => "load_statement"
    @syntax.SyntaxKind::ExportStatement => "export_statement"
    @syntax.SyntaxKind::GrantStatement => "grant_statement"
    @syntax.SyntaxKind::RevokeStatement => "revoke_statement"
    @syntax.SyntaxKind::BeginTransaction => "begin_transaction"
  }
}

///|
fn primitive_node(node : @syntax.SyntaxNode) -> PrimitiveNode {
  let children : Array[PrimitiveNode] = []
  for child in node.children() {
    match child {
      @syntax.SyntaxElement::ChildNode(child_node) =>
        children.push(primitive_node(child_node))
      @syntax.SyntaxElement::Leaf(leaf) => {
        let kind = match leaf.kind {
          @syntax.LeafKind::SourceToken => "token"
          @syntax.LeafKind::SourceTrivia => "trivia"
          @syntax.LeafKind::SourceError => "error"
          @syntax.LeafKind::SourceSkipped => "skipped"
        }
        children.push({
          kind,
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
    children,
  }
}

///|
fn primitive_diagnostic(
  diagnostic : @parser.ParserDiagnostic,
) -> PrimitiveDiagnostic {
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

///|
fn mode_id(mode : ParseMode) -> String {
  match mode {
    ParseMode::Strict => "strict"
    ParseMode::Editor => "editor"
  }
}

///|
pub fn parse(
  raw : Bytes,
  options : ParseOptions,
) -> Result[ParseResult, ParseError] {
  let limits = options.limits
  match validate_limits(limits) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let source = match @source.SourceText::new_with_limit(raw, limits.max_bytes) {
    Ok(source) => source
    Err(@source.SourceError::InputTooLarge(requested_bytes~, max_bytes~)) =>
      return Err(InputTooLarge(requested_bytes~, max_bytes~))
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
  let parsed = @parser.parse_with_limits_context(
    source,
    options.dialect_context,
    parser_mode,
    parser_limits,
  )
  if !parsed.root.is_valid(source.byte_length()) {
    return Err(InvalidSyntaxTree)
  }
  let diagnostics : Array[PrimitiveDiagnostic] = []
  for diagnostic in parsed.diagnostics {
    diagnostics.push(primitive_diagnostic(diagnostic))
  }
  Ok({
    schema_version: "fathom.parse.v1",
    source_transport: "inline-root-v1",
    dialect: options.dialect_id(),
    profile: options.dialect_context.profile_id,
    exact_release: options.dialect_context.exact_release,
    feature_introduction: options.dialect_context.feature_introduction,
    mode: mode_id(options.mode),
    valid: parsed.valid,
    recovered: parsed.recovered,
    source_bytes: source.bytes(),
    source_byte_length: source.byte_length(),
    root: primitive_node(parsed.root),
    diagnostics,
  })
}

///|
pub fn parse_with_metadata(
  raw : Bytes,
  dialect_id : String,
  profile_id : String,
  exact_release : String,
  feature_introduction : String,
  mode_id_value : String,
) -> Result[ParseResult, ParseError] {
  let options = match
    ParseOptions::from_manifest(
      dialect_id, profile_id, exact_release, feature_introduction, mode_id_value,
    ) {
    Ok(options) => options
    Err(error) => return Err(error)
  }
  parse(raw, options)
}

///|
pub fn parse_with_ids(
  raw : Bytes,
  dialect_id : String,
  profile_id : String,
  mode_id_value : String,
) -> Result[ParseResult, ParseError] {
  let options = match ParseOptions::new(dialect_id, profile_id, mode_id_value) {
    Ok(options) => options
    Err(error) => return Err(error)
  }
  parse(raw, options)
}

///|
/// Flink-mode parse entry (DIALECT-03): a document whose dialect selection is
/// validated as `flink` parses through the real Flink grammar —
/// `parse_flink_segment` dispatches SELECT/WITH to `parse_flink_query` and
/// routes genuinely-unsupported statements to FATHOM-PARSE-007. This entry is
/// the parse half for document-context hosts (the LSP document path) whose
/// selection is flink. FATHOM-PARSE-008 is retired as of Phase 11 (D-06): the
/// code stays vacant and is never reused. `profile_id` is gated through
/// `FlinkProfile::from_id` — unknown profiles (e.g. the Doris-shaped `4.x`)
/// are rejected with `UnknownProfile` (FATHOM-SCHEMA-003 at the wire, matching
/// `validate_dialect_profile`), and known profiles populate
/// `exact_release`/`feature_introduction` from `FlinkProfileMetadata` rather
/// than carrying the raw profile string / empty metadata.
pub fn parse_flink(
  raw : Bytes,
  profile_id : String,
  mode_id_value : String,
) -> Result[ParseResult, ParseError] {
  let mode = match mode_id_value {
    "strict" => ParseMode::Strict
    "editor" => ParseMode::Editor
    _ => return Err(UnknownMode(mode_id=mode_id_value))
  }
  let profile = match @dialect.FlinkProfile::from_id(profile_id) {
    Some(profile) => profile
    None => return Err(UnknownProfile(profile_id~))
  }
  let metadata = profile.metadata()
  let context : @dialect.DialectContext = {
    dialect: @dialect.Dialect::Flink,
    profile_id,
    exact_release: metadata.exact_release,
    feature_introduction: metadata.feature_introduction,
  }
  parse(raw, { dialect_context: context, mode, limits: ParseLimits::default() })
}

// Formatter type re-exports (D-38): api is the shared Phase 4 LSP core entry,
// so @api.FormatOptions / @api.FormatResult etc. resolve through the facade.
// Type aliases compile on moon 0.1.20260724 (probe-verified).

///|
pub type FormatOptions = @formatter.FormatOptions

///|
pub type FormatResult = @formatter.FormatResult

///|
pub type FormatDiagnostic = @formatter.FormatDiagnostic

///|
pub type FormatError = @formatter.FormatError

///|
pub type KeywordCase = @formatter.KeywordCase

///|
pub type CommaStyle = @formatter.CommaStyle

///|
pub type NewlineStyle = @formatter.NewlineStyle

// Lint type re-exports (D-38, LINT-01): the api package is the shared core
// entry for the lint surface too, so @api.LintOptions / @api.LintResult etc.
// resolve through the facade (mirrors the formatter aliases above).

///|
pub type LintOptions = @lint.LintOptions

///|
pub type LintResult = @lint.LintResult

///|
pub type LintFinding = @lint.LintFinding

///|
pub type LintEdit = @lint.LintEdit

///|
pub type LintDiagnostic = @lint.LintDiagnostic

///|
pub type RuleOverride = @lint.RuleOverride

///|
pub type LintSeverity = @lint.LintSeverity

///|
pub type RuleSetting = @lint.RuleSetting

// Lineage type re-exports (D-38, LINE-01): the api package is the shared core
// entry for the lineage surface too, so @api.LineageResult / @api.LineageEdge
// etc. resolve through the facade (mirrors the formatter/lint aliases above)
// and binding (07-04) can construct its envelope from @api types without
// importing lineage/ directly (D-38 discipline).

///|
pub type LineageResult = @lineage.LineageResult

///|
pub type LineageEdge = @lineage.LineageEdge

///|
pub type LineageGap = @lineage.LineageGap

///|
pub type StaticCatalog = @analyzer.StaticCatalog

///|
/// Primitive-shaped formatting diagnostic converted from a parser diagnostic
/// (mirror of primitive_diagnostic above, same six fields).
fn format_diagnostic(diagnostic : @parser.ParserDiagnostic) -> FormatDiagnostic {
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

///|
/// Shared core format entry (D-38): one internal parse mirroring `parse`, then
/// the formatter over the in-memory SyntaxNode. Parse diagnostics are converted
/// to FormatDiagnostic shape and prepended so a refusal never masks parse
/// errors (threat T-03-01). UnknownProfile / InputTooLarge / InvalidSyntaxTree
/// propagate as ParseError exactly like `parse`.
pub fn format_text(
  raw : Bytes,
  parse_options : ParseOptions,
  format_options : FormatOptions,
) -> Result[FormatResult, ParseError] {
  let limits = parse_options.limits
  match validate_limits(limits) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let source = match @source.SourceText::new_with_limit(raw, limits.max_bytes) {
    Ok(source) => source
    Err(@source.SourceError::InputTooLarge(requested_bytes~, max_bytes~)) =>
      return Err(InputTooLarge(requested_bytes~, max_bytes~))
  }
  let parser_mode = match parse_options.mode {
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
  let parsed = @parser.parse_with_limits_context(
    source,
    parse_options.dialect_context,
    parser_mode,
    parser_limits,
  )
  if !parsed.root.is_valid(source.byte_length()) {
    return Err(InvalidSyntaxTree)
  }
  let formatted = @formatter.format(
    parsed.root,
    source,
    format_options,
    parse_options.dialect_context,
  )
  let diagnostics : Array[FormatDiagnostic] = []
  for diagnostic in parsed.diagnostics {
    diagnostics.push(format_diagnostic(diagnostic))
  }
  for diagnostic in formatted.diagnostics {
    diagnostics.push(diagnostic)
  }
  Ok({
    accepted: formatted.accepted,
    output: formatted.output,
    diagnostics,
    statement_offsets: formatted.statement_offsets,
  })
}

///|
pub fn format_with_ids(
  raw : Bytes,
  dialect_id : String,
  profile_id : String,
  mode_id_value : String,
  format_options : FormatOptions,
) -> Result[FormatResult, ParseError] {
  let options = match ParseOptions::new(dialect_id, profile_id, mode_id_value) {
    Ok(options) => options
    Err(error) => return Err(error)
  }
  format_text(raw, options, format_options)
}

///|
pub fn format_with_metadata(
  raw : Bytes,
  dialect_id : String,
  profile_id : String,
  exact_release : String,
  feature_introduction : String,
  mode_id_value : String,
  format_options : FormatOptions,
) -> Result[FormatResult, ParseError] {
  let options = match
    ParseOptions::from_manifest(
      dialect_id, profile_id, exact_release, feature_introduction, mode_id_value,
    ) {
    Ok(options) => options
    Err(error) => return Err(error)
  }
  format_text(raw, options, format_options)
}

///|
/// Result of fingerprinting one document (D-08): the UInt64 fingerprint plus
/// the normalized canonical bytes it was computed from.
pub(all) struct FingerprintResult {
  fingerprint : UInt64
  normalized : Bytes
}

///|
/// Shared core fingerprint entry (FING-01, D-08): one internal parse mirroring
/// `format_text`, then `@fingerprint.normalize` over the in-memory SyntaxNode
/// and `@fingerprint.fnv1a64` over the canonical bytes. The fingerprint is a
/// total function over any parsed tree (empty/error material normalize to a
/// deterministic value) — semantically meaningful only on valid statements.
/// UnknownProfile / InputTooLarge / InvalidSyntaxTree propagate as ParseError
/// exactly like `parse`.
pub fn fingerprint_text(
  raw : Bytes,
  parse_options : ParseOptions,
) -> Result[FingerprintResult, ParseError] {
  let limits = parse_options.limits
  match validate_limits(limits) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let source = match @source.SourceText::new_with_limit(raw, limits.max_bytes) {
    Ok(source) => source
    Err(@source.SourceError::InputTooLarge(requested_bytes~, max_bytes~)) =>
      return Err(InputTooLarge(requested_bytes~, max_bytes~))
  }
  let parser_mode = match parse_options.mode {
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
  let parsed = @parser.parse_with_limits_context(
    source,
    parse_options.dialect_context,
    parser_mode,
    parser_limits,
  )
  if !parsed.root.is_valid(source.byte_length()) {
    return Err(InvalidSyntaxTree)
  }
  let canonical = @fingerprint.normalize(
    parsed.root,
    source,
    parse_options.dialect_context,
  )
  Ok({ fingerprint: @fingerprint.fnv1a64(canonical), normalized: canonical })
}

///|
/// Shared internal parse for the analysis entry points (lint/fix). Mirrors the
/// parse half of `format_text`/`fingerprint_text`: validate_limits ->
/// SourceText::new_with_limit -> parse_with_limits_context -> is_valid gate.
/// UnknownProfile / InputTooLarge / InvalidSyntaxTree propagate as ParseError.
fn parse_document(
  raw : Bytes,
  parse_options : ParseOptions,
) -> Result[(@parser.ParsedDocument, @source.SourceText), ParseError] {
  let limits = parse_options.limits
  match validate_limits(limits) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let source = match @source.SourceText::new_with_limit(raw, limits.max_bytes) {
    Ok(source) => source
    Err(@source.SourceError::InputTooLarge(requested_bytes~, max_bytes~)) =>
      return Err(InputTooLarge(requested_bytes~, max_bytes~))
  }
  let parser_mode = match parse_options.mode {
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
  let parsed = @parser.parse_with_limits_context(
    source,
    parse_options.dialect_context,
    parser_mode,
    parser_limits,
  )
  if !parsed.root.is_valid(source.byte_length()) {
    return Err(InvalidSyntaxTree)
  }
  Ok((parsed, source))
}

///|
/// Shared core lint entry (LINT-01, D-04/D-06): one internal parse, then
/// `@lint.run_rules` over the in-memory SyntaxNode. Report mode: findings list
/// (sorted, stable). No catalog is injected here, so analyzer-backed rules
/// (004-007) are silently skipped (ANLY-01, Pitfall 6) — the wire/CLI surface
/// never fabricates semantic findings.
pub fn lint_text(
  raw : Bytes,
  parse_options : ParseOptions,
  lint_options : LintOptions,
) -> Result[LintResult, ParseError] {
  let (parsed, source) = match parse_document(raw, parse_options) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let findings = @lint.run_rules(
    parsed.root,
    source,
    parse_options.dialect_context,
    None,
    lint_options,
  )
  Ok({ accepted: true, findings, output: b"", diagnostics: [] })
}

///|
/// Shared core autofix entry (LINT-01, D-03): one internal parse, then
/// `@lint.apply_fixes` (minimal span edits + D-33 refusal gate). On success the
/// fixed output is REPARSED as a round-trip defense (D-03); if the fixed output
/// does not reparse clean (structurally invalid or still containing
/// error/missing/skipped material), the fix is refused with a FATHOM-LINT-000
/// diagnostic — never partial or unsafe output.
pub fn fix_text(
  raw : Bytes,
  parse_options : ParseOptions,
  lint_options : LintOptions,
) -> Result[LintResult, ParseError] {
  let (parsed, source) = match parse_document(raw, parse_options) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let findings = @lint.run_rules(
    parsed.root,
    source,
    parse_options.dialect_context,
    None,
    lint_options,
  )
  let result = @lint.apply_fixes(
    parsed.root,
    source,
    parse_options.dialect_context,
    findings,
    lint_options,
  )
  if !result.accepted {
    return Ok(result) // D-33 refusal already emitted by apply_fixes
  }
  let fixed = match parse_document(result.output, parse_options) {
    Ok((fixed_parsed, _)) => fixed_parsed
    Err(_) =>
      return Ok(refusal_result("autofix output did not reparse cleanly"))
  }
  if @formatter.first_unsafe_element(fixed.root) is Some(_) {
    return Ok(
      refusal_result(
        "autofix output still contains error/missing/skipped material",
      ),
    )
  }
  Ok(result)
}

///|
/// Shared core lineage entry (LINE-01, D-07): one internal parse mirroring
/// `lint_text` via `parse_document`, then `@lineage.derive_lineage` over the
/// in-memory SyntaxNode. UnknownProfile / InputTooLarge / InvalidSyntaxTree
/// propagate as ParseError exactly like `lint_text`/`format_text`.
///
/// Flink gate (D-08): lineage is Doris-only this phase. A flink selection is
/// rejected AFTER a successful parse with a structured UnknownProfile
/// ParseError (FATHOM-SCHEMA family) — never a silent empty result. The
/// explicit "lineage is Doris-only" message is the wire/CLI boundary's job
/// (07-04).
///
/// Optional catalog (D-05 / T-02-42): `Some(catalog)` injects caller-owned
/// metadata so `*`/`table.*` expand to real edges and external views resolve;
/// `None` derives with zero metadata so every unexpanded star/external view
/// reports a requires-catalog gap (SC2) — never a fabricated edge. The
/// catalog never touches the syntax valid/diagnostic channel (ANLY-01).
///
/// Pure function: the same (raw, parse_options, catalog) re-run yields
/// byte-identical edges/gaps (LINE-01 idempotency); no shared state.
pub fn lineage_text(
  raw : Bytes,
  parse_options : ParseOptions,
  catalog : @analyzer.StaticCatalog?,
) -> Result[LineageResult, ParseError] {
  let (parsed, source) = match parse_document(raw, parse_options) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if parse_options.dialect_id() == "flink" {
    return Err(
      UnknownProfile(profile_id=parse_options.dialect_context.profile_id),
    )
  }
  let result = match catalog {
    Some(catalog) =>
      @lineage.derive_lineage(parsed.root, source.bytes(), catalog)
    None => @lineage.derive_lineage_without_catalog(parsed.root, source.bytes())
  }
  Ok(result)
}

///|
/// Engine-level refusal LintResult (D-33): accepted=false, empty output,
/// exactly one FATHOM-LINT-000 diagnostic.
fn refusal_result(message : String) -> LintResult {
  {
    accepted: false,
    findings: [],
    output: b"",
    diagnostics: [
      {
        code: "FATHOM-LINT-000",
        message,
        start_byte: 0,
        end_byte: 0,
        statement_id: 0U,
      },
    ],
  }
}

///|
pub fn ParseResult::has_root_only_source(self : ParseResult) -> Bool {
  self.source_byte_length == self.source_bytes.length()
}

///|
/// Statement-level entry (D-23): statement ids are assigned in source order to
/// content segments, so the id-th Statement node in `root.children` is the
/// requested statement. Children that are not Statement nodes (trivia-only
/// segments between semicolons, skipped resource tails) never consume an id.
/// Returns None when `statement_id` does not exist (including empty documents).
pub fn ParseResult::statement(
  self : ParseResult,
  statement_id : UInt,
) -> PrimitiveNode? {
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

///|
/// Statement-level diagnostics (D-23): the diagnostics of one statement,
/// filtered by `statement_id` in source/emission order — the DORIS-03 path
/// ("invalid statement does not discard later statements") is directly
/// consumable per statement.
pub fn ParseResult::statement_diagnostics(
  self : ParseResult,
  statement_id : UInt,
) -> Array[PrimitiveDiagnostic] {
  let out : Array[PrimitiveDiagnostic] = []
  for diagnostic in self.diagnostics {
    if diagnostic.statement_id == statement_id {
      out.push(diagnostic)
    }
  }
  out
}

///|
pub fn ParseResult::all_spans_in_bounds(self : ParseResult) -> Bool {
  fn check(
    node : PrimitiveNode,
    length : Int,
    parent_start : Int,
    parent_end : Int,
  ) -> Bool {
    if node.text_len < 0 ||
      node.text_len != node.end_byte - node.start_byte ||
      node.start_byte < 0 ||
      node.start_byte > node.end_byte ||
      node.end_byte > length ||
      node.start_byte < parent_start ||
      node.end_byte > parent_end {
      false
    } else {
      let mut valid = true
      let mut previous_end = node.start_byte
      for child in node.children {
        if child.start_byte < previous_end ||
          !check(child, length, node.start_byte, node.end_byte) {
          valid = false
        }
        previous_end = child.end_byte
      }
      valid
    }
  }
  check(self.root, self.source_byte_length, 0, self.source_byte_length)
}

///|
test "api_requires_explicit_dialect_profile_and_mode" {
  // DIALECT-01 / Pitfall 6: dialect is validated FIRST, then profile.
  assert_true(
    ParseOptions::new("mysql", "4.x", "strict") is Err(UnknownDialect(..)),
  )
  assert_true(
    ParseOptions::new("doris", "mysql", "strict") is Err(UnknownProfile(..)),
  )
  // flink is a legal dialect; Phase 10 accepts exactly the three pinned
  // release profiles (exact-match only — no prefix/suffix/version-compare,
  // no Doris profile borrowing, T-10-01). flink-2.3.0 resolves; the
  // Doris-shaped "2.1" and the adjacent "flink-2.3.0-rc1" are rejected.
  let flink_options = match
    ParseOptions::new("flink", "flink-2.3.0", "strict") {
    Ok(options) => options
    Err(_) => panic()
  }
  assert_eq(flink_options.dialect_id(), "flink")
  assert_eq(flink_options.flink_profile(), Some(@dialect.FlinkProfile::V2_3_0))
  assert_eq(flink_options.flink_profile_metadata().calcite_version, "1.36.0")
  assert_eq(flink_options.exact_release(), "flink-2.3.0")
  assert_true(
    ParseOptions::new("flink", "2.1", "strict") is Err(UnknownProfile(..)),
  )
  assert_true(
    ParseOptions::new("flink", "flink-2.3.0-rc1", "strict")
    is Err(UnknownProfile(..)),
  )
  assert_true(
    ParseOptions::new("flink", "flink-2.3", "strict") is Err(UnknownProfile(..)),
  )
  assert_true(
    ParseOptions::new("doris", "4.x", "unknown") is Err(UnknownMode(..)),
  )
  let options = match ParseOptions::new("doris", "2.1", "editor") {
    Ok(options) => options
    Err(_) => panic()
  }
  // MI-01: profile() is an Option — no silent V4_X fabrication for a
  // context whose profile_id does not resolve.
  assert_eq(options.profile(), Some(@dialect.DorisProfile::V2_1))
  assert_eq(options.dialect_id(), "doris")
  assert_true(options.mode() is ParseMode::Editor)
}

///|
test "api_parse_flink_gates_profiles_and_carries_metadata" {
  // MN-04 + D-06: the LSP document path's flink parse entry gates the profile
  // through FlinkProfile::from_id and populates exact_release/
  // feature_introduction from FlinkProfileMetadata. Phase 11 retires
  // FATHOM-PARSE-008: a valid pinned-profile SELECT now parses to the real
  // Flink grammar (valid=true, zero diagnostics), and an unknown (Doris-shaped
  // or adjacent) profile is rejected with UnknownProfile (FATHOM-SCHEMA-003 at
  // the wire, matching validate_dialect_profile).
  let ok = match parse_flink(b"SELECT 1", "flink-2.3.0", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(ok.dialect, "flink")
  assert_eq(ok.profile, "flink-2.3.0")
  assert_eq(ok.exact_release, "flink-2.3.0")
  assert_eq(ok.feature_introduction, "primary profile")
  assert_true(ok.valid)
  assert_eq(ok.diagnostics.length(), 0)
  assert_true(
    parse_flink(b"SELECT 1", "4.x", "strict")
    is Err(UnknownProfile(profile_id="4.x")),
  )
  assert_true(
    parse_flink(b"SELECT 1", "flink-2.3", "strict")
    is Err(UnknownProfile(profile_id="flink-2.3")),
  )
  assert_true(
    parse_flink(b"SELECT 1", "flink-2.3.0", "turbo")
    is Err(UnknownMode(mode_id="turbo")),
  )
}

///|
test "api_result_owns_source_once_and_has_bounded_descendant_spans" {
  let result = match parse_with_ids(b"SELECT x\r\n", "doris", "3.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(result.source_byte_length, 10)
  assert_true(result.has_root_only_source())
  assert_true(result.all_spans_in_bounds())
  assert_eq(result.diagnostics.length(), 0)
}

///|
test "api_diagnostics_have_stable_namespace_and_snapshot_local_ids" {
  let first = match parse_with_ids(b"bad", "doris", "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  let second = match parse_with_ids(b"bad", "doris", "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(first.diagnostics[0].code.has_prefix("FATHOM-PARSE-"))
  assert_eq(first.diagnostics[0].statement_id, 0U)
  assert_eq(second.diagnostics[0].statement_id, 0U)
}

///|
test "api_empty_input_has_no_synthetic_diagnostic_and_modes_share_shape" {
  let empty = match parse_with_ids(b"", "doris", "2.1", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(empty.source_byte_length, 0)
  assert_eq(empty.root.start_byte, 0)
  assert_eq(empty.root.end_byte, 0)
  assert_eq(empty.diagnostics.length(), 0)
  let strict = match parse_with_ids(b"SELECT", "doris", "3.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  let editor = match parse_with_ids(b"SELECT", "doris", "3.x", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(strict.root.kind, editor.root.kind)
  assert_eq(strict.root.text_len, editor.root.text_len)
  assert_true(!strict.recovered)
  assert_true(editor.recovered)
}

///|
test "api_diagnostic_statement_ids_are_monotonic_per_snapshot" {
  let result = match parse_with_ids(b"bad; bad", "doris", "4.x", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(result.diagnostics.length(), 2)
  assert_eq(result.diagnostics[0].statement_id, 0U)
  assert_eq(result.diagnostics[1].statement_id, 1U)
  assert_true(result.diagnostics[0].code.has_prefix("FATHOM-PARSE-"))
  assert_true(result.diagnostics[1].code.has_prefix("FATHOM-PARSE-"))
}

///|
test "api_lineage_text_doris_select_basic_ok" {
  // LINE-01 / D-07: a valid Doris 4.x SELECT with a catalog yields an Ok
  // LineageResult carrying the t.a -> a passthrough edge, no gaps.
  let options = match ParseOptions::new("doris", "4.x", "strict") {
    Ok(options) => options
    Err(_) => panic()
  }
  let catalog = @analyzer.StaticCatalog::new([
    { name: "t", columns: [{ name: "a", data_type: "INT" }] },
  ])
  let result = match lineage_text(b"SELECT a FROM t", options, Some(catalog)) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(result.edges.length(), 1)
  assert_eq(result.gaps.length(), 0)
  let edge = result.edges[0]
  assert_eq(edge.source_name, "a")
  assert_eq(edge.source_resolved_to, "a")
  assert_eq(edge.source_start_byte, 7)
  assert_eq(edge.source_end_byte, 8)
  assert_eq(edge.target_name, "a")
  assert_eq(edge.target_start_byte, 7)
  assert_eq(edge.target_end_byte, 8)
}

///|
test "api_lineage_text_flink_gate_structured_error" {
  // D-08: a flink selection is rejected with a structured UnknownProfile
  // ParseError (FATHOM-SCHEMA family) — NEVER a silent Ok(empty result).
  let options = match ParseOptions::new("flink", "flink-2.3.0", "strict") {
    Ok(options) => options
    Err(_) => panic()
  }
  let result = lineage_text(b"SELECT a FROM t", options, None)
  assert_true(result is Err(UnknownProfile(profile_id="flink-2.3.0")))
  match result {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}

///|
test "api_lineage_text_star_no_catalog_requires_catalog_gap" {
  // SC2 / D-05: `SELECT * FROM t` with no catalog -> zero edges and one
  // requires-catalog gap at the star span; never a fabricated edge.
  let options = match ParseOptions::new("doris", "4.x", "strict") {
    Ok(options) => options
    Err(_) => panic()
  }
  let result = match lineage_text(b"SELECT * FROM t", options, None) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(result.edges.length(), 0)
  assert_eq(result.gaps.length(), 1)
  assert_eq(result.gaps[0].code, "requires-catalog")
  assert_eq(result.gaps[0].start_byte, 7)
  assert_eq(result.gaps[0].end_byte, 8)
}

///|
test "api_lineage_text_input_too_large_parse_error" {
  // T-07-03-03 / parse_document precedent: oversized input is rejected with a
  // structured InputTooLarge ParseError before any derivation runs (mirrors
  // format_text / formatter_test boundary).
  let options = ParseOptions::for_profile_with_limits(
    @dialect.DorisProfile::V4_X,
    ParseMode::Strict,
    ParseLimits::new(8, 1000, 100, 100, 100),
  )
  let result = lineage_text(b"SELECT abcdefghijklmnopqrstuvwxyz", options, None)
  assert_true(result is Err(InputTooLarge(requested_bytes=_, max_bytes=8)))
}

///|
test "api_lineage_text_empty_document_ok_empty" {
  // FLAGGED ASSUMPTION (LINE-01 empty, RESOLVED): an empty document returns
  // Ok(LineageResult{edges:[], gaps:[]}) — accepted semantics, no synthetic gap.
  let options = match ParseOptions::new("doris", "4.x", "strict") {
    Ok(options) => options
    Err(_) => panic()
  }
  let result = match lineage_text(b"", options, None) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(result.edges.length(), 0)
  assert_eq(result.gaps.length(), 0)
}
