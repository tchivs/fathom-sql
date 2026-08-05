---
phase: 04-ecosystem-and-multi-target-delivery
plan: 02
subsystem: completion-and-lsp-protocol
tags: [moonbit, completion, lsp, utf-16, json-rpc, versions]
requires:
  - phase: 04-00
    provides: production-focused completion/protocol harness boundary
  - phase: 04-01
    provides: Native LSP document snapshots, JSON-RPC protocol, UTF-16 byte-to-range adapter
provides:
  - bounded parser-owned syntax completion facade
  - current-snapshot LSP completion mapping with UTF-16 replacement ranges
  - stale-version and malformed-request protocol hardening
affects: [04-03, 04-04, ECO-01, ECO-03]
tech-stack:
  added: []
  patterns:
    - derive candidates from token classification rows and parser-known clause context
    - keep UTF-8 bytes authoritative and convert LSP positions through one shared binding adapter
    - reject stale full-document snapshots before parsing or publishing diagnostics
key-files:
  created:
    - completion/completion.mbt
    - completion/moon.pkg
    - lsp/completion_test.mbt
    - lsp/protocol_test.mbt
  modified:
    - lsp/handlers.mbt
    - lsp/protocol.mbt
    - lsp/documents.mbt
    - lsp/moon.pkg
    - binding/coordinates.mbt
    - binding/coordinates_test.mbt
key-decisions:
  - "Completion remains syntax-only: candidate labels come from token classification and clause context; catalog/analyzer metadata is never consulted."
  - "Completion requests may carry an optional document version; a mismatch with the current URI snapshot is rejected with -32602."
  - "UTF-16 Position-to-byte conversion is added beside byte-to-position in binding/coordinates.mbt as the single shared coordinate authority."
requirements-completed: [ECO-01, ECO-03]
metrics:
  duration: 2h
  completed: 2026-08-04
  status: complete
actuals:
  tokens: 6989
  tasks: 2
  commits: 2
---

# Phase 4 Plan 2: Syntax Completion and LSP Protocol Hardening Summary

A bounded, deterministic syntax completion facade now supplies profile-aware Doris keyword/clause candidates for incomplete editor snapshots, while Native LSP completion and synchronization reject stale or malformed protocol input and map edits through the shared UTF-16 coordinate policy.

## Accomplishments

- Added `completion.complete(raw, profile_id, cursor_byte)`, which parses editor-mode input, lexes the current snapshot, identifies statement/clause context, filters the existing token classification rows by released profile, applies a 32-item bound, and returns primitive labels plus byte replacement spans.
- Covered statement start, `SELECT`, `FROM`, `WHERE`, `GROUP BY`, `ORDER BY`, `JOIN ... ON`, partial prefixes, profile filtering, stable ordering, and multibyte replacement anchors in `lsp/completion_test.mbt`.
- Added `textDocument/completion` capability advertisement and dispatch. Requests require an open current snapshot, valid UTF-16 `Position`, and (when supplied) the matching document version. Returned `CompletionItem`s contain labels, keyword kind/detail, `textEdit`, and shared-converter UTF-16 ranges.
- Hardened full-document synchronization: negative versions, repeated/stale opens, non-advancing changes, incremental ranges, malformed params, and unknown methods now produce bounded protocol errors for requests and remain silent for notifications where required.
- Rejected JSON-RPC null request IDs while retaining the existing protocol-safe null ID for server-generated parse/frame errors.
- Added the inverse UTF-16 coordinate conversion to `binding/coordinates.mbt`; CRLF is treated as one line and supplementary-plane characters consume two UTF-16 units. This keeps completion request conversion beside the existing byte-to-position implementation rather than introducing a second policy.
- Replaced completion/protocol tautologies with production assertions for current-snapshot completion, stale version rejection, malformed params, unknown methods, lifecycle shutdown/exit, profile gates, bounded output, clause contexts, and coordinate round trips.

## Requirement Coverage

| Requirement | Evidence | Status |
|---|---|---|
| ECO-01 | `lsp/handlers.mbt`, `lsp/documents.mbt`, `lsp/protocol.mbt`, `lsp/protocol_test.mbt` enforce synchronized versions, malformed-request errors, lifecycle safety, and current-snapshot dispatch. | Implemented; 20 targeted package tests passed and framed smoke passed. |
| ECO-03 | `completion/completion.mbt` and `lsp/completion_test.mbt` provide parser/token-owned syntax completion with no catalog path, profile filtering, incomplete-input recovery, bounded candidates, and byte ranges mapped by LSP. | Implemented; completion contexts, ordering, profile gate, multibyte replacement, and LSP mapping passed. |

## Parent Verification

- `moon test --target native --package binding --package lsp`: 20 tests passed, 0 failed.
- `moon build --target native --release --package lsp`: completed with 0 errors.
- Native framed smoke against `_build/native/release/build/lsp/lsp.exe`: 10 valid top-level messages, including malformed-frame recovery, initialize, versioned didOpen/didChange diagnostics, current completion (`FROM`, then `JOIN`), stale-version rejection, malformed completion params, didClose, shutdown, and exit.
  - The plan's `--filter completion`/`--filter lsp` invocations reported no test entries in this MoonBit toolchain; package-level targeted execution is the passing evidence.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added shared UTF-16 Position-to-byte conversion**
- **Found during:** Task 2 completion request mapping
- **Issue:** The existing shared adapter converted authoritative byte offsets to UTF-16 ranges but had no inverse, so a standard LSP completion `Position` could not be mapped back to the current source snapshot without duplicating coordinate arithmetic in the handler.
- **Fix:** Added `position_to_byte` beside `byte_to_position` in `binding/coordinates.mbt`, including CRLF line handling, supplementary-plane UTF-16 units, and bounds rejection; added a round-trip regression assertion.
- **Files modified:** `binding/coordinates.mbt`, `binding/coordinates_test.mbt`
- **Commit:** `cee1423`

**2. [Rule 2 - Missing Critical] Enforced full-document synchronization shape**
- **Found during:** Task 2 protocol hardening
- **Issue:** `didChange` previously accepted an array with extra changes and silently ignored incremental range payloads despite advertising full synchronization.
- **Fix:** Require exactly one content change without a `range`, reject invalid/negative versions, and return request-safe `-32602` errors while preserving notification silence.
- **Files modified:** `lsp/handlers.mbt`
- **Commit:** `cee1423`

No architectural changes, external dependencies, parser forks, catalog access, network/FE/database paths, or host packaging were introduced.

## Risks

- Targeted package tests, Native release build, and framed smoke passed. Completion intentionally offers syntax keywords and clause words only; table/column or other catalog-backed semantic suggestions remain excluded by contract.
- The inverse coordinate converter rejects positions inside a supplementary-plane surrogate pair rather than manufacturing a byte boundary; standard LSP clients should send scalar-boundary UTF-16 positions.

## Known Stubs

None in the implemented plan surface.

## Task Commits

1. `f84e2c1` — `feat(04-02): add parser-owned syntax completion`
2. `cee1423` — `feat(04-02): harden LSP completion protocol`
3. `aafbf6e` — `fix: repair Wave 2 didOpen/didChange handler typing`
4. `9137af6` — `fix: order context-aware completion candidates`
5. `c21e577` — `fix: close wave 2 completion validation gaps`

## Self-Check: PASSED

- Summary file exists at the required phase path.
- `completion/completion.mbt`, `lsp/completion_test.mbt`, and `lsp/protocol_test.mbt` exist.
- Implementation and validation-repair commits listed above are present.
- Targeted package tests, release build, and framed smoke passed.
