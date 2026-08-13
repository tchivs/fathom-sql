---
phase: 08-incremental-parsing-benchmark-gated
plan: 01
subsystem: testing
tags: [benchmark, moon-bench, editor-scale, reparse-latency, bench-gate, @bench]

requires: []
provides:
  - "bench/ MoonBit package (@bench) measuring whole-document reparse latency"
  - "08-BENCHMARK.md: five-element benchmark evidence + branch decision"
  - "COVERAGE.md: api-coverage declaration"
affects: [08-02-descope, 08-incremental-parsing-benchmark-gated, ROADMAP-Phase8]

actuals:
  tokens: 6500   # chars/4 over the realized diff (5 changed files, ~25.8 KB)
  tasks: 3
  commits: 5

tech-stack:
  added: ["@bench.T test-block mechanism + moon bench CLI (moonbitlang/core/bench)", "moon bench --output-json"]
  patterns:
    - "Pattern 2: dual measurement — @api.parse full path + @parser.parse_with_limits_context pure core"
    - "Embedded fixture discipline: corpus bytes embedded as Bytes literals at authoring time, runtime never reads disk"

key-files:
  created:
    - "bench/moon.pkg"
    - "bench/bench.mbt"
    - "bench/build_editor_scale.mbt"
    - ".planning/phases/08-incremental-parsing-benchmark-gated/08-BENCHMARK.md"
    - ".planning/phases/08-incremental-parsing-benchmark-gated/COVERAGE.md"
  modified: []

key-decisions:
  - "Benchmark gate verdict (D-02): >=100KB whole-document reparse median = 27.47 ms <= 50 ms with linear scaling (2.00x/2.04x/2.10x per doubling) -> Branch A (descope); EDIT-01 descoped with evidence, no incremental-parsing code"
  - "Fired branch: A (descope) — orchestrator routes follow-up to 08-02, NOT 08-03/08-04"
  - "@bench verified available on pinned moon 0.1.20260724; bench/ imports @dialect + @bench/@buffer beyond the plan's @api/@parser/@source core surface (required for the pure-core aux test and the harness itself)"

patterns-established:
  - "Benchmark function shape: `test \"bench <name>\" (it : @bench.T) { it.bench(name=..., fn() { it.keep(...) }) }` — verified against moonbitlang/core/bench on this toolchain"
  - "DCE guard: it.keep(parse_result) inside the timed closure prevents dead-code elimination"

requirements-completed: [EDIT-01]

coverage:
  - id: D1
    description: "bench/ MoonBit package with editor-scale synthetic inputs (25/50/100/200 KB) and @bench reparse-latency suite (full @api.parse path + pure-core aux)"
    requirement: "EDIT-01"
    verification:
      - kind: integration
        ref: "moon bench -p bench --target native --output-json --release (9/9 benchmarks pass, exit 0)"
        status: pass
    human_judgment: false
  - id: D2
    description: "08-BENCHMARK.md five-element evidence (fixture list, sizes, median/p95, gate conclusion, toolchain record) with branch decision A"
    requirement: "EDIT-01"
    verification:
      - kind: other
        ref: "grep median/p95/结论 .planning/phases/08-incremental-parsing-benchmark-gated/08-BENCHMARK.md"
        status: pass
    human_judgment: false
  - id: D3
    description: "COVERAGE.md api-coverage declaration (no external API integration)"
    verification:
      - kind: other
        ref: "grep 'No external API integration' .planning/phases/08-incremental-parsing-benchmark-gated/COVERAGE.md"
        status: pass
    human_judgment: false

duration: 41min
completed: 2026-08-12
status: complete
---

# Phase 8 Plan 1: Benchmark Gate Tracer Summary

**Benchmark gate evidence recorded — @bench + moon bench measured whole-document reparse latency on native across 25/50/100/200 KB; ≥100 KB median 27.47 ms ≤ 50 ms with linear scaling → Branch A (descope) fired.**

## FIRED BRANCH: A (descope)

**≥100 KB median that drove the decision: 27.47 ms** (100.39 KB synthetic editor-scale document, `@api.parse` full path, native release). D-02 threshold is > 50 ms; measured 27.47 ms is below it, and per-doubling latency ratios (2.00× / 2.04× / 2.10×) show linear, not superlinear, growth. EDIT-01 is **descoped with evidence** per ROADMAP Phase 8 SC1 — no incremental-parsing code is written. The orchestrator routes the follow-up plan to **08-02 (descope record)**, not 08-03/08-04 (incremental implementation).

## Performance

- **Duration:** ~41 min
- **Started:** 2026-08-12T08:25:00Z (approx)
- **Completed:** 2026-08-12T09:06:41Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Probed `@bench` + `moon bench --output-json` on pinned `moon 0.1.20260724` — **available** (state 1, no degradation; Pitfall 1 resolved).
- Built `bench/` package: `build_editor_scale(size_bytes)` over an 18-entry embedded corpus statement pool (runtime never reads disk) producing 25.14/50.23/100.39/200.33 KB editor-scale documents, plus a full `@bench.T` suite (4-size gradient + 3 corpus baselines + 2 pure-core aux measurements) with `keep()` DCE guards.
- Ran the gate: `moon bench -p bench --target native --output-json` exits 0, 9/9 benchmarks, medians non-zero and growing with size (DCE smoke passes).
- Recorded five-element evidence in `08-BENCHMARK.md` + branch decision + toolchain record; wrote `COVERAGE.md` api-coverage declaration.

## Task Commits

Each task was committed atomically:

1. **Task 1: probe @bench + scaffold bench/ package** - `d180c16` (feat)
2. **Task 2 (TRACER): editor-scale inputs + full reparse bench suite** - `f666d90` (feat)
3. **Task 3: gate evidence + COVERAGE.md + branch decision** - `587b6aa` (docs)

Additional commit: `4dd08be` (fix) — naming-gate prose constraint in the bench header (part of Task 2's deliverable). Plan metadata commit (this SUMMARY): `(docs)`.

## Files Created/Modified

- `bench/moon.pkg` - library package; imports @api/@parser/@source (+ @dialect for the pure-core aux surface, @bench/@buffer harness imports); never imports incremental/
- `bench/build_editor_scale.mbt` - `build_editor_scale(size_bytes) -> Bytes`; 18 embedded corpus statements covering comment headers, blank lines, multi-statement scripts, complex SELECTs, DDL/DML; ends on a statement boundary
- `bench/bench.mbt` - `@bench.T` suite: parse_full_editor_scale_{25k,50k,100k,200k}, parse_full_{select_industrial,script_multi_statement,ddl_create_table}, parse_core_editor_scale_{100k,200k}; `it.keep(...)` prevents DCE
- `.planning/phases/08-incremental-parsing-benchmark-gated/08-BENCHMARK.md` - five elements (fixture list, sizes, median/p95, gate conclusion, toolchain record) + branch decision A
- `.planning/phases/08-incremental-parsing-benchmark-gated/COVERAGE.md` - api-coverage declaration ("No external API integration")

## Decisions Made

- **Branch A (descope)** — mechanical application of locked D-02: ≥100 KB median (27.47 ms) ≤ 50 ms, linear scaling, no O(n²) signs. Recorded in 08-BENCHMARK.md; fired branch recorded here for orchestrator routing (08-02 descope, not 08-03/08-04).
- `moon bench` has no `--version` subcommand; toolchain record uses `moon --version` (moon 0.1.20260724) and `moonc v0.10.5+5e7afb0c0`.
- p95 reporting: the built-in `Summary` exposes `median`/`quartiles`/winsorized `max` (no explicit p95); `max` (5%-winsorized = 95th-percentile clamp) is recorded as the p95 proxy.
- js/wasm supplemental benches not run (D-01 "若可行"); native evidence satisfies the SC1 gate and the branch decision.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] @bench.T requires importing moonbitlang/core/bench (plan assumed built-in)**
- **Found during:** Task 1 (probe)
- **Issue:** The plan stated "@bench attribute 为工具链内置，无需 import"; in this toolchain `@bench.T` resolves only via `moonbitlang/core/bench` (verified against the core bench package source).
- **Fix:** Imported `"moonbitlang/core/bench" @bench` and `"moonbitlang/core/buffer" @buffer` in bench/moon.pkg; also imported `"fathom/sql/dialect" @dialect` because the pure-core aux test must construct a `@dialect.DialectContext` for `@parser.parse_with_limits_context` (no public accessor on ParseOptions). Core tested surface (@api/@parser/@source) is preserved; incremental/ is never imported.
- **Files modified:** bench/moon.pkg
- **Verification:** moon check 0 errors; gate command exit 0.
- **Committed in:** d180c16 (Task 1)

**2. [Rule 3 - Blocking] Naming gate flagged DORIS- prose in bench header**
- **Found during:** Task 3 (post-commit verification)
- **Issue:** scripts/check_naming.py flags `DORIS-(?!0\d)` outside embedded fixture literals; my header comment used "DORIS- text" in prose.
- **Fix:** Reworded the NAMING-GATE CONSTRAINT comment to avoid DORIS- prose; only the embedded `DORIS-03` token (exempt via lookahead) remains.
- **Files modified:** bench/build_editor_scale.mbt
- **Verification:** `python3 scripts/check_naming.py` → "ok: 655 product files scanned, zero forbidden naming remnants".
- **Committed in:** 4dd08be

**3. [Rule 3 - Blocking] `moon bench --version` does not exist**
- **Found during:** Task 1 (probe)
- **Issue:** The plan's toolchain record calls for `moon bench --version`; the subcommand rejects `--version` ("unexpected argument").
- **Fix:** Documented `moon bench` has no `--version`; toolchain record uses `moon --version`. No code change.
- **Verification:** 08-BENCHMARK.md §5 Toolchain Record.
- **Committed in:** 587b6aa (Task 3 doc)

---

**Total deviations:** 3 auto-fixed (all Rule 3 — blocking, resolved inline)
**Impact on plan:** All fixes were necessary to make the plan runnable on the pinned toolchain / pass the project gate. No scope creep; no architectural changes (Rule 4 not triggered).

## Issues Encountered

- The bench test executable aborts when run with no arguments; the generated driver requires a `file:start-end` arg. JSON summaries were captured by invoking `_build/native/release/bench/bench/bench.internal_test.exe "bench.mbt:0-9"` and parsing the `@BATCH_BENCH` payloads.
- Default (non-`--release`) `moon bench` is ~8% slower than `--release`; both modes yield the same gate conclusion (100 KB ≈ 27.5 / 30.5 ms). Release numbers are the recorded evidence.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `08-BENCHMARK.md` + this SUMMARY (fired branch A) give the orchestrator everything needed to route **08-02 (EDIT-01 descope record)**: update REQUIREMENTS.md/ROADMAP.md/STATE.md to mark EDIT-01 descoped-with-evidence (SC1), referencing 08-BENCHMARK.md.
- `bench/` remains a reusable measurement surface for any future performance work (reversible, D-01).
- No blockers.

## Self-Check: PASSED

All 6 deliverable files exist (bench/moon.pkg, bench/bench.mbt, bench/build_editor_scale.mbt, 08-BENCHMARK.md, COVERAGE.md, 08-01-SUMMARY.md); all task commits found (d180c16, f666d90, 4dd08be, 587b6aa).

---
*Phase: 08-incremental-parsing-benchmark-gated*
*Completed: 2026-08-12*
