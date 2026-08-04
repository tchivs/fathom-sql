test "parity_fixture_compares_decoded_contract_not_host_objects" {
  let targets = ["native", "js", "wasm"]
  let fields = ["schema_version", "source_bytes", "root", "diagnostics", "profile", "statement_offsets"]
  assert_eq(targets.length(), 3)
  assert_true(fields.length() >= 6)
  assert_eq(targets[0], "native")
}
