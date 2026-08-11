/// White-box tests for the lint/ library (LINT-01, D-02/D-03/D-33/ANLY-01).
/// CSTs are hand-built (lint/ never imports the parser, D-01/D-21) so rule
/// judgments are exercised deterministically.

fn doris_ctx(profile : String) -> @dialect.DialectContext {
  {
    dialect: @dialect.Dialect::Doris,
    profile_id: profile,
    exact_release: profile,
    feature_introduction: "test",
  }
}

fn checked_span(start : Int, end : Int, length : Int) -> @source.Span {
  match @source.Span::checked(start, end, length) {
    Ok(span) => span
    Err(_) => panic()
  }
}

/// Build Document -> Statement -> family node -> leaves over `source`.
fn lint_doc(
  source : Bytes,
  family : @syntax.SyntaxKind,
  parts : Array[(@syntax.LeafKind, Int, Int)],
) -> (@syntax.SyntaxNode, @source.SourceText) {
  let src = match @source.SourceText::new(source) {
    Ok(value) => value
    Err(_) => panic()
  }
  let length = source.length()
  let leaves : Array[@syntax.SyntaxElement] = []
  for part in parts {
    let (kind, start, end) = part
    leaves.push(
      @syntax.SyntaxElement::Leaf(
        @syntax.SyntaxLeaf::new(kind, checked_span(start, end, length)),
      ),
    )
  }
  let family_span = checked_span(0, length, length)
  let family_node = match @syntax.SyntaxNode::new(family, family_span, leaves) {
    Some(value) => value
    None => panic()
  }
  let stmt = match @syntax.SyntaxNode::new(
    @syntax.SyntaxKind::Statement,
    family_span,
    [@syntax.SyntaxElement::ChildNode(family_node)],
  ) {
    Some(value) => value
    None => panic()
  }
  let doc = match @syntax.SyntaxNode::new(
    @syntax.SyntaxKind::Document,
    family_span,
    [@syntax.SyntaxElement::ChildNode(stmt)],
  ) {
    Some(value) => value
    None => panic()
  }
  (doc, src)
}

test "rule_003_select_star_without_limit_positive" {
  // SELECT * FROM t
  let (doc, src) = lint_doc(
    b"SELECT * FROM t",
    @syntax.SyntaxKind::Select,
    [
      (@syntax.LeafKind::SourceToken, 0, 6), // SELECT
      (@syntax.LeafKind::SourceTrivia, 6, 7), // space
      (@syntax.LeafKind::SourceToken, 7, 8), // *
      (@syntax.LeafKind::SourceTrivia, 8, 9), // space
      (@syntax.LeafKind::SourceToken, 9, 13), // FROM
      (@syntax.LeafKind::SourceTrivia, 13, 14), // space
      (@syntax.LeafKind::SourceToken, 14, 15), // t
    ],
  )
  let findings = run_rules(doc, src, doris_ctx("4.x"), None, LintOptions::default())
  let matching = filter_code(findings, "FATHOM-LINT-003")
  assert_eq(matching.length(), 1)
  assert_eq(matching[0].severity, "warning")
  assert_eq(matching[0].start_byte, 7)
  assert_eq(matching[0].end_byte, 8)
}

test "rule_003_negative_limit_and_no_star" {
  // SELECT * FROM t LIMIT 10
  let (doc1, src1) = lint_doc(
    b"SELECT * FROM t LIMIT 10",
    @syntax.SyntaxKind::Select,
    [
      (@syntax.LeafKind::SourceToken, 0, 6),
      (@syntax.LeafKind::SourceTrivia, 6, 7),
      (@syntax.LeafKind::SourceToken, 7, 8), // *
      (@syntax.LeafKind::SourceTrivia, 8, 9),
      (@syntax.LeafKind::SourceToken, 9, 13), // FROM
      (@syntax.LeafKind::SourceTrivia, 13, 14),
      (@syntax.LeafKind::SourceToken, 14, 15), // t
      (@syntax.LeafKind::SourceTrivia, 15, 16),
      (@syntax.LeafKind::SourceToken, 16, 21), // LIMIT
      (@syntax.LeafKind::SourceTrivia, 21, 22),
      (@syntax.LeafKind::SourceToken, 22, 24), // 10
    ],
  )
  assert_eq(filter_code(run_rules(doc1, src1, doris_ctx("4.x"), None, LintOptions::default()), "FATHOM-LINT-003").length(), 0)
  // SELECT a, b FROM t
  let (doc2, src2) = lint_doc(
    b"SELECT a, b FROM t",
    @syntax.SyntaxKind::Select,
    [
      (@syntax.LeafKind::SourceToken, 0, 6),
      (@syntax.LeafKind::SourceTrivia, 6, 7),
      (@syntax.LeafKind::SourceToken, 7, 8), // a
      (@syntax.LeafKind::SourceToken, 8, 9), // ,
      (@syntax.LeafKind::SourceTrivia, 9, 10),
      (@syntax.LeafKind::SourceToken, 10, 11), // b
      (@syntax.LeafKind::SourceTrivia, 11, 12),
      (@syntax.LeafKind::SourceToken, 12, 16), // FROM
      (@syntax.LeafKind::SourceTrivia, 16, 17),
      (@syntax.LeafKind::SourceToken, 17, 18), // t
    ],
  )
  assert_eq(filter_code(run_rules(doc2, src2, doris_ctx("4.x"), None, LintOptions::default()), "FATHOM-LINT-003").length(), 0)
}

test "rule_001_unquoted_reserved_word_narrow_scope" {
  // SELECT order FROM t -> 001 on `order` (projection item first position)
  let (doc1, src1) = lint_doc(
    b"SELECT order FROM t",
    @syntax.SyntaxKind::Select,
    [
      (@syntax.LeafKind::SourceToken, 0, 6), // SELECT
      (@syntax.LeafKind::SourceTrivia, 6, 7),
      (@syntax.LeafKind::SourceToken, 7, 12), // order (reserved)
      (@syntax.LeafKind::SourceTrivia, 12, 13),
      (@syntax.LeafKind::SourceToken, 13, 17), // FROM
      (@syntax.LeafKind::SourceTrivia, 17, 18),
      (@syntax.LeafKind::SourceToken, 18, 19), // t
    ],
  )
  let f1 = filter_code(run_rules(doc1, src1, doris_ctx("4.x"), None, LintOptions::default()), "FATHOM-LINT-001")
  assert_eq(f1.length(), 1)
  assert_eq(f1[0].start_byte, 7)
  assert_eq(f1[0].end_byte, 12)
  assert_true(f1[0].fix is Some(_))
  // ORDER BY x clause keyword -> no 001
  let (doc2, src2) = lint_doc(
    b"SELECT a FROM t ORDER BY x",
    @syntax.SyntaxKind::Select,
    [
      (@syntax.LeafKind::SourceToken, 0, 6),
      (@syntax.LeafKind::SourceTrivia, 6, 7),
      (@syntax.LeafKind::SourceToken, 7, 8), // a
      (@syntax.LeafKind::SourceTrivia, 8, 9),
      (@syntax.LeafKind::SourceToken, 9, 13), // FROM
      (@syntax.LeafKind::SourceTrivia, 13, 14),
      (@syntax.LeafKind::SourceToken, 14, 15), // t
      (@syntax.LeafKind::SourceTrivia, 15, 16),
      (@syntax.LeafKind::SourceToken, 16, 21), // ORDER
      (@syntax.LeafKind::SourceTrivia, 21, 22),
      (@syntax.LeafKind::SourceToken, 22, 24), // BY
      (@syntax.LeafKind::SourceTrivia, 24, 25),
      (@syntax.LeafKind::SourceToken, 25, 26), // x
    ],
  )
  assert_eq(filter_code(run_rules(doc2, src2, doris_ctx("4.x"), None, LintOptions::default()), "FATHOM-LINT-001").length(), 0)
  // SELECT `order` FROM t (quoted) -> no 001
  let (doc3, src3) = lint_doc(
    b"SELECT `order` FROM t",
    @syntax.SyntaxKind::Select,
    [
      (@syntax.LeafKind::SourceToken, 0, 6),
      (@syntax.LeafKind::SourceTrivia, 6, 7),
      (@syntax.LeafKind::SourceToken, 7, 14), // `order` (quoted)
      (@syntax.LeafKind::SourceTrivia, 14, 15),
      (@syntax.LeafKind::SourceToken, 15, 19), // FROM
      (@syntax.LeafKind::SourceTrivia, 19, 20),
      (@syntax.LeafKind::SourceToken, 20, 21), // t
    ],
  )
  assert_eq(filter_code(run_rules(doc3, src3, doris_ctx("4.x"), None, LintOptions::default()), "FATHOM-LINT-001").length(), 0)
  // SELECT a FROM order (table-name position) -> 001 narrow scope does NOT fire
  let (doc4, src4) = lint_doc(
    b"SELECT a FROM order",
    @syntax.SyntaxKind::Select,
    [
      (@syntax.LeafKind::SourceToken, 0, 6),
      (@syntax.LeafKind::SourceTrivia, 6, 7),
      (@syntax.LeafKind::SourceToken, 7, 8), // a
      (@syntax.LeafKind::SourceTrivia, 8, 9),
      (@syntax.LeafKind::SourceToken, 9, 13), // FROM
      (@syntax.LeafKind::SourceTrivia, 13, 14),
      (@syntax.LeafKind::SourceToken, 14, 19), // order (table name, out of scope)
    ],
  )
  assert_eq(filter_code(run_rules(doc4, src4, doris_ctx("4.x"), None, LintOptions::default()), "FATHOM-LINT-001").length(), 0)
}

test "rule_002_version_gated_merge_advisory" {
  // MERGE under 2.1 -> advisory
  let (doc, src) = lint_doc(
    b"MERGE INTO t USING s ON t.id = s.id",
    @syntax.SyntaxKind::Merge,
    [
      (@syntax.LeafKind::SourceToken, 0, 5), // MERGE
      (@syntax.LeafKind::SourceTrivia, 5, 6),
      (@syntax.LeafKind::SourceToken, 6, 10), // INTO
      (@syntax.LeafKind::SourceTrivia, 10, 11),
      (@syntax.LeafKind::SourceToken, 11, 12), // t
      (@syntax.LeafKind::SourceTrivia, 12, 13),
      (@syntax.LeafKind::SourceToken, 13, 17), // USING
      (@syntax.LeafKind::SourceTrivia, 17, 18),
      (@syntax.LeafKind::SourceToken, 18, 19), // s
      (@syntax.LeafKind::SourceTrivia, 19, 20),
      (@syntax.LeafKind::SourceToken, 20, 22), // ON
      (@syntax.LeafKind::SourceTrivia, 22, 23),
      (@syntax.LeafKind::SourceToken, 23, 25), // t
      (@syntax.LeafKind::SourceToken, 25, 26), // .
      (@syntax.LeafKind::SourceToken, 26, 28), // id
      (@syntax.LeafKind::SourceTrivia, 28, 29),
      (@syntax.LeafKind::SourceToken, 29, 30), // =
      (@syntax.LeafKind::SourceTrivia, 30, 31),
      (@syntax.LeafKind::SourceToken, 31, 32), // s
      (@syntax.LeafKind::SourceToken, 32, 33), // .
      (@syntax.LeafKind::SourceToken, 33, 35), // id
    ],
  )
  let f21 = filter_code(run_rules(doc, src, doris_ctx("2.1"), None, LintOptions::default()), "FATHOM-LINT-002")
  assert_eq(f21.length(), 1)
  assert_eq(f21[0].severity, "info")
  // Same statement under 4.x -> no advisory
  let f24 = filter_code(run_rules(doc, src, doris_ctx("4.x"), None, LintOptions::default()), "FATHOM-LINT-002")
  assert_eq(f24.length(), 0)
}

test "rule_008_deprecated_cluster_by" {
  let (doc, src) = lint_doc(
    b"CLUSTER BY (a) INTO 3 BUCKETS",
    @syntax.SyntaxKind::CreateTable,
    [
      (@syntax.LeafKind::SourceToken, 0, 7), // CLUSTER
      (@syntax.LeafKind::SourceTrivia, 7, 8),
      (@syntax.LeafKind::SourceToken, 8, 10), // BY
      (@syntax.LeafKind::SourceTrivia, 10, 11),
      (@syntax.LeafKind::SourceToken, 11, 12), // (
      (@syntax.LeafKind::SourceToken, 12, 13), // a
      (@syntax.LeafKind::SourceToken, 13, 14), // )
      (@syntax.LeafKind::SourceTrivia, 14, 15),
      (@syntax.LeafKind::SourceToken, 15, 19), // INTO
      (@syntax.LeafKind::SourceTrivia, 19, 20),
      (@syntax.LeafKind::SourceToken, 20, 21), // 3
      (@syntax.LeafKind::SourceTrivia, 21, 22),
      (@syntax.LeafKind::SourceToken, 22, 29), // BUCKETS
    ],
  )
  let f = filter_code(run_rules(doc, src, doris_ctx("4.x"), None, LintOptions::default()), "FATHOM-LINT-008")
  assert_eq(f.length(), 1)
  assert_eq(f[0].start_byte, 0)
  assert_eq(f[0].end_byte, 10)
}

test "analyzer_mapping_004_007_and_anly01_skip" {
  let (doc, src) = lint_doc(
    b"SELECT a FROM t",
    @syntax.SyntaxKind::Select,
    [
      (@syntax.LeafKind::SourceToken, 0, 6),
      (@syntax.LeafKind::SourceTrivia, 6, 7),
      (@syntax.LeafKind::SourceToken, 7, 8), // a
      (@syntax.LeafKind::SourceTrivia, 8, 9),
      (@syntax.LeafKind::SourceToken, 9, 13), // FROM
      (@syntax.LeafKind::SourceTrivia, 13, 14),
      (@syntax.LeafKind::SourceToken, 14, 15), // t
    ],
  )
  let analysis : @analyzer.AnalysisResult = {
    bindings: [],
    diagnostics: [
      { code: "unknown-table", message: "unknown table", start_byte: 14, end_byte: 15 },
      { code: "unknown-column", message: "unknown column", start_byte: 7, end_byte: 8 },
      { code: "ambiguous-reference", message: "ambiguous", start_byte: 7, end_byte: 8 },
      { code: "function-arity", message: "arity", start_byte: 7, end_byte: 8 },
      { code: "requires-complete-parse", message: "ignore me", start_byte: 0, end_byte: 1 },
    ],
  }
  let with_catalog = run_rules(doc, src, doris_ctx("4.x"), Some(analysis), LintOptions::default())
  assert_eq(filter_code(with_catalog, "FATHOM-LINT-004").length(), 1)
  assert_eq(filter_code(with_catalog, "FATHOM-LINT-005").length(), 1)
  assert_eq(filter_code(with_catalog, "FATHOM-LINT-006").length(), 1)
  assert_eq(filter_code(with_catalog, "FATHOM-LINT-007").length(), 1)
  // ANLY-01: no catalog -> zero 004-007 findings
  let no_catalog = run_rules(doc, src, doris_ctx("4.x"), None, LintOptions::default())
  assert_eq(filter_code(no_catalog, "FATHOM-LINT-004").length(), 0)
  assert_eq(filter_code(no_catalog, "FATHOM-LINT-005").length(), 0)
  assert_eq(filter_code(no_catalog, "FATHOM-LINT-006").length(), 0)
  assert_eq(filter_code(no_catalog, "FATHOM-LINT-007").length(), 0)
}

test "apply_fixes_refuses_error_tree_d33" {
  // Tree with a SourceError leaf -> accepted=false + exactly one FATHOM-LINT-000
  let (doc, src) = lint_doc(
    b"SELECT 1\xff",
    @syntax.SyntaxKind::Select,
    [
      (@syntax.LeafKind::SourceToken, 0, 6),
      (@syntax.LeafKind::SourceTrivia, 6, 7),
      (@syntax.LeafKind::SourceToken, 7, 8), // 1
      (@syntax.LeafKind::SourceError, 8, 9), // error material
    ],
  )
  let result = apply_fixes(doc, src, doris_ctx("4.x"), [], LintOptions::default())
  assert_eq(result.accepted, false)
  assert_eq(result.output, b"")
  assert_eq(result.diagnostics.length(), 1)
  assert_eq(result.diagnostics[0].code, "FATHOM-LINT-000")
}

test "apply_fixes_wraps_reserved_word_and_preserves_untouched_bytes" {
  // SELECT order FROM t -> fix output SELECT `order` FROM t
  let (doc, src) = lint_doc(
    b"SELECT order FROM t",
    @syntax.SyntaxKind::Select,
    [
      (@syntax.LeafKind::SourceToken, 0, 6),
      (@syntax.LeafKind::SourceTrivia, 6, 7),
      (@syntax.LeafKind::SourceToken, 7, 12), // order
      (@syntax.LeafKind::SourceTrivia, 12, 13),
      (@syntax.LeafKind::SourceToken, 13, 17), // FROM
      (@syntax.LeafKind::SourceTrivia, 17, 18),
      (@syntax.LeafKind::SourceToken, 18, 19), // t
    ],
  )
  let findings = run_rules(doc, src, doris_ctx("4.x"), None, LintOptions::default())
  let result = apply_fixes(doc, src, doris_ctx("4.x"), findings, LintOptions::default())
  assert_eq(result.accepted, true)
  assert_eq(result.output, b"SELECT `order` FROM t")
}

test "apply_edits_skips_overlap_applies_adjacent" {
  // Valid minimal tree over "abcdef" (single token) so apply_fixes passes its
  // D-33 gate; findings carry arbitrary fix spans (apply_fixes applies them).
  let (doc, src) = lint_doc(
    b"abcdef",
    @syntax.SyntaxKind::Select,
    [(@syntax.LeafKind::SourceToken, 0, 6)],
  )
  // overlapping: [1,3) then [2,4) -> second skipped
  let findings_overlap : Array[LintFinding] = [
    {
      code: "FATHOM-LINT-001",
      severity: "warning",
      message: "a",
      start_byte: 1,
      end_byte: 3,
      statement_id: 0U,
      fix: Some({ start_byte: 1, end_byte: 3, new_text: b"XX" }),
    },
    {
      code: "FATHOM-LINT-001",
      severity: "warning",
      message: "b",
      start_byte: 2,
      end_byte: 4,
      statement_id: 0U,
      fix: Some({ start_byte: 2, end_byte: 4, new_text: b"YY" }),
    },
  ]
  let r1 = apply_fixes(doc, src, doris_ctx("4.x"), findings_overlap, LintOptions::default())
  assert_eq(r1.output, b"aXXdef")
  // adjacent: [1,3) then [3,5) -> both apply
  let findings_adj : Array[LintFinding] = [
    {
      code: "FATHOM-LINT-001",
      severity: "warning",
      message: "a",
      start_byte: 1,
      end_byte: 3,
      statement_id: 0U,
      fix: Some({ start_byte: 1, end_byte: 3, new_text: b"XX" }),
    },
    {
      code: "FATHOM-LINT-001",
      severity: "warning",
      message: "b",
      start_byte: 3,
      end_byte: 5,
      statement_id: 0U,
      fix: Some({ start_byte: 3, end_byte: 5, new_text: b"YY" }),
    },
  ]
  let r2 = apply_fixes(doc, src, doris_ctx("4.x"), findings_adj, LintOptions::default())
  assert_eq(r2.output, b"aXXYYf")
  // out-of-bounds edit skipped
  let findings_oob : Array[LintFinding] = [
    {
      code: "FATHOM-LINT-001",
      severity: "warning",
      message: "z",
      start_byte: 0,
      end_byte: 99,
      statement_id: 0U,
      fix: Some({ start_byte: 0, end_byte: 99, new_text: b"Z" }),
    },
    {
      code: "FATHOM-LINT-001",
      severity: "warning",
      message: "a",
      start_byte: 1,
      end_byte: 3,
      statement_id: 0U,
      fix: Some({ start_byte: 1, end_byte: 3, new_text: b"XX" }),
    },
  ]
  let r3 = apply_fixes(doc, src, doris_ctx("4.x"), findings_oob, LintOptions::default())
  assert_eq(r3.output, b"aXXdef")
}

test "rule_disabled_via_options" {
  // SELECT * FROM t with 003 disabled -> no 003
  let (doc, src) = lint_doc(
    b"SELECT * FROM t",
    @syntax.SyntaxKind::Select,
    [
      (@syntax.LeafKind::SourceToken, 0, 6),
      (@syntax.LeafKind::SourceTrivia, 6, 7),
      (@syntax.LeafKind::SourceToken, 7, 8),
      (@syntax.LeafKind::SourceTrivia, 8, 9),
      (@syntax.LeafKind::SourceToken, 9, 13),
      (@syntax.LeafKind::SourceTrivia, 13, 14),
      (@syntax.LeafKind::SourceToken, 14, 15),
    ],
  )
  let options = match LintOptions::new([
    { code: "FATHOM-LINT-003", setting: RuleSetting::Disabled },
  ]) {
    Ok(value) => value
    Err(_) => panic()
  }
  assert_eq(filter_code(run_rules(doc, src, doris_ctx("4.x"), None, options), "FATHOM-LINT-003").length(), 0)
}

fn filter_code(findings : Array[LintFinding], code : String) -> Array[LintFinding] {
  let out : Array[LintFinding] = []
  for finding in findings {
    if finding.code == code {
      out.push(finding)
    }
  }
  out
}
