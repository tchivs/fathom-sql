/// D-04 flink-lexical snapshot group (Phase 10 waves 1-2): an independent
/// namespace under parity/__snapshot__/ that freezes the D-06 lexical conflicts
/// under both dialects. Wave 1 (10-01) froze the `#` line-comment character;
/// wave 2 (10-02) adds the full conflict matrix: double-quote, slash-comment,
/// E-literal version gate, backtick double-escape, and the unknown-profile
/// rejection. The same raw input tokenizes differently per dialect
/// (DIALECT-02/03/06) and each path is explainable by its snapshot — no silent
/// borrowing of the other dialect's policy.
///
/// The flink-lexical group is an INDEPENDENT namespace (Pitfall 7): filenames
/// are `flink-lexical.{fixture}.{profile}.{mode}.json` and never overlap the
/// Doris baseline group; the Doris 213 snapshots stay byte-identical.
///
/// Generation: `moon test --update --package parity` after the approved-changes
/// register entry is committed (D-08 single-use approval path). CI runs
/// `moon test --package parity` WITHOUT --update so any byte drift fails.

pub(all) struct FlinkLexicalFixture {
  pub fixture_id : String
  pub dialect : String
  pub profile : String
  pub raw : Bytes
}

/// Wave-1 + wave-2 conflict-matrix fixtures. Each D-06 entry is frozen under
/// the relevant flink release profile(s) AND the corresponding doris profile so
/// the same input's different tokenization is frozen side by side. Per-release
/// profile rows come from parity/fixtures/flink-lexical/manifest.tsv
/// (calcite_version/parser_config/url/sha512/tag/commit).
let flink_lexical_fixtures : Array[FlinkLexicalFixture] = [
  // Wave 1 (10-01): `#` is a Doris line comment but a Flink lexical error.
  {
    fixture_id: "hash-comment",
    dialect: "flink",
    profile: "flink-2.3.0",
    raw: b"a # comment",
  },
  {
    fixture_id: "hash-comment",
    dialect: "doris",
    profile: "4.x",
    raw: b"a # comment",
  },
  // Wave 2 (10-02): double-quote — Flink DOUBLE_QUOTE symbol (Parser-calcite-1.36.0.jj:8797)
  // vs Doris Quoted.
  {
    fixture_id: "double-quote",
    dialect: "flink",
    profile: "flink-2.3.0",
    raw: b"SELECT \"a\" FROM t",
  },
  {
    fixture_id: "double-quote",
    dialect: "doris",
    profile: "4.x",
    raw: b"SELECT \"a\" FROM t",
  },
  // Wave 2: slash-comment — Flink SINGLE_LINE_COMMENT `//` (:8901) vs Doris two SLASH symbols.
  {
    fixture_id: "slash-comment",
    dialect: "flink",
    profile: "flink-2.3.0",
    raw: b"SELECT a // comment",
  },
  {
    fixture_id: "slash-comment",
    dialect: "doris",
    profile: "4.x",
    raw: b"SELECT a // comment",
  },
  // Wave 2: E'..' — C_STYLE_ESCAPED_STRING_LITERAL under flink-2.3.0/2.1.3 (:8721/8469),
  // absent under flink-1.20.5 (Calcite 1.32.0); doris has no E-literal prefix.
  {
    fixture_id: "e-literal",
    dialect: "flink",
    profile: "flink-2.3.0",
    raw: b"SELECT E'abc'",
  },
  {
    fixture_id: "e-literal",
    dialect: "flink",
    profile: "flink-2.1.3",
    raw: b"SELECT E'abc'",
  },
  {
    fixture_id: "e-literal",
    dialect: "flink",
    profile: "flink-1.20.5",
    raw: b"SELECT E'abc'",
  },
  {
    fixture_id: "e-literal",
    dialect: "doris",
    profile: "4.x",
    raw: b"SELECT E'abc'",
  },
  // Wave 2: backtick double-escape — BTID under Flink (:8951-8962) vs Doris
  // scan_quoted doubling; both lex one Quoted token, each path frozen separately.
  {
    fixture_id: "backtick-escape",
    dialect: "flink",
    profile: "flink-2.3.0",
    raw: b"SELECT `a``b`",
  },
  {
    fixture_id: "backtick-escape",
    dialect: "doris",
    profile: "4.x",
    raw: b"SELECT `a``b`",
  },
  // Wave 2: unknown-profile — a Doris-shaped profile id under flink is rejected
  // (Pitfall 6, D-01 exact-match from_id) with the shared FATHOM-SCHEMA-003
  // envelope (D-05, no FATHOM-FLINK-* namespace). The frozen envelope carries
  // the rejection under the flink-4x profile slot — the Doris-shaped profile
  // string the fixture exercises.
  {
    fixture_id: "unknown-profile",
    dialect: "flink",
    profile: "4.x",
    raw: b"SELECT 1",
  },
]

fn flink_lexical_fixture(id : String, dialect : String, profile : String) -> FlinkLexicalFixture {
  for fixture in flink_lexical_fixtures {
    if fixture.fixture_id == id && fixture.dialect == dialect && fixture.profile == profile {
      return fixture
    }
  }
  panic()
}

fn flink_lexical_parse_json(id : String, dialect : String, profile : String, mode : String) -> String {
  let fixture = flink_lexical_fixture(id, dialect, profile)
  @utf8.decode_lossy(@binding.fathom_parse_v1(fixture.raw, dialect, profile, mode)[:])
}

fn flink_snapshot_test(t : @test.Test, content : String, filename : String) -> Unit raise SnapshotError {
  t.write(content)
  t.snapshot(filename=filename)
}

// ---------------------------------------------------------------------------
// hash-comment conflict matrix (D-06): the same raw under flink-2.3.0 vs
// doris-4.x tokenizes differently and each path is frozen independently.
// ---------------------------------------------------------------------------
test "flink-lexical hash-comment flink-2.3.0 strict" {
  let t = @test.Test("flink-lexical hash-comment flink-2.3.0 strict")
  flink_snapshot_test(t, flink_lexical_parse_json("hash-comment", "flink", "flink-2.3.0", "strict"), "flink-lexical.hash-comment.flink-2.3.0.strict.json")
}

test "flink-lexical hash-comment flink-2.3.0 editor" {
  let t = @test.Test("flink-lexical hash-comment flink-2.3.0 editor")
  flink_snapshot_test(t, flink_lexical_parse_json("hash-comment", "flink", "flink-2.3.0", "editor"), "flink-lexical.hash-comment.flink-2.3.0.editor.json")
}

test "flink-lexical hash-comment doris-4.x strict" {
  let t = @test.Test("flink-lexical hash-comment doris-4.x strict")
  flink_snapshot_test(t, flink_lexical_parse_json("hash-comment", "doris", "4.x", "strict"), "flink-lexical.hash-comment.doris-4.x.strict.json")
}

test "flink-lexical hash-comment doris-4.x editor" {
  let t = @test.Test("flink-lexical hash-comment doris-4.x editor")
  flink_snapshot_test(t, flink_lexical_parse_json("hash-comment", "doris", "4.x", "editor"), "flink-lexical.hash-comment.doris-4.x.editor.json")
}

/// D-06 conflict contract: the same input must NOT tokenize identically under
/// both dialects. The flink path carries the FATHOM-PARSE-003 `#` lexical
/// error; the doris path carries no such diagnostic (the `#` is a comment).
test "flink_lexical_hash_comment_is_dialect_routed_and_independent" {
  let flink_strict = flink_lexical_parse_json("hash-comment", "flink", "flink-2.3.0", "strict")
  let doris_strict = flink_lexical_parse_json("hash-comment", "doris", "4.x", "strict")
  assert_true(flink_strict.contains("\"dialect\":\"flink\""))
  assert_true(flink_strict.contains("\"profile\":\"flink-2.3.0\""))
  assert_true(flink_strict.contains("FATHOM-PARSE-008"))
  assert_true(flink_strict.contains("FATHOM-PARSE-003"))
  assert_true(doris_strict.contains("\"dialect\":\"doris\""))
  assert_true(doris_strict.contains("\"profile\":\"4.x\""))
  // Doris `#` is a comment: no FATHOM-PARSE-003 lexical diagnostic appears.
  assert_true(!doris_strict.contains("FATHOM-PARSE-003"))
  // Independent namespaces: the flink group never leaks into the doris group.
  assert_true(!flink_strict.contains("\"dialect\":\"doris\""))
  assert_true(!doris_strict.contains("\"dialect\":\"flink\""))
}

// ---------------------------------------------------------------------------
// double-quote conflict matrix (D-06): Flink `"` is a DOUBLE_QUOTE symbol
// (Parser-calcite-1.36.0.jj:8797), Doris `"x"` is one Quoted token.
// ---------------------------------------------------------------------------
test "flink-lexical double-quote flink-2.3.0 strict" {
  let t = @test.Test("flink-lexical double-quote flink-2.3.0 strict")
  flink_snapshot_test(t, flink_lexical_parse_json("double-quote", "flink", "flink-2.3.0", "strict"), "flink-lexical.double-quote.flink-2.3.0.strict.json")
}

test "flink-lexical double-quote flink-2.3.0 editor" {
  let t = @test.Test("flink-lexical double-quote flink-2.3.0 editor")
  flink_snapshot_test(t, flink_lexical_parse_json("double-quote", "flink", "flink-2.3.0", "editor"), "flink-lexical.double-quote.flink-2.3.0.editor.json")
}

test "flink-lexical double-quote doris-4.x strict" {
  let t = @test.Test("flink-lexical double-quote doris-4.x strict")
  flink_snapshot_test(t, flink_lexical_parse_json("double-quote", "doris", "4.x", "strict"), "flink-lexical.double-quote.doris-4.x.strict.json")
}

test "flink-lexical double-quote doris-4.x editor" {
  let t = @test.Test("flink-lexical double-quote doris-4.x editor")
  flink_snapshot_test(t, flink_lexical_parse_json("double-quote", "doris", "4.x", "editor"), "flink-lexical.double-quote.doris-4.x.editor.json")
}

test "flink_lexical_double_quote_is_dialect_routed_and_independent" {
  let flink_strict = flink_lexical_parse_json("double-quote", "flink", "flink-2.3.0", "strict")
  let doris_strict = flink_lexical_parse_json("double-quote", "doris", "4.x", "strict")
  assert_true(flink_strict.contains("\"dialect\":\"flink\""))
  assert_true(flink_strict.contains("\"profile\":\"flink-2.3.0\""))
  assert_true(flink_strict.contains("FATHOM-PARSE-008"))
  // Flink: `"` at byte 7 is a 1-byte DOUBLE_QUOTE Symbol (7-8); Doris: `"a"` is one Quoted (7-10).
  assert_true(flink_strict.contains("\"start_byte\":7,\"end_byte\":8"))
  assert_true(!flink_strict.contains("\"start_byte\":7,\"end_byte\":10"))
  assert_true(doris_strict.contains("\"dialect\":\"doris\""))
  assert_true(doris_strict.contains("\"profile\":\"4.x\""))
  assert_true(doris_strict.contains("\"start_byte\":7,\"end_byte\":10"))
  assert_true(!doris_strict.contains("FATHOM-PARSE-008"))
  assert_true(!flink_strict.contains("\"dialect\":\"doris\""))
  assert_true(!doris_strict.contains("\"dialect\":\"flink\""))
}

// ---------------------------------------------------------------------------
// slash-comment conflict matrix (D-06): Flink `//` is SINGLE_LINE_COMMENT
// (Parser-calcite-1.36.0.jj:8901), Doris lexes `//` as two SLASH symbols.
// ---------------------------------------------------------------------------
test "flink-lexical slash-comment flink-2.3.0 strict" {
  let t = @test.Test("flink-lexical slash-comment flink-2.3.0 strict")
  flink_snapshot_test(t, flink_lexical_parse_json("slash-comment", "flink", "flink-2.3.0", "strict"), "flink-lexical.slash-comment.flink-2.3.0.strict.json")
}

test "flink-lexical slash-comment flink-2.3.0 editor" {
  let t = @test.Test("flink-lexical slash-comment flink-2.3.0 editor")
  flink_snapshot_test(t, flink_lexical_parse_json("slash-comment", "flink", "flink-2.3.0", "editor"), "flink-lexical.slash-comment.flink-2.3.0.editor.json")
}

test "flink-lexical slash-comment doris-4.x strict" {
  let t = @test.Test("flink-lexical slash-comment doris-4.x strict")
  flink_snapshot_test(t, flink_lexical_parse_json("slash-comment", "doris", "4.x", "strict"), "flink-lexical.slash-comment.doris-4.x.strict.json")
}

test "flink-lexical slash-comment doris-4.x editor" {
  let t = @test.Test("flink-lexical slash-comment doris-4.x editor")
  flink_snapshot_test(t, flink_lexical_parse_json("slash-comment", "doris", "4.x", "editor"), "flink-lexical.slash-comment.doris-4.x.editor.json")
}

test "flink_lexical_slash_comment_is_dialect_routed_and_independent" {
  let flink_strict = flink_lexical_parse_json("slash-comment", "flink", "flink-2.3.0", "strict")
  let doris_strict = flink_lexical_parse_json("slash-comment", "doris", "4.x", "strict")
  assert_true(flink_strict.contains("\"dialect\":\"flink\""))
  assert_true(flink_strict.contains("FATHOM-PARSE-008"))
  // Flink: `// comment` (9-19) is ONE Comment token; Doris: `/`(9-10) + `/`(10-11).
  assert_true(flink_strict.contains("\"start_byte\":9,\"end_byte\":19"))
  assert_true(!flink_strict.contains("\"start_byte\":9,\"end_byte\":10"))
  assert_true(doris_strict.contains("\"dialect\":\"doris\""))
  assert_true(doris_strict.contains("\"start_byte\":9,\"end_byte\":10"))
  assert_true(doris_strict.contains("\"start_byte\":10,\"end_byte\":11"))
  assert_true(!doris_strict.contains("FATHOM-PARSE-008"))
}

// ---------------------------------------------------------------------------
// e-literal version gate (D-06 / T-10-08): `E'..'` is C_STYLE_ESCAPED_STRING_LITERAL
// under flink-2.3.0/2.1.3 (Parser-calcite-1.36.0.jj:8721 / 1.34.0:8469) and absent
// under flink-1.20.5 (Calcite 1.32.0 has no such token). Doris has no E prefix.
// ---------------------------------------------------------------------------
test "flink-lexical e-literal flink-2.3.0 strict" {
  let t = @test.Test("flink-lexical e-literal flink-2.3.0 strict")
  flink_snapshot_test(t, flink_lexical_parse_json("e-literal", "flink", "flink-2.3.0", "strict"), "flink-lexical.e-literal.flink-2.3.0.strict.json")
}

test "flink-lexical e-literal flink-2.3.0 editor" {
  let t = @test.Test("flink-lexical e-literal flink-2.3.0 editor")
  flink_snapshot_test(t, flink_lexical_parse_json("e-literal", "flink", "flink-2.3.0", "editor"), "flink-lexical.e-literal.flink-2.3.0.editor.json")
}

test "flink-lexical e-literal flink-2.1.3 strict" {
  let t = @test.Test("flink-lexical e-literal flink-2.1.3 strict")
  flink_snapshot_test(t, flink_lexical_parse_json("e-literal", "flink", "flink-2.1.3", "strict"), "flink-lexical.e-literal.flink-2.1.3.strict.json")
}

test "flink-lexical e-literal flink-2.1.3 editor" {
  let t = @test.Test("flink-lexical e-literal flink-2.1.3 editor")
  flink_snapshot_test(t, flink_lexical_parse_json("e-literal", "flink", "flink-2.1.3", "editor"), "flink-lexical.e-literal.flink-2.1.3.editor.json")
}

test "flink-lexical e-literal flink-1.20.5 strict" {
  let t = @test.Test("flink-lexical e-literal flink-1.20.5 strict")
  flink_snapshot_test(t, flink_lexical_parse_json("e-literal", "flink", "flink-1.20.5", "strict"), "flink-lexical.e-literal.flink-1.20.5.strict.json")
}

test "flink-lexical e-literal flink-1.20.5 editor" {
  let t = @test.Test("flink-lexical e-literal flink-1.20.5 editor")
  flink_snapshot_test(t, flink_lexical_parse_json("e-literal", "flink", "flink-1.20.5", "editor"), "flink-lexical.e-literal.flink-1.20.5.editor.json")
}

test "flink-lexical e-literal doris-4.x strict" {
  let t = @test.Test("flink-lexical e-literal doris-4.x strict")
  flink_snapshot_test(t, flink_lexical_parse_json("e-literal", "doris", "4.x", "strict"), "flink-lexical.e-literal.doris-4.x.strict.json")
}

test "flink-lexical e-literal doris-4.x editor" {
  let t = @test.Test("flink-lexical e-literal doris-4.x editor")
  flink_snapshot_test(t, flink_lexical_parse_json("e-literal", "doris", "4.x", "editor"), "flink-lexical.e-literal.doris-4.x.editor.json")
}

test "flink_lexical_e_literal_is_version_gated_in_fixtures" {
  let v230 = flink_lexical_parse_json("e-literal", "flink", "flink-2.3.0", "strict")
  let v213 = flink_lexical_parse_json("e-literal", "flink", "flink-2.1.3", "strict")
  let v1205 = flink_lexical_parse_json("e-literal", "flink", "flink-1.20.5", "strict")
  // flink-2.3.0/2.1.3: `E'abc'` is ONE literal token (7-13).
  assert_true(v230.contains("\"start_byte\":7,\"end_byte\":13,\"text_len\":6"))
  assert_true(v213.contains("\"start_byte\":7,\"end_byte\":13,\"text_len\":6"))
  // flink-1.20.5: Identifier `E` (7-8) + StringLiteral `'abc'` (8-13).
  assert_true(v1205.contains("\"start_byte\":7,\"end_byte\":8,\"text_len\":1"))
  assert_true(!v1205.contains("\"start_byte\":7,\"end_byte\":13,\"text_len\":6"))
  assert_true(!v230.contains("\"start_byte\":7,\"end_byte\":8,\"text_len\":1"))
}

// ---------------------------------------------------------------------------
// backtick-escape: BTID double-backtick (Parser-calcite-1.36.0.jj:8951-8962)
// under Flink; Doris scan_quoted doubling under Doris. Same tokenization, each
// path frozen independently (D-06: explainable, never a silent borrow).
// ---------------------------------------------------------------------------
test "flink-lexical backtick-escape flink-2.3.0 strict" {
  let t = @test.Test("flink-lexical backtick-escape flink-2.3.0 strict")
  flink_snapshot_test(t, flink_lexical_parse_json("backtick-escape", "flink", "flink-2.3.0", "strict"), "flink-lexical.backtick-escape.flink-2.3.0.strict.json")
}

test "flink-lexical backtick-escape flink-2.3.0 editor" {
  let t = @test.Test("flink-lexical backtick-escape flink-2.3.0 editor")
  flink_snapshot_test(t, flink_lexical_parse_json("backtick-escape", "flink", "flink-2.3.0", "editor"), "flink-lexical.backtick-escape.flink-2.3.0.editor.json")
}

test "flink-lexical backtick-escape doris-4.x strict" {
  let t = @test.Test("flink-lexical backtick-escape doris-4.x strict")
  flink_snapshot_test(t, flink_lexical_parse_json("backtick-escape", "doris", "4.x", "strict"), "flink-lexical.backtick-escape.doris-4.x.strict.json")
}

test "flink-lexical backtick-escape doris-4.x editor" {
  let t = @test.Test("flink-lexical backtick-escape doris-4.x editor")
  flink_snapshot_test(t, flink_lexical_parse_json("backtick-escape", "doris", "4.x", "editor"), "flink-lexical.backtick-escape.doris-4.x.editor.json")
}

test "flink_lexical_backtick_escape_is_dialect_routed_and_independent" {
  let flink_strict = flink_lexical_parse_json("backtick-escape", "flink", "flink-2.3.0", "strict")
  let doris_strict = flink_lexical_parse_json("backtick-escape", "doris", "4.x", "strict")
  // Both dialects lex `` `a``b` `` (7-13) as ONE Quoted token.
  assert_true(flink_strict.contains("\"start_byte\":7,\"end_byte\":13"))
  assert_true(doris_strict.contains("\"start_byte\":7,\"end_byte\":13"))
  assert_true(flink_strict.contains("\"dialect\":\"flink\""))
  assert_true(flink_strict.contains("FATHOM-PARSE-008"))
  assert_true(doris_strict.contains("\"dialect\":\"doris\""))
  assert_true(!doris_strict.contains("FATHOM-PARSE-008"))
  assert_true(!flink_strict.contains("\"dialect\":\"doris\""))
  assert_true(!doris_strict.contains("\"dialect\":\"flink\""))
}

// ---------------------------------------------------------------------------
// unknown-profile: a Doris-shaped profile id under flink is rejected with the
// shared FATHOM-SCHEMA-003 envelope (D-05, Pitfall 6, T-10-01).
// ---------------------------------------------------------------------------
test "flink-lexical unknown-profile flink-4x strict" {
  let t = @test.Test("flink-lexical unknown-profile flink-4x strict")
  flink_snapshot_test(t, flink_lexical_parse_json("unknown-profile", "flink", "4.x", "strict"), "flink-lexical.unknown-profile.flink-4x.strict.json")
}

test "flink-lexical unknown-profile flink-4x editor" {
  let t = @test.Test("flink-lexical unknown-profile flink-4x editor")
  flink_snapshot_test(t, flink_lexical_parse_json("unknown-profile", "flink", "4.x", "editor"), "flink-lexical.unknown-profile.flink-4x.editor.json")
}

test "flink_lexical_unknown_profile_freezes_schema_rejection" {
  let strict = flink_lexical_parse_json("unknown-profile", "flink", "4.x", "strict")
  let editor = flink_lexical_parse_json("unknown-profile", "flink", "4.x", "editor")
  // The rejection rides the shared FATHOM-SCHEMA-003 family (D-05) — no
  // FATHOM-FLINK-* namespace minted; dialect identity is in metadata fields.
  assert_true(strict.contains("\"schema_version\":\"fathom.error.v1\""))
  assert_true(strict.contains("\"code\":\"FATHOM-SCHEMA-003\""))
  assert_true(strict.contains("\"message\":\"unsupported profile: 4.x\""))
  // Selection rejection happens before mode parsing — the envelope is mode-independent.
  assert_eq(strict, editor)
}
