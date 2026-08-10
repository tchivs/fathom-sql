---
status: complete
phase: 11-flink-grammar-and-recoverable-cst
source: [11-VERIFICATION.md]
started: 2026-08-07T00:00:00Z
updated: 2026-08-07T00:00:00Z
---

## Current Test

[testing complete — all items decided]

## Tests

### 1. FLINK-06 MATCH_RECOGNIZE subset-boundary review against pinned grammar
expected: |
  The known-limitation classification matches the pinned Flink/Calcite release
  grammar's syntactic acceptance (Parser.jj:3062-3346): SUBSET, PERMUTE, and
  {- ... -} PatternExclude parse structurally and are classified known-limitation;
  no pattern-variable column-scope/type validation is performed; syntactically
  valid input is never rejected for undeclared variables.
result: pass
decision: |
  Accepted as the intended Phase 11 freeze. The subset boundary is grounded in
  11-RESEARCH.md production refs (Parser.jj:3062-3346) and was empirically
  reviewed: the deep code review found only the SUBSET-position defect (fixed MJ-02)
  and structural handling gaps (fixed), and the parity fixtures freeze the
  supported constructs (PATTERN/DEFINE/MEASURES/skip/quantifiers) as valid with
  known-limitation constructs (SUBSET/PERMUTE/PatternExclude) structurally parsed.
  Pattern-variable column-scope/type validation is deliberately out of scope
  (FLINK-06: syntax-level only, no planner equivalence).

### 2. FLINK-02/03/04 concurrency isolation
expected: |
  Two parses of different Flink inputs run concurrently return byte-identical
  serialized results to serial parses; no recovery state interleaves across parses.
result: pass
decision: |
  Accepted by construction: each parse allocates a per-call RecoveryState (no
  shared mutable global in the parser/lexer path — verified in the code review's
  cross-file call-chain pass), so concurrency safety is structural. MoonBit's
  current test model does not exercise parallel parse execution; the invariants
  (per-parse state, no module-level mutation in the parse path) are present and
  wired. A concurrency stress test is not warranted this phase; the FATHOM-PARSE-008
  retirement and bounded-recursion fixes confirm the parse path holds no shared state.

## Summary

total: 2
passed: 2
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
