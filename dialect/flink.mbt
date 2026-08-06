/// Flink dialect placeholder (Phase 9, D-05): `FlinkProfile` has no released
/// values yet — Phase 10 fills flink-2.3.0 / flink-2.1.3 / flink-1.20.5, and
/// until then every Flink profile is rejected by the selection validation
/// (A1/OQ1). Flink grammar lands in Phase 11; every Flink parse in Phase 9 is
/// an explicit FATHOM-PARSE-008 not-implemented rejection, never a fallback to
/// Doris (DIALECT-03).

/// Flink released-profile placeholder. Empty by design in Phase 9; matching
/// against it is impossible until Phase 10 adds values (research OQ1 option
/// (a) — flink is a legal dialect value, all profiles are rejected).
pub enum FlinkProfile {}

/// Flink keyword rows: intentionally empty in Phase 9 (DIALECT-02). The two
/// row arrays are independent module-level data selected only by
/// context.dialect (Pitfall 7); Phase 10 owns populating this table. No Flink
/// word may affect Doris acceptance and vice versa.
let flink_classification_rows : Array[KeywordEntry] = []
