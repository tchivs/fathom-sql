---
phase: 09-dialect-boundary-and-neutral-naming
plan: 05
subsystem: core
tags: [moonbit, wire-contract, fathom-dialect-v1, fathom-capabilities-v1, fathom-schema-007, d-09, d-10, name-02, dialect-04, parity, baseline]

# Dependency graph
requires:
  - phase: 09-dialect-boundary-and-neutral-naming
    provides: "09-02/09-03: fathom_parse_v1/fathom_format_v1 exports with dialect arg, fathom.parse.v1/fathom.format.v1 wire identity, FATHOM-PARSE/FORMAT code mapping, dialect-aware format/completion"
  - phase: 09-dialect-boundary-and-neutral-naming
    provides: "09-04: fathom/sql module identity, fathom-sql CLI with --dialect/--profile, approved-changes.md register (sections 1-10)"
provides:
  - "fathom_dialect_v1(dialect) export: per-dialect profiles + version metadata under fathom.dialect.v1 (doris 2.1/3.x/4.x with exact_release/feature_introduction from DorisProfile metadata; flink empty set in Phase 9)"
  - "fathom_capabilities_v1() export: global dialect list with per-dialect profile availability under fathom.capabilities.v1"
  - "Complete FATHOM-* code mapping: UnknownDialect + ConflictingSelection -> FATHOM-SCHEMA-007 (new mint); FATHOM-SCHEMA-001..006 and FATHOM-PARSE/FORMAT families per the section-5 table"
  - "validate_schema_version accepts exactly the four fathom.*.v1 namespaces (parse/format/error/capabilities)"
  - "Parity package pinned to the neutral wire surface across native/js/wasm with zero unexpected baseline diffs (213 snapshots unchanged)"
affects: [09-06, 09-07, 09-08, release-planning]

# Actuals (#2632) — pairs with the plan's `estimate` to calibrate future estimates.
actuals:
  tokens: 5319     # chars/4 over realized diff (13951 added + 7327 deleted chars)
  tasks: 2
  commits: 3       # 2 task commits + 1 final metadata commit

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Same-commit export sync (Pitfall 8): #export_name rename carries binding/moon.pkg js/wasm exports lists AND every parity/web callsite in one commit"
    - "D-08 register-first: FATHOM-SCHEMA-007 mint + envelope-field entries recorded in approved-changes.md BEFORE the single parity --update"
    - "Provenance discipline (T-09-18): fathom_dialect_v1 exact_release/feature_introduction sourced only from @api.ParseOptions::new(...).profile_metadata() — nothing fabricated"

key-files:
  created: []
  modified: [binding/exports.mbt, binding/schema.mbt, binding/moon.pkg, parity/export_smoke_test.mbt, parity/parity_test.mbt, parity/schema_test.mbt, parity/run_native.mbt, parity/run_js.mbt, parity/run_wasm.mbt, parity/fixtures/target-matrix.json, parity/baseline_test.mbt, web/src/monaco-adapter.ts, web/src/main.test.ts, docs/API.md, docs/ARCHITECTURE.md, docs/CONFIGURATION.md, docs/TESTING.md, docs/zh-CN/*.md, README.md, README.zh-CN.md, scripts/baseline_diff.py, approved-changes.md, deferred-items.md]

key-decisions:
  - "UnknownDialect serializes to FATHOM-SCHEMA-007 (with ConflictingSelection) per the plan's code mapping — 09-02's interim mapping put it on 003 alongside UnsupportedProfile; profile errors stay 003, dialect errors become distinguishable (OQ3)"
  - "validate_schema_version accepts exactly the four fathom.*.v1 namespaces (parse/format/error/capabilities, D-09); fathom.dialect.v1 is a metadata-query schema, not a result envelope (plan key_link)"
  - "fathom_dialect_v1(dialect) metadata comes from @api.ParseOptions::new('doris', profile, 'strict').profile_metadata() — the same provenance as the format envelope, avoiding a new binding->dialect import"
  - "Unknown dialect in fathom_dialect_v1 returns the SchemaError envelope (fathom.error.v1 + FATHOM-SCHEMA-007 + 'unknown dialect: X') via binding's own SchemaError constructor — ParseError variant constructors are read-only outside api"
  - "Parity test callsites migrated in Task 1's commit (Rule 3): the export rename breaks parity compilation; the same-commit rule (Pitfall 8, T-09-16) requires callsites to move with #export_name"

patterns-established:
  - "Pattern 1: metadata exports (fathom_dialect_v1/fathom_capabilities_v1) serve neutral negotiate-before-parse data; capabilities lists dialects + per-dialect profile availability, dialect carries release metadata"
  - "Pattern 2: wire-contract renames land with a grep gate scoped to the plan's surface; owned-by-later-wave remnants (LSP identity, host smoke) are logged in deferred-items.md with their owning plan"

requirements-completed: [NAME-02, DIALECT-04]

coverage:
  - id: D1
    description: "Four fathom.*.v1 namespaces + four fathom_*_v1 exports in sync (NAME-02): fathom_dialect_v1/fathom_capabilities_v1 added, #export_name == moon.pkg js/wasm exports lists, no old schema/export strings in the plan surface"
    requirement: NAME-02
    verification:
      - kind: unit
        ref: "moon test --target native --package parity --package api 236/236"
        status: pass
      - kind: integration
        ref: "moon test --target js --package parity 228/228; --target wasm 228/228 (runners migrated to fathom_capabilities_v1)"
        status: pass
      - kind: other
        ref: "grep gate over binding/parity/web/docs/README: zero old schema string / export symbol / DORIS- code prefix in the plan surface (remaining matches are 09-06/09-07-owned + corpus provenance, logged in deferred-items.md)"
        status: pass
    human_judgment: false
  - id: D2
    description: "validate_dialect_profile is the single gate and UnknownDialect/ConflictingSelection serialize to FATHOM-SCHEMA-007 (DIALECT-01/OQ3); flink rejected in Phase 9"
    requirement: DIALECT-04
    verification:
      - kind: unit
        ref: "parity/schema_test.mbt matrix: doris 2.1/3.x/4.x Ok, 5.x UnsupportedProfile, flink-2.3.0 UnsupportedProfile, mysql UnknownDialect; export_smoke_test asserts FATHOM-SCHEMA-007 for unknown dialect on parse and format paths"
        status: pass
      - kind: unit
        ref: "moon test --target native --package parity --package api 236/236"
        status: pass
    human_judgment: false
  - id: D3
    description: "fathom_dialect_v1/fathom_capabilities_v1 content: fathom.dialect.v1 with the three doris profiles (exact_release/feature_introduction from DorisProfile metadata), fathom.capabilities.v1 with both dialect names"
    requirement: NAME-02
    verification:
      - kind: unit
        ref: "parity/export_smoke_test.mbt + parity_test.mbt assertions (fathom.dialect.v1, \"id\":\"4.x\", \"dialect\":\"doris\"/\"flink\", exact_release, flink empty profiles)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Baseline gate (D-08): single approved moon test --update --package parity; genuine no-update drift gate green; baseline_diff vs committed HEAD snapshot tree reports zero diffs"
    requirement: NAME-02
    verification:
      - kind: integration
        ref: "moon test --package parity (no --update) 228/228 native/js/wasm after the register was committed (a4f081e)"
        status: pass
      - kind: other
        ref: "python3 scripts/baseline_diff.py --left <git archive HEAD:parity/__snapshot__> --right parity/__snapshot__ --approve approved-changes.md -> ok: 213 snapshots, 0 approved diffs, 0 unexpected (exit 0)"
        status: pass
    human_judgment: false

status: complete
---

# Phase 9 Plan 5: Wire-Contract Completion — fathom_*_v1 exports, fathom.*.v1 schemas, FATHOM-* code mapping, parity surface migration

**One-liner:** Completed the NAME-02 wire-contract cutover — `fathom_dialect_v1(dialect)`/`fathom_capabilities_v1()` exports with the `fathom.dialect.v1`/`fathom.capabilities.v1` schemas, `UnknownDialect`+`ConflictingSelection` → `FATHOM-SCHEMA-007` code mapping, and the full parity package pinned to the neutral surface with zero unexpected baseline diffs.

## Accomplishments

- **Four exports in sync (Pitfall 8, T-09-16):** `#export_name` symbols `fathom_parse_v1`/`fathom_format_v1`/`fathom_dialect_v1`/`fathom_capabilities_v1` == the `binding/moon.pkg` js+wasm `exports` lists exactly; the old `doris_profile_v1`/`doris_capabilities_v1` symbols are gone with zero aliases (D-06).
- **`fathom_dialect_v1(dialect)` (OQ4):** per-dialect profile availability under `fathom.dialect.v1` — doris returns the three profiles with `exact_release`/`feature_introduction` sourced only from `DorisProfile` metadata (via `ParseOptions::profile_metadata()`, T-09-18 provenance); flink returns an empty profile set (Phase 9, A1); unknown dialect returns a structured `FATHOM-SCHEMA-007` error envelope.
- **`fathom_capabilities_v1()` (OQ4):** global negotiation metadata under `fathom.capabilities.v1` — `dialects` (doris 2.1/3.x/4.x, flink empty) plus the retained `parse_schema`/`format_schema`/`source_transport`/`modes`/`targets`/`wasm_gc` fields.
- **Complete `FATHOM-*` mapping (D-10, OQ3):** `UnknownDialect` AND `ConflictingSelection` serialize to the new `FATHOM-SCHEMA-007` (minted in approved-changes.md before the snapshot update); `UnsupportedProfile` stays 003, `UnsupportedMode` 004, metadata-mismatch 005, feature-introduction 006, and the PARSE/FORMAT families keep the section-5 mapping.
- **`validate_schema_version`** accepts exactly the four `fathom.*.v1` result/error namespaces (parse/format/error/capabilities, D-09); `fathom.dialect.v1` is a metadata-query schema, not a result envelope.
- **Parity surface migration (rows 82-83):** `schema_test.mbt` (four-schema + full `validate_dialect_profile` matrix), `export_smoke_test.mbt` and `parity_test.mbt` (new export callsites with dialect arg + `FATHOM-SCHEMA-007` assertions), `target-matrix.json` (fathom schema strings + `dialect` field), and the native/js/wasm runners (`fathom_capabilities_v1`). `coordinates_test.mbt` needed no changes (no wire callsites).
- **Web facade wire references (09-03 deferral):** `monaco-adapter.ts`/`main.test.ts` call `fathom_parse_v1`/`fathom_format_v1` with the `'doris'` dialect argument, check `fathom.error.v1`, and assert `fathom.parse.v1`/`fathom.format.v1` — the demo now matches the built artifact ABI. Docs/README `DORIS-*` codes and `doris.parse.v1` renamed to `FATHOM-*`/`fathom.parse.v1` (prose beyond code strings stays 09-07's).

## Baseline Gate (D-08)

- Single approved `moon test --update --package parity` ran AFTER the register (09-05 section, commit `a4f081e`) — 228/228, **zero snapshot byte changes** (the wire renames do not touch frozen parse/format/cli/completion/lsp bytes).
- Genuine drift gate `moon test --package parity` (no `--update`) green on native, js, and wasm (228/228 each); cross-target byte equality holds.
- `scripts/baseline_diff.py --left <git archive HEAD:parity/__snapshot__> --right parity/__snapshot__ --approve approved-changes.md` → `ok: 213 snapshots, 0 approved diffs, 0 unexpected` (exit 0).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Parity test files migrated in Task 1's commit (not Task 2)**
- **Found during:** Task 1 (renaming `doris_profile_v1`/`doris_capabilities_v1` in binding).
- **Issue:** parity/schema_test.mbt, export_smoke_test.mbt, parity_test.mbt call the removed exports; the parity package could not compile, blocking Task 1's verify (`moon test --target native --package parity --package api`).
- **Fix:** Migrated the parity callsites and assertions in Task 1's commit — the same-commit rule (Pitfall 8, T-09-16) requires callsites to move with `#export_name`; the plan's Task 2 then covered the fixtures (target-matrix.json), the baseline_test comment, and the snapshot gate.
- **Files modified:** parity/schema_test.mbt, parity/export_smoke_test.mbt, parity/parity_test.mbt
- **Commit:** a4f081e

**2. [Rule 3 - Blocking] parity/run_native.mbt + run_js.mbt + run_wasm.mbt migrated to `fathom_capabilities_v1`**
- **Found during:** Task 1 (target builds after the capabilities export rename).
- **Issue:** the three target-scoped runners still called `@binding.doris_capabilities_v1()` — the js/wasm/native parity target builds would break (mirror of the 09-03 deviation for parse/format).
- **Fix:** Migrated to `fathom_capabilities_v1()`.
- **Files modified:** parity/run_native.mbt, parity/run_js.mbt, parity/run_wasm.mbt
- **Commit:** a4f081e
- **Verification:** `moon test --target js --package parity` and `--target wasm` both 228/228.

**3. [Rule 3 - Blocking] Web facade + docs/README wire references migrated (09-03 deferral)**
- **Found during:** Task 1 acceptance grep ("no old-schema string / old export symbol / DORIS- code prefix in product files").
- **Issue:** web/src/monaco-adapter.ts + main.test.ts called the removed `doris_parse_v1`/`doris_format_v1` exports and checked `doris.error.v1`; docs/README still documented `DORIS-PARSE-*`/`DORIS-FORMAT-*`/`doris.parse.v1` (behaviorally stale since 09-02/09-03). The 09-03 summary assigned the web facade to 09-05.
- **Fix:** Migrated the wire-contract references (export symbols with the `'doris'` dialect argument per A4, schema strings, error codes). Docs prose beyond schema/code strings (module names, CLI, dialect tables) remains 09-07's scope.
- **Files modified:** web/src/monaco-adapter.ts, web/src/main.test.ts, docs/API.md, docs/ARCHITECTURE.md, docs/CONFIGURATION.md, docs/TESTING.md, docs/zh-CN/*.md, README.md, README.zh-CN.md, scripts/baseline_diff.py (example comment)
- **Commit:** a4f081e
- **Verification:** `node --experimental-strip-types --test web/src/main.test.ts` 4/4.

### Deferred (owned by later waves — logged in deferred-items.md)

- `parity/fixtures/lsp-tracer.json` (`doris.parse.v1`/`doris.format.v1` + dialect field) → 09-06 (plan context explicitly assigns it).
- `lsp/handlers.mbt:98` `DORIS-LSP-001` (+ `source`/`serverInfo` identity) → 09-06.
- `web/scripts/offline-smoke.mjs:21,26` `DORIS-FORMAT-001` → 09-07 (web host sweep; the file also carries another agent's uncommitted monaco 0.56.0 bump, so it cannot be cleanly committed here).
- `vscode/src/host-test.ts` + `vscode/README.md` `DORIS-PARSE-006` → 09-07 (hosts).
- `corpus/**` provenance rows and the embedded fixture bytes in parity/baseline_test.mbt keep their `DORIS-PARSE`-referencing text — D-04 provenance exempt.

## Next Phase Readiness

- 09-06 (LSP selection resolution) can proceed: `fathom_*_v1` exports are final, `FATHOM-SCHEMA-007` is the dialect-selection error code, and its owned surface is exactly `lsp/handlers.mbt` identity (`DORIS-LSP-001`, `source`, `serverInfo.name`) + `parity/fixtures/lsp-tracer.json`.
- 09-07 (hosts + naming gate) owns the remaining prose (`docs` module/CLI tables, `README` product names), the `vscode` host-test code assertions, `web` host smoke/copy (including `offline-smoke.mjs`), and the NAME-04 gate script.
- The D-06 one-way door holds: no old schema string, export symbol, or `DORIS-*` code prefix remains in the plan surface (binding/parity/web/docs/README); the frozen baseline is byte-identical (213/213 snapshots).

## Self-Check: PASSED

- `09-05-SUMMARY.md` exists in the plan directory.
- Task commits verified in git: `a4f081e` (Task 1 — fathom wire contract), `9eea66c` (Task 2 — parity fixtures).
- Final verification commands all green: `moon test --target native --package parity --package api` (236/236), `moon test --package parity` + `--target js` + `--target wasm` (228/228 each, no `--update`), `baseline_diff.py` 0 approved / 0 unexpected (exit 0), web `main.test.ts` 4/4.
