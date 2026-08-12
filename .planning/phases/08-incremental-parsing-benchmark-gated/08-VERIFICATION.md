---
phase: 08-incremental-parsing-benchmark-gated
verified: 2026-08-12T10:30:00Z
status: passed
score: 8/8 must-haves verified
behavior_unverified: 0 # No runtime state-transition/cancellation/ordering invariants in this phase — the deliverable is a benchmark harness + evidence record, verified by reading the code and evidence artifacts
overrides_applied: 0
gaps: []
deferred: []
---

# Phase 8: Incremental Parsing (Benchmark-Gated) — Verification Report

**Phase Goal:** 仅当 `moon bench` 证明整文档重解析是可测的延迟瓶颈时,交付有界增量解析与定向 CST 重构;否则以证据 descope 并记录。
**Verified:** 2026-08-12
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

The phase goal is a **benchmark-gated, two-branch outcome**: implement incremental parsing (branch B) **only if** `moon bench` demonstrates whole-document reparse is a measurable latency bottleneck; otherwise descope with documented evidence (branch A, the SC1 "or" clause). The benchmark gate fired **branch A** — and the descope-with-evidence outcome is complete and traceable. Goal-backward check: the condition that would trigger implementation (≥100 KB editor-scale median > 50 ms **or** superlinear growth) was measured and **not** met (100.39 KB median 27.47 ms; per-doubling factors ×2.00/×2.04/×2.10 → linear). Therefore the legally required outcome for this phase is the descope record — which exists across all traceability surfaces with the benchmark evidence documented.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SC1 gate harness established: `bench/` package exists with `@bench` functions calling `@api.parse` (api.mbt:431) and `@parser.parse_with_limits_context` (parser.mbt:4275), results consumed via `keep()` to prevent DCE | ✓ VERIFIED | `bench/moon.pkg` (pkgtype library; imports @api/@parser/@source measured surface; never imports `incremental/`); `bench/bench.mbt` — all 9 `@bench.T` closures wrap the parse in `it.bench(name=…, fn() { it.keep(…) })`. Review (08-REVIEW.md) independently confirmed keep() at every closure and byte-accurate embedded fixtures |
| 2 | 08-BENCHMARK.md contains the five gate elements: fixture list, input sizes 25/50/100/200 KB, median/p95, gate conclusion, toolchain record | ✓ VERIFIED | §1 Fixture List (18-entry embedded corpus pool + 3 corpus baselines + 2 pure-core aux), §2 Input Sizes (25.14/50.23/100.39/200.33 KB), §3 Median/p95 (native release), §4 门禁结论, §5 Toolchain Record |
| 3 | Measured numbers honestly recorded: ≥100 KB median 27.47 ms ≤ 50 ms; linear scaling ×2.00/×2.04/×2.10 per doubling; branch decision A explicitly stated; no fabricated numbers | ✓ VERIFIED | 08-BENCHMARK.md §3/§4. Medians 6.72→13.46→27.47→57.76 ms scale linearly (×2.003/×2.041/×2.103). The 200.33 KB median (57.76 ms) exceeds 50 ms and is **openly disclosed** in §4 with a transparency note (2× linear-extrapolation confirmation; linear model ≈55 ms) — the opposite of fabrication. Branch A stated in §4 verdict and in 08-01-SUMMARY ("FIRED BRANCH: A (descope)") |
| 4 | Descope recorded in REQUIREMENTS.md: EDIT-01 marked `[x]` + DESCOPED WITH EVIDENCE + 08-BENCHMARK.md reference | ✓ VERIFIED | REQUIREMENTS.md:34 — `- [x] **EDIT-01**: … — DESCOPED WITH EVIDENCE 2026-08-12: moon bench gate showed editor-scale (≥100KB) whole-doc reparse median 27.47ms (≤50ms threshold) with linear scaling (2.00×/2.04×/2.10× per doubling), no superlinear signs — see .planning/phases/08-incremental-parsing-benchmark-gated/08-BENCHMARK.md`. Traceability table: `EDIT-01 | Phase 8 | Descoped with evidence (see …/08-BENCHMARK.md)` |
| 5 | ROADMAP.md Phase 8 status and STATE.md descope record updated | ✓ VERIFIED | ROADMAP.md:119 `**Status:** Complete — descoped with evidence (see 08-BENCHMARK.md)`; ROADMAP SC1 carries the "or the requirement is descoped with the benchmark evidence documented" clause. STATE.md:280 `| descope_evidence | EDIT-01 incremental parsing — benchmark-gated descope | closed 2026-08-12 — 08-BENCHMARK.md (≥100KB median 27.47ms, linear, branch A) |` |
| 6 | Zero incremental parsing code: no `incremental/` package; `parser/` untouched | ✓ VERIFIED | `glob incremental/**` → Path not found. `parser/` intact (parser.mbt, flink_grammar.mbt, moon.pkg; parse_with_limits_context@4275, ParserLimits, ParseMode all present). bench/ imports measured surface only. Reviewer confirmed change set confined to `bench/` + planning docs (modified: []); orchestrator verified no regression |
| 7 | Gate interpretation pinned in the evidence: boundary-input reading of the 50 ms threshold + methodology bias note | ✓ VERIFIED | 08-BENCHMARK.md §4 carries both review-closure notes: **Gate Interpretation Note (WR-02)** — threshold evaluated at the ≥100 KB editor-scale boundary input (100.39 KB → 27.47 ms); 200 KB is a 2× linear-confirmation; decisive negative = absence of superlinear growth. **Methodology bias note (WR-01)** — recovery-tail fixture in the pool makes measured latency an upper bound for the normal path; branch-A verdict conservative |
| 8 | No regression / no production source changed | ✓ VERIFIED | External (orchestrator-run): test 209/209, api 636/636, fathom-sql 37/37, parity 605/605, bench builds. Read-only spot-check: bench/ is the only code surface added; production sources (parser/, api/, lexer/, dialect/, source/, printer/, syntax/) unchanged per 08-REVIEW.md and SUMMARY `modified: []` for both plans |

**Score:** 8/8 truths verified (0 present, behavior-unverified)

### Deferred Items

None — the branch-A descope is the phase's required outcome, not a deferred gap. EDIT-01's future re-entry is tracked separately as `EDIT-FUTURE-01` in the ROADMAP backlog (post-v2 candidates), outside this phase.

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `bench/moon.pkg` | library package; measured import surface = @api/@parser/@source; never incremental/ | ✓ VERIFIED | Declares `pkgtype(kind: "library")`; imports @api/@parser/@source (+ documented harness imports @dialect/@bench/@buffer, an auto-fixed deviation recorded in 08-01-SUMMARY; no incremental/) |
| `bench/bench.mbt` | `@bench` suite: 25/50/100/200 KB gradient + corpus baselines + pure-core aux; keep() DCE guards | ✓ VERIFIED | 9 `@bench.T` functions (parse_full_editor_scale_{25k,50k,100k,200k}, parse_full_{select_industrial,script_multi_statement,ddl_create_table}, parse_core_editor_scale_{100k,200k}); every timed closure ends `it.keep(…)` |
| `bench/build_editor_scale.mbt` | `build_editor_scale(size_bytes) -> Bytes`; embedded corpus pool; runtime never reads disk | ✓ VERIFIED | 18 embedded `Bytes` literals (byte-identical to committed corpus per review); cyclic concatenation to ≥ target size ending on statement boundary |
| `08-BENCHMARK.md` | Five elements + branch decision + toolchain record + interpretation notes | ✓ VERIFIED | §§1-5 complete; branch A verdict; Gate Interpretation Note + Methodology bias note pinned |
| `COVERAGE.md` | api-coverage declaration | ✓ VERIFIED | Contains "No external API integration: Phase 8 adds an internal benchmark package (bench/) … No external API/SDK/service is integrated." |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | -- | ------ | ------- |
| `bench/bench.mbt` | `@api.parse` | `it.bench(name=…, fn() { it.keep(@api.parse(raw, options)) })` | ✓ WIRED | api.mbt:431 `pub fn parse` verified; result consumed by keep() (DCE guard) |
| `bench/bench.mbt` | `@parser.parse_with_limits_context` | pure-core aux closure with `@source.SourceText` + `@dialect.DialectContext` + `ParserLimits::default()` | ✓ WIRED | parser.mbt:4275 verified; ParseMode::Editor (parser.mbt:3-5), ParserLimits::default (parser.mbt:41-45) verified |
| `bench/build_editor_scale.mbt` | committed corpus fixtures | authoring-time embedded `Bytes` literals | ✓ WIRED | `corpus/doris-4.x/{select-industrial,script-multi-statement,ddl-create-table}.sql` exist; reviewer verified all 18 literals byte-identical to corpus files |
| `08-BENCHMARK.md` | `moon bench -p bench --target native --output-json --release` output | recorded JSON summaries (@BATCH_BENCH payloads), exit 0, 9/9 | ✓ WIRED | §3 documents the exact command and capture method; toolchain record §5 documents `moon --version` (moon 0.1.20260724 / moonc v0.10.5+5e7afb0c0) |
| traceability entries (REQUIREMENTS/ROADMAP/STATE) | 08-BENCHMARK.md measured numbers | explicit citations with 27.47ms / 2.00×/2.04×/2.10× | ✓ WIRED | All three descope records cite the in-repo benchmark file and its real figures — no fabricated evidence (D-17) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `bench/build_editor_scale.mbt` | `editor_scale_pool` (18 embedded `Bytes` literals) | `corpus/doris-{2.1,3.x,4.x}/*.sql` (embedded at authoring time) | ✓ Real corpus bytes | ✓ FLOWING |
| `bench/bench.mbt` → `@api.parse` | `raw` = `build_editor_scale(size_bytes)` | embedded corpus pool → synthetic doc | ✓ Real parse path (envelope serialization included) | ✓ FLOWING |
| `08-BENCHMARK.md` §3 medians | recorded from `moon bench` JSON summaries | gate command execution (exit 0, 9/9) | ✓ Non-zero, monotonically growing with size (6.72→13.46→27.47→57.76 ms) — DCE smoke passes | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Gate command executes and produces structured JSON | `moon bench -p bench --target native --output-json --release` | exit 0, 9/9 benchmarks (recorded in 08-BENCHMARK.md §3/§5 and 08-01-SUMMARY; orchestrator independently confirmed bench builds and full suites pass) | ✓ PASS (recorded evidence; not re-run in this read-only verification) |
| No dead-code elimination (Pitfall 3) | median-non-zero-and-growing smoke | 6.72 → 13.46 → 27.47 → 57.76 ms, all non-zero, monotonic | ✓ PASS |
| @bench availability on pinned toolchain (Pitfall 1) | `moon bench` probe | state 1 (available, no degradation); `@bench.T` + `it.bench`/`it.keep` from `moonbitlang/core/bench` | ✓ PASS |

### Probe Execution

No shell probes (`scripts/*/tests/probe-*.sh`) are declared by or conventional to this phase — the gate probe is the `moon bench` harness itself, whose execution and output are recorded in 08-BENCHMARK.md and independently confirmed building by the orchestrator.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| EDIT-01 | 08-01 / 08-02 | Editor can use bounded incremental parsing and targeted CST refactors without reparsing the full document — only when `moon bench` demonstrates a measurable latency bottleneck | ✓ SATISFIED (descoped with evidence — SC1 "or" clause) | REQUIREMENTS.md:34 `[x]` + DESCOPED WITH EVIDENCE + 08-BENCHMARK.md citation; traceability `Descoped with evidence`; ROADMAP SC1 allows "or the requirement is descoped with the benchmark evidence documented"; no orphaned requirements (EDIT-01 maps to Phase 8 only) |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| — | — | No TBD/FIXME/XXX/HACK/PLACEHOLDER markers | — | None found in `bench/` or phase artifacts |
| — | — | No stub returns (`return null`, empty handlers, hardcoded empty data) | — | None found; all @bench closures call real parse paths and keep() results |

### Human Verification Required

None. This phase is a benchmark-gated **descope-with-evidence** — the deliverable is the measurement harness and the evidence record, both fully verifiable by reading the code and artifacts. No runtime state-transition/cancellation/ordering invariant is asserted. The 200 KB (>50 ms) disclosure and the boundary-input Gate Interpretation Note are documented judgments already resolved through review (WR-02) and pinned in the evidence record; they do not change the branch-A outcome (both D-02 triggers unmet at the ≥100 KB boundary; no superlinear growth). For optional independent reproduction, the gate command is `moon bench -p bench --target native --output-json --release` (recorded in 08-BENCHMARK.md §5).

### Gaps Summary

No gaps found. All 8 must-have truths verify against the actual code and evidence artifacts:

1. The `bench/` harness exists, calls the real parse surfaces (`@api.parse` api.mbt:431; `@parser.parse_with_limits_context` parser.mbt:4275), and consumes results via `keep()` (no DCE).
2. 08-BENCHMARK.md contains all five elements plus the branch decision and toolchain record.
3. The ≥100 KB median (27.47 ms ≤ 50 ms) and linear scaling (×2.00/×2.04/×2.10) are recorded; the branch-A verdict is explicit; the >50 ms 200 KB reading is openly disclosed, not hidden.
4-5. The descope is recorded in all three traceability surfaces (REQUIREMENTS/ROADMAP/STATE) with citations to the in-repo benchmark file.
6. Zero incremental code exists (`incremental/` absent; `parser/` untouched).
7. The gate interpretation and methodology bias are pinned in the evidence.
8. No regression (orchestrator-verified suites) and no production source changes.

---

_Verified: 2026-08-12_
_Verifier: Claude (gsd-verifier)_
