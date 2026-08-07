/// Flink dialect policy: released profile metadata (Phase 10, D-01/D-02) and
/// the Flink keyword rows. `FlinkProfile` is the closed released-profile enum
/// (flink-2.3.0 primary, flink-2.1.3 / flink-1.20.5 regression) mirroring
/// `DorisProfile`; `FlinkProfileMetadata` adds the release-derived
/// `calcite_version` and `parser_config` dimensions (D-02) extracted from the
/// pinned release archives — never hand-written inference or Calcite folklore.
/// The calcite_version/parser_config values are frozen from RESEARCH §7/§8 and
/// re-verified mechanically by scripts/extract_flink_lexical.py against the
/// pinned release POMs (flink-table/pom.xml:81) and PlannerContext.java.
///
/// Flink grammar lands in Phase 11; every Flink parse in Phase 10 is an
/// explicit FATHOM-PARSE-008 not-implemented rejection, never a fallback to
/// Doris (DIALECT-03).

/// Explicit released Flink profile metadata and source-backed lexical leaves.
pub(all) enum FlinkProfile {
  V2_3_0
  V2_1_3
  V1_20_5
} derive(Eq, @debug.Debug)

pub struct FlinkProfileMetadata {
  pub id : String
  pub release_family : String
  pub exact_release : String
  pub calcite_version : String
  pub parser_config : String
  pub feature_introduction : String
}

pub fn FlinkProfile::metadata(self : FlinkProfile) -> FlinkProfileMetadata {
  match self {
    V2_3_0 => {
      id: "flink-2.3.0",
      release_family: "2.x",
      exact_release: "flink-2.3.0",
      calcite_version: "1.36.0",
      parser_config: "Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT",
      feature_introduction: "primary profile",
    }
    V2_1_3 => {
      id: "flink-2.1.3",
      release_family: "2.x",
      exact_release: "flink-2.1.3",
      calcite_version: "1.34.0",
      parser_config: "Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT",
      feature_introduction: "flink-2.1.3 regression profile",
    }
    V1_20_5 => {
      id: "flink-1.20.5",
      release_family: "1.x",
      exact_release: "flink-1.20.5",
      calcite_version: "1.32.0",
      parser_config: "Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT",
      feature_introduction: "flink-1.20.5 regression profile",
    }
  }
}

pub fn FlinkProfile::id(self : FlinkProfile) -> String {
  self.metadata().id
}

/// C_STYLE_ESCAPED_STRING_LITERAL availability (`E'..'`): present in Calcite
/// 1.36.0 (Parser-calcite-1.36.0.jj:8721) and 1.34.0 (:8469), ABSENT in
/// 1.32.0 (flink-1.20.5). The lexer's E-literal profile gate (T-10-08) reads
/// this — never a hand-written Calcite folklore guess.
pub fn FlinkProfile::supports_escape_literal(self : FlinkProfile) -> Bool {
  match self {
    V2_3_0 | V2_1_3 => true
    V1_20_5 => false
  }
}

/// Closed exact-match lookup (D-01, Pitfall 6): only the three pinned release
/// profile ids resolve. `flink-2.3`, `flink-2.3.0-rc1`, and the Doris-shaped
/// `2.1` return None — no prefix/suffix matching, no version comparison, no
/// Doris profile borrowing (T-10-01).
pub fn FlinkProfile::from_id(id : String) -> FlinkProfile? {
  match id {
    "flink-2.3.0" => Some(V2_3_0)
    "flink-2.1.3" => Some(V2_1_3)
    "flink-1.20.5" => Some(V1_20_5)
    _ => None
  }
}

/// Flink keyword rows (10-03): production/conflict words inlined per release
/// with `introduced_profile` = the first Flink release that classifies the
/// word, and `source` = the pinned release grammar path + token line (D-02,
/// Pitfall 3 — never a moving docs URL or Calcite folklore). Scope per
/// RESEARCH Open Question 3 RESOLVED: the words the parser/lexer consume and
/// the D-06 conflict words (142 rows), NOT the full 443/430/412-word release
/// lists (those are committed as the parity/fixtures/flink-lexical/*.txt
/// attachments and validated by scripts/extract_flink_lexical.py).
///
/// The two row arrays are independent module-level data (DIALECT-02, Pitfall
/// 4/7): Doris rows are selected only by context.dialect, Flink rows are
/// additionally filtered by `introduced_profile` <= the selected profile in
/// release order flink-1.20.5 < flink-2.1.3 < flink-2.3.0 (classification.mbt).
/// No Flink word may affect Doris acceptance and vice versa.
let flink_classification_rows : Array[KeywordEntry] = [
  // ---- Baseline flink-1.20.5 Reserved (Calcite 1.32.0 base / Parser.tdd) ----
  { word: b"SELECT", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7800 (SELECT)" },
  { word: b"WITH", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7978 (WITH)" },
  { word: b"FROM", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7520 (FROM)" },
  { word: b"WHERE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7975 (WHERE)" },
  { word: b"GROUP", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7534 (GROUP)" },
  { word: b"HAVING", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7538 (HAVING)" },
  { word: b"ORDER", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7681 (ORDER)" },
  { word: b"LIMIT", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7605 (LIMIT)" },
  { word: b"JOIN", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7577 (JOIN)" },
  { word: b"INNER", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7558 (INNER)" },
  { word: b"LEFT", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7599 (LEFT)" },
  { word: b"RIGHT", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7770 (RIGHT)" },
  { word: b"FULL", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7521 (FULL)" },
  { word: b"CROSS", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7415 (CROSS)" },
  { word: b"NATURAL", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7647 (NATURAL)" },
  { word: b"OUTER", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7686 (OUTER)" },
  { word: b"ON", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7674 (ON)" },
  { word: b"USING", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7957 (USING)" },
  { word: b"UNION", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7942 (UNION)" },
  { word: b"ALL", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7313 (ALL)" },
  { word: b"AS", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7326 (AS)" },
  { word: b"AND", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7318 (AND)" },
  { word: b"OR", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7680 (OR)" },
  { word: b"NOT", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7657 (NOT)" },
  { word: b"IN", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7551 (IN)" },
  { word: b"LIKE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7603 (LIKE)" },
  { word: b"IS", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7572 (IS)" },
  { word: b"NULL", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7660 (NULL)" },
  { word: b"TRUE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7933 (TRUE)" },
  { word: b"FALSE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7503 (FALSE)" },
  { word: b"BETWEEN", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7343 (BETWEEN)" },
  { word: b"EXISTS", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7497 (EXISTS)" },
  { word: b"CASE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7358 (CASE)" },
  { word: b"WHEN", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7973 (WHEN)" },
  { word: b"THEN", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7905 (THEN)" },
  { word: b"ELSE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7479 (ELSE)" },
  { word: b"END", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7482 (END)" },
  { word: b"CAST", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7359 (CAST)" },
  { word: b"DISTINCT", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7467 (DISTINCT)" },
  { word: b"EXCEPT", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7491 (EXCEPT)" },
  { word: b"INTERSECT", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7567 (INTERSECT)" },
  { word: b"OVER", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7688 (OVER)" },
  { word: b"PARTITION", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7701 (PARTITION)" },
  { word: b"ROWS", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7782 (ROWS)" },
  { word: b"RANGE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7735 (RANGE)" },
  { word: b"CURRENT", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7418 (CURRENT)" },
  { word: b"ROW", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7779 (ROW)" },
  { word: b"TABLE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7901 (TABLE)" },
  { word: b"CREATE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7414 (CREATE)" },
  { word: b"INSERT", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7562 (INSERT)" },
  { word: b"UPDATE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7948 (UPDATE)" },
  { word: b"DELETE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7453 (DELETE)" },
  { word: b"SET", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7810 (SET)" },
  { word: b"VALUES", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7962 (VALUES)" },
  { word: b"INTO", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7570 (INTO)" },
  { word: b"OVERWRITE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:203 (OVERWRITE)" },
  { word: b"COMMIT", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7392 (COMMIT)" },
  { word: b"IF", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:190 (IF)" },
  { word: b"BY", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7351 (BY)" },
  { word: b"EVERY", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7490 (EVERY)" },
  { word: b"EXTERNAL", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7501 (EXTERNAL)" },
  { word: b"HASH", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:189 (HASH)" },
  { word: b"MATERIALIZED", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:200 (MATERIALIZED)" },
  { word: b"MERGE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7623 (MERGE)" },
  { word: b"RECURSIVE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7740 (RECURSIVE)" },
  { word: b"REFRESH", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:219 (REFRESH)" },
  { word: b"TABLESAMPLE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7903 (TABLESAMPLE)" },
  { word: b"WINDOW", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7977 (WINDOW)" },
  { word: b"GROUPS", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7537 (GROUPS)" },
  { word: b"OFFSET", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7671 (OFFSET)" },
  { word: b"FETCH", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7504 (FETCH)" },
  { word: b"BUCKETS", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:170 (BUCKETS)" },
  { word: b"COMMENT", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:175 (COMMENT)" },
  { word: b"CUBE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7416 (CUBE)" },
  { word: b"ROLLUP", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7774 (ROLLUP)" },
  { word: b"GROUPING", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7536 (GROUPING)" },
  { word: b"PARTITIONS", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:206 (PARTITIONS)" },
  { word: b"DISTRIBUTED", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:181 (DISTRIBUTED)" },
  { word: b"UNIQUE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7943 (UNIQUE)" },
  { word: b"ESCAPE", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7489 (ESCAPE)" },
  { word: b"COLUMN", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7388 (COLUMN)" },
  { word: b"COLUMNS", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:174 (COLUMNS)" },
  { word: b"FUNCTIONS", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:187 (FUNCTIONS)" },
  { word: b"CALL", classification: Reserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-calcite-1.32.0.jj:7353 (CALL)" },
  // ---- Baseline flink-1.20.5 NonReserved (Parser.tdd nonReservedKeywords) ----
  { word: b"ASC", classification: NonReserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:245 (ASC)" },
  { word: b"DESC", classification: NonReserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:301 (DESC)" },
  { word: b"NULLS", classification: NonReserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:387 (NULLS)" },
  { word: b"FIRST", classification: NonReserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:319 (FIRST)" },
  { word: b"LAST", classification: NonReserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:360 (LAST)" },
  { word: b"KEY", classification: NonReserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:356 (KEY)" },
  { word: b"SETS", classification: NonReserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:456 (SETS)" },
  { word: b"UNBOUNDED", classification: NonReserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:534 (UNBOUNDED)" },
  { word: b"PRECEDING", classification: NonReserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:414 (PRECEDING)" },
  { word: b"FOLLOWING", classification: NonReserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:320 (FOLLOWING)" },
  { word: b"ROW_COUNT", classification: NonReserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:439 (ROW_COUNT)" },
  { word: b"ROLE", classification: NonReserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:434 (ROLE)" },
  { word: b"SCHEMA", classification: NonReserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:442 (SCHEMA)" },
  { word: b"TEMPORARY", classification: NonReserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:518 (TEMPORARY)" },
  { word: b"OPTIONS", classification: NonReserved, introduced_profile: "flink-1.20.5", source: "flink-sql-parser Parser-release-1.20.5.tdd:392 (OPTIONS)" },
  // ---- flink-2.1.3 Reserved delta (RESEARCH §10: 2.1.3 +18 reserved over 1.20.5) ----
  { word: b"DATETIME", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-calcite-1.34.0.jj:7781 (DATETIME)" },
  { word: b"DATE_TRUNC", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-calcite-1.34.0.jj:7780 (DATE_TRUNC)" },
  { word: b"FRIDAY", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-calcite-1.34.0.jj:7868 (FRIDAY)" },
  { word: b"MONDAY", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-calcite-1.34.0.jj:7987 (MONDAY)" },
  { word: b"QUALIFY", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-calcite-1.34.0.jj:8084 (QUALIFY)" },
  { word: b"QUARTERS", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-calcite-1.34.0.jj:8086 (QUARTERS)" },
  { word: b"SATURDAY", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-calcite-1.34.0.jj:8136 (SATURDAY)" },
  { word: b"STRUCTURED", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-release-2.1.3.tdd:223 (STRUCTURED)" },
  { word: b"SUNDAY", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-calcite-1.34.0.jj:8250 (SUNDAY)" },
  { word: b"THURSDAY", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-calcite-1.34.0.jj:8260 (THURSDAY)" },
  { word: b"TIMESTAMP_DIFF", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-calcite-1.34.0.jj:8268 (TIMESTAMP_DIFF)" },
  { word: b"TIMESTAMP_TRUNC", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-calcite-1.34.0.jj:8269 (TIMESTAMP_TRUNC)" },
  { word: b"TIME_DIFF", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-calcite-1.34.0.jj:8263 (TIME_DIFF)" },
  { word: b"TIME_TRUNC", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-calcite-1.34.0.jj:8264 (TIME_TRUNC)" },
  { word: b"TUESDAY", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-calcite-1.34.0.jj:8294 (TUESDAY)" },
  { word: b"VARIANT", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser codegen/templates/Parser.jj:8374 (VARIANT)" },
  { word: b"WEDNESDAY", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-calcite-1.34.0.jj:8332 (WEDNESDAY)" },
  { word: b"WEEKS", classification: Reserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-calcite-1.34.0.jj:8334 (WEEKS)" },
  // ---- flink-2.1.3 NonReserved delta ----
  { word: b"DATETIME_DIFF", classification: NonReserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-release-2.1.3.tdd:295 (DATETIME_DIFF)" },
  { word: b"DATE_DIFF", classification: NonReserved, introduced_profile: "flink-2.1.3", source: "flink-sql-parser Parser-release-2.1.3.tdd:294 (DATE_DIFF)" },
  // ---- flink-2.3.0 Reserved delta (RESEARCH §10: 2.3.0 +13 reserved over 2.1.3) ----
  { word: b"BITMAP", classification: Reserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-release-2.3.0.tdd:202 (BITMAP)" },
  { word: b"CONFLICT", classification: Reserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-release-2.3.0.tdd:211 (CONFLICT)" },
  { word: b"CONNECTIONS", classification: Reserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-release-2.3.0.tdd:212 (CONNECTIONS)" },
  { word: b"CONTAINS_SUBSTR", classification: Reserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-calcite-1.36.0.jj:7993 (CONTAINS_SUBSTR)" },
  { word: b"DATETIME_TRUNC", classification: Reserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-calcite-1.36.0.jj:8029 (DATETIME_TRUNC)" },
  { word: b"DEDUPLICATE", classification: Reserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-release-2.3.0.tdd:215 (DEDUPLICATE)" },
  { word: b"DO", classification: Reserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-release-2.3.0.tdd:218 (DO)" },
  { word: b"JSON_SCOPE", classification: Reserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-calcite-1.36.0.jj:8180 (JSON_SCOPE)" },
  { word: b"NOTHING", classification: Reserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-release-2.3.0.tdd:242 (NOTHING)" },
  { word: b"ORDINAL", classification: Reserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-calcite-1.36.0.jj:8280 (ORDINAL)" },
  { word: b"SAFE_CAST", classification: Reserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-calcite-1.36.0.jj:8384 (SAFE_CAST)" },
  { word: b"SAFE_OFFSET", classification: Reserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-calcite-1.36.0.jj:8385 (SAFE_OFFSET)" },
  { word: b"SAFE_ORDINAL", classification: Reserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-calcite-1.36.0.jj:8386 (SAFE_ORDINAL)" },
  // ---- flink-2.3.0 NonReserved delta (RESEARCH §10: 2.3.0 +10 nonreserved over 2.1.3) ----
  { word: b"ARTIFACT", classification: NonReserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-release-2.3.0.tdd:201 (ARTIFACT)" },
  { word: b"DAYOFWEEK", classification: NonReserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-release-2.3.0.tdd:337 (DAYOFWEEK)" },
  { word: b"DAYOFYEAR", classification: NonReserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-release-2.3.0.tdd:338 (DAYOFYEAR)" },
  { word: b"FROM_BEGINNING", classification: NonReserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-release-2.3.0.tdd:223 (FROM_BEGINNING)" },
  { word: b"FROM_NOW", classification: NonReserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-release-2.3.0.tdd:224 (FROM_NOW)" },
  { word: b"FROM_TIMESTAMP", classification: NonReserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-release-2.3.0.tdd:225 (FROM_TIMESTAMP)" },
  { word: b"RESUME_OR_FROM_BEGINNING", classification: NonReserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-release-2.3.0.tdd:254 (RESUME_OR_FROM_BEGINNING)" },
  { word: b"RESUME_OR_FROM_NOW", classification: NonReserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-release-2.3.0.tdd:255 (RESUME_OR_FROM_NOW)" },
  { word: b"RESUME_OR_FROM_TIMESTAMP", classification: NonReserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-release-2.3.0.tdd:256 (RESUME_OR_FROM_TIMESTAMP)" },
  { word: b"START_MODE", classification: NonReserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-release-2.3.0.tdd:258 (START_MODE)" },
]

/// Release-grammar provenance audit (10-03 Task 3, T-10-14): every inlined
/// flink row's source references the pinned release grammar (path + token
/// line), never a moving docs URL or Calcite folklore (D-02, Pitfall 3).
test "flink_classification_rows_source_references_release_grammar" {
  let rows = flink_classification_rows
  assert_true(rows.length() > 0)
  for row in rows {
    assert_true(
      row.source.contains("flink-sql-parser") &&
      (row.source.contains("Parser-release-") ||
        row.source.contains("Parser-calcite-") ||
        row.source.contains("codegen/templates/Parser.jj"))
    )
    assert_true(!row.source.contains("http"))
  }
  // VARIANT/QUALIFY are 2.1.3-delta reserved words with the W-1 introduced
  // profile and the template/token source.
  match classification_of(flink_2_3_0_context(), b"VARIANT") {
    Some(entry) => assert_eq(entry.source, "flink-sql-parser codegen/templates/Parser.jj:8374 (VARIANT)")
    None => assert_true(false)
  }
}

/// Per-profile non-empty row sets (probe FLINK-01 empty): each pinned release
/// profile has a non-empty row set after this plan, so an empty table is not
/// possible.
test "flink_classification_rows_per_profile_are_non_empty" {
  assert_true(classification_entries(flink_1_20_5_context()).length() > 0)
  assert_true(classification_entries(flink_2_1_3_context()).length() > 0)
  assert_true(classification_entries(flink_2_3_0_context()).length() > 0)
  // Baseline rows (introduced at 1.20.5) are visible under every profile;
  // a 2.1.3 row is visible under 2.1.3+ but absent under 1.20.5; a 2.3.0 row
  // only under 2.3.0.
  assert_true(classification_entries(flink_2_1_3_context()).length() >
    classification_entries(flink_1_20_5_context()).length())
  assert_true(classification_entries(flink_2_3_0_context()).length() >
    classification_entries(flink_2_1_3_context()).length())
}
