/// LINE-01 SC2 cross-target lineage parity (D-07, Phase 12 D-03): the SAME
/// fixture must produce the SAME fathom.lineage.v1 envelope bytes (the edges
/// and gaps arrays with flattened byte spans) on Native, JS, and linear-Wasm.
/// The expected values are hardcoded so any Int-width / serialization /
/// ordering drift on a target fails the assertion (Pitfall 3). Edge/gap
/// ordering is a public contract (Pattern 6): document statement order ->
/// SelectModel branch/CTE order -> SelectItem order -> refs order; star
/// expansion follows scope-entry order x catalog column order
/// (LinkedHashMap determinism). compare_backends.py aggregates the shared
/// parity/__snapshot__ digest across native/js/wasm, so any byte divergence
/// in these fixtures fails the aggregate too (Phase 12 D-03).

test "lineage_export_expression_passthrough_catalog_cross_target" {
  // D-01 expression passthrough: SELECT a + b AS x FROM t -> two edges
  // t.a->x and t.b->x (each projection ref contributes its own edge), both
  // targeting the alias span; no gaps. The catalog_json provides t={a,b}, so
  // the refs resolve to real columns. The same envelope bytes must appear on
  // every target (native/js/wasm).
  let catalog = b"{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"a\",\"data_type\":\"INT\"},{\"name\":\"b\",\"data_type\":\"INT\"}]}]}"
  let text = @utf8.decode_lossy(
    @binding.fathom_lineage_v1(b"SELECT a + b AS x FROM t", "doris", "4.x", "strict", catalog)[:],
  )
  assert_true(text.contains("fathom.lineage.v1"))
  assert_true(text.contains("\"dialect\":\"doris\""))
  assert_true(text.contains("\"profile\":\"4.x\""))
  assert_true(text.contains("\"exact_release\":\"4.x\""))
  assert_true(text.contains("\"edges\":"))
  assert_true(text.contains("\"gaps\":"))
  // Edge 0: t.a -> x (a at [7,8), alias x at [16,17)).
  assert_true(text.contains("\"source_name\":\"a\",\"source_resolved_to\":\"a\",\"source_start_byte\":7,\"source_end_byte\":8,\"target_name\":\"x\",\"target_start_byte\":16,\"target_end_byte\":17"))
  // Edge 1: t.b -> x (b at [11,12), same alias span).
  assert_true(text.contains("\"source_name\":\"b\",\"source_resolved_to\":\"b\",\"source_start_byte\":11,\"source_end_byte\":12,\"target_name\":\"x\",\"target_start_byte\":16,\"target_end_byte\":17"))
  // A fully resolved projection produces no honest gap.
  assert_true(!text.contains("requires-catalog"))
}

test "lineage_export_star_no_catalog_requires_catalog_gap_cross_target" {
  // SC2 / D-05: SELECT * FROM t with empty catalog_json (b"" = no catalog)
  // reports an honest requires-catalog gap at the star span [7,8) — never a
  // fabricated edge (D-06: gaps are strictly separate from edges). The same
  // envelope bytes must appear on every target.
  let text = @utf8.decode_lossy(
    @binding.fathom_lineage_v1(b"SELECT * FROM t", "doris", "4.x", "strict", b"")[:],
  )
  assert_true(text.contains("fathom.lineage.v1"))
  assert_true(text.contains("\"dialect\":\"doris\""))
  assert_true(text.contains("\"edges\":"))
  assert_true(text.contains("\"gaps\":"))
  assert_true(text.contains("\"code\":\"requires-catalog\""))
  assert_true(text.contains("\"start_byte\":7,\"end_byte\":8"))
  // No fabricated edge: the edges array is empty.
  assert_true(!text.contains("\"source_name\":"))
}

test "lineage_export_star_with_catalog_expands_cross_target" {
  // D-05: SELECT * FROM t WITH a catalog expands the star to real
  // passthrough edges (a->a, b->b) in catalog column order (JSON array order,
  // LinkedHashMap determinism); no requires-catalog gap. Both Column bindings
  // share the star span [7,8) (expand_star). Same bytes on every target.
  let catalog = b"{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"a\",\"data_type\":\"INT\"},{\"name\":\"b\",\"data_type\":\"VARCHAR(10)\"}]}]}"
  let text = @utf8.decode_lossy(
    @binding.fathom_lineage_v1(b"SELECT * FROM t", "doris", "4.x", "strict", catalog)[:],
  )
  assert_true(text.contains("fathom.lineage.v1"))
  assert_true(text.contains("\"dialect\":\"doris\""))
  assert_true(text.contains("\"edges\":"))
  assert_true(text.contains("\"gaps\":"))
  // a -> a at the star span.
  assert_true(text.contains("\"source_name\":\"a\",\"source_resolved_to\":\"a\",\"source_start_byte\":7,\"source_end_byte\":8,\"target_name\":\"a\",\"target_start_byte\":7,\"target_end_byte\":8"))
  // b -> b at the star span.
  assert_true(text.contains("\"source_name\":\"b\",\"source_resolved_to\":\"b\",\"source_start_byte\":7,\"source_end_byte\":8,\"target_name\":\"b\",\"target_start_byte\":7,\"target_end_byte\":8"))
  // The catalog resolves the star, so no requires-catalog gap.
  assert_true(!text.contains("requires-catalog"))
}
