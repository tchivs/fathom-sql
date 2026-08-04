---
phase: 03-formatting-and-safe-edits
verified: 2026-08-04T15:44:11Z
status: passed
score: 4/4 must-haves verified
behavior_unverified: 0
overrides_applied: 0
---

# Phase 3: Formatting and Safe Edits Verification Report

**Phase Goal:** Users can choose exact source replay or a deterministic, configurable, comment-preserving canonical rendering and invoke it safely from the `doris-sql format` command.
**Verified:** 2026-08-04T15:44:11Z
**Status:** passed
**Re-verification:** No — initial verification (previous VERIFICATION.md had no `gaps:` section; this report supersedes it with direct codebase/behavioral evidence rather than SUMMARY claims)

## Mode Discrepancy (escalation item — not a code gap)

ROADMAP.md declares `**Mode:** mvp` for Phase 3, but the phase goal is **not** in user-story format. The centralized validation verb (`gsd-tools query user-story.validate --story "<phase goal>" --pick valid`) returns `valid: false` for the goal "Users can choose exact source replay or a deterministic, configurable, comment-preserving canonical rendering and invoke it safely from the `doris-sql format` command." Per `verify-mvp-mode.md`, a `mode: mvp` phase with a non-user-story goal is a discrepancy: the verifier surfaces it and asks the user to run `/gsd mvp-phase 03` to reformat the goal (or correct the ROADMAP mode). This item requires human decision but does not affect the code-achievement verdict below: the goal-backward verification is fully executable against the 4 ROADMAP success criteria, which the plans and code map 1:1.

## Goal Achievement

### Observable Truths

Truths are the four ROADMAP success criteria (the roadmap contract); each plan's `must_haves` map onto them and are folded in below.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Consumer can request canonical output distinct from exact lossless replay, with documented behavior across supported Doris syntax | ✓ VERIFIED | `api.format_text` (api/api.mbt:369) calls `@parser.parse_with_limits_context` then `@formatter.format` — a distinct entry from `print_lossless` (printer/printer.mbt:28). `git log --oneline -- printer/` shows only Phase-01 commits (last `7704c92`); `git status --porcelain -- printer/` = 0 lines; printer untouched (D-27 add-alongside). Per-family clause tables (layout.mbt:157-231) for Select/Insert/Update/Delete/Merge/DDL with parser `consume_word` reference comments; 17 test blocks incl. per-family goldens (`formatter_03_02_family_clause_tables_and_subquery_indent`), flat fallback for unknown families, and 44-row corpus harness |
| 2 | User can configure keyword case, indentation, line width, comma style, newline style, and trailing-newline policy while comments and hints remain attached to their intended source regions | ✓ VERIFIED | `FormatOptions` with exactly six fields (formatter/options.mbt:33-41), defaults Upper/2/100/Trailing/FollowInput/on (options.mbt:49-57), validating `new()` rejecting `indent < 0 || indent > MAX_INDENT(64)` (InvalidIndent) and `line_width <= 0` (InvalidLineWidth) (options.mbt:60-75). Six-dimension goldens: `formatter_03_03_all_six_dimensions_functional` (Lower with quoted `"SELECT"`/`view`/strings untouched, indent 4, width 100-vs-20, Leading comma, Lf override on CRLF input, Crlf override on LF input, trailing-newline off). Comment/hint attachment goldens: `formatter_03_02_script_layout_and_comment_attachment` (inline stays inline, own-line stays own-line, `/*+ hint */` byte-identical never uppercased — `4.x-hint-byte-identical` fixture, line comment forces break after) |
| 3 | Formatter output is deterministic and idempotent, reparses successfully for supported input, and reports or refuses unsafe transformations for unrecoverable/error trees | ✓ VERIFIED | (a) Idempotence: 44-row corpus harness (`formatter_corpus_44_row_harness`) — fixture_ids cross-checked against corpus/manifest.tsv: 44/44 exact match, none missing, none invented; every accepted row byte-exact idempotent + zero-diagnostic reparse; error rows refuse with DORIS-FORMAT-001 + empty output. Option-matrix test (`formatter_03_03_option_matrix_idempotence_and_determinism`) — 2×2×3×2×2×2 = 96 combos × {SELECT, DDL}, byte-exact idempotence AND two-run determinism per combo. (b) Determinism: `formatter_determinism_pure_function_backstop` + real-binary spot-check (two runs byte-identical via `cmp`). (c) Refusal: `formatter_refusal_never_masks_parse_diagnostics`; live CLI probe on `bad` → exit 1, stderr carries BOTH `DORIS-PARSE-007` and `DORIS-FORMAT-001`, stdout empty (refusal never masks parse diagnostics, T-03-01). (d) Never-panic: `formatter_03_03_never_panic_boundary_suite` (empty/whitespace-only/comment-only accepted with empty output; max_bytes → `ParseError::InputTooLarge`, no crash); refusal-diagnostic shape gate `formatter_03_03_refusal_diagnostics_are_well_formed` |
| 4 | User can run `doris-sql format` on a file or standard input to receive formatted SQL and diagnostics, with a non-zero status for invalid input under the selected profile | ✓ VERIFIED | Real release binary `_build/native/release/build/doris-sql/doris-sql.exe` probes (this verification, live): `printf 'select 1' | … format --profile 4.x` → `SELECT 1` on stdout, exit 0; `printf 'bad'` → exit 1, stdout empty, parse+refusal diagnostics on stderr; missing `--profile` → exit 2 with usage message; unknown profile → 2; unknown flag → 2; `--help` → 0. File mode with never-EOF stdin (`< <(sleep 60)`) completes instantly rc=0 (WR-01 fix); `-` and missing-file stdin modes still read stdin; file input wins over piped stdin. CRLF preserved byte-for-byte (`printf 'select 1\r\n'` → `SELECT 1\r\n` via `od -c`). Flag surface drives layout: `--keyword-case lower --no-trailing-newline` → `select 1` (no trailing \n). D-40 moon-test suite: 13 CLI test blocks (12 in doris-sql/cli_test.mbt + 1 in run.mbt) covering stdin/file/missing-file/parse-failure/refusal/nine usage-error variants/CRLF/flag-surface/determinism/empty-stdin |

**Score:** 4/4 truths verified (0 present-but-behavior-unverified; every behavior-dependent truth exercised by tests and/or live binary probes)

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | --------- | ------ | ------- |
| formatter/moon.pkg | D-27 one-way library manifest | ✓ VERIFIED | Imports source/token/syntax + core buffer/debug/utf8 only; no api/parser/printer/lexer fathom imports (negative grep clean) |
| formatter/options.mbt | Six-field FormatOptions + defaults + validation + from_id | ✓ VERIFIED | Present (read); MAX_INDENT=64 cap (WR-02); `formatter_options_default_and_validation` + `formatter_from_id_maps_cli_string_ids` tests pass |
| formatter/error.mbt | FormatError/FormatDiagnostic/FormatResult | ✓ VERIFIED | Present; FormatDiagnostic mirrors PrimitiveDiagnostic shape; FormatResult { accepted, output, diagnostics, statement_offsets } |
| formatter/refuse.mbt | first_unsafe_element recursive scan | ✓ VERIFIED | Present (read); gates every layout call (D-33) |
| formatter/case.mbt | rewrite_keyword via classification table; rewrite_keyword_case with ASCII fold | ✓ VERIFIED | Present; Lower = ASCII A-Z→a-z fold of canonical word; no second keyword list |
| formatter/layout.mbt | Clause tables, measure-then-break, comma styles, comment attachment, paren-depth | ✓ VERIFIED | 870 lines, substantive (read); per-family tables with parser refs; ListKind classification; probe-recorded last-item comma gate |
| formatter/format.mbt | Refusal-first format entry + statement_offsets | ✓ VERIFIED | Present (read); DORIS-FORMAT-001, empty output on refusal, never panics |
| api/api.mbt format_text/format_with_ids/format_with_metadata | D-38 shared core entry | ✓ VERIFIED | Present (read, lines 369-448); InputTooLarge/InvalidSyntaxTree propagate; parse diagnostics converted + prepended |
| doris-sql/ (moon.pkg, ffi.mbt, args.mbt, run.mbt, main.mbt, cli_test.mbt) | Thin executable CLI package | ✓ VERIFIED | All six files present; main.mbt wiring-only; run_format pure; #borrow+@utf8.encode FFI confined to ffi.mbt |
| test/formatter_test.mbt | FormatterFixture harness, 44-row corpus, matrix, boundary suite | ✓ VERIFIED | 1662 lines; 17 test blocks; corpus array has exactly 44 rows matching manifest.tsv |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| api/api.mbt format_text | formatter/format.mbt | One internal parse then `@formatter.format(root, source, format_options)` | ✓ WIRED | Read in api/api.mbt:369-416 |
| formatter/case.mbt | token/token.mbt | `@token.classification_of(raw)` — single keyword authority | ✓ WIRED | Read in case.mbt:8-10 |
| formatter/format.mbt | formatter/refuse.mbt | `find_first_unsafe` gates every layout call | ✓ WIRED | Read in format.mbt:9-15 |
| doris-sql/run.mbt | api/api.mbt | `@api.format_with_ids(input, profile, "strict", format_options)` — sole core call | ✓ WIRED | Read in run.mbt:92; moon.pkg imports api only |
| doris-sql/args.mbt | formatter/options.mbt | `KeywordCase::from_id`/`CommaStyle::from_id`/`NewlineStyle::from_id` | ✓ WIRED | Read in run.mbt:38-61 + cli_test flag-surface test |
| test/formatter_test.mbt | api/api.mbt | `format_with_ids` drives fixtures; `parse_with_ids` re-parses output (D-35) | ✓ WIRED | Read in formatter_corpus_fixture_check |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| formatter output | formatter.format output buffer | Real CST from `parse_with_limits_context`; leaf bytes sliced from SourceText | ✓ Yes — real SQL bytes, keyword-canonicalized, comments verbatim | ✓ FLOWING |
| CLI stdout | outcome.stdout | `result.output` from api.format_with_ids | ✓ Yes — byte-exact `write_fd(1, …)` (unbuffered; CRLF/non-UTF-8 pass through) | ✓ FLOWING |
| CLI stderr | outcome.stderr | render_diagnostics(result.diagnostics) | ✓ Yes — real DORIS-PARSE-*/DORIS-FORMAT-001 rendered (verified on binary) | ✓ FLOWING |
| statement_offsets | FormatResult.statement_offsets | out.buf.length() before each statement's layout | ✓ Yes — asserted in bounds for every corpus row; two-statement fixture offsets [0, len("SELECT 1;")] | ✓ FLOWING |

### Behavioral Spot-Checks (run live, this verification)

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Valid stdin format | `printf 'select 1' \| $BIN format --profile 4.x` | `SELECT 1` stdout, exit 0 | ✓ PASS |
| Parse failure exit 1 + unmasked diagnostics | `printf 'bad' \| $BIN format --profile 4.x` | exit 1, stdout empty, stderr = `DORIS-PARSE-007` + `DORIS-FORMAT-001` | ✓ PASS |
| Refusal exit 1 (version-invalid) | `printf 'MERGE …' \| $BIN format --profile 2.1` | exit 1, stderr = `DORIS-PARSE-006` + `DORIS-FORMAT-001` | ✓ PASS |
| Missing --profile → exit 2 | `printf 'select 1' \| $BIN format` | exit 2, usage message on stderr | ✓ PASS |
| Unknown profile / flag → exit 2 | `… --profile mysql` / `… --bogus` | exit 2 both | ✓ PASS |
| --help → exit 0 | `$BIN --help` | exit 0 | ✓ PASS |
| File mode with never-EOF stdin (WR-01) | `timeout 5 $BIN format --profile 4.x /tmp/fmt-probe.sql < <(sleep 60)` | completes instantly, `SELECT 1`, rc=0 (pre-fix: rc=124 hang) | ✓ PASS |
| stdin `-` still reads stdin | `printf 'select 2' \| $BIN format --profile 4.x -` | `SELECT 2`, rc=0 | ✓ PASS |
| File wins over piped stdin | `printf 'select 99' \| $BIN format --profile 4.x /tmp/fmt-probe.sql` | `SELECT 1` (file), rc=0 | ✓ PASS |
| --indent over-cap (WR-02) | `… --indent 5000000` | exit 2, `invalid --indent value: 5000000 (expected 0..64)` | ✓ PASS |
| --indent boundary | `… --indent 64` (accept) / `--indent -1` (reject) | 64 → rc=0 `SELECT 1`; -1 → exit 2 | ✓ PASS |
| WR-03 linearization | `$BIN format --profile 4.x /tmp/8k.sql` (8000-item select list) | rc=0, elapsed 0.11s (pre-fix 8061 ms), RSS 5.9 MB | ✓ PASS |
| Depth-limit semantics preserved (WR-03) | 200-deep `(` nesting | `DORIS-PARSE-004: parser resource limit reached` + refusal, exit 1 | ✓ PASS |
| Depth under limit still parses | 50-deep `(` nesting | exit 0 | ✓ PASS |
| Determinism | same stdin formatted twice → `cmp` | byte-identical | ✓ PASS |
| Idempotence | format output re-formatted → `cmp` | byte-identical (format(format(x)) == format(x)) | ✓ PASS |
| CRLF byte preservation | `printf 'select 1\r\n' \| $BIN format --profile 4.x` | `SELECT 1\r\n` (od -c) | ✓ PASS |
| Flag surface drives layout | `--keyword-case lower --no-trailing-newline` | `select 1` (no trailing \n) | ✓ PASS |

### Probe Execution

| Probe | Command | Result | Status |
| ----- | ------- | ------ | ------ |
| Full test suite | `moon test` | **196 passed, 0 failed** (includes parser tests — zero Phase 1/2 regressions) | ✓ PASS |
| Type check | `moon check --target native` | 0 errors (164 non-blocking warnings, pre-existing class) | ✓ PASS |
| Release build | `moon build --target native --release` | success; binary at `_build/native/release/build/doris-sql/doris-sql.exe` (805 KB) | ✓ PASS |
| Corpus mirror integrity | fixture_ids in `formatter_corpus_fixtures` vs `corpus/manifest.tsv` | 44/44 exact match, none missing/invented | ✓ PASS |
| Debt markers | grep TBD/FIXME/XXX/TODO/PLACEHOLDER over formatter/, doris-sql/, api/api.mbt | zero hits | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| FMT-01 | 03-01, 03-02 | Deterministic canonical rendering distinct from lossless replay, documented behavior | ✓ SATISFIED | formatter/ package, api.format_text, per-family clause tables + goldens, corpus harness |
| FMT-02 | 03-01, 03-02, 03-03 | Six configurable dimensions; comments/hints attached | ✓ SATISFIED | FormatOptions six fields + validating new(); six-dimension goldens; comment/hint attachment goldens |
| FMT-03 | 03-01, 03-03 | Idempotent, reparses, refuses/reports unsafe | ✓ SATISFIED | 44-row corpus, 96-combo matrix, DORIS-FORMAT-001 refusal with unmasked parse diagnostics, never-panic boundary suite |
| FMT-04 | 03-04 | doris-sql format over file/stdin with SQL, diagnostics, non-zero status | ✓ SATISFIED | Real-binary exit 0/1/2, --profile required, stderr diagnostics, D-40 moon-test suite |

All four FMT-* IDs are accounted for across the four plans (03-01: FMT-01/02/03; 03-02: FMT-01/02; 03-03: FMT-02/03; 03-04: FMT-04). No orphaned requirements — REQUIREMENTS.md maps exactly FMT-01..04 to Phase 3 and all are covered.

### Security Fix Verification (CR-01, WR-01..03)

| Finding | Claimed Fix | Source Evidence | Behavioral Evidence |
| ------- | ----------- | --------------- | ------------------- |
| CR-01 fopen over-read | NUL-terminate path (`@utf8.encode(path) + b"\x00"`) | Read in doris-sql/ffi.mbt `read_file` and cli_test.mbt `b"wb"` write | 300-run probe recorded clean in 03-REVIEW-FIX; suite 196/196 |
| WR-01 stdin hang in file mode | Gate `read_stdin()` on `command.file` | Read in doris-sql/main.mbt:29-33 | Live probe: file mode + never-EOF stdin completes rc=0 (pre-fix rc=124) |
| WR-02 unbounded --indent | `MAX_INDENT = 64` cap in `FormatOptions::new` | Read in formatter/options.mbt:26-31, 60-75 | Live probe: `--indent 5000000` → exit 2; 64 → rc=0 |
| WR-03 O(n²) paren depth | Incremental `cursor.depth` in `Cursor.advance`; `parenthesis_depth` O(1) | Read in parser/parser.mbt:112-145, 246-251 | Live probe: 8k-item list 0.11s (was 8061 ms); depth-limit semantics preserved (200-deep → DORIS-PARSE-004) |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| — | — | None found. No debt markers, no stub returns, no hardcoded empty data, no console-only handlers in phase files | ℹ️ | — |

Info findings IN-01..IN-05 from 03-REVIEW.md remain open (dead `column` field, dead `MissingFile` variant, fixed /tmp fixture path, statement_offsets doc-comment mismatch, CLI re-implements defaults). All are documented Info-level, out of scope for the CR+WR fix pass, and non-blocking for the phase goal.

### Human Verification Required

None — every behavior-dependent truth was exercised by the 196-test suite and/or live binary probes. (The MVP-mode goal-format discrepancy listed at the top of this report is a governance decision for the developer — reformat the ROADMAP goal via `/gsd mvp-phase 03` or correct the mode — not a code-behavior item.)

### Gaps Summary

No gaps. All 4 success criteria verified with direct codebase evidence (source reads) and behavioral evidence (test suite + live CLI probes on the real release binary). Security fixes CR-01/WR-01/WR-02/WR-03 verified in source and behavior. Requirements FMT-01..04 all satisfied and accounted for. The single escalation item is the ROADMAP `mode: mvp` vs non-user-story goal discrepancy, which does not affect code achievement.

---

_Verified: 2026-08-04T15:44:11Z_
_Verifier: Claude (gsd-verifier)_
