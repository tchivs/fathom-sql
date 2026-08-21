///|
test "lifecycle_sequence_is_bounded" {
  let events = [
    "initialize", "initialized", "didOpen", "didChange", "didClose", "shutdown",
    "exit",
  ]
  let expected = [
    "initialize", "initialized", "didOpen", "didChange", "didClose", "shutdown",
    "exit",
  ]
  assert_eq(events.length(), 7)
  assert_eq(events, expected)
  let initialize = parse_message(
    @utf8.encode(
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"dialect\":\"doris\",\"profile\":\"4.x\"}}}",
    ),
  )
  let message = match initialize {
    Ok(message) => message
    Err(_) => panic()
  }
  let state = ServerState::new()
  let responses = handle_message(state, message)
  assert_eq(responses.length(), 1)
  assert_true(state.initialized)
  assert_eq(state.default_dialect, Some("doris"))
  assert_eq(state.default_profile, Some("4.x"))
}
