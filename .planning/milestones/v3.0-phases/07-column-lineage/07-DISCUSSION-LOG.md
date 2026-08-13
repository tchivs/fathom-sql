# Phase 7: Column Lineage - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-11
**Phase:** 7-Column Lineage
**Areas discussed:** Edge model & expression semantics, View resolution, Set-op & INSERT mapping, Catalog injection, Star expansion & gap policy, Delivery surface, Dialect gating

**Mode:** `--auto` — 全部灰区由 Claude 依据既有决策链自动选择推荐项，无用户交互。

---

## 血缘边模型与表达式语义

| Option | Description | Selected |
|--------|-------------|----------|
| 表达式直通 | 输出列表达式内每个已解析列引用各自贡献一条 source→target 边（`a + b AS x` → t.a→x, t.b→x） | ✓ |
| 仅恒等直通 | 仅 `SELECT a AS x` 这类恒等投影产生边；复杂表达式视为不透明派生标记 | |
| 中间表达式节点 | column→expression→column 三节点图 | |

**User's choice:** 表达式直通（推荐默认）— 符合 SQLGlot/OpenLineage 列级血缘惯例；中间表达式节点图顺延 LINE-02。
**Notes:** 边复用 ANAL-01 `SelectItem.refs` 与 Binding；未解析列引用 → `unresolved-reference` gap。

## 视图解析机制

| Option | Description | Selected |
|--------|-------------|----------|
| 同文档视图注册表 | 解析同文档 CREATE VIEW 体 → 内存 view→输出列映射；基表/外部视图列元数据来自 catalog | ✓ |
| 仅 catalog | 视图列元数据全部由 catalog 注入（view 作为 TableInfo），不解析 CREATE VIEW 体 | |
| 两者 | 同文档注册表 + catalog 双源 | |

**User's choice:** 同文档视图注册表（推荐默认）— 兑现 Phase 5 D-05 顺延；外部视图无元数据 → `requires-catalog` gap。
**Notes:** CTE 展开复用 analyzer 既有作用域栈（CteDef 已解析），不新写 CTE 引擎。

## 集合运算与 INSERT 列映射

| Option | Description | Selected |
|--------|-------------|----------|
| 位置映射 + 列列表对齐 | 集合运算输出列 i 继承各分支第 i 列；INSERT 目标列列表与 SELECT 输出按位置对齐；VALUES 按列序；SET 按列名 | ✓ |
| 仅列名匹配 | 全部按列名对齐 | |
| 受限 | 集合运算位置映射，INSERT 仅处理无列列表全表 INSERT | |

**User's choice:** 位置映射 + 列列表对齐（推荐默认）— UNION 输出列名取首分支（Phase 5 既有约定）；INSERT 目标表复用 `resolve_table_references`。

## Catalog 注入面

| Option | Description | Selected |
|--------|-------------|----------|
| 可选 catalog 参数 | `lineage_text`/wire 导出接受可选 catalog（JSON），CLI `--catalog <file>`；缺省全 gap | ✓ |
| 仅库 API | wire/CLI 不带 catalog，仅 MoonBit 库 API 提供 catalog 路径 | |
| 内联 JSON 标志 | CLI `--catalog-json` 内联参数 | |

**User's choice:** 可选 catalog 参数（推荐默认）— 延续 T-02-42（调用方拥有元数据、只被 analyzer 消费）；SC2 要求 `*` 展开需 catalog，缺省诚实全 gap。

## `*` 展开与 Gap 政策

| Option | Description | Selected |
|--------|-------------|----------|
| 独立 gaps 列表 | edges 与 gaps 分离；codes = requires-catalog / unresolved-reference / requires-complete-parse，带 span；有 catalog 时 `*` 展开为边 | ✓ |
| 仅诊断 | gap 承载在 analyzer 诊断列表 | |
| 合并边 | gap 作为带标记的 edge | |

**User's choice:** 独立 gaps 列表（推荐默认）— SC2 明文"不伪造边"；`requires-complete-parse` 复用 `has_error_missing`（D-33 拒绝哲学）。

## 交付面范围

| Option | Description | Selected |
|--------|-------------|----------|
| 全对齐 Phase 6 | `lineage/` 包 + `api.lineage_text` + `fathom.lineage.v1` wire（schema 第 8 命名空间）+ CLI `lineage` 子命令 + parity + docs | ✓ |
| 库 + api | 无 wire/CLI | |
| 库 + wire | 无 CLI | |

**User's choice:** 全对齐 Phase 6（推荐默认）— 研究 ARCHITECTURE 明文 `lineage_text` + `fathom.lineage.v1`；D-06 递延的"真实宿主消费时再接"在此兑现。

## 方言门禁

| Option | Description | Selected |
|--------|-------------|----------|
| Doris-only | 本阶段 lineage 仅 Doris；flink → 显式不支持（FATHOM-SCHEMA 族） | ✓ |
| 方言中性 | flink 也解析 | |
| 静默空 | flink 返回空结果 | |

**User's choice:** Doris-only（推荐默认）— LINE-01 按 Doris 需求定义；延续 D-04/D-05（不新造 FATHOM-LINE-*、不建 flink 命名空间），绝不静默空结果。

---

## Claude's Discretion

`--auto` 模式全部灰区由 Claude 依据既有决策链选择推荐项（D-21、Phase 5 D-01/D-05/D-06、Phase 6 D-04/D-05/D-06、ANLY-01、T-02-42、ROADMAP SC2、研究 Pitfall V1/V3/V6），无用户自由输入。

## Deferred Ideas

- 跨库/catalog 血缘联邦 → LINE-02
- 表达式级 taint / 中间表达式节点图 → LINE-02 级扩展
- Flink 血缘 → 后续阶段
- LSP 血缘可视化 / 语义智能 → TOOL-FUTURE-01
- 视图定义持久化 / 外部视图服务 → catalog 演进
