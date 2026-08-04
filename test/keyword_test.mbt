/// Keyword classification tests (DORIS-04): three-layer table behavior,
/// version-gate metadata, TSV correspondence, and cross-profile audit.

fn parse_kw(raw : Bytes, profile : String, mode : String) -> @api.ParseResult {
  match @api.parse_with_ids(raw, profile, mode) {
    Ok(result) => result
    Err(_) => panic()
  }
}

fn classification_id(kind : @token.ClassificationKind) -> String {
  match kind {
    Reserved => "reserved"
    NonReserved => "non-reserved"
    Contextual => "contextual"
  }
}

fn bytes_equal_ci(left : Bytes, right : Bytes) -> Bool {
  if left.length() != right.length() {
    false
  } else {
    let mut index = 0
    let mut equal = true
    while index < left.length() {
      let l = left[index].to_int()
      let r = right[index].to_int()
      let folded_l = if l >= 97 && l <= 122 { l - 32 } else { l }
      let folded_r = if r >= 97 && r <= 122 { r - 32 } else { r }
      if folded_l != folded_r { equal = false }
      index = index + 1
    }
    equal
  }
}

/// Embedded mirror of corpus/keywords.tsv (D-16): word, classification,
/// introduced_profile, source. The correspondence test below asserts exact
/// parity with the runtime classification table, so the checked-in audit
/// artifact cannot drift from what the parser enforces.
fn tsv_rows() -> Array[(Bytes, String, String, String)] {
  [
    (b"SELECT", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"WITH", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"FROM", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"WHERE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"GROUP", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"HAVING", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"ORDER", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"LIMIT", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"JOIN", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"UNION", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"QUALIFY", "reserved", "3.x", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/ (QUALIFY clause; DorisFeature::Qualify 3.x; absent from the official reserved list)"),
    (b"WINDOW", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/ (Phase 1 clause/recovery word; absent from the official reserved list)"),
    (b"INTO", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"ON", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"USING", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"AS", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"AND", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"OR", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"NOT", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"IN", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"LIKE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"REGEXP", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"IS", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"NULL", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"TRUE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"FALSE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"RECURSIVE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/ (Phase 1 clause/recovery word; absent from the official reserved list)"),
    (b"BY", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"GROUPING", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/ (Phase 1 clause/recovery word; absent from the official reserved list)"),
    (b"SETS", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"ROLLUP", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/ (Phase 1 clause/recovery word; absent from the official reserved list)"),
    (b"CUBE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"ALL", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"DISTINCT", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"DISTINCTROW", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/ (Phase 1 clause/recovery word; absent from the official reserved list)"),
    (b"EXCEPT", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"INNER", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"LEFT", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"RIGHT", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"FULL", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"CROSS", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"NATURAL", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"OUTER", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"PARTITION", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"SAMPLE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/ (Phase 1 clause/recovery word; absent from the official reserved list)"),
    (b"TABLESAMPLE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"OVER", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/ (Phase 1 clause/recovery word; absent from the official reserved list)"),
    (b"ASC", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"DESC", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"NULLS", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/ (Phase 1 clause/recovery word; absent from the official reserved list)"),
    (b"FIRST", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/ (Phase 1 clause/recovery word; absent from the official reserved list)"),
    (b"LAST", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/ (Phase 1 clause/recovery word; absent from the official reserved list)"),
    (b"ROWS", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"RANGE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"GROUPS", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/ (Phase 1 clause/recovery word; absent from the official reserved list)"),
    (b"BETWEEN", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"CURRENT", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"ROW", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"UNBOUNDED", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"PRECEDING", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"FOLLOWING", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"OFFSET", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/ (Phase 1 clause/recovery word; absent from the official reserved list)"),
    (b"OUTFILE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"TABLET", "contextual", "3.x", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/ (TABLET clause; DorisFeature::Tablet 3.x; contextual per D-14 although listed in the official reserved keywords)"),
  ]
}

test "classification_table_mirrors_embedded_tsv_rows" {
  // Forward: every embedded TSV row resolves through classification_of with
  // matching classification / introduced_profile / source.
  for row in tsv_rows() {
    match @token.classification_of(row.0) {
      Some(entry) => {
        assert_eq(classification_id(entry.classification), row.1)
        assert_eq(entry.introduced_profile, row.2)
        assert_eq(entry.source, row.3)
      }
      None => panic()
    }
  }
  // Reverse: every runtime row is represented in the embedded TSV table, so
  // the checked-in audit artifact cannot drift from the runtime table.
  let mut index = 0
  while index < @token.classification_entry_count() {
    let entry = match @token.classification_entry_at(index) {
      Some(entry) => entry
      None => panic()
    }
    let mut found = false
    for row in tsv_rows() {
      if bytes_equal_ci(entry.word, row.0) {
        found = true
        assert_eq(classification_id(entry.classification), row.1)
        assert_eq(entry.introduced_profile, row.2)
        assert_eq(entry.source, row.3)
      }
    }
    assert_true(found)
    index = index + 1
  }
}

test "classification_of_is_case_insensitive_and_returns_metadata" {
  let select = match @token.classification_of(b"SELECT") {
    Some(entry) => entry
    None => panic()
  }
  assert_eq(classification_id(select.classification), "reserved")
  assert_eq(select.introduced_profile, "2.1")
  assert_true(select.source.has_prefix("https://doris.apache.org/"))
  let mixed = match @token.classification_of(b"seLeCt") {
    Some(entry) => entry
    None => panic()
  }
  assert_eq(mixed.word, b"SELECT")
  assert_eq(mixed, select)
  let tablet = match @token.classification_of(b"tablet") {
    Some(entry) => entry
    None => panic()
  }
  assert_eq(classification_id(tablet.classification), "contextual")
  assert_eq(tablet.introduced_profile, "3.x")
  assert_true(@token.classification_of(b"not_a_keyword") is None)
}

test "phase1_reserved_answers_are_preserved_by_the_table" {
  // Full Phase 1 reserved set re-encoded with identical answers: every word
  // the old clause/operator set reserved must still be reserved, and TABLET
  // stays contextual (D-14, existing classification tests pass unchanged).
  let phase1_reserved = [
    b"SELECT", b"WITH", b"FROM", b"WHERE", b"GROUP", b"HAVING", b"ORDER",
    b"LIMIT", b"JOIN", b"UNION", b"QUALIFY", b"WINDOW", b"INTO", b"ON",
    b"USING", b"AS", b"AND", b"OR", b"NOT", b"IN", b"LIKE", b"REGEXP",
    b"IS", b"NULL", b"TRUE", b"FALSE", b"RECURSIVE", b"BY", b"GROUPING",
    b"SETS", b"ROLLUP", b"CUBE", b"ALL", b"DISTINCT", b"DISTINCTROW",
    b"EXCEPT", b"INNER", b"LEFT", b"RIGHT", b"FULL", b"CROSS", b"NATURAL",
    b"OUTER", b"PARTITION", b"SAMPLE", b"TABLESAMPLE", b"OVER", b"ASC",
    b"DESC", b"NULLS", b"FIRST", b"LAST", b"ROWS", b"RANGE", b"GROUPS",
    b"BETWEEN", b"CURRENT", b"ROW", b"UNBOUNDED", b"PRECEDING",
    b"FOLLOWING", b"OFFSET", b"OUTFILE",
  ]
  for raw in phase1_reserved {
    assert_true(@token.is_reserved_word(raw))
    assert_true(!@token.is_unquoted_identifier(raw))
  }
  for raw in [b"select", b"winDow", b"As", b"SeLeCt"] {
    assert_true(@token.is_reserved_word(raw))
  }
  assert_true(!@token.is_reserved_word(b"TABLET"))
  assert_true(@token.is_unquoted_identifier(b"TABLET"))
  assert_true(@token.is_unquoted_identifier(b"user_name"))
}

test "dml_words_do_not_enter_the_shared_clause_set" {
  // Research Pitfall 3: is_clause_keyword is the shared recovery boundary
  // (recover_expression / is_projection_boundary / parse_projection_alias).
  // DML/DDL words must stay out so SELECT recovery is byte-for-byte unchanged.
  for raw in [
    b"VALUES", b"SET", b"WHEN", b"OVERWRITE", b"MERGE", b"INSERT",
    b"UPDATE", b"DELETE", b"MATCHED", b"THEN", b"CREATE", b"BUCKETS",
  ] {
    assert_true(!@token.is_clause_keyword(raw))
  }
}
