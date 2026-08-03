---
phase: 01
slug: core-kernel
status: verified
threats_open: 0
asvs_level: 1
block_on: high
created: 2026-08-03
---

# Phase 1 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Caller bytes/profile → source and lexer | Untrusted raw bytes, profile values, malformed lexical material, and large inputs enter the pure core. | Raw bytes, profile identifiers, limits |
| Lexer tokens → CST/parser | Invalid, incomplete, and version-invalid tokens must not cause source loss, non-progress, or silent profile widening. | Tokens, spans, profile metadata |
| Parser/CST → API host | Source-backed nodes, spans, diagnostics, statement identities, and replay cross the public boundary. | CST, `UInt` statement IDs, diagnostic records |
| Corpus/differential metadata → support contract | Git fixture claims and advisory external observations must not silently widen released syntax support. | Manifest metadata, fixture rows, provenance status |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation / Evidence | Status |
|-----------|----------|-----------|----------|-------------|----------------------|--------|
| T-01-01 | Denial of Service | Source allocation and lexer loops | high | mitigate | Pre-allocation `max_bytes`, advancing scans, bounded lexical material; `source/source.mbt`, `lexer/lexer.mbt`, recovery tests | closed |
| T-01-02 | Tampering | Profile classification | high | mitigate | Only 2.1/3.x/4.x constructible; unknown profiles structurally rejected; no generic fallback | closed |
| T-01-03 | Tampering | Raw-byte/encoding handling | high | mitigate | Invalid UTF-8 remains source-backed error material with stable diagnostics and exact replay | closed |
| T-01-04 | Tampering | Toolchain reproducibility | medium | mitigate | Exact executable output is recorded, but `moon.mod` label says official v0.10.5 while observed output is `moon 0.1.20260724`; requires environment/pin reconciliation | open — below high threshold (non-blocking) |
| T-01-05 | Tampering | Root source payload and node spans | high | mitigate | Root-only source bytes, span bounds/parent checks, no node payload duplication | closed |
| T-01-06 | Tampering | Diagnostic code and statement identity | high | mitigate | Parser/API diagnostic IDs and snapshot counters use MoonBit 32-bit `UInt`, zero-based `0U`/`1U`; commit `27b6d63` | closed |
| T-01-07 | Denial of Service | Pratt/parser recursion | high | mitigate | Finite byte/token/recursion/recovery/diagnostic limits and bounded resource diagnostics | closed |
| T-01-08 | Information Disclosure | Replay output | low | accept | Replay exposes only caller-supplied source; no secret store or I/O in the core | open — accepted risk, non-blocking |
| T-01-09 | Denial of Service | Recovery synchronization | high | mitigate | Progress-or-error recovery, bounded steps, one resource diagnostic, source-backed skipped remainder | closed |
| T-01-10 | Denial of Service | Recursive nesting | high | mitigate | Depth checks stop nested expressions/queries deterministically | closed |
| T-01-11 | Tampering | Strict/editor status | medium | mitigate | One CST family, explicit validity/recovery fields, identical diagnostic schema and replay | closed |
| T-01-12 | Tampering | Statement identity/span | medium | mitigate | Source-order semicolon mapping, checked spans, snapshot-local monotonic `UInt` IDs | closed |
| T-01-13 | Information Disclosure | Error/skipped retention | low | accept | Error/replay paths return only caller bytes and have no secret store or I/O | open — accepted risk, non-blocking |
| T-01-14 | Tampering | Profile/version acceptance | high | mitigate | `ProfileMetadata` exact-release/feature-introduction validation; `ParseOptions::from_manifest` and `parse_with_metadata` reject mismatch before parsing; commit `d6f5b76` | closed |
| T-01-15 | Denial of Service | Industrial expressions/nested SELECTs | high | mitigate | Industrial parser reuses all finite parser limits and recovery paths | closed |
| T-01-16 | Tampering | Manifest/golden provenance | medium | mitigate | Manifest has provenance fields, but `pinned_source_revision=unavailable-offline` remains a known gap; requires verifiable revision | open — below high threshold (non-blocking) |
| T-01-17 | Tampering | Differential records | low | accept | FE/SQLGlot rows are `advisory_only`/`not-run-offline`; released docs remain authoritative | open — accepted risk, non-blocking |
| T-01-SC (01-01) | Tampering | Package installation | low | accept | No package-install task; local core primitives and pinned-toolchain policy only | open — accepted risk, non-blocking |
| T-01-SC (01-02) | Tampering | Package installation | low | accept | No package-install task or third-party runtime in CST/API/replay path | open — accepted risk, non-blocking |
| T-01-SC (01-03) | Tampering | Package installation | low | accept | No package-install task or third-party runtime in recovery/tests | open — accepted risk, non-blocking |
| T-01-SC (01-04) | Tampering | Package installation | low | accept | Corpus/parser checks use local Git data and the configured toolchain; no installation task | open — accepted risk, non-blocking |

*Status: closed · open · open — below high threshold (non-blocking)*  
*Severity: critical > high > medium > low; only open threats at or above `block_on: high` count toward `threats_open`.*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-01 | T-01-08 | Exact replay is intentionally caller-source-only; the offline parser has no secret store, filesystem, network, or FE access. | Phase 1 security disposition | 2026-08-03 |
| AR-02 | T-01-13 | Error/skipped retention preserves caller bytes only; no secret-bearing state enters the core. | Phase 1 security disposition | 2026-08-03 |
| AR-03 | T-01-17 | FE/Nereids and SQLGlot evidence is advisory and explicitly not run offline; released documentation remains authoritative. | Phase 1 security disposition | 2026-08-03 |
| AR-04 | T-01-SC (01-01) | Phase 1 has no package-installation task and uses local core primitives only. | Phase 1 security disposition | 2026-08-03 |
| AR-05 | T-01-SC (01-02) | Phase 1 has no package-installation task or third-party runtime in the CST/API/replay path. | Phase 1 security disposition | 2026-08-03 |
| AR-06 | T-01-SC (01-03) | Phase 1 has no package-installation task or third-party runtime in recovery/tests. | Phase 1 security disposition | 2026-08-03 |
| AR-07 | T-01-SC (01-04) | Corpus and parser checks use repository Git data; no installation or external runtime is required. | Phase 1 security disposition | 2026-08-03 |

*T-01-04 and T-01-16 remain open non-blocking mitigation gaps, not accepted risks.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Blocking Open | Run By |
|------------|---------------|--------|------|---------------|--------|
| 2026-08-03 | 21 | 12 | 9 non-blocking | 0 | `gsd-security-auditor` (ASVS L1) |

Inherited verification used by the audit: `moon check --target native` 0 errors, release build 0 errors, and `moon test` 93/93, all executed by the orchestrating session. The auditor itself did not run a project suite, formatter, or linter.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed for the `high` blocking threshold
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-08-03
