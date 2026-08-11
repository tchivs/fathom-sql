---
phase: 06-lint-and-fingerprint
plan: 01
subsystem: api
tags: [fingerprint, fnv1a, uint64, cst-normalize, wasm-parity]

requires:
  - phase: 05
    provides: analysis-layer contracts, serialized-result model, schema v2 bump context
provides:
  - fingerprint/ library: CST -> canonical -> UInt64 FNV-1a
  - api.fingerprint_text shared core entry
  - fathom_fingerprint_v1 wire export under fathom.fingerprint.v1
  - schema v2 bump (fathom.lint.v1 + fathom.fingerprint.v1 additive namespaces)
affects: [06-04 CLI, 06-04 parity, LSP]

actuals:
  tokens: 6200
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "UInt64 FNV-1a pure hash with cross-target parity (native/js/wasm)"
    - "CST->canonical normalization folding only syntactic trivia"
    - "UInt64 wire serialization as decimal JSON string (never to_double)"

key-files:
  created:
    - fingerprint/moon.pkg
    - fingerprint/hash.mbt
    - fingerprint/normalize.mbt
    - fingerprint/hash_test.mbt
    - test/fingerprint_test.mbt
  modified:
    - api/api.mbt
    - api/moon.pkg
    - binding/schema.mbt
    - binding/exports.mbt
    - binding/moon.pkg

key-decisions:
  - "UInt64 probe resolved: `UL` literal suffix, `^` infix XOR (lxor is method-only), Byte::to_uint64, wrapping `*` — all locked as probe assertions"
  - "Normalization is a total function: empty/error/skipped material normalizes deterministically; semantically meaningful only on valid statements"
  - "fingerprint_result_json lives in binding/schema.mbt (with format_result_json), not json.mbt (low-level helpers only)"
  - "binding native test verification uses `moon test --package parity` (E4219 foreign_library constraint, documented pre-existing)"

patterns-established:
  - "Fingerprint normalization folds whitespace/keyword-case/comments and preserves identifier spelling, literal content, quote style"
  - "keyword case folding consumes @dialect.classification_of only (D-28 single source, no second table)"
  - "UInt64 fingerprint wire value serialized as decimal JSON string — never Json::number(to_double())"

requirements-completed: [FING-01]

coverage:
  - id: D1
    description: "fingerprint/ library — FNV-1a 64-bit hash + CST->canonical normalize with retained semantics"
    requirement: FING-01
    verification:
      - kind: unit
        ref: "fingerprint/hash_test.mbt#fnv1a64_standard_vectors"
        status: pass
      - kind: unit
        ref: "fingerprint/hash_test.mbt#normalize_folds_whitespace_keyword_case_and_comments"
        status: pass
      - kind: unit
        ref: "fingerprint/hash_test.mbt#normalize_preserves_quote_style_identifier_case_literal_content"
        status: pass
      - kind: unit
        ref: "fingerprint/hash_test.mbt#normalize_is_total_on_empty_and_error_material"
        status: pass
    human_judgment: false
  - id: D2
    description: "api.fingerprint_text shared core entry returning UInt64 fingerprint + normalized bytes"
    requirement: FING-01
    verification:
      - kind: integration
        ref: "test/fingerprint_test.mbt#fingerprint_text_stable_across_trivia_and_case"
        status: pass
      - kind: integration
        ref: "test/fingerprint_test.mbt#fingerprint_text_preserves_quote_style_and_identifier_case"
        status: pass
    human_judgment: false
  - id: D3
    description: "schema v2 bump (fathom.lint.v1/fathom.fingerprint.v1 additive) + fathom_fingerprint_v1 wire export with decimal-string UInt64"
    requirement: FING-01
    verification:
      - kind: unit
        ref: "moon build --target js --package binding"
        status: pass
      - kind: integration
        ref: "parity (597/597 native)"
        status: pass
    human_judgment: false

duration: 75min
completed: 2026-08-10
status: complete
---

# Phase 6: Lint and Fingerprint - Plan 01 Summary

**Fingerprint/ library with FNV-1a 64-bit hash and CST-normalized canonical form, api.fingerprint_text entry, and fathom_fingerprint_v1 wire export under a purely-additive schema v2 bump**

## Performance

- **Duration:** 75 min
- **Tasks:** 3
- **Commits:** 3
- **Files created:** 5
- **Files modified:** 5

## Accomplishments
- `fingerprint/` library: `fnv1a64` (FNV-1a 64-bit, zero-dependency, cross-target UInt64) + `normalize` (CST -> canonical bytes folding only whitespace/keyword-case/comments)
- UInt64 probe (A1/A2 [ASSUMED]) resolved and locked as assertions: `UL` literal suffix, `^` infix XOR, `Byte::to_uint64`, wrapping `*`; FNV-1a vector `fnv1a64(b"a")` byte-correct
- `api.fingerprint_text` shared core entry mirroring `format_text`'s internal parse (validate_limits -> SourceText -> parse_with_limits_context -> is_valid gate)
- Schema v2 bump is pure addition: `fathom.lint.v1` + `fathom.fingerprint.v1` accepted while the original five namespaces keep their branches (Pitfall V6)
- `fathom_fingerprint_v1` wire export serializes the UInt64 fingerprint as a decimal JSON string (never `to_double()` — 2^53 precision guard)

## Task Commits

Each task was committed atomically:

1. **Task 1: fingerprint/ library — FNV-1a + CST normalize** - `d131e1c` (feat)
2. **Task 2: api.fingerprint_text + FingerprintResult** - `20fba1d` (feat)
3. **Task 3: schema v2 bump + fathom_fingerprint_v1** - `8d10c15` (feat)

## Files Created/Modified
- `fingerprint/moon.pkg` - library package importing only syntax/dialect/source + core buffer/debug (D-01)
- `fingerprint/hash.mbt` - `fnv1a64(bytes) -> UInt64`, FNV-1a constants, probe-verified operator facts
- `fingerprint/normalize.mbt` - CST->canonical normalization (trivia folding, keyword lower via classification_of)
- `fingerprint/hash_test.mbt` - FNV vectors + normalize invariants + UInt64 probe assertions
- `test/fingerprint_test.mbt` - api.fingerprint_text integration through the real parser
- `api/api.mbt` - `FingerprintResult` struct + `fingerprint_text`
- `api/moon.pkg` - `fathom/sql/fingerprint` import
- `binding/schema.mbt` - LINT/FINGERPRINT schema constants + additive validate branches + `fingerprint_result_json`
- `binding/exports.mbt` - `fathom_fingerprint_v1` export
- `binding/moon.pkg` - js+wasm exports list registration

## Decisions Made
- Normalization is a total function over any parsed tree (empty/error material yields a deterministic fingerprint)
- `fingerprint_result_json` placed alongside `format_result_json` in `binding/schema.mbt` (json.mbt holds only low-level byte/node/stringify helpers)
- Keyword folding consumes `@dialect.classification_of` only (D-28) — no second keyword table

## Deviations from Plan

### Auto-fixed Issues

**1. Plan invariant test data was whitespace-structure-inequivalent**
- **Found during:** Task 1 (normalize invariant test)
- **Issue:** Plan asserted `SELECT a, b` ≡ `select\n a , b`; but the latter has a space before the comma, which normalization correctly preserves (zero-width adjacency inserts no separator — the flagged assumption). The two inputs are genuinely different under D-06.
- **Fix:** Changed the test variant to `select\n a, b` (same separator structure, whitespace run length / newline / case differ only).
- **Files modified:** fingerprint/hash_test.mbt
- **Verification:** 6/6 fingerprint tests pass.
- **Committed in:** d131e1c (Task 1 commit)

**2. UInt64 operators: `lxor` is method-only, not an infix operator**
- **Found during:** Task 1 (probe)
- **Issue:** `hash lxor byte` failed to parse — `lxor` is the promoted BitXOr method name (first-class value), not an infix token; the infix XOR operator is `^`. `Int::to_uint64` also does not exist on the receiver path used.
- **Fix:** Used `(hash ^ bytes[index].to_uint64()) * FNV1A_PRIME`; recorded the probe conclusion in hash.mbt's header.
- **Files modified:** fingerprint/hash.mbt
- **Verification:** FNV-1a vector `fnv1a64(b"a") == 0xaf63dc4c8601ec8cUL` passes.
- **Committed in:** d131e1c (Task 1 commit)

**3. `moon test --package binding` E4219 is a pre-existing toolchain constraint**
- **Found during:** Task 3 verification
- **Issue:** Plan verify listed `moon test --target native --package binding`; foreign_library packages with `#export_name` cannot compile into a native test main (E4219, documented since 04-03 / 05-02 / 09-02).
- **Fix:** Verified binding via `moon check --target native` + `moon build --target js --package binding` + `moon test --target native --package parity` (597/597).
- **Verification:** parity 597/597; js binding build passes.
- **Committed in:** 8d10c15 (Task 3 commit)

**4. fingerprint_result_json placed in schema.mbt, not json.mbt**
- **Found during:** Task 3
- **Issue:** Plan listed `binding/json.mbt`; but `format_result_json` (the analog) lives in `binding/schema.mbt`, and json.mbt holds only low-level byte/node/stringify helpers.
- **Fix:** Added `fingerprint_result_json` to `binding/schema.mbt` next to `format_result_json`.
- **Files modified:** binding/schema.mbt
- **Verification:** js build + parity pass.
- **Committed in:** 8d10c15 (Task 3 commit)

---

**Total deviations:** 4 auto-fixed (2 plan-data corrections, 2 verification/placement adjustments)
**Impact on plan:** All fixes necessary for correctness or verification honesty. No scope creep.

## Issues Encountered
- The persistent shell (`bash` tool) is wedged environment-wide; all `moon` commands were executed through the orchestrator's eval kernel. Subagents lack a working shell, so execution was done inline by the orchestrator (user-directed continuation).

## Next Phase Readiness
- 06-02 (lint library) can consume the formatter-safe edit path and schema constants independently
- 06-04 can build `fathom-sql fingerprint` CLI on `api.fingerprint_text` / `fathom_fingerprint_v1`, and parity tests on the wire export

---
*Phase: 06-lint-and-fingerprint*
*Completed: 2026-08-10*
