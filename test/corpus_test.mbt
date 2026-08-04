/// Embedded replay oracle mirroring every DML/DDL fixture row in
/// corpus/manifest.tsv (CORP-02, D-18, research Pattern 4): each entry runs
/// parse_with_metadata -> print_result == raw, all_spans_in_bounds,
/// expected_valid, and a DORIS-PARSE- diagnostic prefix via the shared
/// metadata_fixture_replay_ok helper (defined in parser_test.mbt, same test
/// package). Entries are committed per statement family together with the
/// fixture SQL files, manifest rows, and coverage rows so every corpus row
/// stays executable and the one-fixture-one-oracle contract is visible.
let dml_ddl_corpus_fixtures : Array[EmbeddedManifestFixture] = [
  // dml-insert-values: INSERT INTO ... VALUES (2.1/3.x/4.x INSERT pages;
  // DEFAULT and multi-row forms are documented in all three trees; the
  // STREAMING hint form is documented in the 4.x grammar).
  {
    fixture_id: "2.1-insert-values",
    profile: "2.1",
    exact_release: "2.1",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released",
    raw: b"INSERT INTO test VALUES (1, 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT);\nINSERT INTO test VALUES (1, 2), (3, 2 + 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT), (3, DEFAULT);\n",
    mode: "strict",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-insert-values",
    profile: "3.x",
    exact_release: "3.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 3.x window and QUALIFY",
    raw: b"INSERT INTO test VALUES (1, 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT);\nINSERT INTO test VALUES (1, 2), (3, 2 + 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT), (3, DEFAULT);\n",
    mode: "strict",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-insert-values",
    profile: "4.x",
    exact_release: "4.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT",
    raw: b"INSERT INTO test VALUES (1, 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT);\nINSERT INTO test VALUES (1, 2), (3, 2 + 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT), (3, DEFAULT);\nINSERT INTO test /*+ STREAMING */ VALUES (1, 2);\n",
    mode: "strict",
    expected_valid: true,
  },
  // dml-insert-select: INSERT INTO ... SELECT (2.1/3.x/4.x INSERT pages;
  // PARTITION and WITH LABEL query forms are documented in all three trees,
  // qualified db.table target verified on the 4.x page).
  {
    fixture_id: "2.1-insert-select",
    profile: "2.1",
    exact_release: "2.1",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released",
    raw: b"INSERT INTO test SELECT * FROM test2;\nINSERT INTO test (c1, c2) SELECT * FROM test2;\nINSERT INTO test PARTITION(p1, p2) WITH LABEL `label1` SELECT * FROM test2;\n",
    mode: "strict",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-insert-select",
    profile: "3.x",
    exact_release: "3.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 3.x window and QUALIFY",
    raw: b"INSERT INTO test SELECT * FROM test2;\nINSERT INTO test (c1, c2) SELECT * FROM test2;\nINSERT INTO test PARTITION(p1, p2) WITH LABEL `label1` SELECT * FROM test2;\n",
    mode: "strict",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-insert-select",
    profile: "4.x",
    exact_release: "4.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT",
    raw: b"INSERT INTO test SELECT * FROM test2;\nINSERT INTO test (c1, c2) SELECT * FROM test2;\nINSERT INTO test PARTITION(p1, p2) WITH LABEL `label1` SELECT * FROM test2;\nINSERT INTO db.test (c1) SELECT c1 FROM test2;\n",
    mode: "strict",
    expected_valid: true,
  },
  // dml-update: 2.1/3.x record the core SET/alias/WHERE forms; the 4.x
  // fixture carries the full grammar (DEFAULT, FROM join, ORDER BY, LIMIT).
  {
    fixture_id: "2.1-update",
    profile: "2.1",
    exact_release: "2.1",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released",
    raw: b"UPDATE t1 SET c1 = 1 WHERE id = 1;\nUPDATE t1 SET c1 = 1, c2 = 2 WHERE id = 1 AND name = 'a';\nUPDATE t1 alias SET c1 = 1;\n",
    mode: "strict",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-update",
    profile: "3.x",
    exact_release: "3.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 3.x window and QUALIFY",
    raw: b"UPDATE t1 SET c1 = 1 WHERE id = 1;\nUPDATE t1 SET c1 = 1, c2 = 2 WHERE id = 1 AND name = 'a';\nUPDATE t1 alias SET c1 = 1;\n",
    mode: "strict",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-update",
    profile: "4.x",
    exact_release: "4.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT",
    raw: b"UPDATE t1 SET c1 = 1 WHERE id = 1;\nUPDATE t1 SET c1 = 1, c2 = DEFAULT WHERE id = 1;\nUPDATE t1 SET t1.c1 = t2.c1 FROM t2 INNER JOIN t3 ON t2.id = t3.id WHERE t1.id = t2.id;\nUPDATE t1 SET c1 = c1 + 1 ORDER BY c1 DESC NULLS LAST LIMIT 10;\n",
    mode: "strict",
    expected_valid: true,
  },
]

test "dml_ddl_corpus_oracle_replays_every_manifest_fixture" {
  assert_true(dml_ddl_corpus_fixtures.length() >= 3)
  for fixture in dml_ddl_corpus_fixtures {
    assert_true(fixture.fixture_id.length() > 0)
    assert_true(metadata_fixture_replay_ok(fixture))
  }
}
