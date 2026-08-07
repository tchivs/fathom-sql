---
status: complete
phase: 09-dialect-boundary-and-neutral-naming
source: [09-VERIFICATION.md]
started: 2026-08-07T00:00:00Z
updated: 2026-08-07T00:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Decide the empty-Flink-input contract
expected: |
  Open a zero-byte document with dialect=flink over LSP (or call
  parse_flink_not_implemented(b"", ...)) and confirm the intended behavior.
  Both alternatives (silent-empty for Doris-parity vs FATHOM-PARSE-008 for
  no-silent-success) are defensible and mutually exclusive under the current
  single-router design; the decision was deliberately deferred out of the
  plan's acceptance criteria.
result: pass
decision: "Accepted the documented deviation as the Phase 9 contract: empty input yields silent empty diagnostics for dialect parity with Doris (single-router statement split happens before dialect routing; FATHOM-PARSE-008 fires on every non-empty flink input). Enforcement of a dialect-aware empty-input diagnostic is tracked as a deferred follow-up (WINDOWS.md #4)."

### 2. Live-host VS Code/IntelliJ dialect-selection UX (deferred to Phase 13)
expected: |
  Real Web/Monaco/VS Code/IntelliJ artifact smoke for explicit dialect selection
  and config precedence, per Phase 13 SC4 and its Validation. Phase 9 scope
  covers the host code paths (initializationOptions, fathom.* config keys,
  extension identity) which are verified; live-editor UX acceptance belongs to
  Phase 13.
result: skipped
reason: "Deferred follow-up: live-editor UX acceptance belongs to Phase 13 SC4 (real Web/Monaco/VS Code/IntelliJ artifact smoke; document revision/stale-response and selection-conflict cases) per ROADMAP."

## Summary

total: 2
passed: 1
issues: 0
pending: 0
skipped: 1
blocked: 0

## Deferred Follow-Ups

- test: 1
  idea: "Enforce dialect-aware FATHOM-PARSE-008 (or equivalent) for empty flink input if no-silent-success is desired beyond Phase 9; currently silent-empty for Doris parity (WINDOWS.md #4)."
  deferred_at: 2026-08-07
- test: 2
  idea: "Live-host VS Code/IntelliJ dialect-selection UX and config precedence smoke (Phase 13 SC4)."
  deferred_at: 2026-08-07

## Gaps
