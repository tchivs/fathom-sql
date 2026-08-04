-- Released Apache Doris 4.x CREATE TABLE ... AS SELECT (CTAS) variant
-- grammar examples.
-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql (Varaint Syntax: CREATE TABLE ... AS SELECT)
CREATE TABLE t AS SELECT a, b FROM src;
CREATE TABLE t (a INT) DISTRIBUTED BY HASH (a) BUCKETS 10 AS SELECT a FROM src;
CREATE TABLE t (a INT, INDEX idx (a)) ENGINE=OLAP COMMENT "ctas" AS SELECT a FROM src;
