-- Released Apache Doris 3.x SELECT grammar examples.
-- Source: https://doris.apache.org/docs/3.x/sql-manual/sql-statements/data-query/SELECT/
WITH recent AS (
  SELECT k, SUM(v) OVER (PARTITION BY k ORDER BY ts ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling
  FROM fact SAMPLE (10)
  WHERE v IN (1, 2, 3)
)
SELECT k, rolling FROM recent QUALIFY rolling > 0 ORDER BY rolling DESC LIMIT 20;

SELECT k FROM fact GROUP BY GROUPING SETS ((k), (k, region));
SELECT k FROM left_table RIGHT JOIN right_table USING (k) UNION DISTINCT SELECT k FROM fallback_table;
