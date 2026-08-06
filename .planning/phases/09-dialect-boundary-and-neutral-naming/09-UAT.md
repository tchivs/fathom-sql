---
status: testing
phase: 09-dialect-boundary-and-neutral-naming
source: [09-VERIFICATION.md]
started: 2026-08-07T00:00:00Z
updated: 2026-08-07T00:00:00Z
---

## Current Test

number: 1
name: Decide the empty-Flink-input contract
expected: |
  Current code publishes an empty diagnostics array for a zero-byte document with
  dialect=flink over LSP. The flagged probe (DIALECT-03 empty) asserted FATHOM-PARSE-008
  "never a silent empty success"; the executor documented mutual exclusion with the
  single-router prohibition (WINDOWS.md #4, 09-02 decisions). Accept the documented
  deviation as the Phase 9 contract, or schedule enforcement in a later phase.
awaiting: user response

## Tests

### 1. Decide the empty-Flink-input contract
expected: |
  Open a zero-byte document with dialect=flink over LSP (or call
  parse_flink_not_implemented(b"", ...)) and confirm the intended behavior.
  Both alternatives (silent-empty for Doris-parity vs FATHOM-PARSE-008 for
  no-silent-success) are defensible and mutually exclusive under the current
  single-router design; the decision was deliberately deferred out of the
  plan's acceptance criteria.
result: [pending]

### 2. Live-host VS Code/IntelliJ dialect-selection UX (deferred to Phase 13)
expected: |
  Real Web/Monaco/VS Code/IntelliJ artifact smoke for explicit dialect selection
  and config precedence, per Phase 13 SC4 and its Validation. Phase 9 scope
  covers the host code paths (initializationOptions, fathom.* config keys,
  extension identity) which are verified; live-editor UX acceptance belongs to
  Phase 13.
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
