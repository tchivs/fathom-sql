/// Fathom Flink completion tests (TOOL-02, D-02). The Flink completion
/// surface is exercised through the same `complete` facade the LSP and wire
/// adapters use: bounded (<= MAX_CANDIDATES=32), profile-gated per
/// introduced_profile (flink-1.20.5 < flink-2.1.3 < flink-2.3.0),
/// context-arm-driven, source-range-safe, and strictly explicit-selection
/// (unknown profile -> UnknownProfile, no Doris fallback, D-01/D-02).

fn labels_contain(items : Array[CompletionItem], label : String) -> Bool {
  let mut found = false
  for item in items {
    if item.label == label { found = true }
  }
  found
}

/// The statement-start verb set is covered under flink-2.3.0 (D-02): the
/// reserved clause verbs plus the D-02 statement verbs added as NonReserved
/// rows, bounded by MAX_CANDIDATES with the neutral detail.
test "flink_statement_start_returns_verb_set" {
  let result = match complete(b"", "flink", "flink-2.3.0", 0) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!result.is_incomplete)
  assert_true(result.items.length() > 0)
  // MAX_CANDIDATES = 32 (completion.mbt const; private to the package, so
  // the bound is pinned here as the observable contract, D-02).
  assert_true(result.items.length() <= 32)
  for verb in [b"SELECT", b"WITH", b"INSERT", b"UPDATE", b"DELETE", b"CREATE",
    b"SET", b"VALUES", b"ALTER", b"DROP", b"SHOW", b"DESCRIBE", b"EXPLAIN",
    b"ANALYZE", b"USE", b"RESET"] {
    assert_true(labels_contain(result.items, @utf8.decode_lossy(verb)))
  }
  for item in result.items {
    assert_eq(item.detail, "SQL syntax keyword")
  }
}

/// A case-insensitive prefix reaches the matching verb through the existing
/// prefix_matches pipeline (D-02).
test "flink_prefix_matches_select" {
  let result = match complete(b"SEL", "flink", "flink-2.3.0", 3) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(labels_contain(result.items, "SELECT"))
  for item in result.items {
    assert_eq(item.new_text, item.label)
  }
}

/// Unknown/unsupported flink profiles reject with the structured
/// UnknownProfile error — never a Doris fallback and never an empty-silent
/// success (D-01/D-02, T-13-02-05). A Doris-shaped profile id under flink is
/// also rejected (exact-match FlinkProfile::from_id, T-10-01).
test "flink_unknown_profile_rejects_no_fallback" {
  let unknown = complete(b"", "flink", "flink-9.9.9", 0)
  assert_true(unknown is Err(UnknownProfile(profile_id="flink-9.9.9")))
  let doris_shape = complete(b"", "flink", "4.x", 0)
  assert_true(doris_shape is Err(UnknownProfile(profile_id="4.x")))
  let unknown_dialect = complete(b"", "mysql", "4.x", 0)
  assert_true(unknown_dialect is Err(UnknownDialect(dialect_id="mysql")))
  // cursor_byte is bounds-checked before any work (T-13-02-06).
  let bad_cursor = complete(b"SEL", "flink", "flink-2.3.0", 99)
  assert_true(bad_cursor is Err(InvalidCursor(cursor=99, source_length=3)))
}

/// Doris statement-start output is byte-identical to the pre-change surface
/// (PARITY-01): the shared clause-keyword set, with no Flink statement verb
/// leaking into a Doris request (T-13-02-07).
test "doris_statement_start_output_unchanged" {
  let result = match complete(b"", "doris", "4.x", 0) {
    Ok(result) => result
    Err(_) => panic()
  }
  let clause_words = [b"SELECT", b"WITH", b"FROM", b"WHERE", b"GROUP", b"HAVING",
    b"ORDER", b"LIMIT", b"JOIN", b"UNION", b"QUALIFY", b"WINDOW", b"INTO", b"ON", b"USING"]
  assert_eq(result.items.length(), clause_words.length())
  for word in clause_words {
    assert_true(labels_contain(result.items, @utf8.decode_lossy(word)))
  }
  assert_true(!labels_contain(result.items, "ALTER"))
  assert_true(!labels_contain(result.items, "DROP"))
  assert_true(!labels_contain(result.items, "SHOW"))
  assert_true(!labels_contain(result.items, "TUMBLE"))
  for item in result.items {
    assert_eq(item.detail, "SQL syntax keyword")
  }
}

/// The ddl-header context fires after CREATE/DROP/ALTER and offers the DDL
/// nouns (CATALOG/DATABASE/FUNCTION/TABLE/VIEW) (D-02).
test "flink_ddl_header_context" {
  let result = match complete(b"CREATE ", "flink", "flink-2.3.0", 7) {
    Ok(result) => result
    Err(_) => panic()
  }
  for word in [b"CATALOG", b"DATABASE", b"FUNCTION", b"TABLE", b"VIEW"] {
    assert_true(labels_contain(result.items, @utf8.decode_lossy(word)))
  }
  let drop_result = match complete(b"DROP ", "flink", "flink-2.3.0", 5) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(labels_contain(drop_result.items, "TABLE"))
  assert_true(labels_contain(drop_result.items, "VIEW"))
  assert_true(labels_contain(drop_result.items, "CATALOG"))
}

/// The watermark context fires after WATERMARK and offers the column-body
/// clause words (WATERMARK/PRIMARY/COMPUTED/METADATA); the partitioned-by
/// context fires after PARTITIONED BY and offers the partition/create-table
/// continuation words (D-02).
test "flink_watermark_partitioned_context" {
  let wm = match complete(b"CREATE TABLE t (id INT, WATERMARK ", "flink", "flink-2.3.0", 34) {
    Ok(result) => result
    Err(_) => panic()
  }
  for word in [b"WATERMARK", b"PRIMARY", b"COMPUTED", b"METADATA"] {
    assert_true(labels_contain(wm.items, @utf8.decode_lossy(word)))
  }
  let pb = match complete(b"CREATE TABLE t (id INT) PARTITIONED BY ", "flink", "flink-2.3.0", 39) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(labels_contain(pb.items, "WITH"))
  assert_true(labels_contain(pb.items, "PRIMARY"))
  assert_true(labels_contain(pb.items, "WATERMARK"))
}

/// The window-tvf context fires at the FROM/JOIN table position and offers
/// the window TVF function names TUMBLE/HOP/CUMULATE/SESSION (D-02).
test "flink_window_tvf_context" {
  let result = match complete(b"SELECT * FROM ", "flink", "flink-2.3.0", 14) {
    Ok(result) => result
    Err(_) => panic()
  }
  for word in [b"TUMBLE", b"HOP", b"CUMULATE", b"SESSION"] {
    assert_true(labels_contain(result.items, @utf8.decode_lossy(word)))
  }
  // The from-clause continuations remain available (JOIN).
  assert_true(labels_contain(result.items, "JOIN"))
}

/// The match-recognize context fires after the MATCH_RECOGNIZE clause words
/// and is scoped to the reserved clause words already in the table
/// (PATTERN/DEFINE/MEASURES/MATCH_NUMBER — RESEARCH OQ3 RESOLVED; sub-clause
/// completion deferred to TOOL-FUTURE-01).
test "flink_match_recognize_context" {
  let result = match complete(b"SELECT * FROM t MATCH_RECOGNIZE ", "flink", "flink-2.3.0", 32) {
    Ok(result) => result
    Err(_) => panic()
  }
  for word in [b"PATTERN", b"DEFINE", b"MEASURES", b"MATCH_NUMBER"] {
    assert_true(labels_contain(result.items, @utf8.decode_lossy(word)))
  }
}
