/// Immutable lossless concrete syntax nodes. Nodes never own source bytes.
pub(all) enum SyntaxKind {
  Document
  Statement
  Select
  Expression
  Token
  Trivia
  Error
  Skipped
  Missing
} derive(Eq, @debug.Debug)

pub(all) enum LeafKind {
  SourceToken
  SourceTrivia
  SourceError
  SourceSkipped
} derive(Eq, @debug.Debug)

pub struct SyntaxLeaf {
  pub kind : LeafKind
  pub span : @source.Span
  pub text_len : Int
}

pub(all) enum SyntaxElement {
  ChildNode(SyntaxNode)
  Leaf(SyntaxLeaf)
}


pub struct SyntaxNode {
  kind : SyntaxKind
  span : @source.Span
  text_len : Int
  children : Array[SyntaxElement]
}

pub fn SyntaxNode::new(
  kind : SyntaxKind,
  span : @source.Span,
  children : Array[SyntaxElement],
) -> SyntaxNode {
  {
    kind: kind,
    span: span,
    text_len: span.length(),
    children: children.copy(),
  }
}

pub fn SyntaxNode::with_text_len(
  kind : SyntaxKind,
  span : @source.Span,
  text_len : Int,
  children : Array[SyntaxElement],
) -> SyntaxNode {
  {
    kind: kind,
    span: span,
    text_len: text_len,
    children: children.copy(),
  }
}

pub fn SyntaxNode::missing(at : Int) -> SyntaxNode {
  let span = match @source.Span::checked(at, at, at) {
    Ok(span) => span
    Err(_) => panic()
  }
  SyntaxNode::new(SyntaxKind::Missing, span, [])
}

pub fn SyntaxNode::kind(self : SyntaxNode) -> SyntaxKind {
  self.kind
}

pub fn SyntaxNode::span(self : SyntaxNode) -> @source.Span {
  self.span
}

pub fn SyntaxNode::text_len(self : SyntaxNode) -> Int {
  self.text_len
}

pub fn SyntaxNode::children(self : SyntaxNode) -> Array[SyntaxElement] {
  self.children.copy()
}

pub fn SyntaxNode::is_missing(self : SyntaxNode) -> Bool {
  self.kind is SyntaxKind::Missing
}

pub fn SyntaxLeaf::new(kind : LeafKind, span : @source.Span) -> SyntaxLeaf {
  { kind: kind, span: span, text_len: span.length() }
}

pub fn SyntaxLeaf::is_zero_width(self : SyntaxLeaf) -> Bool {
  self.text_len == 0
}

pub fn SyntaxElement::span(self : SyntaxElement) -> @source.Span {
  match self {
    ChildNode(node) => node.span()
    Leaf(leaf) => leaf.span
  }
}

pub fn SyntaxElement::text_len(self : SyntaxElement) -> Int {
  match self {
    ChildNode(node) => node.text_len()
    Leaf(leaf) => leaf.text_len
  }
}

pub fn SyntaxNode::leaf_count(self : SyntaxNode) -> Int {
  let mut count = 0
  for child in self.children {
    let amount = match child {
      ChildNode(node) => node.leaf_count()
      Leaf(_) => 1
    }
    count = count + amount
  }
  count
}

test "syntax_nodes_keep_touching_spans_and_zero_width_missing" {
  let first = match @source.Span::checked(0, 2, 2) {
    Ok(span) => span
    Err(_) => panic()
  }
  let second = match @source.Span::checked(2, 2, 2) {
    Ok(span) => span
    Err(_) => panic()
  }
  let node = SyntaxNode::new(
    SyntaxKind::Document,
    match @source.Span::checked(0, 2, 2) {
      Ok(span) => span
      Err(_) => panic()
    },
    [
      Leaf(SyntaxLeaf::new(LeafKind::SourceToken, first)),
      ChildNode(SyntaxNode::missing(2)),
      Leaf(SyntaxLeaf::new(LeafKind::SourceTrivia, second)),
    ],
  )
  assert_eq(node.text_len(), 2)
  assert_eq(node.leaf_count(), 2)
  assert_eq(node.children()[1].text_len(), 0)
}

test "syntax_source_order_and_touching_leaf_spans_are_preserved" {
  let left_span = match @source.Span::checked(0, 1, 3) {
    Ok(span) => span
    Err(_) => panic()
  }
  let right_span = match @source.Span::checked(1, 3, 3) {
    Ok(span) => span
    Err(_) => panic()
  }
  let root_span = match @source.Span::checked(0, 3, 3) {
    Ok(span) => span
    Err(_) => panic()
  }
  let root = SyntaxNode::new(
    SyntaxKind::Document,
    root_span,
    [
      Leaf(SyntaxLeaf::new(LeafKind::SourceToken, left_span)),
      Leaf(SyntaxLeaf::new(LeafKind::SourceTrivia, right_span)),
    ],
  )
  assert_eq(root.children()[0].span().start_byte, 0)
  assert_eq(root.children()[1].span().start_byte, 1)
  assert_eq(root.children()[0].span().end_byte, root.children()[1].span().start_byte)
  assert_eq(root.text_len(), 3)
}
