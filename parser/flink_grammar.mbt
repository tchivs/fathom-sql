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

// Minimal ALTER TABLE body (fleshed out in 11-03 Task 2): RENAME TO / SET
// forms parse; the wider ADD/DROP/MODIFY column clause set is beyond this
// wave's enumerated surface (must-have truths cover CATALOG/DATABASE/VIEW/
// FUNCTION and DROP TABLE).
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

// Minimal CREATE VIEW body (fleshed out in 11-03 Task 2): VIEW + name +
// optional field list + optional COMMENT + AS query.
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

// Minimal CREATE FUNCTION body (fleshed out in 11-03 Task 2): FUNCTION +
// name + AS 'class' + optional LANGUAGE.
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

// Minimal CREATE TABLE body (fleshed out in 11-03 Tasks 3-4): TABLE + name
// + optional parenthesized column body. The full four-column dispatch,
// WATERMARK single-instance enforcement, constraints, and the table-level
// clause sequence [COMMENT][DISTRIBUTED][PARTITIONED BY][WITH][LIKE|AS] land
// in Tasks 3-4.
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
    valid = parse_flink_create_table_body(cursor, state, source, statement_id) && valid
  }
  valid
}

// Minimal column body (fleshed out in 11-03 Task 3).
fn parse_flink_create_table_body(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = expect_symbol(cursor, b"(", state, source, statement_id, "expected ( after CREATE TABLE name")
  let mut any = false
  let mut done = false
  while !done {
    if raw_at(cursor) is Some(b")") {
      done = true
    } else {
      any = true
      valid = parse_flink_typed_column(cursor, state, source, statement_id) && valid
      if consume_symbol(cursor, b",") {
        if raw_at(cursor) is Some(b")") { done = true }
      } else {
        done = true
      }
    }
  }
  if !any {
    let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected at least one column definition", "column", make_span(source, at, at), statement_id)
    valid = false
  }
  valid = expect_symbol(cursor, b")", state, source, statement_id, "expected closing table body parenthesis") && valid
  valid
}

// Minimal typed column (fleshed out in 11-03 Task 3).
fn parse_flink_typed_column(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  if is_identifier_candidate(cursor) {
    advance(cursor)
  } else {
    let at = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
    add_diagnostic(state, "FATHOM-PARSE-002", "expected column name", "identifier", at, statement_id)
    valid = false
  }
  valid = parse_flink_data_type(cursor, state, source, statement_id) && valid
  valid
}
