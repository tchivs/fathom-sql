---
phase: 03-formatting-and-safe-edits
fixed_at: 2026-08-04T21:15:00Z
review_path: .planning/phases/03-formatting-and-safe-edits/03-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 3: Code Review Fix Report

**Fixed at:** 2026-08-04T21:15:00Z
**Source review:** `.planning/phases/03-formatting-and-safe-edits/03-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 4 (Critical + Warning; Info findings out of scope per assignment)
- Fixed: 4
- Skipped: 0

## Fixed Issues

### CR-01: Non-NUL-terminated path buffer passed to `fopen` — heap over-read at the FFI boundary

**Files modified:** `doris-sql/ffi.mbt`, `doris-sql/cli_test.mbt`
**Commit:** `e705645`
**Applied fix:** `read_file` now builds `let path_bytes = @utf8.encode(path) + b"\x00"` and passes the NUL-terminated buffer to `open_file`; the same NUL termination was applied to the `b"wb"` fixture-write call in `cli_test.mbt:37`. `@utf8.encode` allocates exactly the encoded length with no terminator, so the previous call handed `fopen` a buffer that is scanned past its end. The mode literal `b"rb"` was already safe (constant-pool literals carry an implicit NUL).
**Test evidence:** 300-run probe on the rebuilt release binary (150 runs with the short path `/tmp/fmt-probe.sql` + 150 runs with a 200-char path, deliberately varying heap layout): 0 failures, all runs exit 0 with byte-exact `SELECT 1` output. Full suite: `moon test` 196/196 pass.

### WR-01: File mode blocks forever on open stdin — stdin is read before the file-vs-stdin decision

**Files modified:** `doris-sql/main.mbt`
**Commit:** `8dbd05b`
**Applied fix:** `main` gates `read_stdin()` on the parsed command exactly as the review suggested — `Some(path) if path != "-"` yields `b""` (no stdin read), everything else reads stdin:
```moonbit
let stdin_bytes = match command.file {
  Some(path) if path != "-" => b""
  _ => read_stdin()
}
```
**Test evidence:** file mode against a never-EOF stdin pipe (`timeout 5 exe format --profile 4.x /tmp/fmt-probe.sql < <(sleep 60)`) completes instantly with rc=0 and `SELECT 1` — pre-fix the identical scenario timed out (rc=124) before touching the file. `-` and missing-file stdin modes still read stdin (rc=0, `SELECT 1`); file input still wins over piped stdin.

### WR-02: `--indent` is unbounded — legal option values materialize gigabytes of output

**Files modified:** `formatter/options.mbt`, `doris-sql/run.mbt`, `doris-sql/cli_test.mbt`, `test/formatter_test.mbt`
**Commit:** `20ea34b`
**Applied fix:** New documented `pub const MAX_INDENT : Int = 64` in `formatter/options.mbt`; `FormatOptions::new` rejects `indent < 0 || indent > MAX_INDENT` with `InvalidIndent`, mirroring the existing negative-indent ASVS V5 pattern. The CLI error message now reads `invalid --indent value: {value} (expected 0..64)` and the usage text documents `--indent N (0..64)`. Constructor test `formatter_options_default_and_validation` gained over-cap (`65` → `InvalidIndent(value=65)`) and cap-boundary (`64` → `Ok`) assertions; `cli_bad_option_values_exit_2_via_run_format` gained `--indent 5000000` → exit 2.
**Test evidence:** rebuilt binary: `--indent 5000000` exits 2 with `invalid --indent value: 5000000 (expected 0..64)` (pre-fix it was accepted and materialized ~131 MB RSS on a 10-item list); `--indent 64` accepted (rc=0, `SELECT 1`). Full suite 196/196 pass.

### WR-03: End-to-end `format` is O(n²) on comma-separated input — adversarial input pins CPU

**Files modified:** `parser/parser.mbt`
**Commit:** `bc8ba59`
**Applied fix:** Pre-existing Phase 1/2 parser code changed minimally, preserving every semantic:
- `Cursor` gains `mut depth : Int` (initialized `0` at the single construction site in `parse_segment`).
- `advance` maintains depth incrementally for the consumed token, applying exactly the former rescan rules — `(` always `+1`; `)` decrements only above zero (unmatched closers clamp at 0).
- `parenthesis_depth` reads `cursor.depth` in O(1); `depth_allowed` is unchanged.
- Equivalence argument: `advance` is the sole position mutator except (a) a rewind past `"NOT"` in `parse_expression_postfix` (a keyword, never a paren — no depth effect) and (b) a no-op `position = indices.length()` assignment in the trailing-token loop (executes only when `position >= length`). Depth is therefore exactly equal to the former rescan at every position.
**Test evidence:** `moon test` 196/196 pass (0 failed) — zero regressions across the whole suite including all parser tests; `moon check --target native` 0 errors. CLI timing on the rebuilt binary: 4k-item select list 2092 ms → 40 ms; 8k-item list 8061 ms → 70 ms (now linear, ≈115× faster at 8k). Depth-limit semantics preserved: 200-deep `(` nesting still rejected with `DORIS-PARSE-004` (exit 1), 50-deep (under the 128 limit) still parses (exit 0).

## Verification Summary

- `moon test`: **196 passed, 0 failed** (full suite, includes parser tests).
- `moon check --target native`: **0 errors** (164 non-blocking warnings, pre-existing class).
- `moon build --target native --release`: success; binary `_build/native/release/build/doris-sql/doris-sql.exe`.
- CLI smoke: exit 0 (accepted stdin/file), 1 (parse failure + refusal diagnostics both rendered), 2 (usage) — all exact.
- WR-01 probe: file mode with open never-EOF stdin completes rc=0 (pre-fix rc=124).
- CR-01 probe: 300-run loop clean (0 failures, short + long paths).
- WR-02 probe: `--indent 5000000` rejected exit 2; `--indent 64` accepted.
- WR-03 probe: 8k-item select list 70 ms (pre-fix 8061 ms); deep-nesting resource limit intact.

All verification ran in the main checkout (no isolated worktree per the assignment; commits made directly on `master` with normal hooks).

## Skipped Issues

None — all in-scope findings were fixed. Info findings IN-01..IN-05 remain open (out of scope for this Critical+Warning fix pass).

---

_Fixed: 2026-08-04T21:15:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
