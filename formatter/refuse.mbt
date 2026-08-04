/// Recursive scan for material that must never be formatted (D-33): Error /
/// Skipped / Missing nodes and SourceError / SourceSkipped leaves
/// (syntax.mbt:30-37 predicates 123-137). Returns the first unsafe element in
/// document order, mirroring the printer's recursive element walk (printer.mbt:
/// 5-34) with a read-only verdict instead of byte emission.
pub fn first_unsafe_element(root : @syntax.SyntaxNode) -> @syntax.SyntaxElement? {
  for child in root.children() {
    let bad = match child {
      @syntax.SyntaxElement::ChildNode(node) =>
        node.is_error() || node.is_skipped() || node.is_missing() ||
        (first_unsafe_element(node) is Some(_))
      @syntax.SyntaxElement::Leaf(leaf) =>
        leaf.kind is @syntax.LeafKind::SourceError ||
        leaf.kind is @syntax.LeafKind::SourceSkipped
    }
    if bad {
      return Some(child)
    }
  }
  None
}
