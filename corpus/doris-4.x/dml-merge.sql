-- Released Apache Doris 4.x MERGE INTO grammar examples (UNIQUE KEY model;
-- MERGE-INTO is documented only in the 4.x docs tree).
-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/MERGE-INTO/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql
MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.v = s.v;
MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN DELETE;
MERGE INTO t USING s ON t.id = s.id WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.v);
MERGE INTO t USING s ON t.id = s.id WHEN MATCHED AND t.v < s.v THEN UPDATE SET t.v = s.v WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.v);
