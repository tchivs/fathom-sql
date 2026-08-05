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
    - parity/export_smoke_test.mbt
    - parity/moon.pkg
    - parity/parity_test.mbt
    - parity/run_native.mbt
    - parity/run_js.mbt
    - parity/run_wasm.mbt
    - binding/moon.pkg
    - binding/schema.mbt
    - binding/exports.mbt
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
| ECO-04 | `binding/exports.mbt`, `binding/moon.pkg`, and `binding/schema.mbt` expose parse/format/profile/capability functions using explicit primitive `Bytes`, `String`, `Int`, and `Bool` arguments/results. `doris.error.v1` handles malformed profiles/modes/options without internal values. | Implemented; Native/JS/Wasm target checks and JS/Wasm artifact smoke passed. |
| ECO-05 | `parity/fixtures/corpus.json`, `parity/fixtures/target-matrix.json`, `parity/parity_test.mbt`, and the three target runners cover serialized schema, profile metadata, source bytes, recursive roots, diagnostics, spans through the shared schema, formatting outputs, rejection cases, and target metadata. | Implemented; 12 Native parity tests and target builds passed. |

## Parent Target/Build Evidence

- `moon test --target native --package parity`: 12 tests passed, 0 failed. Binding schema/coordinate/export smoke tests run from the non-foreign parity package because selecting the foreign-library package as a Native test target triggers MoonBit error 4219.
- `moon check --target native`: completed with 0 errors.
- `moon check --target native binding`: completed with 0 errors.
- `moon check --target js binding`: completed with 0 errors.
- `moon build --target js binding`: completed with 0 errors; generated ESM d.ts exposes all four stable symbols.
- `moon build --target wasm binding`: completed with 0 errors; generated linear-Wasm module exposes all four stable symbols.
- `moon build --target js parity && moon build --target wasm parity`: both completed with 0 errors.
- JS runtime smoke decoded `doris.parse.v1`, rejected `mysql` as `DORIS-SCHEMA-003`, preserved source bytes, and verified `wasm_gc:false` capability metadata.
- Wasm module smoke found exactly `doris_parse_v1`, `doris_format_v1`, `doris_profile_v1`, and `doris_capabilities_v1` among its four exports.
- No Wasm GC build or compatibility claim is included.

## Task Commits

1. `af7f0ca` — `feat(04-03): add primitive JS and linear Wasm exports`
2. `538b966` — `test(04-03): add cross-target parity corpus and runners`
3. `d293a97` — `test(04-03): add target ABI regression gates`
4. `947b4ef`, `99c7691`, `9767d4b` — foreign-library test relocation and summary metadata
5. `81d2845` — relocate binding schema/coordinate tests into parity
6. `c054c15` — restore binding source dependency and FormatError constructor labels

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
- **Fix:** Replaced the tautology with decoded JSON assertions for schema/profile/source byte length/source bytes/recursive roots/diagnostics/format refusal, deterministic unsupported-input envelopes, and no internal MoonBit type names.
- **Files modified:** `parity/parity_test.mbt`, `parity/run_native.mbt`, `parity/run_js.mbt`, `parity/run_wasm.mbt`, `parity/fixtures/corpus.json`, `parity/fixtures/target-matrix.json`
- **Commit:** `538b966`, `d293a97`

**3. [Rule 3 - Toolchain Boundary] Relocated export smoke tests out of the foreign-library package**
- **Found during:** Parent-target validation
- **Issue:** `moon test --target native --package binding --package parity` turns `binding` into a test main and rejects `#export_name` in a `foreign_library`; it also requires assertion-bearing `run_fixture` to use the `raise` effect.
- **Fix:** Removed `binding/export_smoke_test.mbt`, added real `@binding.doris_*` serialized-byte assertions in `parity/export_smoke_test.mbt`, and changed `run_fixture` to `-> Unit raise`. Production `binding/moon.pkg` and export symbols remain unchanged.
- **Files modified:** `binding/export_smoke_test.mbt` (removed), `parity/export_smoke_test.mbt`, `parity/parity_test.mbt`
- **Commit:** `947b4ef`

No architectural changes, external dependencies, package installs, parser forks, network/FE/database paths, or Web/VS Code host work were introduced.

**4. [Rule 1 - Bug] Restored foreign-library dependencies and formatter error labels**
- **Found during:** Parent Native/JS/Wasm target validation
- **Issue:** The foreign-library manifest omitted the shared `source` dependency used by the coordinate adapter, and `FormatError` constructor fields were matched with incorrect labels, preventing target compilation.
- **Fix:** Added the `source` import and matched `keyword_case_id`, `comma_style_id`, and `newline_style_id` exactly; validated native and JS checks plus JS/Wasm builds.
- **Files modified:** `binding/moon.pkg`, `binding/schema.mbt`
- **Commit:** `c054c15`

## Risks

- Native/JS/Wasm target checks, builds, parity tests, and JS/Wasm artifact smoke passed. Linear Wasm `Bytes` ownership/host decoding remains a host-integration concern; the source-level boundary is explicit and does not expose a MoonBit object handle.
- JSON byte-array encoding is deliberately stable but larger than base64; changing it requires a new source transport/schema version.

## Known Stubs

None in the implemented plan surface. The three runner mains invoke the real binding functions; they intentionally avoid host output so linear Wasm remains portable.

## Self-Check: PASSED

- Required implementation and fixture files exist in the working tree.
- Export, parity, and target repair commits listed above are present.
- No placeholder/TODO/FIXME/empty-result stub was found in the plan's implementation surface.
- Native parity tests, Native checks, JS/Wasm checks/builds, and JS/Wasm artifact smoke passed.
