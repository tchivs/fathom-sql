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

fn node_invariants_hold(
  span : @source.Span,
  text_len : Int,
  children : Array[SyntaxElement],
) -> Bool {
  if span.start_byte < 0 || span.start_byte > span.end_byte || text_len < 0 || text_len != span.length() {
    return false
  }
  let mut previous_end = span.start_byte
  for child in children {
    let child_span = child.span()
    if child.text_len() < 0 || child.text_len() != child_span.length() ||
      child_span.start_byte < span.start_byte || child_span.end_byte > span.end_byte ||
      child_span.start_byte < previous_end {
      return false
    }
    match child {
      ChildNode(node) => if !node.is_valid(span.end_byte) { return false }
      Leaf(leaf) => if leaf.text_len < 0 || leaf.text_len != leaf.span.length() { return false }
    }
    previous_end = child_span.end_byte
  }
  true
}

pub fn SyntaxNode::new(
  kind : SyntaxKind,
  span : @source.Span,
  children : Array[SyntaxElement],
) -> SyntaxNode? {
  let text_len = span.length()
  if node_invariants_hold(span, text_len, children) {
    Some({ kind: kind, span: span, text_len: text_len, children: children.copy() })
  } else {
    None
  }
}

pub fn SyntaxNode::with_text_len(
  kind : SyntaxKind,
  span : @source.Span,
  text_len : Int,
  children : Array[SyntaxElement],
) -> SyntaxNode? {
  if node_invariants_hold(span, text_len, children) {
    Some({ kind: kind, span: span, text_len: text_len, children: children.copy() })
  } else {
    None
  }
}

pub fn SyntaxNode::missing(at : Int, source_length : Int) -> SyntaxNode? {
  match @source.Span::checked(at, at, source_length) {
    Ok(span) => SyntaxNode::new(SyntaxKind::Missing, span, [])
    Err(_) => None
  }
}

pub fn SyntaxNode::error(span : @source.Span, children : Array[SyntaxElement]) -> SyntaxNode? {
  SyntaxNode::new(SyntaxKind::Error, span, children)
}

pub fn SyntaxNode::skipped(span : @source.Span, children : Array[SyntaxElement]) -> SyntaxNode? {
  SyntaxNode::new(SyntaxKind::Skipped, span, children)
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

pub fn SyntaxNode::is_valid(self : SyntaxNode, source_length : Int) -> Bool {
  if self.text_len < 0 || self.span.start_byte < 0 || self.span.start_byte > self.span.end_byte || self.span.end_byte > source_length || self.text_len != self.span.length() {
    false
  } else {
    let mut previous_end = self.span.start_byte
    let mut valid = true
    for child in self.children {
      let child_span = child.span()
      if child.text_len() < 0 || child_span.start_byte < self.span.start_byte || child_span.end_byte > self.span.end_byte || child_span.start_byte < previous_end {
        valid = false
      }
      match child {
        ChildNode(node) => { if !node.is_valid(source_length) { valid = false } }
        Leaf(leaf) => { if leaf.text_len < 0 || leaf.text_len != leaf.span.length() { valid = false } }
      }
      previous_end = child_span.end_byte
    }
    valid
  }
}

pub fn SyntaxNode::is_missing(self : SyntaxNode) -> Bool {
  self.kind is SyntaxKind::Missing
}
pub fn SyntaxNode::is_error(self : SyntaxNode) -> Bool {
  self.kind is SyntaxKind::Error
}

pub fn SyntaxNode::is_skipped(self : SyntaxNode) -> Bool {
  self.kind is SyntaxKind::Skipped
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

fn checked_node(node : SyntaxNode?) -> SyntaxNode {
  match node {
    Some(value) => value
    None => panic()
  }
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
  let node = checked_node(SyntaxNode::new(
    SyntaxKind::Document,
    match @source.Span::checked(0, 2, 2) {
      Ok(span) => span
      Err(_) => panic()
    },
    [
      Leaf(SyntaxLeaf::new(LeafKind::SourceToken, first)),
      ChildNode(checked_node(SyntaxNode::missing(2, 2))),
      Leaf(SyntaxLeaf::new(LeafKind::SourceTrivia, second)),
    ],
  ))
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
  let root = checked_node(SyntaxNode::new(
    SyntaxKind::Document,
    root_span,
    [
      Leaf(SyntaxLeaf::new(LeafKind::SourceToken, left_span)),
      Leaf(SyntaxLeaf::new(LeafKind::SourceTrivia, right_span)),
    ],
  ))
  assert_eq(root.children()[0].span().start_byte, 0)
  assert_eq(root.children()[1].span().start_byte, 1)
  assert_eq(root.children()[0].span().end_byte, root.children()[1].span().start_byte)
  assert_eq(root.text_len(), 3)
}

test "syntax_validation_rejects_negative_or_noncontaining_text" {
  let root_span = match @source.Span::checked(0, 3, 3) {
    Ok(span) => span
    Err(_) => panic()
  }
  let child_span = match @source.Span::checked(1, 2, 3) {
    Ok(span) => span
    Err(_) => panic()
  }
  assert_true(SyntaxNode::with_text_len(SyntaxKind::Document, root_span, -1, []) is None)
  assert_true(SyntaxNode::new(
    SyntaxKind::Document,
    root_span,
    [Leaf(SyntaxLeaf::new(LeafKind::SourceToken, child_span)), Leaf(SyntaxLeaf::new(LeafKind::SourceToken, root_span))],
  ) is None)
  assert_true(SyntaxNode::missing(-1, 3) is None)
  assert_true(SyntaxNode::missing(4, 3) is None)
}
