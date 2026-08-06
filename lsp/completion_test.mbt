test "completion_is_bounded_and_profile_explicit" {
  let result = match @completion.complete(b"", "doris", "4.x", 0) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(result.items.length() > 0)
  assert_true(result.items.length() <= 32)
  let rejected = @completion.complete(b"", "mysql", "4.x", 0)
  assert_true(rejected is Err(_))
}

test "completion_uses_clause_contexts_and_stable_labels" {
  let select_result = match @completion.complete(b"SELECT ", "doris", "4.x", 7) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(select_result.items.length() > 0)
  assert_true(select_result.items[0].label == "FROM")
  let from_result = match @completion.complete(b"SELECT x FROM ", "doris", "4.x", 14) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(from_result.items.length() > 0)
  assert_true(from_result.items[0].label == "JOIN")
  let where_result = match @completion.complete(b"SELECT x FROM t WHERE ", "doris", "4.x", 22) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(where_result.items.length() > 0)
  assert_true(where_result.items[0].label == "AND")
}

test "completion_is_dialect_aware_with_neutral_detail" {
  // (a) doris-mode completion returns the same items as v1 for a
  // representative prefix; the item detail is the dialect-neutral
  // "SQL syntax keyword" (research row 27).
  let select_result = match @completion.complete(b"SEL", "doris", "4.x", 3) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(select_result.items.length() > 0)
  let mut has_select = false
  for item in select_result.items {
    assert_eq(item.detail, "SQL syntax keyword")
    if item.label == "SELECT" && item.new_text == "SELECT" {
      has_select = true
    }
  }
  assert_true(has_select)
  // (b) flink-mode completion returns the structured unsupported-profile
  // error — Doris keyword items never leak into a flink request (Pitfall 6,
  // T-09-10).
  let flink = @completion.complete(b"SEL", "flink", "flink-2.3.0", 3)
  assert_true(flink is Err(@completion.CompletionError::UnknownProfile(profile_id="flink-2.3.0")))
  // (c) unknown dialect returns the structured UnknownDialect error.
  let unknown = @completion.complete(b"SEL", "mysql", "4.x", 3)
  assert_true(unknown is Err(@completion.CompletionError::UnknownDialect(dialect_id="mysql")))
}

test "completion_filters_profile_and_replaces_multibyte_prefix" {
  let old_profile = match @completion.complete(b"SELECT QUAL", "doris", "2.1", 11) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(old_profile.items.length(), 0)
  let raw = @utf8.encode("SELECT 列 FR")
  let result = match @completion.complete(raw, "doris", "4.x", raw.length()) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(result.items.length() > 0)
  assert_eq(result.items[0].label, "FROM")
  assert_eq(result.items[0].start_byte, 11)
  assert_eq(result.items[0].end_byte, raw.length())
}
