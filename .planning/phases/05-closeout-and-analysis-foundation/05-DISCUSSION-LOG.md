# Phase 5: Closeout and Analysis Foundation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-10
**Phase:** 5-closeout-and-analysis-foundation
**Areas discussed:** 分析模型与覆盖范围, 标识符大小写与类型诊断, Catalog 模型扩展, 公共消费面, Closeout 范围

**Mode:** `--auto`（所有灰区由 Claude 依据既有决策链选择推荐项，无用户交互）

---

## 分析模型（ANAL-01 结构）

| Option | Description | Selected |
|--------|-------------|----------|
| A. Analyzer 侧二次解析 token 流 | analyzer 内部对恢复的 token 流建立轻量分析模型（顶层子句切分、括号深度感知），不新增 SyntaxKind、不改 parser，保持 D-21 边界 | ✓ |
| B. 新增 SyntaxKind 细分节点 | 在 parser/syntax 增加子句/表项/限定名节点 — 违反冻结 Doris parser 硬门禁、改变线缆契约 | |
| C. 顺延 SELECT | 只扩展 DML/DDL 表级走查 — 低于 ANAL-01 交付要求（SELECT 是核心） | |

**Claude's choice:** A — Analyzer 侧二次解析 token 流
**Notes:** 依据 parser.mbt `finish_statement`/`segment_children_for_events` 实证：Select 节点为平铺 token-leaf 流，无子句细分；D-21 边界 + Phase 12 冻结基线决定不能在语法层加节点。

## 语句覆盖范围

| Option | Description | Selected |
|--------|-------------|----------|
| A. SELECT 为核心 + DML 列引用扩展 | SELECT 全子句（列表/FROM+JOIN/WHERE/GROUP/HAVING/ORDER/QUALIFY、CTE、子查询、集合运算）+ INSERT/UPDATE/DELETE/MERGE SET/WHERE/VALUES 列引用 + CREATE VIEW 体表引用 | ✓ |
| B. 仅 DML/DDL 表级 | 维持现有走查，不扩 SELECT — 无法满足 ANAL-01 | |

**Claude's choice:** A — SELECT 为核心 + DML 列引用扩展

## 标识符大小写策略

| Option | Description | Selected |
|--------|-------------|----------|
| A. 解析时 ASCII case-fold | catalog key/display 保持作者原样，解析时折叠比较；binding 保留源码拼写 + span；带引号标识符精确匹配 | ✓ |
| B. 构造期归一化 catalog keys | 转小写存储 — 丢失作者 display 名 | |
| C. per-dialect 可配置 | 本阶段仅 Doris，过度设计 | |

**Claude's choice:** A — 解析时 ASCII case-fold
**Notes:** 镜像 parser.mbt `bytes_equal_ci`；满足 ROADMAP SC4（case policy documented；quoted keep exact case）。

## 类型诊断深度

| Option | Description | Selected |
|--------|-------------|----------|
| A. binding 携带类型 + 存在性/歧义/元数诊断 | 列 data_type、函数签名返回类型；未知表/列/函数、歧义非限定引用、函数元数不匹配；无表达式级合一 | ✓ |
| B. 仅名字解析 | 类型存储但不检查 — 低于 "type diagnostics" 要求 | |
| C. 完整类型推导 | 表达式级合一 — 与 ANAL-02 重叠，出界 | |

**Claude's choice:** A — binding 携带类型 + 存在性/歧义/元数诊断

## Catalog 模型扩展

| Option | Description | Selected |
|--------|-------------|----------|
| A. namespace + 函数注册表 | `db.table`/`db.table.column` 限定名解析 + FunctionInfo（name/param types/return type）；视图展开顺延 LINE-01 | ✓ |
| B. 扁平 + 函数表 | 无 db 维度 — 限定引用不完整 | |
| C. 含视图定义展开 | 与 Phase 7 LINE-01 重叠 | |

**Claude's choice:** A — namespace + 函数注册表

## 公共消费面

| Option | Description | Selected |
|--------|-------------|----------|
| A. MoonBit library API | `fathom/sql/analyzer` 返回结构化 AnalysisResult（bindings + 带 span 诊断），可序列化记录；wire/CLI/LSP 在 Phase 6 再接 | ✓ |
| B. 新增 fathom.analyze.v1 wire 导出 | 本阶段无宿主消费，过重 | |
| C. CLI 子命令 fathom-sql analyze | 无宿主消费，过重 | |

**Claude's choice:** A — MoonBit library API

## Closeout 范围

| Option | Description | Selected |
|--------|-------------|----------|
| A. 正式记录/核实证据 + traceability | host-verify.mjs + ci.yml linear-wasm-parity 已在仓库；只更新记录 | ✓ |
| B. 重跑 VS Code 验证 + wasm parity | 2026-08-06 已核实，浪费 | |
| C. 从阶段移除 closeout | 需求仍映射到本阶段，需保留 traceability | |

**Claude's choice:** A — 正式记录/核实证据

---

## Claude's Discretion

`--auto` 模式：所有灰区由 Claude 依据既有决策链（D-21..D-24、Phase 12 冻结基线、ANLY-01、T-02-42）选择推荐项，无用户自由输入。

## Deferred Ideas

- 视图定义展开 → LINE-01（Phase 7）
- 完整类型推导 → ANAL-02（出界）
- wire 导出 fathom.analyze.v1 / CLI 子命令 → Phase 6 或首个宿主消费时
- catalog 感知补全/hover/语义 tokens → TOOL-FUTURE-01
- 增量解析 → EDIT-01（Phase 8）
