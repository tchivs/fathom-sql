///|
test "schema_v2_bump_is_additive" {
  // The v2 bump is PURE ADDITION (Pitfall V6): the two new namespaces appear
  // while all five original namespaces remain usable. The 8th namespace
  // (fathom.lineage.v1, 07-04) is the same pure addition: it appears while
  // all seven prior namespaces keep their behavior unchanged.
  let lint = @utf8.decode_lossy(
    @binding.fathom_lint_v1(b"SELECT 1", "doris", "4.x", "strict", b"[]", false)[:],
  )
  let fingerprint = @utf8.decode_lossy(
    @binding.fathom_fingerprint_v1(b"SELECT 1", "doris", "4.x", "strict")[:],
  )
  assert_true(lint.contains("fathom.lint.v1"))
  assert_true(fingerprint.contains("fathom.fingerprint.v1"))
  // Original five namespaces still usable (no removal).
  let parsed = @utf8.decode_lossy(
    @binding.fathom_parse_v1(b"SELECT 1", "doris", "4.x", "strict")[:],
  )
  let formatted = @utf8.decode_lossy(
    @binding.fathom_format_v1(
      b"select 1", "doris", "4.x", "strict", "upper", 2, 100, "trailing", "follow",
      true,
    )[:],
  )
  let completed = @utf8.decode_lossy(
    @binding.fathom_complete_v1(b"SELECT FRO", "flink", "flink-2.3.0", 9)[:],
  )
  let error = @utf8.decode_lossy(
    @binding.fathom_parse_v1(b"SELECT 1", "doris", "9.x", "strict")[:],
  )
  let capabilities = @utf8.decode_lossy(@binding.fathom_capabilities_v1()[:])
  assert_true(parsed.contains("fathom.parse.v1"))
  assert_true(formatted.contains("fathom.format.v1"))
  assert_true(completed.contains("fathom.complete.v1"))
  assert_true(error.contains("fathom.error.v1"))
  assert_true(capabilities.contains("fathom.capabilities.v1"))
  // LINE-01 (07-04): fathom.lineage.v1 is the 8th namespace — it appears
  // while all seven prior namespaces above remain usable (Pitfall V6).
  let lineage = @utf8.decode_lossy(
    @binding.fathom_lineage_v1(
      b"SELECT a FROM t", "doris", "4.x", "strict", b"",
    )[:],
  )
  assert_true(lineage.contains("fathom.lineage.v1"))
}

///|
test "exports_are_primitive_and_versioned" {
  let parsed = @binding.fathom_parse_v1(b"select 1", "doris", "4.x", "strict")
  let formatted = @binding.fathom_format_v1(
    b"select 1", "doris", "4.x", "strict", "upper", 2, 100, "trailing", "follow",
    true,
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
  assert_true(
    parsed_text.contains("\"source_bytes\":[115,101,108,101,99,116,32,49]"),
  )
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

///|
test "dialect_selection_is_explicit_end_to_end" {
  // (a) The happy path carries neutral wire identity: fathom.parse.v1 schema,
  // dialect and profile metadata fields, valid=true.
  let ok = @utf8.decode_lossy(
    @binding.fathom_parse_v1(b"SELECT 1", "doris", "4.x", "strict")[:],
  )
  assert_true(ok.contains("fathom.parse.v1"))
  assert_true(ok.contains("\"dialect\":\"doris\""))
  assert_true(ok.contains("\"profile\":\"4.x\""))
  assert_true(ok.contains("\"valid\":true"))
  // (b) Invalid input yields a stable FATHOM-PARSE diagnostic; the error
  // envelope carries fathom.error.v1.
  let bad = @utf8.decode_lossy(
    @binding.fathom_parse_v1(b"SELEKT 1", "doris", "4.x", "strict")[:],
  )
  assert_true(bad.contains("FATHOM-PARSE-"))
  let envelope_error = @utf8.decode_lossy(
    @binding.fathom_parse_v1(b"SELECT 1", "doris", "9.x", "strict")[:],
  )
  assert_true(envelope_error.contains("fathom.error.v1"))
  assert_true(envelope_error.contains("FATHOM-SCHEMA-003"))
  // (c) flink-2.3.0 is a valid Phase 11 selection: the parse envelope carries
  // dialect=flink/profile=flink-2.3.0 and a valid SELECT parses through the
  // real Flink grammar (valid=true — FATHOM-PARSE-008 is retired, D-06) —
  // never a Doris parse and never a silent default (DIALECT-03). An unknown
  // flink profile (the Doris-shaped "2.1") still rejects with the structured
  // FATHOM-SCHEMA-003 profile error.
  let flink = @utf8.decode_lossy(
    @binding.fathom_parse_v1(b"SELECT 1", "flink", "flink-2.3.0", "strict")[:],
  )
  assert_true(flink.contains("fathom.parse.v1"))
  assert_true(flink.contains("\"dialect\":\"flink\""))
  assert_true(flink.contains("\"profile\":\"flink-2.3.0\""))
  assert_true(flink.contains("\"exact_release\":\"flink-2.3.0\""))
  assert_true(flink.contains("\"valid\":true"))
  assert_true(!flink.contains("Doris"))
  let flink_unknown = @utf8.decode_lossy(
    @binding.fathom_parse_v1(b"SELECT 1", "flink", "2.1", "strict")[:],
  )
  assert_true(flink_unknown.contains("fathom.error.v1"))
  assert_true(flink_unknown.contains("FATHOM-SCHEMA-003"))
  // Unknown dialect: structured UnknownDialect error (FATHOM-SCHEMA-007).
  let unknown = @utf8.decode_lossy(
    @binding.fathom_parse_v1(b"SELECT 1", "mysql", "4.x", "strict")[:],
  )
  assert_true(unknown.contains("fathom.error.v1"))
  assert_true(unknown.contains("FATHOM-SCHEMA-007"))
  assert_true(unknown.contains("unknown dialect"))
}

///|
test "format_export_is_dialect_aware_with_neutral_wire_identity" {
  // (a) The happy path carries fathom.format.v1 with dialect/profile/
  // exact_release metadata (DIALECT-04, D-09) — the same envelope shape as
  // the parse result.
  let ok = @utf8.decode_lossy(
    @binding.fathom_format_v1(
      b"select 1", "doris", "4.x", "strict", "upper", 2, 100, "trailing", "follow",
      true,
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
      b"select (", "doris", "4.x", "strict", "upper", 2, 100, "trailing", "follow",
      true,
    )[:],
  )
  assert_true(refused.contains("\"accepted\":false"))
  assert_true(refused.contains("FATHOM-FORMAT-001"))
  let bad_option = @utf8.decode_lossy(
    @binding.fathom_format_v1(
      b"select 1", "doris", "4.x", "strict", "mixed", 2, 100, "trailing", "follow",
      true,
    )[:],
  )
  assert_true(bad_option.contains("fathom.error.v1"))
  assert_true(bad_option.contains("FATHOM-FORMAT-002"))
  // (c) flink-2.3.0 is a valid Phase 11 selection: a valid Flink SELECT parses
  // through the real grammar and the formatter ACCEPTS it (accepted=true) —
  // FATHOM-PARSE-008 is retired (D-06), so the not-implemented refusal is
  // gone. An unknown flink profile (the Doris-shaped "2.1") still rejects with
  // the structured FATHOM-SCHEMA-003 profile error.
  let flink = @utf8.decode_lossy(
    @binding.fathom_format_v1(
      b"select 1", "flink", "flink-2.3.0", "strict", "upper", 2, 100, "trailing",
      "follow", true,
    )[:],
  )
  assert_true(flink.contains("fathom.format.v1"))
  assert_true(flink.contains("\"dialect\":\"flink\""))
  assert_true(flink.contains("\"profile\":\"flink-2.3.0\""))
  assert_true(flink.contains("\"accepted\":true"))
  let flink_unknown = @utf8.decode_lossy(
    @binding.fathom_format_v1(
      b"select 1", "flink", "2.1", "strict", "upper", 2, 100, "trailing", "follow",
      true,
    )[:],
  )
  assert_true(flink_unknown.contains("fathom.error.v1"))
  assert_true(flink_unknown.contains("FATHOM-SCHEMA-003"))
  let unknown = @utf8.decode_lossy(
    @binding.fathom_format_v1(
      b"select 1", "mysql", "4.x", "strict", "upper", 2, 100, "trailing", "follow",
      true,
    )[:],
  )
  assert_true(unknown.contains("fathom.error.v1"))
  assert_true(unknown.contains("FATHOM-SCHEMA-007"))
  assert_true(unknown.contains("unknown dialect"))
}

///|
test "flink_internal_route_parses_select" {
  // (d) The internal Flink route (parser entry, bypassing profile rejection):
  // a directly constructed Flink DialectContext parses a valid SELECT through
  // the real Flink grammar (valid=true, zero diagnostics) — FATHOM-PARSE-008
  // is retired (D-06) and never reused.
  let source = match @source.SourceText::new(b"SELECT 1") {
    Ok(source) => source
    Err(_) => panic()
  }
  let context = (
    {
      dialect: @dialect.Dialect::Flink,
      profile_id: "flink-2.3.0",
      exact_release: "flink-2.3.0",
      feature_introduction: "",
    } : @dialect.DialectContext)
  let parsed = @parser.parse(source, context, @parser.ParseMode::Strict)
  assert_true(parsed.valid)
  assert_eq(parsed.diagnostics.length(), 0)
  let statements = parsed.root.children()
  assert_true(statements.length() >= 1)
  assert_true(statements[0].span().end_byte == source.byte_length())
}

///|
test "completion_export_is_dialect_aware_with_neutral_wire_identity" {
  // (a) The happy path carries fathom.complete.v1 with dialect/profile
  // metadata and bounded completion items — never a Doris fallback and never
  // an empty-silent success (D-04, D-01/D-02, T-13-04-02). The empty-input
  // statement-start context returns the Flink statement-verb candidates.
  let ok = @utf8.decode_lossy(
    @binding.fathom_complete_v1(b"", "flink", "flink-2.3.0", 0)[:],
  )
  assert_true(ok.contains("fathom.complete.v1"))
  assert_true(ok.contains("\"dialect\":\"flink\""))
  assert_true(ok.contains("\"profile\":\"flink-2.3.0\""))
  assert_true(ok.contains("\"items\":"))
  // Neutral item text (D-10/D-28, T-13-04-05): the detail is the neutral
  // constant and no item label leaks a dialect name — the dialect rides in
  // the envelope metadata only.
  assert_true(ok.contains("\"detail\":\"SQL syntax keyword\""))
  assert_true(!ok.contains("\"label\":\"doris"))
  assert_true(!ok.contains("\"label\":\"flink"))
  // (b) An unknown/unsupported flink profile returns the structured
  // fathom.error.v1 envelope with FATHOM-SCHEMA-003 — never a Doris-shaped
  // or empty completion (Pitfall 6).
  let profile_error = @utf8.decode_lossy(
    @binding.fathom_complete_v1(b"", "flink", "flink-9.9.9", 0)[:],
  )
  assert_true(profile_error.contains("fathom.error.v1"))
  assert_true(profile_error.contains("FATHOM-SCHEMA-003"))
  // (c) An unknown dialect returns fathom.error.v1 with FATHOM-SCHEMA-007
  // (dialect-first routing).
  let dialect_error = @utf8.decode_lossy(
    @binding.fathom_complete_v1(b"", "mysql", "4.x", 0)[:],
  )
  assert_true(dialect_error.contains("fathom.error.v1"))
  assert_true(dialect_error.contains("FATHOM-SCHEMA-007"))
  assert_true(dialect_error.contains("unknown dialect"))
}

///|
test "completion_wire_error_matrix_and_source_range_edit" {
  // (a) cursor out-of-range -> fathom.error.v1 (InvalidCursor,
  // FATHOM-COMPLETE-001) — never a panic and never a malformed range
  // (D-04, T-13-04-03). The bounds check is single-sourced in the core
  // (@completion.complete); the export never duplicates it.
  let bad_cursor = @utf8.decode_lossy(
    @binding.fathom_complete_v1(b"SELECT 1", "flink", "flink-2.3.0", 9999)[:],
  )
  assert_true(bad_cursor.contains("fathom.error.v1"))
  assert_true(bad_cursor.contains("FATHOM-COMPLETE-001"))
  assert_true(bad_cursor.contains("invalid cursor"))
  // (b) over-limit input (8 MiB + 1) -> structured error envelope
  // (FATHOM-COMPLETE-003, InputTooLarge) — never a crash (T-13-04-08).
  let oversize = Bytes::make(8 * 1024 * 1024 + 1, 32)
  let over = @utf8.decode_lossy(
    @binding.fathom_complete_v1(oversize, "flink", "flink-2.3.0", 0)[:],
  )
  assert_true(over.contains("fathom.error.v1"))
  assert_true(over.contains("FATHOM-COMPLETE-003"))
  // (c) malformed UTF-8 input (0xFF 0xFE is not a valid UTF-8 sequence)
  // returns the structured fathom.complete.v1 or fathom.error.v1 envelope —
  // never a panic and never an unreadable result (T-13-04-08).
  let malformed = @utf8.decode_lossy(
    @binding.fathom_complete_v1(b"\xff\xfe\x00", "flink", "flink-2.3.0", 1)[:],
  )
  assert_true(
    malformed.contains("fathom.complete.v1") ||
    malformed.contains("fathom.error.v1"),
  )
  // (d) a real cursor over a typed prefix returns a FROM item whose
  // start_byte/end_byte cover the "FRO" prefix: [7,9) == "FR" and
  // end_byte == cursor (source-range edit, T-13-02-06 / D-04).
  let edit = @utf8.decode_lossy(
    @binding.fathom_complete_v1(b"SELECT FRO", "flink", "flink-2.3.0", 9)[:],
  )
  assert_true(edit.contains("fathom.complete.v1"))
  assert_true(edit.contains("\"label\":\"FROM\""))
  assert_true(edit.contains("\"start_byte\":7"))
  assert_true(edit.contains("\"end_byte\":9"))
  assert_true(edit.contains("\"new_text\":\"FROM\""))
}
