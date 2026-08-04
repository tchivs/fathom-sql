-- Released Apache Doris 2.1 DELETE grammar examples (predicate form;
-- PARTITION/ORDER BY/LIMIT variants are documented in the 4.x grammar only).
-- Source: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-modification/DML/DELETE/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql
DELETE FROM t WHERE id = 1;
DELETE FROM t WHERE id IN (1, 2, 3) AND name = 'a';
