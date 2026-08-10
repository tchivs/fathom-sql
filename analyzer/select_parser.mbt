/// Byte-level re-parser over the flat token-leaf CST (D-01): recovers token
/// bytes with flattened spans (`source_tokens`) and splits a SELECT body into
/// per-clause slices with paren-depth awareness. Keywords are matched only on
/// whole token bytes (`bytes_equal_ci`), and paren depth only counts whole
/// tokens equal to `(`/`)`, so string/quoted-identifier contents can never
/// trigger a clause boundary (Pitfall 1).

/// Max paren depth before the re-parser bails to a requires-complete-parse
/// diagnostic instead of recursing (T-05-02-01, mirroring parser
/// max_recursion_depth).
const MAX_PAREN_DEPTH : Int = 128

/// Source-token leaf bytes of a node in source order with flattened spans
/// (trivia, error, and skipped leaves are ignored — only SourceToken leaves
/// carry grammar tokens). Twin of `source_token_texts` that carries spans
/// (D-01); returns (token_bytes, start_byte, end_byte) triples to avoid naming
/// @source.Span and importing source.
fn source_tokens(node : @syntax.SyntaxNode, source_bytes : Bytes) -> Array[(Bytes, Int, Int)] {
  let tokens : Array[(Bytes, Int, Int)] = []
  for element in node.children() {
    match element {
      @syntax.SyntaxElement::Leaf(leaf) => {
        if leaf.kind is @syntax.LeafKind::SourceToken {
          let start = leaf.span.start_byte
          let end = leaf.span.end_byte
          if start >= 0 && start <= end && end <= source_bytes.length() {
            tokens.push((source_bytes[start:end].to_owned(), start, end))
          }
        }
      }
      @syntax.SyntaxElement::ChildNode(_) => ()
    }
  }
  tokens
}

/// Whole-token clause keyword at paren depth 0 (D-01). GROUP/ORDER are
/// handled by the caller with BY lookahead where needed; here they map to
/// their clause kinds directly and the splitter stops interpretation.
fn clause_keyword(bytes : Bytes, depth : Int) -> ClauseKind? {
  if depth != 0 {
    return None
  }
  if bytes_equal_ci(bytes, b"FROM") { Some(From) }
  else if bytes_equal_ci(bytes, b"WHERE") { Some(Where) }
  else if bytes_equal_ci(bytes, b"GROUP") { Some(GroupBy) }
  else if bytes_equal_ci(bytes, b"HAVING") { Some(Having) }
  else if bytes_equal_ci(bytes, b"QUALIFY") { Some(Qualify) }
  else if bytes_equal_ci(bytes, b"ORDER") { Some(OrderBy) }
  else if bytes_equal_ci(bytes, b"LIMIT") { Some(Limit) }
  else if bytes_equal_ci(bytes, b"WINDOW") { Some(Window) }
  else if bytes_equal_ci(bytes, b"UNION") { Some(SetOpUnion) }
  else { None }
}

/// True when a whole token is identifier-like for name resolution: not a
/// clause keyword, not a string literal (`'`), not `*`, and not a numeric
/// literal. Quoted identifiers (backtick/`"`) count as identifier-like.
fn is_identifier_token(bytes : Bytes) -> Bool {
  if bytes.length() == 0 {
    return false
  }
  let first = bytes[0].to_int()
  if first == 96 || first == 34 { return true } // quoted identifier
  if first == 39 { return false } // ' string literal
  if first == 42 { return false } // * wildcard
  if first >= 48 && first <= 57 { return false } // digit literal
  clause_keyword(bytes, 0) is None
}

/// Splits a SELECT body's token stream into a minimal SelectCore. The leading
/// SELECT [DISTINCT|ALL] prefix is consumed, then tokens at paren depth 0 are
/// grouped into SelectList items (comma-separated) until FROM; the FROM clause
/// captures the first bare table name. Other clause keywords stop
/// interpretation (their tokens stay unparsed for 05-03). Returns None when
/// paren depth overflows (T-05-02-01).
fn split_select_clauses(tokens : Array[(Bytes, Int, Int)]) -> SelectCore? {
  let length = tokens.length()
  let mut index = 0
  if index < length && bytes_equal_ci(tokens[index].0, b"SELECT") {
    index = index + 1
  }
  if index < length &&
    (bytes_equal_ci(tokens[index].0, b"DISTINCT") ||
    bytes_equal_ci(tokens[index].0, b"DISTINCTROW") ||
    bytes_equal_ci(tokens[index].0, b"ALL")) {
    index = index + 1
  }
  let mut depth = 0
  let mut phase = 0 // 0 = select list, 1 = from clause
  let mut current : Array[TokenSlice] = []
  let select_items : Array[SelectItem] = []
  let from_items : Array[FromItem] = []
  while index < length {
    let (bytes, start, end) = tokens[index]
    let slice = { bytes: bytes, start_byte: start, end_byte: end }
    if bytes == b"(" {
      depth = depth + 1
      if depth > MAX_PAREN_DEPTH { return None }
      if phase == 0 { current.push(slice) }
      index = index + 1
      continue
    }
    if bytes == b")" {
      depth = depth - 1
      if depth < 0 { depth = 0 }
      if phase == 0 { current.push(slice) }
      index = index + 1
      continue
    }
    if depth == 0 {
      match clause_keyword(bytes, 0) {
        Some(From) => {
          if phase == 0 {
            if current.length() > 0 {
              select_items.push({ tokens: current })
              current = []
            }
            phase = 1
          }
        }
        Some(_) => {
          // Other clause boundary (WHERE/GROUP BY/.../UNION): interpretation
          // stops; those clauses are filled by 05-03.
          break
        }
        None => {
          if phase == 0 {
            if bytes == b"," {
              if current.length() > 0 {
                select_items.push({ tokens: current })
                current = []
              }
            } else {
              current.push(slice)
            }
          } else {
            if from_items.length() == 0 && is_identifier_token(bytes) {
              from_items.push({ name: slice })
            }
          }
        }
      }
    } else if phase == 0 {
      // Inside parens: keep accumulating the select item (function args /
      // subqueries) so a later bare identifier isn't misattributed.
      current.push(slice)
    }
    index = index + 1
  }
  if phase == 0 && current.length() > 0 {
    select_items.push({ tokens: current })
  }
  Some({
    select_list: select_items,
    from: from_items,
    where_tokens: [],
    group_by: [],
    having: [],
    qualify: [],
    order_by: [],
    limit: [],
    window: [],
  })
}
