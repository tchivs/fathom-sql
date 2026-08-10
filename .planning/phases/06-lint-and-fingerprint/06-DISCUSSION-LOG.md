# Phase 6: Lint and Fingerprint - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-10
**Phase:** 6-lint-and-fingerprint
**Areas discussed:** 包布局与依赖纪律; Lint 规则集与稳定码; Lint autofix 架构与安全; Lint severity 配置面; Lint CLI/wire 消费面; Fingerprint 归一化语义; Fingerprint UInt64 哈希算法; Fingerprint API 面与跨目标 parity

> **Mode:** `--auto`（全自动）。所有灰区由 Claude 依据既有决策链选择推荐项，无用户交互。每条选择记录如下。

---

## 包布局与依赖纪律（横切）

| Option | Description | Selected |
|--------|-------------|----------|
| 独立库 lint/ + fingerprint/ | fingerprint/ 直接走读 CST（无 catalog）；lint/ 消费 syntax + formatter 安全编辑工具 + 可选 analyzer；parser 永不反向 import（D-21/D-27） | ✓ |

**User's choice:** `[auto]` 独立库布局（研究 ARCHITECTURE analysis 包布局 + D-21/D-27 单向纪律）
**Notes:** fingerprint/ 关键字大小写折叠只消费 `@token.classification_of`（D-28）；lint/ 复用 `formatter/refuse.mbt` `first_unsafe_element`（D-33）；analyzer 增强规则无 catalog 时静默跳过（ANLY-01）。

---

## Lint 规则集与稳定码

| Option | Description | Selected |
|--------|-------------|----------|
| 聚焦初始规则集（约 6–8 条） | SQLFluff 风格注册表：稳定码 `FATHOM-LINT-0xx`、名称、类别、默认 severity、fixable 标记、适用 profile；CST/profile 可确定性判定 + 可选 analyzer | ✓ |
| 最小 3 条示范规则 | 仅证明机制，覆盖不足 |
| 大而全规则集 | 超出本阶段可验证范围，引入语义猜测风险 |

**User's choice:** `[auto]` 聚焦初始规则集（推荐默认）
**Notes:** 候选方向（供 research 落地）：未加引号保留字作标识符、版本门禁语法 advisory、顶层 `SELECT *` 缺 LIMIT、analyzer 增强列引用/歧义、Doris 已废弃语法。规则码是公共契约（costly）。

---

## Lint autofix 架构与安全

| Option | Description | Selected |
|--------|-------------|----------|
| 最小 span edits | violation 局部替换，绝不重排整文档；复用 formatter `first_unsafe_element`（D-33）拒绝 error 树；每个 fix round-trip 断言 | ✓ |
| 全文档重排版 | 复用 format 全量输出；破坏"保留格式"承诺 |
| 直接 token 手术 | 绕过 formatter-safe 路径，违反 D-33 |

**User's choice:** `[auto]` 最小 span edits（研究 ARCHITECTURE Pitfall 2 明文 + D-33）
**Notes:** 树含 error/missing/skipped → accepted=false、空输出、单一拒绝诊断，绝不部分编辑（one-way 安全承诺）。

---

## Lint severity 配置面

| Option | Description | Selected |
|--------|-------------|----------|
| API LintOptions + CLI --rule 覆盖 | 默认注册表 + per-rule enable/disable + severity（error/warning/info）；CLI `--rule <code>=<severity|off>`；无配置文件 | ✓ |
| 配置文件 (yaml/json) | 新能力，超出本阶段 |
| 仅 API | 无法满足"User can run"（SC1） |

**User's choice:** `[auto]` API LintOptions + CLI 覆盖（SQLFluff 风格 + D-39 退出码 0/1/2）
**Notes:** 退出码 0 = 无超过阈值发现，1 = 有发现，2 = 用法/配置错误。

---

## Lint CLI/wire 消费面

| Option | Description | Selected |
|--------|-------------|----------|
| fathom-sql lint + fathom_lint_v1 | 新子命令 + `fathom.lint.v1` wire 导出 + schema v2 bump + api `lint_text`；LSP code actions 顺延 | ✓ |
| 仅 MoonBit library API | 无法满足 SC1 "run" |
| 全链路含 LSP code actions | 超出本阶段（TOOL-FUTURE-01） |

**User's choice:** `[auto]` CLI + wire 导出（Phase 5 D-06 兑现 + ROADMAP depends-on "serialized schema v2 bump"）
**Notes:** `validate_schema_version` 扩接受新命名空间（D-09 纪律）；LSP 面不做（one-way ABI）。

---

## Fingerprint 归一化语义

| Option | Description | Selected |
|--------|-------------|----------|
| 折叠仅 syntactic trivia | 空白→单空格、关键字 ASCII 小写（classification_of）、注释剔除；保留标识符拼写/大小写、字面量内容、引号风格 | ✓ |
| 也折叠标识符大小写 | 违反 FING-01 保留要求 |
| 也归一化字面量 | 改变语义，明确反需求 |

**User's choice:** `[auto]` 折叠仅 syntactic trivia（REQUIREMENT 明文 + 研究 Pitfall V4）
**Notes:** 归一化走读 CST 产生 canonical bytes（非序列化 JSON），与 schema 版本漂移无关（one-way）。

---

## Fingerprint UInt64 哈希算法

| Option | Description | Selected |
|--------|-------------|----------|
| 本地 FNV-1a 64-bit | 纯函数、零依赖、跨目标确定；满足 UInt64 固定 64-bit | ✓ |
| core Hasher (xxHash32) | 32-bit，不满足 FING-01 UInt64 要求 |
| moonbitlang/x crypto SHA-256 | 实验性依赖，违反核心零实验依赖 policy |

**User's choice:** `[auto]` 本地 FNV-1a 64-bit（STACK.md 已核实：core 无 hash 包、Hasher=xxHash32、Int 跨目标宽度不一致）
**Notes:** `Int` 在 Wasm/C 是 32-bit、JS 是 number；只有 `UInt64` 固定 64-bit 跨 Native/JS/linear-Wasm（one-way）。

---

## Fingerprint API 面与跨目标 parity

| Option | Description | Selected |
|--------|-------------|----------|
| CLI + wire + 包 + parity 测试 | `fathom-sql fingerprint` 子命令 + `fathom_fingerprint_v1` 导出（fathom.fingerprint.v1）+ `fingerprint_text -> (UInt64, normalized)` + parity/ 跨 native/js/wasm 一致性测试 | ✓ |
| 仅 library API | 无法满足 SC3 "generate" |
| 仅 CLI | 缺跨目标 parity 证明（SC4） |

**User's choice:** `[auto]` 全交付面 + 跨目标 parity（SC3/SC4 + 研究 ARCHITECTURE + Phase 12 D-03 纪律）
**Notes:** 复用 compare_backends.py / 现有三目标 parity 机制。

---

## Claude's Discretion

`--auto` 模式全部灰区由 Claude 依据既有决策链选择推荐项，无用户自由输入。决策依据：D-04/D-09（命名空间）、D-21/D-27/D-28/D-33（依赖与安全纪律）、D-39（CLI 退出码）、Phase 12 parity 纪律、v3.0 研究（UInt64/无 hash 包/CST 归一化）。D-01..D-08 覆盖全部灰区，无 "you decide"。

## Deferred Ideas

- LSP code actions / catalog-aware 语义智能 → TOOL-FUTURE-01（backlog）
- Lint 规则插件市场 → LINT-02
- 配置文件 → 多用户团队采纳需求出现时再评估
- 标识符 case-fold / 字面量归一化 → 明确反需求（FING-01 保留），永不默认
- 列级血缘 → LINE-01（Phase 7）；增量解析 → EDIT-01（Phase 8，benchmark-gated）
