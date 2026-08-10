# Phase 6: Lint and Fingerprint - Context

**Gathered:** 2026-08-10
**Status:** Ready for planning

<domain>
## Phase Boundary

本阶段交付两个并行能力（v3.0 分析层，`--auto` 全自动决策，无用户交互）：

1. **LINT-01（Doris 专属 Lint）** — 可运行的 Doris 专属 Lint 规则集：SQLFluff 风格规则注册表（稳定规则码、per-rule enable/disable、可配置 severity）+ 安全无损 autofix（保留注释/trivia/格式，按 formatter D-33 原则拒绝 error 树的 unsafe 编辑，每个 fix 通过 round-trip 断言）。
2. **FING-01（跨后端稳定 SQL 指纹）** — 支持语句的稳定指纹与归一化形式：跨空白/关键字大小写/注释稳定；保留标识符拼写、字面量内容、引号风格；UInt64 哈希在 Native/JS/linear-Wasm 三目标一致。

**Requirements:** LINT-01, FING-01

**不在范围：** 列级血缘（LINE-01 → Phase 7）、增量解析（EDIT-01 → Phase 8，benchmark-gated）、完整类型推导（ANAL-02）、LSP code actions / catalog-aware 语义智能（TOOL-FUTURE-01）、Lint 规则插件市场（LINT-02）、跨库血缘联邦（LINE-02）、配置文件（本阶段用 API struct + CLI flags）。

</domain>

<decisions>
## Implementation Decisions

### 包布局与依赖纪律（横切）
- **D-01:** 新增独立库 `lint/` 与 `fingerprint/`（对应研究 ARCHITECTURE 的 analysis 包布局）。`fingerprint/` 直接走读 CST（不 import analyzer，无 catalog 依赖），关键字大小写折叠只消费 `@token.classification_of`（D-28 纪律，不建第二关键字表）。`lint/` 消费 syntax + formatter 安全编辑工具（复用 `formatter/refuse.mbt` 的 `first_unsafe_element`，D-33），analyzer 增强规则可选、在无 catalog 时静默跳过（ANLY-01 纪律：语法 valid 通道永不改变）。parser 永不 import lint/fingerprint（D-21/D-27 单向纪律延续）。**Reversibility:** costly — 包边界是公共模块结构；收窄依赖需迁移 import。

### Lint 规则集与稳定码
- **D-02:** 初始规则集为**聚焦集合（约 6–8 条）**，SQLFluff 风格注册表：每条规则 = 稳定码（`FATHOM-LINT-0xx`，命名中立、D-04 纪律）、名称、类别、默认 severity、fixable 标记、适用 profile。规则必须可确定性地从 CST（+ profile gate）+ 可选 analyzer（有 catalog 时）判定，不引入语义猜测。候选方向供 research 落地：未加引号保留字作标识符、版本门禁语法 advisory（构造需较新 profile）、顶层 `SELECT *` 缺 LIMIT、analyzer 增强的列引用/歧义规则、Doris 已废弃语法。**Reversibility:** costly — 规则码是公共契约；发布后重编号破坏下游配置。

### Lint autofix 架构与安全
- **D-03:** Autofix 产出**最小 span edits**（violation 局部替换，绝不重排整文档——整文档重排会破坏"保留格式"承诺）。安全闸：复用 formatter `first_unsafe_element`（D-33）——树含 error/missing/skipped 材料 → `accepted=false`、空输出、恰好一个拒绝诊断，绝不部分编辑。每个 fix 后必须 round-trip 断言（应用 fix 后 untouched 字节不变、reparse 干净）。**Reversibility:** one-way — autofix 编辑语义是安全承诺；若后续改为整文档重排需重新定义安全边界并迁移断言。

### Lint severity 配置面
- **D-04:** SQLFluff 风格 per-rule 配置：默认注册表 + per-rule enable/disable + severity（error/warning/info）。配置载体 = **API `LintOptions` 结构** + CLI `--rule <code>=<severity|off>` 覆盖；**不引入配置文件**（新能力，超出本阶段）。CLI 退出码沿用 D-39 模式：0 = 无超过阈值发现，1 = 有发现（findings 输出），2 = 用法/配置错误。**Reversibility:** reversible — 配置键可增删。

### Lint CLI/wire 消费面
- **D-05:** Phase 5 D-06 的"有真实宿主消费时再接"在此兑现：新增 `fathom-sql lint` 子命令 + `fathom_lint_v1` wire 导出（`fathom.lint.v1` 命名空间）+ "schema v2 bump"（ROADMAP depends-on 明文；`binding/schema.mbt` `validate_schema_version` 扩接受新命名空间，D-09 纪律）。`api/` 增加 `lint_text` 序列化入口（研究 ARCHITECTURE 约定）。**LSP code actions 顺延**（TOOL-FUTURE-01），本阶段不做 LSP 面。**Reversibility:** one-way — wire 命名空间是公开 ABI；发布后改名需迁移所有宿主。

### Fingerprint 归一化语义
- **D-06:** 归一化折叠**仅 syntactic trivia**：空白折叠为单空格分隔、关键字 ASCII 小写（经 `@token.classification_of`，D-28）、注释整体剔除。**保留**：标识符拼写与大小写（含带引号标识符）、字面量内容、引号风格。归一化走读 CST 产生 canonical bytes（研究 Pitfall V4：normalize the CST, not the serialized JSON），与 schema 版本漂移无关。**Reversibility:** one-way — 归一化语义决定指纹值；改动会改变所有已发布指纹，需版本迁移。

### Fingerprint UInt64 哈希算法
- **D-07:** 本地实现 **FNV-1a 64-bit** 纯函数哈希（canonical bytes → `UInt64`），零依赖、跨目标确定。依据（STACK.md 已核实）：core **无 `hash` 包**、`Hasher` 是 xxHash32（非 64-bit）；`Int` 在 Wasm/C 是 32-bit、JS 是 number，**只有 `UInt64` 固定 64-bit**——满足 FING-01 跨 Native/JS/linear-Wasm 一致。不用 `moonbitlang/x` crypto（实验性，且 policy 要求核心零实验依赖）。**Reversibility:** one-way — 哈希算法决定指纹值；换算法破坏全部已发布指纹。

### Fingerprint API 面与跨目标 parity
- **D-08:** 交付面：`fathom-sql fingerprint` 子命令（输出指纹 UInt64 + 可选归一化文本）+ `fathom_fingerprint_v1` wire 导出（`fathom.fingerprint.v1`，进 validate_schema_version v2 bump）+ `fingerprint/` MoonBit 包 `fingerprint_text(raw, dialect, profile) -> (UInt64, normalized_bytes)`。**parity/ 新增跨目标一致性测试**：同一 fixture 在 native/js/wasm 产出相同 UInt64（复用 compare_backends.py / 现有三目标 parity 机制，Phase 12 D-03 纪律）。**Reversibility:** costly — API 形状与测试面扩展触及公共边界。

### Claude's Discretion
（`--auto` 模式：全部灰区由 Claude 依据既有决策链——D-04/D-09（命名空间）、D-21/D-27/D-28/D-33（依赖与安全纪律）、D-39（CLI 退出码）、Phase 12 parity 纪律、v3.0 研究（UInt64/无 hash 包/CST 归一化）——选择推荐项；D-01..D-08 覆盖全部灰区，无 "you decide"。）

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 需求与路线图
- `.planning/ROADMAP.md` §Phase 6 — Goal / Success Criteria（4 条：LINT-01 规则集、LINT-01 autofix、FING-01 归一化、FING-01 跨目标）
- `.planning/REQUIREMENTS.md` — v3.0 需求 LINT-01 / FING-01 全文
- `.planning/milestones/v3.0-REQUIREMENTS.md` — 归档需求定义与 traceability
- `.planning/PROJECT.md` — Core Value、Constraints、Key Decisions

### 前序阶段决策（延续依据）
- `.planning/STATE.md` §Accumulated Context Decisions — D-21/D-27（单向依赖）、D-28（关键字大小写经 classification_of）、D-33（formatter 拒绝绝对）、D-39（CLI 退出码）、D-04/D-09（fathom.*.v1 命名空间、FATHOM-* 码）、D-05（Catalog 契约）、ANLY-01（analyzer 独立诊断通道）
- `.planning/phases/05-closeout-and-analysis-foundation/05-CONTEXT.md` — D-06（wire/CLI/LSP 在本阶段消费同一分析结果模型）、AnalysisResult 模型
- `.planning/milestones/v1.0-research/SUMMARY.md` — v2 研究：FING-01 必须 UInt64（Int 跨目标宽度不同）、LINT-01 SQLFluff 风格、新包 lint//fingerprint/
- `.planning/milestones/v1.0-research/ARCHITECTURE.md` §Analysis 包布局 — lint/（CST walk + formatter-safe edit）、fingerprint/（CST→canonical→UInt64）、binding/ schema v2 bump、api/ `lint_text`/`fingerprint_text`
- `.planning/milestones/v1.0-research/STACK.md` — core 无 hash 包、Hasher=xxHash32、Int vs UInt64 宽度、LinkedHashMap 确定性
- `.planning/milestones/v1.0-research/PITFALLS.md` §Pitfall V4 — 指纹跨后端漂移与语义折叠预防

### 现状代码（扩展依据）
- `formatter/refuse.mbt` — `first_unsafe_element`（D-33 拒绝扫描，autofix 安全闸直接复用）
- `formatter/format.mbt` — FormatResult（accepted/output/diagnostics/statement_offsets）、trivia 保留模式
- `analyzer/analysis.mbt` — AnalysisResult / Binding / AnalysisDiagnostic（D-06 消费模型）
- `api/api.mbt` — `format_text`/`format_with_ids` 共享核心入口模式（lint_text/fingerprint_text 仿此）
- `binding/schema.mbt` — `validate_schema_version`（v2 bump 点）、envelope JSON 模式
- `binding/exports.mbt` — `#export_name("fathom_lint_v1"/"fathom_fingerprint_v1")` ABI 模式
- `fathom-sql/args.mbt` + `run.mbt` + `main.mbt` — CLI 子命令分发与 D-39 退出码
- `parity/`（`run_js.mbt`/`run_wasm.mbt`/`compare_backends.py`）— 跨目标一致性测试机制
- `docs/API.md` — 公共 API 文档（新增 lint/fingerprint 章节）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `formatter/refuse.mbt` `first_unsafe_element`：递归扫描 error/skipped/missing 材料，Lint autofix 直接复用为安全闸（D-33），无需重写。
- `analyzer/analysis.mbt` 的 `AnalysisResult`/`Binding`/`AnalysisDiagnostic`：Lint analyzer 增强规则的消费模型（D-06 预留）；`FunctionInfo`/`Catalog` 供有 catalog 的规则。
- `@token.classification_of`（D-28）：fingerprint 关键字大小写折叠的唯一关键字来源，不建第二关键字表。
- `source/source.mbt` `@source.Span`：autofix span edit 与 fingerprint 的字节位置基础。
- `binding/exports.mbt` `json_bytes`/`#export_name` + `binding/schema.mbt` envelope：新增两个 wire 导出的直接模板。
- `parity/` `compare_backends.py` + native/js/wasm 三目标机制：fingerprint 跨目标一致性的现成底座。
- `fathom-sql/run.mbt` D-39 退出码映射：`lint`/`fingerprint` 子命令沿用 0/1/2。

### Established Patterns
- 单向依赖纪律（D-21/D-27）：fingerprint/ 只 import syntax + token（classification）；lint/ import syntax + formatter 安全编辑工具 + 可选 analyzer；parser 永不反向 import。
- 拒绝绝对（D-33）：error/missing/skipped → accepted=false、空输出、单一拒绝码——autofix 严格复用，不做部分编辑。
- SQLFluff 风格规则注册表：稳定码 + 类别 + 默认 severity + fixable 标记。
- 序列化 envelope（fathom.*.v1 + dialect/profile metadata，D-09）：新 lint/fingerprint envelope 仿 parse/format/complete。
- 快照/golden + 跨目标 parity 纪律（Phase 12 D-03/D-08）：规则诊断与指纹用 `_test.mbt` 快照 + parity 测试锁定。
- 无 catalog 时行为字节不变（ANLY-01）：analyzer 增强规则无 catalog 时静默跳过，语法 valid 通道永不改变。

### Integration Points
- `binding/schema.mbt` `validate_schema_version` + `binding/exports.mbt` — 新增 `fathom.lint.v1` / `fathom.fingerprint.v1` 命名空间与 `fathom_lint_v1` / `fathom_fingerprint_v1` 导出（schema v2 bump）
- `api/api.mbt` — 新增 `lint_text` / `fingerprint_text` 共享核心入口（仿 `format_text`）
- `fathom-sql/args.mbt` + `run.mbt` + `main.mbt` — 新增 `lint` / `fingerprint` 子命令（D-39 退出码）
- `parity/` — 新增 fingerprint 跨目标 UInt64 一致性测试（native/js/wasm）
- 新 `lint/`、`fingerprint/` MoonBit 包 — 独立库，`moon.pkg` import 契约明确
- `docs/API.md` — 新增 Lint / Fingerprint 公共 API 文档章节

</code_context>

<specifics>
## Specific Ideas

既有边界意图（延续 Phase 5 决策链与 v3.0 研究，本阶段 `--auto` 无逐条新输入）：
- Phase 5 D-06：analyze/lint 消费同一 `AnalysisResult` 模型；wire/CLI/LSP 面在本阶段（Lint 消费时）兑现
- 研究 ARCHITECTURE Pitfall 2/3：lint/ autofix 走 formatter-safe 路径（D-33）；fingerprint/ 归一化 CST 而非序列化 JSON；binding/ schema v2 bump
- 研究 STACK.md 事实：core 无 hash 包、Hasher=xxHash32、`UInt64` 固定 64-bit 跨目标、`Int` 宽度不一致 → FING-01 必须 UInt64
- SQLFluff 风格规则注册表：稳定码 + bundles + severity 配置（研究 FEATURES 明文）
- 命名中立纪律：规则码 `FATHOM-LINT-0xx`、wire 命名空间 `fathom.lint.v1`/`fathom.fingerprint.v1`，无 `doris-lint` 产品名（D-04/D-09、Phase 9 naming gate）

</specifics>

<deferred>
## Deferred Ideas

- LSP code actions（lint 修复/指纹 LSP 诊断）→ TOOL-FUTURE-01（backlog，catalog-aware 语义智能）
- Lint 规则插件市场/外部规则 → LINT-02
- 配置文件（lint/fingerprint 的 yaml/json 配置）→ 首个真实多用户团队采纳需求出现时再评估
- 指纹语义折叠扩展（标识符 case-fold / 字面量归一化）→ 明确反需求（FING-01 要求保留），永不默认
- 列级血缘 → LINE-01（Phase 7）
- 增量解析 → EDIT-01（Phase 8，benchmark-gated）
- 完整类型推导/执行语义 → ANAL-02（出界）

---

*Phase: 6-Lint and Fingerprint*
*Context gathered: 2026-08-10*
