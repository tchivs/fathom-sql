-- Released Apache Doris 4.x malformed DML recovery fixture: editor-mode
-- goldens assert bounded recovery, byte-exact replay, and DORIS-PARSE
-- diagnostics (Phase 1 recovery patterns).
-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/UPDATE/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql
UPDATE t SET x = 1 WHERE;
INSERT INTO t VALUES (1;
