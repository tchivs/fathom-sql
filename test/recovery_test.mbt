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

test "max_bytes_is_rejected_before_source_parse_and_limits_are_structured" {
  let options = @api.ParseOptions::for_profile_with_limits(
    @token.DorisProfile::V4_X,
    @api.ParseMode::Editor,
    @api.ParseLimits::new(8, 1000, 8, 8, 8),
  )
  let too_large = @api.parse(b"SELECT abcdefghijklmnopqrstuvwxyz", options)
  assert_true(too_large is Err(@api.ParseError::InputTooLarge(requested_bytes=_, max_bytes=8)))
  let invalid = @api.parse(
    b"SELECT 1",
    @api.ParseOptions::for_profile_with_limits(
      @token.DorisProfile::V4_X,
      @api.ParseMode::Editor,
      @api.ParseLimits::new(-1, 1000, 8, 8, 8),
    ),
  )
  assert_true(invalid is Err(@api.ParseError::InvalidLimit(limit_name="max_bytes", value=-1)))
}

test "max_tokens_stops_lexer_work_and_retains_remainder" {
  let result = parse_with_limits(
    b"SELECT 1; SELECT 2; SELECT 3",
    @api.ParseLimits::new(8 * 1024 * 1024, 3, 128, 8, 8),
  )
  assert_true(!result.valid)
  assert_true(has_kind(result.root, "skipped"))
  assert_true(result.diagnostics.any(d => d.code == "DORIS-PARSE-004"))
  assert_eq(@printer.print_result(result), b"SELECT 1; SELECT 2; SELECT 3")
}
test "max_recursion_depth_remains_bounded" {
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
