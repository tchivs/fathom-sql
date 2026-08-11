---
phase: 07-column-lineage
verified: 2026-08-11T00:00:00Z
status: passed
score: 15/15 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification: false
---

# Phase 7: Column Lineage (LINE-01) Verification Report

**Phase Goal:** 交付基于 ANAL-01 解析结果的列级血缘，跨查询/视图/CTE/INSERT 展开，并对无 catalog 场景诚实报告 gap。
**Verified:** 2026-08-11
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

The phase goal is achieved end to end. The `lineage/` library derives column-level source→target edges across SELECT / INSERT / CTE / set operations / view expansion using the ANAL-01 analyzer's resolved bindings and the public select-model re-parser (zero re-implementation of name resolution), and every unresolved / no-catalog / incomplete-parse situation produces an explicit honest gap — never a fabricated edge. The frozen parser baseline is untouched, the D-08 flink gate returns structured FATHOM-SCHEMA errors (never silent), `fathom.lineage.v1` is a pure-add 8th schema namespace, and cross-target byte parity is proven on native/js/wasm.

### Observable Truths

| #   | Truth   | Status     | Evidence       |
| --- | ------- | ---------- | -------------- |
| 1   | SC1: User can inspect column-level lineage across SELECT/INSERT/CTE/set operations and view expansion, with source positions on edges | ✓ VERIFIED | `lineage/edges.mbt` `derive_lineage_inner` walks statement bodies (Select/CreateView/Insert); `derive_model` handles CTEs (CTE-qualified targets) and UNION branches (positional mapping via `output_names`); `derive_insert_body` handles INSERT positional mapping; CREATE VIEW bodies derive edges qualified by the view name. Every edge carries `source_start_byte`/`source_end_byte`/`target_start_byte`/`target_end_byte` flattened byte spans. Behavioral tests: `lineage D-01 expression passthrough a + b as x`, `lineage CTE body qualified edge and UNION positional mapping`, `lineage view body edge to view output column`, `lineage INSERT positional mapping with catalog`, `test/lineage_test.mbt` integration goldens. |
| 2   | SC2: Unresolved refs / `*` without catalog / external views without metadata produce explicit `requires-catalog` / `unresolved-reference` gaps — never fabricated edges (incl. CR-01 INSERT fix) | ✓ VERIFIED | `lineage/gaps.mbt` maps unknown-table→(requires-catalog no-catalog / unresolved-reference with catalog), unknown-column/function/ambiguous→unresolved-reference; `edges.mbt` star self-check emits requires-catalog when `expand_star` yields zero columns; `views.mbt` external-view-no-metadata→requires-catalog; `insert.mbt` `resolve_insert_source_tables`/`source_ref_resolved` suppress source edges from unresolved INSERT source tables and emit one honest gap (CR-01 fix). Tests: `lineage star no catalog zero edges with requires-catalog gap`, `lineage unresolved reference maps to gap`, `lineage external view star without metadata is requires-catalog`, `lineage INSERT source unresolved no fabricated edges`, `lineage INSERT without column list no catalog honest gaps`. |
| 3   | Analyzer lineage-facing public surface opened with ANAL-01 zero drift: 8 select-model types `pub(all)`, re-parser/body-location helpers `pub fn`, thin `view_body_location`/`insert_body_location` wrappers, `has_error_missing` public | ✓ VERIFIED | `analyzer/select_model.mbt` `pub(all)` ClauseKind/TokenSlice/NameRef/SelectItem/FromItem/CteDef/SelectCore/SelectModel; `analyzer/select_parser.mbt` `pub fn source_tokens/matching_paren/collect_refs/split_select_model`; `analyzer/resolve.mbt` `pub fn qualified_ref_at/find_word_at_depth0/slice_tokens/has_error_missing/view_body_location/insert_body_location`. `test/analyzer_public_surface_test.mbt` end-to-end locks the surface. Existing analyzer tests and snapshots pass (zero drift); `parser/` untouched. |
| 4   | `* EXCEPT (cols)` honest expansion: excluded columns produce no binding/edge (SC2) | ✓ VERIFIED | `SelectItem.except_cols` captures exclusion slices (`select_parser.mbt` `build_select_item`); `analyzer/resolve.mbt` `expand_star`/`emit_star_columns`/`is_excepted` apply exclusion (unquoted ASCII case-fold, quoted byte-exact). Tests: `wb expand_star except exclusion`, `lineage star all-excluded except list is not a catalog gap`. |
| 5   | `lineage/` independent library with D-21 import discipline: moon.pkg imports ONLY analyzer + syntax (+ core/debug) | ✓ VERIFIED | `lineage/moon.pkg` imports `fathom/sql/analyzer`, `fathom/sql/syntax`, `moonbitlang/core/debug` only. No parser/source/dialect. Negative gate holds: `parser/moon.pkg` has no lineage/analyzer import; `analyzer/moon.pkg` imports only syntax. |
| 6   | Lineage model: `LineageEdge`/`LineageGap`/`LineageResult` `pub(all)` all-pub fields + derive(Eq, Debug); D-06 gaps strictly separate from edges; deterministic ordering is a public contract | ✓ VERIFIED | `lineage/model.mbt` full-pub structs with derive(Eq, @debug.Debug); gap-code consts `GAP_REQUIRES_CATALOG`/`GAP_UNRESOLVED_REFERENCE`/`GAP_REQUIRES_COMPLETE_PARSE`. `derive_item`/`map_diagnostic_gaps` keep gaps and edges in separate arrays. Ordering contract documented (document statement order → branch/CTE order → item order → refs order; star expansion scope-entry × catalog column order, LinkedHashMap determinism) and locked by parity tests. |
| 7   | D-01 expression passthrough: every resolved column ref in an output expression contributes one edge to that output column | ✓ VERIFIED | `lineage/edges.mbt` `derive_item` loops `item.refs`, matches each to a Column binding by span (`column_binding_at`), pushes one edge per ref to the item target. Target = alias_slice / single-ref span / star span. Tests: `lineage D-01 expression passthrough a + b as x`, `lineage D-01 single ref and function argument`, parity `lineage_export_expression_passthrough_catalog_cross_target`. |
| 8   | D-03 view registry + `ViewCatalog[T]`: view output columns from body, view-first lookup with case-fold + shadow, external view without metadata → requires-catalog | ✓ VERIFIED | `lineage/views.mbt` `build_view_registry` maps in-document CREATE VIEW names → output columns (explicit column-list preferred per WR-03 `view_column_list`); `ViewCatalog[T]` implements `Catalog::table` view-first (shadow), `table_in_db`/`function` delegate. Tests: `lineage view registry and ViewCatalog shadow`, `lineage view column list extraction`. |
| 9   | D-04 INSERT positional mapping + VALUES no edges + no-column-list-no-catalog honest gap; CR-01 fix (unresolved source tables → gap, no edges) | ✓ VERIFIED | `lineage/insert.mbt` `derive_insert_source_edges` positionally maps trailing SELECT outputs to the target column list; `resolve_insert_target_columns` applies D-03 quoted byte-exact recheck (WR-02); `star_seen` stops positional mapping after an unexpanded star (WR-01); VALUES rows produce no edges; unresolved source tables emit exactly one honest gap and suppress source edges. Tests: `lineage INSERT positional mapping with catalog`, `lineage INSERT source unresolved no fabricated edges`, `lineage INSERT without column list no catalog honest gaps`, `lineage INSERT VALUES produces no edges`. |
| 10  | `api.lineage_text(raw, parse_options, catalog: StaticCatalog?)` library entry + D-08 flink gate (structured error, never silent) + D-38 type re-exports | ✓ VERIFIED | `api/api.mbt` `pub fn lineage_text` reuses `parse_document`, rejects flink after parse with structured `UnknownProfile` (FATHOM-SCHEMA family), dispatches Some/None catalog → `derive_lineage` / `derive_lineage_without_catalog`; `pub type LineageResult/LineageEdge/LineageGap/StaticCatalog` re-exports. Tests: `api_lineage_text_doris_select_basic_ok`, `api_lineage_text_flink_gate_structured_error`, `api_lineage_text_star_no_catalog_requires_catalog_gap`, `api_lineage_text_input_too_large_parse_error`, `api_lineage_text_empty_document_ok_empty`. |
| 11  | `fathom.lineage.v1` is the 8th schema namespace (pure-add): `LINEAGE_SCHEMA_VERSION` + `validate_schema_version` appended branch, prior 7 namespaces untouched | ✓ VERIFIED | `binding/schema.mbt` `pub const LINEAGE_SCHEMA_VERSION = "fathom.lineage.v1"`; `validate_schema_version` adds the lineage branch to the existing match arms. `parity/export_smoke_test.mbt` `schema_v2_bump_is_additive` asserts the 8th namespace appears while the prior seven remain usable (Pitfall V6). |
| 12  | `fathom_lineage_v1(raw, dialect, profile, mode, catalog_json)` wire export: dialect-first validation, flink → FATHOM-SCHEMA-003 "lineage is Doris-only", bad catalog → FATHOM-SCHEMA-004, envelope; registered in js+wasm exports | ✓ VERIFIED | `binding/exports.mbt` `#export_name("fathom_lineage_v1")`; `binding/moon.pkg` js+wasm `exports` lists each contain `fathom_lineage_v1` (8th export). Tests: `binding_lineage_v1_envelope_contains_metadata_edges_gaps`, `binding_lineage_v1_flink_gate_structured_error`, `binding_lineage_v1_unknown_dialect_structured_error`, `binding_lineage_v1_bad_catalog_json_structured_004_error`. |
| 13  | `parse_catalog_json`: empty/`{}` → no catalog; tables/db_tables/functions → StaticCatalog; invalid input → structured error (never silent fallback) | ✓ VERIFIED | `binding/catalog_json.mbt` `pub fn parse_catalog_json(bytes) -> Result[@api.StaticCatalog?, String]`; empty bytes → Ok(None); malformed JSON/fields → Err(String) → FATHOM-SCHEMA-004 at wire/CLI. Tests: `binding_parse_catalog_json_empty_bytes_and_empty_object_no_catalog`, `binding_parse_catalog_json_tables_builds_catalog`, `binding_parse_catalog_json_db_tables_and_functions`, `binding_parse_catalog_json_invalid_inputs_structured_errors`. |
| 14  | `fathom-sql lineage` subcommand with `--catalog` and D-39 exit codes (0 envelope / 1 parse failure / 2 usage+config incl. flink gate) | ✓ VERIFIED | `fathom-sql/args.mbt` subcommand whitelist + `--catalog` flag; `fathom-sql/run.mbt` `run_lineage` calls `@api.lineage_text` and serializes via `@binding.lineage_result_json` (CLI holds no lineage logic — D-37/D-38); flink → exit 2 "lineage is Doris-only"; bad catalog → exit 2 FATHOM-SCHEMA-004. Tests: `cli_lineage_exit_0_envelope`, `cli_lineage_flink_gate_exit_2`, `cli_lineage_bad_catalog_path_exit_2`, `cli_lineage_bad_catalog_json_exit_2`, `cli_lineage_parse_failure_exit_1`, `cli_lineage_star_with_catalog_exit_0_two_edges`, `cli_lineage_star_no_catalog_requires_catalog_gap`. |
| 15  | Cross-target byte parity + wire smoke + additive schema assertion + bilingual docs + COVERAGE.md declaration | ✓ VERIFIED | `parity/lineage_parity_test.mbt` hardcoded `fathom_lineage_v1` envelope assertions run identically on native/js/wasm; `parity/run_js.mbt` + `run_wasm.mbt` smoke the Bytes+String+Int ABI (no host IO); `docs/API.md` + `docs/zh-CN/API.md` Lineage Entry Points sections (lineage_text signature, gap-code table, D-08 gate, fathom_lineage_v1 wire row); `COVERAGE.md` api-coverage declaration. Orchestrator suite results confirm byte-identical digest across targets. |

**Score:** 15/15 truths verified (0 present-but-behavior-unverified, 0 overrides)

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `lineage/moon.pkg` | library, imports only analyzer + syntax (+ core/debug) | ✓ VERIFIED | D-21 negative gate holds |
| `lineage/model.mbt` | pub(all) LineageEdge/LineageGap/LineageResult + gap-code consts | ✓ VERIFIED | all-pub fields, derive(Eq, Debug) |
| `lineage/edges.mbt` | `derive_lineage`/`derive_lineage_without_catalog` + D-01 passthrough + star self-check | ✓ VERIFIED | SELECT/CTE/UNION/CREATE VIEW walk, span association |
| `lineage/gaps.mbt` | D-06 diagnostic→gap mapping, strictly separate | ✓ VERIFIED | requires-catalog/unresolved-reference/requires-complete-parse |
| `lineage/views.mbt` | view registry + ViewCatalog[T] + external-view gap | ✓ VERIFIED | WR-03 column-list support |
| `lineage/insert.mbt` | INSERT positional mapping + honest gaps | ✓ VERIFIED | CR-01/WR-01/WR-02 fixes present |
| `analyzer/select_model.mbt` | pub(all) 8 types + SelectItem.except_cols | ✓ VERIFIED | — |
| `analyzer/select_parser.mbt` | pub fn source_tokens/split_select_model/... | ✓ VERIFIED | EXCEPT captured in build_select_item |
| `analyzer/resolve.mbt` | pub fn has_error_missing/view_body_location/insert_body_location; expand_star applies except_cols | ✓ VERIFIED | — |
| `api/api.mbt` | `lineage_text` + flink gate + D-38 re-exports | ✓ VERIFIED | — |
| `binding/schema.mbt` | LINEAGE_SCHEMA_VERSION 8th namespace | ✓ VERIFIED | pure-add branch |
| `binding/exports.mbt` + `binding/moon.pkg` | `fathom_lineage_v1` export + js/wasm registration | ✓ VERIFIED | — |
| `binding/catalog_json.mbt` | parse_catalog_json structured | ✓ VERIFIED | — |
| `binding/json.mbt` | lineage_result_json envelope (edges+gaps) | ✓ VERIFIED | — |
| `fathom-sql/run.mbt` + `args.mbt` + `main.mbt` | lineage subcommand + --catalog + D-39 | ✓ VERIFIED | — |
| `parity/lineage_parity_test.mbt` + `run_js.mbt` + `run_wasm.mbt` + `export_smoke_test.mbt` | cross-target parity + smoke + additive assertion | ✓ VERIFIED | — |
| `test/analyzer_public_surface_test.mbt` + `test/lineage_test.mbt` + `test/binding_wire_test.mbt` | cross-package integration + goldens | ✓ VERIFIED | test/moon.pkg imports lineage |
| `docs/API.md` + `docs/zh-CN/API.md` | Lineage Entry Points + wire row + D-08/SC2 notes | ✓ VERIFIED | — |
| `.planning/phases/07-column-lineage/COVERAGE.md` | api-coverage declaration | ✓ VERIFIED | "No external API integration" locked shape |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `source_tokens` | `split_select_model` | public token stream → structured SelectModel | WIRED | edges.mbt/views.mbt/insert.mbt re-parse body slices; empty stream → Some(empty model) |
| `expand_star` | `except_cols` | single-point exclusion in analyzer | WIRED | resolve.mbt emit_star_columns skips excepted columns |
| `derive_lineage` | `@analyzer.analyze` + `split_select_model` | span association of bindings to NameRefs | WIRED | column_binding_at by start/end byte |
| `ViewCatalog[T].table` | view registry → inner catalog | view-first lookup, shadow | WIRED | views.mbt pub impl Catalog |
| star zero-columns | requires-catalog gap | expand_star silent-zero self-check | WIRED | edges.mbt derive_item + WR-04 tests |
| edge/gap ordering | parity envelope bytes | public contract | WIRED | parity hardcoded assertions |
| `lineage_text` | `parse_document` → `derive_lineage` | library entry chain | WIRED | api.mbt:847-864 |
| flink gate | api/binding/CLI three layers | double insurance | WIRED | UnknownProfile / FATHOM-SCHEMA-003 / exit 2 |
| `fathom_lineage_v1` | `catalog_json` → StaticCatalog → `lineage_text` | catalog injection chain | WIRED | exports.mbt:153-190 |
| `validate_schema_version` | `schema_v2_bump_is_additive` | 8th namespace additive lock | WIRED | export_smoke_test asserts |
| CLI `run_lineage` | `@api.lineage_text` only | D-37/D-38 thin adapter | WIRED | run.mbt:215-262 |
| `lineage_parity_test` | `fathom_lineage_v1` ABI | cross-target byte identity | WIRED | run_js/run_wasm smoke + compare_backends digest |
| docs Wire Exports table | binding/moon.pkg exports list | registration consistency | WIRED | both list fathom_lineage_v1 |
| `fathom_lineage_v1` (binding) | `@api.LineageResult` | D-38 envelope construction without lineage/ import | WIRED | json.mbt lineage_result_json consumes @api types |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `derive_lineage` | bindings + SelectModel | `@analyzer.analyze` real resolution + `split_select_model` | Yes | ✓ FLOWING |
| `lineage_text` | LineageResult | `parse_document` → `derive_lineage`/`derive_lineage_without_catalog` | Yes | ✓ FLOWING |
| `fathom_lineage_v1` | envelope Bytes | `lineage_text` → `lineage_result_json` | Yes | ✓ FLOWING |
| `run_lineage` | CliOutcome | `@api.lineage_text` → `@binding.lineage_result_json` | Yes | ✓ FLOWING |
| catalog path | StaticCatalog | `parse_catalog_json` real metadata or honest None | Yes | ✓ FLOWING (None → honest gaps, SC2) |

### Behavioral Spot-Checks

| Behavior | Command (performed by orchestrator) | Result | Status |
| -------- | ----------------------------------- | ------ | ------ |
| lineage/ library suite (edge/gap derivation, CR-01 fix, view/INSERT) | `moon test --package lineage` | 19/19 | ✓ PASS |
| cross-package integration (public surface, lineage goldens, wire) | `moon test --package test` | 209/209 | ✓ PASS |
| api lineage entry + flink gate + catalog semantics | `moon test --package api` | 636/636 | ✓ PASS |
| CLI lineage exit-code matrix | `moon test --package fathom-sql` | 37/37 | ✓ PASS |
| cross-target byte parity | `moon test --package parity` native/js/wasm | 605/605 ×3 | ✓ PASS |
| aggregate digest identical across targets | `python3 scripts/compare_backends.py` | exit 0; digest `2eda3582…` identical | ✓ PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` probes are declared or conventional for this phase (library/CLI/wire phase, not a migration/tooling phase). Behavioral evidence is the test suites listed above, executed by the orchestrator.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| LINE-01 | 07-01..07-05 | User can inspect column-level data lineage across SELECT/INSERT/CTE/set operations and view expansion; unresolved refs and `*` without catalog produce explicit "requires catalog" gaps rather than fabricated edges | ✓ SATISFIED | All 15 truths verified; lineage/ library + api.lineage_text + fathom.lineage.v1 + CLI + parity + docs |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| — | — | No TBD/FIXME/XXX/PLACEHOLDER markers in lineage/, binding/, api/ | ℹ️ | None |
| `lineage/views.mbt` (IN-03) | 83-124 | Star-over-view chains degrade to requires-catalog even with full catalog | ℹ️ Info (documented limitation) | Honest gap produced; consistent with SC2; retained per code review |
| `lineage/views.mbt` (IN-04) | 151-161 | db-qualified CREATE VIEW misses the registry | ℹ️ Info (documented limitation) | Treated as external object → honest requires-catalog gap; retained per code review |
| `api/api.mbt` (IN-01) | 856-858 | Library-surface flink gate message is generic "unsupported profile" | ℹ️ Info (documented limitation) | Structured FATHOM-SCHEMA error still satisfies D-08; wire/CLI carry explicit "lineage is Doris-only" |
| `binding/catalog_json.mbt` (IN-02) | 183-185 | `min_arity` not bounds-validated | ℹ️ Info (documented limitation) | Informational; other fields are shape-validated |

### Known Limitations (accepted as informational per 07-REVIEW.md)

IN-01..IN-04 are retained as documented limitations. None violates the LINE-01 must-have contract: they either produce honest gaps consistent with SC2 (never fabricated edges) or are robustness/documentation nuances on the wire surface. All were explicitly classified informational by the code review and retained in plan/research notes.

### Human Verification Required

None. Every must-have is exercised by a behavioral test that the orchestrator confirmed passing (lineage 19/19, test 209/209, api 636/636, fathom-sql 37/37, parity 605/605 ×3 with identical digest). No visual/user-flow/real-time/external-service dimensions apply to this library/CLI/wire phase.

### Gaps Summary

No gaps found. All 15 must-haves are VERIFIED against the actual codebase (not SUMMARY claims). The code review's single critical finding (CR-01: INSERT trailing-SELECT fabricated edges) and all four warnings (WR-01..04) are confirmed fixed in the source and locked by white-box tests. The frozen parser baseline was not touched (parser/moon.pkg has no lineage/analyzer import; all five plan summaries report "Forbidden dirs untouched" including `git diff --stat parser/` empty at 07-01).

---

_Verified: 2026-08-11_
_Verifier: Claude (gsd-verifier)_
