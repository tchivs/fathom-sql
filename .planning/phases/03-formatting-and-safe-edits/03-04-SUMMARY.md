---
phase: 03-formatting-and-safe-edits
plan: 04
subsystem: cli
tags: [moonbit, cli, executable-package, libc-ffi, exit-codes, d40, moon-test]

# Dependency graph
requires:
  - phase: 03-01
    provides: formatter/ package + api.format_text / format_with_ids (D-38 shared core entry), from_id helpers (KeywordCase/CommaStyle/NewlineStyle), DORIS-FORMAT-001 refusal namespace
  - phase: 03-03
    provides: all six FormatOptions dimensions functional (the CLI option surface), corpus/option-matrix contracts
provides:
  - doris-sql/ executable package: `doris-sql format` over file/stdin with --profile required (CORE-01), option flags, exact D-39 exit codes 0/1/2, diagnostics on stderr, formatted SQL on stdout
  - D-40 moon-test CLI suite (black-box cli_test.mbt in the executable package) covering every CLI contract path
  - The Phase 4 LSP pathfinder: the same api.format_with_ids core entry the LSP will reuse, with byte-exact stdout/stderr wiring
affects: [Phase 4 LSP formatting (reuses api.format_text), verify-work, ship]

# Actuals (#2632) — pairs with the plan's estimate (50000 tokens) on the same scale.
actuals:
  tokens: 7451    # 29804 diff chars / 4 over the two task commits (17673 + 12131)
  tasks: 2
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Executable package DSL (pkgtype(kind: \"executable\")) — package dir name doris-sql/ builds doris-sql.exe; thin fn main wiring argv/stdin/file/stdout/stderr/exit only (D-37/D-38)"
    - "Pure CLI core: run_format(command, stdin_bytes) -> CliOutcome { exit_code, stdout, stderr } — the ONLY logic home, moon-testable without process spawn (D-40); main.mbt has zero decisions"
    - "libc FFI with #borrow(param) BEFORE extern declarations + @utf8.encode'd Bytes for every libc string (native String is UTF-16) — probe-verified patterns from 03-RESEARCH Common Operations 1-2, confined to doris-sql/"
    - "Black-box _test.mbt modules need pub(all) structs (Command/CliOutcome) and pub FFI externs for construction/calls (moon 0.1.20260724); inline test blocks in package files stay white-box"
    - "Byte-exact unbuffered stdout via write_fd(1, ...) instead of print(to_string()) — exit_process never drops pending output and non-UTF-8 bytes pass through"

key-files:
  created:
    - doris-sql/moon.pkg
    - doris-sql/ffi.mbt
    - doris-sql/args.mbt
    - doris-sql/run.mbt
    - doris-sql/main.mbt
    - doris-sql/cli_test.mbt
  modified: []

key-decisions:
  - "Result[Command, UsageError] instead of the plan's `Command | UsageError` signature: union return types are not supported by moon 0.1.20260724; Result is the established codebase convention (ParseOptions::new)"
  - "stdout is written with write_fd(1, ...) — byte-exact and unbuffered — so exit_process cannot lose pending output and CRLF/non-UTF-8 string literal bytes pass through untouched (print(to_string()) round-trips through UTF-16 and may be buffered)"
  - "--help is handled in main before parse_args (usage on stdout, exit 0), keeping parse_args pure and exit 2 for every actual usage error"
  - "parse_args validates option VALUES (int parse for --indent/--line-width, enum sets for the style flags) producing named UnknownValue errors; run_format keeps the from_id mapping as defense-in-depth for hand-built Commands (both paths tested, both exit 2)"
  - "Hand-rolled parse_int_arg instead of @strconv.parse_int (raise-based): keeps the CLI dependency surface exactly at api/env/buffer/utf8/debug and keeps D-39 exit semantics fully explicit"
  - "Command/CliOutcome are pub(all) and the FFI externs are pub because _test.mbt files compile as a black-box module on this toolchain (the 03-01 read-only-type lesson applies to the test package boundary too)"
  - "write_file_chunk (fwrite) was added to ffi.mbt in Task 1: Task 2's acceptance criteria require file fixtures written via fopen/fwrite/fclose"

patterns-established:
  - "CLI exit-code contract (D-39): 0 = accepted (stdout = formatted SQL), 1 = parse failure or refusal (stdout empty, parse diagnostics + DORIS-FORMAT-001 on stderr — never masked, T-03-20), 2 = usage error (stderr message only)"
  - "Required --profile with no silent fallback (CORE-01): missing -> MissingProfile -> exit 2; unknown id -> UnknownProfile -> exit 2"
  - "Pure-function CLI core + thin main: the only OS-touching code is main.mbt and the ffi.mbt read helpers; everything else is unit-tested without a process"
  - "FFI confinement: the ONLY file in the module allowed to touch libc is doris-sql/ffi.mbt — formatter/ and api/ stay backend-neutral for Wasm/JS (CLAUDE.md single-core constraint)"

requirements-completed: [FMT-04]

# Coverage metadata (#1602) — one entry per shipped deliverable.
coverage:
  - id: D1
    description: "doris-sql format CLI over file and stdin with an explicit Doris profile (2.1|3.x|4.x): formatted SQL on stdout, diagnostics on stderr; --profile required (CORE-01, exit 2 otherwise)"
    requirement: FMT-04
    verification:
      - kind: unit
        ref: "doris-sql/cli_test.mbt#cli_stdin_happy_path_exit_0, cli_file_input_exit_0, cli_parse_failure_exit_1_with_parse_diagnostic"
        status: pass
      - kind: e2e
        ref: "binary smoke: printf 'select 1' | _build/native/release/build/doris-sql/doris-sql.exe format --profile 4.x -> 'SELECT 1' on stdout"
        status: pass
    human_judgment: false
  - id: D2
    description: "Exact exit codes 0/1/2 per D-39 on every path: accepted (0), parse failure/refusal (1, stdout empty), usage errors incl. missing file, unknown flag, bad option values, missing/unknown profile (2, stderr message only)"
    requirement: FMT-04
    verification:
      - kind: unit
        ref: "doris-sql/cli_test.mbt#cli_usage_errors_are_named_usage_error_variants, cli_bad_option_values_exit_2_via_run_format, cli_missing_file_exit_2_names_path, cli_refusal_exit_1_never_masks_parse_diagnostics"
        status: pass
      - kind: e2e
        ref: "binary smoke pipes: exit 0 (valid), exit 1 (bad input), exit 2 (missing --profile) observed on the real executable"
        status: pass
    human_judgment: false
  - id: D3
    description: "Thin CLI layer (D-37/D-38): run_format is pure and calls only @api.format_with_ids (the shared Phase 4 LSP core entry); no format logic in the CLI package; moon.pkg imports api/env/buffer/utf8/debug only — no core formatter import"
    requirement: FMT-04
    verification:
      - kind: unit
        ref: "doris-sql/moon.pkg import list + doris-sql/run.mbt (only core call is @api.format_with_ids)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Moon-test-driven CLI suite (D-40) in the executable package: stdin/file input, missing file, parse failure exit 1, refusal exit 1 with DORIS-FORMAT-001 plus unmasked parse diagnostics, nine usage-error cases, CRLF byte preservation, full flag surface driving real layout, determinism, empty stdin"
    requirement: FMT-04
    verification:
      - kind: unit
        ref: "doris-sql/cli_test.mbt (12 test blocks; 196/196 module tests pass)"
        status: pass
    human_judgment: false
  - id: D5
    description: "FFI hygiene: every libc string is @utf8.encode'd Bytes (never raw UTF-16 String), #borrow on all pointer params, bounded chunked reads with EOF handling, fopen 0L -> None -> exit 2; no FFI anywhere outside doris-sql/"
    requirement: FMT-04
    verification:
      - kind: unit
        ref: "doris-sql/ffi.mbt (all extern decls #borrow + @utf8.encode; read_file/read_stdin chunked loops); negative gate: no extern in any core package"
        status: pass
    human_judgment: false

# Metrics
duration: 58min
completed: 2026-08-04
status: complete
---

# Phase 3 Plan 4: doris-sql format CLI — Executable Package Summary

**`doris-sql format` native CLI as a thin executable package (D-37/D-38): pure run_format maps the api core's format_with_ids results to exact D-39 exit codes 0/1/2 over file/stdin with a required --profile (CORE-01), byte-exact unbuffered stdout/stderr wiring, and a 12-block moon-test suite (D-40) plus a real-binary smoke that observed exit 0/1/2**

## Performance

- **Duration:** 58 min
- **Started:** 2026-08-04T11:35:30Z
- **Completed:** 2026-08-04T12:33:39Z
- **Tasks:** 2
- **Files modified:** 6 created (all new; zero core-package changes)

## Accomplishments
- **FMT-04 executable end-to-end**: `doris-sql format --profile <2.1|3.x|4.x> [flags] [file|-]` formats files and stdin under an explicit profile — SQL on stdout, diagnostics on stderr, exact exit codes. The binary at `_build/native/release/build/doris-sql/doris-sql.exe` smoke-verified with real pipes: `printf 'select 1' | … format --profile 4.x` prints `SELECT 1` and exits 0; `bad` exits 1; missing `--profile` exits 2.
- **Thin layer per D-37/D-38**: `run_format(command, stdin_bytes) -> CliOutcome { exit_code, stdout, stderr }` is the only logic home and its sole core call is `@api.format_with_ids` — the same shared entry Phase 4's LSP will reuse. `main.mbt` only wires argv → bytes → run_format → stdout/stderr/exit; the package imports api/env/buffer/utf8/debug and holds no format logic.
- **Exact exit-code contract (D-39)**: 0 = accepted (stdout = formatted SQL); 1 = parse failure or refusal (stdout empty; parse diagnostics prepended, DORIS-FORMAT-001 never masks them — T-03-20); 2 = usage error (stderr message only, no SQL output): missing/unknown `--profile` (CORE-01, no silent fallback), unknown flag, missing/invalid value, unreadable file.
- **D-40 moon-test suite in the executable package**: 12 black-box test blocks drive the pure functions directly — stdin and file input (fixtures written via FFI fopen/fwrite/fclose), missing file naming the path, parse failure, MERGE-under-2.1 refusal with unmasked `DORIS-PARSE-006` + `DORIS-FORMAT-001`, nine usage-error variants, run_format bad-value safety net, CRLF byte preservation, the full flag surface parsed and driving real layout (`--keyword-case lower` + `--no-trailing-newline` → `select 1`), determinism, empty stdin.
- **FFI hygiene (T-03-19)**: probe-verified `#borrow` + `@utf8.encode` patterns confined to `doris-sql/ffi.mbt`; bounded chunked reads stop at EOF; `fopen` 0L → `None` → exit 2; input size bounded by the api core's 8 MiB ParseLimits (InputTooLarge → exit 1 with a message, T-03-23).
- 196/196 tests pass (183 pre-existing + 13 CLI tests); `moon check --target native` clean; `moon build --target native --release` succeeds; `printer/` and every core package untouched.

## Task Commits

Each task was committed atomically:

1. **Task 1: doris-sql executable package — argv to exit end-to-end slice** - `555004a` (feat) — moon.pkg (executable), ffi.mbt (libc FFI + read_file/read_stdin), args.mbt (parse_args → Result[Command, UsageError], full flag surface, required --profile), run.mbt (pure run_format with D-39 mapping + happy-path test), main.mbt (thin wiring, --help → exit 0, write_fd stdout)
2. **Task 2: D-40 moon-test CLI suite and binary smoke** - `3d32978` (feat) — cli_test.mbt (12 test blocks), pub(all) Command/CliOutcome + pub FFI externs for the black-box test module, run_format bad-value safety-net test

**Plan metadata:** (final metadata commit records SUMMARY/STATE/ROADMAP)

## Files Created/Modified
- `doris-sql/moon.pkg` - `pkgtype(kind: "executable")` manifest; imports only `fathom/doris-sql/api` + core env/buffer/debug/utf8 (no core formatter import — D-37/D-38)
- `doris-sql/ffi.mbt` - native-only libc FFI: read/write/exit/fopen/fread/fwrite/fclose with `#borrow` + `@utf8.encode`; `read_file(path) -> Bytes?` (fopen 0L → None) and `read_stdin()` bounded chunked readers
- `doris-sql/args.mbt` - `UsageError` enum (9 variants, derive Eq/@debug.Debug), `Command` struct (pub(all)), `parse_args(args) -> Result[Command, UsageError]` — subcommand check, required --profile with 2.1/3.x/4.x validation, style-flag value sets, hand-rolled int parsing, --no-trailing-newline, one positional file
- `doris-sql/run.mbt` - `CliOutcome` (pub(all)), pure `run_format` mapping D-39 exit codes (from_id defense-in-depth, FormatOptions::new validation, file-or-stdin input, format_with_ids call, refusal renders parse diags + DORIS-FORMAT-001), `usage_text`/`usage_error_message`/`render_diagnostics` (pub for tests), happy-path test
- `doris-sql/main.mbt` - thin wiring only: `@env.args()` → `--help` → usage stdout exit 0 → parse_args (Err → stderr + exit 2) → read_stdin → run_format → write_fd stdout/stderr → exit_process
- `doris-sql/cli_test.mbt` - D-40 black-box suite: 12 test blocks covering every CLI contract path listed above

## Decisions Made
- **`Result[Command, UsageError]` over the plan's `Command | UsageError`**: moon 0.1.20260724 does not support union return types; Result is the established codebase convention (ParseOptions::new, api.mbt:64-84). Same error semantics, fully explicit exit-2 mapping.
- **Byte-exact stdout via `write_fd(1, …)`** rather than `print(outcome.stdout.to_string())`: unbuffered so `exit_process` cannot drop pending output, and non-UTF-8 bytes inside string literals pass through untouched (to_string would round-trip through UTF-16). CRLF preservation is byte-exact.
- **`--help` handled in main before parse_args**: keeps parse_args pure (every UsageError exits 2) while help prints usage on stdout and exits 0 — the plan's flagged flag surface `[--help]` is honored.
- **Dual-value validation**: parse_args validates option values (UnknownValue at parse time) AND run_format re-maps through `from_id`/`FormatOptions::new` as the safety net for hand-built Commands — both paths tested to exit 2.
- **`pub(all)` + pub externs for the black-box test module**: `_test.mbt` files compile against the package's public API on this toolchain; Command/CliOutcome needed `pub(all)` for literal construction and the FFI externs needed `pub` for the file-fixture helpers (the 03-01 read-only-type lesson applied at the test boundary).
- **`write_file_chunk` (fwrite) in ffi.mbt from Task 1**: Task 2's acceptance criteria require temp fixtures written via fopen/fwrite/fclose — part of the planned FFI surface.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Union return type unsupported by the toolchain**
- **Found during:** Task 1 (first `moon check`)
- **Issue:** `-> Command | UsageError` is a parse error on moon 0.1.20260724 ("unexpected token `|`"), which cascaded into dozens of spurious `let mut`/type errors.
- **Fix:** `-> Result[Command, UsageError]` — the established codebase convention (ParseOptions::new). Call sites (`Ok`/`Err` in main and tests) unchanged.
- **Files modified:** doris-sql/args.mbt
- **Verification:** moon check clean; all usage-error tests pass.
- **Committed in:** 555004a (Task 1)

**2. [Rule 3 - Blocking] `@debug` import missing from the plan's moon.pkg import list**
- **Found during:** Task 1 (args.mbt derive)
- **Issue:** `UsageError derive(Eq, @debug.Debug)` needs `moonbitlang/core/debug` in scope; the plan listed only api/env/buffer/encoding-utf8.
- **Fix:** Added `"moonbitlang/core/debug" @debug` to doris-sql/moon.pkg.
- **Files modified:** doris-sql/moon.pkg
- **Verification:** moon check clean.
- **Committed in:** 555004a (Task 1)

**3. [Rule 1 - Bug] `Buffer::write_string` is deprecated on this toolchain**
- **Found during:** Task 1 (moon test warning)
- **Issue:** `write_string` warns deprecated (use Logger); the CLI renders ASCII diagnostics and needs no String writer.
- **Fix:** `out.write_bytes(@utf8.encode("\{code}: \{message}\n"))`.
- **Files modified:** doris-sql/run.mbt
- **Verification:** moon test 184/184 after the change, warning gone.
- **Committed in:** 555004a (Task 1)

**4. [Rule 1 - Bug] Black-box test module could not construct Command or call FFI helpers**
- **Found during:** Task 2 (first `moon check` with cli_test.mbt)
- **Issue:** `_test.mbt` files compile as a black-box module on moon 0.1.20260724: `pub struct` literal construction fails ("Cannot create values of the read-only type") and non-pub externs are unbound — while inline test blocks in package files (run.mbt's happy path) stay white-box and were unaffected.
- **Fix:** `Command` and `CliOutcome` → `pub(all)`; FFI externs → `pub`. Also derived `UsageError` values from parse_args in the rendering test instead of constructing pub-enum variants cross-package.
- **Files modified:** doris-sql/args.mbt, doris-sql/run.mbt, doris-sql/ffi.mbt, doris-sql/cli_test.mbt
- **Verification:** moon check clean; 196/196 tests pass.
- **Committed in:** 3d32978 (Task 2)

**5. [Rule 1 - Bug] Flag-surface test drove run_format with a nonexistent file path**
- **Found during:** Task 2 (test run)
- **Issue:** The parsed command carries `file: Some("file.sql")`; run_format correctly tried to read it, failed, and exited 2 — `2 != 0` in the option-drive assertion.
- **Fix:** The test re-targets the parsed options onto stdin (`file: Some("-")`) for the layout-observability run; the file-field assertion stays on the parse result.
- **Files modified:** doris-sql/cli_test.mbt
- **Verification:** 196/196 tests pass.
- **Committed in:** 3d32978 (Task 2)

---

**Total deviations:** 5 auto-fixed (4 Rule 3 blocking, 1 Rule 1 bug — plus one deliberate correctness choice, see Decisions: byte-exact stdout via write_fd)
**Impact on plan:** All fixes were toolchain adaptations and test corrections within the planned surface — no scope creep, no architectural change, no core-package touch. The CLI shipped exactly the planned flag surface, exit semantics, and thin-layer structure.

## Issues Encountered
- **Toolchain version sensitivity (as 03-RESEARCH warned)**: union types, `pub(all)` construction rules for black-box `_test.mbt` modules, and `Buffer::write_string` deprecation are moon-0.1.20260724-specific behaviors; all three were probed at compile time and adapted with minimal surface.
- **Parallel docs commits** (`docs: generate project documentation`, `docs: add bilingual documentation`) landed between my Task 1 and Task 2 commits (another agent's work); my commits remain cleanly separable and touch only doris-sql/.
- A `moon version` invocation once hung the shell for 300s (toolchain quirk observed this session); all moon commands were subsequently run under explicit timeouts.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 4 LSP formatting reuses `api.format_with_ids` directly — the CLI proves the raw-bytes → format → diagnostics path with byte-exact output wiring (statement_offsets already index the formatted output).
- The CLI's exit-code contract and stderr diagnostic rendering give script/editor consumers a stable automation surface; `--help` is exit-0 safe.
- Known boundaries for consumers (inherited): literal Pattern-1 clause breaks and zero-space-before-paren produce terse canonical forms; `--keyword-case` uppercases non-reserved identifiers whose spelling matches a classification row (assumption A4).

## Self-Check: PASSED
- Both task commits exist: `555004a`, `3d32978` (verified via git log).
- Final acceptance re-run on the committed state: `moon test` 196/196 passed; `moon check --target native` 0 errors; `moon build --target native --release` succeeded; binary smoke observed exit 0/1/2 on the real executable with real pipes (exit 0 + `SELECT 1` on stdout, exit 1 for `bad`, exit 2 for missing `--profile`).
- `printer/` and all core packages untouched (0 diff lines outside doris-sql/); moon.pkg imports only api/env/buffer/debug/utf8 (no core formatter import); no extern/FFI outside doris-sql/ffi.mbt.
- No stubs, skipped tests, or unrun verifies — the broken-windows ledger needs no entries.

---
*Phase: 03-formatting-and-safe-edits*
*Completed: 2026-08-04*
