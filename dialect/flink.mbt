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

/// Flink keyword rows: intentionally empty in Phase 10 wave 1 (DIALECT-02).
/// The two row arrays are independent module-level data selected only by
/// context.dialect (Pitfall 7); 10-03 fills this table per release. No Flink
/// word may affect Doris acceptance and vice versa.
let flink_classification_rows : Array[KeywordEntry] = []
