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

/// Release-order rank for the pinned Flink profile ids
/// (flink-1.20.5 < flink-2.1.3 < flink-2.3.0, D-02). A row introduced in a
/// later release must be ABSENT under earlier profiles; unknown ids return
/// None so an unknown/unsupported profile id never leaks rows (Pitfall 6).
fn flink_release_rank(profile_id : String) -> Int? {
  match profile_id {
    "flink-1.20.5" => Some(0)
    "flink-2.1.3" => Some(1)
    "flink-2.3.0" => Some(2)
    _ => None
  }
}

/// True iff the row's introduced_profile is <= the selected Flink profile in
/// release order — the per-release gate for Flink keyword visibility
/// (T-10-13). Doris rows are never routed through this filter (Pitfall 4).
fn flink_row_visible(row : KeywordEntry, context : DialectContext) -> Bool {
  match (flink_release_rank(row.introduced_profile), flink_release_rank(context.profile_id)) {
    (Some(required), Some(selected)) => required <= selected
    _ => false
  }
}

/// The dialect's classification rows, selected by context.dialect (Pitfall 7):
/// two independent module-level arrays, no shared mutable state (DIALECT-02
/// structural independence). Doris rows are selected by context.dialect and
/// NOTHING else; Flink rows are additionally filtered by
/// `introduced_profile` <= the selected profile in release order
/// flink-1.20.5 < flink-2.1.3 < flink-2.3.0, so a 2.1.3-introduced word is
/// ABSENT under flink-1.20.5 and a 2.3.0-introduced word under both 2.1.3 and
/// 1.20.5 (T-10-13).
fn classification_rows_for(context : DialectContext) -> Array[KeywordEntry] {
  match context.dialect {
    Dialect::Doris => doris_classification_rows
    Dialect::Flink => {
      let rows : Array[KeywordEntry] = []
      for row in flink_classification_rows {
        if flink_row_visible(row, context) {
          rows.push(row)
        }
      }
      rows
    }
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

fn flink_test_context(profile_id : String) -> DialectContext {
  { dialect: Dialect::Flink, profile_id: profile_id, exact_release: profile_id, feature_introduction: "" }
}

fn flink_2_3_0_context() -> DialectContext {
  flink_test_context("flink-2.3.0")
}

fn flink_2_1_3_context() -> DialectContext {
  flink_test_context("flink-2.1.3")
}

fn flink_1_20_5_context() -> DialectContext {
  flink_test_context("flink-1.20.5")
}

/// True iff the word has a Reserved row under the context (D-14 reserved-word
/// gate). Helper used by the release-aware independence test.
fn classification_is_reserved(context : DialectContext, raw : Bytes) -> Bool {
  match classification_of(context, raw) {
    Some(entry) => entry.classification is Reserved
    None => false
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

test "classification_is_dialect_independent_and_release_aware" {
  let doris = doris_test_context()
  let flink_230 = flink_2_3_0_context()
  let flink_213 = flink_2_1_3_context()
  let flink_120 = flink_1_20_5_context()
  // Flink rows are populated per release (10-03, RESEARCH Open Question 3
  // RESOLVED) with release-grammar provenance — never empty after this plan
  // (probe FLINK-01 empty).
  assert_true(classification_entries(flink_230).length() > 0)
  // Version-sensitive words classify Reserved under the profiles that
  // introduced them: VARIANT and QUALIFY are 2.1.3-delta reserved words.
  assert_true(classification_is_reserved(flink_230, b"VARIANT"))
  assert_true(classification_is_reserved(flink_213, b"VARIANT"))
  assert_true(classification_is_reserved(flink_213, b"QUALIFY"))
  // The flink-1.20.5 regression profile sees NEITHER word (T-10-13): the
  // profile-aware filter keeps 2.1.3-introduced rows ABSENT under 1.20.5.
  assert_true(classification_of(flink_120, b"VARIANT") is None)
  assert_true(classification_of(flink_120, b"QUALIFY") is None)
  // A 2.3.0-introduced word is ABSENT under both 2.1.3 and 1.20.5.
  assert_true(classification_of(flink_213, b"SAFE_CAST") is None)
  assert_true(classification_of(flink_120, b"SAFE_CAST") is None)
  assert_true(classification_is_reserved(flink_230, b"SAFE_CAST"))
  // Baseline words remain visible under every profile (introduced at 1.20.5).
  assert_true(classification_is_reserved(flink_120, b"SELECT"))
  assert_true(classification_is_reserved(flink_213, b"SELECT"))
  assert_true(classification_is_reserved(flink_230, b"SELECT"))
  // introduced_profile is the release that first classified the word (W-1
  // 2.1.3-delta list, RESEARCH §10).
  match classification_of(flink_213, b"VARIANT") {
    Some(entry) => assert_eq(entry.introduced_profile, "flink-2.1.3")
    None => assert_true(false)
  }
  match classification_of(flink_213, b"QUALIFY") {
    Some(entry) => assert_eq(entry.introduced_profile, "flink-2.1.3")
    None => assert_true(false)
  }
  // Doris is byte-identical: the row count is derived from the table itself
  // (not a hard-coded pin that breaks on any future keyword-row addition),
  // VARIANT is not a Doris reserved word, SELECT is — no cross-dialect
  // leakage, no global union (DIALECT-02, Pitfall 4, T-10-12). The count
  // assertion still cross-checks the two access paths agree.
  assert_eq(classification_entries(doris).length(), doris_classification_rows.length())
  assert_true(!is_reserved_word(doris, b"VARIANT"))
  assert_true(is_reserved_word(doris, b"SELECT"))
  // The same core word classifies under both dialects independently.
  assert_true(classification_of(flink_230, b"SELECT") is Some(_))
  assert_true(classification_of(doris, b"SELECT") is Some(_))
}
