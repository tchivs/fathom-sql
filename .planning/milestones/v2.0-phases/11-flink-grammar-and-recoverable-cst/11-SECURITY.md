---
phase: 11
slug: flink-grammar-and-recoverable-cst
status: verified
threats_open: 0
asvs_level: 1
created: 2026-08-07
---

# Phase 11 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| SQL input -> Flink grammar parser | Untrusted SQL (incl. hostile nesting) crosses here; must produce a recoverable CST, never crash | bytes -> CST nodes |
| shared parser/CST -> Doris path | Any shared change must keep Doris 213-snapshot byte-identical | bytes -> CST |
| dialect selection -> negative gates | Flink-only constructs must be rejected in Doris mode and vice versa (FATHOM-PARSE-009) | DialectContext -> diagnostics |
| MATCH_RECOGNIZE input -> syntax CST | Syntax-level only; no pattern-variable scope/type validation, no planner equivalence | bytes -> CST |
| fixture manifest -> parity gate | Grammar production refs must come from the pinned release archives (D-05) | archive bytes -> refs |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-11-01 | Tampering | Flink SELECT accepting Doris-only constructs | high | mitigate | add_dialect_gate_diagnostic (FATHOM-PARSE-009) at each Doris-only point + negative fixtures | closed |
| T-11-02 | Tampering | Shared precedence/query changes altering Doris expression acceptance | high | mitigate | precedence(context, cursor) Doris arm byte-identical; 213-snapshot gate after every shared change | closed |
| T-11-03 | Tampering | MATCH_RECOGNIZE accepted as identifier under Flink | high | mitigate | flink_classification_rows row per pinned Calcite token line; classification tests under all 3 profiles | closed |
| T-11-04 | Tampering | FATHOM-PARSE-008 reuse after retirement | medium | mitigate | code stays vacant; register documents vacancy; unsupported routes 007 only | closed |
| T-11-05 | Denial of Service | Incomplete SELECT / empty input unbounded recovery | high | mitigate | consume_recovery_step/depth_allowed budget + finish_statement; incomplete fixtures assert bounded steps; CR-01/02 recursion-depth fixes | closed |
| T-11-06 | Tampering | flink-grammar/lexical snapshots leaking into Doris namespace | medium | mitigate | independent flink-grammar./flink-lexical. naming + register; git diff per-group | closed |
| T-11-07 | Tampering | Fabricated production line refs (folklore) | high | mitigate | extract_flink_grammar.py validates refs against pinned archives; manifest sha512/tag/commit | closed |
| T-11-08 | Tampering | Flink DML accepting Doris-only forms | high | mitigate | add_dialect_gate_diagnostic at each skipped form + negative fixtures | closed |
| T-11-09 | Tampering | Doris accepting Flink-only DML | high | mitigate | Doris parser untouched; negative fixtures assert 009 | closed |
| T-11-10 | Tampering | `name => expr` misparsed in shared expression layer | medium | mitigate | `=>` only in Flink function-call argument layer with 009 under Doris | closed |
| T-11-11 | Tampering | Flink types shifting Doris type acceptance | high | mitigate | parse_flink_data_type separate; Doris type fixtures unchanged | closed |
| T-11-12 | Denial of Service | Incomplete INSERT column list unbounded recovery | high | mitigate | is_flink_insert_boundary + shared budget; incomplete fixtures bounded | closed |
| T-11-13 | Spoofing | Aux statements silently accepted under Doris via shared fallback | medium | mitigate | Doris never routes to Flink productions; unsupported stays 007 with Error node | closed |
| T-11-14 | Tampering | DML/aux snapshots colliding with Doris namespace | medium | mitigate | independent naming + register; git diff per-group | closed |
| T-11-15 | Tampering | Doris-only CREATE TABLE forms under Flink | high | mitigate | 009 gate at each Doris-only form + negative-gate matrix | closed |
| T-11-16 | Tampering | Flink-only CREATE TABLE forms under Doris | high | mitigate | Doris parser untouched; negative fixtures assert 009 | closed |
| T-11-17 | Tampering | Multiple WATERMARK silently overwriting | medium | mitigate | single-instance WATERMARK check with localized error | closed |
| T-11-18 | Denial of Service | Unclosed column body / incomplete DISTRIBUTED unbounded recovery | high | mitigate | is_flink_create_table_clause_boundary + shared budget; incomplete fixtures bounded | closed |
| T-11-19 | Tampering | DISTRIBUTED INTO n BUCKETS with non-positive n | medium | mitigate | positive-integer enforcement per pinned .fails tests | closed |
| T-11-20 | Tampering | DDL snapshots leaking into Doris namespace | medium | mitigate | independent naming + register; git diff per-group | closed |
| T-11-21 | Spoofing | DDL parsing implying catalog/connector/function registration | medium | mitigate | FLINK-03 syntax-level only; documented in prohibitions | closed |
| T-11-22 | Tampering | MATCH_RECOGNIZE accepted as table alias under Doris | high | mitigate | Doris-mode 009 gate at table-ref + negative fixture | closed |
| T-11-23 | Tampering | Window TVF accepted as Doris table-ref | high | mitigate | Doris-mode 009 gate for TUMBLE/HOP/CUMULATE/SESSION + negative fixture | closed |
| T-11-24 | Denial of Service | Unclosed MATCH_RECOGNIZE/PATTERN unbounded recovery | high | mitigate | is_flink_match_recognize_boundary + shared budget; CR-02 depth fix | closed |
| T-11-25 | Tampering | Pattern-variable scope/type validation rejecting valid MR | medium | mitigate | no scope/type validation in parser (Pitfall 6); prohibited; negatives never assert resolution rejection | closed |
| T-11-26 | Spoofing | TVF/MR implying planner/execution equivalence | high | mitigate | syntax-level CST only; prohibitions + fixture classification | closed |
| T-11-27 | Tampering | TVF/MR snapshots leaking into Doris namespace | medium | mitigate | independent flink-grammar naming + final register | closed |
| T-11-28 | Tampering | Fabricated MATCH_RECOGNIZE production line refs | high | mitigate | extract_flink_grammar.py validates against Parser.jj:3062-3346; manifest sha512 | closed |
| T-11-SC | Tampering | npm/pip/cargo installs | low | accept | Zero new runtime dependencies; extract script Python stdlib | closed — accepted |

*Status: open · closed · open — below block_on threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on (high) count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| R-11-01 | T-11-SC (all plans) | Zero new external dependencies; extract_flink_grammar.py is Python stdlib; release archives are research-time fixtures | Planning decision | 2026-08-07 |

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-08-07 | 32 | 32 | 0 | gsd (L1 grep-depth verification, ASVS level 1 short-circuit + blocker-fix re-verification) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-08-07
