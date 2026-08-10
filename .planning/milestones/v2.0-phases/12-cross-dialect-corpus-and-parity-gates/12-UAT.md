---
status: complete
phase: 12-cross-dialect-corpus-and-parity-gates
source: [12-VERIFICATION.md]
started: 2026-08-09T00:00:00Z
updated: 2026-08-09T00:00:00Z
---

## Current Test

[testing complete — all flagged probes confirmed]

## Tests

### 1. CORPUS-01 release-pinned Flink corpus manifest — CONFIRMED
expected: |
  The release-pinned Flink corpus manifest (parity/fixtures/flink/manifest.tsv,
  110 rows, 19 columns) records release/tag/commit, Calcite version/config,
  source URL/heading, retrieval date, hash, expected status, and all 6 categories;
  verify_corpus.py --check enforces it offline; generic SQL acceptance is never
  reported as Flink engine support.
result: pass
decision: |
  CONFIRMED — direct gate execution this session: verify_corpus.py --check exit 0
  (110 rows, header, PINS vs dialect/flink.mbt, 6-category enum
  positive 49 / negative 25 / recovery 17 / planner-prerequisite 13 /
  known-limitation 3 / catalog-prerequisite 3, expected-status, fixture sha256,
  snapshot completeness, 104 archive sha512 re-verified). Semantic distinction
  enforced by generate_corpus_report.py --check (parser-accepted 68 vs
  engine-semantic-prerequisite 19 vs engine-supported 49 positive-only).

### 2. PARITY-01 Doris frozen diff harness — CONFIRMED
expected: |
  diff_parity.py --frozen-only regenerates the snapshot tree, fails (exit 1) on
  ANY difference, and consults NO register; Doris 2.1/3.x/4.x stays equal to the
  frozen baseline; intentional changes require a pre-committed register entry.
result: pass
decision: |
  CONFIRMED — diff_parity.py --frozen-only exit 0 (570/570 regenerated,
  433 snapshots, 0 frozen-vs-current differences, zero residue); executor
  documented injected-drift exit 1 and register-NOT-consulted semantics
  (source :19-23); restore guarantee on failure/SIGTERM verified.

### 3. PARITY-02 cross-backend byte parity — CONFIRMED
expected: |
  The same fixture produces byte-identical serialized results, diagnostics,
  spans, and lossless replay across Native, JavaScript, and linear-Wasm;
  CI runs the three-target matrix including js.
result: pass
decision: |
  CONFIRMED — compare_backends.py exit 0: native/js/wasm all PASS 570/570 with
  IDENTICAL snapshot-tree sha256 digest (5e9bb887e71ddc814d7cd86b4f0b0222352800ace927e20cdabd21057e22020c);
  CI linear-wasm-parity job now runs moon test --target js --package parity.

### 4. PARITY-03 offline gate concurrency safety — CONFIRMED
expected: |
  An interrupted or concurrent gate run leaves no partial state and cannot
  fabricate a pass; verify_corpus.py and compare_backends.py are read-only over
  pinned artifacts; diff_parity.py restores the committed snapshot tree on any
  failure or SIGTERM/SIGINT.
result: pass
decision: |
  CONFIRMED — verify_corpus.py/compare_backends.py are read-only (no mutation of
  parity/__snapshot__; compare_backends verifies digest before/after);
  diff_parity.py restore lifecycle (source :68,94,105) restores the committed
  tree on failure/SIGTERM — executor documented the SIGTERM mid-regeneration
  restore test (exit 2 + tree intact). Parallel gate runs are mutually
  non-interfering because the mutating gate (diff_parity) is CI-serialized and
  the read-only gates hold no state.

## Summary

total: 4
passed: 4
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
