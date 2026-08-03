---
phase: 01-core-kernel
plan: 03
subsystem: core-kernel
tags: [moonbit, recovery, diagnostics, strict-editor, exact-replay]

# Dependency graph
requires:
  - phase: 01-core-kernel/01-02
    provides: immutable source-backed CST, explicit profile parser API, primitive diagnostics, exact replay
provides:
  - bounded progress-or-error parser recovery with expression/clause/statement synchronization
  - strict/editor results sharing one CST family with explicit missing, error, and skipped forms
  - finite byte/token/recursion/recovery/diagnostic limits with stable resource diagnostics
  - deterministic DORIS-PARSE diagnostics and snapshot-local monotonic statement identities
  - deterministic module-root source/parser/recovery tests for malformed, capped, invalid-byte, and replay cases
affects: [01-04-select-corpus, CORE-02, CORE-03, CORE-05, CORE-06, CORE-07]

# Actuals (#2632)
actuals:
  tokens: 8119
  tasks: 2
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns: [bounded recovery budgets, layered synchronization, source-backed skipped remainder, stable resource diagnostics]

key-files:
  created:
    - test/moon.pkg
    - test/source_test.mbt
    - test/parser_test.mbt
    - test/recovery_test.mbt
  modified:
    - parser/parser.mbt
    - api/api.mbt
    - syntax/syntax.mbt
    - printer/printer.mbt

key-decisions:
  - "ParseLimits is exposed at the API boundary and translated into parser-owned limits, preserving parser/API dependency direction."
  - "DORIS-PARSE-003 covers source encoding and unterminated lexical material; DORIS-PARSE-004 is reserved for one bounded resource diagnostic."
  - "Capped input is retained as one source-backed SKIPPED node while primitive replay always returns the one root source snapshot."

patterns-established:
  - "Every recovery path consumes a token or creates a zero-width MISSING node; recovery synchronization stops at delimiters, clause keywords, semicolons, or EOF."
  - "Diagnostic caps reserve a deterministic resource slot and all diagnostic spans remain half-open byte intervals within the root source."

requirements-completed: [CORE-02, CORE-03, CORE-05, CORE-06, CORE-07]

coverage:
  - id: D1
    description: "Bounded strict/editor parser recovery with explicit missing/error/skipped nodes"
    requirement: CORE-06
    verification:
      - kind: unit
        ref: "test/recovery_test.mbt#caps_emit_resource_diagnostic_and_retain_bounded_remainder"
        status: pass
      - kind: other
        ref: "moon test"
        status: pass
    human_judgment: false
  - id: D2
    description: "Stable diagnostic namespace, spans, expected classes, and snapshot-local statement IDs"
    requirement: CORE-05
    verification:
      - kind: unit
        ref: "test/parser_test.mbt#diagnostic_identity_resets_for_each_snapshot"
        status: pass
      - kind: other
        ref: "moon check --target native && moon build --target native --release"
        status: pass
    human_judgment: false
  - id: D3
    description: "Malformed, invalid-byte, newline, Unicode, capped, and lexical inputs replay their original bytes"
    requirement: CORE-03
    verification:
      - kind: unit
        ref: "test/source_test.mbt#source_replay_preserves_line_endings_bom_unicode_and_invalid_bytes"
        status: pass
      - kind: unit
        ref: "test/recovery_test.mbt#malformed_lexical_material_uses_stable_code_and_replays"
        status: pass
    human_judgment: false
# Metrics
duration: 48min
completed: 2026-08-03
status: complete
---

# Phase 1 Plan 3: Bounded Recovery and Stable Diagnostics Summary

**有界 strict/editor 恢复、显式缺失/错误/跳过节点与稳定诊断已接入同一无损 CST，并由离线字节回放与资源上限测试守护。**

## Performance

- **Duration:** 48 min
- **Started:** 2026-08-03T11:08:21Z
- **Completed:** 2026-08-03
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments

- Parser now exposes finite `max_bytes`, `max_tokens`, `max_recursion_depth`, `max_recovery_steps`, and `max_diagnostics` budgets, with progress guards, expression/clause/statement synchronization, and source-backed bounded remainder retention.
- Strict and editor modes continue to use one CST family; malformed inputs remain `valid: false`, while editor results set `recovered` and preserve explicit `MISSING`, `ERROR`, and `SKIPPED` structures without changing source bytes.
- API diagnostics retain severity, stable `DORIS-PARSE-###` codes, message, expected class, byte spans, and zero-based snapshot-local statement identities. Invalid UTF-8 and unterminated lexical material are diagnosed while remaining source-backed.
- Deterministic module-root tests cover line-ending variants, BOM, Unicode/emoji, invalid bytes, malformed expressions, lexical truncation, later statements, resource caps, depth limits, diagnostics, and exact replay.

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement bounded strict/editor recovery and stable diagnostics** - `c3d24c9`
2. **Task 2: Add focused recovery, source, and diagnostic tests** - `305d619`

## Files Created/Modified

- `parser/parser.mbt` - bounded recursive-descent/Pratt recovery, synchronization, limits, diagnostics, and statement identity.
- `api/api.mbt` - public `ParseLimits`, options wiring, and primitive diagnostic transport.
- `syntax/syntax.mbt` - explicit error/skipped node constructors and predicates.
- `printer/printer.mbt` - documents exact root replay after resource caps.
- `test/moon.pkg` - module-root deterministic test package imports.
- `test/source_test.mbt` - raw-byte, newline, BOM, Unicode, invalid-byte, and span-bound tests.
- `test/parser_test.mbt` - SELECT, statement order, strict/editor parity, and diagnostic identity tests.
- `test/recovery_test.mbt` - bounded caps, skipped remainder, recursion depth, lexical errors, and replay tests.

## Decisions Made

- Kept resource limits in the public API while constructing the parser's private limit type through a constructor, avoiding a dependency cycle or cross-package mutable struct construction.
- Reserved `DORIS-PARSE-004` for the single resource-limit diagnostic and retained `DORIS-PARSE-003` for encoding/unterminated lexical material so the diagnostic namespace remains stable and three-digit.
- Retained complete caller bytes at the result root even when parsing is capped; CST descendants remain spans/leaves and `print_result` remains byte-exact.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Diagnosed unterminated lexical tokens carrying lexer diagnostic codes**
- **Found during:** Task 2 (`malformed_lexical_material_uses_stable_code_and_replays`)
- **Issue:** The lexer represents unterminated strings/comments with a token `diagnostic_code` while retaining the normal literal/comment token kind, so checking only `token.is_error()` omitted the parser diagnostic.
- **Fix:** Parser lexical-diagnostic collection now checks both `is_error()` and a present token diagnostic code, preserving source-backed material and emitting `DORIS-PARSE-003`.
- **Files modified:** `parser/parser.mbt`
- **Verification:** `moon test` passed all 36 tests.
- **Committed in:** `c3d24c9`

**Total deviations:** 1 auto-fixed (Rule 1: 1)
**Impact on plan:** The fix was required for the explicitly requested unterminated string/comment and stable lexical diagnostic coverage; no scope creep.

## Issues Encountered

- MoonBit emitted existing non-blocking redundant-public/core-debug/deprecation warnings during check/build/test; no formatter or linter was run, and warnings did not prevent successful verification.
- The focused test package reports unused-import warnings during package checking even though the test files exercise those aliases under `moon test`; all tests execute and pass.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Wave 3 now provides bounded recovery, stable diagnostic identity, and byte-faithful malformed-input behavior for 01-04's released SELECT corpus expansion. The remaining known limitation is that industrial SELECT grammar breadth (joins, windows, grouping sets, and full CTE productions) remains intentionally deferred to 01-04.

## Self-Check: PASSED

- `parser/parser.mbt`, `api/api.mbt`, `syntax/syntax.mbt`, `printer/printer.mbt`, and all four `test/` files exist and were committed in `c3d24c9`/`305d619`.
- Task commits `c3d24c9` and `305d619` are present.
- Final verification passed: `moon check --target native`, `moon build --target native --release`, and `moon test` (`36 passed, 0 failed`).
- Pre-existing `.planning/config.json`, `.planning/.omp-next-action.json`, `.planning/phases/01-core-kernel/01-PATTERNS.md`, and `_build/` were not staged.

## Threat Surface Scan

No new external trust boundary was introduced. The changed parser remains synchronous and offline; limits mitigate untrusted malformed/deep input, and diagnostics/CST spans remain rooted in caller-provided bytes.

---
*Phase: 01-core-kernel*
*Completed: 2026-08-03*
