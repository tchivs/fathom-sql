---
phase: 02-doris-completeness-and-corpus
fixed_at: 2026-08-04T00:00:00Z
review_path: .planning/phases/02-doris-completeness-and-corpus/02-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 02: Code Review Fix Report

**Fixed at:** 2026-08-04
**Source review:** `.planning/phases/02-doris-completeness-and-corpus/02-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 3 (CR-01, WR-01, WR-02 — Critical + Warning; Info excluded per scope)
- Fixed: 3
- Skipped: 0

## Fixed Issues

### CR-01: Unbounded recursion in `parse_type_params` — native stack overflow (SIGSEGV)

**Files modified:** `parser/parser.mbt`, `test/ddl_test.mbt`
**Commit:** `c288f44` (`fix(02-01): CR-01 bound parse_type_params recursion with depth guard`)
**Applied fix:** Threaded a `depth : Int` parameter through `parse_type_params`,
mirroring the existing `parse_expression_context` mechanism. At function entry,
`depth > state.limits.max_recursion_depth` emits the DORIS-PARSE-004 resource
diagnostic via `resource_diagnostic` and returns false; both the `( ... )` and
`< ... >` recursion sites pass `depth + 1`. Generic `< >` brackets never register in
`parenthesis_depth`, so an explicit counter was required to honor
`max_recursion_depth` for type-param nesting.
**Test evidence:**
- Pre-fix reproduction (scratch): 2000-deep `ARRAY<...>` chain parsed as
  `valid=true, diagnostics=0` (guard absent); review documented SIGSEGV at ~100k.
- Post-fix regression test `create_table_deep_generic_nesting_stays_bounded`:
  140 levels (> default limit 128) → `!valid`, DORIS-PARSE-004 present, lossless
  replay; 100 levels (< 128) → `valid`, 0 diagnostics; custom limit 2 with
  4 nested generics → `!valid`, DORIS-PARSE-004 present.
- Crash-scale native verification: ~100k-deep chain (~1.4 MB, ~600k tokens, inside
  default max_bytes/max_tokens) terminates in ~3.6 s with exactly one DORIS-PARSE-004
  diagnostic and `valid=false` — no SIGSEGV.

### WR-01: Bare `CREATE` / `CREATE TEMPORARY` / `CREATE EXTERNAL` accepted as valid with zero diagnostics

**Files modified:** `parser/parser.mbt`, `test/ddl_test.mbt`
**Commit:** `af05b40` (`fix(02-02): WR-01 flag bare CREATE forms as incomplete statements`)
**Applied fix:** Replaced the `None => ()` arm in `parse_create` with the same
DORIS-PARSE-002 diagnostic ("expected TABLE, VIEW, INDEX, or MATERIALIZED VIEW after
CREATE", expected_class "create-form") and `valid = false` used by the `Some(_)` arm.
`finish_statement` pushes the Missing node because `parsed` is false — identical to
every other statement family.
**Test evidence:** Pre-fix reproduction (scratch): `CREATE`, `CREATE TEMPORARY`,
`CREATE EXTERNAL` all `valid=true, diagnostics=0`. Post-fix regression test
`bare_create_forms_report_incomplete_statement`: all three forms in strict and editor
modes → `!valid`, DORIS-PARSE-002 present, lossless replay, Missing node in CST.

### WR-02: `parse_type_params` struct-field heuristic silently accepts malformed column types

**Files modified:** `parser/parser.mbt`, `test/ddl_test.mbt`
**Commit:** `b5e1605` (`fix(02-03): WR-02 reject trailing garbage in non-STRUCT type params`)
**Applied fix:** The extra-identifier (field-name) consumption is now gated on
`struct_style`, derived from the enclosing type name (`bytes_equal_ci(raw, b"STRUCT")`)
captured in `parse_column_type` before advancing, and propagated through nested
`< ... >` recursion (a nested generic's struct context is decided by the
just-consumed identifier). Non-STRUCT generics no longer consume a second identifier,
so `ARRAY<INT FOO>` and `MAP<STRING, INT EXTRA>` fail with diagnostics (recovery
path); `STRUCT<a INT, b STRING>` and nested STRUCT lists remain legal.
**Test evidence:** Pre-fix reproduction (scratch): `ARRAY<INT FOO>` and
`MAP<STRING, INT EXTRA>` both `valid=true, diagnostics=0`. Post-fix regression test
`malformed_type_params_report_trailing_garbage`: both malformed forms → `!valid`,
diagnostics > 0, lossless replay; `STRUCT<a INT, b STRING>`,
`MAP<STRING, STRUCT<a INT, b STRING>>`, `ARRAY<STRUCT<a INT>>` → `valid`, 0 diagnostics.

## Verification

Gates ran in the **main checkout** (`workflow.use_worktrees` is `false` in
`.planning/config.json`; no worktree was created, so no teardown applies).

- `moon test` — **166/166 pass** (163 pre-existing + 3 new regression tests).
- `moon check --target native` — **0 errors** (136 pre-existing warnings only).
- Lossless round-trip preserved: every committed regression test asserts
  `@printer.print_result(result) == raw` and `all_spans_in_bounds()`.
- Crash-scale CR-01 scenario (native test binary): ~100k-deep `ARRAY<...>` input
  terminates with a DORIS-PARSE-004 diagnostic, not SIGSEGV.

## Skipped Issues

None — all in-scope findings were fixed. Info findings IN-01..IN-06 remain open
(out of scope for this fix pass); `02-REVIEW.md` frontmatter updated to
`status: clean` (only Info remains) with per-finding resolution markers and a
Resolutions section.

---

_Fixed: 2026-08-04_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
