# Phase 2: Doris Completeness and Corpus — Pattern Map

**Mapped:** 2026-08-04
**Files analyzed:** 18 new/modified file groups (D-09..D-24 deliverables)
**Analogs found:** 13 / 18 with concrete codebase analogs; 5 are greenfield (analyzer package, corpus tooling, generated report)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `token/token.mbt` | model / language metadata | transform: raw lexeme → profile-aware classification | `token/token.mbt` itself — `is_clause_keyword`/`is_reserved_word`/`is_unquoted_identifier` (3-layer base), `DorisFeature`+`FeatureMetadata` gate (Qualify/Tablet), `ProfileMetadata::for_manifest` validation | exact — extend in place |
| `parser/parser.mbt` | parser / service | request-response: tokens + profile + mode → CST + diagnostics | `parser/parser.mbt` `parse_segment` (1487-1532), `parse_query` (1285-1331), `parse_select_core` (1115-1189), `recover_expression` (1464-1486) | exact — extend in place |
| `syntax/syntax.mbt` | model / CST | transform: builder events → immutable lossless CST | `syntax/syntax.mbt` `SyntaxKind` enum + `SyntaxNode::new`/`node_invariants_hold` | exact — extend in place |
| `api/api.mbt` | API / facade | request-response: primitive options → versioned primitive result | `api/api.mbt` `kind_id` mapping, `PrimitiveNode`/`PrimitiveDiagnostic`/`ParseResult`, `parse_with_ids`/`parse_with_metadata` | exact — extend in place |
| `analyzer/moon.pkg` | config / package manifest | configuration | `parser/moon.pkg` — library package manifest with explicit import list | role-match (imports differ) |
| `analyzer/analyzer.mbt` | service / provider | request-response: CST + injected Catalog → name-resolution checks | partial: `token/token.mbt` `ProfileMetadata` record + `DorisProfile` enum pattern (trait/record shape); `syntax.mbt` read-only views | partial — greenfield, D-21..D-24 sketch |
| `corpus/manifest.tsv` | fixture data / corpus storage | batch: released docs → versioned fixture rows | `corpus/manifest.tsv` (15 rows, header at line 1) | exact — extend columns-in-place, add rows |
| `corpus/coverage.tsv` | report / data | batch: manifest → profile×category coverage | `corpus/coverage.tsv` header + row shape | exact — extend |
| `corpus/differential.tsv` | report / data | batch: differential runs → disagreement rows | `corpus/differential.tsv` header + row shape | exact — extend |
| `corpus/keywords.tsv` | data / report | batch: classification table (D-16) | `corpus/manifest.tsv` TSV convention (tab-delimited, header row) | role-match — new file |
| `corpus/CORPUS-REPORT.md` | report (generated, D-19) | batch: manifest+coverage → matrix report | no analog — generated markdown, `--check` stale-detection mode prescribed by research Pattern 5 | research-only |
| `corpus/doris-{2.1,3.x,4.x}/*.sql` | fixture data / corpus storage | batch: versioned SQL fixtures | `corpus/doris-2.1/select-industrial.sql` (comment header + statements, no `mysql>` prompts) | exact |
| `corpus/tools/generate_corpus_report.py` | tooling / script | batch + file-I/O (stdlib csv/pathlib) | no analog — Python dev tooling; research Pattern 5 + sketch | research-only |
| `corpus/tools/sqlglot_diff.py` | tooling / script | batch + file-I/O, external parse baseline | no analog — Python dev tooling; research Code Example 13 | research-only |
| `test/parser_test.mbt` | test | golden/request-response: statement families → strict CST/result | itself — `parse_strict`/`parse_editor_parser` helpers (1-12), `EmbeddedManifestFixture` + `metadata_fixture_replay_ok` (461-496), DORIS-03 script test (15-24) | exact — extend in place |
| `test/recovery_test.mbt` | test | recovery/property: malformed input → bounded editor CST | itself — `parse_with_limits` helper, `has_kind` tree probe | exact — extend in place |

**Modification-only packages with unchanged boundaries:** `parser/moon.pkg` imports only source/token/lexer/syntax — analyzer MUST NOT be added there (D-21, Pitfall 7). `test/moon.pkg` import list is the template for any new test package.

---

## Pattern Assignments

### `token/token.mbt` (model / language metadata, transform) — D-13..D-16, D-15

**Analog:** `token/token.mbt` (self-extension). All three classification layers and the version gate already exist; Phase 2 widens them.

**Three-layer classification pattern** (token.mbt:199-258) — add DML/DDL grammar words to the correct layer. `is_reserved_word` delegates to `is_clause_keyword` and `is_unquoted_identifier` derives from it:
```moonbit
/// Released-profile clause boundaries shared by parser contexts.
pub fn is_clause_keyword(raw : Bytes) -> Bool {
  token_bytes_equal_ci(raw, b"SELECT") || token_bytes_equal_ci(raw, b"WITH") ||
    token_bytes_equal_ci(raw, b"FROM") || token_bytes_equal_ci(raw, b"WHERE") ||
    token_bytes_equal_ci(raw, b"GROUP") || token_bytes_equal_ci(raw, b"HAVING") ||
    token_bytes_equal_ci(raw, b"ORDER") || token_bytes_equal_ci(raw, b"LIMIT") ||
    token_bytes_equal_ci(raw, b"JOIN") || token_bytes_equal_ci(raw, b"UNION") ||
    token_bytes_equal_ci(raw, b"QUALIFY") || token_bytes_equal_ci(raw, b"WINDOW") ||
    token_bytes_equal_ci(raw, b"INTO") || token_bytes_equal_ci(raw, b"ON") ||
    token_bytes_equal_ci(raw, b"USING")
}
pub fn is_reserved_word(raw : Bytes) -> Bool { is_clause_keyword(raw) || token_bytes_equal_ci(raw, b"AS") || /* ... */ }
pub fn is_unquoted_identifier(raw : Bytes) -> Bool { !is_reserved_word(raw) }
```
**Caution (research Pitfall 3):** `is_clause_keyword` is shared by `recover_expression`, `is_projection_boundary` (parser.mbt:1190-1192), and `parse_projection_alias`. Do NOT add `VALUES`/`SET`/`WHEN`/`BUCKETS` here blindly — DML sync words belong in per-family sets inside parser.mbt (see parser section). Non-reserved grammar words (`BUCKETS`, `PROPERTIES`, `COMMENT`, `AGGREGATE`, `ENGINE`, `ROLLUP`) stay OUT of `is_reserved_word` so they remain usable as unquoted identifiers (research Pitfall 2).

**Version gate pattern — extend `DorisFeature` enum** (token.mbt:105-155). MERGE gets a 4.x `introduced_profile` row exactly like QUALIFY/TABLET:
```moonbit
pub(all) enum DorisFeature {
  Qualify
  Tablet
  // Phase 2 additions (planner names): MergeInto, OrderByClause, PartitionStar, ...
} derive(Eq, @debug.Debug)

pub struct FeatureMetadata {
  pub name : String
  pub keyword : Bytes
  pub introduced_profile : String
  pub diagnostic_code : String
  pub recovery_kind : String
  pub diagnostic_message : String
}

pub fn DorisFeature::metadata(self : DorisFeature) -> FeatureMetadata {
  match self {
    Qualify => {
      name: "QUALIFY",
      keyword: b"QUALIFY",
      introduced_profile: "3.x",
      diagnostic_code: "DORIS-PARSE-006",
      recovery_kind: "error",
      diagnostic_message: "feature QUALIFY is unavailable in the selected released profile",
    }
    Tablet => { /* same shape, TABLET */ }
  }
}
```
**Profile ranking + supports** (token.mbt:157-171): `profile_rank` V2_1=0 < V3_X=1 < V4_X=2; `introduced_rank` maps "2.1"/"3.x"/"4.x". New features reuse this unchanged.

**`ProfileMetadata::for_manifest` MUST be extended** (token.mbt:47-70) — currently only three SELECT feature_introduction strings pass validation; DML/DDL fixture rows with new strings are rejected today (research Pattern 3 warning):
```moonbit
pub fn ProfileMetadata::for_manifest(profile_id, exact_release, feature_introduction) -> Result[ValidatedProfileContext, ProfileMetadataError] {
  let profile = match DorisProfile::from_id(profile_id) { ... }
  let metadata = profile.metadata()
  if feature_introduction != "2.1 baseline SELECT" &&
    feature_introduction != "2.1 baseline; 3.x window and QUALIFY" &&
    feature_introduction != "2.1 baseline; 4.x released SELECT" {
    return Err(UnsupportedFeatureIntroduction(feature_introduction=feature_introduction))
  }
  ...
}
```
The same three-string allowlist appears in `DorisProfile::validate_metadata` (token.mbt:72-104). Add DML/DDL feature strings to BOTH. The canonical `ProfileMetadata` values per profile are at token.mbt:94-103 (`V2_1` → `"2.1 baseline SELECT"` etc.).

**Classification test conventions** (token.mbt tests, e.g. `released_identifier_classification_is_case_insensitive_and_contextual`): loop raw spellings through `is_reserved_word`/`is_unquoted_identifier`; assert `tablet` is NOT reserved (contextual) and `user_name` IS an identifier. Phase 2 adds positive/negative pairs per classification word (research Pitfall 2): word as identifier, alias, property key, quoted name, clause keyword.

---

### `parser/parser.mbt` (parser / service, request-response) — D-09..D-12, D-23

**Analog:** `parser/parser.mbt` (self-extension). The dispatch, recovery, gating, and node-building machinery is exactly what Phase 2 replaces/extends.

**Keyword-first dispatch — replace the SELECT-only gate in `parse_segment`** (parser.mbt:1487-1532). Current gate emits `DORIS-PARSE-001 "expected SELECT statement"` for every non-SELECT/WITH starter; Phase 2 (research Pattern 1 sketch) dispatches INSERT/UPDATE/DELETE/MERGE/CREATE and produces an explicit unsupported-statement node with a NEW stable diagnostic (reserve DORIS-PARSE-007, research Open Question 3) for everything else — never silent (D-12):
```moonbit
fn parse_segment(stream, start_index, end_index, statement_id, state) -> @syntax.SyntaxNode {
  let span = segment_span(stream, start_index, end_index)
  let indices = significant_indices(stream, start_index, end_index)
  let selected = match indices.get(0) {
    Some(first_index) => match stream.raw(first_index) {
      Some(raw) if bytes_equal_ci(raw, b"SELECT") || bytes_equal_ci(raw, b"WITH") => true
      Some(_) => { add_diagnostic(state, "DORIS-PARSE-001", "expected SELECT statement", "statement", span, statement_id); false }
      None => false
    }
    None => false
  }
  if selected {
    let cursor = { stream: stream, indices: indices, position: 0 }
    let parsed = parse_query(cursor, state, stream.source, statement_id)
    let mut trailing = false
    while cursor.position < cursor.indices.length() {
      match raw_at(cursor) {
        Some(raw) if raw == b";" => advance(cursor)
        Some(_) => {
          let before = cursor.position
          trailing = true
          recover_expression(cursor, state, stream.source, statement_id)
          if cursor.position == before { advance(cursor) }
        }
        None => cursor.position = cursor.indices.length()
      }
    }
    if trailing { add_diagnostic(state, "DORIS-PARSE-001", "unexpected tokens after SELECT query", "statement", span, statement_id) }
    let children = segment_children_for_events(stream, start_index, end_index, state.feature_events)
    if !parsed || trailing { children.push(@syntax.SyntaxElement::ChildNode(require_node(@syntax.SyntaxNode::missing(span.end_byte, stream.source.byte_length())))) }
    let select = require_node(@syntax.SyntaxNode::new(@syntax.SyntaxKind::Select, span, children))
    require_node(@syntax.SyntaxNode::new(@syntax.SyntaxKind::Statement, span, [@syntax.SyntaxElement::ChildNode(select)]))
  } else {
    let children = segment_children_for_profile(stream, start_index, end_index)
    let error = require_node(@syntax.SyntaxNode::new(@syntax.SyntaxKind::Error, span, children))
    require_node(@syntax.SyntaxNode::new(@syntax.SyntaxKind::Statement, span, [@syntax.SyntaxElement::ChildNode(error)]))
  }
}
```
**Preserve:** the trailing `;`/recovery loop, `Statement` wrapper, `Missing` push on `!parsed || trailing`, `segment_children_for_events` feature-event leaf substitution, and `statement_id` increment. Only the `selected` match and the per-family parse calls change. Case-insensitivity comes free via `bytes_equal_ci` (parser.mbt:136-154).

**Statement-parser template — `parse_query`/`parse_select_core` shape** (parser.mbt:1285-1331, 1115-1189): every new `parse_insert`/`parse_update`/`parse_delete`/`parse_merge`/`parse_create` returns `Bool`, takes `(cursor, state, source, statement_id)`, consumes clauses with `consume_word`/`expect_word`/`consume_symbol`, and ANDs `valid` through every clause. Clause consumption pattern from parse_select_core:
```moonbit
if consume_word(cursor, b"FROM") { valid = parse_from(cursor, profile, state, source, statement_id) && valid }
if consume_word(cursor, b"WHERE") { valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid }
// ... 
let qualify_span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
if consume_word(cursor, b"QUALIFY") {
  let feature = @token.DorisFeature::Qualify
  if !feature_allowed(state, feature) {
    add_feature_diagnostic(state, feature, qualify_span, statement_id)
    valid = false
  }
  valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid
}
```
This QUALIFY block is the exact template for D-15 gates inside DML/DDL productions (e.g., `MERGE INTO` under 2.1/3.x, `ORDER BY` under <4.1.0, `PARTITION (*)` under <2.1.3). `parse_query` also shows the WITH-CTE loop (parser.mbt:1289-1317) — reuse directly for `UPDATE`/`DELETE`/`MERGE` leading `[cte]`.

**Feature-gate machinery (reuse unchanged)** (parser.mbt:335-375):
```moonbit
fn feature_allowed(state : RecoveryState, feature : @token.DorisFeature) -> Bool { state.profile_context.supports(feature) }
priv struct FeatureEvent { span : @source.Span }
fn record_feature_event(state : RecoveryState, span : @source.Span) -> Unit { state.feature_events.push({ span: span }) }
fn add_feature_diagnostic(state, feature, span, statement_id) -> Unit {
  record_feature_event(state, span)
  let metadata = feature.metadata()
  add_diagnostic(state, metadata.diagnostic_code, metadata.diagnostic_message, "released-version", span, statement_id)
}
fn version_invalid_node(token : @token.Token) -> @syntax.SyntaxElement {
  @syntax.SyntaxElement::ChildNode(require_node(@syntax.SyntaxNode::error(
    token.span,
    [@syntax.SyntaxElement::Leaf(@syntax.SyntaxLeaf::new(@syntax.LeafKind::SourceError, token.span))],
  )))
}
```
`segment_children_for_events` (parser.mbt:1427-1444) rewrites gated tokens into `version_invalid_node` leaves — this is what keeps D-12 "never silently accept" source-backed and lossless.

**Per-family recovery sync sets — extend, don't replace** (research Pattern 2 + Pitfall 3): `recover_expression` (parser.mbt:1464-1486) stops at `)`, `,`, `;`, and `is_clause_keyword`. New DML/DDL parsers should define their own clause-boundary predicates (e.g., `is_insert_clause_boundary`, `is_create_table_clause_boundary`) rather than polluting the shared set. Statement-level panic-mode at `;`/EOF lives in `parse_with_limits_context` (parser.mbt:1589-1689) and is untouched:
```moonbit
while index < parse_end {
  let is_semicolon = match stream.raw(index) { Some(raw) => raw == b";"; None => false }
  if is_semicolon {
    let segment_end = index + 1
    if has_statement_content(stream, segment_start, segment_end) {
      let segment = parse_segment(stream, segment_start, segment_end, statement_id, state)
      if segment.span().length() > 0 {
        root_children.push(@syntax.SyntaxElement::ChildNode(segment))
        statement_id = statement_id + 1U
      }
    } else { append_trivia_segment(root_children, stream, segment_start, segment_end) }
    segment_start = segment_end
  }
  index = index + 1
}
```
DORIS-03 (later statements survive) is guaranteed by this loop — a bad DML segment produces one Error/Statement node with its own `statement_id`; the following `;`-delimited segment parses independently. `segment_statement_id_for_span` (parser.mbt:1386-1407) already maps spans → monotonic ids.

**Node construction invariants** — every new SyntaxKind must be built through `SyntaxNode::new` with touching, in-bounds child spans (see syntax.mbt section). Synthetic material must be zero-width `Missing` only; recovery bytes stay source-backed leaves via `leaf_for_token` (parser.mbt:1358-1367).

**Diagnostic codes in use** (do not reuse): `DORIS-PARSE-001` statement, `-002` incomplete/expected, `-003` lexical, `-004` resource, `-006` feature-version. Reserve `-007+` for D-12 unsupported-statement (research Open Question 3). `add_diagnostic` (parser.mbt:187-209) and `expect_word`/`expect_symbol` (parser.mbt:295-333, `-002` with expected class "keyword"/"symbol") are the emit paths.

---

### `syntax/syntax.mbt` (model / CST, transform) — new SyntaxKinds

**Analog:** `syntax/syntax.mbt` (self-extension).

**Extend the kind enum** (syntax.mbt:3-12) — research Pattern 1 lists: `Insert`, `Update`, `Delete`, `Merge`, `CreateTable`, `CreateView`, `CreateIndex`, `CreateMaterializedView`, plus reusable `ColumnDefinition`, `KeyClause`, `DistributionClause`, `PartitionClause`, `PropertyList`, `ValueList`:
```moonbit
pub(all) enum SyntaxKind {
  Document
  Statement
  Select
  Expression
  Token
  Trivia
  Error
  Skipped
  Missing
} derive(Eq, @debug.Debug)
```
Keep the `Statement` wrapper (one `Statement` per segment, exactly as parse_segment does today) so `root.children.length()` == statement count stays a stable DORIS-03 assertion.

**Node construction invariants — copy, never weaken** (syntax.mbt:27-64): `node_invariants_hold` requires `text_len == span.length()`, children in ascending touching order, all child spans within parent span. `SyntaxNode::new` returns `None` on violation → `require_node` panics. Every new DML/DDL node must satisfy this; research Pitfall 4 (lossless replay breaks) is exactly a new parse function violating these invariants. Zero-width synthetic nodes: `SyntaxNode::missing(at, source_length)` (syntax.mbt:82-86); error/skipped wrappers: `SyntaxNode::error`/`skipped` (syntax.mbt:89-96).

**Existing invariant tests to mirror for new kinds** (syntax.mbt tests): `syntax_nodes_keep_touching_spans_and_zero_width_missing`, `syntax_validation_rejects_negative_or_noncontaining_text`, `syntax_error_and_skipped_reject_malformed_child_spans`.

---

### `api/api.mbt` (API / facade, request-response) — D-23 statement-level accessors

**Analog:** `api/api.mbt` (self-extension).

**Extend `kind_id` for every new SyntaxKind** (api.mbt:90-105) — the primitive wire contract maps kinds to lowercase strings:
```moonbit
fn kind_id(kind : @syntax.SyntaxKind) -> String {
  match kind {
    @syntax.SyntaxKind::Document => "document"
    @syntax.SyntaxKind::Statement => "statement"
    @syntax.SyntaxKind::Select => "select"
    @syntax.SyntaxKind::Expression => "expression"
    // Phase 2: "insert" | "update" | "delete" | "merge" | "create_table" | ...
    @syntax.SyntaxKind::Token => "token"
    @syntax.SyntaxKind::Trivia => "trivia"
    @syntax.SyntaxKind::Error => "error"
    @syntax.SyntaxKind::Skipped => "skipped"
    @syntax.SyntaxKind::Missing => "missing"
  }
}
```
This match is exhaustive — adding kinds without extending `kind_id` breaks compilation, which is the safety net.

**Statement-level accessors (D-23)** build on existing shape: `ParseResult` (api.mbt:129-142) already carries `root : PrimitiveNode` + `diagnostics : Array[PrimitiveDiagnostic]`, and `PrimitiveDiagnostic.statement_id : UInt` (api.mbt:119-127) is already populated by the parser. A `statement(node_id)` accessor walks `root.children` (each `Statement` gets its index as id) and filters diagnostics by `statement_id`. Entry points to extend: `parse_with_ids` (api.mbt:318-331) / `parse_with_metadata` (api.mbt:302-316) — both funnel through `parse` (api.mbt:214-268), which validates limits → builds SourceText → calls `@parser.parse_with_limits_context` → `parsed.root.is_valid(source.byte_length())` (returns `InvalidSyntaxTree` on failure) → serializes primitives. Keep this funnel; add accessors on top.

**Wire-schema tests to mirror:** `api_result_owns_source_once_and_has_bounded_descendant_spans` (all_spans_in_bounds), `api_diagnostic_statement_ids_are_monotonic_per_snapshot` (`b"bad; bad"` → ids 0U,1U).

---

### `analyzer/moon.pkg` + `analyzer/analyzer.mbt` (NEW package, D-21..D-24)

**Analog:** `parser/moon.pkg` for the manifest; research Code Example 12 for content. No repository package consumes a Catalog — this is the first.

**Package manifest — copy `parser/moon.pkg` shape, imports `syntax` (and optionally `api`) ONLY:**
```text
// parser/moon.pkg (existing, read-only) — one-way dependency chain source of truth
pkgtype(kind: "library")
import {
  "fathom/doris-sql/source" @source,
  "fathom/doris-sql/token" @token,
  "fathom/doris-sql/lexer" @lexer,
  "fathom/doris-sql/syntax" @syntax,
}
```
`analyzer/moon.pkg` must list only `syntax`/`api` imports; the parser package must NEVER gain an analyzer import (D-21, Pitfall 7 — verify via moon.pkg diff in review).

**Minimal catalog shape (D-22, D-24)** — research sketch, planner validates against pinned toolchain:
```moonbit
// analyzer/analyzer.mbt — name-resolution-level catalog, no type inference, no FE semantics
pub struct ColumnInfo { pub name : String, pub data_type : String }
pub struct TableInfo { pub name : String, pub columns : Array[ColumnInfo] }

pub trait Catalog {
  fn table(self, name : String) -> TableInfo?
}

pub struct StaticCatalog { tables : Map[String, TableInfo] }
pub fn StaticCatalog::lookup(self : StaticCatalog, name : String) -> TableInfo? { self.tables.get(name) }
```
Deliverable is interface + docs + minimal impl; full ANAL-01 resolution is v2 (D-24). Do not touch the syntax-only `valid` channel.

---

### `corpus/manifest.tsv` / `coverage.tsv` / `differential.tsv` (extend in place) — D-17..D-20, CORP-01..04

**Analog:** the existing files; extend columns-in-place and add rows. Header + one row (verbatim, current):
```text
# manifest.tsv header (line 1) — DO NOT rename columns (research Pattern 4)
fixture_id	profile	exact_release	feature_introduction	official_url	retrieval_date	pinned_source_revision	page_heading	code_fence	category	support_status	parse_mode	classification	provenance_status
2.1-industrial	2.1	2.1	2.1 baseline SELECT	https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-query/SELECT/	2026-08-03	unavailable-offline	SELECT	grammar:sql	industrial-select	supported	strict	parse-only	known-gap: GitHub revision lookup returned an empty API result
```
New Phase 2 category values (research Pattern 4 recommendation): `dml-insert`, `dml-insert-overwrite`, `dml-update`, `dml-delete`, `dml-merge`, `ddl-create-table`, `ddl-create-table-key`, `ddl-create-table-distribution`, `ddl-create-table-partition`, `ddl-create-table-properties`, `ddl-create-table-ctas`, `ddl-create-table-like`, `ddl-create-view`, `ddl-create-index`, `ddl-create-materialized-view`, `keyword-classification`, `script-multi-statement`, `malformed-recovery`. Provenance discipline: `unavailable-offline` + `known-gap:` for GitHub revision; versioned `official_url` (docs site IS reachable this session — research Environment table).

```text
# coverage.tsv header (line 1)
profile	category	fixture_count	supported_count	expected_error_count	known_gap	coverage_note
2.1	industrial-select	1	1	0	pinned revision unavailable offline	SELECT hints, projection modifiers, ...
# ... plus the "all / known-gaps" row that makes the no-full-compatibility claim explicit
```
Invariant (research Pattern 5): every manifest fixture appears in exactly one coverage row; the `all/known-gaps` row continues.

```text
# differential.tsv header (line 1)
fixture_id	public_contract	fe_nereids_observation	sqlglot_observation	resolution	advisory_only
2.1-industrial	released-docs	not-run-offline	not-run-offline	public support is determined only by released-docs manifest	true
```
New rows: sqlglot rows get `sqlglot_accepted` observations from `corpus/tools/sqlglot_diff.py` (Code Example 13) with pinned `sqlglot==30.14.0` in the resolution; FE/Nereids stays `not-run-offline` + manual script (D-20). `advisory_only=true` on every row — neither is a contract.

### `corpus/doris-{2.1,3.x,4.x}/*.sql` (NEW fixtures)

**Analog:** `corpus/doris-2.1/select-industrial.sql` — standalone statements only, `--` provenance header, no `mysql>` prompts / `Query OK` / placeholder variables (research Pitfall 6):
```sql
-- Released Apache Doris 2.1 SELECT grammar examples.
-- Source: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-query/SELECT/
SELECT DISTINCT k, SUM(v) AS total
FROM fact PARTITION (p0) TABLESAMPLE (10)
...
SELECT a FROM first_table UNION ALL SELECT a FROM second_table;
SELECT `group`, `window` FROM `table`;
```
One file per variant, not one mega-fixture per family (research anti-pattern): `dml-insert-values.sql`, `dml-insert-select.sql`, `dml-insert-overwrite.sql`, `dml-update.sql`, `dml-delete.sql`, `dml-merge.sql`, `ddl-create-table-key.sql`, `ddl-create-table-distribution.sql`, `ddl-create-table-partition.sql`, `ddl-create-table-properties.sql`, `ddl-create-table-ctas.sql`, `ddl-create-table-like.sql`, `ddl-create-view.sql`, `ddl-create-index.sql`, `ddl-create-materialized-view.sql`, `script-multi-statement.sql`, `malformed-recovery.sql`.

---

### `test/parser_test.mbt` (extend) and `test/recovery_test.mbt` (extend) — CORP-02, DORIS-03

**Analog:** both files extend themselves. Test-package imports (`test/moon.pkg`) already include api/parser/printer/source/token — sufficient for DML/DDL tests; add nothing unless analyzer tests arrive.

**Helper convention** (parser_test.mbt:1-12) — keep and reuse for new families:
```moonbit
fn parse_strict(raw : Bytes) -> @api.ParseResult {
  match @api.parse_with_ids(raw, "3.x", "strict") { Ok(result) => result; Err(_) => panic() }
}
fn parse_editor_parser(raw : Bytes) -> @api.ParseResult {
  match @api.parse_with_ids(raw, "3.x", "editor") { Ok(result) => result; Err(_) => panic() }
}
```

**DORIS-03 script test — copy `select_and_later_statement_keep_source_order_and_ids` (parser_test.mbt:15-24) and parameterize with DML/DDL** (research Code Example 11 + Pitfall 5):
```moonbit
test "select_and_later_statement_keep_source_order_and_ids" {
  let result = parse_strict(b"SELECT a + 1; bad; SELECT b")
  assert_eq(@printer.print_result(result), b"SELECT a + 1; bad; SELECT b")
  assert_eq(result.root.children.length(), 3)
  assert_true(!result.valid)
  let bad = result.diagnostics[0]
  assert_true(bad.start_byte <= bad.end_byte)
  assert_eq(bad.statement_id, 1U)
}
```
Phase 2 adds: `b"INSERT INTO t VALUES (1); bad; SELECT b"` (3 Statement nodes, id 1U on the bad one), `b"CREATE TABLE t (a INT; INSERT INTO t VALUES (1); SELECT * FROM t"` (unclosed `(` must not swallow later statements — Pitfall 5), byte-exact replay asserted on each.

**Version-gate tests — copy `released_profiles_gate_qualify_without_generic_fallback` / `version_invalid_features_share_metadata_gate_and_editor_shape` (parser_test.mbt:199-224, 269-289)**: MERGE under 2.1/3.x → `DORIS-PARSE-006` + `recovered` in editor; positive gate under 4.x. Also `gated_feature_spellings_are_contextual_outside_productions` (291-306) for non-reserved DDL words usable as identifiers.

**Manifest-driven replay test — extend `EmbeddedManifestFixture` + `metadata_fixture_replay_ok` (parser_test.mbt:461-496) and `released_manifest_metadata_drives_deterministic_parse_replay` (498-551)**: this is the executable CORP-02 oracle (parse via `parse_with_metadata` → `print_result == raw`, `all_spans_in_bounds`, expected_valid, `DORIS-PARSE-` prefix on every diagnostic). Add one fixture entry per new corpus row (2.1/3.x/4.x DML + DDL); `metadata_mismatch_unknown_and_unsupported_rows_are_rejected_before_parse` (553-577) already proves the manifest validation gate.

**Recovery/limits tests — copy `test/recovery_test.mbt` shape**: `parse_with_limits` helper (V4_X + editor + custom limits), `has_kind(root, "skipped")` tree probe, `DORIS-PARSE-004` resource assertion, `print_result == raw` on every malformed input. Phase 2 adds DDL adversarial fixtures (unclosed `(`, huge property lists, statement-count stress).

---

## Shared Patterns

### Statement segmentation (D-11, D-23, DORIS-03)
**Source:** `parser/parser.mbt` `parse_with_limits_context` (1589-1689) + `has_statement_content` (1346-1356) + `segment_statement_id_for_span` (1386-1407)
**Apply to:** all new statement parsers; do NOT introduce regex `;` splitting (research anti-pattern — semicolons inside strings/comments are lexer-absorbed).
**Core:** token-level `;` terminates segments; `has_statement_content` skips trivia-only segments; `statement_id` increments per non-empty segment; `parse_segment` is called per segment and wrapped in `Statement`.

### Feature version gating (D-15)
**Source:** `token/token.mbt` `DorisFeature`+`FeatureMetadata` (105-155), `DorisProfile::supports` (157-171); `parser/parser.mbt` `feature_allowed`/`add_feature_diagnostic`/`version_invalid_node` (335-375), `segment_children_for_events` (1427-1444)
**Apply to:** MERGE (4.x), `ORDER BY` (4.1.0), `PARTITION (*)` (2.1.3), `BUCKETS AUTO`, `AUTO PARTITION BY` — every production with a documented introduction version. Gate failure = DORIS-PARSE-006 + source-backed error node; never silent (D-12).

### Error handling
**Source:** `parser/parser.mbt` `add_diagnostic` (187-209, bounded by max_diagnostics + resource_emitted), `resource_diagnostic` (167-184, DORIS-PARSE-004), `expect_word`/`expect_symbol` (295-333, DORIS-PARSE-002 with expected class)
**Apply to:** all new parse functions. Diagnostics carry `severity="error"`, stable `code`, `expected_class`, span, `statement_id`. Unsupported statement starters get a NEW code (reserve DORIS-PARSE-007) — never DORIS-PARSE-001 "expected SELECT".

### Lossless replay invariant (CORE)
**Source:** `printer/printer.mbt` `print_lossless`/`print_result` (24-35, 61-73, leaf walk over source slices); `syntax/syntax.mbt` `node_invariants_hold` (27-49)
**Apply to:** every new statement family and every recovery path. Gate: `@printer.print_result(parse(raw)) == raw` byte-exact; zero-width `Missing` only for synthetic material. Covered by tests `printer_replays_the_complete_parser_api_path` and Pitfall 4 fixtures.

### Recovery (D-11)
**Source:** `parser/parser.mbt` `recover_expression` (1464-1486, sync set `)`/`,`/`;`/is_clause_keyword), `consume_recovery_step` (212-224, bounded), `depth_allowed` (244-253)
**Apply to:** per-family sync sets inside new parsers; statement-level panic-mode at `;`/EOF unchanged. Progress-or-error invariant: every recovery path consumes input or creates an explicit zero-width node.

### Identifier/word validation
**Source:** `parser/parser.mbt` `is_identifier_candidate` (379-390, Quoted token OR Identifier token passing `is_unquoted_identifier`), `is_word_token` (268-279), `consume_word` (281-286), `is_expression_operand` (392-404)
**Apply to:** column names, table names, partition names, property keys in DDL — a reserved word must require backticks, non-reserved grammar words stay identifiers (Pitfall 2).

### TSV corpus conventions
**Source:** `corpus/manifest.tsv` (14 columns, tab-delimited), `corpus/coverage.tsv`, `corpus/differential.tsv`
**Apply to:** new rows and `corpus/keywords.tsv` (D-16: word / classification / introduced_profile / source). Tab-delimited with header; provenance `unavailable-offline` + `known-gap:`; every parser production's words get a keywords.tsv row (single source of truth).

### Test conventions
**Source:** `test/parser_test.mbt` helpers (1-12), `EmbeddedManifestFixture` (461-496), per-family positive/negative/malformed loops with `for profile in [...] for mode in [...]`; `test/recovery_test.mbt` `parse_with_limits` + `has_kind`
**Apply to:** all new families — strict/editor paired fixtures, version-negative fixtures per profile, round-trip assertion on every input, snapshot updates only via reviewed `moon test --update` diff (Pitfall 7 discipline).

---

## No Analog Found (planner uses RESEARCH.md patterns)

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `analyzer/analyzer.mbt` | service / provider | request-response (catalog lookup) | First package consuming an injected Catalog; trait/record shape follows research Code Example 12 + token.mbt record conventions |
| `corpus/keywords.tsv` | data / report | batch | New deliverable (D-16); TSV shape follows manifest.tsv convention |
| `corpus/CORPUS-REPORT.md` | report (generated) | batch | Generated artifact (D-19); research Pattern 5 prescribes stdlib-Python generator + `--check` stale mode |
| `corpus/tools/generate_corpus_report.py` | tooling / script | batch + file-I/O | No Python in repo; research Pattern 5 + csv/pathlib stdlib guidance |
| `corpus/tools/sqlglot_diff.py` | tooling / script | batch + file-I/O | Research Code Example 13 provides the full shape; pin `sqlglot==30.14.0`, `advisory_only=true` rows |

---

## Metadata

**Analog search scope:** `/opt/source/Fathom/{source,token,lexer,syntax,parser,api,printer,test,corpus}` — all Phase 1 files read (parser.mbt 67.1KB full function map + targeted reads; token.mbt, syntax.mbt, api.mbt, printer.mbt, source.mbt, lexer.mbt read; all corpus TSVs + fixtures read; Phase 1 PATTERNS.md read for layout lineage).
**Files scanned:** 16 source/test files + 3 TSVs + 3 fixtures + 4 package manifests
**Pattern extraction date:** 2026-08-04
**Key cross-cutting warnings for the planner:**
1. `ProfileMetadata::for_manifest` and `DorisProfile::validate_metadata` both hard-code the 3 SELECT feature_introduction strings — extend BOTH before any DML/DDL fixture row is accepted (research Pattern 3).
2. `kind_id` in api.mbt is an exhaustive match — new SyntaxKinds force the api change by compilation.
3. Do not add DML words to the shared `is_clause_keyword` set without re-running Phase 1 SELECT recovery fixtures (research Pitfall 3).
4. `parser/moon.pkg` must never import `analyzer` (D-21); verify by diff in code review (Pitfall 7).
5. MERGE is 4.x-doc-only — 2.1/3.x profiles must emit DORIS-PARSE-006 (Pitfall 1).
