// White-box tests for the analyzer re-parser and resolution helpers (plan
// 05-03). These exercise internal functions directly — clause boundaries
// (with GROUP/ORDER two-word detection), paren-depth counting that is immune
// to string literals, qualified-name splitting, quoted-identifier
// identification, and case-fold comparison — paths the black-box integration
// surface cannot trigger without a full parse (lsp/selection_wbtest.mbt
// convention). No parser import: everything lives inside the analyzer package
// (D-21).

///|
/// Builds a (bytes, span) token array from bare word bytes, assigning
/// monotonically increasing dummy byte offsets (spans are not asserted here).
fn wb_tokens(words : Array[Bytes]) -> Array[(Bytes, Int, Int)] {
  let out : Array[(Bytes, Int, Int)] = []
  let mut offset = 0
  for word in words {
    out.push((word, offset, offset + word.length()))
    offset = offset + word.length() + 1
  }
  out
}

///|
test "wb clause_break full boundaries" {
  let toks = wb_tokens([
    b"SELECT", b"a", b"FROM", b"t", b"WHERE", b"b", b"GROUP", b"BY", b"a", b"HAVING",
    b"c", b"QUALIFY", b"d", b"ORDER", b"BY", b"e", b"LIMIT", b"5", b"WINDOW", b"w",
    b"AS", b"(", b")", b"UNION", b"SELECT", b"b", b"FROM", b"u",
  ])
  assert_eq(clause_kind_at(toks, 2, 0), Some(From))
  assert_eq(clause_kind_at(toks, 4, 0), Some(Where))
  assert_eq(clause_kind_at(toks, 6, 0), Some(GroupBy))
  assert_eq(clause_kind_at(toks, 9, 0), Some(Having))
  assert_eq(clause_kind_at(toks, 11, 0), Some(Qualify))
  assert_eq(clause_kind_at(toks, 13, 0), Some(OrderBy))
  assert_eq(clause_kind_at(toks, 16, 0), Some(Limit))
  assert_eq(clause_kind_at(toks, 18, 0), Some(Window))
  assert_eq(clause_kind_at(toks, 23, 0), Some(SetOpUnion))
  // None of these boundaries fire at depth > 0.
  assert_eq(clause_kind_at(toks, 2, 1), None)
  assert_eq(clause_kind_at(toks, 4, 3), None)
}

///|
test "wb clause_break group order two word" {
  // `order` as a column name: not followed by BY -> no boundary.
  let toks = wb_tokens([b"SELECT", b"order", b"FROM", b"t"])
  assert_eq(clause_kind_at(toks, 1, 0), None)
  assert_eq(clause_kind_at(toks, 2, 0), Some(From))
  // ORDER BY together -> boundary.
  let toks2 = wb_tokens([b"SELECT", b"a", b"FROM", b"t", b"ORDER", b"BY", b"a"])
  assert_eq(clause_kind_at(toks2, 4, 0), Some(OrderBy))
  // GROUP BY together -> boundary; bare GROUP not.
  let toks3 = wb_tokens([b"SELECT", b"a", b"FROM", b"t", b"GROUP", b"BY", b"a"])
  assert_eq(clause_kind_at(toks3, 4, 0), Some(GroupBy))
  let toks4 = wb_tokens([b"SELECT", b"group", b"FROM", b"t"])
  assert_eq(clause_kind_at(toks4, 1, 0), None)
}

///|
test "wb paren depth immune to strings" {
  // A `'('` string token is not a paren: depth never changes for it.
  let toks = wb_tokens([b"WHERE", b"a", b"=", b"'('", b"FROM", b"t"])
  assert_eq(clause_kind_at(toks, 3, 0), None)
  // `SELECT 'FROM'` must not produce a From boundary inside the select list.
  let stmt = wb_tokens([b"SELECT", b"'FROM'", b"FROM", b"t"])
  match split_select_model(stmt) {
    Some(model) => {
      assert_eq(model.branches.length(), 1)
      let core = model.branches[0]
      assert_eq(core.from.length(), 1)
      assert_eq(core.select_list.length(), 1)
      // The string literal contributes no identifier reference.
      assert_eq(core.select_list[0].refs.length(), 0)
    }
    None => panic()
  }
}

///|
test "wb paren depth string literal not counted" {
  // `WHERE a = '(' GROUP BY a`: the `'('` string must not unbalance depth, so
  // GROUP BY is still recognized as the next clause boundary.
  let toks = wb_tokens([
    b"SELECT", b"a", b"FROM", b"t", b"WHERE", b"a", b"=", b"'('", b"GROUP", b"BY",
    b"a",
  ])
  match split_select_model(toks) {
    Some(model) => {
      let core = model.branches[0]
      assert_eq(core.where_refs.length(), 1)
      assert_eq(core.group_by.length(), 1)
    }
    None => panic()
  }
}

///|
test "wb qualified name split 1 2 3 parts" {
  let one = collect_refs([{ bytes: b"a", start_byte: 0, end_byte: 1 }])
  assert_eq(one.length(), 1)
  assert_eq(one[0].parts.length(), 1)
  assert_true(!one[0].star)
  assert_true(!one[0].is_call)
  let two = collect_refs([
    { bytes: b"t", start_byte: 0, end_byte: 1 },
    { bytes: b".", start_byte: 1, end_byte: 2 },
    { bytes: b"a", start_byte: 2, end_byte: 3 },
  ])
  assert_eq(two[0].parts.length(), 2)
  let three = collect_refs([
    { bytes: b"db", start_byte: 0, end_byte: 2 },
    { bytes: b".", start_byte: 2, end_byte: 3 },
    { bytes: b"t", start_byte: 3, end_byte: 4 },
    { bytes: b".", start_byte: 4, end_byte: 5 },
    { bytes: b"b", start_byte: 5, end_byte: 6 },
  ])
  assert_eq(three[0].parts.length(), 3)
  // t.* star with qualifier.
  let star = collect_refs([
    { bytes: b"t", start_byte: 0, end_byte: 1 },
    { bytes: b".", start_byte: 1, end_byte: 2 },
    { bytes: b"*", start_byte: 2, end_byte: 3 },
  ])
  assert_true(star[0].star)
  assert_eq(star[0].parts.length(), 1)
  // count(...) is a function call, not a column ref.
  let call = collect_refs([
    { bytes: b"count", start_byte: 0, end_byte: 5 },
    { bytes: b"(", start_byte: 5, end_byte: 6 },
    { bytes: b"*", start_byte: 6, end_byte: 7 },
    { bytes: b")", start_byte: 7, end_byte: 8 },
  ])
  assert_eq(call.length(), 1)
  assert_true(call[0].is_call)
}

///|
test "wb quoted identification and case fold" {
  assert_true(is_quoted(b"`T`"))
  assert_true(is_quoted(b"\"T\""))
  assert_true(!is_quoted(b"T"))
  assert_eq(identifier_text(b"`T`"), "T")
  assert_eq(identifier_text(b"\"col\""), "col")
  assert_eq(identifier_text(b"col"), "col")
  // Unquoted matching folds ASCII case; quoted matching is byte-exact (D-03).
  let cols = [{ name: "A", data_type: "INT" }]
  match find_column_in(cols, "a", false) {
    Some(col) => assert_eq(col.name, "A")
    None => panic()
  }
  assert_true(find_column_in(cols, "a", true) is None)
  match find_column_in(cols, "A", true) {
    Some(col) => assert_eq(col.name, "A")
    None => panic()
  }
  assert_true(bytes_equal_ci(b"FOO", b"foo"))
  assert_true(bytes_equal_ci(b"FrOm", b"FROM"))
  assert_true(!bytes_equal_ci(b"FOO", b"bar"))
}

///|
test "wb split full select model all clauses" {
  let toks = wb_tokens([
    b"SELECT", b"a", b"FROM", b"t", b"WHERE", b"b", b"=", b"1", b"GROUP", b"BY",
    b"a", b"HAVING", b"count", b"(", b"*", b")", b">", b"1", b"QUALIFY", b"a", b">",
    b"0", b"ORDER", b"BY", b"a", b"LIMIT", b"5",
  ])
  match split_select_model(toks) {
    Some(model) => {
      assert_eq(model.branches.length(), 1)
      let core = model.branches[0]
      assert_eq(core.select_list.length(), 1)
      assert_eq(core.from.length(), 1)
      assert_eq(core.where_refs.length(), 1)
      assert_eq(core.group_by.length(), 1)
      assert_eq(core.having.length(), 1) // count(*) call
      assert_eq(core.qualify.length(), 1)
      assert_eq(core.order_by.length(), 1)
      assert_eq(core.limit.length(), 1)
    }
    None => panic()
  }
}

///|
test "wb split union chain model" {
  let toks = wb_tokens([
    b"SELECT", b"a", b"FROM", b"t", b"UNION", b"ALL", b"SELECT", b"b", b"FROM", b"u",
  ])
  match split_select_model(toks) {
    Some(model) => {
      assert_eq(model.branches.length(), 2)
      assert_eq(model.branches[0].set_op, Some("UNION ALL"))
      assert_eq(model.branches[1].set_op, None)
    }
    None => panic()
  }
}

///|
test "wb paren depth limit returns none" {
  let words : Array[Bytes] = [b"SELECT", b"a"]
  let mut i = 0
  while i < 140 {
    words.push(b"(")
    i = i + 1
  }
  let mut j = 0
  while j < 140 {
    words.push(b")")
    j = j + 1
  }
  words.push(b"FROM")
  words.push(b"t")
  let toks = wb_tokens(words)
  assert_true(split_select_model(toks) is None)
}

///|
test "wb build_select_item binary expr no bare alias" {
  // CR-01: `price * qty` must not bind the right operand as an alias.
  let item = build_select_item([
    { bytes: b"price", start_byte: 0, end_byte: 5 },
    { bytes: b"*", start_byte: 6, end_byte: 7 },
    { bytes: b"qty", start_byte: 8, end_byte: 11 },
  ])
  assert_eq(item.alias, None)
  assert_eq(item.refs.length(), 2)
  assert_eq(item.refs[0].parts[0].bytes, b"price")
  assert_eq(item.refs[1].parts[0].bytes, b"qty")
  assert_true(!item.star)
  // `a + b` also stays an expression, not `b` as an alias.
  let item2 = build_select_item([
    { bytes: b"a", start_byte: 0, end_byte: 1 },
    { bytes: b"+", start_byte: 2, end_byte: 3 },
    { bytes: b"b", start_byte: 4, end_byte: 5 },
  ])
  assert_eq(item2.alias, None)
  assert_eq(item2.refs.length(), 2)
  // `a >= b` comparison too.
  let item3 = build_select_item([
    { bytes: b"a", start_byte: 0, end_byte: 1 },
    { bytes: b">=", start_byte: 2, end_byte: 4 },
    { bytes: b"b", start_byte: 5, end_byte: 6 },
  ])
  assert_eq(item3.alias, None)
  assert_eq(item3.refs.length(), 2)
}

///|
test "wb build_select_item bare alias still works" {
  // `a b` is an implicit alias.
  let item = build_select_item([
    { bytes: b"a", start_byte: 0, end_byte: 1 },
    { bytes: b"b", start_byte: 2, end_byte: 3 },
  ])
  assert_eq(item.alias, Some("b"))
  assert_eq(item.refs.length(), 1)
  assert_eq(item.refs[0].parts[0].bytes, b"a")
  // `t.a b` — qualified ref + implicit alias.
  let item2 = build_select_item([
    { bytes: b"t", start_byte: 0, end_byte: 1 },
    { bytes: b".", start_byte: 1, end_byte: 2 },
    { bytes: b"a", start_byte: 2, end_byte: 3 },
    { bytes: b"b", start_byte: 4, end_byte: 5 },
  ])
  assert_eq(item2.alias, Some("b"))
  assert_eq(item2.refs.length(), 1)
  assert_eq(item2.refs[0].parts.length(), 2)
  // `count(*) x` — the `*` sits inside the call parens, so x is still an
  // implicit alias (not a binary-expression operand).
  let item3 = build_select_item([
    { bytes: b"count", start_byte: 0, end_byte: 5 },
    { bytes: b"(", start_byte: 5, end_byte: 6 },
    { bytes: b"*", start_byte: 6, end_byte: 7 },
    { bytes: b")", start_byte: 7, end_byte: 8 },
    { bytes: b"x", start_byte: 9, end_byte: 10 },
  ])
  assert_eq(item3.alias, Some("x"))
  assert_eq(item3.refs.length(), 1)
  assert_true(item3.refs[0].is_call)
}

///|
test "wb from order by not table alias" {
  // `SELECT a FROM t ORDER BY a` — ORDER BY must not be consumed as a bare
  // table alias of t (Pitfall 2 clause boundary): t is the only FROM item
  // and ORDER BY still yields an order_by ref.
  let toks = wb_tokens([b"SELECT", b"a", b"FROM", b"t", b"ORDER", b"BY", b"a"])
  match split_select_model(toks) {
    Some(model) => {
      let core = model.branches[0]
      assert_eq(core.from.length(), 1)
      assert_eq(core.from[0].alias, None)
      assert_eq(core.order_by.length(), 1)
    }
    None => panic()
  }
  // GROUP BY directly after the table is a boundary too.
  let toks2 = wb_tokens([b"SELECT", b"a", b"FROM", b"t", b"GROUP", b"BY", b"a"])
  match split_select_model(toks2) {
    Some(model) => {
      let core = model.branches[0]
      assert_eq(core.from.length(), 1)
      assert_eq(core.from[0].alias, None)
      assert_eq(core.group_by.length(), 1)
    }
    None => panic()
  }
  // `FROM t order` (no BY) still binds `order` as a bare table alias.
  let toks3 = wb_tokens([b"SELECT", b"a", b"FROM", b"t", b"order"])
  match split_select_model(toks3) {
    Some(model) => {
      let core = model.branches[0]
      assert_eq(core.from.length(), 1)
      assert_eq(core.from[0].alias, Some("order"))
    }
    None => panic()
  }
}

///|
test "wb collect_refs over window skip" {
  // WR-03: `SUM(x) OVER (PARTITION BY y ORDER BY z)` must not collect the
  // window spec tokens (PARTITION/BY/y/ORDER/z) as column references.
  let refs = collect_refs([
    { bytes: b"SUM", start_byte: 0, end_byte: 3 },
    { bytes: b"(", start_byte: 3, end_byte: 4 },
    { bytes: b"x", start_byte: 4, end_byte: 5 },
    { bytes: b")", start_byte: 5, end_byte: 6 },
    { bytes: b"OVER", start_byte: 7, end_byte: 11 },
    { bytes: b"(", start_byte: 11, end_byte: 12 },
    { bytes: b"PARTITION", start_byte: 12, end_byte: 21 },
    { bytes: b"BY", start_byte: 22, end_byte: 24 },
    { bytes: b"y", start_byte: 25, end_byte: 26 },
    { bytes: b"ORDER", start_byte: 27, end_byte: 32 },
    { bytes: b"BY", start_byte: 33, end_byte: 35 },
    { bytes: b"z", start_byte: 36, end_byte: 37 },
    { bytes: b")", start_byte: 37, end_byte: 38 },
  ])
  assert_eq(refs.length(), 2) // the SUM call and its argument x
  assert_true(refs[0].is_call)
  assert_eq(refs[0].parts[0].bytes, b"SUM")
  assert_eq(refs[1].parts[0].bytes, b"x")
  // Named-window reference `OVER w` is skipped too.
  let refs2 = collect_refs([
    { bytes: b"SUM", start_byte: 0, end_byte: 3 },
    { bytes: b"(", start_byte: 3, end_byte: 4 },
    { bytes: b"x", start_byte: 4, end_byte: 5 },
    { bytes: b")", start_byte: 5, end_byte: 6 },
    { bytes: b"OVER", start_byte: 7, end_byte: 11 },
    { bytes: b"w", start_byte: 12, end_byte: 13 },
  ])
  assert_eq(refs2.length(), 2)
  assert_eq(refs2[1].parts[0].bytes, b"x")
}

///|
test "wb build_select_item except cols captured" {
  // Task 2 (Pitfall 3 option a): `* EXCEPT (b)` captures the excluded column
  // token slices instead of discarding them (D-03), while the star projection
  // marker and empty refs remain.
  let item = build_select_item([
    { bytes: b"*", start_byte: 0, end_byte: 1 },
    { bytes: b"EXCEPT", start_byte: 2, end_byte: 8 },
    { bytes: b"(", start_byte: 9, end_byte: 10 },
    { bytes: b"b", start_byte: 10, end_byte: 11 },
    { bytes: b")", start_byte: 11, end_byte: 12 },
  ])
  assert_true(item.star)
  assert_eq(item.except_cols.length(), 1)
  assert_eq(item.except_cols[0].bytes, b"b")
  assert_eq(item.except_cols[0].start_byte, 10)
  assert_eq(item.except_cols[0].end_byte, 11)
  assert_eq(item.refs.length(), 0)
  // Multi-column EXCEPT: each top-level identifier is one exclusion slice.
  let item2 = build_select_item([
    { bytes: b"*", start_byte: 0, end_byte: 1 },
    { bytes: b"EXCEPT", start_byte: 2, end_byte: 8 },
    { bytes: b"(", start_byte: 9, end_byte: 10 },
    { bytes: b"b", start_byte: 10, end_byte: 11 },
    { bytes: b",", start_byte: 11, end_byte: 12 },
    { bytes: b"c", start_byte: 13, end_byte: 14 },
    { bytes: b")", start_byte: 14, end_byte: 15 },
  ])
  assert_true(item2.star)
  assert_eq(item2.except_cols.length(), 2)
  assert_eq(item2.except_cols[0].bytes, b"b")
  assert_eq(item2.except_cols[1].bytes, b"c")
  // Quoted exclusion keeps its quotes for byte-exact matching at expand_star.
  let item3 = build_select_item([
    { bytes: b"*", start_byte: 0, end_byte: 1 },
    { bytes: b"EXCEPT", start_byte: 2, end_byte: 8 },
    { bytes: b"(", start_byte: 9, end_byte: 10 },
    { bytes: b"\"B\"", start_byte: 10, end_byte: 13 },
    { bytes: b")", start_byte: 13, end_byte: 14 },
  ])
  assert_eq(item3.except_cols.length(), 1)
  assert_eq(item3.except_cols[0].bytes, b"\"B\"")
  // A non-star item is unaffected.
  let item4 = build_select_item([
    { bytes: b"a", start_byte: 0, end_byte: 1 },
    { bytes: b"+", start_byte: 2, end_byte: 3 },
    { bytes: b"b", start_byte: 4, end_byte: 5 },
  ])
  assert_true(!item4.star)
  assert_eq(item4.except_cols.length(), 0)
}

///|
test "wb expand_star except exclusion" {
  // Task 2 Behavior Test 2: `* EXCEPT (b)` over a scope exposing a/b/c yields
  // Column bindings for a and c only (no b); a plain `*` still yields a/b/c.
  let scope : Array[ScopeEntry] = [
    {
      key: "t",
      kind: ScopeKind::Table,
      columns: [
        { name: "a", data_type: "INT" },
        { name: "b", data_type: "INT" },
        { name: "c", data_type: "INT" },
      ],
      display: "t",
      is_quoted: false,
      block: 0,
    },
  ]
  let catalog = StaticCatalog::new([])
  let b1 : Array[Binding] = []
  let d1 : Array[AnalysisDiagnostic] = []
  let cols1 = expand_star(None, 7, 8, scope, catalog, b1, d1, [
    { bytes: b"b", start_byte: 0, end_byte: 1 },
  ])
  assert_eq(cols1.length(), 2)
  assert_eq(cols1[0].name, "a")
  assert_eq(cols1[1].name, "c")
  assert_eq(b1.length(), 2)
  assert_eq(b1[0].kind, BindingKind::Column)
  assert_eq(b1[0].name, "a")
  assert_eq(b1[0].start_byte, 7) // star span shared (D-03)
  assert_eq(b1[0].end_byte, 8)
  assert_eq(b1[1].name, "c")
  assert_eq(d1.length(), 0)
  // No EXCEPT -> all three columns expand.
  let b2 : Array[Binding] = []
  let d2 : Array[AnalysisDiagnostic] = []
  let cols2 = expand_star(None, 7, 8, scope, catalog, b2, d2, [])
  assert_eq(cols2.length(), 3)
  assert_eq(b2.length(), 3)
}

///|
test "wb expand_star except quote byte recheck" {
  // Task 2 Behavior Test 3 (D-03): quoted EXCEPT slices match byte-exact;
  // unquoted slices fold ASCII case — mirroring find_column_in so exclusion
  // and resolution share one matching rule.
  let scope : Array[ScopeEntry] = [
    {
      key: "t",
      kind: ScopeKind::Table,
      columns: [
        { name: "B", data_type: "INT" },
        { name: "b", data_type: "INT" },
      ],
      display: "t",
      is_quoted: false,
      block: 0,
    },
  ]
  let catalog = StaticCatalog::new([])
  // Quoted "B": byte-exact — removes only the "B" column, leaves "b".
  let b1 : Array[Binding] = []
  let d1 : Array[AnalysisDiagnostic] = []
  let cols1 = expand_star(None, 0, 1, scope, catalog, b1, d1, [
    { bytes: b"\"B\"", start_byte: 0, end_byte: 3 },
  ])
  assert_eq(cols1.length(), 1)
  assert_eq(cols1[0].name, "b")
  // Unquoted b: ASCII case-fold — removes both "B" and "b".
  let b2 : Array[Binding] = []
  let d2 : Array[AnalysisDiagnostic] = []
  let cols2 = expand_star(None, 0, 1, scope, catalog, b2, d2, [
    { bytes: b"b", start_byte: 0, end_byte: 1 },
  ])
  assert_eq(cols2.length(), 0)
}
