/// Deterministic single forward pass over the statement's flat leaf sequence
/// (research Pattern 2): break decisions read only the token sequence, never
/// the running column, so idempotence holds by construction. Output bytes are
/// either original leaf bytes or the fixed whitespace alphabet { " ", "\n",
/// "\r\n" } (research Pitfall 4).

struct Layout {
  buf : @buffer.Buffer
  mut column : Int
  indent_level : Int
  newline : Bytes
  options : FormatOptions
  // pending emission state, materialized by the next emit
  mut pending_space : Bool
  mut pending_break : Bool
  mut pending_break_indent : Int
  // "(" forbids a space on its right (zero-space rule)
  mut no_space_next : Bool
  // defensive failure channel: source.slice failures become refusal diagnostics
  mut failed : @syntax.SyntaxElement?
}

fn Layout::new(options : FormatOptions, newline : Bytes) -> Layout {
  {
    buf: @buffer.Buffer::Buffer(size_hint=1024),
    column: 0,
    indent_level: 0,
    newline: newline,
    options: options,
    pending_space: false,
    pending_break: false,
    pending_break_indent: 0,
    no_space_next: false,
    failed: None,
  }
}

/// Write text, resolving the pending separator first: a pending break wins over
/// a pending space; `zero_space_before` drops the pending space entirely
/// (punctuation rule: no space before , ; ) ().
fn Layout::emit(self : Layout, text : Bytes, zero_space_before : Bool) -> Unit {
  if self.pending_break {
    self.buf.write_bytes(self.newline)
    self.buf.write_bytes(indent_bytes(self.options.indent() * self.pending_break_indent))
    self.column = self.options.indent() * self.pending_break_indent
    self.pending_break = false
    self.pending_space = false
  } else if self.pending_space && !self.no_space_next && !zero_space_before {
    self.buf.write_bytes(b" ")
    self.column = self.column + 1
  }
  self.pending_space = false
  self.no_space_next = false
  self.buf.write_bytes(text)
  self.column = self.column + text.length()
}

/// Emit a SourceToken leaf: keyword spelling canonicalized via the
/// classification table (D-28), punctuation zero-space rules applied.
fn Layout::emit_token(self : Layout, raw : Bytes) -> Unit {
  let zero_space_before = raw == b"," || raw == b";" || raw == b")" || raw == b"("
  self.emit(rewrite_keyword(raw), zero_space_before)
  if raw == b"(" {
    self.no_space_next = true
  }
}

/// Request a single canonical space before the next emitted byte.
fn Layout::space(self : Layout) -> Unit {
  self.pending_space = true
}

/// Request a line break before the next emitted byte at the current indent.
fn Layout::break_line(self : Layout) -> Unit {
  self.pending_break = true
  self.pending_break_indent = self.indent_level
  self.pending_space = false
}

/// Request a line break at an explicit indent level (list items at indent+1).
fn Layout::break_line_at(self : Layout, indent_level : Int) -> Unit {
  self.pending_break = true
  self.pending_break_indent = indent_level
  self.pending_space = false
}

fn indent_bytes(count : Int) -> Bytes {
  if count <= 0 {
    b""
  } else {
    @utf8.encode(" ".repeat(count))
  }
}

/// Newline-style resolution (D-32 / flagged assumption A2): FollowInput scans
/// the source for the first CRLF (CRLF-as-one-break convention, source.mbt:
/// 31-45); any CRLF makes the whole output CRLF.
pub fn detect_newline(source : @source.SourceText, style : NewlineStyle) -> Bytes {
  match style {
    NewlineStyle::Lf => b"\n"
    NewlineStyle::Crlf => b"\r\n"
    NewlineStyle::FollowInput => {
      let bytes = source.bytes()
      let mut index = 0
      while index + 1 < bytes.length() {
        if bytes[index].to_int() == 13 && bytes[index + 1].to_int() == 10 {
          return b"\r\n"
        }
        index = index + 1
      }
      b"\n"
    }
  }
}

/// Trailing-newline policy (D-32 / flagged assumption A3): normalize the tail
/// to exactly one newline when enabled (add if missing, collapse 2+ to 1),
/// strip all trailing newlines when disabled. Empty output stays empty.
pub fn finalize_output(output : Bytes, newline : Bytes, trailing : Bool) -> Bytes {
  if output.length() == 0 {
    return b""
  }
  let newline_length = newline.length()
  let mut end = output.length()
  while end >= newline_length && output[(end - newline_length):end] == newline {
    end = end - newline_length
  }
  if end == 0 {
    return b""
  }
  if trailing {
    output[0:end].to_owned() + newline
  } else {
    output[0:end].to_owned()
  }
}

/// Per-statement-kind clause tables (research Pattern 1): the ONLY grammar
/// knowledge duplicated outside parser/ (Pitfall 7). The Select table mirrors
/// the parser's clause consumption (consume_word family, parser.mbt:300-306);
/// other families gain their tables in 03-02.
fn clause_breaks(kind : @syntax.SyntaxKind) -> Array[Bytes] {
  match kind {
    @syntax.SyntaxKind::Select => [
      b"FROM", b"WHERE", b"GROUP", b"HAVING", b"ORDER", b"LIMIT",
      b"QUALIFY", b"WINDOW", b"UNION", b"JOIN", b"ON", b"INTO", b"EXCEPT",
    ]
    _ => []
  }
}

fn is_clause_keyword(kind : @syntax.SyntaxKind, raw : Bytes) -> Bool {
  let table = clause_breaks(kind)
  for word in table {
    if bytes_equal_ci(raw, word) {
      return true
    }
  }
  false
}

fn bytes_equal_ci(left : Bytes, right : Bytes) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut index = 0
  while index < left.length() {
    let a = left[index].to_int()
    let b = right[index].to_int()
    let la = if a >= 65 && a <= 90 { a + 32 } else { a }
    let lb = if b >= 65 && b <= 90 { b + 32 } else { b }
    if la != lb {
      return false
    }
    index = index + 1
  }
  true
}

fn bytes_contains_newline(raw : Bytes) -> Bool {
  let mut index = 0
  while index < raw.length() {
    if raw[index].to_int() == 10 {
      return true
    }
    index = index + 1
  }
  false
}

fn is_bom(raw : Bytes) -> Bool {
  raw.length() == 3 && raw[0].to_int() == 0xef && raw[1].to_int() == 0xbb &&
    raw[2].to_int() == 0xbf
}

fn is_line_comment(raw : Bytes) -> Bool {
  if raw.length() >= 2 && raw[0].to_int() == 45 && raw[1].to_int() == 45 {
    return true
  }
  if raw.length() >= 1 && raw[0].to_int() == 35 {
    return true
  }
  false
}

fn is_comment(raw : Bytes) -> Bool {
  if raw.length() >= 2 && raw[0].to_int() == 47 && raw[1].to_int() == 42 {
    return true
  }
  is_line_comment(raw)
}

/// The first ChildNode under a Statement node that is not itself Statement.
fn statement_family(node : @syntax.SyntaxNode) -> @syntax.SyntaxKind? {
  for child in node.children() {
    match child {
      @syntax.SyntaxElement::ChildNode(child_node) => {
        if !(child_node.kind() is @syntax.SyntaxKind::Statement) {
          return Some(child_node.kind())
        }
      }
      @syntax.SyntaxElement::Leaf(_) => ()
    }
  }
  None
}

fn collect_leaves(node : @syntax.SyntaxNode, out : Array[@syntax.SyntaxElement]) -> Unit {
  for child in node.children() {
    match child {
      @syntax.SyntaxElement::ChildNode(child_node) => collect_leaves(child_node, out)
      @syntax.SyntaxElement::Leaf(leaf) => out.push(@syntax.SyntaxElement::Leaf(leaf))
    }
  }
}

/// Measure-then-break decision (research Pattern 2): the break decision reads
/// only the token sequence — non-trivia leaf lengths + one canonical space per
/// trivia run + ", " per comma — so it is invariant to input whitespace and
/// idempotent across passes.
struct SelectListInfo {
  end_index : Int
  total_length : Int
  break_mode : Bool
}

fn select_list_info(
  leaves : Array[@syntax.SyntaxElement],
  start_index : Int,
  family : @syntax.SyntaxKind,
  source : @source.SourceText,
  options : FormatOptions,
) -> SelectListInfo {
  let mut index = start_index
  let mut total = 0
  let mut run_count = 0
  let mut in_run = false
  let mut end_index = leaves.length()
  while index < leaves.length() {
    match leaves[index] {
      @syntax.SyntaxElement::ChildNode(_) => ()
      @syntax.SyntaxElement::Leaf(leaf) => {
        if leaf.kind is @syntax.LeafKind::SourceToken {
          match source.slice(leaf.span) {
            Some(raw) => {
              if raw == b"," {
                total = total + 2
                in_run = false
              } else if is_clause_keyword(family, raw) {
                end_index = index
                break
              } else {
                total = total + raw.length()
                in_run = false
              }
            }
            None => {
              end_index = index
              break
            }
          }
        } else {
          if !in_run {
            run_count = run_count + 1
            in_run = true
          }
        }
      }
    }
    index = index + 1
  }
  {
    end_index: end_index,
    total_length: total + run_count,
    break_mode: total + run_count > options.line_width(),
  }
}

fn find_comma(
  leaves : Array[@syntax.SyntaxElement],
  from : Int,
  to : Int,
  source : @source.SourceText,
) -> Int? {
  let mut index = from
  while index < to {
    match leaves[index] {
      @syntax.SyntaxElement::Leaf(leaf) if leaf.kind is @syntax.LeafKind::SourceToken => {
        match source.slice(leaf.span) {
          Some(raw) if raw == b"," => return Some(index)
          _ => ()
        }
      }
      _ => ()
    }
    index = index + 1
  }
  None
}

/// The single token/trivia walker (research Pattern 1/3):
/// - SourceToken leaves: keyword case via the classification table; clause
///   keywords force a break before them (unless first); punctuation rules.
/// - SourceTrivia leaves: comments emitted verbatim (D-28/D-36); a comment
///   whose original trivia run contains a newline goes on its own line and a
///   line comment forces a break after itself (Pattern 3); whitespace-only
///   runs collapse to the canonical single space.
fn layout_sequence(
  leaves : Array[@syntax.SyntaxElement],
  from : Int,
  to : Int,
  family : @syntax.SyntaxKind,
  source : @source.SourceText,
  options : FormatOptions,
  out : Layout,
  statement_mode : Bool,
) -> Unit {
  let mut index = from
  let mut emitted_any = false
  let mut run_has_newline = false
  while index < to {
    match leaves[index] {
      @syntax.SyntaxElement::ChildNode(_) => index = index + 1
      @syntax.SyntaxElement::Leaf(leaf) => {
        if leaf.kind is @syntax.LeafKind::SourceToken {
          let raw = match source.slice(leaf.span) {
            Some(bytes) => bytes
            None => {
              out.failed = Some(leaves[index])
              return
            }
          }
          if statement_mode && !emitted_any {
            // A statement's first significant token starts at column 0: drop
            // any pending separator left by leading trivia.
            out.pending_space = false
          }
          if statement_mode && !emitted_any && (family is @syntax.SyntaxKind::Select) &&
            bytes_equal_ci(raw, b"SELECT") {
            out.emit_token(raw)
            emitted_any = true
            run_has_newline = false
            let info = select_list_info(leaves, index + 1, family, source, options)
            if info.break_mode {
              layout_select_items(leaves, index + 1, info.end_index, family, source, options, out)
              index = info.end_index
            } else {
              index = index + 1
            }
            continue
          }
          if statement_mode && emitted_any && is_clause_keyword(family, raw) {
            out.break_line()
          }
          out.emit_token(raw)
          emitted_any = true
          run_has_newline = false
          index = index + 1
          continue
        }
        if leaf.kind is @syntax.LeafKind::SourceTrivia {
          let bytes = match source.slice(leaf.span) {
            Some(bytes) => bytes
            None => {
              out.failed = Some(leaves[index])
              return
            }
          }
          if is_bom(bytes) {
            out.emit(bytes, false)
            index = index + 1
            continue
          }
          if bytes_contains_newline(bytes) {
            run_has_newline = true
          }
          if is_comment(bytes) {
            if run_has_newline {
              out.break_line()
            } else {
              out.space()
            }
            out.emit(bytes, false)
            if is_line_comment(bytes) {
              out.break_line()
            }
          } else {
            out.space()
          }
          index = index + 1
          continue
        }
        // SourceError / SourceSkipped leaves: the refusal scan (D-33) runs
        // before any layout, so reaching one here is a defensive refusal.
        out.failed = Some(leaves[index])
        return
      }
    }
  }
}

/// Break-mode select list (research Pattern 2 / D-31): one item per line at
/// indent+1 with the comma at the end of each item line; the last item carries
/// no comma (flagged assumption A1).
fn layout_select_items(
  leaves : Array[@syntax.SyntaxElement],
  from : Int,
  to : Int,
  family : @syntax.SyntaxKind,
  source : @source.SourceText,
  options : FormatOptions,
  out : Layout,
) -> Unit {
  let mut cursor = from
  while cursor < to {
    let comma_index = find_comma(leaves, cursor, to, source)
    let item_end = match comma_index {
      Some(comma_at) => comma_at
      None => to
    }
    out.break_line_at(out.indent_level + 1)
    layout_sequence(leaves, cursor, item_end, family, source, options, out, false)
    match comma_index {
      Some(comma_at) => {
        match leaves[comma_at] {
          @syntax.SyntaxElement::Leaf(comma_leaf) => {
            match source.slice(comma_leaf.span) {
              Some(comma_bytes) => out.emit_token(comma_bytes)
              None => {
                out.failed = Some(leaves[comma_at])
                return
              }
            }
          }
          @syntax.SyntaxElement::ChildNode(_) => out.emit_token(b",")
        }
        cursor = comma_at + 1
      }
      None => cursor = to
    }
  }
}

/// Layout one Statement node's leaves (research Pattern 1).
fn layout_statement(
  family : @syntax.SyntaxKind,
  node : @syntax.SyntaxNode,
  source : @source.SourceText,
  options : FormatOptions,
  out : Layout,
) -> Unit {
  let leaves : Array[@syntax.SyntaxElement] = []
  for child in node.children() {
    match child {
      @syntax.SyntaxElement::ChildNode(child_node) => collect_leaves(child_node, leaves)
      @syntax.SyntaxElement::Leaf(leaf) => leaves.push(@syntax.SyntaxElement::Leaf(leaf))
    }
  }
  layout_sequence(leaves, 0, leaves.length(), family, source, options, out, true)
}
