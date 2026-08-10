---
phase: 13
slug: toolchain-and-editor-packaging
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (high)
threats_open: 0
asvs_level: 1
created: 2026-08-10
---

# Phase 13 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> Phase 13 (Toolchain and Editor Packaging) exposed Flink through the full neutral toolchain: formatter, completion, analyzer, CLI/LSP, JS/linear-Wasm wire (`fathom_complete_v1`), Web/Monaco, VS Code, IntelliJ, and the CI packaging smoke.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| JS/Wasm wire boundary (binding exports) | `fathom_parse_v1` / `fathom_format_v1` / `fathom_complete_v1` / `fathom_dialect_v1` / `fathom_capabilities_v1` | UTF-8 JSON Bytes: raw SQL, dialect/profile, cursor_byte; result/error envelopes (`fathom.*.v1`, `fathom.error.v1`) |
| LSP stdio boundary | `fathom-lsp` / `fathom-sql lsp` — didOpen/didChange/formatting/completion/initialize | JSON-RPC messages, UTF-16 positions, document text + document-level dialect/profile extension fields |
| Host config boundary | Web/Monaco, VS Code, IntelliJ (dialect, profile) selection | dialect/profile strings, per-dialect profile maps (`PROFILES_BY_DIALECT`), LSP initializationOptions / settings |
| Formatter/Completion/Analyzer core | Flink covered-family gate, single classification pool, syntax-view-only analyzer | SQL source bytes, spans, syntax nodes, `introduced_profile`-gated classification rows |
| CI/release boundary | offline gates (`diff_parity --frozen-only`, `check_naming.py`, `compare_backends.py`, `verify_corpus.py`) | snapshot files, naming inventory, corpus manifests; no network beyond the MoonBit installer curl |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-13-01-01 | Tampering | Uncovered Flink family silently single-lined via `_ => []` | high | mitigate | `flink_statement_covered` gate before layout_sequence routes uncovered families through `Layout.failed` (layout.mbt:356,949) | closed |
| T-13-01-02 | Tampering | Partial output on refusal (truncated/single-line bytes emitted before refusal) | high | mitigate | Refusal path returns accepted=false + empty output + exactly one FATHOM-FORMAT-001; refusal oracle asserts empty output | closed |
| T-13-01-03 | Spoofing | Refusal masks parse diagnostics (FATHOM-FORMAT-001 hides the real syntax error) | high | mitigate | Parse diagnostics preserved/prepended, never replaced (T-03-01); refusal oracle asserts parse diagnostics present | closed |
| T-13-01-04 | Tampering | Doris frozen baseline drifts when Flink arms touch shared tables | high | mitigate | Dialect-conditional gate (fires for Flink only); `diff_parity --frozen-only` after every change; no `--update` | closed |
| T-13-01-05 | Tampering | Flink clause_breaks arm diverges from parser consume_word, breaking the reparse gate | medium | mitigate | Every break keyword mirrors parser.mbt usage; zero-diagnostic reparse of formatted output is a per-fixture assertion | closed |
| T-13-01-06 | Spoofing | flink-format snapshots drift under CI (unapproved --update) | high | mitigate | CI runs `moon test --package parity` WITHOUT `--update`; snapshot files only via the sanctioned register flow | closed |
| T-13-01-SC | Tampering | npm/pip/cargo installs | low | accept | Zero new runtime dependencies (RESEARCH Package Legitimacy Audit N/A); all changes are in-repo MoonBit | closed |
| T-13-02-01 | Tampering | A completion-specific keyword list drifts from the parser's classification table | high | mitigate | D-28 single-table discipline: candidate pool is `classification_entries` only; regression guard greps for no completion-specific table | closed |
| T-13-02-02 | Tampering | A Reserved classification addition changes parse behavior and moves frozen flink-grammar/lexical snapshots | high | mitigate | Extension is NonReserved-only (parse-neutral); `moon test --package parity` no `--update` + `diff_parity` | closed |
| T-13-02-03 | Denial of Service | Unbounded completion on a broad context | medium | mitigate | `MAX_CANDIDATES=32` enforced in the two-pass loop; boundedness test asserts <=32 for the widest context | closed |
| T-13-02-04 | Tampering | Profile gating bypass — a 2.3.0-introduced word offered under flink-1.20.5 | high | mitigate | `classification_entries` -> `flink_row_visible` filters by `introduced_profile <= selected`; per-profile gating tests | closed |
| T-13-02-05 | Tampering | Silent fallback — unknown profile returns a Doris-shaped candidate list or an empty-silent success | high | mitigate | UnknownProfile on unknown/unsupported profile; no Doris-profile borrowing (exact-match `from_id`) | closed |
| T-13-02-06 | Tampering | Source-range edit with wrong byte offsets corrupts the editor buffer | medium | mitigate | start_byte/end_byte from `cursor_replacement`; multibyte prefix test asserts start_byte <= cursor_byte | closed |
| T-13-02-07 | Tampering | Doris completion bytes drift when Flink arms are added | high | mitigate | New context arms gated on Flink; Doris context strings/ordering unchanged; PARITY-01 + lsp completion tests | closed |
| T-13-02-SC | Tampering | npm/pip/cargo installs | low | accept | Zero new runtime dependencies (RESEARCH Package Legitimacy Audit N/A). | closed |
| T-13-03-01 | Tampering | Analyzer imports parser/token/lexer/api, breaking the D-21 read-only boundary | high | mitigate | analyzer/moon.pkg imports only `fathom/sql/syntax`; grep gate == 1 fathom/sql import; parser/moon.pkg never imports analyzer | closed |
| T-13-03-02 | Spoofing | Analyzer fabricates a table resolution for a missing table or no catalog | high | mitigate | Missing tables are simply absent from the result; no-catalog returns empty; never-fabricate discipline (ANLY-01) | closed |
| T-13-03-03 | Tampering | Catalog metadata reaches the parser and changes parser validity | high | mitigate | Analyzer consumes only `@syntax.SyntaxNode` + source bytes; no-catalog case asserts byte-identical parse | closed |
| T-13-03-04 | Tampering | Wrong leading-prefix skip resolves the wrong table (e.g. UPSERT arm skipping past the name) | medium | mitigate | UPSERT/CreateView/OVERWRITE-PARTITION arms mirror the parser's emitted kinds; per-family fixtures assert the resolved name | closed |
| T-13-03-05 | Tampering | Analyzer over-reaches into column/identifier resolution, changing public returned-set semantics | high | mitigate | Table-level only; docs/API.md scope note; query-body boundary asserted (INSERT ... SELECT resolves only the target table) | closed |
| T-13-03-06 | Tampering | Doris analyzer bytes drift when Flink arms are added | high | mitigate | Additive Flink arms; existing analyzer_test Doris fixtures unchanged; `diff_parity --frozen-only` | closed |
| T-13-03-SC | Tampering | npm/pip/cargo installs | low | accept | Zero new runtime dependencies (RESEARCH Package Legitimacy Audit N/A). | closed |
| T-13-04-01 | Tampering | fathom_complete_v1 missing from the built JS/Wasm artifact (partial registration) | high | mitigate | Five-file change set in one commit; moon.pkg js+wasm both contain the symbol; grep gate + `moon build --target js/wasm` | closed |
| T-13-04-02 | Spoofing | Unknown dialect/profile silently returns a Doris-shaped or empty completion | high | mitigate | Dialect-first: UnknownDialect -> FATHOM-SCHEMA-007, UnknownProfile -> FATHOM-SCHEMA-003; export smoke asserts the error envelopes | closed |
| T-13-04-03 | Tampering | Out-of-range cursor panics or emits a malformed range | medium | mitigate | Cursor bounds-checked in the core (InvalidCursor, completion.mbt); wire error matrix asserts the error envelope | closed |
| T-13-04-04 | Tampering | Int ABI mismatch on linear-Wasm (cursor_byte not mapped) | medium | mitigate | run_wasm.mbt exercises fathom_complete_v1; compare_backends.py proves three-target byte-identity | closed |
| T-13-04-05 | Tampering | Envelope leaks a dialect name into item text | medium | mitigate | Neutral detail "SQL syntax keyword"; export smoke asserts no doris/flink string in items (D-10, D-28) | closed |
| T-13-04-06 | Tampering | Schema validator rejects fathom.complete.v1 (registration gap) | high | mitigate | `validate_schema_version` registers COMPLETE_SCHEMA_VERSION; export smoke asserts the envelope is accepted | closed |
| T-13-04-07 | Tampering | Frozen snapshot drift from the additive export | high | mitigate | No `--update` in CI; `moon test --package parity` green; `diff_parity --frozen-only` | closed |
| T-13-04-08 | Tampering | Malformed UTF-8 / invalid JSON at the JS/Wasm boundary causes a panic or unreadable result | medium | mitigate | Raw input stays Bytes end-to-end; `@utf8.decode_lossy` on decode; export_smoke_test asserts a malformed-UTF-8 + oversize case returns the structured fathom.error.v1 envelope, never a panic | closed |
| T-13-04-SC | Tampering | npm/pip/cargo installs | low | accept | Zero new runtime dependencies (RESEARCH Package Legitimacy Audit N/A). | closed |
| T-13-05-01 | Tampering | A host that depended on -32603/-32602 to disable format/completion buttons breaks when real results arrive | high | mitigate | Three response shapes (error vs empty vs real) pinned in tests; hosts updated in 13-06 to handle all three | closed |
| T-13-05-02 | Tampering | A flink document silently formatted under Doris policy (sentinel removed but no real path) | high | mitigate | `formatting_result` calls `@api.format_with_ids` with the document's own dialect/profile; refusal (FATHOM-FORMAT-001) is surfaced | closed |
| T-13-05-03 | Tampering | Wrong UTF-16 textEdit range on a multibyte prefix corrupts the editor buffer | medium | mitigate | `@binding.span_to_range` shared single path (CRLF-as-one-break, 4-byte->2-units); multibyte prefix textEdit test | closed |
| T-13-05-04 | Spoofing | A stale completion under an old dialect/profile version is published | high | mitigate | Existing version + selection stale guard (D-03 pub guard); profile-switch reparse test verifies only the current selection publishes | closed |
| T-13-05-05 | Tampering | CLI flink format returns the wrong exit code (accepted/refusal/usage) | medium | mitigate | cli_test flink matrix (0/1/2); D-39 mapping unchanged; parse diagnostics never masked on refusal | closed |
| T-13-05-06 | Tampering | A second UTF-16 converter drifts from binding.coordinates | high | mitigate | lsp/coordinates.mbt single `span_to_range`; grep gate (== 1); flink path reuses `diagnostic_range` | closed |
| T-13-05-07 | Tampering | Doris LSP/CLI bytes drift when flink paths are added | high | mitigate | Additive flink handling; existing lsp/cli tests unchanged; `diff_parity --frozen-only` | closed |
| T-13-05-SC | Tampering | npm/pip/cargo installs | low | accept | Zero new runtime dependencies (RESEARCH Package Legitimacy Audit N/A). | closed |
| T-13-06-01 | Tampering | Host accepts a cross-dialect profile (flink + '2.1') and sends it to the server | high | mitigate | Per-dialect `PROFILES_BY_DIALECT` + pair validation in validateSelection/normalizeProfile; server re-validates (authoritative) | closed |
| T-13-06-02 | Tampering | Host coerces or defaults a profile on validation failure (silent fallback) | high | mitigate | Explicit MISSING_SELECTION / config error on any invalid pair; no normalizeProfile-style fallback | closed |
| T-13-06-03 | Tampering | Host dynamically pulls the profile list or shares cross-host JSON, coupling hosts or adding network | medium | mitigate | Static constants only per D-05; offline-first (PARITY-03); no network dependency in host validation | closed |
| T-13-06-04 | Tampering | Harness assertion pins the old flat list, masking a D-05 drift or failing after the legit change | high | mitigate | Same-commit rule: each host constant change updates its harness assertion (offline-smoke/launch-smoke/source-smoke) | closed |
| T-13-06-05 | Tampering | Host auto-detects dialect or guesses by extension, violating the locked selection model | high | mitigate | D-06 checkpoint confirms the transport stays unchanged; no auto-detection/extension guessing; flink selection is explicit | closed |
| T-13-06-06 | Tampering | A host maintains a second parser, diverging from the shared wire/LSP surface | high | mitigate | All hosts call fathom_*_v1 / fathom-lsp only; no local parse implementation (TOOL-05, D-04) | closed |
| T-13-06-07 | Spoofing | Host-side validation gap lets a flink file be analyzed under Doris policy | high | mitigate | Server-authoritative validate_selection/validate_dialect_profile; per-file override verified on flink files | closed |
| T-13-06-SC | Tampering | npm/pip/cargo installs | low | accept | All host deps already pinned (monaco-editor, vscode-languageclient, LSP4IJ — RESEARCH Package Legitimacy Audit) | closed |
| T-13-07-01 | Spoofing | A host smoke silently skips (VS Code unavailable / network miss) and the job prints ok | high | mitigate | Non-continue-on-error fail-closed steps; a skipped host reds the job (Pitfall 8, ECO-07 precedent) | closed |
| T-13-07-02 | Tampering | CI smoke network creep (npm registry pull / FE/cluster/DB access) | high | mitigate | Offline discipline; pinned npm cache; only the MoonBit installer curl remains (PARITY-03, A5) | closed |
| T-13-07-03 | Tampering | --update flag added to a CI job, absorbing snapshot drift | high | mitigate | No `--update` in any run line (grep gate); the packaging job is a smoke, never a snapshot writer | closed |
| T-13-07-04 | Spoofing | A flink document over a real host receives a Doris-policy result or a -32603/-32602 sentinel | high | mitigate | host-test flink-mode asserts real diagnostics/format/completion (never the sentinels) — the 13-05 real-path contract | closed |
| T-13-07-05 | Tampering | Web smoke uses a stale binding.js lacking fathom_complete_v1 | medium | mitigate | offline-smoke asserts the built artifact exports fathom_complete_v1 (13-04 output); `npm run build` before the smoke | closed |
| T-13-07-06 | Tampering | docs/CONFIGURATION.md flink pairs drift from the host constants | medium | mitigate | Same-commit doc update with the (dialect, profile) validity table matching PROFILES_BY_DIALECT | closed |
| T-13-07-07 | Tampering | Host smoke asserts the old flat profile list, masking a 13-06 drift | high | mitigate | Harnesses assert the per-dialect pairs from 13-06 (Pitfall 5) | closed |
| T-13-07-08 | Spoofing | Naming gate misses a product-level Doris remnant in the new CI/doc content | medium | mitigate | `check_naming.py` runs in the gate stack after the changes (NAME-04) | closed |
| T-13-07-SC | Tampering | npm/pip/cargo installs | low | accept | All host deps already pinned and approved (RESEARCH Package Legitimacy Audit); no new package introduced | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above `security_block_on` (high) count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|-----------|-----------|-------------|------|
| T-13-01-SC | T-13-01-SC | Zero new runtime dependencies (RESEARCH Package Legitimacy Audit N/A); all changes are in-repo MoonBit | Plan (D-08 offline policy) | 2026-08-10 |
| T-13-02-SC | T-13-02-SC | Zero new runtime dependencies (RESEARCH Package Legitimacy Audit N/A) | Plan (D-08 offline policy) | 2026-08-10 |
| T-13-03-SC | T-13-03-SC | Zero new runtime dependencies (RESEARCH Package Legitimacy Audit N/A) | Plan (D-08 offline policy) | 2026-08-10 |
| T-13-04-SC | T-13-04-SC | Zero new runtime dependencies (RESEARCH Package Legitimacy Audit N/A) | Plan (D-08 offline policy) | 2026-08-10 |
| T-13-05-SC | T-13-05-SC | Zero new runtime dependencies (RESEARCH Package Legitimacy Audit N/A) | Plan (D-08 offline policy) | 2026-08-10 |
| T-13-06-SC | T-13-06-SC | All host deps already pinned (monaco-editor, vscode-languageclient, LSP4IJ — RESEARCH Package Legitimacy Audit) | Plan (D-08 offline policy) | 2026-08-10 |
| T-13-07-SC | T-13-07-SC | All host deps already pinned and approved (RESEARCH Package Legitimacy Audit); no new package introduced | Plan (D-08 offline policy) | 2026-08-10 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-08-10 | 56 | 56 | 0 | orchestrator (L1 grep-verify) + gsd-code-reviewer (standard) |

**Verification method (ASVS L1, register authored at plan time):** all 49 `mitigate` dispositions were grep-verified against the implementation (key controls: `flink_statement_covered` gate, `FATHOM-FORMAT-001` refusal, `MAX_CANDIDATES=32`, `introduced_profile` filter, analyzer D-21 import gate, `fathom_complete_v1` in js+wasm exports, `fathom.complete.v1` in `validate_schema_version`, single `span_to_range`, host `PROFILES_BY_DIALECT`, zero `--update` in CI). The 7 `accept` dispositions are documented in the Accepted Risks Log. Independent gsd-code-reviewer (standard depth, 42 files) found 0 critical / 5 warnings / 7 info; all 5 warnings and 3 info were fixed (commit `d2927bd`); 4 accepted-deferred items documented in 13-REVIEW.md.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-08-10
