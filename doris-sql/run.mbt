/// Pure CLI logic home (D-37/D-38): maps a parsed Command plus stdin bytes to
/// an exact CliOutcome { exit_code, stdout, stderr } (D-39). This is the ONLY
/// logic in the CLI package — no format logic lives here; the single core call
/// is @api.format_with_ids (the shared Phase 4 LSP entry, D-38). Pure and
/// moon-testable (D-40): no process spawn, no shared state, no temp files —
/// parallel or interrupted invocations cannot corrupt each other.

pub(all) struct CliOutcome {
  exit_code : Int
  stdout : Bytes
  stderr : Bytes
}

const DEFAULT_INDENT : Int = 2
const DEFAULT_LINE_WIDTH : Int = 100

/// D-39 exit mapping:
/// 0 = accepted — stdout carries the formatted SQL, stderr empty;
/// 1 = parse failure or format refusal — stdout empty, diagnostics on stderr
///     (the api core prepends the parse diagnostics, so the DORIS-FORMAT-001
///     refusal never masks them, T-03-20);
/// 2 = usage error (missing file, bad option value, unknown profile) —
///     stderr message only, no SQL output.
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
  let result = match @api.format_with_ids(input, "doris", command.profile, "strict", format_options) {
    Ok(result) => result
    Err(error) => return parse_error_outcome(error)
  }
  if result.accepted {
    { exit_code: 0, stdout: result.output, stderr: b"" }
  } else {
    { exit_code: 1, stdout: b"", stderr: render_diagnostics(result.diagnostics) }
  }
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

/// Maps a ParseError from the api core. UnknownProfile is defense-in-depth
/// (parse_args already validates the profile -> exit 2); everything else is an
/// input/processing failure -> exit 1 (T-03-23: InputTooLarge exits 1 with the
/// message, never a crash).
fn parse_error_outcome(error : @api.ParseError) -> CliOutcome {
  match error {
    @api.ParseError::UnknownProfile(profile_id~) => {
      usage_error("unknown --profile value: \{profile_id} (expected 2.1, 3.x, or 4.x)")
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
/// core has already prepended the parse diagnostics, so the DORIS-FORMAT-001
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
  "usage: doris-sql format --profile <2.1|3.x|4.x> [--keyword-case upper|lower] [--indent N (0..64)] [--line-width N] [--comma-style trailing|leading] [--newline-style follow|lf|crlf] [--no-trailing-newline] [--help] [file|-]\n"
}

/// Usage-error message for exit 2 (stderr only, no SQL output).
pub fn usage_error_message(error : UsageError) -> String {
  match error {
    MissingSubcommand => "missing subcommand (expected: format)\n"
    UnknownSubcommand(sub~) => "unknown subcommand: \{sub} (expected: format)\n"
    MissingProfile => "missing required flag: --profile <2.1|3.x|4.x>\n"
    UnknownProfile(profile_id~) => "unknown --profile value: \{profile_id} (expected 2.1, 3.x, or 4.x)\n"
    UnknownFlag(flag~) => "unknown flag: \{flag}\n"
    MissingValue(flag~) => "missing value for flag: \{flag}\n"
    UnknownValue(flag~, value~) => "invalid value for \{flag}: \{value}\n"
    MissingFile => "cannot read file\n"
  }
}

test "run_format_stdin_happy_path" {
  let command : Command = {
    profile: "4.x",
    keyword_case: None,
    indent: None,
    line_width: None,
    comma_style: None,
    newline_style: None,
    trailing_newline: true,
    file: Some("-"),
  }
  let outcome = run_format(command, b"select 1")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stdout, b"SELECT 1\n")
  assert_eq(outcome.stderr.length(), 0)
}
