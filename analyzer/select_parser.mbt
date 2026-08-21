/// Byte-level re-parser over the flat token-leaf CST (D-01): recovers token
/// bytes with flattened spans (`source_tokens`) and splits a SELECT statement
/// into a full `SelectModel` — WITH/CTE prefix, all clauses (SELECT list /
/// FROM+JOIN / WHERE / GROUP BY / HAVING / QUALIFY / WINDOW / ORDER BY /
/// LIMIT) with paren-depth awareness, and UNION chains. Keywords are matched
/// only on whole token bytes (`bytes_equal_ci`) and paren depth only counts
/// whole tokens equal to `(`/`)`, so string/quoted-identifier contents can
/// never trigger a clause boundary or unbalance the depth counter (Pitfall 1).
///
/// The parser accepts only what the frozen Doris parser accepts: UNION chains
/// are split; EXCEPT is a projection modifier handled inside a select item;
/// INTERSECT is not in the acceptance set and is never fabricated as a branch
/// (Pitfall 2).

///|
/// Max paren depth before the re-parser bails to a requires-complete-parse
/// diagnostic instead of recursing (T-05-03-01, mirroring parser
/// max_recursion_depth).
const MAX_PAREN_DEPTH : Int = 128

///|
/// Source-token leaf bytes of a node in source order with flattened spans
/// (trivia, error, and skipped leaves are ignored — only SourceToken leaves
/// carry grammar tokens). Twin of `source_token_texts` that carries spans
/// (D-01); returns (token_bytes, start_byte, end_byte) triples to avoid naming
/// @source.Span and importing source.
pub fn source_tokens(
  node : @syntax.SyntaxNode,
  source_bytes : Bytes,
) -> Array[(Bytes, Int, Int)] {
  let tokens : Array[(Bytes, Int, Int)] = []
  for element in node.children() {
    match element {
      @syntax.SyntaxElement::Leaf(leaf) =>
        if leaf.kind is @syntax.LeafKind::SourceToken {
          let start = leaf.span.start_byte
          let end = leaf.span.end_byte
          if start >= 0 && start <= end && end <= source_bytes.length() {
            tokens.push((source_bytes[start:end].to_owned(), start, end))
          }
        }
      @syntax.SyntaxElement::ChildNode(_) => ()
    }
  }
  tokens
}

///|
/// Words that are always top-level SELECT clause boundaries at paren depth 0
/// (D-01). GROUP/ORDER are handled separately (they only break on a following
/// BY — Pitfall 2).
fn is_boundary_word(bytes : Bytes) -> Bool {
  bytes_equal_ci(bytes, b"FROM") ||
  bytes_equal_ci(bytes, b"WHERE") ||
  bytes_equal_ci(bytes, b"HAVING") ||
  bytes_equal_ci(bytes, b"QUALIFY") ||
  bytes_equal_ci(bytes, b"LIMIT") ||
  bytes_equal_ci(bytes, b"WINDOW") ||
  bytes_equal_ci(bytes, b"UNION")
}

///|
/// Reserved words that can never be unquoted identifiers in an expression.
/// This is the analyzer's dialect-independent approximation of the parser's
/// `is_reserved_word` (the analyzer cannot import dialect, D-21). GROUP/ORDER
/// are intentionally absent so a column named `order` (when not followed by
/// BY) stays resolvable (Pitfall 2); quoted identifiers are always
/// identifier-like and never keywords (D-03).
fn is_reserved_word(bytes : Bytes) -> Bool {
  is_boundary_word(bytes) ||
  bytes_equal_ci(bytes, b"AND") ||
  bytes_equal_ci(bytes, b"OR") ||
  bytes_equal_ci(bytes, b"NOT") ||
  bytes_equal_ci(bytes, b"IN") ||
  bytes_equal_ci(bytes, b"IS") ||
  bytes_equal_ci(bytes, b"BETWEEN") ||
  bytes_equal_ci(bytes, b"LIKE") ||
  bytes_equal_ci(bytes, b"EXISTS") ||
  bytes_equal_ci(bytes, b"ASC") ||
  bytes_equal_ci(bytes, b"DESC") ||
  bytes_equal_ci(bytes, b"NULL") ||
  bytes_equal_ci(bytes, b"TRUE") ||
  bytes_equal_ci(bytes, b"FALSE") ||
  bytes_equal_ci(bytes, b"NULLS") ||
  bytes_equal_ci(bytes, b"OVER") ||
  bytes_equal_ci(bytes, b"AS") ||
  bytes_equal_ci(bytes, b"BY") ||
  bytes_equal_ci(bytes, b"ON") ||
  bytes_equal_ci(bytes, b"USING") ||
  bytes_equal_ci(bytes, b"CASE") ||
  bytes_equal_ci(bytes, b"WHEN") ||
  bytes_equal_ci(bytes, b"THEN") ||
  bytes_equal_ci(bytes, b"ELSE") ||
  bytes_equal_ci(bytes, b"END") ||
  bytes_equal_ci(bytes, b"ALL") ||
  bytes_equal_ci(bytes, b"DISTINCT") ||
  bytes_equal_ci(bytes, b"SELECT") ||
  bytes_equal_ci(bytes, b"WITH") ||
  bytes_equal_ci(bytes, b"RECURSIVE") ||
  bytes_equal_ci(bytes, b"LEFT") ||
  bytes_equal_ci(bytes, b"RIGHT") ||
  bytes_equal_ci(bytes, b"FULL") ||
  bytes_equal_ci(bytes, b"INNER") ||
  bytes_equal_ci(bytes, b"CROSS") ||
  bytes_equal_ci(bytes, b"NATURAL") ||
  bytes_equal_ci(bytes, b"OUTER") ||
  bytes_equal_ci(bytes, b"JOIN")
}

///|
/// True when a whole token is identifier-like for name resolution: a quoted
/// identifier (backtick/`"`), or an unquoted word that is not a reserved
/// keyword, a string literal (`'`), `*`, a numeric literal, or punctuation/
/// operator symbols. ASCII symbol bytes are never identifier starts; UTF-8
/// multibyte starts remain identifier-like.
fn is_identifier_token(bytes : Bytes) -> Bool {
  if bytes.length() == 0 {
    return false
  }
  let first = bytes[0].to_int()
  if first == 96 || first == 34 {
    return true
  } // quoted identifier
  if first == 39 {
    return false
  } // ' string literal
  if first == 42 {
    return false
  } // * wildcard
  if first >= 48 && first <= 57 {
    return false
  } // digit literal
  // ASCII operators/punctuation are never identifiers (`=`, `<`, `+`, ...).
  if first < 128 &&
    !(first >= 65 && first <= 90) && // A-Z
    !(first >= 97 && first <= 122) && // a-z
    first != 95 { // _
    return false
  }
  !is_reserved_word(bytes)
}

///|
/// Words that must not be taken as a bare table alias in a FROM item
/// (JOIN structure, clause boundaries, table options).
fn is_from_suffix_word(bytes : Bytes) -> Bool {
  is_boundary_word(bytes) ||
  is_reserved_word(bytes) ||
  bytes_equal_ci(bytes, b"PARTITION") ||
  bytes_equal_ci(bytes, b"SAMPLE") ||
  bytes_equal_ci(bytes, b"TABLESAMPLE") ||
  bytes_equal_ci(bytes, b"TABLET")
}

///|
/// True when `tokens[index]` starts a FROM-suffix boundary that must not be
/// consumed as a bare table/subquery alias: a boundary/suffix word, or
/// GROUP/ORDER when followed by BY (Pitfall 2). `SELECT a FROM t ORDER BY a`
/// must not bind `ORDER` as an alias of `t`.
fn is_from_clause_boundary(
  tokens : Array[(Bytes, Int, Int)],
  index : Int,
) -> Bool {
  if index >= tokens.length() {
    return true
  }
  let bytes = tokens[index].0
  if is_from_suffix_word(bytes) {
    return true
  }
  if (bytes_equal_ci(bytes, b"GROUP") || bytes_equal_ci(bytes, b"ORDER")) &&
    index + 1 < tokens.length() &&
    bytes_equal_ci(tokens[index + 1].0, b"BY") {
    return true
  }
  false
}

///|
/// Clause keyword at paren depth 0 with GROUP/ORDER two-word detection
/// (Pitfall 2): GROUP/ORDER only break when the next significant token is BY.
/// Strings and quoted identifiers can never match (whole-token byte compare).
fn clause_kind_at(
  tokens : Array[(Bytes, Int, Int)],
  index : Int,
  depth : Int,
) -> ClauseKind? {
  if depth != 0 {
    return None
  }
  if index >= tokens.length() {
    return None
  }
  let bytes = tokens[index].0
  if bytes_equal_ci(bytes, b"FROM") {
    return Some(From)
  }
  if bytes_equal_ci(bytes, b"WHERE") {
    return Some(Where)
  }
  if bytes_equal_ci(bytes, b"GROUP") {
    if index + 1 < tokens.length() && bytes_equal_ci(tokens[index + 1].0, b"BY") {
      return Some(GroupBy)
    }
    return None
  }
  if bytes_equal_ci(bytes, b"HAVING") {
    return Some(Having)
  }
  if bytes_equal_ci(bytes, b"QUALIFY") {
    return Some(Qualify)
  }
  if bytes_equal_ci(bytes, b"ORDER") {
    if index + 1 < tokens.length() && bytes_equal_ci(tokens[index + 1].0, b"BY") {
      return Some(OrderBy)
    }
    return None
  }
  if bytes_equal_ci(bytes, b"LIMIT") {
    return Some(Limit)
  }
  if bytes_equal_ci(bytes, b"WINDOW") {
    return Some(Window)
  }
  if bytes_equal_ci(bytes, b"UNION") {
    return Some(SetOpUnion)
  }
  None
}

///|
/// Index of the `)` matching the `(` at `open`, or `length` when unbalanced.
pub fn matching_paren(tokens : Array[(Bytes, Int, Int)], open : Int) -> Int {
  let mut depth = 0
  let mut i = open
  while i < tokens.length() {
    if tokens[i].0 == b"(" {
      depth = depth + 1
    } else if tokens[i].0 == b")" {
      depth = depth - 1
      if depth == 0 {
        return i
      }
    }
    i = i + 1
  }
  tokens.length()
}

///|
/// Index of the `)` matching the `(` at `open` in a TokenSlice list, or
/// `length` when unbalanced (WR-03, window-spec skipping).
fn matching_paren_slices(tokens : Array[TokenSlice], open : Int) -> Int {
  let mut depth = 0
  let mut i = open
  while i < tokens.length() {
    if tokens[i].bytes == b"(" {
      depth = depth + 1
    } else if tokens[i].bytes == b")" {
      depth = depth - 1
      if depth == 0 {
        return i
      }
    }
    i = i + 1
  }
  tokens.length()
}

///|
/// Extracts dotted name references from a token slice list. A reference is a
/// maximal run of identifier segments separated by `.`, optionally ending in
/// `*` (then `star` is set) or followed by `(` (then `is_call` is set).
/// Subquery groups `(SELECT ...)` / `(WITH ...)` are skipped whole so their
/// columns never resolve against the enclosing scope; function-call parens
/// (`count(a)`) keep collecting the argument refs.
pub fn collect_refs(tokens : Array[TokenSlice]) -> Array[NameRef] {
  let refs : Array[NameRef] = []
  let length = tokens.length()
  let mut i = 0
  while i < length {
    let bytes = tokens[i].bytes
    // WR-03: skip a window-function OVER specification whole so its
    // PARTITION BY / ORDER BY / ROWS-RANGE keywords and window columns never
    // resolve as column references (`SUM(x) OVER (PARTITION BY y ...)` must
    // not report y / PARTITION / ORDER as unknown-column). Covers both the
    // inline spec `OVER (...)` and the named-window reference `OVER w`.
    if bytes_equal_ci(bytes, b"OVER") {
      if i + 1 < length && tokens[i + 1].bytes == b"(" {
        let close = matching_paren_slices(tokens, i + 1)
        i = if close < length { close + 1 } else { length }
        continue
      } else if i + 1 < length && is_identifier_token(tokens[i + 1].bytes) {
        i = i + 2
        continue
      }
    }
    if is_identifier_token(bytes) {
      let parts : Array[TokenSlice] = []
      let start_byte = tokens[i].start_byte
      let mut end_byte = tokens[i].end_byte
      let mut star = false
      let mut j = i
      let mut run_ok = true
      while j < length && run_ok {
        if is_identifier_token(tokens[j].bytes) {
          parts.push(tokens[j])
          end_byte = tokens[j].end_byte
          j = j + 1
        } else if tokens[j].bytes == b"." {
          if j + 1 < length && is_identifier_token(tokens[j + 1].bytes) {
            j = j + 1 // the identifier is consumed by the next iteration
          } else if j + 1 < length && tokens[j + 1].bytes == b"*" {
            star = true
            end_byte = tokens[j + 1].end_byte
            j = j + 2
            run_ok = false
          } else {
            run_ok = false
          }
        } else {
          run_ok = false
        }
      }
      let is_call = !star && j < length && tokens[j].bytes == b"("
      let call_args : Array[TokenSlice] = if is_call {
        // Capture the tokens between the call's `(` and its matching `)` —
        // parens excluded — for depth-0 argument counting (D-04).
        let args : Array[TokenSlice] = []
        let mut k = j + 1
        let mut arg_depth = 1
        while k < length && arg_depth > 0 {
          if tokens[k].bytes == b"(" {
            arg_depth = arg_depth + 1
          } else if tokens[k].bytes == b")" {
            arg_depth = arg_depth - 1
            if arg_depth == 0 {
              break
            }
          }
          args.push(tokens[k])
          k = k + 1
        }
        args
      } else {
        []
      }
      refs.push({ parts, star, is_call, call_args, start_byte, end_byte })
      i = j
    } else if bytes == b"(" {
      // Subquery group: skip whole without collecting inner refs.
      if i + 1 < length &&
        (
          bytes_equal_ci(tokens[i + 1].bytes, b"SELECT") ||
          bytes_equal_ci(tokens[i + 1].bytes, b"WITH")
        ) {
        i = i + 1
        let mut group_depth = 1
        while i < length && group_depth > 0 {
          if tokens[i].bytes == b"(" {
            group_depth = group_depth + 1
          } else if tokens[i].bytes == b")" {
            group_depth = group_depth - 1
          }
          i = i + 1
        }
        continue
      }
      i = i + 1
    } else {
      i = i + 1
    }
  }
  refs
}

///|
/// True when `bytes` is an infix operator token (arithmetic, comparison, or
/// logical). Used to reject trailing bare aliases for binary expressions
/// (CR-01): `SELECT price * qty` must not bind `qty` as an alias.
fn is_infix_operator(bytes : Bytes) -> Bool {
  bytes == b"+" ||
  bytes == b"-" ||
  bytes == b"*" ||
  bytes == b"/" ||
  bytes == b"%" ||
  bytes == b"||" ||
  bytes == b"=" ||
  bytes == b"<" ||
  bytes == b">" ||
  bytes == b"<=" ||
  bytes == b">=" ||
  bytes == b"!=" ||
  bytes == b"<>" ||
  bytes == b"&" ||
  bytes == b"|" ||
  bytes == b"^" ||
  bytes == b"AND" ||
  bytes == b"OR" ||
  bytes == b"LIKE" ||
  bytes == b"IN" ||
  bytes == b"IS" ||
  bytes == b"BETWEEN"
}

///|
/// True when a paren-depth-0 infix operator appears in `tokens`. Operators
/// inside parenthesized subexpressions (e.g. the `*` in `count(*)` or `+` in
/// `(a + b)`) are not at the top level and do not disqualify a trailing bare
/// alias (CR-01).
fn has_top_level_operator(tokens : Array[TokenSlice]) -> Bool {
  let mut depth = 0
  for t in tokens {
    let bytes = t.bytes
    if bytes == b"(" {
      depth = depth + 1
    } else if bytes == b")" {
      if depth > 0 {
        depth = depth - 1
      }
    } else if depth == 0 && is_infix_operator(bytes) {
      return true
    }
  }
  false
}

///|
/// Builds a SelectItem from one comma-delimited projection slice: splits the
/// AS alias at the first top-level AS, detects a trailing bare alias, marks
/// star projections (`*`, `t.*`, `db.t.*`, `* EXCEPT (cols)`), and extracts
/// the expression's name references.
fn build_select_item(tokens : Array[TokenSlice]) -> SelectItem {
  // First top-level AS.
  let mut as_index = -1
  let mut depth = 0
  let mut i = 0
  while i < tokens.length() {
    let bytes = tokens[i].bytes
    if bytes == b"(" {
      depth = depth + 1
    } else if bytes == b")" {
      if depth > 0 {
        depth = depth - 1
      }
    } else if depth == 0 && bytes_equal_ci(bytes, b"AS") {
      as_index = i
      break
    }
    i = i + 1
  }
  let mut body_tokens : Array[TokenSlice] = []
  let mut alias : String? = None
  let mut alias_slice : TokenSlice? = None
  if as_index >= 0 {
    for j in 0..<as_index {
      body_tokens.push(tokens[j])
    }
    if as_index + 1 < tokens.length() {
      let a = tokens[as_index + 1]
      alias = Some(identifier_text(a.bytes))
      alias_slice = Some(a)
    }
  } else {
    body_tokens = tokens
  }
  // Trailing bare alias (only when the expression has at least one token
  // before it, the last token is identifier-like and not preceded by `.`,
  // and no paren-depth-0 infix operator precedes it). CR-01: `SELECT price *
  // qty` / `a + b` / `a >= b` must NOT bind the right operand as an alias —
  // a top-level infix operator means the trailing identifier is the right
  // operand of a binary expression, not an implicit alias. `count(*) x` and
  // `(a + b) c` still alias (their operators sit inside parens).
  if as_index < 0 && body_tokens.length() >= 2 {
    let last = body_tokens[body_tokens.length() - 1]
    let prev = body_tokens[body_tokens.length() - 2]
    if is_identifier_token(last.bytes) &&
      prev.bytes != b"." &&
      last.bytes != b"*" {
      let prefix : Array[TokenSlice] = []
      for j in 0..<(body_tokens.length() - 1) {
        prefix.push(body_tokens[j])
      }
      if !has_top_level_operator(prefix) {
        alias = Some(identifier_text(last.bytes))
        alias_slice = Some(last)
        body_tokens = prefix
      }
    }
  }
  // Star projection: `*` or `t.*` / `db.t.*` (last token `*` preceded by `.`),
  // or `* EXCEPT (cols)` (first token `*` with a top-level EXCEPT suffix).
  let except_cols : Array[TokenSlice] = []
  if body_tokens.length() > 0 && body_tokens[0].bytes == b"*" {
    // Capture `EXCEPT ( ... )` after a leading `*`: the parenthesized
    // column-name token slices are collected into except_cols (D-03) and the
    // EXCEPT clause is stripped from the body. Each top-level identifier
    // between the parens is one exclusion column; quoted slices keep their
    // quotes for byte-exact matching at expand_star.
    let mut except_index = -1
    let mut d = 0
    let mut j = 0
    while j < body_tokens.length() {
      let b = body_tokens[j].bytes
      if b == b"(" {
        d = d + 1
      } else if b == b")" {
        if d > 0 {
          d = d - 1
        }
      } else if d == 0 && bytes_equal_ci(b, b"EXCEPT") {
        except_index = j
        break
      }
      j = j + 1
    }
    if except_index >= 0 {
      let open = except_index + 1
      let close = matching_paren_slices(body_tokens, open)
      if close < body_tokens.length() {
        let mut k = open + 1
        while k < close {
          if is_identifier_token(body_tokens[k].bytes) {
            except_cols.push(body_tokens[k])
          }
          k = k + 1
        }
      }
      let arr : Array[TokenSlice] = []
      for k in 0..<except_index {
        arr.push(body_tokens[k])
      }
      body_tokens = arr
    }
  }
  let star = body_tokens.length() > 0 &&
    body_tokens[body_tokens.length() - 1].bytes == b"*"
  let star_qualifier : NameRef? = if star {
    if body_tokens.length() >= 3 &&
      body_tokens[body_tokens.length() - 2].bytes == b"." {
      let qual : Array[TokenSlice] = []
      for j in 0..<(body_tokens.length() - 2) {
        qual.push(body_tokens[j])
      }
      let refs = collect_refs(qual)
      if refs.length() > 0 {
        Some(refs[0])
      } else {
        None
      }
    } else {
      None
    }
  } else {
    None
  }
  let refs = if star { [] } else { collect_refs(body_tokens) }
  {
    tokens: body_tokens,
    alias,
    alias_slice,
    star,
    star_qualifier,
    refs,
    except_cols,
  }
}

///|
/// Collects name references from a clause's token slice list. Used for
/// WHERE/GROUP BY/HAVING/QUALIFY/ORDER BY: accumulates all tokens up to the
/// next depth-0 clause boundary (or the end of the range), then extracts refs.
fn collect_clause_refs(
  tokens : Array[(Bytes, Int, Int)],
  start : Int,
  end : Int,
) -> (Array[NameRef], Int)? {
  let slices : Array[TokenSlice] = []
  let mut index = start
  let mut depth = 0
  while index < end {
    match clause_kind_at(tokens, index, depth) {
      Some(_) => break
      None => {
        let (bytes, s, e) = tokens[index]
        if bytes == b"(" {
          depth = depth + 1
          if depth > MAX_PAREN_DEPTH {
            return None
          }
        } else if bytes == b")" {
          if depth > 0 {
            depth = depth - 1
          }
        }
        slices.push({ bytes, start_byte: s, end_byte: e })
        index = index + 1
      }
    }
  }
  Some((collect_refs(slices), index))
}

///|
/// Collects raw token slices up to the next depth-0 clause boundary (for
/// LIMIT / WINDOW, which are not name-resolved).
fn collect_clause_tokens(
  tokens : Array[(Bytes, Int, Int)],
  start : Int,
  end : Int,
) -> (Array[TokenSlice], Int)? {
  let slices : Array[TokenSlice] = []
  let mut index = start
  let mut depth = 0
  while index < end {
    match clause_kind_at(tokens, index, depth) {
      Some(_) => break
      None => {
        let (bytes, s, e) = tokens[index]
        if bytes == b"(" {
          depth = depth + 1
          if depth > MAX_PAREN_DEPTH {
            return None
          }
        } else if bytes == b")" {
          if depth > 0 {
            depth = depth - 1
          }
        }
        slices.push({ bytes, start_byte: s, end_byte: e })
        index = index + 1
      }
    }
  }
  Some((slices, index))
}

///|
/// Rebuilds a core with a set-op attached (UNION chains, Pitfall 2).
fn core_with_set_op(core : SelectCore, op : String) -> SelectCore {
  {
    select_list: core.select_list,
    from: core.from,
    joins: core.joins,
    where_refs: core.where_refs,
    group_by: core.group_by,
    having: core.having,
    qualify: core.qualify,
    order_by: core.order_by,
    limit: core.limit,
    window: core.window,
    set_op: Some(op),
  }
}

///|
/// Parses one SELECT core starting at `start` within `[0, end)`. Returns the
/// core and the index just past it (at the next boundary or `end`).
fn parse_core(
  tokens : Array[(Bytes, Int, Int)],
  start : Int,
  end : Int,
  nest : Int,
) -> (SelectCore, Int)? {
  let mut index = start
  if index >= end || !bytes_equal_ci(tokens[index].0, b"SELECT") {
    return None
  }
  index = index + 1
  // SELECT [DISTINCT | DISTINCTROW | ALL].
  if index < end &&
    (
      bytes_equal_ci(tokens[index].0, b"DISTINCT") ||
      bytes_equal_ci(tokens[index].0, b"DISTINCTROW") ||
      bytes_equal_ci(tokens[index].0, b"ALL")
    ) {
    index = index + 1
  }
  // EXCEPT projection modifier: `SELECT [ALL] EXCEPT (cols)`.
  if index < end && bytes_equal_ci(tokens[index].0, b"EXCEPT") {
    index = index + 1
    if index < end && tokens[index].0 == b"(" {
      let close = matching_paren(tokens, index)
      if close >= end {
        return None
      }
      index = close + 1
    }
  }
  // SELECT list.
  let select_items : Array[SelectItem] = []
  let mut item_tokens : Array[TokenSlice] = []
  let mut depth = 0
  while index < end {
    match clause_kind_at(tokens, index, depth) {
      Some(_) => break
      None => {
        let (bytes, s, e) = tokens[index]
        if depth == 0 && bytes == b"," {
          select_items.push(build_select_item(item_tokens))
          item_tokens = []
        } else {
          if bytes == b"(" {
            depth = depth + 1
            if depth > MAX_PAREN_DEPTH {
              return None
            }
          } else if bytes == b")" {
            if depth > 0 {
              depth = depth - 1
            }
          }
          item_tokens.push({ bytes, start_byte: s, end_byte: e })
        }
        index = index + 1
      }
    }
  }
  if item_tokens.length() > 0 {
    select_items.push(build_select_item(item_tokens))
  }
  // Remaining clauses.
  let from_items : Array[FromItem] = []
  let join_items : Array[FromItem] = []
  let mut where_refs : Array[NameRef] = []
  let mut group_by : Array[NameRef] = []
  let mut having : Array[NameRef] = []
  let mut qualify : Array[NameRef] = []
  let mut order_by : Array[NameRef] = []
  let mut limit_tokens : Array[TokenSlice] = []
  let mut window_tokens : Array[TokenSlice] = []
  let mut set_op : String? = None
  let mut done = false
  while index < end && !done {
    match clause_kind_at(tokens, index, 0) {
      // SelectList is never returned by clause_kind_at (the select list is
      // consumed before this loop); the arm exists only for exhaustiveness.
      Some(SelectList) => index = index + 1
      Some(From) => {
        index = index + 1
        match parse_from(tokens, index, end, nest) {
          Some((from, joins, next)) => {
            for item in from {
              from_items.push(item)
            }
            for item in joins {
              join_items.push(item)
            }
            index = next
          }
          None => return None
        }
      }
      Some(Where) => {
        index = index + 1
        match collect_clause_refs(tokens, index, end) {
          Some((refs, next)) => {
            where_refs = refs
            index = next
          }
          None => return None
        }
      }
      Some(GroupBy) => {
        index = index + 2 // GROUP BY
        match collect_clause_refs(tokens, index, end) {
          Some((refs, next)) => {
            group_by = refs
            index = next
          }
          None => return None
        }
      }
      Some(Having) => {
        index = index + 1
        match collect_clause_refs(tokens, index, end) {
          Some((refs, next)) => {
            having = refs
            index = next
          }
          None => return None
        }
      }
      Some(Window) => {
        index = index + 1
        match collect_clause_tokens(tokens, index, end) {
          Some((slices, next)) => {
            window_tokens = slices
            index = next
          }
          None => return None
        }
      }
      Some(Qualify) => {
        index = index + 1
        match collect_clause_refs(tokens, index, end) {
          Some((refs, next)) => {
            qualify = refs
            index = next
          }
          None => return None
        }
      }
      Some(OrderBy) => {
        index = index + 2 // ORDER BY
        match collect_clause_refs(tokens, index, end) {
          Some((refs, next)) => {
            order_by = refs
            index = next
          }
          None => return None
        }
      }
      Some(Limit) => {
        index = index + 1
        match collect_clause_tokens(tokens, index, end) {
          Some((slices, next)) => {
            limit_tokens = slices
            index = next
          }
          None => return None
        }
      }
      Some(SetOpUnion) => {
        let mut op = "UNION"
        if index + 1 < end && bytes_equal_ci(tokens[index + 1].0, b"ALL") {
          op = "UNION ALL"
        } else if index + 1 < end &&
          bytes_equal_ci(tokens[index + 1].0, b"DISTINCT") {
          op = "UNION DISTINCT"
        }
        set_op = Some(op)
        done = true
      }
      None =>
        // Skip unexpected tokens at depth 0 (INTO OUTFILE, table options).
        if index >= end {
          done = true
        } else if tokens[index].0 == b"(" {
          let close = matching_paren(tokens, index)
          if close >= end {
            return None
          }
          index = close + 1
        } else {
          index = index + 1
        }
    }
  }
  Some(
    (
      {
        select_list: select_items,
        from: from_items,
        joins: join_items,
        where_refs,
        group_by,
        having,
        qualify,
        order_by,
        limit: limit_tokens,
        window: window_tokens,
        set_op,
      },
      index,
    ),
  )
}

///|
/// Join modifier when tokens[index] starts a JOIN clause (`JOIN` or a
/// modifier [OUTER] JOIN), else None. Lookahead ensures a bare `LEFT`/`RIGHT`
/// column name is not misread as a join start.
fn join_clause_at(tokens : Array[(Bytes, Int, Int)], index : Int) -> String? {
  if index >= tokens.length() {
    return None
  }
  let bytes = tokens[index].0
  if bytes_equal_ci(bytes, b"JOIN") {
    return Some("JOIN")
  }
  let modifier : String? = if bytes_equal_ci(bytes, b"INNER") {
    Some("INNER")
  } else if bytes_equal_ci(bytes, b"LEFT") {
    Some("LEFT")
  } else if bytes_equal_ci(bytes, b"RIGHT") {
    Some("RIGHT")
  } else if bytes_equal_ci(bytes, b"FULL") {
    Some("FULL")
  } else if bytes_equal_ci(bytes, b"CROSS") {
    Some("CROSS")
  } else if bytes_equal_ci(bytes, b"NATURAL") {
    Some("NATURAL")
  } else {
    None
  }
  match modifier {
    Some(name) => {
      let mut look = index + 1
      if look < tokens.length() && bytes_equal_ci(tokens[look].0, b"OUTER") {
        look = look + 1
      }
      if look < tokens.length() && bytes_equal_ci(tokens[look].0, b"JOIN") {
        Some(name)
      } else {
        None
      }
    }
    None => None
  }
}

///|
/// Parses one FROM item (table ref or subquery) at `index`. The returned
/// `join` field is set from the pending join modifier (None for base refs).
fn parse_from_item(
  tokens : Array[(Bytes, Int, Int)],
  index : Int,
  end : Int,
  nest : Int,
  join : String?,
) -> (FromItem, Int)? {
  if index >= end {
    return None
  }
  // Subquery: `( query )` with an optional alias.
  if tokens[index].0 == b"(" {
    let close = matching_paren(tokens, index)
    if close >= end {
      return None
    }
    if nest >= MAX_PAREN_DEPTH {
      return None
    }
    match parse_model(tokens, index + 1, close, nest + 1) {
      Some(model) => {
        let mut after = close + 1
        let mut alias : String? = None
        let mut alias_slice : TokenSlice? = None
        if after < end && bytes_equal_ci(tokens[after].0, b"AS") {
          after = after + 1
          if after < end && is_identifier_token(tokens[after].0) {
            alias = Some(identifier_text(tokens[after].0))
            alias_slice = Some({
              bytes: tokens[after].0,
              start_byte: tokens[after].1,
              end_byte: tokens[after].2,
            })
            after = after + 1
          }
        } else if after < end &&
          is_identifier_token(tokens[after].0) &&
          !is_from_clause_boundary(tokens, after) {
          alias = Some(identifier_text(tokens[after].0))
          alias_slice = Some({
            bytes: tokens[after].0,
            start_byte: tokens[after].1,
            end_byte: tokens[after].2,
          })
          after = after + 1
        }
        return Some(
          (
            {
              name: None,
              alias,
              alias_slice,
              is_subquery: true,
              subquery: Some(model),
              join,
              depth: 0,
            },
            after,
          ),
        )
      }
      None => return None
    }
  }
  // Qualified table name: ident (`.` ident)*.
  let parts : Array[TokenSlice] = []
  let mut after = index
  while after < end && is_identifier_token(tokens[after].0) {
    parts.push({
      bytes: tokens[after].0,
      start_byte: tokens[after].1,
      end_byte: tokens[after].2,
    })
    after = after + 1
    if after < end && tokens[after].0 == b"." {
      after = after + 1
      if after >= end || !is_identifier_token(tokens[after].0) {
        break
      }
    } else {
      break
    }
  }
  if parts.length() == 0 {
    return None
  }
  let name_ref = {
    parts,
    star: false,
    is_call: false,
    call_args: [],
    start_byte: parts[0].start_byte,
    end_byte: parts[parts.length() - 1].end_byte,
  }
  // Alias.
  let mut alias : String? = None
  let mut alias_slice : TokenSlice? = None
  if after < end && bytes_equal_ci(tokens[after].0, b"AS") {
    after = after + 1
    if after < end && is_identifier_token(tokens[after].0) {
      alias = Some(identifier_text(tokens[after].0))
      alias_slice = Some({
        bytes: tokens[after].0,
        start_byte: tokens[after].1,
        end_byte: tokens[after].2,
      })
      after = after + 1
    }
  } else if after < end &&
    is_identifier_token(tokens[after].0) &&
    !is_from_clause_boundary(tokens, after) {
    alias = Some(identifier_text(tokens[after].0))
    alias_slice = Some({
      bytes: tokens[after].0,
      start_byte: tokens[after].1,
      end_byte: tokens[after].2,
    })
    after = after + 1
  }
  // Skip table options (PARTITION (..), SAMPLE/TABLESAMPLE/TABLET).
  let mut option_done = false
  while !option_done && after < end {
    let bytes = tokens[after].0
    if bytes_equal_ci(bytes, b"PARTITION") ||
      bytes_equal_ci(bytes, b"SAMPLE") ||
      bytes_equal_ci(bytes, b"TABLESAMPLE") ||
      bytes_equal_ci(bytes, b"TABLET") {
      after = after + 1
      if after < end && tokens[after].0 == b"(" {
        let close = matching_paren(tokens, after)
        if close >= end {
          return None
        }
        after = close + 1
      } else {
        while after < end &&
              !(clause_kind_at(tokens, after, 0) is Some(_)) &&
              tokens[after].0 != b"," &&
              !(join_clause_at(tokens, after) is Some(_)) {
          after = after + 1
        }
      }
    } else {
      option_done = true
    }
  }
  Some(
    (
      {
        name: Some(name_ref),
        alias,
        alias_slice,
        is_subquery: false,
        subquery: None,
        join,
        depth: 0,
      },
      after,
    ),
  )
}

///|
/// Parses the FROM clause starting at `index` (just after FROM). Returns
/// (base items, JOIN items, next index). Comma-separated refs land in `from`;
/// JOIN-attached refs land in `joins` with their join modifier.
fn parse_from(
  tokens : Array[(Bytes, Int, Int)],
  start : Int,
  end : Int,
  nest : Int,
) -> (Array[FromItem], Array[FromItem], Int)? {
  let from_items : Array[FromItem] = []
  let join_items : Array[FromItem] = []
  let mut index = start
  let mut pending_join : String? = None
  while index < end {
    match clause_kind_at(tokens, index, 0) {
      Some(_) => break
      None => ()
    }
    if tokens[index].0 == b"," {
      index = index + 1
      pending_join = None
      continue
    }
    match join_clause_at(tokens, index) {
      Some(modifier) => {
        pending_join = Some(modifier)
        index = index + 1
        if index < end && bytes_equal_ci(tokens[index].0, b"OUTER") {
          index = index + 1
        }
        if index < end && bytes_equal_ci(tokens[index].0, b"JOIN") {
          index = index + 1
        }
        continue
      }
      None => ()
    }
    match parse_from_item(tokens, index, end, nest, pending_join) {
      Some((item, next)) => {
        match pending_join {
          Some(_) => join_items.push(item)
          None => from_items.push(item)
        }
        index = next
        pending_join = None
        // Consume ON / USING join conditions (not name-resolved in this plan).
        if index < end &&
          (
            bytes_equal_ci(tokens[index].0, b"ON") ||
            bytes_equal_ci(tokens[index].0, b"USING")
          ) {
          index = index + 1
          let mut cond_depth = 0
          while index < end {
            match clause_kind_at(tokens, index, cond_depth) {
              Some(_) if cond_depth == 0 => break
              _ => {
                let bytes = tokens[index].0
                if bytes == b"(" {
                  cond_depth = cond_depth + 1
                  if cond_depth > MAX_PAREN_DEPTH {
                    return None
                  }
                } else if bytes == b")" {
                  if cond_depth > 0 {
                    cond_depth = cond_depth - 1
                  }
                } else if cond_depth == 0 && bytes == b"," {
                  break
                } else if cond_depth == 0 &&
                  join_clause_at(tokens, index) is Some(_) {
                  break
                }
                index = index + 1
              }
            }
          }
        }
      }
      None => break
    }
  }
  Some((from_items, join_items, index))
}

///|
/// Parses a WITH CTE prefix starting at `index` (just after WITH). Returns
/// the CTE definitions and the index just past the prefix.
fn parse_cte_prefix(
  tokens : Array[(Bytes, Int, Int)],
  start : Int,
  end : Int,
  nest : Int,
) -> (Array[CteDef], Int)? {
  let ctes : Array[CteDef] = []
  let mut index = start
  if index < end && bytes_equal_ci(tokens[index].0, b"RECURSIVE") {
    index = index + 1 // Doris rejects WITH RECURSIVE in the parser; skip defensively.
  }
  let mut cte_done = false
  while !cte_done {
    if index >= end || !is_identifier_token(tokens[index].0) {
      return None
    }
    let name = identifier_text(tokens[index].0)
    index = index + 1
    // Optional column-name list `(c1, c2)`.
    let mut alias : String? = None
    if index < end && tokens[index].0 == b"(" {
      let close = matching_paren(tokens, index)
      if close >= end {
        return None
      }
      let parts : Array[String] = []
      for j in (index + 1)..<close {
        if is_identifier_token(tokens[j].0) {
          parts.push(identifier_text(tokens[j].0))
        }
      }
      alias = Some(join_strings(parts, ","))
      index = close + 1
    }
    if index >= end || !bytes_equal_ci(tokens[index].0, b"AS") {
      return None
    }
    index = index + 1
    if index >= end || tokens[index].0 != b"(" {
      return None
    }
    let open = index
    let close = matching_paren(tokens, open)
    if close >= end {
      return None
    }
    if nest >= MAX_PAREN_DEPTH {
      return None
    }
    match parse_model(tokens, open + 1, close, nest + 1) {
      Some(model) => {
        if model.branches.length() == 0 {
          return None
        }
        ctes.push({ name, alias, body: model.branches[0] })
        index = close + 1
      }
      None => return None
    }
    if index < end && tokens[index].0 == b"," {
      index = index + 1
    } else {
      cte_done = true
    }
  }
  Some((ctes, index))
}

///|
/// Joins an array of strings with a separator (avoids core `join` dependency).
fn join_strings(parts : Array[String], sep : String) -> String {
  let mut out = ""
  let mut first = true
  for part in parts {
    if first {
      out = out + part
      first = false
    } else {
      out = out + sep + part
    }
  }
  out
}

///|
/// Parses a full query (WITH prefix + SELECT core + UNION chain) within
/// `[start, end)`.
fn parse_model(
  tokens : Array[(Bytes, Int, Int)],
  start : Int,
  end : Int,
  nest : Int,
) -> SelectModel? {
  let ctes : Array[CteDef] = []
  let branches : Array[SelectCore] = []
  let mut index = start
  if index < end && bytes_equal_ci(tokens[index].0, b"WITH") {
    match parse_cte_prefix(tokens, index + 1, end, nest) {
      Some((parsed, next)) => {
        for cte in parsed {
          ctes.push(cte)
        }
        index = next
      }
      None => return None
    }
  }
  match parse_core(tokens, index, end, nest) {
    Some((core, next)) => {
      branches.push(core)
      index = next
    }
    None => return None
  }
  // UNION chain (parser acceptance: only UNION [ALL|DISTINCT]).
  while index < end {
    match clause_kind_at(tokens, index, 0) {
      Some(SetOpUnion) => {
        let last = branches.length() - 1
        let prev = branches[last]
        let mut op = "UNION"
        let mut look = index + 1
        if look < end && bytes_equal_ci(tokens[look].0, b"ALL") {
          op = "UNION ALL"
          look = look + 1
        } else if look < end && bytes_equal_ci(tokens[look].0, b"DISTINCT") {
          op = "UNION DISTINCT"
          look = look + 1
        }
        branches[last] = core_with_set_op(prev, op)
        index = look
        match parse_core(tokens, index, end, nest) {
          Some((core, next)) => {
            branches.push(core)
            index = next
          }
          None => return None
        }
      }
      _ => break
    }
  }
  Some({ ctes, branches })
}

///|
/// Splits a SELECT statement's token stream into a SelectModel. Returns None
/// on paren-depth overflow (T-05-03-01). An empty token stream yields an
/// empty model (`branches = []`) — no panic, no fabricated content (LINE-01
/// empty-document contract: lineage/ re-parses a statement-free document to
/// an empty model).
pub fn split_select_model(tokens : Array[(Bytes, Int, Int)]) -> SelectModel? {
  if tokens.length() == 0 {
    return Some({ ctes: [], branches: [] })
  }
  parse_model(tokens, 0, tokens.length(), 0)
}
