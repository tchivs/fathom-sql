-- Released Apache Doris 4.x CREATE MATERIALIZED VIEW examples: the sync form
-- (restricted single-table body) plus the async form (BUILD/REFRESH clauses
-- with an unrestricted query, documented identically in the 2.1/3.x/4.x
-- async-materialized-view pages).
-- Sources:
--   https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/sync-materialized-view/CREATE-MATERIALIZED-VIEW/
--   https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/async-materialized-view/CREATE-ASYNC-MATERIALIZED-VIEW/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql
CREATE MATERIALIZED VIEW mv AS SELECT k, SUM(v) FROM t GROUP BY k;
CREATE MATERIALIZED VIEW complete_mv (orderkey COMMENT 'Order key') BUILD IMMEDIATE REFRESH AUTO ON SCHEDULE EVERY 1 DAY STARTS '2099-01-01 20:30:00' DISTRIBUTED BY HASH (orderkey) BUCKETS 2 PROPERTIES ("replication_num" = "1") AS SELECT o_orderkey, l_orderkey FROM orders LEFT JOIN lineitem ON l_orderkey = o_orderkey;
CREATE MATERIALIZED VIEW IF NOT EXISTS mv2 BUILD DEFERRED REFRESH COMPLETE ON MANUAL AS SELECT 1;
