---
phase: 09-dialect-boundary-and-neutral-naming
plan: 03
subsystem: api
tags: [dialect, dialect-aware-format, dialect-aware-completion, fathom-format-v1, fathom-format-001-007, neutral-detail, d-08, d-09, d-10, d-28]
dependency_graph:
  requires:
    - phase: 09-01
      provides: "Frozen Doris v1 baseline (213 parity snapshots), approved-changes.md D-08 register, scripts/baseline_diff.py"
    - phase: 09-02
      provides: "dialect/ package (Dialect, DialectContext, per-dialect classification), context-threaded parse path, fathom.parse.v1/fathom_format_v1 exports, format/completion signature-threaded but behaviorally Doris-only"
  provides:
    - "Dialect-aware format path: format_with_ids(raw, dialect_id, profile_id, mode_id, ...) validates dialect-first (flink -> FATHOM-SCHEMA-003 before any formatting, T-09-10), formatter refusal emits FATHOM-FORMAT-001, format wire envelope carries fathom.format.v1 + dialect/profile/exact_release metadata (DIALECT-04)"
    - "Neutral format wire identity: FORMAT_SCHEMA_VERSION fathom.format.v1, FATHOM-FORMAT-001..007 in both formatter emission and binding mapping, fathom_format_v1 dialect-first at the export boundary (NAME-02 format half, D-09/D-10)"
    - "Dialect-aware completion: item detail neutralized to 'SQL syntax keyword' (row 27), flink requests return the structured unsupported-profile error — Doris keyword items never leak (Pitfall 6), unknown dialect -> UnknownDialect"
    - "Doris byte-parity proof: 692 approved diffs / 0 unexpected (Task 1) and 398 approved / 0 unexpected (Task 2) via baseline_diff.py vs the committed HEAD snapshot tree; 0 format snapshots changed formatted bytes; 0 completion snapshots changed item labels/order/ranges (DIALECT-03 ordering probe resolved)"
  affects: [09-05, 09-06, 09-07]
tech-stack:
  added: []
  patterns:
    - "Dialect-first validation at every selection boundary, including the format export: ParseOptions::new before option parsing (Pitfall 6, T-09-10)"
    - "Format result envelope mirrors the parse envelope metadata shape (dialect/profile/exact_release, DIALECT-04, D-09)"
    - "Single approved --update per register entry: the completion detail key:detail register pattern extends the D-08 machine-readable register"
key-files:
  created: []
  modified:
    - formatter/format.mbt (FATHOM-FORMAT-001 refusal code)
    - binding/schema.mbt (FORMAT_SCHEMA_VERSION fathom.format.v1, FATHOM-FORMAT-002..007, format_result_json dialect/exact_release)
    - binding/exports.mbt (fathom_format_v1 dialect-first + FATHOM-FORMAT-002/003/004)
    - completion/completion.mbt (neutral 'SQL syntax keyword' detail)
    - parity/parity_test.mbt + export_smoke_test.mbt + baseline_test.mbt + run_js.mbt + run_wasm.mbt
    - test/formatter_test.mbt, lsp/completion_test.mbt, lsp/diagnostics_formatting_test.mbt
    - doris-sql/cli_test.mbt + run.mbt
    - parity/__snapshot__ (124 files updated in one approved run)
key-decisions:
  - "Dialect-first validation at the fathom_format_v1 export boundary (before option parsing): a flink request returns FATHOM-SCHEMA-003 for any option set, satisfying T-09-10's 'no formatting under Doris policy' literally"
  - "format_result_json signature extended to (source, result, dialect, profile, exact_release): the wire envelope carries the same metadata as the parse envelope (DIALECT-04, D-09); exact_release derived from ParseOptions at each callsite"
  - "Export-level format assertions (fathom_format_v1 / fathom.format.v1 / FATHOM-SCHEMA-003) live in parity/export_smoke_test.mbt, not test/formatter_test.mbt — the test package cannot import binding (foreign_library E4219 on native test targets, documented since 04-03)"
  - "The plan's literal assertion 'a refusal yields FATHOM-FORMAT-001 with fathom.error.v1' is not reachable: a refusal is a FormatDiagnostic inside the fathom.format.v1 envelope; fathom.error.v1 only carries API-level errors. Implemented: refusal -> FATHOM-FORMAT-001 in the format envelope, option errors -> fathom.error.v1 + FATHOM-FORMAT-002"
  - "api/api.mbt needed no 09-03 change: format_with_ids/format_with_metadata already carry dialect_id and thread DialectContext from 09-02; the format metadata requirement is satisfied at the binding wire envelope"
requirements-completed: [DIALECT-02, DIALECT-03, NAME-02]
coverage:
  - id: D1
    description: "Dialect-aware format path with neutral wire identity: format_with_ids validates dialect-first (flink -> FATHOM-SCHEMA-003 before any formatting), formatter refusal emits FATHOM-FORMAT-001, FORMAT_SCHEMA_VERSION is fathom.format.v1, FATHOM-FORMAT-001..007 in formatter emission and binding mapping, fathom_format_v1 export with #export_name + moon.pkg exports lists in sync, format result envelope carries dialect/profile/exact_release; Doris formatted bytes byte-identical to v1"
    requirement: NAME-02
    verification:
      - kind: integration
        ref: "moon test --target native --package test --package parity --package formatter --package api (382 pass)"
        status: pass
      - kind: integration
        ref: "scripts/baseline_diff.py --left $(git archive HEAD:parity/__snapshot__) --right parity/__snapshot__ (692 approved, 0 unexpected)"
        status: pass
      - kind: unit
        ref: "parity/export_smoke_test.mbt#format_export_is_dialect_aware_with_neutral_wire_identity"
        status: pass
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_dialect_selection_is_validated_first"
        status: pass
    human_judgment: false
  - id: D2
    description: "Dialect-aware completion: doris-mode items byte-identical to v1 (labels, order, ranges) with the neutral 'SQL syntax keyword' detail; flink-mode returns the structured UnknownProfile error with no Doris items; unknown dialect returns UnknownDialect; item generation and profile_allows route through dialect classification_entries"
    requirement: DIALECT-02
    verification:
      - kind: integration
        ref: "moon test --target native --package completion --package lsp --package test --package parity (393 pass)"
        status: pass
      - kind: integration
        ref: "scripts/baseline_diff.py (398 approved, 0 unexpected); completion snapshot label/order/range changes = 0/27"
        status: pass
      - kind: unit
        ref: "lsp/completion_test.mbt#completion_is_dialect_aware_with_neutral_detail"
        status: pass
    human_judgment: false
metrics:
  duration: 25 min
  completed_date: 2026-08-06
  tasks: 2
  commits: 3
  files: 140
status: complete
actuals:
  tokens: 294123  # chars/4 over the realized diff incl. 124 generated snapshot files (estimate 30000 assumed hand-written code)
  tasks: 2
  commits: 3
---

# Phase 09 Plan 03: Dialect-Aware Format and Completion — Neutral Wire Identity

**Dialect-aware format and completion paths: formatter keyword-case rewriting and the FATHOM-FORMAT-001 refusal route through the selected dialect's classification, completion items carry the neutral "SQL syntax keyword" detail with flink explicitly rejected (FATHOM-SCHEMA-003, no Doris-policy leak), and the format wire identity is fully fathom.format.v1 / FATHOM-FORMAT-001..007 with dialect/profile/exact_release metadata — Doris v1 bytes proven byte-identical by the approved-change baseline gate**

## Performance

- **Duration:** 25 min
- **Started:** 2026-08-06T15:12:00Z
- **Completed:** 2026-08-06T15:36:44Z
- **Tasks:** 2
- **Commits:** 3 (1b5c720, 4e4bcee, fa927dc) + final docs commit
- **Files modified:** 140 (incl. 124 updated baseline snapshots)

## Accomplishments

- **Dialect-aware format path (Task 1):** `format_with_ids(raw, dialect_id, profile_id, mode_id, ...)` (already dialect-threaded by 09-02) now produces a fully neutral wire envelope: `FORMAT_SCHEMA_VERSION` is `fathom.format.v1`; the formatter refusal emits `FATHOM-FORMAT-001`; `format_error_json` maps `FATHOM-FORMAT-002..007`; `format_result_json` carries `dialect`/`profile`/`exact_release` metadata mirroring the parse envelope (DIALECT-04, D-09). Keyword case rewriting was already routed through `dialect.classification_of(context, raw)` by 09-02 — for a Doris context this is the same table as v1, so output bytes are identical (verified: 0 format snapshots changed `formatted` bytes).
- **Dialect-first at the export boundary (Pitfall 6, T-09-10):** `fathom_format_v1` validates the selection via `ParseOptions::new(dialect, profile, mode)` BEFORE option parsing — a flink request returns the structured `FATHOM-SCHEMA-003` error for any option set, never a Doris-policy format. The `ParseOptions` also supplies `exact_release` for the result envelope.
- **Neutral format wire identity (NAME-02 format half, D-10):** `fathom_format_v1` (with `#export_name` and binding/moon.pkg js/wasm exports lists in sync — carried over from 09-02), `FATHOM-FORMAT-001..007` in both formatter emission and binding mapping; grep gate confirms no `DORIS-FORMAT-`/`doris.format.v1` remains in formatter/, binding/, api/, parity/ *.mbt/*.pkg.
- **Dialect-aware completion (Task 2, rows 26-27):** item detail neutralized from "Doris syntax keyword" to "SQL syntax keyword"; `profile_allows` and item generation already route through `dialect.classification_entries(context)` (09-02). flink-mode completion returns the structured `UnknownProfile` error — Doris items never leak; unknown dialect returns `UnknownDialect`.
- **Doris byte-parity proof (D-08 gate):** single approved `moon test --update --package parity` after the register entry was committed; `baseline_diff.py` vs the committed HEAD snapshot tree reports **692 approved / 0 unexpected** (Task 1) and **398 approved / 0 unexpected** (Task 2). The genuine drift gate (`moon test --package parity` without `--update`) is green (228/228). Probe DIALECT-03 ordering **resolved**: 0/27 completion snapshots changed item labels, order, or ranges — the dialect dimension adds no reordering.

## Task Commits

| Task | Name | Commit | Key files |
| ---- | ---- | ------ | --------- |
| 0 | Register approved change entries (D-08 single-use path) | 1b5c720 | approved-changes.md (key:detail machine pattern + section 9) |
| 1 | Dialect-aware format path — FATHOM-FORMAT codes, fathom.format.v1, fathom_format_v1 | 4e4bcee | formatter/format.mbt, binding/schema.mbt, binding/exports.mbt, parity tests + 97 snapshots, test/formatter_test.mbt, lsp/diagnostics_formatting_test.mbt, doris-sql tests |
| 2 | Dialect-aware completion + tests | fa927dc | completion/completion.mbt, lsp/completion_test.mbt, 27 completion snapshots |

## Files Created/Modified

- `formatter/format.mbt` - refusal diagnostic code DORIS-FORMAT-001 -> FATHOM-FORMAT-001 (D-10); doc comments updated
- `formatter/error.mbt` - FormatResult doc comment updated to FATHOM-FORMAT-001
- `binding/schema.mbt` - FORMAT_SCHEMA_VERSION = fathom.format.v1; format_error_json FATHOM-FORMAT-002..007; format_result_json(source, result, dialect, profile, exact_release) with dialect/exact_release fields
- `binding/exports.mbt` - fathom_format_v1 dialect-first validation (ParseOptions before options), FATHOM-FORMAT-002/003/004 at the export boundary, exact_release threaded into the envelope
- `completion/completion.mbt` - item detail "Doris syntax keyword" -> "SQL syntax keyword" (row 27, neutral)
- `parity/export_smoke_test.mbt` - fathom.format.v1 assertion + new `format_export_is_dialect_aware_with_neutral_wire_identity` test (a/b/c: happy path metadata, refusal FATHOM-FORMAT-001, flink FATHOM-SCHEMA-003)
- `parity/parity_test.mbt` - FATHOM-FORMAT-001/002/006 + fathom.format.v1 + dialect field assertions
- `parity/baseline_test.mbt` - cli_format_json format_result_json callsite with dialect/exact_release
- `parity/run_js.mbt`, `parity/run_wasm.mbt` - Rule 3: stale doris_parse_v1/doris_format_v1 callsites -> fathom_*_v1 with dialect (js/wasm parity builds were broken since 09-02)
- `test/formatter_test.mbt` - FATHOM-FORMAT-001 rename (12 sites) + `formatter_dialect_selection_is_validated_first` (flink/unknown rejection, refusal code)
- `lsp/diagnostics_formatting_test.mbt` - fathom.format.v1 constants + new format_result_json signature
- `lsp/completion_test.mbt` - `completion_is_dialect_aware_with_neutral_detail` (neutral detail, flink/unknown structured errors)
- `doris-sql/cli_test.mbt`, `doris-sql/run.mbt` - FATHOM-FORMAT-001 assertion + doc comments
- `parity/__snapshot__/` - 124 files updated in the single approved run (97 format/cli/lsp + 27 completion)

## Decisions Made

- **Dialect-first at the format export boundary:** `fathom_format_v1` runs `ParseOptions::new(dialect, profile, mode)` before keyword-case/comma/newline option parsing. A flink request therefore returns `FATHOM-SCHEMA-003` for any option set — the plan's prohibition "Flink requests must never be formatted or completed under Doris policy" is satisfied literally (T-09-10), and the same ParseOptions supplies `exact_release` for the envelope.
- **format_result_json metadata signature:** extended to `(source, result, dialect, profile, exact_release)` so the wire envelope carries the same dialect/profile/exact_release metadata as the parse envelope (DIALECT-04, D-09). Callers (fathom_format_v1, parity cli_format_json, lsp test) derive exact_release via `ParseOptions::new` — infallible because the selection was already validated.
- **Export-level assertions live in parity:** the plan's literal placement of fathom_format_v1 assertions in test/formatter_test.mbt is unreachable — the test package does not import binding, and adding that import breaks the native test target with E4219 (foreign_library #export_name, documented in ci.yml since 04-03). The (a)-(c) assertions were placed in parity/export_smoke_test.mbt, matching the 09-02 pattern; test/formatter_test.mbt got the api-level dialect-first + refusal assertions.
- **Refusal envelope nuance:** the plan's literal assertion "a refusal yields FATHOM-FORMAT-001 with fathom.error.v1" is not reachable — a refusal is a FormatDiagnostic inside the fathom.format.v1 format envelope; fathom.error.v1 only carries API-level selection/option errors. Implemented: refusal -> FATHOM-FORMAT-001 in the format envelope; option errors -> fathom.error.v1 + FATHOM-FORMAT-002. The observable contract (neutral code family, stable envelopes) holds.
- **api/api.mbt unchanged:** the plan listed it in files_modified, but 09-02 already threaded dialect_id into format_with_ids/format_with_metadata and the DialectContext into formatter.format; the format metadata requirement is satisfied at the binding wire envelope. No 09-03 change needed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Stale cross-target runners referenced exports removed in 09-02**
- **Found during:** Task 1 (parity surface sweep for the wire migration)
- **Issue:** parity/run_js.mbt and parity/run_wasm.mbt still called `@binding.doris_parse_v1(source, "4.x", "editor")` / `doris_format_v1(...)` — exports that 09-02 renamed to fathom_*_v1 and re-signatured. The js/wasm parity target builds have been broken since 09-02 (09-02's native-only gate could not compile these files, which are target-scoped in parity/moon.pkg).
- **Fix:** Migrated both runners to `fathom_parse_v1`/`fathom_format_v1` with the dialect argument ("doris" right after raw).
- **Files modified:** parity/run_js.mbt, parity/run_wasm.mbt
- **Verification:** `moon build --target js parity` and `moon build --target wasm parity` both green (0 errors).
- **Committed in:** 4e4bcee (Task 1 commit)

**2. [Rule 3 - Blocking] Test placement and refusal-envelope wording unreachable as literally planned**
- **Found during:** Task 1 (writing the (a)-(c) format assertions)
- **Issue:** (i) test/formatter_test.mbt cannot call fathom_format_v1 — the test package does not import binding and importing a foreign_library with #export_name breaks the native test target (E4219, documented since 04-03); (ii) "a refusal yields FATHOM-FORMAT-001 with fathom.error.v1" is not reachable — refusals are diagnostics inside the fathom.format.v1 envelope.
- **Fix:** Export-level assertions placed in parity/export_smoke_test.mbt (a/b/c per plan); api-level flink/unknown/refusal assertions in test/formatter_test.mbt; refusal asserted as FATHOM-FORMAT-001 inside the format envelope and fathom.error.v1 exercised via the FATHOM-FORMAT-002 option-error path.
- **Files modified:** parity/export_smoke_test.mbt, test/formatter_test.mbt
- **Verification:** Task 1 gate 382/382; export smoke test passes.
- **Committed in:** 4e4bcee (Task 1 commit)

**3. [Documented deferral] parity/fixtures + web + docs remnants are owned by later waves**
- **Found during:** Task 1 (acceptance grep "no old-format-schema or DORIS-FORMAT- string remains in formatter/, binding/, api/, or parity/")
- **Issue:** parity/fixtures/lsp-tracer.json and target-matrix.json still carry `doris.format.v1`; web/ (monaco-adapter, offline-smoke.mjs, main.test.ts) and docs/ still reference DORIS-FORMAT-001 / doris.format.v1.
- **Fix:** None applied — research rows 80-81 explicitly assign lsp-tracer.json to 09-06 and target-matrix.json + web facade to 09-05; docs naming is 09-07's gate. The 09-03 grep gate scopes to formatter/, binding/, api/, parity/ *.mbt/*.pkg, which is clean; the two fixture JSONs and host/docs files are tracked for their owning waves.
- **Files modified:** none (intentional deferral)
- **Verification:** grep over the gate scope returns no matches.
- **Committed in:** n/a

---

**Total deviations:** 3 auto-fixed (2 blocking, 1 documented deferral)
**Impact on plan:** All fixes required for the plan's own gates and for repo health (the js/wasm parity builds were already broken). No scope creep; no behavior change beyond the approved-change register.

## Issues Encountered

- `moon test --target native --package doris-sql` fails with E4219 (`#export_name` in a foreign_library on a test-target build) — a pre-existing toolchain boundary documented in ci.yml ("known since v1 (04-03)"), not a 09-03 regression: my changes added no `#export_name` and the module-wide `moon check --target native` compiles doris-sql cleanly (0 errors). The cli_test.mbt FATHOM-FORMAT-001 assertion is verified through the parity CLI homomorph (cli_format_json) and the format-path tests; the CLI package test suite has not been runnable via moon test since 04-03.
- The completion-detail register pattern (`key:detail: Doris syntax keyword -> SQL syntax keyword`) is a new machine-readable line form for the register; baseline_diff.py's existing `key:<key>: <old> -> <new>` parser consumed it without modification.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 09-05 (fathom_dialect_v1/capabilities + parity surface migration): binding still emits doris.profile.v1/doris.capabilities.v1 and doris_profile_v1/doris_capabilities_v1 exports (retained per 09-02); parity/fixtures/target-matrix.json carries the old schema strings; web adapter + offline-smoke.mjs still reference doris.format.v1/DORIS-FORMAT-001 (now behaviorally stale since the formatter emits FATHOM-FORMAT-001).
- 09-06 (LSP document context): lsp/handlers.mbt callsites are compile-correct with "doris" hardcoded; parity/fixtures/lsp-tracer.json (doris.parse.v1/doris.format.v1) is owned by this plan; format envelope now carries dialect/exact_release so LSP output gains the metadata.
- 09-07 (naming gate): docs/API.md + docs/CONFIGURATION.md + zh-CN still document DORIS-FORMAT-001; the completion detail neutralization is complete so no "Doris syntax keyword" remains in product code.
- CLI: doris-sql/run.mbt + cli_test.mbt already carry the dialect argument and FATHOM-FORMAT-001; the full CLI dialect surface (--dialect flag, D-11) is 09-04.

## Self-Check: PASSED

- All key files exist on disk and are committed: formatter/format.mbt (FATHOM-FORMAT-001), binding/schema.mbt (fathom.format.v1), binding/exports.mbt, completion/completion.mbt, parity tests, test/formatter_test.mbt, lsp tests.
- Commits verified in git log: 1b5c720, 4e4bcee, fa927dc.
- Gate evidence: Task 1 `moon test --target native --package test --package parity --package formatter --package api` 382/382; Task 2 `moon test --target native --package completion --package lsp --package test --package parity` 393/393; `moon test --package parity` (no --update) 228/228; baseline_diff 692+398 approved / 0 unexpected; `moon build --target js|wasm parity` 0 errors; `moon check --target native` 0 errors; 0 format snapshots changed formatted bytes; 0/27 completion snapshots changed labels/order/ranges.

---
*Phase: 09-dialect-boundary-and-neutral-naming*
*Completed: 2026-08-06*
