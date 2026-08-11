---
phase: 07-column-lineage
plan: 02
subsystem: analysis
tags: [moonbit, lineage, column-lineage, catalog, views, insert]

# Dependency graph
requires:
  - phase: 07-01
    provides: "Analyzer lineage-facing public surface: pub(all) select-model types, split_select_model / source_tokens / view_body_location / insert_body_location / has_error_missing, SelectItem.except_cols"
provides:
  - "`lineage/` independent library (D-21: imports only analyzer + syntax + core/debug): pub(all) LineageEdge/LineageGap/LineageResult + gap-code consts"
  - "`derive_lineage(root, bytes, catalog)` generic over [T: Catalog] + `derive_lineage_without_catalog` — SELECT/CTE/UNION/CREATE VIEW/INSERT column-level edges with flattened byte spans"
  - "D-06 honest gaps: requires-catalog (star self-check / unknown-table no catalog / external view), unresolved-reference (unknown-column/function/table, ambiguous merged), requires-complete-parse (error/missing) — strictly separate from edges"
  - "D-03 view registry + `ViewCatalog[T]` generic Catalog wrapper (view-first lookup, same-name view shadows catalog table, delegate table_in_db/function)"
  - "D-04 INSERT positional mapping: target column list / catalog column order / VALUES no edges / no-col-list requires-catalog gap"
affects: [07-03, 07-04, 07-05]

# Actuals (#2632) — pairs with the plan's `estimate` (76000 estimateTokens) to calibrate.
actuals:
  tokens: 16236     # chars/4 over the realized diff (64,943 diff chars / 4)
  tasks: 3
  commits: 3        # task commits; the SUMMARY/metadata commit is tracked separately by the orchestrator

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Trait objects are NOT supported on moon 0.1.20260724 — `catalog : @analyzer.Catalog?` (a trait used as a type) is a compile error, so derive_lineage mirrors `@analyzer.analyze`'s generic `[T : Catalog]` shape plus a dedicated no-catalog entry"
    - "White-box tests must live in `_wbtest.mbt` (analyzer convention): `_test.mbt` files are black-box on this toolchain and cannot see package-private functions"
    - "Local type aliases (`type ABinding = @analyzer.Binding`) dodge a moon 0.1.20260724 parse quirk where `Array[@pkg.Type],` in a test-file signature is sometimes mis-tokenized"

key-files:
  created:
    - lineage/moon.pkg
    - lineage/model.mbt
    - lineage/edges.mbt
    - lineage/gaps.mbt
    - lineage/views.mbt
    - lineage/insert.mbt
    - lineage/lineage_wbtest.mbt

key-decisions:
  - "derive_lineage is generic `[T : @analyzer.Catalog]` (plan's `Catalog?` trait-object signature is unimplementable on moon 0.1.20260724 — Rule 3 deviation); no-catalog is `derive_lineage_without_catalog` passing an empty StaticCatalog with catalog_none=true so unknown tables map to requires-catalog"
  - "Two-pass analyze in derive_lineage_inner: pass 1 (inner catalog) expands stars inside CREATE VIEW bodies for the view registry; pass 2 (ViewCatalog) resolves `FROM v`"
  - "Unexpanded-star gap is the single catalog report per body: when it fires, redundant unknown-table -> requires-catalog gaps in the same body are suppressed (star-gap suppression)"
  - "INSERT with a column list names targets without catalog metadata, so its unknown-table diagnostic is suppressed; without a column list and no catalog columns, the target-table span yields one requires-catalog gap (Open Question 3)"
  - "INSERT trailing SELECT source columns use model-ref source spelling (analyzer does not bind the trailing body — Open Question 4 independent-scope re-parse)"

patterns-established:
  - "Star self-check (SC2): a star SelectItem with zero Column bindings at its star span and no resolvable table binding in the body -> requires-catalog gap at the star span; never fabricate column names"
  - "Span association: edge/gap endpoints come exclusively from analyzer bindings + select-model token spans (flattened Int bytes); no re-implemented name resolution"

requirements-completed: [LINE-01]

coverage:
  - id: D1
    description: "derive_lineage entry + SELECT/CTE/UNION D-01 expression-passthrough edges (a+b AS x -> t.a->x + t.b->x; function-arg refs; CTE-qualified targets; UNION positional names; star passthrough) with flattened byte spans"
    requirement: LINE-01
    verification:
      - kind: unit
        ref: "lineage/lineage_wbtest.mbt#lineage D-01 expression passthrough a + b as x"
        status: pass
      - kind: unit
        ref: "lineage/lineage_wbtest.mbt#lineage D-01 single ref and function argument"
        status: pass
      - kind: unit
        ref: "lineage/lineage_wbtest.mbt#lineage CTE body qualified edge and UNION positional mapping"
        status: pass
    human_judgment: false
  - id: D2
    description: "D-06 honest gaps strictly separate from edges: star/unknown-table-no-catalog -> requires-catalog; unknown-column/function/ambiguous -> unresolved-reference (message preserved); error/missing -> requires-complete-parse; star-with-catalog -> real edges, no gaps"
    requirement: LINE-01
    verification:
      - kind: unit
        ref: "lineage/lineage_wbtest.mbt#lineage star no catalog zero edges with requires-catalog gap"
        status: pass
      - kind: unit
        ref: "lineage/lineage_wbtest.mbt#lineage star with catalog expands to real edges"
        status: pass
      - kind: unit
        ref: "lineage/lineage_wbtest.mbt#lineage unresolved reference maps to gap"
        status: pass
      - kind: unit
        ref: "lineage/lineage_wbtest.mbt#lineage unknown-table no catalog is requires-catalog"
        status: pass
      - kind: unit
        ref: "lineage/lineage_wbtest.mbt#lineage ambiguous reference merges to unresolved-reference"
        status: pass
      - kind: unit
        ref: "lineage/lineage_wbtest.mbt#lineage error body reports requires-complete-parse"
        status: pass
    human_judgment: false
  - id: D3
    description: "D-03 view registry + ViewCatalog[T]: view output columns from the view body; view-first Catalog.table with case-fold + stored-key byte recheck; same-name view shadows catalog table; table_in_db/function delegate; external view without metadata -> requires-catalog"
    requirement: LINE-01
    verification:
      - kind: unit
        ref: "lineage/lineage_wbtest.mbt#lineage view registry and ViewCatalog shadow"
        status: pass
      - kind: unit
        ref: "lineage/lineage_wbtest.mbt#lineage view body edge to view output column"
        status: pass
      - kind: unit
        ref: "lineage/lineage_wbtest.mbt#lineage external view star without metadata is requires-catalog"
        status: pass
    human_judgment: false
  - id: D4
    description: "D-04 INSERT positional mapping: target column list aligned to trailing SELECT output; no-column-list no-catalog -> single requires-catalog gap at target-table span with source edge still produced; VALUES rows -> no edges; ViewCatalog generic impl compiles on moon 0.1.20260724"
    requirement: LINE-01
    verification:
      - kind: unit
        ref: "lineage/lineage_wbtest.mbt#lineage INSERT positional mapping"
        status: pass
      - kind: unit
        ref: "lineage/lineage_wbtest.mbt#lineage INSERT without column list no catalog gap"
        status: pass
      - kind: unit
        ref: "lineage/lineage_wbtest.mbt#lineage INSERT VALUES produces no edges"
        status: pass
    human_judgment: false

# Metrics
duration: 95min
completed: 2026-08-11
status: complete
---

# Phase 07 Plan 02: Column Lineage Core Library (lineage/)

**`lineage/` independent library delivering `derive_lineage` — D-01 expression-passthrough edges across SELECT/CTE/UNION/CREATE VIEW/INSERT with flattened byte spans, D-06 honest gaps (requires-catalog / unresolved-reference / requires-complete-parse) strictly separate from edges, the D-03 view registry + `ViewCatalog[T]` generic catalog wrapper, and D-04 INSERT positional mapping — zero new dependencies (D-21: imports only analyzer + syntax).**

## Performance

- **Duration:** 95 min
- **Started:** 2026-08-11T15:20:00Z
- **Completed:** 2026-08-11T16:55:00Z
- **Tasks:** 3
- **Files modified:** 7 (all new in `lineage/`)

## Accomplishments
- **`derive_lineage(root, source_bytes, catalog)`** (generic over `[T: Catalog]`, mirroring `@analyzer.analyze`) plus **`derive_lineage_without_catalog`**: walks a parsed document's statements, re-parses each SELECT-family body via the analyzer's public `split_select_model`, associates analyzer Column bindings to model NameRefs by flattened byte span (D-02), and emits one edge per resolved column reference to its output column (D-01 expression passthrough). CTE bodies derive edges with CTE-qualified targets (`t.a -> c.a`); UNION branches map positionally to the first branch's column names; subquery bodies recurse with alias-qualified targets.
- **D-06 honest gaps** in `gaps.mbt`, strictly separate from edges (SC2): the star self-check reports `requires-catalog` at the star span when `expand_star` silently yields zero columns and no resolvable table binding exists in the body; `unknown-table` maps to `requires-catalog` (no catalog) or `unresolved-reference` (catalog injected); `unknown-column`/`unknown-function`/`ambiguous-reference` merge to `unresolved-reference` with the analyzer message preserved (Open Question 2); error/missing bodies yield a single `requires-complete-parse` gap (D-33). An unexpanded-star gap suppresses redundant unknown-table -> requires-catalog gaps in the same body (one catalog report per body).
- **D-03 view registry + `ViewCatalog[T]`**: in-document CREATE VIEW bodies are located via `view_body_location`, re-parsed with `split_select_model`, and mapped to output columns. `ViewCatalog[T]` (pub struct + `pub impl[T: Catalog] Catalog`) checks the registry first (parsing-time ASCII case-fold, stored-key byte recheck for quoted identifiers) then delegates to the inner catalog; a same-name view shadows a catalog table (Pitfall 4); `table_in_db`/`function` delegate (views are default-db only, A3).
- **D-04 INSERT positional mapping** in `insert.mbt`: `INSERT INTO t(c1,c2) SELECT a,b FROM u` maps the trailing SELECT output columns positionally to the column list (`u.a -> t.c1`, `u.b -> t.c2`); without a column list the catalog column order is used, and without catalog columns a single `requires-catalog` gap at the target-table span is produced while source edges still emit (Open Question 3); VALUES rows produce no edges (row literals carry no column references); a `WITH LABEL` prefix is skipped as part of the INSERT prefix.
- **15 white-box tests** in `lineage/lineage_wbtest.mbt` (constructed `SelectModel`/`Binding`/`StaticCatalog` values directly — no parser import, D-21) lock the edge/gap derivation, view registry/ViewCatalog semantics, and INSERT mapping. `moon check --target native` clean; `moon test --target native --package lineage` 15/15.

## Task Commits

Each task was committed atomically:

1. **Task 1: lineage/ package + model + derive_lineage SELECT/CTE/UNION edges (tracer)** - `e81b233` (feat)
2. **Task 2: D-06 gap derivation (requires-catalog / unresolved-reference / requires-complete-parse)** - `67656fa` (feat)
3. **Task 3: view registry + ViewCatalog[T] wrapper + INSERT positional mapping (D-03/D-04)** - `09145a4` (feat)

**Plan metadata:** (separate `docs(07-02)` commit by the orchestrator)

## Files Created/Modified
- `lineage/moon.pkg` - library package; imports only `fathom/sql/analyzer`, `fathom/sql/syntax`, `moonbitlang/core/debug` (D-21 negative gate: never parser/source/dialect)
- `lineage/model.mbt` - `pub(all)` LineageEdge/LineageGap/LineageResult (all-pub fields, derive(Eq, @debug.Debug)) + GAP_REQUIRES_CATALOG / GAP_UNRESOLVED_REFERENCE / GAP_REQUIRES_COMPLETE_PARSE consts
- `lineage/edges.mbt` - `derive_lineage` / `derive_lineage_without_catalog`, document walk (SELECT / CREATE VIEW / INSERT dispatch), derive_model/core/item (D-01 edges + star self-check), span association helpers, UTF-8/identifier/CI utilities
- `lineage/gaps.mbt` - `map_diagnostic_gaps` (D-06 diagnostic -> gap mapping with star-fired suppression)
- `lineage/views.mbt` - view registry build (view_name / view_output_columns / build_view_registry) + `ViewCatalog[T]` + generic Catalog impl
- `lineage/insert.mbt` - `derive_insert_body` (INSERT prefix/col-list/trailing-body handling, WITH LABEL skip, positional source edges, gap policy)
- `lineage/lineage_wbtest.mbt` - 15 white-box tests (edge/gap derivation, view registry/ViewCatalog, INSERT mapping, determinism)

## Decisions Made
- **derive_lineage is generic** (deviation, see below): the plan's `catalog : @analyzer.Catalog?` (trait used as a type) is a compile error on moon 0.1.20260724. `derive_lineage[T : Catalog]` mirrors `@analyzer.analyze`; `derive_lineage_without_catalog` covers the no-catalog case (empty StaticCatalog + catalog_none flag so unknown tables map to requires-catalog).
- **Two-pass analyze**: pass 1 (inner catalog) expands stars inside CREATE VIEW bodies to build the registry; pass 2 (ViewCatalog) resolves `FROM v` references and drives the body walk.
- **Star-gap suppression**: an unexpanded star is the single requires-catalog report for its body, so redundant unknown-table -> requires-catalog gaps are dropped (matches the plan's `SELECT * FROM t` no-catalog test expecting one gap at the star span).
- **INSERT gap policy**: a column list names targets without catalog metadata (no gap); no column list + no catalog columns -> one requires-catalog gap at the target-table span (Open Question 3).
- **INSERT trailing SELECT sources**: the analyzer does not bind the trailing body, so source column names come from the re-parsed model refs' source spelling when no binding exists (Open Question 4 independent-scope re-parse).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Trait-object signature unimplementable: `catalog : @analyzer.Catalog?`**
- **Found during:** Task 1 (first `moon check --target native` probe)
- **Issue:** moon 0.1.20260724 rejects a trait used as a type (`@analyzer.Catalog` is a trait, not a type), so the plan's optional-trait-object parameter cannot be spelled. A `DynCatalog` trait-object wrapper also failed for the same reason.
- **Fix:** `derive_lineage` is generic `[T : @analyzer.Catalog]` (mirroring `@analyzer.analyze`), and the no-catalog case is a dedicated `derive_lineage_without_catalog` passing `StaticCatalog::new([])` with an explicit `catalog_none` flag so unknown tables map to requires-catalog. Callers inject their own catalog type; the API layer (07-03) maps its `StaticCatalog?` option to these two entries.
- **Files modified:** lineage/model.mbt, lineage/edges.mbt
- **Verification:** `moon check --target native` passes; tests green.
- **Committed in:** e81b233 (Task 1)

**2. [Rule 3 - Blocking] `_test.mbt` files are black-box: package-private `derive_select_body` unbound**
- **Found during:** Task 1 (`moon check` — `derive_select_body` reported unbound, `CteDef` record literal not found)
- **Issue:** On moon 0.1.20260724 a `_test.mbt` file is compiled as an external black-box test and cannot see package-private functions; the plan's `lineage_test.mbt` white-box intent requires the analyzer's `_wbtest.mbt` convention (cf. `analyzer/analyzer_wbtest.mbt`).
- **Fix:** Named the test file `lineage/lineage_wbtest.mbt` (white-box); package-private `derive_select_body`/`derive_insert_body`/`view_output_columns`/`ViewCatalog` are now visible. Local type aliases (`type ABinding = @analyzer.Binding`, ...) dodge a moon parser quirk with `Array[@pkg.Type],` in test-file signatures; out-param arrays replace tuple returns in the test runner.
- **Files modified:** lineage/lineage_wbtest.mbt (renamed from lineage_test.mbt)
- **Verification:** `moon test --target native --package lineage` 15/15.
- **Committed in:** e81b233 / 67656fa / 09145a4

### Interpreted per the plan's own contracts

**3. Task 1/2 boundary**: `gaps.mbt` exists in the working tree during Task 1 because the tracer's `derive_select_body` needs the star-gap self-check (Task 1 Test 4). Task 1's commit staged only moon.pkg/model.mbt/edges.mbt/lineage_wbtest.mbt; Task 2's commit added gaps.mbt plus the diagnostic mapping and the five gap tests. The plan's "3 tasks / 3 commits" structure is preserved.

**4. INSERT trailing SELECT source columns are shallow** (Open Question 4): the analyzer's `analyze_dml_body` does not analyze the trailing SELECT body, so its refs have no analyzer bindings. `derive_insert_source_edges` falls back to the model refs' source spelling (`ref_last_part`) for `source_name`/`source_resolved_to`; when a future analyzer binds the trailing body, the code automatically uses the binding instead. This is the plan's Open Question 4 resolution, not a fabricated edge (SC2).

---

**Total deviations:** 2 auto-fixed (both Rule 3 blocking), 2 documented interpretations
**Impact on plan:** Both auto-fixes were necessary for the deliverable to compile on the pinned toolchain; they change the public entry shape (generic instead of trait-object optional) without changing the lineage semantics or the edge/gap contracts. No scope creep.

## Issues Encountered
- **moon 0.1.20260724 toolchain constraints**: no trait objects (drove the generic signature), black-box `_test.mbt` (drove `_wbtest.mbt`), record construction needs `Type::{ ... }` when the type name is explicit, and a parser quirk where `Array[@pkg.Type],` in a test-file signature is sometimes mis-tokenized (worked around with local type aliases). All documented in code comments.
- **Concurrent agents observed** committing to other branches during execution (their commits appeared in hub logs but not in this branch's history); my three commits remain sequential and intact on `master`. No analyzer/parser/api/binding/fathom-sql/parity files were touched by this plan.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `lineage/` exposes the library surface 07-03 consumes: `derive_lineage` (generic over `[T: Catalog]`) and `derive_lineage_without_catalog` for the no-catalog path. 07-03's `api.lineage_text(raw, parse_options, catalog : StaticCatalog?)` maps `Some`/`None` to these two entries.
- Edge/gap ordering is deterministic (document order -> model/branch/CTE order -> item order -> refs order; star expansion follows scope-entry order x catalog column order), satisfying the parity byte-consistency input contract for 07-05.
- Known limitations for downstream: star-over-view in a registry build (pass 1 uses only the inner catalog) yields zero output columns for that view (referencing it with `*` reports requires-catalog); `INSERT ... WITH LABEL` combined with a column list is not located by `insert_body_location` (accepted edge case); INSERT trailing SELECT star cannot be expanded (requires-catalog gap).

---
*Phase: 07-column-lineage*
*Completed: 2026-08-11*
