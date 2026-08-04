-- Released Apache Doris 4.x CREATE INDEX grammar examples (INVERTED, NGRAM_BF,
-- and ANN index types with properties and comments).
-- Source: https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/index/CREATE-INDEX/
-- Retrieved: 2026-08-04
-- Code fence: grammar:sql
CREATE INDEX index1 ON table1 (col1) USING INVERTED;
CREATE INDEX index2 ON table1 (col1) USING NGRAM_BF PROPERTIES ("gram_size" = "3", "bf_size" = "1024");
CREATE INDEX IF NOT EXISTS idx ON t (c) COMMENT 'index comment';
CREATE INDEX idx ON db.table1 (col1, col2) USING ANN PROPERTIES ("index_type" = "hnsw", "metric_type" = "l2_distance", "dim" = "128");
