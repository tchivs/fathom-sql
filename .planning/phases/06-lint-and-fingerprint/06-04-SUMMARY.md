---
phase: 06-lint-and-fingerprint
plan: 04
subsystem: cli
tags: [cli, parity, docs, fingerprint, lint]

requires:
  - phase: 06
    plan: 01
    provides: fathom_fingerprint_v1, api.fingerprint_text
  - phase: 06
    plan: 02
    provides: lint/ library rules + autofix
  - phase: 06
    plan: 03
    provides: api.lint_text/fix_text, fathom_lint_v1
provides:
  - fathom-sql lint + fingerprint subcommands (D-39 0/1/2)
  - FING-01 SC4 cross-target fingerprint parity proof (native/js/wasm)
  - Lint/Fingerprint API docs (EN + zh-CN)
affects: [release packaging, CI]

actuals:
  tokens: 5200
  tasks: 3
  commits: 4

tech-stack:
  added: []
  patterns:
    - "CLI thin adapter: run_lint/run_fingerprint call @api only (D-37/D-38)"
    - "Cross-target parity: same decimal fingerprint string pinned on native/js/wasm"

key-files:
  created:
    - parity/fingerprint_parity_test.mbt
  modified:
    - fathom-sql/args.mbt
    - fathom-sql/run.mbt
    - fathom-sql/main.mbt
    - fathom-sql/cli_test.mbt
    - parity/run_js.mbt
    - parity/run_wasm.mbt
    - parity/export_smoke_test.mbt
    - docs/API.md
    - docs/zh-CN/API.md
    - .github/workflows/ci.yml

key-decisions:
  - "CLI never fabricates semantic findings: lint subcommand (no catalog) runs only CST rules 001/002/003/008 (ANLY-01)"
  - "fingerprint stdout is the UInt64 as a DECIMAL STRING (never number form, 2^53 precision)"
  - "--rule CODE=SEVERITY|off repeatable; unknown code/severity -> exit 2"
  - "FING-01 cross-target parity pinned by hardcoding the expected decimal fingerprint in the parity test"

patterns-established:
  - "D-39 exit codes extended to lint (0 clean / 1 findings or refusal / 2 usage) and fingerprint (0 success / 1 parse failure / 2 usage)"
  - "CI native matrix extended with fingerprint/lint/fathom-sql packages"

requirements-completed: [LINT-01, FING-01]

coverage:
  - id: D1
    description: "fathom-sql lint subcommand with --rule/--fix and D-39 exit codes"
    requirement: LINT-01
    verification:
      - kind: unit
        ref: "fathom-sql/cli_test.mbt#cli_lint_report_exit_0_no_findings"
        status: pass
      - kind: unit
        ref: "fathom-sql/cli_test.mbt#cli_lint_report_exit_1_findings_rendered"
        status: pass
      - kind: unit
        ref: "fathom-sql/cli_test.mbt#cli_lint_fix_refusal_exit_1_d33"
        status: pass
      - kind: unit
        ref: "fathom-sql/cli_test.mbt#cli_lint_unknown_rule_flag_exit_2"
        status: pass
    human_judgment: false
  - id: D2
    description: "fathom-sql fingerprint subcommand with decimal-string output"
    requirement: FING-01
    verification:
      - kind: unit
        ref: "fathom-sql/cli_test.mbt#cli_fingerprint_exit_0_decimal_string"
        status: pass
      - kind: unit
        ref: "fathom-sql/cli_test.mbt#cli_fingerprint_normalized_outputs_canonical_text"
        status: pass
    human_judgment: false
  - id: D3
    description: "FING-01 SC4 cross-target parity — same decimal fingerprint on native/js/wasm"
    requirement: FING-01
    verification:
      - kind: unit
        ref: "parity/fingerprint_parity_test.mbt#fingerprint_export_stable_cross_target_decimal_string"
        status: pass
      - kind: unit
        ref: "moon test --target js --package parity (602/602)"
        status: pass
      - kind: unit
        ref: "moon test --target wasm --package parity (602/602)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Lint/Fingerprint API docs (EN + zh-CN) with wire exports table"
    requirement: LINT-01
    verification:
      - kind: other
        ref: "docs/API.md + docs/zh-CN/API.md contain lint_text/fingerprint_text/FATHOM-LINT-000/fathom_lint_v1/fathom_fingerprint_v1"
        status: pass
    human_judgment: false

duration: 75min
completed: 2026-08-10
status: complete
---

# Phase 6: Lint and Fingerprint - Plan 04 Summary

**fathom-sql lint/fingerprint subcommands with D-39 exit codes, cross-target fingerprint parity proof, and bilingual API docs**

## Performance

- **Tasks:** 3
- **Commits:** 4
- **Files created:** 1
- **Files modified:** 10

## Accomplishments
- `fathom-sql lint` subcommand: report mode (exit 0 clean / exit 1 findings), `--fix` autofix (D-33 refusal → exit 1 + FATHOM-LINT-000), `--rule CODE=SEVERITY|off` repeatable config, unknown code → exit 2
- `fathom-sql fingerprint` subcommand: UInt64 fingerprint as decimal string on stdout (+ `--normalized` canonical text)
- FING-01 SC4 cross-target parity: `parity/fingerprint_parity_test.mbt` pins the same decimal fingerprint (214897735614764786) on Native, JS, and linear-Wasm (602/602 on each target)
- Wire smoke in `parity/run_js.mbt` + `run_wasm.mbt` for `fathom_lint_v1` / `fathom_fingerprint_v1`
- `export_smoke_test.mbt` asserts schema v2 bump is additive (new 2 namespaces + old 5 intact)
- Bilingual docs (EN + zh-CN): Lint Entry Points + Fingerprint Entry Points + Wire Exports table + FNV-1a non-cryptographic boundary + FATHOM-LINT-000 refusal code
- CI native matrix extended with `fingerprint`/`lint`/`fathom-sql` packages

## Task Commits

1. **Task 1: CLI lint + fingerprint subcommands** - `ae20185` (feat)
2. **Task 2: parity cross-target + wire smoke + export smoke** - `3d69066` (feat)
3. **Task 3: docs + CI matrix** - `2fa06d1` (docs)

## Files Created/Modified
- `fathom-sql/args.mbt` - subcommand whitelist + `--rule`/`--fix`/`--normalized` + Command fields
- `fathom-sql/run.mbt` - run_lint / run_fingerprint + render helpers
- `fathom-sql/main.mbt` - dispatch
- `fathom-sql/cli_test.mbt` - exit-code matrix (29 tests)
- `parity/fingerprint_parity_test.mbt` - cross-target decimal-string assertions
- `parity/run_js.mbt` + `run_wasm.mbt` - wire smoke
- `parity/export_smoke_test.mbt` - schema v2 additive assertion
- `docs/API.md` + `docs/zh-CN/API.md` - Lint/Fingerprint sections + wire table
- `.github/workflows/ci.yml` - native matrix extension

## Decisions Made
- CLI is a thin adapter (D-37): run_lint/run_fingerprint call @api only, no lint/fingerprint logic in the CLI
- fingerprint stdout is the decimal string (never number form)
- Cross-target parity pinned by hardcoded expected fingerprint value

## Deviations from Plan

### Auto-fixed Issues

**1. `Bytes::to_string()` is the debug form (`b"..."`), not the decoded text**
- **Found during:** Task 1 (fingerprint CLI tests)
- **Issue:** The digit/suffix checks operated on the debug form and failed.
- **Fix:** Decode via `@utf8.decode(outcome.stdout)` in the tests.
- **Files modified:** fathom-sql/cli_test.mbt
- **Committed in:** ae20185

**2. `@api.RuleOverride` record literals need explicit type annotations in tests**
- **Found during:** Task 1
- **Issue:** Standalone array literals of `RuleOverride` couldn't infer the type through the alias chain.
- **Fix:** Annotated `let overrides : Array[@api.RuleOverride] = [...]`.
- **Files modified:** fathom-sql/cli_test.mbt
- **Committed in:** ae20185

**3. ci.yml native matrix lacked the new packages**
- **Found during:** wave-3 verification
- **Issue:** The CI matrix predates the lint/fingerprint packages and fathom-sql CLI; their tests would not run in CI.
- **Fix:** Added `--package fingerprint --package lint --package fathom-sql` to the native matrix.
- **Files modified:** .github/workflows/ci.yml
- **Committed in:** 2fa06d1

---

**Total deviations:** 3 auto-fixed (2 test mechanics, 1 CI coverage)
**Impact on plan:** No scope creep; all fixes were necessary for correct tests and CI coverage.

## Next Phase Readiness
- LINT-01 and FING-01 are fully delivered: rule set + safe autofix + CLI + wire + docs + cross-target parity
- Phase 7 (Lineage) can build on the analyzer model; Phase 8 (Incremental) unchanged

---
*Phase: 06-lint-and-fingerprint*
*Completed: 2026-08-10*
