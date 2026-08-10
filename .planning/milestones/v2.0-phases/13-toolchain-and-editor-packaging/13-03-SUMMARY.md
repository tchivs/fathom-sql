---
phase: 13-toolchain-and-editor-packaging
plan: 03
subsystem: api
tags: [flink, analyzer, d-03, d-21, d-22, d-24, catalog, table-level, upsert, create-view]

# Dependency graph
requires:
  - phase: 10-flink-release-profiles-and-lexical-core
    provides: FlinkProfile/FlinkProfileMetadata closed enum (flink-1.20.5 < flink-2.1.3 < flink-2.3.0) used by the test helper flink_context
  - phase: 11-flink-grammar-and-recoverable-cst
    provides: the Flink parser emitting Insert/Update/Delete/CreateTable/CreateView statement kinds, with UPSERT mapped to SyntaxKind::Insert (parser.mbt:4196) and CREATE [TEMPORARY] VIEW resolved via flink_create_form_kind (parser.mbt:4065)
  - phase: 12-cross-dialect-corpus-and-parity-gates
    provides: the frozen Doris baseline and flink snapshot discipline via diff_parity.py --frozen-only (PARITY-01, no --update)
  - phase: 09-dialect-boundary-and-neutral-naming
    provides: the D-21 read-only syntax-view discipline (analyzer imports only fathom/sql/syntax; parser never imports analyzer) and DialectContext/Dialect::Flink
provides:
  - resolve_table_references extended in place to the Flink statement families — Insert (incl. UPSERT INTO and INSERT OVERWRITE ... PARTITION), Update, Delete, CreateTable, CreateView — table-level only, no separate Flink entry point (D-03)
  - leading_prefix_end Insert arm recognizes the UPSERT leading keyword (parser maps UPSERT -> SyntaxKind::Insert); new CreateView arm skips CREATE [TEMPORARY] VIEW [IF NOT EXISTS]
  - Flink analyzer test matrix: UPSERT INTO, CREATE VIEW, family source-order, no-catalog byte-identical parse, empty document, INSERT...SELECT target-only boundary, INSERT OVERWRITE PARTITION, Doris behavior unchanged
  - docs/API.md + docs/zh-CN/API.md Flink analyzer scope paragraph (supported families, table-level boundary, v2 deferral)
affects: [TOOL-03 verifier, v2 ANAL-01 full column/identifier name resolution (D-24), docs/API.md analyzer consumers, catalog-aware completion TOOL-FUTURE-01]

# Actuals (#2632) — pairs with the plan's `estimate` (36000 chars/4) to calibrate future estimates.
actuals:
  tokens: 4471    # chars/4 over the realized diff (17,885 diff chars across the 4 changed files)
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Flink leading-prefix handling shares the existing Doris leading_prefix_end arms (additive; UPSERT widens the Insert first-keyword check, CreateView is a new arm) — the walk stays a positional skip over direct SourceToken leaves
    - Analyzer test fixtures parse via @parser.parse_with_limits with a flink_context helper (mirrors doris_context; FlinkProfile::from_id + metadata), then resolve against a StaticCatalog — the same read-only walk the public API exposes

key-files:
  created: []
  modified:
    - analyzer/analyzer.mbt
    - test/analyzer_test.mbt
    - docs/API.md
    - docs/zh-CN/API.md

key-decisions:
  - "D-03 one-way door: extend the EXISTING resolve_table_references in place (option-a) — Flink leading-prefix shapes in leading_prefix_end + CreateView in the matched-kind set, signature unchanged; no separate resolve_flink_table_references entry, no column/identifier-level resolution or type diagnostics this phase (D-24)."
  - "INSERT OVERWRITE ... PARTITION needs no PARTITION skip: the Flink parser consumes the qualified table name BEFORE the PARTITION spec (parse_flink_insert), so the existing INSERT OVERWRITE arm already lands on the target; the fixture flink_analyzer_insert_overwrite_partition_resolves_target pins this."
  - "The UPSERT arm widens the Insert first-keyword check to (INSERT | UPSERT) and then reuses the existing OVERWRITE [TABLE]|INTO skip — Flink's RichSqlInsert allows UPSERT OVERWRITE too, and the Doris forms are untouched (PARITY-01)."
  - "Adding CreateView to the matched-kind set is the documented one-way returned-set change: Doris CREATE VIEW is now also resolved (previously ignored), scoped as target-table-only with the query body not walked."

patterns-established:
  - "Pattern: additive Flink leading-prefix arms — Flink shapes reuse the Doris leading_prefix_end skip logic with only the first-keyword set widened and a new CreateView arm; Doris byte behavior is unchanged (PARITY-01)."
  - "Pattern: analyzer test fixture construction — a flink_context helper builds the DialectContext from the pinned FlinkProfile metadata, mirroring doris_context, and tests parse via @parser.parse_with_limits to obtain a @syntax.SyntaxNode root for resolve_table_references."

requirements-completed: [TOOL-03]

coverage:
  - id: D1
    description: "Flink analyzer tracer — UPSERT INTO and CREATE VIEW resolve their target table/view names through the existing resolve_table_references walk with a StaticCatalog (UPSERT INTO t VALUES (1) -> [t]; CREATE VIEW v AS SELECT * FROM t -> [v], query body not walked)"
    requirement: TOOL-03
    verification:
      - kind: unit
        ref: "test/analyzer_test.mbt#flink_analyzer_upsert_into_resolves_target"
        status: pass
      - kind: unit
        ref: "test/analyzer_test.mbt#flink_analyzer_create_view_resolves_target"
        status: pass
    human_judgment: false
  - id: D2
    description: "Full Flink target-table family matrix — mixed script (UPSERT INTO / UPDATE / DELETE / CREATE TABLE / CREATE VIEW) resolves [t1,t2,t3,t4,v5] in source order with a catalog holding all five; absent tables omitted; empty Flink document returns []; INSERT ... SELECT resolves only the target (dst), not the source; INSERT OVERWRITE ... PARTITION resolves the target"
    requirement: TOOL-03
    verification:
      - kind: unit
        ref: "test/analyzer_test.mbt#flink_analyzer_family_matrix_source_order"
        status: pass
      - kind: unit
        ref: "test/analyzer_test.mbt#flink_analyzer_empty_document_returns_empty"
        status: pass
      - kind: unit
        ref: "test/analyzer_test.mbt#flink_analyzer_insert_select_resolves_only_target"
        status: pass
      - kind: unit
        ref: "test/analyzer_test.mbt#flink_analyzer_insert_overwrite_partition_resolves_target"
        status: pass
    human_judgment: false
  - id: D3
    description: "No-catalog analysis returns [] and the syntax-only parse result is identical whether or not resolution is called (parser validity independent of catalog, ANLY-01); analyzer/moon.pkg imports only fathom/sql/syntax and parser/moon.pkg has no analyzer reference (D-21 negative gate); Doris analyzer behavior unchanged (existing Doris fixtures pass; diff_parity --frozen-only reports 0 differences)"
    requirement: TOOL-03
    verification:
      - kind: unit
        ref: "test/analyzer_test.mbt#flink_analyzer_no_catalog_empty_and_byte_identical_parse"
        status: pass
      - kind: unit
        ref: "test/analyzer_test.mbt#doris_analyzer_behavior_unchanged"
        status: pass
      - kind: other
        ref: "grep gate: analyzer/moon.pkg has exactly 1 fathom/sql import; parser/moon.pkg has no 'analyzer'"
        status: pass
      - kind: other
        ref: "scripts/diff_parity.py --frozen-only (455 snapshots, 0 frozen-vs-current differences)"
        status: pass
      - kind: other
        ref: "scripts/check_naming.py (601 product files, zero forbidden naming remnants)"
        status: pass
    human_judgment: false

# Metrics
duration: 8min
completed: 2026-08-10
status: complete
---

# Phase 13 Plan 03: Flink analyzer — resolve_table_references extended in place to Insert (UPSERT INTO / INSERT OVERWRITE), Update, Delete, CreateTable, and CreateView with table-level, optional-catalog semantics

**The Flink analyzer slice of TOOL-03/D-03: resolve_table_references now resolves the Flink target-table families (UPSERT INTO, INSERT OVERWRITE ... PARTITION, UPDATE, DELETE, CREATE TABLE, CREATE VIEW) through the existing read-only walk — with an optional catalog (no catalog → empty results, parser validity byte-identical, ANLY-01), the D-21 import discipline and parser/analyzer negative gate intact, and Doris behavior byte-identical.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-08-10T03:10:00Z (approx, first task commit 03:18:50 UTC)
- **Completed:** 2026-08-10T03:20:19Z (UTC)
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- **D-03 one-way door (Task 1, auto-resolved option-a):** extend the existing `resolve_table_references` in place — Flink leading-prefix shapes in `leading_prefix_end` + `CreateView` in the matched-kind set, keeping the public signature `pub fn[T : Catalog] resolve_table_references(node, source_bytes, catalog) -> Array[String]` unchanged. No separate `resolve_flink_table_references` entry (no API fragmentation), no column/identifier-level resolution or type diagnostics this phase (D-24).
- **UPSERT INTO (Task 2 tracer):** the Insert leading-prefix arm now recognizes the `UPSERT` first keyword — the Flink parser maps `UPSERT` to `SyntaxKind::Insert` (parser.mbt:4196), and Flink's RichSqlInsert also allows `UPSERT OVERWRITE`, so the widened `(INSERT | UPSERT)` check reuses the existing `OVERWRITE [TABLE]|INTO` skip. `UPSERT INTO t VALUES (1)` resolves to `["t"]`.
- **INSERT OVERWRITE ... PARTITION (Task 2):** verified against the parser — `parse_flink_insert` consumes the qualified table name BEFORE the `PARTITION` spec, so no PARTITION skip is needed; the existing `INSERT OVERWRITE` arm already lands on the target. Pinned by `flink_analyzer_insert_overwrite_partition_resolves_target`.
- **CREATE VIEW (Task 2 tracer):** new `leading_prefix_end` CreateView arm skips `CREATE [TEMPORARY] VIEW [IF NOT EXISTS]`; `CreateView` added to the matched-kind set (the one-way returned-set change: Doris CREATE VIEW is now also resolved). `CREATE VIEW v AS SELECT * FROM t` resolves to `["v"]` — the query body (`t`) is NOT walked (target-table boundary, D-24).
- **Flink family matrix + boundary/no-catalog cases (Task 3):** a mixed script resolves `["t1","t2","t3","t4","v5"]` in source order; the empty Flink document returns `[]`; `INSERT INTO dst SELECT * FROM src` resolves only `["dst"]`; a no-catalog analysis returns `[]` and the syntax parse is identical with or without resolution (ANLY-01); the D-21 import discipline (`analyzer/moon.pkg` = exactly 1 `fathom/sql` import) and the parser/analyzer negative gate stay green; Doris analyzer behavior is unchanged (existing fixtures pass, `diff_parity.py --frozen-only` = 0 differences).
- **Docs (Task 3):** `docs/API.md` + `docs/zh-CN/API.md` document the Flink analyzer scope — supported families, table-level boundary, v2 column/identifier deferral — with the existing case-sensitivity/last-wins notes preserved verbatim.

## Task Commits

Each task was committed atomically:

1. **Task 1: Confirm the Flink analyzer extension scope — D-03 one-way door** - `(auto-resolved option-a, no commit)` — decision checkpoint auto-selected "extend the existing resolve_table_references in place, table-level only"
2. **Task 2: Flink analyzer tracer — UPSERT INTO + CREATE VIEW end-to-end with StaticCatalog** - `98c52cb` (feat) — leading_prefix_end Insert UPSERT + CreateView arms, CreateView in the matched set, tracer + matrix tests (UPSERT, CREATE VIEW, no-catalog byte-identical, family source-order, empty, INSERT...SELECT, INSERT OVERWRITE PARTITION, Doris unchanged)
3. **Task 3: Full Flink target-table family matrix + no-catalog/empty cases + docs/API.md scope** - `a77d0cf` (docs) — Flink analyzer scope paragraph in docs/API.md + docs/zh-CN/API.md

**Plan metadata:** `(summary commit follows)`

## Files Created/Modified
- `analyzer/analyzer.mbt` - leading_prefix_end Insert arm recognizes `(INSERT | UPSERT)` then reuses the `OVERWRITE [TABLE]|INTO` skip; new CreateView arm (`CREATE [TEMPORARY] VIEW [IF NOT EXISTS]`); resolve_table_references matched-kind set adds CreateView; doc comments updated (Flink families, target-table-only boundary, ANLY-01)
- `test/analyzer_test.mbt` - NEW flink_context helper (FlinkProfile::from_id + metadata, mirrors doris_context) + 8 Flink/Doris analyzer tests: upsert-into, create-view, no-catalog byte-identical, family matrix source-order, empty document, INSERT...SELECT target-only, INSERT OVERWRITE PARTITION, Doris behavior unchanged
- `docs/API.md` - Flink analyzer scope paragraph (supported families, table-level boundary, v2 deferral; case-sensitivity/last-wins preserved verbatim)
- `docs/zh-CN/API.md` - same scope paragraph in Chinese

## Decisions Made
- D-03 one-way: extend `resolve_table_references` in place (option-a); signature unchanged; no separate Flink entry; no column/identifier-level resolution or type diagnostics this phase (D-24).
- INSERT OVERWRITE ... PARTITION needs no PARTITION skip — the parser places the table name before the PARTITION spec; the existing arm lands on the target.
- The UPSERT arm widens the Insert first-keyword check to `(INSERT | UPSERT)` and reuses the existing OVERWRITE/TABLE/INTO skip — covers both `UPSERT INTO` and `UPSERT OVERWRITE` with zero Doris drift.
- Adding CreateView to the matched set is the documented one-way returned-set change; Doris CREATE VIEW is newly resolved (target-table only).

## Deviations from Plan

### Auto-fixed Issues

**1. [Plan-text vs API reality] The plan's tracer fixture text said `@api.parse_with_ids(raw, "flink", ...)` for resolve_table_references calls, but parse_with_ids returns a PrimitiveNode root, not a SyntaxNode**
- **Found during:** Task 2 (writing the tracer fixtures)
- **Issue:** `@api.parse_with_ids` returns `ParseResult.root : PrimitiveNode` (a JSON-serializable view), while `resolve_table_references` takes a `@syntax.SyntaxNode`. Passing `parsed.root` straight through is a type error (moon Error 4014).
- **Fix:** Parsed the Flink fixtures via `@parser.parse_with_limits` with a `flink_context("flink-2.3.0")` helper (mirrors the existing `doris_context` pattern in test/recovery_test.mbt and the pre-existing Doris analyzer fixtures) to obtain a `@syntax.SyntaxNode` root; the no-catalog byte-identical assertion compares two `parse_with_limits` results.
- **Files modified:** test/analyzer_test.mbt
- **Verification:** moon test --package analyzer --package test --package api = 769 passed (761 baseline + 8 new).
- **Committed in:** 98c52cb (Task 2 commit)

---

**Total deviations:** 1 (plan-text vs API reality alignment)
**Impact on plan:** The fix keeps the end-to-end path (Flink document → resolve_table_references → target table list) identical to the plan's must-have truth; the analyzer surface is unchanged. No scope creep.

## Issues Encountered
- The D-21/negative-gate greps use `grep -c 'fathom/sql' analyzer/moon.pkg` == 1 and `! grep -q 'analyzer' parser/moon.pkg`; both hold (verified after each task).
- `moon test --target native` (unscoped full suite) fails on the `binding` package (`#export_name` requires `pkgtype(kind: "foreign_library")` for the native target) — pre-existing and unrelated; the plan's verification commands scope explicitly to `--package analyzer --package test --package api --package parity`, all of which pass.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- The Flink analyzer core (leading-prefix arms + CreateView in the matched set) is the D-03 foundation; consumers can run syntax-only Flink analysis with an optional catalog through the existing `resolve_table_references`.
- Table-level resolution is complete for the Flink target-table families; column/identifier-level reference resolution and type diagnostics remain deferred to v2 (D-24) and are documented in docs/API.md.
- Frozen Doris baseline (213) and flink-grammar/flink-lexical snapshots remain byte-identical (455 snapshots, 0 drift); `--update` stays excluded from CI.

---
*Phase: 13-toolchain-and-editor-packaging*
*Completed: 2026-08-10*

## Self-Check: PASSED
- Files verified: analyzer/analyzer.mbt, test/analyzer_test.mbt, docs/API.md, docs/zh-CN/API.md, .planning/phases/13-toolchain-and-editor-packaging/13-03-SUMMARY.md.
- Commits verified: 98c52cb (Task 2 tracer), a77d0cf (Task 3 docs).
- Gates: moon test --target native --package analyzer --package test --package api --package parity = 769 passed (no --update); scripts/diff_parity.py --frozen-only = 455 snapshots, 0 differences; scripts/check_naming.py = 601 product files, zero forbidden naming remnants; analyzer/moon.pkg has exactly 1 fathom/sql import; parser/moon.pkg has no 'analyzer' reference.
