-- Released Apache Doris 2.1 SELECT grammar examples.
-- Source: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-query/SELECT/
SELECT DISTINCT k, SUM(v) AS total
FROM fact PARTITION (p0) TABLESAMPLE (10)
WHERE v BETWEEN 1 AND 9
GROUP BY ROLLUP(k)
HAVING SUM(v) > 0
ORDER BY total DESC
LIMIT 10;

SELECT a FROM left_table LEFT OUTER JOIN right_table ON left_table.k = right_table.k;
SELECT a FROM first_table UNION ALL SELECT a FROM second_table;
SELECT `group`, `window` FROM `table`;
