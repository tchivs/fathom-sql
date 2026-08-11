---
phase: 07-column-lineage
plan: 03
subsystem: analysis
tags: [moonbit, lineage, column-lineage, api, flink-gate, snapshot-golden]

# Dependency graph
requires:
  - phase: 07-02
    provides: "lineage/ independent library: derive_lineage[T: Catalog] + derive_lineage_without_catalog, LineageEdge/LineageGap/LineageResult, D-03 view registry + ViewCatalog, D-04 INSERT positional mapping"
provides:
  - "`api.lineage_text(raw, parse_options, catalog: @analyzer.StaticCatalog?)` library entry (D-07): parse_document reuse, flink gate (D-08) → structured UnknownProfile after parse (never silent empty), Some/None catalog → derive_lineage / derive_lineage_without_catalog"
  - "D-38 type re-exports: @api.LineageResult / @api.LineageEdge / @api.LineageGap / @api.StaticCatalog — binding (07-04) consumes @api types without importing lineage/"
  - "test/lineage_test.mbt parse → lineage integration tests + 7 snapshot goldens (expression passthrough, star no-catalog/with-catalog, CTE/UNION positional, INSERT positional, * EXCEPT honest expansion, view registry expansion, api-facade consistency)"
affects: [07-04, 07-05]

# Actuals (#2632) — pairs with the plan's `estimate` (56000 estimateTokens) to calibrate.
actuals:
  tokens: 5820      # chars/4 over the realized diff (23,281 diff chars / 4)
  tasks: 2
  commits: 3        # RED test + GREEN feat + Task 2 test; SUMMARY/metadata commit tracked separately

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "api facade is a thin parse+derive passthrough: lineage_text reuses parse_document and maps Some/None catalog to derive_lineage / derive_lineage_without_catalog — no second lineage implementation"
    - "Inline `test \"api_...\" {}` blocks in api/api.mbt are the api package's test convention (pre-existing); the 5 lineage tests follow it"
    - "Snapshot-before-assert in integration tests guarantees the golden is written even when a prediction is wrong, aiding debugging (moon test --update only write path)"

key-files:
  created:
    - test/lineage_test.mbt
    - test/__snapshot__/lineage.expression-passthrough.doris-4.x.json
    - test/__snapshot__/lineage.star-no-catalog.doris-4.x.json
    - test/__snapshot__/lineage.star-with-catalog.doris-4.x.json
    - test/__snapshot__/lineage.cte-union-positional.doris-4.x.json
    - test/__snapshot__/lineage.insert-positional.doris-4.x.json
    - test/__snapshot__/lineage.star-except-honest.doris-4.x.json
    - test/__snapshot__/lineage.view-registry-expansion.doris-4.x.json
  modified:
    - api/api.mbt
    - api/moon.pkg
    - test/moon.pkg

key-decisions:
  - "Flink gate (D-08) fires AFTER a successful parse, returning Err(UnknownProfile(profile_id)) — a structured FATHOM-SCHEMA-family ParseError, never a silent Ok(empty); the explicit 'lineage is Doris-only' message is deferred to the wire/CLI boundary (07-04)"
  - "catalog: @analyzer.StaticCatalog? maps Some(c) → @lineage.derive_lineage(..., c) and None → @lineage.derive_lineage_without_catalog(...) (the toolchain cannot spell trait objects, so the optional concrete StaticCatalog is the api surface)"
  - "D-38 re-exports make api the shared core entry: binding/CLI consume @api.LineageResult/LineageEdge/LineageGap/StaticCatalog without importing lineage/ directly"
  - "TDD for Task 1: RED commit added the 5 failing api lineage tests (unbound lineage_text), GREEN commit implemented lineage_text + re-exports"

patterns-established:
  - "lineage_text mirrors lint_text/fingerprint_text: parse_document reuse (validate_limits → SourceText::new_with_limit → parse_with_limits_context → is_valid gate) then the analysis library entry; ParseError precedence identical to format_text (T-07-03-03)"
  - "Integration tests live in test/ (D-21: lineage cannot import parser); parse via @parser.parse_with_limits (doris 4.x strict) then derive via @api.lineage_text; snapshot goldens lock edge/gap structure and order"

requirements-completed: [LINE-01]

coverage:
  - id: D1
    description: "api.lineage_text library entry with flink gate (D-08) and optional catalog injection; D-38 type re-exports (LineageResult/LineageEdge/LineageGap/StaticCatalog); parse_document reuse with identical ParseError precedence"
    requirement: LINE-01
    verification:
      - kind: unit
        ref: "api/api.mbt#api_lineage_text_doris_select_basic_ok"
        status: pass
      - kind: unit
        ref: "api/api.mbt#api_lineage_text_flink_gate_structured_error"
        status: pass
      - kind: unit
        ref: "api/api.mbt#api_lineage_text_star_no_catalog_requires_catalog_gap"
        status: pass
      - kind: unit
        ref: "api/api.mbt#api_lineage_text_input_too_large_parse_error"
        status: pass
      - kind: unit
        ref: "api/api.mbt#api_lineage_text_empty_document_ok_empty"
        status: pass
    human_judgment: false
  - id: D2
    description: "test/lineage_test.mbt parse → lineage integration tests + 7 snapshot goldens locking edge/gap structure and document order across expression passthrough, star no-catalog/with-catalog, CTE/UNION positional, INSERT positional, * EXCEPT honest expansion, view registry expansion, and api-facade/library consistency"
    requirement: LINE-01
    verification:
      - kind: integration
        ref: "test/lineage_test.mbt#lineage expression passthrough doris-4.x"
        status: pass
      - kind: integration
        ref: "test/lineage_test.mbt#lineage star no catalog doris-4.x"
        status: pass
      - kind: integration
        ref: "test/lineage_test.mbt#lineage star with catalog doris-4.x"
        status: pass
      - kind: integration
        ref: "test/lineage_test.mbt#lineage cte union positional doris-4.x"
        status: pass
      - kind: integration
        ref: "test/lineage_test.mbt#lineage insert positional doris-4.x"
        status: pass
      - kind: integration
        ref: "test/lineage_test.mbt#lineage star except honest expansion doris-4.x"
        status: pass
      - kind: integration
        ref: "test/lineage_test.mbt#lineage view registry expansion doris-4.x"
        status: pass
      - kind: integration
        ref: "test/lineage_test.mbt#lineage api facade matches lib entry no catalog"
        status: pass
    human_judgment: false

# Metrics
duration: 39min
completed: 2026-08-11
status: complete
---

# Phase 07 Plan 03: api.lineage_text library entry + integration snapshot goldens

**`api.lineage_text(raw, parse_options, catalog: StaticCatalog?)` — the library-surface consumer entry for LINE-01: parse_document reuse, D-08 flink gate (structured UnknownProfile after parse, never silent empty), optional catalog mapping Some/None to derive_lineage / derive_lineage_without_catalog, D-38 type re-exports (LineageResult/LineageEdge/LineageGap/StaticCatalog), plus 7 integration snapshot goldens in test/ locking edge/gap structure and document order.**

## Performance

- **Duration:** 39 min
- **Started:** 2026-08-11T07:20:00Z
- **Completed:** 2026-08-11T07:59:15Z
- **Tasks:** 2
- **Files modified:** 11 (2 api files, 2 test config/files, 7 new snapshot goldens)

## Accomplishments
- **`api.lineage_text` library entry (D-07)**: reuses `parse_document` (validate_limits → SourceText::new_with_limit → parse_with_limits_context → is_valid gate), so UnknownProfile/InputTooLarge/InvalidSyntaxTree propagate as ParseError exactly like `lint_text`/`format_text` (T-07-03-03). The flink gate (D-08) fires AFTER a successful parse and returns `Err(UnknownProfile(profile_id))` — a structured FATHOM-SCHEMA-family ParseError, never a silent Ok(empty); the explicit "lineage is Doris-only" message is the wire/CLI boundary's job (07-04).
- **Optional catalog (D-05/T-02-42)**: `catalog : @analyzer.StaticCatalog?` maps `Some(c)` → `@lineage.derive_lineage(parsed.root, bytes, c)` and `None` → `@lineage.derive_lineage_without_catalog(...)` — the toolchain cannot spell trait objects, so the concrete optional StaticCatalog is the api surface (07-02 deviation respected). `None` derives with zero metadata: every star/external view reports a requires-catalog gap (SC2), never a fabricated edge. The catalog never touches the syntax valid channel (ANLY-01).
- **D-38 type re-exports**: `pub type LineageResult/LineageEdge/LineageGap = @lineage.*` and `pub type StaticCatalog = @analyzer.StaticCatalog` — api becomes the shared core entry so binding (07-04) constructs its envelope from @api types without importing lineage/ directly.
- **5 api-package tests** (inline, the api package's existing convention): doris valid → Ok edge; flink → Err UnknownProfile (never Ok empty); star no-catalog → requires-catalog gap; oversized → InputTooLarge; empty doc → Ok empty (flagged assumption RESOLVED).
- **8 integration tests + 7 snapshot goldens** in test/ (D-21: lineage cannot import parser, so integration lives in test/): expression passthrough (2 edges), star no-catalog (0 edges + gap) / with-catalog (2 real edges), CTE+UNION positional mapping (3 edges incl. `t.a→c.a` and positional `b→a`), INSERT positional (`u.a→t.c1`, `u.b→t.c2`), `* EXCEPT` honest expansion (no b edge), view registry expansion (`t.a→v.a` + star over view), and api-facade ≡ library-entry consistency (no-catalog byte-identical).

## Task Commits

Each task was committed atomically (Task 1 was TDD):

1. **Task 1 RED: add failing api lineage_text tests** - `f715166` (test)
2. **Task 1 GREEN: implement api.lineage_text + flink gate + type re-exports** - `57dea0c` (feat)
3. **Task 2: lineage integration tests + snapshot goldens** - `fb31806` (test)

**Plan metadata:** (separate `docs(07-03)` commit)

## Files Created/Modified
- `api/api.mbt` - `lineage_text` (parse_document reuse + flink gate + optional catalog) + D-38 re-exports + 5 inline lineage tests
- `api/moon.pkg` - + `@analyzer` + `@lineage` imports
- `test/lineage_test.mbt` (new) - `lineage_sql` / `lineage_result_to_json` / `lineage_snapshot_test` + 8 integration tests
- `test/moon.pkg` - + `@lineage` import (test-only, matches @formatter/@dialect convention)
- `test/__snapshot__/lineage.*.doris-4.x.json` (7 new) - edge/gap structure + order goldens

## Decisions Made
- **Flink gate after parse (D-08)**: `if parse_options.dialect_id() == "flink" { return Err(UnknownProfile(profile_id)) }` — placed strictly after `parse_document` and before derive, so a successful flink parse still gets the structured rejection; never silent empty. The plan's FATHOM-SCHEMA-003 wire mapping is deferred to 07-04.
- **Optional catalog → two library entries**: the api surface takes the concrete `@analyzer.StaticCatalog?`; `Some`/`None` dispatch to `derive_lineage` / `derive_lineage_without_catalog` (07-02's generic + no-catalog design). No new lineage semantics introduced at the api layer.
- **Type re-exports (D-38)** added to the existing formatter/lint alias block — `@api.LineageResult` etc. resolve through the facade for binding (07-04).
- **TDD RED/GREEN** for Task 1 (plan `tdd="true"`): the api package's convention is inline `test "api_..."` blocks in api/api.mbt, so the RED commit added the 5 tests there (compile-fail state, `lineage_text` unbound), and GREEN added the implementation.

## Deviations from Plan

### Auto-fixed Issues

None - plan executed as written; both tasks compiled and verified on the first GREEN run.

### Interpreted per the plan's own contracts

**1. Task 1 test location: inline in api/api.mbt (package convention) rather than a new `_test.mbt` file**
- **Found during:** Task 1 (TDD RED)
- **Issue:** The plan's `<files>` for Task 1 lists only api/api.mbt + api/moon.pkg, yet the acceptance criteria require "api 包内 test 全绿". The api package's established test convention (pre-existing `test "api_..."` blocks at the bottom of api.mbt) is inline, not a separate `_test.mbt` file.
- **Fix:** Added the 5 lineage tests inline in api/api.mbt (matching the package convention), keeping all Task 1 changes within the plan's declared files. The RED commit staged api/moon.pkg + api/api.mbt; GREEN staged api/api.mbt.
- **Verification:** `moon test --target native --package api` 633/633 green (RED compile-fail proved the tests compile in the api package).
- **Committed in:** f715166 / 57dea0c

**2. Empty-document test added beyond the 4 named behaviors**
- **Found during:** Task 1 (behavior list has 4 tests; must_haves flagged assumption LINE-01 empty)
- **Issue:** The plan's must_haves truth "lineage_text 对空文档返回 Ok(LineageResult{edges:[],gaps:[]})" (flagged assumption) is not among the Task 1 `<behavior>` list's 4 tests.
- **Fix:** Added `api_lineage_text_empty_document_ok_empty` locking Ok(empty), satisfying the flagged assumption deterministically.
- **Files modified:** api/api.mbt
- **Verification:** green in the api package run.
- **Committed in:** f715166 / 57dea0c

**3. Snapshot-before-assert ordering in test/lineage_test.mbt**
- **Found during:** Task 2 (test authoring)
- **Issue:** The analyzer pattern asserts then snapshots; if a prediction is wrong the golden is never written, leaving no artifact to debug against.
- **Fix:** Each snapshot test writes `t.write(content)` + `t.snapshot(...)` BEFORE the field assertions, so `moon test --update` always freezes the observed edges/gaps; assertions then lock the structural contract. Deterministic and matches the plan's "moon test --update 唯一写路径".
- **Files modified:** test/lineage_test.mbt
- **Verification:** `moon test --target native --package test` 200/200 green (192 pre-existing + 8 new).

---

**Total deviations:** 0 auto-fixed; 3 documented interpretations
**Impact on plan:** All interpretations keep changes within the plan's declared files or satisfy explicit must_haves/acceptance criteria. No scope creep.

## Issues Encountered
- `moon test --target native` without `--package` fails on the pre-existing `binding` foreign_library `#export_name` config (needs `pkgtype(kind: "foreign_library")`) — out of scope (binding/ untouched); the plan's scoped verify commands (`--package api` / `--package test`) pass.
- `moon test --package api` reports a global 633-test total (includes api + its dependents like parity), while `--package test` reports 200 — the scoped counts differ across package targets on this toolchain; both run with 0 failures.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `api.lineage_text` is the frozen library surface for 07-04 (wire/CLI): binding can construct the `fathom.lineage.v1` envelope from `@api.LineageResult`/`@api.LineageEdge`/`@api.LineageGap` (D-38), and the CLI/wire boundary implements the flink gate's explicit "lineage is Doris-only" message (D-08 double-insurance) and `--catalog <file>` injection.
- Edge/gap ordering is deterministic and snapshot-locked (7 goldens) — the parity byte-consistency input contract for 07-05.
- 5 api behavioral tests + 8 integration tests give 07-04/07-05 a stable regression net.

---
*Phase: 07-column-lineage*
*Completed: 2026-08-11*

## Self-Check: PASSED
- Files verified on disk: api/api.mbt, api/moon.pkg, test/moon.pkg, test/lineage_test.mbt, .planning/phases/07-column-lineage/07-03-SUMMARY.md, all 7 test/__snapshot__/lineage.*.json goldens
- Commits verified in git log: f715166 (Task 1 RED), 57dea0c (Task 1 GREEN), fb31806 (Task 2)
- Test runs: `moon check --target native` RC=0 (0 errors); `moon test --target native --package api` 633/633; `moon test --target native --package test` 200/200 (192 pre-existing + 8 new)
- Forbidden dirs untouched: `git status --short -- lineage/ binding/ fathom-sql/ parity/ parser/ analyzer/` empty
