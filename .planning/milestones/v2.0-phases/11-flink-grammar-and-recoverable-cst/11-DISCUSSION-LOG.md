# Phase 11: Flink Grammar and Recoverable CST - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-07
**Phase:** 11-flink-grammar-and-recoverable-cst
**Areas discussed:** Grammar 作用域与子集, CST 与恢复, 方言路由与负门禁, 语句覆盖与交付顺序
**Mode:** --auto（用户以「继续」延续 auto 链；所有灰区自动选择推荐项，单次通过）

---

## Grammar 作用域与子集

| Option | Description | Selected |
|--------|-------------|----------|
| 全量枚举范围 + 研究定义子集 | FLINK-02..06 全部入本阶段；Window TVF/MATCH_RECOGNIZE 的 supported/known-limitation 子集由研究阶段从 release grammar + Calcite 测试定义并冻结 | ✓ |
| 子集先行 | 先只做核心查询，DDL/TVF/MR 推迟 | |

**User's choice:** 推荐项（全量枚举 + 研究定义子集）— D-01
**Notes:** 需求已明文枚举；research flags 明文要求定义 TVF/MR 子集；语法级即可，不声称 planner 等价（FLINK-06）。

## CST 与恢复

| Option | Description | Selected |
|--------|-------------|----------|
| 复用 Doris 无损 CST 节点体系 | 同一 source-backed Statement/Clause/Expr + error/missing/skipped + span/trivia；新增 Flink 语句族节点 | ✓ |
| 独立 Flink AST | 为 Flink 另建一套 AST | |

**User's choice:** 推荐项（复用 CST 体系）— D-02/D-03
**Notes:** 无损 round-trip 是核心产品契约（CST-01）；恢复纪律与 Doris 一致（语句级 panic + 子句级尽力 + editor/strict）。

## 方言路由与负门禁

| Option | Description | Selected |
|--------|-------------|----------|
| 单一路由 + 双向负门禁 | parse_segment Flink 分支换真实 grammar；Flink-only 在 Doris 拒绝、Doris-only 在 Flink 拒绝，稳定 FATHOM-PARSE-* 码 | ✓ |
| 仅单向（Flink 内校验） | 只在 Flink 模式校验，Doris 模式不拒 Flink 语法 | |

**User's choice:** 推荐项（双向负门禁）— D-04
**Notes:** SC4 明文双向；诊断码 dialect-neutral（D-10 延续）。

## 语句覆盖与交付顺序

| Option | Description | Selected |
|--------|-------------|----------|
| Vertical slice 按需求顺序 | FLINK-02 核心查询 → 03 DDL → 04 CREATE TABLE → 05 TVF → 06 MR，每片含双模式 + 快照 | ✓ |
| 水平分层 | 先全部语句骨架，再统一表达式 | |

**User's choice:** 推荐项（vertical slice）— D-07
**Notes:** MVP 模式（vertical slicing）；FATHOM-PARSE-008 退役（D-06）属路线图既定行为变更。

## Claude's Discretion

无 — 所有灰区由既有决策链（Phase 9 D-01..D-11、Phase 10 D-01..D-06 + 本阶段 D-01..D-07）明确覆盖。

## Deferred Ideas

- Flink 工具链（TOOL-01..03）→ Phase 13
- 全量 Flink corpus/parity → Phase 12
- planner/执行等价、catalog 依赖语义 → 不在 v2.0 范围
- 自动方言检测 → 未来阶段
- transpile → CONVERT-FUTURE-01
