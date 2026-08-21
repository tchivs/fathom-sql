///|
/// Formatter tracer tests (plan 03-01): embedded fixtures mirroring the Phase 2
/// EmbeddedManifestFixture convention (test/parser_test.mbt:463-505). Runtime
/// tests never load the disk — raw bytes and goldens are embedded (STATE.md).
///
/// NAMING-GATE CONSTRAINT (IN-03): scripts/check_naming.py exempts this file
/// from the DORIS- pattern (EMBEDDED_FIXTURE_FILES) ONLY because its DORIS-
/// text lives inside frozen embedded fixture/golden bytes. Do NOT add DORIS-
/// text (comments, messages, identifiers) OUTSIDE embedded fixture literals
/// here — the exemption is file-scoped, so the gate cannot see it.
///
/// Contracts under test:
/// - byte-exact idempotence format(format(x)) == format(x) (D-34, Pitfall 6:
///   full Bytes equality, no trimming);
/// - zero-diagnostic reparse of accepted output (D-35);
/// - absolute refusal with FATHOM-FORMAT-001 on error trees (D-33);
/// - CRLF byte-for-byte preservation (flagged assumption A2);
/// - empty input formats to empty output.
struct FormatterFixture {
  fixture_id : String
  profile : String
  mode : String
  raw : Bytes
  expected_valid : Bool
  expected_golden : Bytes
  /// Per-fixture FormatOptions; None uses the defaults (D-29..D-32). The same
  /// options drive the idempotence pass so format(format(x)) is byte-exact
  /// under the fixture's own policy (D-34).
  options : @formatter.FormatOptions?
}

///|
fn formatter_fixture_ok(fixture : FormatterFixture) -> Bool {
  let options = match fixture.options {
    Some(opts) => opts
    None => @formatter.FormatOptions::default()
  }
  let formatted = match
    @api.format_with_ids(
      fixture.raw,
      "doris",
      fixture.profile,
      fixture.mode,
      options,
    ) {
    Ok(result) => result
    Err(_) => return false
  }
  if fixture.expected_valid {
    if !formatted.accepted || formatted.output != fixture.expected_golden {
      return false
    }
    // D-34: idempotence — formatting the formatted output is byte-identical.
    let again = match
      @api.format_with_ids(
        formatted.output,
        "doris",
        fixture.profile,
        fixture.mode,
        options,
      ) {
      Ok(result) => result
      Err(_) => return false
    }
    if again.output != formatted.output {
      return false
    }
    // D-35: the formatted output reparses cleanly with zero diagnostics.
    let reparsed = match
      @api.parse_with_ids(
        formatted.output,
        "doris",
        fixture.profile,
        fixture.mode,
      ) {
      Ok(result) => result
      Err(_) => return false
    }
    if !reparsed.valid || reparsed.diagnostics.length() != 0 {
      return false
    }
    true
  } else {
    // D-33: refusal — no partial output is ever emitted.
    if formatted.accepted || formatted.output.length() != 0 {
      return false
    }
    let mut found = false
    for diagnostic in formatted.diagnostics {
      if diagnostic.code.has_prefix("FATHOM-FORMAT-") {
        found = true
      }
    }
    found
  }
}

///|
test "formatter_tracer_fixtures_hit_goldens_and_oracles" {
  let fixtures = [
    // 4.x SELECT with lowercase keywords, a hint block, an inline block
    // comment, and a line comment: hint/comment bytes verbatim (D-36),
    // keywords uppercased via the classification table (D-28/D-29), trailing
    // newline exactly one (D-32).
    {
      fixture_id: "4.x-select-comments-hint",
      profile: "4.x",
      mode: "strict",
      raw: b"select /*+ SET_VAR(enable_vectorized_engine=true) */ a, /* keep */ b -- trailing\nfrom t",
      expected_valid: true,
      options: None,
      expected_golden: b"SELECT /*+ SET_VAR(enable_vectorized_engine=true) */ a, /* keep */ b -- trailing\nFROM t\n",
    },
    // 3.x multi-clause SELECT (FROM/WHERE/GROUP BY/ORDER BY) whose select list
    // exceeds line_width 100: measure-then-break puts one item per line at
    // indent+1 (Pattern 2), clause keywords break at column 0 (Pattern 1).
    {
      fixture_id: "3.x-select-multiclause-long-list",
      profile: "3.x",
      mode: "strict",
      raw: b"select user_id, user_name, user_email, user_phone, user_address, user_status, user_created_at, user_updated_at from user_profile where user_status = 'active' group by user_id order by user_created_at",
      expected_valid: true,
      options: None,
      expected_golden: b"SELECT\n  user_id,\n  user_name,\n  user_email,\n  user_phone,\n  user_address,\n  user_status,\n  user_created_at,\n  user_updated_at\nFROM user_profile\nWHERE user_status = 'active'\nGROUP BY user_id\nORDER BY user_created_at\n",
    },
    // Error tree (unsupported statement): absolute refusal, empty output.
    {
      fixture_id: "4.x-error-tree-refusal",
      profile: "4.x",
      mode: "strict",
      raw: b"drop table x",
      expected_valid: false,
      options: None,
      expected_golden: b"",
    },
    // Version-invalid 2.1 MERGE (SourceError leaf): refusal with FATHOM-FORMAT-001.
    {
      fixture_id: "2.1-merge-version-invalid-refusal",
      profile: "2.1",
      mode: "strict",
      raw: b"MERGE INTO t USING s ON a=b WHEN MATCHED THEN UPDATE SET x=1",
      expected_valid: false,
      options: None,
      expected_golden: b"",
    },
    // Empty input: accepted, empty output, no diagnostics.
    {
      fixture_id: "4.x-empty",
      profile: "4.x",
      mode: "strict",
      raw: b"",
      expected_valid: true,
      options: None,
      expected_golden: b"",
    },
    // CRLF input: \r\n preserved byte-for-byte (flagged assumption A2).
    {
      fixture_id: "4.x-crlf",
      profile: "4.x",
      mode: "strict",
      raw: b"select a\r\nfrom t",
      expected_valid: true,
      options: None,
      expected_golden: b"SELECT a\r\nFROM t\r\n",
    },
  ]
  for fixture in fixtures {
    assert_true(formatter_fixture_ok(fixture))
  }
}

///|
test "formatter_options_default_and_validation" {
  let defaults = @formatter.FormatOptions::default()
  assert_true(defaults.keyword_case() is @formatter.KeywordCase::Upper)
  assert_eq(defaults.indent(), 2)
  assert_eq(defaults.line_width(), 100)
  assert_true(defaults.comma_style() is @formatter.CommaStyle::Trailing)
  assert_true(defaults.newline_style() is @formatter.NewlineStyle::FollowInput)
  assert_true(defaults.trailing_newline())
  // ASVS V5: invalid config fails construction, never reaches layout.
  let bad_indent = @formatter.FormatOptions::new(
    @formatter.KeywordCase::Upper,
    -1,
    100,
    @formatter.CommaStyle::Trailing,
    @formatter.NewlineStyle::FollowInput,
    true,
  )
  assert_true(
    bad_indent is Err(@formatter.FormatError::InvalidIndent(value=-1)),
  )
  // WR-02: indent is capped (MAX_INDENT = 64) so a typo like --indent
  // 5000000 fails construction instead of materializing gigabytes of
  // leading spaces per broken line.
  let over_cap_indent = @formatter.FormatOptions::new(
    @formatter.KeywordCase::Upper,
    65,
    100,
    @formatter.CommaStyle::Trailing,
    @formatter.NewlineStyle::FollowInput,
    true,
  )
  assert_true(
    over_cap_indent is Err(@formatter.FormatError::InvalidIndent(value=65)),
  )
  // The cap itself remains a valid indent.
  let cap_indent = @formatter.FormatOptions::new(
    @formatter.KeywordCase::Upper,
    64,
    100,
    @formatter.CommaStyle::Trailing,
    @formatter.NewlineStyle::FollowInput,
    true,
  )
  assert_true(cap_indent is Ok(_))
  let bad_width = @formatter.FormatOptions::new(
    @formatter.KeywordCase::Upper,
    2,
    0,
    @formatter.CommaStyle::Trailing,
    @formatter.NewlineStyle::FollowInput,
    true,
  )
  assert_true(
    bad_width is Err(@formatter.FormatError::InvalidLineWidth(value=0)),
  )
}

///|
test "formatter_refusal_never_masks_parse_diagnostics" {
  // Threat T-03-01: format_text converts FATHOM-PARSE-* diagnostics and
  // prepends them so FATHOM-FORMAT-001 never masks parse errors.
  let raw = b"MERGE INTO t USING s ON a=b WHEN MATCHED THEN UPDATE SET x=1"
  let options = @formatter.FormatOptions::default()
  let parse_options = match @api.ParseOptions::new("doris", "2.1", "strict") {
    Ok(options) => options
    Err(_) => panic()
  }
  let result = match @api.format_text(raw, parse_options, options) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!result.accepted)
  assert_eq(result.output.length(), 0)
  assert_true(result.diagnostics.length() >= 2)
  assert_true(result.diagnostics[0].code.has_prefix("FATHOM-PARSE-"))
  assert_true(result.diagnostics[0].code == "FATHOM-PARSE-006")
  // Exactly one FATHOM-FORMAT-001, and it comes after the parse diagnostics.
  let mut format_count = 0
  for diagnostic in result.diagnostics {
    if diagnostic.code == "FATHOM-FORMAT-001" {
      format_count = format_count + 1
    }
  }
  assert_eq(format_count, 1)
  assert_eq(
    result.diagnostics[result.diagnostics.length() - 1].code,
    "FATHOM-FORMAT-001",
  )
  // The diagnostic shape mirrors PrimitiveDiagnostic fields.
  let refusal = result.diagnostics[result.diagnostics.length() - 1]
  assert_eq(refusal.severity, "error")
  assert_eq(refusal.expected_class, "format")
  assert_true(refusal.start_byte <= refusal.end_byte)
  assert_eq(refusal.statement_id, 0U)
}

///|
test "formatter_from_id_maps_cli_string_ids" {
  // The CLI flag surface (03-04) maps string values with these helpers.
  assert_true(
    @formatter.KeywordCase::from_id("upper")
    is Some(@formatter.KeywordCase::Upper),
  )
  assert_true(
    @formatter.KeywordCase::from_id("lower")
    is Some(@formatter.KeywordCase::Lower),
  )
  assert_true(@formatter.KeywordCase::from_id("mixed") is None)
  assert_true(
    @formatter.CommaStyle::from_id("trailing")
    is Some(@formatter.CommaStyle::Trailing),
  )
  assert_true(
    @formatter.CommaStyle::from_id("leading")
    is Some(@formatter.CommaStyle::Leading),
  )
  assert_true(@formatter.CommaStyle::from_id("none") is None)
  assert_true(
    @formatter.NewlineStyle::from_id("follow")
    is Some(@formatter.NewlineStyle::FollowInput),
  )
  assert_true(
    @formatter.NewlineStyle::from_id("lf") is Some(@formatter.NewlineStyle::Lf),
  )
  assert_true(
    @formatter.NewlineStyle::from_id("crlf")
    is Some(@formatter.NewlineStyle::Crlf),
  )
  assert_true(@formatter.NewlineStyle::from_id("auto") is None)
}

///|
test "formatter_statement_offsets_index_into_output" {
  let options = @formatter.FormatOptions::default()
  let result = match
    @api.format_with_ids(
      b"select 1; select 2", "doris", "4.x", "strict", options,
    ) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(result.accepted)
  let offsets = result.statement_offsets
  assert_eq(offsets.length(), 2)
  assert_eq(offsets[0], 0)
  assert_true(offsets[1] > offsets[0])
  assert_true(offsets[1] < result.output.length())
  // The inter-statement separator newline is emitted as part of the next
  // statement's layout (pending break materialized at its first token), so the
  // second statement's offset points at the separator byte: len("SELECT 1;").
  assert_eq(offsets[1], b"SELECT 1;".length())
  // Statement-per-line separation; the input's second statement has no
  // trailing semicolon, so neither does the output.
  assert_eq(result.output, b"SELECT 1;\nSELECT 2\n")
  // Empty documents yield an empty offsets array.
  let empty = match
    @api.format_with_ids(b"", "doris", "4.x", "strict", options) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(empty.statement_offsets.length(), 0)
  assert_eq(empty.output.length(), 0)
}

///|
test "formatter_metadata_and_ids_agree_on_output" {
  // format_with_metadata (manifest-style) and format_with_ids must produce the
  // same formatted output — metadata propagation is irrelevant to formatting.
  let raw = b"select /*+ SET_VAR(enable_vectorized_engine=true) */ a, /* keep */ b -- trailing\nfrom t"
  let options = @formatter.FormatOptions::default()
  let via_ids = match
    @api.format_with_ids(raw, "doris", "4.x", "strict", options) {
    Ok(result) => result
    Err(_) => panic()
  }
  let via_metadata = match
    @api.format_with_metadata(
      raw, "doris", "4.x", "4.x", "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT",
      "strict", options,
    ) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(via_ids.accepted)
  assert_true(via_metadata.accepted)
  assert_eq(via_metadata.output, via_ids.output)
  assert_eq(via_metadata.diagnostics.length(), via_ids.diagnostics.length())
}

///|
test "formatter_determinism_pure_function_backstop" {
  // Probe FMT-01: format_text is a pure function of (raw, parse_options,
  // format_options) — repeated calls return byte-identical output and
  // diagnostics, with no shared mutable state or IO.
  let raw = b"select user_id, user_name, user_email, user_phone, user_address, user_status, user_created_at, user_updated_at from user_profile where user_status = 'active' group by user_id order by user_created_at"
  let options = @formatter.FormatOptions::default()
  let parse_options = match @api.ParseOptions::new("doris", "3.x", "strict") {
    Ok(options) => options
    Err(_) => panic()
  }
  let first = match @api.format_text(raw, parse_options, options) {
    Ok(result) => result
    Err(_) => panic()
  }
  let second = match @api.format_text(raw, parse_options, options) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(first.accepted)
  assert_true(second.accepted)
  assert_eq(second.output, first.output)
  assert_eq(second.diagnostics.length(), first.diagnostics.length())
}

///|
test "formatter_options_error_propagation_never_reaches_api" {
  // ASVS V5: invalid option structs fail construction, so the api entry only
  // ever receives validated FormatOptions values (type-safe by construction).
  let bad_indent = @formatter.FormatOptions::new(
    @formatter.KeywordCase::Upper,
    -2,
    100,
    @formatter.CommaStyle::Trailing,
    @formatter.NewlineStyle::FollowInput,
    true,
  )
  assert_true(
    bad_indent is Err(@formatter.FormatError::InvalidIndent(value=-2)),
  )
  let bad_width = @formatter.FormatOptions::new(
    @formatter.KeywordCase::Upper,
    2,
    -10,
    @formatter.CommaStyle::Trailing,
    @formatter.NewlineStyle::FollowInput,
    true,
  )
  assert_true(
    bad_width is Err(@formatter.FormatError::InvalidLineWidth(value=-10)),
  )
}

///|
/// 03-02 Task 1: per-family clause tables (research Pattern 1) — every
/// supported statement family renders with hard breaks only at its table's
/// clause keywords (never at the statement's first token), subquery bodies
/// indent inner clauses at +1, and unknown families fall back to flat
/// token-sequence-preserving emission. All fixtures assert byte-exact
/// idempotence (D-34) and zero-diagnostic reparse (D-35).
///
/// Canonical spacing convention (inherited from 03-01): no space before
/// "(" — so FROM(, WHERE(, VALUES(, KEY( etc. render parens directly
/// attached to the preceding keyword (zero-space punctuation rule).
test "formatter_03_02_family_clause_tables_and_subquery_indent" {
  let fixtures = [
    // INSERT: INTO (table keyword) breaks after the family start; VALUES
    // clause breaks; the single VALUES row fits inline.
    {
      fixture_id: "4.x-insert-values-family",
      profile: "4.x",
      mode: "strict",
      raw: b"insert into test values (1, 2);",
      expected_valid: true,
      options: None,
      expected_golden: b"INSERT\nINTO test\nVALUES(1, 2);\n",
    },
    // UPDATE: SET and WHERE break; the SET assignment list stays inline
    // (SET is not a list context — commas flow in canonical ", " form).
    {
      fixture_id: "4.x-update-set-where-family",
      profile: "4.x",
      mode: "strict",
      raw: b"update t1 set c1 = 1, c2 = default where id = 1;",
      expected_valid: true,
      options: None,
      expected_golden: b"UPDATE t1\nSET c1 = 1, c2 = DEFAULT\nWHERE id = 1;\n",
    },
    // DELETE: FROM breaks after the family start; WHERE breaks.
    {
      fixture_id: "4.x-delete-from-where-family",
      profile: "4.x",
      mode: "strict",
      raw: b"delete from t where id = 1;",
      expected_valid: true,
      options: None,
      expected_golden: b"DELETE\nFROM t\nWHERE id = 1;\n",
    },
    // MERGE (4.x): every Merge-table keyword breaks (INTO USING ON WHEN
    // THEN UPDATE SET) per the literal Pattern-1 rule.
    {
      fixture_id: "4.x-merge-family",
      profile: "4.x",
      mode: "strict",
      raw: b"merge into t using s on t.id = s.id when matched then update set t.v = s.v;",
      expected_valid: true,
      options: None,
      expected_golden: b"MERGE\nINTO t\nUSING s\nON t.id = s.id\nWHEN MATCHED\nTHEN\nUPDATE\nSET t.v = s.v;\n",
    },
    // CREATE VIEW: AS and SELECT break (DDL shared table); FROM is not in
    // the DDL table so the query body stays on the SELECT line.
    {
      fixture_id: "4.x-create-view-family",
      profile: "4.x",
      mode: "strict",
      raw: b"create view v as select a, b from t;",
      expected_valid: true,
      options: None,
      expected_golden: b"CREATE VIEW v\nAS\nSELECT a, b FROM t;\n",
    },
    // CREATE TABLE with the full body: column definitions break at indent+1,
    // clause keywords (COMMENT inside the column group, ENGINE, UNIQUE KEY,
    // ORDER BY, PARTITION BY, DISTRIBUTED BY, ROLLUP, PROPERTIES) break at
    // their level; RANGE(k1) (PARTITION ...) partition definitions fit
    // inline; type words keep input case (only classification-table words
    // are rewritten, D-28).
    {
      fixture_id: "4.x-create-table-family",
      profile: "4.x",
      mode: "strict",
      raw: b"create table example_table (k1 tinyint, k2 decimal(10, 2) default \"10.5\", k3 char(10) comment \"string column\", k4 int not null default \"1\" comment \"int column\", v1 bigint sum default \"0\" comment \"aggregate value\", index idx_k1 (k1) using bitmap comment \"index comment\") engine=olap unique key(k1, k2) order by(k1) comment \"my table\" partition by range(k1) (partition p1 values less than (\"2021-01-01\"), partition p2 values less than (\"2022-01-01\")) distributed by hash(k1) buckets 32 rollup (r1 (k1) duplicate key (k1)) properties (\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");",
      expected_valid: true,
      options: None,
      expected_golden: b"CREATE\nTABLE example_table(\n  k1 tinyint,\n  k2 decimal(10, 2) DEFAULT \"10.5\",\n  k3 char(10)\n  COMMENT \"string column\",\n  k4 int NOT NULL DEFAULT \"1\"\n  COMMENT \"int column\",\n  v1 bigint sum DEFAULT \"0\"\n  COMMENT \"aggregate value\",\n  INDEX idx_k1(k1) USING bitmap\n  COMMENT \"index comment\"\n)\nENGINE=olap UNIQUE\nKEY(k1, k2)\nORDER BY(k1)\nCOMMENT \"my table\"\nPARTITION BY RANGE(k1)(PARTITION p1 VALUES LESS THAN(\"2021-01-01\"), PARTITION p2 VALUES LESS THAN(\"2022-01-01\"))\nDISTRIBUTED BY HASH(k1) BUCKETS 32\nROLLUP(r1(k1) DUPLICATE KEY(k1))\nPROPERTIES(\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");\n",
    },
    // Subquery indentation (Task 1 acceptance): the paren group after FROM is
    // an expression-run body whose clause keywords break at indent+1; the
    // inner SELECT starts its own line at +1; paren depth returns to the
    // statement level after the closing paren (outer WHERE at column 0).
    {
      fixture_id: "4.x-select-subquery-indent",
      profile: "4.x",
      mode: "strict",
      raw: b"select user_id, user_name from (select user_id, user_name from user_profile where user_status = 'active') sub where user_id > 1",
      expected_valid: true,
      options: None,
      expected_golden: b"SELECT user_id, user_name\nFROM(\n  SELECT user_id, user_name\n  FROM user_profile\n  WHERE user_status = 'active') sub\nWHERE user_id > 1\n",
    },
  ]
  for fixture in fixtures {
    assert_true(formatter_fixture_ok(fixture))
  }
}

///|
/// 03-02 Task 1: a family without a clause table (a bare ValueList-shaped
/// document, constructed directly against the CST since the parser never
/// produces one) falls back to token-sequence-preserving flat emission — no
/// clause break is forced and every leaf byte is replayed.
test "formatter_unknown_family_falls_back_to_flat_emission" {
  let raw = b"(1, 2)"
  let source = match @source.SourceText::new_with_limit(raw, 8388608) {
    Ok(s) => s
    Err(_) => panic()
  }
  let span = fn(start : Int, end : Int) -> @source.Span {
    match @source.Span::checked(start, end, raw.length()) {
      Ok(s) => s
      Err(_) => panic()
    }
  }
  let leaves = [
    @syntax.SyntaxElement::Leaf(
      @syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceToken, span(0, 1)),
    ),
    @syntax.SyntaxElement::Leaf(
      @syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceToken, span(1, 2)),
    ),
    @syntax.SyntaxElement::Leaf(
      @syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceToken, span(2, 3)),
    ),
    @syntax.SyntaxElement::Leaf(
      @syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceTrivia, span(3, 4)),
    ),
    @syntax.SyntaxElement::Leaf(
      @syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceToken, span(4, 5)),
    ),
    @syntax.SyntaxElement::Leaf(
      @syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceToken, span(5, 6)),
    ),
  ]
  let family = match
    @syntax.SyntaxNode::new(@syntax.SyntaxKind::ValueList, span(0, 6), leaves) {
    Some(node) => node
    None => panic()
  }
  let statement = match
    @syntax.SyntaxNode::new(@syntax.SyntaxKind::Statement, span(0, 6), [
      @syntax.SyntaxElement::ChildNode(family),
    ]) {
    Some(node) => node
    None => panic()
  }
  let root = match
    @syntax.SyntaxNode::new(@syntax.SyntaxKind::Document, span(0, 6), [
      @syntax.SyntaxElement::ChildNode(statement),
    ]) {
    Some(node) => node
    None => panic()
  }
  let result = @formatter.format(
    root,
    source,
    @formatter.FormatOptions::default(),
    doris_context("4.x"),
  )
  assert_true(result.accepted)
  // Flat emission: `(1, 2)` with the canonical single trailing newline — the
  // ValueList family has no clause table, so no break is forced anywhere and
  // the full token sequence is replayed byte-for-byte.
  assert_eq(result.output, b"(1, 2)\n")
  assert_eq(result.diagnostics.length(), 0)
}

///|
/// 03-02 Task 2: measure-then-break list layout (research Pattern 2). The
/// flat-fit decision reads only the summed leaf spans (never the running
/// column), so idempotence holds by construction; comma placement follows
/// options.comma_style(); expression runs (function arguments, arithmetic
/// parens) are never broken internally; a last-item comma is emitted only
/// where the empirical reparse probe accepted it (see comment below).
///
/// Empirical trailing-comma probe (4.x strict, run during implementation —
/// flagged assumption A1 / research Open Q1): parse_with_ids accepts a comma
/// after the last list item in exactly two contexts —
///   PROPERTIES ( ... )              ACCEPTS (probe: 1 and 2 items)
///   partition-defs ( ... ) after )  ACCEPTS (probe: 1 and 2 items)
/// and REJECTS it everywhere else: select list, VALUES rows, VALUES row
/// interior, column definitions, IN list, KEY list, function arguments,
/// PARTITIONS list, INSERT column list. Emitted last-item commas therefore
/// appear only in the two accepted contexts below (goldens assert the
/// reparse gate); every other context emits no last-item comma.
test "formatter_03_02_list_layout_and_comma_styles" {
  let narrow = match
    @formatter.FormatOptions::new(
      @formatter.KeywordCase::Upper,
      2,
      20,
      @formatter.CommaStyle::Trailing,
      @formatter.NewlineStyle::FollowInput,
      true,
    ) {
    Ok(opts) => opts
    Err(_) => panic()
  }
  let leading = match
    @formatter.FormatOptions::new(
      @formatter.KeywordCase::Upper,
      2,
      20,
      @formatter.CommaStyle::Leading,
      @formatter.NewlineStyle::FollowInput,
      true,
    ) {
    Ok(opts) => opts
    Err(_) => panic()
  }
  let fixtures = [
    // (a) A VALUES list that fits: whole-list-fits emits it inline.
    {
      fixture_id: "4.x-values-list-fits-inline",
      profile: "4.x",
      mode: "strict",
      raw: b"insert into t values (1, 2), (3, 4), (5, 6), (7, 8)",
      expected_valid: true,
      options: None,
      expected_golden: b"INSERT\nINTO t\nVALUES(1, 2),(3, 4),(5, 6),(7, 8)\n",
    },
    // (b) The same VALUES list at line_width 20: one row per line at
    // indent+1, trailing commas, no last-item comma (probe: VALUES rejects).
    {
      fixture_id: "4.x-values-list-break-one-row-per-line",
      profile: "4.x",
      mode: "strict",
      raw: b"insert into t values (1, 2), (3, 4), (5, 6), (7, 8)",
      expected_valid: true,
      options: Some(narrow),
      expected_golden: b"INSERT\nINTO t\nVALUES\n  (1, 2),\n  (3, 4),\n  (5, 6),\n  (7, 8)\n",
    },
    // (c) Select list at line_width 20: one item per line at indent+1 with
    // Trailing comma placement; no last-item comma (probe: select rejects).
    {
      fixture_id: "4.x-select-list-break-trailing",
      profile: "4.x",
      mode: "strict",
      raw: b"select a, b, c, d, e, f, g, h, i, j, k from t where id = 1",
      expected_valid: true,
      options: Some(narrow),
      expected_golden: b"SELECT\n  a,\n  b,\n  c,\n  d,\n  e,\n  f,\n  g,\n  h,\n  i,\n  j,\n  k\nFROM t\nWHERE id = 1\n",
    },
    // (d) Leading comma style: the comma opens the following item's line.
    {
      fixture_id: "4.x-select-list-break-leading",
      profile: "4.x",
      mode: "strict",
      raw: b"select a, b, c, d, e, f, g, h, i, j, k from t where id = 1",
      expected_valid: true,
      options: Some(leading),
      expected_golden: b"SELECT\n  a\n  , b\n  , c\n  , d\n  , e\n  , f\n  , g\n  , h\n  , i\n  , j\n  , k\nFROM t\nWHERE id = 1\n",
    },
    // (e) Expression runs are never broken internally: function arguments
    // (f( ... )) and arithmetic parens stay on one line even when long.
    {
      fixture_id: "4.x-function-args-never-broken",
      profile: "4.x",
      mode: "strict",
      raw: b"select f(argument_one, argument_two, argument_three, argument_four, argument_five) from t",
      expected_valid: true,
      options: None,
      expected_golden: b"SELECT f(argument_one, argument_two, argument_three, argument_four, argument_five)\nFROM t\n",
    },
    {
      fixture_id: "4.x-arithmetic-parens-never-broken",
      profile: "4.x",
      mode: "strict",
      raw: b"select * from t where (a + b) * (c - d) / (e % f) > 10 and x = 1",
      expected_valid: true,
      options: None,
      expected_golden: b"SELECT *\nFROM t\nWHERE(a + b) *(c - d) /(e % f) > 10 AND x = 1\n",
    },
    // (f) CREATE TABLE column definitions: the column list breaks at
    // indent+1 when over width (column-definition list context). Seven
    // columns measure ~47 flat chars, so the break needs line_width 20.
    {
      fixture_id: "4.x-create-table-column-list-break",
      profile: "4.x",
      mode: "strict",
      raw: b"create table t (a int, b int, c int, d int, e int, f int, g int)",
      expected_valid: true,
      options: Some(narrow),
      expected_golden: b"CREATE\nTABLE t(\n  a int,\n  b int,\n  c int,\n  d int,\n  e int,\n  f int,\n  g int\n)\n",
    },
    // (g) Probe-accepted contexts: PROPERTIES and partition definitions emit
    // the last-item trailing comma (recorded above); the golden's reparse
    // gate re-verifies Doris acceptance for each emitted comma.
    {
      fixture_id: "4.x-properties-last-item-comma",
      profile: "4.x",
      mode: "strict",
      raw: b"create table t (k1 int) properties (\"storage_medium\" = \"SSD\", \"replication_num\" = \"3\", \"storage_cooldown_ttl\" = \"1d\", \"light_schema_change\" = \"true\")",
      expected_valid: true,
      options: None,
      expected_golden: b"CREATE\nTABLE t(k1 int)\nPROPERTIES(\n  \"storage_medium\" = \"SSD\",\n  \"replication_num\" = \"3\",\n  \"storage_cooldown_ttl\" = \"1d\",\n  \"light_schema_change\" = \"true\",\n)\n",
    },
    {
      fixture_id: "4.x-partition-defs-last-item-comma",
      profile: "4.x",
      mode: "strict",
      raw: b"create table t (k1 date) partition by range(k1) (partition p1 values less than (\"2021-01-01\"), partition p2 values less than (\"2022-01-01\"), partition p3 values less than (\"2023-01-01\"))",
      expected_valid: true,
      options: None,
      expected_golden: b"CREATE\nTABLE t(k1 date)\nPARTITION BY RANGE(k1)(\n  PARTITION p1 VALUES LESS THAN(\"2021-01-01\"),\n  PARTITION p2 VALUES LESS THAN(\"2022-01-01\"),\n  PARTITION p3 VALUES LESS THAN(\"2023-01-01\"),\n)\n",
    },
    // Probe-rejected context (record): IN lists get NO last-item comma even
    // when broken (probe: IN rejects).
    {
      fixture_id: "4.x-in-list-no-last-item-comma",
      profile: "4.x",
      mode: "strict",
      raw: b"select * from t where id in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11) and x = 1",
      expected_valid: true,
      options: Some(narrow),
      expected_golden: b"SELECT *\nFROM t\nWHERE id IN(\n  1,\n  2,\n  3,\n  4,\n  5,\n  6,\n  7,\n  8,\n  9,\n  10,\n  11\n) AND x = 1\n",
    },
  ]
  for fixture in fixtures {
    assert_true(formatter_fixture_ok(fixture))
  }
}

///|
/// 03-02 Task 3: multi-statement script layout (research Open Q4 resolution)
/// and the full comment/hint attachment rule (research Pattern 3). Each
/// statement renders on its own line at column 0 with one newline between
/// statements; `;` tokens are preserved as part of the statement's token
/// sequence; document-leading/trailing comments and between-statement
/// comments survive verbatim at their positions; inline comments stay inline;
/// own-line comments stay on their own line; hints are byte-identical.
test "formatter_03_02_script_layout_and_comment_attachment" {
  let fixtures = [
    // (a) Two-statement script: statement-per-line, one newline separator,
    // both trailing semicolons preserved verbatim.
    {
      fixture_id: "4.x-two-statement-script",
      profile: "4.x",
      mode: "strict",
      raw: b"select 1; select 2;",
      expected_valid: true,
      options: None,
      expected_golden: b"SELECT 1;\nSELECT 2;\n",
    },
    // (b) Script with a leading comment, a comment between statements, and a
    // trailing comment: all three preserved verbatim at their document
    // positions (statement-leading trivia for lead/between; a document-level
    // trivia leaf for the trailing comment).
    {
      fixture_id: "4.x-script-comments-at-document-positions",
      profile: "4.x",
      mode: "strict",
      raw: b"-- lead\nselect 1;\n-- between\nselect 2;\n-- trail",
      expected_valid: true,
      options: None,
      expected_golden: b"-- lead\nSELECT 1;\n-- between\nSELECT 2;\n-- trail\n",
    },
    // (c) Inline comment: a comment after code on the same line (no newline
    // in its original trivia run) stays inline.
    {
      fixture_id: "4.x-inline-comment-stays-inline",
      profile: "4.x",
      mode: "strict",
      raw: b"select a, b from t -- trailing",
      expected_valid: true,
      options: None,
      expected_golden: b"SELECT a, b\nFROM t -- trailing\n",
    },
    // (d) Own-line comment: a comment whose original trivia run contains a
    // newline goes on its own line at the current indent.
    {
      fixture_id: "4.x-own-line-comment-stays-own-line",
      profile: "4.x",
      mode: "strict",
      raw: b"select a from t\n-- own line\nwhere id = 1",
      expected_valid: true,
      options: None,
      expected_golden: b"SELECT a\nFROM t\n-- own line\nWHERE id = 1\n",
    },
    // (e) Hint block: /*+ ... */ bytes verbatim, never uppercased (D-36,
    // research Pitfall 2).
    {
      fixture_id: "4.x-hint-byte-identical",
      profile: "4.x",
      mode: "strict",
      raw: b"select /*+ SET_VAR(enable_vectorized_engine=true) */ a, b from t",
      expected_valid: true,
      options: None,
      expected_golden: b"SELECT /*+ SET_VAR(enable_vectorized_engine=true) */ a, b\nFROM t\n",
    },
    // (f) A line comment at the end of a statement line forces a break after
    // itself (required for -- comments, which would swallow the next clause).
    {
      fixture_id: "4.x-line-comment-forces-break",
      profile: "4.x",
      mode: "strict",
      raw: b"select a, b from t -- c\nwhere id = 1",
      expected_valid: true,
      options: None,
      expected_golden: b"SELECT a, b\nFROM t -- c\nWHERE id = 1\n",
    },
    // (g) The 4.x corpus multi-statement script embedded as raw bytes: all
    // -- provenance-header comments preserved byte-for-byte, statements one
    // per line with their semicolons, family clause breaks per table.
    {
      fixture_id: "4.x-corpus-script",
      profile: "4.x",
      mode: "strict",
      raw: b"-- Released Apache Doris 4.x multi-statement script fixture (DORIS-03): a\n-- semicolon-separated document parses each statement independently with\n-- monotonic statement ids; the invalid-statement variant (later statements\n-- survive) is asserted by the corpus_test oracle.\n-- Source: statement-family pages (https://doris.apache.org/docs/4.x/sql-manual/sql-statements/)\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE TABLE t (a INT); INSERT INTO t VALUES (1); SELECT * FROM t;\nINSERT INTO t VALUES (2); SELECT b;",
      expected_valid: true,
      options: None,
      expected_golden: b"-- Released Apache Doris 4.x multi-statement script fixture (DORIS-03): a\n-- semicolon-separated document parses each statement independently with\n-- monotonic statement ids; the invalid-statement variant (later statements\n-- survive) is asserted by the corpus_test oracle.\n-- Source: statement-family pages (https://doris.apache.org/docs/4.x/sql-manual/sql-statements/)\n-- Retrieved: 2026-08-04\n-- Code fence: grammar:sql\nCREATE\nTABLE t(a INT);\nINSERT\nINTO t\nVALUES(1);\nSELECT *\nFROM t;\nINSERT\nINTO t\nVALUES(2);\nSELECT b;\n",
    },
  ]
  for fixture in fixtures {
    assert_true(formatter_fixture_ok(fixture))
  }
  // statement_offsets stay correct under the per-line loop: the second
  // statement's offset points at the separator byte (len("SELECT 1;")).
  let options = @formatter.FormatOptions::default()
  let result = match
    @api.format_with_ids(
      b"select 1; select 2;", "doris", "4.x", "strict", options,
    ) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(result.accepted)
  assert_eq(result.statement_offsets.length(), 2)
  assert_eq(result.statement_offsets[0], 0)
  assert_eq(result.statement_offsets[1], b"SELECT 1;".length())
}

///|
/// 03-03 Task 1: every one of the six FormatOptions dimensions drives real
/// layout behavior (FMT-02, D-26) — keyword case (Upper/Lower), indent width,
/// line width, comma style, newline style (FollowInput/Lf/Crlf), and the
/// trailing-newline policy. Lower rewrites only classification-table words to
/// their ASCII case-fold; identifiers, quoted names, strings, comments, and
/// hints stay byte-identical (D-28/D-36). All fixtures run the full oracle
/// (golden + byte-exact idempotence D-34 + zero-diagnostic reparse D-35).
test "formatter_03_03_all_six_dimensions_functional" {
  let lower = match
    @formatter.FormatOptions::new(
      @formatter.KeywordCase::Lower,
      2,
      100,
      @formatter.CommaStyle::Trailing,
      @formatter.NewlineStyle::FollowInput,
      true,
    ) {
    Ok(opts) => opts
    Err(_) => panic()
  }
  let indent4 = match
    @formatter.FormatOptions::new(
      @formatter.KeywordCase::Upper,
      4,
      20,
      @formatter.CommaStyle::Trailing,
      @formatter.NewlineStyle::FollowInput,
      true,
    ) {
    Ok(opts) => opts
    Err(_) => panic()
  }
  let width20 = match
    @formatter.FormatOptions::new(
      @formatter.KeywordCase::Upper,
      2,
      20,
      @formatter.CommaStyle::Trailing,
      @formatter.NewlineStyle::FollowInput,
      true,
    ) {
    Ok(opts) => opts
    Err(_) => panic()
  }
  let leading = match
    @formatter.FormatOptions::new(
      @formatter.KeywordCase::Upper,
      2,
      100,
      @formatter.CommaStyle::Leading,
      @formatter.NewlineStyle::FollowInput,
      true,
    ) {
    Ok(opts) => opts
    Err(_) => panic()
  }
  let lf_override = match
    @formatter.FormatOptions::new(
      @formatter.KeywordCase::Upper,
      2,
      100,
      @formatter.CommaStyle::Trailing,
      @formatter.NewlineStyle::Lf,
      true,
    ) {
    Ok(opts) => opts
    Err(_) => panic()
  }
  let crlf_override = match
    @formatter.FormatOptions::new(
      @formatter.KeywordCase::Upper,
      2,
      100,
      @formatter.CommaStyle::Trailing,
      @formatter.NewlineStyle::Crlf,
      true,
    ) {
    Ok(opts) => opts
    Err(_) => panic()
  }
  let no_trailing = match
    @formatter.FormatOptions::new(
      @formatter.KeywordCase::Upper,
      2,
      100,
      @formatter.CommaStyle::Trailing,
      @formatter.NewlineStyle::FollowInput,
      false,
    ) {
    Ok(opts) => opts
    Err(_) => panic()
  }
  let fixtures = [
    // (a) Lower keyword case: SELECT/FROM/AS rewrite to lowercase; the quoted
    // "SELECT" string literal, the `view` identifier (already lowercase), the
    // 'TEXT' literal, the inline block comment, and the -- line comment stay
    // byte-identical (D-28: only classification-table words are rewritten).
    {
      fixture_id: "4.x-lower-keyword-case",
      profile: "4.x",
      mode: "strict",
      raw: b"SELECT \"SELECT\" AS label, view, 'TEXT', /* keep */ 42 FROM t -- note",
      expected_valid: true,
      options: Some(lower),
      expected_golden: b"select \"SELECT\" as label, view, 'TEXT', /* keep */ 42\nfrom t -- note\n",
    },
    // (b) indent 4: a broken select list indents items with 4 spaces
    // (options.indent() drives break_line indents — no fixed 2 remains).
    {
      fixture_id: "4.x-indent-4",
      profile: "4.x",
      mode: "strict",
      raw: b"select a, b, c, d, e, f, g, h, i, j, k from t where id = 1",
      expected_valid: true,
      options: Some(indent4),
      expected_golden: b"SELECT\n    a,\n    b,\n    c,\n    d,\n    e,\n    f,\n    g,\n    h,\n    i,\n    j,\n    k\nFROM t\nWHERE id = 1\n",
    },
    // (c) line_width observable: the same list fits inline at width 100 and
    // breaks one-item-per-line at width 20 (measure-then-break reads
    // options.line_width(), not a fixed 100).
    {
      fixture_id: "4.x-line-width-100-fits",
      profile: "4.x",
      mode: "strict",
      raw: b"select alpha, beta, gamma, delta, epsilon from t where id = 1",
      expected_valid: true,
      options: None,
      expected_golden: b"SELECT alpha, beta, gamma, delta, epsilon\nFROM t\nWHERE id = 1\n",
    },
    {
      fixture_id: "4.x-line-width-20-breaks",
      profile: "4.x",
      mode: "strict",
      raw: b"select alpha, beta, gamma, delta, epsilon from t where id = 1",
      expected_valid: true,
      options: Some(width20),
      expected_golden: b"SELECT\n  alpha,\n  beta,\n  gamma,\n  delta,\n  epsilon\nFROM t\nWHERE id = 1\n",
    },
    // (d) Leading comma style at the DEFAULT width: a long select list breaks
    // at width 100 and the comma opens each following item's line.
    {
      fixture_id: "4.x-leading-comma-default-width",
      profile: "4.x",
      mode: "strict",
      raw: b"select user_id, user_name, user_email, user_phone, user_address, user_status, user_created_at, user_updated_at, user_region, user_org, user_active from user_profile where user_status = 'active' group by user_id order by user_created_at",
      expected_valid: true,
      options: Some(leading),
      expected_golden: b"SELECT\n  user_id\n  , user_name\n  , user_email\n  , user_phone\n  , user_address\n  , user_status\n  , user_created_at\n  , user_updated_at\n  , user_region\n  , user_org\n  , user_active\nFROM user_profile\nWHERE user_status = 'active'\nGROUP BY user_id\nORDER BY user_created_at\n",
    },
    // (e) newline_style Lf override: a CRLF input emits \n only (override
    // beats FollowInput).
    {
      fixture_id: "4.x-newline-lf-override-crlf-input",
      profile: "4.x",
      mode: "strict",
      raw: b"select a\r\nfrom t",
      expected_valid: true,
      options: Some(lf_override),
      expected_golden: b"SELECT a\nFROM t\n",
    },
    // (f) newline_style Crlf override: an LF input emits \r\n only.
    {
      fixture_id: "4.x-newline-crlf-override-lf-input",
      profile: "4.x",
      mode: "strict",
      raw: b"select a\nfrom t",
      expected_valid: true,
      options: Some(crlf_override),
      expected_golden: b"SELECT a\r\nFROM t\r\n",
    },
    // (g) trailing_newline false: no trailing newline in the output, and the
    // output stays idempotent (format(format(x)) == format(x)).
    {
      fixture_id: "4.x-trailing-newline-off",
      profile: "4.x",
      mode: "strict",
      raw: b"select 1",
      expected_valid: true,
      options: Some(no_trailing),
      expected_golden: b"SELECT 1",
    },
    // (h) trailing_newline true (default): three trailing newlines collapse to
    // exactly one (normalize-to-exactly-one policy, D-32 / assumption A3).
    {
      fixture_id: "4.x-trailing-newline-normalize-on",
      profile: "4.x",
      mode: "strict",
      raw: b"select 1\n\n\n",
      expected_valid: true,
      options: None,
      expected_golden: b"SELECT 1\n",
    },
  ]
  for fixture in fixtures {
    assert_true(formatter_fixture_ok(fixture))
  }
}

///|
/// 03-03 Task 2: the FULL 44-row manifest mirror (D-34/D-35 corpus
/// contract, research Pattern 6 — the Phase 2 embedded fixture
/// convention, test/parser_test.mbt:463-505). One row per
/// corpus/manifest.tsv row: fixture_id and profile copied from the
/// manifest, mode per parse_mode, raw embedded from the matching
/// corpus/doris-{2.1,3.x,4.x}/*.sql file (provenance headers
/// stripped, matching corpus_test.mbt's embedded records) or from
/// the recorded inline bytes for rows without a disk file;
/// expected_valid per support_status. Goldens were authored by the
/// first formatter run and REVIEWED before commit (research
/// Pitfall 7 — never a blind `moon test --update`). Runtime never
/// loads disk (STATE.md). No CRLF rows exist in the manifest; the
/// \r\n byte-preservation contract is covered by the 4.x-crlf and
/// newline-override fixtures in this file.
///
/// Authoring deviation (probe-verified): the 4.x-industrial disk
/// body carries `TABLET (1001)` after the aliased subquery `AS d`;
/// the parser accepts TABLET only on unaliased table refs (probe:
/// `FROM t TABLET (1001)` valid, `FROM t AS d TABLET (1001)`
/// invalid with FATHOM-PARSE-001 trailing recovery), so the
/// embedded raw drops the TABLET clause to keep the manifest's
/// supported status and the D-35 zero-diagnostic reparse gate.
let formatter_corpus_fixtures : Array[FormatterFixture] = [
  {
    fixture_id: "2.1-boundary-empty",
    profile: "2.1",
    mode: "editor",
    raw: b"SELECT FROM t",
    expected_valid: false,
    options: None,
    expected_golden: b"",
  },
  {
    fixture_id: "2.1-boundary-single",
    profile: "2.1",
    mode: "strict",
    raw: b"SELECT 1",
    expected_valid: true,
    options: None,
    expected_golden: b"SELECT 1\n",
  },
  {
    fixture_id: "2.1-contextual-keyword",
    profile: "2.1",
    mode: "strict",
    raw: b"SELECT `group`, `window` FROM `table`",
    expected_valid: true,
    options: None,
    expected_golden: b"SELECT `group`, `window`\nFROM `table`\n",
  },
  {
    fixture_id: "2.1-create-index",
    profile: "2.1",
    mode: "strict",
    raw: b"CREATE INDEX index1 ON table1 (col1) USING INVERTED;\nCREATE INDEX idx ON db.table1 (col1, col2) USING INVERTED;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"CREATE INDEX index1 ON table1(col1) USING INVERTED;\nCREATE INDEX idx ON db.table1(col1, col2) USING INVERTED;\n",
  },
  {
    fixture_id: "2.1-create-table",
    profile: "2.1",
    mode: "strict",
    raw: b"CREATE TABLE example_table (k1 TINYINT, k2 DECIMAL(10, 2) DEFAULT \"10.5\", k3 CHAR(10) COMMENT \"string column\", v1 BIGINT SUM DEFAULT \"0\" COMMENT \"aggregate value\", INDEX idx_k1 (k1) USING BITMAP COMMENT \"index comment\") ENGINE=OLAP AGGREGATE KEY(k1) COMMENT \"my table\" DISTRIBUTED BY HASH(k1) BUCKETS 10 PROPERTIES (\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");\nCREATE TABLE t (k1 DATE, k2 INT) AUTO PARTITION BY RANGE (TO_DAYS(k1)) () DISTRIBUTED BY HASH (k2) BUCKETS 3;\nCREATE TABLE t2 (k1 INT) DISTRIBUTED BY HASH (k1) BUCKETS AUTO;\nCREATE TABLE t3 (k1 DATE) PARTITION BY RANGE (k1) (PARTITION p1 VALUES LESS THAN ('2021-01-01'), PARTITION p2 VALUES LESS THAN (MAXVALUE));\n",
    expected_valid: true,
    options: None,
    expected_golden: b"CREATE\nTABLE example_table(\n  k1 TINYINT,\n  k2 DECIMAL(10, 2) DEFAULT \"10.5\",\n  k3 CHAR(10)\n  COMMENT \"string column\",\n  v1 BIGINT SUM DEFAULT \"0\"\n  COMMENT \"aggregate value\",\n  INDEX idx_k1(k1) USING BITMAP\n  COMMENT \"index comment\"\n)\nENGINE=OLAP AGGREGATE\nKEY(k1)\nCOMMENT \"my table\"\nDISTRIBUTED BY HASH(k1) BUCKETS 10\nPROPERTIES(\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");\nCREATE\nTABLE t(k1 DATE, k2 INT) AUTO\nPARTITION BY RANGE(TO_DAYS(k1))()\nDISTRIBUTED BY HASH(k2) BUCKETS 3;\nCREATE\nTABLE t2(k1 INT)\nDISTRIBUTED BY HASH(k1) BUCKETS AUTO;\nCREATE\nTABLE t3(k1 DATE)\nPARTITION BY RANGE(k1)(PARTITION p1 VALUES LESS THAN('2021-01-01'), PARTITION p2 VALUES LESS THAN(MAXVALUE));\n",
  },
  {
    fixture_id: "2.1-create-view",
    profile: "2.1",
    mode: "strict",
    raw: b"CREATE VIEW v AS SELECT a, b FROM t;\nCREATE VIEW v (a, b) AS SELECT a, b FROM t;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"CREATE VIEW v\nAS\nSELECT a, b FROM t;\nCREATE VIEW v(a, b)\nAS\nSELECT a, b FROM t;\n",
  },
  {
    fixture_id: "2.1-delete",
    profile: "2.1",
    mode: "strict",
    raw: b"DELETE FROM t WHERE id = 1;\nDELETE FROM t WHERE id IN (1, 2, 3) AND name = 'a';\n",
    expected_valid: true,
    options: None,
    expected_golden: b"DELETE\nFROM t\nWHERE id = 1;\nDELETE\nFROM t\nWHERE id IN(1, 2, 3) AND name = 'a';\n",
  },
  {
    fixture_id: "2.1-industrial",
    profile: "2.1",
    mode: "strict",
    raw: b"SELECT DISTINCT k, SUM(v) AS total\nFROM fact PARTITION (p0) TABLESAMPLE (10)\nWHERE v BETWEEN 1 AND 9\nGROUP BY ROLLUP(k)\nHAVING SUM(v) > 0\nORDER BY total DESC\nLIMIT 10;\n\nSELECT a FROM left_table LEFT OUTER JOIN right_table ON left_table.k = right_table.k;\nSELECT a FROM first_table UNION ALL SELECT a FROM second_table;\nSELECT `group`, `window` FROM `table`;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"SELECT DISTINCT k, SUM(v) AS total\nFROM fact PARTITION(p0) TABLESAMPLE(10)\nWHERE v BETWEEN 1 AND 9\nGROUP BY ROLLUP(k)\nHAVING SUM(v) > 0\nORDER BY total DESC\nLIMIT 10;\nSELECT a\nFROM left_table LEFT OUTER\nJOIN right_table\nON left_table.k = right_table.k;\nSELECT a\nFROM first_table\nUNION ALL SELECT a\nFROM second_table;\nSELECT `group`, `window`\nFROM `table`;\n",
  },
  {
    fixture_id: "2.1-insert-select",
    profile: "2.1",
    mode: "strict",
    raw: b"INSERT INTO test SELECT * FROM test2;\nINSERT INTO test (c1, c2) SELECT * FROM test2;\nINSERT INTO test PARTITION(p1, p2) WITH LABEL `label1` SELECT * FROM test2;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"INSERT\nINTO test\nSELECT * FROM test2;\nINSERT\nINTO test(c1, c2)\nSELECT * FROM test2;\nINSERT\nINTO test\nPARTITION(p1, p2)\nWITH\nLABEL `label1`\nSELECT * FROM test2;\n",
  },
  {
    fixture_id: "2.1-insert-values",
    profile: "2.1",
    mode: "strict",
    raw: b"INSERT INTO test VALUES (1, 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT);\nINSERT INTO test VALUES (1, 2), (3, 2 + 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT), (3, DEFAULT);\n",
    expected_valid: true,
    options: None,
    expected_golden: b"INSERT\nINTO test\nVALUES(1, 2);\nINSERT\nINTO test(c1, c2)\nVALUES(1, DEFAULT);\nINSERT\nINTO test\nVALUES(1, 2),(3, 2 + 2);\nINSERT\nINTO test(c1, c2)\nVALUES(1, DEFAULT),(3, DEFAULT);\n",
  },
  {
    fixture_id: "2.1-invalid-encoding",
    profile: "2.1",
    mode: "editor",
    raw: b"SELECT \xff",
    expected_valid: false,
    options: None,
    expected_golden: b"",
  },
  {
    fixture_id: "2.1-merge",
    profile: "2.1",
    mode: "strict",
    raw: b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.v = s.v",
    expected_valid: false,
    options: None,
    expected_golden: b"",
  },
  {
    fixture_id: "2.1-update",
    profile: "2.1",
    mode: "strict",
    raw: b"UPDATE t1 SET c1 = 1 WHERE id = 1;\nUPDATE t1 SET c1 = 1, c2 = 2 WHERE id = 1 AND name = 'a';\nUPDATE t1 alias SET c1 = 1;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"UPDATE t1\nSET c1 = 1\nWHERE id = 1;\nUPDATE t1\nSET c1 = 1, c2 = 2\nWHERE id = 1 AND name = 'a';\nUPDATE t1 alias\nSET c1 = 1;\n",
  },
  {
    fixture_id: "3.x-boundary-set-many",
    profile: "3.x",
    mode: "strict",
    raw: b"SELECT 1 UNION SELECT 2 UNION ALL SELECT 3 UNION DISTINCT SELECT 4",
    expected_valid: true,
    options: None,
    expected_golden: b"SELECT 1\nUNION SELECT 2\nUNION ALL SELECT 3\nUNION DISTINCT SELECT 4\n",
  },
  {
    fixture_id: "3.x-boundary-set-one",
    profile: "3.x",
    mode: "strict",
    raw: b"SELECT k FROM t UNION SELECT k FROM t2",
    expected_valid: true,
    options: None,
    expected_golden: b"SELECT k\nFROM t\nUNION SELECT k\nFROM t2\n",
  },
  {
    fixture_id: "3.x-create-index",
    profile: "3.x",
    mode: "strict",
    raw: b"CREATE INDEX index1 ON table1 (col1) USING INVERTED;\nCREATE INDEX idx ON db.table1 (col1, col2) USING INVERTED;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"CREATE INDEX index1 ON table1(col1) USING INVERTED;\nCREATE INDEX idx ON db.table1(col1, col2) USING INVERTED;\n",
  },
  {
    fixture_id: "3.x-create-table",
    profile: "3.x",
    mode: "strict",
    raw: b"CREATE TABLE example_table (k1 TINYINT, k2 DECIMAL(10, 2) DEFAULT \"10.5\", k3 CHAR(10) COMMENT \"string column\", v1 BIGINT SUM DEFAULT \"0\" COMMENT \"aggregate value\", INDEX idx_k1 (k1) USING BITMAP COMMENT \"index comment\") ENGINE=OLAP AGGREGATE KEY(k1) COMMENT \"my table\" DISTRIBUTED BY HASH(k1) BUCKETS 10 PROPERTIES (\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");\nCREATE TABLE t (k1 DATE, k2 INT) AUTO PARTITION BY RANGE (TO_DAYS(k1)) () DISTRIBUTED BY HASH (k2) BUCKETS 3;\nCREATE TABLE t2 (k1 INT) DISTRIBUTED BY HASH (k1) BUCKETS AUTO;\nCREATE TABLE t3 (k1 DATE) PARTITION BY RANGE (k1) (PARTITION p1 VALUES LESS THAN ('2021-01-01'), PARTITION p2 VALUES LESS THAN (MAXVALUE));\n",
    expected_valid: true,
    options: None,
    expected_golden: b"CREATE\nTABLE example_table(\n  k1 TINYINT,\n  k2 DECIMAL(10, 2) DEFAULT \"10.5\",\n  k3 CHAR(10)\n  COMMENT \"string column\",\n  v1 BIGINT SUM DEFAULT \"0\"\n  COMMENT \"aggregate value\",\n  INDEX idx_k1(k1) USING BITMAP\n  COMMENT \"index comment\"\n)\nENGINE=OLAP AGGREGATE\nKEY(k1)\nCOMMENT \"my table\"\nDISTRIBUTED BY HASH(k1) BUCKETS 10\nPROPERTIES(\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");\nCREATE\nTABLE t(k1 DATE, k2 INT) AUTO\nPARTITION BY RANGE(TO_DAYS(k1))()\nDISTRIBUTED BY HASH(k2) BUCKETS 3;\nCREATE\nTABLE t2(k1 INT)\nDISTRIBUTED BY HASH(k1) BUCKETS AUTO;\nCREATE\nTABLE t3(k1 DATE)\nPARTITION BY RANGE(k1)(PARTITION p1 VALUES LESS THAN('2021-01-01'), PARTITION p2 VALUES LESS THAN(MAXVALUE));\n",
  },
  {
    fixture_id: "3.x-create-view",
    profile: "3.x",
    mode: "strict",
    raw: b"CREATE VIEW v AS SELECT a, b FROM t;\nCREATE VIEW v (a, b) AS SELECT a, b FROM t;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"CREATE VIEW v\nAS\nSELECT a, b FROM t;\nCREATE VIEW v(a, b)\nAS\nSELECT a, b FROM t;\n",
  },
  {
    fixture_id: "3.x-delete",
    profile: "3.x",
    mode: "strict",
    raw: b"DELETE FROM t WHERE id = 1;\nDELETE FROM t WHERE id IN (1, 2, 3) AND name = 'a';\n",
    expected_valid: true,
    options: None,
    expected_golden: b"DELETE\nFROM t\nWHERE id = 1;\nDELETE\nFROM t\nWHERE id IN(1, 2, 3) AND name = 'a';\n",
  },
  {
    fixture_id: "3.x-industrial",
    profile: "3.x",
    mode: "strict",
    raw: b"WITH recent AS (\n  SELECT k, SUM(v) OVER (PARTITION BY k ORDER BY ts ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling\n  FROM fact SAMPLE (10)\n  WHERE v IN (1, 2, 3)\n)\nSELECT k, rolling FROM recent QUALIFY rolling > 0 ORDER BY rolling DESC LIMIT 20;\n\nSELECT k FROM fact GROUP BY GROUPING SETS ((k), (k, region));\nSELECT k FROM left_table RIGHT JOIN right_table USING (k) UNION DISTINCT SELECT k FROM fallback_table;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"WITH recent AS(\n  SELECT k, SUM(v) OVER(PARTITION BY k\n  ORDER BY ts ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling\n  FROM fact SAMPLE(10)\n  WHERE v IN(1, 2, 3)) SELECT k, rolling\nFROM recent\nQUALIFY rolling > 0\nORDER BY rolling DESC\nLIMIT 20;\nSELECT k\nFROM fact\nGROUP BY GROUPING SETS((k),(k, region));\nSELECT k\nFROM left_table RIGHT\nJOIN right_table USING(k)\nUNION DISTINCT SELECT k\nFROM fallback_table;\n",
  },
  {
    fixture_id: "3.x-insert-select",
    profile: "3.x",
    mode: "strict",
    raw: b"INSERT INTO test SELECT * FROM test2;\nINSERT INTO test (c1, c2) SELECT * FROM test2;\nINSERT INTO test PARTITION(p1, p2) WITH LABEL `label1` SELECT * FROM test2;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"INSERT\nINTO test\nSELECT * FROM test2;\nINSERT\nINTO test(c1, c2)\nSELECT * FROM test2;\nINSERT\nINTO test\nPARTITION(p1, p2)\nWITH\nLABEL `label1`\nSELECT * FROM test2;\n",
  },
  {
    fixture_id: "3.x-insert-values",
    profile: "3.x",
    mode: "strict",
    raw: b"INSERT INTO test VALUES (1, 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT);\nINSERT INTO test VALUES (1, 2), (3, 2 + 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT), (3, DEFAULT);\n",
    expected_valid: true,
    options: None,
    expected_golden: b"INSERT\nINTO test\nVALUES(1, 2);\nINSERT\nINTO test(c1, c2)\nVALUES(1, DEFAULT);\nINSERT\nINTO test\nVALUES(1, 2),(3, 2 + 2);\nINSERT\nINTO test(c1, c2)\nVALUES(1, DEFAULT),(3, DEFAULT);\n",
  },
  {
    fixture_id: "3.x-merge",
    profile: "3.x",
    mode: "strict",
    raw: b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.v = s.v",
    expected_valid: false,
    options: None,
    expected_golden: b"",
  },
  {
    fixture_id: "3.x-recovery",
    profile: "3.x",
    mode: "editor",
    raw: b"SELECT k FROM t WHERE",
    expected_valid: false,
    options: None,
    expected_golden: b"",
  },
  {
    fixture_id: "3.x-unsupported-profile",
    profile: "2.1",
    mode: "strict",
    raw: b"SELECT k FROM t QUALIFY k > 0",
    expected_valid: false,
    options: None,
    expected_golden: b"",
  },
  {
    fixture_id: "3.x-update",
    profile: "3.x",
    mode: "strict",
    raw: b"UPDATE t1 SET c1 = 1 WHERE id = 1;\nUPDATE t1 SET c1 = 1, c2 = 2 WHERE id = 1 AND name = 'a';\nUPDATE t1 alias SET c1 = 1;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"UPDATE t1\nSET c1 = 1\nWHERE id = 1;\nUPDATE t1\nSET c1 = 1, c2 = 2\nWHERE id = 1 AND name = 'a';\nUPDATE t1 alias\nSET c1 = 1;\n",
  },
  {
    fixture_id: "4.x-boundary-set-two",
    profile: "4.x",
    mode: "strict",
    raw: b"SELECT 1 UNION SELECT 2; SELECT 3 UNION ALL SELECT 4",
    expected_valid: true,
    options: None,
    expected_golden: b"SELECT 1\nUNION SELECT 2;\nSELECT 3\nUNION ALL SELECT 4\n",
  },
  {
    fixture_id: "4.x-create-index",
    profile: "4.x",
    mode: "strict",
    raw: b"CREATE INDEX index1 ON table1 (col1) USING INVERTED;\nCREATE INDEX index2 ON table1 (col1) USING NGRAM_BF PROPERTIES (\"gram_size\" = \"3\", \"bf_size\" = \"1024\");\nCREATE INDEX IF NOT EXISTS idx ON t (c) COMMENT 'index comment';\nCREATE INDEX idx ON db.table1 (col1, col2) USING ANN PROPERTIES (\"index_type\" = \"hnsw\", \"metric_type\" = \"l2_distance\", \"dim\" = \"128\");\n",
    expected_valid: true,
    options: None,
    expected_golden: b"CREATE INDEX index1 ON table1(col1) USING INVERTED;\nCREATE INDEX index2 ON table1(col1) USING NGRAM_BF\nPROPERTIES(\"gram_size\" = \"3\", \"bf_size\" = \"1024\");\nCREATE INDEX IF NOT EXISTS idx ON t(c)\nCOMMENT 'index comment';\nCREATE INDEX idx ON db.table1(col1, col2) USING ANN\nPROPERTIES(\"index_type\" = \"hnsw\", \"metric_type\" = \"l2_distance\", \"dim\" = \"128\");\n",
  },
  {
    fixture_id: "4.x-create-materialized-view",
    profile: "4.x",
    mode: "strict",
    raw: b"CREATE MATERIALIZED VIEW mv AS SELECT k, SUM(v) FROM t GROUP BY k;\nCREATE MATERIALIZED VIEW complete_mv (orderkey COMMENT 'Order key') BUILD IMMEDIATE REFRESH AUTO ON SCHEDULE EVERY 1 DAY STARTS '2099-01-01 20:30:00' DISTRIBUTED BY HASH (orderkey) BUCKETS 2 PROPERTIES (\"replication_num\" = \"1\") AS SELECT o_orderkey, l_orderkey FROM orders LEFT JOIN lineitem ON l_orderkey = o_orderkey;\nCREATE MATERIALIZED VIEW IF NOT EXISTS mv2 BUILD DEFERRED REFRESH COMPLETE ON MANUAL AS SELECT 1;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"CREATE MATERIALIZED VIEW mv\nAS\nSELECT k, SUM(v) FROM t GROUP BY k;\nCREATE MATERIALIZED VIEW complete_mv(orderkey COMMENT 'Order key') BUILD IMMEDIATE REFRESH AUTO ON SCHEDULE EVERY 1 DAY STARTS '2099-01-01 20:30:00'\nDISTRIBUTED BY HASH(orderkey) BUCKETS 2\nPROPERTIES(\"replication_num\" = \"1\")\nAS\nSELECT o_orderkey, l_orderkey FROM orders LEFT JOIN lineitem ON l_orderkey = o_orderkey;\nCREATE MATERIALIZED VIEW IF NOT EXISTS mv2 BUILD DEFERRED REFRESH COMPLETE ON MANUAL\nAS\nSELECT 1;\n",
  },
  {
    fixture_id: "4.x-create-table",
    profile: "4.x",
    mode: "strict",
    raw: b"CREATE TABLE example_table (k1 TINYINT, k2 DECIMAL(10, 2) DEFAULT \"10.5\", k3 CHAR(10) COMMENT \"string column\", k4 INT NOT NULL DEFAULT \"1\" COMMENT \"int column\", v1 BIGINT SUM DEFAULT \"0\" COMMENT \"aggregate value\", INDEX idx_k1 (k1) USING BITMAP COMMENT \"index comment\") ENGINE=OLAP UNIQUE KEY(k1, k2) ORDER BY(k1) COMMENT \"my table\" PARTITION BY RANGE(k1) (PARTITION p1 VALUES LESS THAN (\"2021-01-01\"), PARTITION p2 VALUES LESS THAN (\"2022-01-01\")) DISTRIBUTED BY HASH(k1) BUCKETS 32 ROLLUP (r1 (k1) DUPLICATE KEY (k1)) PROPERTIES (\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");\nCREATE TEMPORARY TABLE t (a INT);\nCREATE TABLE t2 (k1 INT) DISTRIBUTED BY HASH (k1) BUCKETS AUTO;\nCREATE TABLE t3 (k1 DATE, k2 INT) AUTO PARTITION BY RANGE (TO_DAYS(k1)) () DISTRIBUTED BY HASH (k2) BUCKETS 3;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"CREATE\nTABLE example_table(\n  k1 TINYINT,\n  k2 DECIMAL(10, 2) DEFAULT \"10.5\",\n  k3 CHAR(10)\n  COMMENT \"string column\",\n  k4 INT NOT NULL DEFAULT \"1\"\n  COMMENT \"int column\",\n  v1 BIGINT SUM DEFAULT \"0\"\n  COMMENT \"aggregate value\",\n  INDEX idx_k1(k1) USING BITMAP\n  COMMENT \"index comment\"\n)\nENGINE=OLAP UNIQUE\nKEY(k1, k2)\nORDER BY(k1)\nCOMMENT \"my table\"\nPARTITION BY RANGE(k1)(PARTITION p1 VALUES LESS THAN(\"2021-01-01\"), PARTITION p2 VALUES LESS THAN(\"2022-01-01\"))\nDISTRIBUTED BY HASH(k1) BUCKETS 32\nROLLUP(r1(k1) DUPLICATE KEY(k1))\nPROPERTIES(\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");\nCREATE TEMPORARY\nTABLE t(a INT);\nCREATE\nTABLE t2(k1 INT)\nDISTRIBUTED BY HASH(k1) BUCKETS AUTO;\nCREATE\nTABLE t3(k1 DATE, k2 INT) AUTO\nPARTITION BY RANGE(TO_DAYS(k1))()\nDISTRIBUTED BY HASH(k2) BUCKETS 3;\n",
  },
  {
    fixture_id: "4.x-create-table-ctas",
    profile: "4.x",
    mode: "strict",
    raw: b"CREATE TABLE t AS SELECT a, b FROM src;\nCREATE TABLE t (a INT) DISTRIBUTED BY HASH (a) BUCKETS 10 AS SELECT a FROM src;\nCREATE TABLE t (a INT, INDEX idx (a)) ENGINE=OLAP COMMENT \"ctas\" AS SELECT a FROM src;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"CREATE\nTABLE t\nAS\nSELECT a, b FROM src;\nCREATE\nTABLE t(a INT)\nDISTRIBUTED BY HASH(a) BUCKETS 10\nAS\nSELECT a FROM src;\nCREATE\nTABLE t(a INT, INDEX idx(a))\nENGINE=OLAP\nCOMMENT \"ctas\"\nAS\nSELECT a FROM src;\n",
  },
  {
    fixture_id: "4.x-create-table-like",
    profile: "4.x",
    mode: "strict",
    raw: b"CREATE TABLE new_t LIKE existing_t;\nCREATE TABLE new_t LIKE existing_t WITH ROLLUP (r1, r2);\nCREATE TABLE db.new_t LIKE db.existing_t;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"CREATE\nTABLE new_t\nLIKE existing_t;\nCREATE\nTABLE new_t\nLIKE existing_t WITH\nROLLUP(r1, r2);\nCREATE\nTABLE db.new_t\nLIKE db.existing_t;\n",
  },
  {
    fixture_id: "4.x-create-view",
    profile: "4.x",
    mode: "strict",
    raw: b"CREATE VIEW v AS SELECT a, b FROM t;\nCREATE VIEW IF NOT EXISTS db.v (a COMMENT 'col a') AS SELECT x AS a FROM t;\nCREATE VIEW v AS WITH cte AS (SELECT 1) SELECT * FROM cte;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"CREATE VIEW v\nAS\nSELECT a, b FROM t;\nCREATE VIEW IF NOT EXISTS db.v(a COMMENT 'col a')\nAS\nSELECT x\nAS a FROM t;\nCREATE VIEW v\nAS WITH cte\nAS(\n  SELECT 1)\nSELECT * FROM cte;\n",
  },
  {
    fixture_id: "4.x-delete",
    profile: "4.x",
    mode: "strict",
    raw: b"DELETE FROM t WHERE id = 1;\nDELETE FROM t PARTITION p1 WHERE id = 1 AND name = 'a';\nDELETE FROM t PARTITIONS (p1, p2) WHERE id IN (1, 2, 3);\nDELETE FROM t WHERE id = 1 ORDER BY id LIMIT 10;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"DELETE\nFROM t\nWHERE id = 1;\nDELETE\nFROM t\nPARTITION p1\nWHERE id = 1 AND name = 'a';\nDELETE\nFROM t\nPARTITIONS(p1, p2)\nWHERE id IN(1, 2, 3);\nDELETE\nFROM t\nWHERE id = 1\nORDER BY id\nLIMIT 10;\n",
  },
  {
    fixture_id: "4.x-industrial",
    profile: "4.x",
    mode: "strict",
    raw: b"SELECT /*+ SET_VAR(exec_mem_limit=1G) */\n  d.k, COUNT(*) AS n,\n  SUM(d.v) OVER (PARTITION BY d.k ORDER BY d.ts RANGE BETWEEN 1 PRECEDING AND CURRENT ROW) AS running\nFROM (SELECT k, v, ts FROM detail WHERE v IS NOT NULL) AS d\nGROUP BY CUBE(d.k)\nHAVING COUNT(*) > 1\nORDER BY n DESC\nLIMIT 5 OFFSET 2\nINTO OUTFILE 'result.csv';\n\nSELECT k FROM t1 UNION SELECT k FROM t2 UNION ALL SELECT k FROM t3;",
    expected_valid: true,
    options: None,
    expected_golden: b"SELECT\n  /*+ SET_VAR(exec_mem_limit=1G) */ d.k,\n  COUNT(*) AS n,\n  SUM(d.v) OVER(PARTITION BY d.k\n  ORDER BY d.ts RANGE BETWEEN 1 PRECEDING AND CURRENT ROW) AS running\nFROM(\n  SELECT k, v, ts\n  FROM detail\n  WHERE v IS NOT NULL) AS d\nGROUP BY CUBE(d.k)\nHAVING COUNT(*) > 1\nORDER BY n DESC\nLIMIT 5 OFFSET 2\nINTO OUTFILE 'result.csv';\nSELECT k\nFROM t1\nUNION SELECT k\nFROM t2\nUNION ALL SELECT k\nFROM t3;\n",
  },
  {
    fixture_id: "4.x-insert-overwrite",
    profile: "4.x",
    mode: "strict",
    raw: b"INSERT OVERWRITE table test VALUES (1, 2);\nINSERT OVERWRITE table test PARTITION (p1, p2) SELECT * FROM test2;\nINSERT OVERWRITE table test PARTITION (*) SELECT * FROM test2;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"INSERT OVERWRITE TABLE test\nVALUES(1, 2);\nINSERT OVERWRITE TABLE test\nPARTITION(p1, p2)\nSELECT * FROM test2;\nINSERT OVERWRITE TABLE test\nPARTITION(*)\nSELECT * FROM test2;\n",
  },
  {
    fixture_id: "4.x-insert-select",
    profile: "4.x",
    mode: "strict",
    raw: b"INSERT INTO test SELECT * FROM test2;\nINSERT INTO test (c1, c2) SELECT * FROM test2;\nINSERT INTO test PARTITION(p1, p2) WITH LABEL `label1` SELECT * FROM test2;\nINSERT INTO db.test (c1) SELECT c1 FROM test2;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"INSERT\nINTO test\nSELECT * FROM test2;\nINSERT\nINTO test(c1, c2)\nSELECT * FROM test2;\nINSERT\nINTO test\nPARTITION(p1, p2)\nWITH\nLABEL `label1`\nSELECT * FROM test2;\nINSERT\nINTO db.test(c1)\nSELECT c1 FROM test2;\n",
  },
  {
    fixture_id: "4.x-insert-values",
    profile: "4.x",
    mode: "strict",
    raw: b"INSERT INTO test VALUES (1, 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT);\nINSERT INTO test VALUES (1, 2), (3, 2 + 2);\nINSERT INTO test (c1, c2) VALUES (1, DEFAULT), (3, DEFAULT);\nINSERT INTO test /*+ STREAMING */ VALUES (1, 2);\n",
    expected_valid: true,
    options: None,
    expected_golden: b"INSERT\nINTO test\nVALUES(1, 2);\nINSERT\nINTO test(c1, c2)\nVALUES(1, DEFAULT);\nINSERT\nINTO test\nVALUES(1, 2),(3, 2 + 2);\nINSERT\nINTO test(c1, c2)\nVALUES(1, DEFAULT),(3, DEFAULT);\nINSERT\nINTO test /*+ STREAMING */\nVALUES(1, 2);\n",
  },
  {
    fixture_id: "4.x-invalid-encoding",
    profile: "4.x",
    mode: "editor",
    raw: b"SELECT \xff",
    expected_valid: false,
    options: None,
    expected_golden: b"",
  },
  {
    fixture_id: "4.x-malformed-recovery",
    profile: "4.x",
    mode: "editor",
    raw: b"UPDATE t SET x = 1 WHERE;\nINSERT INTO t VALUES (1;\n",
    expected_valid: false,
    options: None,
    expected_golden: b"",
  },
  {
    fixture_id: "4.x-merge",
    profile: "4.x",
    mode: "strict",
    raw: b"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.v = s.v;\nMERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN DELETE;\nMERGE INTO t USING s ON t.id = s.id WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.v);\nMERGE INTO t USING s ON t.id = s.id WHEN MATCHED AND t.v < s.v THEN UPDATE SET t.v = s.v WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.v);\n",
    expected_valid: true,
    options: None,
    expected_golden: b"MERGE\nINTO t\nUSING s\nON t.id = s.id\nWHEN MATCHED\nTHEN\nUPDATE\nSET t.v = s.v;\nMERGE\nINTO t\nUSING s\nON t.id = s.id\nWHEN MATCHED\nTHEN\nDELETE;\nMERGE\nINTO t\nUSING s\nON t.id = s.id\nWHEN NOT MATCHED\nTHEN\nINSERT\nVALUES(s.id, s.v);\nMERGE\nINTO t\nUSING s\nON t.id = s.id\nWHEN MATCHED\nAND t.v < s.v\nTHEN\nUPDATE\nSET t.v = s.v\nWHEN NOT MATCHED\nTHEN\nINSERT\nVALUES(s.id, s.v);\n",
  },
  {
    fixture_id: "4.x-recovery",
    profile: "4.x",
    mode: "editor",
    raw: b"SELECT k +",
    expected_valid: false,
    options: None,
    expected_golden: b"",
  },
  {
    fixture_id: "4.x-script-multi-statement",
    profile: "4.x",
    mode: "strict",
    raw: b"CREATE TABLE t (a INT); INSERT INTO t VALUES (1); SELECT * FROM t;\nINSERT INTO t VALUES (2); SELECT b;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"CREATE\nTABLE t(a INT);\nINSERT\nINTO t\nVALUES(1);\nSELECT *\nFROM t;\nINSERT\nINTO t\nVALUES(2);\nSELECT b;\n",
  },
  {
    fixture_id: "4.x-update",
    profile: "4.x",
    mode: "strict",
    raw: b"UPDATE t1 SET c1 = 1 WHERE id = 1;\nUPDATE t1 SET c1 = 1, c2 = DEFAULT WHERE id = 1;\nUPDATE t1 SET t1.c1 = t2.c1 FROM t2 INNER JOIN t3 ON t2.id = t3.id WHERE t1.id = t2.id;\nUPDATE t1 SET c1 = c1 + 1 ORDER BY c1 DESC NULLS LAST LIMIT 10;\n",
    expected_valid: true,
    options: None,
    expected_golden: b"UPDATE t1\nSET c1 = 1\nWHERE id = 1;\nUPDATE t1\nSET c1 = 1, c2 = DEFAULT\nWHERE id = 1;\nUPDATE t1\nSET t1.c1 = t2.c1\nFROM t2 INNER\nJOIN t3\nON t2.id = t3.id\nWHERE t1.id = t2.id;\nUPDATE t1\nSET c1 = c1 + 1\nORDER BY c1 DESC NULLS LAST\nLIMIT 10;\n",
  },
]

///|
/// Oracle per row: accepted fixtures hit the reviewed golden
/// byte-exact, stay idempotent format(format(x)) == format(x)
/// (D-34), reparse with zero diagnostics (D-35), and keep every
/// statement offset inside the output; expected_error and
/// version-negative rows refuse with empty output and a
/// FATHOM-FORMAT-001 diagnostic (the malformed half of D-34 is a
/// refusal assertion, research Pitfall 6 — never a skipped test).
fn formatter_corpus_fixture_check(fixture : FormatterFixture) -> String {
  let options = match fixture.options {
    Some(opts) => opts
    None => @formatter.FormatOptions::default()
  }
  let formatted = match
    @api.format_with_ids(
      fixture.raw,
      "doris",
      fixture.profile,
      fixture.mode,
      options,
    ) {
    Ok(result) => result
    Err(_) => return fixture.fixture_id + ": api Err"
  }
  if fixture.expected_valid {
    if !formatted.accepted {
      return fixture.fixture_id + ": refused but expected accepted"
    }
    if formatted.output != fixture.expected_golden {
      return fixture.fixture_id + ": output != golden"
    }
    for offset in formatted.statement_offsets {
      if offset < 0 || offset > formatted.output.length() {
        return fixture.fixture_id + ": statement offset out of bounds"
      }
    }
    let again = match
      @api.format_with_ids(
        formatted.output,
        "doris",
        fixture.profile,
        fixture.mode,
        options,
      ) {
      Ok(result) => result
      Err(_) => return fixture.fixture_id + ": idempotence api Err"
    }
    if again.output != formatted.output {
      return fixture.fixture_id + ": not idempotent"
    }
    let reparsed = match
      @api.parse_with_ids(
        formatted.output,
        "doris",
        fixture.profile,
        fixture.mode,
      ) {
      Ok(result) => result
      Err(_) => return fixture.fixture_id + ": reparse api Err"
    }
    if !reparsed.valid || reparsed.diagnostics.length() != 0 {
      return fixture.fixture_id + ": reparse not clean"
    }
    ""
  } else {
    if formatted.accepted || formatted.output.length() != 0 {
      return fixture.fixture_id +
        ": expected refusal but accepted or emitted output"
    }
    let mut found = false
    for diagnostic in formatted.diagnostics {
      if diagnostic.code == "FATHOM-FORMAT-001" {
        found = true
      }
    }
    if !found {
      return fixture.fixture_id + ": no FATHOM-FORMAT-001 refusal"
    }
    ""
  }
}

///|
test "formatter_corpus_44_row_harness" {
  assert_eq(formatter_corpus_fixtures.length(), 44)
  let mut failures = ""
  for i in 0..<formatter_corpus_fixtures.length() {
    let message = formatter_corpus_fixture_check(formatter_corpus_fixtures[i])
    if message.length() > 0 {
      failures = failures + message + "\n"
    }
  }
  assert_eq(failures, "")
}

///|
/// 03-03 Task 3: the FMT-03 contract is closed with the option-matrix
/// idempotence + determinism suite (D-34 across configurations), the
/// never-panic boundary suite (threat T-03-16/T-03-18), and the
/// refusal-diagnostic shape gate. The option sets below are the supported
/// values only — invalid values are rejected at construction (ASVS V5,
/// formatter_options_default_and_validation) and never looped here.
fn formatter_matrix_check(
  label : String,
  raw : Bytes,
  options : @formatter.FormatOptions,
  profile : String,
) -> String {
  let first = match
    @api.format_with_ids(raw, "doris", profile, "strict", options) {
    Ok(result) => result
    Err(_) => return label + ": format api Err"
  }
  let again = match
    @api.format_with_ids(first.output, "doris", profile, "strict", options) {
    Ok(result) => result
    Err(_) => return label + ": idempotence api Err"
  }
  if again.output != first.output {
    return label + ": not idempotent"
  }
  // Determinism (probe FMT-01 backstop): a second run from the original raw
  // must be byte-identical to the first.
  let second = match
    @api.format_with_ids(raw, "doris", profile, "strict", options) {
    Ok(result) => result
    Err(_) => return label + ": determinism api Err"
  }
  if second.output != first.output {
    return label + ": not deterministic"
  }
  ""
}

///|
fn matrix_combo_name(
  kc : @formatter.KeywordCase,
  cs : @formatter.CommaStyle,
  ns : @formatter.NewlineStyle,
  tn : Bool,
  indent : Int,
  width : Int,
) -> String {
  let kc_name = match kc {
    @formatter.KeywordCase::Upper => "Upper"
    @formatter.KeywordCase::Lower => "Lower"
  }
  let cs_name = match cs {
    @formatter.CommaStyle::Trailing => "Trailing"
    @formatter.CommaStyle::Leading => "Leading"
  }
  let ns_name = match ns {
    @formatter.NewlineStyle::FollowInput => "FollowInput"
    @formatter.NewlineStyle::Lf => "Lf"
    @formatter.NewlineStyle::Crlf => "Crlf"
  }
  kc_name +
  "/" +
  cs_name +
  "/" +
  ns_name +
  "/trailing=" +
  tn.to_string() +
  "/indent=" +
  indent.to_string() +
  "/width=" +
  width.to_string()
}

///|
test "formatter_03_03_option_matrix_idempotence_and_determinism" {
  let keyword_cases = [
    @formatter.KeywordCase::Upper,
    @formatter.KeywordCase::Lower,
  ]
  let comma_styles = [
    @formatter.CommaStyle::Trailing,
    @formatter.CommaStyle::Leading,
  ]
  let newline_styles = [
    @formatter.NewlineStyle::FollowInput,
    @formatter.NewlineStyle::Lf,
    @formatter.NewlineStyle::Crlf,
  ]
  let trailing_newlines = [true, false]
  let indents = [2, 4]
  let line_widths = [100, 40]
  // Representative SELECT (breaks at width 40, fits at 100) and one DDL
  // fixture: both must be byte-exact idempotent under every combination.
  let select_raw = b"select user_id, user_name, user_email, user_phone, user_address, user_status, user_created_at, user_updated_at from user_profile where user_status = 'active' group by user_id order by user_created_at"
  let ddl_raw = b"create table t (k1 int, k2 decimal(10, 2) default \"10.5\", k3 char(10) comment \"string column\", v1 bigint sum default \"0\" comment \"aggregate value\") engine=olap unique key(k1) comment \"my table\" distributed by hash(k1) buckets 10 properties (\"replication_num\" = \"1\", \"storage_medium\" = \"SSD\");"
  let mut failures = ""
  for kc in keyword_cases {
    for cs in comma_styles {
      for ns in newline_styles {
        for tn in trailing_newlines {
          for indent in indents {
            for width in line_widths {
              let options = match
                @formatter.FormatOptions::new(kc, indent, width, cs, ns, tn) {
                Ok(opts) => opts
                Err(_) => panic()
              }
              let combo = matrix_combo_name(kc, cs, ns, tn, indent, width)
              let select_failure = formatter_matrix_check(
                "select", select_raw, options, "4.x",
              )
              if select_failure.length() > 0 {
                failures = failures + combo + "/" + select_failure + "\n"
              }
              let ddl_failure = formatter_matrix_check(
                "ddl", ddl_raw, options, "4.x",
              )
              if ddl_failure.length() > 0 {
                failures = failures + combo + "/" + ddl_failure + "\n"
              }
            }
          }
        }
      }
    }
  }
  assert_eq(failures, "")
}

///|
/// Never-panic boundary suite (threat T-03-16/T-03-18, research Pitfall 4):
/// empty, whitespace-only, and comment-only documents format without panic
/// and without fabricated statements; the max_bytes boundary propagates
/// InputTooLarge as a ParseError, never a crash; and every corpus fixture
/// plus the boundary inputs format without panic.
test "formatter_03_03_never_panic_boundary_suite" {
  let options = @formatter.FormatOptions::default()
  // Empty document: accepted, empty output, no diagnostics, no offsets.
  let empty = match
    @api.format_with_ids(b"", "doris", "4.x", "strict", options) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(empty.accepted)
  assert_eq(empty.output.length(), 0)
  assert_eq(empty.diagnostics.length(), 0)
  assert_eq(empty.statement_offsets.length(), 0)
  // Whitespace-only: same shape, nothing fabricated.
  let ws = match
    @api.format_with_ids(b"   \n", "doris", "4.x", "strict", options) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(ws.accepted)
  assert_eq(ws.output.length(), 0)
  assert_eq(ws.statement_offsets.length(), 0)
  // Comment-only document: the comment is preserved verbatim, no fabricated
  // statements, and the trailing-newline policy applies (on -> exactly one).
  let comment = match
    @api.format_with_ids(
      b"-- only a comment", "doris", "4.x", "strict", options,
    ) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(comment.accepted)
  assert_eq(comment.output, b"-- only a comment\n")
  assert_eq(comment.diagnostics.length(), 0)
  assert_eq(comment.statement_offsets.length(), 0)
  // trailing-newline off on a comment-only document: no trailing newline.
  let no_trailing = match
    @formatter.FormatOptions::new(
      @formatter.KeywordCase::Upper,
      2,
      100,
      @formatter.CommaStyle::Trailing,
      @formatter.NewlineStyle::FollowInput,
      false,
    ) {
    Ok(opts) => opts
    Err(_) => panic()
  }
  let comment_nt = match
    @api.format_with_ids(
      b"-- only a comment", "doris", "4.x", "strict", no_trailing,
    ) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(comment_nt.accepted)
  assert_eq(comment_nt.output, b"-- only a comment")
  // max_bytes boundary: the input is rejected before parsing with a
  // structured InputTooLarge ParseError — never a panic or partial output.
  let tight = @api.ParseOptions::for_profile_with_limits(
    @dialect.DorisProfile::V4_X,
    @api.ParseMode::Strict,
    @api.ParseLimits::new(8, 1000, 8, 8, 8),
  )
  let too_large = @api.format_text(
    b"SELECT abcdefghijklmnopqrstuvwxyz", tight, options,
  )
  assert_true(
    too_large
    is Err(@api.ParseError::InputTooLarge(requested_bytes=_, max_bytes=8)),
  )
  // Never-panic backstop: every corpus fixture (supported AND error rows)
  // and every boundary input formats without crashing. The oracle already
  // asserts the results; this loop is the explicit no-crash assertion.
  for i in 0..<formatter_corpus_fixtures.length() {
    let fixture = formatter_corpus_fixtures[i]
    let _ = match
      @api.format_with_ids(
        fixture.raw,
        "doris",
        fixture.profile,
        fixture.mode,
        options,
      ) {
      Ok(result) => result
      Err(_) => panic()
    }
  }
  let boundary_inputs = [
    b"", b"   \n", b"-- only a comment", b"/* block only */",
  ]
  for i in 0..<boundary_inputs.length() {
    let _ = match
      @api.format_with_ids(
        boundary_inputs[i],
        "doris",
        "4.x",
        "strict",
        options,
      ) {
      Ok(result) => result
      Err(_) => panic()
    }
  }
}

///|
/// Refusal-diagnostic shape gate: every FATHOM-FORMAT- diagnostic on the
/// error half of the corpus is well-formed — "error" severity, expected_class
/// "format", valid span ordering, and a statement_id.
test "formatter_03_03_refusal_diagnostics_are_well_formed" {
  for i in 0..<formatter_corpus_fixtures.length() {
    let fixture = formatter_corpus_fixtures[i]
    if fixture.expected_valid {
      continue
    }
    let options = match fixture.options {
      Some(opts) => opts
      None => @formatter.FormatOptions::default()
    }
    let result = match
      @api.format_with_ids(
        fixture.raw,
        "doris",
        fixture.profile,
        fixture.mode,
        options,
      ) {
      Ok(result) => result
      Err(_) => panic()
    }
    assert_true(!result.accepted)
    let mut format_found = false
    for diagnostic in result.diagnostics {
      if diagnostic.code.has_prefix("FATHOM-FORMAT-") {
        format_found = true
        assert_eq(diagnostic.severity, "error")
        assert_eq(diagnostic.expected_class, "format")
        assert_true(diagnostic.start_byte <= diagnostic.end_byte)
        assert_true(diagnostic.message.length() > 0)
      }
    }
    assert_true(format_found)
  }
}

///|
/// DIALECT-03 / Pitfall 6: the format path is dialect-aware end-to-end.
/// (a) A flink selection is accepted only for the pinned release profiles; the
/// not-implemented tree is refused with FATHOM-FORMAT-001 (never partial
/// bytes, never a Doris-policy output for a flink request — T-09-10); an
/// unknown flink profile rejects with UnknownProfile BEFORE any formatting
/// runs. (b) The refusal diagnostic on malformed input carries the neutral
/// FATHOM-FORMAT-001 code.
test "formatter_dialect_selection_is_validated_first" {
  // (a) flink-2.3.0 is a valid Phase 11 selection: a valid Flink SELECT
  // parses through the real grammar and formats (accepted=true) —
  // FATHOM-PARSE-008 is retired (D-06), so the not-implemented refusal is
  // gone. An unknown flink profile (the Doris-shaped "2.1") is rejected by
  // the api entry before any work.
  let flink = match
    @api.format_with_ids(
      b"select 1",
      "flink",
      "flink-2.3.0",
      "strict",
      @formatter.FormatOptions::default(),
    ) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(flink.accepted)
  assert_true(flink.output.length() > 0)
  assert_eq(flink.diagnostics.length(), 0)
  let flink_unknown = @api.format_with_ids(
    b"select 1",
    "flink",
    "2.1",
    "strict",
    @formatter.FormatOptions::default(),
  )
  assert_true(
    flink_unknown is Err(@api.ParseError::UnknownProfile(profile_id="2.1")),
  )
  // Unknown dialect: structured UnknownDialect, never a Doris fallback.
  let unknown = @api.format_with_ids(
    b"select 1",
    "mysql",
    "4.x",
    "strict",
    @formatter.FormatOptions::default(),
  )
  assert_true(
    unknown is Err(@api.ParseError::UnknownDialect(dialect_id="mysql")),
  )
  // (b) A refusal on malformed input carries exactly one FATHOM-FORMAT-001
  // and the parse diagnostics are prepended, never masked (T-03-01).
  let refused = match
    @api.format_with_ids(
      b"select (",
      "doris",
      "4.x",
      "strict",
      @formatter.FormatOptions::default(),
    ) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(!refused.accepted)
  assert_eq(refused.output.length(), 0)
  assert_eq(
    refused.diagnostics[refused.diagnostics.length() - 1].code,
    "FATHOM-FORMAT-001",
  )
  // Doris formatting output is unchanged by the dialect dimension: the corpus
  // harness above asserts byte-exact goldens and idempotence under "doris".
}
