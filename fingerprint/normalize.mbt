/// Lossless CST -> canonical bytes (D-06): fold only syntactic trivia.
///
/// Per-leaf rules:
/// - `SourceTrivia`: comment / BOM -> dropped entirely; whitespace / newline
///   -> collapse to at most one 0x20 separator, emitted only between two
///   emitted tokens (leading/trailing trivia emit no bytes; adjacent
///   zero-width token pairs do not gain a separator — Open Question 3 /
///   flagged assumptions resolved).
/// - `SourceToken`: if `@dialect.classification_of` matches (D-28 single
///   keyword source — no second keyword table, Pitfall 14 / naming gate),
///   emit the ASCII lowercase canonical word; otherwise emit the raw bytes
///   verbatim, preserving identifier spelling & case, literal content, and
///   quote style (FING-01 retention contract).
/// - `SourceError` / `SourceSkipped`: emit raw bytes verbatim — normalize is
///   a total function (any input, including empty/error trees, yields a
///   deterministic fingerprint); it is semantically meaningful only on valid
///   statements.
pub fn normalize(
  root : @syntax.SyntaxNode,
  source : @source.SourceText,
  context : @dialect.DialectContext,
) -> Bytes {
  let normalizer = Normalizer::new(root.text_len())
  normalize_node(root, source, context, normalizer)
  normalizer.buf.to_bytes()
}

struct Normalizer {
  buf : @buffer.Buffer
  mut pending_space : Bool
}

fn Normalizer::new(size_hint : Int) -> Normalizer {
  { buf: @buffer.Buffer::Buffer(size_hint=size_hint), pending_space: false }
}

/// Emit the inter-token separator if a whitespace run preceded this token and
/// the buffer is non-empty (never a leading space). Clears the pending flag.
fn Normalizer::emit_separator(self : Normalizer) -> Unit {
  if self.pending_space && self.buf.length() > 0 {
    self.buf.write_bytes(b" ")
  }
  self.pending_space = false
}

fn Normalizer::emit_token_bytes(self : Normalizer, bytes : Bytes) -> Unit {
  self.emit_separator()
  self.buf.write_bytes(bytes)
}

fn normalize_node(
  node : @syntax.SyntaxNode,
  source : @source.SourceText,
  context : @dialect.DialectContext,
  normalizer : Normalizer,
) -> Unit {
  for child in node.children() {
    match child {
      @syntax.SyntaxElement::ChildNode(child_node) =>
        normalize_node(child_node, source, context, normalizer)
      @syntax.SyntaxElement::Leaf(leaf) =>
        normalize_leaf(leaf, source, context, normalizer)
    }
  }
}

fn normalize_leaf(
  leaf : @syntax.SyntaxLeaf,
  source : @source.SourceText,
  context : @dialect.DialectContext,
  normalizer : Normalizer,
) -> Unit {
  let bytes = match source.slice(leaf.span) {
    Some(bytes) => bytes
    None => return
  }
  match leaf.kind {
    @syntax.LeafKind::SourceTrivia => {
      if is_comment(bytes) || is_bom(bytes) {
        () // comment / BOM dropped entirely
      } else {
        normalizer.pending_space = true // whitespace / newline run
      }
    }
    @syntax.LeafKind::SourceToken => {
      match @dialect.classification_of(context, bytes) {
        Some(entry) => normalizer.emit_token_bytes(ascii_case_fold(entry.word))
        None => normalizer.emit_token_bytes(bytes)
      }
    }
    @syntax.LeafKind::SourceError | @syntax.LeafKind::SourceSkipped => {
      normalizer.emit_token_bytes(bytes)
    }
  }
}

/// `/* ... */` block comments, `--` line comments, and `#` line comments
/// (mirror of formatter/layout.mbt is_comment — Doris treats `#` as a
/// comment; the lexer already routed trivia to SourceTrivia per dialect).
fn is_comment(raw : Bytes) -> Bool {
  if raw.length() >= 2 && raw[0].to_int() == 47 && raw[1].to_int() == 42 {
    return true
  }
  if raw.length() >= 2 && raw[0].to_int() == 45 && raw[1].to_int() == 45 {
    return true
  }
  if raw.length() >= 1 && raw[0].to_int() == 35 {
    return true
  }
  false
}

/// UTF-8 BOM (mirror of formatter/layout.mbt is_bom).
fn is_bom(raw : Bytes) -> Bool {
  raw.length() == 3 && raw[0].to_int() == 0xef && raw[1].to_int() == 0xbb &&
    raw[2].to_int() == 0xbf
}

/// ASCII A-Z -> a-z byte-wise fold (same helper shape as
/// formatter/case.mbt ascii_case_fold — keyword canonical words are ASCII
/// uppercase by construction; this is a byte case fold, NOT a second keyword
/// classification table, so D-28 is preserved).
fn ascii_case_fold(raw : Bytes) -> Bytes {
  let out : Array[Byte] = []
  let mut index = 0
  while index < raw.length() {
    let byte = raw[index].to_int()
    let folded = if byte >= 65 && byte <= 90 { byte + 32 } else { byte }
    out.push(folded.to_byte())
    index = index + 1
  }
  Bytes::from_array(out)
}
