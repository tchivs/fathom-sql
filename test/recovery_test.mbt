///|
/// Shared Doris test context helper (same package as the parse helpers):
/// profile ids are the validated surface; metadata strings are audit metadata
/// only for classification/feature gates.
fn doris_context(profile_id : String) -> @dialect.DialectContext {
  {
    dialect: @dialect.Dialect::Doris,
    profile_id,
    exact_release: profile_id,
    feature_introduction: "",
  }
}

///|
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

///|
fn parse_with_limits(
  raw : Bytes,
  limits : @api.ParseLimits,
) -> @api.ParseResult {
  let options = @api.ParseOptions::for_profile_with_limits(
    @dialect.DorisProfile::V4_X,
    @api.ParseMode::Editor,
    limits,
  )
  match @api.parse(raw, options) {
    Ok(result) => result
    Err(_) => panic()
  }
}

///|
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
    if diagnostic.code == "FATHOM-PARSE-004" {
      resource = true
      assert_eq(diagnostic.expected_class, "resource")
    }
  }
  assert_true(resource)
}

///|
test "max_bytes_is_rejected_before_source_parse_and_limits_are_structured" {
  let options = @api.ParseOptions::for_profile_with_limits(
    @dialect.DorisProfile::V4_X,
    @api.ParseMode::Editor,
    @api.ParseLimits::new(8, 1000, 8, 8, 8),
  )
  let too_large = @api.parse(b"SELECT abcdefghijklmnopqrstuvwxyz", options)
  assert_true(
    too_large
    is Err(@api.ParseError::InputTooLarge(requested_bytes=_, max_bytes=8)),
  )
  let invalid = @api.parse(
    b"SELECT 1",
    @api.ParseOptions::for_profile_with_limits(
      @dialect.DorisProfile::V4_X,
      @api.ParseMode::Editor,
      @api.ParseLimits::new(-1, 1000, 8, 8, 8),
    ),
  )
  assert_true(
    invalid
    is Err(@api.ParseError::InvalidLimit(limit_name="max_bytes", value=-1)),
  )
}

///|
test "max_tokens_stops_lexer_work_and_retains_remainder" {
  let result = parse_with_limits(
    b"SELECT 1; SELECT 2; SELECT 3",
    @api.ParseLimits::new(8 * 1024 * 1024, 3, 128, 8, 8),
  )
  assert_true(!result.valid)
  assert_true(has_kind(result.root, "skipped"))
  assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-004"))
  assert_eq(@printer.print_result(result), b"SELECT 1; SELECT 2; SELECT 3")
}

///|
test "max_recursion_depth_remains_bounded" {
  let deep = parse_with_limits(
    b"SELECT (((((((((((((((1)))))))))))))))",
    @api.ParseLimits::new(8 * 1024 * 1024, 1000, 2, 4, 8),
  )
  assert_true(!deep.valid)
  assert_true(deep.diagnostics.length() > 0)
  assert_eq(
    @printer.print_result(deep),
    b"SELECT (((((((((((((((1)))))))))))))))",
  )

  let nested = parse_with_limits(
    b"SELECT f(f(f(f(1)))) FROM t WHERE x IN (SELECT y FROM u WHERE z IN (SELECT q FROM v))",
    @api.ParseLimits::new(8 * 1024 * 1024, 1000, 2, 64, 8),
  )
  assert_true(!nested.valid)
  let mut resource = false
  for diagnostic in nested.diagnostics {
    if diagnostic.code == "FATHOM-PARSE-004" {
      resource = true
    }
  }
  assert_true(resource)
}

///|
test "diagnostic_caps_preserve_first_error_and_emit_one_resource" {
  let raw = b"bad; bad; bad; bad; bad"
  for cap in [1, 2, 4] {
    let result = parse_with_limits(
      raw,
      @api.ParseLimits::new(8 * 1024 * 1024, 1000, 128, 100, cap),
    )
    assert_true(result.diagnostics.length() <= cap)
    assert_true(result.diagnostics.length() > 0)
    if cap == 1 {
      assert_eq(result.diagnostics[0].code, "FATHOM-PARSE-004")
    } else {
      assert_eq(result.diagnostics[0].code, "FATHOM-PARSE-007")
    }
    let mut resources = 0
    for diagnostic in result.diagnostics {
      if diagnostic.code == "FATHOM-PARSE-004" {
        resources = resources + 1
      }
    }
    assert_eq(resources, 1)
  }
}

///|
test "malformed_lexical_material_uses_stable_code_and_replays" {
  let raw = b"SELECT 'unterminated /* comment"
  let result = parse_with_limits(raw, @api.ParseLimits::default())
  assert_true(!result.valid)
  assert_eq(@printer.print_result(result), raw)
  let mut found = false
  for diagnostic in result.diagnostics {
    assert_true(diagnostic.code.has_prefix("FATHOM-PARSE-"))
    if diagnostic.code == "FATHOM-PARSE-003" {
      found = true
      assert_true(diagnostic.start_byte < diagnostic.end_byte)
    }
  }
  assert_true(found)
}

///|
test "closed_lexical_material_preserves_invalid_utf8_diagnostic" {
  let raws = [b"SELECT '\xff'", b"SELECT `bad\xff`", b"SELECT /*\xff*/ 1"]
  for raw in raws {
    let result = parse_with_limits(raw, @api.ParseLimits::default())
    assert_true(!result.valid)
    assert_eq(@printer.print_result(result), raw)
    let mut found = false
    for diagnostic in result.diagnostics {
      if diagnostic.code == "FATHOM-PARSE-003" {
        found = true
        assert_true(diagnostic.start_byte < diagnostic.end_byte)
      }
    }
    assert_true(found)
  }
}

///|
test "lexical_diagnostics_follow_nonempty_statement_segments" {
  let raw = b"SELECT 1;; -- middle\n; SELECT \xff"
  for mode in ["strict", "editor"] {
    let result = match @api.parse_with_ids(raw, "doris", "4.x", mode) {
      Ok(result) => result
      Err(_) => panic()
    }
    assert_true(!result.valid)
    assert_eq(@printer.print_result(result), raw)
    let mut lexical = 0
    for diagnostic in result.diagnostics {
      if diagnostic.code == "FATHOM-PARSE-003" {
        lexical = lexical + 1
        assert_eq(diagnostic.statement_id, 1U)
        assert_true(diagnostic.start_byte < diagnostic.end_byte)
      }
    }
    assert_eq(lexical, 1)
  }
}

///|
test "resource_diagnostics_use_nonempty_segment_identity" {
  let raw = b"SELECT 1;; -- middle\n; SELECT 2"
  let limits = @api.ParseLimits::new(8 * 1024 * 1024, 9, 128, 100, 8)
  let result = parse_with_limits(raw, limits)
  assert_true(!result.valid)
  assert_eq(@printer.print_result(result), raw)
  let mut resources = 0
  for diagnostic in result.diagnostics {
    if diagnostic.code == "FATHOM-PARSE-004" {
      resources = resources + 1
      assert_eq(diagnostic.statement_id, 1U)
    }
  }
  assert_eq(resources, 1)
}

///|
test "byte_cap_resource_diagnostics_follow_nonempty_segment_identity" {
  let raw = b"SELECT 1;; -- middle\n; SELECT 2"
  let source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = @parser.parse_with_limits(
    source,
    doris_context("4.x"),
    @parser.ParseMode::Editor,
    @parser.ParserLimits::new(14, 1000, 128, 100, 8),
  )
  let mut found = false
  for diagnostic in parsed.diagnostics {
    if diagnostic.code == "FATHOM-PARSE-004" {
      found = true
      assert_eq(diagnostic.statement_id, 1U)
      assert_true(diagnostic.span.start_byte < diagnostic.span.end_byte)
    }
  }
  assert_true(found)
  assert_eq(@printer.print_lossless(parsed.root, source), raw)
  let empty_source = match @source.SourceText::new(b";;") {
    Ok(source) => source
    Err(_) => panic()
  }
  let empty = @parser.parse_with_limits(
    empty_source,
    doris_context("4.x"),
    @parser.ParseMode::Editor,
    @parser.ParserLimits::new(1, 1000, 128, 100, 8),
  )
  let mut empty_found = false
  for diagnostic in empty.diagnostics {
    if diagnostic.code == "FATHOM-PARSE-004" {
      empty_found = true
      assert_eq(diagnostic.statement_id, 0U)
      assert_true(diagnostic.span.start_byte < diagnostic.span.end_byte)
    }
  }
  assert_true(empty_found)
}

///|
test "api_rejects_every_negative_parser_limit_before_parse" {
  let invalids = [
    @api.ParseLimits::new(-1, 1, 1, 1, 1),
    @api.ParseLimits::new(1, -1, 1, 1, 1),
    @api.ParseLimits::new(1, 1, -1, 1, 1),
    @api.ParseLimits::new(1, 1, 1, -1, 1),
    @api.ParseLimits::new(1, 1, 1, 1, -1),
  ]
  for limits in invalids {
    let options = @api.ParseOptions::for_profile_with_limits(
      @dialect.DorisProfile::V4_X,
      @api.ParseMode::Strict,
      limits,
    )
    assert_true(
      @api.parse(b"", options) is Err(@api.ParseError::InvalidLimit(..)),
    )
  }
}

///|
test "quoted_comment_token_split_cap_emits_resource_diagnostic" {
  for raw in [b"SELECT 'ok\xfftail'", b"SELECT /*ok\xfe tail*/ 1"] {
    let result = parse_with_limits(
      raw,
      @api.ParseLimits::new(8 * 1024 * 1024, 3, 128, 100, 8),
    )
    assert_true(!result.valid)
    assert_true(result.recovered)
    assert_true(result.diagnostics.any(d => d.code == "FATHOM-PARSE-004"))
    assert_eq(@printer.print_result(result), raw)
  }
}
