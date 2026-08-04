-- Released Apache Doris 4.x CREATE TABLE grammar examples (full body incl.
-- the 4.1.0+ ORDER BY clause, TEMPORARY modifier, rollup, partitions,
-- distribution/buckets, properties).
-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql
CREATE TABLE example_table (k1 TINYINT, k2 DECIMAL(10, 2) DEFAULT "10.5", k3 CHAR(10) COMMENT "string column", k4 INT NOT NULL DEFAULT "1" COMMENT "int column", v1 BIGINT SUM DEFAULT "0" COMMENT "aggregate value", INDEX idx_k1 (k1) USING BITMAP COMMENT "index comment") ENGINE=OLAP UNIQUE KEY(k1, k2) ORDER BY(k1) COMMENT "my table" PARTITION BY RANGE(k1) (PARTITION p1 VALUES LESS THAN ("2021-01-01"), PARTITION p2 VALUES LESS THAN ("2022-01-01")) DISTRIBUTED BY HASH(k1) BUCKETS 32 ROLLUP (r1 (k1) DUPLICATE KEY (k1)) PROPERTIES ("replication_num" = "1", "storage_medium" = "SSD");
CREATE TEMPORARY TABLE t (a INT);
CREATE TABLE t2 (k1 INT) DISTRIBUTED BY HASH (k1) BUCKETS AUTO;
CREATE TABLE t3 (k1 DATE, k2 INT) AUTO PARTITION BY RANGE (TO_DAYS(k1)) () DISTRIBUTED BY HASH (k2) BUCKETS 3;
