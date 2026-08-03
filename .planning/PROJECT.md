# Doris SQL Parser SDK

## What This Is

Doris SQL Parser SDK 是一个面向 Apache Doris SQL 的开源基础设施项目，提供独立、完整、可嵌入的解析与工具链能力。它以官方文档语法和示例为覆盖基准，使用 MoonBit 构建同一套核心代码，并输出 Native CLI/LSP 与 WebAssembly/JavaScript SDK，服务编辑器、Web 工具和自动化流水线。

项目的核心差异化是无损 CST：解析树保留注释、空白、换行和源码位置，使格式化、诊断与编辑器能力能够 round-trip 而不破坏用户源码；在此基础上逐步提供格式化、Lint、列级血缘和 SQL 指纹等分析能力。

## Core Value

用户可以对 Doris SQL 进行高覆盖、精确诊断且无损 round-trip 的解析与编辑，而不依赖 Doris FE、商业闭源 GSP 或薄弱的方言适配。

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] 提供保留注释、空白、换行和源码位置的无损 CST，以及可 round-trip 的解析/打印基础能力
- [ ] 以官方 Doris 文档语料库驱动语法覆盖，优先实现工业级 SELECT、JOIN、窗口、CTE、GROUPING SETS 和 Pratt 表达式解析
- [ ] 覆盖 Doris DML、DDL 及 Doris 特有建表、分布、动态分区和物化视图语法，并对非法 SQL 提供精确、可恢复的诊断
- [ ] 提供可配置的 CST Pretty Printer 与 `doris-sql format` CLI，支持注释保留、缩进和关键字风格配置
- [ ] 提供 Native CLI/LSP 与 WebAssembly/JavaScript SDK，使同一解析器可用于 LSP、CLI、Web 和 Monaco 集成
- [ ] 保持解析与可选语义分析分离，允许无 catalog 元数据时进行纯语法校验，并为后续注入表/列元数据留下接口

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
*Last updated: 2026-08-03 after initialization*
