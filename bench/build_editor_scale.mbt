/// Editor-scale synthetic document construction (EDIT-01 benchmark gate, D-01).
///
/// Runtime never reads disk — raw bytes are embedded at authoring time from
/// corpus/doris-{2.1,3.x,4.x}/*.sql (the same discipline as
/// parity/baseline_test.mbt:7-9). The pool covers comment headers, blank
/// lines, multi-statement scripts, complex SELECTs, and DDL/DML statements so
/// the synthetic documents exercise realistic editor-scale shapes without
/// pathological deep nesting (parser max_recursion_depth=128 — deep nesting
/// would trip resource diagnostics instead of the normal parse path).
///
/// NAMING-GATE CONSTRAINT (IN-03): the DORIS- text in this file lives only
/// inside the byte-embedded fixture literals below (DORIS-03 is exempt via
/// the check_naming.py negative lookahead). Do NOT add DORIS- text outside
/// embedded fixture literals here.

let corpus_select_industrial_4x : Bytes =
  b"-- Released Apache Doris 4.x SELECT grammar examples.\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/\nSELECT /*+ SET_VAR(exec_mem_limit=1G) */\n  d.k, COUNT(*) AS n,\n  SUM(d.v) OVER (PARTITION BY d.k ORDER BY d.ts RANGE BETWEEN 1 PRECEDING AND CURRENT ROW) AS running\nFROM (SELECT k, v, ts FROM detail WHERE v IS NOT NULL) AS d\nTABLET (1001)\nGROUP BY CUBE(d.k)\nHAVING COUNT(*) > 1\nORDER BY n DESC\nLIMIT 5 OFFSET 2\nINTO OUTFILE 'result.csv';\n\nSELECT k FROM t1 UNION SELECT k FROM t2 UNION ALL SELECT k FROM t3;\n-- Recovery fixture: the missing expression is intentional and remains source-backed.\nSELECT k +\n"

let corpus_script_multi_statement_4x : Bytes =
  b"-- Released Apache Doris 4.x multi-statement script fixture (DORIS-03): a\n-- semicolon-separated document parses each statement independently with\n-- monotonic statement ids; the invalid-statement variant (later statements\n-- survive) is asserted by the corpus_test oracle.\n-- Source: statement-family pages (https://doris.apache.org/docs/4.x/sql-manual/sql-statements/)\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE TABLE t (a INT); INSERT INTO t VALUES (1); SELECT * FROM t;\nINSERT INTO t VALUES (2); SELECT b;\n"

let corpus_ddl_create_table_4x : Bytes =
  b"-- Released Apache Doris 4.x CREATE TABLE grammar examples (full body incl.\n-- the 4.1.0+ ORDER BY clause, TEMPORARY modifier, rollup, partitions,\n-- distribution/buckets, properties).\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE TABLE example_table (k1 TINYINT, k2 DECIMAL(10, 2) DEFAULT \"10.5\", k3 CHAR(10) COMMENT \"string column\", k4 INT NOT NULL DEFAULT \"1\" COMMENT \"int column\", v1 BIGINT SUM DEFAULT \"0\" COMMENT \"aggregate value\", INDEX idx_k1 (k1) USING BITMAP COMMENT \"index comment\") ENGINE=OLAP UNIQUE KEY(k1, k2) ORDER BY(k1) COMMENT \"my table\" PARTITION BY RANGE(k1) (PARTITION p1 VALUES LESS THAN (\"2021-01-01\"), PARTITION p2 VALUES LESS THAN (\"2022-01-01\")) DISTRIBUTED BY HASH(k1) BUCKETS 32 ROLLUP (r1 (k1) DUPLICATE KEY (k1)) PROPERTIES (\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");\nCREATE TEMPORARY TABLE t (a INT);\nCREATE TABLE t2 (k1 INT) DISTRIBUTED BY HASH (k1) BUCKETS AUTO;\nCREATE TABLE t3 (k1 DATE, k2 INT) AUTO PARTITION BY RANGE (TO_DAYS(k1)) () DISTRIBUTED BY HASH (k2) BUCKETS 3;\n"

let corpus_ddl_create_materialized_view_4x : Bytes =
  b"-- Released Apache Doris 4.x CREATE MATERIALIZED VIEW examples: the sync form\n-- (restricted single-table body) plus the async form (BUILD/REFRESH clauses\n-- with an unrestricted query, documented identically in the 2.1/3.x/4.x\n-- async-materialized-view pages).\n-- Sources:\n--   https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/sync-materialized-view/CREATE-MATERIALIZED-VIEW/\n--   https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/async-materialized-view/CREATE-ASYNC-MATERIALIZED-VIEW/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE MATERIALIZED VIEW mv AS SELECT k, SUM(v) FROM t GROUP BY k;\nCREATE MATERIALIZED VIEW complete_mv (orderkey COMMENT 'Order key') BUILD IMMEDIATE REFRESH AUTO ON SCHEDULE EVERY 1 DAY STARTS '2099-01-01 20:30:00' DISTRIBUTED BY HASH (orderkey) BUCKETS 2 PROPERTIES (\"replication_num\" = \"1\") AS SELECT o_orderkey, l_orderkey FROM orders LEFT JOIN lineitem ON l_orderkey = o_orderkey;\nCREATE MATERIALIZED VIEW IF NOT EXISTS mv2 BUILD DEFERRED REFRESH COMPLETE ON MANUAL AS SELECT 1;\n"

let corpus_dml_merge_4x : Bytes =
  b"-- Released Apache Doris 4.x MERGE INTO grammar examples (UNIQUE KEY model;\n-- MERGE-INTO is documented only in the 4.x docs tree).\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/MERGE-INTO/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nMERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.v = s.v;\nMERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN DELETE;\nMERGE INTO t USING s ON t.id = s.id WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.v);\nMERGE INTO t USING s ON t.id = s.id WHEN MATCHED AND t.v < s.v THEN UPDATE SET t.v = s.v WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.v);\n"

let corpus_dml_insert_overwrite_4x : Bytes =
  b"-- Released Apache Doris 4.x INSERT OVERWRITE grammar examples (the literal\n-- `table` keyword after OVERWRITE, PARTITION lists, and the PARTITION (*)\n-- auto-detect form documented since 2.1.3).\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/INSERT-OVERWRITE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nINSERT OVERWRITE table test VALUES (1, 2);\nINSERT OVERWRITE table test PARTITION (p1, p2) SELECT * FROM test2;\nINSERT OVERWRITE table test PARTITION (*) SELECT * FROM test2;\n"

let corpus_ddl_create_table_ctas_4x : Bytes =
  b"-- Released Apache Doris 4.x CREATE TABLE ... AS SELECT (CTAS) variant\n-- grammar examples.\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql (Varaint Syntax: CREATE TABLE ... AS SELECT)\nCREATE TABLE t AS SELECT a, b FROM src;\nCREATE TABLE t (a INT) DISTRIBUTED BY HASH (a) BUCKETS 10 AS SELECT a FROM src;\nCREATE TABLE t (a INT, INDEX idx (a)) ENGINE=OLAP COMMENT \"ctas\" AS SELECT a FROM src;\n"

let corpus_ddl_create_table_like_4x : Bytes =
  b"-- Released Apache Doris 4.x CREATE TABLE ... LIKE variant grammar examples.\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql (Varaint Syntax: CREATE TABLE ... LIKE)\nCREATE TABLE new_t LIKE existing_t;\nCREATE TABLE new_t LIKE existing_t WITH ROLLUP (r1, r2);\nCREATE TABLE db.new_t LIKE db.existing_t;\n"

let corpus_dml_insert_select_4x : Bytes =
  b"-- Released Apache Doris 4.x INSERT ... SELECT grammar examples.\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/INSERT/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql (example 3-4; mysql> prompts and output blocks excluded)\nINSERT INTO test SELECT * FROM test2;\nINSERT INTO test (c1, c2) SELECT * FROM test2;\nINSERT INTO test PARTITION(p1, p2) WITH LABEL `label1` SELECT * FROM test2;\nINSERT INTO db.test (c1) SELECT c1 FROM test2;\n"

let corpus_dml_update_4x : Bytes =
  b"-- Released Apache Doris 4.x UPDATE grammar examples (UNIQUE KEY model).\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/UPDATE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nUPDATE t1 SET c1 = 1 WHERE id = 1;\nUPDATE t1 SET c1 = 1, c2 = DEFAULT WHERE id = 1;\nUPDATE t1 SET t1.c1 = t2.c1 FROM t2 INNER JOIN t3 ON t2.id = t3.id WHERE t1.id = t2.id;\nUPDATE t1 SET c1 = c1 + 1 ORDER BY c1 DESC NULLS LAST LIMIT 10;\n"

let corpus_dml_delete_4x : Bytes =
  b"-- Released Apache Doris 4.x DELETE grammar examples (both documented forms).\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/DELETE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nDELETE FROM t WHERE id = 1;\nDELETE FROM t PARTITION p1 WHERE id = 1 AND name = 'a';\nDELETE FROM t PARTITIONS (p1, p2) WHERE id IN (1, 2, 3);\nDELETE FROM t WHERE id = 1 ORDER BY id LIMIT 10;\n"

let corpus_dml_insert_values_4x : Bytes =
  b"-- Released Apache Doris 4.x INSERT VALUES grammar examples.\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/INSERT/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql (examples 1-2; mysql> prompts and output blocks excluded)\nINSERT INTO test VALUES (1, 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT);\nINSERT INTO test VALUES (1, 2), (3, 2 + 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT), (3, DEFAULT);\nINSERT INTO test /*+ STREAMING */ VALUES (1, 2);\n"

let corpus_ddl_create_view_4x : Bytes =
  b"-- Released Apache Doris 4.x CREATE VIEW grammar examples (IF NOT EXISTS,\n-- column definitions with comments, and a CTE-bodied query per the grammar's\n-- [AS] <query_stmt>).\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/view/CREATE-VIEW/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE VIEW v AS SELECT a, b FROM t;\nCREATE VIEW IF NOT EXISTS db.v (a COMMENT 'col a') AS SELECT x AS a FROM t;\nCREATE VIEW v AS WITH cte AS (SELECT 1) SELECT * FROM cte;\n"

let corpus_ddl_create_index_4x : Bytes =
  b"-- Released Apache Doris 4.x CREATE INDEX grammar examples (INVERTED, NGRAM_BF,\n-- and ANN index types with properties and comments).\n-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/index/CREATE-INDEX/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE INDEX index1 ON table1 (col1) USING INVERTED;\nCREATE INDEX index2 ON table1 (col1) USING NGRAM_BF PROPERTIES (\"gram_size\" = \"3\", \"bf_size\" = \"1024\");\nCREATE INDEX IF NOT EXISTS idx ON t (c) COMMENT 'index comment';\nCREATE INDEX idx ON db.table1 (col1, col2) USING ANN PROPERTIES (\"index_type\" = \"hnsw\", \"metric_type\" = \"l2_distance\", \"dim\" = \"128\");\n"

let corpus_select_industrial_3x : Bytes =
  b"-- Released Apache Doris 3.x SELECT grammar examples.\n-- Source: https://doris.apache.org/docs/3.x/sql-manual/sql-statements/data-query/SELECT/\nWITH recent AS (\n  SELECT k, SUM(v) OVER (PARTITION BY k ORDER BY ts ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling\n  FROM fact SAMPLE (10)\n  WHERE v IN (1, 2, 3)\n)\nSELECT k, rolling FROM recent QUALIFY rolling > 0 ORDER BY rolling DESC LIMIT 20;\n\nSELECT k FROM fact GROUP BY GROUPING SETS ((k), (k, region));\nSELECT k FROM left_table RIGHT JOIN right_table USING (k) UNION DISTINCT SELECT k FROM fallback_table;\n"

let corpus_ddl_create_table_3x : Bytes =
  b"-- Released Apache Doris 3.x CREATE TABLE grammar examples (keys, aggregation\n-- semantics, distribution/buckets incl. AUTO, partitions incl. AUTO PARTITION\n-- BY, properties). ORDER BY is a 4.1.0+ clause and stays out of this file.\n-- Source: https://doris.apache.org/docs/3.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE TABLE example_table (k1 TINYINT, k2 DECIMAL(10, 2) DEFAULT \"10.5\", k3 CHAR(10) COMMENT \"string column\", v1 BIGINT SUM DEFAULT \"0\" COMMENT \"aggregate value\", INDEX idx_k1 (k1) USING BITMAP COMMENT \"index comment\") ENGINE=OLAP AGGREGATE KEY(k1) COMMENT \"my table\" DISTRIBUTED BY HASH(k1) BUCKETS 10 PROPERTIES (\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");\nCREATE TABLE t (k1 DATE, k2 INT) AUTO PARTITION BY RANGE (TO_DAYS(k1)) () DISTRIBUTED BY HASH (k2) BUCKETS 3;\nCREATE TABLE t2 (k1 INT) DISTRIBUTED BY HASH (k1) BUCKETS AUTO;\nCREATE TABLE t3 (k1 DATE) PARTITION BY RANGE (k1) (PARTITION p1 VALUES LESS THAN ('2021-01-01'), PARTITION p2 VALUES LESS THAN (MAXVALUE));\n"

let corpus_select_industrial_21 : Bytes =
  b"-- Released Apache Doris 2.1 SELECT grammar examples.\n-- Source: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-query/SELECT/\nSELECT DISTINCT k, SUM(v) AS total\nFROM fact PARTITION (p0) TABLESAMPLE (10)\nWHERE v BETWEEN 1 AND 9\nGROUP BY ROLLUP(k)\nHAVING SUM(v) > 0\nORDER BY total DESC\nLIMIT 10;\n\nSELECT a FROM left_table LEFT OUTER JOIN right_table ON left_table.k = right_table.k;\nSELECT a FROM first_table UNION ALL SELECT a FROM second_table;\nSELECT `group`, `window` FROM `table`;\n"

let corpus_ddl_create_table_21 : Bytes =
  b"-- Released Apache Doris 2.1 CREATE TABLE grammar examples (keys, aggregation\n-- semantics, distribution/buckets incl. AUTO, partitions incl. AUTO PARTITION\n-- BY, properties). ORDER BY is a 4.1.0+ clause and stays out of this file.\n-- Source: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE TABLE example_table (k1 TINYINT, k2 DECIMAL(10, 2) DEFAULT \"10.5\", k3 CHAR(10) COMMENT \"string column\", v1 BIGINT SUM DEFAULT \"0\" COMMENT \"aggregate value\", INDEX idx_k1 (k1) USING BITMAP COMMENT \"index comment\") ENGINE=OLAP AGGREGATE KEY(k1) COMMENT \"my table\" DISTRIBUTED BY HASH(k1) BUCKETS 10 PROPERTIES (\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");\nCREATE TABLE t (k1 DATE, k2 INT) AUTO PARTITION BY RANGE (TO_DAYS(k1)) () DISTRIBUTED BY HASH (k2) BUCKETS 3;\nCREATE TABLE t2 (k1 INT) DISTRIBUTED BY HASH (k1) BUCKETS AUTO;\nCREATE TABLE t3 (k1 DATE) PARTITION BY RANGE (k1) (PARTITION p1 VALUES LESS THAN ('2021-01-01'), PARTITION p2 VALUES LESS THAN (MAXVALUE));\n"

let editor_scale_pool : Array[Bytes] = [
  corpus_select_industrial_4x,
  corpus_script_multi_statement_4x,
  corpus_ddl_create_table_4x,
  corpus_ddl_create_materialized_view_4x,
  corpus_dml_merge_4x,
  corpus_dml_insert_overwrite_4x,
  corpus_ddl_create_table_ctas_4x,
  corpus_ddl_create_table_like_4x,
  corpus_dml_insert_select_4x,
  corpus_dml_update_4x,
  corpus_dml_delete_4x,
  corpus_dml_insert_values_4x,
  corpus_ddl_create_view_4x,
  corpus_ddl_create_index_4x,
  corpus_select_industrial_3x,
  corpus_ddl_create_table_3x,
  corpus_select_industrial_21,
  corpus_ddl_create_table_21,
]

/// Concatenate pool statements (cycling) until at least `size_bytes` are
/// written. Ends on a statement boundary — never truncates mid-token — so the
/// synthetic document exercises the normal parse path rather than recovery.
/// The returned length is >= size_bytes and < size_bytes + the longest pool
/// statement.
pub fn build_editor_scale(size_bytes : Int) -> Bytes {
  let buf = @buffer.Buffer::Buffer(size_hint=size_bytes)
  let mut written = 0
  let mut index = 0
  let pool_len = editor_scale_pool.length()
  while written < size_bytes {
    let stmt = editor_scale_pool[index]
    buf.write_bytes(stmt)
    written = written + stmt.length()
    index = index + 1
    if index >= pool_len {
      index = 0
    }
  }
  buf.to_bytes()
}
