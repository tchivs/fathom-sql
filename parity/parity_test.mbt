test "parity_fixture_compares_decoded_contract_not_host_objects" {
  let targets = ["native", "js", "wasm"]
  let expected_targets = ["native", "js", "wasm"]
  let fields = ["schema_version", "source_bytes", "root", "diagnostics", "profile", "statement_offsets"]
  let expected_fields = ["schema_version", "source_bytes", "root", "diagnostics", "profile", "statement_offsets"]
  assert_eq(targets.length(), 3)
  assert_eq(targets, expected_targets)
  assert_eq(targets[0], "native")
  assert_eq(targets[1], "js")
  assert_eq(targets[2], "wasm")
  assert_eq(fields.length(), 6)
  assert_eq(fields, expected_fields)
  assert_eq(fields[0], "schema_version")
  assert_eq(fields[1], "source_bytes")
  assert_eq(fields[2], "root")
  assert_eq(fields[3], "diagnostics")
  assert_eq(fields[4], "profile")
  assert_eq(fields[5], "statement_offsets")
}
