---
phase: 07-column-lineage
plan: 05
subsystem: testing
tags: [moonbit, lineage, parity, docs, api-coverage]

# Dependency graph
requires:
  - phase: 07-04
    provides: "fathom.lineage.v1 wire export + fathom_lineage_v1(raw, dialect, profile, mode, catalog_json) ABI + binding/catalog_json.mbt parse_catalog_json + fathom-sql lineage subcommand — the frozen host-consumer surface the parity suite and docs consume"
  - phase: 07-03
    provides: "api.lineage_text(raw, parse_options, catalog: StaticCatalog?) + LineageResult/LineageEdge/LineageGap + lineage/ derive_lineage"
  - phase: 07-02
    provides: "lineage/ library derive_lineage[T: Catalog] + honest gap derivation"
provides:
  - "LINE-01 cross-target parity proof: parity/lineage_parity_test.mbt hardcoded fathom_lineage_v1 envelope assertions (edges/gaps/dialect/profile) run identically on native/js/wasm; compare_backends.py aggregate digest identical across targets"
  - "bilingual Lineage docs: docs/API.md + docs/zh-CN/API.md Lineage Entry Points section + fathom_lineage_v1 (8th export) wire row + lineage_text endpoints row + D-08 flink gate + SC2 no-catalog gap semantics"
  - ".planning/phases/07-column-lineage/COVERAGE.md api-coverage declaration (locked 'No external API integration' shape) for the api_coverage_gate"
affects: [08-edit-recovery, docs, ship gate]

# Actuals (#2632) — pairs with the plan's `estimate` (58000 estimateTokens, low confidence) to calibrate.
actuals:
  tokens: 6116      # chars/4 over the realized diff (24,466 diff chars / 4)
  tasks: 3
  commits: 3        # Task commits; SUMMARY/metadata commit tracked separately

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "parity hardcoded-expected-value pattern (fingerprint_parity_test.mbt:10-32): the same fathom_lineage_v1 envelope bytes asserted on native/js/wasm, so any target-specific serialization/ordering drift fails the assertion"
    - "export_smoke_test schema_v2_bump_is_additive extended to the 8th namespace: fathom.lineage.v1 appears while all seven prior namespaces stay usable (Pitfall V6 pure addition)"
    - "run_js/run_wasm smoke: fathom_lineage_v1 Bytes+String+Int ABI exercised with no println/env host IO (linear-Wasm portability)"

key-files:
  created:
    - parity/lineage_parity_test.mbt
    - .planning/phases/07-column-lineage/COVERAGE.md
  modified:
    - parity/run_js.mbt
    - parity/run_wasm.mbt
    - parity/export_smoke_test.mbt
    - docs/API.md
    - docs/zh-CN/API.md

key-decisions:
  - "Parity test uses hardcoded envelope substrings (no new snapshot fixtures): the fingerprint_parity_test pattern proves byte identity via per-target assertion + compare_backends.py tree digest; adding new snapshot files would require moon test --update and risk colliding with the concurrent 07-02 peer's snapshot tree"
  - "Docs document fathom_lineage_v1 catalog_json empty-bytes/'{}' = no catalog (SC2 honest requires-catalog gaps) and the D-08 flink gate (FATHOM-SCHEMA-003 'lineage is Doris-only') verbatim from the 07-04 implementation"

patterns-established:
  - "Lineage parity mirrors fingerprint parity: three-target byte identity for edges/gaps with hardcoded expected values, aggregated by compare_backends.py (Phase 12 D-03 discipline)"

requirements-completed: [LINE-01]

coverage:
  - id: D1
    description: "parity/lineage_parity_test.mbt — fathom_lineage_v1 same-fixture envelope bytes identical on native/js/wasm (hardcoded edges/gaps/dialect/profile assertions; catalog expression fixture, no-catalog requires-catalog gap fixture, star-with-catalog expansion)"
    requirement: LINE-01
    verification:
      - kind: e2e
        ref: "moon test --target native --package parity (605/605)"
        status: pass
      - kind: e2e
        ref: "moon test --target js --package parity (605/605)"
        status: pass
      - kind: e2e
        ref: "moon test --target wasm --package parity (605/605)"
        status: pass
      - kind: e2e
        ref: "python3 scripts/compare_backends.py (exit 0; digest 2eda3582… identical across native/js/wasm, 455 snapshot files)"
        status: pass
    human_judgment: false
  - id: D2
    description: "run_js/run_wasm fathom_lineage_v1 smoke (Bytes+String+Int ABI, no host IO) + export_smoke_test 8th-namespace additive assertion (fathom.lineage.v1 appears; existing 7 still usable)"
    requirement: LINE-01
    verification:
      - kind: e2e
        ref: "parity/run_js.mbt + run_wasm.mbt (js/wasm parity build, no println/env)"
        status: pass
      - kind: unit
        ref: "parity/export_smoke_test.mbt#schema_v2_bump_is_additive"
        status: pass
    human_judgment: false
  - id: D3
    description: "bilingual docs Lineage Entry Points section + fathom_lineage_v1 wire row (8th export) + lineage_text endpoints row + D-08/SC2 notes"
    requirement: LINE-01
    verification:
      - kind: other
        ref: "grep lineage_text/fathom_lineage_v1/fathom.lineage.v1/requires-catalog docs/API.md + docs/zh-CN/API.md (each ≥1: EN 3/2/3/4, ZH 3/2/3/4)"
        status: pass
    human_judgment: false
  - id: D4
    description: "COVERAGE.md api-coverage declaration (locked shape: No external API integration; lineage/ + fathom.lineage.v1 + fathom-sql lineage CLI subcommand)"
    requirement: LINE-01
    verification:
      - kind: other
        ref: "grep 'No external API integration'/'lineage/'/'fathom.lineage.v1'/'fathom-sql lineage CLI subcommand' COVERAGE.md (each =1; 238 bytes / 2 lines read-back, byte-exact locked shape)"
        status: pass
    human_judgment: false

# Metrics
duration: 20min
completed: 2026-08-11
status: complete
---

# Phase 07 Plan 05: Lineage parity cross-target + bilingual docs + COVERAGE.md api-coverage

**LINE-01 close-out: three-target (native/js/wasm) byte-identical lineage parity proven by hardcoded fathom_lineage_v1 envelope assertions, bilingual Lineage public-API docs, and the locked COVERAGE.md api-coverage declaration.**

## Performance

- **Duration:** 20 min
- **Started:** 2026-08-11T08:25:00Z
- **Completed:** 2026-08-11T08:45:37Z
- **Tasks:** 3
- **Commits:** 3 task commits + 1 docs/metadata commit
- **Files created:** 2 (parity/lineage_parity_test.mbt, .planning/phases/07-column-lineage/COVERAGE.md)
- **Files modified:** 5 (parity/run_js.mbt, parity/run_wasm.mbt, parity/export_smoke_test.mbt, docs/API.md, docs/zh-CN/API.md)

## Accomplishments
- **LINE-01 cross-target parity proof (D-07, Phase 12 D-03)**: `parity/lineage_parity_test.mbt` mirrors the fingerprint_parity_test hardcoded-expected-value pattern — the SAME `fathom_lineage_v1` envelope bytes asserted on native/js/wasm for (a) `SELECT a + b AS x FROM t` with a catalog JSON (two expression-passthrough edges `t.a→x`, `t.b→x` with flattened byte spans, no gaps), (b) `SELECT * FROM t` with empty catalog_json (one honest `requires-catalog` gap at the star span, zero edges — SC2), and (c) `SELECT * FROM t` with a catalog (star expansion to `a→a`, `b→b` in catalog column order). `python3 scripts/compare_backends.py` exits 0 with a snapshot-tree sha256 digest identical across all three targets.
- **Wire smoke + schema 8th-namespace assertion**: `parity/run_js.mbt` + `run_wasm.mbt` each add a `fathom_lineage_v1(b"SELECT a FROM t", "doris", "4.x", "strict", b"")` smoke call (`ignore(lineaged)`) — Bytes+String+Int ABI, no println/env host IO (linear-Wasm portability). `parity/export_smoke_test.mbt`'s `schema_v2_bump_is_additive` now asserts `fathom.lineage.v1` as the 8th namespace appearing while the existing seven namespaces remain usable (Pitfall V6 pure addition).
- **Bilingual Lineage docs (commit_docs: true)**: `docs/API.md` + `docs/zh-CN/API.md` gain a **Lineage Entry Points** section (the `lineage_text(raw, parse_options, catalog?)` signature, `LineageResult`/`LineageEdge`/`LineageGap` structures, optional-catalog semantics — `None` → star/external-view yields `requires-catalog` gap, SC2, the gap-codes table `requires-catalog`/`unresolved-reference`/`requires-complete-parse`, and the D-08 flink gate note), the `fathom_lineage_v1` row (8th export, `catalog_json` empty bytes = no catalog) in the Wire Exports table, a `lineage_text` row in the endpoints table, and the `fathom.lineage.v1` 8th-namespace pure-addition note.
- **COVERAGE.md api-coverage declaration**: `.planning/phases/07-column-lineage/COVERAGE.md` written with the byte-locked shape (`# API Coverage` + `No external API integration: Phase 7 adds an internal lineage analysis package (lineage/), an internal wire namespace (fathom.lineage.v1), and a fathom-sql lineage CLI subcommand. No external API/SDK/service is integrated.`) — 238 bytes / 2 lines, read-back verified.

## Task Commits

1. **Task 1: lineage parity cross-target + smoke + 8th namespace** - `b9f9ecd` (test)
2. **Task 2: bilingual Lineage section + wire row + D-08/SC2 notes** - `22baf48` (docs)
3. **Task 3: COVERAGE.md api-coverage declaration** - `c29e3ad` (docs)

**Plan metadata:** (separate `docs(07-05)` commit)

## Files Created/Modified
- `parity/lineage_parity_test.mbt` (new) - 3 hardcoded-expected-value tests proving fathom_lineage_v1 envelope byte identity across native/js/wasm (catalog expression edges, no-catalog requires-catalog gap, star-with-catalog expansion)
- `parity/run_js.mbt` - fathom_lineage_v1 smoke call (Bytes+String+Int ABI, no host IO)
- `parity/run_wasm.mbt` - fathom_lineage_v1 smoke call (same, linear-Wasm portable)
- `parity/export_smoke_test.mbt` - schema_v2_bump_is_additive extended with fathom.lineage.v1 (8th namespace, existing 7 still usable)
- `docs/API.md` - Lineage Entry Points section + fathom_lineage_v1 wire row + lineage_text endpoints row + D-08/SC2 notes
- `docs/zh-CN/API.md` - mirrored Chinese section/rows/notes
- `.planning/phases/07-column-lineage/COVERAGE.md` (new) - api-coverage declaration (locked shape)

## Decisions Made
- **Parity test uses hardcoded envelope substrings rather than new snapshot fixtures**: the fingerprint_parity_test pattern proves byte identity via per-target assertion + compare_backends.py tree digest; adding new snapshot files would require `moon test --update` and risk colliding with the concurrently-running 07-02 peer's snapshot tree in the shared repo.
- **Docs mirror the 07-04 implementation verbatim**: `catalog_json` empty bytes / `{}` = no catalog (SC2 honest gaps) and flink → `FATHOM-SCHEMA-003` "lineage is Doris-only" (D-08, never a silent empty result).

## Deviations from Plan

None - plan executed exactly as written. The three tasks matched the plan's file boundaries (`files_modified` = 7: parity ×4, docs ×2, COVERAGE ×1); `scripts/compare_backends.py` logic and the `lineage/`/`api/`/`binding/`/`fathom-sql/`/`parser/`/`analyzer/` dirs were not modified.

## Issues Encountered
- The peer executor `Exec0702` (07-02 plan) was concurrently committing lineage/analyzer work to the shared repo while this plan ran, so peer commit output interleaved into the hub shell logs. Every one of this plan's commits was verified clean via `git show --stat` (only this plan's files) and `git log` (this plan's three commits stacked directly on the 07-04 HEAD `57b6bf3`). No file overlap or index contamination occurred because each task staged only its own files.
- `moon test --target js|wasm --package parity` reports a pre-existing `unused_package 'utf8'` warning on the non-test main module (the alias is used only in test blocks) — a warning, not an error; all 605 tests pass on every target.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- LINE-01 is fully delivered end to end: lineage/ library (07-02) + api.lineage_text (07-03) + fathom.lineage.v1 wire / CLI (07-04) + three-target byte parity + bilingual docs + api-coverage declaration (07-05). The ship gate's api-coverage detector can now seal on the COVERAGE.md reasoned declaration.
- The parity suite (605 tests on each of native/js/wasm, digest-identical snapshot tree) is the regression harness for any future serializer/ordering change to the lineage envelope.
- `docs/API.md` is the single public surface reference for the lineage API, wire export, gap codes, and D-08 flink gate.

---
*Phase: 07-column-lineage*
*Completed: 2026-08-11*

## Self-Check: PASSED
- Files verified on disk: parity/lineage_parity_test.mbt, parity/run_js.mbt, parity/run_wasm.mbt, parity/export_smoke_test.mbt, docs/API.md, docs/zh-CN/API.md, .planning/phases/07-column-lineage/COVERAGE.md, .planning/phases/07-column-lineage/07-05-SUMMARY.md
- Commits verified in git log: b9f9ecd (Task 1), 22baf48 (Task 2), c29e3ad (Task 3)
- Test runs: `moon test --target native --package parity` 605/605; `--target js` 605/605; `--target wasm` 605/605; `python3 scripts/compare_backends.py` exit 0 with digest `2eda35825e17746e13ddaddc9604fe62824c5bba8dc1343f33e063f60b6ed065` identical across targets
- Doc greps: EN lineage_text=3, fathom_lineage_v1=2, fathom.lineage.v1=3, requires-catalog=4; ZH lineage_text=3, fathom_lineage_v1=2, fathom.lineage.v1=3, requires-catalog=4 (all ≥1)
- COVERAGE.md greps: No external API integration=1, lineage/=1, fathom.lineage.v1=1, fathom-sql lineage CLI subcommand=1; 238 bytes / 2 lines, byte-exact locked shape
- Forbidden dirs untouched: `git status --short -- lineage/ api/ binding/ fathom-sql/ parser/ analyzer/ scripts/compare_backends.py` empty of this plan's files (only pre-existing `fathom-sql/pkg.generated.mbti` untracked artifact)
