-- Released Apache Doris 4.x UPDATE grammar examples (UNIQUE KEY model).
-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/UPDATE/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql
UPDATE t1 SET c1 = 1 WHERE id = 1;
UPDATE t1 SET c1 = 1, c2 = DEFAULT WHERE id = 1;
UPDATE t1 SET t1.c1 = t2.c1 FROM t2 INNER JOIN t3 ON t2.id = t3.id WHERE t1.id = t2.id;
UPDATE t1 SET c1 = c1 + 1 ORDER BY c1 DESC NULLS LAST LIMIT 10;
