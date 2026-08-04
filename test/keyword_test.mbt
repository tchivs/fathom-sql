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
    (b"INSERT", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"UPDATE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"DELETE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"OVERWRITE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"VALUES", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"SET", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"WHEN", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"THEN", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"DEFAULT", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"CREATE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"TABLE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"INDEX", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"IF", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"EXISTS", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"KEY", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"DUPLICATE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"UNIQUE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"DISTRIBUTED", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"AUTO", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"RANGE", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"LIST", "reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"),
    (b"MERGE", "reserved", "4.x", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/MERGE-INTO/ (4.x-doc-only statement per D-09; not in the official reserved list; DorisFeature::MergeInto 4.x)"),
    (b"BUCKETS", "non-reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (DISTRIBUTED BY ... BUCKETS clause; absent from the official reserved list)"),
    (b"PROPERTIES", "non-reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (PROPERTIES clause; absent from the official reserved list)"),
    (b"COMMENT", "non-reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (COMMENT clause; absent from the official reserved list)"),
    (b"AGGREGATE", "non-reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (AGGREGATE key model; absent from the official reserved list)"),
    (b"ENGINE", "non-reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (ENGINE = clause; absent from the official reserved list)"),
    (b"VIEW", "non-reserved", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/view/CREATE-VIEW/ (CREATE VIEW statement; absent from the official reserved list)"),
    (b"MATCHED", "contextual", "4.x", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/MERGE-INTO/ (WHEN MATCHED clause; absent from the official reserved list)"),
    (b"LABEL", "contextual", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/INSERT/ (WITH LABEL clause; absent from the official reserved list)"),
    (b"HASH", "contextual", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (DISTRIBUTED BY HASH clause; absent from the official reserved list)"),
    (b"RANDOM", "contextual", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (DISTRIBUTED BY RANDOM clause; absent from the official reserved list)"),
    (b"LESS", "contextual", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (VALUES LESS THAN clause; absent from the official reserved list)"),
    (b"THAN", "contextual", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (VALUES LESS THAN clause; absent from the official reserved list)"),
    (b"PARTITIONS", "contextual", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (partition-list clause; absent from the official reserved list)"),
    (b"TEMPORARY", "contextual", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (CREATE TEMPORARY TABLE modifier; absent from the official reserved list)"),
    (b"EXTERNAL", "contextual", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (CREATE EXTERNAL TABLE modifier; absent from the official reserved list)"),
    (b"MATERIALIZED", "contextual", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/sync-materialized-view/CREATE-MATERIALIZED-VIEW/ (CREATE MATERIALIZED VIEW word; absent from the official reserved list)"),
    (b"AUTO_INCREMENT", "contextual", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (column option; absent from the official reserved list)"),
    (b"CURRENT_TIMESTAMP", "contextual", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (DEFAULT/ON UPDATE value; absent from the official reserved list)"),
    (b"GENERATED", "contextual", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (generated-column word; absent from the official reserved list)"),
    (b"ALWAYS", "contextual", "2.1", "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (generated-column word; absent from the official reserved list)"),
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

test "non_reserved_and_contextual_dml_ddl_words_are_usable_identifiers" {
  // Research Pitfall 2: grammar words absent from the official reserved list
  // stay usable as unquoted identifiers, aliases, and property keys (D-14).
  let words = [
    b"BUCKETS", b"PROPERTIES", b"COMMENT", b"AGGREGATE", b"ENGINE",
    b"VIEW", b"MATCHED", b"LABEL", b"HASH", b"RANDOM", b"LESS", b"THAN",
    b"PARTITIONS", b"TEMPORARY", b"EXTERNAL", b"MATERIALIZED",
    b"AUTO_INCREMENT", b"CURRENT_TIMESTAMP", b"GENERATED", b"ALWAYS",
    b"TABLET",
  ]
  for word in words {
    for profile in ["2.1", "3.x", "4.x"] {
      let projection = parse_kw(b"SELECT " + word + b" FROM t", profile, "strict")
      assert_true(projection.valid)
      assert_eq(projection.diagnostics.length(), 0)
      assert_eq(@printer.print_result(projection), b"SELECT " + word + b" FROM t")
      let alias = parse_kw(b"SELECT a AS " + word + b" FROM t", profile, "strict")
      assert_true(alias.valid)
      assert_eq(alias.diagnostics.length(), 0)
      let property = parse_kw(
        b"CREATE TABLE t (a INT) PROPERTIES (" + word + b" = \"1\")",
        profile,
        "strict",
      )
      assert_true(property.valid)
      assert_eq(property.diagnostics.length(), 0)
      let quoted = parse_kw(b"SELECT `" + word + b"` FROM t", profile, "strict")
      assert_true(quoted.valid)
      assert_eq(quoted.diagnostics.length(), 0)
      assert_eq(@printer.print_result(quoted), b"SELECT `" + word + b"` FROM t")
    }
  }
}

test "reserved_dml_ddl_words_require_backticks_as_identifiers" {
  // Reserved words must be rejected as unquoted identifiers (DORIS-PARSE-002)
  // and accepted backticked; the shared clause set is untouched.
  let words = [
    b"INSERT", b"UPDATE", b"DELETE", b"OVERWRITE", b"VALUES", b"SET",
    b"WHEN", b"THEN", b"DEFAULT", b"CREATE", b"TABLE", b"INDEX", b"IF",
    b"EXISTS", b"KEY", b"DUPLICATE", b"UNIQUE", b"DISTRIBUTED", b"AUTO",
    b"RANGE", b"LIST", b"MERGE",
  ]
  for word in words {
    for profile in ["2.1", "3.x", "4.x"] {
      let alias = parse_kw(b"SELECT a AS " + word + b" FROM t", profile, "strict")
      assert_true(!alias.valid)
      assert_true(alias.diagnostics.any(d => d.code == "DORIS-PARSE-002"))
      assert_eq(@printer.print_result(alias), b"SELECT a AS " + word + b" FROM t")
      let property = parse_kw(
        b"CREATE TABLE t (a INT) PROPERTIES (" + word + b" = \"1\")",
        profile,
        "strict",
      )
      assert_true(!property.valid)
      assert_true(property.diagnostics.any(d => d.code == "DORIS-PARSE-002"))
      assert_eq(
        @printer.print_result(property),
        b"CREATE TABLE t (a INT) PROPERTIES (" + word + b" = \"1\")",
      )
      let quoted = parse_kw(b"SELECT `" + word + b"` FROM t", profile, "strict")
      assert_true(quoted.valid)
      assert_eq(quoted.diagnostics.length(), 0)
      assert_eq(@printer.print_result(quoted), b"SELECT `" + word + b"` FROM t")
    }
  }
}

test "version_invalid_keyword_use_emits_006_through_feature_gates" {
  // MERGE is 4.x-doc-only (D-09): 2.1/3.x must emit DORIS-PARSE-006 through
  // the DorisFeature::MergeInto gate — never silent acceptance (D-15).
  let merge = b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.v = s.v"
  for profile in ["2.1", "3.x"] {
    let result = parse_kw(merge, profile, "strict")
    assert_true(!result.valid)
    assert_true(result.diagnostics.any(d => d.code == "DORIS-PARSE-006"))
    assert_eq(@printer.print_result(result), merge)
    assert_true(result.all_spans_in_bounds())
  }
  let merge_ok = parse_kw(merge, "4.x", "strict")
  assert_true(merge_ok.valid)
  assert_eq(merge_ok.diagnostics.length(), 0)
  // QUALIFY and TABLET are 3.x-gated words (DorisFeature rows).
  let qualify = parse_kw(b"SELECT a FROM t QUALIFY a = 1", "2.1", "strict")
  assert_true(!qualify.valid)
  assert_true(qualify.diagnostics.any(d => d.code == "DORIS-PARSE-006"))
  let tablet = parse_kw(b"SELECT a FROM t TABLET (1)", "2.1", "strict")
  assert_true(!tablet.valid)
  assert_true(tablet.diagnostics.any(d => d.code == "DORIS-PARSE-006"))
  // MATCHED carries "4.x" introduced_profile metadata but no standalone word
  // gate: outside the (4.x-gated) MERGE production it remains an identifier —
  // the word-level classification gate and the DorisFeature production gate
  // are distinct layers.
  let matched = parse_kw(b"SELECT matched FROM t", "2.1", "strict")
  assert_true(matched.valid)
  assert_eq(matched.diagnostics.length(), 0)
  assert_eq(@printer.print_result(matched), b"SELECT matched FROM t")
}

test "grammar_words_still_work_in_clause_position" {
  // Every classified DML/DDL word keeps its clause-keyword role inside its own
  // statement family (02-01/02-02 behavior) — classification only affects
  // identifier acceptance elsewhere.
  let raws = [
    b"INSERT INTO t VALUES (1, DEFAULT)",
    b"UPDATE t SET c1 = 1 WHERE id = 1",
    b"DELETE FROM t WHERE id = 1",
    b"DELETE FROM t PARTITIONS (p1, p2) WHERE id = 1",
    b"INSERT INTO t WITH LABEL lab VALUES (1)",
    b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.v = s.v",
    b"CREATE TABLE t (a INT) ENGINE = OLAP DUPLICATE KEY (a) COMMENT 'c' DISTRIBUTED BY HASH (a) BUCKETS 10 PROPERTIES (\"k\" = \"v\")",
    b"CREATE TABLE t (a INT) DISTRIBUTED BY RANDOM BUCKETS 10",
    b"CREATE TABLE t (a INT) PARTITION BY RANGE (a) (PARTITION p1 VALUES LESS THAN (10))",
    b"CREATE TABLE t (a INT) AUTO PARTITION BY LIST (a) ()",
    b"CREATE TABLE t (a INT, c1 INT AUTO_INCREMENT(1), c2 DATETIME DEFAULT CURRENT_TIMESTAMP, c3 BIGINT GENERATED ALWAYS AS (a * 2))",
    b"CREATE VIEW v AS SELECT 1",
    b"CREATE INDEX idx ON t (a) USING INVERTED",
    b"CREATE MATERIALIZED VIEW mv AS SELECT a FROM t",
    b"CREATE TABLE t2 LIKE t1",
    b"CREATE TABLE t2 AS SELECT a FROM t",
  ]
  for raw in raws {
    let result = parse_kw(raw, "4.x", "strict")
    assert_true(result.valid)
    assert_eq(result.diagnostics.length(), 0)
    assert_eq(@printer.print_result(result), raw)
    assert_true(result.all_spans_in_bounds())
  }
}
