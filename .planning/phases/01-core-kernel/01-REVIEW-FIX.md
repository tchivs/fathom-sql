---
phase: 01-core-kernel
fixed_at: 2026-08-04T00:00:00Z
review_path: .planning/phases/01-core-kernel/01-REVIEW.md
iteration: 13
findings_in_scope: 1
fixed: 1
skipped: 0
status: all_fixed
---

# Phase 1: Code Review Fix Report

**Fixed at:** 2026-08-04T00:00:00Z  
**Source review:** `.planning/phases/01-core-kernel/01-REVIEW.md`  
**Iteration:** 13

**Summary:**
- Current iteration scope: T-01-14 (manifest exact-release and feature-introduction metadata gate).
- Fixed: 1; skipped: 0; commit: `d6f5b76`.
- Iteration 12 (`WR-32` through `WR-38`, `T-01-06`) remains recorded below as historical fixes.
- This report remains an uncommitted planning artifact for the orchestrating session.

## Historical fixes retained from iteration 12

## Fixed Issues

### WR-32: Reserved SQL literals were rejected as expression operands

**Files modified:** `parser/parser.mbt`, `test/parser_test.mbt`  
**Commit:** `a846f60`  
**Applied fix:** Expression operand classification now explicitly accepts unquoted `NULL`, `TRUE`, and `FALSE` as literal operands while retaining reserved-word rejection for identifiers. Strict/editor regression cases cover projection, predicates, `IN`, `ORDER BY`, function arguments, exact replay, and bounded spans.

### WR-33: Invalid quoted/comment scans could exceed `max_tokens`

**Files modified:** `lexer/lexer.mbt`, `test/recovery_test.mbt`  
**Commit:** `804549e`  
**Applied fix:** Quoted/comment scans now enforce the token cap before every split or invalid-byte push and return the first omitted source byte. `TokenStream.truncated_at` preserves that source-backed location, allowing parser resource recovery to emit `DORIS-PARSE-004` while retaining the complete source for replay. Regression tests cover invalid UTF-8 inside strings/comments, bounded token arrays, truncation spans, resource diagnostics, and replay.

### WR-34: WINDOW definition trailing comma was accepted

**Files modified:** `parser/parser.mbt`, `test/parser_test.mbt`  
**Commit:** `2552a9b`  
**Applied fix:** After a WINDOW definition comma, the parser now requires another window identifier and emits source-backed `DORIS-PARSE-002` at EOF or the next clause. Strict/editor malformed cases assert invalidity, recovery diagnostics, exact replay, and in-bounds spans.

### WR-35: GROUPING SETS trailing comma was accepted

**Files modified:** `parser/parser.mbt`, `test/parser_test.mbt`  
**Commit:** `e79729e`  
**Applied fix:** GROUPING SETS now requires a grouping set after each comma and rejects a comma immediately before `)` with a source-backed `DORIS-PARSE-002`. Strict/editor diagnostics, replay, and span regression cases cover EOF and a following clause.

### WR-36: WITH RECURSIVE was silently ignored

**Files modified:** `parser/parser.mbt`, `test/parser_test.mbt`  
**Commit:** `2b37b80`  
**Applied fix:** `WITH RECURSIVE` now emits `DORIS-PARSE-006` on the `RECURSIVE` token and propagates invalidity/recovery without discarding the CTE source. Ordinary `WITH` CTEs remain valid; strict/editor diagnostics, replay, and span tests cover both paths.

### WR-37: EXCEPT was accepted after DISTINCT/DISTINCTROW

**Files modified:** `parser/parser.mbt`, `test/parser_test.mbt`  
**Commit:** `d4047c5`  
**Applied fix:** Projection modifier tracking now permits `EXCEPT` only after `ALL`, while `SELECT * EXCEPT (...)` remains on the explicit wildcard production. Invalid DISTINCT/DISTINCTROW forms consume their option for recovery and emit source-backed `DORIS-PARSE-002`; valid ALL/star forms retain exact replay and spans.

### WR-38: SAMPLE/TABLESAMPLE accepted comma-separated values

**Files modified:** `parser/parser.mbt`, `test/parser_test.mbt`  
**Commit:** `1d5c252`  
**Applied fix:** Table-value parsing now distinguishes singular SAMPLE/TABLESAMPLE values from list-capable TABLET values. SAMPLE/TABLESAMPLE multi-value forms receive `DORIS-PARSE-002`, while valid units, REPEATABLE forms, TABLET lists, replay, and spans remain covered.

### T-01-06: Diagnostic statement IDs were exposed as signed Int

**Files modified:** `parser/parser.mbt`, `api/api.mbt`, `test/parser_test.mbt`, `test/recovery_test.mbt`  
**Commit:** `27b6d63`  
**Applied fix:** ParserDiagnostic and PrimitiveDiagnostic now expose MoonBit's built-in 32-bit `UInt`; every statement-id parameter and both snapshot-local counters use `UInt` with `0U` initialization and `1U` increments. Regression assertions cover strict/editor diagnostics, replay and span/resource/lexical paths, semicolon trivia identity, per-snapshot reset, and non-negative converted range checks. No `statement_id : Int` or negative comparison remains in implementation/API.

## Historical iteration 12 verification

The following gates belong to the retained WR-32..WR-38/T-01-06 fixes and remain historical evidence; iteration 13 verification is recorded below.

All iteration 12 gates ran in the main checkout `/opt/source/Fathom` after commit `27b6d63`.

- `moon check --target native`: **0 errors, 96 warnings**.
- `moon build --target native --release`: **0 errors, 70 warnings**.
- `moon test`: **92 passed, 0 failed**.
- No formatter, linter, dependency installation, external service, or unrelated project suite was run.
- Planning metadata (`.planning/config.json`, checkpoints/next-action/task-results, `01-PATTERNS.md`) and `_build/` were not staged or committed.

## Skipped Issues

None — all in-scope findings were fixed.

## Iteration 13 — T-01-14

### T-01-14: Manifest exact-release and feature-introduction metadata gate

**Files modified:** `token/token.mbt`, `api/api.mbt`, `parser/parser.mbt`, `test/parser_test.mbt`
**Commit:** `d6f5b76`
**Applied fix:** Canonical `ProfileMetadata` now carries exact release and controlled feature-introduction values. `ParseOptions::from_manifest`/`parse_with_metadata` validate metadata before parsing and return structured `ProfileMetadataMismatch`, `UnknownProfile`, or `UnsupportedFeatureIntroduction` errors. The parser receives a validated profile context for feature gates; legacy `parse_with_ids` still uses canonical profile metadata. Deterministic embedded fixtures exercise 2.1, 3.x, and 4.x parse/replay/diagnostic/span paths without filesystem or network I/O.

**Verification:** `moon check --target native` passed with 0 errors (116 warnings); `moon build --target native --release` passed with 0 errors (109 warnings); `moon test` passed with 93/93 tests. All commands ran in the main checkout `/opt/source/Fathom`; these are the required acceptance gates, with no additional project suite. No formatter, linter, or external I/O was run.

**Iteration 13 summary:** Findings in scope: 1; Fixed: 1; Skipped: 0.

---

_Fixed: 2026-08-04T00:00:00Z_  
_Fixer: Claude (gsd-code-fixer)  
_Iteration: 13_
