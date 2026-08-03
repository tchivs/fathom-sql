fn has_kind(node : @api.PrimitiveNode, wanted : String) -> Bool {
  if node.kind == wanted {
    true
  } else {
    let mut found = false
    for child in node.children {
      if has_kind(child, wanted) {
        found = true
      }
    }
    found
  }
}

fn parse_with_limits(raw : Bytes, limits : @api.ParseLimits) -> @api.ParseResult {
  let options = @api.ParseOptions::for_profile_with_limits(
    @token.DorisProfile::V4_X,
    @api.ParseMode::Editor,
    limits,
  )
  match @api.parse(raw, options) {
    Ok(result) => result
    Err(_) => panic()
  }
}

test "caps_emit_resource_diagnostic_and_retain_bounded_remainder" {
  let limits = @api.ParseLimits::new(8 * 1024 * 1024, 3, 128, 2, 4)
  let raw = b"SELECT 1; SELECT 2; SELECT 3"
  let result = parse_with_limits(raw, limits)
  assert_true(!result.valid)
  assert_true(result.recovered)
  assert_eq(@printer.print_result(result), raw)
  assert_true(has_kind(result.root, "skipped"))
  let mut resource = false
  for diagnostic in result.diagnostics {
    if diagnostic.code == "DORIS-PARSE-004" {
      resource = true
      assert_eq(diagnostic.expected_class, "resource")
    }
  }
  assert_true(resource)
}

test "max_bytes_and_depth_are_finite_and_source_backed" {
  let bytes_limited = parse_with_limits(
    b"SELECT abcdefghijklmnopqrstuvwxyz",
    @api.ParseLimits::new(8, 1000, 8, 8, 8),
  )
  assert_eq(@printer.print_result(bytes_limited), b"SELECT abcdefghijklmnopqrstuvwxyz")
  assert_true(!bytes_limited.valid)
  let deep = parse_with_limits(
    b"SELECT (((((((((((((((1)))))))))))))))",
    @api.ParseLimits::new(8 * 1024 * 1024, 1000, 2, 4, 8),
  )
  assert_true(!deep.valid)
  assert_true(deep.diagnostics.length() > 0)
  assert_eq(@printer.print_result(deep), b"SELECT (((((((((((((((1)))))))))))))))")
}

test "malformed_lexical_material_uses_stable_code_and_replays" {
  let raw = b"SELECT 'unterminated /* comment"
  let result = parse_with_limits(raw, @api.ParseLimits::default())
  assert_true(!result.valid)
  assert_eq(@printer.print_result(result), raw)
  let mut found = false
  for diagnostic in result.diagnostics {
    assert_true(diagnostic.code.has_prefix("DORIS-PARSE-"))
    if diagnostic.code == "DORIS-PARSE-003" {
      found = true
      assert_true(diagnostic.start_byte < diagnostic.end_byte)
    }
  }
  assert_true(found)
}
