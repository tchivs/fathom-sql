---
phase: 04-ecosystem-and-multi-target-delivery
plan: 01
subsystem: native-lsp-boundary
tags: [moonbit, lsp, json-rpc, schema, utf-16, formatter]
requires:
  - phase: 04-00
    provides: focused schema, coordinate, framing, lifecycle, diagnostics, and formatting harnesses
  - phase: 03-01
    provides: api.parse_with_ids, api.format_with_ids, primitive results, formatter refusal and statement-offset contracts
  - phase: 03-04
    provides: Native executable and libc FFI boundary conventions
provides:
  - versioned doris.parse.v1 and doris.format.v1 primitive JSON envelopes
  - bounded Native Content-Length JSON-RPC LSP executable with full-document synchronization
  - centralized UTF-8 byte to UTF-16 LSP range conversion and diagnostics/full-document formatting edits
affects: [04-02, 04-03, 04-04, js-wasm, vscode]
actuals:
  tokens: 9901
  tasks: 3
  commits: 4
tech-stack:
  added: []
  patterns:
    - primitive JSON envelopes carry source bytes once as inline-root-v1 arrays and preserve half-open byte spans
    - Native framing owns bounded stdio and emits protocol-safe errors while core packages remain backend-neutral
    - LSP diagnostics and formatting use one SourceText-based UTF-16 converter; statement_offsets are never source ranges
key-files:
  created:
    - binding/json.mbt
    - binding/schema.mbt
    - binding/coordinates.mbt
    - lsp/framing.mbt
    - lsp/protocol.mbt
    - lsp/documents.mbt
    - lsp/coordinates.mbt
    - lsp/handlers.mbt
    - lsp/main.mbt
    - parity/fixtures/lsp-tracer.json
  modified:
    - binding/moon.pkg
    - binding/schema_test.mbt
    - binding/coordinates_test.mbt
    - lsp/moon.pkg
    - lsp/framing_test.mbt
    - lsp/lifecycle_test.mbt
    - lsp/diagnostics_formatting_test.mbt
key-decisions:
  - "Use inline-root-v1 with JSON byte arrays for exact source transport; changing encoding requires a new schema/transport version."
  - "Require initializationOptions.profile and accept only 2.1, 3.x, or 4.x; no silent dialect fallback."
  - "Return one full-document TextEdit from byte 0 through source EOF; formatter statement_offsets remain output-only metadata."
patterns-established:
  - "Schema serialization is composed from api.ParseResult, PrimitiveNode, PrimitiveDiagnostic, and FormatResult without exposing MoonBit ADTs."
  - "DocumentStore accepts didChange only when the supplied full-content version strictly advances the stored snapshot."
requirements-completed: [ECO-01, ECO-02, ECO-05]
coverage:
  - id: D1
    description: "Versioned parse/format envelopes with source transport, profile/mode validation, recursive CST leaves, diagnostics, and formatting offsets"
    requirement: ECO-05
    verification:
      - kind: unit
        ref: "binding/schema_test.mbt#schema_serializes_real_parse_result_and_refuses_unknown_versions"
        status: unknown
    human_judgment: true
    rationale: "Validation commands were intentionally skipped; parent executor must run the targeted schema suite."
  - id: D2
    description: "Native bounded Content-Length JSON-RPC framing, lifecycle, full-content document state, and malformed-frame responses"
    requirement: ECO-01
    verification:
      - kind: unit
        ref: "lsp/framing_test.mbt#malformed_frame_is_rejected_not_crashed"
        status: unknown
      - kind: integration
        ref: "moon build --target native --release and framed initialize/open/change/close/shutdown/exit tracer session"
        status: unknown
    human_judgment: true
    rationale: "Validation commands were intentionally skipped; parent executor must build and smoke-test the executable."
  - id: D3
    description: "Parser diagnostics and accepted/refused formatting mapped to UTF-16 diagnostics and one safe full-document edit"
    requirement: ECO-02
    verification:
      - kind: unit
        ref: "lsp/diagnostics_formatting_test.mbt#lsp_publishes_diagnostics_and_one_full_document_edit"
        status: unknown
      - kind: unit
        ref: "binding/coordinates_test.mbt#utf16_conversion_treats_crlf_as_one_line"
        status: unknown
    human_judgment: true
    rationale: "Validation commands were intentionally skipped; parent executor must run targeted diagnostics/coordinate suites."
---

# Phase 4 Plan 1: Native Schema and LSP Tracer Summary

**Versioned primitive parse/format envelopes and a real bounded Native `doris-lsp` stdio tracer with strict document versions, UTF-16 ranges, diagnostics, and safe full-document formatting edits.**

## Performance

- **Duration:** implementation session; validation was intentionally deferred to the parent executor
- **Started:** 2026-08-04
- **Completed:** 2026-08-04
- **Tasks:** 3
- **Files modified/created:** 17 plan artifacts plus the existing Wave 0 harness updates

## Accomplishments

- Added `doris.parse.v1` and `doris.format.v1` JSON serializers over the existing API primitive result shapes, including explicit source transport, exact source byte arrays, profile metadata, recursive node leaves, diagnostics, accepted output, and output-only statement offsets.
- Added schema/profile/mode/transport validation with explicit structured unsupported-version errors rather than silent fallback.
- Added a Native executable LSP edge with bounded `Content-Length`/CRLF framing, exact body reads, malformed-frame JSON-RPC errors, JSON-RPC 2.0 lifecycle handling, explicit profile selection, and no FE/database/network dependency.
- Added newest-version-only full-content URI snapshots and production handlers for `didOpen`, `didChange`, `didClose`, `publishDiagnostics`, `textDocument/formatting`, `shutdown`, and `exit`.
- Added one shared SourceText-based byte-to-UTF-16 converter covering CRLF and supplementary-plane characters. Accepted formatting returns one full-document edit; refusal returns no edit and publishes formatter diagnostics.
- Replaced Wave 0 schema, coordinate, framing, lifecycle, and diagnostics/formatting tautologies with production API and handler assertions, and added `parity/fixtures/lsp-tracer.json`.

## Task Commits

1. **Task 1: Freeze serialized envelope and coordinate policy** - `63f9455` (feat)
2. **Task 2: Implement Native JSON-RPC LSP lifecycle and document synchronization** - `76eedfc` (feat)
3. **Task 3: Wire diagnostics and full-document formatting TextEdit** - `55fecea` (feat)
4. **Task 2 hardening: protocol-safe malformed frame handling** - `3c406ab` (fix)

**Plan metadata:** `95092fa` (docs: summarize Native schema and LSP tracer)

## Files Created/Modified

- `binding/schema.mbt`, `binding/json.mbt` - versioned primitive envelope and JSON construction.
- `binding/coordinates.mbt` - authoritative byte-to-line/UTF-16 conversion.
- `lsp/framing.mbt` - bounded Native Content-Length framing and stdio IO.
- `lsp/protocol.mbt` - JSON-RPC parsing, IDs, responses, notifications, and protocol errors.
- `lsp/documents.mbt` - URI/version/raw-byte full-document snapshots.
- `lsp/handlers.mbt` - lifecycle, synchronization, diagnostics, and formatting dispatch.
- `lsp/coordinates.mbt` - protocol-edge range helpers using the shared converter.
- `lsp/main.mbt`, `lsp/moon.pkg` - buildable executable boundary.
- `parity/fixtures/lsp-tracer.json` - representative versioned tracer fixture.
- Wave 0 test files - now call production serializers, converter, framing decoder, lifecycle handler, and formatting handler.

## Decisions Made

- JSON source transport is an explicit integer byte array under `inline-root-v1`; no MoonBit ADT or backend object crosses the boundary.
- Initialization requires an explicit supported Doris profile in `initializationOptions.profile`.
- Full-content synchronization is the first safe document model, and stale/non-advancing changes are ignored.
- UTF-8 byte offsets remain authoritative; UTF-16 line/character positions are derived only at the LSP edge.
- Formatter output is returned as one full-document edit, never by incorrectly reusing formatter output offsets as source ranges.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Malformed frames initially terminated the read loop**
- **Found during:** Task 2 hardening
- **Issue:** A malformed `Content-Length` frame could be indistinguishable from EOF and would terminate the server without a protocol-safe error response.
- **Fix:** Changed `read_frame` to distinguish `Ok(None)` EOF from `Err(FrameError)` and emit a bounded JSON-RPC parse error before continuing.
- **Files modified:** `lsp/framing.mbt`, `lsp/main.mbt`
- **Verification:** Static implementation review; targeted validation intentionally deferred per execution instruction.
- **Committed in:** `3c406ab` (follow-up fix to the Task 2 boundary)

**2. [Rule 3 - Blocking] Production harnesses needed package imports and real calls**
- **Found during:** Tasks 1-3
- **Issue:** Wave 0 tests asserted literal strings/arrays without exercising serializers, framing, lifecycle state, coordinates, or formatting handlers.
- **Fix:** Updated manifests and harnesses to call the production packages and added the checked-in tracer fixture.
- **Files modified:** `binding/moon.pkg`, `binding/schema_test.mbt`, `binding/coordinates_test.mbt`, `lsp/moon.pkg`, `lsp/framing_test.mbt`, `lsp/lifecycle_test.mbt`, `lsp/diagnostics_formatting_test.mbt`, `parity/fixtures/lsp-tracer.json`
- **Verification:** Static implementation review; targeted validation intentionally deferred per execution instruction.
- **Committed in:** `63f9455`, `76eedfc`, `55fecea`

**Total deviations:** 2 auto-fixed (Rule 2, Rule 3)
**Impact on plan:** Both changes are directly required for protocol safety and for the Wave 0 harnesses to test production behavior. No parser fork, host dependency, network service, or scope expansion was introduced.

### Toolchain correction after parent validation

**3. [Rule 1 - Bug] Corrected MoonBit core JSON namespace usage**
- **Found during:** Wave 1 parent targeted compile validation
- **Issue:** Production binding serializers referenced `@json.Json` and `@json.Json::...`, but the MoonBit core JSON value type and constructors are exposed as built-in `Json` and `Json::...` names.
- **Fix:** Replaced the type and constructor namespace in `binding/json.mbt` and the related `binding/schema.mbt` references; the `@json` package alias and serialization semantics remain unchanged.
- **Files modified:** `binding/json.mbt`, `binding/schema.mbt`
- **Verification:** Validation commands intentionally skipped per parent instruction; confirmed no `@json.Json` references remain under `binding/`.
- **Commit:** `0814d53` (atomic follow-up correction)

### Constructor collision correction

**4. [Rule 1 - Bug] Renamed RpcId constructors to avoid JSON pattern collisions**
- **Found during:** Wave 1 parent targeted compile validation
- **Issue:** Unqualified JSON patterns `Number`, `String`, and `Null` resolved to same-package `RpcId` constructors, causing native compilation failures.
- **Fix:** Renamed the public constructors to `IntId`, `TextId`, and `NullId`; updated all LSP construction and pattern sites while preserving JSON-RPC wire serialization.
- **Files modified:** `lsp/protocol.mbt`, `lsp/main.mbt`
- **Verification:** Validation commands intentionally skipped per parent instruction.
- **Commit:** Atomic follow-up correction commit (hash reported to parent executor).
## Issues Encountered

- The repository contains unrelated planning changes and untracked planning artifacts from parallel workflow activity; they were not staged or modified by these implementation commits.
- The plan's targeted verification commands and Native framed smoke session were intentionally not run because the parent explicitly required validation to be skipped. Exact commands for the parent are listed below.

## Verification Commands for Parent Executor

Run the plan's targeted checks from the repository root:

- `moon test --target native --filter schema`
- `moon test --target native --filter coordinates`
- `moon test --target native --filter lifecycle`
- `moon test --target native --filter framing`
- `moon test --target native --filter diagnostics_formatting`
- Build the `lsp/` executable for Native and feed a framed initialize → initialized → didOpen → didChange → didClose → shutdown → exit session, including a malformed frame, then assert framed responses and newest-version diagnostics.

These commands/results are **expected but unrun by this executor**; no pass/fail claim is made here.

## Security and Risk Notes

- The Native boundary caps headers at 16 KiB and frame bodies at 8 MiB, reads exact body bytes, validates JSON UTF-8, and emits framed protocol errors.
- Parser input remains bounded by the existing API/parser limits. The document store retains only the newest full-content snapshot per URI.
- Process IO is confined to the LSP executable. No FE, database, HTTP, network, catalog, or second parser path was added.
- The parent should pay particular attention to MoonBit toolchain syntax/API compatibility when running the targeted suites because validation was intentionally skipped.

## Known Stubs

None in the implemented plan surface. Completion, JS/Wasm exports, and browser/VS Code packaging remain intentionally owned by later plans and were not added here.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

The shared serialized schema and coordinate policy are ready for later JS/Wasm wrappers and parity work. The Native LSP tracer now provides the production boundary for subsequent completion hardening and host packaging. Parent validation is required before expanding the wave.

## Self-Check: PASSED

- Task commits `63f9455`, `76eedfc`, and `55fecea` exist and contain only task-related implementation/harness files.
- The required summary output and all plan artifacts are present.
- Validation commands were intentionally skipped as required by the parent assignment; coverage entries remain `unknown` rather than claiming unobserved passes.

---
*Phase: 04-ecosystem-and-multi-target-delivery*
*Completed: 2026-08-04*


### Wave 1 compile-fix repair

**3. [Rule 1 - Bug] Repaired LSP same-package and built-in JSON namespaces**
- **Found during:** Wave 1 parent targeted package compilation
- **Issue:** LSP production and test files used sibling package aliases for files in the same package, and referenced core JSON as `@json.Json`; response builders also relied on untyped map literals for `.stringify()`.
- **Fix:** Switched sibling references to same-package names, changed JSON values/constructors to `Json`/`Json::`, retained `@json.parse` for package parsing, and explicitly typed JSON-RPC response objects as `Json`.
- **Files modified:** `lsp/*.mbt`
- **Verification:** Validation commands intentionally skipped per parent instruction; static search confirms no forbidden namespaces remain under `lsp/`.
- **Commit:** Included in the atomic compile-fix commit for this repair.

### Wave 1 remaining LSP compiler corrections

**4. [Rule 1 - Bug] Applied toolchain-compatible LSP JSON and mutability fixes**
- **Found during:** Wave 1 parent targeted package compilation
- **Issue:** Core `Json::Number` exposes one positional payload, `Json::Null` cannot cross the package boundary as a constructed value, and two local bindings were unnecessarily mutable.
- **Fix:** Matched `Json::Number(number, ..)`, returned built-in `null`, and removed mutability from `responses` and `state` without changing protocol behavior.
- **Files modified:** `lsp/protocol.mbt`, `lsp/handlers.mbt`, `lsp/main.mbt`
- **Verification:** Validation commands intentionally skipped per parent instruction.
- **Commit:** `24f6fe5` (atomic compile-fix correction)

### Wave 1 JSON pattern-constructor correction

**4. [Rule 1 - Bug] Use unqualified built-in JSON pattern constructors in LSP matches**
- **Found during:** Wave 1 parent targeted package compilation
- **Issue:** MoonBit's core `Json` patterns are matched as unqualified `Number`, `String`, `Null`, `Object`, and `Array`; qualified `Json::...` forms are expression constructors and cause pattern-constructor type mismatches.
- **Fix:** Updated `lsp/protocol.mbt` to use unqualified JSON pattern constructors in every match and type test, while preserving `Json::number/string/array/object` expression constructors and built-in `null` values.
- **Files modified:** `lsp/protocol.mbt`
- **Verification:** Validation commands intentionally skipped per parent instruction; sibling-package search found no additional qualified JSON pattern forms under `lsp/`.
- **Commit:** This atomic follow-up correction commit (hash reported to parent executor).