---
phase: 11-flink-grammar-and-recoverable-cst
plan: 01
subsystem: parser
tags: [flink, grammar, select, cte, join, aggregation, set-operations, cst, recovery, moonbit, snapshot, dialect-gate]

# Dependency graph
requires:
  - phase: 10-flink-release-profiles-and-lexical-core
    provides: "FlinkProfile closed enum + FlinkProfileMetadata (calcite pins 1.36.0/1.34.0/1.32.0), flink_classification_rows (142 rows, release-grammar source), flink-lexical snapshot namespace, validate_dialect_profile gate, FATHOM-PARSE-008 not-implemented Flink route"
provides:
  - "Real parse_flink_segment keyword-first dispatch (SELECT/WITH via with_prefix_verb) routing through the Flink-safe query path; unknown starters -> FATHOM-PARSE-007 (D-06, FATHOM-PARSE-008 retired and vacant)"
  - "parser/flink_grammar.mbt parse_flink_query + parse_flink_select_core: Flink-safe SELECT/CTE/JOIN/aggregation plus the Calcite CompoundQuery set-op loop (UNION/INTERSECT/EXCEPT + ALL/DISTINCT, Parser-calcite-1.36.0.jj:3395)"
  - "precedence(context, cursor) dialect policy table: Doris arm byte-identical, Flink arm adds || CONCAT (A3, Parser-calcite-1.36.0.jj:8793)"
  - "add_dialect_gate_diagnostic (FATHOM-PARSE-009, D-04): construct-level bidirectional negative gate at Doris-only construct points (INTO OUTFILE, QUALIFY, PARTITION/TABLET/SAMPLE/TABLESAMPLE/REPEATABLE)"
  - "MATCH_RECOGNIZE + MATCH_NUMBER/MEASURES/PATTERN/DEFINE Calcite-base reserved rows (Pitfall 9) visible under every Flink profile; classification tests"
  - "D-02 one-way CST contract surface: 22 SyntaxKind variants appended at the enum end + snake_case kind_id wire strings"
  - "flink-grammar snapshot namespace (flink-grammar.{fixture}.flink-2.3.0.{strict,editor}.json) with provenance manifest and scripts/extract_flink_grammar.py line-ref validator"
affects: [11-02, 11-03, 11-04, 11-05, 12-cross-dialect-corpus-and-parity-gates, 13-toolchain-and-editor-packaging]

# Actuals (#2632) — pairs with the plan's `estimate` (52000) to calibrate future estimates.
# Same estimateTokens scale (chars/4 over the realized diff), never a harness token count.
actuals:
  tokens: 39439
  tasks: 4
  commits: 4

# Tech tracking
tech-stack:
  added:
    - "parser/flink_grammar.mbt (Flink statement-family productions, same parser package)"
    - "scripts/extract_flink_grammar.py (Python stdlib production line-ref validator)"
    - "FATHOM-PARSE-009 diagnostic code (construct-level dialect-gate rejection)"
  patterns:
    - "Keyword-first dispatch copied from parse_doris_segment; shared query skeleton under dialect gates (D-04/D-06)"
    - "precedence(context, cursor) dialect policy table — Doris arm verbatim, Flink arm layered (Pattern 4, Pitfall 7)"
    - "Independent flink-grammar snapshot namespace under the D-08 parity gate (D-05)"
    - "Calcite-base-only reserved rows with extract_flink_grammar.py provenance validation (Pitfall 9)"

key-files:
  created:
    - "parser/flink_grammar.mbt"
    - "scripts/extract_flink_grammar.py"
    - "parity/fixtures/flink-grammar/manifest.tsv"
    - "parity/flink_grammar_test.mbt"
    - "parity/__snapshot__/flink-grammar.{fixture}.flink-2.3.0.{strict,editor}.json (14 files)"
    - ".planning/phases/11-flink-grammar-and-recoverable-cst/approved-changes.md"
  modified:
    - "parser/parser.mbt (parse_flink_segment real dispatch, precedence(context,cursor), add_dialect_gate_diagnostic, dialect gates, 008 test rewrite)"
    - "dialect/flink.mbt (MATCH_RECOGNIZE-family reserved rows)"
    - "dialect/classification.mbt (MATCH_RECOGNIZE reserved tests)"
    - "syntax/syntax.mbt (22 Flink SyntaxKind variants appended)"
    - "api/api.mbt (kind_id wire strings + flink parse test rewrite)"
    - "parity/flink_lexical_test.mbt + parity/__snapshot__/flink-lexical.*.json (008 -> real-grammar re-generation)"
    - "parity/moon.pkg (printer import for lossless-replay assertions)"
    - "scripts/extract_flink_lexical.py (Calcite-base-only reserved carve-out)"
    - "test/formatter_test.mbt, parity/export_smoke_test.mbt, lsp/handlers.mbt, lsp/selection_test.mbt (008-asserting surfaces updated)"

key-decisions:
  - "D-04 locked (auto-selected option-a): mint FATHOM-PARSE-009 'syntax is not supported in the selected dialect' for construct-level dialect-gate rejection; FATHOM-PARSE-007 stays reserved for whole-statement unsupported; dialect rides in envelope metadata (D-10)"
  - "D-02 locked (auto-selected option-a): coarse per-statement-family SyntaxKind variants appended at the enum end + snake_case kind_id strings; sub-type detail rides in metadata/spans"
  - "D-06: FATHOM-PARSE-008 retired and vacant — never reused; valid Flink SQL routes through the real grammar, genuinely-unsupported whole statements route through FATHOM-PARSE-007"
  - "MATCH_RECOGNIZE/MATCH_NUMBER/MEASURES/PATTERN/DEFINE are Calcite-base reserved tokens present in all three pinned releases (Pitfall 9), so they classify Reserved under every Flink profile (introduced_profile flink-1.20.5)"
  - "=> (NAMED_ARGUMENT_ASSIGNMENT) consumption deferred to 11-02 (function-call argument layer); the Flink precedence arm only adds || CONCAT per the tracer's acceptance"

patterns-established:
  - "Pattern 1: parse_flink_segment keyword-first dispatch (D-04/D-06) — SELECT/WITH -> parse_flink_query, unknown -> unsupported_statement (007)"
  - "Pattern 2: shared query skeleton under dialect gates — parse_select_core/parse_table_ref/parse_cte_prefix reject Doris-only constructs with FATHOM-PARSE-009 under Flink while the Doris arm stays byte-identical (Pitfall 1/7)"
  - "Pattern 3: precedence(context, cursor) dialect policy table (Pattern 4, RESEARCH §7)"
  - "Pattern 4: Calcite-base-only reserved rows + extract_flink_grammar.py provenance validation (Pitfall 9)"
  - "Pattern 5: flink-grammar independent snapshot namespace + approved-changes register (D-05/D-08)"

requirements-completed: [FLINK-02, CST-01]

coverage:
  - id: D1
    description: "Real parse_flink_segment dispatch + Flink SELECT path: SELECT/WITH through parse_flink_query (shared Flink-safe query skeleton); valid Flink SELECT with CTE+JOIN+aggregation parses valid=true into a Select CST node with no FATHOM-PARSE-008"
    requirement: FLINK-02
    verification:
      - kind: e2e
        ref: "fathom-sql parse --dialect flink --profile flink-2.3.0 on the tracer SQL (exit 0, dialect=flink/profile=flink-2.3.0/valid=true, no 008)"
        status: pass
      - kind: unit
        ref: "parser/parser.mbt#parser_flink_context_parses_select"
        status: pass
    human_judgment: false
  - id: D2
    description: "Set operations (FLINK-02): UNION [ALL]/INTERSECT [ALL]/EXCEPT [ALL] parse valid=true through the CompoundQuery set-op loop (Parser-calcite-1.36.0.jj:3395); flink-grammar set-operation fixtures frozen in strict/editor modes"
    requirement: FLINK-02
    verification:
      - kind: integration
        ref: "parity/flink_grammar_test.mbt (set-union-all/set-intersect/set-except/set-intersect-all/set-except-all snapshots)"
        status: pass
      - kind: e2e
        ref: "CLI UNION ALL / INTERSECT / EXCEPT parse valid=true under flink-2.3.0"
        status: pass
    human_judgment: false
  - id: D3
    description: "Bidirectional dialect-negative gate (D-04): Doris-only SELECT constructs (INTO OUTFILE, QUALIFY, TABLESAMPLE, SAMPLE, TABLET, PARTITION table option, REPEATABLE) reject with FATHOM-PARSE-009 + valid=false under Flink while the same SQL under Doris parses exactly as the frozen baseline"
    requirement: FLINK-02
    verification:
      - kind: e2e
        ref: "CLI: SELECT * FROM t INTO OUTFILE 'x' and TABLESAMPLE(10) under flink -> FATHOM-PARSE-009; same under doris-4.x valid=true"
        status: pass
    human_judgment: false
  - id: D4
    description: "MATCH_RECOGNIZE + MATCH_NUMBER/MEASURES/PATTERN/DEFINE Calcite-base reserved rows (Pitfall 9): Reserved under every Flink profile (flink-2.3.0/2.1.3/1.20.5); backtick-quoted SELECT `MATCH_RECOGNIZE` parses as an identifier, unquoted is rejected"
    requirement: FLINK-02
    verification:
      - kind: unit
        ref: "dialect/classification.mbt#classification_is_dialect_independent_and_release_aware"
        status: pass
      - kind: e2e
        ref: "CLI: SELECT `MATCH_RECOGNIZE` FROM t valid=true; SELECT MATCH_RECOGNIZE FROM t rejected"
        status: pass
    human_judgment: false
  - id: D5
    description: "FATHOM-PARSE-008 retirement (D-06): code vacant and never reused; no valid Flink statement produces it; flink-lexical assertions/snapshots re-generated to real-grammar expectations; parser/api/export/formatter/lsp 008-asserting surfaces updated together"
    requirement: FLINK-02
    verification:
      - kind: integration
        ref: "moon test --target native --package parser --package dialect --package api --package lsp --package test (311+35+146 passed)"
        status: pass
    human_judgment: false
  - id: D6
    description: "D-02 CST contract surface: 22 Flink SyntaxKind variants appended at the enum end (existing ordinals preserved) + matching snake_case kind_id wire strings; exhaustive match proves the surface is complete"
    requirement: CST-01
    verification:
      - kind: unit
        ref: "moon test --target native --package syntax --package api (294 passed)"
        status: pass
    human_judgment: false
  - id: D7
    description: "flink-grammar snapshot namespace + provenance: parity/fixtures/flink-grammar/manifest.tsv (sha512/tag/commit/grammar_path), scripts/extract_flink_grammar.py validates production line refs against the pinned Parser-calcite files (exit 1 on a deliberately wrong ref); Doris 213-snapshot baseline byte-identical"
    requirement: CST-01
    verification:
      - kind: other
        ref: "python3 scripts/extract_flink_grammar.py (exit 0, ok line); deliberately wrong ref exit 1"
        status: pass
      - kind: integration
        ref: "moon test --package parity (281 passed, no --update); git diff --name-only -- parity/__snapshot__ shows only flink-(grammar|lexical).* files"
        status: pass
    human_judgment: false
  - id: D8
    description: "CST-01 lossless replay: print_lossless(parse(x)) == x byte-exact for every flink-grammar positive and recovery fixture in strict and editor modes; incomplete SELECT yields a bounded Missing/Error node under the shared recovery budget"
    requirement: CST-01
    verification:
      - kind: unit
        ref: "parity/flink_grammar_test.mbt#flink_grammar_select_cte_join_agg_lossless + select_incomplete_lossless + set_*_lossless"
        status: pass
    human_judgment: false

# Metrics
duration: 92min
completed: 2026-08-09
status: complete
---

# Phase 11 Plan 1: Flink Grammar and Recoverable CST — Summary

**Real Flink SELECT grammar through a keyword-first `parse_flink_segment` dispatch — CTE+JOIN+aggregation and UNION/INTERSECT/EXCEPT set-ops parse to a lossless recoverable CST under `fathom-sql parse --dialect flink --profile flink-2.3.0`, with the FATHOM-PARSE-009 bidirectional dialect gate, MATCH_RECOGNIZE Calcite-base reserved rows, and the D-02 SyntaxKind/kind_id contract surface — while the Doris 213-snapshot baseline stays byte-identical.**

## Performance

- **Duration:** ~92 min
- **Started:** 2026-08-09T07:55:00Z
- **Completed:** 2026-08-09T09:27:00Z
- **Tasks:** 4 (2 checkpoint decisions auto-selected + tracer + CST-surface/auto)
- **Files modified:** 45 (16 source + 28 snapshots + 1 register)

## Accomplishments
- **Real Flink SELECT path (FLINK-02, D-06):** `parse_flink_segment` is now a keyword-first dispatcher (SELECT/WITH via `with_prefix_verb`); `parser/flink_grammar.mbt` `parse_flink_query` + `parse_flink_select_core` run the shared query skeleton's Flink-safe subset. The tracer SQL (`WITH o AS (...) SELECT u.name, SUM(o.amount) AS total FROM o JOIN users u ON ... GROUP BY u.name`) parses valid=true into a Select CST node — FATHOM-PARSE-008 is retired and vacant.
- **Set operations (FLINK-02):** `UNION [ALL] / INTERSECT [ALL] / EXCEPT [ALL]` parse valid=true through the Calcite CompoundQuery loop (Parser-calcite-1.36.0.jj:3395) — the shared `parse_query` only handled UNION, so the Flink query entry layers INTERSECT/EXCEPT.
- **`precedence(context, cursor)` dialect policy table (Pattern 4):** the Doris arm returns the frozen v1 table byte-identically; the Flink arm adds `||` CONCAT (Parser-calcite-1.36.0.jj:8793) at A3. `=>` (named-argument assignment) consumption is deferred to 11-02 per the plan's must-have scope.
- **Bidirectional negative gate (D-04, FATHOM-PARSE-009):** `add_dialect_gate_diagnostic` rejects Doris-only SELECT constructs (INTO OUTFILE, QUALIFY, PARTITION/TABLET/SAMPLE/TABLESAMPLE/REPEATABLE) under Flink — `SELECT * FROM t INTO OUTFILE 'x'` and `TABLESAMPLE(10)` both emit FATHOM-PARSE-009 with valid=false, while the identical SQL under doris-4.x parses exactly as the frozen baseline.
- **MATCH_RECOGNIZE reserved rows (Pitfall 9):** `MATCH_RECOGNIZE` + `MATCH_NUMBER`/`MEASURES`/`PATTERN`/`DEFINE` are Calcite-base reserved tokens present in all three pinned releases; they classify Reserved under every Flink profile. Backtick-quoted `` `MATCH_RECOGNIZE` `` parses as an identifier; unquoted is rejected.
- **D-02 CST contract surface (one-way):** 22 Flink SyntaxKind variants appended at the enum END (existing ordinals preserved — Doris wire output never shifts) + matching snake_case `kind_id` strings; the exhaustive match proves completeness.
- **flink-grammar snapshot namespace + provenance (D-05):** 14 goldens (`select-cte-join-agg`, `select-incomplete`, `set-union-all`, `set-intersect`, `set-except`, `set-intersect-all`, `set-except-all` × strict/editor) with `parity/fixtures/flink-grammar/manifest.tsv` provenance and `scripts/extract_flink_grammar.py` validating production line refs against the pinned Parser-calcite files.
- **CST-01 lossless replay:** every positive and recovery fixture asserts `print_lossless(parse(x)) == x` byte-exact in both strict and editor modes; the incomplete `SELECT a, b FROM t WHERE` yields a bounded Missing/Error node under the shared recovery budget.

## Task Commits

Each task was committed atomically:

1. **Task 1: Confirm D-04 dialect-gate diagnostic family (checkpoint decision)** — auto-selected option-a (mint FATHOM-PARSE-009)
2. **Task 2: Confirm D-02 CST statement-family shape (checkpoint decision)** — auto-selected option-a (coarse kinds)
3. **Task 3 (tracer): End-to-end Flink SELECT through real parse_flink_segment dispatch** - `ba53559` (feat) + `06956ed` (test: flink-lexical snapshot re-generation)
4. **Task 4: D-02 CST contract surface + flink-grammar snapshot namespace + register** - `0653c75` (feat) + `154e887` (test: flink-grammar snapshots)

**Plan metadata:** pending final docs commit

## Files Created/Modified
- `parser/parser.mbt` - parse_flink_segment real dispatch (D-06); precedence(context,cursor) + precedence_doris/precedence_flink; add_dialect_gate_diagnostic (FATHOM-PARSE-009); dialect gates in parse_select_core (EXCEPT/QUALIFY/INTO), parse_table_ref (Doris-only table options), parse_cte_prefix (WITH RECURSIVE); parser 008 test rewritten
- `parser/flink_grammar.mbt` - parse_flink_query + parse_flink_select_core (Flink-safe SELECT/CTE/JOIN/aggregation + set-op loop)
- `dialect/flink.mbt` - MATCH_RECOGNIZE + MATCH_NUMBER/MEASURES/PATTERN/DEFINE reserved rows (flink-1.20.5 baseline, Parser-calcite-1.32.0.jj line refs)
- `dialect/classification.mbt` - MATCH_RECOGNIZE-family reserved test assertions
- `syntax/syntax.mbt` - 22 Flink SyntaxKind variants appended at the enum end
- `api/api.mbt` - 22 kind_id wire strings; flink parse test rewritten (real grammar)
- `parity/flink_lexical_test.mbt` + `parity/__snapshot__/flink-lexical.*.json` - 008 assertions/snapshots -> real-grammar expectations (hash-comment -> 007, double-quote -> 002, slash-comment/backtick valid=true)
- `parity/flink_grammar_test.mbt` - FlinkGrammarFixture + snapshot harness + 7 fixtures with lossless assertions
- `parity/fixtures/flink-grammar/manifest.tsv` - provenance rows (sha512/tag/commit/grammar_path)
- `parity/moon.pkg` - printer import for lossless-replay assertions
- `scripts/extract_flink_grammar.py` - production line-ref validator (exit 1 on wrong ref)
- `scripts/extract_flink_lexical.py` - Calcite-base-only reserved carve-out (MATCH_RECOGNIZE/MATCH_NUMBER)
- `test/formatter_test.mbt`, `parity/export_smoke_test.mbt`, `lsp/handlers.mbt`, `lsp/selection_test.mbt` - 008-asserting surfaces updated to the real grammar
- `.planning/phases/11-flink-grammar-and-recoverable-cst/approved-changes.md` - D-08 register (008 retirement, 009 minting, flink-grammar namespace, flink-lexical re-generation)

## Decisions Made
- **D-04 locked (auto-selected option-a):** mint FATHOM-PARSE-009 "syntax is not supported in the selected dialect" for construct-level dialect-gate rejection; FATHOM-PARSE-007 stays reserved for whole-statement unsupported; the dialect rides in the parse envelope metadata (D-10), never in the code prefix.
- **D-02 locked (auto-selected option-a):** coarse per-statement-family SyntaxKind variants appended at the enum end + snake_case kind_id strings; statement sub-types (SHOW TABLES vs SHOW CATALOGS) ride in node metadata/spans.
- **D-06:** FATHOM-PARSE-008 retired and vacant — never reused; valid Flink SQL routes through the real grammar; genuinely-unsupported whole statements (e.g. CREATE TABLE, DDL) route through FATHOM-PARSE-007.
- **MATCH_RECOGNIZE-family rows:** present in all three pinned releases (Calcite 1.32.0/1.34.0/1.36.0), so introduced_profile flink-1.20.5 makes them Reserved under every Flink profile (acceptance requires flink-2.3.0/2.1.3/1.20.5).
- **`=>` deferred to 11-02:** the Flink precedence arm adds only `||` CONCAT; named-argument `=>` consumption at the function-call argument layer lands with the expression breadth in 11-02 (plan must-have scope).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated 008-asserting surfaces beyond the plan's file list**
- **Found during:** Task 3 (tracer)
- **Issue:** `moon test --package api` (which transitively runs parity tests) plus the formatter and LSP suites assert the retired FATHOM-PARSE-008 route — `api_parse_flink_not_implemented_gates_profiles_and_carries_metadata`, `test/formatter_test.mbt formatter_dialect_selection_is_validated_first`, `lsp/selection_test.mbt` (h)/(j), `parity/export_smoke_test.mbt` (c)/(d). Leaving them would break the shared test suite after the 008 retirement.
- **Fix:** Rewrote each to the real-grammar expectations (valid Flink SELECT parses valid=true with zero diagnostics; LSP publishes an empty diagnostics array; the formatter accepts valid Flink trees). The api flink entry's doc comment was updated; the function name `parse_flink_not_implemented` is retained as a historical LSP call-site artifact (renaming would touch lsp/handlers.mbt beyond this wave's scope).
- **Files modified:** api/api.mbt, test/formatter_test.mbt, lsp/handlers.mbt, lsp/selection_test.mbt, parity/export_smoke_test.mbt
- **Verification:** `moon test --target native --package api --package test --package lsp` all pass (311/146/35).
- **Committed in:** ba53559 (part of Task 3 commit)

**2. [Rule 3 - Blocking] extract_flink_lexical.py carve-out for Calcite-base-only reserved rows**
- **Found during:** Task 3 (dialect rows)
- **Issue:** the existing `scripts/extract_flink_lexical.py` validates every inlined `flink_classification_rows` word against the committed Parser.tdd-derived reserved lists. `MATCH_RECOGNIZE` and `MATCH_NUMBER` are valid Calcite base tokens (generated Parser.jj) absent from those lists — the script would exit 1 on the new rows.
- **Fix:** added `CALCITE_BASE_ONLY_RESERVED = {"MATCH_RECOGNIZE", "MATCH_NUMBER"}` carve-out: these words skip the Parser.tdd presence check and are instead validated by `scripts/extract_flink_grammar.py` against the pinned Parser-calcite token lines (Pitfall 9 provenance ownership).
- **Files modified:** scripts/extract_flink_lexical.py
- **Verification:** `python3 scripts/extract_flink_lexical.py` exits 0 (147 inlined rows).
- **Committed in:** ba53559 (part of Task 3 commit)

**3. [Rule 3 - Blocking] Renamed duplicate snapshot helper in the parity package**
- **Found during:** Task 4 (flink_grammar_test.mbt)
- **Issue:** `flink_snapshot_test` is already defined in `parity/flink_lexical_test.mbt` (same package) — the new file's helper collided.
- **Fix:** renamed to `flink_grammar_snapshot_test` (analogous to the Phase 10 duplicate-helper fix).
- **Files modified:** parity/flink_grammar_test.mbt
- **Verification:** `moon check --target native parity` passes.
- **Committed in:** 0653c75 (part of Task 4 commit)

---

**Total deviations:** 3 auto-fixed (all Rule 3 blocking). None required user approval; no scope creep — each was necessary to keep the shared suite green after the 008 retirement / new rows / new test file.
**Impact on plan:** All fixes are correctness/maintainability adjustments consistent with the plan's D-06 clean-cutover and Pitfall-9 intents.

## Issues Encountered
- **`moon build --target native --release` full build link failure (`undefined reference to main`)** — pre-existing project quirk (verified at the pre-phase-11 base commit `6c12ea2` and in `deferred-items.md`): the module root is a library and the whole-repo build tries to link it as an executable. Not caused by this plan. The `fathom-sql` CLI builds individually (`moon build --target native --release fathom-sql`), and all CLI acceptance checks pass against the built exe. The plan's Task 3 verify line uses the root build; I ran the equivalent package-scoped build + the full CLI check chain instead.
- **Stale flink-lexical snapshots mid-wave:** after the parser change, the 14 flink-lexical snapshot tests fail until the `--update` (the plan's intended ordering — the register entry is committed before the single `--update`). The Task 3 code commit and the snapshot regeneration commit are separated accordingly.

## Known Stubs

None in the parser/CST path. Deliberate deferrals documented for the verifier:
- `=>` (NAMED_ARGUMENT_ASSIGNMENT) consumption at the function-call argument layer — deferred to 11-02 (plan must-have scope; the tracer's Flink precedence arm only adds `||`).
- LSP formatting of real Flink trees: `lsp/handlers.mbt` still returns the -32603 "flink grammar is not yet implemented" refusal for flink documents (MI-06). This is an intentional LSP-surface decision outside this wave's file scope; the change lands with the Phase 13 toolchain wave (TOOL-01..03). The parse path over LSP now publishes real-grammar (empty) diagnostics.

## Next Phase Readiness
- **11-02** can build INSERT/UPSERT/UPDATE/DELETE, EXPLAIN/SHOW/DESCRIBE/ANALYZE, and the full bidirectional negative-gate matrix on the real `parse_flink_segment` dispatch + FATHOM-PARSE-009 helper + D-02 SyntaxKind/kind_id surface + flink-grammar snapshot harness.
- **11-03..11-05** consume the same statement-entry, CST-surface, and snapshot-namespace contracts for Catalog/DDL, CREATE TABLE complex forms, Window TVF, and MATCH_RECOGNIZE (whose reserved rows and MatchRecognize kind are already locked).
- **12** reuses the flink-grammar namespace and `scripts/extract_flink_grammar.py` provenance pattern for the cross-dialect corpus/parity gates.
- The `precedence(context, cursor)` policy table and `add_dialect_gate_diagnostic` are the reusable seams for all remaining Flink expression/type and negative-gate work.

## Self-Check: PASSED

- Files verified: 11-01-SUMMARY.md, parser/flink_grammar.mbt, parity/flink_grammar_test.mbt, parity/fixtures/flink-grammar/manifest.tsv, scripts/extract_flink_grammar.py, approved-changes.md
- Commits verified: ba53559, 06956ed, 0653c75, 154e887 (git log --oneline)
- Doris baseline: `moon test --package parity` 281/281 without --update; `git diff --name-only -- parity/__snapshot__` shows only flink-(grammar|lexical).* files (zero doris drift)
- Full suite: parser/dialect/syntax/api 311, parity 281, lsp 35, test 146 — all passing

---
*Phase: 11-flink-grammar-and-recoverable-cst*
*Completed: 2026-08-09*
