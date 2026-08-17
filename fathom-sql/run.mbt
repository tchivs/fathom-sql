/// Pure CLI logic home (D-37/D-38): maps a parsed Command plus stdin bytes to
/// an exact CliOutcome { exit_code, stdout, stderr } (D-39). This is the ONLY
/// logic in the CLI package — no format logic lives here; the single core call
/// is @api.format_with_ids (the shared Phase 4 LSP entry, D-38) for format and
/// @api.parse_with_ids for parse. Pure and moon-testable (D-40): no process
/// spawn, no shared state, no temp files — parallel or interrupted invocations
/// cannot corrupt each other. run_lsp delegates to the shared
/// @lsp.serve_stdio loop (single server implementation, T-09-15) with the
/// parsed dialect/profile as workspace defaults.

pub(all) struct CliOutcome {
  exit_code : Int
  stdout : Bytes
  stderr : Bytes
}

const DEFAULT_INDENT : Int = 2
const DEFAULT_LINE_WIDTH : Int = 100

/// D-39 exit mapping:
/// 0 = accepted — stdout carries the formatted SQL / serialized parse
///     envelope / (lsp) the server loop ran to completion, stderr empty;
/// 1 = parse failure or format refusal — stdout empty, diagnostics on stderr
///     (the api core prepends the parse diagnostics, so the FATHOM-FORMAT-001
///     refusal never masks them, T-03-20);
/// 2 = usage error (missing/unknown dialect, missing file, bad option value,
///     unknown profile) — stderr message only, no SQL output.
/// `--version` (VER-02/D-02/D-07): exit 0, stdout exactly
/// `"<name> <product_version>\n"`, empty stderr. The string comes from the
/// single source @version.version_line — the binary never carries a second
/// version constant.
pub fn run_version(name : String) -> CliOutcome {
  let bytes = @utf8.encode(@version.version_line(name))
  { exit_code: 0, stdout: bytes, stderr: b"" }
}

pub fn run_format(command : Command, stdin_bytes : Bytes) -> CliOutcome {
  let keyword_case = match command.keyword_case {
    Some(id) => match @api.KeywordCase::from_id(id) {
      Some(value) => value
      None => return bad_value("--keyword-case", id)
    }
    None => @api.KeywordCase::Upper
  }
  let comma_style = match command.comma_style {
    Some(id) => match @api.CommaStyle::from_id(id) {
      Some(value) => value
      None => return bad_value("--comma-style", id)
    }
    None => @api.CommaStyle::Trailing
  }
  let newline_style = match command.newline_style {
    Some(id) => match @api.NewlineStyle::from_id(id) {
      Some(value) => value
      None => return bad_value("--newline-style", id)
    }
    None => @api.NewlineStyle::FollowInput
  }
  let indent = match command.indent {
    Some(value) => value
    None => DEFAULT_INDENT
  }
  let line_width = match command.line_width {
    Some(value) => value
    None => DEFAULT_LINE_WIDTH
  }
  let format_options = match @api.FormatOptions::new(
    keyword_case,
    indent,
    line_width,
    comma_style,
    newline_style,
    command.trailing_newline,
  ) {
    Ok(options) => options
    Err(@api.FormatError::InvalidIndent(value~)) => {
      // Cap mirrors @formatter.MAX_INDENT (formatter/options.mbt) — WR-02.
      return usage_error("invalid --indent value: \{value} (expected 0..64)")
    }
    Err(@api.FormatError::InvalidLineWidth(value~)) => {
      return usage_error("invalid --line-width value: \{value} (expected a positive integer)")
    }
    Err(_) => return usage_error("internal format option error")
  }
  let input = match command.file {
    Some(path) if path != "-" => match read_file(path) {
      Some(bytes) => bytes
      None => return usage_error("cannot read file: \{path}")
    }
    _ => stdin_bytes
  }
  let result = match @api.format_with_ids(input, command.dialect, command.profile, "strict", format_options) {
    Ok(result) => result
    Err(error) => return parse_error_outcome(command.dialect, error)
  }
  if result.accepted {
    { exit_code: 0, stdout: result.output, stderr: b"" }
  } else {
    { exit_code: 1, stdout: b"", stderr: render_diagnostics(result.diagnostics) }
  }
}

/// Serialized parse envelope (fathom.parse.v1, D-09) on stdout, exit 0.
/// Parse failures exit 1 with the api core's structured diagnostics on
/// stderr; selection errors exit 2 via parse_error_outcome (defense-in-depth
/// — parse_args already validated dialect/profile).
pub fn run_parse(command : Command, stdin_bytes : Bytes) -> CliOutcome {
  let input = match command.file {
    Some(path) if path != "-" => match read_file(path) {
      Some(bytes) => bytes
      None => return usage_error("cannot read file: \{path}")
    }
    _ => stdin_bytes
  }
  let result = match @api.parse_with_ids(input, command.dialect, command.profile, "strict") {
    Ok(result) => result
    Err(error) => return parse_error_outcome(command.dialect, error)
  }
  {
    exit_code: 0,
    stdout: @utf8.encode(@binding.parse_result_json(result) + "\n"),
    stderr: b"",
  }
}

/// LSP subcommand: run the shared stdio server loop with the parsed
/// --dialect/--profile as workspace defaults (D-01 seam). The loop returns
/// only after the client's exit notification; exit 0.
pub fn run_lsp(command : Command) -> CliOutcome {
  @lsp.serve_stdio(Some(command.dialect), Some(command.profile))
  { exit_code: 0, stdout: b"", stderr: b"" }
}

/// Shared ParseOptions construction for the analysis subcommands
/// (lint/fingerprint): dialect-first validation (Pitfall 6, T-09-10). A
/// selection error maps to the D-39 parse_error_outcome (exit 2 for unknown
/// dialect/profile — defense-in-depth, parse_args already validated).
fn parse_options(command : Command) -> Result[@api.ParseOptions, CliOutcome] {
  match @api.ParseOptions::new(command.dialect, command.profile, "strict") {
    Ok(options) => Ok(options)
    Err(error) => Err(parse_error_outcome(command.dialect, error))
  }
}

/// D-39 lint exit mapping:
///   0 = no findings (report mode) OR all fixes applied + reparse clean
///       (--fix mode, accepted=true);
///   1 = findings rendered on stderr (report mode) OR D-33 refusal /
///       FATHOM-LINT-000 (--fix mode, accepted=false);
///   2 = usage/config error (invalid --rule value, unknown rule code).
pub fn run_lint(command : Command, stdin_bytes : Bytes) -> CliOutcome {
  let selection = match parse_options(command) {
    Ok(options) => options
    Err(outcome) => return outcome
  }
  let lint_options = match @api.LintOptions::new(command.overrides) {
    Ok(options) => options
    Err(_) => return usage_error("unknown rule code in --rule")
  }
  let input = match command.file {
    Some(path) if path != "-" => match read_file(path) {
      Some(bytes) => bytes
      None => return usage_error("cannot read file: \{path}")
    }
    _ => stdin_bytes
  }
  if command.fix {
    match @api.fix_text(input, selection, lint_options) {
      Ok(result) => {
        if result.accepted {
          { exit_code: 0, stdout: result.output, stderr: b"" }
        } else {
          { exit_code: 1, stdout: b"", stderr: render_lint_diagnostics(result.diagnostics) }
        }
      }
      Err(error) => parse_error_outcome(command.dialect, error)
    }
  } else {
    match @api.lint_text(input, selection, lint_options) {
      Ok(result) => {
        if result.findings.length() == 0 {
          { exit_code: 0, stdout: b"", stderr: b"" }
        } else {
          { exit_code: 1, stdout: b"", stderr: render_lint_findings(result.findings) }
        }
      }
      Err(error) => parse_error_outcome(command.dialect, error)
    }
  }
}

/// D-39 fingerprint exit mapping:
///   0 = success — stdout carries the UInt64 fingerprint as a DECIMAL STRING
///       (never a number form; 2^53 precision, Pitfall 3) plus, with
///       --normalized, the canonical text;
///   1 = parse failure — diagnostics on stderr;
///   2 = usage error.
pub fn run_fingerprint(command : Command, stdin_bytes : Bytes) -> CliOutcome {
  let selection = match parse_options(command) {
    Ok(options) => options
    Err(outcome) => return outcome
  }
  let input = match command.file {
    Some(path) if path != "-" => match read_file(path) {
      Some(bytes) => bytes
      None => return usage_error("cannot read file: \{path}")
    }
    _ => stdin_bytes
  }
  match @api.fingerprint_text(input, selection) {
    Ok(result) => {
      let out = @buffer.Buffer::Buffer(size_hint=64)
      out.write_bytes(@utf8.encode(result.fingerprint.to_string() + "\n"))
      if command.normalized {
        out.write_bytes(result.normalized)
        out.write_bytes(b"\n")
      }
      { exit_code: 0, stdout: out.to_bytes(), stderr: b"" }
    }
    Err(error) => parse_error_outcome(command.dialect, error)
  }
}

/// D-39 lineage exit mapping (LINE-01, D-07/D-08):
///   0 = success — stdout carries the fathom.lineage.v1 envelope
///       (dialect/profile/exact_release metadata + edges + gaps);
///   1 = parse failure — diagnostics on stderr;
///   2 = usage/config error — bad --catalog path, invalid catalog JSON
///       (FATHOM-SCHEMA-004), or a flink selection (lineage is Doris-only,
///       D-08) — stderr message only, no SQL output.
/// The CLI is a thin adapter (D-37/D-38): it calls @api.lineage_text and
/// serializes via @binding.lineage_result_json — no lineage logic lives here.
pub fn run_lineage(command : Command, stdin_bytes : Bytes) -> CliOutcome {
  let selection = match parse_options(command) {
    Ok(options) => options
    Err(outcome) => return outcome
  }
  // Flink gate (D-08, T-07-04-01): lineage is Doris-only this phase. A flink
  // selection exits 2 with the explicit message — never a silent empty result
  // (double-insurance with the fathom_lineage_v1 wire gate).
  if selection.dialect_id() == "flink" {
    return usage_error("lineage is Doris-only")
  }
  let catalog : @api.StaticCatalog? = match command.catalog {
    Some(path) => {
      let bytes = match read_file(path) {
        Some(bytes) => bytes
        None => return usage_error("cannot read file: \{path}")
      }
      match @binding.parse_catalog_json(bytes) {
        Ok(catalog) => catalog
        Err(message) => return usage_error("invalid catalog JSON (FATHOM-SCHEMA-004): \{message}")
      }
    }
    None => None
  }
  let input = match command.file {
    Some(path) if path != "-" => match read_file(path) {
      Some(bytes) => bytes
      None => return usage_error("cannot read file: \{path}")
    }
    _ => stdin_bytes
  }
  match @api.lineage_text(input, selection, catalog) {
    Ok(result) => {
      {
        exit_code: 0,
        stdout: @utf8.encode(
          @binding.lineage_result_json(
            input,
            result,
            command.dialect,
            command.profile,
            selection.exact_release(),
          ) + "\n",
        ),
        stderr: b"",
      }
    }
    Err(error) => parse_error_outcome(command.dialect, error)
  }
}

/// Render lint findings to stderr, one per line (report mode exit 1).
fn render_lint_findings(findings : Array[@api.LintFinding]) -> Bytes {
  let out = @buffer.Buffer::Buffer(size_hint=256)
  for finding in findings {
    out.write_bytes(@utf8.encode("\{finding.code}: \{finding.message}\n"))
  }
  out.to_bytes()
}

/// Render lint diagnostics to stderr, one per line (--fix refusal exit 1).
fn render_lint_diagnostics(diagnostics : Array[@api.LintDiagnostic]) -> Bytes {
  let out = @buffer.Buffer::Buffer(size_hint=256)
  for diagnostic in diagnostics {
    out.write_bytes(@utf8.encode("\{diagnostic.code}: \{diagnostic.message}\n"))
  }
  out.to_bytes()
}

fn bad_value(flag : String, value : String) -> CliOutcome {
  usage_error("invalid value for \{flag}: \{value}")
}

fn usage_error(message : String) -> CliOutcome {
  {
    exit_code: 2,
    stdout: b"",
    stderr: @utf8.encode("\{message}\n"),
  }
}

/// Maps a ParseError from the api core. UnknownProfile/UnknownDialect are
/// defense-in-depth (parse_args already validates both -> exit 2); everything
/// else is an input/processing failure -> exit 1 (T-03-23: InputTooLarge exits
/// 1 with the message, never a crash). The dialect rides along so the flink
/// profile-rejection message can list the released values (flink-2.3.0|
/// flink-2.1.3|flink-1.20.5) instead of advertising doris values (MI-02,
/// T-10-05).
fn parse_error_outcome(dialect : String, error : @api.ParseError) -> CliOutcome {
  match error {
    @api.ParseError::UnknownDialect(dialect_id~) => {
      usage_error("unknown dialect: \{dialect_id} (expected doris or flink)")
    }
    @api.ParseError::UnknownProfile(profile_id~) => {
      if dialect == "flink" {
        usage_error("unknown --profile value: \{profile_id} (expected flink-2.3.0, flink-2.1.3, or flink-1.20.5)")
      } else {
        usage_error("unknown --profile value: \{profile_id} (expected 2.1, 3.x, or 4.x)")
      }
    }
    @api.ParseError::UnknownMode(mode_id~) => {
      usage_error("unknown mode: \{mode_id}")
    }
    @api.ParseError::InputTooLarge(requested_bytes~, max_bytes~) => {
      {
        exit_code: 1,
        stdout: b"",
        stderr: @utf8.encode("input too large: \{requested_bytes} bytes (limit \{max_bytes})\n"),
      }
    }
    _ => {
      {
        exit_code: 1,
        stdout: b"",
        stderr: b"internal parse error\n",
      }
    }
  }
}

/// Render all diagnostics to stderr bytes, one per line. On refusal the api
/// core has already prepended the parse diagnostics, so the FATHOM-FORMAT-001
/// refusal never masks them (T-03-20).
pub fn render_diagnostics(diagnostics : Array[@api.FormatDiagnostic]) -> Bytes {
  let out = @buffer.Buffer::Buffer(size_hint=256)
  for diagnostic in diagnostics {
    out.write_bytes(@utf8.encode("\{diagnostic.code}: \{diagnostic.message}\n"))
  }
  out.to_bytes()
}

/// --help text (printed to stdout, exit 0).
pub fn usage_text() -> String {
  "usage: fathom-sql parse|format|lsp|lint|fingerprint|lineage --dialect <doris|flink> --profile <id> [--keyword-case upper|lower] [--indent N (0..64)] [--line-width N] [--comma-style trailing|leading] [--newline-style follow|lf|crlf] [--rule <CODE>=<error|warning|info|off>] [--fix] [--normalized] [--catalog <file>] [--no-trailing-newline] [--help] [file|-]\n"
}

/// Usage-error message for exit 2 (stderr only, no SQL output).
pub fn usage_error_message(error : UsageError) -> String {
  match error {
    MissingSubcommand => "missing subcommand (expected: parse, format, lsp, lint, fingerprint, or lineage)\n"
    UnknownSubcommand(sub~) => "unknown subcommand: \{sub} (expected: parse, format, lsp, lint, fingerprint, or lineage)\n"
    MissingDialect => "missing required flag: --dialect <doris|flink>\n"
    UnknownDialect(dialect_id~) => "unknown dialect: \{dialect_id} (expected doris or flink)\n"
    MissingProfile => "missing required flag: --profile <doris 2.1|3.x|4.x | flink flink-2.3.0|flink-2.1.3|flink-1.20.5>\n"
    UnknownProfile(profile_id~, dialect_id~) => {
      if dialect_id == "flink" {
        // flink accepts exactly the three pinned release profiles (Phase 10,
        // D-01) — the message must not imply that 2.1/3.x/4.x are usable
        // values for it (MI-02, Pitfall 6).
        "unknown --profile value: \{profile_id} (expected flink-2.3.0, flink-2.1.3, or flink-1.20.5)\n"
      } else {
        "unknown --profile value: \{profile_id} (expected 2.1, 3.x, or 4.x)\n"
      }
    }
    UnknownFlag(flag~) => "unknown flag: \{flag}\n"
    MissingValue(flag~) => "missing value for flag: \{flag}\n"
    UnknownValue(flag~, value~) => "invalid value for \{flag}: \{value}\n"
  }
}

test "run_format_stdin_happy_path" {
  let command : Command = {
    subcommand: "format",
    dialect: "doris",
    profile: "4.x",
    keyword_case: None,
    indent: None,
    line_width: None,
    comma_style: None,
    newline_style: None,
    trailing_newline: true,
    file: Some("-"),
    catalog: None,
    overrides: [],
    fix: false,
    normalized: false,
  }
  let outcome = run_format(command, b"select 1")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stdout, b"SELECT 1\n")
  assert_eq(outcome.stderr.length(), 0)
}

test "run_parse_stdin_happy_path" {
  let command : Command = {
    subcommand: "parse",
    dialect: "doris",
    profile: "4.x",
    keyword_case: None,
    indent: None,
    line_width: None,
    comma_style: None,
    newline_style: None,
    trailing_newline: true,
    file: Some("-"),
    catalog: None,
    overrides: [],
    fix: false,
    normalized: false,
  }
  let outcome = run_parse(command, b"SELECT 1")
  assert_eq(outcome.exit_code, 0)
  assert_true(outcome.stdout.to_string().contains("fathom.parse.v1"))
  assert_eq(outcome.stderr.length(), 0)
}
