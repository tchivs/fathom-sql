-- Released Apache Doris 3.x INSERT VALUES grammar examples.
-- Source: https://doris.apache.org/docs/3.x/sql-manual/sql-statements/data-modification/DML/INSERT/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql (examples 1-2; mysql> prompts and output blocks excluded)
INSERT INTO test VALUES (1, 2);
INSERT INTO test (c1, c2) VALUES (1, DEFAULT);
INSERT INTO test VALUES (1, 2), (3, 2 + 2);
INSERT INTO test (c1, c2) VALUES (1, DEFAULT), (3, DEFAULT);
