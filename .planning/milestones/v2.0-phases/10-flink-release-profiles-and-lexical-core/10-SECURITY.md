---
phase: 10
slug: flink-release-profiles-and-lexical-core
status: verified
threats_open: 0
asvs_level: 1
created: 2026-08-07
---

# Phase 10 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| profile strings -> FlinkProfile::from_id | Untrusted `--profile`/selection strings cross here; closed-enum exact-match with structured rejection | strings -> FlinkProfile enum |
| release POM/grammar -> extracted metadata | The Calcite pin and parser config must come from the pinned archive, never hand-inferred (D-02) | archive bytes -> metadata |
| lexer dialect branches -> token stream | A Flink branch must never inherit Doris policy (`#`/`//`/quote/literal handling); Doris arm byte-identical | DialectContext -> tokens |
| flink keyword rows -> identifier acceptance | Rows selected by dialect AND profile (introduced_profile <= selected); no union leakage | DialectContext -> classification |
| snapshot files -> parity gate | flink-lexical snapshots must stay in their namespace; Doris baseline byte-identical | snapshots -> diff result |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-10-01 | Tampering | Flink profile string injection (`flink-2.3.0; DROP...`, `flink-2.3`, `2.1`) | high | mitigate | Closed FlinkProfile enum + from_id exact-match ("flink-2.3.0"/"flink-2.1.3"/"flink-1.20.5" only; dialect/flink.mbt:79); unknown -> UnknownProfile -> FATHOM-SCHEMA-003; CLI/API tests cover boundary set | closed |
| T-10-02 | Tampering | Lexical dialect confusion (`#` accepted as comment under Flink) | high | mitigate | lexer branches by context.dialect; Doris arm byte-identical (git show verified); conflict snapshot freezes Flink Error vs Doris Comment | closed |
| T-10-03 | Tampering | Calcite pin / parser-config fabrication (2.1.3 pin hand-inferred) | high | mitigate | D-02 extract script reads pinned release POMs (verified 1.36.0/1.34.0/1.32.0); manifest records sha512/tag/commit; script re-verifies manifest sha512 (MN-03) | closed |
| T-10-04 | Tampering | Doris baseline drift during flink unlock | high | mitigate | parity gate without --update; approved-changes register committed before any update; git diff --name-only -- parity/__snapshot__ shows no doris-named snapshot changed; 260/260 parity green | closed |
| T-10-05 | Spoofing | Neutral-message regression (flink rejection advertising doris values) | medium | mitigate | run.mbt flink/UnknownProfile/MissingProfile messages list both dialect value sets; CLI exit-2 tests assert text | closed |
| T-10-06 | Tampering | flink-lexical snapshots merge into the Doris namespace | medium | mitigate | Independent flink-lexical naming + register documents namespace boundary; per-group git diff check | closed |
| T-10-07 | Tampering | Flink lexical branch leaks Doris policy (`//` or `"` accepted as Doris does, `#` as comment) | high | mitigate | Explicit `match context.dialect` at every branch; Doris arm byte-identical; conflict fixtures assert difference; `#` -> Error token under Flink | closed |
| T-10-08 | Tampering | E-literal profile gate wrong (E accepted under flink-1.20.5) | high | mitigate | Gate reads selected FlinkProfile (flink-2.3.0/2.1.3 allow C_STYLE_ESCAPED, 1.20.5 denies — Parser.jj 1.32.0 absent); E-literal fixture under all three profiles | closed |
| T-10-09 | Tampering | Doris 213-snapshot drift during lexer branch work | high | mitigate | parity gate without --update; register committed before update; git diff --name-only shows no doris-named snapshot changed | closed |
| T-10-10 | Tampering | flink-lexical matrix merged into Doris namespace | medium | mitigate | Independent flink-lexical naming + register entry; per-group diff | closed |
| T-10-11 | Denial of Service | Matrix fixture explosion slows parity suite | low | accept | Bounded matrix (5 conflict entries x relevant profiles x 2 modes); filenames enumerated in plan/register | closed — accepted |
| T-10-12 | Tampering | Keyword union leakage (Flink word affects Doris acceptance or vice versa) | high | mitigate | Independent module-level arrays; Doris selected only by context.dialect, Flink filtered by introduced_profile <= selected; independence test asserts Doris 116 preserved + is_reserved_word(doris, VARIANT) false | closed |
| T-10-13 | Tampering | Version-sensitive word misclassified (VARIANT/QUALIFY under 1.20.5) | high | mitigate | Per-release rows with introduced_profile; profile-aware routing filter (dialect/classification.mbt:65-69); tests assert 1.20.5 absence; extract script validates rows against release lists | closed |
| T-10-14 | Tampering | Fabricated classification source (docs folklore instead of release grammar) | medium | mitigate | Row source columns are release-grammar path+line (e.g. Parser.jj:8640 VARIANT); audit test + script validation | closed |
| T-10-15 | Tampering | Doris classification drift during row-table work | high | mitigate | Doris rows untouched; classification_entries(doris) derived from doris_classification_rows.length(); parity gate no --update | closed |
| T-10-SC | Tampering | npm/pip/cargo installs | low | accept | Zero new dependencies; extract script is Python stdlib (hashlib.sha512) | closed — accepted |

*Status: open · closed · open — below block_on threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on (high) count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| R-10-01 | T-10-11 | Flink lexical conflict matrix is bounded (5 conflict entries x relevant profiles x 2 modes); snapshot filenames enumerated in the plan and register so growth is controlled | Planning decision (plan-time) | 2026-08-07 |
| R-10-02 | T-10-SC (all plans) | Zero new external dependencies; extract_flink_lexical.py is Python stdlib; release archives are research-time fixtures, not shipped | Planning decision (plan-time) | 2026-08-07 |

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-08-07 | 21 | 21 | 0 | gsd (L1 grep-depth verification, ASVS level 1 short-circuit) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-08-07
