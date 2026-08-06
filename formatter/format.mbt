/// Refusal-first format entry (D-33, research Pattern 5): a tree containing
/// error/missing/skipped material returns accepted=false with empty output and
/// exactly one FATHOM-FORMAT-001 diagnostic — never partial bytes. The
/// function never panics: every source.slice failure becomes a refusal
/// diagnostic.
pub fn format(
  root : @syntax.SyntaxNode,
  source : @source.SourceText,
  options : FormatOptions,
  context : @dialect.DialectContext,
) -> FormatResult {
  match find_first_unsafe(root) {
    Some((element, statement_id)) => {
      let span = element.span()
      return {
        accepted: false,
        output: b"",
        diagnostics: [refusal_diagnostic(span, statement_id)],
        statement_offsets: [],
      }
    }
    None => ()
  }
  let newline = detect_newline(source, options.newline_style())
  let out = Layout::new(context, options, newline)
  let statement_offsets : Array[Int] = []
  for child in root.children() {
    match child {
      @syntax.SyntaxElement::ChildNode(node) if node.kind() is @syntax.SyntaxKind::Statement => {
        // Record the output byte offset where this statement's first emitted
        // byte lands (research Open Question 5). Trailing-newline normalization
        // only touches the tail, so offsets stay valid in the final output.
        statement_offsets.push(out.buf.length())
        match statement_family(node) {
          Some(family) => layout_statement(family, node, source, options, out)
          None => ()
        }
        // Statements are separated by one newline (research Open Question 4);
        // the last statement's pending break never materializes and the
        // trailing-newline policy takes over.
        out.break_line()
      }
      @syntax.SyntaxElement::Leaf(leaf) => layout_document_trivia(leaf, source, out)
      @syntax.SyntaxElement::ChildNode(_) => () // skipped tails are refused above
    }
    if out.failed is Some(_) {
      break
    }
  }
  match out.failed {
    Some(element) => {
      let span = element.span()
      return {
        accepted: false,
        output: b"",
        diagnostics: [refusal_diagnostic(span, 0U)],
        statement_offsets: [],
      }
    }
    None => ()
  }
  {
    accepted: true,
    output: finalize_output(out.buf.to_bytes(), newline, options.trailing_newline()),
    diagnostics: [],
    statement_offsets: statement_offsets,
  }
}

/// First unsafe element together with the id of the Statement node containing
/// it (0U when it sits outside any statement — e.g. a resource-skipped tail).
fn find_first_unsafe(root : @syntax.SyntaxNode) -> (@syntax.SyntaxElement, UInt)? {
  let mut statement_id : UInt = 0U
  for child in root.children() {
    match child {
      @syntax.SyntaxElement::ChildNode(node) if node.kind() is @syntax.SyntaxKind::Statement => {
        match first_unsafe_element(node) {
          Some(element) => return Some((element, statement_id))
          None => statement_id = statement_id + 1U
        }
      }
      @syntax.SyntaxElement::ChildNode(node) => {
        match first_unsafe_element(node) {
          Some(element) => return Some((element, 0U))
          None => ()
        }
      }
      @syntax.SyntaxElement::Leaf(leaf) => {
        if leaf.kind is @syntax.LeafKind::SourceError || leaf.kind is @syntax.LeafKind::SourceSkipped {
          return Some((child, 0U))
        }
      }
    }
  }
  None
}

/// Document-level trivia segments between statements (research Pattern 3):
/// comments go on their own line verbatim; whitespace-only segments collapse
/// away (statements own their line separation); stray token leaves (e.g. a
/// lone `;`) are emitted verbatim.
fn layout_document_trivia(
  leaf : @syntax.SyntaxLeaf,
  source : @source.SourceText,
  out : Layout,
) -> Unit {
  let bytes = match source.slice(leaf.span) {
    Some(bytes) => bytes
    None => {
      out.failed = Some(@syntax.SyntaxElement::Leaf(leaf))
      return
    }
  }
  if leaf.kind is @syntax.LeafKind::SourceToken {
    out.emit_token(bytes)
  } else if is_bom(bytes) {
    out.emit(bytes, false)
  } else if is_comment(bytes) {
    if out.buf.length() > 0 {
      out.break_line()
    }
    out.emit(bytes, false)
    if is_line_comment(bytes) {
      out.break_line()
    }
  }
}

fn refusal_diagnostic(span : @source.Span, statement_id : UInt) -> FormatDiagnostic {
  {
    severity: "error",
    code: "FATHOM-FORMAT-001",
    message: "refusing to format a tree containing error/missing/skipped material",
    expected_class: "format",
    start_byte: span.start_byte,
    end_byte: span.end_byte,
    statement_id: statement_id,
  }
}
