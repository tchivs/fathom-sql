-- Released Apache Doris 4.x multi-statement script fixture (DORIS-03): a
-- semicolon-separated document parses each statement independently with
-- monotonic statement ids; the invalid-statement variant (later statements
-- survive) is asserted by the corpus_test oracle.
-- Source: statement-family pages (https://doris.apache.org/docs/4.x/sql-manual/sql-statements/)
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql
CREATE TABLE t (a INT); INSERT INTO t VALUES (1); SELECT * FROM t;
INSERT INTO t VALUES (2); SELECT b;
