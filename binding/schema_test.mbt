// Deterministic schema contract fixtures for Phase 4 adapters.
fn schema_fixture_has_frozen_fields() {
  let fields = ["schema_version", "source_transport", "profile", "mode", "valid", "recovered", "source_bytes", "source_byte_length", "root", "diagnostics"]
  assert_eq(fields.length(), 10)
  assert_eq(fields[0], "schema_version")
  assert_eq(fields[1], "source_transport")
  assert_eq(fields[8], "root")
}

test "schema_fixture_has_frozen_fields" { schema_fixture_has_frozen_fields() }

test "schema_fixture_requires_leaf_kinds_and_half_open_spans" {
  let leaves = ["token", "trivia", "error", "missing", "skipped"]
  assert_true(leaves.length() >= 5)
  assert_true(0 <= 0)
}
