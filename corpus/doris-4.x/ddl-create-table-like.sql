-- Released Apache Doris 4.x CREATE TABLE ... LIKE variant grammar examples.
-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql (Varaint Syntax: CREATE TABLE ... LIKE)
CREATE TABLE new_t LIKE existing_t;
CREATE TABLE new_t LIKE existing_t WITH ROLLUP (r1, r2);
CREATE TABLE db.new_t LIKE db.existing_t;
