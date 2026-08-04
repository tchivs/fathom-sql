-- Released Apache Doris 2.1 CREATE TABLE grammar examples (keys, aggregation
-- semantics, distribution/buckets incl. AUTO, partitions incl. AUTO PARTITION
-- BY, properties). ORDER BY is a 4.1.0+ clause and stays out of this file.
-- Source: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql
CREATE TABLE example_table (k1 TINYINT, k2 DECIMAL(10, 2) DEFAULT "10.5", k3 CHAR(10) COMMENT "string column", v1 BIGINT SUM DEFAULT "0" COMMENT "aggregate value", INDEX idx_k1 (k1) USING BITMAP COMMENT "index comment") ENGINE=OLAP AGGREGATE KEY(k1) COMMENT "my table" DISTRIBUTED BY HASH(k1) BUCKETS 10 PROPERTIES ("replication_num" = "1", "storage_medium" = "SSD");
CREATE TABLE t (k1 DATE, k2 INT) AUTO PARTITION BY RANGE (TO_DAYS(k1)) () DISTRIBUTED BY HASH (k2) BUCKETS 3;
CREATE TABLE t2 (k1 INT) DISTRIBUTED BY HASH (k1) BUCKETS AUTO;
CREATE TABLE t3 (k1 DATE) PARTITION BY RANGE (k1) (PARTITION p1 VALUES LESS THAN ('2021-01-01'), PARTITION p2 VALUES LESS THAN (MAXVALUE));
