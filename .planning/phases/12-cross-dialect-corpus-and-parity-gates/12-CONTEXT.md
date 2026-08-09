# Phase 12: Cross-Dialect Corpus and Parity Gates - Context

**Gathered:** 2026-08-09
**Status:** Ready for planning

<domain>
## Phase Boundary

本阶段把前序各阶段已建的分散门禁（Phase 9 Doris baseline 冻结 + approved-changes 注册表、Phase 10 flink-lexical manifest、Phase 11 flink-grammar fixtures + 快照）整合为维护者可审计的跨方言覆盖与 parity 契约：发布钉住的 Flink corpus manifest（release/tag/commit、Calcite 版本/config、URL/标题/检索日期/hash、期望状态、6 类分类），Doris 冻结 diff harness（PARITY-01），跨后端（Native/JS/linear-Wasm）字节级一致（PARITY-02），以及离线 CI/release 门禁 + parser-接受 vs 引擎-语义 区分（PARITY-03）。不新增 Flink grammar/词法能力（Phase 10/11 已完成）、不实现工具链（Phase 13）。

**Requirements:** CORPUS-01, PARITY-01, PARITY-02, PARITY-03（4 个）

</domain>

<decisions>
## Implementation Decisions

### Corpus Manifest 与分类语义
- **D-01:** Flink corpus manifest 采用统一 release-pinned 格式：每个 fixture 记录 release/tag/commit、Calcite 版本/config、来源 URL/文档标题、检索日期、hash、期望状态，以及 6 类分类（positive / negative / recovery / known-limitation / catalog-prerequisite / planner-prerequisite）。分类语义在 fixture 层面固化：**generic SQL 被解析器接受 ≠ Flink 引擎支持** — 一个 SQL 即使语法可解析，若依赖 catalog/planner/引擎语义仍按其前置分类标注，绝不把语法接受报告为引擎支持（research flags 明文）。**Reversibility:** costly — manifest 是公共审计契约，字段语义变更需全量重标。
- **D-02:** 现有 flink-lexical（Phase 10）与 flink-grammar（Phase 11）fixture/快照迁入统一 corpus 结构，按 6 类重新归类；不丢任何现有 fixture。**Reversibility:** reversible。

### Doris 冻结 Diff Harness（PARITY-01）
- **D-03:** 复用 Phase 9 的 baseline 门禁（D-07/D-08：213 快照 + approved-changes 注册表 + baseline_diff），形式化为显式 diff harness：任何共享/方言改造后输出「冻结 vs 当前」差异报告；故意变更须经注册表批准流，docs-vs-parser 冲突显式可见，绝不静默批量更新快照。**Reversibility:** reversible — harness 可增补，但一旦 CI 接线即成为契约。
- **D-04:** PARITY-01 覆盖 Doris 2.1/3.x/4.x 的 valid/invalid/recovery/CST/span/diagnostic/formatter/completion 全部既有快照面；Phase 10/11 的 flink 改造不得引入未记录 Doris 变更（已由零漂移保证，本阶段形式化验证）。**Reversibility:** one-way — 冻结 baseline 是 Phase 9 起确立的公共契约。

### 跨后端 Parity（PARITY-02）
- **D-05:** 同一 fixture 集在 Native/JS/linear-Wasm 三目标上序列化结果、诊断、span、lossless replay 字节级一致；CI 增加三目标矩阵并比对字节。**Reversibility:** one-way — 跨后端字节一致性是 SDK 核心承诺，任何后端偏差都是契约破坏。

### 离线门禁与语义区分（PARITY-03）
- **D-06:** 离线 manifest/hash 验证器（纯本地，无网络/Doris-FE/Flink-cluster/DB 运行时访问）；release 钉住工件（归档 + 校验和）为唯一事实源，禁移动 docs。覆盖报告区分 parser 接受 vs catalog/planner/引擎语义前置，双方言同制。**Reversibility:** one-way — CI 门禁形态是发布契约。

### 冲突可见性
- **D-07:** docs/source/Calcite 三方冲突（fixture 期望 vs 实现 vs release 事实）显式报告 + 人工裁决入口；任何「更新快照以匹配实现」的批量动作须经注册表批准并记录理由。**Reversibility:** reversible。

### Claude's Discretion
（未出现 "you decide"；所有灰区由既有决策链 + 本阶段 D-01..D-07 明确覆盖。）

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 需求与路线图
- `.planning/REQUIREMENTS.md` — CORPUS-01, PARITY-01..03
- `.planning/ROADMAP.md` §Phase 12 — Goal/SC/Validation/Research flags
- `.planning/PROJECT.md` — Current Milestone v2.0

### 前序阶段决策与门禁（整合依据）
- `.planning/phases/09-dialect-boundary-and-neutral-naming/09-CONTEXT.md` — D-07/D-08（Doris baseline 冻结 + 注册表批准制）、D-10（诊断身份）
- `.planning/phases/09-dialect-boundary-and-neutral-naming/09-RESEARCH.md` — baseline 冻结流程、parity 门禁设计
- `.planning/phases/10-flink-release-profiles-and-lexical-core/10-RESEARCH.md` — Calcite pin 表、flink-lexical manifest、release 归档/校验和
- `.planning/phases/11-flink-grammar-and-recoverable-cst/11-RESEARCH.md` — flink-grammar fixtures、production 行号、TVF/MR 子集
- 各阶段 `approved-changes.md` 注册表、`parity/__snapshot__/` 快照组（doris baseline 213、flink-lexical 26、flink-grammar ~90+）

### 现状代码与数据（扩展依据）
- `parity/` — baseline_test.mbt、flink_lexical_test.mbt、flink_grammar_test.mbt、fixtures/、__snapshot__/
- `scripts/baseline_diff.py`、`scripts/extract_flink_lexical.py`、`scripts/extract_flink_grammar.py` — 门禁/提取工具
- `.github/workflows/ci.yml` — parity-gate、native/js/wasm 矩阵
- `corpus/` — manifest.tsv + tools/check_keywords.py

### 外部事实源（研究期钉住）
- `/tmp/flink-research/` — 三个 release 源码归档 + 校验和（Phase 10 已验证）；fixture 来源
- Apache Flink release 官方归档（URL/校验和已入 manifest）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `parity/baseline_test.mbt` + `@test.T::snapshot` + `scripts/baseline_diff.py` + `approved-changes.md` — Doris 冻结 diff harness 与注册表批准制（PARITY-01 直接形式化）
- `parity/fixtures/flink-lexical/manifest.tsv` + `extract_flink_lexical.py`（manifest sha512 复验）— corpus manifest 蓝本
- `extract_flink_grammar.py`（production 行号校验 + manifest）— fixture 溯源
- parity 三目标测试（native/js/wasm `moon test --target ... --package parity`）— PARITY-02 字节比对基础
- `.github/workflows/ci.yml` parity-gate job — 离线门禁接线点

### Established Patterns
- 快照/golden 纪律 + 注册批准制（D-08）
- release 钉住 + 校验和 + 可审计来源（Phase 10 D-02）
- dialect 不进诊断 code 前缀（D-10）
- 有界恢复 + 无损 round-trip（CST-01）

### Integration Points
- `parity/` — 统一 corpus 目录结构 + manifest + 快照分组
- `scripts/` — 新 `verify_corpus.py`（离线 hash/分类验证器）、扩展 baseline_diff
- `.github/workflows/ci.yml` — 三目标 parity 矩阵 + 离线门禁 job
- 既有 fixture（flink-lexical/flink-grammar/doris baseline）— 迁入统一分类

</code_context>

<specifics>
## Specific Ideas

用户明确的边界意图（来自前序讨论链延续）：
- 6 类 fixture 分类：positive/negative/recovery/known-limitation/catalog-prerequisite/planner-prerequisite
- generic SQL 接受 ≠ Flink 引擎支持（PARITY-03 / research flags 明文）
- 离线：无 Doris FE / Flink cluster / 数据库 / 网络运行时访问（SC4 明文）
- docs-vs-parser 冲突可见，不批量更新快照（Validation 明文）
- 同一 fixture 跨 Native/JS/linear-Wasm 字节级一致（SC3 / PARITY-02）

</specifics>

<deferred>
## Deferred Ideas

- Flink 工具链（format/completion/analyzer 方言分发）→ Phase 13（TOOL-01..03）
- 新 Flink grammar/词法能力 → 不在 Phase 12（Phase 10/11 已完成语法面）
- planner/执行等价、catalog 注入的语义解析 → 不在 v2.0 SDK 范围
- 自动方言检测（即使 opt-in）→ 未来阶段
- 显式跨方言转换（transpile）→ CONVERT-FUTURE-01

</deferred>

---

*Phase: 12-Cross-Dialect Corpus and Parity Gates*
*Context gathered: 2026-08-09*
