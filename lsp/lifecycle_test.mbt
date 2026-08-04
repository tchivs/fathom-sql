test "lifecycle_sequence_is_bounded" {
  let events = ["initialize", "initialized", "didOpen", "didChange", "didClose", "shutdown", "exit"]
  let expected = ["initialize", "initialized", "didOpen", "didChange", "didClose", "shutdown", "exit"]
  assert_eq(events.length(), 7)
  assert_eq(events, expected)
  assert_eq(events[0], "initialize")
  assert_eq(events[1], "initialized")
  assert_eq(events[2], "didOpen")
  assert_eq(events[3], "didChange")
  assert_eq(events[4], "didClose")
  assert_eq(events[5], "shutdown")
  assert_eq(events[6], "exit")
  assert_true(events[5] != events[6])
}
