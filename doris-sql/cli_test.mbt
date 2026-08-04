/// D-40 moon-test CLI suite (03-04 Task 2). Drives the pure functions directly
/// — no process spawn exists in core (research Pattern 6); the exit 0/1/2
/// behavior is additionally smoke-verified on the real binary in the plan
/// verify step. File-input fixtures are created/read only via the FFI helpers
/// (fopen/fwrite/fclose, research Common Operation 2) — never a process or a
/// core fs package.
///
/// Contract under test (D-37..D-40):
/// - run_format(command, stdin_bytes) -> CliOutcome { exit_code, stdout, stderr }
/// - exit 0 = accepted (stdout = formatted SQL); 1 = parse failure or refusal
///   (stdout empty, diagnostics on stderr, refusal never masks parse errors);
///   2 = usage error (stderr message only).

fn command_stdin(profile : String) -> Command {
  {
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
  let path = "/tmp/doris-sql-cli-fixture-file-input.sql"
  let handle = open_file(@utf8.encode(path) + b"\x00", b"wb")
  assert_true(handle != 0L)
  let content = b"select 1"
  ignore(write_file_chunk(content, 1, content.length(), handle))
  ignore(close_file(handle))
  // stdin carries a different statement; the file must win.
  let command : Command = {
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
    profile: "4.x",
    keyword_case: None,
    indent: None,
    line_width: None,
    comma_style: None,
    newline_style: None,
    trailing_newline: true,
    file: Some("/nonexistent/doris-sql-definitely-missing.sql"),
  }
  let outcome = run_format(command, b"")
  assert_eq(outcome.exit_code, 2)
  assert_eq(outcome.stdout.length(), 0)
  assert_true(outcome.stderr.to_string().contains("/nonexistent/doris-sql-definitely-missing.sql"))
}

test "cli_parse_failure_exit_1_with_parse_diagnostic" {
  let outcome = run_format(command_stdin("4.x"), b"bad")
  assert_eq(outcome.exit_code, 1)
  assert_eq(outcome.stdout.length(), 0)
  assert_true(outcome.stderr.to_string().contains("DORIS-PARSE-"))
}

test "cli_refusal_exit_1_never_masks_parse_diagnostics" {
  // MERGE is introduced in 4.x; under 2.1 strict the parser wraps it in a
  // SourceError leaf -> formatter refusal. The api core prepends the parse
  // diagnostics, so the refusal renders BOTH DORIS-PARSE-* and DORIS-FORMAT-001
  // (T-03-20: the refusal never masks the parse errors).
  let raw = b"MERGE INTO t USING s ON a=b WHEN MATCHED THEN UPDATE SET x=1"
  let outcome = run_format(command_stdin("2.1"), raw)
  assert_eq(outcome.exit_code, 1)
  assert_eq(outcome.stdout.length(), 0)
  let stderr = outcome.stderr.to_string()
  assert_true(stderr.contains("DORIS-FORMAT-001"))
  assert_true(stderr.contains("DORIS-PARSE-"))
}

test "cli_usage_errors_are_named_usage_error_variants" {
  assert_true(parse_args([]) is Err(MissingSubcommand))
  assert_true(parse_args(["parse"]) is Err(UnknownSubcommand(sub="parse")))
  assert_true(parse_args(["format"]) is Err(MissingProfile))
  assert_true(parse_args(["format", "--profile", "mysql"]) is Err(UnknownProfile(profile_id="mysql")))
  assert_true(parse_args(["format", "--profile", "4.x", "--indent"]) is Err(MissingValue(flag="--indent")))
  assert_true(parse_args(["format", "--profile", "4.x", "--unknown-flag"]) is Err(UnknownFlag(flag="--unknown-flag")))
  assert_true(parse_args(["format", "--profile", "4.x", "--comma-style", "sideways"]) is Err(UnknownValue(flag="--comma-style", value="sideways")))
  assert_true(parse_args(["format", "--profile", "4.x", "--indent", "abc"]) is Err(UnknownValue(flag="--indent", value="abc")))
  assert_true(parse_args(["format", "--profile", "4.x", "a.sql", "b.sql"]) is Err(UnknownFlag(flag="b.sql")))
}

test "cli_bad_option_values_exit_2_via_run_format" {
  // run_format is the defense-in-depth safety net: a hand-built Command with an
  // unknown enum id exits 2 naming the flag and value even when parse_args was
  // bypassed.
  let bad_comma : Command = {
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
    Err(error) => panic()
  }
  // "-" and a missing positional both mean stdin.
  match parse_args(["format", "--profile", "3.x"]) {
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
  assert_true(usage_error_message(error_of(["format"])).contains("--profile"))
  assert_true(usage_error_message(error_of(["format", "--profile", "4.x", "--bogus"])).contains("--bogus"))
  assert_true(usage_error_message(error_of(["format", "--profile", "4.x", "--comma-style", "sideways"])).contains("sideways"))
  assert_true(usage_error_message(error_of([])).contains("format"))
  assert_true(usage_text().contains("--profile"))
}
