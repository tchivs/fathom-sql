---
phase: 06-lint-and-fingerprint
plan: 03
subsystem: api
tags: [lint, wire, envelope, binding]

requires:
  - phase: 06
    plan: 01
    provides: schema v2 bump (fathom.lint.v1), formatter-safe refusal pattern
  - phase: 06
    plan: 02
    provides: lint/ library (run_rules, apply_fixes)
provides:
  - api.lint_text / api.fix_text shared core entries
  - fathom_lint_v1 wire export with overrides JSON parsing
  - lint_result_json envelope serialization
affects: [06-04 CLI, parity, docs]

actuals:
  tokens: 4200
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Overrides as UTF-8 JSON array parsed structurally (never silent default)"
    - "fix_text round-trip reparse defense over apply_fixes"

key-files:
  created:
    - test/lint_test.mbt
  modified:
    - api/api.mbt
    - api/moon.pkg
    - binding/exports.mbt
    - binding/schema.mbt
    - binding/moon.pkg

key-decisions:
  - "parse_document helper shared by lint_text/fix_text (and reusable) mirrors format_text's internal parse"
  - "fix_text refuses via FATHOM-LINT-000 if the fixed output fails to reparse clean (D-03 defense in depth)"
  - "lint_result_json lives in binding/schema.mbt next to format/fingerprint envelopes"
  - "fathom_lint_v1 parses overrides structurally; malformed JSON / unknown code / unknown severity -> structured fathom.error.v1"

patterns-established:
  - "D-38 lint type aliases re-exported through @api (LintOptions/LintResult/.../RuleOverride/LintSeverity/RuleSetting)"
  - "wire/CLI run only CST rules (001/002/003/008) — analyzer-enhanced 004-007 need an injected catalog (ANLY-01)"

requirements-completed: [LINT-01]

coverage:
  - id: D1
    description: "api.lint_text / api.fix_text + D-38 lint type aliases"
    requirement: LINT-01
    verification:
      - kind: integration
        ref: "test/lint_test.mbt#lint_text_reports_select_star_without_limit"
        status: pass
      - kind: integration
        ref: "test/lint_test.mbt#lint_text_reports_unquoted_reserved_word_on_recoverable_tree"
        status: pass
      - kind: integration
        ref: "test/lint_test.mbt#fix_text_valid_input_no_fixable_findings_returns_unchanged"
        status: pass
      - kind: integration
        ref: "test/lint_test.mbt#fix_text_refuses_tree_with_unsafe_material_d33"
        status: pass
    human_judgment: false
  - id: D2
    description: "fathom_lint_v1 wire export + lint_result_json envelope with overrides parsing"
    requirement: LINT-01
    verification:
      - kind: integration
        ref: "parity/fingerprint_parity_test.mbt#lint_export_is_additive_and_primitive"
        status: pass
      - kind: unit
        ref: "moon build --target js --package binding"
        status: pass
    human_judgment: false

duration: 60min
completed: 2026-08-10
status: complete
---

# Phase 6: Lint and Fingerprint - Plan 03 Summary

**api.lint_text/api.fix_text with D-38 lint type aliases, fathom_lint_v1 wire export with structural overrides parsing, and the fathom.lint.v1 JSON envelope**

## Performance

- **Tasks:** 2
- **Commits:** 2
- **Files created:** 1
- **Files modified:** 5

## Accomplishments
- `api.lint_text` (report) and `api.fix_text` (autofix with round-trip reparse defense) shared core entries
- D-38 lint type aliases (`LintOptions`/`LintResult`/`LintFinding`/`LintEdit`/`LintDiagnostic`/`RuleOverride`/`LintSeverity`/`RuleSetting`) re-exported through `@api`
- `fathom_lint_v1(raw, dialect, profile, mode, overrides, fix)` wire export — dialect-first validation, structural overrides JSON parsing (malformed input → structured error, never silent default)
- `lint_result_json` fathom.lint.v1 envelope
- 6 integration tests through the real parser

## Task Commits

1. **Task 1: api.lint_text + api.fix_text + D-38 aliases** - `6ec5aaa` (feat)
2. **Task 2: fathom_lint_v1 + lint_result_json** - `c8dec38` (feat)

## Files Created/Modified
- `api/api.mbt` - parse_document helper, lint_text, fix_text (with reparse defense), D-38 lint aliases
- `api/moon.pkg` - `fathom/sql/lint` import
- `binding/schema.mbt` - lint_result_json
- `binding/exports.mbt` - fathom_lint_v1 + parse_overrides helper
- `binding/moon.pkg` - js+wasm exports registration
- `test/lint_test.mbt` - integration tests

## Decisions Made
- `fix_text` refuses with FATHOM-LINT-000 when the fixed output does not reparse clean (defense in depth over apply_fixes' D-33 gate)
- Overrides wire format: `[{"code":"FATHOM-LINT-0xx","setting":"off|error|warning|info"}]`; `[]`/empty = default registry

## Deviations from Plan

### Auto-fixed Issues

**1. `@parser.ParseResult` type name was wrong**
- **Found during:** Task 1
- **Issue:** The plan referenced the parser's result type as `@parser.ParseResult`; the actual type is `@parser.ParsedDocument`.
- **Fix:** Corrected the `parse_document` return type annotation.
- **Files modified:** api/api.mbt
- **Committed in:** 6ec5aaa

**2. `SELECT order FROM t` does not parse cleanly — fix integration test re-targeted**
- **Found during:** Task 1
- **Issue:** The plan's fix_text test expected `SELECT order FROM t` → `SELECT `order` FROM t`. But `order` is reserved, so the parser produces a recoverable tree with a `missing` node → apply_fixes correctly refuses (D-33). The fix-works path is demonstrable only on hand-built CSTs (covered in lint/lint_test.mbt white-box).
- **Fix:** The integration test asserts the correct observable behavior: fix_text on a valid input returns unchanged output; fix_text on a recoverable tree with a missing node refuses with FATHOM-LINT-000.
- **Files modified:** test/lint_test.mbt
- **Committed in:** 6ec5aaa

---

**Total deviations:** 2 auto-fixed (1 type-name correction, 1 test re-target to real D-33 behavior)
**Impact on plan:** No scope creep; both reflect the real parser/autofix contract.

## Next Phase Readiness
- 06-04 CLI can call `@api.lint_text/fix_text/fingerprint_text` directly
- parity smoke can call `fathom_lint_v1` / `fathom_fingerprint_v1`

---
*Phase: 06-lint-and-fingerprint*
*Completed: 2026-08-10*
