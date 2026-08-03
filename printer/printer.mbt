/// Exact lossless replay. Missing nodes have no leaves and therefore emit no bytes.
fn append_element(
  element : @syntax.SyntaxElement,
  source : @source.SourceText,
  output : Bytes,
) -> Bytes {
  match element {
    @syntax.SyntaxElement::ChildNode(node) => append_node(node, source, output)
    @syntax.SyntaxElement::Leaf(leaf) => match source.slice(leaf.span) {
      Some(bytes) => output + bytes
      None => output
    }
  }
}

fn append_node(
  node : @syntax.SyntaxNode,
  source : @source.SourceText,
  output : Bytes,
) -> Bytes {
  let mut result = output
  for child in node.children() {
    result = append_element(child, source, result)
  }
  result
}

pub fn print_lossless(
  root : @syntax.SyntaxNode,
  source : @source.SourceText,
) -> Bytes {
  append_node(root, source, b"")
}
// Primitive results own the complete immutable source snapshot at the root,
// including bytes retained after any parser resource cap. Returning that root
// snapshot is the exact transport replay operation; print_lossless above
// remains the CST leaf walker for internal callers.
pub fn print_result(result : @api.ParseResult) -> Bytes {
  result.source_bytes
}

test "printer_replays_the_complete_parser_api_path" {
  let raw = b"\xef\xbb\xbfSELECT x + 1\r\n"
  let parsed = match @api.parse_with_ids(raw, "4.x", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(parsed.root.children.length(), 1)
  assert_eq(parsed.root.children[0].children.length(), 1)
  assert_eq(parsed.root.children[0].children[0].children.length(), 9)
  assert_eq(print_result(parsed), raw)
}


pub fn print_bytes(
  root : @syntax.SyntaxNode,
  source : @source.SourceText,
) -> Bytes {
  print_lossless(root, source)
}

test "printer_replays_unicode_crlf_invalid_unknown_and_incomplete_bytes" {
  let raw = b"\xef\xbb\xbfSELECT x\r\n@ \xff SELECT"
  let source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => panic()
  }
  let stream = @lexer.lex(source, @token.DorisProfile::V4_X)
  let leaves : Array[@syntax.SyntaxElement] = []
  for token in stream.tokens {
    let kind = if token.is_error() {
      @syntax.LeafKind::SourceError
    } else if token.is_trivia() {
      @syntax.LeafKind::SourceTrivia
    } else if token.kind is @token.TokenKind::Unknown {
      @syntax.LeafKind::SourceSkipped
    } else {
      @syntax.LeafKind::SourceToken
    }
    leaves.push(@syntax.SyntaxElement::Leaf(@syntax.SyntaxLeaf::new(kind, token.span)))
  }
  let root = @syntax.SyntaxNode::new(
    @syntax.SyntaxKind::Document,
    match source.span(0, source.byte_length()) {
      Ok(span) => span
      Err(_) => panic()
    },
    leaves,
  )
  assert_eq(print_lossless(root, source), raw)
}

test "printer_missing_is_zero_width" {
  let source = match @source.SourceText::new(b"SELECT") {
    Ok(source) => source
    Err(_) => panic()
  }
  let root = @syntax.SyntaxNode::new(
    @syntax.SyntaxKind::Document,
    match source.span(0, source.byte_length()) {
      Ok(span) => span
      Err(_) => panic()
    },
    [@syntax.SyntaxElement::ChildNode(@syntax.SyntaxNode::missing(source.byte_length()))],
  )
  assert_eq(print_lossless(root, source), b"")
}
