---
phase: 07-column-lineage
plan: 04
subsystem: wire
tags: [moonbit, lineage, wire, catalog-json, cli, flink-gate]

# Dependency graph
requires:
  - phase: 07-03
    provides: "api.lineage_text(raw, parse_options, catalog: StaticCatalog?) + D-38 type re-exports (LineageResult/LineageEdge/LineageGap/StaticCatalog) — binding consumes @api types without importing lineage/"
  - phase: 07-02
    provides: "lineage/ library derive_lineage[T: Catalog] + honest gap derivation"
provides:
  - "fathom.lineage.v1 wire export (8th schema namespace, PURE ADDITION — Pitfall V6): binding/schema.mbt LINEAGE_SCHEMA_VERSION + validate_schema_version 8th branch; fathom_lineage_v1(raw, dialect, profile, mode, catalog_json) ABI for Native/JS/Wasm hosts (js+wasm exports lists)"
  - "binding/catalog_json.mbt parse_catalog_json(bytes) -> Result[StaticCatalog?, String]: tables/db_tables/functions JSON -> StaticCatalog with structured errors (invalid UTF-8/JSON/fields -> Err -> FATHOM-SCHEMA-004, never silent)"
  - "fathom-sql lineage --dialect doris --profile <id> [--catalog <file>] [file|-] subcommand with D-39 exit codes (0 envelope / 1 parse failure / 2 usage+config incl. flink gate)"
affects: [07-05, docs/API.md]

# Actuals (#2632) — pairs with the plan's `estimate` (70000 estimateTokens, low confidence) to calibrate.
actuals:
  tokens: 7851      # chars/4 over the realized diff (31,405 diff chars / 4)
  tasks: 3
  commits: 4        # Task commits; SUMMARY/metadata commit tracked separately

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "binding foreign_library cannot be the DIRECT target of a native test build on moon 0.1.20260724 (#export_name, error 4219) — the wire tests live in test/ which imports @binding as a dependency (same relationship as fathom-sql, natively testable)"
    - "fathom_lineage_v1 mirrors fathom_lint_v1: dialect-first ParseOptions::new -> flink gate (FATHOM-SCHEMA-003 'lineage is Doris-only') -> catalog_json parse (FATHOM-SCHEMA-004) -> @api.lineage_text -> lineage_result_json envelope"
    - "CLI thin adapter (D-37/D-38): run_lineage calls @api.lineage_text + @binding.parse_catalog_json/lineage_result_json — no lineage logic in the CLI"

key-files:
  created:
    - binding/catalog_json.mbt
    - test/binding_wire_test.mbt
  modified:
    - binding/schema.mbt
    - binding/json.mbt
    - binding/exports.mbt
    - binding/moon.pkg
    - fathom-sql/args.mbt
    - fathom-sql/run.mbt
    - fathom-sql/main.mbt
    - fathom-sql/cli_test.mbt
    - test/moon.pkg

key-decisions:
  - "catalog_json.mbt was created in Task 1 (not Task 2) because fathom_lineage_v1 depends on parse_catalog_json for its catalog_json handling — each task's verify must compile/pass atomically; Task 2 then adds the 4 catalog_json behavior tests (empty/tables/db_tables+functions/invalid). The plan's <files> boundary was interpreted: the total modified-file set is identical to files_modified."
  - "binding wire tests are hosted in test/binding_wire_test.mbt (test/ imports @binding) because the binding foreign_library #export_name cannot compile when binding is the DIRECT native test target (error 4219, pre-existing toolchain limitation) — the plan's 'binding 包内 test' is realized as binding-behavior tests run via --package test"
  - "flink gate fires immediately after parse_options (before catalog/file handling) in run_lineage — wire-consistent ordering with fathom_lineage_v1 (D-08 double-insurance)"
  - "Verification adapted to the local pinned toolchain (moon 0.1.20260724): root `moon check --target native` and `moon test --target native --package binding` fail on the pre-existing binding #export_name config; the working equivalents are `moon check --package-path binding`, `moon build --target js|wasm --package binding`, `moon test --package test` / `--package fathom-sql`"
  - "CLI parse-failure exit-1 test uses oversized input (8 MiB + 1, InputTooLarge) rather than invalid syntax — b\"bad\" parses to a valid recovered tree on this toolchain"

patterns-established:
  - "parse_catalog_json mirrors parse_overrides (exports.mbt): empty bytes/'{}' -> Ok(None) default; @utf8.decode try/catch -> Err; @json.parse try/catch -> Err; per-field type/shape validation -> Err; never a silent fallback (T-06-03-01/ASVS V5)"
  - "fathom.lineage.v1 envelope carries dialect/profile/exact_release metadata (D-09) + source_bytes + edges[] + gaps[]; edge/gap spans serialize with Json::number(to_double()) (T-07-04-04, < 2^53 safe)"
  - "Edge/gap array order is the public parity contract (Pattern 6): document order -> SelectModel branch/CTE order -> SelectItem order -> refs order; star expansion follows scope-entry order x catalog JSON column order (StaticCatalog LinkedHashMap determinism)"

requirements-completed: [LINE-01]

coverage:
  - id: D1
    description: "fathom.lineage.v1 wire export (8th schema namespace pure-add + fathom_lineage_v1 ABI with dialect-first validation, flink FATHOM-SCHEMA-003 gate, catalog FATHOM-SCHEMA-004 handling; js+wasm exports registration)"
    requirement: LINE-01
    verification:
      - kind: unit
        ref: "test/binding_wire_test.mbt#binding_lineage_v1_envelope_contains_metadata_edges_gaps"
        status: pass
      - kind: unit
        ref: "test/binding_wire_test.mbt#binding_lineage_v1_flink_gate_structured_error"
        status: pass
      - kind: unit
        ref: "test/binding_wire_test.mbt#binding_validate_schema_version_lineage_8th_additive"
        status: pass
      - kind: unit
        ref: "test/binding_wire_test.mbt#binding_lineage_v1_unknown_dialect_structured_error"
        status: pass
      - kind: build
        ref: "moon build --target js --package binding (0 errors)"
        status: pass
      - kind: build
        ref: "moon build --target wasm --package binding (0 errors)"
        status: pass
    human_judgment: false
  - id: D2
    description: "binding/catalog_json.mbt parse_catalog_json: empty/'{}' -> Ok(None); tables/db_tables/functions -> StaticCatalog (JSON column order); invalid UTF-8/JSON/fields -> Err(String) -> FATHOM-SCHEMA-004 at the wire"
    requirement: LINE-01
    verification:
      - kind: unit
        ref: "test/binding_wire_test.mbt#binding_parse_catalog_json_empty_bytes_and_empty_object_no_catalog"
        status: pass
      - kind: unit
        ref: "test/binding_wire_test.mbt#binding_parse_catalog_json_tables_builds_catalog"
        status: pass
      - kind: unit
        ref: "test/binding_wire_test.mbt#binding_parse_catalog_json_db_tables_and_functions"
        status: pass
      - kind: unit
        ref: "test/binding_wire_test.mbt#binding_parse_catalog_json_invalid_inputs_structured_errors"
        status: pass
      - kind: unit
        ref: "test/binding_wire_test.mbt#binding_lineage_v1_bad_catalog_json_structured_004_error"
        status: pass
    human_judgment: false
  - id: D3
    description: "fathom-sql lineage subcommand with --catalog and D-39 exit codes (0 envelope / 1 parse failure / 2 usage+config incl. flink gate and FATHOM-SCHEMA-004)"
    requirement: LINE-01
    verification:
      - kind: unit
        ref: "fathom-sql/cli_test.mbt#cli_lineage_exit_0_envelope"
        status: pass
      - kind: unit
        ref: "fathom-sql/cli_test.mbt#cli_lineage_flink_gate_exit_2"
        status: pass
      - kind: unit
        ref: "fathom-sql/cli_test.mbt#cli_lineage_bad_catalog_path_exit_2"
        status: pass
      - kind: unit
        ref: "fathom-sql/cli_test.mbt#cli_lineage_bad_catalog_json_exit_2"
        status: pass
      - kind: unit
        ref: "fathom-sql/cli_test.mbt#cli_lineage_parse_failure_exit_1"
        status: pass
      - kind: unit
        ref: "fathom-sql/cli_test.mbt#cli_lineage_star_with_catalog_exit_0_two_edges"
        status: pass
      - kind: unit
        ref: "fathom-sql/cli_test.mbt#cli_lineage_star_no_catalog_requires_catalog_gap"
        status: pass
      - kind: unit
        ref: "fathom-sql/cli_test.mbt#cli_lineage_flag_surface_and_usage"
        status: pass
    human_judgment: false

# Metrics
duration: 28min
completed: 2026-08-11
status: complete
---

# Phase 07 Plan 04: fathom.lineage.v1 wire export + catalog JSON + fathom-sql lineage subcommand

**LINE-01 host-consumer surface: `fathom.lineage.v1` wire export (8th schema namespace, pure-add), `binding/catalog_json.mbt` (catalog JSON → StaticCatalog with structured errors), and `fathom-sql lineage --catalog <file>` CLI subcommand (D-39 exit 0/1/2).**

## Performance

- **Duration:** 28 min
- **Started:** 2026-08-11T08:05:00Z
- **Completed:** 2026-08-11T08:33:39Z
- **Tasks:** 3
- **Commits:** 4 task commits + 1 docs/metadata commit
- **Files created:** 2 (binding/catalog_json.mbt, test/binding_wire_test.mbt)
- **Files modified:** 9 (binding ×4, fathom-sql ×4, test/moon.pkg)

## Accomplishments
- **`fathom.lineage.v1` wire export (D-07, Pitfall V6)**: `binding/schema.mbt` adds `LINEAGE_SCHEMA_VERSION` and appends the 8th branch to `validate_schema_version` — PURE ADDITION, the original 7 namespaces' branches are byte-identical (verified by the additive test). `binding/json.mbt` adds `lineage_result_json` (envelope with dialect/profile/exact_release metadata, source bytes, `edges[]` + `gaps[]`; spans via `Json::number(to_double())`, safe < 2^53). `binding/exports.mbt` adds `#export_name("fathom_lineage_v1")` `fathom_lineage_v1(raw, dialect, profile, mode, catalog_json)` — dialect-first `ParseOptions::new` validation, flink gate → structured `FATHOM-SCHEMA-003` + "lineage is Doris-only" (never silent empty, D-08), catalog_json via `parse_catalog_json` (bad input → `FATHOM-SCHEMA-004`), then `@api.lineage_text` → envelope. Registered in BOTH js and wasm exports lists in `binding/moon.pkg` (Pitfall 5).
- **`binding/catalog_json.mbt` (D-05, T-07-04-02)**: `parse_catalog_json(bytes) -> Result[@api.StaticCatalog?, String]` mirrors `parse_overrides` — empty bytes / `"{}"` → `Ok(None)` (no catalog, all stars honest gaps); invalid UTF-8 → `Err("invalid UTF-8 in catalog JSON")`; malformed JSON → `Err("malformed JSON in catalog JSON")`; the `{tables, db_tables, functions}` shape → `StaticCatalog::new` / `with_db` / `with_function` with JSON-array column order (LinkedHashMap determinism, the star-expansion parity contract). Missing/type-mismatched fields → structured `Err(String)` — never a silent fallback.
- **`fathom-sql lineage` subcommand (D-37/D-38/D-39)**: `args.mbt` adds `"lineage"` to the subcommand whitelist, `pub catalog : String?` to `Command`, and the `--catalog <file>` flag (missing value → `MissingValue` exit 2). `run.mbt` adds `run_lineage` — parse_options → flink gate (exit 2 "lineage is Doris-only") → `--catalog` read + `parse_catalog_json` (bad path/JSON → exit 2) → `@api.lineage_text` → `@binding.lineage_result_json` envelope on stdout (exit 0) / parse failure (exit 1). `main.mbt` dispatches "lineage". `usage_text`/`usage_error_message` list lineage + `--catalog`.
- **Tests**: 10 new binding wire/catalog_json tests in `test/binding_wire_test.mbt` (hosted in test/ because the binding foreign_library can't be a direct native test target) + 8 new CLI lineage tests in `fathom-sql/cli_test.mbt`. Full native matrix 986/986 green; JS and Wasm binding builds clean.

## Task Commits

1. **Task 1 RED: add failing fathom_lineage_v1 wire tests** - `f970753` (test)
2. **Task 1 GREEN: implement fathom.lineage.v1 wire + catalog_json parsing** - `e748129` (feat)
3. **Task 2: catalog_json parsing behavior tests** - `bea8856` (test)
4. **Task 3: fathom-sql lineage subcommand + --catalog + D-39 exit codes** - `c84020d` (feat)

**Plan metadata:** (separate `docs(07-04)` commit)

## Files Created/Modified
- `binding/schema.mbt` - `LINEAGE_SCHEMA_VERSION` + `validate_schema_version` 8th branch (pure add)
- `binding/json.mbt` - `lineage_result_json` envelope serializer
- `binding/exports.mbt` - `fathom_lineage_v1` wire export (flink gate + catalog FATHOM-SCHEMA-004)
- `binding/catalog_json.mbt` (new) - `parse_catalog_json` (tables/db_tables/functions → StaticCatalog, structured errors)
- `binding/moon.pkg` - js+wasm exports += `fathom_lineage_v1`; + `@analyzer` import
- `fathom-sql/args.mbt` - lineage whitelist + `Command.catalog` + `--catalog` flag
- `fathom-sql/run.mbt` - `run_lineage` (D-39 0/1/2) + usage_text/usage_error_message update
- `fathom-sql/main.mbt` - lineage dispatch
- `fathom-sql/cli_test.mbt` - lineage exit-code matrix + updated usage-text assertions
- `test/binding_wire_test.mbt` (new) - binding wire + catalog_json behavior tests
- `test/moon.pkg` - + `@binding` + `@utf8` imports

## Decisions Made
- **catalog_json.mbt created in Task 1**: `fathom_lineage_v1` needs `parse_catalog_json` to compile atomically; Task 2 then adds its behavior tests. The plan's file-boundary was interpreted — total modified set identical to `files_modified`.
- **Binding tests hosted in test/**: the binding foreign_library `#export_name` cannot compile when binding is the direct native test target (error 4219, pre-existing). `test/` imports `@binding` as a dependency (proven natively testable by fathom-sql) and runs 209 tests.
- **Flink gate before catalog/file handling** in `run_lineage` — wire-consistent with `fathom_lineage_v1` (D-08 double-insurance).
- **Verification adapted to moon 0.1.20260724**: root `moon check --target native` / `moon test --package binding` fail on the pre-existing binding config; used `moon check --package-path binding`, `moon build --target js|wasm --package binding`, `moon test --package test`/`fathom-sql`.
- **CLI parse-failure test uses oversized input** (8 MiB+1 → InputTooLarge exit 1) since `b"bad"` parses to a valid recovered tree on this toolchain.

## Deviations from Plan

### Auto-fixed Issues

**1. `unused_mut` on array builders in catalog_json.mbt**
- **Found during:** Task 1 GREEN (first compile)
- **Issue:** `let mut tables/columns/param_types` declared `mut` but only mutated via `Array.push` (arrays are reference-mutated in place).
- **Fix:** Removed the `mut` bindings.
- **Files modified:** binding/catalog_json.mbt
- **Committed in:** e748129

**2. Missed `catalog: None` on one nested Command literal (8-space indent)**
- **Found during:** Task 3 verification
- **Issue:** A Command literal inside `cli_flag_surface_parses_and_drives_options` used 8-space indentation and was missed by the bulk replace_all (4-space pattern).
- **Fix:** Added `catalog: None` to that literal.
- **Files modified:** fathom-sql/cli_test.mbt
- **Committed in:** c84020d

**3. Two pre-existing usage-text assertions needed the lineage surface**
- **Found during:** Task 3 verification
- **Issue:** `cli_d11_exit_2_matrix_through_usage_error_message` and `cli_usage_error_message_renders_exit_2_text` asserted the OLD subcommand list ("...lsp, lint, or fingerprint") and usage text without lineage — they failed once the usage surface grew.
- **Fix:** Updated the assertions to the new surface ("...lint, fingerprint, or lineage" and `parse|format|lsp|lint|fingerprint|lineage`).
- **Files modified:** fathom-sql/cli_test.mbt
- **Committed in:** c84020d

**4. `b"bad"` does not produce a parse-failure exit for lineage**
- **Found during:** Task 3 verification
- **Issue:** The parse-failure test used `b"bad"` expecting exit 1, but on this toolchain `bad` parses to a valid recovered tree (lineage derives a `requires-complete-parse` gap → exit 0).
- **Fix:** Switched the test to oversized input (`Bytes::make(8 MiB + 1, 32)` → `InputTooLarge` → exit 1).
- **Files modified:** fathom-sql/cli_test.mbt
- **Committed in:** c84020d

### Interpreted per the plan's own contracts

**1. `catalog_json.mbt` created in Task 1, not Task 2**
- **Found during:** Task 1 (GREEN)
- **Issue:** The plan's Task 1 `<files>` omits catalog_json.mbt, but `fathom_lineage_v1`'s catalog_json handling requires `parse_catalog_json` to compile (Task 1's verify must pass atomically). Creating it in Task 1 makes Task 2 a test-only commit.
- **Fix:** Created `binding/catalog_json.mbt` fully in Task 1 (no placeholder); Task 2 adds the 4 behavior tests. The total modified-file set matches the plan's `files_modified`.
- **Files modified:** binding/catalog_json.mbt (Task 1), test/binding_wire_test.mbt (Task 2)
- **Committed in:** e748129 / bea8856

**2. Binding wire tests hosted in test/ rather than in binding/**
- **Found during:** Task 1 (test location)
- **Issue:** The plan requires "binding 包内 test 全绿", but `moon test --target native --package binding` fails on the pre-existing binding foreign_library `#export_name` (error 4219, documented in 07-03). Binding cannot host native test blocks.
- **Fix:** Hosted all binding wire/catalog_json tests in `test/binding_wire_test.mbt` (test/ imports @binding as a dependency and runs natively — 209/209). Same behavioral coverage, run via `moon test --package test`.
- **Files modified:** test/moon.pkg, test/binding_wire_test.mbt
- **Committed in:** f970753 / bea8856

**3. Verification command adaptation (plan's `moon check --target native` / `moon test --package binding` not runnable locally)**
- **Found during:** Task 1 baseline probe
- **Issue:** Root `moon check --target native` and `moon test --target native --package binding` fail on the pre-existing binding `#export_name` config with the pinned moon 0.1.20260724 (CI uses `latest`, where it passes).
- **Fix:** Used the working equivalents: `moon check --package-path binding`, `moon build --target js|wasm --package binding` (validates the wire export registration on the actual foreign targets), and `moon test --package test` / `--package fathom-sql`. The full CI native matrix (986/986) passes.
- **Files modified:** none (verification only)

---

**Total deviations:** 4 auto-fixed (3 test mechanics, 1 behavioral test correction); 3 documented interpretations
**Impact on plan:** All deviations keep the behavioral surface identical to the plan; no scope creep. The verification adaptation is forced by the pre-existing toolchain limitation.

## Issues Encountered
- `moon fmt --check` with the local pinned moon 0.1.20260724 reports diffs on MY files AND on pre-existing untouched files (api/moon.pkg, analyzer/*, fathom-sql/ffi.mbt, moon.mod) — the local formatter version wants `///|` doc markers, no `@alias` imports, and blank lines after `pkgtype`. This is toolchain-version drift (CI runs `latest`), NOT a regression introduced here; the committed repo style is the source of truth and my files match it.
- Root `moon check --target native` fails locally on the pre-existing binding `#export_name` foreign_library config (error 4219) — same limitation documented in the 07-03 summary.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `fathom.lineage.v1` wire + `fathom_lineage_v1` ABI are the frozen host-consumer surface for 07-05 parity: same fixture on native/js/wasm must yield byte-identical edges/gaps (edge/gap ordering contract locked by the envelope serializer and StaticCatalog LinkedHashMap order).
- `parse_catalog_json` is the public catalog-input contract for the wire and CLI (D-05).
- `fathom-sql lineage --catalog <file>` gives terminal users the D-39 0/1/2 lineage check.
- docs/API.md Lineage section can now document `fathom_lineage_v1` (8th export), `lineage_result_json`, `parse_catalog_json`, and the CLI subcommand.

---
*Phase: 07-column-lineage*
*Completed: 2026-08-11*

## Self-Check: PASSED
- Files verified on disk: binding/schema.mbt, binding/json.mbt, binding/exports.mbt, binding/catalog_json.mbt, binding/moon.pkg, fathom-sql/args.mbt, fathom-sql/run.mbt, fathom-sql/main.mbt, fathom-sql/cli_test.mbt, test/binding_wire_test.mbt, test/moon.pkg, .planning/phases/07-column-lineage/07-04-SUMMARY.md
- Commits verified in git log: f970753 (Task 1 RED), e748129 (Task 1 GREEN), bea8856 (Task 2), c84020d (Task 3)
- Test runs: full native matrix 986/986; `moon check --package-path binding` 0 errors; `moon build --target js|wasm --package binding` 0 errors; CLI binary smoke (exit 0 envelope / flink exit 2 / bad catalog exit 2 / star-expansion 2 edges)
- Forbidden dirs untouched: `git status --short -- lineage/ api/ parity/ parser/ analyzer/` empty
