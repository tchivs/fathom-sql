/// Deterministic single forward pass over the statement's flat leaf sequence
/// (research Pattern 2): break decisions read only the token sequence, never
/// the running column, so idempotence holds by construction. Output bytes are
/// either original leaf bytes or the fixed whitespace alphabet { " ", "\n",
/// "\r\n" } (research Pitfall 4). The one exception is the probe-accepted
/// last-item trailing comma (Task 2, empirical gate): a synthesized `,` is
/// emitted only in list contexts where the reparse probe proved Doris accepts
/// it (PROPERTIES and partition-definition lists; recorded in formatter_test).

struct Layout {
  context : @dialect.DialectContext
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
  // indent of the current output line (last materialized break): comments
  // attach to the line they already occupy, not the statement base indent
  // (research Pattern 3 — "own line at the current indent")
  mut line_indent : Int
  // paren nesting depth: 0 at statement level; clause keywords nested inside
  // a paren group (subquery bodies, list interiors) break at indent_level + 1
  // (research Pattern 1 subquery rule)
  mut paren_depth : Int
  // defensive failure channel: source.slice failures become refusal diagnostics
  mut failed : @syntax.SyntaxElement?
}

fn Layout::new(context : @dialect.DialectContext, options : FormatOptions, newline : Bytes) -> Layout {
  {
    context: context,
    buf: @buffer.Buffer::Buffer(size_hint=1024),
    column: 0,
    indent_level: 0,
    newline: newline,
    options: options,
    pending_space: false,
    pending_break: false,
    pending_break_indent: 0,
    no_space_next: false,
    line_indent: 0,
    paren_depth: 0,
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
    self.line_indent = self.pending_break_indent
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
/// classification table with the configured case (D-26/D-28 —
/// options.keyword_case() picks Upper canonical or Lower ASCII fold),
/// punctuation zero-space rules applied, and the canonical ", " separator
/// promised after every comma (so flat emission and the measure-then-break
/// measure agree even when the input omits the space).
fn Layout::emit_token(self : Layout, raw : Bytes) -> Unit {
  let zero_space_before = raw == b"," || raw == b";" || raw == b")" || raw == b"("
  self.emit(rewrite_keyword_case(self.context, raw, self.options.keyword_case()), zero_space_before)
  if raw == b"(" {
    self.no_space_next = true
  }
  if raw == b"," {
    self.pending_space = true
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

/// Break indent for the current position: clause keywords nested inside a
/// paren group (subquery body) break one level deeper than the statement.
fn Layout::break_indent(self : Layout) -> Int {
  self.indent_level + (if self.paren_depth > 0 { 1 } else { 0 })
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
/// knowledge duplicated outside parser/ (Pitfall 7). Every keyword mirrors the
/// parser's own consume_word usage (parser.mbt:281-306) — the D-35 reparse
/// gate catches omissions. All tables stay in this ONE file (Pitfall 7).
fn clause_breaks(kind : @syntax.SyntaxKind) -> Array[Bytes] {
  match kind {
    // Select — parse_query (parser.mbt:1348-1366, UNION at 1361) +
    // parse_select_core (FROM 1174, WHERE 1175, GROUP 1176, HAVING 1177,
    // WINDOW 1178, QUALIFY 1196, ORDER 1204, LIMIT 1205, INTO 1206) +
    // parse_from JOIN/ON (986-1022) + EXCEPT (1159).
    @syntax.SyntaxKind::Select => [
      b"FROM", b"WHERE", b"GROUP", b"HAVING", b"ORDER", b"LIMIT",
      b"QUALIFY", b"WINDOW", b"UNION", b"JOIN", b"ON", b"INTO", b"EXCEPT",
    ]
    // Insert — parse_insert (parser.mbt:1487-1535): INTO 1498, PARTITION
    // 1501, WITH 1517, VALUES 1532, SELECT via is_query_start 1534.
    @syntax.SyntaxKind::Insert => [
      b"INTO", b"VALUES", b"SELECT", b"PARTITION", b"WITH", b"LABEL",
    ]
    // Update — parse_update (parser.mbt:1612-1660): SET 1632, FROM 1642,
    // WHERE 1647, ORDER 1652, LIMIT 1657; JOIN/ON via parse_from.
    @syntax.SyntaxKind::Update => [
      b"SET", b"FROM", b"WHERE", b"ORDER", b"LIMIT", b"JOIN", b"ON",
    ]
    // Delete — parse_delete (parser.mbt:1665-1719): FROM, PARTITION /
    // PARTITIONS, USING 1701, WHERE 1706, ORDER 1711, LIMIT 1716; JOIN/ON
    // via parse_from.
    @syntax.SyntaxKind::Delete => [
      b"FROM", b"PARTITION", b"PARTITIONS", b"USING", b"WHERE",
      b"ORDER", b"LIMIT", b"JOIN", b"ON",
    ]
    // Merge — parse_merge (parser.mbt:1724-1800): INTO, USING 1759, ON 1766,
    // WHEN 1776, AND 1784, THEN 1789, UPDATE 1790, SET 1791, DELETE 1795,
    // INSERT 1797, VALUES via parse_values_rows.
    @syntax.SyntaxKind::Merge => [
      b"INTO", b"USING", b"ON", b"WHEN", b"THEN", b"UPDATE", b"SET",
      b"DELETE", b"INSERT", b"VALUES", b"AND",
    ]
    // DDL kinds share one table: CREATE family selection via create_form_kind
    // (parser.mbt:1839-1855) + parse_create_table (ENGINE 2444, ORDER 2459,
    // COMMENT 2470, DISTRIBUTED 2486, ROLLUP 2489, PROPERTIES 2492, AS 2496,
    // SELECT via is_query_start) + LIKE 2425 + KEY (parse_create_table_body
    // 2569 / parse_create_index 2124).
    @syntax.SyntaxKind::CreateTable | @syntax.SyntaxKind::CreateView |
    @syntax.SyntaxKind::CreateIndex | @syntax.SyntaxKind::CreateMaterializedView => [
      b"CREATE", b"TABLE", b"ENGINE", b"KEY", b"COMMENT", b"PARTITION",
      b"DISTRIBUTED", b"ROLLUP", b"PROPERTIES", b"LIKE", b"AS", b"SELECT",
      b"ORDER",
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

/// Query starts at paren depth > 0 open a subquery body (research Pattern 1):
/// SELECT and WITH force a break at indent+1 inside a paren group so
/// `FROM (SELECT ...)` renders its inner query on its own lines.
fn is_query_start(raw : Bytes) -> Bool {
  bytes_equal_ci(raw, b"SELECT") || bytes_equal_ci(raw, b"WITH")
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

/// Comma-separated list contexts (research Pattern 2 / Task 2): the kind of a
/// list determines (a) whether it splits on commas and (b) whether the
/// empirical reparse probe accepted a last-item trailing comma.
enum ListKind {
  /// SELECT column list (keyword list, split on depth-0 commas)
  SelectList
  /// VALUES rows (keyword list, split on depth-0 commas; one row per item)
  ValuesRows
  /// PROPERTIES ( ... ) — probe-accepted last-item trailing comma
  Properties
  /// Partition-definition group ( ... ) following a `)` — probe-accepted
  PartitionDefs
  /// CREATE/INSERT column definitions: ( ... ) following a table name
  ColumnDefs
  /// Other opener-keyword groups (IN, KEY, PARTITION, ...): no last comma
  Other
}

/// Classify a `( ... )` group by the significant token before the `(`.
/// List contexts (Task 2): the opening paren follows a list-opener keyword,
/// follows a `)` (partition-definition position, e.g. RANGE(k1) (...) ), or
/// follows an identifier in a column-definition position (CREATE/INSERT).
/// Everything else (function arguments, arithmetic grouping, subquery bodies)
/// is an expression run that is never broken internally (Pattern 2 / Pitfall 1).
fn list_context_kind(prev : Bytes?, family : @syntax.SyntaxKind) -> ListKind? {
  match prev {
    None => None
    Some(raw) => {
      if bytes_equal_ci(raw, b"PROPERTIES") {
        return Some(ListKind::Properties)
      }
      if is_list_opener(raw) {
        return Some(ListKind::Other)
      }
      if raw == b")" {
        return Some(ListKind::PartitionDefs)
      }
      let column_def_family =
        family is @syntax.SyntaxKind::CreateTable ||
        family is @syntax.SyntaxKind::CreateView ||
        family is @syntax.SyntaxKind::CreateIndex ||
        family is @syntax.SyntaxKind::CreateMaterializedView ||
        family is @syntax.SyntaxKind::Insert
      if column_def_family && !is_clause_keyword(family, raw) && is_identifier_like(raw) {
        return Some(ListKind::ColumnDefs)
      }
      None
    }
  }
}

/// List-opener keywords from Task 2. SELECT is deliberately excluded here:
/// a SELECT keyword list is handled by the keyword-list path, and a `(`
/// directly after SELECT (e.g. `SELECT (a + b)`) is an expression run.
fn is_list_opener(raw : Bytes) -> Bool {
  bytes_equal_ci(raw, b"VALUES") || bytes_equal_ci(raw, b"IN") ||
    bytes_equal_ci(raw, b"PARTITION") || bytes_equal_ci(raw, b"PARTITIONS") ||
    bytes_equal_ci(raw, b"PROPERTIES") || bytes_equal_ci(raw, b"KEY") ||
    bytes_equal_ci(raw, b"DISTRIBUTED") || bytes_equal_ci(raw, b"ROLLUP") ||
    bytes_equal_ci(raw, b"USING")
}

/// A word-shaped token (letter or underscore start): identifiers and
/// non-table keywords are both "identifier-like" for column-definition
/// positions; clause-table keywords and punctuation are excluded.
fn is_identifier_like(raw : Bytes) -> Bool {
  if raw.length() == 0 {
    return false
  }
  let first = raw[0].to_int()
  (first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first == 95
}

/// Result of a measure-then-break scan (research Pattern 2): the flat-length
/// measure simulates the exact emission rules (pending space / zero-space /
/// no-space-after-"(") so the fit decision is a pure function of the token
/// sequence — invariant to input whitespace, hence idempotent across passes.
struct CommaListScan {
  end_index : Int
  flat_length : Int
  break_mode : Bool
  item_starts : Array[Int]
  item_ends : Array[Int]
  /// Index of a trailing comma at split depth (input already carries one,
  /// e.g. a probe-accepted PROPERTIES list formatted once): such a comma is
  /// not an item separator and contributes nothing to the flat measure, so
  /// format(format(x)) reproduces the same items and the same decision.
  trailing_comma_index : Int?
}

/// Single forward pass over leaves[from..to): tracks paren depth relative to
/// split_depth, splits items at commas on split_depth, measures the flat
/// single-line length with the emission rules, and stops at a clause keyword
/// (keyword lists), a `;`, or the group's closing `)`.
fn scan_comma_list(
  leaves : Array[@syntax.SyntaxElement],
  from : Int,
  to : Int,
  split_depth : Int,
  family : @syntax.SyntaxKind,
  source : @source.SourceText,
  stop_at_clause : Bool,
  options : FormatOptions,
) -> CommaListScan {
  let mut index = from
  let mut depth = split_depth
  let mut len = 0
  let mut pending = false
  let mut no_space_next = false
  let item_starts : Array[Int] = [from]
  let item_ends : Array[Int] = []
  let mut trailing_comma : Int? = None
  while index < to {
    match leaves[index] {
      @syntax.SyntaxElement::ChildNode(_) => ()
      @syntax.SyntaxElement::Leaf(leaf) if leaf.kind is @syntax.LeafKind::SourceToken => {
        let raw = match source.slice(leaf.span) {
          Some(bytes) => bytes
          None => {
            break
          }
        }
        if raw == b";" && depth == split_depth {
          break
        }
        if depth == split_depth && stop_at_clause && is_clause_keyword(family, raw) {
          break
        }
        if raw == b")" {
          if depth == split_depth {
            break
          }
          depth = depth - 1
        } else if raw == b"(" {
          depth = depth + 1
        }
        // A comma at split depth that is followed only by trivia and then the
        // list end is a TRAILING comma (input already formatted once, e.g. a
        // probe-accepted PROPERTIES list): it is not an item separator and
        // contributes nothing to the flat measure, so format(format(x))
        // reproduces the same items and the same fit decision.
        if raw == b"," && depth == split_depth && trailing_comma is None &&
          is_trailing_comma_position(leaves, index + 1, to, family, source, stop_at_clause) {
          trailing_comma = Some(index)
          item_ends.push(index)
          index = index + 1
          continue
        }
        let zero = raw == b"," || raw == b";" || raw == b")" || raw == b"("
        if pending && !no_space_next && !zero {
          len = len + 1
        }
        if zero {
          pending = false
        }
        len = len + raw.length()
        no_space_next = raw == b"("
        if raw == b"," {
          pending = true
          if depth == split_depth {
            item_ends.push(index)
            item_starts.push(index + 1)
          }
        }
      }
      @syntax.SyntaxElement::Leaf(leaf) if leaf.kind is @syntax.LeafKind::SourceTrivia => {
        let bytes = match source.slice(leaf.span) {
          Some(b) => b
          None => break
        }
        if is_comment(bytes) {
          if !no_space_next {
            len = len + 1
          }
          len = len + bytes.length()
          pending = false
        } else {
          pending = true
        }
      }
      @syntax.SyntaxElement::Leaf(_) => ()
    }
    index = index + 1
  }
  // Close the last open item: normal lists push here; a trailing comma or an
  // early stop already closed every item (item_starts.length() == item_ends.length()).
  if item_starts.length() > item_ends.length() {
    item_ends.push(index)
  }
  {
    end_index: index,
    flat_length: len,
    break_mode: len > options.line_width(),
    item_starts: item_starts,
    item_ends: item_ends,
    trailing_comma_index: trailing_comma,
  }
}

/// True when the significant token after `from` is the list end — a `)`, a
/// `;`, a clause-keyword stop (keyword lists), or the end of the range — so
/// the comma before it is a trailing comma rather than an item separator.
fn is_trailing_comma_position(
  leaves : Array[@syntax.SyntaxElement],
  from : Int,
  to : Int,
  family : @syntax.SyntaxKind,
  source : @source.SourceText,
  stop_at_clause : Bool,
) -> Bool {
  let mut look = from
  while look < to {
    match leaves[look] {
      @syntax.SyntaxElement::ChildNode(_) => look = look + 1
      @syntax.SyntaxElement::Leaf(leaf) if leaf.kind is @syntax.LeafKind::SourceToken => {
        let nraw = match source.slice(leaf.span) {
          Some(b) => b
          None => return false
        }
        return nraw == b")" || nraw == b";" ||
          (stop_at_clause && is_clause_keyword(family, nraw))
      }
      @syntax.SyntaxElement::Leaf(_) => look = look + 1
    }
  }
  true
}

/// Break-mode comma list emission (research Pattern 2 / D-31): one item per
/// line at item_indent; comma placement per options.comma_style(); a last-item
/// comma is emitted only where the reparse probe accepted it (Properties /
/// PartitionDefs — Task 2 empirical gate, default NO per assumption A1).
fn layout_comma_list_break(
  leaves : Array[@syntax.SyntaxElement],
  scan : CommaListScan,
  family : @syntax.SyntaxKind,
  source : @source.SourceText,
  options : FormatOptions,
  out : Layout,
  item_indent : Int,
  opener : Bytes?,
  kind : ListKind,
) -> Unit {
  let item_count = scan.item_starts.length()
  let last_item_comma = kind is ListKind::Properties || kind is ListKind::PartitionDefs
  match options.comma_style() {
    CommaStyle::Trailing => {
      let mut i = 0
      while i < item_count {
        out.break_line_at(item_indent)
        layout_sequence(
          leaves,
          scan.item_starts[i],
          scan.item_ends[i],
          family,
          source,
          options,
          out,
          false,
          if i == 0 { opener } else { None },
          false,
        )
        if i < item_count - 1 {
          emit_token_at(leaves, scan.item_ends[i], source, out)
        } else if last_item_comma {
          // Emit the probe-accepted last-item comma: the input's own trailing
          // comma when one is already there (idempotence pass), else a
          // synthesized "," (the one non-leaf byte the probe sanctions).
          match scan.trailing_comma_index {
            Some(comma_at) => emit_token_at(leaves, comma_at, source, out)
            None => out.emit_token(b",")
          }
        }
        i = i + 1
      }
    }
    CommaStyle::Leading => {
      let mut i = 0
      while i < item_count {
        out.break_line_at(item_indent)
        if i > 0 {
          emit_token_at(leaves, scan.item_ends[i - 1], source, out)
          out.space()
        }
        layout_sequence(
          leaves,
          scan.item_starts[i],
          scan.item_ends[i],
          family,
          source,
          options,
          out,
          false,
          if i == 0 { opener } else { None },
          false,
        )
        i = i + 1
      }
    }
  }
}

/// Emit a `( ... )` group classified as a list context: measure the interior;
/// inline when it fits, one item per line at indent+1 with the closing paren
/// back at the statement indent otherwise. Returns the index after `)`.
fn layout_paren_group(
  leaves : Array[@syntax.SyntaxElement],
  open_index : Int,
  family : @syntax.SyntaxKind,
  source : @source.SourceText,
  options : FormatOptions,
  out : Layout,
  kind : ListKind,
) -> Int {
  // The "(" is already emitted and paren_depth already incremented by the
  // caller; the interior splits on commas at the group's own depth.
  let scan = scan_comma_list(
    leaves,
    open_index + 1,
    leaves.length(),
    out.paren_depth,
    family,
    source,
    false,
    options,
  )
  let close_index = scan.end_index
  if scan.break_mode {
    layout_comma_list_break(leaves, scan, family, source, options, out, out.indent_level + 1, None, kind)
    out.break_line_at(out.indent_level)
    emit_token_at(leaves, close_index, source, out)
  } else {
    // Whole-list-fits emits the list inline; clause breaks are suppressed so
    // a subquery item cannot break an inline group (Task 2 acceptance).
    layout_sequence(
      leaves,
      open_index + 1,
      close_index,
      family,
      source,
      options,
      out,
      false,
      Some(b"("),
      true,
    )
    emit_token_at(leaves, close_index, source, out)
  }
  out.paren_depth = out.paren_depth - 1
  close_index + 1
}

/// Emit the SourceToken leaf at `index` (verbatim bytes via emit_token).
fn emit_token_at(
  leaves : Array[@syntax.SyntaxElement],
  index : Int,
  source : @source.SourceText,
  out : Layout,
) -> Unit {
  match leaves[index] {
    @syntax.SyntaxElement::Leaf(leaf) => {
      match source.slice(leaf.span) {
        Some(raw) => out.emit_token(raw)
        None => out.failed = Some(leaves[index])
      }
    }
    @syntax.SyntaxElement::ChildNode(_) => out.emit_token(b",")
  }
}

/// The single token/trivia walker (research Pattern 1/3):
/// - SourceToken leaves: keyword case via the classification table; clause
///   keywords force a break before them (unless first, or suppressed inside an
///   inline list); punctuation rules; paren-depth tracking; list contexts.
/// - SourceTrivia leaves: comments emitted verbatim (D-28/D-36); a comment
///   whose original trivia run contains a newline goes on its own line at the
///   current line indent and a line comment forces a break after itself
///   (Pattern 3); whitespace-only runs collapse to the canonical single space.
fn layout_sequence(
  leaves : Array[@syntax.SyntaxElement],
  from : Int,
  to : Int,
  family : @syntax.SyntaxKind,
  source : @source.SourceText,
  options : FormatOptions,
  out : Layout,
  statement_mode : Bool,
  prev_token : Bytes?,
  suppress_clause_breaks : Bool,
) -> Unit {
  let mut index = from
  let mut emitted_any = false
  let mut run_has_newline = false
  let mut prev = prev_token
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
            // any pending space left by leading trivia.
            out.pending_space = false
          }
          let is_clause = is_clause_keyword(family, raw)
          let at_statement_level = statement_mode && emitted_any && is_clause
          let inside_group = out.paren_depth > 0 && !suppress_clause_breaks &&
            (is_clause || is_query_start(raw))
          if at_statement_level || inside_group {
            out.break_line_at(out.break_indent())
          }
          // Keyword-list triggers (research Pattern 2): the select list
          // (family Select, statement start or subquery start) and the VALUES
          // rows (Insert/Merge) measure-then-break their comma tails.
          let mut keyword_list : ListKind? = None
          if (family is @syntax.SyntaxKind::Select) && bytes_equal_ci(raw, b"SELECT") &&
            ((statement_mode && !emitted_any) || out.paren_depth > 0) {
            keyword_list = Some(ListKind::SelectList)
          } else if (family is @syntax.SyntaxKind::Insert ||
            family is @syntax.SyntaxKind::Merge) && bytes_equal_ci(raw, b"VALUES") {
            keyword_list = Some(ListKind::ValuesRows)
          }
          let paren_kind : ListKind? = if raw == b"(" {
            list_context_kind(prev, family)
          } else {
            None
          }
          out.emit_token(raw)
          emitted_any = true
          run_has_newline = false
          if raw == b"(" {
            out.paren_depth = out.paren_depth + 1
            match paren_kind {
              Some(kind) => {
                index = layout_paren_group(leaves, index, family, source, options, out, kind)
                prev = Some(b")")
              }
              None => {
                prev = Some(raw)
                index = index + 1
              }
            }
            continue
          }
          if raw == b")" {
            out.paren_depth = out.paren_depth - 1
            prev = Some(raw)
            index = index + 1
            continue
          }
          prev = Some(raw)
          index = index + 1
          match keyword_list {
            Some(kind) => {
              let scan = scan_comma_list(
                leaves,
                index,
                to,
                out.paren_depth,
                family,
                source,
                true,
                options,
              )
              if scan.break_mode {
                layout_comma_list_break(
                  leaves,
                  scan,
                  family,
                  source,
                  options,
                  out,
                  out.indent_level + 1,
                  Some(raw),
                  kind,
                )
                index = scan.end_index
              }
            }
            None => ()
          }
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
            // A comment whose original trivia run contains a newline goes on
            // its own line at the current line indent; a line comment forces a
            // break after itself. At the very start of the output (document
            // leading comment, buffer still empty) no break and no space is
            // forced — the comment is simply the first emitted bytes. A
            // comment that is the first leaf of a broken-list item arrives
            // with the item's break already pending: that break is the correct
            // line start (item indent, not the stale line_indent), so it must
            // NOT be overwritten (03-03 Rule 1 fix — hint/hint-block placement
            // flip-flopped between format passes otherwise).
            if run_has_newline {
              if out.buf.length() > 0 && !out.pending_break {
                out.break_line_at(out.line_indent)
              }
            } else if out.buf.length() > 0 && !out.pending_break {
              out.space()
            }
            out.emit(bytes, false)
            emitted_any = true
            if is_line_comment(bytes) {
              out.break_line_at(out.line_indent)
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
  layout_sequence(leaves, 0, leaves.length(), family, source, options, out, true, None, false)
}
