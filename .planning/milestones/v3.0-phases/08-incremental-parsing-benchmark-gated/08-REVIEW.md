---
phase: 08-incremental-parsing-benchmark-gated
reviewed: 2026-08-12T09:30:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - bench/bench.mbt
  - bench/build_editor_scale.mbt
  - bench/moon.pkg
findings:
  critical: 0
  warning: 2
  info: 4
  total: 6
status: issues
---

# Phase 8: Code Review Report — bench/ Benchmark Harness (EDIT-01 Gate)

**Reviewed:** 2026-08-12T09:30:00Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues

## Summary

Reviewed the new `bench/` MoonBit package (bench.mbt, build_editor_scale.mbt, moon.pkg) — the EDIT-01 benchmark-gate harness that produced the Branch-A (descope) evidence in 08-BENCHMARK.md. The review is read-only (no bash); API signatures were cross-checked against `api/api.mbt`, `parser/parser.mbt`, `source/source.mbt`, `dialect/dialect.mbt`, and `/opt/moonbit/lib/core/bench|buffer`.

**Verified sound (no findings):**

1. **DCE avoidance — PASS.** All 9 `@bench` closures consume the parse result through `it.keep(...)` (`bench.mbt:32,38,44,50,58,64,70,84,96`). `Bench::keep` moves the value into a `@ref` stored on the captured `Bench`, so the parse cannot be eliminated. The recorded medians (6.72 → 13.46 → 27.47 → 57.76 ms, 08-BENCHMARK.md:66-67) empirically confirm the measured path is not dead-code-eliminated. Setup (`build_editor_scale`, `ParseOptions::new`, `SourceText::new`, `ParserLimits::default`) runs in the test body, outside the timed closure — correct.
2. **Embedded fixtures byte-accurate — PASS.** All 18 embedded `Bytes` literals in `build_editor_scale.mbt` were compared line-for-line against the committed `corpus/doris-{2.1,3.x,4.x}/*.sql` files (each corpus file read in full). All are byte-identical. Runtime never reads disk.
3. **Size gradient reaches 100/200 KB — PASS.** `build_editor_scale` (`build_editor_scale.mbt:96-107`) appends pool statements until `written >= size_bytes`, so the output is guaranteed ≥ the target. Recorded actuals (102,796 B ≥ 102,400 B; 205,137 B ≥ 204,800 B) satisfy the bound; pool-total arithmetic (~11.6 KB over the 18 entries) is consistent with the recorded sizes and with the ~2/4/9/18 recovery-tail occurrences implied by the cyclic composition.
4. **No production/parser code changed.** The change set is confined to the three `bench/` files plus planning docs/COVERAGE.md (per 08-01-SUMMARY commit list `d180c16, f666d90, 4dd08be, 587b6aa`; `modified: []`). All parser/lexer/api/dialect files are separate and untouched; the review scope confirms only `bench/` artifacts.
5. **Dual-measurement methodology sound.** The aux path (`parse_with_limits_context`, parser.mbt:4275) builds the CST and `it.keep` retains it — it measures parse, not serialization. The `feature_introduction: ""` in `bench_core_context()` (bench.mbt:24) is a **non-issue**: the parser gates features off `context.profile_id` (`DorisProfile::from_id(state.context.profile_id)`, parser.mbt:381), never the `feature_introduction` string, so the manual context parses identically to the validated `ParseOptions` context. Envelope serialization cost at 100 KB (~0.33 ms, ~1.2%) matches the code shape (`api.parse` adds `primitive_node`/`primitive_diagnostic`).

Two WARNINGs concern **benchmark-evidence accuracy and gate-record precision** rather than code correctness, plus four INFO-level robustness/maintainability notes.

## Warnings

### WR-01: Synthetic editor-scale documents contain recovery-path content, contradicting the documented "normal parse path, not recovery" claim

**File:** `bench/build_editor_scale.mbt:16-17, 71, 91-93`; `08-BENCHMARK.md:40-43`
**Issue:** The pool's first entry `corpus_select_industrial_4x` is a byte-accurate copy of `corpus/doris-4.x/select-industrial.sql`, whose final statement is the intentional recovery fixture `SELECT k +` (incomplete expression). Because the pool cycles, every synthetic 25/50/100/200 KB document contains one incomplete statement per ~11.6 KB cycle — approximately 2, 4, 9, and 18 occurrences respectively. Yet the function doc (`build_editor_scale.mbt:91-93`) and 08-BENCHMARK.md §2 (lines 40-43) both assert the synthetic docs "exercise normal parse paths, not recovery." That is inaccurate: the measured latency repeatedly includes panic-mode/error-recovery cost, not only the normal parse path. This does not threaten the descope verdict (recovery is not cheaper than normal parse, so including it makes the 27.47 ms reading conservative), but the evidence record mischaracterizes its own input, which weakens the "evidence-driven" claim of the gate.
**Fix:** Either remove the recovery-tail fixture from the editor-scale pool (e.g., substitute a non-recovery SELECT copy — note `corpus/doris-4.x/malformed-recovery.sql` is already excluded from the pool) so the synthetic docs truly exercise the normal parse path, or correct the docs to state that the pool includes a periodic recovery-path statement (arguably realistic for editor input) and quantify it (≈1 per cycle, ~2/4/9/18 occurrences in the gradient).

### WR-02: D-02 threshold wording ("≥100 KB median > 50 ms") is inconsistent with the 200 KB measurement; gate verdict depends on an interpretation that is only documented in the evidence, not the decision

**File:** `08-BENCHMARK.md:59, 78-90`; decision `D-02` in `08-CONTEXT.md`
**Issue:** D-02 states branch B fires when an "editor-scale (≥100 KB) whole-document reparse median > 50 ms." The 200.33 KB input is an editor-scale (≥100 KB) document, and its median is **57.76 ms > 50 ms** (08-BENCHMARK.md:59) — a literal reading of D-02 fires branch B. The gate verdict (Branch A) instead evaluates the threshold at the 100.39 KB boundary input (27.47 ms) and treats 200 KB as a scaling probe. The transparency note (lines 87-90) discloses this and the linear model (≈55 ms predicted) supports A, so the conclusion is defensible — but the boundary-input interpretation is not recorded in the locked decision (D-02) and is at risk of being misread in the 08-02 descope record that propagates this decision.
**Fix:** In the 08-02 descope record (and, if convenient, REQUIREMENTS.md/ROADMAP EDIT-01 note), pin the interpretation explicitly: "the 50 ms threshold is evaluated at the ≥100 KB boundary input (100 KB); larger sizes are measured only to detect superlinear growth," and reference the linear-model consistency of the 200 KB point. This removes the only non-mechanical step in an otherwise mechanical D-02 application.

## Info

### IN-01: `bench/build_editor_scale.mbt` is not in the naming-gate file-scoped exemption; header prose itself contains a DORIS- token

**File:** `bench/build_editor_scale.mbt:11-14`; `scripts/check_naming.py:136-138`
**Issue:** The NAMING-GATE CONSTRAINT comment implies the file enjoys the same `EMBEDDED_FIXTURE_FILES` exemption as `parity/baseline_test.mbt`, but `scripts/check_naming.py` only lists `parity/baseline_test.mbt` and `test/formatter_test.mbt`. Today the only DORIS- token is `DORIS-03`, which the `DORIS-(?!0\d)` regex exempts regardless of file scope, so the gate passes — but any future `DORIS-10`/`DORIS-0X`-shaped text would be flagged. Also, the header comment itself contains `DORIS-03` outside the fixture literals, slightly contradicting its own "lives only inside the byte-embedded fixture literals" statement.
**Fix:** Add `"bench/build_editor_scale.mbt"` to `EMBEDDED_FIXTURE_FILES` (keeping the same header-constraint discipline), and reword the header so the DORIS- reference is only inside a fixture literal (or explicitly call out the lookahead exemption for the header's own mention).

### IN-02: No automated byte-accuracy check links the embedded pool to the committed corpus (drift risk)

**File:** `bench/build_editor_scale.mbt:3-5`; `08-BENCHMARK.md:9-11`
**Issue:** The embedded literals are currently byte-accurate (verified this review), but unlike `parity/baseline-hashes.txt` (which pins corpus bytes), nothing at build/test time asserts `embedded == read(corpus)`. A future corpus edit would silently diverge the benchmark inputs from "the exact committed corpus bytes" claimed in 08-BENCHMARK.md, invalidating reproducibility.
**Fix:** Add a small parity test (e.g., in `parity/` or `bench/`) that hashes each embedded pool entry against the pinned corpus file (reuse `parity/baseline-hashes.txt`), or at minimum record the corpus commit SHA in a comment.

### IN-03: Pool redundancy — the 3.x and 2.1 CREATE TABLE fixtures are byte-identical in body

**File:** `bench/build_editor_scale.mbt:61-62, 67-68`
**Issue:** `corpus_ddl_create_table_3x` and `corpus_ddl_create_table_21` embed byte-identical SQL bodies (only the header comments differ: "3.x" vs "2.1"). Two of the 18 pool entries are therefore duplicates, slightly over-weighting synthetic docs toward CREATE TABLE content. Harmless for the gate, but inflates the pool and the "18 distinct corpus statements" impression.
**Fix:** Drop one of the two duplicates (or keep both and note the redundancy in the pool comment).

### IN-04: Hardcoded "4.x" profile + `panic()` on setup error aborts the entire bench run

**File:** `bench/bench.mbt:11-16, 77-79, 89-91`
**Issue:** `bench_options()`/`bench_core_context()` hardcode `"4.x"`, and setup errors (`ParseOptions::new` Err, `SourceText::new` Err) call `panic()` — a single failed setup aborts all 9 benchmarks rather than skipping that one. Acceptable for a benchmark harness on a pinned profile, but fragile if the 4.x profile is ever renamed.
**Fix:** Optional — use `ParseOptions::for_profile(@dialect.DorisProfile::V4_X, ParseMode::Editor)` for the full path, and replace `panic()` with a skip/warn so one broken bench does not sink the suite.

---

_Reviewed: 2026-08-12T09:30:00Z_
_Reviewer: Claude (gsd-code-reviewer, BenchReviewer)_
_Depth: standard_

---

## Resolutions (applied 2026-08-12)

Both WARNINGs addressed in the evidence record (`08-BENCHMARK.md`), committed with the phase artifacts:

- **WR-01** — `08-BENCHMARK.md` §4 now carries a **Methodology bias note**: the embedded pool includes the recovery-tail fixture (`select-industrial.sql`), so synthetic docs cycle recovery-path content (~1 per ~11.6 KB cycle). The doc no longer claims "normal parse path only"; it states the recovery component makes the measured latency an **upper bound** for the normal path, so the branch-A (fast) verdict is conservative. No fixture change (re-running the gate for a bias that strengthens the verdict is not warranted).
- **WR-02** — `08-BENCHMARK.md` §4 now carries an explicit **Gate Interpretation Note**: D-02's 50 ms threshold is evaluated at the ≥100 KB editor-scale boundary input (100.39 KB → 27.47 ms); the 200.33 KB point (57.76 ms) is a 2× linear-extrapolation confirmation (linear model ≈55 ms, matches), and the decisive negative signal is the **absence of superlinear growth** (per-doubling ×2.00/×2.04/×2.10). The 08-02 descope record references this file, so the interpretation is pinned for downstream readers.
- **IN-01..04** — retained as noted (naming-gate exemption, embedded-vs-corpus byte-accuracy check, 3.x/2.1 duplicate pool entries, hardcoded 4.x + panic setup) — all non-blocking for a benchmark-only package; IN-02/IN-04 recorded as follow-ups in the SUMMARY.

