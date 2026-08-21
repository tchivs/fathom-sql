///|
/// FNV-1a vectors + normalize invariants + UInt64 probe assertions
/// (06-01 Task 1 acceptance). The UInt64 probe facts are also recorded in
/// hash.mbt's header comment.
test "fnv1a64_standard_vectors" {
  assert_eq(fnv1a64(b""), 0xcbf29ce484222325UL)
  assert_eq(fnv1a64(b"a"), 0xaf63dc4c8601ec8cUL)
  assert_eq(fnv1a64(b"foobar"), 0x85944171f73967e8UL)
}

///|
test "fnv1a64_is_sensitive_to_content_and_order" {
  assert_true(fnv1a64(b"SELECT 1") != fnv1a64(b"SELECT 2"))
  assert_true(fnv1a64(b"ab") != fnv1a64(b"ba"))
}

///|
test "uint64_probe_assertions" {
  // A1 / Open Question 1 probe conclusions, locked as assertions so any
  // toolchain drift (literal suffix, wrapping multiply, operator) fails loud.
  let x : UInt64 = 0xffffffffffffffffUL
  assert_eq(x * 2UL, 0xfffffffffffffffeUL) // wrapping multiply
  let b : Byte = 97
  assert_eq(b.to_uint64(), 97UL) // Byte::to_uint64 zero-extends
  assert_eq(0xcbf29ce484222325UL ^ 0UL, 0xcbf29ce484222325UL) // ^ infix XOR
}

///|
fn doris_test_context() -> @dialect.DialectContext {
  {
    dialect: @dialect.Dialect::Doris,
    profile_id: "4.x",
    exact_release: "4.x",
    feature_introduction: "test",
  }
}

///|
/// Build a minimal Document node from ordered (leaf kind, start, end) spans
/// over `source`, plus the SourceText. Leaf spans must be contiguous and
/// ascending so SyntaxNode::new invariants hold.
fn doc(
  source : Bytes,
  parts : Array[(@syntax.LeafKind, Int, Int)],
) -> (@syntax.SyntaxNode, @source.SourceText) {
  let src = match @source.SourceText::new(source) {
    Ok(value) => value
    Err(_) => panic()
  }
  let leaves : Array[@syntax.SyntaxElement] = []
  for part in parts {
    let (kind, start, end) = part
    let span = match @source.Span::checked(start, end, source.length()) {
      Ok(value) => value
      Err(_) => panic()
    }
    leaves.push(
      @syntax.SyntaxElement::Leaf(@syntax.SyntaxLeaf::new(kind, span)),
    )
  }
  let root_span = match
    @source.Span::checked(0, source.length(), source.length()) {
    Ok(value) => value
    Err(_) => panic()
  }
  let node = match
    @syntax.SyntaxNode::new(@syntax.SyntaxKind::Document, root_span, leaves) {
    Some(value) => value
    None => panic()
  }
  (node, src)
}

///|
fn select_a_b_parts() -> Array[(@syntax.LeafKind, Int, Int)] {
  [
    (@syntax.LeafKind::SourceToken, 0, 6), // SELECT
    (@syntax.LeafKind::SourceTrivia, 6, 7), // space
    (@syntax.LeafKind::SourceToken, 7, 8), // a
    (@syntax.LeafKind::SourceToken, 8, 9), // ,
    (@syntax.LeafKind::SourceTrivia, 9, 10), // space
    (@syntax.LeafKind::SourceToken, 10, 11), // b
  ]
}

///|
test "normalize_folds_whitespace_keyword_case_and_comments" {
  let ctx = doris_test_context()
  // SELECT a, b
  let (n1, s1) = doc(b"SELECT a, b", select_a_b_parts())
  // select\n a, b — different keyword case, newline + space run; same
  // separator structure as "SELECT a, b" (no whitespace before the comma)
  let (n2, s2) = doc(b"select\n a, b", [
    (@syntax.LeafKind::SourceToken, 0, 6), // select
    (@syntax.LeafKind::SourceTrivia, 6, 8), // \n + space run
    (@syntax.LeafKind::SourceToken, 8, 9), // a
    (@syntax.LeafKind::SourceToken, 9, 10), // ,
    (@syntax.LeafKind::SourceTrivia, 10, 11), // space
    (@syntax.LeafKind::SourceToken, 11, 12), // b
  ])
  // SELECT /*c*/ a, b — comment dropped
  let (n3, s3) = doc(b"SELECT /*c*/ a, b", [
    (@syntax.LeafKind::SourceToken, 0, 6), // SELECT
    (@syntax.LeafKind::SourceTrivia, 6, 7), // space
    (@syntax.LeafKind::SourceTrivia, 7, 12), // /*c*/ comment
    (@syntax.LeafKind::SourceTrivia, 12, 13), // space
    (@syntax.LeafKind::SourceToken, 13, 14), // a
    (@syntax.LeafKind::SourceToken, 14, 15), // ,
    (@syntax.LeafKind::SourceTrivia, 15, 16), // space
    (@syntax.LeafKind::SourceToken, 16, 17), // b
  ])
  let c1 = normalize(n1, s1, ctx)
  let c2 = normalize(n2, s2, ctx)
  let c3 = normalize(n3, s3, ctx)
  assert_eq(c1, b"select a, b")
  assert_eq(c1, c2)
  assert_eq(c1, c3)
}

///|
test "normalize_preserves_quote_style_identifier_case_literal_content" {
  let ctx = doris_test_context()
  // SELECT "A"  (quoted identifier, double quotes)
  let (n1, s1) = doc(b"SELECT \"A\"", [
    (@syntax.LeafKind::SourceToken, 0, 6), // SELECT
    (@syntax.LeafKind::SourceTrivia, 6, 7),
    (@syntax.LeafKind::SourceToken, 7, 10), // "A"
  ])
  // SELECT 'A'  (string literal, single quotes)
  let (n2, s2) = doc(b"SELECT 'A'", [
    (@syntax.LeafKind::SourceToken, 0, 6),
    (@syntax.LeafKind::SourceTrivia, 6, 7),
    (@syntax.LeafKind::SourceToken, 7, 10), // 'A'
  ])
  assert_true(normalize(n1, s1, ctx) != normalize(n2, s2, ctx))
  // SELECT a vs SELECT A — identifier case preserved
  let (n3, s3) = doc(b"SELECT A", [
    (@syntax.LeafKind::SourceToken, 0, 6),
    (@syntax.LeafKind::SourceTrivia, 6, 7),
    (@syntax.LeafKind::SourceToken, 7, 8), // A (identifier, not keyword)
  ])
  let (n4, s4) = doc(b"SELECT a", [
    (@syntax.LeafKind::SourceToken, 0, 6),
    (@syntax.LeafKind::SourceTrivia, 6, 7),
    (@syntax.LeafKind::SourceToken, 7, 8), // a
  ])
  assert_true(normalize(n3, s3, ctx) != normalize(n4, s4, ctx))
  // SELECT 'x' vs SELECT 'y' — literal content preserved
  let (n5, s5) = doc(b"SELECT 'x'", [
    (@syntax.LeafKind::SourceToken, 0, 6),
    (@syntax.LeafKind::SourceTrivia, 6, 7),
    (@syntax.LeafKind::SourceToken, 7, 10), // 'x'
  ])
  let (n6, s6) = doc(b"SELECT 'y'", [
    (@syntax.LeafKind::SourceToken, 0, 6),
    (@syntax.LeafKind::SourceTrivia, 6, 7),
    (@syntax.LeafKind::SourceToken, 7, 10), // 'y'
  ])
  assert_true(normalize(n5, s5, ctx) != normalize(n6, s6, ctx))
}

///|
test "normalize_is_total_on_empty_and_error_material" {
  let ctx = doris_test_context()
  // Empty document -> empty canonical -> fingerprint = FNV offset basis.
  let (n, s) = doc(b"", [])
  let empty_canonical = normalize(n, s, ctx)
  assert_eq(empty_canonical, b"")
  assert_eq(fnv1a64(empty_canonical), 0xcbf29ce484222325UL)
  // error/skipped material emitted verbatim (total function).
  let (ne, se) = doc(b"SELECT \xff\xfe", [
    (@syntax.LeafKind::SourceToken, 0, 6),
    (@syntax.LeafKind::SourceTrivia, 6, 7),
    (@syntax.LeafKind::SourceSkipped, 7, 9), // raw non-UTF-8 tail
  ])
  assert_eq(normalize(ne, se, ctx), b"select \xff\xfe")
}
