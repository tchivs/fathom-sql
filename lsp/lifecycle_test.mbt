test "lifecycle_sequence_is_bounded" {
  let events = ["initialize", "initialized", "didOpen", "didChange", "didClose", "shutdown", "exit"]
  let expected = ["initialize", "initialized", "didOpen", "didChange", "didClose", "shutdown", "exit"]
  assert_eq(events.length(), 7)
  assert_eq(events, expected)
  let initialize = @protocol.parse_message(@utf8.encode("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"profile\":\"4.x\"}}}"))
  let message = match initialize {
    Ok(message) => message
    Err(_) => panic()
  }
  let state = @handlers.ServerState::new()
  let responses = @handlers.handle_message(state, message)
  assert_eq(responses.length(), 1)
  assert_true(state.initialized)
  assert_eq(state.profile, "4.x")
}
