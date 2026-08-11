---
phase: 07-column-lineage
reviewed: 2026-08-11T00:00:00Z
depth: standard
files_reviewed: 30
files_reviewed_list:
  - analyzer/select_model.mbt
  - analyzer/select_parser.mbt
  - analyzer/resolve.mbt
  - analyzer/analyzer_wbtest.mbt
  - lineage/moon.pkg
  - lineage/model.mbt
  - lineage/edges.mbt
  - lineage/gaps.mbt
  - lineage/views.mbt
  - lineage/insert.mbt
  - lineage/lineage_wbtest.mbt
  - api/api.mbt
  - api/moon.pkg
  - binding/schema.mbt
  - binding/json.mbt
  - binding/exports.mbt
  - binding/catalog_json.mbt
  - binding/moon.pkg
  - fathom-sql/args.mbt
  - fathom-sql/run.mbt
  - fathom-sql/main.mbt
  - fathom-sql/cli_test.mbt
  - parity/lineage_parity_test.mbt
  - parity/export_smoke_test.mbt
  - parity/run_js.mbt
  - parity/run_wasm.mbt
  - test/analyzer_public_surface_test.mbt
  - test/lineage_test.mbt
  - test/binding_wire_test.mbt
  - test/moon.pkg
findings:
  critical: 1
  warning: 4
  info: 4
  total: 9
status: issues
---

# Phase 7: Code Review Report

**Reviewed:** 2026-08-11
**Depth:** standard (per-file analysis with cross-file where it matters)
**Files Reviewed:** 30
**Status:** issues_found

## Summary

Phase 7 delivers LINE-01 column lineage end to end: the `lineage/` library (`derive_lineage` / `derive_lineage_without_catalog`), the analyzer Wave-0 public surface (`pub(all)` select-model types, `* EXCEPT` honest expansion), `api.lineage_text`, the `fathom.lineage.v1` wire export, the `fathom-sql lineage` CLI subcommand, and three-target parity. The D-21 import discipline (lineage/ imports only analyzer+syntax) and the D-08 flink gate are correctly implemented and well tested; schema v2 is a clean pure-add of the 8th namespace; catalog JSON parsing is structured-error-on-invalid and never silently falls back. The star self-check (`requires-catalog` when `expand_star` silently yields zero columns) is the right SC2 mechanism and is wired consistently.

The most significant problem is in the INSERT trailing-SELECT path: because the analyzer never analyzes the trailing SELECT body, `derive_insert_source_edges` emits edges for column references whose source table is completely unresolved, and no gap is produced — a direct tension with the SC2 "never fabricate lineage edges / unresolved refs produce explicit gaps" invariant. This behavior is locked in by the white-box test `lineage INSERT positional mapping`. The remaining findings are narrower correctness gaps (INSERT source star positional misalignment, quoted-identifier case-fold on INSERT target-column resolution, ignored CREATE VIEW column-alias lists) plus robustness/documentation notes.

## Critical Issues

### CR-01: INSERT trailing-SELECT source refs fabricate lineage edges for unresolved references with no gap (SC2)

**File:** `lineage/insert.mbt:119-158` (`derive_insert_source_edges`); locked in by `lineage/lineage_wbtest.mbt:340-360` (`lineage INSERT positional mapping`)

**Issue:** `analyze_dml_body` never analyzes the trailing SELECT body, so its table/column refs have no analyzer bindings and produce no analyzer diagnostics. `derive_insert_source_edges` then unconditionally emits an edge per `item.refs`, falling back to `ref_last_part(ref)` (source spelling) for both `source_name` and `source_resolved_to`. For `INSERT INTO t(c1) SELECT a FROM missing_table` (no catalog), the result is a confident edge `a -> t.c1` with **zero gaps** — the unresolved table `missing_table` is silently dropped and never reported. This violates SC2/D-06, which require unresolved references to produce an explicit `requires-catalog` / `unresolved-reference` gap and forbid fabricating edges. The white-box test even constructs this case with an empty catalog, empty bindings, and no diagnostics and asserts 2 edges / 0 gaps, so the defect is enshrined as expected behavior.

Even with a full catalog, the trailing body is unanalyzed, so `INSERT INTO t(c1) SELECT a FROM u` emits an unqualified `a -> t.c1` with no verification that `u.a` exists — a downstream lineage consumer cannot distinguish this from a resolved reference.

**Fix:** Resolve the trailing SELECT body's FROM/JOIN table refs against the catalog before emitting source edges (the model's `FromItem.name` refs are already available from `split_select_model`). For each source table that does not resolve: emit a `requires-catalog` gap (no catalog injected) or `unresolved-reference` gap (catalog injected) at the table-ref span, and either suppress the body's source edges or qualify them so the unresolved provenance is explicit. At minimum, emit the gap and stop claiming a resolved source. Update the white-box test to reflect the honest-gap contract.

## Warnings

### WR-01: INSERT source star misaligns subsequent positional columns

**File:** `lineage/insert.mbt:120-157`

**Issue:** In `derive_insert_source_edges`, a star item emits a `requires-catalog` gap but does **not** advance `pos`; only the non-star branch does `pos = pos + 1`. For `INSERT INTO t(c1,c2) SELECT *, x FROM u`, the star reports a gap and then `x` is mapped at `pos = 0` to `t.c1` instead of `t.c2`. Because a star's output column count is unknowable without catalog expansion, any positional mapping after a star is unsound; the current code silently misaligns.

**Fix:** When a star item is encountered in the INSERT source, emit the `requires-catalog` gap and stop positional mapping for the remainder of that branch (alignment is unknowable), or conservatively drop subsequent edges for that branch. Do not continue assigning positions after an unexpanded star.

### WR-02: `resolve_insert_target_columns` misses the quoted-identifier byte-exact rule (Pitfall V1)

**File:** `lineage/insert.mbt:78-104`

**Issue:** For a no-column-list INSERT, target column names come from `Catalog::table` / `Catalog::table_in_db` keyed by `identifier_text(...)`. `identifier_text` strips quotes, and the trait lookup (e.g. `StaticCatalog`) folds ASCII case — so a **quoted** target table `` INSERT INTO `T` SELECT ... `` resolves case-insensitively to a catalog table named `t`, producing the wrong target column list. The analyzer's own resolve path (`resolve_table_name_ref`) applies a quoted byte-exact re-check (D-03); this helper bypasses it.

**Fix:** Reuse the analyzer's quoted-aware resolution (or replicate the `is_quoted` → byte-exact rule) when resolving the target table's column list, matching `resolve_table_name_ref` semantics. Add a test with a quoted target table whose catalog entry differs only in case.

### WR-03: CREATE VIEW explicit column-alias list is ignored by the view registry

**File:** `lineage/views.mbt:56-80` (`view_output_columns`); analyzer skips the list at `analyzer/resolve.mbt:1461-1468`

**Issue:** For `CREATE VIEW v (x, y) AS SELECT a, b FROM t`, `view_output_columns` names the view's output columns from the SELECT body (`a`, `b`) and never reads the explicit `(x, y)` list. `SELECT * FROM v` then expands to edges targeting `a`/`b` rather than the declared view columns `x`/`y` — incorrect view expansion (D-03) for the column-alias-list form, which Doris accepts.

**Fix:** When a CREATE VIEW body carries an explicit column-name list between the view name and `AS`, use those names (in order) as the view's output-column names instead of the body-derived names. `view_body_location` already locates the list; expose its token range and consume it in `view_output_columns` / `build_view_registry`.

### WR-04: Star self-check is suppressed by a coarse body-wide table-binding signal

**File:** `lineage/edges.mbt:333-345` (star self-check), `:616` (`body_has_table_binding` computed once per statement body), propagated into subqueries/CTEs at `:419/:439/:482/:501`

**Issue:** `body_has_table_binding` is computed for the whole statement body and threaded down to every nested body. A star with zero expanded column bindings is treated as "all-excluded / empty, not a catalog miss" whenever *any* table in the body resolved. Two silent cases:
1. A catalog table explicitly declared with `"columns": []` — `SELECT * FROM t` yields zero bindings, a Table binding exists, so **no edge and no gap** are produced (a silent drop rather than an honest `requires-catalog`).
2. A nested subquery star over an unresolvable table inside a body where another table resolved — the star is silent (only the `unknown-table` diagnostic channel reports, so the `requires-catalog` code is never chosen for the star itself).

**Fix:** Scope the "has a resolvable table" signal to the specific star: for `table.*`, check whether *that table* resolved; for bare `*`, require at least one scope entry with a non-empty column list. When the catalog explicitly provides a table with an empty column array, report `requires-catalog` (no column metadata) instead of silently producing nothing.

## Info

### IN-01: Library-surface flink gate returns a misleading message

**File:** `api/api.mbt:856-858`

**Issue:** `lineage_text` rejects a flink selection with `Err(UnknownProfile(profile_id))`, which serializes as "unsupported profile: flink-2.3.0" — implying the profile is invalid rather than that lineage is Doris-only. The wire (`binding/exports.mbt`) and CLI carry the explicit "lineage is Doris-only" message, but direct `@api.lineage_text` library callers get the generic one. The structured error satisfies D-08, but the message is misleading.

**Fix:** Return a dedicated `ParseError` variant (or reuse `UnsupportedFeatureIntroduction`-style messaging) so the library surface also conveys "lineage is Doris-only" for a valid flink selection.

### IN-02: `min_arity` in catalog JSON is not bounds-validated

**File:** `binding/catalog_json.mbt:183-185`

**Issue:** `Some(Json::Number(n, ..)) => n.to_int()` accepts any JSON number — fractional values truncate and huge values may saturate — on caller-injected, untrusted input. Other catalog fields are shape-validated; this one is not.

**Fix:** Validate `min_arity` is an integral non-negative value within a sane range, returning `Err(String)` otherwise, consistent with the rest of `parse_catalog_json`.

### IN-03: Star-over-view chains degrade to requires-catalog even with a full catalog

**File:** `lineage/views.mbt:83-124` (`build_view_registry`)

**Issue:** Registry construction runs pass 1 with only the inner catalog, so `CREATE VIEW v2 AS SELECT * FROM v1` yields zero output columns for `v2` (v1 is not in the base catalog); `SELECT * FROM v2` then reports `requires-catalog` even when the full base metadata is available. Documented as a known limitation, but it silently under-delivers on the D-03 "view expansion" promise for the common chain-with-star shape.

**Fix:** Build the registry iteratively (resolve later views against the registry accumulated so far, re-deriving star bindings per view) so star-over-view chains resolve. At minimum, surface this as a `requires-catalog` gap with a message that names the unresolved view rather than a generic star message.

### IN-04: db-qualified CREATE VIEW never matches the registry

**File:** `lineage/views.mbt:151-161` (`ViewCatalog::table` / `table_in_db`)

**Issue:** `CREATE VIEW db.v AS ...` registers under the key `"db.v"`, but `ViewCatalog::table` only intercepts single-part lookups, and `table_in_db` delegates straight to the inner catalog. A `FROM db.v` reference therefore misses the in-document view registry (assumption A3). Documented, but a db-qualified in-document view is silently treated as an external object.

**Fix:** Either register views under the unqualified name and reject/intercept db-qualified view references explicitly, or implement `table_in_db` to consult the registry for the `db`-qualified name. Add a test for the db-qualified CREATE VIEW form.

---

_Reviewed: 2026-08-11_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

---

## Resolutions (applied 2026-08-11)

All findings addressed in commit `7c01e39` and verified by the suite:

- **CR-01** — `lineage/insert.mbt`: `derive_insert_source_edges` now resolves the trailing SELECT's FROM/JOIN source tables against the catalog (`resolve_insert_source_tables` / `resolve_from_source`); references from an unresolved table are suppressed and exactly one honest gap (`requires-catalog` no-catalog / `unresolved-reference` with catalog) is emitted at the table-ref span. White-box tests updated + new tests (`lineage INSERT source unresolved no fabricated edges`, `lineage INSERT without column list no catalog honest gaps`).
- **WR-01** — after an unexpanded star in an INSERT source, positional mapping stops (`star_seen`), so subsequent columns are never misaligned.
- **WR-02** — `resolve_insert_target_columns` applies the D-03 quoted byte-exact rule (`is_quoted` re-check against `TableInfo.name`).
- **WR-03** — `lineage/views.mbt` gains `view_column_list`; `view_output_columns` prefers an explicit CREATE VIEW column-name list over body-derived names.
- **WR-04** — the star self-check now emits `requires-catalog` for a zero-column star unless `except_cols` explains an all-excluded expansion (empty-columns table and nested-subquery cases now report honestly).
- **IN-01..04** — informational; retained as documented limitations (library flink-gate message, `min_arity` bounds, star-over-view chains, db-qualified views) in the plan/research notes.

**Verification:** lineage 19/19, test 209/209, api 636/636, fathom-sql 37/37, parity 605/605 ×3 (native/js/wasm, `compare_backends.py` digest `2eda3582…`).

