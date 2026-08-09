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

// ---------------------------------------------------------------------------
// FLINK-02 DML: INSERT/UPSERT (RichSqlInsert, parserImpls.ftl:2306-2379)
// ---------------------------------------------------------------------------

/// `(INSERT|UPSERT) (INTO|OVERWRITE) table [PARTITION (k=v,...)] [(cols)]
///   (query | VALUES rows) [ON CONFLICT DO (ERROR|NOTHING|DEDUPLICATE)]`
///
/// Reuses the shared parse_insert skeleton (:1502-1559) shape but follows the
/// Flink RichSqlInsert production: UPSERT, OVERWRITE, the key=value PARTITION
/// spec, and the ON CONFLICT DO tail are Flink-only (D-04 — each is a 009 gate
/// under Doris via the fixtures, never parsed there). Doris-only INSERT forms
/// (WITH LABEL, DISTRIBUTED ... BUCKETS) are construct-level 009 gates here.
fn parse_flink_insert(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = true
  if !(consume_word(cursor, b"INSERT") || consume_word(cursor, b"UPSERT")) {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected INSERT or UPSERT statement", "keyword", make_span(source, at, at), statement_id)
    valid = false
  }
  if consume_word(cursor, b"INTO") {
    ()
  } else if consume_word(cursor, b"OVERWRITE") {
    ()
  } else {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected INTO or OVERWRITE after INSERT", "keyword", make_span(source, at, at), statement_id)
    valid = false
  }
  valid = parse_qualified_name(cursor, state, source, statement_id, "table name") && valid
  if consume_word(cursor, b"PARTITION") {
    valid = parse_flink_partition_spec(cursor, state, source, statement_id) && valid
  }
  if raw_at(cursor) is Some(b"(") {
    let columns_ok = parse_identifier_option(cursor, state, source, statement_id, "column")
    if !columns_ok {
      // D-03: an unclosed column list recovers to the next insert clause
      // (PARTITION/ON CONFLICT/SELECT/VALUES/`)`), never swallowing the
      // statement (T-11-12).
      recover_to_clause_boundary(cursor, state, source, statement_id, is_flink_insert_boundary)
    }
    valid = columns_ok && valid
  }
  // Doris-only INSERT forms under Flink → FATHOM-PARSE-009 (D-04, §9 matrix):
  // WITH LABEL and the Doris DISTRIBUTED ... BUCKETS distribution form.
  if raw_at(cursor) is Some(raw) && (bytes_equal_ci(raw, b"WITH") || bytes_equal_ci(raw, b"DISTRIBUTED")) {
    let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_dialect_gate_diagnostic(state, span, statement_id)
    valid = false
    consume_gated_remainder(cursor, state, source, statement_id)
  }
  if consume_word(cursor, b"VALUES") {
    valid = parse_values_rows(cursor, state, source, statement_id) && valid
  } else if is_query_start(cursor) {
    valid = parse_flink_query(cursor, state, source, statement_id) && valid
  } else if raw_at(cursor) is Some(b";") || raw_at(cursor) is None {
    // Incomplete statement: bounded recovery; finish_statement adds the
    // Missing node (CST-01, D-03).
    ()
  } else {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected VALUES or query after INSERT", "insert-source", make_span(source, at, at), statement_id)
    valid = false
  }
  if consume_word(cursor, b"ON") {
    valid = expect_word(cursor, b"CONFLICT", state, source, statement_id, "expected CONFLICT after ON") && valid
    valid = expect_word(cursor, b"DO", state, source, statement_id, "expected DO after ON CONFLICT") && valid
    if consume_word(cursor, b"ERROR") || consume_word(cursor, b"NOTHING") || consume_word(cursor, b"DEDUPLICATE") {
      ()
    } else {
      let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected ERROR, NOTHING, or DEDUPLICATE after ON CONFLICT DO", "insert-on-conflict", make_span(source, at, at), statement_id)
      valid = false
    }
  }
  valid
}

/// `PARTITION ( col = value [ , ... ] )` — Flink PartitionSpecCommaList
/// (parserImpls.ftl:2306-2379). Key/value pairs, not the Doris identifier list.
fn parse_flink_partition_spec(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = expect_symbol(cursor, b"(", state, source, statement_id, "expected opening PARTITION parenthesis")
  let mut any = false
  let mut done = false
  while !done {
    if raw_at(cursor) is Some(b")") {
      done = true
    } else {
      any = true
      if is_identifier_candidate(cursor) {
        advance(cursor)
      } else {
        let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        add_diagnostic(state, "FATHOM-PARSE-002", "expected partition column", "identifier", span, statement_id)
        valid = false
        if raw_at(cursor) is Some(b")") { done = true } else { advance(cursor) }
      }
      valid = expect_symbol(cursor, b"=", state, source, statement_id, "expected = in partition spec") && valid
      let before = cursor.position
      let value_ok = parse_expression(cursor, 1, 1, state, source, statement_id)
      valid = value_ok && valid
      if cursor.position == before { recover_expression(cursor, state, source, statement_id); valid = false }
      if consume_symbol(cursor, b",") {
        if raw_at(cursor) is Some(b")") {
          let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
          add_diagnostic(state, "FATHOM-PARSE-002", "expected partition value after comma", "partition", span, statement_id)
          valid = false
          done = true
        }
      } else {
        done = true
      }
    }
  }
  if !any {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected partition specification", "partition", make_span(source, at, at), statement_id)
    valid = false
  }
  valid = expect_symbol(cursor, b")", state, source, statement_id, "expected closing PARTITION parenthesis") && valid
  valid
}

// ---------------------------------------------------------------------------
// FLINK-02 DML: UPDATE / DELETE (Calcite SqlUpdate :1794-1832, SqlDelete
// :1768-1789) — the shared skeletons' Flink-safe subset, with Doris-only
// clauses rejected by the FATHOM-PARSE-009 dialect gate (D-04, §9 matrix).
// ---------------------------------------------------------------------------

fn is_flink_update_boundary(raw : Bytes) -> Bool {
  bytes_equal_ci(raw, b"SET") || bytes_equal_ci(raw, b"WHERE") ||
    bytes_equal_ci(raw, b"COMMENT") || bytes_equal_ci(raw, b"WITH") ||
    bytes_equal_ci(raw, b"FROM") || bytes_equal_ci(raw, b"ORDER") ||
    bytes_equal_ci(raw, b"LIMIT")
}

/// Consumes the remainder of a dialect-gated (FATHOM-PARSE-009) construct
/// losslessly and boundedly (shared recovery budget, D-03) so the gate is the
/// primary diagnostic and no spurious trailing-token 001 is emitted.
fn consume_gated_remainder(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Unit {
  let mut done = false
  while !done {
    match raw_at(cursor) {
      None => done = true
      Some(raw) if raw == b";" => done = true
      Some(_) => {
        let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        if consume_recovery_step(state, span, statement_id) { advance(cursor) } else { done = true }
      }
    }
  }
}

/// Calcite SqlUpdate (:1794-1832): `UPDATE tableRef [alias] SET assignment_list
/// [WHERE expr]`. The shared parse_update's Doris-only clauses (COMMENT, WITH
/// LABEL) are construct-level 009 gates here; FROM/ORDER/LIMIT are left as
/// trailing (the shared skeleton's Doris arms are never entered).
fn parse_flink_update(
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
  valid = expect_word(cursor, b"UPDATE", state, source, statement_id, "expected UPDATE statement") && valid
  valid = parse_qualified_name(cursor, state, source, statement_id, "target table") && valid
  // Optional [AS] alias; family clause keywords are never consumed as an alias.
  if consume_word(cursor, b"AS") {
    if is_identifier_candidate(cursor) {
      advance(cursor)
    } else {
      let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected table alias after AS", "identifier", make_span(source, at, at), statement_id)
      valid = false
    }
  } else if is_identifier_candidate(cursor) {
    match raw_at(cursor) {
      Some(raw) if is_flink_update_boundary(raw) => ()
      _ => advance(cursor)
    }
  }
  if consume_word(cursor, b"SET") {
    let set_ok = parse_assignment_list(cursor, state, source, statement_id)
    if !set_ok { recover_to_clause_boundary(cursor, state, source, statement_id, is_flink_update_boundary) }
    valid = set_ok && valid
  } else {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected SET clause in UPDATE", "clause", make_span(source, at, at), statement_id)
    valid = false
    recover_to_clause_boundary(cursor, state, source, statement_id, is_flink_update_boundary)
  }
  if consume_word(cursor, b"WHERE") {
    let where_ok = parse_expression(cursor, 1, 1, state, source, statement_id)
    if !where_ok { recover_to_clause_boundary(cursor, state, source, statement_id, is_flink_update_boundary) }
    valid = where_ok && valid
  }
  // Doris-only UPDATE clauses (COMMENT / WITH LABEL) under Flink → 009.
  if raw_at(cursor) is Some(raw) && (bytes_equal_ci(raw, b"COMMENT") || bytes_equal_ci(raw, b"WITH")) {
    let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_dialect_gate_diagnostic(state, span, statement_id)
    valid = false
    consume_gated_remainder(cursor, state, source, statement_id)
  }
  valid
}

fn is_flink_delete_boundary(raw : Bytes) -> Bool {
  bytes_equal_ci(raw, b"WHERE") || bytes_equal_ci(raw, b"PARTITION") ||
    bytes_equal_ci(raw, b"PARTITIONS") || bytes_equal_ci(raw, b"USING") ||
    bytes_equal_ci(raw, b"ORDER") || bytes_equal_ci(raw, b"LIMIT")
}

/// Calcite SqlDelete (:1768-1789): `DELETE FROM tableRef [AS alias]
/// [WHERE expr]`. The shared parse_delete's Doris-only clauses (PARTITION,
/// USING) are construct-level 009 gates here.
fn parse_flink_delete(
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
  valid = expect_word(cursor, b"DELETE", state, source, statement_id, "expected DELETE statement") && valid
  valid = expect_word(cursor, b"FROM", state, source, statement_id, "expected FROM after DELETE") && valid
  valid = parse_qualified_name(cursor, state, source, statement_id, "table name") && valid
  if consume_word(cursor, b"AS") {
    if is_identifier_candidate(cursor) {
      advance(cursor)
    } else {
      let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected table alias after AS", "identifier", make_span(source, at, at), statement_id)
      valid = false
    }
  } else if is_identifier_candidate(cursor) {
    match raw_at(cursor) {
      Some(raw) if is_flink_delete_boundary(raw) => ()
      _ => advance(cursor)
    }
  }
  // Doris-only DELETE clauses (PARTITION/PARTITIONS/USING) under Flink → 009.
  if raw_at(cursor) is Some(raw) && (bytes_equal_ci(raw, b"PARTITION") || bytes_equal_ci(raw, b"PARTITIONS") || bytes_equal_ci(raw, b"USING")) {
    let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_dialect_gate_diagnostic(state, span, statement_id)
    valid = false
    consume_gated_remainder(cursor, state, source, statement_id)
  }
  if consume_word(cursor, b"WHERE") {
    let where_ok = parse_expression(cursor, 1, 1, state, source, statement_id)
    if !where_ok { recover_to_clause_boundary(cursor, state, source, statement_id, is_flink_delete_boundary) }
    valid = where_ok && valid
  }
  valid
}

// ---------------------------------------------------------------------------
// FLINK-02 auxiliary statements (SqlRichExplain :3079-3117, SqlShow*,
// SqlRichDescribe* :867-880, SqlAnalyzeTable :3413-3443, USE/SET/RESET)
// ---------------------------------------------------------------------------

/// `EXPLAIN [PLAN FOR] query` (SqlRichExplain, parserImpls.ftl:3079-3117).
fn parse_flink_explain(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"EXPLAIN", state, source, statement_id, "expected EXPLAIN statement")
  if consume_word(cursor, b"PLAN") {
    valid = expect_word(cursor, b"FOR", state, source, statement_id, "expected FOR after EXPLAIN PLAN") && valid
  }
  if is_query_start(cursor) {
    valid = parse_flink_query(cursor, state, source, statement_id) && valid
  } else {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected query after EXPLAIN", "query", make_span(source, at, at), statement_id)
    valid = false
  }
  valid
}

/// String-literal pattern after LIKE/ILIKE (SqlShow* family).
fn parse_flink_like_pattern(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  match token_at(cursor) {
    Some(token) if token.kind is @token.TokenKind::StringLiteral => {
      advance(cursor)
      true
    }
    _ => {
      let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected string literal pattern after LIKE", "string", make_span(source, at, at), statement_id)
      false
    }
  }
}

/// `SHOW CREATE (TABLE|VIEW|DATABASE|FUNCTION|CATALOG) name`.
fn parse_flink_show_create_target(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  let type_ok = consume_word(cursor, b"TABLE") || consume_word(cursor, b"VIEW") ||
    consume_word(cursor, b"DATABASE") || consume_word(cursor, b"FUNCTION") ||
    consume_word(cursor, b"CATALOG")
  if !type_ok {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected TABLE/VIEW/DATABASE/FUNCTION/CATALOG after SHOW CREATE", "show-target", make_span(source, at, at), statement_id)
    valid = false
  }
  valid = parse_qualified_name(cursor, state, source, statement_id, "SHOW CREATE object name") && valid
  valid
}

/// `SHOW (CATALOGS|DATABASES|TABLES|VIEWS|FUNCTIONS|COLUMNS) [FROM|IN name]
///   [LIKE|ILIKE|NOT LIKE pattern]` plus SHOW CREATE and SHOW CURRENT forms
/// (SqlShow* family, statementParserMethods Parser.tdd:651-727). A trailing
/// token (e.g. `SHOW TABLES db1` missing FROM/IN) is a localized error at the
/// offending token.
fn parse_flink_show(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"SHOW", state, source, statement_id, "expected SHOW statement")
  if consume_word(cursor, b"CREATE") {
    valid = parse_flink_show_create_target(cursor, state, source, statement_id) && valid
    return valid
  }
  if consume_word(cursor, b"CURRENT") {
    if consume_word(cursor, b"CATALOG") || consume_word(cursor, b"DATABASE") {
      ()
    } else {
      let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected CATALOG or DATABASE after SHOW CURRENT", "show-target", make_span(source, at, at), statement_id)
      valid = false
    }
    return valid
  }
  let type_ok = consume_word(cursor, b"CATALOGS") || consume_word(cursor, b"DATABASES") ||
    consume_word(cursor, b"TABLES") || consume_word(cursor, b"VIEWS") ||
    consume_word(cursor, b"FUNCTIONS") || consume_word(cursor, b"COLUMNS")
  if !type_ok {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected SHOW target (CATALOGS/DATABASES/TABLES/VIEWS/FUNCTIONS/COLUMNS/CREATE/CURRENT)", "show-target", make_span(source, at, at), statement_id)
    valid = false
  }
  if consume_word(cursor, b"FROM") || consume_word(cursor, b"IN") {
    valid = parse_qualified_name(cursor, state, source, statement_id, "SHOW scope name") && valid
  }
  let mut pattern_done = false
  while !pattern_done {
    if consume_word(cursor, b"NOT") {
      valid = expect_word(cursor, b"LIKE", state, source, statement_id, "expected LIKE after NOT") && valid
      valid = parse_flink_like_pattern(cursor, state, source, statement_id) && valid
    } else if consume_word(cursor, b"LIKE") || consume_word(cursor, b"ILIKE") {
      valid = parse_flink_like_pattern(cursor, state, source, statement_id) && valid
    } else {
      pattern_done = true
    }
  }
  if raw_at(cursor) is Some(raw) && !(raw == b";") {
    let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "FATHOM-PARSE-002", "unexpected token after SHOW statement", "show", span, statement_id)
    valid = false
    // Consume the offending token(s) losslessly so no spurious trailing-001
    // diagnostic is emitted (the localized error at the offending token is
    // the primary diagnostic).
    consume_gated_remainder(cursor, state, source, statement_id)
  }
  valid
}

/// `DESCRIBE|DESC [EXTENDED] [TABLE|FUNCTION|DATABASE|CATALOG] name`
/// (SqlRichDescribeTable, parserImpls.ftl:867-880). A bare `DESCRIBE t`
/// (no kind word) is the table-name form.
fn parse_flink_describe(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = true
  if !(consume_word(cursor, b"DESCRIBE") || consume_word(cursor, b"DESC")) {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected DESCRIBE statement", "keyword", make_span(source, at, at), statement_id)
    valid = false
  }
  ignore(consume_word(cursor, b"EXTENDED"))
  ignore(
    consume_word(cursor, b"TABLE") || consume_word(cursor, b"FUNCTION") ||
      consume_word(cursor, b"DATABASE") || consume_word(cursor, b"CATALOG"),
  )
  valid = parse_qualified_name(cursor, state, source, statement_id, "describe target") && valid
  valid
}

/// `ANALYZE TABLE t [PARTITION(...)]` (SqlAnalyzeTable, parserImpls.ftl:
/// 3413-3443). Doris-only options (BUCKETS) are a construct-level 009 gate.
fn parse_flink_analyze(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"ANALYZE", state, source, statement_id, "expected ANALYZE statement")
  valid = expect_word(cursor, b"TABLE", state, source, statement_id, "expected TABLE after ANALYZE") && valid
  valid = parse_qualified_name(cursor, state, source, statement_id, "table name") && valid
  if consume_word(cursor, b"PARTITION") {
    valid = parse_flink_partition_spec(cursor, state, source, statement_id) && valid
  }
  if raw_at(cursor) is Some(raw) && bytes_equal_ci(raw, b"BUCKETS") {
    let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_dialect_gate_diagnostic(state, span, statement_id)
    valid = false
    consume_gated_remainder(cursor, state, source, statement_id)
  }
  valid
}

/// `USE [CATALOG] name` (SqlUseCatalog/SqlUseDatabase).
fn parse_flink_use(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"USE", state, source, statement_id, "expected USE statement")
  ignore(consume_word(cursor, b"CATALOG"))
  valid = parse_qualified_name(cursor, state, source, statement_id, "USE target") && valid
  valid
}

/// `SET 'k' = 'v'` / `SET k = v` / `RESET 'k'` / bare `RESET`
/// (SqlSetOption/SqlSet/SqlReset, parserImpls.ftl:3294-3333).
fn parse_flink_set_reset(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = true
  if consume_word(cursor, b"SET") {
    valid = parse_flink_option_value(cursor, state, source, statement_id) && valid
    valid = expect_symbol(cursor, b"=", state, source, statement_id, "expected = in SET option") && valid
    valid = parse_flink_option_value(cursor, state, source, statement_id) && valid
  } else if consume_word(cursor, b"RESET") {
    if raw_at(cursor) is Some(_) && !(raw_at(cursor) is Some(b";")) {
      valid = parse_flink_option_value(cursor, state, source, statement_id) && valid
    }
  } else {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected SET or RESET statement", "keyword", make_span(source, at, at), statement_id)
    valid = false
  }
  valid
}

/// A SET/RESET key or value: string literal, identifier, or number.
fn parse_flink_option_value(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  match token_at(cursor) {
    Some(token) if token.kind is @token.TokenKind::StringLiteral || token.kind is @token.TokenKind::Number => {
      advance(cursor)
      true
    }
    Some(_) if is_identifier_candidate(cursor) => {
      advance(cursor)
      true
    }
    _ => {
      let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected SET/RESET option key or value", "option", make_span(source, at, at), statement_id)
      false
    }
  }
}

// ---------------------------------------------------------------------------
// Flink data types (dataTypeParserMethods, Parser.tdd:759-765) — a SEPARATE
// path from the shared parse_column_type, so the Doris type set stays
// byte-identical (Pitfall 7). Handles basic types with precision/scale
// (TIMESTAMP_LTZ(3), DECIMAL(p,s)), generic types (ARRAY<T>, MAP<K,V>,
// MULTISET<T>, ROW<f1 T1,...>), and the optional [NOT] NULL suffix.
// ---------------------------------------------------------------------------

fn parse_flink_data_type(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = true
  if is_identifier_candidate(cursor) {
    advance(cursor)
  } else {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected Flink data type", "type", make_span(source, at, at), statement_id)
    return false
  }
  // Optional precision/scale: ( p [, s] ).
  if consume_symbol(cursor, b"(") {
    if !consume_symbol(cursor, b")") {
      valid = parse_expression_list(cursor, state, source, statement_id, true) && valid
      valid = expect_symbol(cursor, b")", state, source, statement_id, "expected closing type precision parenthesis") && valid
    }
  }
  // Optional generic args: < ... > (nested types; ROW field names are
  // consumed as a trailing identifier per element — syntax-level only).
  if raw_at(cursor) is Some(b"<") {
    advance(cursor)
    if !consume_symbol(cursor, b">") {
      let mut element_done = false
      while !element_done {
        valid = parse_flink_data_type(cursor, state, source, statement_id) && valid
        if is_identifier_candidate(cursor) && !(raw_at(cursor) is Some(b",")) && !(raw_at(cursor) is Some(b">")) {
          advance(cursor)
        }
        if consume_symbol(cursor, b",") {
          if raw_at(cursor) is Some(b">") || raw_at(cursor) is None {
            let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
            add_diagnostic(state, "FATHOM-PARSE-002", "expected type after comma in type generic", "type-parameter", make_span(source, at, at), statement_id)
            valid = false
            element_done = true
          }
        } else {
          element_done = true
        }
      }
      valid = expect_symbol(cursor, b">", state, source, statement_id, "expected closing type generic bracket") && valid
    }
  }
  // Optional nullability suffix: [NOT] NULL (ExtendedDataType,
  // parserImpls.ftl:1395-1420).
  if consume_word(cursor, b"NOT") {
    valid = expect_word(cursor, b"NULL", state, source, statement_id, "expected NULL after NOT in data type") && valid
  } else {
    ignore(consume_word(cursor, b"NULL"))
  }
  valid
}

// ---------------------------------------------------------------------------
// FLINK-03 DDL (SqlCreateExtended/SqlDropExtended parserImpls.ftl:2850-2920,
// SqlAlter* statementParserMethods Parser.tdd:651-727). Syntax-level only:
// parsing CREATE CATALOG ... WITH (...) or CREATE FUNCTION ... AS 'class' is
// pure grammar — no connector validation, catalog registration, or function
// resolution (FLINK-03 prohibitions).
// ---------------------------------------------------------------------------

/// A single-quoted string literal (Flink DDL class strings, COMMENT, LIKE
/// patterns, METADATA aliases): consumes a StringLiteral token or reports a
/// localized FATHOM-PARSE-002 at the offending token.
fn parse_flink_string_literal(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  what : String,
) -> Bool {
  match token_at(cursor) {
    Some(token) if token.kind is @token.TokenKind::StringLiteral => {
      advance(cursor)
      true
    }
    _ => {
      let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected string literal for " + what, "string", at, statement_id)
      false
    }
  }
}

/// `WITH ( 'key' = 'value', ... )` — Flink connector options / catalog and
/// database properties (Properties(), parserImpls.ftl:1506-1556). The `WITH`
/// keyword is consumed here and the parenthesized pair list delegates to the
/// shared parse_properties_clause (identical pair shape; the PropertyList CST
/// is carried by the raw token children of the statement node).
fn parse_flink_with_properties(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  what : String,
) -> Bool {
  let mut valid = expect_word(cursor, b"WITH", state, source, statement_id, "expected WITH before " + what + " properties")
  valid = parse_properties_clause(cursor, state, source, statement_id, what + " WITH options") && valid
  valid
}

/// `( 'key', ... )` — the ALTER ... RESET key list (string literals or
/// identifiers, SqlAlterCatalog/SqlAlterDatabase RESET branch).
fn parse_flink_reset_key_list(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = expect_symbol(cursor, b"(", state, source, statement_id, "expected ( after RESET")
  let mut any = false
  let mut done = false
  while !done {
    if raw_at(cursor) is Some(b")") {
      done = true
    } else {
      let is_key = match token_at(cursor) {
        Some(token) => token.kind is @token.TokenKind::StringLiteral || is_identifier_candidate(cursor)
        None => false
      }
      if !is_key {
        let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        add_diagnostic(state, "FATHOM-PARSE-002", "expected reset key", "key", at, statement_id)
        valid = false
        done = true
      } else {
        any = true
        advance(cursor)
        if consume_symbol(cursor, b",") {
          if raw_at(cursor) is Some(b")") { done = true }
        } else {
          done = true
        }
      }
    }
  }
  if !any {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected at least one reset key", "key", make_span(source, at, at), statement_id)
    valid = false
  }
  valid = expect_symbol(cursor, b")", state, source, statement_id, "expected closing RESET parenthesis") && valid
  valid
}

/// CREATE dispatch: second-word routing after the optional [TEMPORARY
/// [SYSTEM]] prefix (SqlCreateExtended, parserImpls.ftl:2850-2920). Each
/// family (CATALOG/DATABASE/TABLE/VIEW/FUNCTION) routes to its own
/// production; the statement kind is resolved by flink_create_form_kind in
/// parser.mbt (the CREATE arm of parse_flink_segment).
fn parse_flink_create(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"CREATE", state, source, statement_id, "expected CREATE statement")
  // [TEMPORARY [SYSTEM]] prefix before FUNCTION/TABLE.
  if consume_word(cursor, b"TEMPORARY") {
    ignore(consume_word(cursor, b"SYSTEM"))
  }
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, b"CATALOG") => valid = parse_flink_create_catalog(cursor, state, source, statement_id) && valid
    Some(raw) if bytes_equal_ci(raw, b"DATABASE") => valid = parse_flink_create_database(cursor, state, source, statement_id) && valid
    Some(raw) if bytes_equal_ci(raw, b"TABLE") => valid = parse_flink_create_table(cursor, state, source, statement_id) && valid
    Some(raw) if bytes_equal_ci(raw, b"VIEW") => valid = parse_flink_create_view(cursor, state, source, statement_id) && valid
    Some(raw) if bytes_equal_ci(raw, b"FUNCTION") => valid = parse_flink_create_function(cursor, state, source, statement_id) && valid
    _ => {
      let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected CATALOG, DATABASE, TABLE, VIEW, or FUNCTION after CREATE", "create-form", at, statement_id)
      valid = false
    }
  }
  valid
}

/// ALTER dispatch (SqlAlterCatalog/SqlAlterDatabase/SqlAlterTable/
/// SqlAlterView/SqlAlterFunction, statementParserMethods Parser.tdd:651-727).
/// Every family resolves to the coarse AlterTable statement kind (D-02).
fn parse_flink_alter(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"ALTER", state, source, statement_id, "expected ALTER statement")
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, b"CATALOG") => valid = parse_flink_alter_catalog(cursor, state, source, statement_id) && valid
    Some(raw) if bytes_equal_ci(raw, b"DATABASE") => valid = parse_flink_alter_database(cursor, state, source, statement_id) && valid
    Some(raw) if bytes_equal_ci(raw, b"TABLE") => valid = parse_flink_alter_table(cursor, state, source, statement_id) && valid
    Some(raw) if bytes_equal_ci(raw, b"VIEW") => valid = parse_flink_alter_view(cursor, state, source, statement_id) && valid
    Some(raw) if bytes_equal_ci(raw, b"FUNCTION") => valid = parse_flink_alter_function(cursor, state, source, statement_id) && valid
    _ => {
      let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected CATALOG, DATABASE, TABLE, VIEW, or FUNCTION after ALTER", "alter-form", at, statement_id)
      valid = false
    }
  }
  valid
}

/// DROP dispatch (SqlDropExtended, parserImpls.ftl:2850-2920). The
/// statement kind is resolved by flink_drop_form_kind in parser.mbt.
fn parse_flink_drop(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"DROP", state, source, statement_id, "expected DROP statement")
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, b"CATALOG") => valid = parse_flink_drop_catalog(cursor, state, source, statement_id) && valid
    Some(raw) if bytes_equal_ci(raw, b"DATABASE") => valid = parse_flink_drop_database(cursor, state, source, statement_id) && valid
    Some(raw) if bytes_equal_ci(raw, b"TABLE") => valid = parse_flink_drop_table(cursor, state, source, statement_id) && valid
    Some(raw) if bytes_equal_ci(raw, b"VIEW") => valid = parse_flink_drop_view(cursor, state, source, statement_id) && valid
    Some(raw) if bytes_equal_ci(raw, b"FUNCTION") => valid = parse_flink_drop_function(cursor, state, source, statement_id) && valid
    _ => {
      let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected CATALOG, DATABASE, TABLE, VIEW, or FUNCTION after DROP", "drop-form", at, statement_id)
      valid = false
    }
  }
  valid
}

/// `CREATE CATALOG [IF NOT EXISTS] name [COMMENT '...'] [WITH Properties()]`
/// (SqlCreateCatalog, parserImpls.ftl:142-188). Syntax-level only: the WITH
/// option list is parsed as a PropertyList CST — no connector registration,
/// no catalog semantics (FLINK-03).
fn parse_flink_create_catalog(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"CATALOG", state, source, statement_id, "expected CATALOG after CREATE")
  if consume_word(cursor, b"IF") {
    valid = expect_word(cursor, b"NOT", state, source, statement_id, "expected NOT after IF") && valid
    valid = expect_word(cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF NOT") && valid
  }
  valid = parse_qualified_name(cursor, state, source, statement_id, "catalog name") && valid
  if consume_word(cursor, b"COMMENT") {
    valid = parse_flink_string_literal(cursor, state, source, statement_id, "catalog COMMENT") && valid
  }
  if consume_word(cursor, b"WITH") {
    valid = parse_properties_clause(cursor, state, source, statement_id, "CATALOG WITH options") && valid
  }
  valid
}

/// `DROP CATALOG [IF EXISTS] name` (SqlDropCatalog, parserImpls.ftl:173-188).
fn parse_flink_drop_catalog(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"CATALOG", state, source, statement_id, "expected CATALOG after DROP")
  if consume_word(cursor, b"IF") {
    valid = expect_word(cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF") && valid
  }
  valid = parse_qualified_name(cursor, state, source, statement_id, "catalog name") && valid
  valid
}

/// `ALTER CATALOG name SET (...)` / `ALTER CATALOG name RESET ('key', ...)` /
/// `ALTER CATALOG name COMMENT '...'` (SqlAlterCatalog,
/// statementParserMethods Parser.tdd:659).
fn parse_flink_alter_catalog(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"CATALOG", state, source, statement_id, "expected CATALOG after ALTER")
  valid = parse_qualified_name(cursor, state, source, statement_id, "catalog name") && valid
  if consume_word(cursor, b"SET") {
    valid = parse_properties_clause(cursor, state, source, statement_id, "ALTER CATALOG SET options") && valid
  } else if consume_word(cursor, b"RESET") {
    valid = parse_flink_reset_key_list(cursor, state, source, statement_id) && valid
  } else if consume_word(cursor, b"COMMENT") {
    valid = parse_flink_string_literal(cursor, state, source, statement_id, "catalog COMMENT") && valid
  } else {
    let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected SET, RESET, or COMMENT after ALTER CATALOG name", "alter-catalog", at, statement_id)
    valid = false
  }
  valid
}

/// `CREATE DATABASE [IF NOT EXISTS] name [COMMENT '...'] [WITH Properties()]`
/// (SqlCreateDatabase, parserImpls.ftl:301-372).
fn parse_flink_create_database(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"DATABASE", state, source, statement_id, "expected DATABASE after CREATE")
  if consume_word(cursor, b"IF") {
    valid = expect_word(cursor, b"NOT", state, source, statement_id, "expected NOT after IF") && valid
    valid = expect_word(cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF NOT") && valid
  }
  valid = parse_qualified_name(cursor, state, source, statement_id, "database name") && valid
  if consume_word(cursor, b"COMMENT") {
    valid = parse_flink_string_literal(cursor, state, source, statement_id, "database COMMENT") && valid
  }
  if consume_word(cursor, b"WITH") {
    valid = parse_properties_clause(cursor, state, source, statement_id, "DATABASE WITH options") && valid
  }
  valid
}

/// `DROP DATABASE [IF EXISTS] name [RESTRICT|CASCADE]`
/// (SqlDropDatabase, parserImpls.ftl:351-372).
fn parse_flink_drop_database(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"DATABASE", state, source, statement_id, "expected DATABASE after DROP")
  if consume_word(cursor, b"IF") {
    valid = expect_word(cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF") && valid
  }
  valid = parse_qualified_name(cursor, state, source, statement_id, "database name") && valid
  ignore(consume_word(cursor, b"RESTRICT") || consume_word(cursor, b"CASCADE"))
  valid
}

/// `ALTER DATABASE name SET (...)` (SqlAlterDatabase,
/// statementParserMethods Parser.tdd:664).
fn parse_flink_alter_database(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"DATABASE", state, source, statement_id, "expected DATABASE after ALTER")
  valid = parse_qualified_name(cursor, state, source, statement_id, "database name") && valid
  if consume_word(cursor, b"SET") {
    valid = parse_properties_clause(cursor, state, source, statement_id, "ALTER DATABASE SET options") && valid
  } else {
    let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected SET after ALTER DATABASE name", "alter-database", at, statement_id)
    valid = false
  }
  valid
}

/// `DROP TABLE [IF EXISTS] name` (SqlDropTable, parserImpls.ftl:1777-1792).
fn parse_flink_drop_table(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"TABLE", state, source, statement_id, "expected TABLE after DROP")
  if consume_word(cursor, b"IF") {
    valid = expect_word(cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF") && valid
  }
  valid = parse_qualified_name(cursor, state, source, statement_id, "table name") && valid
  valid
}

/// `ALTER TABLE name RENAME TO name` / `ALTER TABLE name SET (...)`
/// (SqlAlterTable, statementParserMethods Parser.tdd:692 area). The full
/// ALTER TABLE clause set (ADD/DROP/MODIFY columns) is beyond this wave's
/// enumerated surface (must-have truths cover CATALOG/DATABASE/VIEW/FUNCTION
/// and DROP TABLE); the RENAME/SET forms parse so the ALTER TABLE starter
/// never falls through to a spurious trailing error.
fn parse_flink_alter_table(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"TABLE", state, source, statement_id, "expected TABLE after ALTER")
  valid = parse_qualified_name(cursor, state, source, statement_id, "table name") && valid
  if consume_word(cursor, b"RENAME") {
    valid = expect_word(cursor, b"TO", state, source, statement_id, "expected TO after RENAME") && valid
    valid = parse_qualified_name(cursor, state, source, statement_id, "new table name") && valid
  } else if consume_word(cursor, b"SET") {
    valid = parse_properties_clause(cursor, state, source, statement_id, "ALTER TABLE SET options") && valid
  }
  valid
}

/// `CREATE VIEW [IF NOT EXISTS] name [(field_list)] [COMMENT '...'] AS query`
/// (SqlCreateView, parserImpls.ftl:2414-2439). The AS query reuses the shared
/// query skeleton's Flink-safe subset (parse_flink_query). The field list is
/// preserved as a parenthesized ( name [type], ... ) list.
fn parse_flink_create_view(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"VIEW", state, source, statement_id, "expected VIEW after CREATE")
  if consume_word(cursor, b"IF") {
    valid = expect_word(cursor, b"NOT", state, source, statement_id, "expected NOT after IF") && valid
    valid = expect_word(cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF NOT") && valid
  }
  valid = parse_qualified_name(cursor, state, source, statement_id, "view name") && valid
  if raw_at(cursor) is Some(b"(") {
    valid = parse_flink_view_field_list(cursor, state, source, statement_id) && valid
  }
  if consume_word(cursor, b"COMMENT") {
    valid = parse_flink_string_literal(cursor, state, source, statement_id, "view COMMENT") && valid
  }
  if consume_word(cursor, b"AS") {
    valid = parse_flink_query(cursor, state, source, statement_id) && valid
  } else if raw_at(cursor) is Some(_) && !(raw_at(cursor) is Some(b";")) {
    let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected AS query in CREATE VIEW", "view-query", at, statement_id)
    valid = false
  }
  valid
}

/// `( field_name [type], ... )` — the optional CREATE VIEW field list
/// (SqlCreateView, parserImpls.ftl:2414-2439).
fn parse_flink_view_field_list(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = expect_symbol(cursor, b"(", state, source, statement_id, "expected ( after CREATE VIEW name")
  let mut any = false
  let mut done = false
  while !done {
    if raw_at(cursor) is Some(b")") {
      done = true
    } else {
      any = true
      if is_identifier_candidate(cursor) {
        advance(cursor)
        // Optional field type.
        if raw_at(cursor) is Some(raw) && !(raw == b",") && !(raw == b")") {
          valid = parse_flink_data_type(cursor, state, source, statement_id) && valid
        }
      } else {
        let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        add_diagnostic(state, "FATHOM-PARSE-002", "expected view field name", "identifier", at, statement_id)
        valid = false
        done = true
      }
      if consume_symbol(cursor, b",") {
        if raw_at(cursor) is Some(b")") { done = true }
      } else {
        done = true
      }
    }
  }
  if !any {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected at least one view field", "view-field", make_span(source, at, at), statement_id)
    valid = false
  }
  valid = expect_symbol(cursor, b")", state, source, statement_id, "expected closing view field list parenthesis") && valid
  valid
}

/// `CREATE [TEMPORARY [SYSTEM]] FUNCTION [IF NOT EXISTS] name AS 'class'
/// [LANGUAGE JAVA|SCALA|PYTHON]` (SqlCreateFunction, parserImpls.ftl:
/// 390-480). The class string is a single-quoted string literal; all three
/// LANGUAGE values are accepted syntactically (no function resolution,
/// FLINK-03). The [TEMPORARY [SYSTEM]] prefix is consumed by
/// parse_flink_create before dispatch.
fn parse_flink_create_function(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"FUNCTION", state, source, statement_id, "expected FUNCTION after CREATE")
  if consume_word(cursor, b"IF") {
    valid = expect_word(cursor, b"NOT", state, source, statement_id, "expected NOT after IF") && valid
    valid = expect_word(cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF NOT") && valid
  }
  valid = parse_qualified_name(cursor, state, source, statement_id, "function name") && valid
  valid = expect_word(cursor, b"AS", state, source, statement_id, "expected AS 'class' in CREATE FUNCTION") && valid
  valid = parse_flink_string_literal(cursor, state, source, statement_id, "function class") && valid
  if consume_word(cursor, b"LANGUAGE") {
    if !(consume_word(cursor, b"JAVA") || consume_word(cursor, b"SCALA") || consume_word(cursor, b"PYTHON")) {
      let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected JAVA, SCALA, or PYTHON after LANGUAGE", "function-language", at, statement_id)
      valid = false
    }
  }
  valid
}

fn parse_flink_drop_view(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"VIEW", state, source, statement_id, "expected VIEW after DROP")
  if consume_word(cursor, b"IF") {
    valid = expect_word(cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF") && valid
  }
  valid = parse_qualified_name(cursor, state, source, statement_id, "view name") && valid
  valid
}

fn parse_flink_drop_function(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"FUNCTION", state, source, statement_id, "expected FUNCTION after DROP")
  if consume_word(cursor, b"IF") {
    valid = expect_word(cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF") && valid
  }
  valid = parse_qualified_name(cursor, state, source, statement_id, "function name") && valid
  valid
}

fn parse_flink_alter_view(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"VIEW", state, source, statement_id, "expected VIEW after ALTER")
  valid = parse_qualified_name(cursor, state, source, statement_id, "view name") && valid
  if consume_word(cursor, b"RENAME") {
    valid = expect_word(cursor, b"TO", state, source, statement_id, "expected TO after RENAME") && valid
    valid = parse_qualified_name(cursor, state, source, statement_id, "new view name") && valid
  } else if consume_word(cursor, b"AS") {
    valid = parse_flink_query(cursor, state, source, statement_id) && valid
  }
  valid
}

fn parse_flink_alter_function(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"FUNCTION", state, source, statement_id, "expected FUNCTION after ALTER")
  valid = parse_qualified_name(cursor, state, source, statement_id, "function name") && valid
  valid = expect_word(cursor, b"AS", state, source, statement_id, "expected AS 'class' in ALTER FUNCTION") && valid
  valid = parse_flink_string_literal(cursor, state, source, statement_id, "function class") && valid
  if consume_word(cursor, b"LANGUAGE") {
    if !(consume_word(cursor, b"JAVA") || consume_word(cursor, b"SCALA") || consume_word(cursor, b"PYTHON")) {
      let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected JAVA, SCALA, or PYTHON after LANGUAGE", "function-language", at, statement_id)
      valid = false
    }
  }
  valid
}

// ---------------------------------------------------------------------------
// FLINK-04 CREATE TABLE (SqlCreateTable, parserImpls.ftl:1585-1712). The
// optional parenthesized column body dispatches the four Flink column forms
// per TableColumn (:1103-1145): typed physical column, computed column
// `name AS expr`, metadata column `name type METADATA [FROM 'alias'] [VIRTUAL]`,
// and table constraint / WATERMARK. The table-level clause sequence
// [COMMENT][DISTRIBUTED][PARTITIONED BY][WITH][LIKE|AS] lands in Task 4
// (parse_flink_create_table_tail).
// ---------------------------------------------------------------------------

/// `CREATE [TEMPORARY] TABLE [IF NOT EXISTS] name [ ( column_defs ) ]
///   [table-level clauses]`. The [TEMPORARY] prefix is consumed by
/// parse_flink_create before dispatch.
fn parse_flink_create_table(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"TABLE", state, source, statement_id, "expected TABLE after CREATE")
  if consume_word(cursor, b"IF") {
    valid = expect_word(cursor, b"NOT", state, source, statement_id, "expected NOT after IF") && valid
    valid = expect_word(cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF NOT") && valid
  }
  valid = parse_qualified_name(cursor, state, source, statement_id, "table name") && valid
  if raw_at(cursor) is Some(b"(") {
    advance(cursor)
    valid = parse_flink_create_table_body(cursor, state, source, statement_id) && valid
    let closed = expect_symbol(cursor, b")", state, source, statement_id, "expected closing table body parenthesis")
    if !closed {
      recover_to_clause_boundary(cursor, state, source, statement_id, is_flink_create_table_clause_boundary)
    }
    valid = closed && valid
  }
  valid = parse_flink_create_table_tail(cursor, state, source, statement_id) && valid
  valid
}

/// The parenthesized column body loop: while-comma shape copying the Doris
/// parse_create_table_body skeleton (:2881-2919) but dispatching the four
/// Flink column forms per TableColumn (:1103-1145). WATERMARK is
/// single-instance (a second one is a localized multipleWatermarksUnsupported
/// error, never a silent overwrite — :1121-1140); a trailing comma is a
/// bounded FATHOM-PARSE-002 at the closing parenthesis (D-03).
fn parse_flink_create_table_body(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  let mut any = false
  let mut watermark_seen = false
  let mut done = false
  while !done {
    if raw_at(cursor) is Some(b")") {
      done = true
    } else {
      any = true
      if raw_at(cursor) is Some(raw) && bytes_equal_ci(raw, b"WATERMARK") {
        let wm_ok = parse_flink_watermark(cursor, state, source, statement_id, watermark_seen)
        valid = wm_ok && valid
        watermark_seen = true
      } else if is_flink_table_constraint_start(cursor) {
        valid = parse_flink_table_constraint(cursor, state, source, statement_id) && valid
      } else {
        valid = parse_flink_column(cursor, state, source, statement_id) && valid
      }
      if consume_symbol(cursor, b",") {
        if raw_at(cursor) is Some(b")") {
          let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
          add_diagnostic(state, "FATHOM-PARSE-002", "expected column definition after comma", "table-body", make_span(source, at, at), statement_id)
          valid = false
          done = true
        }
      } else {
        done = true
      }
    }
  }
  if !any {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected at least one column definition", "table-body", make_span(source, at, at), statement_id)
    valid = false
  }
  valid
}

/// True when the cursor sits on a Flink table-constraint starter: `PRIMARY
/// KEY`, `UNIQUE (cols)` / `UNIQUE KEY`, or `CONSTRAINT name` (UniqueSpec +
/// ConstraintEnforcement, parserImpls.ftl:1432-1504).
fn is_flink_table_constraint_start(cursor : Cursor) -> Bool {
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, b"PRIMARY") =>
      peek_raw(cursor, 1) is Some(next) && bytes_equal_ci(next, b"KEY")
    Some(raw) if bytes_equal_ci(raw, b"UNIQUE") => match peek_raw(cursor, 1) {
      Some(next) => bytes_equal_ci(next, b"KEY") || next == b"("
      None => false
    }
    Some(raw) if bytes_equal_ci(raw, b"CONSTRAINT") =>
      peek_raw(cursor, 1) is Some(_)
    _ => false
  }
}

/// Table/column constraint: `[CONSTRAINT name] (PRIMARY KEY | UNIQUE)
/// [(cols)] [NOT ENFORCED]` (UniqueSpec + ConstraintEnforcement,
/// parserImpls.ftl:1432-1504). The column list is present for the table-level
/// form (`PRIMARY KEY (id) NOT ENFORCED`) and absent for the column-level form
/// (`a INT PRIMARY KEY NOT ENFORCED`). A bare `ENFORCED` (or a missing
/// enforcement tail) is a localized FATHOM-PARSE-002 — Flink does not support
/// enforced primary-key constraints (testCreateTableWithPrimaryKeyEnforced
/// .fails family).
fn parse_flink_table_constraint(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  if consume_word(cursor, b"CONSTRAINT") {
    if is_identifier_candidate(cursor) {
      advance(cursor)
    } else {
      let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected constraint name after CONSTRAINT", "constraint-name", at, statement_id)
      valid = false
    }
  }
  if consume_word(cursor, b"PRIMARY") {
    valid = expect_word(cursor, b"KEY", state, source, statement_id, "expected KEY after PRIMARY") && valid
  } else if consume_word(cursor, b"UNIQUE") {
    ignore(consume_word(cursor, b"KEY"))
  } else {
    let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected PRIMARY KEY or UNIQUE in table constraint", "constraint", at, statement_id)
    valid = false
  }
  // Table-level form has a parenthesized simple identifier list.
  if raw_at(cursor) is Some(b"(") {
    advance(cursor)
    valid = parse_flink_identifier_list(cursor, state, source, statement_id, "constraint") && valid
    valid = expect_symbol(cursor, b")", state, source, statement_id, "expected closing constraint parenthesis") && valid
  }
  // ConstraintEnforcement: NOT ENFORCED required; bare ENFORCED is a localized
  // error (Flink has no enforced-constraint support in the SDK subset).
  if consume_word(cursor, b"NOT") {
    valid = expect_word(cursor, b"ENFORCED", state, source, statement_id, "expected ENFORCED after NOT") && valid
  } else {
    let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected NOT ENFORCED after PRIMARY KEY", "constraint", at, statement_id)
    valid = false
    ignore(consume_word(cursor, b"ENFORCED"))
  }
  valid
}

/// Consumes the remainder of a dialect-gated column-body element (up to the
/// next depth-0 `,` or `)`, both left unconsumed) so the gate is the primary
/// diagnostic and the body loop / close-paren handling stays intact (D-03,
/// bounded best-effort recovery). Paren depth is tracked so a nested
/// `PROCTIME()` / `(a)` in the gated element does not stop the scan early.
fn consume_body_element_remainder(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Unit {
  let mut depth = 0
  let mut done = false
  while !done {
    match raw_at(cursor) {
      None => done = true
      Some(raw) if raw == b")" => {
        if depth == 0 {
          done = true
        } else {
          depth = depth - 1
          advance(cursor)
        }
      }
      Some(raw) if raw == b"(" => {
        depth = depth + 1
        advance(cursor)
      }
      Some(raw) if raw == b"," && depth == 0 => done = true
      Some(_) => {
        let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        if consume_recovery_step(state, span, statement_id) { advance(cursor) } else { done = true }
      }
    }
  }
}

/// A parenthesized simple identifier list — `( col, ... )` used by the
/// table-level PRIMARY KEY / UNIQUE / PARTITIONED BY column lists.
fn parse_flink_identifier_list(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  what : String,
) -> Bool {
  let mut valid = true
  let mut any = false
  let mut done = false
  while !done {
    if raw_at(cursor) is Some(b")") {
      done = true
    } else {
      if is_identifier_candidate(cursor) {
        any = true
        advance(cursor)
      } else {
        let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        add_diagnostic(state, "FATHOM-PARSE-002", "expected identifier in " + what, "identifier", at, statement_id)
        valid = false
        done = true
      }
      if consume_symbol(cursor, b",") {
        if raw_at(cursor) is Some(b")") { done = true }
      } else {
        done = true
      }
    }
  }
  if !any {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected at least one identifier in " + what, "identifier", make_span(source, at, at), statement_id)
    valid = false
  }
  valid
}

/// A column body element that is not WATERMARK / a table constraint: reads the
/// column name, then dispatches computed (`name AS expr`, ComputedColumn
/// :1150-1176) vs typed / metadata (`name type [METADATA ...]`, TypedColumn
/// :1146-1130 / MetadataColumn :1176-1210).
fn parse_flink_column(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if is_identifier_candidate(cursor) {
    advance(cursor)
  } else {
    let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected column name", "identifier", at, statement_id)
    return false
  }
  if raw_at(cursor) is Some(raw) && bytes_equal_ci(raw, b"AS") {
    return parse_flink_computed_column(cursor, state, source, statement_id)
  }
  parse_flink_typed_column(cursor, state, source, statement_id)
}

/// Computed column tail: `AS expr [COMMENT '...']` (ComputedColumn,
/// parserImpls.ftl:1150-1176). The expression uses the shared Pratt parser.
fn parse_flink_computed_column(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = expect_word(cursor, b"AS", state, source, statement_id, "expected AS in computed column")
  let before = cursor.position
  let expr_ok = parse_expression(cursor, 1, 1, state, source, statement_id)
  if cursor.position == before {
    recover_expression(cursor, state, source, statement_id)
    valid = false
  } else {
    valid = expr_ok && valid
  }
  valid = parse_flink_column_comment(cursor, state, source, statement_id) && valid
  valid
}

/// Typed physical column tail: `type [METADATA ...] [constraint] [COMMENT]`
/// (TypedColumn :1146-1130, MetadataColumn :1176-1210). A metadata column is
/// `name type METADATA [FROM 'alias'] [VIRTUAL] [COMMENT '...']`.
fn parse_flink_typed_column(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = parse_flink_data_type(cursor, state, source, statement_id)
  // Doris-only AUTO_INCREMENT column form under Flink → 009 (T-11-15, §9).
  if raw_at(cursor) is Some(raw) && bytes_equal_ci(raw, b"AUTO_INCREMENT") {
    let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_dialect_gate_diagnostic(state, span, statement_id)
    valid = false
    consume_body_element_remainder(cursor, state, source, statement_id)
    return valid
  }
  if consume_word(cursor, b"METADATA") {
    if consume_word(cursor, b"FROM") {
      valid = parse_flink_string_literal(cursor, state, source, statement_id, "metadata alias") && valid
    }
    ignore(consume_word(cursor, b"VIRTUAL"))
    valid = parse_flink_column_comment(cursor, state, source, statement_id) && valid
    return valid
  }
  // Column-level constraint: [CONSTRAINT name] (PRIMARY KEY | UNIQUE)
  // [NOT ENFORCED].
  if raw_at(cursor) is Some(raw) && (bytes_equal_ci(raw, b"CONSTRAINT") || bytes_equal_ci(raw, b"PRIMARY") || bytes_equal_ci(raw, b"UNIQUE")) {
    valid = parse_flink_table_constraint(cursor, state, source, statement_id) && valid
  }
  valid = parse_flink_column_comment(cursor, state, source, statement_id) && valid
  valid
}

/// `COMMENT '...'` on a column (or computed column). Returns true when no
/// COMMENT follows.
fn parse_flink_column_comment(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if consume_word(cursor, b"COMMENT") {
    return parse_flink_string_literal(cursor, state, source, statement_id, "column COMMENT")
  }
  true
}

/// WATERMARK body: `WATERMARK FOR <col> AS <expr>` (parserImpls.ftl:
/// 1121-1140). The event-time column is a qualified name and the strategy
/// expression uses the shared Pratt parser (including Flink INTERVAL
/// literals). A second WATERMARK emits the localized
/// multipleWatermarksUnsupported error at the WATERMARK token — never a
/// silent overwrite (T-11-17).
fn parse_flink_watermark(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  already_seen : Bool,
) -> Bool {
  let start_span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
  let mut valid = expect_word(cursor, b"WATERMARK", state, source, statement_id, "expected WATERMARK")
  valid = expect_word(cursor, b"FOR", state, source, statement_id, "expected FOR after WATERMARK") && valid
  valid = parse_qualified_name(cursor, state, source, statement_id, "watermark event-time column") && valid
  valid = expect_word(cursor, b"AS", state, source, statement_id, "expected AS in WATERMARK") && valid
  let before = cursor.position
  let expr_ok = parse_expression(cursor, 1, 1, state, source, statement_id)
  if cursor.position == before {
    recover_expression(cursor, state, source, statement_id)
    valid = false
  } else {
    valid = expr_ok && valid
  }
  if already_seen {
    add_diagnostic(state, "FATHOM-PARSE-002", "multiple WATERMARK clauses are not supported", "watermark", start_span, statement_id)
    valid = false
  }
  valid
}

// Table-level clause sequence [COMMENT][DISTRIBUTED][PARTITIONED BY][WITH]
// [LIKE|AS] in the pinned SqlCreateTable order (parserImpls.ftl:1585-1712).
// Each Doris-only CREATE TABLE sub-form (DUPLICATE/UNIQUE/AGGREGATE KEY,
// ENGINE =, ROLLUP, PROPERTIES, AUTO PARTITION BY, PARTITION BY, DISTRIBUTED
// BY ... BUCKETS) is a construct-level FATHOM-PARSE-009 gate here (T-11-15,
// D-04 §9 matrix).
fn parse_flink_create_table_tail(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  if consume_word(cursor, b"COMMENT") {
    valid = parse_flink_string_literal(cursor, state, source, statement_id, "table COMMENT") && valid
  }
  if consume_word(cursor, b"DISTRIBUTED") {
    valid = parse_flink_distribution_clause(cursor, state, source, statement_id) && valid
  }
  if consume_word(cursor, b"PARTITIONED") {
    valid = expect_word(cursor, b"BY", state, source, statement_id, "expected BY after PARTITIONED") && valid
    if raw_at(cursor) is Some(b"(") {
      advance(cursor)
      valid = parse_flink_identifier_list(cursor, state, source, statement_id, "PARTITIONED BY") && valid
      valid = expect_symbol(cursor, b")", state, source, statement_id, "expected closing PARTITIONED BY parenthesis") && valid
    } else {
      let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected ( after PARTITIONED BY", "partitioned-by", at, statement_id)
      valid = false
    }
  }
  if consume_word(cursor, b"WITH") {
    valid = parse_properties_clause(cursor, state, source, statement_id, "table WITH connector options") && valid
  }
  if consume_word(cursor, b"LIKE") {
    valid = parse_flink_table_like(cursor, state, source, statement_id) && valid
  } else if consume_word(cursor, b"AS") {
    // CTAS: AS query (SqlCreateTableAs :1650-1690).
    if is_query_start(cursor) {
      valid = parse_flink_query(cursor, state, source, statement_id) && valid
    } else {
      let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected query after AS in CREATE TABLE", "ctas-query", at, statement_id)
      valid = false
    }
  }
  // Doris-only CREATE TABLE sub-forms under Flink → FATHOM-PARSE-009
  // (T-11-15, §9 matrix): DUPLICATE/UNIQUE/AGGREGATE KEY, ENGINE =, ROLLUP,
  // PROPERTIES, AUTO PARTITION BY, PARTITION BY RANGE/LIST.
  if raw_at(cursor) is Some(raw) && (bytes_equal_ci(raw, b"DUPLICATE") ||
    bytes_equal_ci(raw, b"UNIQUE") || bytes_equal_ci(raw, b"AGGREGATE") ||
    bytes_equal_ci(raw, b"ENGINE") || bytes_equal_ci(raw, b"ROLLUP") ||
    bytes_equal_ci(raw, b"PROPERTIES") || bytes_equal_ci(raw, b"AUTO") ||
    bytes_equal_ci(raw, b"PARTITION")) {
    let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_dialect_gate_diagnostic(state, span, statement_id)
    valid = false
    consume_gated_remainder(cursor, state, source, statement_id)
  }
  valid
}

/// `DISTRIBUTED [BY [HASH|RANGE](cols)] [INTO n BUCKETS]` (SqlDistribution,
/// parserImpls.ftl:1560-1600, IntoBuckets :1556-1570). `n` must be a positive
/// integer (`INTO -3 BUCKETS` / `INTO 0 BUCKETS` are localized errors);
/// `RANDOM` distribution is unsupported (testCreateTableWithRandomDistribution
/// .fails); the Doris `DISTRIBUTED BY ... BUCKETS` form is a FATHOM-PARSE-009
/// gate (T-11-19).
fn parse_flink_distribution_clause(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  if consume_word(cursor, b"BY") {
    if consume_word(cursor, b"HASH") || consume_word(cursor, b"RANGE") {
      if raw_at(cursor) is Some(b"(") {
        advance(cursor)
        valid = parse_flink_identifier_list(cursor, state, source, statement_id, "DISTRIBUTED BY") && valid
        valid = expect_symbol(cursor, b")", state, source, statement_id, "expected closing DISTRIBUTED BY parenthesis") && valid
      } else {
        let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        add_diagnostic(state, "FATHOM-PARSE-002", "expected ( after DISTRIBUTED BY HASH/RANGE", "distribution", at, statement_id)
        valid = false
      }
    } else if raw_at(cursor) is Some(raw) && bytes_equal_ci(raw, b"RANDOM") {
      // RANDOM distribution is unsupported (testCreateTableWithRandomDistribution
      // .fails, parserImpls.ftl:1560-1600).
      let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "FATHOM-PARSE-002", "RANDOM distribution is not supported", "distribution", at, statement_id)
      valid = false
      advance(cursor)
    } else {
      let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected HASH or RANGE after DISTRIBUTED BY", "distribution", at, statement_id)
      valid = false
    }
  }
  if consume_word(cursor, b"INTO") {
    let count_ok = match token_at(cursor) {
      Some(token) if token.kind is @token.TokenKind::Number => {
        let raw = match raw_at(cursor) { Some(raw) => raw; None => b"" }
        if is_positive_integer_raw(raw) {
          advance(cursor)
          true
        } else {
          let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
          add_diagnostic(state, "FATHOM-PARSE-002", "expected positive integer bucket count after INTO", "distribution", at, statement_id)
          valid = false
          advance(cursor)
          false
        }
      }
      _ => {
        let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        add_diagnostic(state, "FATHOM-PARSE-002", "expected positive integer bucket count after INTO", "distribution", at, statement_id)
        valid = false
        false
      }
    }
    if count_ok {
      valid = expect_word(cursor, b"BUCKETS", state, source, statement_id, "expected BUCKETS after bucket count") && valid
    } else {
      // The malformed bucket-count remainder is consumed losslessly so the
      // localized error is the primary diagnostic (no spurious trailing 001).
      consume_gated_remainder(cursor, state, source, statement_id)
    }
  } else if raw_at(cursor) is Some(raw) && bytes_equal_ci(raw, b"RANDOM") {
    // `DISTRIBUTED RANDOM` (no BY) is also unsupported.
    let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "FATHOM-PARSE-002", "RANDOM distribution is not supported", "distribution", at, statement_id)
    valid = false
    advance(cursor)
  } else if raw_at(cursor) is Some(raw) && bytes_equal_ci(raw, b"BUCKETS") {
    // Doris-only DISTRIBUTED BY ... BUCKETS n|AUTO form under Flink → 009.
    let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_dialect_gate_diagnostic(state, span, statement_id)
    valid = false
    consume_gated_remainder(cursor, state, source, statement_id)
  }
  valid
}

/// True when the raw bytes are a decimal integer ≥ 1 (the DISTRIBUTED INTO
/// bucket count; a decimal point or exponent fails — the count must be an
/// integer, T-11-19).
fn is_positive_integer_raw(raw : Bytes) -> Bool {
  if raw.length() == 0 { return false }
  let mut i = 0
  while i < raw.length() {
    let byte = raw[i].to_int()
    if byte < 48 || byte > 57 { return false }
    i = i + 1
  }
  !(raw.length() == 1 && raw[0].to_int() == 48)
}

/// `LIKE table [(INCLUDING|EXCLUDING|OVERWRITING <feature> ...)]`
/// (SqlTableLike, parserImpls.ftl:1714-1790). The feature list is
/// parenthesized and preserved syntactically; the feature keywords are
/// ALL/CONSTRAINTS/DISTRIBUTION/GENERATED/METADATA/OPTIONS/PARTITIONS/
/// WATERMARKS.
fn parse_flink_table_like(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = parse_qualified_name(cursor, state, source, statement_id, "LIKE source table") && true
  if raw_at(cursor) is Some(b"(") {
    advance(cursor)
    let mut any = false
    let mut done = false
    while !done {
      if raw_at(cursor) is Some(b")") {
        done = true
      } else {
        if consume_word(cursor, b"INCLUDING") || consume_word(cursor, b"EXCLUDING") ||
          consume_word(cursor, b"OVERWRITING") {
          if consume_word(cursor, b"ALL") {
            any = true
          } else if is_identifier_candidate(cursor) {
            advance(cursor)
            any = true
          } else {
            let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
            add_diagnostic(state, "FATHOM-PARSE-002", "expected LIKE feature after INCLUDING/EXCLUDING/OVERWRITING", "like-feature", at, statement_id)
            valid = false
            done = true
          }
        } else {
          let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
          add_diagnostic(state, "FATHOM-PARSE-002", "expected INCLUDING, EXCLUDING, or OVERWRITING in LIKE options", "like-option", at, statement_id)
          valid = false
          done = true
        }
        if consume_symbol(cursor, b",") {
          if raw_at(cursor) is Some(b")") { done = true }
        } else {
          done = true
        }
      }
    }
    if !any {
      let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected at least one LIKE feature", "like-feature", make_span(source, at, at), statement_id)
      valid = false
    }
    valid = expect_symbol(cursor, b")", state, source, statement_id, "expected closing LIKE options parenthesis") && valid
  }
  valid
}

// ---------------------------------------------------------------------------
// FLINK-05 Window TVF (TableFunctionCall, Parser.jj:2443-2460). Syntax-level
// only: TUMBLE/HOP/CUMULATE/SESSION window table functions (and the explicit
// TABLE(...) wrapper, MatchRecognizeTest.scala:141-148) parse into
// source-backed token CST — no event-time / watermark / window-aggregate type
// inference (FLINK-05 prohibition, T-11-26). The window output columns
// window_start/window_end/window_time are ordinary projection identifiers
// (Pitfall 8 — legacy TUMBLE_START()/TUMBLE_ROWTIME() are never TVF output
// columns here). TUMBLE/HOP/SESSION/DESCRIPTOR are non-reserved words
// (Parser.tdd:587/:384/:509/:351); CUMULATE has no keyword token (A2), so the
// call rides the generic table-function-call path with no dedicated dispatch.
// ---------------------------------------------------------------------------

/// Window TVF entry: the TVF name (TUMBLE/HOP/CUMULATE/SESSION or the
/// TABLE(...) wrapper) followed by `(`, routed from the Flink parse_table_ref
/// branch via is_flink_tvf_starter. Positional arguments are validated in
/// order (table, descriptor, size, optional offset); named-argument `=>`
/// forms (NAMED_ARGUMENT_ASSIGNMENT, Parser.jj:8794) are recognized in the
/// argument layer without reordering positional args (probe FLINK-05
/// ordering).
fn parse_flink_tvf_call(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = true
  let is_table_wrapper = match raw_at(cursor) {
    Some(raw) => bytes_equal_ci(raw, b"TABLE")
    None => false
  }
  // The TVF name token is verified by is_flink_tvf_starter (TUMBLE/HOP/
  // CUMULATE/SESSION or TABLE followed by `(`), so it is consumed regardless
  // of keyword classification (CUMULATE has no keyword token at all — A2).
  match raw_at(cursor) {
    Some(_) => advance(cursor)
    None => {
      let at = source.byte_length()
      add_diagnostic(state, "FATHOM-PARSE-002", "expected window TVF name", "tvf-name", make_span(source, at, at), statement_id)
      return false
    }
  }
  valid = expect_symbol(cursor, b"(", state, source, statement_id, "expected ( after window TVF name") && valid
  if is_table_wrapper {
    // TABLE( <tvf-call> ): the explicit wrapper form.
    if is_flink_tvf_starter(cursor) {
      valid = parse_flink_tvf_call(cursor, state, source, statement_id) && valid
    } else if is_identifier_candidate(cursor) {
      valid = parse_qualified_name(cursor, state, source, statement_id, "TABLE wrapper table reference") && valid
    } else {
      let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected table function inside TABLE( )", "tvf-argument", make_span(source, at, at), statement_id)
      valid = false
    }
    valid = expect_symbol(cursor, b")", state, source, statement_id, "expected closing TABLE wrapper parenthesis") && valid
  } else {
    valid = parse_flink_tvf_arguments(cursor, state, source, statement_id) && valid
  }
  valid
}

/// The parenthesized TVF argument list. Position 0 must be a TABLE table
/// reference (the first argument of every window TVF — consume the TABLE
/// keyword then parse a qualified name). The standard form requires at least
/// TABLE + DESCRIPTOR + INTERVAL size (3 positional args); an optional fourth
/// INTERVAL is the offset. A missing table (position 0 is not TABLE) or a
/// too-short list (e.g. `TUMBLE(TABLE T1)`) is a localized FATHOM-PARSE-002
/// at the offending position (probe FLINK-05 empty; negative fixtures).
fn parse_flink_tvf_arguments(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  let mut arg_index = 0
  let mut any = false
  let mut done = false
  while !done {
    if raw_at(cursor) is Some(b")") {
      done = true
    } else {
      any = true
      let before = cursor.position
      let arg_ok = parse_flink_tvf_argument(cursor, state, source, statement_id, arg_index)
      valid = arg_ok && valid
      if cursor.position == before {
        recover_expression(cursor, state, source, statement_id)
        valid = false
      }
      arg_index = arg_index + 1
      if consume_symbol(cursor, b",") {
        if raw_at(cursor) is Some(b")") || raw_at(cursor) is None {
          let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
          add_diagnostic(state, "FATHOM-PARSE-002", "expected TVF argument after comma", "tvf-argument", make_span(source, at, at), statement_id)
          valid = false
          done = true
        }
      } else {
        done = true
      }
    }
  }
  if !any {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected at least one TVF argument", "tvf-argument", make_span(source, at, at), statement_id)
    valid = false
  }
  // Standard TVF arity: TABLE + DESCRIPTOR + INTERVAL size (probe FLINK-05
  // ordering/empty — a too-short list is a localized error at the offending
  // position, e.g. the `)` in `TUMBLE(TABLE T1)`).
  if arg_index < 3 {
    let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "FATHOM-PARSE-002", "window TVF requires TABLE, DESCRIPTOR, and INTERVAL size arguments", "tvf-argument", at, statement_id)
    valid = false
  }
  valid = expect_symbol(cursor, b")", state, source, statement_id, "expected closing window TVF parenthesis") && valid
  valid
}

/// A single TVF argument: either a named-argument `name => value` form
/// (NAMED_ARGUMENT_ASSIGNMENT, Parser.jj:8794) or a positional value. The
/// positional index (arg_index) drives the positional-kind validation.
fn parse_flink_tvf_argument(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  arg_index : Int,
) -> Bool {
  if is_named_argument_arrow(cursor) {
    // Consume the argument name, then the arrow.
    advance(cursor)
    match raw_at(cursor) {
      Some(raw) if raw == b"=>" => advance(cursor)
      _ => {
        let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        add_diagnostic(state, "FATHOM-PARSE-002", "expected => after TVF named argument name", "named-argument", span, statement_id)
        return false
      }
    }
    return parse_flink_tvf_argument_value(cursor, state, source, statement_id, arg_index)
  }
  parse_flink_tvf_argument_value(cursor, state, source, statement_id, arg_index)
}

/// A TVF argument value. Position 0 must be a TABLE table reference (the
/// first argument of every window TVF — consume the TABLE keyword then parse
/// a qualified name). Later positions fall through to the shared expression
/// parser, which covers DESCRIPTOR(col) (a non-reserved function call) and
/// the INTERVAL size/offset literals.
fn parse_flink_tvf_argument_value(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  arg_index : Int,
) -> Bool {
  if arg_index == 0 {
    if raw_at(cursor) is Some(raw) && bytes_equal_ci(raw, b"TABLE") {
      advance(cursor)
      return parse_qualified_name(cursor, state, source, statement_id, "TVF table reference")
    }
    let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "FATHOM-PARSE-002", "window TVF first argument must be a TABLE reference", "tvf-argument", span, statement_id)
    // Consume the offending expression so the TVF argument loop advances past
    // it — never leave the cursor at a nested `)` (e.g. DESCRIPTOR(rowtime)'s
    // close) that the loop would misread as the TVF close (probe FLINK-05
    // empty; the shared recovery-step budget caps this).
    let before = cursor.position
    let expr_ok = parse_expression(cursor, 1, 1, state, source, statement_id)
    if cursor.position == before {
      recover_expression(cursor, state, source, statement_id)
    }
    ignore(expr_ok)
    return false
  }
  let before = cursor.position
  let expr_ok = parse_expression(cursor, 1, 1, state, source, statement_id)
  if cursor.position == before {
    recover_expression(cursor, state, source, statement_id)
    false
  } else {
    expr_ok
  }
}

// ---------------------------------------------------------------------------
// FLINK-06 MATCH_RECOGNIZE (MatchRecognize, Parser.jj:3062-3346). Syntax-level
// CST only — no planner/execution equivalence (FLINK-06 prohibition, T-11-26).
// Pattern variables parse as plain identifiers with NO column-scope/type
// validation: a syntactically valid MATCH_RECOGNIZE referencing an undeclared
// variable is never rejected (Pitfall 6, T-11-25). The sub-language has its
// own sync points (is_flink_match_recognize_boundary) so an unclosed
// PATTERN/DEFINE recovers at the sub-language boundary or `;` under the shared
// recovery budget (Pitfall 4/8, CST-01, T-11-24).
// ---------------------------------------------------------------------------

/// `MATCH_RECOGNIZE ( [PARTITION BY expr-list] [ORDER BY order-list]
///   [MEASURES measure-list] [ONE ROW PER MATCH | ALL ROWS PER MATCH]
///   [AFTER MATCH SKIP ...] PATTERN ( pattern_expr ) [WITHIN INTERVAL literal]
///   DEFINE var AS expr-list )`. PATTERN and DEFINE are required
/// (Parser.jj:3157-3178); a missing DEFINE or unclosed PATTERN is a localized
/// error that recovers at the sub-language boundary (negative/recovery
/// fixtures).
fn parse_match_recognize(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"MATCH_RECOGNIZE", state, source, statement_id, "expected MATCH_RECOGNIZE")
  valid = expect_symbol(cursor, b"(", state, source, statement_id, "expected ( after MATCH_RECOGNIZE") && valid
  // Optional pre-PATTERN clauses in the pinned order (Parser.jj:3091-3154).
  valid = parse_match_recognize_pre_pattern_clauses(cursor, state, source, statement_id) && valid
  // PATTERN ( pattern_expr ) — required (Parser.jj:3157-3176).
  if consume_word(cursor, b"PATTERN") {
    let pat_open = expect_symbol(cursor, b"(", state, source, statement_id, "expected ( after PATTERN")
    valid = pat_open && valid
    // ^ strict-start anchor (Parser.jj:3160).
    ignore(consume_symbol(cursor, b"^"))
    let pattern_ok = parse_pattern_expr(cursor, state, source, statement_id)
    valid = pattern_ok && valid
    // $ strict-end anchor (Parser.jj:3166).
    ignore(consume_symbol(cursor, b"$"))
    let pat_close = expect_symbol(cursor, b")", state, source, statement_id, "expected closing PATTERN parenthesis")
    valid = pat_close && valid
    if !pat_close {
      // An unclosed PATTERN recovers at the next sub-language sync point
      // (Pitfall 4/8, T-11-24).
      recover_to_clause_boundary(cursor, state, source, statement_id, is_flink_match_recognize_boundary)
    }
  } else {
    let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected PATTERN clause in MATCH_RECOGNIZE", "match-pattern", at, statement_id)
    valid = false
  }
  // [ WITHIN INTERVAL literal ] (Parser.jj:3170) — parse_flink_interval_literal
  // consumes the INTERVAL keyword itself.
  if consume_word(cursor, b"WITHIN") {
    valid = parse_flink_interval_literal(cursor, state, source, statement_id) && valid
  }
  // DEFINE var AS expr-list — required (Parser.jj:3177-3178).
  if consume_word(cursor, b"DEFINE") {
    valid = parse_pattern_definition_list(cursor, state, source, statement_id) && valid
  } else {
    let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected DEFINE clause in MATCH_RECOGNIZE", "match-define", at, statement_id)
    valid = false
  }
  let close = expect_symbol(cursor, b")", state, source, statement_id, "expected closing MATCH_RECOGNIZE parenthesis")
  valid = close && valid
  if !close {
    recover_to_clause_boundary(cursor, state, source, statement_id, is_flink_match_recognize_boundary)
  }
  valid
}

/// The optional pre-PATTERN clauses in pinned order (Parser.jj:3091-3154):
/// PARTITION BY expr-list, ORDER BY order-list, MEASURES measure-list,
/// ONE ROW PER MATCH / ALL ROWS PER MATCH, and AFTER MATCH SKIP. The loop
/// terminates at PATTERN, `)`, or a non-clause token (which the PATTERN
/// requirement check then reports).
fn parse_match_recognize_pre_pattern_clauses(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  let mut done = false
  while !done {
    if consume_word(cursor, b"PARTITION") {
      valid = expect_word(cursor, b"BY", state, source, statement_id, "expected BY after PARTITION in MATCH_RECOGNIZE") && valid
      valid = parse_expression_list(cursor, state, source, statement_id, true) && valid
    } else if consume_word(cursor, b"ORDER") {
      valid = parse_order_by(cursor, state, source, statement_id) && valid
    } else if consume_word(cursor, b"MEASURES") {
      valid = parse_measure_column_list(cursor, state, source, statement_id) && valid
    } else if consume_word(cursor, b"ONE") {
      valid = expect_word(cursor, b"ROW", state, source, statement_id, "expected ROW after ONE") && valid
      valid = expect_word(cursor, b"PER", state, source, statement_id, "expected PER after ONE ROW") && valid
      valid = expect_word(cursor, b"MATCH", state, source, statement_id, "expected MATCH after ONE ROW PER") && valid
    } else if consume_word(cursor, b"ALL") {
      valid = expect_word(cursor, b"ROWS", state, source, statement_id, "expected ROWS after ALL") && valid
      valid = expect_word(cursor, b"PER", state, source, statement_id, "expected PER after ALL ROWS") && valid
      valid = expect_word(cursor, b"MATCH", state, source, statement_id, "expected MATCH after ALL ROWS PER") && valid
    } else if consume_word(cursor, b"AFTER") {
      valid = parse_after_match_skip(cursor, state, source, statement_id) && valid
    } else if consume_word(cursor, b"SUBSET") {
      // SUBSET name = ( var [, var]* ) — parsed structurally and classified
      // known-limitation in fixtures (subsetList, Parser.jj:3182; RESEARCH
      // §8.2 — syntax accepted, no planner semantics).
      if is_identifier_candidate(cursor) {
        advance(cursor)
      } else {
        let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        add_diagnostic(state, "FATHOM-PARSE-002", "expected SUBSET name", "subset-name", at, statement_id)
        valid = false
      }
      valid = expect_symbol(cursor, b"=", state, source, statement_id, "expected = after SUBSET name") && valid
      if consume_symbol(cursor, b"(") {
        valid = parse_flink_identifier_list(cursor, state, source, statement_id, "SUBSET") && valid
        valid = expect_symbol(cursor, b")", state, source, statement_id, "expected closing SUBSET parenthesis") && valid
      } else {
        let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        add_diagnostic(state, "FATHOM-PARSE-002", "expected ( after SUBSET name =", "subset", at, statement_id)
        valid = false
      }
    } else {
      done = true
    }
  }
  valid
}

/// `AFTER MATCH SKIP (TO NEXT ROW | TO FIRST var | TO LAST var |
///   PAST LAST ROW)` (AfterOption, Parser.jj:3123-3154).
fn parse_after_match_skip(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = expect_word(cursor, b"MATCH", state, source, statement_id, "expected MATCH after AFTER") && true
  valid = expect_word(cursor, b"SKIP", state, source, statement_id, "expected SKIP after AFTER MATCH") && valid
  if consume_word(cursor, b"TO") {
    if consume_word(cursor, b"NEXT") {
      valid = expect_word(cursor, b"ROW", state, source, statement_id, "expected ROW after TO NEXT") && valid
    } else if consume_word(cursor, b"FIRST") || consume_word(cursor, b"LAST") {
      if is_identifier_candidate(cursor) {
        advance(cursor)
      } else {
        let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        add_diagnostic(state, "FATHOM-PARSE-002", "expected pattern variable after TO FIRST/LAST", "pattern-variable", at, statement_id)
        valid = false
      }
    } else {
      let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected NEXT ROW, FIRST, or LAST after TO", "skip-to", at, statement_id)
      valid = false
    }
  } else if consume_word(cursor, b"PAST") {
    valid = expect_word(cursor, b"LAST", state, source, statement_id, "expected LAST after PAST") && valid
    valid = expect_word(cursor, b"ROW", state, source, statement_id, "expected ROW after PAST LAST") && valid
  } else {
    let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected TO or PAST after AFTER MATCH SKIP", "skip-policy", at, statement_id)
    valid = false
  }
  valid
}

/// `MEASURES expr [AS alias] [, expr [AS alias]]` (MeasureColumnCommaList,
/// Parser.jj:3101-3103). MATCH_NUMBER()/MATCH_ROWTIME()/MATCH_PROCTIME() are
/// consumed as ordinary match function calls (MATCH_NUMBER is a Reserved row,
/// Pitfall 9, so the expression operand gate would reject it — RESEARCH §5.6).
fn parse_measure_column_list(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  let mut any = false
  let mut done = false
  while !done {
    if raw_at(cursor) is Some(b")") {
      done = true
    } else {
      any = true
      let before = cursor.position
      let item_ok = if is_flink_match_function(cursor) {
        parse_flink_match_function_call(cursor, state, source, statement_id)
      } else {
        parse_expression(cursor, 1, 1, state, source, statement_id)
      }
      valid = item_ok && valid
      if cursor.position == before {
        recover_expression(cursor, state, source, statement_id)
        valid = false
      }
      if consume_word(cursor, b"AS") {
        if is_identifier_candidate(cursor) {
          advance(cursor)
        } else {
          let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
          add_diagnostic(state, "FATHOM-PARSE-002", "expected measure alias after AS", "measure-alias", at, statement_id)
          valid = false
        }
      }
      if consume_symbol(cursor, b",") {
        if raw_at(cursor) is Some(b")") || raw_at(cursor) is None {
          let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
          add_diagnostic(state, "FATHOM-PARSE-002", "expected measure after comma", "measure", make_span(source, at, at), statement_id)
          valid = false
          done = true
        }
      } else {
        done = true
      }
    }
  }
  if !any {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected at least one MEASURES column", "measure", make_span(source, at, at), statement_id)
    valid = false
  }
  valid
}

/// `DEFINE var AS expr [, var AS expr]` (PatternDefinitionCommaList,
/// Parser.jj:3177-3178). Pattern variables are plain identifiers; the
/// definition expression uses the shared Pratt parser. NO column-scope/type
/// validation — an expression referencing an undeclared pattern variable is
/// syntactically accepted (Pitfall 6, FLINK-06 prohibition).
fn parse_pattern_definition_list(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  let mut any = false
  let mut done = false
  while !done {
    if raw_at(cursor) is Some(b")") {
      done = true
    } else {
      any = true
      if is_identifier_candidate(cursor) {
        advance(cursor)
      } else {
        let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        add_diagnostic(state, "FATHOM-PARSE-002", "expected pattern variable in DEFINE", "pattern-variable", at, statement_id)
        valid = false
        done = true
      }
      valid = expect_word(cursor, b"AS", state, source, statement_id, "expected AS after DEFINE pattern variable") && valid
      let before = cursor.position
      let expr_ok = parse_expression(cursor, 1, 1, state, source, statement_id)
      if cursor.position == before {
        recover_expression(cursor, state, source, statement_id)
        valid = false
      } else {
        valid = expr_ok && valid
      }
      if consume_symbol(cursor, b",") {
        if raw_at(cursor) is Some(b")") || raw_at(cursor) is None {
          let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
          add_diagnostic(state, "FATHOM-PARSE-002", "expected pattern definition after comma", "pattern-definition", make_span(source, at, at), statement_id)
          valid = false
          done = true
        }
      } else {
        done = true
      }
    }
  }
  if !any {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected at least one DEFINE pattern definition", "pattern-definition", make_span(source, at, at), statement_id)
    valid = false
  }
  valid
}

/// True when the cursor sits on a MATCH_RECOGNIZE measure function:
/// MATCH_NUMBER()/MATCH_ROWTIME()/MATCH_PROCTIME() (RESEARCH §5.6).
/// MATCH_NUMBER is a Reserved Calcite-base row (Pitfall 9) so it is consumed
/// specially in the MEASURES clause rather than through the identifier operand
/// gate.
fn is_flink_match_function(cursor : Cursor) -> Bool {
  match raw_at(cursor) {
    Some(raw) => bytes_equal_ci(raw, b"MATCH_NUMBER") || bytes_equal_ci(raw, b"MATCH_ROWTIME") ||
      bytes_equal_ci(raw, b"MATCH_PROCTIME")
    None => false
  }
}

/// `MATCH_NUMBER()` / `MATCH_ROWTIME()` / `MATCH_PROCTIME()` — ordinary
/// function calls in MEASURES (RESEARCH §5.6). Syntax-level only; the zero-
/// argument form parses directly.
fn parse_flink_match_function_call(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  if !is_flink_match_function(cursor) {
    let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected MATCH_NUMBER, MATCH_ROWTIME, or MATCH_PROCTIME", "match-function", at, statement_id)
    return false
  }
  advance(cursor)
  valid = expect_symbol(cursor, b"(", state, source, statement_id, "expected ( after match function") && valid
  if !consume_symbol(cursor, b")") {
    valid = parse_expression_list(cursor, state, source, statement_id, true) && valid
    valid = expect_symbol(cursor, b")", state, source, statement_id, "expected closing match function parenthesis") && valid
  }
  valid
}

/// `pattern_expr := pattern_concatenation ('|' pattern_concatenation)*`
/// (PATTERN_ALTER, Parser.jj:3218-3222).
fn parse_pattern_expr(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = parse_pattern_concat(cursor, state, source, statement_id)
  while consume_symbol(cursor, b"|") {
    valid = parse_pattern_concat(cursor, state, source, statement_id) && valid
  }
  valid
}

/// `pattern_concatenation := pattern_factor (pattern_factor)*`
/// (PATTERN_CONCAT, Parser.jj:3236-3240). Stops at the sub-language
/// boundaries: `)` (group / PATTERN close), `|` (ALTER), `^`/`$` (anchors —
/// consumed by parse_match_recognize), or a MATCH_RECOGNIZE clause keyword
/// (is_flink_match_recognize_boundary). A bare `PATTERN ()` (no factor) is a
/// localized FATHOM-PARSE-002 (negative fixture).
fn parse_pattern_concat(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  let mut any = false
  let mut done = false
  while !done {
    match raw_at(cursor) {
      None => done = true
      Some(raw) if raw == b")" || raw == b"|" || raw == b"^" || raw == b"$" || raw == b"," => done = true
      Some(raw) if is_flink_match_recognize_boundary(raw) => done = true
      Some(_) => {
        let before = cursor.position
        let factor_ok = parse_pattern_factor(cursor, state, source, statement_id)
        any = any || factor_ok
        valid = factor_ok && valid
        if cursor.position == before {
          recover_expression(cursor, state, source, statement_id)
          valid = false
          done = true
        }
      }
    }
  }
  if !any {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected pattern variable or group in PATTERN", "pattern", make_span(source, at, at), statement_id)
    valid = false
  }
  valid
}

/// `pattern_factor := pattern_primary [quantifier]` (PatternFactor /
/// PatternQuantifier, Parser.jj:3314-3317).
fn parse_pattern_factor(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let primary_ok = parse_pattern_primary(cursor, state, source, statement_id)
  let quantifier_ok = parse_pattern_quantifier(cursor, state, source, statement_id)
  primary_ok && quantifier_ok
}

/// `pattern_primary := pattern_variable | ( pattern_expr ) | PERMUTE(...) |
///   {- ... -}` (PatternFactor, Parser.jj:3294-3346). PERMUTE and {- ... -}
/// (PatternExclude) parse structurally and are classified known-limitation in
/// the fixtures (RESEARCH §8.2 — syntax accepted, no planner semantics).
fn parse_pattern_primary(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if is_identifier_candidate(cursor) {
    // Pattern variable, or PERMUTE(...) (a Calcite-base pattern combinator,
    // known-limitation — structurally parsed as identifier + parenthesized
    // comma-separated pattern list, Parser.jj:3337-3346).
    advance(cursor)
    if consume_symbol(cursor, b"(") {
      let mut inner = parse_pattern_expr(cursor, state, source, statement_id)
      while consume_symbol(cursor, b",") {
        inner = parse_pattern_expr(cursor, state, source, statement_id) && inner
      }
      let closed = expect_symbol(cursor, b")", state, source, statement_id, "expected closing PERMUTE parenthesis")
      return inner && closed
    }
    true
  } else if consume_symbol(cursor, b"(") {
    // Group: ( pattern_expr ).
    let inner = parse_pattern_expr(cursor, state, source, statement_id)
    let closed = expect_symbol(cursor, b")", state, source, statement_id, "expected closing pattern group parenthesis")
    inner && closed
  } else if consume_symbol(cursor, b"{") {
    // PatternExclude {- ... -} (Parser.jj:3294-3335, known-limitation).
    if consume_symbol(cursor, b"-") {
      let mut inner_valid = true
      let mut done = false
      while !done {
        if raw_at(cursor) is Some(b"-") && peek_raw(cursor, 1) is Some(b"}") {
          done = true
        } else if raw_at(cursor) is None || raw_at(cursor) is Some(b";") ||
          raw_at(cursor) is Some(b")") {
          done = true
        } else {
          let before = cursor.position
          let factor_ok = parse_pattern_factor(cursor, state, source, statement_id)
          inner_valid = factor_ok && inner_valid
          if cursor.position == before {
            recover_expression(cursor, state, source, statement_id)
            inner_valid = false
            done = true
          }
        }
      }
      if raw_at(cursor) is Some(b"-") { advance(cursor) }
      let closed = expect_symbol(cursor, b"}", state, source, statement_id, "expected } to close pattern exclude")
      inner_valid && closed
    } else {
      let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected - after { in pattern exclude", "pattern-exclude", at, statement_id)
      advance(cursor)
      false
    }
  } else {
    let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected pattern variable, group, or exclude in PATTERN", "pattern", at, statement_id)
    false
  }
}

/// `quantifier := {n} | {n,} | {n,m} | {,m} | + | * | ?` with an optional
/// reluctant `?` suffix (PatternQuantifier, Parser.jj:3314-3317).
fn parse_pattern_quantifier(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  if consume_symbol(cursor, b"{") {
    let current_raw = match raw_at(cursor) { Some(raw) => raw; None => b"" }
    if raw_at(cursor) is Some(b"}") {
      let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected quantifier bounds in {}", "pattern-quantifier", at, statement_id)
      advance(cursor)
      valid = false
    } else if raw_at(cursor) is Some(b",") {
      // {,m}
      advance(cursor)
      let upper_raw = match raw_at(cursor) { Some(raw) => raw; None => b"" }
      if is_positive_integer_raw(upper_raw) {
        advance(cursor)
      } else {
        let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        add_diagnostic(state, "FATHOM-PARSE-002", "expected positive integer quantifier upper bound", "pattern-quantifier", at, statement_id)
        valid = false
      }
      valid = expect_symbol(cursor, b"}", state, source, statement_id, "expected } to close quantifier") && valid
    } else if is_positive_integer_raw(current_raw) {
      advance(cursor)
      if consume_symbol(cursor, b",") {
        if !(raw_at(cursor) is Some(b"}")) {
          let upper_raw = match raw_at(cursor) { Some(raw) => raw; None => b"" }
          if is_positive_integer_raw(upper_raw) {
            advance(cursor)
          } else {
            let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
            add_diagnostic(state, "FATHOM-PARSE-002", "expected positive integer quantifier upper bound", "pattern-quantifier", at, statement_id)
            valid = false
          }
        }
      }
      valid = expect_symbol(cursor, b"}", state, source, statement_id, "expected } to close quantifier") && valid
    } else {
      let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
      add_diagnostic(state, "FATHOM-PARSE-002", "expected positive integer quantifier bound", "pattern-quantifier", at, statement_id)
      valid = false
      advance(cursor)
    }
  } else if consume_symbol(cursor, b"+") || consume_symbol(cursor, b"*") || consume_symbol(cursor, b"?") {
    ()
  }
  // Reluctant quantifier suffix: an additional `?` (PatternQuantifier
  // reluctant flag, Parser.jj:3314-3317).
  ignore(consume_symbol(cursor, b"?"))
  valid
}
