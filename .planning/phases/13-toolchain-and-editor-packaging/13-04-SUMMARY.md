---
phase: 13-toolchain-and-editor-packaging
plan: 04
subsystem: binding
tags: [flink, completion, d-04, toot-05, wire, fathom-complete-v1, js, wasm, parity]

# Dependency graph
requires:
  - phase: 13-toolchain-and-editor-packaging
    provides: 13-02 Flink completion core — @completion.complete(raw, dialect, profile, cursor_byte) returns real Flink results (Flink DialectContext construction, profile gating by introduced_profile, bounded MAX_CANDIDATES=32, source-range edits) that this plan wraps over the wire
  - phase: 09-dialect-boundary-and-neutral-naming
    provides: NAME-02 four fathom.*.v1 namespaces + FATHOM-* codes + A4 export order (dialect right after raw) + D-10 neutral diagnostic/naming discipline; the D-04 decision chain
  - phase: 12-cross-dialect-corpus-and-parity-gates
    provides: three-target byte-parity discipline (PARITY-02, compare_backends.py) and the frozen snapshot tree (no --update)
provides:
  - #export_name("fathom_complete_v1") primitive export (raw, dialect, profile, cursor_byte : Int) -> Bytes over JS ESM + linear-Wasm, mirroring fathom_format_v1 (A4 order)
  - fathom.complete.v1 result envelope (schema_version + source_transport + dialect/profile metadata + is_incomplete + items label/detail/start_byte/end_byte/new_text) registered in validate_schema_version as the fifth namespace
  - fathom.error.v1 error envelope for completion: FATHOM-SCHEMA-007 (unknown dialect), FATHOM-SCHEMA-003 (unknown/unsupported profile), FATHOM-COMPLETE-001 (InvalidCursor), FATHOM-COMPLETE-002 (InvalidSource), FATHOM-COMPLETE-003 (InputTooLarge)
  - five-file registration shipped in ONE commit (exports.mbt, schema.mbt, moon.pkg js+wasm, docs/API.md, check_naming.py neutrality) — both JS and linear-Wasm built artifacts export the symbol
  - wire error matrix in parity/export_smoke_test.mbt: dialect-first routing, cursor bounds, oversize input, malformed UTF-8 (never a panic), and a source-range FROM edit over the wire
  - run_js.mbt + run_wasm.mbt exercise fathom_complete_v1 — the cursor_byte : Int ABI is confirmed on linear-Wasm (A6 probe)
  - docs/API.md + docs/zh-CN/API.md: full five-export wire surface table + fathom.complete.v1 envelope + error codes
affects: [TOOL-05 verifier, 13-06 host dialect/profile selection wiring, web/src/monaco-adapter.ts + vscode + jetbrains completion hosts, TOOL-FUTURE-01 catalog-aware completion]

# Actuals (#2632) — pairs with the plan's `estimate` (38000 chars/4) to calibrate future estimates.
actuals:
  tokens: 5187    # chars/4 over the realized diff (20,748 diff chars across the 8 changed files)
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - New primitive wire export = five-file change set in one commit (exports.mbt #export_name + schema.mbt envelope/validation + moon.pkg js+wasm exports + docs + naming-gate neutrality), verified by grepping the built binding.js and the linear-Wasm export section (Pitfall 3/8)
    - Completion envelope mirrors format_result_json (schema.mbt:113-133): dialect/profile selection metadata rides at the envelope root, item text stays neutral (D-10/D-28), cursor bounds single-sourced in the core

key-files:
  created: []
  modified:
    - binding/exports.mbt
    - binding/schema.mbt
    - binding/moon.pkg
    - parity/export_smoke_test.mbt
    - parity/run_js.mbt
    - parity/run_wasm.mbt
    - docs/API.md
    - docs/zh-CN/API.md

key-decisions:
  - "D-04 one-way door (Task 1, auto-selected option-a under auto_advance): confirm fathom_complete_v1(raw, dialect, profile, cursor_byte) -> Bytes (A4 export order) with the fathom.complete.v1 result envelope and fathom.error.v1 error envelope (FATHOM-SCHEMA-003/007 + FATHOM-COMPLETE-*) — the five-file change set shipped in one commit (Task 2 tracer)."
  - "Completion error codes: dialect/profile reuse the parse/format FATHOM-SCHEMA codes (UnknownDialect -> FATHOM-SCHEMA-007, UnknownProfile -> FATHOM-SCHEMA-003) so hosts see a uniform schema-code surface; completion-local errors (InvalidCursor/InvalidSource/InputTooLarge) use the new FATHOM-COMPLETE-001/002/003 family — always the fathom.error.v1 envelope, never a panic."
  - "docs/zh-CN/API.md updated in the same docs commit as docs/API.md to keep the translation in sync (repo convention from 13-03), staying inside the plan's five-file change-set intent."
  - "Malformed UTF-8 (T-13-04-08) is handled by the byte-oriented core (raw Bytes end-to-end, decode_lossy labels): the wire returns a structured fathom.complete.v1/fathom.error.v1 envelope — the export smoke asserts the structured envelope, never a panic."

patterns-established:
  - "Pattern: primitive wire export + envelope = mirror fathom_format_v1's shape (exports.mbt:38-72) with #export_name + pub fn returning json_bytes(completion_result_json(...)) on Ok / json_bytes(completion_error_json(...)) on Err; cursor bounds stay single-sourced in the core (InvalidCursor), never duplicated in the binding export."
  - "Pattern: completion item text neutrality — the detail constant 'SQL syntax keyword' and envelope-only dialect/profile metadata keep the D-10/D-28 discipline; the export smoke asserts no 'label':\"doris\"/\"label\":\"flink\" in items."

requirements-completed: [TOOL-05]

# Coverage metadata (#1602) — one entry per shipped deliverable.
coverage:
  - id: D1
    description: "fathom_complete_v1 primitive export (A4: raw, dialect, profile, cursor_byte) with the fathom.complete.v1 result envelope — registered in all five places in one commit (exports.mbt #export_name, schema.mbt validate_schema_version, moon.pkg js+wasm exports, docs/API.md + zh-CN, check_naming.py neutrality) so both the built binding.js and the linear-Wasm binding.wasm export the symbol"
    requirement: TOOL-05
    verification:
      - kind: other
        ref: "moon build --target js binding && moon build --target wasm binding (0 errors); grep 'fathom_complete_v1' _build/js/debug/build/binding/binding.js; linear-Wasm export-section parse shows fathom_complete_v1"
        status: pass
      - kind: other
        ref: "test \"$(grep -c 'fathom_complete_v1' binding/moon.pkg)\" -ge 2"
        status: pass
      - kind: unit
        ref: "parity/export_smoke_test.mbt#completion_export_is_dialect_aware_with_neutral_wire_identity"
        status: pass
    human_judgment: false
  - id: D2
    description: "Dialect-first error routing + neutral item text — unknown flink profile returns fathom.error.v1 + FATHOM-SCHEMA-003, unknown dialect returns fathom.error.v1 + FATHOM-SCHEMA-007, valid flink-2.3.0 returns fathom.complete.v1 with items; item detail is the neutral constant and no item label leaks a dialect name (D-10/D-28)"
    requirement: TOOL-05
    verification:
      - kind: unit
        ref: "parity/export_smoke_test.mbt#completion_export_is_dialect_aware_with_neutral_wire_identity"
        status: pass
      - kind: unit
        ref: "parity/export_smoke_test.mbt#completion_wire_error_matrix_and_source_range_edit"
        status: pass
    human_judgment: false
  - id: D3
    description: "Completion wire error matrix + source-range edit — cursor out-of-range returns fathom.error.v1 + FATHOM-COMPLETE-001 (bounds single-sourced in the core), over-limit input returns FATHOM-COMPLETE-003, malformed UTF-8 input returns a structured fathom.complete.v1/fathom.error.v1 envelope (never a panic, T-13-04-08), and fathom_complete_v1(b\"SELECT FRO\", \"flink\", \"flink-2.3.0\", 9) returns a FROM item with start_byte=7/end_byte=9 covering the FRO prefix"
    requirement: TOOL-05
    verification:
      - kind: unit
        ref: "parity/export_smoke_test.mbt#completion_wire_error_matrix_and_source_range_edit"
        status: pass
      - kind: unit
        ref: "completion/completion_test.mbt#flink_unknown_profile_rejects_no_fallback"
        status: pass
    human_judgment: false
  - id: D4
    description: "Three-target byte-identity over the completion wire — parity/run_js.mbt + parity/run_wasm.mbt exercise fathom_complete_v1 (cursor_byte : Int ABI confirmed on linear-Wasm, A6), moon test --target native/js/wasm --package parity all pass, and compare_backends.py proves an identical snapshot-tree sha256 digest across native/js/wasm (PARITY-02)"
    requirement: TOOL-05
    verification:
      - kind: other
        ref: "moon test --target native --package parity --package completion (608 passed) && moon test --target js --package parity (597 passed) && moon test --target wasm --package parity (597 passed)"
        status: pass
      - kind: other
        ref: "python3 scripts/compare_backends.py — 3 targets PASS, digest 2eda35825e17746e13ddaddc9604fe62824c5bba8dc1343f33e063f60b6ed065 identical across targets"
        status: pass
      - kind: other
        ref: "python3 scripts/check_naming.py — 601 product files, zero forbidden naming remnants"
        status: pass
    human_judgment: false

# Metrics
duration: 25min
completed: 2026-08-10
status: complete
---

# Phase 13 Plan 04: fathom_complete_v1 wire contract + fathom.complete.v1 envelope (TOOL-05/D-04)

**Exposes the 13-02 Flink completion core as a new stable wire contract — `#export_name("fathom_complete_v1")` with the A4 signature (raw, dialect, profile, cursor_byte) over JS ESM and linear-Wasm, a `fathom.complete.v1` result envelope carrying neutral completion items (label/detail/start_byte/end_byte/new_text), dialect-first error routing via `fathom.error.v1` (FATHOM-SCHEMA-003/007 + FATHOM-COMPLETE-*), and a five-file registration shipped in one commit so both built artifacts export the symbol.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-08-10
- **Completed:** 2026-08-10
- **Tasks:** 3
- **Files modified:** 8

## Accomplishments
- **D-04 one-way door (Task 1, auto-selected option-a):** confirmed `fathom_complete_v1(raw : Bytes, dialect : String, profile : String, cursor_byte : Int) -> Bytes` (A4 export order — raw first, dialect second, mirroring fathom_parse_v1/fathom_format_v1) with the `fathom.complete.v1` result envelope and `fathom.error.v1` error envelope; the five-file change set shipped in one commit (Task 2 tracer).
- **fathom_complete_v1 export (Task 2 tracer):** `binding/exports.mbt` adds `#export_name("fathom_complete_v1")` matching `@completion.complete` — `Ok(result) => json_bytes(completion_result_json(result, dialect, profile))`, `Err(error) => json_bytes(completion_error_json(error))` — mirroring the fathom_format_v1 blueprint (exports.mbt:38-72). Cursor bounds are single-sourced in the core (InvalidCursor, completion.mbt), never duplicated in the export.
- **fathom.complete.v1 envelope + error envelope (Task 2):** `binding/schema.mbt` adds `COMPLETE_SCHEMA_VERSION = "fathom.complete.v1"`, `completion_result_json` (items label/detail/start_byte/end_byte/new_text + dialect/profile metadata + is_incomplete), `completion_error_json` (fathom.error.v1 + FATHOM-SCHEMA-003/007 + FATHOM-COMPLETE-001/002/003), and registers the fifth namespace in `validate_schema_version` alongside parse/format/error/capabilities.
- **Five-file registration (Task 2):** `binding/moon.pkg` appends `fathom_complete_v1` to BOTH the js AND wasm exports lists (Pitfall 3/8) and adds the `@completion` import; the built `binding.js` and the linear-Wasm `binding.wasm` export section both contain the symbol (verified by grep and a wasm export-section parse). `docs/API.md` + `docs/zh-CN/API.md` enumerate the full five-export wire surface + envelope + error codes; `scripts/check_naming.py` stays green (`fathom_complete_v1` is neutral).
- **Wire error matrix + cross-target (Task 3):** `parity/export_smoke_test.mbt` adds the full error matrix — cursor out-of-range → fathom.error.v1 + FATHOM-COMPLETE-001, over-limit input → FATHOM-COMPLETE-003, malformed UTF-8 input → structured fathom.complete.v1/fathom.error.v1 envelope (never a panic, T-13-04-08), and `fathom_complete_v1(b"SELECT FRO", "flink", "flink-2.3.0", 9)` → fathom.complete.v1 with a FROM item whose start_byte=7/end_byte=9 cover the "FRO" prefix. `parity/run_js.mbt` + `parity/run_wasm.mbt` exercise the export, confirming the cursor_byte : Int ABI on linear-Wasm (A6 probe).
- **Three-target byte-identity (Task 3):** `moon test --target native/js/wasm --package parity` all pass and `python3 scripts/compare_backends.py` reports an identical snapshot-tree sha256 digest (2eda3582…) across native/js/wasm — PARITY-02 holds, no `--update` anywhere (frozen 455-snapshot tree untouched).

## Task Commits

Each task was committed atomically:

1. **Task 1: Confirm the fathom_complete_v1 wire contract form — D-04 one-way door** - `(auto-resolved option-a, no commit)` — decision checkpoint auto-selected "fathom_complete_v1(raw, dialect, profile, cursor_byte) + fathom.complete.v1 envelope + five-file registration in one commit" under auto_advance
2. **Task 2: fathom_complete_v1 export + fathom.complete.v1 envelope + five-file registration end-to-end** - `c6eb2f9` (feat) — exports.mbt export, schema.mbt envelope/validation, moon.pkg js+wasm exports, export_smoke wire smoke, docs/API.md + zh-CN wire surface
3. **Task 3: Wire error matrix + cross-target registration + completion core boundary** - `f2568f9` (test) — export_smoke error matrix (InvalidCursor/oversize/malformed-UTF-8/FROM edit), run_js + run_wasm completion callsites

**Plan metadata:** `(summary commit follows)`

## Files Created/Modified
- `binding/exports.mbt` - `#export_name("fathom_complete_v1")` + `pub fn fathom_complete_v1(raw, dialect, profile, cursor_byte) -> Bytes` matching `@completion.complete`; Ok → completion_result_json, Err → completion_error_json; header doc updated to the five-export ABI surface
- `binding/schema.mbt` - `COMPLETE_SCHEMA_VERSION = "fathom.complete.v1"`; `completion_result_json` (items label/detail/start_byte/end_byte/new_text + dialect/profile/is_incomplete); `completion_error_json` (fathom.error.v1 + FATHOM-SCHEMA-003/007 + FATHOM-COMPLETE-001/002/003); `validate_schema_version` registers the fifth namespace
- `binding/moon.pkg` - `fathom/sql/completion` import + `fathom_complete_v1` appended to the js AND wasm exports arrays (Pitfall 3/8)
- `parity/export_smoke_test.mbt` - `completion_export_is_dialect_aware_with_neutral_wire_identity` (happy path + unknown profile FATHOM-SCHEMA-003 + unknown dialect FATHOM-SCHEMA-007 + neutral item text) and `completion_wire_error_matrix_and_source_range_edit` (InvalidCursor/oversize/malformed-UTF-8/FROM prefix edit)
- `parity/run_js.mbt` + `parity/run_wasm.mbt` - `fathom_complete_v1(b"SELECT FRO", "flink", "flink-2.3.0", 9)` callsite exercising the cursor_byte : Int ABI on JS + linear-Wasm (A6)
- `docs/API.md` + `docs/zh-CN/API.md` - "Wire Exports (JS ESM / linear-Wasm)" section: five-export table, A4 order note, fathom.complete.v1 envelope example, and the completion error-code table

## Decisions Made
- D-04 one-way: confirm `fathom_complete_v1(raw, dialect, profile, cursor_byte) -> Bytes` (A4) + `fathom.complete.v1` envelope + five-file registration in one commit (option-a) — the wire schema is published, so later changes require a schema migration.
- Completion error codes: reuse FATHOM-SCHEMA-003/007 for profile/dialect (uniform schema-code surface with parse/format), new FATHOM-COMPLETE-001/002/003 for InvalidCursor/InvalidSource/InputTooLarge — always the fathom.error.v1 envelope.
- Neutral item text (D-10/D-28): detail constant "SQL syntax keyword"; dialect/profile ride in envelope metadata only.
- Cursor bounds single-sourced in `@completion.complete` (InvalidCursor); the binding export never re-checks.

## Deviations from Plan

None - plan executed exactly as written. The only additive scope was `docs/zh-CN/API.md` in the Task 2 docs commit, keeping the translated API reference in sync with `docs/API.md` (repo convention from 13-03) — this stays inside the plan's five-file change-set intent.

**Total deviations:** 0 auto-fixed
**Impact on plan:** No scope creep; all verification gates pass on the exact committed content.

## Issues Encountered
- The GSD runtime (`gsd-core/bin/lib`) is not built in this environment and `gsd-tools.cjs` cannot run (missing `cli-exit.cjs`, no TypeScript to rebuild, no network for `npm install`). The plan's execution did not depend on gsd-tools for task work: state/ROADMAP updates were out of scope per the orchestrator environment (do not modify STATE.md/ROADMAP.md), the final SUMMARY commit was made with plain `git commit` (single-repo, no sub_repos), and the broken-windows ledger (`gsd_run windows append`) had no applicable entries (no stubs, skipped tests, or unrun verifies in this plan — every `<verify>` ran and passed).
- The plan's Task 2 acceptance "grep the wasm exports for the symbol" was satisfied by parsing the linear-Wasm export section of `_build/wasm/debug/build/binding/binding.wasm` directly (the wasm binary format's export section) — the artifact exports all five `fathom_*_v1` symbols.
- `moon test --target native` (unscoped full suite) fails on the `binding` package (`#export_name` requires `pkgtype(kind: "foreign_library")` for the native target) — pre-existing and unrelated (documented in 13-03); the plan's verification scopes explicitly to `--package parity --package completion`.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- The completion wire contract is complete and registered on both JS and linear-Wasm: hosts can call `fathom_complete_v1` and receive `fathom.complete.v1` envelopes with neutral, source-range completion items.
- The full five-export wire surface (parse/format/complete/dialect/capabilities) is enumerated in docs/API.md — 13-06 host selection wiring can consume `fathom_complete_v1` from Web/Monaco, VS Code, and IntelliJ.
- Frozen Doris baseline (213) and flink-grammar/flink-lexical snapshots remain byte-identical (455 snapshots, compare_backends digest unchanged); `--update` stays excluded from CI.

---
*Phase: 13-toolchain-and-editor-packaging*
*Completed: 2026-08-10*

## Self-Check: PASSED
- Files verified: binding/exports.mbt, binding/schema.mbt, binding/moon.pkg, parity/export_smoke_test.mbt, parity/run_js.mbt, parity/run_wasm.mbt, docs/API.md, docs/zh-CN/API.md, .planning/phases/13-toolchain-and-editor-packaging/13-04-SUMMARY.md.
- Commits verified: c6eb2f9 (Task 2 tracer), f2568f9 (Task 3 error matrix + cross-target).
- Gates: moon test --target native --package parity --package completion = 608 passed; moon test --target js --package parity = 597 passed; moon test --target wasm --package parity = 597 passed; moon build --target js binding + moon build --target wasm binding = 0 errors; built binding.js and linear-Wasm binding.wasm export fathom_complete_v1; python3 scripts/compare_backends.py = 3 targets PASS, digest 2eda35825e17746e13ddaddc9604fe62824c5bba8dc1343f33e063f60b6ed065 identical; python3 scripts/check_naming.py = 601 product files, zero forbidden naming remnants; no --update anywhere.
