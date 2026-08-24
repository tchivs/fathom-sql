/// Safe lossless autofix (LINT-01, D-03): minimal span edits over a valid tree,
/// with the formatter D-33 refusal principle applied absolutely.
///
/// Safety contract:
///   - Tree containing error/missing/skipped material -> `accepted=false`,
///     empty output, exactly one FATHOM-LINT-000 refusal diagnostic — never
///     partial edits (D-33, mirror of formatter FATHOM-FORMAT-001).
///   - Edits only ever replace a fixable finding's span (the engine only
///     attaches `fix` to SourceToken-leaf spans — trivia are separate leaves,
///     never touched, Pitfall 1).
///   - Edits are validated in-bounds (ASVS V5, Span::checked semantics) and
///     applied in source order; overlapping edits skip the later one
///     (adjacency RESOLVED: end==start pairs both apply).
///   - The returned output is the fixed source; the reparse round-trip defense
///     lives at the api layer (api.fix_text, 06-03) because lint/ never
///     imports the parser (D-01/D-21).

///|
/// One lint-channel diagnostic (engine-level, D-33 refusal).
pub(all) struct LintDiagnostic {
  code : String
  message : String
  start_byte : Int
  end_byte : Int
  statement_id : UInt
} derive(Eq, @debug.Debug)

///|
/// Lint operation result. `accepted` is always true in report mode and false
/// only when a fix was refused; `output` carries the fixed source in fix mode
/// (empty on refusal); `findings` is the finding list; `diagnostics` carries
/// the FATHOM-LINT-000 refusal (empty otherwise).
pub(all) struct LintResult {
  accepted : Bool
  findings : Array[LintFinding]
  output : Bytes
  diagnostics : Array[LintDiagnostic]
} derive(Eq, @debug.Debug)

///|
/// Apply the fixable findings' edits to the source, after the D-33 safety
/// gate. Fix-only: findings without `fix` are reported but not applied.
pub fn apply_fixes(
  root : @syntax.SyntaxNode,
  source : @source.SourceText,
  _context : @dialect.DialectContext,
  findings : Array[LintFinding],
  _options : LintOptions,
) -> LintResult {
  // D-33 absolute refusal gate (reuse formatter/refuse.mbt — never rewrite the
  // unsafe scan).
  match @formatter.first_unsafe_element(root) {
    Some(element) => {
      let span = element.span()
      return {
        accepted: false,
        findings: [],
        output: b"",
        diagnostics: [
          {
            code: "FATHOM-LINT-000",
            message: "refusing to autofix a tree containing error/missing/skipped material",
            start_byte: span.start_byte,
            end_byte: span.end_byte,
            statement_id: 0U,
          },
        ],
      }
    }
    None => ()
  }
  let edits : Array[LintEdit] = []
  for finding in findings {
    match finding.fix {
      Some(fix) => edits.push(fix)
      None => ()
    }
  }
  edits.sort_by(fn(a, b) {
    if a.start_byte != b.start_byte {
      a.start_byte - b.start_byte
    } else {
      a.end_byte - b.end_byte
    }
  })
  let output = apply_edits(source.bytes(), edits)
  { accepted: true, findings, output, diagnostics: [] }
}

///|
/// Apply non-overlapping, in-bounds edits to the source bytes. Out-of-bounds
/// edits are skipped (Span::checked semantics, ASVS V5); an edit whose start
/// falls inside a previously applied edit's range is skipped (overlap rule);
/// adjacent (end == next start) edits both apply.
fn apply_edits(source : Bytes, edits : Array[LintEdit]) -> Bytes {
  let buf = @buffer.Buffer::Buffer(size_hint=source.length())
  let mut cursor = 0
  let mut last_end = -1
  for edit in edits {
    if edit.start_byte < 0 ||
      edit.end_byte < edit.start_byte ||
      edit.end_byte > source.length() {
      continue
    }
    if edit.start_byte < last_end {
      continue // overlap: skip the later edit
    }
    buf.write_bytes(source[cursor:edit.start_byte])
    buf.write_bytes(edit.new_text)
    cursor = edit.end_byte
    last_end = edit.end_byte
  }
  buf.write_bytes(source[cursor:source.length()])
  buf.to_bytes()
}
