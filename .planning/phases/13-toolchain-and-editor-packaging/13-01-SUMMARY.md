---
phase: 13-toolchain-and-editor-packaging
plan: 01
subsystem: api
tags: [flink, formatter, refusal-first, d-33, layout, parity-snapshot, d-08]

# Dependency graph
requires:
  - phase: 11-flink-grammar-and-recoverable-cst
    provides: Flink statement-family SyntaxKinds and the Flink-safe parser (parse_flink_segment, parser.mbt:4140-4240) that emits them
  - phase: 12-cross-dialect-corpus-and-parity-gates
    provides: parity snapshot namespace discipline, diff_parity.py --frozen-only, approved-changes D-08 register
  - phase: 09-dialect-boundary-and-neutral-naming
    provides: DialectContext/Dialect::Flink, the formatter refusal-first channel (FATHOM-FORMAT-001, D-33)
provides:
  - Flink covered-family gate: flink_statement_covered + layout_statement dialect-conditional refusal for uncovered Flink families
  - Full D-01 20-family Flink layout coverage (clause_breaks arms per Flink-only family)
  - flink-format snapshot namespace (22 snapshots) + idempotence/zero-diagnostic-reparse/refusal oracle + covered-set completeness probe
affects: [13-04 wire surface, 13-02 completion, TOOL-01 verifier, Fathom formatter consumers]

# Actuals (#2632) — pairs with the plan's `estimate` to calibrate future estimates.
# Same estimateTokens scale (chars/4 over the realized diff), never a harness token count.
actuals:
  tokens: 10033    # chars/4 over the realized diff (40,131 chars incl. generated snapshots)
  tasks: 3
  commits: 4

# Tech tracking
tech-stack:
  added: []
  patterns:
    - dialect-conditional covered-family gate routing a programming-gap refusal through the existing Layout.failed channel
    - independent flink-format snapshot namespace (Pitfall 7) with per-fixture idempotence + zero-diagnostic reparse oracle

key-files:
  created:
    - parity/flink_format_test.mbt
    - .planning/phases/13-toolchain-and-editor-packaging/approved-changes.md
    - parity/__snapshot__/flink-format.*.json (22 snapshots)
  modified:
    - formatter/layout.mbt
    - parity/moon.pkg

key-decisions:
  - "Reuse the shared Select/Insert/Update/Delete/CreateTable/CreateView Doris clause_breaks arms for Flink (same SyntaxKind, overlapping clause words); Flink-only families get their own arms. Shared arms unchanged so the Doris 213 baseline stays byte-identical (PARITY-01)."
  - "The covered-family gate routes uncovered Flink families through the EXISTING Layout.failed -> FATHOM-FORMAT-001 refusal channel — no new result type (error.mbt FormatResult unchanged, D-33)."
  - "flink_statement_covered made pub and parity/moon.pkg gained formatter+syntax imports so the completeness probe machine-checks the covered set directly (must-have flagged-unverified probe), instead of a hand-maintained duplicate list."
  - "approved-changes.md register entry created and committed in Task 1 (before the first sanctioned moon test --update), honoring the D-08 hard gate even though the plan's task list placed it in Task 3."

patterns-established:
  - "Pattern: covered-family gate — a dialect-conditional predicate + layout_statement gate placed BEFORE layout_sequence that converts an uncovered family into a refusal via Layout.failed, never a silent single-line (D-01, Pitfall 1)."
  - "Pattern: flink-format oracle — per-fixture snapshot + format(format(x))==format(x) + zero-diagnostic reparse + statement-offset bounds; refusal rows assert accepted=false, empty output, exactly one FATHOM-FORMAT-001, parse diagnostics preserved (T-03-01)."

requirements-completed: [TOOL-01]

coverage:
  - id: D1
    description: "Flink covered-family gate — every statement family the Flink parser can emit is either covered by a layout arm or refused via exactly one FATHOM-FORMAT-001 with empty output (no silent Doris-layout single line)"
    requirement: TOOL-01
    verification:
      - kind: integration
        ref: "parity/flink_format_test.mbt#flink-format completeness probe: covered set never silently single-lines"
        status: pass
      - kind: integration
        ref: "parity/flink_format_test.mbt#flink_format_oracle_all_fixtures"
        status: pass
    human_judgment: false
  - id: D2
    description: "Flink canonical formatting for the D-01 20 covered families — multi-line clause-break layout frozen in the independent flink-format snapshot namespace; idempotent and zero-diagnostic reparse per fixture"
    requirement: TOOL-01
    verification:
      - kind: integration
        ref: "parity/flink_format_test.mbt#flink-format select-basic flink-2.3.0 strict"
        status: pass
      - kind: integration
        ref: "moon test --target native --package test --package formatter --package parity --package api (750 passed)"
        status: pass
      - kind: other
        ref: "scripts/diff_parity.py --frozen-only (455 snapshots, 0 frozen-vs-current differences)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Refusal oracle — unsafe Flink trees (missing expression tail AND unclosed paren) refuse with accepted=false, empty output, exactly one FATHOM-FORMAT-001, and every parse diagnostic preserved/prepended (never masked)"
    requirement: TOOL-01
    verification:
      - kind: integration
        ref: "parity/flink_format_test.mbt#flink-format refusal oracle: unsafe tree refuses, parse diagnostics preserved"
        status: pass
    human_judgment: false

# Metrics
duration: 10min
completed: 2026-08-10
status: complete
---

# Phase 13 Plan 01: Flink covered-family formatter gate + flink-format snapshot namespace

**Refusal-first Flink canonical formatting for all 20 Phase-11 statement families, backed by a dialect-conditional covered-family gate (FATHOM-FORMAT-001 for uncovered families), a new independent flink-format snapshot namespace, and a machine-checked completeness probe — with the frozen Doris 213-snapshot baseline byte-identical.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-08-10T10:35:00Z (approx, first plan commit 10:36:01 +0800)
- **Completed:** 2026-08-10T02:45:38Z (UTC)
- **Tasks:** 3
- **Files modified:** 26 (4 source/doc + 22 snapshots)

## Accomplishments
- **Covered-family gate (D-01):** `formatter/layout.mbt` gains `pub fn flink_statement_covered(family)` (the exact D-01 20-family set) and a dialect-conditional gate in `layout_statement` placed BEFORE `layout_sequence`. Under a Flink context any family not in the covered table routes through `Layout.failed` → exactly one `FATHOM-FORMAT-001` with empty output — never a silent Doris-layout single line (Pitfall 1). The gate is dialect-conditional and never fires for Doris.
- **Full 20-family layout coverage:** every Flink-only family got its own `clause_breaks` arm mirroring parser `consume_word` usage (ShowStatement, DescribeStatement, ExplainStatement, AnalyzeStatement, CreateCatalog/Database/Function, DropCatalog/Database/Table/View/Function, AlterTable, SetOption, UseStatement). Shared Select/Insert/Update/Delete/CreateTable/CreateView arms are reused unchanged so Doris output is byte-identical.
- **flink-format snapshot namespace:** 22 `flink-format.{fixture}.flink-2.3.0.strict.json` snapshots in a NEW independent namespace (Pitfall 7), generated via the single sanctioned `moon test --update --package parity` run after the D-08 register entry was committed. CI runs without `--update`, so the group is a genuine drift gate.
- **Oracle + completeness probe:** per-fixture idempotence `format(format(x))==format(x)`, zero-diagnostic reparse under flink-2.3.0 strict, statement-offset bounds; refusal rows assert `accepted=false`, empty output, exactly one FATHOM-FORMAT-001; the refusal oracle proves parse diagnostics are never masked (T-03-01). The completeness probe machine-checks that every Flink-emittable statement family is covered and no covered family silently single-lines.
- **Doris zero-drift proven:** `scripts/diff_parity.py --frozen-only` reports 0 frozen-vs-current differences across 455 snapshots after every change; `moon test --package parity` (no `--update`) is green; `scripts/check_naming.py` clean.

## Task Commits

Each task was committed atomically:

1. **Task 1: Flink covered-family gate + minimal covered set end-to-end** - `b21a82d` (feat) — gate + 6-family predicate + select-basic snapshot + uncovered-family refusal (SHOW)
2. **Task 2: Full Flink statement-family coverage — clause_breaks/layout arms for every family** - `0ea6044` (feat) — 20-family predicate + 15 Flink-only arms + 22 snapshots + completeness probe
3. **Task 3: flink-format snapshot namespace + refusal/idempotence assertions + Doris zero-drift gate** - `369aa19` (test) — unclosed-paren refusal fixture + strengthened refusal oracle + full-surface gate

**Plan metadata:** `8e64bc3` (docs: approved-changes D-08 register — committed first so every sanctioned `--update` had a pre-declared entry)

## Files Created/Modified
- `formatter/layout.mbt` - `flink_statement_covered` predicate, `first_child_element` helper, `layout_statement` covered-family gate, 15 Flink-only `clause_breaks` arms (shared Doris arms untouched)
- `parity/flink_format_test.mbt` - NEW flink-format snapshot namespace: 24 fixtures (22 positive + 2 unsafe refusal), per-fixture snapshot tests, oracle harness (idempotence/reparse/offsets/refusal), covered-set completeness probe, refusal oracle
- `parity/moon.pkg` - added `fathom/sql/formatter` and `fathom/sql/syntax` imports for the blackbox probe
- `parity/__snapshot__/flink-format.*.json` - 22 frozen canonical-format snapshots (new independent namespace)
- `.planning/phases/13-toolchain-and-editor-packaging/approved-changes.md` - D-08 register pre-declaring the flink-format namespace + covered-family gate behavior

## Decisions Made
- Reuse the shared Doris clause_breaks arms for the six shared families rather than duplicating Flink-specific tables; add per-family arms only for the 15 Flink-only families. This keeps Doris output byte-identical (PARITY-01) while giving every covered Flink family an explicit (non-`_ => []`) arm.
- Route the programming-gap refusal through the EXISTING `Layout.failed` → `FATHOM-FORMAT-001` channel (format.mbt:48-52). No new result type; `FormatResult` (error.mbt) unchanged.
- Made `flink_statement_covered` public and added the parity imports so the completeness probe enumerates and machine-checks the covered set directly (the plan's flagged-unverified TOOL-01 probe) instead of hand-maintaining a second list.
- Approved-changes register entry created in Task 1 (before the first `--update`) rather than Task 3: D-08 requires the entry to be committed before any sanctioned update, and Tasks 1-2 already generate snapshots.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] parity/moon.pkg missing formatter/syntax imports for the machine-checked probe**
- **Found during:** Task 1 (covered-set probe)
- **Issue:** The plan's must-have flagged-unverified probe requires a test that machine-checks `flink_statement_covered` against the parser's emit set, and the Task 2 acceptance literally asserts its return values for specific kinds. parity is a blackbox executable package that did not import `formatter`/`syntax`, so the direct predicate check was impossible.
- **Fix:** Added `fathom/sql/formatter @formatter` and `fathom/sql/syntax @syntax` to `parity/moon.pkg` imports (the plan's `files_modified` list did not include this config file).
- **Files modified:** parity/moon.pkg
- **Verification:** `moon test --target native --package parity` compiles and the completeness probe passes.
- **Committed in:** b21a82d (Task 1 commit)

**2. [Rule 3 - Blocking] `flink_statement_covered` made pub for direct probe access**
- **Found during:** Task 1 (covered-set probe)
- **Issue:** The plan's completeness probe (must-have flagged-unverified) needs to call the predicate; the sketch's `fn flink_statement_covered` was package-private.
- **Fix:** Declared it `pub fn` (formatter is a library package; no API surface change beyond the predicate becoming callable).
- **Files modified:** formatter/layout.mbt
- **Verification:** Probe asserts the 20-family covered set and the 7 clause-level kinds correctly.
- **Committed in:** b21a82d / 0ea6044

**3. [D-08 ordering] approved-changes.md register created in Task 1 instead of Task 3**
- **Found during:** Task 1 (before the first sanctioned `--update`)
- **Issue:** The plan lists the register creation under Task 3, but Tasks 1-2 already run `moon test --update` to generate snapshots, and D-08 requires the register entry to be committed BEFORE any sanctioned update. Creating it in Task 3 would have violated the hard gate.
- **Fix:** Created and committed `.planning/phases/13-toolchain-and-editor-packaging/approved-changes.md` as the first plan commit (8e64bc3), pre-declaring the flink-format namespace + covered-family gate behavior.
- **Verification:** Every `--update` run afterwards touched ONLY `flink-format.*` files (verified via `git status --short parity/__snapshot__`).
- **Committed in:** 8e64bc3 (docs, before Task 1)

---

**Total deviations:** 3 auto-fixed (2 Rule 3 blocking, 1 D-08 ordering alignment)
**Impact on plan:** All necessary for the machine-checked probe and the D-08 hard gate. No scope creep — no new runtime behavior beyond the plan's contract.

## Issues Encountered
- MoonBit `for` loops do not support tuple destructuring in the iterator (`for (a, b) in arr` is a parse error); rewrote the three probe loops to `for pair in arr { let (a, b) = pair ... }`.
- MoonBit blackbox-test packages report benign `unused_package` warnings for imports used only from `_test.mbt` files (pre-existing pattern in parity; `@formatter`/`@syntax`/`@utf8`/`@printer`). Not task-caused; no action taken.
- A temporary probe file (`parity/zz_probe_refusal_test.mbt`) was left by a `rm` that prompted for confirmation; removed with `rm -f` before the final gate.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- The flink-format snapshot namespace and oracle are the reference for 13-02 (Flink completion) and the 13-04 wire surface, which can reuse the same `format_with_ids` path.
- The covered-family gate means any future Flink statement family added to the parser MUST be added to `flink_statement_covered` + `clause_breaks` or it will refuse — the completeness probe machine-checks this.
- Doris baseline remains frozen (455 snapshots, 0 drift); `--update` remains excluded from CI.

---
*Phase: 13-toolchain-and-editor-packaging*
*Completed: 2026-08-10*

## Self-Check: PASSED
- Files verified: 13-01-SUMMARY.md, approved-changes.md, formatter/layout.mbt, parity/flink_format_test.mbt, 22 flink-format snapshots.
- Commits verified: 8e64bc3 (register), b21a82d (Task 1), 0ea6044 (Task 2), 369aa19 (Task 3).
- Gates: moon test --target native --package test --package formatter --package parity --package api = 750 passed (no --update); scripts/diff_parity.py --frozen-only = 455 snapshots, 0 differences; scripts/check_naming.py clean; git status --short parity/__snapshot__ empty (all flink-format.* committed).
