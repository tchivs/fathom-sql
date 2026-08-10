# Phase 13: Toolchain and Editor Packaging - Context

**Gathered:** 2026-08-10
**Status:** Ready for planning

<domain>
## Phase Boundary

本阶段把 Phase 11/12 已就绪的 Flink 语法与 CST 贯通到全部中立工具链与编辑器宿主：Flink formatter（TOOL-01）、Flink 有界补全（TOOL-02）、Flink 语法级 analyzer + 可选 catalog（TOOL-03）、`fathom-sql parse|format|lsp --dialect flink` + `fathom-lsp` 端到端（TOOL-04），以及 JS/linear-Wasm、Web/Monaco、VS Code、IntelliJ 的同源 dialect-aware API/schema 与 per-file/per-session 选择（TOOL-05）。不新增 Flink grammar/词法能力（Phase 10/11 已完成）、不建立 corpus/parity 门禁（Phase 12 已完成）、不做 planner/执行等价或完整 ANAL-01 语义解析（v2 范围）。

**Requirements:** TOOL-01, TOOL-02, TOOL-03, TOOL-04, TOOL-05（5 个）

</domain>

<decisions>
## Implementation Decisions

### Flink Formatter（TOOL-01）
- **D-01:** Flink formatter 覆盖 **Phase 11 解析器可产出的全部 Flink 语句族**（SELECT/INSERT/UPDATE/DELETE/EXPLAIN/SHOW/DESCRIBE/ANALYZE、CREATE TABLE/VIEW/CATALOG/DATABASE/FUNCTION、Window TVF、MATCH_RECOGNIZE）。layout 表（`clause_breaks`/`statement_family`/`layout_statement`）必须覆盖每个 Flink 族；未覆盖族视为编程缺口 → 按不安全处理，沿用 refusal-first：`accepted=false`、空输出、恰好一条 `FATHOM-FORMAT-001`（D-33），绝无部分输出。refusal-first、idempotence（`format(format(x)) == format(x)`）、`statement_offsets`、keyword case 改写（D-28 单表纪律）全部延续；Doris 输出零漂移（先跑冻结 baseline，无 `--update`）。**Reversibility:** costly — formatter 输出是公共契约，已发布族的布局改动需兼容性维护。
- **D-02:** Flink 补全候选**复用 `dialect/flink.mbt` 分类表作为唯一候选池**（延续 D-28 "no second keyword list" 纪律，不建补全专用表）；per-profile gating 用 `introduced_profile` 按 `flink-1.20.5 < flink-2.1.3 < flink-2.3.0` 引入顺序镜像 Doris `profile_allows`。`completion_context` 扩展 Flink 上下文：statement-start、DDL 头（CREATE/DROP/ALTER…）、WATERMARK、PARTITIONED BY、Window TVF 函数名（TUMBLE/HOP/CUMULATE/SESSION）、MATCH_RECOGNIZE（PATTERN/DEFINE/MEASURES/…）。保持有界（`MAX_CANDIDATES=32`）、纯语法、`CompletionItem` source-range edit（start_byte/end_byte/new_text）不变；无 catalog。**Reversibility:** reversible。

### Flink Analyzer（TOOL-03）
- **D-03:** 扩展既有 `resolve_table_references` 走查至 Flink 语句族（Insert/Update/Delete/CreateTable/CreateView 的 Flink leading-prefix 形态），保持 D-21 只读 syntax-view 纪律（analyzer 不 import parser/token/lexer/api/source；parser 永不 import analyzer；负门禁维持）与可选 catalog（无 catalog → 空结果、parser validity 字节不变，ANLY-01）。表级解析与 Doris 当前最小范围对齐（D-22/D-24）；column/identifier 级引用解析与类型诊断按 D-24 顺延 v2 — TOOL-03 的 "column, and identifier references" 以"受支持引用 = 目标表引用"为边界并在文档标注。**Reversibility:** one-way — `resolve_table_references` 是公共 API，扩展会改变返回集合语义，发布后需迁移。

### 补全 Wire 契约（TOOL-05 / binding）
- **D-04:** 新增 `fathom_complete_v1(raw, dialect, profile, cursor_byte)` 导出 + `fathom.complete.v1` 信封，镜像 `fathom_parse_v1`/`fathom_format_v1`（dialect 紧跟 raw，A4；返回 UTF-8 JSON Bytes）。这是 NAME-02 锁定的四个命名空间（parse/format/error/capabilities）之外的**新增稳定 wire 契约**，须在 schema、文档、命名门禁（check_naming.py 中立性）显式登记。Web/Monaco 与 JS/linear-Wasm 宿主由此获得与 LSP 相同的补全面。**Reversibility:** one-way — wire schema 发布后变更需 schema 迁移。

### 宿主 Per-Dialect Profile 校验（TOOL-05）
- **D-05:** Web/VS Code/IntelliJ 三宿主保持静态常量模式，将扁平 profile 列表改为 **(dialect, profile) 二元组校验**：doris → `2.1/3.x/4.x`；flink → `flink-2.3.0/flink-2.1.3/flink-1.20.5`。profile 下拉/校验随所选 dialect 切换（选 flink 才出现 flink 值）。服务端（`binding.validate_dialect_profile` / LSP `validate_selection`）仍权威校验（纵深防御，宿主侧失败也显式报错而非回退）。不动态拉取、不共享跨宿主 JSON 定义（避免宿主耦合与网络依赖，离线优先）。**Reversibility:** reversible。

### 每文件 vs 每会话方言选择（TOOL-04/05）
- **D-06:** 保持已锁定选择模型（D-01/D-02/D-03）：workspace/session 默认（LSP initializationOptions / CLI `--dialect` `--profile` / VS Code `fathom.dialect` / IntelliJ FathomSettings）+ 每文件 LSP `didOpen`/`didChange` dialect/profile 扩展字段覆盖（已实现）。本阶段只让 flink 值通过各宿主校验并让 per-file 覆盖在 flink 文件上生效；不引入自动检测、不加按扩展名猜测（D-01 禁）。**Reversibility:** one-way — 选择传输契约（didOpen extension fields / initializationOptions）是 LSP 公共契约。

### LSP/CLI 集成面（TOOL-04）
- **D-07:** LSP 的 flink format 从 `-32603 not-implemented` 换成真实 `@api.format_with_ids` 路径；flink completion 从 `-32602` 拒绝换成真实 `@completion.complete` 结果（`CompletionItem` → LSP `textEdit` UTF-16 range + `newText`，复用 `completion_item_json` 与 `binding` coordinates）。CLI `fathom-sql format --dialect flink` 走 `@api.format_with_ids`，退出码沿用 D-39（0 accepted / 1 refusal / 2 usage）；UTF-16 转换沿用 `binding.coordinates`。Doris 既有 LSP/CLI 行为零漂移。**Reversibility:** costly — LSP 行为契约（错误 vs 空数组 vs 真实结果）是宿主依赖面。

### 宿主打包 Smoke 深度（research flags）
- **D-08:** 复用既有 harness：VS Code 真 extension-host 验证（`vscode/scripts/host-verify.mjs`，Phase 4 ECO-07 模式）；IntelliJ Gradle 构建 + LSP 启动 smoke（`gradlew` + 配置 flink 后启动 `fathom-lsp`）；Web Chromium smoke（Phase 4 ECO-06 模式：monaco-adapter 单测 + 浏览器断言）。每个宿主验收：打开 flink 文件 → 选择 flink dialect/profile → 收到诊断（支持处验证 format/completion）。CI 增加三宿主最终打包 smoke job；全程离线（无网络/FE/cluster/DB，PARITY-03 纪律）。**Reversibility:** reversible。

### Claude's Discretion
（`--auto` 模式：所有灰区由 Claude 依据既有决策链选择推荐项，无用户自由输入；D-01..D-08 覆盖全部灰区，无 "you decide"。）

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 需求与路线图
- `.planning/REQUIREMENTS.md` — v2.0 需求；Phase 13 负责 TOOL-01..05
- `.planning/ROADMAP.md` §Phase 13 — Goal/Success Criteria/Validation/Research flags（refusal/idempotence fixtures、bounded completion contexts、analyzer catalog/no-catalog、Native CLI/LSP 协议流、JS/linear-Wasm facade、三宿主 artifact smoke、命名门禁）
- `.planning/PROJECT.md` — Current Milestone v2.0 与中立产品定位

### 前序阶段决策与研究（延续依据）
- `.planning/phases/09-dialect-boundary-and-neutral-naming/09-CONTEXT.md` — D-01..D-11（显式选择、wire 契约 NAME-02、baseline 门禁 D-07/D-08、诊断身份 D-10、CLI D-11、LSP D-01..D-03）
- `.planning/phases/09-dialect-boundary-and-neutral-naming/09-RESEARCH.md` — 迁移映射、baseline 冻结流程、命名门禁设计
- `.planning/phases/10-flink-release-profiles-and-lexical-core/10-CONTEXT.md` — D-01..D-06（FlinkProfile、Calcite pin、词法核心）
- `.planning/phases/11-flink-grammar-and-recoverable-cst/11-CONTEXT.md` — D-01..D-07（Flink 语句族 CST 节点、双向负门禁、工具链顺延 Phase 13 的既定承诺）
- `.planning/phases/12-cross-dialect-corpus-and-parity-gates/12-CONTEXT.md` — CORPUS-01/PARITY-01..03（Doris 零漂移门禁、跨后端字节一致、离线纪律）
- `.planning/research/ARCHITECTURE.md`、`STACK.md`、`FEATURES.md`、`PITFALLS.md` — 分层、陷阱与显式选择 stake
- 各阶段 `approved-changes.md` 注册表、`parity/__snapshot__/` 快照组（doris baseline 213、flink-lexical 26、flink-grammar ~90+）

### 现状代码（扩展依据）
- `formatter/` — format.mbt（refusal-first D-33）、layout.mbt（clause_breaks/statement_family 现仅 Doris 族）、options.mbt、case.mbt、refuse.mbt
- `completion/completion.mbt` — `complete()` 现对 flink 全拒（UnknownProfile）；`profile_allows` Flink=false；`completion_context` 仅 Doris 上下文
- `analyzer/analyzer.mbt` — `resolve_table_references` 仅 Doris 语句族（D-21/D-22/D-24 纪律）
- `api/api.mbt` — `format_text`/`format_with_ids`（flink context 现直接进 Doris layout，无 guard）、`parse_flink`、`FormatOptions`
- `lsp/handlers.mbt` — flink format=`-32603 not-implemented`；flink completion=`-32602` 拒绝；`completion_item_json`/`diagnostic_range` UTF-16；document-level dialect 传输（didOpen/didChange extension fields）
- `fathom-sql/run.mbt`、`args.mbt` — CLI format 现对 flink 无 guard；`--dialect flink` 已接受 pinned profiles（D-11/Phase 10）
- `binding/exports.mbt` — `fathom_parse_v1`/`fathom_format_v1`（format 对 flink 现 FATHOM-SCHEMA-003 拒绝）、`fathom_dialect_v1`/`fathom_capabilities_v1`
- `binding/schema.mbt` — `validate_dialect_profile`、wire envelope（NAME-02 四命名空间）
- `web/src/monaco-adapter.ts` — `DIALECTS` 含 flink 但 `PROFILES` 仅 Doris（`['2.1','3.x','4.x']`）
- `vscode/src/extension-contract.ts`、`extension.ts` — `SUPPORTED_PROFILES` 仅 Doris
- `jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomSettings.kt` — `ALLOWED_PROFILES` 仅 Doris
- `dialect/flink.mbt` — FlinkProfile/FlinkProfileMetadata/142 行分类表（补全候选池与 per-profile gating 来源）
- `syntax/syntax.mbt` — Flink 语句族 SyntaxKind（CreateCatalog/DropDatabase/AlterTable/WatermarkClause/WindowTvf/MatchRecognize 等）
- `parity/`、`scripts/check_naming.py`、`.github/workflows/ci.yml` — 门禁、命名 inventory、CI 接线点

### 外部事实源（研究期钉住）
- Apache Flink release 归档与 Calcite pin（Phase 10 已验证；URL/校验和入 manifest）— 补全/格式化事实源延续
- `/tmp/flink-research/` — 三个 release 源码归档（Phase 10/11 已下载验证）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `formatter/` 的 `find_first_unsafe` + `FATHOM-FORMAT-001` refusal-first（D-33）：Flink 不安全树拒绝直接复用
- `completion/` 的 `CompletionItem`/`CompletionList`/`MAX_CANDIDATES=32`/两遍优先级排序：Flink 补全骨架
- `dialect/flink.mbt` 142 行分类表 + `introduced_profile`：Flink 补全候选池与 per-profile gating
- `binding/coordinates.mbt`（`position_to_byte`/`byte_to_position` UTF-16）：LSP completion textEdit range 与 UTF-16 契约
- `binding/exports.mbt` ABI 模式（`fathom_*_v1` primitive Bytes、dialect 紧跟 raw，A4）：`fathom_complete_v1` 蓝本
- `vscode/scripts/host-verify.mjs` + Phase 4 ECO-07 harness：VS Code 真 extension-host 验证
- `jetbrains/` gradlew 构建 + `FathomSettings.kt`（ALLOWED_DIALECTS/PROFILES）：IntelliJ 校验点
- `parity/baseline_test.mbt` + `scripts/baseline_diff.py` + `approved-changes.md`：Doris 零漂移门禁（D-08 机制）

### Established Patterns
- 闭合枚举 + metadata 校验 + 结构化错误（CORE-01 传统）
- refusal-first 契约（D-33）+ 无部分输出 + idempotence 测试
- 快照/golden 纪律 + 注册批准制（D-08）
- 显式 (dialect, profile) 选择，无默认/自动检测（D-01/D-02）
- 单一关键字表纪律（D-28）— 补全不建第二表
- 离线门禁（PARITY-03）：无网络/FE/cluster/DB 运行时访问
- 方言不进诊断 code 前缀（D-10）；wire 命名中立（NAME-02）

### Integration Points
- `formatter/layout.mbt` — 新增 Flink 族 `clause_breaks`/`statement_family`/`layout_statement` 分支（D-01）
- `completion/completion.mbt` — `profile_allows` Flink 分支 + Flink `completion_context`（D-02）
- `analyzer/analyzer.mbt` — Flink `leading_prefix_end` + 语句族（D-03）
- `lsp/handlers.mbt` — flink format/completion 从拒绝换真实路径（D-07）
- `fathom-sql/run.mbt` — format 对 flink 走真实路径（现无 guard）
- `binding/exports.mbt` + `binding/schema.mbt` — `fathom_complete_v1` + `fathom.complete.v1` 信封（D-04）
- `web/`、`vscode/`、`jetbrains/` — (dialect, profile) 二元组校验 + flink profile 值（D-05）
- `.github/workflows/ci.yml` — 三宿主打包 smoke + 补全/格式化 parity 快照接线（D-08）

</code_context>

<specifics>
## Specific Ideas

用户明确的边界意图（延续 Phase 9/10/11 讨论链，本阶段 `--auto` 无逐条新输入）：
- Flink 工具链顺延 Phase 13 是既定承诺（Phase 10/11 deferred 明文），本阶段兑现
- 显式 (dialect, profile) 选择、无自动检测/静默回退（D-01/D-02）
- refusal-first：Flink 不安全树格式化无部分输出（TOOL-01 SC1 明文）
- 有界补全：关键字、DDL、WATERMARK、Window TVF、MATCH_RECOGNIZE 上下文（TOOL-02 SC2 明文）
- 语法级 analyzer：parser validity 与 catalog 无关（TOOL-03 SC2 明文）
- 离线门禁：宿主 smoke 无网络/FE/cluster/DB（PARITY-03 / Validation 明文）
- 命名中立门禁继续适用：新 wire 契约 `fathom.complete.v1` 亦须过 check_naming.py 中立性

</specifics>

<deferred>
## Deferred Ideas

- 完整 ANAL-01 name resolution（column/identifier 级引用解析）与类型诊断 → v2（D-24 既定；TOOL-03 仅目标表引用）
- catalog 感知补全（表/列名补全、hover、语义 tokens）→ TOOL-FUTURE-01
- 自动方言检测（即使 opt-in）→ 未来阶段
- 显式跨方言转换（transpile）→ CONVERT-FUTURE-01
- Wasm GC 作为一等兼容承诺 → TARGET-FUTURE-01
- 动态 profile 拉取（宿主运行时从 capabilities 获取）→ 本阶段选静态二元组（D-05）；如需多方言扩张再评估

---

*Phase: 13-Toolchain and Editor Packaging*
*Context gathered: 2026-08-10*
