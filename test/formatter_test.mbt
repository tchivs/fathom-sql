/// Formatter tracer tests (plan 03-01): embedded fixtures mirroring the Phase 2
/// EmbeddedManifestFixture convention (test/parser_test.mbt:463-505). Runtime
/// tests never load the disk — raw bytes and goldens are embedded (STATE.md).
///
/// Contracts under test:
/// - byte-exact idempotence format(format(x)) == format(x) (D-34, Pitfall 6:
///   full Bytes equality, no trimming);
/// - zero-diagnostic reparse of accepted output (D-35);
/// - absolute refusal with DORIS-FORMAT-001 on error trees (D-33);
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

fn formatter_fixture_ok(fixture : FormatterFixture) -> Bool {
  let options = match fixture.options {
    Some(opts) => opts
    None => @formatter.FormatOptions::default()
  }
  let formatted = match @api.format_with_ids(fixture.raw, fixture.profile, fixture.mode, options) {
    Ok(result) => result
    Err(_) => return false
  }
  if fixture.expected_valid {
    if !formatted.accepted || formatted.output != fixture.expected_golden {
      return false
    }
    // D-34: idempotence — formatting the formatted output is byte-identical.
    let again = match @api.format_with_ids(formatted.output, fixture.profile, fixture.mode, options) {
      Ok(result) => result
      Err(_) => return false
    }
    if again.output != formatted.output {
      return false
    }
    // D-35: the formatted output reparses cleanly with zero diagnostics.
    let reparsed = match @api.parse_with_ids(formatted.output, fixture.profile, fixture.mode) {
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
      if diagnostic.code.has_prefix("DORIS-FORMAT-") {
        found = true
      }
    }
    found
  }
}

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
    // Version-invalid 2.1 MERGE (SourceError leaf): refusal with DORIS-FORMAT-001.
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
  assert_true(bad_indent is Err(@formatter.FormatError::InvalidIndent(value=-1)))
  let bad_width = @formatter.FormatOptions::new(
    @formatter.KeywordCase::Upper,
    2,
    0,
    @formatter.CommaStyle::Trailing,
    @formatter.NewlineStyle::FollowInput,
    true,
  )
  assert_true(bad_width is Err(@formatter.FormatError::InvalidLineWidth(value=0)))
}

test "formatter_refusal_never_masks_parse_diagnostics" {
  // Threat T-03-01: format_text converts DORIS-PARSE-* diagnostics and
  // prepends them so DORIS-FORMAT-001 never masks parse errors.
  let raw = b"MERGE INTO t USING s ON a=b WHEN MATCHED THEN UPDATE SET x=1"
  let options = @formatter.FormatOptions::default()
  let parse_options = match @api.ParseOptions::new("2.1", "strict") {
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
  assert_true(result.diagnostics[0].code.has_prefix("DORIS-PARSE-"))
  assert_true(result.diagnostics[0].code == "DORIS-PARSE-006")
  // Exactly one DORIS-FORMAT-001, and it comes after the parse diagnostics.
  let mut format_count = 0
  for diagnostic in result.diagnostics {
    if diagnostic.code == "DORIS-FORMAT-001" {
      format_count = format_count + 1
    }
  }
  assert_eq(format_count, 1)
  assert_eq(result.diagnostics[result.diagnostics.length() - 1].code, "DORIS-FORMAT-001")
  // The diagnostic shape mirrors PrimitiveDiagnostic fields.
  let refusal = result.diagnostics[result.diagnostics.length() - 1]
  assert_eq(refusal.severity, "error")
  assert_eq(refusal.expected_class, "format")
  assert_true(refusal.start_byte <= refusal.end_byte)
  assert_eq(refusal.statement_id, 0U)
}

test "formatter_from_id_maps_cli_string_ids" {
  // The CLI flag surface (03-04) maps string values with these helpers.
  assert_true(@formatter.KeywordCase::from_id("upper") is Some(@formatter.KeywordCase::Upper))
  assert_true(@formatter.KeywordCase::from_id("lower") is Some(@formatter.KeywordCase::Lower))
  assert_true(@formatter.KeywordCase::from_id("mixed") is None)
  assert_true(@formatter.CommaStyle::from_id("trailing") is Some(@formatter.CommaStyle::Trailing))
  assert_true(@formatter.CommaStyle::from_id("leading") is Some(@formatter.CommaStyle::Leading))
  assert_true(@formatter.CommaStyle::from_id("none") is None)
  assert_true(@formatter.NewlineStyle::from_id("follow") is Some(@formatter.NewlineStyle::FollowInput))
  assert_true(@formatter.NewlineStyle::from_id("lf") is Some(@formatter.NewlineStyle::Lf))
  assert_true(@formatter.NewlineStyle::from_id("crlf") is Some(@formatter.NewlineStyle::Crlf))
  assert_true(@formatter.NewlineStyle::from_id("auto") is None)
}

test "formatter_statement_offsets_index_into_output" {
  let options = @formatter.FormatOptions::default()
  let result = match @api.format_with_ids(b"select 1; select 2", "4.x", "strict", options) {
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
  let empty = match @api.format_with_ids(b"", "4.x", "strict", options) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(empty.statement_offsets.length(), 0)
  assert_eq(empty.output.length(), 0)
}

test "formatter_metadata_and_ids_agree_on_output" {
  // format_with_metadata (manifest-style) and format_with_ids must produce the
  // same formatted output — metadata propagation is irrelevant to formatting.
  let raw = b"select /*+ SET_VAR(enable_vectorized_engine=true) */ a, /* keep */ b -- trailing\nfrom t"
  let options = @formatter.FormatOptions::default()
  let via_ids = match @api.format_with_ids(raw, "4.x", "strict", options) {
    Ok(result) => result
    Err(_) => panic()
  }
  let via_metadata = match @api.format_with_metadata(
    raw,
    "4.x",
    "4.x",
    "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT",
    "strict",
    options,
  ) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(via_ids.accepted)
  assert_true(via_metadata.accepted)
  assert_eq(via_metadata.output, via_ids.output)
  assert_eq(via_metadata.diagnostics.length(), via_ids.diagnostics.length())
}

test "formatter_determinism_pure_function_backstop" {
  // Probe FMT-01: format_text is a pure function of (raw, parse_options,
  // format_options) — repeated calls return byte-identical output and
  // diagnostics, with no shared mutable state or IO.
  let raw = b"select user_id, user_name, user_email, user_phone, user_address, user_status, user_created_at, user_updated_at from user_profile where user_status = 'active' group by user_id order by user_created_at"
  let options = @formatter.FormatOptions::default()
  let parse_options = match @api.ParseOptions::new("3.x", "strict") {
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
  assert_true(bad_indent is Err(@formatter.FormatError::InvalidIndent(value=-2)))
  let bad_width = @formatter.FormatOptions::new(
    @formatter.KeywordCase::Upper,
    2,
    -10,
    @formatter.CommaStyle::Trailing,
    @formatter.NewlineStyle::FollowInput,
    true,
  )
  assert_true(bad_width is Err(@formatter.FormatError::InvalidLineWidth(value=-10)))
}

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
    @syntax.SyntaxElement::Leaf(@syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceToken, span(0, 1))),
    @syntax.SyntaxElement::Leaf(@syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceToken, span(1, 2))),
    @syntax.SyntaxElement::Leaf(@syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceToken, span(2, 3))),
    @syntax.SyntaxElement::Leaf(@syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceTrivia, span(3, 4))),
    @syntax.SyntaxElement::Leaf(@syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceToken, span(4, 5))),
    @syntax.SyntaxElement::Leaf(@syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceToken, span(5, 6))),
  ]
  let family = match @syntax.SyntaxNode::new(@syntax.SyntaxKind::ValueList, span(0, 6), leaves) {
    Some(node) => node
    None => panic()
  }
  let statement = match @syntax.SyntaxNode::new(
    @syntax.SyntaxKind::Statement,
    span(0, 6),
    [@syntax.SyntaxElement::ChildNode(family)],
  ) {
    Some(node) => node
    None => panic()
  }
  let root = match @syntax.SyntaxNode::new(
    @syntax.SyntaxKind::Document,
    span(0, 6),
    [@syntax.SyntaxElement::ChildNode(statement)],
  ) {
    Some(node) => node
    None => panic()
  }
  let result = @formatter.format(root, source, @formatter.FormatOptions::default())
  assert_true(result.accepted)
  // Flat emission: `(1, 2)` with the canonical single trailing newline — the
  // ValueList family has no clause table, so no break is forced anywhere and
  // the full token sequence is replayed byte-for-byte.
  assert_eq(result.output, b"(1, 2)\n")
  assert_eq(result.diagnostics.length(), 0)
}

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
  let narrow = match @formatter.FormatOptions::new(
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
  let leading = match @formatter.FormatOptions::new(
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

