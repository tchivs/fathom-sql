///|
/// FING-01 SC4 cross-target fingerprint parity (D-08): the SAME fixture must
/// produce the SAME decimal fingerprint string on Native, JS, and linear-Wasm.
/// The expected value is hardcoded so any Int-width / serialization drift on a
/// target fails the assertion (Pitfall 3). The wire envelope asserts the
/// UInt64 fingerprint is a DECIMAL STRING — never a JSON number (2^53
/// precision, T-06-01-01).
test "fingerprint_export_stable_cross_target_decimal_string" {
  // SELECT 1 normalizes to "select 1"; FNV-1a 64-bit is deterministic. The
  // same decimal string must appear on every target (native/js/wasm).
  let text = @utf8.decode_lossy(
    @binding.fathom_fingerprint_v1(b"SELECT 1", "doris", "4.x", "strict")[:],
  )
  assert_true(text.contains("fathom.fingerprint.v1"))
  assert_true(text.contains("\"dialect\":\"doris\""))
  assert_true(text.contains("\"profile\":\"4.x\""))
  assert_true(text.contains("\"fingerprint\":\"214897735614764786\""))
  assert_true(text.contains("\"normalized\":[115,101,108,101,99,116,32,49]"))
  // Never a JSON number form (to_double would round above 2^53).
  assert_true(!text.contains("\"fingerprint\":214897735614764786"))
}

///|
test "fingerprint_export_stable_across_trivia_case_and_comments" {
  let a = @utf8.decode_lossy(
    @binding.fathom_fingerprint_v1(b"SELECT 1", "doris", "4.x", "strict")[:],
  )
  let b = @utf8.decode_lossy(
    @binding.fathom_fingerprint_v1(b"select\n 1", "doris", "4.x", "strict")[:],
  )
  let c = @utf8.decode_lossy(
    @binding.fathom_fingerprint_v1(b"SELECT /*c*/ 1", "doris", "4.x", "strict")[:],
  )
  assert_true(a.contains("\"fingerprint\":\"214897735614764786\""))
  assert_true(b.contains("\"fingerprint\":\"214897735614764786\""))
  assert_true(c.contains("\"fingerprint\":\"214897735614764786\""))
}

///|
test "fingerprint_export_preserves_quote_style_identifier_case_literals" {
  // SELECT "A" (double-quoted identifier) vs SELECT 'A' (string literal):
  // the normalized byte arrays differ -> different fingerprints (FING-01
  // retention contract; identifiers/literals/quote style are preserved).
  let double = @utf8.decode_lossy(
    @binding.fathom_fingerprint_v1(b"SELECT \"A\"", "doris", "4.x", "strict")[:],
  )
  let single = @utf8.decode_lossy(
    @binding.fathom_fingerprint_v1(b"SELECT 'A'", "doris", "4.x", "strict")[:],
  )
  // "select \"A\"" bytes
  assert_true(
    double.contains("\"normalized\":[115,101,108,101,99,116,32,34,65,34]"),
  )
  // "select 'A'" bytes
  assert_true(
    single.contains("\"normalized\":[115,101,108,101,99,116,32,39,65,39]"),
  )
  // identifier case preserved: SELECT A != SELECT a
  let upper = @utf8.decode_lossy(
    @binding.fathom_fingerprint_v1(b"SELECT A", "doris", "4.x", "strict")[:],
  )
  let lower = @utf8.decode_lossy(
    @binding.fathom_fingerprint_v1(b"SELECT a", "doris", "4.x", "strict")[:],
  )
  // "select A" = ...65 ; "select a" = ...97
  assert_true(upper.contains("\"normalized\":[115,101,108,101,99,116,32,65]"))
  assert_true(lower.contains("\"normalized\":[115,101,108,101,99,116,32,97]"))
}

///|
test "lint_export_is_additive_and_primitive" {
  // fathom_lint_v1 with the default registry (empty overrides array) reports
  // the select-star finding on the wire (LINT-01; schema v2 additive, the old
  // five namespaces are asserted in export_smoke_test.mbt).
  let text = @utf8.decode_lossy(
    @binding.fathom_lint_v1(
      b"SELECT * FROM t", "doris", "4.x", "strict", b"[]", false,
    )[:],
  )
  assert_true(text.contains("fathom.lint.v1"))
  assert_true(text.contains("\"dialect\":\"doris\""))
  assert_true(text.contains("\"profile\":\"4.x\""))
  assert_true(text.contains("\"accepted\":true"))
  assert_true(text.contains("FATHOM-LINT-003"))
  // invalid overrides JSON -> structured error, never a silent default
  let bad = @utf8.decode_lossy(
    @binding.fathom_lint_v1(
      b"SELECT 1", "doris", "4.x", "strict", b"not-json", false,
    )[:],
  )
  assert_true(bad.contains("fathom.error.v1"))
  assert_true(bad.contains("FATHOM-SCHEMA-004"))
}
