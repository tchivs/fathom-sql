/// CLI argument parsing (D-38/D-39/D-11). Hand-rolled on purpose: @argparse
/// owns help/exit behavior, and D-39's exit semantics must be fully explicit.
/// Mirrors the string-id -> enum -> structured-error convention of
/// ParseOptions::new (api.mbt:64-84): every bad flag or value is a named
/// UsageError that main maps to exit 2 (stderr message only, no SQL output).
///
/// D-11 explicit-selection contract: `--dialect <doris|flink>` and
/// `--profile <id>` are REQUIRED for every subcommand (parse|format|lsp);
/// missing or unknown values exit 2 — the CLI never defaults a dialect.

///|
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

///|
/// Parsed invocation. `subcommand` is one of "parse"|"format"|"lsp"|"lint"|
/// "fingerprint"|"lineage" (D-11); `dialect` and `profile` are always set by
/// parse_args. `file` None or "-" means stdin; trailing_newline defaults true
/// and --no-trailing-newline clears it. `catalog` carries the optional
/// `--catalog <file>` path for the lineage subcommand (D-05). `pub(all)` so
/// the black-box cli_test.mbt module can construct test Commands (moon
/// 0.1.20260724 rejects pub-struct literals cross-package without it — 03-01
/// lesson).
pub(all) struct Command {
  subcommand : String
  dialect : String
  profile : String
  keyword_case : String?
  indent : Int?
  line_width : Int?
  comma_style : String?
  newline_style : String?
  trailing_newline : Bool
  file : String?
  catalog : String?
  overrides : Array[@api.RuleOverride]
  fix : Bool
  normalized : Bool
}

///|
/// Flag surface (D-11, research Open Q2 RESOLVED):
/// `fathom-sql parse|format|lsp|lint|fingerprint|lineage --dialect <doris|flink>
/// --profile <id> [--keyword-case upper|lower] [--indent N] [--line-width N]
/// [--comma-style trailing|leading] [--newline-style follow|lf|crlf]
/// [--no-trailing-newline] [--rule <CODE>=<severity|off>] [--fix] [--normalized]
/// [--catalog <file>] [--help] [file|-]`.
/// --dialect and --profile are REQUIRED: missing -> MissingDialect /
/// MissingProfile -> exit 2 (D-11 — no silent default dialect). --help is
/// handled in main before parse_args.
pub fn parse_args(args : Array[String]) -> Result[Command, UsageError] {
  if args.length() == 0 {
    return Err(MissingSubcommand)
  }
  let subcommand = args[0]
  if subcommand != "parse" &&
    subcommand != "format" &&
    subcommand != "lsp" &&
    subcommand != "lint" &&
    subcommand != "fingerprint" &&
    subcommand != "lineage" {
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
  let mut catalog : String? = None
  let overrides : Array[@api.RuleOverride] = []
  let mut fix = false
  let mut normalized = false
  let mut index = 1
  while index < args.length() {
    let arg = args[index]
    if arg == "--dialect" {
      index = index + 1
      if index >= args.length() {
        return Err(MissingValue(flag="--dialect"))
      }
      let value = args[index]
      if value != "doris" && value != "flink" {
        return Err(UnknownDialect(dialect_id=value))
      }
      dialect = Some(value)
    } else if arg == "--profile" {
      index = index + 1
      if index >= args.length() {
        return Err(MissingValue(flag="--profile"))
      }
      profile = Some(args[index])
    } else if arg == "--rule" {
      index = index + 1
      if index >= args.length() {
        return Err(MissingValue(flag="--rule"))
      }
      match parse_rule_flag(args[index]) {
        Ok(rule_override) => overrides.push(rule_override)
        Err(error) => return Err(error)
      }
    } else if arg == "--catalog" {
      index = index + 1
      if index >= args.length() {
        return Err(MissingValue(flag="--catalog"))
      }
      catalog = Some(args[index])
    } else if arg == "--fix" {
      fix = true
    } else if arg == "--normalized" {
      normalized = true
    } else if arg == "--keyword-case" ||
      arg == "--comma-style" ||
      arg == "--newline-style" ||
      arg == "--indent" ||
      arg == "--line-width" {
      index = index + 1
      if index >= args.length() {
        return Err(MissingValue(flag=arg))
      }
      let value = args[index]
      match arg {
        "--keyword-case" => {
          if value != "upper" && value != "lower" {
            return Err(UnknownValue(flag="--keyword-case", value~))
          }
          keyword_case = Some(value)
        }
        "--comma-style" => {
          if value != "trailing" && value != "leading" {
            return Err(UnknownValue(flag="--comma-style", value~))
          }
          comma_style = Some(value)
        }
        "--newline-style" => {
          if value != "follow" && value != "lf" && value != "crlf" {
            return Err(UnknownValue(flag="--newline-style", value~))
          }
          newline_style = Some(value)
        }
        "--indent" =>
          match parse_int_arg(value) {
            Some(number) => indent = Some(number)
            None => return Err(UnknownValue(flag="--indent", value~))
          }
        "--line-width" =>
          match parse_int_arg(value) {
            Some(number) => line_width = Some(number)
            None => return Err(UnknownValue(flag="--line-width", value~))
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
  // flink accepts exactly the three pinned release profiles (Phase 10, D-01).
  // The dialect travels with the error so the exit-2 message can list the
  // released values (MI-02).
  if !is_valid_dialect_profile(dialect_value, profile_value) {
    return Err(
      UnknownProfile(profile_id=profile_value, dialect_id=dialect_value),
    )
  }
  Ok({
    subcommand,
    dialect: dialect_value,
    profile: profile_value,
    keyword_case,
    indent,
    line_width,
    comma_style,
    newline_style,
    trailing_newline,
    file,
    catalog,
    overrides,
    fix,
    normalized,
  })
}

///|
/// Parse one `--rule <code>=<severity|off>` flag into a RuleOverride (D-04).
/// The value must contain exactly one `=`, a non-empty code, and a severity of
/// error/warning/info/off; anything else is an UnknownValue usage error that
/// main maps to exit 2. Code existence in the registry is validated later by
/// `@api.LintOptions::new` in run_lint (also exit 2 on unknown code).
fn parse_rule_flag(value : String) -> Result[@api.RuleOverride, UsageError] {
  let split = value.split_once("=")
  match split {
    Some((code_view, setting_view)) => {
      let code = code_view.to_string()
      let setting = setting_view.to_string()
      if code.length() == 0 {
        return Err(UnknownValue(flag="--rule", value~))
      }
      let parsed = if setting == "off" {
        @api.RuleSetting::Disabled
      } else {
        match @api.LintSeverity::from_id(setting) {
          Some(severity) => @api.RuleSetting::Severity(severity)
          None => return Err(UnknownValue(flag="--rule", value~))
        }
      }
      Ok({ code, setting: parsed })
    }
    None => Err(UnknownValue(flag="--rule", value~))
  }
}

///|
/// Explicit dialect+profile validation (D-11, mirrors binding's
/// validate_dialect_profile): doris accepts 2.1/3.x/4.x; flink accepts the
/// three pinned release profiles (Phase 10, D-01) — exact match only, no
/// prefix/suffix/version-compare (Pitfall 6, T-10-01).
pub fn is_valid_dialect_profile(dialect : String, id : String) -> Bool {
  match dialect {
    "doris" => id == "2.1" || id == "3.x" || id == "4.x"
    "flink" =>
      id == "flink-2.3.0" || id == "flink-2.1.3" || id == "flink-1.20.5"
    _ => false
  }
}

///|
/// Hand-rolled optional-sign integer parse (no @strconv import — the CLI
/// dependency surface stays at api/lsp/binding/env/buffer/utf8/debug). "4" ->
/// Some(4), "-1" -> Some(-1), "abc" -> None. Negative values reach
/// FormatOptions::new, which rejects them with InvalidIndent/InvalidLineWidth
/// (exit 2). The pre-multiply magnitude cap (values up to ~1e9 are accepted)
/// is a value-range sanity gate for --indent/--line-width, not an overflow
/// guard: Int64 arithmetic cannot overflow here, and FormatOptions::new
/// applies the authoritative bounds (indent 0..64).
fn parse_int_arg(value : String) -> Int? {
  let chars = value.to_array()
  if chars.length() == 0 {
    return None
  }
  let mut start = 0
  let mut negative = false
  if chars[0] == '-' {
    negative = true
    start = 1
  }
  if start >= chars.length() {
    return None
  }
  let mut number = 0
  while start < chars.length() {
    let code = chars[start].to_int()
    if code < 48 || code > 57 {
      return None
    }
    if number > 100000000 {
      return None
    }
    number = number * 10 + (code - 48)
    start = start + 1
  }
  if negative {
    Some(-number)
  } else {
    Some(number)
  }
}
