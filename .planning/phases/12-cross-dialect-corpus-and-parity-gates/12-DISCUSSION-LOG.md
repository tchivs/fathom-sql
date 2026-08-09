# Phase 12: Cross-Dialect Corpus and Parity Gates - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-09
**Phase:** 12-cross-dialect-corpus-and-parity-gates
**Areas discussed:** Corpus Manifest 与分类语义, Doris 冻结 Diff Harness, 跨后端 Parity, 离线门禁与语义区分, 冲突可见性
**Mode:** --auto（用户以「继续」延续 auto 链；所有灰区自动选择推荐项，单次通过）

---

## Corpus Manifest 与分类语义

| Option | Description | Selected |
|--------|-------------|----------|
| 统一 release-pinned manifest + 6 类分类 | 每 fixture 记录 release/tag/commit、Calcite、URL/标题/日期/hash/期望状态 + positive/negative/recovery/known-limitation/catalog-prereq/planner-prereq；generic SQL 接受 ≠ 引擎支持 | ✓ |
| 仅维护既有 manifest 不扩展分类 | 不引入 6 类语义 | |

**User's choice:** 推荐项（统一 manifest + 6 类）— D-01/D-02
**Notes:** research flags 明文要求定义分类语义；CORPUS-01 字段枚举；既有 flink-lexical/flink-grammar fixtures 迁入统一结构不丢失。

## Doris 冻结 Diff Harness

| Option | Description | Selected |
|--------|-------------|----------|
| 形式化 Phase 9 baseline 门禁 | 显式 diff 报告 + 故意变更批准流；docs-vs-parser 冲突可见，不批量更新 | ✓ |
| 新建独立 harness | 另起炉灶 | |

**User's choice:** 推荐项（形式化既有门禁）— D-03/D-04
**Notes:** PARITY-01 即 Phase 9 D-07/D-08 的正式化；Phase 10/11 已保证 Doris 零漂移，本阶段验证。

## 跨后端 Parity

| Option | Description | Selected |
|--------|-------------|----------|
| 三目标字节级一致 | Native/JS/linear-Wasm 同一 fixture 序列化/诊断/span/lossless 字节一致 + CI 矩阵 | ✓ |
| 仅 native 验证 | 不扩三目标 | |

**User's choice:** 推荐项（三目标字节一致）— D-05
**Notes:** SC3/PARITY-02 明文；既有三目标 parity 测试为基础。

## 离线门禁与语义区分

| Option | Description | Selected |
|--------|-------------|----------|
| 离线 hash 验证 + parser/引擎语义区分报告 | 纯本地，release 钉住工件唯一事实源；覆盖报告区分 parser 接受 vs catalog/planner/引擎前置 | ✓ |
| 在线验证 | 允许网络访问 release | |

**User's choice:** 推荐项（离线 + 语义区分）— D-06
**Notes:** SC4/PARITY-03 明文禁网络/FE/cluster/DB。

## 冲突可见性

| Option | Description | Selected |
|--------|-------------|----------|
| 三方冲突显式报告 + 人工裁决 | docs/source/Calcite 冲突可见，批量更新须注册批准 | ✓ |
| 静默更新快照匹配实现 | 不设冲突报告 | |

**User's choice:** 推荐项（冲突可见）— D-07
**Notes:** Validation 明文「keep source provenance and docs-vs-parser conflicts visible rather than bulk-updating snapshots」。

## Claude's Discretion

无 — 所有灰区由既有决策链（Phase 9 D-01..D-11、Phase 10 D-01..D-06、Phase 11 D-01..D-07 + 本阶段 D-01..D-07）明确覆盖。

## Deferred Ideas

- Flink 工具链（TOOL-01..03）→ Phase 13
- 新 Flink grammar/词法能力 → 不在 Phase 12
- planner/执行等价、catalog 注入语义 → 不在 v2.0 范围
- 自动方言检测 → 未来阶段
- transpile → CONVERT-FUTURE-01
