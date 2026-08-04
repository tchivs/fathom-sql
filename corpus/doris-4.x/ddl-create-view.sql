-- Released Apache Doris 4.x CREATE VIEW grammar examples (IF NOT EXISTS,
-- column definitions with comments, and a CTE-bodied query per the grammar's
-- [AS] <query_stmt>).
-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/view/CREATE-VIEW/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql
CREATE VIEW v AS SELECT a, b FROM t;
CREATE VIEW IF NOT EXISTS db.v (a COMMENT 'col a') AS SELECT x AS a FROM t;
CREATE VIEW v AS WITH cte AS (SELECT 1) SELECT * FROM cte;
