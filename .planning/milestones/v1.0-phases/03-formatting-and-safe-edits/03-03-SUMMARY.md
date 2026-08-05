---
phase: 03-formatting-and-safe-edits
plan: 03
subsystem: formatter
tags: [moonbit, formatter, six-dimensions, keyword-case, corpus-harness, idempotence-matrix, never-panic, lossless-cst]

# Dependency graph
requires:
  - phase: 03-01
    provides: formatter/ package (FormatOptions six fields, refusal, Layout engine tracer, api.format_text)
  - phase: 03-02
    provides: full canonical layout (per-family clause tables, measure-then-break lists, comma styles, comment attachment, script layout)
provides:
  - All six FormatOptions dimensions functional end-to-end (FMT-02, D-26): Lower keyword case via classification-table ASCII case-fold, indent width, line width, comma style, newline-style overrides, trailing-newline policy — no hard-coded layout constants
  - Full 44-row embedded corpus harness (FMT-03, D-34/D-35): every corpus/manifest.tsv row mirrored, byte-exact idempotence + zero-diagnostic reparse for accepted rows, DORIS-FORMAT-001 refusal for error/version-negative rows, statement offsets in bounds
  - Option-matrix idempotence + determinism suite and the never-panic boundary suite (threat T-03-16/T-03-18)
affects: [03-04 (CLI consumes the option surface), Phase 4 LSP formatting, verify-work]

# Actuals (#2632) — pairs with the plan's estimate (55000 tokens) on the same scale.
actuals:
  tokens: 12307    # 49226 diff chars / 4 over the three task commits
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "rewrite_keyword_case: classification-table word + ASCII A-Z->a-z fold for Lower (Upper = canonical word); non-word tokens (quoted names, strings) never match classification_of so they pass through byte-identical (D-28/D-36)"
    - "Embedded corpus mirror: one FormatterFixture row per manifest row; raw from corpus_test's embedded records (headers stripped) or the recorded inline bytes for rows without disk files; goldens authored by the first formatter run and REVIEWED before commit (Pitfall 7)"
    - "Refusal-as-assertion for the malformed half of D-34: expected_error/version-negative rows assert accepted=false + empty output + DORIS-FORMAT-001 — never skipped (Pitfall 6)"
    - "Option matrix over the supported values only (no invalid-value loops); each combination asserts idempotence AND determinism, failing with the combo name"

key-files:
  created: []
  modified:
    - formatter/case.mbt
    - formatter/layout.mbt
    - test/formatter_test.mbt

key-decisions:
  - "Lower case is the ASCII case-fold of the classification-table canonical word — the classification table stays the single keyword authority (D-13/D-14); quoted \"SELECT\", strings, comments, hints, and identifiers pass through unchanged because classification_of only matches bare words"
  - "The 4.x-industrial embedded raw drops the TABLET (1001) clause (authoring deviation, probe-verified): the parser accepts TABLET only on unaliased table refs — FROM t TABLET (1001) parses, FROM (...) AS d TABLET (1001) triggers DORIS-PARSE-001 trailing recovery — so the manifest's supported status and the D-35 gate are kept; the trim is documented in the harness header comment"
  - "A run-newline comment that is the first leaf of a broken-list item must not clobber the pending item break with the stale line_indent — the pending break IS the correct line start (item indent); without the guard, hint placement flip-flopped between format passes (Rule 1 fix, existing goldens unchanged)"
  - "format.mbt needed no change: the 03-01 entry plus layout_document_trivia already handle empty/whitespace-only (accepted, empty output) and comment-only (verbatim + trailing-newline policy) documents — discharged by tests, same as 03-02's format.mbt scope"
  - "No CRLF rows exist in the 44-row manifest; the \\r\\n byte-preservation contract is carried by the 4.x-crlf fixture and the Lf/Crlf override fixtures in formatter_test.mbt"

requirements-completed: [FMT-02, FMT-03]

# Coverage metadata (#1602) — one entry per shipped deliverable.
coverage:
  - id: D1
    description: "All six format dimensions functional end-to-end: Lower keyword case (identifiers/quoted names/strings/comments/hints byte-identical), indent 4 in broken lists, line_width 20 breaks where 100 does not, Leading comma at default width, Lf override on CRLF input, Crlf override on LF input, trailing-newline off and normalize-to-one — each golden-tested with idempotence + reparse"
    requirement: FMT-02
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_03_03_all_six_dimensions_functional"
        status: pass
    human_judgment: true
  - id: D2
    description: "No hard-coded policy constants in layout code paths: grep over formatter/layout.mbt finds only the Lf/Crlf byte definitions and options accessors — every policy value flows from FormatOptions (D-26)"
    requirement: FMT-02
    verification:
      - kind: unit
        ref: "grep audit over formatter/layout.mbt (127-138 are the Lf/Crlf definitions; line_width at scan_comma_list, indent at emit, comma_style at layout_comma_list_break, newline_style at detect_newline, trailing_newline at finalize_output, keyword_case at emit_token)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Full 44-row embedded corpus harness: fixture_ids match corpus/manifest.tsv exactly; 30 rows from corpus_test's embedded records, 14 authored from disk select-industrial bodies (recovery tail split into the 4.x-recovery row) and recorded inline bytes; every accepted row byte-exact idempotent and zero-diagnostic reparse; every error/version-negative row refuses with DORIS-FORMAT-001 and empty output; statement offsets index into output"
    requirement: FMT-03
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_corpus_44_row_harness"
        status: pass
    human_judgment: true
  - id: D4
    description: "Option-matrix idempotence + determinism: cartesian product of all six dimensions' supported values (2 x 2 x 3 x 2 x 2 x 2 = 96 combos) x {SELECT, DDL} fixtures, byte-exact idempotence and two-run determinism per combo, failures name the offending combination"
    requirement: FMT-03
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_03_03_option_matrix_idempotence_and_determinism"
        status: pass
    human_judgment: false
  - id: D5
    description: "Never-panic boundary suite: empty, whitespace-only, comment-only documents accepted with no fabricated statements and the trailing-newline policy applied to comment-only output; max_bytes boundary yields ParseError::InputTooLarge; the full corpus array plus boundary inputs format without panic"
    requirement: FMT-03
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_03_03_never_panic_boundary_suite"
        status: pass
    human_judgment: false
  - id: D6
    description: "Refusal-diagnostic shape gate over the corpus error rows: every DORIS-FORMAT- diagnostic has error severity, expected_class \"format\", valid span ordering, and a non-empty message"
    requirement: FMT-03
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_03_03_refusal_diagnostics_are_well_formed"
        status: pass
    human_judgment: false

# Metrics
duration: 63min
completed: 2026-08-04
status: complete
---

# Phase 3 Plan 3: Six-Dimension Configuration, Corpus Contract, and Idempotence Matrix Summary

**All six FormatOptions dimensions drive real layout behavior with no hard-coded constants, the full 44-row manifest is mirrored into an embedded corpus harness proving byte-exact idempotence and zero-diagnostic reparse (D-34/D-35), the option matrix is idempotent and deterministic across every supported combination, and the formatter is proven never to panic on boundary inputs**

## Performance

- **Duration:** 63 min
- **Started:** 2026-08-04T11:05:00Z
- **Completed:** 2026-08-04T12:08:00Z
- **Tasks:** 3
- **Files modified:** 3 (formatter/case.mbt, formatter/layout.mbt, test/formatter_test.mbt)

## Accomplishments
- **Six dimensions functional (FMT-02 / D-26)**: `rewrite_keyword_case` (case.mbt) renders Upper as the classification-table canonical word and Lower as its ASCII case-fold — the classification table stays the single keyword authority; quoted names, strings, comments, hints, and identifiers pass through byte-identical because `classification_of` only matches bare words. `emit_token` now reads `options.keyword_case()`; the grep audit confirms the only literal newlines in layout.mbt are the Lf/Crlf definitions in `detect_newline`, and every policy value flows through options accessors (line_width in measure-then-break, indent in break_line, comma_style, newline_style, trailing_newline). Eight golden fixtures make each dimension observable (Lower, indent 4, width-100-vs-20, Leading at default width, Lf/Crlf overrides beating FollowInput, trailing-newline off, normalize-to-one).
- **Full 44-row corpus harness (FMT-03 / D-34/D-35)**: `formatter_corpus_fixtures` mirrors every manifest row — 30 from the corpus_test embedded records (provenance headers stripped, matching the Phase 2 convention), 14 authored from the disk select-industrial bodies (the 4.x recovery tail split into the `4.x-recovery` row) and the recorded inline bytes for boundary/invalid-encoding/contextual/unsupported rows. The oracle per row: accepted fixtures hit the reviewed golden byte-exact, stay idempotent, reparse with zero diagnostics, and keep every statement offset inside the output; error/version-negative rows refuse with empty output and DORIS-FORMAT-001 (the malformed half of D-34 is a refusal assertion, never a skipped test — Pitfall 6). Goldens were authored by the first formatter run and reviewed before commit (Pitfall 7); runtime loads no disk files (STATE.md).
- **Option-matrix idempotence + determinism**: the cartesian product of the supported values of all six dimensions (96 combinations) is asserted byte-exact idempotent AND deterministic (two runs identical) for a representative SELECT and one DDL fixture; a failure names the offending combination (keyword/comma/newline/trailing/indent/width).
- **Never-panic boundary suite**: empty, whitespace-only, and comment-only documents format accepted with no fabricated statements (the trailing-newline policy applies to comment-only output — on = exactly one, off = none); the max_bytes boundary yields `ParseError::InputTooLarge`, never a crash (T-03-16); the full corpus array plus boundary inputs run without panic (T-03-18, Pitfall 4).
- **Refusal-diagnostic shape gate**: every DORIS-FORMAT- diagnostic across the corpus error rows is well-formed (error severity, expected_class "format", valid span ordering, non-empty message).
- 183/183 tests pass; `moon check --target native` clean; `printer/` untouched (D-27); formatter imports still only source/token/syntax + core.

## Task Commits

Each task was committed atomically:

1. **Task 1: All six dimensions functional with no hard-coded layout constants** - `0ae2248` (feat) — `rewrite_keyword_case` + `ascii_case_fold` in case.mbt, `emit_token` wired to `options.keyword_case()`, and eight dimension-observable goldens (Lower with quoted `"SELECT"`/`view` untouched, indent 4, width 100-vs-20, Leading at default width, Lf/Crlf overrides, trailing-newline off, normalize-to-one)
2. **Task 2: Full 44-row embedded corpus harness (D-34/D-35 contract)** - `ab31d8d` (feat) — `formatter_corpus_fixtures` (44 rows) + `formatter_corpus_fixture_check` oracle + `formatter_corpus_44_row_harness` test; goldens authored and reviewed; Rule 1 fix for the pending-break clobber in layout.mbt
3. **Task 3: Option-matrix idempotence, determinism, and never-panic boundary suite** - `2c2c96e` (feat) — matrix (96 combos x SELECT/DDL) with combo-named failures, boundary suite (empty/whitespace/comment-only/max_bytes), refusal-diagnostic shape gate, never-panic loop over the corpus

**Plan metadata:** (final metadata commit records SUMMARY/STATE/ROADMAP)

## Files Created/Modified
- `formatter/case.mbt` - Added `rewrite_keyword_case(raw, KeywordCase)` (Upper = canonical classification word via existing `rewrite_keyword`; Lower = ASCII A-Z->a-z fold of the canonical word) and the `ascii_case_fold` helper
- `formatter/layout.mbt` - `emit_token` now calls `rewrite_keyword_case(raw, self.options.keyword_case())`; Rule 1 fix: a run-newline comment that is the first leaf of a broken-list item no longer clobbers the pending item break with the stale `line_indent` (`!out.pending_break` guards on both comment branches)
- `test/formatter_test.mbt` - `formatter_03_03_all_six_dimensions_functional` (8 dimension fixtures), `formatter_corpus_fixtures` (44 embedded rows), `formatter_corpus_fixture_check` + `formatter_corpus_44_row_harness`, `formatter_matrix_check`/`matrix_combo_name` + `formatter_03_03_option_matrix_idempotence_and_determinism`, `formatter_03_03_never_panic_boundary_suite`, `formatter_03_03_refusal_diagnostics_are_well_formed`

## Decisions Made
- **Lower = ASCII fold of the classification-table word**: the table (token.mbt:450-460) stays the single keyword authority; profile-independent per flagged assumption A7. Quoted `"SELECT"`, strings, and comments never reach the rewrite (non-word bytes fail `classification_of`).
- **Embedded raw policy for the 44-row mirror**: rows with disk files use the corpus_test embedded records (headers stripped — the established Phase 2 convention; the header-preservation path is already covered by the 03-02 `4.x-corpus-script` fixture); rows without disk files embed the recorded inline bytes (boundary/invalid-encoding/contextual/unsupported) or the disk-body split (4.x recovery tail -> `4.x-recovery` row).
- **4.x-industrial TABLET trim** (authoring deviation): the disk body's `TABLET (1001)` after `AS d` hits a pre-existing parser gap (TABLET only parsed on unaliased table refs — probe-verified: `FROM t TABLET (1001)` valid, `FROM t AS d TABLET (1001)` invalid with DORIS-PARSE-001). The embedded raw drops the clause so the manifest's supported status and the D-35 zero-diagnostic gate hold; recorded in the harness header comment.
- **Comment-break guard (Rule 1)**: `break_line_at(line_indent)` overwrote a pending item break when a hint/comment opened a broken-list item, making hint placement depend on whether the input newline sat before or after the hint — a genuine pass-1/pass-2 flip. The guard keeps the pending break (the correct line start at item indent); all existing goldens unchanged.
- **format.mbt unchanged**: the 03-01 entry + `layout_document_trivia` already satisfy the empty/trivia-only acceptance (verified by probe before writing assertions) — same discharge pattern as 03-02.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Hint placement flip-flopped between format passes**
- **Found during:** Task 2 (44-row harness idempotence run — `4.x-industrial: not idempotent`)
- **Issue:** A comment whose original trivia run contains a newline (a hint opening a broken-list item) called `break_line_at(out.line_indent)` with the stale line_indent (0) while the list item's break (indent 1) was still pending — overwriting it. Whether the newline preceded or followed the hint in the input trivia decided the hint's indent, so format(format(x)) moved the hint between passes.
- **Fix:** Both comment branches now skip their break/space request when a pending break already exists (`!out.pending_break`) — the pending break is the correct line start at the item indent.
- **Files modified:** formatter/layout.mbt
- **Verification:** `4.x-industrial` idempotent; all existing goldens byte-identical (180/180 before Task 3, 183/183 after).
- **Committed in:** ab31d8d (Task 2 commit)

**2. [Rule 3 - Blocking] Golden authoring needed a runnable probe harness**
- **Found during:** Task 2 (golden authoring)
- **Issue:** `moon test` swallows `println` output for passing tests and the generated test driver needs opaque file/index args, so the plan's "set expected_golden by the first authoring run" needed a working channel to observe formatter output.
- **Fix:** A temporary probe test file (`test/formatter_probe.mbt`) with one intentionally-failing assert per fixture rendered the actual output as hex in the failure message; goldens were decoded from the rendered hex, reviewed, and embedded; the probe was deleted before the Task 2 commit.
- **Files modified:** test/formatter_probe.mbt (temporary, deleted; not committed)
- **Verification:** All 44 embedded goldens match the observed output; harness passes.
- **Committed in:** ab31d8d (probe itself never committed)

### Auth Gates

None.

## Known Stubs

None — no placeholder goldens, no skipped fixtures, no unrun verifies. The only synthesized byte in the engine (the probe-sanctioned last-item comma from 03-02) is unchanged and re-verified by the corpus harness. The 4.x-industrial TABLET trim is a documented authoring deviation with probe evidence, not a stub.

## Threat Surface Scan

No new security-relevant surface: the formatter remains a pure, backend-neutral library over the lossless CST; no new endpoints, file access, or schema changes. All six threat-model mitigations for this plan (T-03-14 matrix idempotence, T-03-15 corpus drift, T-03-16 max_bytes, T-03-17 invalid config, T-03-18 panic) are implemented and tested as described in the coverage table.

## Next Phase Readiness
- 03-04 CLI consumes the option surface directly: `KeywordCase::from_id` / `CommaStyle::from_id` / `NewlineStyle::from_id` string-id mapping was already tested (03-01) and the six-dimension behavior is now golden-locked end to end.
- Phase 4 LSP formatting can reuse `api.format_with_ids`/`format_with_metadata` with per-editor options; `statement_offsets` are asserted in bounds across every multi-statement corpus row (ECO-02 range edits).
- Known boundary for consumers (unchanged from 03-02): the literal Pattern-1 clause breaks and zero-space-before-paren convention produce terse canonical forms; all deterministic, idempotent, reparse-clean, and golden-locked.

## Self-Check: PASSED
- All three task commits exist: `0ae2248`, `ab31d8d`, `2c2c96e` (verified via git log).
- Final acceptance re-run on the committed state: `moon test` 183/183 passed; `moon check --target native` 0 errors; `printer/` untouched (0 diff lines); D-27 negative import gates hold (formatter/moon.pkg unchanged).
- 44-row array verified against manifest.tsv (fixture_id match, no skipped/invented rows); every error row asserts DORIS-FORMAT-001 refusal; option matrix covers all 96 supported combinations; boundary suite green; no stubs or skipped tests — the broken-windows ledger needs no entries.

---
*Phase: 03-formatting-and-safe-edits*
*Completed: 2026-08-04*
