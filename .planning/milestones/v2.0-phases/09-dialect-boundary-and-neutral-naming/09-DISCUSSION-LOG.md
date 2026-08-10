# Phase 9: Dialect Boundary and Neutral Naming - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-06
**Phase:** 9-Dialect Boundary and Neutral Naming
**Areas discussed:** Dialect 选择优先级, 命名清理边界, Doris baseline 范围, Schema 与诊断身份, Baseline 冻结形式, CLI 参数形态

---

## Dialect 选择优先级

| Option | Description | Selected |
|--------|-------------|----------|
| 文档优先 | 文档级显式配置 > workspace/session 初始化 > languageId 映射；同一来源冲突报错 | ✓ |
| languageId 优先 | languageId 是唯一权威，API/LSP 配置只作默认值 | |
| 会话优先 | initialize 时 workspace dialect 唯一权威，文档不能覆盖 | |

**User's choice:** 文档优先
**Notes:** 支持一个 workspace 同时使用 Doris 和 Flink；选择结果可审计。

| Option | Description | Selected |
|--------|-------------|----------|
| 显式 workspace 默认 | 允许显式配置 workspace/project 默认 dialect+profile；无配置且文档无显式选择时报配置错误 | ✓ |
| 每文档必选 | 每个文档必须携带 dialect+profile，workspace 不提供默认 | |
| languageId 兜底 | 无显式设置时按 languageId 映射作为默认 | |

**User's choice:** 显式 workspace 默认
**Notes:** 排除了隐式 languageId 兜底；languageId 仅在用户显式配置映射时参与。

| Option | Description | Selected |
|--------|-------------|----------|
| 立即重解析 | 切换后立即按新 context 重解析当前 revision，刷新结果并丢弃旧异步结果 | ✓ |
| 下次编辑生效 | 只在下一次编辑或手动 Parse 时生效 | |
| 仅新文档生效 | 已打开文档保持原 context | |

**User's choice:** 立即重解析

---

## 命名清理边界

| Option | Description | Selected |
|--------|-------------|----------|
| 归档豁免 | milestones/v1.0-*、v1.0-research 等历史归档保持原样；gate 只覆盖现行文件 | ✓ |
| 全量清理 | 所有文件含历史归档都要过改名 gate | |

**User's choice:** 归档豁免

| Option | Description | Selected |
|--------|-------------|----------|
| 保留方言类型名 | DorisProfile/DorisFeature 保留，新增 Dialect/DialectContext/FlinkProfile | ✓ |
| 全量泛化 | 统一 Profile/Feature + dialect 字段 | |

**User's choice:** 保留方言类型名
**Notes:** 产品层只改包名/export/schema/错误码/二进制/LSP identity/扩展/文档标题。

---

## Doris Baseline 范围

| Option | Description | Selected |
|--------|-------------|----------|
| 全量冻结 | CST/span、diagnostics、strict/editor、formatter、completion、CLI exit、LSP、schema 字节级比较 | ✓ |
| 核心子集 | 只冻结 parser/API 核心，formatter/completion/CLI/LSP 后续再验证 | |

**User's choice:** 全量冻结

---

## Schema 与诊断身份

| Option | Description | Selected |
|--------|-------------|----------|
| 中立 schema+metadata | fathom.*.v1 统一，dialect/profile 放 metadata 字段，code 统一 FATHOM-* | ✓ |
| code 带方言前缀 | schema 中立但诊断 code 保留 DORIS-*/FLINK-* | |

**User's choice:** 中立 schema+metadata

---

## Baseline 冻结形式

| Option | Description | Selected |
|--------|-------------|----------|
| 快照 diff 门禁 | 用 corpus+快照建立 baseline 目录，改造后 diff，字节级一致或经批准变更才通过 | ✓ |
| 仅现有测试 | 188 测试全绿即视为无回归 | |
| 快照+测试 | 双保险，工作量最大 | |

**User's choice:** 快照 diff 门禁

---

## CLI 参数形态

| Option | Description | Selected |
|--------|-------------|----------|
| 分开必选 | `fathom-sql parse --dialect doris --profile 4.x`，缺失即报错 | ✓ |
| 合并参数 | `--dialect doris:4.x` 合并成一个参数 | |

**User's choice:** 分开必选

---

## Claude's Discretion

无 — 所有灰区均由用户明确选择。

## Deferred Ideas

- Flink grammar/工具链细节 → Phase 10/11/13
- Flink corpus 提取与 Calcite pin → Phase 10/12
- 自动方言检测（即使 opt-in）→ 未来阶段
- 显式跨方言转换 → CONVERT-FUTURE-01
