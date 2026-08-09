/// Flink statement-family productions (Phase 11, D-04/D-06). Same package as
/// parser.mbt (parser/moon.pkg has no file list, so the package auto-compiles
/// every .mbt file), which means every priv parser primitive is accessible:
/// Cursor/RecoveryState/consume_word/expect_word/advance/raw_at/make_span/
/// finish_statement/recover_to_clause_boundary/significant_indices/
/// parse_cte_prefix/parse_select_core/parse_from/parse_table_ref/depth_allowed.
///
/// Doris table_ref/type/DDL bodies are NEVER reused (Pitfall 1/7): this file is
/// the Flink-safe SELECT path that the wave-1 tracer lands. The dialect gates
/// live inside the shared functions (parse_select_core / parse_table_ref /
/// parse_cte_prefix) so the Doris arm stays byte-identical while the Flink arm
/// rejects Doris-only constructs with FATHOM-PARSE-009 (D-04).

/// FLINK-02 core query surface: SELECT/CTE/JOIN/aggregation/expressions plus
/// the Calcite set-operation mechanism (UNION/INTERSECT/EXCEPT + ALL/DISTINCT,
/// CompoundQuery via QueryOrExpr, Parser-calcite-1.36.0.jj:3395). The shared
/// parse_query only loops on UNION; INTERSECT and EXCEPT are Calcite base
/// set-ops the shared skeleton does not cover, so the Flink query entry adds
/// them here (D-07 vertical slice FLINK-02 first).
fn parse_flink_query(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = true
  if raw_at(cursor) is Some(raw) && bytes_equal_ci(raw, b"WITH") {
    valid = parse_cte_prefix(cursor, state, source, statement_id) && valid
  }
  valid = parse_flink_select_core(cursor, state, source, statement_id) && valid
  let mut set_done = false
  while !set_done {
    if consume_word(cursor, b"UNION") || consume_word(cursor, b"INTERSECT") || consume_word(cursor, b"EXCEPT") {
      ignore(consume_word(cursor, b"ALL"))
      ignore(consume_word(cursor, b"DISTINCT"))
      valid = parse_flink_select_core(cursor, state, source, statement_id) && valid
    } else {
      set_done = true
    }
  }
  valid
}

/// Flink-safe SELECT core: the shared parse_select_core. The Doris-only
/// branches (EXCEPT projection modifier, QUALIFY, INTO OUTFILE) are gated to
/// the Doris dialect inside parse_select_core, and the Doris-only table options
/// (PARTITION/TABLET/SAMPLE/TABLESAMPLE/REPEATABLE) are gated inside
/// parse_table_ref — under Flink each is rejected with FATHOM-PARSE-009. This
/// thin wrapper is the Flink entry so parse_flink_query can layer the
/// INTERSECT/EXCEPT set-ops on top without touching the shared query loop.
fn parse_flink_select_core(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  parse_select_core(cursor, cursor.stream.context, state, source, statement_id)
}
