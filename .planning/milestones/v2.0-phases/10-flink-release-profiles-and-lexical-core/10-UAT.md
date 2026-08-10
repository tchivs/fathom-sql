---
status: complete
phase: 10-flink-release-profiles-and-lexical-core
source: [10-VERIFICATION.md]
started: 2026-08-07T00:00:00Z
updated: 2026-08-07T00:00:00Z
---

## Current Test

[testing complete — verifier found no human_verification items; all 3 success criteria verified with behavioral evidence]

## Tests

### 1. Flink release profile selection (SC1)
expected: |
  User can select flink-2.3.0 (primary), flink-2.1.3 / flink-1.20.5 (regression)
  profiles through CLI/API/wire; an unsupported profile is rejected explicitly.
result: pass
evidence: |
  FlinkProfile closed enum + from_id exact-match (dialect/flink.mbt:79);
  CLI flink-2.3.0 exits 0 with FATHOM-PARSE-008 (lexical-accepted, grammar pending Phase 11);
  unknown profile exits 2 with released-value message (fathom-sql cli_test 16/16);
  extract script validates 3 pins + manifest sha512 re-verify (exit 0).

### 2. Auditable release metadata + Calcite pin (SC2)
expected: |
  Each accepted profile reports release source/tag/commit, Calcite version, parser
  configuration, and feature metadata; the 2.1.3 Calcite pin is extracted from that release.
result: pass
evidence: |
  FlinkProfileMetadata exposes calcite_version 1.36.0/1.34.0/1.32.0 and parser_config,
  extracted from each release's own flink-table/pom.xml (verified in 10-RESEARCH.md §7);
  fathom.dialect.v1 wire output carries dialect=flink + profile + exact_release;
  manifest.tsv records url/sha512/tag/commit; scripts/extract_flink_lexical.py re-verifies manifest sha512 (MN-03).

### 3. Release-specific lexical + keyword behavior (SC3)
expected: |
  Flink input receives release-specific comment, quote, literal, operator, identifier,
  and keyword classification with trivia/spans preserved; conflict cases have explainable
  snapshots; no Doris-policy leakage; Doris baseline byte-identical.
result: pass
evidence: |
  lexer flink branches (# Error vs doris Comment, // and -- SINGLE_LINE_COMMENT, backtick
  double-escape, no-backslash strings, X/U&/N/E/_CHARSETNAME literals with E profile-gated,
  ||/=>/.. symbols); profile-aware classification (VARIANT/QUALIFY Reserved under 2.1.3+,
  None under 1.20.5); 26 flink-lexical conflict-matrix snapshots; parity 260/260 incl.
  213-snapshot Doris baseline WITHOUT --update (zero drift).

## Summary

total: 3
passed: 3
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
