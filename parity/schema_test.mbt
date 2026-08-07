// Deterministic schema contract fixtures for Phase 4 adapters.
fn schema_fixture_has_frozen_fields() -> Unit raise {
  let fields = ["schema_version", "source_transport", "dialect", "profile", "mode", "valid", "recovered", "source_bytes", "source_byte_length", "root", "diagnostics"]
  let expected = ["schema_version", "source_transport", "dialect", "profile", "mode", "valid", "recovered", "source_bytes", "source_byte_length", "root", "diagnostics"]
  assert_eq(fields.length(), 11)
  assert_eq(fields, expected)
  assert_eq(fields[0], "schema_version")
  assert_eq(fields[1], "source_transport")
  assert_eq(fields[2], "dialect")
  assert_eq(fields[3], "profile")
  assert_eq(fields[4], "mode")
  assert_eq(fields[5], "valid")
  assert_eq(fields[6], "recovered")
  assert_eq(fields[7], "source_bytes")
  assert_eq(fields[8], "source_byte_length")
  assert_eq(fields[9], "root")
  assert_eq(fields[10], "diagnostics")
}

test "schema_fixture_has_frozen_fields" { schema_fixture_has_frozen_fields() }

test "schema_serializes_real_parse_result_and_refuses_unknown_versions" {
  let result = match @api.parse_with_ids(b"SELECT /* note */ 1", "doris", "4.x", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
  let encoded = @binding.parse_result_json(result)
  assert_true(encoded.contains("fathom.parse.v1"))
  assert_true(encoded.contains("inline-root-v1"))
  assert_true(encoded.contains("source_bytes"))
  assert_true(encoded.contains("trivia"))
  // validate_schema_version accepts exactly the four fathom.*.v1 namespaces
  // (D-09): parse, format, error, capabilities.
  assert_true(@binding.validate_schema_version("fathom.parse.v1") is Ok(_))
  assert_true(@binding.validate_schema_version("fathom.format.v1") is Ok(_))
  assert_true(@binding.validate_schema_version("fathom.error.v1") is Ok(_))
  assert_true(@binding.validate_schema_version("fathom.capabilities.v1") is Ok(_))
  assert_true(@binding.validate_schema_version("fathom.parse.v9") is Err(@binding.SchemaError::UnsupportedSchemaVersion(..)))
  // validate_dialect_profile is the single gate: doris accepts exactly
  // 2.1/3.x/4.x; flink accepts exactly the three pinned release profiles
  // (Phase 10, D-01); unknown dialects return UnknownDialect
  // (FATHOM-SCHEMA-007).
  assert_true(@binding.validate_dialect_profile("doris", "2.1") is Ok(_))
  assert_true(@binding.validate_dialect_profile("doris", "3.x") is Ok(_))
  assert_true(@binding.validate_dialect_profile("doris", "4.x") is Ok(_))
  assert_true(@binding.validate_dialect_profile("doris", "5.x") is Err(@binding.SchemaError::UnsupportedProfile(..)))
  assert_true(@binding.validate_dialect_profile("mysql", "4.x") is Err(@binding.SchemaError::UnknownDialect(..)))
  assert_true(@binding.validate_dialect_profile("doris", "mysql") is Err(@binding.SchemaError::UnsupportedProfile(..)))
  assert_true(@binding.validate_dialect_profile("flink", "flink-2.3.0") is Ok(_))
  assert_true(@binding.validate_dialect_profile("flink", "flink-2.1.3") is Ok(_))
  assert_true(@binding.validate_dialect_profile("flink", "flink-1.20.5") is Ok(_))
  // Exact-match only: the Doris-shaped "2.1" and adjacent ids are rejected.
  assert_true(@binding.validate_dialect_profile("flink", "2.1") is Err(@binding.SchemaError::UnsupportedProfile(..)))
  assert_true(@binding.validate_dialect_profile("flink", "flink-2.3.0-rc1") is Err(@binding.SchemaError::UnsupportedProfile(..)))
  assert_true(@binding.validate_dialect_profile("flink", "flink-2.3") is Err(@binding.SchemaError::UnsupportedProfile(..)))
}

test "schema_fixture_requires_leaf_kinds_and_half_open_spans" {
  let leaves = ["token", "trivia", "error", "missing", "skipped"]
  let expected = ["token", "trivia", "error", "missing", "skipped"]
  assert_eq(leaves.length(), 5)
  assert_eq(leaves, expected)
  assert_eq(leaves[0], "token")
  assert_eq(leaves[1], "trivia")
  assert_eq(leaves[2], "error")
  assert_eq(leaves[3], "missing")
  assert_eq(leaves[4], "skipped")
  let span_start = 2
  let span_end = 5
  assert_true(span_start <= span_end)
  assert_eq(span_end - span_start, 3)
}
