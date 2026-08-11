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

### ✅ v2.0: Multi-Dialect: Flink SQL & Neutral Naming — SHIPPED 2026-08-10

Multi-dialect SQL SDK：单方言 Doris 解析器升级为多方言 SQL SDK——Flink SQL 全链（release-pinned profiles、词法核心、grammar + 可恢复无损 CST、formatter、completion、analyzer、LSP/CLI、JS/linear-Wasm wire、Web/VS Code/IntelliJ 三宿主）+ 产品命名中立化（fathom-sql/fathom-lsp/fathom.*.v1）+ 跨方言 release-pinned corpus 与 parity 门禁。24/24 v2 需求验证通过，全程离线，Doris 冻结 baseline 零漂移。

- **Archive:** [v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md) · [v2.0-REQUIREMENTS.md](milestones/v2.0-REQUIREMENTS.md) · [v2.0-phases](milestones/v2.0-phases/)
- **Status:** SHIPPED (verified_closeout — artifact audit clear, all 5 phases verified, 24/24 requirements complete, threats_open 0)

<details>
<summary>v2.0 Phase Details (archived)</summary>

### Phase 9: Dialect Boundary and Neutral Naming

**Goal**: 在 API/CLI/LSP/JS-Wasm/Web/VS Code/IntelliJ 全程显式选择 dialect/profile，完成产品命名中立化 cutover 与命名门禁，冻结 Doris baseline。
**Requirements**: DIALECT-01..04, NAME-01..04
**Status:** Complete 2026-08-10 (7 plans)

### Phase 10: Flink Release Profiles and Lexical Core

**Goal**: 可审计的 Flink release profile（flink-2.3.0 主 + 2.1.3/1.20.5 回归）与独立 Flink 词法/关键字核心。
**Requirements**: FLINK-01
**Status:** Complete 2026-08-10 (3 plans)

### Phase 11: Flink Grammar and Recoverable CST

**Goal**: 真实 Flink 语句级 grammar 与无损/有界/可恢复 CST（核心查询、DDL、CREATE TABLE 复杂形式、Window TVF、MATCH_RECOGNIZE、双向负门禁）。
**Requirements**: FLINK-02..06, CST-01
**Status:** Complete 2026-08-10 (4 plans)

### Phase 12: Cross-Dialect Corpus and Parity Gates

**Goal**: release-pinned Flink corpus manifest、Doris 冻结 diff harness、Native/JS/linear-Wasm 字节级一致、离线 CI 门禁。
**Requirements**: CORPUS-01, PARITY-01..03
**Status:** Complete 2026-08-10 (3 plans)

### Phase 13: Toolchain and Editor Packaging

**Goal**: Flink 贯通全部中立工具链与宿主——formatter、completion、analyzer、CLI/LSP、JS/linear-Wasm wire（fathom_complete_v1）、Web/Monaco、VS Code、IntelliJ。
**Requirements**: TOOL-01..05
**Status:** Complete 2026-08-10 (7 plans; verified 28/28, threats_open 0)

</details>

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
**Status:** Complete — 4 of 4 plans complete (05-01 closeout evidence formalized, 05-02 ANAL-01 foundation: D-05 Catalog contract + SELECT analyze tracer, 05-03 full SELECT analysis model: clause split + scope-stack resolution + integration/white-box tests, 05-04 function resolution + arity, DML/CREATE VIEW column refs, and the complete type-diagnostic set with docs/API.md updated)

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
**Status:** Complete — 2026-08-10 (4 plans: 06-01 fingerprint library+api+wiring, 06-02 lint library+autofix, 06-03 lint api+wire, 06-04 CLI+parity+docs; verifier 4/4 SC passed)

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
**Status:** Planned — 5 plans ready to execute (07-01 analyzer public surface Wave 0 tracer → 07-02 lineage core → 07-03 api.lineage_text → 07-04 wire/CLI → 07-05 parity/docs)

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
