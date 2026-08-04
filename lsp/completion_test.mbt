test "completion_is_bounded_and_profile_explicit" {
  let result = match @completion.complete(b"", "4.x", 0) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(result.items.length() > 0)
  assert_true(result.items.length() <= 32)
  let rejected = @completion.complete(b"", "mysql", 0)
  assert_true(rejected is Err(_))
}

test "completion_uses_clause_contexts_and_stable_labels" {
  let select_result = match @completion.complete(b"SELECT ", "4.x", 7) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(select_result.items.length() > 0)
  assert_true(select_result.items[0].label == "FROM")
  let from_result = match @completion.complete(b"SELECT x FROM ", "4.x", 14) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(from_result.items.length() > 0)
  assert_true(from_result.items[0].label == "JOIN")
  let where_result = match @completion.complete(b"SELECT x FROM t WHERE ", "4.x", 22) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(where_result.items.length() > 0)
  assert_true(where_result.items[0].label == "AND")
}

test "completion_filters_profile_and_replaces_multibyte_prefix" {
  let old_profile = match @completion.complete(b"SELECT QUAL", "2.1", 11) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(old_profile.items.length(), 0)
  let raw = @utf8.encode("SELECT 列 FR")
  let result = match @completion.complete(raw, "4.x", raw.length()) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(result.items.length() > 0)
  assert_eq(result.items[0].label, "FROM")
  assert_eq(result.items[0].start_byte, 11)
  assert_eq(result.items[0].end_byte, raw.length())
}
