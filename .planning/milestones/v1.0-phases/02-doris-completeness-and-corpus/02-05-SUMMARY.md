---
phase: 02-doris-completeness-and-corpus
plan: 05
subsystem: api
tags: [moonbit, analyzer, catalog, statement-accessors, d-21, d-22, d-23, d-24, anly-01]
requires:
  - phase: 02-01
    provides: DML statement kinds (Insert/Update/Delete/Merge) with Statement wrappers and monotonic statement_id
  - phase: 02-02
    provides: DDL CreateTable kind and per-family clause sync sets
provides:
  - Independent analyzer/ moon package (imports syntax read views only; parser core has zero dependency on it — D-21)
  - Minimal table→column Catalog trait/record (ColumnInfo, TableInfo, StaticCatalog with case-sensitive lookup — D-22)
  - ParseResult::statement / ParseResult::statement_diagnostics statement-level accessors by statement_id (D-23)
  - resolve_table_references: name-resolution-level target-table demo over syntax read views with injected catalog
  - Interface + docs + minimal implementation only; full ANAL-01 resolution documented as v2 (D-24)
affects: [02-06, phase-03, ship, verify-work]
actuals:
  tokens: 5567   # chars/4 over the realized diff (22267 chars added)
  tasks: 3
  commits: 3
tech-stack:
  added: []
  patterns:
    - "New-package manifest: pkgtype(kind: \"library\") + explicit import list, mirroring parser/moon.pkg"
    - "Open trait for injectable catalog: pub(open) trait with `table(Self, String)`; generic constraint `fn[T : Catalog]` (new trait system)"
    - "pub(all) struct for records consumers must construct cross-package (repo precedent: pub(all) struct Token)"
    - "Analyzer boundary: consumes only syntax read views + caller-supplied source bytes; never parser/token/lexer/api"
key-files:
  created:
    - analyzer/moon.pkg
    - analyzer/analyzer.mbt
    - test/analyzer_test.mbt
  modified:
    - api/api.mbt
    - test/moon.pkg
key-decisions:
  - "D-21 add-alongside: analyzer/ is an independent library importing only fathom/doris-sql/syntax; parser core import list (source, token, lexer, syntax) unchanged and enforced by a negative gate"
  - "D-22 minimal catalog: ColumnInfo { name, data_type }, TableInfo { name, columns }, open trait Catalog { table(Self, String) -> TableInfo? }, StaticCatalog backed by Map with case-sensitive keys (documented), last-wins on duplicate names"
  - "D-23 statement entry: ParseResult::statement(statement_id) returns the id-th Statement node (non-statement root children never consume ids); statement_diagnostics filters by statement_id preserving source order"
  - "D-24 scope: interface + docs + minimal implementation only; full ANAL-01 name resolution and type diagnostics are v2, stated in package doc comments"
  - "Resolver text extraction requires caller-supplied source bytes because CST nodes never own source bytes (syntax.mbt invariant); signature is resolve_table_references(node, source_bytes, catalog)"
  - "UTF-8 identifier decode implemented locally (Char::from_int + String::from_iter) to keep the analyzer import list at exactly one fathom package"
patterns-established:
  - "Analyzer boundary pattern: read-only CST walk + injected catalog; missing tables are simply absent (no diagnostics, no type inference)"
  - "Leading-keyword prefix scan per statement kind (case-insensitive) then qualified-name capture (identifier [. identifier]*)"
  - "Statement-level accessor pattern: id-th Statement node walk, trivia/skipped root children never consume ids"
requirements-completed: [ANLY-01]
coverage:
  - id: D1
    description: "Independent analyzer/ package with Catalog trait and StaticCatalog (hit/miss/empty lookup), zero parser coupling (D-21, D-22)"
    requirement: ANLY-01
    verification:
      - kind: unit
        ref: "test/analyzer_test.mbt#analyzer_catalog_lookup_hits_and_misses"
        status: pass
      - kind: unit
        ref: "test/analyzer_test.mbt#analyzer_empty_catalog_lookup_returns_none"
        status: pass
      - kind: unit
        ref: "test/analyzer_test.mbt#analyzer_catalog_trait_dispatches_to_static_catalog"
        status: pass
      - kind: unit
        ref: "test/analyzer_test.mbt#analyzer_syntax_only_path_is_unchanged_by_catalog"
        status: pass
    human_judgment: false
  - id: D2
    description: "Statement-level accessors ParseResult::statement / statement_diagnostics by statement_id with per-id node/diagnostic isolation (D-23, DORIS-03 path)"
    requirement: ANLY-01
    verification:
      - kind: unit
        ref: "test/analyzer_test.mbt#analyzer_statement_accessors_isolate_nodes_and_diagnostics_by_id"
        status: pass
      - kind: unit
        ref: "test/analyzer_test.mbt#analyzer_statement_accessors_on_empty_document"
        status: pass
      - kind: unit
        ref: "test/analyzer_test.mbt#analyzer_statement_diagnostics_stay_ordered_by_source_position"
        status: pass
    human_judgment: false
  - id: D3
    description: "resolve_table_references resolves DML/DDL target tables against an injected catalog over syntax read views; identical syntax results with and without a catalog (D-22, ANLY-01)"
    requirement: ANLY-01
    verification:
      - kind: unit
        ref: "test/analyzer_test.mbt#analyzer_resolve_table_references_against_injected_catalog"
        status: pass
      - kind: unit
        ref: "test/analyzer_test.mbt#analyzer_resolve_table_references_empty_catalog_and_no_statements"
        status: pass
    human_judgment: false
duration: 15min
completed: 2026-08-04
status: complete
---

# Phase 02 Plan 05: Analyzer Package, Catalog, and Statement-Level Accessors

**Independent `analyzer/` MoonBit package with a minimal table→column Catalog trait/StaticCatalog (D-21/D-22), statement-level `ParseResult` accessors by `statement_id` (D-23), and a name-resolution demo over syntax read views — all alongside an unchanged, catalog-free syntax-only parse path (ANLY-01), with interface + docs + minimal implementation only (D-24).**

## Performance

- **Duration:** 15 min
- **Started:** 2026-08-04T04:57:29Z
- **Completed:** 2026-08-04T05:12:13Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments
- Analyzer package scaffold: `analyzer/moon.pkg` (library, imports only `fathom/doris-sql/syntax`) + `analyzer/analyzer.mbt` with `ColumnInfo`, `TableInfo`, open `Catalog` trait, `StaticCatalog` (case-sensitive keys, last-wins), and boundary doc comments; parser core import list unchanged (negative gate: no analyzer reference in parser/moon.pkg).
- Statement-level entry on the public boundary: `ParseResult::statement(statement_id)` and `ParseResult::statement_diagnostics(statement_id)` isolate node and diagnostics per statement on a mixed DML script (`insert; bad; select`) — the DORIS-03 acceptance path is directly consumable; empty documents return None; per-statement slices keep source order.
- Name-resolution demo: `resolve_table_references(node, source_bytes, catalog)` walks Statement children, extracts the target table name for Insert/Update/Delete/Merge/CreateTable via leading-keyword prefix + qualified-name scan, and returns only names present in the injected catalog; parsing with no catalog yields identical syntax results.
- Full suite green: 160 tests pass; the plan verify (`moon test && ! grep -q 'fathom/doris-sql/analyzer' parser/moon.pkg`) passes after each task.

## Task Commits

Each task was committed atomically:

1. **Task 1: Analyzer package scaffold with Catalog trait and StaticCatalog** - `94e34d8` (feat)
2. **Task 2: Statement-level accessors on ParseResult (D-23)** - `f527845` (feat)
3. **Task 3: Name-resolution demo over syntax read views with injected catalog** - `07e22eb` (feat)

**Plan metadata:** pending final docs commit.

## Files Created/Modified
- `analyzer/moon.pkg` - New independent library package; imports only `fathom/doris-sql/syntax` (D-21).
- `analyzer/analyzer.mbt` - `ColumnInfo`, `TableInfo`, open `Catalog` trait, `StaticCatalog::new/lookup`, `pub impl`, UTF-8 decoder, `resolve_table_references` with prefix scan and qualified-name capture; boundary doc comments (D-22/D-24).
- `api/api.mbt` - Additive `ParseResult::statement` and `ParseResult::statement_diagnostics`; no changes to parser, schema_version, or existing fields.
- `test/moon.pkg` - Added the analyzer import.
- `test/analyzer_test.mbt` - Catalog hit/miss/empty/trait-dispatch tests, syntax-only path unchanged by catalog, D-23 accessor tests (isolation, empty document, ordering), and end-to-end resolver tests over all five DML/DDL kinds.

## Decisions Made
- D-21 add-alongside: analyzer is a separate package; parser core keeps its exact Phase 1 import list (enforced by negative gate in verify).
- D-22 catalog shape per research sketch: minimal table→column mapping, case-sensitive keys documented, last-wins on duplicates.
- D-23 accessors keyed by `statement_id`; the id-th Statement node walk (not raw `root.children[id]`) because trivia-only segments and skipped tails never consume ids.
- D-24: only interface + docs + minimal implementation ship; ANAL-01 full name resolution and type diagnostics are v2.
- Resolver takes caller-supplied source bytes: CST nodes never own source bytes, so token text is recovered via the source slice.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Trait/generic syntax adapted to the pinned toolchain (moon 0.1.20260724, v0.10.5 line)**
- **Found during:** Task 1 (analyzer package scaffold)
- **Issue:** The research sketch's `pub trait Catalog { fn table(self, name : String) -> TableInfo? }` and `impl Catalog for StaticCatalog with table(self, name : String) ...` fail to compile on the pinned toolchain ("Partial type is not allowed in toplevel declarations", "trait, not a type", `fn f[..]` deprecated). The new trait system declares methods as `table(Self, String)`, implementations as `pub impl Trait for Type with table(self, name)` (types inferred), and uses traits via generic constraints `fn[T : Trait]` instead of trait-typed parameters. `pub struct` records are read-only cross-package; consumer-constructible records need `pub(all) struct` (repo precedent: `pub(all) struct Token`).
- **Fix:** `pub(open) trait Catalog { table(Self, String) -> TableInfo? }`, `pub impl Catalog for StaticCatalog with table(self, name) { self.lookup(name) }`, `pub(all) struct` for ColumnInfo/TableInfo, and generic-constrained resolver/helper signatures. Semantics identical to the plan.
- **Files modified:** analyzer/analyzer.mbt, test/analyzer_test.mbt
- **Verification:** 160 tests pass; catalog hit/miss/empty and trait-dispatch tests green.
- **Committed in:** 94e34d8, 07e22eb

**2. [Rule 3 - Blocking] resolve_table_references signature gains `source_bytes : Bytes`**
- **Found during:** Task 3 (name-resolution demo)
- **Issue:** The plan pins `resolve_table_references(node : @syntax.SyntaxNode, catalog : Catalog) -> Array[String]`, but CST nodes never own source bytes (syntax.mbt invariant) and `SyntaxLeaf` carries only span/text_len — the target table-name token text is unrecoverable without the source. The plan's own text says "leaf text via the source slice".
- **Fix:** Signature is `pub fn[T : Catalog] resolve_table_references(node, source_bytes : Bytes, catalog : T) -> Array[String]`; leaf text is recovered by slicing the caller-supplied source bytes at each leaf span. The analyzer still imports only syntax (Bytes is a core builtin type, not an import).
- **Files modified:** analyzer/analyzer.mbt, test/analyzer_test.mbt
- **Verification:** End-to-end resolver test resolves `t`/`t4`/`t5` and excludes absent `t2`/`t3`.
- **Committed in:** 07e22eb

**3. [Rule 3 - Blocking] Bytes→String conversion is the debug representation, not UTF-8 text**
- **Found during:** Task 3 (name-resolution demo)
- **Issue:** `Bytes::to_string()` on the pinned toolchain yields the Show/debug form `b"t"` instead of `t`, so catalog lookups always missed and the resolver returned `[]`.
- **Fix:** Added a local lossy UTF-8 decoder (`utf8_to_string`, via `Char::from_int` + `String::from_iter`) so the analyzer import list stays exactly `{syntax}` (D-21 letter); malformed bytes become U+FFFD.
- **Files modified:** analyzer/analyzer.mbt
- **Verification:** Resolver end-to-end test now resolves the expected names.
- **Committed in:** 07e22eb

**4. [Rule 1 - Bug] ParseResult::statement implemented as id-th Statement walk instead of raw `root.children[id]`**
- **Found during:** Task 2 (statement accessors)
- **Issue:** The plan's literal reading ("root child whose index equals statement_id") is wrong for documents containing trivia-only segments or skipped resource tails — `parse_with_limits_context` appends trivia leaves and Skipped nodes to root.children, which would shift or corrupt statement ids (threat T-02-43).
- **Fix:** The accessor returns the id-th child whose kind is "statement" (non-statement children never consume ids); identical to the literal index in all plan-specified cases, strictly more correct otherwise; documented in the doc comment.
- **Files modified:** api/api.mbt, test/analyzer_test.mbt
- **Verification:** Mixed-script isolation test, empty-document test, ordering test all pass.
- **Committed in:** f527845

**5. [Rule 2 - Missing Critical] Task 3 test input extended to cover all five resolver kinds**
- **Found during:** Task 3 (name-resolution demo)
- **Issue:** The plan's pinned demo input (insert/update/create-table) leaves Delete and Merge resolution untested even though the resolver contract explicitly covers all five 02-01/02-02 kinds.
- **Fix:** Extended the end-to-end script with `DELETE FROM t4 WHERE a = 1` and `MERGE INTO t5 USING src ...` (4.x); catalog holds t/t4/t5, and t2/t3 remain absent exactly as pinned.
- **Files modified:** test/analyzer_test.mbt
- **Verification:** `assert_eq(resolved, ["t", "t4", "t5"])` plus absence assertions for t2/t3.
- **Committed in:** 07e22eb

---

**Total deviations:** 5 auto-fixed (3 blocking, 1 bug, 1 missing critical)
**Impact on plan:** All auto-fixes were required to make the pinned interfaces compile and behave correctly on the pinned toolchain; the analyzer boundary (syntax-only imports, parser zero-dependency, unchanged syntax-only channel) is preserved exactly. No scope creep.

## Issues Encountered
- `moon test` on the pinned toolchain revealed the new trait/generic syntax, `pub(all)` construction rules, `var` reservedness (use `let mut`), `Bytes::to_string()` debug repr, and `Map([])` constructor deprecation — all resolved via the deviations above.
- Probing the CST required a temporary test file and a temporary test-package import; both were removed before commit (no residue; test/moon.pkg ends with only the planned analyzer import).
- The plan's statement-ordering test input (`SELECT 2 +`) produced two same-position DORIS-PARSE-002 diagnostics (existing parser behavior), so the ordering test was rebuilt around statements with known single-diagnostic counts while keeping the 002/007 mix and monotonic-position assertions.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `analyzer/` package is consumable: consumers can build a StaticCatalog (or implement the open Catalog trait) and resolve statement-level tables without touching the parser.
- `ParseResult::statement`/`statement_diagnostics` give the DORIS-03 path a direct per-statement API; the syntax-only channel is proven byte-identical with and without a catalog.
- ANLY-01 is executable; full ANAL-01 name resolution/type diagnostics are documented as v2 (D-24) — the natural scope of a future analyzer phase.

---
*Phase: 02-doris-completeness-and-corpus*
*Completed: 2026-08-04*

## Self-Check: PASSED

All plan artifacts verified on disk and in git history:

- Files: analyzer/moon.pkg, analyzer/analyzer.mbt, test/analyzer_test.mbt, api/api.mbt, test/moon.pkg, 02-05-SUMMARY.md — all present.
- Commits: `94e34d8` (Task 1), `f527845` (Task 2), `07e22eb` (Task 3) — all present in git log.
- Final suite: `moon test` → 160 tests, 160 passed, 0 failed.
- D-21 negative gate: parser/moon.pkg contains no analyzer reference (verified per task).
