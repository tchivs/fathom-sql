///|
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

///|
test "completion_uses_clause_contexts_and_stable_labels" {
  let select_result = match
    @completion.complete(b"SELECT ", "doris", "4.x", 7) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(select_result.items.length() > 0)
  assert_true(select_result.items[0].label == "FROM")
  let from_result = match
    @completion.complete(b"SELECT x FROM ", "doris", "4.x", 14) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(from_result.items.length() > 0)
  assert_true(from_result.items[0].label == "JOIN")
  let where_result = match
    @completion.complete(b"SELECT x FROM t WHERE ", "doris", "4.x", 22) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(where_result.items.length() > 0)
  assert_true(where_result.items[0].label == "AND")
}

///|
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
  // (b) flink-mode completion returns real Flink candidates (D-02, 13-02):
  // the Flink branch constructs a Flink DialectContext and offers the
  // classification-filtered words; Doris keyword items never leak into a
  // flink request (D-28, T-13-02-07).
  let flink = match @completion.complete(b"SEL", "flink", "flink-2.3.0", 3) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(flink.items.length() > 0)
  let mut flink_has_select = false
  for item in flink.items {
    assert_eq(item.detail, "SQL syntax keyword")
    if item.label == "SELECT" && item.new_text == "SELECT" {
      flink_has_select = true
    }
    // A Doris-only word never leaks into a flink request.
    assert_true(item.label != "TABLET")
  }
  assert_true(flink_has_select)
  // (c) an unknown flink profile rejects with the structured UnknownProfile
  // error — no Doris fallback, no empty-silent success (T-13-02-05).
  let unknown_flink = @completion.complete(b"SEL", "flink", "flink-9.9.9", 3)
  assert_true(
    unknown_flink
    is Err(
      @completion.CompletionError::UnknownProfile(profile_id="flink-9.9.9")
    ),
  )
  // (d) unknown dialect returns the structured UnknownDialect error.
  let unknown = @completion.complete(b"SEL", "mysql", "4.x", 3)
  assert_true(
    unknown
    is Err(@completion.CompletionError::UnknownDialect(dialect_id="mysql")),
  )
}

///|
test "completion_filters_profile_and_replaces_multibyte_prefix" {
  let old_profile = match
    @completion.complete(b"SELECT QUAL", "doris", "2.1", 11) {
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

///|
test "flink_completion_returns_real_textedit_no_32602" {
  // D-07 (13-05): a flink-selected document's textDocument/completion returns
  // real items with a UTF-16 textEdit through the shared completion_item_json
  // path — the -32602 flink policy rejection is gone (13-02 made complete()
  // return Ok for flink). The response is a standard LSP completion list
  // (echoed id + result + items), never an error and never a Doris fallback.
  let state = ServerState::new()
  let initialize = message(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"dialect\":\"flink\",\"profile\":\"flink-2.3.0\"}}}",
  )
  assert_eq(handle_message(state, initialize).length(), 1)
  let open = message(
    "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///flink-complete.sql\",\"version\":1,\"text\":\"SELECT \"}}}",
  )
  assert_eq(handle_message(state, open).length(), 1)
  let request = message(
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file:///flink-complete.sql\",\"version\":1},\"position\":{\"line\":0,\"character\":7}}}",
  )
  let responses = handle_message(state, request)
  assert_eq(responses.length(), 1)
  let body = @utf8.decode_lossy(responses[0])
  assert_true(!body.contains("-32602"))
  assert_true(body.contains("\"result\""))
  assert_true(body.contains("\"items\""))
  assert_true(body.contains("\"textEdit\""))
  assert_true(body.contains("\"FROM\""))
}

///|
test "flink_completion_multibyte_utf16_range" {
  // D-07 (Don't Hand-Roll): a flink completion on a multibyte prefix returns
  // a textEdit whose range is UTF-16 (line/character) via the shared
  // @binding.span_to_range path — "名称" counts as 2 UTF-16 units, not 6
  // bytes. The FROM item replaces the FR prefix at bytes 14..16, which map to
  // UTF-16 characters 10..12 on line 0.
  let raw = @utf8.encode("SELECT 名称 FR")
  let core = match
    @completion.complete(raw, "flink", "flink-2.3.0", raw.length()) {
    Ok(result) => result
    Err(_) => panic()
  }
  let mut from_item = None
  for item in core.items {
    if item.label == "FROM" {
      from_item = Some(item)
    }
  }
  let item = match from_item {
    Some(item) => item
    None => panic()
  }
  assert_eq(item.start_byte, 14)
  assert_eq(item.end_byte, raw.length())
  // LSP surface: open a flink document and request completion at the UTF-16
  // position of the byte cursor (character 12 == raw.length() in UTF-16).
  let state = ServerState::new()
  ignore(
    handle_message(
      state,
      message(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"dialect\":\"flink\",\"profile\":\"flink-2.3.0\"}}}",
      ),
    ),
  )
  let open = message(
    "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///flink-mb.sql\",\"version\":1,\"text\":\"SELECT 名称 FR\",\"dialect\":\"flink\",\"profile\":\"flink-2.3.0\"}}}",
  )
  ignore(handle_message(state, open))
  let request = message(
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file:///flink-mb.sql\",\"version\":1},\"position\":{\"line\":0,\"character\":12}}}",
  )
  let responses = handle_message(state, request)
  assert_eq(responses.length(), 1)
  let body = @utf8.decode_lossy(responses[0])
  assert_true(!body.contains("-32602"))
  assert_true(body.contains("\"start\":{\"line\":0,\"character\":10}"))
  assert_true(body.contains("\"end\":{\"line\":0,\"character\":12}"))
  assert_true(body.contains("\"newText\":\"FROM\""))
}
