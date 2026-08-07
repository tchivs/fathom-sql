/// D-04 flink-lexical snapshot group (Phase 10 wave 1): an independent
/// namespace under parity/__snapshot__/ that freezes the first D-06 lexical
/// conflict — the `#` line-comment character — under both dialects. The same
/// raw input tokenizes differently per dialect (DIALECT-02/03/06): under
/// flink-2.3.0 `#` is NOT a Calcite token (lexical error -> FATHOM-PARSE-003,
/// plus the statement-level FATHOM-PARSE-008 not-implemented diagnostic);
/// under doris-4.x `#` is a line comment and the bare `a` statement is the
/// existing unsupported-statement FATHOM-PARSE-007. Each path is explainable
/// by its snapshot (D-06) — no silent borrowing of the other dialect's policy.
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

/// Wave-1 conflict-matrix fixtures. The hash-comment entry is the D-06 core
/// conflict: `#` is a Doris line comment but a Flink lexical error. Per-release
/// profile rows come from parity/fixtures/flink-lexical/manifest.tsv
/// (calcite_version/parser_config/url/sha512/tag/commit).
let flink_lexical_fixtures : Array[FlinkLexicalFixture] = [
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
