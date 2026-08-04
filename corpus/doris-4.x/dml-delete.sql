-- Released Apache Doris 4.x DELETE grammar examples (both documented forms).
-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/DELETE/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql
DELETE FROM t WHERE id = 1;
DELETE FROM t PARTITION p1 WHERE id = 1 AND name = 'a';
DELETE FROM t PARTITIONS (p1, p2) WHERE id IN (1, 2, 3);
DELETE FROM t WHERE id = 1 ORDER BY id LIMIT 10;
