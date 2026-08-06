/// Per-dialect keyword classification (DIALECT-02). Every classification query
/// takes a DialectContext and selects its rows by `context.dialect` and
/// nothing else (Pitfall 7): the two row arrays are independent module-level
/// data with no shared mutable state, so a Flink word can never affect Doris
/// acceptance and vice versa. No parameterless public query survives
/// (Pitfall 1).

/// Three-layer keyword classification (D-14): reserved words require backticks
/// as identifiers, non-reserved grammar words stay usable as unquoted
/// identifiers, and contextual words are clause-only (identifiers elsewhere).
/// Name preserved per D-05 (moved from token/token.mbt).
pub enum ClassificationKind {
  Reserved
  NonReserved
  Contextual
} derive(Eq, @debug.Debug)

/// One classified keyword row: word spelling, classification, the released
/// profile that introduced the classification-relevant usage, and the official
/// docs source row. Every word the parser productions use has a row
/// (D-13/D-16 single source of truth). This is the ClassificationEntry shape
/// from token/token.mbt renamed to the dialect-neutral KeywordEntry (D-05
/// keeps the kind name; the row type is shared by both dialects).
pub struct KeywordEntry {
  pub word : Bytes
  pub classification : ClassificationKind
  pub introduced_profile : String
  pub source : String
} derive(Eq, @debug.Debug)

/// ASCII case-insensitive byte compare (moved verbatim from
/// token/token.mbt:221-236): the shared lookup algorithm for every dialect's
/// row array.
fn token_bytes_equal_ci(actual : Bytes, expected : Bytes) -> Bool {
  if actual.length() != expected.length() {
    false
  } else {
    let mut index = 0
    let mut equal = true
    while index < actual.length() {
      let left = actual[index].to_int()
      let right = expected[index].to_int()
      let folded_left = if left >= 97 && left <= 122 { left - 32 } else { left }
      let folded_right = if right >= 97 && right <= 122 { right - 32 } else { right }
      if folded_left != folded_right { equal = false }
      index = index + 1
    }
    equal
  }
}

/// The dialect's classification rows, selected by context.dialect and nothing
/// else (Pitfall 7): two independent module-level arrays, no shared mutable
/// state (DIALECT-02 structural independence).
fn classification_rows_for(context : DialectContext) -> Array[KeywordEntry] {
  match context.dialect {
    Dialect::Doris => doris_classification_rows
    Dialect::Flink => flink_classification_rows
  }
}

/// Case-insensitive lookup of a word's classification row (D-13/D-14).
pub fn classification_of(context : DialectContext, raw : Bytes) -> KeywordEntry? {
  let rows = classification_rows_for(context)
  let mut index = 0
  while index < rows.length() {
    let entry = rows[index]
    if token_bytes_equal_ci(raw, entry.word) {
      return Some(entry)
    }
    index = index + 1
  }
  None
}

/// All rows for the context's dialect (replaces token's
/// classification_entry_count/classification_entry_at accessors used by
/// completion and the keyword audit tests).
pub fn classification_entries(context : DialectContext) -> Array[KeywordEntry] {
  classification_rows_for(context)
}

/// Released-profile clause boundaries shared by parser contexts.
pub fn is_clause_keyword(context : DialectContext, raw : Bytes) -> Bool {
  token_bytes_equal_ci(raw, b"SELECT") || token_bytes_equal_ci(raw, b"WITH") ||
    token_bytes_equal_ci(raw, b"FROM") || token_bytes_equal_ci(raw, b"WHERE") ||
    token_bytes_equal_ci(raw, b"GROUP") || token_bytes_equal_ci(raw, b"HAVING") ||
    token_bytes_equal_ci(raw, b"ORDER") || token_bytes_equal_ci(raw, b"LIMIT") ||
    token_bytes_equal_ci(raw, b"JOIN") || token_bytes_equal_ci(raw, b"UNION") ||
    token_bytes_equal_ci(raw, b"QUALIFY") || token_bytes_equal_ci(raw, b"WINDOW") ||
    token_bytes_equal_ci(raw, b"INTO") || token_bytes_equal_ci(raw, b"ON") ||
    token_bytes_equal_ci(raw, b"USING")
}

/// Released-profile reserved words: table-backed (D-14) — true iff a Reserved
/// row exists (case-insensitive). Answers match the Phase 1 clause/operator
/// set exactly; TABLET remains contextual.
pub fn is_reserved_word(context : DialectContext, raw : Bytes) -> Bool {
  match classification_of(context, raw) {
    Some(entry) => entry.classification is Reserved
    None => false
  }
}

pub fn is_unquoted_identifier(context : DialectContext, raw : Bytes) -> Bool {
  !is_reserved_word(context, raw)
}

fn doris_test_context() -> DialectContext {
  {
    dialect: Dialect::Doris,
    profile_id: "4.x",
    exact_release: "4.x",
    feature_introduction: "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT",
  }
}

test "released_identifier_classification_is_case_insensitive_and_contextual" {
  let context = doris_test_context()
  for raw in [b"SELECT", b"with", b"As", b"AND", b"or", b"FROM", b"window"] {
    assert_true(is_reserved_word(context, raw))
    assert_true(!is_unquoted_identifier(context, raw))
  }
  assert_true(is_clause_keyword(context, b"SeLeCt"))
  assert_true(is_clause_keyword(context, b"FrOm"))
  assert_true(!is_clause_keyword(context, b"AND"))
  assert_true(!is_reserved_word(context, b"tablet"))
  assert_true(is_unquoted_identifier(context, b"tablet"))
  assert_true(is_unquoted_identifier(context, b"user_name"))
}

test "classification_is_dialect_independent_and_flink_rows_are_empty" {
  let doris = doris_test_context()
  let flink = { dialect: Dialect::Flink, profile_id: "flink-2.3.0", exact_release: "flink-2.3.0", feature_introduction: "" }
  // The same word classified under Doris stays classified under Doris, while
  // the Flink table is intentionally empty in Phase 9 (DIALECT-02; Phase 10
  // fills it) — no cross-dialect leakage, no global union.
  assert_true(classification_of(doris, b"SELECT") is Some(_))
  assert_true(classification_of(flink, b"SELECT") is None)
  assert_eq(classification_entries(flink).length(), 0)
  assert_true(!is_reserved_word(flink, b"SELECT"))
  assert_true(is_unquoted_identifier(flink, b"SELECT"))
}
