---
phase: 11-flink-grammar-and-recoverable-cst
plan: 04
subsystem: parser
tags: [flink, window-tvf, match-recognize, recoverable-cst, dialect-gate, snapshot]

# Dependency graph
requires:
  - phase: 11-03
    provides: Flink CREATE TABLE complex forms (SqlCreateTable :1585-1712), Catalog/DATABASE/VIEW/FUNCTION DDL dispatch, flink-grammar snapshot harness
provides:
  - "Window TVF (TUMBLE/HOP/CUMULATE/SESSION + TABLE wrapper + DESCRIPTOR/INTERVAL/offset/named args) through the Flink table-ref path (TableFunctionCall, Parser.jj:2443-2460)"
  - "Syntax-level MATCH_RECOGNIZE sub-language (PATTERN/DEFINE/MEASURES/skip policy/pattern variables/quantifiers, anchors, WITHIN INTERVAL) with independent sync points (MatchRecognize, Parser.jj:3062-3346)"
  - "Bidirectional dialect-negative gates: Window TVF and MATCH_RECOGNIZE reject under Doris with FATHOM-PARSE-009 (T-11-22/T-11-23), completing the D-04 matrix"
  - "TVF + MATCH_RECOGNIZE supported/known-limitation subset frozen into flink-grammar fixtures and snapshots (50 goldens) with provenance manifest rows"
affects: [12-cross-dialect-corpus-and-parity-gates, 13-toolchain-and-editor-packaging]

actuals:
  tokens: 74405   # chars/4 over the realized diff (297623 chars)
  tasks: 3
  commits: 5

tech-stack:
  added: []
  patterns:
    - "Generic table-function-call TVF path with positional + named-argument validation (TableFunctionCall)"
    - "Independent nested sub-language with its own recovery sync points (is_flink_match_recognize_boundary)"
    - "Construct-level dialect gate at the table-ref point (FATHOM-PARSE-009) symmetric to the Doris-only gate"

key-files:
  created:
    - "parity/__snapshot__/flink-grammar.tvf-*.json (22) + flink-grammar.match-recognize-*.json (28) — TVF/MR snapshot goldens"
  modified:
    - "parser/parser.mbt — Flink parse_table_ref TVF branch + MATCH_RECOGNIZE suffix, Doris 009 gates, is_flink_tvf_starter / is_match_recognize_suffix / is_flink_match_recognize_boundary"
    - "parser/flink_grammar.mbt — parse_flink_tvf_call + arguments, parse_match_recognize + pattern sub-language"
    - "parity/flink_grammar_test.mbt — TVF + MATCH_RECOGNIZE four-category fixtures + bidirectional/undeclared-variable gates"
    - "parity/fixtures/flink-grammar/manifest.tsv — 25 TVF/MR provenance rows"
    - "scripts/extract_flink_grammar.py — validate_manifest accepts template/gate provenance formats (Rule 1 fix)"
    - ".planning/phases/11-flink-grammar-and-recoverable-cst/approved-changes.md — Wave 4 register rows"

key-decisions:
  - "Window TVF rides the generic table-function-call path (no dedicated dispatch): TUMBLE/HOP/SESSION/DESCRIPTOR non-reserved (Parser.tdd:587/:384/:509/:351), CUMULATE no keyword token (A2)"
  - "MATCH_RECOGNIZE is an independent sub-language with its own sync points so unclosed PATTERN/DEFINE recovers at the boundary or ';' under the shared budget (Pitfall 4/8, T-11-24)"
  - "SUBSET/PERMUTE/{- -} parse structurally and are classified known-limitation in fixtures (RESEARCH §8.2); no pattern-variable column-scope validation (Pitfall 6, FLINK-06)"
  - "TVF positional arguments validated in order (table/descriptor/size/offset); named `=>` args recognized without reordering (probe FLINK-05 ordering)"
  - "Both constructs are Flink-only: 009 gate at the table-ref point under Doris (T-11-22/T-11-23); no planner/execution equivalence claimed (FLINK-05/06, T-11-26)"

patterns-established:
  - "Pattern: generic TVF argument layer with positional-kind validation + named-argument => recognition"
  - "Pattern: nested sub-language recovery via dedicated boundary predicate + shared consume_recovery_step/depth_allowed budget"

requirements-completed: [FLINK-05, FLINK-06]

coverage:
  - id: D1
    description: "Window TVF forms (TUMBLE/HOP/CUMULATE/SESSION + TABLE wrapper + DESCRIPTOR/INTERVAL/offset/named args) parse into recoverable lossless CST under flink-2.3.0; window_start/window_end/window_time are ordinary projection identifiers"
    requirement: FLINK-05
    verification:
      - kind: unit
        ref: "parity/flink_grammar_test.mbt#flink-grammar tvf-tumble-day / tvf-hop-four-arg / tvf-cumulate / tvf-session / tvf-table-wrapper / tvf-offset-interval / tvf-named-arg"
        status: pass
      - kind: integration
        ref: "_build/native/release/build/fathom-sql/fathom-sql.exe parse --dialect flink --profile flink-2.3.0 (TASK 1 VERIFY PASSED)"
        status: pass
    human_judgment: false
  - id: D2
    description: "MATCH_RECOGNIZE parses as a syntax-level sub-language (PATTERN/DEFINE/MEASURES/skip/variables/quantifiers, anchors, WITHIN INTERVAL) with bounded recovery at its own sync points and no pattern-variable scope validation"
    requirement: FLINK-06
    verification:
      - kind: unit
        ref: "parity/flink_grammar_test.mbt#flink-grammar match-recognize-full / -anchors / -within-interval / -all-rows / -measures-time / -skip-last / -recovery"
        status: pass
      - kind: integration
        ref: "_build/native/release/build/fathom-sql/fathom-sql.exe parse --dialect flink --profile flink-2.3.0 (TASK 2 VERIFY PASSED)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Window TVF and MATCH_RECOGNIZE reject under Doris with FATHOM-PARSE-009 while the same inputs parse valid under Flink (bidirectional negative gate, no double-valid)"
    requirement: FLINK-05
    verification:
      - kind: unit
        ref: "parity/flink_grammar_test.mbt#flink_grammar_tvf_is_dialect_gated / flink_grammar_match_recognize_is_dialect_gated"
        status: pass
      - kind: integration
        ref: "_build/native/release/build/fathom-sql/fathom-sql.exe parse --dialect doris --profile 4.x (FATHOM-PARSE-009)"
        status: pass
    human_judgment: false
  - id: D4
    description: "TVF + MATCH_RECOGNIZE supported/known-limitation subset frozen into fixtures/snapshots (50 goldens) with provenance manifest rows; extract_flink_grammar.py exits 0; Doris 213-snapshot baseline byte-identical"
    requirement: FLINK-05
    verification:
      - kind: unit
        ref: "scripts/extract_flink_grammar.py (exit 0, 97 manifest rows); moon test --package parity (570/570); git diff parity/__snapshot__ (no doris drift)"
        status: pass
    human_judgment: false

duration: 2h
completed: 2026-08-09
status: complete
---

# Phase 11 Plan 04: Window TVF + MATCH_RECOGNIZE Summary

**Window TVF (TUMBLE/HOP/CUMULATE/SESSION) and syntax-level MATCH_RECOGNIZE land as the final Flink grammar slice** — both ride source-backed recoverable CST with bounded recovery, both reject under Doris with FATHOM-PARSE-009, and the supported/known-limitation subset is frozen into 50 new flink-grammar goldens while the Doris 213-snapshot baseline stays byte-identical.

## Performance

- **Duration:** 2h
- **Started:** 2026-08-09
- **Completed:** 2026-08-09
- **Tasks:** 3 completed
- **Files modified:** 8 source/test/register files + 50 new snapshots

## Accomplishments
- **Window TVF (FLINK-05):** `parse_flink_tvf_call` + positional argument validation parses TUMBLE/HOP/CUMULATE/SESSION (plus the explicit `TABLE(...)` wrapper) with TABLE/`DESCRIPTOR(col)`/INTERVAL size and optional offset arguments, named `=>` arguments (NAMED_ARGUMENT_ASSIGNMENT, Parser.jj:8794), and `window_start`/`window_end`/`window_time` as ordinary projection identifiers — via the generic table-function-call path (TableFunctionCall, Parser.jj:2443-2460), no dedicated dispatch.
- **MATCH_RECOGNIZE (FLINK-06):** `parse_match_recognize` as an independent sub-language covers PARTITION BY / ORDER BY / MEASURES (MATCH_NUMBER()/MATCH_ROWTIME()/MATCH_PROCTIME() as ordinary calls) / ONE ROW vs ALL ROWS PER MATCH / AFTER MATCH SKIP (TO NEXT ROW, TO FIRST|LAST var, PAST LAST ROW) / PATTERN with `^`/`$` anchors, `|` ALTER, concatenation, and `{n}`/`{n,}`/`{n,m}`/`{,m}`/`+`/`*`/`?` + reluctant `?` quantifiers / WITHIN INTERVAL / DEFINE. SUBSET, PERMUTE, and `{- ... -}` parse structurally and are classified known-limitation; no pattern-variable column-scope validation (Pitfall 6). Recovery is bounded by `is_flink_match_recognize_boundary` + the shared recovery budget (Pitfall 4/8, T-11-24).
- **Bidirectional negative gate (D-04):** Window TVF and MATCH_RECOGNIZE reject under Doris with FATHOM-PARSE-009 at the table-ref point (T-11-23/T-11-22) while the same inputs parse valid under Flink — no double-valid (Pitfall 2). The `flink_grammar_tvf_is_dialect_gated` / `flink_grammar_match_recognize_is_dialect_gated` / `flink_grammar_match_recognize_undeclared_variable_is_accepted` tests freeze the matrix.
- **Subset freeze + provenance (Task 3):** 50 new flink-grammar goldens (25 fixtures × strict/editor) across positive/negative/incomplete/recovery categories; 25 manifest provenance rows (Parser-calcite-1.36.0.jj:2391 TableFunctionCall / :3020 MatchRecognize with template line refs 2443-2460 / 3062-3346); every positive/recovery fixture asserts `print_lossless(parse(x)) == x` in both modes; `extract_flink_grammar.py` exits 0; Doris 213-snapshot baseline byte-identical (D-08).

## Task Commits

Each task was committed atomically:

1. **Task 1: Window TVF through the Flink table-ref path** - `5f2d8d8` (feat) + `bbaa250` (test goldens)
2. **Task 2: parse_match_recognize syntax-level sub-language** - `7f0edaa` (feat) + `c92cfd7` (test goldens)
3. **Task 3: TVF + MATCH_RECOGNIZE subset freeze + snapshot finalization** - `f221f7b` (fix: validator provenance formats)

## Files Created/Modified
- `parser/parser.mbt` - Flink parse_table_ref TVF branch (`is_flink_tvf_starter`) + MATCH_RECOGNIZE suffix (`is_match_recognize_suffix`), Doris-mode FATHOM-PARSE-009 gates at the table-ref point (T-11-22/T-11-23), `is_flink_match_recognize_boundary` sub-language sync predicate
- `parser/flink_grammar.mbt` - `parse_flink_tvf_call`/`parse_flink_tvf_arguments`/`parse_flink_tvf_argument(_value)`; `parse_match_recognize` + pre-pattern clauses + `parse_after_match_skip` + measure/define lists + `parse_pattern_expr`/`concat`/`factor`/`primary`/`quantifier`
- `parity/flink_grammar_test.mbt` - 25 TVF/MR fixtures (positive/negative/incomplete/recovery) + snapshot tests + lossless assertions + bidirectional/undeclared-variable gate tests
- `parity/fixtures/flink-grammar/manifest.tsv` - 25 TVF/MR provenance rows
- `parity/__snapshot__/flink-grammar.tvf-*.json` (22) + `flink-grammar.match-recognize-*.json` (28) - snapshot goldens
- `scripts/extract_flink_grammar.py` - validate_manifest accepts parserImpls.ftl / Parser.tdd / D-04 gate provenance (Rule 1 fix)
- `.planning/phases/11-flink-grammar-and-recoverable-cst/approved-changes.md` - Wave 4 register rows (TVF + MR snapshot groups + validator fix)

## Decisions Made
- **TVF generic path:** no dedicated TUMBLE/HOP/CUMULATE/SESSION dispatch — the non-reserved / no-keyword words ride the generic table-function-call path (RESEARCH §5.5).
- **MATCH_RECOGNIZE independent sub-language:** own sync points (`is_flink_match_recognize_boundary`) so unclosed PATTERN/DEFINE recovers at the boundary or `;` under the shared budget (Pitfall 4/8).
- **Known-limitation freeze:** SUBSET/PERMUTE/`{- -}` parse structurally, classified known-limitation; negative-offset TVF (`INTERVAL '-8' HOUR`) syntactically accepted, known-limitation (RESEARCH §8).
- **No pattern-variable validation:** a syntactically valid MATCH_RECOGNIZE referencing an undeclared variable is never rejected (Pitfall 6, FLINK-06).
- **Doris-side 009 gates** at the table-ref point for TVF/MR complete the D-04 bidirectional matrix.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] extract_flink_grammar.py rejected established manifest provenance formats**
- **Found during:** Task 3 (verify: `python3 scripts/extract_flink_grammar.py` exited 1)
- **Issue:** `validate_manifest` only accepted `Parser-calcite-{v}.jj:{line}` grammar_path rows; the 11-02/11-03 rows legitimately referencing `parserImpls.ftl:{line}` / `Parser.tdd:{line}` / `D-04 gate:` provenance failed the validator (a pre-existing defect since 11-02, not introduced by this plan).
- **Fix:** `validate_manifest` now verifies Parser-calcite rows against the pinned files (unchanged) and accepts the template/gate provenance sources the manifest records (D-05 — the pinned release's own codegen templates and in-repo dialect gates).
- **Files modified:** `scripts/extract_flink_grammar.py`
- **Verification:** `python3 scripts/extract_flink_grammar.py` exits 0 (13 production refs + 2 Calcite-base reserved rows + 97 manifest rows).
- **Committed in:** `f221f7b` (Task 3 commit)

**2. [Rule 1 - Bug] TVF arg-0 failure left the cursor at a nested `)`**
- **Found during:** Task 1 (CLI smoke test of the negative `TUMBLE(DESCRIPTOR(rowtime), INTERVAL '1' DAY)`)
- **Issue:** when the first TVF argument was not a TABLE reference, `parse_flink_tvf_argument_value` returned without consuming, and `recover_expression` stopped at the nested `)` of `DESCRIPTOR(rowtime)` — the argument loop then misread it as the TVF close and `parse_from` treated the leftover comma as a FROM-list separator (spurious FATHOM-PARSE-001).
- **Fix:** arg-0 failure now consumes the offending expression via the shared Pratt parser before returning false, so the loop advances past it (recovery budget caps it).
- **Files modified:** `parser/flink_grammar.mbt`
- **Verification:** `TUMBLE(DESCRIPTOR(rowtime), INTERVAL '1' DAY)` now yields two localized 002 diagnostics with no spurious trailing 001.
- **Committed in:** `5f2d8d8` (part of Task 1 commit)

**3. [Rule 1 - Bug] WITHIN INTERVAL double-consumed the INTERVAL keyword; PERMUTE/SUBSET needed comma/structure handling**
- **Found during:** Task 2 (CLI smoke tests of WITHIN INTERVAL, PERMUTE(A, B), SUBSET)
- **Issue:** `WITHIN INTERVAL '1' MINUTE` failed because the code consumed INTERVAL then called `parse_flink_interval_literal` (which expects INTERVAL again); `PERMUTE(A, B)` failed because `,` was not a pattern-concat stop; `SUBSET U = (A, B)` had no clause handler.
- **Fix:** WITHIN delegates to `parse_flink_interval_literal` directly; pattern concat stops at `,` so PERMUTE's comma loop handles the list; added a structural SUBSET clause handler.
- **Files modified:** `parser/flink_grammar.mbt`
- **Verification:** WITHIN INTERVAL, PERMUTE, and SUBSET fixtures all parse valid=true under flink-2.3.0.
- **Committed in:** `7f0edaa` (part of Task 2 commit)

---

**Total deviations:** 3 auto-fixed (Rule 1 bug fixes)
**Impact on plan:** All auto-fixes were necessary for correctness (validator integrity + parser recovery/structural correctness). No scope creep — each fix keeps the deliverable within the frozen subset.

## Issues Encountered
- The plan's Task 1 and Task 2 share every parser file (parser.mbt table-ref branch, flink_grammar.mbt, the parity test), so the implementation was split into per-task commits by temporarily stripping the MATCH_RECOGNIZE block for the Task-1 commit and restoring it for Task 2 — preserving atomic per-task commits without reordering shared edits.
- The `_build/native/release/build/fathom-sql/fathom-sql.exe` binary is not rebuilt by `moon test`; the verify commands required an explicit `moon build --target native --release fathom-sql` to exercise the new grammar.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 11 grammar scope is complete: FLINK-02..06 + CST-01 all land real Flink grammar with the Doris baseline intact. Window TVF and MATCH_RECOGNIZE are syntax-level CST (no planner/execution equivalence), ready for Phase 12 cross-dialect corpus/parity and Phase 13 tooling.
- Known-limitation surface (SUBSET/PERMUTE/`{- -}` structural, negative-offset TVF) is frozen in fixtures for the verifier; no blocking concerns.

---
*Phase: 11-flink-grammar-and-recoverable-cst*
*Completed: 2026-08-09*
