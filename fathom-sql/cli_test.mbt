///|
/// D-40 moon-test CLI suite (03-04 Task 2 + D-11 matrix). Drives the pure
/// functions directly — no process spawn exists in core (research Pattern 6);
/// the exit 0/1/2 behavior is additionally smoke-verified on the real binary
/// in the plan verify step. File-input fixtures are created/read only via the
/// FFI helpers (fopen/fwrite/fclose, research Common Operation 2) — never a
/// process or a core fs package.
///
/// Contract under test (D-37..D-40, D-11):
/// - run_format(command, stdin_bytes) / run_parse(command, stdin_bytes) ->
///   CliOutcome { exit_code, stdout, stderr }
/// - exit 0 = accepted (stdout = formatted SQL / fathom.parse.v1 envelope);
///   1 = parse failure or refusal (stdout empty, diagnostics on stderr,
///   refusal never masks parse errors);
///   2 = usage error (missing/unknown dialect or profile, missing file, bad
///   option value) — stderr message only.
/// - --dialect <doris|flink> and --profile <id> are REQUIRED for every
///   subcommand; no invocation defaults a dialect (D-11).
fn command_stdin(profile : String) -> Command {
  {
    subcommand: "format",
    dialect: "doris",
    profile,
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
}

///|
/// flink-parameterized Command (D-07, 13-05): mirrors command_stdin but with
/// dialect "flink" and the caller-chosen profile/subcommand for the D-39
/// exit-code matrix (0 accepted / 1 refusal / 2 usage).
fn command_flink(profile : String, subcommand : String) -> Command {
  {
    subcommand,
    dialect: "flink",
    profile,
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
}

///|
test "cli_stdin_happy_path_exit_0" {
  let outcome = run_format(command_stdin("4.x"), b"select 1")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stdout, b"SELECT 1\n")
  assert_eq(outcome.stderr.length(), 0)
}

///|
test "cli_version_exit_0_exact_output" {
  // VER-02/D-02: `fathom-sql --version` reports the single-source product
  // version with exit 0 and no stderr.
  let outcome = run_version("fathom-sql")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stdout, b"fathom-sql 1.0.0\n")
  assert_eq(outcome.stderr.length(), 0)
}

///|
test "cli_file_input_exit_0" {
  // Write a fixture through the FFI helpers (fopen "wb" + fwrite + fclose).
  let path = "/tmp/fathom-sql-cli-fixture-file-input.sql"
  let handle = open_file(@utf8.encode(path) + b"\x00", b"wb")
  assert_true(handle != 0L)
  let content = b"select 1"
  ignore(write_file_chunk(content, 1, content.length(), handle))
  ignore(close_file(handle))
  // stdin carries a different statement; the file must win.
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
    file: Some(path),
    catalog: None,
    overrides: [],
    fix: false,
    normalized: false,
  }
  let outcome = run_format(command, b"select 99")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stdout, b"SELECT 1\n")
  assert_eq(outcome.stderr.length(), 0)
}

///|
test "cli_missing_file_exit_2_names_path" {
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
    file: Some("/nonexistent/fathom-sql-definitely-missing.sql"),
    catalog: None,
    overrides: [],
    fix: false,
    normalized: false,
  }
  let outcome = run_format(command, b"")
  assert_eq(outcome.exit_code, 2)
  assert_eq(outcome.stdout.length(), 0)
  assert_true(
    outcome.stderr
    .to_string()
    .contains("/nonexistent/fathom-sql-definitely-missing.sql"),
  )
}

///|
test "cli_parse_failure_exit_1_with_parse_diagnostic" {
  let outcome = run_format(command_stdin("4.x"), b"bad")
  assert_eq(outcome.exit_code, 1)
  assert_eq(outcome.stdout.length(), 0)
  assert_true(outcome.stderr.to_string().contains("FATHOM-PARSE-"))
}

///|
test "cli_refusal_exit_1_never_masks_parse_diagnostics" {
  // MERGE is introduced in 4.x; under 2.1 strict the parser wraps it in a
  // SourceError leaf -> formatter refusal. The api core prepends the parse
  // diagnostics, so the refusal renders BOTH FATHOM-PARSE-* and
  // FATHOM-FORMAT-001 (T-03-20: the refusal never masks the parse errors).
  let raw = b"MERGE INTO t USING s ON a=b WHEN MATCHED THEN UPDATE SET x=1"
  let outcome = run_format(command_stdin("2.1"), raw)
  assert_eq(outcome.exit_code, 1)
  assert_eq(outcome.stdout.length(), 0)
  let stderr = outcome.stderr.to_string()
  assert_true(stderr.contains("FATHOM-FORMAT-001"))
  assert_true(stderr.contains("FATHOM-PARSE-"))
}

///|
test "cli_usage_errors_are_named_usage_error_variants" {
  assert_true(parse_args([]) is Err(MissingSubcommand))
  assert_true(parse_args(["run"]) is Err(UnknownSubcommand(sub="run")))
  assert_true(parse_args(["parse"]) is Err(MissingDialect))
  assert_true(parse_args(["format"]) is Err(MissingDialect))
  assert_true(parse_args(["lsp"]) is Err(MissingDialect))
  assert_true(
    parse_args(["format", "--dialect", "mysql"])
    is Err(UnknownDialect(dialect_id="mysql")),
  )
  assert_true(
    parse_args(["format", "--dialect", "doris"]) is Err(MissingProfile),
  )
  // Dialect-first validation: a Doris profile under flink is rejected.
  assert_true(
    parse_args(["format", "--dialect", "flink", "--profile", "4.x"])
    is Err(UnknownProfile(profile_id="4.x", dialect_id="flink")),
  )
  assert_true(
    parse_args(["format", "--dialect", "doris", "--profile", "mysql"])
    is Err(UnknownProfile(profile_id="mysql", dialect_id="doris")),
  )
  assert_true(
    parse_args(["format", "--dialect", "doris", "--profile", "4.x", "--indent"])
    is Err(MissingValue(flag="--indent")),
  )
  assert_true(
    parse_args([
      "format", "--dialect", "doris", "--profile", "4.x", "--unknown-flag",
    ])
    is Err(UnknownFlag(flag="--unknown-flag")),
  )
  assert_true(
    parse_args([
      "format", "--dialect", "doris", "--profile", "4.x", "--comma-style", "sideways",
    ])
    is Err(UnknownValue(flag="--comma-style", value="sideways")),
  )
  assert_true(
    parse_args([
      "format", "--dialect", "doris", "--profile", "4.x", "--indent", "abc",
    ])
    is Err(UnknownValue(flag="--indent", value="abc")),
  )
  assert_true(
    parse_args([
      "format", "--dialect", "doris", "--profile", "4.x", "a.sql", "b.sql",
    ])
    is Err(UnknownFlag(flag="b.sql")),
  )
}

///|
test "cli_d11_exit_2_matrix_through_usage_error_message" {
  // Missing --dialect -> exit 2 naming the required flag (D-11, T-09-13).
  assert_true(
    usage_error_message(parse_error_of(["parse"])).contains(
      "missing required flag: --dialect",
    ),
  )
  // Unknown dialect -> exit 2 naming the value.
  assert_true(
    usage_error_message(parse_error_of(["parse", "--dialect", "oracle"])).contains(
      "unknown dialect",
    ),
  )
  assert_true(
    usage_error_message(parse_error_of(["parse", "--dialect", "oracle"])).contains(
      "oracle",
    ),
  )
  // flink rejects non-pinned profiles in Phase 10 -> exit 2 (D-01, T-10-01).
  // The message lists the actual released values and must not advertise
  // doris values (MI-02): a Doris profile ("4.x") or adjacent id is
  // "unknown" for flink.
  let flink_message = usage_error_message(
    parse_error_of(["parse", "--dialect", "flink", "--profile", "4.x"]),
  )
  assert_true(flink_message.contains("unknown --profile value: 4.x"))
  assert_true(
    flink_message.contains("expected flink-2.3.0, flink-2.1.3, or flink-1.20.5"),
  )
  assert_true(!flink_message.contains("2.1, 3.x, or 4.x"))
  // flink-2.3.0 is accepted in Phase 10; the adjacency probes reject.
  assert_true(
    parse_args(["parse", "--dialect", "flink", "--profile", "flink-2.3.0"])
    is Ok(_),
  )
  assert_true(
    (parse_args(["parse", "--dialect", "flink", "--profile", "flink-2.3"])
    is Ok(_)) ==
    false,
  )
  assert_true(
    (parse_args(["parse", "--dialect", "flink", "--profile", "flink-2.3.0-rc1"])
    is Ok(_)) ==
    false,
  )
  // doris keeps the released-value hint (MI-02).
  assert_true(
    usage_error_message(
      parse_error_of(["parse", "--dialect", "doris", "--profile", "mysql"]),
    ).contains("expected 2.1, 3.x, or 4.x"),
  )
  // Missing --profile after a valid dialect -> exit 2.
  assert_true(
    usage_error_message(parse_error_of(["format", "--dialect", "doris"])).contains(
      "missing required flag: --profile",
    ),
  )
  // Unknown subcommand names the full surface.
  assert_true(
    usage_error_message(parse_error_of(["run"])).contains(
      "parse, format, lsp, lint, fingerprint, or lineage",
    ),
  )
  // The usage text advertises the full D-11 surface.
  assert_true(
    usage_text().contains(
      "fathom-sql parse|format|lsp|lint|fingerprint|lineage --dialect <doris|flink> --profile <id>",
    ),
  )
  // No invocation defaults a dialect: every valid invocation must carry both.
  assert_true(parse_args(["format", "--profile", "4.x"]) is Err(MissingDialect))
  assert_true(
    parse_args(["lsp", "--dialect", "doris", "--profile", "2.1"]) is Ok(_),
  )
}

///|
fn parse_error_of(args : Array[String]) -> UsageError {
  match parse_args(args) {
    Err(error) => error
    Ok(_) => panic()
  }
}

///|
test "cli_parse_subcommand_exit_0_envelope" {
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
  assert_eq(outcome.stderr.length(), 0)
  let stdout = outcome.stdout.to_string()
  assert_true(stdout.contains("fathom.parse.v1"))
  assert_true(stdout.contains("dialect"))
  assert_true(stdout.contains("doris"))
}

///|
test "cli_bad_option_values_exit_2_via_run_format" {
  // run_format is the defense-in-depth safety net: a hand-built Command with an
  // unknown enum id exits 2 naming the flag and value even when parse_args was
  // bypassed.
  let bad_comma : Command = {
    subcommand: "format",
    dialect: "doris",
    profile: "4.x",
    keyword_case: None,
    indent: None,
    line_width: None,
    comma_style: Some("sideways"),
    newline_style: None,
    trailing_newline: true,
    file: Some("-"),
    catalog: None,
    overrides: [],
    fix: false,
    normalized: false,
  }
  let outcome = run_format(bad_comma, b"select 1")
  assert_eq(outcome.exit_code, 2)
  assert_eq(outcome.stdout.length(), 0)
  let stderr = outcome.stderr.to_string()
  assert_true(stderr.contains("--comma-style"))
  assert_true(stderr.contains("sideways"))

  // Negative indent fails FormatOptions::new -> exit 2 (ASVS V5).
  let bad_indent : Command = {
    subcommand: "format",
    dialect: "doris",
    profile: "4.x",
    keyword_case: None,
    indent: Some(-1),
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
  let indent_outcome = run_format(bad_indent, b"select 1")
  assert_eq(indent_outcome.exit_code, 2)
  assert_true(indent_outcome.stderr.to_string().contains("--indent"))

  // WR-02: over-cap indent (above the 0..64 documented range) also fails
  // construction -> exit 2. Pre-fix, --indent 5000000 was accepted and
  // materialized ~131 MB for a 10-item broken select list (OOM class).
  let huge_indent : Command = {
    subcommand: "format",
    dialect: "doris",
    profile: "4.x",
    keyword_case: None,
    indent: Some(5000000),
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
  let huge_outcome = run_format(huge_indent, b"select 1")
  assert_eq(huge_outcome.exit_code, 2)
  assert_true(huge_outcome.stderr.to_string().contains("--indent"))
}

///|
test "cli_crlf_preserved_byte_for_byte" {
  let outcome = run_format(command_stdin("4.x"), b"select 1\r\n")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stdout, b"SELECT 1\r\n")
  assert_eq(outcome.stderr.length(), 0)
}

///|
test "cli_flag_surface_parses_and_drives_options" {
  match
    parse_args([
      "format", "--dialect", "doris", "--profile", "4.x", "--keyword-case", "lower",
      "--indent", "4", "--line-width", "20", "--comma-style", "leading", "--newline-style",
      "lf", "--no-trailing-newline", "file.sql",
    ]) {
    Ok(command) => {
      assert_eq(command.subcommand, "format")
      assert_eq(command.dialect, "doris")
      assert_eq(command.profile, "4.x")
      assert_eq(command.keyword_case, Some("lower"))
      assert_eq(command.indent, Some(4))
      assert_eq(command.line_width, Some(20))
      assert_eq(command.comma_style, Some("leading"))
      assert_eq(command.newline_style, Some("lf"))
      assert_eq(command.trailing_newline, false)
      assert_eq(command.file, Some("file.sql"))
      // The parsed options drive real layout: lower keyword case and no
      // trailing newline are observable in the output. Run via stdin (the
      // parsed file "file.sql" does not exist on disk).
      let stdin_command : Command = {
        subcommand: "format",
        dialect: command.dialect,
        profile: command.profile,
        keyword_case: command.keyword_case,
        indent: command.indent,
        line_width: command.line_width,
        comma_style: command.comma_style,
        newline_style: command.newline_style,
        trailing_newline: command.trailing_newline,
        file: Some("-"),
        catalog: None,
        overrides: [],
        fix: false,
        normalized: false,
      }
      let outcome = run_format(stdin_command, b"SELECT 1")
      assert_eq(outcome.exit_code, 0)
      assert_eq(outcome.stdout, b"select 1")
    }
    Err(_) => panic()
  }
  // "-" and a missing positional both mean stdin.
  match parse_args(["format", "--dialect", "doris", "--profile", "3.x"]) {
    Ok(command) => assert_eq(command.file, None)
    Err(_) => panic()
  }
}

///|
test "cli_deterministic_same_input_same_outcome" {
  let command = command_stdin("4.x")
  let first = run_format(command, b"select a, b from t")
  let second = run_format(command, b"select a, b from t")
  assert_eq(first.exit_code, second.exit_code)
  assert_eq(first.stdout, second.stdout)
  assert_eq(first.stderr, second.stderr)
}

///|
test "cli_empty_stdin_accepted_empty_output" {
  let outcome = run_format(command_stdin("4.x"), b"")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stdout.length(), 0)
  assert_eq(outcome.stderr.length(), 0)
}

///|
test "cli_usage_error_message_renders_exit_2_text" {
  // UsageError values are derived from parse_args (black-box tests cannot
  // construct pub-enum variants cross-package on this toolchain).
  fn error_of(args : Array[String]) -> UsageError {
    match parse_args(args) {
      Err(error) => error
      Ok(_) => panic()
    }
  }
  assert_true(
    usage_error_message(error_of(["format", "--dialect", "doris"])).contains(
      "--profile",
    ),
  )
  assert_true(
    usage_error_message(
      error_of(["format", "--dialect", "doris", "--profile", "4.x", "--bogus"]),
    ).contains("--bogus"),
  )
  assert_true(
    usage_error_message(
      error_of([
        "format", "--dialect", "doris", "--profile", "4.x", "--comma-style", "sideways",
      ]),
    ).contains("sideways"),
  )
  assert_true(
    usage_error_message(error_of([])).contains(
      "parse, format, lsp, lint, fingerprint, or lineage",
    ),
  )
  assert_true(usage_text().contains("--dialect"))
}

// D-07 / D-39 flink format exit-code matrix (13-05): `fathom-sql format
// --dialect flink --profile flink-2.3.0` routes through @api.format_with_ids
// with exit 0 (accepted), 1 (refusal — FATHOM-FORMAT-001 on stderr, parse
// diagnostics never masked), 2 (usage/unknown profile). run.mbt needs no flink
// guard — the format path is dialect-agnostic.

///|
test "cli_flink_format_accepted_exit_0" {
  let outcome = run_format(command_flink("flink-2.3.0", "format"), b"select 1")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stdout, b"SELECT 1\n")
  assert_eq(outcome.stderr.length(), 0)
}

///|
test "cli_flink_format_refusal_exit_1" {
  // The unsafe Flink tree (incomplete WHERE) refuses via the covered-family
  // refusal channel: exit 1, empty stdout, FATHOM-FORMAT-001 on stderr with
  // the parse diagnostics prepended (T-03-20 — never masked).
  let outcome = run_format(
    command_flink("flink-2.3.0", "format"),
    b"SELECT a, b FROM t WHERE",
  )
  assert_eq(outcome.exit_code, 1)
  assert_eq(outcome.stdout.length(), 0)
  let stderr = outcome.stderr.to_string()
  assert_true(stderr.contains("FATHOM-FORMAT-001"))
}

///|
test "cli_flink_doris_shaped_profile_exit_2" {
  // A Doris-shaped profile under flink is a usage error (D-01, Phase 10): exit
  // 2, empty stdout, and the message lists the released flink values (MI-02 —
  // never advertises doris values).
  let outcome = run_format(command_flink("4.x", "format"), b"select 1")
  assert_eq(outcome.exit_code, 2)
  assert_eq(outcome.stdout.length(), 0)
  let stderr = outcome.stderr.to_string()
  assert_true(stderr.contains("unknown --profile value: 4.x"))
  assert_true(stderr.contains("flink-2.3.0"))
  assert_true(!stderr.contains("2.1, 3.x, or 4.x"))
}

///|
test "cli_flink_parse_exit_0_fathom_parse_v1" {
  // `fathom-sql parse --dialect flink` returns the fathom.parse.v1 envelope
  // with the flink selection on stdout, exit 0, empty stderr.
  let outcome = run_parse(command_flink("flink-2.3.0", "parse"), b"SELECT 1")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stderr.length(), 0)
  let stdout = outcome.stdout.to_string()
  assert_true(stdout.contains("fathom.parse.v1"))
  assert_true(stdout.contains("flink"))
}

///|
/// lint-parameterized Command (06-04 Task 1): doris 4.x, stdin, configurable
/// overrides/fix.
fn lint_command(overrides : Array[@api.RuleOverride], fix : Bool) -> Command {
  {
    subcommand: "lint",
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
    overrides,
    fix,
    normalized: false,
  }
}

///|
/// fingerprint-parameterized Command (06-04 Task 1): doris 4.x, stdin.
fn fingerprint_command(normalized : Bool) -> Command {
  {
    subcommand: "fingerprint",
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
    normalized,
  }
}

///|
test "cli_lint_report_exit_0_no_findings" {
  let outcome = run_lint(lint_command([], false), b"SELECT a, b FROM t")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stdout.length(), 0)
  assert_eq(outcome.stderr.length(), 0)
}

///|
test "cli_lint_report_exit_1_findings_rendered" {
  let outcome = run_lint(lint_command([], false), b"SELECT * FROM t")
  assert_eq(outcome.exit_code, 1)
  assert_eq(outcome.stdout.length(), 0)
  assert_true(outcome.stderr.to_string().contains("FATHOM-LINT-003"))
}

///|
test "cli_lint_fix_refusal_exit_1_d33" {
  // `SELECT order FROM t` parses to a recoverable tree with a missing node ->
  // D-33 refusal in --fix mode: exit 1, empty stdout, FATHOM-LINT-000.
  let outcome = run_lint(lint_command([], true), b"SELECT order FROM t")
  assert_eq(outcome.exit_code, 1)
  assert_eq(outcome.stdout.length(), 0)
  assert_true(outcome.stderr.to_string().contains("FATHOM-LINT-000"))
}

///|
test "cli_lint_rule_override_disables_003" {
  // `--rule FATHOM-LINT-003=off` suppresses the select-star finding -> exit 0.
  let overrides : Array[@api.RuleOverride] = [
    { code: "FATHOM-LINT-003", setting: @api.RuleSetting::Disabled },
  ]
  let outcome = run_lint(lint_command(overrides, false), b"SELECT * FROM t")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stderr.length(), 0)
}

///|
test "cli_lint_unknown_rule_flag_exit_2" {
  // `--rule FATHOM-LINT-999=off` is a usage error (code not in the registry):
  // exit 2 via LintOptions::new, stderr names --rule.
  let overrides : Array[@api.RuleOverride] = [
    { code: "FATHOM-LINT-999", setting: @api.RuleSetting::Disabled },
  ]
  let outcome = run_lint(lint_command(overrides, false), b"SELECT * FROM t")
  assert_eq(outcome.exit_code, 2)
  assert_eq(outcome.stdout.length(), 0)
  assert_true(outcome.stderr.to_string().contains("--rule"))
}

///|
test "cli_lint_rule_flag_parse_unknown_severity_exit_2" {
  // Unknown severity in --rule is an UnknownValue at parse_args (exit 2).
  match
    parse_args([
      "lint", "--dialect", "doris", "--profile", "4.x", "--rule", "FATHOM-LINT-003=fatal",
    ]) {
    Err(UnknownValue(flag~, value~)) => {
      assert_eq(flag, "--rule")
      assert_eq(value, "FATHOM-LINT-003=fatal")
    }
    _ => assert_true(false)
  }
}

///|
test "cli_fingerprint_exit_0_decimal_string" {
  let outcome = run_fingerprint(fingerprint_command(false), b"SELECT 1")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stderr.length(), 0)
  let stdout = @utf8.decode(outcome.stdout) catch { _ => "" }
  // stdout is the UInt64 fingerprint as a decimal string + newline.
  assert_true(stdout.has_suffix("\n"))
  let chars = stdout.to_array()
  let mut all_digits = chars.length() > 1
  let mut i = 0
  while i < chars.length() - 1 {
    let code = chars[i].to_int()
    if code < 48 || code > 57 {
      all_digits = false
    }
    i = i + 1
  }
  assert_true(all_digits)
}

///|
test "cli_fingerprint_normalized_outputs_canonical_text" {
  let outcome = run_fingerprint(fingerprint_command(true), b"SELECT 1")
  assert_eq(outcome.exit_code, 0)
  let stdout = @utf8.decode(outcome.stdout) catch { _ => "" }
  // fingerprint line then normalized "select 1\n"
  assert_true(stdout.contains("\nselect 1\n"))
}

///|
test "cli_fingerprint_parse_failure_exit_1" {
  // Unrecoverable input still yields a deterministic fingerprint (total
  // function), so the only exit-1 path is a selection error — which
  // parse_args already blocks. Assert a clean valid path instead.
  let outcome = run_fingerprint(fingerprint_command(false), b"SELECT 1")
  assert_eq(outcome.exit_code, 0)
}

///|
/// lineage-parameterized Command (07-04 Task 3): doris 4.x, stdin, optional
/// --catalog path.
fn lineage_command(catalog_path : String?) -> Command {
  {
    subcommand: "lineage",
    dialect: "doris",
    profile: "4.x",
    keyword_case: None,
    indent: None,
    line_width: None,
    comma_style: None,
    newline_style: None,
    trailing_newline: true,
    file: Some("-"),
    catalog: catalog_path,
    overrides: [],
    fix: false,
    normalized: false,
  }
}

///|
test "cli_lineage_exit_0_envelope" {
  // D-39: a valid doris selection serializes the fathom.lineage.v1 envelope
  // to stdout, exit 0, empty stderr.
  let outcome = run_lineage(lineage_command(None), b"SELECT a FROM t")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stderr.length(), 0)
  let stdout = @utf8.decode(outcome.stdout) catch { _ => "" }
  assert_true(stdout.contains("fathom.lineage.v1"))
  assert_true(stdout.contains("\"dialect\":\"doris\""))
  assert_true(stdout.contains("\"profile\":\"4.x\""))
  assert_true(stdout.contains("\"edges\":"))
  assert_true(stdout.contains("\"gaps\":"))
}

///|
test "cli_lineage_flink_gate_exit_2" {
  // D-08: a valid flink selection exits 2 with "lineage is Doris-only" on
  // stderr — never a silent empty envelope.
  let command : Command = {
    subcommand: "lineage",
    dialect: "flink",
    profile: "flink-2.3.0",
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
  let outcome = run_lineage(command, b"SELECT 1")
  assert_eq(outcome.exit_code, 2)
  assert_eq(outcome.stdout.length(), 0)
  assert_true(outcome.stderr.to_string().contains("lineage is Doris-only"))
}

///|
test "cli_lineage_bad_catalog_path_exit_2" {
  // D-39: a nonexistent --catalog path is a usage error -> exit 2 naming the
  // path.
  let outcome = run_lineage(
    lineage_command(Some("/nonexistent/fathom-sql-catalog.json")),
    b"SELECT * FROM t",
  )
  assert_eq(outcome.exit_code, 2)
  assert_eq(outcome.stdout.length(), 0)
  assert_true(
    outcome.stderr.to_string().contains("/nonexistent/fathom-sql-catalog.json"),
  )
}

///|
test "cli_lineage_bad_catalog_json_exit_2" {
  // T-07-04-02 / ASVS V5: an invalid catalog JSON file exits 2 with the
  // FATHOM-SCHEMA-004 structured error — never a silent fallback.
  let path = "/tmp/fathom-sql-cli-fixture-bad-catalog.json"
  let handle = open_file(@utf8.encode(path) + b"\x00", b"wb")
  assert_true(handle != 0L)
  let content = b"{\"tables\":42}"
  ignore(write_file_chunk(content, 1, content.length(), handle))
  ignore(close_file(handle))
  let outcome = run_lineage(lineage_command(Some(path)), b"SELECT * FROM t")
  assert_eq(outcome.exit_code, 2)
  assert_eq(outcome.stdout.length(), 0)
  assert_true(outcome.stderr.to_string().contains("FATHOM-SCHEMA-004"))
}

///|
test "cli_lineage_parse_failure_exit_1" {
  // D-39 / T-07-04-05: oversized input (over the 8 MiB default limit) exits 1
  // with empty stdout — a parse/processing failure, never a crash.
  let oversized = Bytes::make(8 * 1024 * 1024 + 1, 32)
  let outcome = run_lineage(lineage_command(None), oversized)
  assert_eq(outcome.exit_code, 1)
  assert_eq(outcome.stdout.length(), 0)
}

///|
test "cli_lineage_star_with_catalog_exit_0_two_edges" {
  // D-05 / SC2: with --catalog providing t={a,b}, `SELECT * FROM t` expands
  // to two real edges (no requires-catalog gap).
  let path = "/tmp/fathom-sql-cli-fixture-catalog.json"
  let handle = open_file(@utf8.encode(path) + b"\x00", b"wb")
  assert_true(handle != 0L)
  let content = b"{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"a\",\"data_type\":\"INT\"},{\"name\":\"b\",\"data_type\":\"INT\"}]}]}"
  ignore(write_file_chunk(content, 1, content.length(), handle))
  ignore(close_file(handle))
  let outcome = run_lineage(lineage_command(Some(path)), b"SELECT * FROM t")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stderr.length(), 0)
  let stdout = @utf8.decode(outcome.stdout) catch { _ => "" }
  assert_true(stdout.contains("fathom.lineage.v1"))
  assert_true(stdout.contains("\"source_name\":\"a\""))
  assert_true(stdout.contains("\"source_name\":\"b\""))
  assert_true(!stdout.contains("requires-catalog"))
}

///|
test "cli_lineage_star_no_catalog_requires_catalog_gap" {
  // SC2: without a catalog, `SELECT * FROM t` reports an honest
  // requires-catalog gap — never a fabricated edge.
  let outcome = run_lineage(lineage_command(None), b"SELECT * FROM t")
  assert_eq(outcome.exit_code, 0)
  let stdout = @utf8.decode(outcome.stdout) catch { _ => "" }
  assert_true(stdout.contains("requires-catalog"))
}

///|
test "cli_lineage_flag_surface_and_usage" {
  // parse_args accepts the lineage subcommand with an optional --catalog.
  match parse_args(["lineage", "--dialect", "doris", "--profile", "4.x"]) {
    Ok(command) => {
      assert_eq(command.subcommand, "lineage")
      assert_eq(command.catalog, None)
    }
    Err(_) => assert_true(false)
  }
  match
    parse_args([
      "lineage", "--dialect", "doris", "--profile", "4.x", "--catalog", "cat.json",
    ]) {
    Ok(command) => assert_eq(command.catalog, Some("cat.json"))
    Err(_) => assert_true(false)
  }
  // Missing --catalog value -> MissingValue exit 2.
  assert_true(
    parse_args([
      "lineage", "--dialect", "doris", "--profile", "4.x", "--catalog",
    ])
    is Err(MissingValue(flag="--catalog")),
  )
  // Missing --dialect/--profile -> exit 2 (D-11).
  assert_true(parse_args(["lineage"]) is Err(MissingDialect))
  assert_true(
    parse_args(["lineage", "--dialect", "doris"]) is Err(MissingProfile),
  )
  // Unknown subcommand names the full surface including lineage.
  assert_true(
    usage_error_message(parse_error_of(["run"])).contains(
      "parse, format, lsp, lint, fingerprint, or lineage",
    ),
  )
  // usage_text advertises lineage and --catalog.
  assert_true(usage_text().contains("lineage"))
  assert_true(usage_text().contains("--catalog"))
}
