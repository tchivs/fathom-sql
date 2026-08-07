test "exports_are_primitive_and_versioned" {
  let parsed = @binding.fathom_parse_v1(b"select 1", "doris", "4.x", "strict")
  let formatted = @binding.fathom_format_v1(
    b"select 1", "doris", "4.x", "strict", "upper", 2, 100, "trailing", "follow", true,
  )
  let dialect = @binding.fathom_dialect_v1("doris")
  let capabilities = @binding.fathom_capabilities_v1()
  assert_true(parsed.length() > 0)
  assert_true(formatted.length() > 0)
  assert_true(dialect.length() > 0)
  assert_true(capabilities.length() > 0)
  let parsed_text = @utf8.decode_lossy(parsed[:])
  let formatted_text = @utf8.decode_lossy(formatted[:])
  let dialect_text = @utf8.decode_lossy(dialect[:])
  let capabilities_text = @utf8.decode_lossy(capabilities[:])
  assert_true(parsed_text.contains("fathom.parse.v1"))
  assert_true(parsed_text.contains("\"source_bytes\":[115,101,108,101,99,116,32,49]"))
  assert_true(!parsed_text.contains("ParseResult"))
  assert_true(formatted_text.contains("fathom.format.v1"))
  assert_true(formatted_text.contains("\"source_bytes\":"))
  assert_true(!formatted_text.contains("FormatResult"))
  assert_true(dialect_text.contains("fathom.dialect.v1"))
  assert_true(dialect_text.contains("\"dialect\":\"doris\""))
  assert_true(dialect_text.contains("\"id\":\"4.x\""))
  assert_true(capabilities_text.contains("fathom.capabilities.v1"))
  assert_true(capabilities_text.contains("\"dialect\":\"doris\""))
  assert_true(capabilities_text.contains("\"dialect\":\"flink\""))
}

test "dialect_selection_is_explicit_end_to_end" {
  // (a) The happy path carries neutral wire identity: fathom.parse.v1 schema,
  // dialect and profile metadata fields, valid=true.
  let ok = @utf8.decode_lossy(@binding.fathom_parse_v1(b"SELECT 1", "doris", "4.x", "strict")[:])
  assert_true(ok.contains("fathom.parse.v1"))
  assert_true(ok.contains("\"dialect\":\"doris\""))
  assert_true(ok.contains("\"profile\":\"4.x\""))
  assert_true(ok.contains("\"valid\":true"))
  // (b) Invalid input yields a stable FATHOM-PARSE diagnostic; the error
  // envelope carries fathom.error.v1.
  let bad = @utf8.decode_lossy(@binding.fathom_parse_v1(b"SELEKT 1", "doris", "4.x", "strict")[:])
  assert_true(bad.contains("FATHOM-PARSE-"))
  let envelope_error = @utf8.decode_lossy(@binding.fathom_parse_v1(b"SELECT 1", "doris", "9.x", "strict")[:])
  assert_true(envelope_error.contains("fathom.error.v1"))
  assert_true(envelope_error.contains("FATHOM-SCHEMA-003"))
  // (c) flink-2.3.0 is a valid Phase 10 selection: the parse envelope carries
  // dialect=flink/profile=flink-2.3.0 with the explicit FATHOM-PARSE-008
  // not-implemented diagnostic — never a Doris parse and never a silent
  // default (DIALECT-03). An unknown flink profile (the Doris-shaped "2.1")
  // still rejects with the structured FATHOM-SCHEMA-003 profile error.
  let flink = @utf8.decode_lossy(@binding.fathom_parse_v1(b"SELECT 1", "flink", "flink-2.3.0", "strict")[:])
  assert_true(flink.contains("fathom.parse.v1"))
  assert_true(flink.contains("\"dialect\":\"flink\""))
  assert_true(flink.contains("\"profile\":\"flink-2.3.0\""))
  assert_true(flink.contains("\"exact_release\":\"flink-2.3.0\""))
  assert_true(flink.contains("FATHOM-PARSE-008"))
  assert_true(!flink.contains("Doris"))
  let flink_unknown = @utf8.decode_lossy(@binding.fathom_parse_v1(b"SELECT 1", "flink", "2.1", "strict")[:])
  assert_true(flink_unknown.contains("fathom.error.v1"))
  assert_true(flink_unknown.contains("FATHOM-SCHEMA-003"))
  // Unknown dialect: structured UnknownDialect error (FATHOM-SCHEMA-007).
  let unknown = @utf8.decode_lossy(@binding.fathom_parse_v1(b"SELECT 1", "mysql", "4.x", "strict")[:])
  assert_true(unknown.contains("fathom.error.v1"))
  assert_true(unknown.contains("FATHOM-SCHEMA-007"))
  assert_true(unknown.contains("unknown dialect"))
}

test "format_export_is_dialect_aware_with_neutral_wire_identity" {
  // (a) The happy path carries fathom.format.v1 with dialect/profile/
  // exact_release metadata (DIALECT-04, D-09) — the same envelope shape as
  // the parse result.
  let ok = @utf8.decode_lossy(
    @binding.fathom_format_v1(
      b"select 1", "doris", "4.x", "strict", "upper", 2, 100, "trailing", "follow", true,
    )[:],
  )
  assert_true(ok.contains("fathom.format.v1"))
  assert_true(ok.contains("\"dialect\":\"doris\""))
  assert_true(ok.contains("\"profile\":\"4.x\""))
  assert_true(ok.contains("\"exact_release\":\"4.x\""))
  assert_true(ok.contains("\"accepted\":true"))
  // (b) A refusal (malformed input) yields exactly one FATHOM-FORMAT-001
  // inside the format envelope; format-option errors carry fathom.error.v1
  // with the FATHOM-FORMAT code family.
  let refused = @utf8.decode_lossy(
    @binding.fathom_format_v1(
      b"select (", "doris", "4.x", "strict", "upper", 2, 100, "trailing", "follow", true,
    )[:],
  )
  assert_true(refused.contains("\"accepted\":false"))
  assert_true(refused.contains("FATHOM-FORMAT-001"))
  let bad_option = @utf8.decode_lossy(
    @binding.fathom_format_v1(
      b"select 1", "doris", "4.x", "strict", "mixed", 2, 100, "trailing", "follow", true,
    )[:],
  )
  assert_true(bad_option.contains("fathom.error.v1"))
  assert_true(bad_option.contains("FATHOM-FORMAT-002"))
  // (c) flink-2.3.0 is a valid Phase 10 selection: the formatter refuses the
  // not-implemented tree (FATHOM-FORMAT-001, never partial bytes) inside the
  // fathom.format.v1 envelope — no Doris-policy formatting of a flink request
  // (Pitfall 6, T-09-10). An unknown flink profile (the Doris-shaped "2.1")
  // still rejects with the structured FATHOM-SCHEMA-003 profile error.
  let flink = @utf8.decode_lossy(
    @binding.fathom_format_v1(
      b"select 1", "flink", "flink-2.3.0", "strict", "upper", 2, 100, "trailing", "follow", true,
    )[:],
  )
  assert_true(flink.contains("fathom.format.v1"))
  assert_true(flink.contains("\"dialect\":\"flink\""))
  assert_true(flink.contains("\"profile\":\"flink-2.3.0\""))
  assert_true(flink.contains("\"accepted\":false"))
  assert_true(flink.contains("FATHOM-FORMAT-001"))
  let flink_unknown = @utf8.decode_lossy(
    @binding.fathom_format_v1(
      b"select 1", "flink", "2.1", "strict", "upper", 2, 100, "trailing", "follow", true,
    )[:],
  )
  assert_true(flink_unknown.contains("fathom.error.v1"))
  assert_true(flink_unknown.contains("FATHOM-SCHEMA-003"))
  let unknown = @utf8.decode_lossy(
    @binding.fathom_format_v1(
      b"select 1", "mysql", "4.x", "strict", "upper", 2, 100, "trailing", "follow", true,
    )[:],
  )
  assert_true(unknown.contains("fathom.error.v1"))
  assert_true(unknown.contains("FATHOM-SCHEMA-007"))
  assert_true(unknown.contains("unknown dialect"))
}

test "flink_internal_route_returns_not_implemented_statement" {
  // (d) The internal Flink route (parser entry, bypassing profile rejection):
  // a directly constructed Flink DialectContext parses to a Statement node
  // carrying FATHOM-PARSE-008 — no Doris grammar runs.
  let source = match @source.SourceText::new(b"SELECT 1") {
    Ok(source) => source
    Err(_) => panic()
  }
  let context = ({
    dialect: @dialect.Dialect::Flink,
    profile_id: "flink-2.3.0",
    exact_release: "flink-2.3.0",
    feature_introduction: "",
  } : @dialect.DialectContext)
  let parsed = @parser.parse(source, context, @parser.ParseMode::Strict)
  assert_true(!parsed.valid)
  assert_eq(parsed.diagnostics.length(), 1)
  assert_eq(parsed.diagnostics[0].code, "FATHOM-PARSE-008")
  assert_eq(parsed.diagnostics[0].message, "flink grammar is not yet implemented in this release")
  let statements = parsed.root.children()
  assert_true(statements.length() >= 1)
  assert_true(statements[0].span().end_byte == source.byte_length())
}
