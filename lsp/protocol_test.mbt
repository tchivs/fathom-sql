fn message(text : String) -> RpcMessage {
  match parse_message(@utf8.encode(text)) {
    Ok(value) => value
    Err(_) => panic()
  }
}

test "completion_dispatch_uses_current_utf16_snapshot" {
  let state = ServerState::new()
  let initialize = message("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"dialect\":\"doris\",\"profile\":\"4.x\"}}}")
  assert_eq(handle_message(state, initialize).length(), 1)
  let open = message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///completion.sql\",\"version\":1,\"text\":\"SELECT \"}}}")
  assert_eq(handle_message(state, open).length(), 1)
  let request = message("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file:///completion.sql\",\"version\":1},\"position\":{\"line\":0,\"character\":7}}}")
  let responses = handle_message(state, request)
  assert_eq(responses.length(), 1)
  let body = @utf8.decode_lossy(responses[0])
  assert_true(body.contains("items"))
  assert_true(body.contains("FROM"))
  assert_true(body.contains("textEdit"))
}

test "stale_and_malformed_requests_return_bounded_errors" {
  let state = ServerState::new()
  ignore(handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"dialect\":\"doris\",\"profile\":\"4.x\"}}}")))
  ignore(handle_message(state, message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///stale.sql\",\"version\":2,\"text\":\"SELECT 1\"}}}")))
  let stale = handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"file:///stale.sql\",\"version\":1},\"contentChanges\":[{\"text\":\"SELECT 2\"}]}}"))
  assert_eq(stale.length(), 1)
  assert_true(@utf8.decode_lossy(stale[0]).contains("-32602"))
  let malformed = handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"textDocument/completion\",\"params\":{}}"))
  assert_eq(malformed.length(), 1)
  assert_true(@utf8.decode_lossy(malformed[0]).contains("-32602"))
  let unknown = handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"textDocument/unknown\"}"))
  assert_eq(unknown.length(), 1)
  assert_true(@utf8.decode_lossy(unknown[0]).contains("-32601"))
}

test "shutdown_and_exit_remain_clean_after_completion_requests" {
  let state = ServerState::new()
  ignore(handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"dialect\":\"doris\",\"profile\":\"2.1\"}}}")))
  let shutdown = handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\"}"))
  assert_eq(shutdown.length(), 1)
  ignore(handle_message(state, message("{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}")))
  assert_true(state.shutdown)
  assert_true(state.exited)
}
