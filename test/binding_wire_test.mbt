/// Binding-package wire tests (07-04). The binding package is a
/// `foreign_library`: `#export_name` cannot compile when binding is the
/// DIRECT target of a native test build (moon 0.1.20260724, error 4219), so
/// the wire behavior is exercised here — in the integration test package that
/// imports @binding as a dependency (same pattern as parity/export_smoke_test
/// running on js/wasm, but natively testable). The catalog_json / fathom_lineage_v1
/// tests live here because binding itself cannot host native test blocks.

test "binding_lineage_v1_envelope_contains_metadata_edges_gaps" {
  // LINE-01 / D-07: the fathom.lineage.v1 envelope carries the schema
  // version, source transport, dialect/profile/exact_release metadata, source
  // bytes, and the edges + gaps arrays.
  let out = @binding.fathom_lineage_v1(b"SELECT a FROM t", "doris", "4.x", "strict", b"")
  let text = @utf8.decode_lossy(out[:])
  assert_true(text.contains("fathom.lineage.v1"))
  assert_true(text.contains("\"dialect\":\"doris\""))
  assert_true(text.contains("\"profile\":\"4.x\""))
  assert_true(text.contains("\"exact_release\":\"4.x\""))
  assert_true(text.contains("\"edges\":"))
  assert_true(text.contains("\"gaps\":"))
}

test "binding_lineage_v1_flink_gate_structured_error" {
  // D-08 / T-07-04-01: a valid flink selection is rejected with the
  // structured FATHOM-SCHEMA-003 error envelope and the explicit
  // "lineage is Doris-only" message — NEVER a silent empty result.
  let out = @binding.fathom_lineage_v1(b"SELECT 1", "flink", "flink-2.3.0", "strict", b"")
  let text = @utf8.decode_lossy(out[:])
  assert_true(text.contains("fathom.error.v1"))
  assert_true(text.contains("FATHOM-SCHEMA-003"))
  assert_true(text.contains("lineage is Doris-only"))
}

test "binding_validate_schema_version_lineage_8th_additive" {
  // Pitfall V6: the 8th namespace fathom.lineage.v1 is accepted while all
  // seven existing namespaces keep their branches untouched (pure addition).
  assert_eq(@binding.validate_schema_version("fathom.lineage.v1"), Ok(()))
  assert_eq(@binding.validate_schema_version("fathom.parse.v1"), Ok(()))
  assert_eq(@binding.validate_schema_version("fathom.format.v1"), Ok(()))
  assert_eq(@binding.validate_schema_version("fathom.complete.v1"), Ok(()))
  assert_eq(@binding.validate_schema_version("fathom.lint.v1"), Ok(()))
  assert_eq(@binding.validate_schema_version("fathom.fingerprint.v1"), Ok(()))
  assert_eq(@binding.validate_schema_version("fathom.error.v1"), Ok(()))
  assert_eq(@binding.validate_schema_version("fathom.capabilities.v1"), Ok(()))
}

test "binding_lineage_v1_unknown_dialect_structured_error" {
  // Dialect-first validation (Pitfall 6): an unknown dialect maps to the
  // fathom.error.v1 envelope with FATHOM-SCHEMA-007 before any lineage work.
  let out = @binding.fathom_lineage_v1(b"SELECT 1", "mysql", "4.x", "strict", b"")
  let text = @utf8.decode_lossy(out[:])
  assert_true(text.contains("fathom.error.v1"))
  assert_true(text.contains("FATHOM-SCHEMA-007"))
  assert_true(text.contains("unknown dialect"))
}
