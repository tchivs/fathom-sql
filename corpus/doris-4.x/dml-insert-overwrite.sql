-- Released Apache Doris 4.x INSERT OVERWRITE grammar examples (the literal
-- `table` keyword after OVERWRITE, PARTITION lists, and the PARTITION (*)
-- auto-detect form documented since 2.1.3).
-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/INSERT-OVERWRITE/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql
INSERT OVERWRITE table test VALUES (1, 2);
INSERT OVERWRITE table test PARTITION (p1, p2) SELECT * FROM test2;
INSERT OVERWRITE table test PARTITION (*) SELECT * FROM test2;
