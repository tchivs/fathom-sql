# Doris SQL Parser SDK

## What This Is

Doris SQL Parser SDK 是一个面向 Apache Doris SQL 的开源基础设施项目，提供独立、完整、可嵌入的解析与工具链能力。它以官方文档语法和示例为覆盖基准，使用 MoonBit 构建同一套核心代码，并输出 Native CLI/LSP 与 WebAssembly/JavaScript SDK，服务编辑器、Web 工具和自动化流水线。

项目的核心差异化是无损 CST：解析树保留注释、空白、换行和源码位置，使格式化、诊断与编辑器能力能够 round-trip 而不破坏用户源码；在此基础上逐步提供格式化、Lint、列级血缘和 SQL 指纹等分析能力。

## Core Value

用户可以对 Doris SQL 进行高覆盖、精确诊断且无损 round-trip 的解析与编辑，而不依赖 Doris FE、商业闭源 GSP 或薄弱的方言适配。

## Requirements

### Validated

- [x] 提供保留注释、空白、换行和源码位置的无损 CST，以及可 round-trip 的解析/打印基础能力 — Validated in Phase 1: Core Kernel
- [x] 以官方 Doris 文档语料库驱动语法覆盖，优先实现工业级 SELECT、JOIN、窗口、CTE、GROUPING SETS 和 Pratt 表达式解析 — Validated in Phase 1: Core Kernel
- [x] 覆盖 Doris DML、DDL 及 Doris 特有建表、分布、动态分区和物化视图语法，并对非法 SQL 提供精确、可恢复的诊断 — Validated in Phase 2: Doris Completeness and Corpus
- [x] 保持解析与可选语义分析分离，允许无 catalog 元数据时进行纯语法校验，并为后续注入表/列元数据留下接口 — Validated in Phase 2: Doris Completeness and Corpus
- [x] 提供可配置的 CST Pretty Printer 与 `doris-sql format` CLI，支持注释保留、缩进和关键字风格配置 — Validated in Phase 3: Formatting and Safe Edits
- [x] 提供 Native CLI/LSP 与 WebAssembly/JavaScript SDK，使同一解析器可用于 LSP、CLI、Web 和 Monaco 集成 — Validated in Phase 4: Ecosystem and Multi-Target Delivery

### Active

(None — all v1 requirements validated across Phases 1-4)

### Out of Scope

- 复杂语义分析（函数存在性、完整类型推导和依赖 Doris FE 的执行语义）在初始版本不纳入核心范围，以避免替代 FE `EXPLAIN` 并失控扩张。
- M5+ 的企业级 Lint 规则、列级血缘和 SQL 指纹/归一化不进入首个四阶段交付，待解析内核、格式化和生态接口稳定后再评估。
- 不构建商业闭源方案或依赖 Doris FE 内部服务的封闭集成；核心 SDK 必须可独立发布和使用。

## Context

- 当前目录是绿地项目；没有既有应用代码、包清单或 GSD 规划文档。
- 目标域是 Apache Doris SQL 工具链。现有 sqlglot Doris 方言存在注释/格式丢失与方言覆盖偏薄的问题；Doris FE 的 g4 语法不适合作为独立、完整发布的 SDK；GSP 是商业闭源方案；当前生态缺少 Doris LSP。
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

**v1.0 SHIPPED — 2026-08-05** (override_closeout, 5 documented overrides)

- **代码规模:** ~15.5k 行 MoonBit(7 核心包 + lsp/binding/parity/completion/analyzer/formatter/doris-sql)+ ~1.3k 行 TS/Py/MJS(web demo、vscode 扩展、corpus 工具);257 文件,52 个 feat commits,2 天交付。
- **测试:** 188/188 MoonBit 测试(test/parity/doris-sql/lsp)+ node 7/7 + 23/23 Chromium 断言(executor 实测)+ 全部 --check 绿。
- **能力:** 无损 CST round-trip、SELECT+DML/DDL 覆盖(2.1/3.x/4.x profile 门控)、44 行官方语料 manifest、配置化格式化(6 维)+ CLI(exit 0/1/2)、Native LSP(诊断/格式化/补全,utf-16)、JS ESM + linear Wasm facade、离线 Monaco 演示、VS Code 扩展。
- **已知边界:** ECO-07 已在真实 VS Code 1.132.0 宿主验证通过(2026-08-06,3 模式扩展宿主测试);linear-Wasm CI 运行时执行步骤已加入 `.github/workflows/ci.yml` 与发布门禁;FE/Nereids 差分脚本待人工执行;9/44 manifest 行经 formatter harness 覆盖(对应关系手工维护)。

## Current Milestone: v2.0 Analysis and Intelligence

**Goal:** 在 v1.0 稳定的无损 CST、格式化与多后端生态之上，把 SDK 从语法层扩展到语义与分析层（catalog 名字解析与类型诊断、Doris 专属 Lint、列级血缘、SQL 指纹），并收尾 v1.0 遗留验证项（VS Code 宿主验证、linear-Wasm CI 步骤）。

**Target features:**
- ANAL-01 catalog 注入的名字解析与类型诊断（延续 v1 analyzer 边界 D-21/D-22/D-24）
- LINT-01 Doris 专属 lint 规则集（可配置 severity + 安全 autofix）
- LINE-01 列级血缘
- FING-01 稳定 SQL 指纹与归一化
- EDIT-01 有界增量解析与定向 CST 重构（基准证明必要性后）
- 收尾:ECO-07 在装有 VS Code 的机器上人工验证扩展(04-04 Task 4)
- 收尾:发布前补 linear-Wasm CI 运行时执行步骤

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
*Last updated: 2026-08-05 after milestone v2.0 started*
