// Public-surface end-to-end tests for the analyzer Wave 0 (plan 07-01):
// parse -> @analyzer.source_tokens -> @analyzer.split_select_model over the
// real Doris parser, asserting the cross-package-readable SelectModel
// structure, the empty-document total function, and the public
// has_error_missing scan. These live in the test package because the analyzer
// package cannot import the parser (D-21); the integration surface mirrors
// analyzer_anal01_test.mbt.

/// Parses `raw` as a Doris 4.x strict document and returns the root node.
fn parse_root(raw : Bytes) -> @syntax.SyntaxNode {
  let source = match @source.SourceText::new_with_limit(raw, 8 * 1024 * 1024) {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = @parser.parse_with_limits(
    source,
    doris_context("4.x"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  if !parsed.valid {
    panic()
  }
  parsed.root
}

/// Walks root -> Statement -> the first Select body node (mirrors the
/// analyzer's own Document -> Statement -> body dispatch in resolve.mbt).
fn first_select_body(root : @syntax.SyntaxNode) -> @syntax.SyntaxNode? {
  for element in root.children() {
    match element {
      @syntax.SyntaxElement::ChildNode(statement_node) => {
        if statement_node.kind() is @syntax.SyntaxKind::Statement {
          for inner in statement_node.children() {
            match inner {
              @syntax.SyntaxElement::ChildNode(body) => {
                if body.kind() is @syntax.SyntaxKind::Select {
                  return Some(body)
                }
              }
              @syntax.SyntaxElement::Leaf(_) => ()
            }
          }
        }
      }
      @syntax.SyntaxElement::Leaf(_) => ()
    }
  }
  None
}

test "public-surface select-model end-to-end" {
  // Test 1: SELECT a + b AS x FROM t (doris 4.x strict) -> source_tokens ->
  // split_select_model yields one branch, one select item, two refs, alias x.
  let raw = b"SELECT a + b AS x FROM t"
  let source = match @source.SourceText::new_with_limit(raw, 8 * 1024 * 1024) {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = @parser.parse_with_limits(
    source,
    doris_context("4.x"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  assert_true(parsed.valid)
  let body = match first_select_body(parsed.root) {
    Some(body) => body
    None => panic()
  }
  let tokens = @analyzer.source_tokens(body, source.bytes())
  assert_true(tokens.length() >= 7) // SELECT a + b AS x FROM t
  let model = match @analyzer.split_select_model(tokens) {
    Some(model) => model
    None => panic()
  }
  assert_eq(model.branches.length(), 1)
  assert_eq(model.branches[0].select_list.length(), 1)
  assert_eq(model.branches[0].select_list[0].refs.length(), 2)
  assert_eq(model.branches[0].select_list[0].alias, Some("x"))
}

test "public-surface empty token stream empty model" {
  // Test 2: an empty token stream re-parses to an empty SelectModel
  // (branches = []): total function, no panic, no fabricated content.
  let tokens : Array[(Bytes, Int, Int)] = []
  let model = match @analyzer.split_select_model(tokens) {
    Some(model) => model
    None => panic()
  }
  assert_eq(model.branches.length(), 0)
  assert_eq(model.ctes.length(), 0)
}

test "public-surface has_error_missing positive negative" {
  // Test 3: has_error_missing is false for a clean SELECT body and true for a
  // statement carrying error/missing material (D-33 refusal scan).
  let clean_body = match first_select_body(parse_root(b"SELECT a FROM t")) {
    Some(body) => body
    None => panic()
  }
  assert_true(!@analyzer.has_error_missing(clean_body))

  // A malformed statement (missing select items) carries Missing material.
  let broken_raw = b"SELECT"
  let broken_source = match @source.SourceText::new_with_limit(broken_raw, 8 * 1024 * 1024) {
    Ok(source) => source
    Err(_) => panic()
  }
  let broken_parsed = @parser.parse_with_limits(
    broken_source,
    doris_context("4.x"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  // The statement body is present even when the parse is not valid; walk to
  // the first Select body (the analyzer dispatches the same way).
  let broken_body = match first_select_body(broken_parsed.root) {
    Some(body) => body
    None => panic()
  }
  assert_true(@analyzer.has_error_missing(broken_body))
}
