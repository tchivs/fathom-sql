-- Released Apache Doris 2.1 INSERT ... SELECT grammar examples.
-- Source: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-modification/DML/INSERT/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql (example 3-4; mysql> prompts and output blocks excluded)
INSERT INTO test SELECT * FROM test2;
INSERT INTO test (c1, c2) SELECT * FROM test2;
INSERT INTO test PARTITION(p1, p2) WITH LABEL `label1` SELECT * FROM test2;
