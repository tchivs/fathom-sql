# Roadmap: Fathom SQL Parser SDK

## Overview

v1.0 shipped the lossless CST core, Doris DML/DDL + corpus, configurable formatting + CLI, and Native LSP / JS-Wasm facade / Web-Monaco / VS Code integration (27/27 requirements). v2.0 (redefined 2026-08-06) turns the single-dialect Doris parser into a multi-dialect SQL SDK: a dialect abstraction layer, a Flink SQL dialect across the whole toolchain, and product-neutral naming (binaries/schema/error codes/extensions/docs). The former v2.0 analysis-layer scope (ANAL/LINT/LINE/FING/EDIT) is deferred to v3.0.

## Milestones

### ✅ v1.0: milestone — SHIPPED 2026-08-05

Doris SQL Parser SDK 首个可发布里程碑。无损 CST 内核、SELECT/DML/DDL 覆盖、版本化官方语料库、可配置格式化与 CLI、Native LSP / JS-Wasm facade / Web-Monaco / VS Code 集成。27/27 v1 需求验证通过,全部离线可用。

- **Archive:** [v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md) · [v1.0-REQUIREMENTS.md](milestones/v1.0-REQUIREMENTS.md) · [v1.0-MILESTONE-AUDIT.md](v1.0-MILESTONE-AUDIT.md)
- **Status:** SHIPPED (override_closeout — 5 documented verification overrides in STATE.md Deferred Items)

<details>
<summary>v1.0 Phase Details (archived)</summary>

### Phase 1: Core Kernel

**Goal**: Consumers can parse an explicitly selected Doris 2.1, 3.x, or 4.x profile into a lossless, recoverable CST with precise diagnostics and industrial SELECT/expression coverage, entirely offline.
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: CORE-01..CORE-07
**Status:** Complete 2026-08-03 (4/4 plans)

### Phase 2: Doris Completeness and Corpus

**Goal**: Users can parse version-supported Doris scripts and warehouse-specific DML/DDL with localized errors, while maintainers and consumers can inspect reproducible coverage and the syntax-only/analyzer boundary.
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: DORIS-01..04, CORP-01..04, ANLY-01
**Status:** Complete 2026-08-04 (6/6 plans)

### Phase 3: Formatting and Safe Edits

**Goal**: Users can choose exact source replay or a deterministic, configurable, comment-preserving canonical rendering and invoke it safely from the `doris-sql format` command.
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: FMT-01..04
**Status:** Complete 2026-08-04 (4/4 plans)

### Phase 4: Ecosystem and Multi-Target Delivery

**Goal**: Editors, web applications, and automation can use one versioned Doris parser through Native LSP/CLI and stable Wasm/JavaScript facades with consistent results across targets.
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: ECO-01..07
**Status:** Complete 2026-08-05 (5/5 plans)

</details>

## v2.0: Multi-Dialect: Flink SQL & Neutral Naming — PLANNING

v2.0 将已交付的单方言 Doris SDK 升级为显式选择的多方言 SQL SDK：共享无损 CST/source/token/recovery 机制，按方言隔离词法、关键字、文法、诊断、formatter 与 completion policy，并以同一套 Native/JavaScript/linear-Wasm API 服务 Doris 与 Flink。产品公共身份一次性中立化为 `fathom/sql`、`fathom-sql`、`fathom-lsp`、`fathom.*.v1` 与 `FATHOM-*`；Doris 仅作为显式 dialect/profile/corpus/provenance 保留，不提供旧别名、自动方言检测、generic fallback 或默认 transpilation。

**Requirements:** [REQUIREMENTS.md](REQUIREMENTS.md) — 24 v2.0 requirements, all mapped below
**Research:** [research/SUMMARY.md](research/SUMMARY.md) — research-derived order and hard gates

## Phases

- [x] **Phase 9: Dialect Boundary and Neutral Naming** - Establish explicit dialect/profile context, isolate Doris policy, freeze the Doris baseline, and complete the clean product-identity cutover. (completed 2026-08-07)
- [x] **Phase 10: Flink Release Profiles and Lexical Core** - Lock Flink release/Calcite contracts and deliver profile-specific Flink lexical behavior. (completed 2026-08-07)
- [ ] **Phase 11: Flink Grammar and Recoverable CST** - Deliver Flink statement/DDL/window/pattern grammar with strict/editor lossless recovery.
- [ ] **Phase 12: Cross-Dialect Corpus and Parity Gates** - Turn pinned sources and the Doris baseline into reproducible cross-dialect and cross-backend release gates.
- [ ] **Phase 13: Toolchain and Editor Packaging** - Expose Flink through formatter, analyzer, completion, CLI/LSP, JS/Wasm, Web, VS Code, and IntelliJ.

## Phase Details

### Phase 9: Dialect Boundary and Neutral Naming

**Goal**: Users can explicitly select Doris or Flink and its valid profile at every public boundary, while the SDK exposes one neutral product identity and preserves the shipped Doris behavior.
**Mode**: mvp
**Depends on**: Phase 4 (v1.0 shipped)
**Requirements**: DIALECT-01, DIALECT-02, DIALECT-03, DIALECT-04, NAME-01, NAME-02, NAME-03, NAME-04
**Success Criteria** (what must be TRUE):

  1. User receives a structured configuration error for missing, unknown, or conflicting dialect/profile selection through API, CLI, LSP, JS/Wasm, Web, VS Code, and IntelliJ; no entry point silently detects or falls back to another dialect.
  2. The selected dialect controls independent keyword classification and an explicit statement/clause route, so Doris and Flink policies cannot change one another's identifier acceptance or recovery behavior.
  3. Parse, format, completion, LSP, and serialized results expose dialect, profile, exact-release metadata, strict/editor mode, byte spans, statement identity, and stable `FATHOM-*` diagnostics.
  4. Public imports, binaries, exports, schemas, errors, LSP identity, editor settings, release assets, and documentation use neutral `fathom` naming with no old aliases; `Doris` remains only as a dialect/profile/corpus/provenance value.

**Validation**: Freeze the v1 Doris 2.1/3.x/4.x valid, invalid, recovery, CST/span, diagnostic, formatter, completion, CLI, LSP, and schema outputs before migration; compare the post-migration outputs byte-for-byte/shape-for-shape, run the explicit-selection matrix, and enforce a repository naming forbidden/allowlist inventory.
**Research flags**: No new external technology choice is required; planning must still inventory every public import/export/asset and distinguish product-name remnants from allowed Doris dialect/provenance references.
**Plans**: 7/7 plans executed

- [x] 09-01-PLAN.md
- [x] 09-02-PLAN.md
- [x] 09-03-PLAN.md
- [x] 09-04-PLAN.md
- [x] 09-05-PLAN.md
- [x] 09-06-PLAN.md
- [x] 09-07-PLAN.md

### Phase 10: Flink Release Profiles and Lexical Core

**Goal**: Users can select an auditable Flink release profile whose lexical behavior is independent from Doris and grounded in the matching Flink/Calcite contract.
**Mode**: mvp
**Depends on**: Phase 9
**Requirements**: FLINK-01
**Success Criteria** (what must be TRUE):

  1. User can select `flink-2.3.0` as the primary profile or `flink-2.1.3`/`flink-1.20.5` regression profiles, while an unsupported profile is rejected explicitly.
  2. Each accepted profile reports its release source/tag/commit, Calcite version, parser configuration, and feature metadata; the exact Calcite pin for 2.1.3 is extracted from that release rather than inferred.
  3. Flink input receives release-specific comment, quote, literal, operator, identifier, and reserved/non-reserved/contextual classification behavior with source trivia/spans preserved; conflict cases have explainable snapshots rather than Doris-policy leakage.

**Validation**: Verify pinned Flink source archives and checksums, read each release parser configuration/POM, and exercise a lexical conflict matrix for comments, quoting, X/U& literals, identifiers, operators, and unknown profiles in both dialects. Do not use moving `dev`/`stable` docs or a Flink/Calcite runtime.
**Research flags**: Confirm the exact `flink-2.1.3` Calcite version/config from its release POM/source; validate double-quote, `#`, `//`, X/U&/B literal behavior with executable release fixtures rather than Calcite folklore.
**Plans**: 3/3 plans executed
**Wave 1**

- [x] 10-01-PLAN.md — Flink profile identity (flink-2.3.0/2.1.3/1.20.5 + Calcite pins) + end-to-end selection unlock + provenance/flink-lexical scaffold (tracer)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 10-02-PLAN.md — Flink lexical core: quoting, literals, operators, identifiers + conflict-matrix snapshots

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 10-03-PLAN.md — Flink keyword classification per release + provenance attachments

### Phase 11: Flink Grammar and Recoverable CST

**UI hint**: no
**Goal**: Users can parse everyday Flink SQL and its distinctive DDL/window/pattern constructs into a lossless, bounded, recoverable CST without changing Doris acceptance or diagnostics.
**Mode**: mvp
**Depends on**: Phase 10
**Requirements**: FLINK-02, FLINK-03, FLINK-04, FLINK-05, FLINK-06, CST-01
**Success Criteria** (what must be TRUE):

  1. User can parse Flink SELECT/CTE/JOIN/aggregation/set operations/expressions/types, INSERT/UPDATE/DELETE, EXPLAIN/SHOW/DESCRIBE/ANALYZE with localized strict/editor diagnostics.
  2. User can inspect structured CST for Flink Catalog/DATABASE/TABLE/VIEW/FUNCTION DDL and CREATE TABLE physical, metadata, computed, WATERMARK, primary-key, partition/distribution, connector-options, LIKE, and AS forms.
  3. User can inspect source-backed Window TVF CST for TUMBLE/HOP/CUMULATE/SESSION and syntax-level MATCH_RECOGNIZE for PATTERN/DEFINE/MEASURES/skip policy/variables/quantifiers, without a planner or execution-equivalence claim.
  4. Strict and editor mode preserve comments, whitespace, newlines, unknown/error/missing/skipped material, source bytes, and spans in a bounded recoverable CST; lossless replay is byte-identical and Flink-only syntax is rejected in Doris mode (and vice versa) with stable diagnostics.

**Validation**: Use pinned release grammar positives, negatives, incomplete inputs, and recovery fixtures; assert bounded progress, source-backed nodes, strict/editor shape parity, lossless replay, and bidirectional dialect-negative gates. Re-run the frozen Doris baseline before accepting any shared parser/CST change.
**Research flags**: Reconcile each release's `flink-sql-parser` productions with matching Calcite tests; define the supported/known-limitation subset for Window TVF and MATCH_RECOGNIZE, especially nested recovery and planner-prerequisite cases.
**Plans**: 1/4 plans executed
**Wave 1**

- [x] 11-01-PLAN.md — Phase one-way gates (D-02 CST shape, D-04 FATHOM-PARSE-009) + FLINK-02 core-query tracer (real parse_flink_segment dispatch, precedence dialect arm, 008 retirement, flink-grammar snapshot namespace)

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 11-02-PLAN.md — FLINK-02 DML + auxiliary statements (INSERT/UPSERT/UPDATE/DELETE, EXPLAIN/SHOW/DESCRIBE/ANALYZE, USE/SET/RESET) + Flink expression/type breadth

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 11-03-PLAN.md — FLINK-03/04 Catalog/DDL entry points + CREATE TABLE complex forms (four-column body, WATERMARK, constraints, table-level clauses, LIKE/AS, DDL negative-gate matrix)

**Wave 4** *(blocked on Wave 3 completion)*

- [ ] 11-04-PLAN.md — FLINK-05/06 Window TVF (TUMBLE/HOP/CUMULATE/SESSION) + syntax-level MATCH_RECOGNIZE + supported/known-limitation subset freeze

### Phase 12: Cross-Dialect Corpus and Parity Gates

**Goal**: Maintainers can audit reproducible Doris/Flink coverage and release only when dialect behavior and cross-backend serialized results remain within explicit parity contracts.
**Mode**: standard
**Depends on**: Phase 11
**Requirements**: CORPUS-01, PARITY-01, PARITY-02, PARITY-03
**Success Criteria** (what must be TRUE):

  1. Maintainer can inspect a release-pinned Flink corpus manifest containing release/tag/commit, Calcite version/config, source URL/heading, retrieval date, hash, expected status, and positive/negative/recovery/known-limitation/catalog/planner categories.
  2. Doris 2.1/3.x/4.x valid, invalid, recovery, CST/span, diagnostic, formatter, and completion behavior remains equal to the frozen baseline, or every intentional difference is explicitly recorded and approved.
  3. The same fixture produces byte-identical serialized results, diagnostics, spans, and lossless replay across Native, JavaScript, and linear-Wasm targets.
  4. Offline CI/release checks use only pinned artifacts and distinguish parser acceptance from catalog/planner/engine semantic prerequisites for both dialects, without Doris FE, Flink cluster, database, or network runtime access.

**Validation**: Run an offline manifest/hash verifier, frozen Doris diff harness, cross-dialect positive/negative/recovery snapshots, and Native/JS/linear-Wasm serialized comparisons; keep source provenance and docs-vs-parser conflicts visible rather than bulk-updating snapshots.
**Research flags**: Design the auditable extraction/diff workflow, resolve docs/source/Calcite conflicts, and define category semantics so generic SQL acceptance is never reported as Flink engine support.
**Plans**: TBD

### Phase 13: Toolchain and Editor Packaging

**Goal**: Users can use the selected Flink or Doris dialect through the complete neutral formatter, analyzer, completion, CLI/LSP, Web, VS Code, and IntelliJ toolchain.
**Mode**: standard
**Depends on**: Phase 12
**Requirements**: TOOL-01, TOOL-02, TOOL-03, TOOL-04, TOOL-05
**Success Criteria** (what must be TRUE):

  1. User can canonical-format supported Flink CST separately from lossless replay, while unsafe error/missing/skipped material returns an explicit refusal and no partial output.
  2. User receives bounded, dialect/profile-aware syntax completion for Flink keywords, DDL, WATERMARK, Window TVF, and MATCH_RECOGNIZE contexts, and can run syntax-only Flink analysis with optional catalog metadata without changing parser validity.
  3. User can run `fathom-sql parse|format|lsp --dialect flink` and `fathom-lsp` end to end with diagnostics, formatting, completion, UTF-16 positions, and document-level dialect selection.
  4. User can use the same dialect-aware API/schema through JS/linear-Wasm, Web/Monaco, VS Code, and IntelliJ; each host selects Doris or Flink per file/session and does not maintain a second parser implementation.

**Validation**: Exercise refusal and idempotence fixtures, bounded completion contexts, analyzer catalog/no-catalog cases, Native CLI/LSP protocol flows, JS/linear-Wasm facade calls, and real Web/Monaco/VS Code/IntelliJ artifact smoke; verify document revision/stale-response and selection-conflict cases plus the neutral naming gate.
**Research flags**: Verify MoonBit primitive JS/linear-Wasm ABI and JSON Unicode/size/malformed-input behavior; confirm LSP UTF-16 and selection precedence in real hosts and run final VS Code/IntelliJ/Web packaging smoke.
**Plans**: TBD

## v3.0: Analysis and Intelligence — PLANNING (deferred)

> **DEFERRED 2026-08-06:** formerly v2.0; deferred when v2.0 was redefined as Multi-Dialect. Requirements archived at [milestones/v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md).

Doris SQL Parser SDK 从语法层扩展到语义与分析层:catalog 名字解析、Doris 专属 Lint、列级血缘、跨后端稳定指纹,以及基准门控的增量解析;并在首个阶段收尾 v1.0 遗留验证项(VS Code 宿主验证、linear-Wasm CI 步骤)。

- **Requirements:** [milestones/v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md) — 7 requirements (CLOSE-01/02, ANAL-01, LINT-01, LINE-01, FING-01, EDIT-01)
- **Research:** [milestones/v1.0-research/SUMMARY.md](milestones/v1.0-research/SUMMARY.md) — v1/v2 analysis-feature research (archived 2026-08-06)

### Phase 5: Closeout and Analysis Foundation

**Goal**: 收尾 v1.0 两项遗留验证(人工 VS Code 宿主验证 + linear-Wasm CI 运行时执行),并把 `analyzer/` 从最小 catalog 边界扩展为可用的 catalog 名字解析与类型诊断(ANAL-01)。
**Mode:** standard
**Depends on**: Phase 4 (v1.0)
**Requirements**: CLOSE-01, CLOSE-02, ANAL-01
**Status:** Not started

Success criteria:

1. User can verify the shipped VS Code extension on a machine with VS Code — it connects to the Native LSP over the standard client protocol and exposes Doris diagnostics, comment-preserving formatting, and completion with the documented single-string `positionEncoding` (CLOSE-01).
2. Release CI includes a linear-Wasm execution step: `moon build --target wasm` runs the parity fixture suite and produces byte-identical serialized output to Native and JS (CLOSE-02).
3. User receives catalog-backed name resolution for Doris tables, columns, functions, and scopes — qualified/unqualified refs, aliases, CTEs, subqueries, star expansion with catalog — with source spans preserved on every binding (ANAL-01).
4. Name resolution matches Doris case-insensitive identifier semantics while preserving source spelling and span (case policy documented; quoted identifiers keep exact case).

### Phase 6: Lint and Fingerprint

**Goal**: 交付 Doris 专属 Lint 规则集(可配置 severity + 安全无损 autofix)与稳定跨后端 SQL 指纹/归一化。
**Mode:** standard
**Depends on**: Phase 5 (serialized schema v2 bump; lint/autofix reuses formatter-safe edit path)
**Requirements**: LINT-01, FING-01
**Status:** Not started

Success criteria:

1. User can run a Doris-specific lint rule set with stable rule codes, per-rule enable/disable, and configurable severity (SQLFluff-style registry) (LINT-01).
2. Autofix preserves comments/trivia/formatting and refuses unsafe edits on error trees (formatter D-33 refusal principle); every fix passes round-trip assertions (LINT-01).
3. User can generate stable SQL fingerprints and normalized forms — stable across whitespace, keyword case, and comments; preserving identifier spelling, literal content, and quote style (FING-01).
4. Fingerprints are identical across Native, JS, and linear-Wasm targets (UInt64-based hash; cross-target parity test) (FING-01).

### Phase 7: Column Lineage

**Goal**: 交付基于 ANAL-01 解析结果的列级血缘,跨查询/视图/CTE/INSERT 展开,并对无 catalog 场景诚实报告 gap。
**Mode:** standard
**Depends on**: Phase 5 (ANAL-01 resolution)
**Requirements**: LINE-01
**Status:** Not started

Success criteria:

1. User can inspect column-level data lineage across supported queries and views — SELECT/INSERT/CTE/set operations and view expansion — with source positions on edges (LINE-01).
2. Unresolved references and `*` expansion without catalog metadata produce explicit "requires catalog" gaps rather than fabricated edges (LINE-01).

### Phase 8: Incremental Parsing (Benchmark-Gated)

**Goal**: 仅当 `moon bench` 证明整文档重解析是可测的延迟瓶颈时,交付有界增量解析与定向 CST 重构;否则以证据 descope 并记录。
**Mode:** standard
**Depends on**: Phase 5 (stable CST, source revisions + LineIndex)
**Requirements**: EDIT-01
**Status:** Not started (gated)

Success criteria:

1. `moon bench` benchmarks demonstrate whole-document reparse is a measurable latency bottleneck for editor-scale documents (EDIT-01 gate) — or the requirement is descoped with the benchmark evidence documented.
2. Incremental parse output is byte-identical to whole-document reparse on the same input (`print_lossless(parse_incremental(x)) == print_lossless(parse_full(x))`) for every edit fixture (EDIT-01).
3. Editor can apply bounded incremental parsing and targeted CST refactors without reparsing the full document, with span-overlap invalidation and no stale spans/trivia (EDIT-01).

## Backlog

No unmapped v2.0 requirements remain: all 24 active requirements map exactly once to Phases 9-13. Post-v2 candidates remain deliberately outside this roadmap: `FLINK-FUTURE-01` (planner/catalog/type/execution equivalence), `TOOL-FUTURE-01` (semantic editor intelligence), `DIALECT-FUTURE-01` (third-party dialect registry), `EDIT-FUTURE-01` (benchmark-gated incremental CST/refactors), `TARGET-FUTURE-01` (Wasm GC first-class support), and `CONVERT-FUTURE-01` (explicit opt-in transpilation). The deferred v3.0 analysis requirements remain archived below and are not v2.0 mappings.

## Dependency and Ordering Rationale

1. **Phase 9 first** — every lexer, parser route, public schema, host, and naming surface needs one explicit immutable dialect/profile context; freezing the Doris baseline before refactoring prevents new tests from hiding regressions.
2. **Phase 10 before grammar** — Flink release/source/Calcite pins and lexical policy determine what “supported” means; the 2.1.3 Calcite gap and quote/comment/literal behavior must be resolved before accepting grammar.
3. **Phase 11 after lexical contract** — shared source/token/CST/Pratt/recovery mechanics can then route to separate Flink productions for core SQL, DDL, Window TVF, and MATCH_RECOGNIZE without a Doris fallback; the frozen Doris baseline remains a hard gate.
4. **Phase 12 after parser behavior** — pinned corpus metadata, acceptance/recovery categories, Doris parity, and Native/JS/linear-Wasm comparisons need stable CST and serialized results; this is a release gate, not cleanup.
5. **Phase 13 last** — formatter/completion/analyzer and CLI/LSP/Web/VS Code/IntelliJ adapters consume the stable dialect-aware API/schema. Real host and ABI smoke tests validate that no adapter silently chooses a dialect or maintains a second parser.

**Execution order:** Phase 9 → Phase 10 → Phase 11 → Phase 12 → Phase 13. No phase may replace explicit selection with automatic detection, generic MySQL fallback, Flink runtime/planner dependencies, default transpilation, or an unbenchmarked incremental parser.

## Next Milestone

v3.0 (deferred analysis layer) starts only after v2.0 Multi-Dialect completes. Its historical Phase 5-8 structure and requirements remain below, with the original archive link [milestones/v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md); none of `CLOSE-01/02`, `ANAL-01`, `LINT-01`, `LINE-01`, `FING-01`, or `EDIT-01` is mapped to v2.0.

**Coverage (v2.0):** 24/24 requirements mapped exactly once — Phase 9: 8, Phase 10: 1, Phase 11: 6, Phase 12: 4, Phase 13: 5.
