-- Released Apache Doris 3.x CREATE VIEW grammar examples (plain and column
-- defined forms; IF NOT EXISTS / column comments verified on the 4.x page).
-- Source: https://doris.apache.org/docs/3.x/sql-manual/sql-statements/table-and-view/view/CREATE-VIEW/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql
CREATE VIEW v AS SELECT a, b FROM t;
CREATE VIEW v (a, b) AS SELECT a, b FROM t;
