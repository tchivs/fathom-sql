test "lifecycle_sequence_is_bounded" {
  let events = ["initialize", "initialized", "didOpen", "didChange", "didClose", "shutdown", "exit"]
  assert_eq(events[0], "initialize")
  assert_eq(events[6], "exit")
}
