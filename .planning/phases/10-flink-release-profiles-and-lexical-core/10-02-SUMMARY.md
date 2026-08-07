---
phase: 10-flink-release-profiles-and-lexical-core
plan: 02
subsystem: api
tags: [flink, calcite, lexer, dialect, moonbit, snapshot, parity, tdd]

# Dependency graph
requires:
  - phase: 10-flink-release-profiles-and-lexical-core
    provides: "10-01 FlinkProfile enum + FlinkProfileMetadata (calcite_version/parser_config) + the `#` lexical branch + flink-lexical manifest/extractor scaffold"
provides:
  - "Dialect-parameterized lexer: `//` comments, `\"` DOUBLE_QUOTE symbol, BTID backtick double-escape, `'...'` strings without backslash escape, X/U&/N/E prefixed literals (E profile-gated), B-is-not-a-prefix, `||`/`=>`/`..` single symbols"
  - "flink-lexical conflict-matrix snapshot group (26 files): double-quote, slash-comment, e-literal version gate, backtick-escape, unknown-profile — independent namespace, Doris 213-snapshot baseline byte-identical"
  - "doris-4.x provenance row in the flink-lexical manifest and the wave-2 approved-changes register entry"
affects: [10-flink-release-profiles-and-lexical-core (10-03 keyword classification), 11-flink-grammar-and-recoverable-cst]

# Actuals (#2632) — pairs with the plan's `estimate` (34k chars/4). Same scale (chars/4 over the realized diff).
actuals:
  tokens: 15783
  tasks: 2
  commits: 4

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "match context.dialect at each scanning branch with the Doris arm preserved verbatim (Pitfall 1 zero-drift)"
    - "E-literal availability gate as FlinkProfile::supports_escape_literal — policy authority in dialect/, lexer reads it via from_id (T-10-08)"
    - "independent flink-lexical snapshot namespace with approved-changes register discipline (D-04/D-08): register commit BEFORE the single --update"

key-files:
  created:
    - parity/__snapshot__/flink-lexical.{double-quote,slash-comment,e-literal,backtick-escape,unknown-profile}.*.json (22 files)
  modified:
    - lexer/lexer.mbt
    - dialect/flink.mbt
    - parity/flink_lexical_test.mbt
    - parity/fixtures/flink-lexical/manifest.tsv
    - .planning/phases/10-flink-release-profiles-and-lexical-core/approved-changes.md

key-decisions:
  - "TokenKind unchanged: Flink prefixed literals (X/U&/N/E'..') map to the existing StringLiteral kind — minimal-extension bias documented in lexer.mbt; a distinct kind is unnecessary (token/token.mbt untouched)"
  - "E'..' availability lives on FlinkProfile::supports_escape_literal (flink-2.3.0/2.1.3 true, flink-1.20.5 false), grounding the gate in the pinned Calcite version evidence (Parser-calcite-1.36.0.jj:8721 / 1.34.0:8469 / absent in 1.32.0)"
  - "unknown-profile fixture freezes a Doris-shaped profile id (4.x) under flink — Pitfall 6: profile-id forms are never borrowed across dialects; the FATHOM-SCHEMA-003 envelope is mode-independent"

patterns-established:
  - "Dialect-parameterized scanner: Flink arms use dedicated scanners (scan_flink_string / scan_flink_escaped_string / scan_flink_backtick) grounded in the pinned Calcite grammar; Doris arms keep scan_quoted byte-identically"
  - "symbol_width_flink extends the shared comparison-op width with CONCAT/NAMED_ARGUMENT_ASSIGNMENT/DOUBLE_PERIOD without touching the Doris path"
  - "flink_prefixed_literal detects X/U&/N/E at the identifier boundary using direct byte comparisons (Bytes has no slice in moon 0.1.20260724)"

requirements-completed: [FLINK-01]

# Coverage (#1602) — per-deliverable Requirements Traceability Matrix.
coverage:
  - id: D1
    description: "Dialect-parameterized lexer branches: `//` comments (one Comment under Flink, two SLASH symbols under Doris), `\"` DOUBLE_QUOTE Symbol under Flink, BTID backtick double-escape, `'...'` strings without backslash escape, X/U&/N prefixed literals as single tokens, B-is-not-a-prefix, `||`/`=>`/`..` single Symbol tokens — Doris arms byte-identical"
    requirement: FLINK-01
    verification:
      - kind: unit
        ref: "lexer/lexer.mbt#flink_lexer_slash_comment_routes_by_dialect"
        status: pass
      - kind: unit
        ref: "lexer/lexer.mbt#flink_lexer_double_quote_routes_by_dialect"
        status: pass
      - kind: unit
        ref: "lexer/lexer.mbt#flink_lexer_backtick_btid_escaping"
        status: pass
      - kind: unit
        ref: "lexer/lexer.mbt#flink_lexer_prefixed_literals_and_b_not_prefix"
        status: pass
      - kind: unit
        ref: "lexer/lexer.mbt#flink_lexer_operator_symbols_single_tokens"
        status: pass
      - kind: unit
        ref: "lexer/lexer.mbt#flink_lexer_comparison_operators_remain_single_symbols_both_dialects"
        status: pass
    human_judgment: false
  - id: D2
    description: "E'..' (C_STYLE_ESCAPED_STRING_LITERAL) availability gated by the selected FlinkProfile — ONE literal token under flink-2.3.0/2.1.3, Identifier `E` + StringLiteral under flink-1.20.5"
    requirement: FLINK-01
    verification:
      - kind: unit
        ref: "lexer/lexer.mbt#flink_lexer_e_literal_is_profile_gated"
        status: pass
      - kind: integration
        ref: "parity/flink_lexical_test.mbt#flink_lexical_e_literal_is_version_gated_in_fixtures"
        status: pass
    human_judgment: false
  - id: D3
    description: "flink-lexical conflict-matrix snapshot group (26 files): double-quote, slash-comment, e-literal version gate, backtick-escape, unknown-profile — explainable per-dialect tokenization (D-06), Doris 213-snapshot baseline byte-identical, register-before-update discipline (D-04/D-08)"
    requirement: FLINK-01
    verification:
      - kind: integration
        ref: "moon test --package parity (no --update) — 260 tests pass, git diff --name-only -- parity/__snapshot__ shows only flink-lexical.* files"
        status: pass
    human_judgment: false

# Metrics
duration: 10min
completed: 2026-08-07
status: complete
---

# Phase 10 Plan 2: Flink Lexical Core Summary

**Dialect-parameterized Flink lexer (comments, quoting, literals, operators, backtick escaping) frozen as a 26-file flink-lexical conflict-matrix snapshot group while the Doris 213-snapshot baseline stays byte-identical**

## Performance

- **Duration:** 10 min
- **Started:** 2026-08-07T11:11:27Z
- **Completed:** 2026-08-07T11:21:24Z
- **Tasks:** 2
- **Files modified:** 27 (5 source/manifest/register + 22 generated snapshots)

## Accomplishments
- Full §9 Flink lexical matrix implemented as `match context.dialect` branches in the shared scanner: `//` and `--` are SINGLE_LINE_COMMENT, `"` is a DOUBLE_QUOTE symbol, backticks scan per BTID double-escape (no backslash, no raw newline), single-quoted strings double `''` with NO backslash escape, X/U&/N prefixed literals become one StringLiteral token, E is profile-gated (flink-2.3.0/2.1.3 yes, flink-1.20.5 no), B is not a literal prefix, and `||`/`=>`/`..` scan as single symbols — every branch grounded in the pinned release grammar (Parser-calcite-1.36.0.jj:8708-8962).
- Doris arms byte-identical: all 6 behavior tests assert the Doris path verbatim, `moon test --package parity` passes with zero doris-named snapshot drift.
- D-06 conflict matrix frozen as explainable flink-lexical snapshots: double-quote (Symbol vs Quoted), slash-comment (Comment vs two Symbols), e-literal version gate (8 snapshots across 3 flink profiles + doris), backtick-escape, and unknown-profile (FATHOM-SCHEMA-003 for a Doris-shaped id under flink — Pitfall 6).
- D-08 register discipline followed: the wave-2 register entry + manifest + test code were committed BEFORE the single approved `--update`; the Doris 213-snapshot baseline is byte-identical.

## Task Commits

Each task was committed atomically:

1. **Task 1: Dialect-aware lexer branches for Flink quoting, literals, operators, and backtick escaping** (TDD)
   - `71e21c9` (test) — RED: 6 failing Flink lexical behavior tests
   - `2d835fa` (feat) — GREEN: lexer dialect branches + `FlinkProfile::supports_escape_literal`
2. **Task 2: Conflict-matrix parity fixtures + flink-lexical snapshot group expansion**
   - `f37a324` (feat) — wave-2 fixtures, 22 snapshot gates + 5 conflict assertions, manifest doris-4.x row, approved-changes register
   - `03e70d2` (test) — 22 frozen flink-lexical snapshot files

## Files Created/Modified
- `lexer/lexer.mbt` — `scan_flink_string`/`scan_flink_escaped_string`/`scan_flink_backtick`/`symbol_width_flink`/`flink_prefixed_literal`/`flink_supports_escape_literal`; dialect branches in `lex_with_limit` (`//`, `"`, backtick, single-quote, literal prefixes, symbol width); 6 new Flink behavior tests
- `dialect/flink.mbt` — `FlinkProfile::supports_escape_literal` (E'..' availability gate, policy authority)
- `parity/flink_lexical_test.mbt` — wave-2 conflict-matrix fixtures, 22 `@test.T::snapshot` gates, 5 conflict-assertion tests
- `parity/__snapshot__/flink-lexical.{double-quote,slash-comment,e-literal,backtick-escape,unknown-profile}.*.json` — 22 new frozen snapshots (26 total with wave-1 hash-comment)
- `parity/fixtures/flink-lexical/manifest.tsv` — appended doris-4.x provenance row
- `.planning/phases/10-flink-release-profiles-and-lexical-core/approved-changes.md` — wave-2 register entries

## Decisions Made
- **Minimal TokenKind extension:** Flink prefixed literals (X/U&/N/E'..') map to the existing `StringLiteral` kind — `token/token.mbt` is untouched. The plan allowed this unless "a distinct TokenKind is documented as necessary"; it is not necessary for the token-stream/snapshot contract.
- **Policy authority for the E gate:** `FlinkProfile::supports_escape_literal` lives in `dialect/flink.mbt` (the DIALECT-02 policy authority); the lexer reads the selected profile via `from_id` — never a hardcoded version string in the scanner.
- **unknown-profile fixture semantics:** a Doris-shaped profile id (`4.x`) requested under flink freezes the FATHOM-SCHEMA-003 rejection envelope, directly exercising Pitfall 6 (profile-id forms never borrowed across dialects). The envelope is mode-independent (rejection before mode parsing).

## Deviations from Plan

None — plan executed as written (2 documentation notes below, no Rule 1-4 auto-fixes needed).

**Notes (not deviations from intent):**

1. **Test 3 strengthened for BTID faithfulness.** The plan's stated assertions (`` `a``b` `` → one Quoted token, lone backtick → unterminated) already pass under the shared `scan_quoted`; to actually exercise the Flink-specific BTID scanner I added one assertion that `` `x\` `` closes at the final backtick under Flink (BTID has no backslash escape) — directly grounded in the pinned BTID grammar (Parser-calcite-1.36.0.jj:8951-8962).
2. **Plan verify quirk.** The Task 2 `<verify>` line `grep -l "flink-lexical\." parity/__snapshot__/*.json | wc -l` searches file *content* (which contains no `flink-lexical.` string) and returns 0; the correct file-name count via glob is **26** (`ls parity/__snapshot__/flink-lexical.*.json | wc -l`). The deliverable satisfies the intent; the count is verified as 26.

---

**Total deviations:** 0 auto-fixed (Rules 1-4)
**Impact on plan:** None — no scope creep, no correctness fixes required.

## Issues Encountered
- `Bytes` has no `slice` method on moon 0.1.20260724 — the Flink literal-prefix detection was rewritten to use direct byte comparisons (`bytes[start].to_int()`, single-character prefix length check) instead of sub-byte slicing.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- 10-03 can build the Flink keyword classification on top of a verified lexical core; the E-literal gate (`FlinkProfile::supports_escape_literal`) and the flink-lexical snapshot namespace are the reusable contracts.
- Phase 11 grammar work consumes the dialect-parameterized lexer directly: `"` as Symbol, backtick BTID Quoted, `'...'` no-backslash strings, prefixed literals, and `||`/`=>`/`..` single symbols are already tokenized per the pinned Calcite contract.
- No blockers.

---
*Phase: 10-flink-release-profiles-and-lexical-core*
*Completed: 2026-08-07*

## Self-Check: PASSED
- Files exist: 10-02-SUMMARY.md, lexer/lexer.mbt, dialect/flink.mbt, parity/flink_lexical_test.mbt, manifest.tsv
- Commits exist: 71e21c9 (RED), 2d835fa (GREEN), f37a324 (fixtures+register), 03e70d2 (snapshots)
- flink-lexical snapshot count: 26 (glob-verified)
