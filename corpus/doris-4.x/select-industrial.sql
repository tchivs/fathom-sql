-- Released Apache Doris 4.x SELECT grammar examples.
-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/
SELECT /*+ SET_VAR(exec_mem_limit=1G) */
  d.k, COUNT(*) AS n,
  SUM(d.v) OVER (PARTITION BY d.k ORDER BY d.ts RANGE BETWEEN 1 PRECEDING AND CURRENT ROW) AS running
FROM (SELECT k, v, ts FROM detail WHERE v IS NOT NULL) AS d
TABLET (1001)
GROUP BY CUBE(d.k)
HAVING COUNT(*) > 1
ORDER BY n DESC
LIMIT 5 OFFSET 2
INTO OUTFILE 'result.csv';

SELECT k FROM t1 UNION SELECT k FROM t2 UNION ALL SELECT k FROM t3;
-- Recovery fixture: the missing expression is intentional and remains source-backed.
SELECT k, FROM malformed_projection;
