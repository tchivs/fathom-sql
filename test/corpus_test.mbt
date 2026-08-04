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
  // dml-delete: 2.1/3.x record the predicate form; the 4.x fixture carries
  // both documented forms (PARTITION/PARTITIONS, ORDER BY, LIMIT).
  {
    fixture_id: "2.1-delete",
    profile: "2.1",
    exact_release: "2.1",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released",
    raw: b"DELETE FROM t WHERE id = 1;\nDELETE FROM t WHERE id IN (1, 2, 3) AND name = 'a';\n",
    mode: "strict",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-delete",
    profile: "3.x",
    exact_release: "3.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 3.x window and QUALIFY",
    raw: b"DELETE FROM t WHERE id = 1;\nDELETE FROM t WHERE id IN (1, 2, 3) AND name = 'a';\n",
    mode: "strict",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-delete",
    profile: "4.x",
    exact_release: "4.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT",
    raw: b"DELETE FROM t WHERE id = 1;\nDELETE FROM t PARTITION p1 WHERE id = 1 AND name = 'a';\nDELETE FROM t PARTITIONS (p1, p2) WHERE id IN (1, 2, 3);\nDELETE FROM t WHERE id = 1 ORDER BY id LIMIT 10;\n",
    mode: "strict",
    expected_valid: true,
  },
  // ddl-create-table: 2.1/3.x record the full body minus the 4.1.0+ ORDER BY
  // clause; BUCKETS AUTO and AUTO PARTITION BY are documented in the 2.1
  // grammar (A3 verification moved the BucketsAuto gate to 2.1). The 4.x
  // fixture carries ORDER BY, the TEMPORARY modifier, and ROLLUP.
  {
    fixture_id: "2.1-create-table",
    profile: "2.1",
    exact_release: "2.1",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released",
    raw: b"CREATE TABLE example_table (k1 TINYINT, k2 DECIMAL(10, 2) DEFAULT \"10.5\", k3 CHAR(10) COMMENT \"string column\", v1 BIGINT SUM DEFAULT \"0\" COMMENT \"aggregate value\", INDEX idx_k1 (k1) USING BITMAP COMMENT \"index comment\") ENGINE=OLAP AGGREGATE KEY(k1) COMMENT \"my table\" DISTRIBUTED BY HASH(k1) BUCKETS 10 PROPERTIES (\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");\nCREATE TABLE t (k1 DATE, k2 INT) AUTO PARTITION BY RANGE (TO_DAYS(k1)) () DISTRIBUTED BY HASH (k2) BUCKETS 3;\nCREATE TABLE t2 (k1 INT) DISTRIBUTED BY HASH (k1) BUCKETS AUTO;\nCREATE TABLE t3 (k1 DATE) PARTITION BY RANGE (k1) (PARTITION p1 VALUES LESS THAN ('2021-01-01'), PARTITION p2 VALUES LESS THAN (MAXVALUE));\n",
    mode: "strict",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-create-table",
    profile: "3.x",
    exact_release: "3.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 3.x window and QUALIFY",
    raw: b"CREATE TABLE example_table (k1 TINYINT, k2 DECIMAL(10, 2) DEFAULT \"10.5\", k3 CHAR(10) COMMENT \"string column\", v1 BIGINT SUM DEFAULT \"0\" COMMENT \"aggregate value\", INDEX idx_k1 (k1) USING BITMAP COMMENT \"index comment\") ENGINE=OLAP AGGREGATE KEY(k1) COMMENT \"my table\" DISTRIBUTED BY HASH(k1) BUCKETS 10 PROPERTIES (\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");\nCREATE TABLE t (k1 DATE, k2 INT) AUTO PARTITION BY RANGE (TO_DAYS(k1)) () DISTRIBUTED BY HASH (k2) BUCKETS 3;\nCREATE TABLE t2 (k1 INT) DISTRIBUTED BY HASH (k1) BUCKETS AUTO;\nCREATE TABLE t3 (k1 DATE) PARTITION BY RANGE (k1) (PARTITION p1 VALUES LESS THAN ('2021-01-01'), PARTITION p2 VALUES LESS THAN (MAXVALUE));\n",
    mode: "strict",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-create-table",
    profile: "4.x",
    exact_release: "4.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT",
    raw: b"CREATE TABLE example_table (k1 TINYINT, k2 DECIMAL(10, 2) DEFAULT \"10.5\", k3 CHAR(10) COMMENT \"string column\", k4 INT NOT NULL DEFAULT \"1\" COMMENT \"int column\", v1 BIGINT SUM DEFAULT \"0\" COMMENT \"aggregate value\", INDEX idx_k1 (k1) USING BITMAP COMMENT \"index comment\") ENGINE=OLAP UNIQUE KEY(k1, k2) ORDER BY(k1) COMMENT \"my table\" PARTITION BY RANGE(k1) (PARTITION p1 VALUES LESS THAN (\"2021-01-01\"), PARTITION p2 VALUES LESS THAN (\"2022-01-01\")) DISTRIBUTED BY HASH(k1) BUCKETS 32 ROLLUP (r1 (k1) DUPLICATE KEY (k1)) PROPERTIES (\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");\nCREATE TEMPORARY TABLE t (a INT);\nCREATE TABLE t2 (k1 INT) DISTRIBUTED BY HASH (k1) BUCKETS AUTO;\nCREATE TABLE t3 (k1 DATE, k2 INT) AUTO PARTITION BY RANGE (TO_DAYS(k1)) () DISTRIBUTED BY HASH (k2) BUCKETS 3;\n",
    mode: "strict",
    expected_valid: true,
  },
  // ddl-create-view: 2.1/3.x record plain and column-defined forms; the 4.x
  // fixture adds IF NOT EXISTS, column comments, and a CTE-bodied query.
  {
    fixture_id: "2.1-create-view",
    profile: "2.1",
    exact_release: "2.1",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released",
    raw: b"CREATE VIEW v AS SELECT a, b FROM t;\nCREATE VIEW v (a, b) AS SELECT a, b FROM t;\n",
    mode: "strict",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-create-view",
    profile: "3.x",
    exact_release: "3.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 3.x window and QUALIFY",
    raw: b"CREATE VIEW v AS SELECT a, b FROM t;\nCREATE VIEW v (a, b) AS SELECT a, b FROM t;\n",
    mode: "strict",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-create-view",
    profile: "4.x",
    exact_release: "4.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT",
    raw: b"CREATE VIEW v AS SELECT a, b FROM t;\nCREATE VIEW IF NOT EXISTS db.v (a COMMENT 'col a') AS SELECT x AS a FROM t;\nCREATE VIEW v AS WITH cte AS (SELECT 1) SELECT * FROM cte;\n",
    mode: "strict",
    expected_valid: true,
  },
  // ddl-create-index: 2.1/3.x record INVERTED (the only type those pages
  // document); the 4.x fixture adds NGRAM_BF/ANN, properties, and comments.
  {
    fixture_id: "2.1-create-index",
    profile: "2.1",
    exact_release: "2.1",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released",
    raw: b"CREATE INDEX index1 ON table1 (col1) USING INVERTED;\nCREATE INDEX idx ON db.table1 (col1, col2) USING INVERTED;\n",
    mode: "strict",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-create-index",
    profile: "3.x",
    exact_release: "3.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 3.x window and QUALIFY",
    raw: b"CREATE INDEX index1 ON table1 (col1) USING INVERTED;\nCREATE INDEX idx ON db.table1 (col1, col2) USING INVERTED;\n",
    mode: "strict",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-create-index",
    profile: "4.x",
    exact_release: "4.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT",
    raw: b"CREATE INDEX index1 ON table1 (col1) USING INVERTED;\nCREATE INDEX index2 ON table1 (col1) USING NGRAM_BF PROPERTIES (\"gram_size\" = \"3\", \"bf_size\" = \"1024\");\nCREATE INDEX IF NOT EXISTS idx ON t (c) COMMENT 'index comment';\nCREATE INDEX idx ON db.table1 (col1, col2) USING ANN PROPERTIES (\"index_type\" = \"hnsw\", \"metric_type\" = \"l2_distance\", \"dim\" = \"128\");\n",
    mode: "strict",
    expected_valid: true,
  },
  // dml-insert-overwrite (4.x-only family): literal table keyword, PARTITION
  // lists, and the PARTITION (*) auto-detect form documented since 2.1.3.
  {
    fixture_id: "4.x-insert-overwrite",
    profile: "4.x",
    exact_release: "4.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT",
    raw: b"INSERT OVERWRITE table test VALUES (1, 2);\nINSERT OVERWRITE table test PARTITION (p1, p2) SELECT * FROM test2;\nINSERT OVERWRITE table test PARTITION (*) SELECT * FROM test2;\n",
    mode: "strict",
    expected_valid: true,
  },
  // dml-merge: 4.x-supported; 2.1/3.x rows are version negatives (the 4.x-gate
  // honors the released-docs authority that MERGE-INTO is 4.x-doc-only).
  {
    fixture_id: "2.1-merge",
    profile: "2.1",
    exact_release: "2.1",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released",
    raw: b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.v = s.v",
    mode: "strict",
    expected_valid: false,
  },
  {
    fixture_id: "3.x-merge",
    profile: "3.x",
    exact_release: "3.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 3.x window and QUALIFY",
    raw: b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.v = s.v",
    mode: "strict",
    expected_valid: false,
  },
  {
    fixture_id: "4.x-merge",
    profile: "4.x",
    exact_release: "4.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT",
    raw: b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.v = s.v;\nMERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN DELETE;\nMERGE INTO t USING s ON t.id = s.id WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.v);\nMERGE INTO t USING s ON t.id = s.id WHEN MATCHED AND t.v < s.v THEN UPDATE SET t.v = s.v WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.v);\n",
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
