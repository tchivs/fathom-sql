---
phase: 04-ecosystem-and-multi-target-delivery
plan: 03
subsystem: js-wasm-boundary-and-parity
tags: [moonbit, js-esm, linear-wasm, primitive-abi, parity, schema]
requires:
  - phase: 04-01
    provides: versioned doris.parse.v1/doris.format.v1 envelopes and shared Native schema producer
  - phase: 04-02
    provides: completed Wave 2 package and protocol contracts
provides:
  - stable primitive JS ESM and linear-Wasm export facade
  - shared profile/capability metadata and deterministic error envelopes
  - cross-target parity fixture corpus, runners, and target ABI regression gates
affects: [04-04, ECO-04, ECO-05]
tech-stack:
  added: []
  patterns:
    - "foreign_library exports return UTF-8 JSON Bytes and accept raw source Bytes plus primitive profile/mode/options"
    - "inline-root-v1 carries source bytes once; recursive nodes remain primitive kind/span/length/children records"
    - "parity assertions decode serialized bytes and reject internal MoonBit type names"
    - "linear Wasm is the compatibility promise; capabilities explicitly set wasm_gc=false"
key-files:
  created:
    - binding/exports.mbt
    - parity/fixtures/corpus.json
    - parity/fixtures/target-matrix.json
  modified:
    - binding/moon.pkg
    - binding/schema.mbt
    - binding/export_smoke_test.mbt
    - parity/moon.pkg
    - parity/parity_test.mbt
    - parity/run_native.mbt
    - parity/run_js.mbt
    - parity/run_wasm.mbt
decisions:
  - "Use four stable #export_name symbols: doris_parse_v1, doris_format_v1, doris_profile_v1, and doris_capabilities_v1."
  - "All operation results and errors cross JS/Wasm as UTF-8 serialized JSON Bytes; raw SQL input remains explicit Bytes and source_bytes is retained in the envelope."
  - "Formatting options are explicit primitive arguments rather than a MoonBit options object."
  - "Wasm GC is not advertised; target metadata names only native, js-esm, and wasm-linear."
metrics:
  duration: implementation session
  completed: 2026-08-04
  status: complete
actuals:
  tokens: 5033
  tasks: 3
  commits: 3
---

# Phase 4 Plan 3: JS ESM and Linear-Wasm Parity Summary

**Stable primitive `doris.parse.v1`/`doris.format.v1` exports for JS ESM and linear Wasm, backed by the same schema producer as Native LSP and a deterministic cross-target fixture/ABI gate suite.**

## Accomplishments

- Converted `binding/` into a dedicated `foreign_library` boundary with explicit ESM and linear-Wasm export configuration.
- Added `doris_parse_v1(raw, profile, mode)` and `doris_format_v1(raw, profile, mode, keyword_case, indent, line_width, comma_style, newline_style, trailing_newline)`, returning only serialized UTF-8 JSON bytes.
- Added `doris_profile_v1` and `doris_capabilities_v1` metadata exports. Capabilities include supported profiles/modes, `inline-root-v1`, target names, and an explicit `wasm_gc: false` compatibility declaration.
- Extended the authoritative `binding/schema.mbt` producer with deterministic `doris.error.v1` envelopes for schema/profile/mode/format/parse failures, profile metadata, and capability metadata. No parser or formatter fork was introduced.
- Added nine checked-in fixture cases covering profiles 2.1/3.x/4.x, valid/recovered/error SQL, comments and hints, CRLF, non-ASCII text, formatter refusal, raw bytes including NUL/non-UTF-8 values, and empty input.
- Added target-specific Native, JS, and linear-Wasm runners that call the same primitive facade without `println`, `env`, libc, network, database, or FE dependencies.
- Replaced the previous parity tautology with decoded JSON assertions for schema/profile/source byte length/source bytes/root/diagnostics/format refusal, deterministic unsupported-input envelopes, and no internal MoonBit type names. Added a target matrix manifest with repeatable target commands and the linear-Wasm-only policy.

## Requirement Coverage

| Requirement | Evidence | Status |
|---|---|---|
| ECO-04 | `binding/exports.mbt`, `binding/moon.pkg`, and `binding/schema.mbt` expose parse/format/profile/capability functions using explicit primitive `Bytes`, `String`, `Int`, and `Bool` arguments/results. `doris.error.v1` handles malformed profiles/modes/options without internal values. | Implemented; parent target build/smoke gate pending. |
| ECO-05 | `parity/fixtures/corpus.json`, `parity/fixtures/target-matrix.json`, `parity/parity_test.mbt`, and the three target runners cover serialized schema, profile metadata, source bytes, recursive roots, diagnostics, spans through the shared schema, formatting outputs, rejection cases, and target metadata. | Implemented; parent parity/build gate pending. |

## Target/Build Evidence Expected by Parent

The plan's automated verification commands were intentionally not run in this executor, per the parent instruction. The parent should run:

- `moon test --target native --filter export_smoke`
- `moon test --target native --filter parity`
- `moon check --target native && moon build --target js && moon build --target wasm`

The checked-in runners and `target-matrix.json` provide the target-specific entrypoints and expected compatibility metadata for those commands. No Wasm GC build or compatibility claim is included.

## Task Commits

1. `af7f0ca` — `feat(04-03): add primitive JS and linear Wasm exports`
2. `538b966` — `test(04-03): add cross-target parity corpus and runners`
3. `d293a97` — `test(04-03): add target ABI regression gates`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added deterministic errors for all primitive boundary failures**
- **Found during:** Task 1 export design
- **Issue:** The existing schema only serialized `SchemaError`; exported parse/format functions also need stable envelopes for unknown modes/profiles, invalid format options, input limits, and invalid parser trees.
- **Fix:** Added `error_json`, `parse_error_json`, and `format_error_json` to the shared schema producer. Exports return these UTF-8 JSON bytes rather than throwing or leaking MoonBit errors.
- **Files modified:** `binding/schema.mbt`, `binding/exports.mbt`
- **Commit:** `af7f0ca`

**2. [Rule 2 - Missing Critical] Added explicit raw-byte and ABI regression cases**
- **Found during:** Tasks 2-3 parity design
- **Issue:** The pre-existing parity files only compared literal arrays and did not exercise the exported facade or raw-byte/error contracts.
- **Fix:** Replaced the tautology with real calls through `binding` and added fixture/target-matrix cases for non-ASCII, CRLF, NUL/non-UTF-8 bytes, empty input, refusal, rejection, and internal-type absence.
- **Files modified:** `parity/parity_test.mbt`, `parity/run_native.mbt`, `parity/run_js.mbt`, `parity/run_wasm.mbt`, `parity/moon.pkg`, `binding/export_smoke_test.mbt`, `parity/fixtures/corpus.json`, `parity/fixtures/target-matrix.json`
- **Commit:** `538b966`, `d293a97`

No architectural changes, external dependencies, package installs, parser forks, network/FE/database paths, or Web/VS Code host work were introduced.

## Risks

- Cross-target compiler/build and runtime parity verification remains intentionally delegated to the parent executor; this summary does not claim those commands passed.
- Linear Wasm `Bytes` ownership/host decoding must be confirmed by the parent target artifact smoke. The source-level boundary is explicit and does not expose a MoonBit object handle.
- JSON byte-array encoding is deliberately stable but larger than base64; changing it requires a new source transport/schema version.

## Known Stubs

None in the implemented plan surface. The three runner mains invoke the real binding functions; they intentionally avoid host output so linear Wasm remains portable.

## Self-Check: PASSED

- Required implementation and fixture files exist in the working tree.
- Commits `af7f0ca`, `538b966`, and `d293a97` exist in git history.
- No placeholder/TODO/FIXME/empty-result stub was found in the plan's implementation surface.
- Unrun verification commands are explicitly recorded above for the parent executor; no unsupported pass claim is made.
