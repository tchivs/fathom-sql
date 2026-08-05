---
phase: 01-core-kernel
verified: 2026-08-03T17:08:07Z
verified_at: 2026-08-03T17:08:07Z
status: gaps_found
score: 9/11 goal-truths verified
verification_mode: re-verification, goal-backward source audit with inherited main-session gates
re_verification:
  previous_status: PARTIAL
  previous_score: 9/11 goal-truths verified
  gaps_closed:
    - "T-01-06 diagnostic statement identity is now an unsigned UInt in parser/API and regression assertions."
    - "T-01-14 metadata-aware parse_with_metadata/from_manifest validates canonical exact release and feature-introduction before parsing and passes validated context into feature gates."
  gaps_remaining:
    - "The manifest and three disk fixture files are still not consumed by the MoonBit test runtime; five embedded records are tested instead."
    - "The observed MoonBit executable version does not match the official v0.10.5 label in moon.mod."
    - "Manifest source revisions remain unavailable-offline/known-gap."
  regressions: []
blocking_findings: 0
non_blocking_boundaries: 3
overrides_applied: 0
inherited_evidence:
  - "Main session: moon check --target native: 0 errors, 116 warnings (not run by this verifier)."
  - "Main session: moon build --target native --release: 0 errors, 109 warnings (not run by this verifier)."
  - "Main session: moon test: 93 passed, 0 failed (not run by this verifier)."
  - "01-REVIEW-FIX.md iteration 13 records commit d6f5b76 and the same 0/116, 0/109, 93/93 gates; this verifier treats them as inherited."
local_commands_run:
  - "wc -l on implementation, tests, corpus, and fixture artifacts"
  - "static reads/searches of token, API, parser, tests, corpus, all four plans/summaries, REVIEW, and REVIEW-FIX"
  - "date -u for report timestamp"
not_run:
  - "moon check, moon build, moon test, formatter, linter, package installation, FE/Nereids, SQLGlot, database, network, filesystem fixture loading, or external service"
gaps:
  - truth: "Every supported and negative released corpus fixture is manifest-driven and executable through strict/editor, diagnostics, spans, and exact replay."
    status: partial
    reason: "The source artifacts and manifest schema exist, and five deterministic embedded records exercise metadata-aware parsing, but the runtime test does not open corpus/manifest.tsv or any of the three disk select-industrial.sql files."
    artifacts:
      - path: "test/parser_test.mbt"
        issue: "EmbeddedManifestFixture has five inline raw records at lines 498-550; no filesystem or manifest loader is present."
      - path: "corpus/manifest.tsv"
        issue: "15-line/14-column manifest is static Git data and has no test-runtime consumer."
      - path: "corpus/doris-2.1/select-industrial.sql"
        issue: "Released fixture exists but is not loaded by test/parser_test.mbt."
      - path: "corpus/doris-3.x/select-industrial.sql"
        issue: "Released fixture exists but is not loaded by test/parser_test.mbt."
      - path: "corpus/doris-4.x/select-industrial.sql"
        issue: "Released fixture exists but is not loaded by test/parser_test.mbt."
    missing:
      - "Either add a deterministic manifest/disk-fixture consumer with strict/editor, diagnostic, span, and replay assertions, or explicitly narrow the plan-04 executable-golden claim."
  - truth: "The pinned MoonBit toolchain metadata is reproducible and aligned with the claimed official v0.10.5 line."
    status: partial
    reason: "moon.mod records the observed executable verbatim as moon 0.1.20260724 (5f1406a 2026-07-24), while its comment labels that record the official v0.10.5 line. No toolchain identity policy has resolved the mismatch."
    artifacts:
      - path: "moon.mod"
        issue: "Observed version and official v0.10.5 label are both present but not demonstrably the same release line."
    missing:
      - "Resolve and document whether the observed executable is accepted for the v0.10.5 policy, or pin/use the requested toolchain and update the metadata."
deferred:
  - truth: "Broad reproducible official-document manifest/golden/recovery execution and coverage reporting."
    addressed_in: "Phase 2"
    evidence: "ROADMAP Phase 2 success criterion 4 explicitly publishes reproducible official-document fixture manifests, golden/recovery results, version/category coverage, and differential reports."
behavior_unverified_items: []
---

# Phase 1: Core Kernel Verification Report

**Phase Goal:** Consumers can parse an explicitly selected Doris 2.1, 3.x, or 4.x profile into a lossless, recoverable CST with precise diagnostics and industrial SELECT/expression coverage, entirely offline.

**Verified at:** 2026-08-03T17:08:07Z  
**Status:** **GAPS FOUND (0 blocking findings; 2 plan/toolchain partials and 1 provenance boundary retained)**  
**Re-verification:** Yes — after T-01-06 UInt closure (`27b6d63`) and T-01-14 metadata closure (`d6f5b76`).  
**Method:** Goal-backward static source audit. SUMMARY and REVIEW claims were treated as leads, not proof. Current source, tests, corpus, all four plans/summaries, `01-REVIEW.md`, and `01-REVIEW-FIX.md` were read. No project build/test command was run in this verifier.

## Executive Conclusion

Phase 1 的四个 roadmap success criteria 与 CORE-01..07 的核心行为在当前源码中均有实现证据；profile 入口只接受 `2.1`、`3.x`、`4.x`，工业 SELECT 使用显式 profile 的递归下降/Pratt 路径，CST 和 printer 保留源 bytes/trivia/error material，strict/editor 共享 bounded recovery，diagnostic identity 已 clean-cutover 为 `UInt`。API 的 `parse_with_metadata`/`ParseOptions::from_manifest` 也已真实接入：它在 parser 运行前校验 exact release 与 feature-introduction，随后把 validated context 传入 profile feature gate，并回传 metadata。

本报告不把计划 04 的“磁盘 manifest/fixture executable golden”声明为完成：`test/parser_test.mbt` 只执行 5 条 embedded inline records，未读取 `corpus/manifest.tsv` 或三份 `select-industrial.sql`。这是真实的 plan-level wiring gap，但不构成当前 review 的 blocking finding，Phase 2 roadmap 已明确承接更广泛的 reproducible corpus work。也不把 `moon.mod` 的 observed `0.1.20260724` 与 official `v0.10.5` label mismatch，或 manifest 的 `unavailable-offline` revision/provenance，伪装为已闭合。

`01-REVIEW.md`（2026-08-03T17:07:46Z，40 files，critical/warning/info/total 均为 0）与 `01-REVIEW-FIX.md` iteration 13 均已读取。Review 结论中的 CR-01..09、WR-01..38、T-01-06、T-01-14 CLOSED 与本报告当前源码证据一致；review 明确将磁盘 fixture、toolchain、provenance 作为 non-active boundaries，而非 active finding。

## Goal Truths

| # | Goal truth | Status | Evidence |
|---|---|---|---|
| 1 | Consumer chooses exactly Doris 2.1/3.x/4.x and no generic fallback is silently used. | **VERIFIED** | `token/token.mbt:3-7,196-202` defines only three profiles; `api/api.mbt:64-75,348-356` rejects unknown/mysql and unknown mode. |
| 2 | Industrial documented SELECT/expression forms use one explicit-profile path. | **VERIFIED (inherited behavior evidence)** | `parser/parser.mbt` has one recursive-descent SELECT/query path plus centralized Pratt expression handling. Tests cover CTE/subquery, hints, joins, predicates/functions, windows, grouping sets/ROLLUP/CUBE, TABLET/SAMPLE/TABLESAMPLE, OUTFILE and UNION chains; main session reports 93/93, not rerun here. |
| 3 | CST traversal and replay preserve original bytes, spelling, comments, whitespace, newline style, unknown/error material, and bounded spans. | **VERIFIED (inherited behavior evidence)** | `source/source.mbt` owns raw bytes and checked spans; `syntax` leaves are source-backed; `api.ParseResult` stores root `source_bytes`; `printer` replays source spans. Existing source/parser/recovery assertions cover BOM, CRLF, Unicode/emoji, invalid UTF-8, unknown/error and zero-width MISSING material; the 93/93 gate is inherited. |
| 4 | Incomplete/malformed input yields bounded recoverable CST plus explicit missing/error/skipped nodes and linked diagnostics. | **VERIFIED (inherited behavior evidence)** | `parser/parser.mbt:1589-1688` applies byte/token/recursion/recovery/diagnostic limits and emits source-backed SKIPPED/MISSING/ERROR nodes and `DORIS-PARSE-004`; `test/recovery_test.mbt` covers caps, deep nesting, malformed lexical material, replay and statement identity. |
| 5 | Diagnostics expose severity, stable code, message, expected class, byte span, and unsigned statement identity. | **VERIFIED** | `parser/parser.mbt:88-95` and `api/api.mbt:170-178` expose `statement_id : UInt`; parser initializes/increments `0U`/`1U` at `1623-1651`. Tests assert snapshot reset, monotonic IDs and lexical/resource paths. T-01-06 commit `27b6d63` removes the former signed-Int risk. |
| 6 | Source ownership is immutable/root-only and nodes do not duplicate source payloads. | **VERIFIED** | `source/source.mbt:86-115` stores one bytes snapshot plus LineIndex; syntax nodes/leaves store spans/text lengths; `api.ParseResult.source_bytes` is the root payload and `has_root_only_source`/`all_spans_in_bounds` are asserted. |
| 7 | Resource limits are finite and preserve source-backed remainder/replay. | **VERIFIED (inherited behavior evidence)** | `api.ParseLimits` and parser limits expose max bytes/tokens/recursion/recovery/diagnostics; recovery tests assert `DORIS-PARSE-004`, SKIPPED remainder, bounded spans and exact replay. Main-session gates are inherited, not rerun. |
| 8 | Source/lexer preserves invalid encoding and unterminated material without normalization or non-progress. | **VERIFIED (inherited behavior evidence)** | `lexer/lexer.mbt` retains invalid runs as source-backed error tokens and bounds quoted/comment scans; `test/recovery_test.mbt:111-162,241-249` asserts `DORIS-PARSE-003`, progress, spans and replay. |
| 9 | Released corpus metadata is complete and honest, with executable metadata-aware coverage. | **PARTIAL** | `corpus/manifest.tsv` has 14 columns and 14 rows across 2.1/3.x/4.x, exact release/introduction, URLs, dates, modes/statuses and explicit known gaps. `test/parser_test.mbt:463-577` executes five embedded records through `parse_with_metadata`, checking validity, profile/release/introduction round-trip, diagnostics, spans and replay; it does not consume the manifest or disk fixtures. |
| 10 | Parser is synchronous/offline and independent of FE/DB/filesystem/network/runtime-specific parser implementations. | **VERIFIED** | Package manifests form a local source→token→lexer→syntax/parser→api/printer graph. Static inspection found no FE, database, network, filesystem loader, host, CLI, LSP, Wasm/JS or runtime-specific parser path. Differential rows explicitly remain offline/advisory. |
| 11 | Pinned toolchain metadata is reproducible and aligned with claimed official line. | **PARTIAL** | `moon.mod:1-4` records `moon 0.1.20260724 (5f1406a 2026-07-24)` verbatim but labels it official v0.10.5. The mismatch is disclosed, not resolved. |

**Score:** **9/11** goal truths verified. Truth 9 remains partial only for disk manifest/fixture execution; its metadata-aware API/embedded records are verified. Truth 11 remains a documented toolchain-policy boundary. `blocking_findings: 0`; these are not represented as closed.

## Four Roadmap Success Criteria

| # | Success criterion | Verdict | Evidence / limitation |
|---|---|---|---|
| 1 | Consumer chooses a Doris profile and parses documented SELECT, JOIN, CTE, window, grouping, set-operation, hint and expression forms without generic fallback. | **PASS for core goal; metadata gate CLOSED; disk fixture link PARTIAL** | Explicit profile API, rejection tests, industrial parser/tests, `parse_with_metadata`, and 5 embedded records provide current evidence. Exact metadata mismatch/unsupported-introduction rows fail before parse (`test/parser_test.mbt:553-565`). The three disk fixtures are not loaded. |
| 2 | Traversable CST/replay preserves bytes, spelling, comments, whitespace, newlines, unknown/error material and spans. | **PASS** | Source-backed spans/leaves, root-only source payload, printer paths and inherited tests cover valid, malformed, Unicode, CRLF, BOM and invalid-byte replay. |
| 3 | Incomplete/malformed SQL yields bounded recoverable CST with explicit missing/error/skipped nodes and statement-linked diagnostics. | **PASS** | Finite limits, progress/recovery synchronization, explicit node kinds and UInt statement identity are implemented; recovery tests and inherited 93/93 gate cover the behavior. |
| 4 | Parsing/diagnostics run fully offline without FE, DB or runtime-specific parser implementation. | **PASS with provenance boundary** | Local-only package graph and static scan show no prohibited runtime dependency. FE/Nereids and SQLGlot remain advisory/not-run-offline; manifest SHA/provenance is `unavailable-offline`, which affects reproducibility evidence, not runtime offline operation. |

Roadmap core behavior is present and all four criteria pass at the goal level. The report remains `gaps_found` because the plan-04 executable disk-fixture link and plan-01 toolchain alignment are not silently promoted to PASS; both have zero active review findings and the corpus expansion is explicitly deferred to Phase 2.

## Metadata-Aware API and Embedded Fixture Verification

| Check | Evidence | Status |
|---|---|---|
| Canonical profile metadata | `token/token.mbt:9-16,107-131` defines exact release and controlled feature-introduction for all three profiles. | VERIFIED |
| Manifest metadata validation | `token/token.mbt:55-80`, `api/api.mbt:93-112` reject unknown profile, unsupported introduction and exact release/introduction mismatch before parsing. | VERIFIED |
| Parser gate propagation | `parser/parser.mbt:335-362` calls `ValidatedProfileContext::supports`; `api.parse` passes the validated context and emits result metadata. | VERIFIED |
| Public metadata entry point | `api/api.mbt:299-311` exposes `parse_with_metadata`; no fallback to `parse_with_ids` occurs after metadata errors. | VERIFIED |
| Embedded records | `test/parser_test.mbt:498-550` contains exactly five inline records: 2.1, 3.x, 4.x valid paths plus 2.1 invalid encoding and 4.x editor recovery. | VERIFIED (embedded scope) |
| Mismatch/unknown/unsupported rejection | `test/parser_test.mbt:553-577` asserts pre-parse errors for wrong release, wrong introduction, unsupported introduction, unknown profile and canonical metadata. | VERIFIED |
| Disk manifest/fixture linkage | No `corpus/manifest.tsv` or `corpus/doris-*/select-industrial.sql` path is referenced by the test loader; inline `raw` bytes are used instead. | **NOT WIRED / non-blocking plan gap** |

## Required Artifacts — Levels 1–4

| Artifact | L1 exists | L2 substantive | L3 wired | L4/data flow | Result |
|---|---:|---:|---:|---:|---|
| `moon.mod` | yes | yes: valid module and recorded version output | yes: consumed at MoonBit build boundary (inherited gate) | n/a | PARTIAL: label/toolchain boundary |
| `source/source.mbt` | yes | yes: SourceText, Span, LineIndex and pre-allocation byte limit | yes: imported by token/lexer/parser/api/printer | caller bytes flow to token spans and results | PASS |
| `token/token.mbt` | yes | yes: three profiles, canonical metadata, feature gates and classification | yes: imported by lexer/parser/API/tests | selected profile/validated metadata flow to parser gates | PASS |
| `lexer/lexer.mbt` | yes | yes: trivia/literal/unknown/error scanning and token cap | yes: parser calls lexer; tests call lexer | token spans slice source snapshot | PASS |
| `syntax/syntax.mbt` | yes | yes: immutable node/leaf kinds and Missing/Error/Skipped | yes: parser constructs nodes; API projects them | children retain source spans only | PASS |
| `parser/parser.mbt` | yes | yes: industrial SELECT/Pratt grammar, metadata context, recovery and limits | yes: API calls parser and tests exercise API/parser | profile/source/limits/metadata flow to CST/diagnostics | PASS |
| `api/api.mbt` | yes | yes: options, metadata validation, result, root payload, UInt diagnostics | yes: tests and printer consume result | source/metadata/diagnostics flow to transport | PASS |
| `printer/printer.mbt` | yes | yes: source-backed lossless and primitive replay | yes: tests/recovery invoke replay | leaf/root source produces original bytes | PASS |
| `test/source_test.mbt`, `test/parser_test.mbt`, `test/recovery_test.mbt` | yes | yes: focused source/parser/recovery and metadata assertions (31/997/249 lines) | yes: package includes them; inherited 93-test gate includes them | assertions exercise core and embedded metadata records, not disk corpus | PASS with fixture-scope boundary |
| `corpus/manifest.tsv`, `coverage.tsv`, `differential.tsv` | yes | yes: complete schema/data and explicit known gaps | PARTIAL: static data, no runtime loader | rows do not flow into test parser calls | PARTIAL |
| `corpus/doris-{2.1,3.x,4.x}/select-industrial.sql` | yes | yes: released-profile SQL examples (13/11/16 lines) | ORPHANED from test runtime | no source path reference or fixture read | PARTIAL |

## Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `source/source.mbt` | `lexer/lexer.mbt` | lexer scans immutable snapshot and emits spans | WIRED | Lexer receives SourceText and validates token spans. |
| `token/token.mbt` | `lexer/lexer.mbt` | profile/raw token metadata | WIRED | Lexer accepts DorisProfile and stores it on tokens. |
| `parser/parser.mbt` | `syntax/syntax.mbt` | CST and recovery nodes | WIRED | Parser constructs Select/Statement/Error/Skipped/Missing nodes. |
| `syntax/syntax.mbt` | `printer/printer.mbt` | source-backed leaf walk | WIRED | Printer walks children and source spans. |
| `api/api.mbt` | `parser/parser.mbt` | options/limits/validated metadata/result conversion | WIRED | API validates limits and metadata, calls `parse_with_limits_context`, and maps diagnostics. |
| `test/parser_test.mbt` | `api.parse_with_metadata` | embedded fixture metadata route | WIRED | Five embedded records execute through metadata-aware parse, replay, span and diagnostic checks. |
| `api.parse_with_metadata` | `parser.feature_allowed` | validated profile context | WIRED | `parse` passes `profile_context`; parser feature gates use `context.supports`. |
| `corpus/manifest.tsv` | `test/parser_test.mbt` | manifest-driven loader | **NOT WIRED** | No path read; tests use inline `EmbeddedManifestFixture` records. |
| `corpus/manifest.tsv` | `parser/parser.mbt` | exact release/feature metadata gate | **PARTIAL** | Metadata gate is real through canonical API inputs, but TSV fields are not automatically loaded into those inputs. |
| `test/parser_test.mbt` | disk SQL fixtures | fixture replay/golden execution | **NOT WIRED** | No disk fixture filename/reference appears in the runtime test path. |

## Data-Flow Trace

| Consumer | Dynamic data | Source | Flow status |
|---|---|---|---|
| API `ParseResult` | `source_bytes`, root, diagnostics, profile metadata | caller Bytes → SourceText → lexer/parser → primitive conversion | FLOWING |
| Metadata-aware result | exact release/introduction and feature gate | caller/manifest-shaped arguments → `from_manifest` → validated context → parser/result | FLOWING |
| CST printer | leaf spans/trivia/errors | SourceText snapshot and SyntaxNode children | FLOWING |
| Recovery result | skipped remainder and resource diagnostics | token/byte/recursion/recovery limits → `DORIS-PARSE-004` + source-backed nodes | FLOWING |
| Embedded fixture checks | inline raw bytes and expected metadata/validity | five in-source records → `parse_with_metadata` → replay/spans/diagnostics | FLOWING (embedded only) |
| Corpus reports | fixture/status/provenance rows | static TSV files | STATIC; not consumed by tests |

## Behavioral Spot-Checks

| Behavior | Evidence | Status |
|---|---|---|
| Profile rejection and version-invalid diagnostics | `token` profile tests; parser QUALIFY/TABLET tests; `test/parser_test.mbt:199-224,253-267`; inherited 93/93 | PASS (inherited) |
| Exact release/feature mismatch rejection before parse | `test/parser_test.mbt:553-565` asserts `ProfileMetadataMismatch`, `UnsupportedFeatureIntroduction`, and `UnknownProfile` | PASS (inherited) |
| Embedded metadata-aware replay across 2.1/3.x/4.x | `test/parser_test.mbt:498-550` checks five records, replay, validity, metadata fields, diagnostic namespace and spans | PASS (inherited) |
| Exact replay over valid, malformed, Unicode, CRLF, BOM, invalid bytes, unknown/error material | source/parser/recovery/printer tests; inherited 93/93 | PASS (inherited) |
| Bounded token/byte/recursion/recovery/diagnostic limits | `test/recovery_test.mbt:27-249`; inherited 93/93 | PASS (inherited) |
| UInt statement identity reset/monotonicity and non-empty segment mapping | parser/recovery tests with `0U`/`1U`; `27b6d63`; inherited 93/93 | PASS (inherited) |
| Industrial SELECT path | parser tests and three static fixture files; inherited 93/93 | PASS for inline/parser path; disk fixture execution not proven |
| Manifest/disk fixture loader | `test/parser_test.mbt` has no filesystem/manifest read and uses embedded records | **FAIL for plan link / PARTIAL phase contract** |

## Probe / Build Evidence Boundary

No phase probe script was declared or discovered in the four plans/summaries. This verifier did not run MoonBit commands. The inherited main-session evidence is:

- `moon check --target native`: **0 errors, 116 warnings** — inherited, not rerun.
- `moon build --target native --release`: **0 errors, 109 warnings** — inherited, not rerun.
- `moon test`: **93 passed, 0 failed** — inherited, not rerun.

No formatter, linter, package installation, FE/Nereids, SQLGlot, database, network, filesystem fixture loading, or external service was run.

## Requirements Coverage

| Requirement | Status | Evidence |
|---|---|---|
| CORE-01 | **SATISFIED** | Explicit 2.1/3.x/4.x API, unknown/MySQL rejection, metadata mismatch rejection and profile-aware QUALIFY/TABLET diagnostics. |
| CORE-02 | **SATISFIED** | Immutable source-backed CST, trivia/error/skipped leaves, spans/text lengths, root-only source bytes and bounds/replay tests. |
| CORE-03 | **SATISFIED** | Printer/source/recovery assertions preserve bytes across comments, whitespace, newlines, Unicode, invalid/unknown/error/incomplete material. |
| CORE-04 | **SATISFIED_WITH_EMBEDDED_FIXTURE_BOUNDARY** | Single industrial SELECT path and named forms are covered by parser/inline tests; released disk fixture files are not loaded by tests. |
| CORE-05 | **SATISFIED** | Severity/code/message/expected class/span and UInt statement identity are present; T-01-06 is closed. |
| CORE-06 | **SATISFIED** | Shared strict/editor CST family, explicit Missing/Error/Skipped nodes, bounded recovery and malformed-input coverage. |
| CORE-07 | **SATISFIED** | Pure local package graph and static scan show no FE/DB/network/filesystem/runtime-specific parser dependency. |

No Phase 1 requirement is orphaned. All four plans collectively declare and cover CORE-01..07. DORIS-01..04, CORP-01..04, ANLY-01, FMT-01..04, and ECO-01..07 are assigned to later roadmap phases and are not counted as Phase 1 requirements.

## Threat-Model Mitigation Audit

This is a verifier-side static audit, not a replacement for the separately requested security-auditor verdict.

| Threat ID | Mitigation status | Evidence / remaining risk |
|---|---|---|
| T-01-01 | MITIGATED | Pre-allocation max-byte check, progressing lexer, token/recovery/depth/diagnostic caps and bounded replay tests. |
| T-01-02 | MITIGATED | Exactly three profile constructors, unknown rejection and no generic fallback. |
| T-01-03 | MITIGATED | Invalid UTF-8 remains source-backed ERROR material with stable lexical/parser diagnostics and replay. |
| T-01-04 | **NON-BLOCKING BOUNDARY** | Exact observed executable output is recorded, but the “official v0.10.5 line” label conflicts with `0.1.20260724`; policy remains unresolved. |
| T-01-05 | MITIGATED | Singular root source payload and descendant span bounds. |
| T-01-06 | **CLOSED** | Public parser/API diagnostic identity is `UInt`; `0U`/`1U` snapshot-local tests and `27b6d63` close the former signed-Int risk. |
| T-01-07 | MITIGATED | Progress/error hooks and finite recursion/recovery/diagnostic limits. |
| T-01-08 | ACCEPTED | Replay exposes only caller-provided bytes; no secret/I/O boundary exists in core. Formal low-risk log remains with security auditor. |
| T-01-09 | MITIGATED | Recovery-step cap, synchronization and source-backed remainder. |
| T-01-10 | MITIGATED | Recursion-depth cap and deterministic resource diagnostic. |
| T-01-11 | MITIGATED | Strict/editor share CST and diagnostics; recovery does not promote validity. |
| T-01-12 | MITIGATED | Checked spans and source-order snapshot-local UInt identities. |
| T-01-13 | ACCEPTED | Error/skipped retention returns caller bytes only; no secret store or I/O. Formal low-risk log remains with security auditor. |
| T-01-14 | **CLOSED** | `d6f5b76` adds canonical exact-release/feature-introduction validation, `parse_with_metadata`, validated context propagation and rejection tests. |
| T-01-15 | MITIGATED | Existing byte/token/depth/recovery/diagnostic budgets cover industrial/nested paths. |
| T-01-16 | **NON-BLOCKING PROVENANCE BOUNDARY** | Manifest records URL/date/heading/fence/status but revision is `unavailable-offline`; no verifiable pinned commit exists. |
| T-01-17 | ACCEPTED | Differential rows are advisory-only and not-run-offline; released-doc records remain acceptance authority. Formal low-risk log remains with security auditor. |
| T-01-SC | ACCEPTED | No package installation or third-party runtime introduced. |

## Anti-Patterns and Review Cross-Check

- Static scans of source, tests and corpus found no unreferenced `TODO`, `FIXME`, `XXX`, `HACK`, placeholder, or empty implementation markers.
- No static empty-data rendering or console-only handler exists; this is a library/core, not a UI.
- Final `01-REVIEW.md` reports no active CR-01..09, WR-01..38, T-01-06 or T-01-14 findings; frontmatter counts are critical 0, warning 0, info 0, total 0. The current source inspection confirms the UInt and metadata closures rather than treating review claims as proof.
- The intentional offline provenance disposition remains visible in TSV (`unavailable-offline`, `known-gap`) and is not converted to a reproducibility PASS.
- `EmbeddedManifestFixture` is substantive and wired, but it is not mislabeled as a disk manifest loader; the missing disk linkage is reported above.

## Gaps and Recommended Closure

1. **Keep corpus scope honest / Phase 2 handoff.** Add a deterministic manifest/disk-fixture consumer and execute tracked rows through strict/editor, diagnostics, spans and replay, or explicitly narrow plan 04's executable-golden wording. Phase 2 success criterion 4 directly covers this broader corpus contract.
2. **Resolve compiler identity policy.** State whether `moon 0.1.20260724` is accepted for the documentation's v0.10.5 line; otherwise pin/use the requested toolchain and update `moon.mod`.
3. **Later provenance closure.** Replace `unavailable-offline` with a verifiable released-document revision when available; retain `known-gap` until then. This is not evidence that offline parsing depends on network access.
4. **Accepted low-risk formal log.** Security auditor should record T-01-08, T-01-13 and T-01-SC accepted dispositions in the requested `SECURITY.md` process; this report does not create or modify that file.

---

_Verified: 2026-08-03T17:08:07Z_  
_Verifier: Claude (gsd-verifier)_  
_Status: GAPS FOUND — roadmap/core behavior is present and all active review findings are closed, while disk fixture wiring and reproducibility boundaries remain explicitly open._
