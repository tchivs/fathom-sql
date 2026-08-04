fn json_text(bytes : Bytes) -> String {
  @utf8.decode_lossy(bytes[:])
}

fn fixture_source(id : String) -> Bytes {
  match id {
    "valid-2.1" => b"select 1"
    "recovered-3.x" => b"select ("
    "error-4.x" => b"select @@@"
    "comments-hint" => b"select /*+ SET_VAR(x=1) */ 1 -- note\r\n"
    "crlf-multiple" => b"select 1;\r\nselect 2"
    "non-ascii" => b"select '中文'"
    "format-refusal" => b"select ("
    "raw-bytes" => b"select \xff\x00\x0a"
    "empty" => b""
    _ => b""
  }
}

fn fixture_profile(id : String) -> String {
  match id {
    "valid-2.1" | "non-ascii" | "empty" => "2.1"
    "recovered-3.x" | "crlf-multiple" | "raw-bytes" => "3.x"
    _ => "4.x"
  }
}

fn run_fixture(id : String) -> Unit raise {
  let source = fixture_source(id)
  let profile = fixture_profile(id)
  let parsed = json_text(@binding.doris_parse_v1(source, profile, "editor"))
  let formatted = json_text(@binding.doris_format_v1(
    source,
    profile,
    "strict",
    "upper",
    2,
    100,
    "trailing",
    "follow",
    true,
  ))
  assert_true(parsed.length() > 0)
  assert_true(formatted.length() > 0)
  assert_true(parsed.contains("doris.parse.v1") || parsed.contains("doris.error.v1"))
  assert_true(parsed.contains("\"profile\":\"\{profile}\""))
  assert_true(parsed.contains("\"source_byte_length\":\{source.length()}"))
  assert_true(parsed.contains("\"source_bytes\":"))
  assert_true(parsed.contains("\"root\":"))
  assert_true(parsed.contains("\"diagnostics\":"))
  assert_true(formatted.contains("doris.format.v1") || formatted.contains("doris.error.v1"))
  assert_true(formatted.contains("\"source_bytes\":"))
}

test "parity_corpus_exercises_profiles_recovery_comments_bytes_and_refusal" {
  let ids = [
    "valid-2.1",
    "recovered-3.x",
    "error-4.x",
    "comments-hint",
    "crlf-multiple",
    "non-ascii",
    "format-refusal",
    "raw-bytes",
    "empty",
  ]
  for id in ids {
    run_fixture(id)
  }
  let refused = json_text(@binding.doris_format_v1(
    b"select (",
    "4.x",
    "strict",
    "upper",
    2,
    100,
    "trailing",
    "follow",
    true,
  ))
  assert_true(refused.contains("\"accepted\":false"))
  assert_true(refused.contains("DORIS-FORMAT-001"))
}

test "parity_rejects_unknown_profile_mode_and_options" {
  let unknown_profile = json_text(@binding.doris_parse_v1(b"select 1", "mysql", "strict"))
  assert_true(unknown_profile.contains("doris.error.v1"))
  assert_true(unknown_profile.contains("DORIS-SCHEMA-003"))
  let unknown_mode = json_text(@binding.doris_parse_v1(b"select 1", "4.x", "interactive"))
  assert_true(unknown_mode.contains("DORIS-SCHEMA-004"))
  let unknown_case = json_text(@binding.doris_format_v1(
    b"select 1", "4.x", "strict", "mixed", 2, 100, "trailing", "follow", true,
  ))
  assert_true(unknown_case.contains("DORIS-FORMAT-002"))
  let invalid_width = json_text(@binding.doris_format_v1(
    b"select 1", "4.x", "strict", "upper", 2, 0, "trailing", "follow", true,
  ))
  assert_true(invalid_width.contains("DORIS-FORMAT-006"))
}

test "parity_capabilities_exclude_wasm_gc_and_expose_linear_wasm" {
  let capabilities = json_text(@binding.doris_capabilities_v1())
  assert_true(capabilities.contains("doris.capabilities.v1"))
  assert_true(capabilities.contains("js-esm"))
  assert_true(capabilities.contains("wasm-linear"))
  assert_true(capabilities.contains("\"wasm_gc\":false"))
  let profile = json_text(@binding.doris_profile_v1("3.x"))
  assert_true(profile.contains("doris.profile.v1"))
  assert_true(profile.contains("\"exact_release\":"))
  let bad_profile = json_text(@binding.doris_profile_v1("mysql"))
  assert_true(bad_profile.contains("DORIS-SCHEMA-003"))
}

test "target_abi_regression_preserves_bytes_and_exposes_only_primitives" {
  let valid = json_text(@binding.doris_parse_v1(b"select 1", "4.x", "strict"))
  assert_true(valid.contains("\"schema_version\":\"doris.parse.v1\""))
  assert_true(valid.contains("\"source_bytes\":[115,101,108,101,99,116,32,49]"))
  assert_true(!valid.contains("SyntaxNode"))
  assert_true(!valid.contains("ParseResult"))
  let empty = json_text(@binding.doris_parse_v1(b"", "2.1", "strict"))
  assert_true(empty.contains("\"source_byte_length\":0"))
  assert_true(empty.contains("\"source_bytes\":[]"))
  let malformed = json_text(@binding.doris_parse_v1(b"\xff", "3.x", "editor"))
  assert_true(malformed.contains("\"source_bytes\":[255]"))
  assert_true(malformed.contains("\"diagnostics\":"))
  let formatted = json_text(@binding.doris_format_v1(
    b"select 1", "4.x", "strict", "upper", 2, 100, "trailing", "lf", true,
  ))
  assert_true(formatted.contains("\"schema_version\":\"doris.format.v1\""))
  assert_true(!formatted.contains("FormatResult"))
}
