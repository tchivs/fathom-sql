# Roadmap: Doris SQL Parser SDK

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

Doris SQL Parser SDK 从单方言升级为多方言 SQL SDK:引入方言抽象层(Dialect 体系、关键字表隔离、API/schema/LSP 的 dialect 参数、Doris 字节级不变 parity gate),新增 Flink SQL 方言全链(词法/关键字、文法、CST/诊断、formatter/analyzer/completion/LSP/CLI),并完成产品命名中立化(`fathom-sql`/`fathom-lsp`、`fathom/sql` 模块、`FATHOM-*` 错误码、`fathom.*.v1` schema、扩展/文档改名,不考虑向后兼容)。

- **Requirements:** [REQUIREMENTS.md](REQUIREMENTS.md) — 待定义
- **Research:** [research/SUMMARY.md](research/SUMMARY.md) — 待 v2.0 方言 research

### Phase 9: Dialect Boundary and Neutral Naming (tentative)

**Goal**: 引入方言抽象层与产品命名中立化,保持 Doris 解析字节级不变。
**Mode:** mvp
**Depends on**: Phase 4 (v1.0)
**Status:** Not started (phases TBD by roadmapper)

## v3.0: Analysis and Intelligence — PLANNING (deferred)

> **DEFERRED 2026-08-06:** formerly v2.0; deferred when v2.0 was redefined as Multi-Dialect. Requirements archived at [milestones/v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md).

Doris SQL Parser SDK 从语法层扩展到语义与分析层:catalog 名字解析、Doris 专属 Lint、列级血缘、跨后端稳定指纹,以及基准门控的增量解析;并在首个阶段收尾 v1.0 遗留验证项(VS Code 宿主验证、linear-Wasm CI 步骤)。

- **Requirements:** [milestones/v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md) — 7 requirements (CLOSE-01/02, ANAL-01, LINT-01, LINE-01, FING-01, EDIT-01)
- **Research:** [research/SUMMARY.md](research/SUMMARY.md) — v2 analysis-feature research (2026-08-05)

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

(No backlog items — all v2.0 requirements are mapped to phases below.)

## Dependency and Ordering Rationale

1. **Phase 5 first** — user-selected: close the two v1 deferred verification items (human VS Code host, linear-Wasm CI) before new analysis features, and lay the ANAL-01 resolution foundation that LINE-01 depends on.
2. **Phase 6 parallelizable** — LINT-01 and FING-01 are largely independent of ANAL-01; they share the schema v2 bump from Phase 5 and reuse the formatter-safe edit path for autofix.
3. **Phase 7 after Phase 5** — column lineage (LINE-01) requires resolved column bindings from ANAL-01.
4. **Phase 8 gated** — incremental parsing (EDIT-01) is the riskiest and must be justified by `moon bench` evidence; the v1 research explicitly deferred it until measurements warrant it.

## Next Milestone

v3.0 (deferred analysis layer) — starts after v2.0 Multi-Dialect completes. Scope carried from the archived [milestones/v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md): ANAL-01/LINT-01/LINE-01/FING-01/EDIT-01. Candidate later scope (see the archived requirements § Future): ANAL-02 full type inference (likely out of scope), LINT-02 rule plugins/marketplace, LINE-02 cross-catalog lineage federation, EDIT-02 broad structural refactors, Wasm GC first-class target.

**Coverage (v2.0):** TBD — requirements being defined.
