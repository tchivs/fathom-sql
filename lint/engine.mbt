/// Lint rule engine (LINT-01, D-02/D-28/D-33): CST walk + statement-family
/// dispatch + the eight rule judgments.
///
/// D-28 discipline: every keyword judgment consumes `@dialect.classification_of`
/// / `@dialect.is_reserved_word` — there is NO second keyword table here
/// (Pitfall 14 / naming gate). ANLY-01 discipline: analyzer-backed rules
/// (004-007) only fire when a caller injects an `AnalysisResult`; without a
/// catalog they are silently skipped and the syntax-valid channel is never
/// touched.

///|
/// A token leaf's text + flattened span, pre-extracted from the CST.
struct LintToken {
  text : Bytes
  start : Int
  end : Int
}

///|
/// ASCII case-insensitive byte compare (mirror of dialect/classification.mbt).
fn bytes_equal_ci(actual : Bytes, expected : Bytes) -> Bool {
  if actual.length() != expected.length() {
    false
  } else {
    let mut index = 0
    let mut equal = true
    while index < actual.length() {
      let left = actual[index].to_int()
      let right = expected[index].to_int()
      let folded_left = if left >= 97 && left <= 122 { left - 32 } else { left }
      let folded_right = if right >= 97 && right <= 122 {
        right - 32
      } else {
        right
      }
      if folded_left != folded_right {
        equal = false
      }
      index = index + 1
    }
    equal
  }
}

///|
fn severity_id(severity : LintSeverity) -> String {
  match severity {
    LintSeverity::Error => "error"
    LintSeverity::Warning => "warning"
    LintSeverity::Info => "info"
  }
}

///|
/// Effective severity string for a rule code, or None when the rule is
/// disabled (override `off` / registry `enabled:false`).
fn effective_severity(options : LintOptions, code : String) -> String? {
  for rule in default_registry() {
    if rule.code == code {
      match options.rule_setting(rule) {
        None => return None
        Some(RuleSetting::Disabled) => return None
        Some(RuleSetting::Severity(severity)) =>
          return Some(severity_id(severity))
      }
    }
  }
  None
}

///|
/// The first ChildNode under a Statement node that is not itself a Statement
/// (mirror of formatter/layout.mbt statement_family — re-implemented locally
/// per D-01 import discipline).
fn statement_family(node : @syntax.SyntaxNode) -> @syntax.SyntaxKind? {
  for child in node.children() {
    match child {
      @syntax.SyntaxElement::ChildNode(child_node) =>
        if !(child_node.kind() is @syntax.SyntaxKind::Statement) {
          return Some(child_node.kind())
        }
      @syntax.SyntaxElement::Leaf(_) => ()
    }
  }
  None
}

///|
/// Collect every SourceToken leaf's text + span under a node, in source order.
fn collect_tokens(
  node : @syntax.SyntaxNode,
  source : @source.SourceText,
  out : Array[LintToken],
) -> Unit {
  for child in node.children() {
    match child {
      @syntax.SyntaxElement::ChildNode(child_node) =>
        collect_tokens(child_node, source, out)
      @syntax.SyntaxElement::Leaf(leaf) =>
        if leaf.kind is @syntax.LeafKind::SourceToken {
          match source.slice(leaf.span) {
            Some(text) =>
              out.push({
                text,
                start: leaf.span.start_byte,
                end: leaf.span.end_byte,
              })
            None => ()
          }
        }
    }
  }
}

///|
/// Release-order rank for the Doris profile ids (2.1 < 3.x < 4.x). Used by the
/// version-gated advisory (002) to compare the selected profile against a
/// construct's introduction profile.
fn profile_rank(profile_id : String) -> Int {
  match profile_id {
    "2.1" => 0
    "3.x" => 1
    "4.x" => 2
    _ => 2
  }
}

///|
/// True when the token's raw bytes start with a quote (backtick or double
/// quote) — quoted identifiers are never judged as keywords.
fn is_quoted(raw : Bytes) -> Bool {
  raw.length() > 0 && (raw[0].to_int() == 0x60 || raw[0].to_int() == 0x22)
}

///|
/// True when the first byte is an ASCII letter (a plausible identifier word).
fn is_word_start(raw : Bytes) -> Bool {
  if raw.length() == 0 {
    false
  } else {
    let byte = raw[0].to_int()
    (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
  }
}

///|
fn push_finding(
  findings : Array[LintFinding],
  code : String,
  severity : String,
  message : String,
  start : Int,
  end : Int,
  statement_id : UInt,
  fix : LintEdit?,
) -> Unit {
  findings.push({
    code,
    severity,
    message,
    start_byte: start,
    end_byte: end,
    statement_id,
    fix,
  })
}

///|
/// True when a token ends the SELECT projection. `ORDER` and `GROUP` only end
/// it when followed by `BY` (`ORDER BY` / `GROUP BY`); a bare `order`/`group`
/// in the projection is a reserved word used as an identifier (rule 001
/// target), not a clause boundary.
fn projection_end(
  context : @dialect.DialectContext,
  text : Bytes,
  next_text : Bytes?,
) -> Bool {
  if bytes_equal_ci(text, b"ORDER") || bytes_equal_ci(text, b"GROUP") {
    match next_text {
      Some(next) => bytes_equal_ci(next, b"BY")
      None => false
    }
  } else {
    @dialect.is_clause_keyword(context, text)
  }
}

///|
/// Rules 001 + 003 over a SELECT-family statement (D-02 focused scope):
///   - 001 unquoted-reserved-word: NARROW scope — the first token of each
///     projection item only (Open Question 6 time-constrained fallback). Table
///     name position (e.g. `SELECT a FROM order`) is explicitly OUT of this
///     phase's 001 scope.
///   - 003 select-star-without-limit: a `*` appears in the projection AND the
///     statement has no LIMIT token AND no `(` (conservative: skip complex/
///     subquery shapes).
fn rule_select_001_003(
  tokens : Array[LintToken],
  context : @dialect.DialectContext,
  options : LintOptions,
  statement_id : UInt,
  findings : Array[LintFinding],
) -> Unit {
  let severity_001 = effective_severity(options, "FATHOM-LINT-001")
  let severity_003 = effective_severity(options, "FATHOM-LINT-003")
  let mut in_projection = false
  let mut at_item_start = false
  let mut has_star = false
  let mut star_start = 0
  let mut star_end = 0
  let mut has_limit = false
  let mut has_paren = false
  let mut index = 0
  while index < tokens.length() {
    let token = tokens[index]
    let text = token.text
    if in_projection {
      let next_text = if index + 1 < tokens.length() {
        Some(tokens[index + 1].text)
      } else {
        None
      }
      if projection_end(context, text, next_text) {
        in_projection = false
        at_item_start = false
      } else if bytes_equal_ci(text, b",") {
        at_item_start = true
      } else {
        if bytes_equal_ci(text, b"*") {
          if !has_star {
            has_star = true
            star_start = token.start
            star_end = token.end
          }
        }
        if at_item_start {
          match severity_001 {
            Some(severity) =>
              if is_word_start(text) &&
                !is_quoted(text) &&
                @dialect.is_reserved_word(context, text) {
                push_finding(
                  findings,
                  "FATHOM-LINT-001",
                  severity,
                  "reserved word used as an unquoted identifier in the SELECT projection; quote it with backticks",
                  token.start,
                  token.end,
                  statement_id,
                  Some({
                    start_byte: token.start,
                    end_byte: token.end,
                    new_text: quote_identifier(text),
                  }),
                )
              }
            None => ()
          }
          at_item_start = false
        }
      }
    } else if !bytes_equal_ci(text, b"SELECT") {
      () // not yet in projection
    } else {
      in_projection = true
      at_item_start = true
    }
    if bytes_equal_ci(text, b"(") {
      has_paren = true
    }
    if bytes_equal_ci(text, b"LIMIT") {
      has_limit = true
    }
    index = index + 1
  }
  if has_star && !has_limit && !has_paren {
    match severity_003 {
      Some(severity) =>
        push_finding(
          findings,
          "FATHOM-LINT-003",
          severity,
          "SELECT * without LIMIT",
          star_start,
          star_end,
          statement_id,
          None,
        )
      None => ()
    }
  }
}

///|
/// Backtick-wrap a reserved word so it becomes a quoted identifier (rule 001
/// fix, D-03). Only ever applied to the raw identifier token bytes.
fn quote_identifier(raw : Bytes) -> Bytes {
  b"\x60" + raw + b"\x60"
}

///|
/// Rule 002 version-gated-syntax advisory: a construct whose introduction
/// profile is newer than the selected profile. Seeded from repo-grounded
/// features (DorisFeature::MergeInto introduced_profile "4.x", STATE.md).
fn rule_version_gated(
  family : @syntax.SyntaxKind?,
  tokens : Array[LintToken],
  context : @dialect.DialectContext,
  options : LintOptions,
  statement_id : UInt,
  findings : Array[LintFinding],
) -> Unit {
  match family {
    Some(@syntax.SyntaxKind::Merge) =>
      match effective_severity(options, "FATHOM-LINT-002") {
        Some(severity) =>
          if profile_rank(context.profile_id) < profile_rank("4.x") {
            for token in tokens {
              if bytes_equal_ci(token.text, b"MERGE") {
                push_finding(
                  findings,
                  "FATHOM-LINT-002",
                  severity,
                  "MERGE statement requires the 4.x Doris profile",
                  token.start,
                  token.end,
                  statement_id,
                  None,
                )
                break
              }
            }
          }
        None => ()
      }
    _ => ()
  }
}

///|
/// Rule 008 deprecated-syntax advisory (info). Seeded from a repo-grounded
/// legacy construct: `CLUSTER BY` is documented in the 2.1/3.x CREATE TABLE
/// key clause but is a known corpus gap (not implemented by the parser,
/// CORPUS-REPORT) — flagged as legacy/deprecated syntax. The table is
/// corpus-driven and grows with the corpus (D-02).
fn rule_deprecated(
  tokens : Array[LintToken],
  options : LintOptions,
  statement_id : UInt,
  findings : Array[LintFinding],
) -> Unit {
  match effective_severity(options, "FATHOM-LINT-008") {
    Some(severity) => {
      let mut index = 0
      while index < tokens.length() {
        if bytes_equal_ci(tokens[index].text, b"CLUSTER") {
          if index + 1 < tokens.length() &&
            bytes_equal_ci(tokens[index + 1].text, b"BY") {
            push_finding(
              findings,
              "FATHOM-LINT-008",
              severity,
              "CLUSTER BY is a legacy 2.1/3.x-documented key-clause construct (corpus known-gap, not implemented by the parser)",
              tokens[index].start,
              tokens[index + 1].end,
              statement_id,
              None,
            )
            index = index + 1
          }
        }
        index = index + 1
      }
    }
    None => ()
  }
}

///|
/// Map analyzer-channel diagnostics to lint findings (004-007). Runs ONLY when
/// an `AnalysisResult` is injected (ANLY-01); spans are preserved. The owning
/// statement id is derived by span containment (AnalysisDiagnostic carries no
/// statement id).
fn analyzer_findings(
  root : @syntax.SyntaxNode,
  analysis : @analyzer.AnalysisResult?,
) -> Array[LintFinding] {
  let out : Array[LintFinding] = []
  match analysis {
    None => out
    Some(result) => {
      let statements : Array[(@source.Span, UInt)] = []
      let mut sid : UInt = 0U
      for child in root.children() {
        match child {
          @syntax.SyntaxElement::ChildNode(node) if node.kind()
            is @syntax.SyntaxKind::Statement => {
            statements.push((node.span(), sid))
            sid = sid + 1U
          }
          _ => ()
        }
      }
      for diag in result.diagnostics {
        let mapped = match diag.code {
          "unknown-table" => Some(("FATHOM-LINT-004", "error"))
          "unknown-column" => Some(("FATHOM-LINT-005", "error"))
          "ambiguous-reference" => Some(("FATHOM-LINT-006", "warning"))
          "function-arity" => Some(("FATHOM-LINT-007", "error"))
          _ => None
        }
        match mapped {
          Some((code, severity)) =>
            out.push({
              code,
              severity,
              message: diag.message,
              start_byte: diag.start_byte,
              end_byte: diag.end_byte,
              statement_id: statement_id_containing(statements, diag.start_byte),
              fix: None,
            })
          None => ()
        }
      }
      out
    }
  }
}

///|
fn statement_id_containing(
  statements : Array[(@source.Span, UInt)],
  byte : Int,
) -> UInt {
  for item in statements {
    let (span, sid) = item
    if byte >= span.start_byte && byte <= span.end_byte {
      return sid
    }
  }
  0U
}

///|
/// Run all enabled rules over a parsed document. Findings are sorted by
/// source order then rule code, deterministic across runs (flagged assumption
/// ordering RESOLVED).
pub fn run_rules(
  root : @syntax.SyntaxNode,
  source : @source.SourceText,
  context : @dialect.DialectContext,
  analysis : @analyzer.AnalysisResult?,
  options : LintOptions,
) -> Array[LintFinding] {
  let findings : Array[LintFinding] = []
  let mut statement_id : UInt = 0U
  for child in root.children() {
    match child {
      @syntax.SyntaxElement::ChildNode(node) if node.kind()
        is @syntax.SyntaxKind::Statement => {
        let family = statement_family(node)
        let tokens : Array[LintToken] = []
        collect_tokens(node, source, tokens)
        match family {
          Some(@syntax.SyntaxKind::Select) =>
            rule_select_001_003(
              tokens, context, options, statement_id, findings,
            )
          _ => ()
        }
        rule_version_gated(
          family, tokens, context, options, statement_id, findings,
        )
        rule_deprecated(tokens, options, statement_id, findings)
        statement_id = statement_id + 1U
      }
      _ => ()
    }
  }
  let analyzer_out = analyzer_findings(root, analysis)
  for finding in analyzer_out {
    findings.push(finding)
  }
  findings.sort_by(fn(a, b) {
    if a.start_byte != b.start_byte {
      a.start_byte - b.start_byte
    } else {
      a.code.compare(b.code)
    }
  })
  findings
}
