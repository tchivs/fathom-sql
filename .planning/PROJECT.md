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

**v2.0 Phase 12 COMPLETE — 2026-08-10** (Cross-Dialect Corpus and Parity Gates)

- **统一 release-pinned Flink corpus:** `parity/fixtures/flink/manifest.tsv`（110 行 × 19 列，release/tag/commit、Calcite 版本/config、URL/标题/检索日期/hash/期望状态、6 类分类 positive 49 / negative 25 / recovery 17 / planner-prereq 13 / known-limitation 3 / catalog-prereq 3）+ 110 个已提交 .sql fixture（embedded b"..." 字节匹配）。
- **离线门禁:** `verify_corpus.py --check`（纯 stdlib，110 行 + 104 归档 sha512 复验，无网络）；`diff_parity.py --frozen-only`（CI 模式对任何差异 exit 1、不 consult 注册表；`--approve <register>` 本地批准流；restore 保证）；`compare_backends.py`（三目标 fail-closed + 快照树确定性 digest）。
- **跨后端字节一致:** native/js/wasm 三目标 570/570，快照树 sha256 digest 完全一致（5e9bb887…）；CI linear-wasm-parity 增 js 运行时 + compare_backends 汇总。
- **语义区分:** coverage 报告 parser-accepted 68 vs engine-semantic-prerequisite 19 vs engine-supported 49（仅 positive）；catalog/planner/known-limitation 永不计入引擎支持。
- **Doris 零漂移:** diff_parity 433 快照 0 差异；812/812 测试；CI 无任何 `--update`。
- **测试:** 812/812 MoonBit + 三目标 parity 570/570 + 全部门禁 exit 0；威胁注册 20/20 关闭（ASVS L1）。

## Current Milestone: v2.0 Multi-Dialect: Flink SQL & Neutral Naming

**Goal:** 将单方言 Doris 解析器升级为多方言 SQL SDK——引入方言抽象层，新增 Flink SQL 方言全链（解析/CST/诊断/格式化/补全/LSP/CLI），并完成产品命名中立化（二进制/schema/错误码/扩展/文档），使同一无损 CST 内核服务 Doris 与 Flink 两个方言。原 v2.0 分析层（Analysis and Intelligence）顺延为 v3.0。

**Target features:**
- 方言抽象层：Dialect 体系、关键字表隔离、API/schema/LSP 的 dialect 参数、Doris 字节级不变 parity gate
- Flink SQL 方言：词法/关键字表、文法（DDL/DML/窗口 TVF/MATCH_RECOGNIZE）、CST/诊断
- Flink 工具链：formatter/analyzer/completion/LSP/CLI 方言分发
- 命名中立化：`fathom-sql`/`fathom-lsp`、`fathom/sql` 模块、`FATHOM-*` 错误码、`fathom.*.v1` schema、扩展/文档改名（不考虑向后兼容）
- Flink 官方语料 + CI：来源锁定、快照、跨后端 parity

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
*Last updated: 2026-08-10 after Phase 12 (Cross-Dialect Corpus and Parity Gates) completion*
