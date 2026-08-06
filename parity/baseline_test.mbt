/// D-07/D-08 v1 baseline freeze (wave 1 of phase 09): snapshot EVERY corpus
/// fixture x profile x mode combination through the CURRENT (pre-rename)
/// shared entries so later dialect/naming waves can only land byte-identical
/// or pre-approved changes. The mechanism is MoonBit's @test.T::snapshot:
/// `moon test --update --package parity` generates parity/__snapshot__/ once;
/// afterwards `moon test --package parity` (no --update) fails on ANY byte
/// difference (research 09-RESEARCH.md §9.2). Runtime never reads disk — raw
/// bytes are embedded at authoring time from corpus/doris-{2.1,3.x,4.x}/*.sql
/// plus the manifest's inline rows (STATE.md convention), and
/// parity/baseline-hashes.txt pins the corpus files (T-09-03).
///
/// Cross-target byte equality (PARITY-02 foundation, research §9.2 step 5):
/// the shared cross-target snapshot file is written by whichever target runs
/// the parity suite, and every other target must reproduce the identical
/// bytes or `moon test` fails. CI runs the parity suite on native and
/// linear-Wasm (and the suite is runnable on js) so a target-specific
/// serialization regression is caught by the same byte-level gate.

pub(all) struct BaselineFixture {
  pub fixture_id : String
  pub profile : String
  pub raw : Bytes
  pub expected_valid : Bool
}

/// All 44 corpus/manifest.tsv data rows, in manifest order. File-backed rows
/// embed the exact committed bytes of the corpus .sql files (including the
/// provenance comment headers; the 4.x-industrial file carries the TABLET (1001)
/// clause and the trailing source-backed recovery fixture — v1 behavior on the
/// real file is frozen as-is). Inline rows embed the test-oracle raws
/// (test/corpus_test.mbt + test/formatter_test.mbt) for the boundary,
/// recovery, invalid-encoding, and 2.1/3.x MERGE negatives.
let baseline_fixtures : Array[BaselineFixture] = [
  {
    fixture_id: "2.1-industrial",
    profile: "2.1",
    raw: b"-- Released Apache Doris 2.1 SELECT grammar examples.\n-- Source: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-query/SELECT/\nSELECT DISTINCT k, SUM(v) AS total\nFROM fact PARTITION (p0) TABLESAMPLE (10)\nWHERE v BETWEEN 1 AND 9\nGROUP BY ROLLUP(k)\nHAVING SUM(v) > 0\nORDER BY total DESC\nLIMIT 10;\n\nSELECT a FROM left_table LEFT OUTER JOIN right_table ON left_table.k = right_table.k;\nSELECT a FROM first_table UNION ALL SELECT a FROM second_table;\nSELECT `group`, `window` FROM `table`;\n",
    expected_valid: true,
  },
  {
    fixture_id: "2.1-boundary-empty",
    profile: "2.1",
    raw: b"SELECT FROM t",
    expected_valid: false,
  },
  {
    fixture_id: "2.1-boundary-single",
    profile: "2.1",
    raw: b"SELECT 1",
    expected_valid: true,
  },
  {
    fixture_id: "2.1-contextual-keyword",
    profile: "2.1",
    raw: b"SELECT `group`, `window` FROM `table`",
    expected_valid: true,
  },
  {
    fixture_id: "2.1-invalid-encoding",
    profile: "2.1",
    raw: b"SELECT \xff",
    expected_valid: false,
  },
  {
    fixture_id: "3.x-industrial",
    profile: "3.x",
    raw: b"-- Released Apache Doris 3.x SELECT grammar examples.\n-- Source: https://doris.apache.org/docs/3.x/sql-manual/sql-statements/data-query/SELECT/\nWITH recent AS (\n  SELECT k, SUM(v) OVER (PARTITION BY k ORDER BY ts ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling\n  FROM fact SAMPLE (10)\n  WHERE v IN (1, 2, 3)\n)\nSELECT k, rolling FROM recent QUALIFY rolling > 0 ORDER BY rolling DESC LIMIT 20;\n\nSELECT k FROM fact GROUP BY GROUPING SETS ((k), (k, region));\nSELECT k FROM left_table RIGHT JOIN right_table USING (k) UNION DISTINCT SELECT k FROM fallback_table;\n",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-boundary-set-one",
    profile: "3.x",
    raw: b"SELECT k FROM t UNION SELECT k FROM t2",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-boundary-set-many",
    profile: "3.x",
    raw: b"SELECT 1 UNION SELECT 2 UNION ALL SELECT 3 UNION DISTINCT SELECT 4",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-recovery",
    profile: "3.x",
    raw: b"SELECT k FROM t WHERE",
    expected_valid: false,
  },
  {
    fixture_id: "3.x-unsupported-profile",
    profile: "3.x",
    raw: b"SELECT k FROM t QUALIFY k > 0",
    expected_valid: false,
  },
  {
    fixture_id: "4.x-industrial",
    profile: "4.x",
    raw: b"-- Released Apache Doris 4.x SELECT grammar examples.\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/\nSELECT /*+ SET_VAR(exec_mem_limit=1G) */\n  d.k, COUNT(*) AS n,\n  SUM(d.v) OVER (PARTITION BY d.k ORDER BY d.ts RANGE BETWEEN 1 PRECEDING AND CURRENT ROW) AS running\nFROM (SELECT k, v, ts FROM detail WHERE v IS NOT NULL) AS d\nTABLET (1001)\nGROUP BY CUBE(d.k)\nHAVING COUNT(*) > 1\nORDER BY n DESC\nLIMIT 5 OFFSET 2\nINTO OUTFILE 'result.csv';\n\nSELECT k FROM t1 UNION SELECT k FROM t2 UNION ALL SELECT k FROM t3;\n-- Recovery fixture: the missing expression is intentional and remains source-backed.\nSELECT k +\n",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-boundary-set-two",
    profile: "4.x",
    raw: b"SELECT 1 UNION SELECT 2; SELECT 3 UNION ALL SELECT 4",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-recovery",
    profile: "4.x",
    raw: b"SELECT k +",
    expected_valid: false,
  },
  {
    fixture_id: "4.x-invalid-encoding",
    profile: "4.x",
    raw: b"SELECT \xff",
    expected_valid: false,
  },
  {
    fixture_id: "2.1-insert-values",
    profile: "2.1",
    raw: b"-- Released Apache Doris 2.1 INSERT VALUES grammar examples.\n-- Source: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-modification/DML/INSERT/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql (examples 1-2; mysql> prompts and output blocks excluded)\nINSERT INTO test VALUES (1, 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT);\nINSERT INTO test VALUES (1, 2), (3, 2 + 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT), (3, DEFAULT);\n",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-insert-values",
    profile: "3.x",
    raw: b"-- Released Apache Doris 3.x INSERT VALUES grammar examples.\n-- Source: https://doris.apache.org/docs/3.x/sql-manual/sql-statements/data-modification/DML/INSERT/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql (examples 1-2; mysql> prompts and output blocks excluded)\nINSERT INTO test VALUES (1, 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT);\nINSERT INTO test VALUES (1, 2), (3, 2 + 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT), (3, DEFAULT);\n",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-insert-values",
    profile: "4.x",
    raw: b"-- Released Apache Doris 4.x INSERT VALUES grammar examples.\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/INSERT/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql (examples 1-2; mysql> prompts and output blocks excluded)\nINSERT INTO test VALUES (1, 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT);\nINSERT INTO test VALUES (1, 2), (3, 2 + 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT), (3, DEFAULT);\nINSERT INTO test /*+ STREAMING */ VALUES (1, 2);\n",
    expected_valid: true,
  },
  {
    fixture_id: "2.1-insert-select",
    profile: "2.1",
    raw: b"-- Released Apache Doris 2.1 INSERT ... SELECT grammar examples.\n-- Source: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-modification/DML/INSERT/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql (example 3-4; mysql> prompts and output blocks excluded)\nINSERT INTO test SELECT * FROM test2;\nINSERT INTO test (c1, c2) SELECT * FROM test2;\nINSERT INTO test PARTITION(p1, p2) WITH LABEL `label1` SELECT * FROM test2;\n",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-insert-select",
    profile: "3.x",
    raw: b"-- Released Apache Doris 3.x INSERT ... SELECT grammar examples.\n-- Source: https://doris.apache.org/docs/3.x/sql-manual/sql-statements/data-modification/DML/INSERT/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql (example 3-4; mysql> prompts and output blocks excluded)\nINSERT INTO test SELECT * FROM test2;\nINSERT INTO test (c1, c2) SELECT * FROM test2;\nINSERT INTO test PARTITION(p1, p2) WITH LABEL `label1` SELECT * FROM test2;\n",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-insert-select",
    profile: "4.x",
    raw: b"-- Released Apache Doris 4.x INSERT ... SELECT grammar examples.\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/INSERT/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql (example 3-4; mysql> prompts and output blocks excluded)\nINSERT INTO test SELECT * FROM test2;\nINSERT INTO test (c1, c2) SELECT * FROM test2;\nINSERT INTO test PARTITION(p1, p2) WITH LABEL `label1` SELECT * FROM test2;\nINSERT INTO db.test (c1) SELECT c1 FROM test2;\n",
    expected_valid: true,
  },
  {
    fixture_id: "2.1-update",
    profile: "2.1",
    raw: b"-- Released Apache Doris 2.1 UPDATE grammar examples (core SET/FROM/WHERE\n-- forms; the ORDER BY/LIMIT clause is documented in the 4.x grammar only).\n-- Source: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-modification/DML/UPDATE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nUPDATE t1 SET c1 = 1 WHERE id = 1;\nUPDATE t1 SET c1 = 1, c2 = 2 WHERE id = 1 AND name = 'a';\nUPDATE t1 alias SET c1 = 1;\n",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-update",
    profile: "3.x",
    raw: b"-- Released Apache Doris 3.x UPDATE grammar examples (core SET/FROM/WHERE\n-- forms; the ORDER BY/LIMIT clause is documented in the 4.x grammar only).\n-- Source: https://doris.apache.org/docs/3.x/sql-manual/sql-statements/data-modification/DML/UPDATE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nUPDATE t1 SET c1 = 1 WHERE id = 1;\nUPDATE t1 SET c1 = 1, c2 = 2 WHERE id = 1 AND name = 'a';\nUPDATE t1 alias SET c1 = 1;\n",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-update",
    profile: "4.x",
    raw: b"-- Released Apache Doris 4.x UPDATE grammar examples (UNIQUE KEY model).\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/UPDATE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nUPDATE t1 SET c1 = 1 WHERE id = 1;\nUPDATE t1 SET c1 = 1, c2 = DEFAULT WHERE id = 1;\nUPDATE t1 SET t1.c1 = t2.c1 FROM t2 INNER JOIN t3 ON t2.id = t3.id WHERE t1.id = t2.id;\nUPDATE t1 SET c1 = c1 + 1 ORDER BY c1 DESC NULLS LAST LIMIT 10;\n",
    expected_valid: true,
  },
  {
    fixture_id: "2.1-delete",
    profile: "2.1",
    raw: b"-- Released Apache Doris 2.1 DELETE grammar examples (predicate form;\n-- PARTITION/ORDER BY/LIMIT variants are documented in the 4.x grammar only).\n-- Source: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-modification/DML/DELETE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nDELETE FROM t WHERE id = 1;\nDELETE FROM t WHERE id IN (1, 2, 3) AND name = 'a';\n",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-delete",
    profile: "3.x",
    raw: b"-- Released Apache Doris 3.x DELETE grammar examples (predicate form;\n-- PARTITION/ORDER BY/LIMIT variants are documented in the 4.x grammar only).\n-- Source: https://doris.apache.org/docs/3.x/sql-manual/sql-statements/data-modification/DML/DELETE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nDELETE FROM t WHERE id = 1;\nDELETE FROM t WHERE id IN (1, 2, 3) AND name = 'a';\n",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-delete",
    profile: "4.x",
    raw: b"-- Released Apache Doris 4.x DELETE grammar examples (both documented forms).\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/DELETE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nDELETE FROM t WHERE id = 1;\nDELETE FROM t PARTITION p1 WHERE id = 1 AND name = 'a';\nDELETE FROM t PARTITIONS (p1, p2) WHERE id IN (1, 2, 3);\nDELETE FROM t WHERE id = 1 ORDER BY id LIMIT 10;\n",
    expected_valid: true,
  },
  {
    fixture_id: "2.1-create-table",
    profile: "2.1",
    raw: b"-- Released Apache Doris 2.1 CREATE TABLE grammar examples (keys, aggregation\n-- semantics, distribution/buckets incl. AUTO, partitions incl. AUTO PARTITION\n-- BY, properties). ORDER BY is a 4.1.0+ clause and stays out of this file.\n-- Source: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE TABLE example_table (k1 TINYINT, k2 DECIMAL(10, 2) DEFAULT \"10.5\", k3 CHAR(10) COMMENT \"string column\", v1 BIGINT SUM DEFAULT \"0\" COMMENT \"aggregate value\", INDEX idx_k1 (k1) USING BITMAP COMMENT \"index comment\") ENGINE=OLAP AGGREGATE KEY(k1) COMMENT \"my table\" DISTRIBUTED BY HASH(k1) BUCKETS 10 PROPERTIES (\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");\nCREATE TABLE t (k1 DATE, k2 INT) AUTO PARTITION BY RANGE (TO_DAYS(k1)) () DISTRIBUTED BY HASH (k2) BUCKETS 3;\nCREATE TABLE t2 (k1 INT) DISTRIBUTED BY HASH (k1) BUCKETS AUTO;\nCREATE TABLE t3 (k1 DATE) PARTITION BY RANGE (k1) (PARTITION p1 VALUES LESS THAN ('2021-01-01'), PARTITION p2 VALUES LESS THAN (MAXVALUE));\n",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-create-table",
    profile: "3.x",
    raw: b"-- Released Apache Doris 3.x CREATE TABLE grammar examples (keys, aggregation\n-- semantics, distribution/buckets incl. AUTO, partitions incl. AUTO PARTITION\n-- BY, properties). ORDER BY is a 4.1.0+ clause and stays out of this file.\n-- Source: https://doris.apache.org/docs/3.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE TABLE example_table (k1 TINYINT, k2 DECIMAL(10, 2) DEFAULT \"10.5\", k3 CHAR(10) COMMENT \"string column\", v1 BIGINT SUM DEFAULT \"0\" COMMENT \"aggregate value\", INDEX idx_k1 (k1) USING BITMAP COMMENT \"index comment\") ENGINE=OLAP AGGREGATE KEY(k1) COMMENT \"my table\" DISTRIBUTED BY HASH(k1) BUCKETS 10 PROPERTIES (\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");\nCREATE TABLE t (k1 DATE, k2 INT) AUTO PARTITION BY RANGE (TO_DAYS(k1)) () DISTRIBUTED BY HASH (k2) BUCKETS 3;\nCREATE TABLE t2 (k1 INT) DISTRIBUTED BY HASH (k1) BUCKETS AUTO;\nCREATE TABLE t3 (k1 DATE) PARTITION BY RANGE (k1) (PARTITION p1 VALUES LESS THAN ('2021-01-01'), PARTITION p2 VALUES LESS THAN (MAXVALUE));\n",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-create-table",
    profile: "4.x",
    raw: b"-- Released Apache Doris 4.x CREATE TABLE grammar examples (full body incl.\n-- the 4.1.0+ ORDER BY clause, TEMPORARY modifier, rollup, partitions,\n-- distribution/buckets, properties).\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE TABLE example_table (k1 TINYINT, k2 DECIMAL(10, 2) DEFAULT \"10.5\", k3 CHAR(10) COMMENT \"string column\", k4 INT NOT NULL DEFAULT \"1\" COMMENT \"int column\", v1 BIGINT SUM DEFAULT \"0\" COMMENT \"aggregate value\", INDEX idx_k1 (k1) USING BITMAP COMMENT \"index comment\") ENGINE=OLAP UNIQUE KEY(k1, k2) ORDER BY(k1) COMMENT \"my table\" PARTITION BY RANGE(k1) (PARTITION p1 VALUES LESS THAN (\"2021-01-01\"), PARTITION p2 VALUES LESS THAN (\"2022-01-01\")) DISTRIBUTED BY HASH(k1) BUCKETS 32 ROLLUP (r1 (k1) DUPLICATE KEY (k1)) PROPERTIES (\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");\nCREATE TEMPORARY TABLE t (a INT);\nCREATE TABLE t2 (k1 INT) DISTRIBUTED BY HASH (k1) BUCKETS AUTO;\nCREATE TABLE t3 (k1 DATE, k2 INT) AUTO PARTITION BY RANGE (TO_DAYS(k1)) () DISTRIBUTED BY HASH (k2) BUCKETS 3;\n",
    expected_valid: true,
  },
  {
    fixture_id: "2.1-create-view",
    profile: "2.1",
    raw: b"-- Released Apache Doris 2.1 CREATE VIEW grammar examples (plain and column\n-- defined forms; IF NOT EXISTS / column comments verified on the 4.x page).\n-- Source: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/table-and-view/view/CREATE-VIEW/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE VIEW v AS SELECT a, b FROM t;\nCREATE VIEW v (a, b) AS SELECT a, b FROM t;\n",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-create-view",
    profile: "3.x",
    raw: b"-- Released Apache Doris 3.x CREATE VIEW grammar examples (plain and column\n-- defined forms; IF NOT EXISTS / column comments verified on the 4.x page).\n-- Source: https://doris.apache.org/docs/3.x/sql-manual/sql-statements/table-and-view/view/CREATE-VIEW/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE VIEW v AS SELECT a, b FROM t;\nCREATE VIEW v (a, b) AS SELECT a, b FROM t;\n",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-create-view",
    profile: "4.x",
    raw: b"-- Released Apache Doris 4.x CREATE VIEW grammar examples (IF NOT EXISTS,\n-- column definitions with comments, and a CTE-bodied query per the grammar's\n-- [AS] <query_stmt>).\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/view/CREATE-VIEW/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE VIEW v AS SELECT a, b FROM t;\nCREATE VIEW IF NOT EXISTS db.v (a COMMENT 'col a') AS SELECT x AS a FROM t;\nCREATE VIEW v AS WITH cte AS (SELECT 1) SELECT * FROM cte;\n",
    expected_valid: true,
  },
  {
    fixture_id: "2.1-create-index",
    profile: "2.1",
    raw: b"-- Released Apache Doris 2.1 CREATE INDEX grammar examples (INVERTED is the\n-- only index type the 2.1 CREATE TABLE/INDEX pages document).\n-- Source: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/table-and-view/index/CREATE-INDEX/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE INDEX index1 ON table1 (col1) USING INVERTED;\nCREATE INDEX idx ON db.table1 (col1, col2) USING INVERTED;\n",
    expected_valid: true,
  },
  {
    fixture_id: "3.x-create-index",
    profile: "3.x",
    raw: b"-- Released Apache Doris 3.x CREATE INDEX grammar examples (INVERTED is the\n-- only index type the 3.x CREATE TABLE/INDEX pages document).\n-- Source: https://doris.apache.org/docs/3.x/sql-manual/sql-statements/table-and-view/index/CREATE-INDEX/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE INDEX index1 ON table1 (col1) USING INVERTED;\nCREATE INDEX idx ON db.table1 (col1, col2) USING INVERTED;\n",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-create-index",
    profile: "4.x",
    raw: b"-- Released Apache Doris 4.x CREATE INDEX grammar examples (INVERTED, NGRAM_BF,\n-- and ANN index types with properties and comments).\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/index/CREATE-INDEX/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE INDEX index1 ON table1 (col1) USING INVERTED;\nCREATE INDEX index2 ON table1 (col1) USING NGRAM_BF PROPERTIES (\"gram_size\" = \"3\", \"bf_size\" = \"1024\");\nCREATE INDEX IF NOT EXISTS idx ON t (c) COMMENT 'index comment';\nCREATE INDEX idx ON db.table1 (col1, col2) USING ANN PROPERTIES (\"index_type\" = \"hnsw\", \"metric_type\" = \"l2_distance\", \"dim\" = \"128\");\n",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-insert-overwrite",
    profile: "4.x",
    raw: b"-- Released Apache Doris 4.x INSERT OVERWRITE grammar examples (the literal\n-- `table` keyword after OVERWRITE, PARTITION lists, and the PARTITION (*)\n-- auto-detect form documented since 2.1.3).\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/INSERT-OVERWRITE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nINSERT OVERWRITE table test VALUES (1, 2);\nINSERT OVERWRITE table test PARTITION (p1, p2) SELECT * FROM test2;\nINSERT OVERWRITE table test PARTITION (*) SELECT * FROM test2;\n",
    expected_valid: true,
  },
  {
    fixture_id: "2.1-merge",
    profile: "2.1",
    raw: b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.v = s.v",
    expected_valid: false,
  },
  {
    fixture_id: "3.x-merge",
    profile: "3.x",
    raw: b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.v = s.v",
    expected_valid: false,
  },
  {
    fixture_id: "4.x-merge",
    profile: "4.x",
    raw: b"-- Released Apache Doris 4.x MERGE INTO grammar examples (UNIQUE KEY model;\n-- MERGE-INTO is documented only in the 4.x docs tree).\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/MERGE-INTO/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nMERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.v = s.v;\nMERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN DELETE;\nMERGE INTO t USING s ON t.id = s.id WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.v);\nMERGE INTO t USING s ON t.id = s.id WHEN MATCHED AND t.v < s.v THEN UPDATE SET t.v = s.v WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.v);\n",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-create-table-ctas",
    profile: "4.x",
    raw: b"-- Released Apache Doris 4.x CREATE TABLE ... AS SELECT (CTAS) variant\n-- grammar examples.\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql (Varaint Syntax: CREATE TABLE ... AS SELECT)\nCREATE TABLE t AS SELECT a, b FROM src;\nCREATE TABLE t (a INT) DISTRIBUTED BY HASH (a) BUCKETS 10 AS SELECT a FROM src;\nCREATE TABLE t (a INT, INDEX idx (a)) ENGINE=OLAP COMMENT \"ctas\" AS SELECT a FROM src;\n",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-create-table-like",
    profile: "4.x",
    raw: b"-- Released Apache Doris 4.x CREATE TABLE ... LIKE variant grammar examples.\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql (Varaint Syntax: CREATE TABLE ... LIKE)\nCREATE TABLE new_t LIKE existing_t;\nCREATE TABLE new_t LIKE existing_t WITH ROLLUP (r1, r2);\nCREATE TABLE db.new_t LIKE db.existing_t;\n",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-create-materialized-view",
    profile: "4.x",
    raw: b"-- Released Apache Doris 4.x CREATE MATERIALIZED VIEW examples: the sync form\n-- (restricted single-table body) plus the async form (BUILD/REFRESH clauses\n-- with an unrestricted query, documented identically in the 2.1/3.x/4.x\n-- async-materialized-view pages).\n-- Sources:\n--   https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/sync-materialized-view/CREATE-MATERIALIZED-VIEW/\n--   https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/async-materialized-view/CREATE-ASYNC-MATERIALIZED-VIEW/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE MATERIALIZED VIEW mv AS SELECT k, SUM(v) FROM t GROUP BY k;\nCREATE MATERIALIZED VIEW complete_mv (orderkey COMMENT 'Order key') BUILD IMMEDIATE REFRESH AUTO ON SCHEDULE EVERY 1 DAY STARTS '2099-01-01 20:30:00' DISTRIBUTED BY HASH (orderkey) BUCKETS 2 PROPERTIES (\"replication_num\" = \"1\") AS SELECT o_orderkey, l_orderkey FROM orders LEFT JOIN lineitem ON l_orderkey = o_orderkey;\nCREATE MATERIALIZED VIEW IF NOT EXISTS mv2 BUILD DEFERRED REFRESH COMPLETE ON MANUAL AS SELECT 1;\n",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-script-multi-statement",
    profile: "4.x",
    raw: b"-- Released Apache Doris 4.x multi-statement script fixture (DORIS-03): a\n-- semicolon-separated document parses each statement independently with\n-- monotonic statement ids; the invalid-statement variant (later statements\n-- survive) is asserted by the corpus_test oracle.\n-- Source: statement-family pages (https://doris.apache.org/docs/4.x/sql-manual/sql-statements/)\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE TABLE t (a INT); INSERT INTO t VALUES (1); SELECT * FROM t;\nINSERT INTO t VALUES (2); SELECT b;\n",
    expected_valid: true,
  },
  {
    fixture_id: "4.x-malformed-recovery",
    profile: "4.x",
    raw: b"-- Released Apache Doris 4.x malformed DML recovery fixture: editor-mode\n-- goldens assert bounded recovery, byte-exact replay, and DORIS-PARSE\n-- diagnostics (Phase 1 recovery patterns).\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/UPDATE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nUPDATE t SET x = 1 WHERE;\nINSERT INTO t VALUES (1;\n",
    expected_valid: false,
  },
]

fn baseline_fixture(id : String) -> BaselineFixture {
  for fixture in baseline_fixtures {
    if fixture.fixture_id == id { return fixture }
  }
  panic()
}

fn parse_json(id : String, mode : String) -> String {
  let fixture = baseline_fixture(id)
  @utf8.decode_lossy(@binding.fathom_parse_v1(fixture.raw, "doris", fixture.profile, mode))
}

/// Default formatter options per D-29..D-32 (upper, 2, 100, trailing, follow,
/// trailing newline on) — the same values the v1 parity harness calls
/// doris_format_v1 with.
fn format_json(id : String) -> String {
  let fixture = baseline_fixture(id)
  @utf8.decode_lossy(
    @binding.fathom_format_v1(
      fixture.raw, "doris", fixture.profile, "strict", "upper", 2, 100, "trailing", "follow", true,
    ),
  )
}

/// CLI homomorph (D-37/D-38): the doris-sql format CLI is a thin wrapper over
/// @api.format_with_ids mapped to CliOutcome; its stdout envelope is
/// @binding.format_result_json, frozen here via the same call chain. The
/// envelope carries dialect/profile/exact_release metadata (DIALECT-04).
fn cli_format_json(id : String) -> String {
  let fixture = baseline_fixture(id)
  let options = match @api.FormatOptions::new(
    @api.KeywordCase::Upper,
    2,
    100,
    @api.CommaStyle::Trailing,
    @api.NewlineStyle::FollowInput,
    true,
  ) {
    Ok(options) => options
    Err(_) => panic()
  }
  match @api.format_with_ids(fixture.raw, "doris", fixture.profile, "strict", options) {
    Ok(result) => {
      let exact_release = match @api.ParseOptions::new("doris", fixture.profile, "strict") {
        Ok(options) => options.profile_metadata().exact_release
        Err(_) => panic()
      }
      @binding.format_result_json(fixture.raw, result, "doris", fixture.profile, exact_release)
    }
    Err(_) => panic()
  }
}

/// Completion items JSON (RESEARCH §9.1: label/detail/start/end/new_text +
/// is_incomplete) at cursor=end, via the shared @completion.complete facade
/// the LSP completion handler consumes.
fn completion_json(id : String) -> String {
  let fixture = baseline_fixture(id)
  let list = match @completion.complete(fixture.raw, "doris", fixture.profile, fixture.raw.length()) {
    Ok(list) => list
    Err(_) => return "{\"error\":\"completion failed\"}"
  }
  let items : Array[Json] = []
  for item in list.items {
    items.push({
      "label": Json::string(item.label),
      "detail": Json::string(item.detail),
      "start_byte": Json::number(item.start_byte.to_double()),
      "end_byte": Json::number(item.end_byte.to_double()),
      "new_text": Json::string(item.new_text),
    })
  }
  @binding.stringify({
    "is_incomplete": Json::boolean(list.is_incomplete),
    "items": Json::array(items),
  })
}

/// LSP homomorph (parity/fixtures/lsp-tracer.json pattern): the protocol
/// output for a didOpen (publishDiagnostics carries the editor-mode parse
/// envelope) plus a formatting round-trip (the strict format envelope), as
/// two JSON documents — one per line, mirroring the tracer fixture's
/// parse-envelope + format section.
fn lsp_json(id : String) -> String {
  parse_json(id, "editor") + "\n" + format_json(id)
}

fn snapshot_test(t : @test.Test, content : String, filename : String) -> Unit raise SnapshotError {
  t.write(content)
  t.snapshot(filename=filename)
}

// ---------------------------------------------------------------------------
// Parse snapshots: full 44-fixture x {strict, editor} matrix (D-07).
// ---------------------------------------------------------------------------
test "parse 2.1-industrial strict" {
  let t = @test.Test("parse 2.1-industrial strict")
  snapshot_test(t, parse_json("2.1-industrial", "strict"), "2.1-industrial.2.1.strict.json")
}

test "parse 2.1-industrial editor" {
  let t = @test.Test("parse 2.1-industrial editor")
  snapshot_test(t, parse_json("2.1-industrial", "editor"), "2.1-industrial.2.1.editor.json")
}

test "parse 2.1-boundary-empty strict" {
  let t = @test.Test("parse 2.1-boundary-empty strict")
  snapshot_test(t, parse_json("2.1-boundary-empty", "strict"), "2.1-boundary-empty.2.1.strict.json")
}

test "parse 2.1-boundary-empty editor" {
  let t = @test.Test("parse 2.1-boundary-empty editor")
  snapshot_test(t, parse_json("2.1-boundary-empty", "editor"), "2.1-boundary-empty.2.1.editor.json")
}

test "parse 2.1-boundary-single strict" {
  let t = @test.Test("parse 2.1-boundary-single strict")
  snapshot_test(t, parse_json("2.1-boundary-single", "strict"), "2.1-boundary-single.2.1.strict.json")
}

test "parse 2.1-boundary-single editor" {
  let t = @test.Test("parse 2.1-boundary-single editor")
  snapshot_test(t, parse_json("2.1-boundary-single", "editor"), "2.1-boundary-single.2.1.editor.json")
}

test "parse 2.1-contextual-keyword strict" {
  let t = @test.Test("parse 2.1-contextual-keyword strict")
  snapshot_test(t, parse_json("2.1-contextual-keyword", "strict"), "2.1-contextual-keyword.2.1.strict.json")
}

test "parse 2.1-contextual-keyword editor" {
  let t = @test.Test("parse 2.1-contextual-keyword editor")
  snapshot_test(t, parse_json("2.1-contextual-keyword", "editor"), "2.1-contextual-keyword.2.1.editor.json")
}

test "parse 2.1-invalid-encoding strict" {
  let t = @test.Test("parse 2.1-invalid-encoding strict")
  snapshot_test(t, parse_json("2.1-invalid-encoding", "strict"), "2.1-invalid-encoding.2.1.strict.json")
}

test "parse 2.1-invalid-encoding editor" {
  let t = @test.Test("parse 2.1-invalid-encoding editor")
  snapshot_test(t, parse_json("2.1-invalid-encoding", "editor"), "2.1-invalid-encoding.2.1.editor.json")
}

test "parse 3.x-industrial strict" {
  let t = @test.Test("parse 3.x-industrial strict")
  snapshot_test(t, parse_json("3.x-industrial", "strict"), "3.x-industrial.3.x.strict.json")
}

test "parse 3.x-industrial editor" {
  let t = @test.Test("parse 3.x-industrial editor")
  snapshot_test(t, parse_json("3.x-industrial", "editor"), "3.x-industrial.3.x.editor.json")
}

test "parse 3.x-boundary-set-one strict" {
  let t = @test.Test("parse 3.x-boundary-set-one strict")
  snapshot_test(t, parse_json("3.x-boundary-set-one", "strict"), "3.x-boundary-set-one.3.x.strict.json")
}

test "parse 3.x-boundary-set-one editor" {
  let t = @test.Test("parse 3.x-boundary-set-one editor")
  snapshot_test(t, parse_json("3.x-boundary-set-one", "editor"), "3.x-boundary-set-one.3.x.editor.json")
}

test "parse 3.x-boundary-set-many strict" {
  let t = @test.Test("parse 3.x-boundary-set-many strict")
  snapshot_test(t, parse_json("3.x-boundary-set-many", "strict"), "3.x-boundary-set-many.3.x.strict.json")
}

test "parse 3.x-boundary-set-many editor" {
  let t = @test.Test("parse 3.x-boundary-set-many editor")
  snapshot_test(t, parse_json("3.x-boundary-set-many", "editor"), "3.x-boundary-set-many.3.x.editor.json")
}

test "parse 3.x-recovery strict" {
  let t = @test.Test("parse 3.x-recovery strict")
  snapshot_test(t, parse_json("3.x-recovery", "strict"), "3.x-recovery.3.x.strict.json")
}

test "parse 3.x-recovery editor" {
  let t = @test.Test("parse 3.x-recovery editor")
  snapshot_test(t, parse_json("3.x-recovery", "editor"), "3.x-recovery.3.x.editor.json")
}

test "parse 3.x-unsupported-profile strict" {
  let t = @test.Test("parse 3.x-unsupported-profile strict")
  snapshot_test(t, parse_json("3.x-unsupported-profile", "strict"), "3.x-unsupported-profile.3.x.strict.json")
}

test "parse 3.x-unsupported-profile editor" {
  let t = @test.Test("parse 3.x-unsupported-profile editor")
  snapshot_test(t, parse_json("3.x-unsupported-profile", "editor"), "3.x-unsupported-profile.3.x.editor.json")
}

test "parse 4.x-industrial strict" {
  let t = @test.Test("parse 4.x-industrial strict")
  snapshot_test(t, parse_json("4.x-industrial", "strict"), "4.x-industrial.4.x.strict.json")
}

test "parse 4.x-industrial editor" {
  let t = @test.Test("parse 4.x-industrial editor")
  snapshot_test(t, parse_json("4.x-industrial", "editor"), "4.x-industrial.4.x.editor.json")
}

test "parse 4.x-boundary-set-two strict" {
  let t = @test.Test("parse 4.x-boundary-set-two strict")
  snapshot_test(t, parse_json("4.x-boundary-set-two", "strict"), "4.x-boundary-set-two.4.x.strict.json")
}

test "parse 4.x-boundary-set-two editor" {
  let t = @test.Test("parse 4.x-boundary-set-two editor")
  snapshot_test(t, parse_json("4.x-boundary-set-two", "editor"), "4.x-boundary-set-two.4.x.editor.json")
}

test "parse 4.x-recovery strict" {
  let t = @test.Test("parse 4.x-recovery strict")
  snapshot_test(t, parse_json("4.x-recovery", "strict"), "4.x-recovery.4.x.strict.json")
}

test "parse 4.x-recovery editor" {
  let t = @test.Test("parse 4.x-recovery editor")
  snapshot_test(t, parse_json("4.x-recovery", "editor"), "4.x-recovery.4.x.editor.json")
}

test "parse 4.x-invalid-encoding strict" {
  let t = @test.Test("parse 4.x-invalid-encoding strict")
  snapshot_test(t, parse_json("4.x-invalid-encoding", "strict"), "4.x-invalid-encoding.4.x.strict.json")
}

test "parse 4.x-invalid-encoding editor" {
  let t = @test.Test("parse 4.x-invalid-encoding editor")
  snapshot_test(t, parse_json("4.x-invalid-encoding", "editor"), "4.x-invalid-encoding.4.x.editor.json")
}

test "parse 2.1-insert-values strict" {
  let t = @test.Test("parse 2.1-insert-values strict")
  snapshot_test(t, parse_json("2.1-insert-values", "strict"), "2.1-insert-values.2.1.strict.json")
}

test "parse 2.1-insert-values editor" {
  let t = @test.Test("parse 2.1-insert-values editor")
  snapshot_test(t, parse_json("2.1-insert-values", "editor"), "2.1-insert-values.2.1.editor.json")
}

test "parse 3.x-insert-values strict" {
  let t = @test.Test("parse 3.x-insert-values strict")
  snapshot_test(t, parse_json("3.x-insert-values", "strict"), "3.x-insert-values.3.x.strict.json")
}

test "parse 3.x-insert-values editor" {
  let t = @test.Test("parse 3.x-insert-values editor")
  snapshot_test(t, parse_json("3.x-insert-values", "editor"), "3.x-insert-values.3.x.editor.json")
}

test "parse 4.x-insert-values strict" {
  let t = @test.Test("parse 4.x-insert-values strict")
  snapshot_test(t, parse_json("4.x-insert-values", "strict"), "4.x-insert-values.4.x.strict.json")
}

test "parse 4.x-insert-values editor" {
  let t = @test.Test("parse 4.x-insert-values editor")
  snapshot_test(t, parse_json("4.x-insert-values", "editor"), "4.x-insert-values.4.x.editor.json")
}

test "parse 2.1-insert-select strict" {
  let t = @test.Test("parse 2.1-insert-select strict")
  snapshot_test(t, parse_json("2.1-insert-select", "strict"), "2.1-insert-select.2.1.strict.json")
}

test "parse 2.1-insert-select editor" {
  let t = @test.Test("parse 2.1-insert-select editor")
  snapshot_test(t, parse_json("2.1-insert-select", "editor"), "2.1-insert-select.2.1.editor.json")
}

test "parse 3.x-insert-select strict" {
  let t = @test.Test("parse 3.x-insert-select strict")
  snapshot_test(t, parse_json("3.x-insert-select", "strict"), "3.x-insert-select.3.x.strict.json")
}

test "parse 3.x-insert-select editor" {
  let t = @test.Test("parse 3.x-insert-select editor")
  snapshot_test(t, parse_json("3.x-insert-select", "editor"), "3.x-insert-select.3.x.editor.json")
}

test "parse 4.x-insert-select strict" {
  let t = @test.Test("parse 4.x-insert-select strict")
  snapshot_test(t, parse_json("4.x-insert-select", "strict"), "4.x-insert-select.4.x.strict.json")
}

test "parse 4.x-insert-select editor" {
  let t = @test.Test("parse 4.x-insert-select editor")
  snapshot_test(t, parse_json("4.x-insert-select", "editor"), "4.x-insert-select.4.x.editor.json")
}

test "parse 2.1-update strict" {
  let t = @test.Test("parse 2.1-update strict")
  snapshot_test(t, parse_json("2.1-update", "strict"), "2.1-update.2.1.strict.json")
}

test "parse 2.1-update editor" {
  let t = @test.Test("parse 2.1-update editor")
  snapshot_test(t, parse_json("2.1-update", "editor"), "2.1-update.2.1.editor.json")
}

test "parse 3.x-update strict" {
  let t = @test.Test("parse 3.x-update strict")
  snapshot_test(t, parse_json("3.x-update", "strict"), "3.x-update.3.x.strict.json")
}

test "parse 3.x-update editor" {
  let t = @test.Test("parse 3.x-update editor")
  snapshot_test(t, parse_json("3.x-update", "editor"), "3.x-update.3.x.editor.json")
}

test "parse 4.x-update strict" {
  let t = @test.Test("parse 4.x-update strict")
  snapshot_test(t, parse_json("4.x-update", "strict"), "4.x-update.4.x.strict.json")
}

test "parse 4.x-update editor" {
  let t = @test.Test("parse 4.x-update editor")
  snapshot_test(t, parse_json("4.x-update", "editor"), "4.x-update.4.x.editor.json")
}

test "parse 2.1-delete strict" {
  let t = @test.Test("parse 2.1-delete strict")
  snapshot_test(t, parse_json("2.1-delete", "strict"), "2.1-delete.2.1.strict.json")
}

test "parse 2.1-delete editor" {
  let t = @test.Test("parse 2.1-delete editor")
  snapshot_test(t, parse_json("2.1-delete", "editor"), "2.1-delete.2.1.editor.json")
}

test "parse 3.x-delete strict" {
  let t = @test.Test("parse 3.x-delete strict")
  snapshot_test(t, parse_json("3.x-delete", "strict"), "3.x-delete.3.x.strict.json")
}

test "parse 3.x-delete editor" {
  let t = @test.Test("parse 3.x-delete editor")
  snapshot_test(t, parse_json("3.x-delete", "editor"), "3.x-delete.3.x.editor.json")
}

test "parse 4.x-delete strict" {
  let t = @test.Test("parse 4.x-delete strict")
  snapshot_test(t, parse_json("4.x-delete", "strict"), "4.x-delete.4.x.strict.json")
}

test "parse 4.x-delete editor" {
  let t = @test.Test("parse 4.x-delete editor")
  snapshot_test(t, parse_json("4.x-delete", "editor"), "4.x-delete.4.x.editor.json")
}

test "parse 2.1-create-table strict" {
  let t = @test.Test("parse 2.1-create-table strict")
  snapshot_test(t, parse_json("2.1-create-table", "strict"), "2.1-create-table.2.1.strict.json")
}

test "parse 2.1-create-table editor" {
  let t = @test.Test("parse 2.1-create-table editor")
  snapshot_test(t, parse_json("2.1-create-table", "editor"), "2.1-create-table.2.1.editor.json")
}

test "parse 3.x-create-table strict" {
  let t = @test.Test("parse 3.x-create-table strict")
  snapshot_test(t, parse_json("3.x-create-table", "strict"), "3.x-create-table.3.x.strict.json")
}

test "parse 3.x-create-table editor" {
  let t = @test.Test("parse 3.x-create-table editor")
  snapshot_test(t, parse_json("3.x-create-table", "editor"), "3.x-create-table.3.x.editor.json")
}

test "parse 4.x-create-table strict" {
  let t = @test.Test("parse 4.x-create-table strict")
  snapshot_test(t, parse_json("4.x-create-table", "strict"), "4.x-create-table.4.x.strict.json")
}

test "parse 4.x-create-table editor" {
  let t = @test.Test("parse 4.x-create-table editor")
  snapshot_test(t, parse_json("4.x-create-table", "editor"), "4.x-create-table.4.x.editor.json")
}

test "parse 2.1-create-view strict" {
  let t = @test.Test("parse 2.1-create-view strict")
  snapshot_test(t, parse_json("2.1-create-view", "strict"), "2.1-create-view.2.1.strict.json")
}

test "parse 2.1-create-view editor" {
  let t = @test.Test("parse 2.1-create-view editor")
  snapshot_test(t, parse_json("2.1-create-view", "editor"), "2.1-create-view.2.1.editor.json")
}

test "parse 3.x-create-view strict" {
  let t = @test.Test("parse 3.x-create-view strict")
  snapshot_test(t, parse_json("3.x-create-view", "strict"), "3.x-create-view.3.x.strict.json")
}

test "parse 3.x-create-view editor" {
  let t = @test.Test("parse 3.x-create-view editor")
  snapshot_test(t, parse_json("3.x-create-view", "editor"), "3.x-create-view.3.x.editor.json")
}

test "parse 4.x-create-view strict" {
  let t = @test.Test("parse 4.x-create-view strict")
  snapshot_test(t, parse_json("4.x-create-view", "strict"), "4.x-create-view.4.x.strict.json")
}

test "parse 4.x-create-view editor" {
  let t = @test.Test("parse 4.x-create-view editor")
  snapshot_test(t, parse_json("4.x-create-view", "editor"), "4.x-create-view.4.x.editor.json")
}

test "parse 2.1-create-index strict" {
  let t = @test.Test("parse 2.1-create-index strict")
  snapshot_test(t, parse_json("2.1-create-index", "strict"), "2.1-create-index.2.1.strict.json")
}

test "parse 2.1-create-index editor" {
  let t = @test.Test("parse 2.1-create-index editor")
  snapshot_test(t, parse_json("2.1-create-index", "editor"), "2.1-create-index.2.1.editor.json")
}

test "parse 3.x-create-index strict" {
  let t = @test.Test("parse 3.x-create-index strict")
  snapshot_test(t, parse_json("3.x-create-index", "strict"), "3.x-create-index.3.x.strict.json")
}

test "parse 3.x-create-index editor" {
  let t = @test.Test("parse 3.x-create-index editor")
  snapshot_test(t, parse_json("3.x-create-index", "editor"), "3.x-create-index.3.x.editor.json")
}

test "parse 4.x-create-index strict" {
  let t = @test.Test("parse 4.x-create-index strict")
  snapshot_test(t, parse_json("4.x-create-index", "strict"), "4.x-create-index.4.x.strict.json")
}

test "parse 4.x-create-index editor" {
  let t = @test.Test("parse 4.x-create-index editor")
  snapshot_test(t, parse_json("4.x-create-index", "editor"), "4.x-create-index.4.x.editor.json")
}

test "parse 4.x-insert-overwrite strict" {
  let t = @test.Test("parse 4.x-insert-overwrite strict")
  snapshot_test(t, parse_json("4.x-insert-overwrite", "strict"), "4.x-insert-overwrite.4.x.strict.json")
}

test "parse 4.x-insert-overwrite editor" {
  let t = @test.Test("parse 4.x-insert-overwrite editor")
  snapshot_test(t, parse_json("4.x-insert-overwrite", "editor"), "4.x-insert-overwrite.4.x.editor.json")
}

test "parse 2.1-merge strict" {
  let t = @test.Test("parse 2.1-merge strict")
  snapshot_test(t, parse_json("2.1-merge", "strict"), "2.1-merge.2.1.strict.json")
}

test "parse 2.1-merge editor" {
  let t = @test.Test("parse 2.1-merge editor")
  snapshot_test(t, parse_json("2.1-merge", "editor"), "2.1-merge.2.1.editor.json")
}

test "parse 3.x-merge strict" {
  let t = @test.Test("parse 3.x-merge strict")
  snapshot_test(t, parse_json("3.x-merge", "strict"), "3.x-merge.3.x.strict.json")
}

test "parse 3.x-merge editor" {
  let t = @test.Test("parse 3.x-merge editor")
  snapshot_test(t, parse_json("3.x-merge", "editor"), "3.x-merge.3.x.editor.json")
}

test "parse 4.x-merge strict" {
  let t = @test.Test("parse 4.x-merge strict")
  snapshot_test(t, parse_json("4.x-merge", "strict"), "4.x-merge.4.x.strict.json")
}

test "parse 4.x-merge editor" {
  let t = @test.Test("parse 4.x-merge editor")
  snapshot_test(t, parse_json("4.x-merge", "editor"), "4.x-merge.4.x.editor.json")
}

test "parse 4.x-create-table-ctas strict" {
  let t = @test.Test("parse 4.x-create-table-ctas strict")
  snapshot_test(t, parse_json("4.x-create-table-ctas", "strict"), "4.x-create-table-ctas.4.x.strict.json")
}

test "parse 4.x-create-table-ctas editor" {
  let t = @test.Test("parse 4.x-create-table-ctas editor")
  snapshot_test(t, parse_json("4.x-create-table-ctas", "editor"), "4.x-create-table-ctas.4.x.editor.json")
}

test "parse 4.x-create-table-like strict" {
  let t = @test.Test("parse 4.x-create-table-like strict")
  snapshot_test(t, parse_json("4.x-create-table-like", "strict"), "4.x-create-table-like.4.x.strict.json")
}

test "parse 4.x-create-table-like editor" {
  let t = @test.Test("parse 4.x-create-table-like editor")
  snapshot_test(t, parse_json("4.x-create-table-like", "editor"), "4.x-create-table-like.4.x.editor.json")
}

test "parse 4.x-create-materialized-view strict" {
  let t = @test.Test("parse 4.x-create-materialized-view strict")
  snapshot_test(t, parse_json("4.x-create-materialized-view", "strict"), "4.x-create-materialized-view.4.x.strict.json")
}

test "parse 4.x-create-materialized-view editor" {
  let t = @test.Test("parse 4.x-create-materialized-view editor")
  snapshot_test(t, parse_json("4.x-create-materialized-view", "editor"), "4.x-create-materialized-view.4.x.editor.json")
}

test "parse 4.x-script-multi-statement strict" {
  let t = @test.Test("parse 4.x-script-multi-statement strict")
  snapshot_test(t, parse_json("4.x-script-multi-statement", "strict"), "4.x-script-multi-statement.4.x.strict.json")
}

test "parse 4.x-script-multi-statement editor" {
  let t = @test.Test("parse 4.x-script-multi-statement editor")
  snapshot_test(t, parse_json("4.x-script-multi-statement", "editor"), "4.x-script-multi-statement.4.x.editor.json")
}

test "parse 4.x-malformed-recovery strict" {
  let t = @test.Test("parse 4.x-malformed-recovery strict")
  snapshot_test(t, parse_json("4.x-malformed-recovery", "strict"), "4.x-malformed-recovery.4.x.strict.json")
}

test "parse 4.x-malformed-recovery editor" {
  let t = @test.Test("parse 4.x-malformed-recovery editor")
  snapshot_test(t, parse_json("4.x-malformed-recovery", "editor"), "4.x-malformed-recovery.4.x.editor.json")
}

// ---------------------------------------------------------------------------
// Format snapshots: full expected-valid matrix (35 fixtures, default options).
// ---------------------------------------------------------------------------
test "format 2.1-industrial" {
  let t = @test.Test("format 2.1-industrial")
  snapshot_test(t, format_json("2.1-industrial"), "2.1-industrial.2.1.format.json")
}

test "format 2.1-boundary-single" {
  let t = @test.Test("format 2.1-boundary-single")
  snapshot_test(t, format_json("2.1-boundary-single"), "2.1-boundary-single.2.1.format.json")
}

test "format 2.1-contextual-keyword" {
  let t = @test.Test("format 2.1-contextual-keyword")
  snapshot_test(t, format_json("2.1-contextual-keyword"), "2.1-contextual-keyword.2.1.format.json")
}

test "format 3.x-industrial" {
  let t = @test.Test("format 3.x-industrial")
  snapshot_test(t, format_json("3.x-industrial"), "3.x-industrial.3.x.format.json")
}

test "format 3.x-boundary-set-one" {
  let t = @test.Test("format 3.x-boundary-set-one")
  snapshot_test(t, format_json("3.x-boundary-set-one"), "3.x-boundary-set-one.3.x.format.json")
}

test "format 3.x-boundary-set-many" {
  let t = @test.Test("format 3.x-boundary-set-many")
  snapshot_test(t, format_json("3.x-boundary-set-many"), "3.x-boundary-set-many.3.x.format.json")
}

test "format 4.x-industrial" {
  let t = @test.Test("format 4.x-industrial")
  snapshot_test(t, format_json("4.x-industrial"), "4.x-industrial.4.x.format.json")
}

test "format 4.x-boundary-set-two" {
  let t = @test.Test("format 4.x-boundary-set-two")
  snapshot_test(t, format_json("4.x-boundary-set-two"), "4.x-boundary-set-two.4.x.format.json")
}

test "format 2.1-insert-values" {
  let t = @test.Test("format 2.1-insert-values")
  snapshot_test(t, format_json("2.1-insert-values"), "2.1-insert-values.2.1.format.json")
}

test "format 3.x-insert-values" {
  let t = @test.Test("format 3.x-insert-values")
  snapshot_test(t, format_json("3.x-insert-values"), "3.x-insert-values.3.x.format.json")
}

test "format 4.x-insert-values" {
  let t = @test.Test("format 4.x-insert-values")
  snapshot_test(t, format_json("4.x-insert-values"), "4.x-insert-values.4.x.format.json")
}

test "format 2.1-insert-select" {
  let t = @test.Test("format 2.1-insert-select")
  snapshot_test(t, format_json("2.1-insert-select"), "2.1-insert-select.2.1.format.json")
}

test "format 3.x-insert-select" {
  let t = @test.Test("format 3.x-insert-select")
  snapshot_test(t, format_json("3.x-insert-select"), "3.x-insert-select.3.x.format.json")
}

test "format 4.x-insert-select" {
  let t = @test.Test("format 4.x-insert-select")
  snapshot_test(t, format_json("4.x-insert-select"), "4.x-insert-select.4.x.format.json")
}

test "format 2.1-update" {
  let t = @test.Test("format 2.1-update")
  snapshot_test(t, format_json("2.1-update"), "2.1-update.2.1.format.json")
}

test "format 3.x-update" {
  let t = @test.Test("format 3.x-update")
  snapshot_test(t, format_json("3.x-update"), "3.x-update.3.x.format.json")
}

test "format 4.x-update" {
  let t = @test.Test("format 4.x-update")
  snapshot_test(t, format_json("4.x-update"), "4.x-update.4.x.format.json")
}

test "format 2.1-delete" {
  let t = @test.Test("format 2.1-delete")
  snapshot_test(t, format_json("2.1-delete"), "2.1-delete.2.1.format.json")
}

test "format 3.x-delete" {
  let t = @test.Test("format 3.x-delete")
  snapshot_test(t, format_json("3.x-delete"), "3.x-delete.3.x.format.json")
}

test "format 4.x-delete" {
  let t = @test.Test("format 4.x-delete")
  snapshot_test(t, format_json("4.x-delete"), "4.x-delete.4.x.format.json")
}

test "format 2.1-create-table" {
  let t = @test.Test("format 2.1-create-table")
  snapshot_test(t, format_json("2.1-create-table"), "2.1-create-table.2.1.format.json")
}

test "format 3.x-create-table" {
  let t = @test.Test("format 3.x-create-table")
  snapshot_test(t, format_json("3.x-create-table"), "3.x-create-table.3.x.format.json")
}

test "format 4.x-create-table" {
  let t = @test.Test("format 4.x-create-table")
  snapshot_test(t, format_json("4.x-create-table"), "4.x-create-table.4.x.format.json")
}

test "format 2.1-create-view" {
  let t = @test.Test("format 2.1-create-view")
  snapshot_test(t, format_json("2.1-create-view"), "2.1-create-view.2.1.format.json")
}

test "format 3.x-create-view" {
  let t = @test.Test("format 3.x-create-view")
  snapshot_test(t, format_json("3.x-create-view"), "3.x-create-view.3.x.format.json")
}

test "format 4.x-create-view" {
  let t = @test.Test("format 4.x-create-view")
  snapshot_test(t, format_json("4.x-create-view"), "4.x-create-view.4.x.format.json")
}

test "format 2.1-create-index" {
  let t = @test.Test("format 2.1-create-index")
  snapshot_test(t, format_json("2.1-create-index"), "2.1-create-index.2.1.format.json")
}

test "format 3.x-create-index" {
  let t = @test.Test("format 3.x-create-index")
  snapshot_test(t, format_json("3.x-create-index"), "3.x-create-index.3.x.format.json")
}

test "format 4.x-create-index" {
  let t = @test.Test("format 4.x-create-index")
  snapshot_test(t, format_json("4.x-create-index"), "4.x-create-index.4.x.format.json")
}

test "format 4.x-insert-overwrite" {
  let t = @test.Test("format 4.x-insert-overwrite")
  snapshot_test(t, format_json("4.x-insert-overwrite"), "4.x-insert-overwrite.4.x.format.json")
}

test "format 4.x-merge" {
  let t = @test.Test("format 4.x-merge")
  snapshot_test(t, format_json("4.x-merge"), "4.x-merge.4.x.format.json")
}

test "format 4.x-create-table-ctas" {
  let t = @test.Test("format 4.x-create-table-ctas")
  snapshot_test(t, format_json("4.x-create-table-ctas"), "4.x-create-table-ctas.4.x.format.json")
}

test "format 4.x-create-table-like" {
  let t = @test.Test("format 4.x-create-table-like")
  snapshot_test(t, format_json("4.x-create-table-like"), "4.x-create-table-like.4.x.format.json")
}

test "format 4.x-create-materialized-view" {
  let t = @test.Test("format 4.x-create-materialized-view")
  snapshot_test(t, format_json("4.x-create-materialized-view"), "4.x-create-materialized-view.4.x.format.json")
}

test "format 4.x-script-multi-statement" {
  let t = @test.Test("format 4.x-script-multi-statement")
  snapshot_test(t, format_json("4.x-script-multi-statement"), "4.x-script-multi-statement.4.x.format.json")
}

// ---------------------------------------------------------------------------
// CLI homomorph snapshots: full expected-valid matrix (exit-code/stdout surface).
// ---------------------------------------------------------------------------
test "cli 2.1-industrial" {
  let t = @test.Test("cli 2.1-industrial")
  snapshot_test(t, cli_format_json("2.1-industrial"), "2.1-industrial.2.1.cli.json")
}

test "cli 2.1-boundary-single" {
  let t = @test.Test("cli 2.1-boundary-single")
  snapshot_test(t, cli_format_json("2.1-boundary-single"), "2.1-boundary-single.2.1.cli.json")
}

test "cli 2.1-contextual-keyword" {
  let t = @test.Test("cli 2.1-contextual-keyword")
  snapshot_test(t, cli_format_json("2.1-contextual-keyword"), "2.1-contextual-keyword.2.1.cli.json")
}

test "cli 3.x-industrial" {
  let t = @test.Test("cli 3.x-industrial")
  snapshot_test(t, cli_format_json("3.x-industrial"), "3.x-industrial.3.x.cli.json")
}

test "cli 3.x-boundary-set-one" {
  let t = @test.Test("cli 3.x-boundary-set-one")
  snapshot_test(t, cli_format_json("3.x-boundary-set-one"), "3.x-boundary-set-one.3.x.cli.json")
}

test "cli 3.x-boundary-set-many" {
  let t = @test.Test("cli 3.x-boundary-set-many")
  snapshot_test(t, cli_format_json("3.x-boundary-set-many"), "3.x-boundary-set-many.3.x.cli.json")
}

test "cli 4.x-industrial" {
  let t = @test.Test("cli 4.x-industrial")
  snapshot_test(t, cli_format_json("4.x-industrial"), "4.x-industrial.4.x.cli.json")
}

test "cli 4.x-boundary-set-two" {
  let t = @test.Test("cli 4.x-boundary-set-two")
  snapshot_test(t, cli_format_json("4.x-boundary-set-two"), "4.x-boundary-set-two.4.x.cli.json")
}

test "cli 2.1-insert-values" {
  let t = @test.Test("cli 2.1-insert-values")
  snapshot_test(t, cli_format_json("2.1-insert-values"), "2.1-insert-values.2.1.cli.json")
}

test "cli 3.x-insert-values" {
  let t = @test.Test("cli 3.x-insert-values")
  snapshot_test(t, cli_format_json("3.x-insert-values"), "3.x-insert-values.3.x.cli.json")
}

test "cli 4.x-insert-values" {
  let t = @test.Test("cli 4.x-insert-values")
  snapshot_test(t, cli_format_json("4.x-insert-values"), "4.x-insert-values.4.x.cli.json")
}

test "cli 2.1-insert-select" {
  let t = @test.Test("cli 2.1-insert-select")
  snapshot_test(t, cli_format_json("2.1-insert-select"), "2.1-insert-select.2.1.cli.json")
}

test "cli 3.x-insert-select" {
  let t = @test.Test("cli 3.x-insert-select")
  snapshot_test(t, cli_format_json("3.x-insert-select"), "3.x-insert-select.3.x.cli.json")
}

test "cli 4.x-insert-select" {
  let t = @test.Test("cli 4.x-insert-select")
  snapshot_test(t, cli_format_json("4.x-insert-select"), "4.x-insert-select.4.x.cli.json")
}

test "cli 2.1-update" {
  let t = @test.Test("cli 2.1-update")
  snapshot_test(t, cli_format_json("2.1-update"), "2.1-update.2.1.cli.json")
}

test "cli 3.x-update" {
  let t = @test.Test("cli 3.x-update")
  snapshot_test(t, cli_format_json("3.x-update"), "3.x-update.3.x.cli.json")
}

test "cli 4.x-update" {
  let t = @test.Test("cli 4.x-update")
  snapshot_test(t, cli_format_json("4.x-update"), "4.x-update.4.x.cli.json")
}

test "cli 2.1-delete" {
  let t = @test.Test("cli 2.1-delete")
  snapshot_test(t, cli_format_json("2.1-delete"), "2.1-delete.2.1.cli.json")
}

test "cli 3.x-delete" {
  let t = @test.Test("cli 3.x-delete")
  snapshot_test(t, cli_format_json("3.x-delete"), "3.x-delete.3.x.cli.json")
}

test "cli 4.x-delete" {
  let t = @test.Test("cli 4.x-delete")
  snapshot_test(t, cli_format_json("4.x-delete"), "4.x-delete.4.x.cli.json")
}

test "cli 2.1-create-table" {
  let t = @test.Test("cli 2.1-create-table")
  snapshot_test(t, cli_format_json("2.1-create-table"), "2.1-create-table.2.1.cli.json")
}

test "cli 3.x-create-table" {
  let t = @test.Test("cli 3.x-create-table")
  snapshot_test(t, cli_format_json("3.x-create-table"), "3.x-create-table.3.x.cli.json")
}

test "cli 4.x-create-table" {
  let t = @test.Test("cli 4.x-create-table")
  snapshot_test(t, cli_format_json("4.x-create-table"), "4.x-create-table.4.x.cli.json")
}

test "cli 2.1-create-view" {
  let t = @test.Test("cli 2.1-create-view")
  snapshot_test(t, cli_format_json("2.1-create-view"), "2.1-create-view.2.1.cli.json")
}

test "cli 3.x-create-view" {
  let t = @test.Test("cli 3.x-create-view")
  snapshot_test(t, cli_format_json("3.x-create-view"), "3.x-create-view.3.x.cli.json")
}

test "cli 4.x-create-view" {
  let t = @test.Test("cli 4.x-create-view")
  snapshot_test(t, cli_format_json("4.x-create-view"), "4.x-create-view.4.x.cli.json")
}

test "cli 2.1-create-index" {
  let t = @test.Test("cli 2.1-create-index")
  snapshot_test(t, cli_format_json("2.1-create-index"), "2.1-create-index.2.1.cli.json")
}

test "cli 3.x-create-index" {
  let t = @test.Test("cli 3.x-create-index")
  snapshot_test(t, cli_format_json("3.x-create-index"), "3.x-create-index.3.x.cli.json")
}

test "cli 4.x-create-index" {
  let t = @test.Test("cli 4.x-create-index")
  snapshot_test(t, cli_format_json("4.x-create-index"), "4.x-create-index.4.x.cli.json")
}

test "cli 4.x-insert-overwrite" {
  let t = @test.Test("cli 4.x-insert-overwrite")
  snapshot_test(t, cli_format_json("4.x-insert-overwrite"), "4.x-insert-overwrite.4.x.cli.json")
}

test "cli 4.x-merge" {
  let t = @test.Test("cli 4.x-merge")
  snapshot_test(t, cli_format_json("4.x-merge"), "4.x-merge.4.x.cli.json")
}

test "cli 4.x-create-table-ctas" {
  let t = @test.Test("cli 4.x-create-table-ctas")
  snapshot_test(t, cli_format_json("4.x-create-table-ctas"), "4.x-create-table-ctas.4.x.cli.json")
}

test "cli 4.x-create-table-like" {
  let t = @test.Test("cli 4.x-create-table-like")
  snapshot_test(t, cli_format_json("4.x-create-table-like"), "4.x-create-table-like.4.x.cli.json")
}

test "cli 4.x-create-materialized-view" {
  let t = @test.Test("cli 4.x-create-materialized-view")
  snapshot_test(t, cli_format_json("4.x-create-materialized-view"), "4.x-create-materialized-view.4.x.cli.json")
}

test "cli 4.x-script-multi-statement" {
  let t = @test.Test("cli 4.x-script-multi-statement")
  snapshot_test(t, cli_format_json("4.x-script-multi-statement"), "4.x-script-multi-statement.4.x.cli.json")
}

// ---------------------------------------------------------------------------
// Completion snapshots: representative subset (one fixture per profile per
// statement class; enumerated in approved-changes.md item 6).
// ---------------------------------------------------------------------------
test "completion 2.1-industrial" {
  let t = @test.Test("completion 2.1-industrial")
  snapshot_test(t, completion_json("2.1-industrial"), "2.1-industrial.2.1.completion.json")
}

test "completion 2.1-insert-values" {
  let t = @test.Test("completion 2.1-insert-values")
  snapshot_test(t, completion_json("2.1-insert-values"), "2.1-insert-values.2.1.completion.json")
}

test "completion 2.1-update" {
  let t = @test.Test("completion 2.1-update")
  snapshot_test(t, completion_json("2.1-update"), "2.1-update.2.1.completion.json")
}

test "completion 2.1-delete" {
  let t = @test.Test("completion 2.1-delete")
  snapshot_test(t, completion_json("2.1-delete"), "2.1-delete.2.1.completion.json")
}

test "completion 2.1-create-table" {
  let t = @test.Test("completion 2.1-create-table")
  snapshot_test(t, completion_json("2.1-create-table"), "2.1-create-table.2.1.completion.json")
}

test "completion 2.1-create-view" {
  let t = @test.Test("completion 2.1-create-view")
  snapshot_test(t, completion_json("2.1-create-view"), "2.1-create-view.2.1.completion.json")
}

test "completion 2.1-create-index" {
  let t = @test.Test("completion 2.1-create-index")
  snapshot_test(t, completion_json("2.1-create-index"), "2.1-create-index.2.1.completion.json")
}

test "completion 3.x-industrial" {
  let t = @test.Test("completion 3.x-industrial")
  snapshot_test(t, completion_json("3.x-industrial"), "3.x-industrial.3.x.completion.json")
}

test "completion 3.x-insert-values" {
  let t = @test.Test("completion 3.x-insert-values")
  snapshot_test(t, completion_json("3.x-insert-values"), "3.x-insert-values.3.x.completion.json")
}

test "completion 3.x-update" {
  let t = @test.Test("completion 3.x-update")
  snapshot_test(t, completion_json("3.x-update"), "3.x-update.3.x.completion.json")
}

test "completion 3.x-delete" {
  let t = @test.Test("completion 3.x-delete")
  snapshot_test(t, completion_json("3.x-delete"), "3.x-delete.3.x.completion.json")
}

test "completion 3.x-create-table" {
  let t = @test.Test("completion 3.x-create-table")
  snapshot_test(t, completion_json("3.x-create-table"), "3.x-create-table.3.x.completion.json")
}

test "completion 3.x-create-view" {
  let t = @test.Test("completion 3.x-create-view")
  snapshot_test(t, completion_json("3.x-create-view"), "3.x-create-view.3.x.completion.json")
}

test "completion 3.x-create-index" {
  let t = @test.Test("completion 3.x-create-index")
  snapshot_test(t, completion_json("3.x-create-index"), "3.x-create-index.3.x.completion.json")
}

test "completion 4.x-industrial" {
  let t = @test.Test("completion 4.x-industrial")
  snapshot_test(t, completion_json("4.x-industrial"), "4.x-industrial.4.x.completion.json")
}

test "completion 4.x-insert-values" {
  let t = @test.Test("completion 4.x-insert-values")
  snapshot_test(t, completion_json("4.x-insert-values"), "4.x-insert-values.4.x.completion.json")
}

test "completion 4.x-update" {
  let t = @test.Test("completion 4.x-update")
  snapshot_test(t, completion_json("4.x-update"), "4.x-update.4.x.completion.json")
}

test "completion 4.x-delete" {
  let t = @test.Test("completion 4.x-delete")
  snapshot_test(t, completion_json("4.x-delete"), "4.x-delete.4.x.completion.json")
}

test "completion 4.x-merge" {
  let t = @test.Test("completion 4.x-merge")
  snapshot_test(t, completion_json("4.x-merge"), "4.x-merge.4.x.completion.json")
}

test "completion 4.x-insert-overwrite" {
  let t = @test.Test("completion 4.x-insert-overwrite")
  snapshot_test(t, completion_json("4.x-insert-overwrite"), "4.x-insert-overwrite.4.x.completion.json")
}

test "completion 4.x-create-table" {
  let t = @test.Test("completion 4.x-create-table")
  snapshot_test(t, completion_json("4.x-create-table"), "4.x-create-table.4.x.completion.json")
}

test "completion 4.x-create-view" {
  let t = @test.Test("completion 4.x-create-view")
  snapshot_test(t, completion_json("4.x-create-view"), "4.x-create-view.4.x.completion.json")
}

test "completion 4.x-create-index" {
  let t = @test.Test("completion 4.x-create-index")
  snapshot_test(t, completion_json("4.x-create-index"), "4.x-create-index.4.x.completion.json")
}

test "completion 4.x-create-materialized-view" {
  let t = @test.Test("completion 4.x-create-materialized-view")
  snapshot_test(t, completion_json("4.x-create-materialized-view"), "4.x-create-materialized-view.4.x.completion.json")
}

test "completion 4.x-create-table-ctas" {
  let t = @test.Test("completion 4.x-create-table-ctas")
  snapshot_test(t, completion_json("4.x-create-table-ctas"), "4.x-create-table-ctas.4.x.completion.json")
}

test "completion 4.x-create-table-like" {
  let t = @test.Test("completion 4.x-create-table-like")
  snapshot_test(t, completion_json("4.x-create-table-like"), "4.x-create-table-like.4.x.completion.json")
}

test "completion 4.x-script-multi-statement" {
  let t = @test.Test("completion 4.x-script-multi-statement")
  snapshot_test(t, completion_json("4.x-script-multi-statement"), "4.x-script-multi-statement.4.x.completion.json")
}

// ---------------------------------------------------------------------------
// LSP homomorph snapshots: same representative subset (parse editor envelope
// + format strict envelope per fixture; lsp-tracer.json pattern).
// ---------------------------------------------------------------------------
test "lsp 2.1-industrial" {
  let t = @test.Test("lsp 2.1-industrial")
  snapshot_test(t, lsp_json("2.1-industrial"), "2.1-industrial.2.1.lsp.json")
}

test "lsp 2.1-insert-values" {
  let t = @test.Test("lsp 2.1-insert-values")
  snapshot_test(t, lsp_json("2.1-insert-values"), "2.1-insert-values.2.1.lsp.json")
}

test "lsp 2.1-update" {
  let t = @test.Test("lsp 2.1-update")
  snapshot_test(t, lsp_json("2.1-update"), "2.1-update.2.1.lsp.json")
}

test "lsp 2.1-delete" {
  let t = @test.Test("lsp 2.1-delete")
  snapshot_test(t, lsp_json("2.1-delete"), "2.1-delete.2.1.lsp.json")
}

test "lsp 2.1-create-table" {
  let t = @test.Test("lsp 2.1-create-table")
  snapshot_test(t, lsp_json("2.1-create-table"), "2.1-create-table.2.1.lsp.json")
}

test "lsp 2.1-create-view" {
  let t = @test.Test("lsp 2.1-create-view")
  snapshot_test(t, lsp_json("2.1-create-view"), "2.1-create-view.2.1.lsp.json")
}

test "lsp 2.1-create-index" {
  let t = @test.Test("lsp 2.1-create-index")
  snapshot_test(t, lsp_json("2.1-create-index"), "2.1-create-index.2.1.lsp.json")
}

test "lsp 3.x-industrial" {
  let t = @test.Test("lsp 3.x-industrial")
  snapshot_test(t, lsp_json("3.x-industrial"), "3.x-industrial.3.x.lsp.json")
}

test "lsp 3.x-insert-values" {
  let t = @test.Test("lsp 3.x-insert-values")
  snapshot_test(t, lsp_json("3.x-insert-values"), "3.x-insert-values.3.x.lsp.json")
}

test "lsp 3.x-update" {
  let t = @test.Test("lsp 3.x-update")
  snapshot_test(t, lsp_json("3.x-update"), "3.x-update.3.x.lsp.json")
}

test "lsp 3.x-delete" {
  let t = @test.Test("lsp 3.x-delete")
  snapshot_test(t, lsp_json("3.x-delete"), "3.x-delete.3.x.lsp.json")
}

test "lsp 3.x-create-table" {
  let t = @test.Test("lsp 3.x-create-table")
  snapshot_test(t, lsp_json("3.x-create-table"), "3.x-create-table.3.x.lsp.json")
}

test "lsp 3.x-create-view" {
  let t = @test.Test("lsp 3.x-create-view")
  snapshot_test(t, lsp_json("3.x-create-view"), "3.x-create-view.3.x.lsp.json")
}

test "lsp 3.x-create-index" {
  let t = @test.Test("lsp 3.x-create-index")
  snapshot_test(t, lsp_json("3.x-create-index"), "3.x-create-index.3.x.lsp.json")
}

test "lsp 4.x-industrial" {
  let t = @test.Test("lsp 4.x-industrial")
  snapshot_test(t, lsp_json("4.x-industrial"), "4.x-industrial.4.x.lsp.json")
}

test "lsp 4.x-insert-values" {
  let t = @test.Test("lsp 4.x-insert-values")
  snapshot_test(t, lsp_json("4.x-insert-values"), "4.x-insert-values.4.x.lsp.json")
}

test "lsp 4.x-update" {
  let t = @test.Test("lsp 4.x-update")
  snapshot_test(t, lsp_json("4.x-update"), "4.x-update.4.x.lsp.json")
}

test "lsp 4.x-delete" {
  let t = @test.Test("lsp 4.x-delete")
  snapshot_test(t, lsp_json("4.x-delete"), "4.x-delete.4.x.lsp.json")
}

test "lsp 4.x-merge" {
  let t = @test.Test("lsp 4.x-merge")
  snapshot_test(t, lsp_json("4.x-merge"), "4.x-merge.4.x.lsp.json")
}

test "lsp 4.x-insert-overwrite" {
  let t = @test.Test("lsp 4.x-insert-overwrite")
  snapshot_test(t, lsp_json("4.x-insert-overwrite"), "4.x-insert-overwrite.4.x.lsp.json")
}

test "lsp 4.x-create-table" {
  let t = @test.Test("lsp 4.x-create-table")
  snapshot_test(t, lsp_json("4.x-create-table"), "4.x-create-table.4.x.lsp.json")
}

test "lsp 4.x-create-view" {
  let t = @test.Test("lsp 4.x-create-view")
  snapshot_test(t, lsp_json("4.x-create-view"), "4.x-create-view.4.x.lsp.json")
}

test "lsp 4.x-create-index" {
  let t = @test.Test("lsp 4.x-create-index")
  snapshot_test(t, lsp_json("4.x-create-index"), "4.x-create-index.4.x.lsp.json")
}

test "lsp 4.x-create-materialized-view" {
  let t = @test.Test("lsp 4.x-create-materialized-view")
  snapshot_test(t, lsp_json("4.x-create-materialized-view"), "4.x-create-materialized-view.4.x.lsp.json")
}

test "lsp 4.x-create-table-ctas" {
  let t = @test.Test("lsp 4.x-create-table-ctas")
  snapshot_test(t, lsp_json("4.x-create-table-ctas"), "4.x-create-table-ctas.4.x.lsp.json")
}

test "lsp 4.x-create-table-like" {
  let t = @test.Test("lsp 4.x-create-table-like")
  snapshot_test(t, lsp_json("4.x-create-table-like"), "4.x-create-table-like.4.x.lsp.json")
}

test "lsp 4.x-script-multi-statement" {
  let t = @test.Test("lsp 4.x-script-multi-statement")
  snapshot_test(t, lsp_json("4.x-script-multi-statement"), "4.x-script-multi-statement.4.x.lsp.json")
}

// ---------------------------------------------------------------------------
// Cross-target byte equality (PARITY-02 foundation, research §9.2 step 5):
// this snapshot filename is shared by every target build of the parity
// suite; native, js, and wasm must reproduce identical bytes or the gate
// fails on the diverging target. CI runs the parity suite on native and
// linear-Wasm.
// ---------------------------------------------------------------------------
test "cross-target 4.x-industrial strict byte equality" {
  let t = @test.Test("cross-target 4.x-industrial strict byte equality")
  snapshot_test(t, parse_json("4.x-industrial", "strict"), "cross-target.4.x-industrial.strict.json")
}
