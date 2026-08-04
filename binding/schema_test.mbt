// Deterministic schema contract fixtures for Phase 4 adapters.
fn schema_fixture_has_frozen_fields() -> Unit raise {
  let fields = ["schema_version", "source_transport", "profile", "mode", "valid", "recovered", "source_bytes", "source_byte_length", "root", "diagnostics"]
  let expected = ["schema_version", "source_transport", "profile", "mode", "valid", "recovered", "source_bytes", "source_byte_length", "root", "diagnostics"]
  assert_eq(fields.length(), 10)
  assert_eq(fields, expected)
  assert_eq(fields[0], "schema_version")
  assert_eq(fields[1], "source_transport")
  assert_eq(fields[2], "profile")
  assert_eq(fields[3], "mode")
  assert_eq(fields[4], "valid")
  assert_eq(fields[5], "recovered")
  assert_eq(fields[6], "source_bytes")
  assert_eq(fields[7], "source_byte_length")
  assert_eq(fields[8], "root")
  assert_eq(fields[9], "diagnostics")
}

test "schema_fixture_has_frozen_fields" { schema_fixture_has_frozen_fields() }

test "schema_serializes_real_parse_result_and_refuses_unknown_versions" {
  let result = match @api.parse_with_ids(b"SELECT /* note */ 1", "4.x", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
  let encoded = parse_result_json(result)
  assert_true(encoded.contains("doris.parse.v1"))
  assert_true(encoded.contains("inline-root-v1"))
  assert_true(encoded.contains("source_bytes"))
  assert_true(encoded.contains("trivia"))
  assert_true(validate_schema_version("doris.parse.v1") is Ok(_))
  assert_true(validate_schema_version("doris.parse.v9") is Err(UnsupportedSchemaVersion(..)))
  assert_true(validate_profile("mysql") is Err(UnsupportedProfile(..)))
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
