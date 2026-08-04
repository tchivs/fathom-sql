---
phase: 03-formatting-and-safe-edits
reviewed: 2026-08-04T12:30:00Z
depth: standard
files_reviewed: 16
files_reviewed_list:
  - formatter/options.mbt
  - formatter/error.mbt
  - formatter/refuse.mbt
  - formatter/case.mbt
  - formatter/layout.mbt
  - formatter/format.mbt
  - formatter/moon.pkg
  - api/api.mbt
  - api/moon.pkg
  - doris-sql/moon.pkg
  - doris-sql/ffi.mbt
  - doris-sql/args.mbt
  - doris-sql/run.mbt
  - doris-sql/main.mbt
  - doris-sql/cli_test.mbt
  - test/formatter_test.mbt
findings:
  critical: 0
  warning: 0
  info: 5
  total: 5
status: clean
---

# Phase 3: Code Review Report

**Reviewed:** 2026-08-04T12:30:00Z
**Depth:** standard
**Files Reviewed:** 16
**Status:** clean — CR-01/WR-01/WR-02/WR-03 fixed (see Resolutions); only Info findings remain open.

## Summary

Reviewed the full Phase 03 surface: the new `formatter/` package (options, error, refusal scan, keyword case, layout engine, format entry), the `api.format_text` facade, and the `doris-sql` native CLI (FFI, args, run, main, tests), plus the corpus/idempotence/boundary test suite in `test/formatter_test.mbt`.

Verification performed (all pass): `moon test` — 196/196 tests, including the 44-row corpus harness, the option-matrix idempotence/determinism suite, and the never-panic boundary suite. Live CLI probes confirmed: exit codes 0/1/2 exact (accepted / parse-failure+refusal / usage), refusal never masks parse diagnostics (`DORIS-PARSE-002` + `DORIS-FORMAT-001` both rendered), trailing-comma inputs are refused by the parser before layout can drop them, and deep nesting does not panic.

Findings concentrate in three areas: (1) a memory-safety defect at the libc FFI boundary (non-NUL-terminated path handed to `fopen`); (2) two behavioral/robustness defects in the CLI (unconditional stdin read blocks file mode; unbounded `--indent` materializes gigabytes of output); (3) a pre-existing O(n²) parser helper (`parenthesis_depth`) that the new format entry exposes end-to-end on comma-heavy input (8k-item select list ≈ 8 s, scaling quadratically). The formatter core itself is a clean single-pass design: break decisions read only the token sequence, idempotence holds by construction and is byte-asserted across all 44 corpus rows and the full 2×2×3×2×2×2 option matrix.

## Critical Issues

### CR-01: Non-NUL-terminated path buffer passed to `fopen` — heap over-read at the FFI boundary

**File:** `doris-sql/ffi.mbt:44`
**Issue:** `open_file(@utf8.encode(path), b"rb")` hands `fopen` a `moonbit_bytes_t` whose backing buffer is exactly `utf8_length` bytes. Verified in the pinned core (`/opt/moonbit/lib/core/encoding/utf8/encode_nonjs.mbt:116-134`): `encode` allocates `FixedArray::make(utf8_length, ...)` and returns it without any terminator. The generated C (release build, `doris-sql.c` line ~11028) is `fopen((moonbit_bytes_t)encoded_bytes, (moonbit_bytes_t)literal_12.data)`. `fopen` scans for a NUL terminator, so it reads past the end of the heap allocation — undefined behavior: it may open a different file (path + adjacent heap bytes) or fault on an unmapped page. The mode argument `b"rb"` is safe (byte literals carry an implicit NUL in the constant pool, `data[3] = {114, 98, 0}`); only the path is affected. A 300-run stress probe showed no observable failure (MoonBit's fresh arenas are zeroed, masking the over-read in this single-shot CLI), but the defect is latent UB in a security-critical boundary and the same pattern repeats in `doris-sql/cli_test.mbt:37`.
**Fix:** Terminate the path explicitly before the call:
```moonbit
pub fn read_file(path : String) -> Bytes? {
  let path_bytes = @utf8.encode(path) + b"\x00"
  let handle = open_file(path_bytes, b"rb")
  ...
}
```
(Mirror in `cli_test.mbt:37` for the `b"wb"` call.)

**Resolution:** fixed in commit `e705645` (`fix(03): CR-01 ...`) — `read_file` now builds `let path_bytes = @utf8.encode(path) + b"\x00"` and passes `path_bytes` to `open_file`; the same NUL termination was applied to the `b"wb"` fixture-write call in `cli_test.mbt`. Verified with the 300-run probe (150× short path + 150× 200-char path, varying heap layout): 0 failures, all runs exit 0 with byte-exact output.

## Warnings

### WR-01: File mode blocks forever on open stdin — stdin is read before the file-vs-stdin decision

**File:** `doris-sql/main.mbt:29`
**Issue:** `main` calls `read_stdin()` unconditionally, before `run_format` decides whether `command.file` selects a file. Demonstrated: `sleep 30 | doris-sql format --profile 4.x /tmp/fmt-probe.sql` never completes (timeout rc=124). Any invocation with an open stdin that does not deliver EOF — an interactive terminal, CI with a live stdin pipe, a parent process holding fd 0 — hangs before touching the file. `run_format` is pure and correct; the ordering defect is in `main`.
**Fix:** Only read stdin when the file is absent or `-`:
```moonbit
let stdin_bytes = match command.file {
  Some(path) if path != "-" => b""
  _ => read_stdin()
}
```

**Resolution:** fixed in commit `8dbd05b` (`fix(03): WR-01 ...`) — `main` gates `read_stdin()` on `command.file` exactly as suggested. Verified on the rebuilt binary: file mode with a never-EOF stdin pipe (`timeout 5 exe format --profile 4.x /tmp/fmt-probe.sql < <(sleep 60)`) completes instantly with rc=0 and `SELECT 1` (pre-fix rc=124); `-` and stdin modes still read stdin; file input still wins over piped stdin.

### WR-02: `--indent` is unbounded — legal option values materialize gigabytes of output

**File:** `formatter/options.mbt:54` (validation accepts any `indent >= 0`); `formatter/layout.mbt:114-119` (`indent_bytes` → `" ".repeat(count)` per broken line)
**Issue:** `FormatOptions::new` only rejects negative indent, and `parse_int_arg` (args.mbt) caps the CLI value at ~1e9. Every broken line then materializes `indent × break_indent` spaces into the output buffer. Measured: `--indent 5000000` on a 10-item broken select list → 131 MB peak RSS (baseline 2 MB); the accepted maximum (~1e9) implies tens of GB of output per statement → OOM kill of the CLI (a crash class the never-panic/bounded-work contract is meant to exclude). A typo (`--indent 5000000`) is enough to produce a multi-gigabyte file.
**Fix:** Cap the option in `FormatOptions::new` (e.g. reject `indent > 64` or a documented max) so invalid configuration fails construction like `InvalidIndent`, mirroring the ASVS V5 pattern already used for negatives.

**Resolution:** fixed in commit `20ea34b` (`fix(03): WR-02 ...`) — `FormatOptions::new` rejects `indent < 0 || indent > 64` with `InvalidIndent` (new `pub const MAX_INDENT : Int = 64` in options.mbt); the CLI error message and usage text document the `0..64` range. Constructor tests (`formatter_options_default_and_validation`) assert 65 → `InvalidIndent(value=65)` and 64 → `Ok`; the CLI test asserts `--indent 5000000` → exit 2. Verified on the binary: `--indent 5000000` exits 2 with `invalid --indent value: 5000000 (expected 0..64)`; `--indent 64` accepted.

### WR-03: End-to-end `format` is O(n²) on comma-separated input — adversarial input pins CPU

**File:** `parser/parser.mbt:230-243` (`parenthesis_depth` rescans tokens `0..position`); exercised via `api/api.mbt` `format_text` → `parse_with_limits_context`
**Issue:** Root cause predates Phase 03, but the new format entry is the exposed path and the phase's bounded-work focus covers it. `depth_allowed` (parser.mbt:244) calls `parenthesis_depth`, which rescans every token from position 0 on each `parse_expression_context` invocation — O(position) per expression, O(n²) per statement. Measured with the Phase 03 CLI: flat select list 1000 → 284 ms, 4000 → 2092 ms, 8000 → 8061 ms (≈4× time for 2× input); a 30k-item `IN (...)` list exceeds 20 s. Multi-statement input is linear (168 → 193 ms for 2000 → 4000 statements), confirming the quadratic is the comma-expression path. A valid 8 MB input (1M-token limit) with a large comma list would burn many minutes of CPU — a DoS vector for a server-side format service, and it will also hit `parse` itself.
**Fix (parser package, follow-up):** Maintain paren depth incrementally in `Cursor` (track depth on `advance` when the token is `(`/`)`) instead of rescanning; `depth_allowed` then reads `cursor.depth` in O(1). Formatter-side layout is already a single forward pass and needs no change.

**Resolution:** fixed in commit `bc8ba59` (`fix(03): WR-03 ...`) — `Cursor` gains `mut depth : Int`, `advance` applies the `(`/`)` transform for the consumed token (mirroring the rescan rules exactly: `(` always +1, `)` −1 only above 0), `parenthesis_depth` reads `cursor.depth` in O(1), and the single cursor construction site initializes `depth: 0`. The only direct position mutation outside `advance` rewinds past `"NOT"` (a keyword, never a paren), so the incremental depth is exactly equal to the former rescan at every position. Verified: `moon test` 196/196 pass (zero regressions); CLI timing 4k items 2092→40 ms, 8k items 8061→70 ms (now linear); 200-deep nesting still rejected with DORIS-PARSE-004 (limit semantics preserved).

## Info

### IN-01: Dead `column` field in `Layout` — misleading about the design

**File:** `formatter/layout.mbt:12, 37, 58, 64, 69`
**Issue:** `Layout.column` is written in `emit` (including `column = column + 1` for the space) but never read anywhere — all fit decisions use `scan_comma_list`'s flat measure, as the header comment claims. The dead state invites a future maintainer to "fix" a perceived bug by reading it. Remove the field, or delete the `+ 1` space accounting if the field is kept for future use.
**Fix:** Delete `column` (5 touch points) and the `self.column = self.column + 1` line in the pending-space branch.

### IN-02: `MissingFile` `UsageError` variant is dead code

**File:** `doris-sql/args.mbt:16`; `doris-sql/run.mbt:156`
**Issue:** `parse_args` never returns `MissingFile` — a missing positional yields `None` (stdin), and a second positional is `UnknownFlag`. The variant and its `usage_error_message` arm are unreachable.
**Fix:** Either wire it (e.g. reject a `format` invocation with neither file nor stdin) or delete the variant.

### IN-03: Fixed `/tmp` fixture path in CLI tests — parallel-run collision risk

**File:** `doris-sql/cli_test.mbt:30`
**Issue:** `cli_file_input_exit_0` writes and reads `/tmp/doris-sql-cli-fixture-file-input.sql`. Two test processes (CI matrix, parallel `moon test`) can interleave write/read on the same path, and the file is left behind on failure. Use a per-process unique path (e.g. PID-suffixed) and clean up in the test.
**Fix:** Derive the path from the process id, or use `mkstemp`-style naming via the FFI helpers.

### IN-04: `statement_offsets` doc comment contradicts observed behavior

**File:** `formatter/format.mbt:30-33`
**Issue:** The comment says the offset is "the byte offset where this statement's first emitted byte lands," but the offset is recorded before the pending separator break materializes, so it points at the separator newline byte — exactly what `formatter_statement_offsets_index_into_output` asserts (`offsets[1] == len("SELECT 1;")`). The comment and the test disagree about the contract.
**Fix:** Update the comment to "the byte offset of the separator preceding this statement's first emitted byte" (or record the offset after materializing the pending break, if the landing-byte contract is preferred).

### IN-05: CLI re-implements `FormatOptions` defaults — drift risk

**File:** `doris-sql/run.mbt:24-25` (`DEFAULT_INDENT`, `DEFAULT_LINE_WIDTH`)
**Issue:** `run_format` hard-codes `2`/`100`, duplicating `FormatOptions::default()` (formatter/options.mbt:36-46). A future default change in the core silently leaves the CLI on old values. Route the defaults through `FormatOptions::default()` accessors instead of local constants.

---

## Resolutions (gsd-code-fixer)

Applied 2026-08-04; each fix committed atomically. Verified: `moon test` 196/196 pass
(0 failed); `moon check --target native` 0 errors; CLI smoke exit codes 0/1/2 exact;
file mode no longer blocks on an open stdin; the CR-01 300-run probe is clean; the
indent cap rejects `--indent 5000000` with exit 2; end-to-end format on an 8k-item
select list dropped from 8061 ms to 70 ms (linear, was quadratic).

- **CR-01** — fixed in `e705645` (`fix(03): CR-01 ...`): fopen path buffers are
  NUL-terminated (`@utf8.encode(path) + b"\x00"`) in `read_file` and in the
  `cli_test.mbt` `b"wb"` fixture write; the heap over-read is impossible.
- **WR-01** — fixed in `8dbd05b` (`fix(03): WR-01 ...`): `main` reads stdin only
  when `command.file` is `None` or `"-"`; file mode no longer hangs on an open stdin.
- **WR-02** — fixed in `20ea34b` (`fix(03): WR-02 ...`): `FormatOptions::new` caps
  indent at `MAX_INDENT = 64` (`InvalidIndent` beyond it, mirroring the negative
  check); CLI error message and usage text document `0..64`; constructor and CLI
  handling tests updated.
- **WR-03** — fixed in `bc8ba59` (`fix(03): WR-03 ...`): paren depth is maintained
  incrementally in `Cursor.advance`; `parenthesis_depth` is O(1); the O(n²)
  comma-list path is linear with zero parser-semantics change (196/196 tests pass).

Info findings IN-01..IN-05 remain open (out of scope for this fix pass).

_Reviewed: 2026-08-04T12:30:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Fixed: 2026-08-04_
_Fixer: Claude (gsd-code-fixer)_
