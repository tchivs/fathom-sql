-- Released Apache Doris 3.x UPDATE grammar examples (core SET/FROM/WHERE
-- forms; the ORDER BY/LIMIT clause is documented in the 4.x grammar only).
-- Source: https://doris.apache.org/docs/3.x/sql-manual/sql-statements/data-modification/DML/UPDATE/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql
UPDATE t1 SET c1 = 1 WHERE id = 1;
UPDATE t1 SET c1 = 1, c2 = 2 WHERE id = 1 AND name = 'a';
UPDATE t1 alias SET c1 = 1;
