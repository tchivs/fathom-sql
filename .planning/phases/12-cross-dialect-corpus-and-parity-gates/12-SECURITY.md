---
phase: 12
slug: cross-dialect-corpus-and-parity-gates
status: verified
threats_open: 0
asvs_level: 1
created: 2026-08-09
---

# Phase 12 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| fixture bytes -> manifest sha256 | Committed .sql fixtures must match manifest hashes; drift fails offline --check | bytes -> sha256 |
| fixture_id -> .sql path | A crafted fixture_id must not traverse paths | string -> file path |
| snapshot tree -> diff harness | The frozen Doris baseline must never be silently modified; --update only via single-use approval | snapshots -> diff result |
| gate scripts -> CI | Offline gates must stay read-only and network-free; no --update in CI | files -> exit code |
| coverage report -> release decision | Catalog/planner/known-limitation must never be counted as engine-supported | rows -> report |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-12-01-01 | Tampering | manifest fixture_sha256 vs committed .sql bytes | high | mitigate | verify_corpus.py sha256_file per row; drift fails --check (verified exit 0 on 110 rows) | closed |
| T-12-01-02 | Tampering | Category mislabel — planner/catalog-prerequisite reported as positive/engine-supported | high | mitigate | 6-category enum + expected_status consistency + coverage prerequisite hard rule (parser-accepted 68 vs engine-prereq 19 vs engine-supported 49) | closed |
| T-12-01-03 | Tampering | Path traversal via fixture_id | medium | mitigate | fixture_id prefix whitelist (flink-grammar./flink-lexical.) + reject path separators/dot-dot | closed |
| T-12-01-04 | Spoofing | Gate blind spot — empty manifest / 0 files exits 0 | high | mitigate | non-empty guard: empty manifest exits 1; coverage rows >= 1 | closed |
| T-12-01-05 | Tampering | Embedded-raw provenance drift (.sql vs b"..." literals) | high | mitigate | extract_flink_grammar.py byte-compares embedded literals to .sql (97+13 byte-match verified) | closed |
| T-12-01-06 | Repudiation | Fabricated hash/provenance masking an unavailable release | medium | mitigate | never-fabricate discipline; archive-missing recorded as archive-not-present | closed |
| T-12-02-01 | Tampering | Unregistered Doris drift absorbed by local/CI --update | high | mitigate | single-use approval path; --frozen-only fails on ALL drift; NEVER --update in CI (CI grep-verified no --update) | closed |
| T-12-02-02 | Spoofing | Frozen-vs-current self-comparison reporting zero | high | mitigate | --frozen-only regenerates current output and byte+path compares; injected drift fails with file named (executor-tested exit 1) | closed |
| T-12-02-03 | Tampering | Docs-vs-parser conflicts silently resolved by overwriting snapshots | high | mitigate | unexpected diffs exit 1 → human-adjudication register with recorded reason (D-07) | closed |
| T-12-02-04 | Availability | Temp regeneration leaves working tree modified after crash | high | mitigate | move/restore lifecycle; restore-on-failure returns committed bytes; exit 2 on failed move (SIGTERM mid-regen test: tree intact) | closed |
| T-12-02-05 | Tampering | Forged/empty register masking unapproved drift | medium | mitigate | register parsed via baseline_diff engine (malformed rows fail); --frozen-only consults NO register | closed |
| T-12-03-01 | Tampering | js target silently skipped | high | mitigate | js runtime step in CI + compare_backends non-empty guard (skipped target exits 1); 3-target digest identical 5e9bb887 | closed |
| T-12-03-02 | Tampering | Byte differences normalized away in parity proof | high | mitigate | byte-identity on committed snapshot files; digest over raw bytes; no normalization | closed |
| T-12-03-03 | Spoofing | CI network creep | high | mitigate | verify_corpus/compare_backends stdlib read-only; only pre-existing installer curl | closed |
| T-12-03-04 | Tampering | --update added to a CI job | high | mitigate | parity-gate keeps no-update constraint; verify gate greps run lines | closed |
| T-12-03-05 | Spoofing | Frozen baseline proof degrades to self-comparison | high | mitigate | --frozen-only regenerates + byte/path compares; wired as parity-gate frozenness step | closed |
| T-12-03-06 | Tampering | Coverage report counts prerequisites as engine-supported in CI | high | mitigate | generate_corpus_report.py --check hard-gates the prerequisite rule in corpus job | closed |
| T-12-01-SC / 02-SC / 03-SC | Tampering | npm/pip/cargo installs | low | accept | Zero new runtime dependencies; all gates Python stdlib | closed — accepted |

*Status: open · closed · open — below block_on threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on (high) count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| R-12-01 | T-12-0X-SC (all plans) | Zero new external dependencies; verify_corpus/diff_parity/compare_backends are Python stdlib; release archives remain research-time fixtures | Planning decision | 2026-08-09 |

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-08-09 | 20 | 20 | 0 | gsd (L1 grep-depth verification, ASVS level 1 short-circuit + gate-execution re-verification) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-08-09
