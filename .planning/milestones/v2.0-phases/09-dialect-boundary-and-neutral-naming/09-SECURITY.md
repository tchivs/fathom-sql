---
phase: 09
slug: dialect-boundary-and-neutral-naming
status: verified
threats_open: 0
asvs_level: 1
created: 2026-08-07
---

# Phase 9 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| corpus fixtures -> snapshot tests | Untrusted SQL (malformed/recovery rows) flows into frozen snapshots; the gate must fail, never silently update | SQL text -> JSON snapshots |
| dialect/profile strings -> api ParseOptions | Untrusted selection strings cross here; must be closed-enum validated with structured errors, never silently defaulted | strings -> Dialect/DialectProfile enums |
| Flink context -> parser | Any parse under a Flink context must reject explicitly (FATHOM-PARSE-008), never fall back to Doris grammar | DialectContext -> CST/diagnostics |
| editor client -> initialize/didChangeConfiguration/didOpen selection params | Untrusted selection strings and settings cross here; closed-enum validated (D-02), never guessed | LSP params -> Document DialectContext |
| async parse results -> publishDiagnostics | A stale result computed under an old selection/version must never overwrite newer diagnostics (D-03) | async Bytes -> diagnostics |
| JS/Wasm host -> binding exports | The export ABI is the public JS/linear-Wasm contract; half-migration breaks consumers silently | Bytes -> Bytes |
| host config keys -> LSP selection | Keys named with the old identity or a defaulted dialect break the explicit-selection guarantee | JSON settings -> DialectContext |
| repository content -> naming gate | The gate's pattern+scope matrix decides violation vs allowed dialect semantics | file paths + text -> exit code |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-09-01 | Tampering | parity/__snapshot__ silent update | high | mitigate | CI runs `moon test --package parity` without --update; approved-changes.md + baseline_diff.py make unregistered diffs exit non-zero (D-08); verified: 213 snapshots, 0 unexpected diffs | closed |
| T-09-02 | Tampering | Refactor lands before baseline (records post-refactor bytes) | high | mitigate | Wave 1 ordering enforced by depends_on; baseline_test.mbt committed before 09-02 started | closed |
| T-09-03 | Tampering | baseline-hashes.txt fabricated/missing | medium | mitigate | sha256 computed on host from committed corpus; file committed; `sha256sum -c parity/baseline-hashes.txt` added to CI parity-gate (MI-04 fix) | closed |
| T-09-04 | Denial of Service | Snapshot explosion slows CI | low | accept | 44 fixtures x 2 modes bounded; completion/LSP homomorphs use representative subset enumerated in approved-changes.md register item 6 | closed — accepted |
| T-09-05 | Tampering | Dialect confusion injection (attacker-controlled dialect/profile strings) | high | mitigate | Closed Dialect enum + ParseOptions::new validates dialect first then profile; unknown/missing/conflict -> structured UnknownDialect/ConflictingSelection; results carry actual selection metadata (ASVS V5) | closed |
| T-09-06 | Tampering | Cross-dialect classification leakage (global union effect) | high | mitigate | Two module-level rows arrays selected only by context.dialect; parameterless public queries removed (classification_of takes DialectContext — verified); baseline gate pins Doris acceptance | closed |
| T-09-07 | Tampering | Flink mode silently accepts Doris grammar (try-all fallback) | high | mitigate | Single parse_segment router; parse_flink_segment returns source-backed FATHOM-PARSE-008 (4 occurrences in parser/parser.mbt — verified); no fallback path exists | closed |
| T-09-08 | Spoofing | Neutral-message regression (Doris phrasing leaks into flink errors) | medium | mitigate | validate_dialect_profile + neutral messages; dialect expressed in fields (D-10); grep gates in acceptance criteria; flink profile message corrected (MI-02) | closed |
| T-09-09 | Tampering | Export half-migration (#export_name vs moon.pkg exports) | medium | mitigate | Both lists updated in same commit; fathom_*_v1 exports + js/wasm exports lists synced (09-05); NAME-04 gate backs up | closed |
| T-09-10 | Tampering | Flink request formatted/completed under Doris keyword policy | high | mitigate | dialect-first validation in complete/format_with_ids; flink -> FATHOM-SCHEMA-003 before keyword enumeration; flink formatting returns structured not-implemented error (MI-06) | closed |
| T-09-11 | Tampering | Case rewriting reads a stale global classification table | medium | mitigate | rewrite_keyword routes through dialect classification; parameterless queries removed (09-02) | closed |
| T-09-12 | Tampering | Partial FATHOM-FORMAT migration (formatter emits new, binding maps old) | medium | mitigate | Emission + mapping updated in same task; grep gates; NAME-04 gate | closed |
| T-09-13 | Tampering | CLI silently defaults a dialect (no --dialect) | high | mitigate | --dialect/--profile required for every subcommand; MissingDialect/MissingProfile -> exit 2 (args.mbt:15,17 — verified); cli_test 16/16 | closed |
| T-09-14 | Tampering | Old binary/asset names still referenced by scripts or workflow | medium | mitigate | git mv in one commit + release workflow renamed; NAME-04 gate scans workflows; cli_test covers new surface | closed |
| T-09-15 | Spoofing | Duplicated server loop diverges (CLI lsp vs fathom-lsp) | medium | mitigate | Single serve_stdio implementation; fathom-lsp main and run_lsp are thin callers | closed |
| T-09-16 | Tampering | Export half-migration (#export_name vs moon.pkg exports vs parity callsites) | high | mitigate | Same-commit rule for all three surfaces; parity export_smoke_test per target; verified 228/228 native/js/wasm | closed |
| T-09-17 | Tampering | Old-schema consumption confusion during cutover | medium | mitigate | Clean cutover with zero aliases (D-06); NAME-04 gate rejects doris.*.v1 in product files; no dual-serving | closed |
| T-09-18 | Spoofing | Fabricated profile/exact_release metadata in fathom_dialect_v1 | low | mitigate | Values sourced only from DorisProfile::metadata; prohibition (provenance discipline) | closed |
| T-09-19 | Tampering | Dialect-confusion injection via client selection strings (initialize/didChange/settings) | high | mitigate | resolve_selection validates through validate_dialect_profile; missing/unknown/conflicting -> FATHOM-SCHEMA-007 or -32602; no default path (D-02, ASVS V5); MA-01 fix: serve_stdio defaults fallback | closed |
| T-09-20 | Spoofing | Stale async results overwrite newer diagnostics after a dialect switch | high | mitigate | DocumentStore version monotonicity (documents.mbt:36 `version <= document.version` rejects stale — verified) + publish only when stored version matches (D-03) | closed |
| T-09-21 | Tampering | Implicit languageId fallback re-introduced (silent dialect guess) | high | mitigate | language_mapping participates only when user-configured (D-02); MissingSelection test is a permanent negative gate | closed |
| T-09-22 | Spoofing | Old LSP identity leaks (doris-lsp / DORIS-LSP-001 / source doris) | medium | mitigate | grep gates + NAME-04 gate scans lsp/; FATHOM-LSP-001 + source fathom + serverInfo fathom-lsp (09-06) | closed |
| T-09-23 | Tampering | Flink-selected document parsed under Doris policy over LSP | high | mitigate | Document context drives parse_with_ids; flink -> FATHOM-PARSE-008 surfaced unchanged; tests (h)/(j) | closed |
| T-09-24 | Tampering | Host half-migration (one host renamed, another stale) | high | mitigate | Same-plan commit rule; check_naming.py scans all host trees; source-smoke + web/vscode builds per host | closed |
| T-09-25 | Tampering | Gate bypass via scan-scope gaps (unlisted file types/paths) | medium | mitigate | Explicit product-file scope list (§7.2) + final repository-wide sweep; probe test proves exit 1 on violation; zero-scan hard-fail added (MI-03) | closed |
| T-09-26 | Tampering | False-positive gate deleting Doris dialect semantics (Dialect::Doris, corpus provenance) | medium | mitigate | FORBIDDEN patterns precise (never bare 'doris'); ALLOWLIST_CONTEXTS protect D-05/D-04 surfaces; 349 files scanned 0 remnants | closed |
| T-09-27 | Tampering | Default-dialect reintroduction in hosts (first-open guess) | high | mitigate | D-02 prohibitions: normalizeProfile/'4.x' fallbacks deleted; gate forbids old default shapes; host tests assert no default | closed |
| T-09-28 | Tampering | Release asset mismatch (workflow names vs binary identity) | medium | mitigate | fathom-native-release.yml + fathom-lsp-* landed in 09-04; gate scans workflows | closed |
| T-09-SC | Tampering | npm/pip/cargo installs | low | accept | Zero new external dependencies this phase; scripts are Python stdlib | closed — accepted |

*Status: open · closed · open — below block_on threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on (high) count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| R-09-01 | T-09-04 | Snapshot count bounded (44 fixtures x 2 modes); completion/LSP homomorph subset enumerated in approved-changes.md register item 6, keeping D-07 full-freeze claim auditable | Planning decision (plan-time) | 2026-08-06 |
| R-09-02 | T-09-SC (all plans) | Zero new external dependencies; check_naming.py / baseline_diff.py are Python stdlib | Planning decision (plan-time) | 2026-08-06 |
| R-09-03 | (empty-Flink input) | Empty input under a flink context publishes silent empty diagnostics for Doris parity (single-router statement split precedes dialect routing); FATHOM-PARSE-008 fires on every non-empty flink input. Accepted as Phase 9 contract by UAT decision 2026-08-07; enforcement of a dialect-aware empty-input diagnostic tracked as deferred follow-up (WINDOWS.md #4) | User decision via UAT | 2026-08-07 |

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-08-07 | 33 | 33 | 0 | gsd (L1 grep-depth verification, ASVS level 1 short-circuit) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-08-07
