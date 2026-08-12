# Fathom SQL Parser SDK

## What This Is

Fathom SQL Parser SDK 是一个面向显式选择 SQL 方言的开源基础设施项目，首批支持 Apache Doris SQL 与 Flink SQL。它提供独立、完整、可嵌入的解析与工具链能力，以各方言的锁定官方文档和源码为覆盖基准，使用 MoonBit 构建同一套核心代码，并输出 Native CLI/LSP 与 WebAssembly/JavaScript SDK，服务编辑器、Web 工具和自动化流水线。

项目的核心差异化是无损 CST：解析树保留注释、空白、换行和源码位置，使格式化、诊断与编辑器能力能够 round-trip 而不破坏用户源码；在此基础上按方言提供格式化、Lint、列级血缘和 SQL 指纹等分析能力。

## Core Value

用户可以对显式选择的 Doris 或 Flink SQL 进行高覆盖、精确诊断且无损 round-trip 的解析与编辑，而不依赖 Doris FE、Flink cluster、数据库、商业闭源 GSP 或通用方言静默回退。

## Requirements

### Validated

- [x] 提供保留注释、空白、换行和源码位置的无损 CST，以及可 round-trip 的解析/打印基础能力 — Validated in Phase 1: Core Kernel
- [x] 以官方 Doris 文档语料库驱动语法覆盖，优先实现工业级 SELECT、JOIN、窗口、CTE、GROUPING SETS 和 Pratt 表达式解析 — Validated in Phase 1: Core Kernel
- [x] 覆盖 Doris DML、DDL 及 Doris 特有建表、分布、动态分区和物化视图语法，并对非法 SQL 提供精确、可恢复的诊断 — Validated in Phase 2: Doris Completeness and Corpus
- [x] 保持解析与可选语义分析分离，允许无 catalog 元数据时进行纯语法校验，并为后续注入表/列元数据留下接口 — Validated in Phase 2: Doris Completeness and Corpus
- [x] 提供可配置的 CST Pretty Printer 与 `doris-sql format` CLI，支持注释保留、缩进和关键字风格配置 — Validated in Phase 3: Formatting and Safe Edits
- [x] 提供 Native CLI/LSP 与 WebAssembly/JavaScript SDK，使同一解析器可用于 LSP、CLI、Web 和 Monaco 集成 — Validated in Phase 4: Ecosystem and Multi-Target Delivery
- [x] 消费者可在 API、CLI、LSP、JS/Wasm、Web、VS Code、IntelliJ 显式选择 `doris`/`flink` 方言与 profile；缺失/未知/冲突返回结构化配置错误，无自动检测与静默回退 — Validated in Phase 9: Dialect Boundary and Neutral Naming
- [x] 解析器使用相互独立的 Doris/Flink 词法关键字策略，语句/子句文法显式按方言路由；方言间互不影响标识符接受与恢复行为 — Validated in Phase 9: Dialect Boundary and Neutral Naming
- [x] 解析、格式化、补全、LSP 与序列化结果携带 dialect/profile/exact-release 元数据，`FATHOM-*` 诊断跨公共边界稳定 — Validated in Phase 9: Dialect Boundary and Neutral Naming
- [x] 产品层完成 `fathom/sql`、`fathom-sql`、`fathom-lsp` 中立命名 cutover（模块/二进制/导出/schema/错误码/扩展/文档），无旧名 alias；Doris 仅保留为方言/profile/corpus/provenance 语义标识 — Validated in Phase 9: Dialect Boundary and Neutral Naming
- [x] CI 内置命名 inventory/allowlist 门禁（`check_naming.py`），拒绝产品层 `doris-sql`/`doris-lsp`/`doris.*`/`DORIS-*` 残留 — Validated in Phase 9: Dialect Boundary and Neutral Naming
- [x] 消费者可选择钉住的 Flink release profile（`flink-2.3.0` 主 + `flink-2.1.3`/`flink-1.20.5` 回归），每个 profile 记录真实 release 的 Calcite 版本/parser 配置（自该 release 提取），不支持者显式拒绝 — Validated in Phase 10: Flink Release Profiles and Lexical Core
- [x] 消费者可解析 Flink 核心查询与日常语句（SELECT/CTE/JOIN/聚合/集合运算/表达式/类型/INSERT/UPDATE/DELETE/EXPLAIN/SHOW/DESCRIBE/ANALYZE）与 Catalog/DDL 入口（CREATE/ALTER/DROP CATALOG/DATABASE/TABLE/VIEW/FUNCTION），可恢复诊断 — Validated in Phase 11: Flink Grammar and Recoverable CST
- [x] 消费者可解析 Flink CREATE TABLE 物理/元数据/计算列、WATERMARK、PRIMARY KEY NOT ENFORCED、PARTITIONED BY、分布、WITH 选项、LIKE、AS 形式，保留 token 拼写/trivia/span — Validated in Phase 11: Flink Grammar and Recoverable CST
- [x] 消费者可解析 Window TVF（TUMBLE/HOP/CUMULATE/SESSION，含 TABLE/DESCRIPTOR/区间字面量/命名参数/窗口输出列）与语法级 MATCH_RECOGNIZE（PATTERN/DEFINE/MEASURES/skip/变量/量词），不声称 planner/执行等价 — Validated in Phase 11: Flink Grammar and Recoverable CST
- [x] 消费者可在严格/编辑器模式将 Flink 输入解析为可恢复无损 CST：注释/空白/换行/未知/错误/缺失/跳过材料/源码字节/span 全部 round-trip 无丢失 — Validated in Phase 11: Flink Grammar and Recoverable CST
- [x] 维护者可检查 release-pinned Flink corpus manifest（release/tag/commit、Calcite 版本/config、URL/标题/检索日期/hash、期望状态、positive/negative/recovery/known-limitation/catalog/planner 6 类） — Validated in Phase 12: Cross-Dialect Corpus and Parity Gates
- [x] Doris 2.1/3.x/4.x 的 valid/invalid/recovery/CST/span/diagnostic/formatter/completion 行为与冻结 baseline 保持相等，或每项故意差异显式记录批准 — Validated in Phase 12: Cross-Dialect Corpus and Parity Gates
- [x] 同一 fixture 在 Native/JavaScript/linear-Wasm 目标产生字节级一致的序列化结果/诊断/span/lossless replay — Validated in Phase 12: Cross-Dialect Corpus and Parity Gates
- [x] CI/release 检查仅从钉住离线工件运行（无 Doris FE/Flink cluster/数据库/网络），覆盖报告区分 parser 接受与引擎语义前置 — Validated in Phase 12: Cross-Dialect Corpus and Parity Gates
- [x] 消费者可对受支持的 Flink CST 做 canonical 格式化（独立于 lossless replay）；含 error/missing/skipped 的不安全树显式拒绝且无部分输出 — Validated in Phase 13: Toolchain and Editor Packaging
- [x] 消费者可获取有界、dialect/profile 感知的 Flink 语法补全（关键字、DDL、WATERMARK、Window TVF、MATCH_RECOGNIZE 上下文），并运行带可选 catalog 的语法级 Flink analyzer，parser validity 与 catalog 无关 — Validated in Phase 13: Toolchain and Editor Packaging
- [x] 消费者可端到端使用 `fathom-sql parse|format|lsp --dialect flink` 与 `fathom-lsp`（诊断/格式化/补全/UTF-16/文档级方言选择） — Validated in Phase 13: Toolchain and Editor Packaging
- [x] 消费者可在 JS/linear-Wasm、Web/Monaco、VS Code、IntelliJ 使用同一 dialect-aware API/schema（含新增 `fathom_complete_v1`/`fathom.complete.v1`），每文件/会话显式选择 Doris 或 Flink，无第二套 parser — Validated in Phase 13: Toolchain and Editor Packaging
- [x] 用户可检查跨查询/视图的列级数据血缘（SELECT/INSERT/CTE/集合运算与视图展开，边带源码位置）；未解析引用与无 catalog 的 `*` 展开产生显式 "requires catalog" gap 而非伪造边 — Validated in Phase 7: Column Lineage

### Active

(None — all v1 requirements validated across Phases 1-4; v2.0 requirements land with their phases)

### Out of Scope

- 复杂语义分析（函数存在性、完整类型推导和依赖 Doris FE 的执行语义）在初始版本不纳入核心范围，以避免替代 FE `EXPLAIN` 并失控扩张。
- M5+ 的企业级 Lint 规则、列级血缘和 SQL 指纹/归一化不进入首个四阶段交付，待解析内核、格式化和生态接口稳定后再评估。
- 不构建商业闭源方案或依赖 Doris FE 内部服务的封闭集成；核心 SDK 必须可独立发布和使用。

## Context

- 当前目录是绿地项目；没有既有应用代码、包清单或 GSD 规划文档。
- 目标域是可独立发布的多方言 SQL 工具链，首批覆盖 Apache Doris 与 Apache Flink SQL。现有 sqlglot/通用 SQL 方案存在注释/格式丢失、方言覆盖偏薄或验证宽松的问题；Doris FE 与 Flink runtime 都不作为 SDK 的运行时依赖。
- 目标语言为 MoonBit。核心代码应保持纯数据、低依赖，使用 enum、struct ADT 和模式匹配表达 AST/CST；不可变 trivia 结构适合跨 Native 与 Wasm 后端复用。
- 建议的五层边界是：Lexer（保留 trivia）→ Parser（递归下降 + Pratt）→ 无损 CST/AST → Pretty Printer → 应用与分析层（CLI、LSP、Wasm/JS SDK、Lint、血缘、指纹）。
- 可持续覆盖依赖官方文档语料库：按 Doris 版本标记 2.1/3.0/4.0，覆盖官方 SQL 示例，并用 golden/snapshot 测试与 CI 追踪语法演进。
- 目标验收信号包括官方文档示例通过率、非法 SQL 的诊断质量、`parse(print(parse(x))) == x` 的无损 round-trip、CLI/LSP/Web 端到端可用性以及与 sqlglot、ANTLR JS 的性能基线。

## Constraints

- **语言与后端**: 核心解析器使用 MoonBit，并从同一份代码编译 Native 与 Wasm/JS — 避免为 Web、LSP 和 CLI 维护多套解析实现。
- **源码保真**: CST 节点必须保留 Span 与 trivia；格式化和后续编辑不能丢失注释、空白或换行 — 这是区别于现有薄方言方案的核心价值。
- **解析策略**: 采用手写递归下降 Parser，表达式采用 Pratt parsing；错误恢复至少支持语句级 panic-mode 与子句级尽力恢复 — IDE 场景必须能处理半成品 SQL。
- **覆盖基准**: 以官方文档为语法权威和可执行语料，按 Doris 版本维护关键字分类与语法示例 — 避免仅以不完整 g4 或薄方言为准。
- **语义边界**: Parser 只负责语法，Analyzer 通过可选 catalog 注入名字解析 — 无元数据时仍必须支持纯前端语法校验。
- **交付顺序**: 先把 SELECT 与表达式做到工业级，再横向扩展 DML/DDL、格式化和生态集成 — 不以初期全覆盖牺牲错误恢复、性能和测试质量。

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| 以无损 CST 作为核心数据模型，而非只提供纯 AST | 保留 trivia 和 Span，支持无损格式化、精确诊断与编辑器集成 | — Pending |
| 手写递归下降 + Pratt 表达式，不使用生成器作为核心 Parser | 更容易控制半成品 SQL 的错误恢复、增量解析和 IDE 体验 | — Pending |
| 用官方文档语料库驱动覆盖和版本演进 | 让覆盖可衡量、可回归，目标是文档示例 100% 通过 | — Pending |
| Parser 与可选 Analyzer 分离 | 无 catalog 也能纯语法校验，同时为列/名字解析留出扩展点 | — Pending |
| 一套 MoonBit 核心同时输出 Native 与 Wasm/JS | 以同一实现覆盖 CLI、LSP、Web 和 Monaco 场景 | — Pending |
| 先交付四个里程碑：内核、完整性、格式化、生态 | 先建立可靠解析基础，再扩展工具链，控制语法跟进风险 | — Pending |

## Current State

**v2.0 SHIPPED — 2026-08-10** (Multi-Dialect: Flink SQL & Neutral Naming) — 24/24 requirements validated, verified_closeout

- **Flink formatter（TOOL-01/D-01）:** `formatter/layout.mbt` 20 族 Flink covered-family gate + 全套 Flink 语句族布局；未覆盖族 → `FATHOM-FORMAT-001` 拒绝（accepted=false、空输出）；`flink-format.*` 快照 22 个 + idempotence/零诊断 reparse/refusal oracle + 覆盖完备性探针。
- **Flink completion（TOOL-02/D-02）:** `complete()` 真实 Flink DialectContext；`profile_allows` Flink 臂；6 个 Flink `completion_context` 臂（statement-start/ddl-header/watermark/partitioned-by/window-tvf/match-recognize）；`flink_classification_rows` 扩至 169 行（NonReserved，parse-neutral）；MAX_CANDIDATES=32；无第二关键字表（D-28）。
- **Flink analyzer（TOOL-03/D-03）:** `resolve_table_references` 覆盖 Flink Insert/Update/Delete/CreateTable/CreateView（UPSERT INTO / INSERT OVERWRITE / CREATE [TEMPORARY] VIEW 前缀）；D-21 只读 syntax-view 纪律 + 可选 catalog；表级范围（D-24）。
- **Wire 契约（TOOL-05/D-04）:** 新增 `fathom_complete_v1` + `fathom.complete.v1`（第五命名空间，注册进 validate_schema_version / binding.js / binding.wasm / docs / 命名门禁）；三目标字节一致 digest。
- **LSP/CLI（TOOL-04/D-07）:** LSP flink format → `@api.format_with_ids`（-32603 哨兵移除）、completion → `@completion.complete`（-32602 拒绝移除）；UTF-16 单点 `span_to_range`；CLI D-39 退出码（0/1/2）。
- **三宿主（TOOL-05/D-05/D-06）:** Web/VS Code/IntelliJ 均改为 (dialect, profile) 二元组校验（doris 2.1/3.x/4.x；flink flink-2.3.0/2.1.3/1.20.5），静态常量、服务端权威、离线。
- **打包 smoke（TOOL-05/D-08）:** VS Code 真 extension-host flink 模式 4 模式、IntelliJ Gradle build+launch、Web Chromium offline-smoke；CI `host-packaging-smoke` job；全程离线。
- **门禁:** native 876/js 597/wasm 597 测试全绿；diff_parity --frozen-only 455 快照 0 差异；check_naming 602 文件零残留；三目标 digest 一致；verifier 28/28 must-haves 通过。

**v3.0 Phase 5 COMPLETE — 2026-08-10** (Closeout and Analysis Foundation) — CLOSE-01/02 已核实（D-07 正式记录），ANAL-01 catalog 名字解析与类型诊断交付（verifier 13/13 must-haves）

- **Analyzer 契约（D-05 one-way）:** `Catalog` trait 定形为 `table`/`table_in_db`/`function` 三方法 + `FunctionInfo`（name/param_types/return_type/min_arity）；StaticCatalog 增 db 作用域表与函数注册表；唯一实现者与测试 helper 同 commit 迁移；resolve_table_references 行为不变。
- **SELECT 分析模型（D-01）:** analyzer 侧对平铺 token-leaf CST 二次解析（顶层子句切分 + 括号深度感知 + 作用域栈），CTE/子查询/UNION 链/AS 别名/限定名 `db.table.col`/带 catalog 星号展开；带引号标识符经 case-fold `Catalog::table` + `TableInfo.name` 字节复核精确匹配（D-03）；binding 保留源码拼写 + 平铺 Int span（D-06）。
- **类型诊断（D-04）:** 函数调用解析与元数检查；unknown-table/column/function、ambiguous-reference、function-arity 诊断集；独立诊断通道（ANLY-01 语法 valid 不变）。
- **门禁:** native 886 测试全绿（analyzer+test 191）；frozen Doris parity 597 + diff_parity --frozen-only 455 快照 0 差异；D-21 负门禁（analyzer/moon.pkg + parser/moon.pkg 零 diff）干净；code review 1 BLOCKER + 6 WARNING 全修复。

**v3.0 Phase 7 COMPLETE — 2026-08-11** (Column Lineage) — LINE-01 列级血缘交付（verifier 15/15 must-haves；code review CR-01 + WR-01..04 全修复）

- **lineage/ 独立库（D-21）:** `derive_lineage`/`derive_lineage_without_catalog` 只 import analyzer+syntax（永不 parser）；D-01 表达式直通边（投影表达式内每个已解析列引用各一条 source→target 边）；D-06 独立 gap 列表（requires-catalog / unresolved-reference / requires-complete-parse）；视图注册表 + `ViewCatalog[T]`（D-03，视图 shadow catalog 表）；INSERT/CTE/UNION 位置映射（D-04，与 analyzer 现实调和：EXCEPT 投影修饰符、INTERSECT 不接受集）；SC2 诚实 gap——无 catalog 星号/外部视图/未解析引用绝不伪造边。
- **analyzer 公开面（Wave 0）:** 8 个 select-model 类型 pub(all) + re-parser/体定位入口公开；`* EXCEPT (cols)` 诚实展开（SelectItem.except_cols）；has_error_missing 公开；零 parser/冻结 baseline 改动。
- **api/wire/CLI:** `api.lineage_text(raw, parse_options, catalog?)` + flink 门禁（FATHOM-SCHEMA-003 "lineage is Doris-only"，D-08）；`fathom.lineage.v1` 第 8 命名空间（schema 纯增，Pitfall V6）+ `fathom_lineage_v1`（catalog_json 解析，非法输入 FATHOM-SCHEMA-004）；`fathom-sql lineage --catalog <file>` 子命令（D-39 0/1/2）。
- **parity/docs:** lineage_parity_test 三目标字节一致（605/605 ×3，digest `2eda3582…`）；双语 API 文档 Lineage 章节 + COVERAGE.md api-coverage 声明。
- **门禁:** lineage 19/19、test 209/209、api 636/636、fathom-sql 37/37、parity 605/605 ×3；frozen Doris parity 455 快照 0 差异；D-21 负门禁干净。

**v3.0 Phase 8 COMPLETE — 2026-08-12** (Incremental Parsing, Benchmark-Gated) — **EDIT-01 DESCoped with benchmark evidence**（verifier 8/8 must-haves；code review WR-01/WR-02 全修复）

- **基准门禁（08-01 tracer）:** 新建 `bench/` 包（`@bench` attribute，moon 0.1.20260724 实测可用）；整文档重解析延迟梯度 25/50/100/200KB（corpus 内嵌语句池 + 合成 editor-scale，运行时零磁盘读）；native release 下 **100KB median 27.47ms（≤50ms 阈值）、200KB 57.76ms（线性外推一致）**，per-doubling ×2.00/×2.04/×2.10 —— **线性、无超线性增长**。
- **门禁结论（D-02 阈值）:** editor-scale（≥100KB）整文档重解析**不是可测延迟瓶颈** → **分支 A：EDIT-01 descoped with evidence**（ROADMAP SC1 "or" 条款）。`08-BENCHMARK.md` 记录五要素（fixture/规模/median+p95/结论/工具链）+ Gate Interpretation Note（阈值在 ≥100KB 边界输入判定；200KB 为线性确认）+ Methodology bias note（recovery 路径使测量为上界，结论保守）。
- **descope 记录（08-02）:** REQUIREMENTS.md EDIT-01 → `[x]` + DESCOPED WITH EVIDENCE（引用 08-BENCHMARK.md）；ROADMAP Phase 8 = Complete — descoped with evidence；STATE.md Deferred Items `descope_evidence` 行 closed。**零增量解析代码**（无 incremental/ 包，parser/ 冻结 baseline 未动）。
- **门禁:** bench 9/9、test 209/209、api 636/636、fathom-sql 37/37、parity 605/605；命名门禁 655 文件零残留；verifier 8/8。

## Current Milestone: v2.0 Multi-Dialect: Flink SQL & Neutral Naming — SHIPPED 2026-08-10

**Goal:** 将单方言 Doris 解析器升级为多方言 SQL SDK——引入方言抽象层，新增 Flink SQL 方言全链（解析/CST/诊断/格式化/补全/LSP/CLI），并完成产品命名中立化（二进制/schema/错误码/扩展/文档），使同一无损 CST 内核服务 Doris 与 Flink 两个方言。原 v2.0 分析层（Analysis and Intelligence）顺延为 v3.0。

**Target features:**
- 方言抽象层：Dialect 体系、关键字表隔离、API/schema/LSP 的 dialect 参数、Doris 字节级不变 parity gate
- Flink SQL 方言：词法/关键字表、文法（DDL/DML/窗口 TVF/MATCH_RECOGNIZE）、CST/诊断
- Flink 工具链：formatter/analyzer/completion/LSP/CLI 方言分发
- 命名中立化：`fathom-sql`/`fathom-lsp`、`fathom/sql` 模块、`FATHOM-*` 错误码、`fathom.*.v1` schema、扩展/文档改名（不考虑向后兼容）
- Flink 官方语料 + CI：来源锁定、快照、跨后端 parity

**Status:** SHIPPED 2026-08-10 — archived at [milestones/v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md) · [milestones/v2.0-REQUIREMENTS.md](milestones/v2.0-REQUIREMENTS.md) · [milestones/v2.0-phases](milestones/v2.0-phases/)

## Next Milestone Goals: v3.0 Analysis and Intelligence

从语法层扩展到语义与分析层：catalog 名字解析（ANAL-01 ✅ Phase 5 完成）、Doris 专属 Lint（LINT-01）、列级血缘（LINE-01）、跨后端稳定指纹（FING-01）、基准门控增量解析（EDIT-01）。要求已归档于 [milestones/v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md)。

**Requirements:** CLOSE-01/02 ✅（Phase 5 已核实）、ANAL-01 ✅（Phase 5 已交付）、LINT-01 ✅（Phase 6）、FING-01 ✅（Phase 6）、LINE-01 ✅（Phase 7）、EDIT-01 ⛔ DESCoped with evidence（Phase 8，`moon bench` 门禁：≥100KB median 27.47ms ≤ 50ms、线性）
**Start:** `/gsd:new-milestone` — 提问 → 研究 → 需求 → 路线图（v3.0 已全部完成：Phase 5-8；下一里程碑 /gsd:new-milestone）

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-08-12 after v3.0 Phase 8 Incremental Parsing (Benchmark-Gated) COMPLETE — EDIT-01 descoped with evidence*
