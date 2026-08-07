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
    profile: profile,
    keyword_case: None,
    indent: None,
    line_width: None,
    comma_style: None,
    newline_style: None,
    trailing_newline: true,
    file: Some("-"),
  }
}

test "cli_stdin_happy_path_exit_0" {
  let outcome = run_format(command_stdin("4.x"), b"select 1")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stdout, b"SELECT 1\n")
  assert_eq(outcome.stderr.length(), 0)
}

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
  }
  let outcome = run_format(command, b"select 99")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stdout, b"SELECT 1\n")
  assert_eq(outcome.stderr.length(), 0)
}

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
  }
  let outcome = run_format(command, b"")
  assert_eq(outcome.exit_code, 2)
  assert_eq(outcome.stdout.length(), 0)
  assert_true(outcome.stderr.to_string().contains("/nonexistent/fathom-sql-definitely-missing.sql"))
}

test "cli_parse_failure_exit_1_with_parse_diagnostic" {
  let outcome = run_format(command_stdin("4.x"), b"bad")
  assert_eq(outcome.exit_code, 1)
  assert_eq(outcome.stdout.length(), 0)
  assert_true(outcome.stderr.to_string().contains("FATHOM-PARSE-"))
}

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

test "cli_usage_errors_are_named_usage_error_variants" {
  assert_true(parse_args([]) is Err(MissingSubcommand))
  assert_true(parse_args(["run"]) is Err(UnknownSubcommand(sub="run")))
  assert_true(parse_args(["parse"]) is Err(MissingDialect))
  assert_true(parse_args(["format"]) is Err(MissingDialect))
  assert_true(parse_args(["lsp"]) is Err(MissingDialect))
  assert_true(parse_args(["format", "--dialect", "mysql"]) is Err(UnknownDialect(dialect_id="mysql")))
  assert_true(parse_args(["format", "--dialect", "doris"]) is Err(MissingProfile))
  // Dialect-first validation: a Doris profile under flink is rejected.
  assert_true(parse_args(["format", "--dialect", "flink", "--profile", "4.x"]) is Err(UnknownProfile(profile_id="4.x", dialect_id="flink")))
  assert_true(parse_args(["format", "--dialect", "doris", "--profile", "mysql"]) is Err(UnknownProfile(profile_id="mysql", dialect_id="doris")))
  assert_true(parse_args(["format", "--dialect", "doris", "--profile", "4.x", "--indent"]) is Err(MissingValue(flag="--indent")))
  assert_true(parse_args(["format", "--dialect", "doris", "--profile", "4.x", "--unknown-flag"]) is Err(UnknownFlag(flag="--unknown-flag")))
  assert_true(parse_args(["format", "--dialect", "doris", "--profile", "4.x", "--comma-style", "sideways"]) is Err(UnknownValue(flag="--comma-style", value="sideways")))
  assert_true(parse_args(["format", "--dialect", "doris", "--profile", "4.x", "--indent", "abc"]) is Err(UnknownValue(flag="--indent", value="abc")))
  assert_true(parse_args(["format", "--dialect", "doris", "--profile", "4.x", "a.sql", "b.sql"]) is Err(UnknownFlag(flag="b.sql")))
}

test "cli_d11_exit_2_matrix_through_usage_error_message" {
  // Missing --dialect -> exit 2 naming the required flag (D-11, T-09-13).
  assert_true(usage_error_message(parse_error_of(["parse"])).contains("missing required flag: --dialect"))
  // Unknown dialect -> exit 2 naming the value.
  assert_true(usage_error_message(parse_error_of(["parse", "--dialect", "oracle"])).contains("unknown dialect"))
  assert_true(usage_error_message(parse_error_of(["parse", "--dialect", "oracle"])).contains("oracle"))
  // flink rejects non-pinned profiles in Phase 10 -> exit 2 (D-01, T-10-01).
  // The message lists the actual released values and must not advertise
  // doris values (MI-02): a Doris profile ("4.x") or adjacent id is
  // "unknown" for flink.
  let flink_message = usage_error_message(parse_error_of(["parse", "--dialect", "flink", "--profile", "4.x"]))
  assert_true(flink_message.contains("unknown --profile value: 4.x"))
  assert_true(flink_message.contains("expected flink-2.3.0, flink-2.1.3, or flink-1.20.5"))
  assert_true(!flink_message.contains("2.1, 3.x, or 4.x"))
  // flink-2.3.0 is accepted in Phase 10; the adjacency probes reject.
  assert_true(parse_args(["parse", "--dialect", "flink", "--profile", "flink-2.3.0"]).is_ok())
  assert_true(parse_args(["parse", "--dialect", "flink", "--profile", "flink-2.3"]).is_ok() == false)
  assert_true(parse_args(["parse", "--dialect", "flink", "--profile", "flink-2.3.0-rc1"]).is_ok() == false)
  // doris keeps the released-value hint (MI-02).
  assert_true(usage_error_message(parse_error_of(["parse", "--dialect", "doris", "--profile", "mysql"])).contains("expected 2.1, 3.x, or 4.x"))
  // Missing --profile after a valid dialect -> exit 2.
  assert_true(usage_error_message(parse_error_of(["format", "--dialect", "doris"])).contains("missing required flag: --profile"))
  // Unknown subcommand names the full surface.
  assert_true(usage_error_message(parse_error_of(["run"])).contains("parse, format, or lsp"))
  // The usage text advertises the full D-11 surface.
  assert_true(usage_text().contains("fathom-sql parse|format|lsp --dialect <doris|flink> --profile <id>"))
  // No invocation defaults a dialect: every valid invocation must carry both.
  assert_true(parse_args(["format", "--profile", "4.x"]) is Err(MissingDialect))
  assert_true(parse_args(["lsp", "--dialect", "doris", "--profile", "2.1"]).is_ok())
}

fn parse_error_of(args : Array[String]) -> UsageError {
  match parse_args(args) {
    Err(error) => error
    Ok(_) => panic()
  }
}

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
  }
  let outcome = run_parse(command, b"SELECT 1")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stderr.length(), 0)
  let stdout = outcome.stdout.to_string()
  assert_true(stdout.contains("fathom.parse.v1"))
  assert_true(stdout.contains("dialect"))
  assert_true(stdout.contains("doris"))
}

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
  }
  let huge_outcome = run_format(huge_indent, b"select 1")
  assert_eq(huge_outcome.exit_code, 2)
  assert_true(huge_outcome.stderr.to_string().contains("--indent"))
}

test "cli_crlf_preserved_byte_for_byte" {
  let outcome = run_format(command_stdin("4.x"), b"select 1\r\n")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stdout, b"SELECT 1\r\n")
  assert_eq(outcome.stderr.length(), 0)
}

test "cli_flag_surface_parses_and_drives_options" {
  match parse_args([
    "format",
    "--dialect",
    "doris",
    "--profile",
    "4.x",
    "--keyword-case",
    "lower",
    "--indent",
    "4",
    "--line-width",
    "20",
    "--comma-style",
    "leading",
    "--newline-style",
    "lf",
    "--no-trailing-newline",
    "file.sql",
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

test "cli_deterministic_same_input_same_outcome" {
  let command = command_stdin("4.x")
  let first = run_format(command, b"select a, b from t")
  let second = run_format(command, b"select a, b from t")
  assert_eq(first.exit_code, second.exit_code)
  assert_eq(first.stdout, second.stdout)
  assert_eq(first.stderr, second.stderr)
}

test "cli_empty_stdin_accepted_empty_output" {
  let outcome = run_format(command_stdin("4.x"), b"")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.stdout.length(), 0)
  assert_eq(outcome.stderr.length(), 0)
}

test "cli_usage_error_message_renders_exit_2_text" {
  // UsageError values are derived from parse_args (black-box tests cannot
  // construct pub-enum variants cross-package on this toolchain).
  fn error_of(args : Array[String]) -> UsageError {
    match parse_args(args) {
      Err(error) => error
      Ok(_) => panic()
    }
  }
  assert_true(usage_error_message(error_of(["format", "--dialect", "doris"])).contains("--profile"))
  assert_true(usage_error_message(error_of(["format", "--dialect", "doris", "--profile", "4.x", "--bogus"])).contains("--bogus"))
  assert_true(usage_error_message(error_of(["format", "--dialect", "doris", "--profile", "4.x", "--comma-style", "sideways"])).contains("sideways"))
  assert_true(usage_error_message(error_of([])).contains("parse, format, or lsp"))
  assert_true(usage_text().contains("--dialect"))
}
