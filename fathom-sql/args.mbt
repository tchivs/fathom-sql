/// CLI argument parsing (D-38/D-39/D-11). Hand-rolled on purpose: @argparse
/// owns help/exit behavior, and D-39's exit semantics must be fully explicit.
/// Mirrors the string-id -> enum -> structured-error convention of
/// ParseOptions::new (api.mbt:64-84): every bad flag or value is a named
/// UsageError that main maps to exit 2 (stderr message only, no SQL output).
///
/// D-11 explicit-selection contract: `--dialect <doris|flink>` and
/// `--profile <id>` are REQUIRED for every subcommand (parse|format|lsp);
/// missing or unknown values exit 2 — the CLI never defaults a dialect.

/// Usage errors map to exit 2 (D-39).
pub enum UsageError {
  MissingSubcommand
  UnknownSubcommand(sub~ : String)
  MissingDialect
  UnknownDialect(dialect_id~ : String)
  MissingProfile
  UnknownProfile(profile_id~ : String, dialect_id~ : String)
  UnknownFlag(flag~ : String)
  MissingValue(flag~ : String)
  UnknownValue(flag~ : String, value~ : String)
} derive(Eq, @debug.Debug)

/// Parsed invocation. `subcommand` is one of "parse"|"format"|"lsp" (D-11);
/// `dialect` and `profile` are always set by parse_args. `file` None or "-"
/// means stdin; trailing_newline defaults true and --no-trailing-newline
/// clears it. `pub(all)` so the black-box cli_test.mbt module can construct
/// test Commands (moon 0.1.20260724 rejects pub-struct literals
/// cross-package without it — 03-01 lesson).
pub(all) struct Command {
  pub subcommand : String
  pub dialect : String
  pub profile : String
  keyword_case : String?
  indent : Int?
  line_width : Int?
  comma_style : String?
  newline_style : String?
  trailing_newline : Bool
  file : String?
}

/// Flag surface (D-11, research Open Q2 RESOLVED):
/// `fathom-sql parse|format|lsp --dialect <doris|flink> --profile <id>
/// [--keyword-case upper|lower] [--indent N] [--line-width N] [--comma-style
/// trailing|leading] [--newline-style follow|lf|crlf] [--no-trailing-newline]
/// [--help] [file|-]`.
/// --dialect and --profile are REQUIRED: missing -> MissingDialect /
/// MissingProfile -> exit 2 (D-11 — no silent default dialect). --help is
/// handled in main before parse_args.
pub fn parse_args(args : Array[String]) -> Result[Command, UsageError] {
  if args.length() == 0 { return Err(MissingSubcommand) }
  let subcommand = args[0]
  if subcommand != "parse" && subcommand != "format" && subcommand != "lsp" {
    return Err(UnknownSubcommand(sub=subcommand))
  }
  let mut dialect : String? = None
  let mut profile : String? = None
  let mut keyword_case : String? = None
  let mut indent : Int? = None
  let mut line_width : Int? = None
  let mut comma_style : String? = None
  let mut newline_style : String? = None
  let mut trailing_newline = true
  let mut file : String? = None
  let mut index = 1
  while index < args.length() {
    let arg = args[index]
    if arg == "--dialect" {
      index = index + 1
      if index >= args.length() { return Err(MissingValue(flag="--dialect")) }
      let value = args[index]
      if value != "doris" && value != "flink" { return Err(UnknownDialect(dialect_id=value)) }
      dialect = Some(value)
    } else if arg == "--profile" {
      index = index + 1
      if index >= args.length() { return Err(MissingValue(flag="--profile")) }
      profile = Some(args[index])
    } else if arg == "--keyword-case" || arg == "--comma-style" || arg == "--newline-style" ||
      arg == "--indent" || arg == "--line-width" {
      index = index + 1
      if index >= args.length() { return Err(MissingValue(flag=arg)) }
      let value = args[index]
      match arg {
        "--keyword-case" => {
          if value != "upper" && value != "lower" {
            return Err(UnknownValue(flag="--keyword-case", value=value))
          }
          keyword_case = Some(value)
        }
        "--comma-style" => {
          if value != "trailing" && value != "leading" {
            return Err(UnknownValue(flag="--comma-style", value=value))
          }
          comma_style = Some(value)
        }
        "--newline-style" => {
          if value != "follow" && value != "lf" && value != "crlf" {
            return Err(UnknownValue(flag="--newline-style", value=value))
          }
          newline_style = Some(value)
        }
        "--indent" => {
          match parse_int_arg(value) {
            Some(number) => indent = Some(number)
            None => return Err(UnknownValue(flag="--indent", value=value))
          }
        }
        "--line-width" => {
          match parse_int_arg(value) {
            Some(number) => line_width = Some(number)
            None => return Err(UnknownValue(flag="--line-width", value=value))
          }
        }
        _ => ()
      }
    } else if arg == "--no-trailing-newline" {
      trailing_newline = false
    } else if arg.has_prefix("--") {
      return Err(UnknownFlag(flag=arg))
    } else if file is None {
      file = Some(arg)
    } else {
      // A second positional argument is a usage error, not an ignore.
      return Err(UnknownFlag(flag=arg))
    }
    index = index + 1
  }
  let dialect_value = match dialect {
    Some(value) => value
    None => return Err(MissingDialect)
  }
  let profile_value = match profile {
    Some(value) => value
    None => return Err(MissingProfile)
  }
  // Dialect-first validation (Pitfall 6): the profile is checked per dialect;
  // flink rejects every profile in Phase 9 (A1/OQ1). The dialect travels with
  // the error so the exit-2 message can say so (MI-02).
  if !is_valid_dialect_profile(dialect_value, profile_value) {
    return Err(UnknownProfile(profile_id=profile_value, dialect_id=dialect_value))
  }
  Ok({
    subcommand: subcommand,
    dialect: dialect_value,
    profile: profile_value,
    keyword_case: keyword_case,
    indent: indent,
    line_width: line_width,
    comma_style: comma_style,
    newline_style: newline_style,
    trailing_newline: trailing_newline,
    file: file,
  })
}

/// Explicit dialect+profile validation (D-11, mirrors binding's
/// validate_dialect_profile): doris accepts 2.1/3.x/4.x; flink accepts no
/// profile in Phase 9.
pub fn is_valid_dialect_profile(dialect : String, id : String) -> Bool {
  match dialect {
    "doris" => id == "2.1" || id == "3.x" || id == "4.x"
    _ => false
  }
}

/// Hand-rolled optional-sign integer parse (no @strconv import — the CLI
/// dependency surface stays at api/lsp/binding/env/buffer/utf8/debug). "4" ->
/// Some(4), "-1" -> Some(-1), "abc" -> None. Negative values reach
/// FormatOptions::new, which rejects them with InvalidIndent/InvalidLineWidth
/// (exit 2). The magnitude bound keeps the accumulator far below Int
/// overflow.
fn parse_int_arg(value : String) -> Int? {
  let chars = value.to_array()
  if chars.length() == 0 { return None }
  let mut start = 0
  let mut negative = false
  if chars[0] == '-' {
    negative = true
    start = 1
  }
  if start >= chars.length() { return None }
  let mut number = 0
  while start < chars.length() {
    let code = chars[start].to_int()
    if code < 48 || code > 57 { return None }
    if number > 100000000 { return None }
    number = number * 10 + (code - 48)
    start = start + 1
  }
  if negative { Some(-number) } else { Some(number) }
}
