-- Released Apache Doris 2.1 CREATE INDEX grammar examples (INVERTED is the
-- only index type the 2.1 CREATE TABLE/INDEX pages document).
-- Source: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/table-and-view/index/CREATE-INDEX/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql
CREATE INDEX index1 ON table1 (col1) USING INVERTED;
CREATE INDEX idx ON db.table1 (col1, col2) USING INVERTED;
