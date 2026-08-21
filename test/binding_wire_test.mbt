///|
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
  let out = @binding.fathom_lineage_v1(
    b"SELECT a FROM t", "doris", "4.x", "strict", b"",
  )
  let text = @utf8.decode_lossy(out[:])
  assert_true(text.contains("fathom.lineage.v1"))
  assert_true(text.contains("\"dialect\":\"doris\""))
  assert_true(text.contains("\"profile\":\"4.x\""))
  assert_true(text.contains("\"exact_release\":\"4.x\""))
  assert_true(text.contains("\"edges\":"))
  assert_true(text.contains("\"gaps\":"))
}

///|
test "binding_lineage_v1_flink_gate_structured_error" {
  // D-08 / T-07-04-01: a valid flink selection is rejected with the
  // structured FATHOM-SCHEMA-003 error envelope and the explicit
  // "lineage is Doris-only" message — NEVER a silent empty result.
  let out = @binding.fathom_lineage_v1(
    b"SELECT 1", "flink", "flink-2.3.0", "strict", b"",
  )
  let text = @utf8.decode_lossy(out[:])
  assert_true(text.contains("fathom.error.v1"))
  assert_true(text.contains("FATHOM-SCHEMA-003"))
  assert_true(text.contains("lineage is Doris-only"))
}

///|
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

///|
test "binding_lineage_v1_unknown_dialect_structured_error" {
  // Dialect-first validation (Pitfall 6): an unknown dialect maps to the
  // fathom.error.v1 envelope with FATHOM-SCHEMA-007 before any lineage work.
  let out = @binding.fathom_lineage_v1(
    b"SELECT 1", "mysql", "4.x", "strict", b"",
  )
  let text = @utf8.decode_lossy(out[:])
  assert_true(text.contains("fathom.error.v1"))
  assert_true(text.contains("FATHOM-SCHEMA-007"))
  assert_true(text.contains("unknown dialect"))
}

///|
test "binding_parse_catalog_json_empty_bytes_and_empty_object_no_catalog" {
  // D-05: empty bytes and "{}" both mean no catalog (Ok(None)) — every
  // star/external view reports an honest requires-catalog gap (SC2).
  match @binding.parse_catalog_json(b"") {
    Ok(None) => ()
    _ => assert_true(false)
  }
  match @binding.parse_catalog_json(b"{}") {
    Ok(None) => ()
    _ => assert_true(false)
  }
}

///|
test "binding_parse_catalog_json_tables_builds_catalog" {
  // A {tables: [...]} document builds a StaticCatalog; column order is the
  // JSON array order (LinkedHashMap determinism — the star-expansion parity
  // contract, Pattern 6).
  let json = b"{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"a\",\"data_type\":\"INT\"},{\"name\":\"b\",\"data_type\":\"VARCHAR\"}]}]}"
  match @binding.parse_catalog_json(json) {
    Ok(Some(catalog)) => {
      let table = catalog.lookup("t")
      match table {
        Some(table) => {
          assert_eq(table.name, "t")
          assert_eq(table.columns.length(), 2)
          assert_eq(table.columns[0].name, "a")
          assert_eq(table.columns[0].data_type, "INT")
          assert_eq(table.columns[1].name, "b")
        }
        None => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "binding_parse_catalog_json_db_tables_and_functions" {
  // {db_tables: [...]} routes through StaticCatalog::with_db and
  // {functions: [...]} through with_function (D-05).
  let json = b"{\"db_tables\":[{\"db\":\"db1\",\"name\":\"t\",\"table\":{\"name\":\"t\",\"columns\":[{\"name\":\"a\",\"data_type\":\"INT\"}]}}],\"functions\":[{\"name\":\"f\",\"param_types\":[\"INT\",\"INT\"],\"return_type\":\"INT\",\"min_arity\":1}]}"
  match @binding.parse_catalog_json(json) {
    Ok(Some(catalog)) => {
      let table = catalog.lookup_in_db("db1", "t")
      match table {
        Some(table) => {
          assert_eq(table.name, "t")
          assert_eq(table.columns.length(), 1)
          assert_eq(table.columns[0].name, "a")
        }
        None => assert_true(false)
      }
      let function = catalog.lookup_function("f")
      match function {
        Some(function) => {
          assert_eq(function.name, "f")
          assert_eq(function.param_types.length(), 2)
          assert_eq(function.param_types[0], "INT")
          assert_eq(function.return_type, "INT")
          assert_eq(function.min_arity, 1)
        }
        None => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "binding_parse_catalog_json_invalid_inputs_structured_errors" {
  // T-07-04-02 / T-06-03-01 / ASVS V5: malformed UTF-8, malformed JSON, a
  // non-object root, type-mismatched fields, and missing required fields are
  // structured Err(String) — NEVER a silent fallback to the no-catalog
  // behavior.
  match @binding.parse_catalog_json(b"\xff\xfe\x00") {
    Err(message) => assert_true(message.contains("invalid UTF-8"))
    _ => assert_true(false)
  }
  match @binding.parse_catalog_json(b"not json") {
    Err(message) => assert_true(message.contains("malformed JSON"))
    _ => assert_true(false)
  }
  match @binding.parse_catalog_json(b"[1,2]") {
    Err(message) => assert_true(message.contains("must be an object"))
    _ => assert_true(false)
  }
  match @binding.parse_catalog_json(b"{\"tables\":42}") {
    Err(message) => assert_true(message.contains("'tables' must be an array"))
    _ => assert_true(false)
  }
  match @binding.parse_catalog_json(b"{\"tables\":[{\"columns\":[]}]}") {
    Err(message) => assert_true(message.contains("missing string name"))
    _ => assert_true(false)
  }
  match
    @binding.parse_catalog_json(
      b"{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"a\"}]}]}",
    ) {
    Err(message) => assert_true(message.contains("missing string data_type"))
    _ => assert_true(false)
  }
}

///|
test "binding_lineage_v1_bad_catalog_json_structured_004_error" {
  // T-07-04-02 / ASVS V5: a malformed catalog_json reaches the wire as a
  // structured FATHOM-SCHEMA-004 error envelope — never a silent fallback to
  // the no-catalog behavior.
  let out = @binding.fathom_lineage_v1(
    b"SELECT * FROM t", "doris", "4.x", "strict", b"{\"tables\":42}",
  )
  let text = @utf8.decode_lossy(out[:])
  assert_true(text.contains("fathom.error.v1"))
  assert_true(text.contains("FATHOM-SCHEMA-004"))
}
