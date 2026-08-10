---
phase: 11-flink-grammar-and-recoverable-cst
verified: 2026-08-09T10:56:47Z
status: passed
score: 24/28 must-haves verified
behavior_unverified: 4 # Count of ⚠️ PRESENT_BEHAVIOR_UNVERIFIED truths (present + wired, invariant not exercised by a test); each is detailed in behavior_unverified_items below and in human_verification
overrides_applied: 0
gaps: [] # No FAILED truths, no MISSING/STUB artifacts, no NOT_WIRED key links, no blocker anti-patterns
behavior_unverified_items:

  - truth: "[probe FLINK-02 concurrency] The parser is a pure function of (source, dialect, profile, mode) with no shared mutable state across statements — concurrent parses cannot interleave recovery state."
    test: "Run two parses of distinct Flink inputs in parallel (e.g. two threads/processes invoking parse on different source strings) and confirm each returns the byte-identical serialized result it would return in isolation."
    expected: "Each concurrent parse yields the same diagnostics/spans/lossless replay as a serial parse of the same input; no recovery state bleeds across parses."
    why_human: "RecoveryState is per-parse by construction (a design argument visible in source), but no test in the suite executes two parses concurrently; the multi-statement fixtures pin statement-level isolation within a single parse, not thread-level concurrency."

  - truth: "[probe FLINK-03 concurrency] No shared mutable state is introduced by the Flink DDL parser — concurrent parses of the same DDL are isolated by construction and pinned by the multi-statement fixtures."
    test: "Concurrently parse Flink DDL statements (CREATE TABLE/VIEW/FUNCTION/CATALOG/DATABASE) and confirm results equal the serial parse results."
    expected: "Byte-identical serialized CST/diagnostics per input under concurrent execution; per-parse RecoveryState means no interleaving."
    why_human: "Same by-construction guarantee as the FLINK-02 concurrency probe; no concurrent-execution test exists in the suite."

  - truth: "[probe FLINK-04 concurrency] No shared mutable state is introduced by the CREATE TABLE body parser — concurrent parses of the same DDL are isolated by construction and pinned by the multi-statement fixtures."
    test: "Concurrently parse the same CREATE TABLE complex forms (four-column body, WATERMARK, constraints, table-level clauses) and confirm results equal the serial parse results."
    expected: "Byte-identical serialized CST/diagnostics per input under concurrent execution."
    why_human: "Same by-construction guarantee; no concurrent-execution test exists."

  - truth: "[probe FLINK-06 unclassified] MATCH_RECOGNIZE nested sub-language subset boundary (SUBSET/PERMUTE/{- -} known-limitation; no pattern-variable column-scope/type validation) is the recommended freeze, requiring executor verification against the pinned Parser.jj:3062-3346."
    test: "Review the frozen subset classification (SUBSET, PERMUTE, {- ... -} PatternExclude parse structurally and are known-limitation; syntactically valid input is never rejected for undeclared variables) against the pinned Flink/Calcite release grammar."
    expected: "The known-limitation classification matches the pinned grammar's syntactic acceptance; the no-scope-validation boundary is the intended freeze."
    why_human: "The probe was explicitly flagged 'unclassified — requires manual review' (no repository analog); the subset freeze is a judgment call against pinned grammar line refs that fixture/snapshot evidence cannot fully substitute for."
human_verification:

  - test: "Review the frozen MATCH_RECOGNIZE supported/known-limitation subset boundary against the pinned release grammar (Parser.jj:3062-3346): SUBSET, PERMUTE, and {- ... -} PatternExclude parse structurally and are classified known-limitation; no pattern-variable column-scope/type validation is performed."
    expected: "The known-limitation classification matches the pinned Flink/Calcite release grammar's syntactic acceptance for these constructs, and the 'syntactically valid input is never rejected for undeclared variables' boundary is the intended freeze."
    why_human: "The FLINK-06 probe was explicitly flagged 'unclassified — requires manual review' (no repository analog); verifying the subset boundary against the pinned grammar line refs is a judgment call the fixture/snapshot evidence cannot fully substitute for."

  - test: "Exercise FLINK-02/03/04 concurrency isolation by running two parses of different Flink inputs concurrently and confirming results equal serial parses (see behavior_unverified_items)."
    expected: "Concurrent parses return byte-identical serialized results to serial parses; no recovery state interleaves across parses."
    why_human: "Per-parse RecoveryState makes concurrency safe by construction, but no test exercises concurrent execution; the invariants are present and wired, not behaviorally proven."
---

# Phase 11: Flink Grammar and Recoverable CST — Verification Report

**Phase Goal:** Users can parse everyday Flink SQL and its distinctive DDL/window/pattern constructs into a lossless, bounded, recoverable CST without changing Doris acceptance or diagnostics.
**Verified:** 2026-08-09T10:56:47Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

The phase goal is **achieved in the codebase**. Goal-backward verification confirms every roadmap success criterion is observably true:

- Real `parse_flink_segment` keyword-first dispatch routes SELECT/WITH/INSERT/UPSERT/UPDATE/DELETE/EXPLAIN/SHOW/DESCRIBE/ANALYZE/USE/SET/RESET/CREATE/ALTER/DROP into `parser/flink_grammar.mbt` productions (2621 lines), producing source-backed CST in the `fathom.parse.v1` envelope with dialect/profile metadata. FATHOM-PARSE-008 is retired and vacant; genuinely-unsupported whole statements route to FATHOM-PARSE-007.
- Distinctive Flink constructs parse valid under flink-2.3.0: CREATE TABLE with WATERMARK/PRIMARY KEY NOT ENFORCED/computed/metadata columns/connector options/LIKE/AS; Window TVF TUMBLE/HOP/CUMULATE/SESSION with TABLE/DESCRIPTOR/INTERVAL/named args; syntax-level MATCH_RECOGNIZE with PATTERN/DEFINE/MEASURES/skip policy/variables/quantifiers/anchors/WITHIN INTERVAL.
- The bidirectional negative gate is live in both directions with stable diagnostics: Flink-only constructs reject under Doris (construct-level FATHOM-PARSE-009, whole-statement FATHOM-PARSE-007), Doris-only constructs reject under Flink (FATHOM-PARSE-009); shared syntax stays valid in both (no double-valid).
- Bounded recoverable CST is proven by the crash-safety fixes (hostile nested-generic and nested-PatternExclude inputs recover with a resource diagnostic instead of SIGSEGV; `WITH t` returns a recoverable unsupported-statement instead of SIGABRT) and by 160 lossless-replay assertions (`print_lossless(parse(x)) == x` in strict and editor modes) that all pass.
- Doris acceptance and diagnostics are unchanged: `moon test --package parity` passes **570/570 without `--update`** and `git diff --name-only -- parity/__snapshot__` shows **zero** doris-named snapshot changes (only the new `flink-grammar.*` group and the registered `flink-lexical.*` re-generation).

The remaining open items are **human-verification only**: 3 concurrency-isolation probes (by-construction guarantee, no concurrent test) and the FLINK-06 subset-boundary manual review. No FAILED truths, no MISSING/STUB artifacts, no broken key links, and no blocker anti-patterns were found.

### Observable Truths

| #   | Truth   | Status     | Evidence       |
| --- | ------- | ---------- | -------------- |
| 1   | **SC1**: User can parse Flink core queries (SELECT/CTE/JOIN/aggregation/set ops/expressions/types) and INSERT/UPDATE/DELETE, EXPLAIN/SHOW/DESCRIBE/ANALYZE with localized strict/editor diagnostics | ✓ VERIFIED | CLI: CTE+JOIN+AGG SELECT, INSERT OVERWRITE+PARTITION, UPSERT, ON CONFLICT DO NOTHING all valid=true, zero diagnostics; set-op loop (UNION/INTERSECT/EXCEPT + ALL) in `parse_flink_select_core`; `SHOW TABLES db1` emits a localized 002 at the offending token; parity `flink-grammar.select-*/insert-*/update-*/delete-*/explain-*/show-*/describe-*/analyze-*` fixtures + snapshots pass |
| 2   | **SC2**: User can inspect structured CST for Flink Catalog/DATABASE/TABLE/VIEW/FUNCTION DDL and CREATE TABLE physical/metadata/computed/WATERMARK/PK/partition/distribution/connector/LIKE/AS forms | ✓ VERIFIED | CLI: CREATE CATALOG WITH(...), CREATE TABLE full complex form (four column kinds + WATERMARK + PK NOT ENFORCED + COMMENT/DISTRIBUTED/PARTITIONED/WITH) valid=true; D-02 kinds create_catalog/create_table/create_view/create_function/watermark_clause etc. flow into the wire CST; parity `flink-grammar.create-*/drop-*/alter-*/create-table-*` fixtures + 194 goldens pass |
| 3   | **SC3**: User can inspect source-backed Window TVF (TUMBLE/HOP/CUMULATE/SESSION) and syntax-level MATCH_RECOGNIZE (PATTERN/DEFINE/MEASURES/skip/variables/quantifiers) CST, without a planner or execution-equivalence claim | ✓ VERIFIED | CLI: TUMBLE/HOP 4-arg, MATCH_RECOGNIZE full/anchors/quantifiers/WITHIN INTERVAL/SUBSET/PERMUTE/PatternExclude all valid=true; undeclared pattern variable accepted (no scope validation); window_start/end/time ordinary identifiers; no planner semantics anywhere in parser/flink_grammar.mbt |
| 4   | **SC4**: Strict and editor mode preserve comments/whitespace/newlines/unknown/error/missing/skipped material/source bytes/spans in a bounded recoverable CST; lossless replay byte-identical; Flink-only syntax rejected in Doris mode and vice versa with stable diagnostics | ✓ VERIFIED | 160 lossless assertions pass in strict+editor (parity 570/570); crash-safety repros exit 0 (no SIGSEGV/SIGABRT); bidirectional gates verified via CLI both directions; FATHOM-PARSE-009/007 stable codes; envelope carries dialect/profile/exact_release/mode |
| 5   | FATHOM-PARSE-008 retired and vacant; no valid Flink statement produces it; genuinely-unsupported whole statements route through FATHOM-PARSE-007 | ✓ VERIFIED | grep: 008 absent from all phase smoke tests (valid=true, no 008); `MERGE INTO ...` routes to 007; `SHOW TABLES` / `CREATE CATALOG` under Doris → 007; register §1 |
| 6   | FATHOM-PARSE-009 minted (D-04) with dialect in envelope metadata (D-10), never in the code prefix | ✓ VERIFIED | `add_dialect_gate_diagnostic` (parser.mbt:418) emits 009 with message "syntax is not supported in the selected dialect"; CLI confirms 009 both gate directions; envelope carries `dialect: flink` / `profile: flink-2.3.0`; register §2 |
| 7   | MATCH_RECOGNIZE + MATCH_NUMBER/MEASURES/PATTERN/DEFINE classify Reserved under every Flink profile (identifier only when backtick-quoted) | ✓ VERIFIED | dialect/flink.mbt:196-200 rows with Parser-calcite line refs; classification tests pass (dialect 8/8); `` SELECT `MATCH_RECOGNIZE` `` identifier, unquoted rejected |
| 8   | D-02 CST contract surface: 22 SyntaxKind variants appended at the enum end + snake_case kind_id wire strings (Doris ordinals preserved) | ✓ VERIFIED | syntax.mbt:26-47 appends 22 kinds after Missing; api.mbt:356-377 kind_id strings; parity 570/570 + 0 doris-snapshot diffs prove ordinals untouched |
| 9   | Flink data types parse via `parse_flink_data_type` (dataTypeParserMethods), incl. ROW&lt;...&gt;, TIMESTAMP(p) WITH [LOCAL] TIME ZONE, ARRAY/MAP/MULTISET generics; Doris `parse_column_type` untouched | ✓ VERIFIED | CLI: ROW&lt;f1 INT, f2 STRING&gt;, ROW&lt;f1 DECIMAL(10,2)&gt;, TIMESTAMP(3) WITH LOCAL TIME ZONE, ARRAY&lt;DECIMAL(10,2)&gt;, MAP&lt;STRING,INT&gt; all valid=true (MJ-01/MJ-04 fixes verified); Doris type set byte-identical (parity gate) |
| 10  | Doris baseline zero-drift: `moon test --package parity` (no --update) passes and no doris-named snapshot changes | ✓ VERIFIED | Parity **570/570** without --update; `git diff --name-only -- parity/__snapshot__` non-flink count = 0; only 194 new `flink-grammar.*` goldens + registered flink-lexical re-generation |
| 11  | MATCH_RECOGNIZE performs no pattern-variable column-scope/type validation; known-limitation subset (SUBSET/PERMUTE/{- -} structural) frozen; no planner/execution equivalence claim | ✓ VERIFIED | CLI: undeclared variable `B` in PATTERN(A B) with only DEFINE A accepted valid=true; PERMUTE/PatternExclude parse valid=true (structural); `flink_grammar_match_recognize_undeclared_variable_is_accepted` test passes; no planner logic in source |
| 12  | Crash-safety: nested ARRAY&lt;...&gt; and nested {- ... -} bounded by max_recursion_depth (no SIGSEGV); `WITH t` no out-of-bounds abort; `watermark` column under Doris valid | ✓ VERIFIED | REVIEW repros re-run: ARRAY&lt;×150000 exits 0, {- ×60000 exits 0, `WITH t` exits 0 under both dialects (was EXIT 139/134); `CREATE TABLE t (watermark INT)` under doris-4.x valid=true zero diags (CR-03); commits 217055c/e3cd867/7dbf792/c0ae0b2 present |
| 13  | [probe FLINK-02 adjacency] exactly-equal / just-touching constructs neither merge nor drop spans (span-contiguity invariant) | ✓ VERIFIED | node_invariants_hold mechanism (syntax.mbt:81) enforces span/text_len contiguity on every node; boundary fixtures (CTE/JOIN/insert-recovery) pass byte-exact lossless assertions in parity |
| 14  | [probe FLINK-02 empty] empty/single-token Flink input yields a bounded error/missing node with a localized diagnostic, never an infinite loop or fabricated subtree | ✓ VERIFIED | `select-incomplete`, `create-table-incomplete-*`, `match-recognize-empty-pattern`, `tvf-missing-*` fixtures pass lossless assertions; CLI `WITH t` and `TUMBLE(TABLE T1)` return bounded recoverable diagnostics |
| 15  | [probe FLINK-02 ordering] equal-precedence operators and set operations parse left-associative and stable (shared Pratt frozen) | ✓ VERIFIED | set-operation fixtures (union/intersect/except + ALL) frozen in snapshots; precedence(context,cursor) Doris arm byte-identical; parity suite passes |
| 16  | [probe CST-01 boundary] recovery at segment/statement boundaries stops exactly at the boundary token without consuming it into previous statement's skipped material | ✓ VERIFIED | `insert-recovery`, `update-recovery`, `view-recovery`, `match-recognize-recovery`, `tvf-recovery` fixtures assert the trailing statement parses as its own statement_id; all pass parity |
| 17  | [probe CST-01 precision] byte spans are exact half-open [start, end) offsets with no off-by-one | ✓ VERIFIED | Lossless replay `print_lossless(parse(x)) == x` is byte-exact for every positive/recovery fixture in both modes (160 assertions); CST walk shows contiguous [start,end) spans |
| 18  | [probe FLINK-02 idempotency] parsing the same Flink DML/aux input twice yields byte-identical serialized results; repeated parse of an already-recovered input is stable | ✓ VERIFIED | Snapshot mechanism freezes deterministic single-parse output (97 DML/aux goldens match current parses); deterministic parser confirmed by snapshot stability |
| 19  | [probe FLINK-02 MERGE] MERGE INTO under Flink routes to the unsupported path (FATHOM-PARSE-007) pending Calcite-base acceptance (ASSUMED A1) | ✓ VERIFIED | CLI: `MERGE INTO t USING s ...` → valid=false, codes [FATHOM-PARSE-007]; register §7 records the [ASSUMED] A1 outcome |
| 20  | [probe FLINK-03 idempotency] parsing the same Flink DDL input twice yields byte-identical results; repeated parse of an already-recovered DDL input is stable | ✓ VERIFIED | DDL snapshots freeze deterministic output; parity suite passes |
| 21  | [probe FLINK-03 concurrency] no shared mutable state in Flink DDL parser — concurrent parses isolated by construction | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Per-parse RecoveryState by construction (source-visible); multi-statement DDL fixtures pin statement-level isolation, but no test runs two parses concurrently → human verification |
| 22  | [probe FLINK-04 idempotency] re-parsing the same CREATE TABLE body yields byte-identical CST/diagnostics; trailing comma / empty column list fails deterministically the same way | ✓ VERIFIED | `create-table-trailing-comma`, `create-table-*` negative fixtures frozen in snapshots; parity passes |
| 23  | [probe FLINK-04 concurrency] no shared mutable state in CREATE TABLE body parser — concurrent parses isolated by construction | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Same by-construction guarantee as #21; no concurrent test → human verification |
| 24  | [probe FLINK-05 adjacency] TVF argument boundaries (TABLE t vs DESCRIPTOR(col) vs INTERVAL literal) stay distinct source-backed child nodes (WindowTvf span-contiguity) | ✓ VERIFIED | tvf-* fixtures (tumble/hop/cumulate/session/table-wrapper/offset/named-arg) pass lossless assertions; each argument a distinct child in CST |
| 25  | [probe FLINK-05 empty] empty/truncated TVF call yields a bounded error/missing node, never an infinite loop | ✓ VERIFIED | `tvf-missing-table`, `tvf-missing-descriptor-size`, `tvf-incomplete-interval` fixtures pass lossless; CLI `TUMBLE(DESCRIPTOR(rowtime), INTERVAL '1' DAY)` → two localized 002, no spurious 001 |
| 26  | [probe FLINK-05 ordering] TVF argument order (table, descriptor, size, optional offset) is positional and stable; named `=>` args recognized without reordering | ✓ VERIFIED | tvf fixtures freeze positional order; `TUMBLE(data => ..., timecol => ..., size => ...)` valid=true, unknown name → 002 (MN-03); parity passes |
| 27  | [probe FLINK-02 concurrency] parser is a pure function of (source, dialect, profile, mode) with no shared mutable state across statements — concurrent parses cannot interleave recovery state (guaranteed by construction, pinned by multi-statement fixtures) | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Per-parse RecoveryState by construction; multi-statement fixtures pin statement-level isolation; no test executes concurrent parses → human verification |
| 28  | [probe FLINK-06 unclassified] MATCH_RECOGNIZE subset boundary (SUBSET/PERMUTE/{- -} known-limitation; no pattern-variable scope validation) requires manual review against pinned Parser.jj:3062-3346 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Code parses SUBSET/PERMUTE/PatternExclude structurally and never rejects undeclared variables (CLI + passing tests); the freeze-vs-pinned-grammar classification is a judgment call → human verification |

**Score:** 24/28 truths verified (4 present, behavior-unverified → human verification)

### Required Artifacts

| Artifact | Expected    | Status | Details |
| -------- | ----------- | ------ | ------- |
| `parser/parser.mbt` (4543 lines) | `parse_flink_segment` real dispatch, `precedence(context,cursor)` Flink arm, `add_dialect_gate_diagnostic` (009), 008 retirement, dialect gates | ✓ VERIFIED | All present (parser.mbt:267/418/1905/4146); dispatch arms SELECT/WITH/INSERT/UPSERT/UPDATE/DELETE/EXPLAIN/SHOW/DESCRIBE/ANALYZE/USE/SET/RESET/CREATE/ALTER/DROP; FATHOM-PARSE-008 vacant; wired via CLI |
| `parser/flink_grammar.mbt` (2621 lines) | Flink query/DML/aux/DDL/CREATE TABLE/TVF/MATCH_RECOGNIZE productions | ✓ VERIFIED | All 40+ named productions present (parse_flink_query/select_core/insert/update/delete/explain/show/describe/analyze/use/set_reset/data_type/create/alter/drop/create_table/tvf_call/match_recognize/pattern_*); substantive; wired |
| `syntax/syntax.mbt` | 22 Flink SyntaxKind variants appended at enum end + node_invariants_hold | ✓ VERIFIED | syntax.mbt:26-47 + :81; Doris ordinals preserved (parity zero-drift) |
| `api/api.mbt` | kind_id wire strings for 22 kinds; `parse_flink` (renamed from not_implemented) | ✓ VERIFIED | api.mbt:356-377 kind_id strings; `fn parse_flink` exists; 0 occurrences of `parse_flink_not_implemented` (IN-01) |
| `dialect/flink.mbt` | MATCH_RECOGNIZE + MATCH_NUMBER/MEASURES/PATTERN/DEFINE reserved rows | ✓ VERIFIED | flink.mbt:196-200 with Parser-calcite line refs; classification tests pass |
| `parity/flink_grammar_test.mbt` (2603 lines) | 97 fixtures + snapshot harness + lossless + bidirectional gate tests | ✓ VERIFIED | 160 lossless assertions; `flink_grammar_bidirectional` helper; gate tests (tvf/match_recognize/watermark/named_arg etc.); parity 570/570 |
| `parity/fixtures/flink-grammar/manifest.tsv` + 194 goldens | provenance manifest + flink-grammar snapshot namespace | ✓ VERIFIED | 97 manifest rows; 194 goldens (97 strict + 97 editor); validator exits 0 |
| `scripts/extract_flink_grammar.py` | production line-ref validator | ✓ VERIFIED | `python3 scripts/extract_flink_grammar.py` exits 0 (13 production refs + 2 Calcite-base reserved + 97 manifest rows) |
| `approved-changes.md` | D-08 register (008 retirement, 009 minting, snapshot groups, re-freezes) | ✓ VERIFIED | Sections 1-8 present incl. review-fix re-freeze §8 |

### Key Link Verification

| From | To  | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `parse_flink_segment` dispatch (parser.mbt) | `parse_flink_query` / `parse_flink_insert` / `parse_flink_create` / ... (flink_grammar.mbt) | keyword-first dispatch arms + `finish_statement` with D-02 kind | ✓ WIRED | All arms route to Flink productions; CLI proves end-to-end |
| `parse_flink_data_type` | `parse_flink_create_table` column body | typed/metadata column type parsing — one Flink type parser | ✓ WIRED | `create-table-columns` fixture (TIMESTAMP_LTZ(3), METADATA FROM) valid=true |
| `parse_flink_create_table` clause loop | `is_flink_create_table_clause_boundary` | bounded unclosed-body recovery | ✓ WIRED | `create-table-incomplete-*` fixtures recover at clause boundary; lossless |
| `parse_table_ref` Flink TVF branch | `parse_flink_tvf_call` | `is_flink_tvf_starter` routing | ✓ WIRED | TUMBLE/HOP/CUMULATE/SESSION + TABLE(...) parse valid=true |
| `parse_table_ref` MATCH_RECOGNIZE suffix | `parse_match_recognize` | `is_match_recognize_suffix` LOOKAHEAD | ✓ WIRED | MR full/anchors/subset/permute/exclude parse valid=true |
| `parse_match_recognize` | `is_flink_match_recognize_boundary` | bounded sub-language recovery | ✓ WIRED | `match-recognize-recovery` fixture; unclosed PATTERN stops at boundary/`;` |
| `dialect/flink.mbt` MATCH_RECOGNIZE row | `classification_of` | flink_classification_rows lookup | ✓ WIRED | Reserved under every Flink profile; classification tests pass |
| `add_dialect_gate_diagnostic` | fathom.parse.v1 diagnostics array | FATHOM-PARSE-009 emission, dialect in envelope metadata | ✓ WIRED | CLI: both gate directions emit 009/007; envelope carries dialect/profile |
| Doris/parity snapshots | `moon test --package parity` | D-08 byte gate (no --update) | ✓ WIRED | 570/570 passes; 0 doris-named snapshot diffs |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| Flink SELECT CST | statement root + children | `parse_flink_query` over real token stream via `parse_flink_segment` | ✓ Real — CTE+JOIN+AGG input → valid=true Select node with source-backed token/trivia leaves | ✓ FLOWING |
| CREATE TABLE CST | create_table node + column/watermark/pk children | `parse_flink_create_table` (four-way TableColumn dispatch) | ✓ Real — full complex form → valid=true, CST walk shows source spans | ✓ FLOWING |
| Window TVF CST | WindowTvf node + TABLE/DESCRIPTOR/INTERVAL children | `parse_flink_tvf_call` over Flink table-ref | ✓ Real — TUMBLE/HOP/CUMULATE/SESSION parse valid=true with distinct child nodes | ✓ FLOWING |
| MATCH_RECOGNIZE CST | MatchRecognize node + sub-language children | `parse_match_recognize` (independent production) | ✓ Real — PATTERN/DEFINE/MEASURES/skip/quantifiers/anchors all source-backed | ✓ FLOWING |
| Diagnostics | FATHOM-PARSE-009/007/002 codes | `add_dialect_gate_diagnostic` / localized add_diagnostic | ✓ Real — gate fires on actual dialect mismatch; localized spans at offending token | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Flink SELECT CTE+JOIN+AGG | `fathom-sql parse --dialect flink --profile flink-2.3.0` | valid=true, 0 diags, no 008 | ✓ PASS |
| INSERT OVERWRITE+PARTITION / UPSERT / ON CONFLICT | CLI flink-2.3.0 | all valid=true, 0 diags | ✓ PASS |
| CREATE CATALOG WITH(...) | CLI flink-2.3.0 | valid=true | ✓ PASS |
| CREATE TABLE full complex form | CLI flink-2.3.0 | valid=true (pinned clause order) | ✓ PASS |
| Window TVF TUMBLE + HOP 4-arg | CLI flink-2.3.0 | valid=true | ✓ PASS |
| MATCH_RECOGNIZE full / anchors / quantifiers / WITHIN / SUBSET / PERMUTE / PatternExclude | CLI flink-2.3.0 | all valid=true | ✓ PASS |
| Undeclared pattern variable accepted | CLI flink-2.3.0 | valid=true (no scope validation) | ✓ PASS |
| Flink-only under Doris → 009 | TUMBLE/MATCH_RECOGNIZE/WATERMARK/PK NOT ENFORCED under doris-4.x | valid=false, FATHOM-PARSE-009 | ✓ PASS |
| Whole-statement DDL under Doris → 007 | CREATE CATALOG / SHOW TABLES under doris-4.x | valid=false, FATHOM-PARSE-007 | ✓ PASS |
| Doris-only under Flink → 009 | DUPLICATE KEY / ENGINE / INTO OUTFILE / TABLESAMPLE / INSERT DISTRIBUTED under flink-2.3.0 | valid=false, FATHOM-PARSE-009 | ✓ PASS |
| Shared syntax valid in both | plain CREATE TABLE / CTE SELECT under both dialects | valid=true both (no double-valid) | ✓ PASS |
| CR-01 nested ARRAY ×150000 | CLI flink-2.3.0 | EXIT 0 (was 139 SIGSEGV) | ✓ PASS |
| CR-02 nested {- -} ×60000 | CLI flink-2.3.0 | EXIT 0 (was 139 SIGSEGV) | ✓ PASS |
| CR-04 `WITH t` | CLI flink + doris | EXIT 0 both (was 134 SIGABRT) | ✓ PASS |
| CR-03 `watermark` column | CLI doris-4.x | valid=true, 0 diags | ✓ PASS |
| MJ-01 ROW&lt;...&gt; | CLI flink-2.3.0 | ROW&lt;f1 INT,f2 STRING&gt; / ROW&lt;INT,STRING&gt; / ROW&lt;f1 DECIMAL(10,2)&gt; all valid=true | ✓ PASS |
| MJ-04 TIMESTAMP WITH TIME ZONE + AT TIME ZONE | CLI flink-2.3.0 | valid=true both | ✓ PASS |
| MN-01 ANALYZE COMPUTE STATISTICS | CLI flink-2.3.0 | valid=true both forms | ✓ PASS |
| MN-03 TVF named-arg validation | CLI flink-2.3.0 | valid names valid=true; `foo =>` → 002 | ✓ PASS |
| MN-04 SHOW COLUMNS FROM t FROM db | CLI flink-2.3.0 | valid=true | ✓ PASS |
| Full per-package test matrix | `moon test --target native --package {parser,dialect,syntax,api,test,lsp,parity}` | 9/8/4/579/146/35/570 all pass | ✓ PASS |
| Doris zero-drift | `git diff --name-only -- parity/__snapshot__` | 0 non-flink files | ✓ PASS |
| Provenance validator | `python3 scripts/extract_flink_grammar.py` | exit 0, 97 manifest rows | ✓ PASS |

### Probe Execution

| Probe | Command | Result | Status |
| ----- | ------- | ------ | ------ |
| No phase-declared `scripts/*/tests/probe-*.sh` scripts exist | `find scripts -name 'probe-*.sh'` | none found | SKIPPED (no probe scripts; verification used CLI smoke + fixture/parity execution) |
| extract_flink_grammar.py provenance validator (plan-declared runnable check) | `python3 scripts/extract_flink_grammar.py` | exit 0: "13 production line refs verified ... 97 flink-grammar manifest rows verified" | PASS |
| extract_flink_lexical.py (Calcite-base reserved carve-out) | `python3 scripts/extract_flink_lexical.py` | exit 0 (147 inlined rows) | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| FLINK-02 | 11-01, 11-02 | Core queries + DML (INSERT/UPSERT/UPDATE/DELETE) + EXPLAIN/SHOW/DESCRIBE/ANALYZE + expressions/types with recoverable diagnostics | ✓ SATISFIED | CLI smoke + `flink-grammar.select-*/insert-*/update-*/delete-*/explain-*/show-*/describe-*/analyze-*/cast-*/row-ctor/array-ctor/named-arg` fixtures pass |
| FLINK-03 | 11-03 | Catalog/DATABASE/TABLE/VIEW/FUNCTION DDL as structured CST statement families | ✓ SATISFIED | CLI CREATE/ALTER/DROP CATALOG/DATABASE/VIEW/FUNCTION valid=true; `flink-grammar.create-*/drop-*/alter-*` fixtures pass; whole-statement 007 under Doris |
| FLINK-04 | 11-03 | CREATE TABLE physical/metadata/computed/WATERMARK/PK NOT ENFORCED/PARTITIONED/distribution/WITH/LIKE/AS forms with token spelling/trivia/spans | ✓ SATISFIED | CLI full complex form valid=true; `flink-grammar.create-table-*` fixtures (columns/typed/watermark-second/pk-enforced/full-clauses/like/as/with-as/negative gates) pass |
| FLINK-05 | 11-04 | Window TVF TUMBLE/HOP/CUMULATE/SESSION with TABLE/DESCRIPTOR/interval/named args/window output columns | ✓ SATISFIED | CLI TUMBLE/HOP/CUMULATE valid=true; `flink-grammar.tvf-*` fixtures pass; 009 under Doris |
| FLINK-06 | 11-04 | Syntax-level MATCH_RECOGNIZE CST/diagnostics (PATTERN/DEFINE/MEASURES/skip/variables/quantifiers); no planner/execution equivalence | ✓ SATISFIED | CLI full MR + anchors + quantifiers + WITHIN + SUBSET + PERMUTE valid=true; undeclared var accepted; `flink-grammar.match-recognize-*` fixtures pass |
| CST-01 | 11-01, 11-02, 11-03, 11-04 | Strict/editor recoverable lossless CST — comments/whitespace/newlines/unknown/error/missing/skipped/bytes/spans round-trip without loss | ✓ SATISFIED | 160 lossless assertions pass in both modes; crash-safety bounded (no SIGSEGV/SIGABRT); zero-drift gate |

**Orphaned requirements:** None — all 6 phase-11 requirements (FLINK-02..06, CST-01) are claimed by 11-01..11-04 plans and verified.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| parser/flink_grammar.mbt, parser/parser.mbt | — | Debt markers (TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER) | ℹ️ None found | 0 matches in phase-modified parser files |
| — | — | Empty/stub returns, hardcoded-empty data, props-wired-empty | ℹ️ None found | All productions parse real input into source-backed CST; no placeholder bodies |
| `binding/moon.pkg` (Phase 10, not phase 11) | — | `moon test --target native` full-repo fails to compile `binding` foreign_library (`#export_name` toolchain-version mismatch, error 4219) | ℹ️ Pre-existing (IN-04 family) | Does not affect phase-11 packages: per-package matrix (parser/dialect/syntax/api/test/lsp/parity) all pass; `binding` was last touched in Phase 10 (commit aa280db) and is a JS/Wasm facade package |
| `parser/parser.mbt` `argument_list_has_arrow` (714-745) | — | O(n) pre-scan per function call (both dialects) | ℹ️ Accepted by review (IN-02) | Behavior-neutral on valid Doris input; shared hot path — accepted, no change |

### Human Verification Required

The following items could not be closed programmatically. Per the honest-verifier protocol, the backstop probe truths abstain when explicit behavioral evidence is absent. All 24 other must-haves are verified with codebase evidence.

1. **MATCH_RECOGNIZE supported/known-limitation subset boundary (FLINK-06 unclassified probe)**
   - **Test:** Review the frozen subset boundary (SUBSET, PERMUTE, `{- ... -}` PatternExclude parse structurally and are classified known-limitation; no pattern-variable column-scope/type validation) against the pinned Flink/Calcite release grammar (Parser.jj:3062-3346).
   - **Expected:** The known-limitation classification matches the pinned grammar's syntactic acceptance; "syntactically valid input is never rejected for undeclared variables" is the intended freeze.
   - **Why human:** The FLINK-06 probe was explicitly flagged "unclassified — requires manual review" (no repository analog); the subset freeze is a judgment call against pinned grammar line refs that fixtures cannot fully substitute for.

2. **FLINK-02 concurrency isolation**
   - **Test:** Run two parses of different Flink inputs concurrently; confirm each returns the byte-identical serialized result it returns in isolation.
   - **Expected:** Concurrent parses equal serial parses; no recovery state interleaves.
   - **Why human:** Per-parse RecoveryState is a by-construction guarantee visible in source; no test in the suite executes concurrent parses (multi-statement fixtures pin statement-level, not thread-level, isolation).

3. **FLINK-03 concurrency isolation (Flink DDL parser)**
   - **Test:** Concurrently parse Flink DDL statements and confirm results equal serial parses.
   - **Expected:** Byte-identical serialized CST/diagnostics per input; per-parse state.
   - **Why human:** Same by-construction guarantee as #2; no concurrent-execution test exists.

4. **FLINK-04 concurrency isolation (CREATE TABLE body parser)**
   - **Test:** Concurrently parse the same CREATE TABLE complex forms and confirm results equal serial parses.
   - **Expected:** Byte-identical serialized CST/diagnostics per input.
   - **Why human:** Same by-construction guarantee; no concurrent-execution test exists.

### Gaps Summary

**No gaps found.** No must-have truth FAILED, no artifact MISSING/STUB/ORPHANED/HOLLOW, no key link NOT_WIRED, and no blocker anti-pattern. The phase goal is achieved:

- **FLINK-02..06 + CST-01 all satisfied** with real, source-backed, recoverable CST and stable diagnostics.
- **Crash-safety proven:** the 4 review BLOCKERs (nested-generic/PatternExclude SIGSEGV, `WITH t` SIGABRT, `watermark` Doris regression) and 4 MAJORs (ROW&lt;...&gt;, SUBSET order, non-reserved column hijacking, WITH TIME ZONE/AT TIME ZONE) are fixed and verified via re-run of the original repros.
- **Doris zero-drift:** parity 570/570 without `--update`; 0 doris-named snapshot diffs.
- **Bidirectional negative gates** verified both directions with FATHOM-PARSE-009/007; shared syntax valid in both dialects (no double-valid).

The only open items are **human-verification** (4 items): the FLINK-06 subset-boundary manual review and 3 concurrency-isolation probes that are safe by construction but not exercised by any concurrent test. These are not code defects — the code is present, wired, and behaviorally correct in every tested dimension.

---

_Verified: 2026-08-09T10:56:47Z_
_Verifier: Claude (gsd-verifier)_
