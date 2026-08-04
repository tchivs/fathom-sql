/// CLI argument parsing (D-38/D-39). Hand-rolled on purpose: @argparse owns
/// help/exit behavior, and D-39's exit semantics must be fully explicit.
/// Mirrors the string-id -> enum -> structured-error convention of
/// ParseOptions::new (api.mbt:64-84): every bad flag or value is a named
/// UsageError that main maps to exit 2 (stderr message only, no SQL output).

/// Usage errors map to exit 2 (D-39).
pub enum UsageError {
  MissingSubcommand
  UnknownSubcommand(sub~ : String)
  MissingProfile
  UnknownProfile(profile_id~ : String)
  UnknownFlag(flag~ : String)
  MissingValue(flag~ : String)
  UnknownValue(flag~ : String, value~ : String)
  MissingFile
} derive(Eq, @debug.Debug)

/// Parsed format invocation. `file` None or "-" means stdin; trailing_newline
/// defaults true and --no-trailing-newline clears it.
pub struct Command {
  profile : String
  keyword_case : String?
  indent : Int?
  line_width : Int?
  comma_style : String?
  newline_style : String?
  trailing_newline : Bool
  file : String?
}

/// Flag surface (flagged assumption, research Open Q2 RESOLVED):
/// `format --profile <2.1|3.x|4.x> [--keyword-case upper|lower] [--indent N]
/// [--line-width N] [--comma-style trailing|leading] [--newline-style
/// follow|lf|crlf] [--no-trailing-newline] [--help] [file|-]`.
/// --profile is REQUIRED: missing -> MissingProfile -> exit 2 (CORE-01 — no
/// silent default profile). --help is handled in main before parse_args.
pub fn parse_args(args : Array[String]) -> Result[Command, UsageError] {
  if args.length() == 0 { return Err(MissingSubcommand) }
  if args[0] != "format" { return Err(UnknownSubcommand(sub=args[0])) }
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
    if arg == "--profile" {
      index = index + 1
      if index >= args.length() { return Err(MissingValue(flag="--profile")) }
      let value = args[index]
      if !is_valid_profile(value) { return Err(UnknownProfile(profile_id=value)) }
      profile = Some(value)
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
  match profile {
    Some(profile_value) => Ok({
      profile: profile_value,
      keyword_case: keyword_case,
      indent: indent,
      line_width: line_width,
      comma_style: comma_style,
      newline_style: newline_style,
      trailing_newline: trailing_newline,
      file: file,
    })
    None => Err(MissingProfile)
  }
}

fn is_valid_profile(id : String) -> Bool {
  id == "2.1" || id == "3.x" || id == "4.x"
}

/// Hand-rolled optional-sign integer parse (no @strconv import — the CLI
/// dependency surface stays at api/env/buffer/utf8/debug). "4" -> Some(4),
/// "-1" -> Some(-1), "abc" -> None. Negative values reach FormatOptions::new,
/// which rejects them with InvalidIndent/InvalidLineWidth (exit 2). The
/// magnitude bound keeps the accumulator far below Int overflow.
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
