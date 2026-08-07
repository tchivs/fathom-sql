# Phase 10: Flink Release Profiles and Lexical Core - Context

**Gathered:** 2026-08-07
**Status:** Ready for planning

<domain>
## Phase Boundary

本阶段把 Phase 9 的 Flink 占位面（`FlinkProfile {}` 空枚举、`flink_classification_rows = []`、所有 flink 请求 FATHOM-PARSE-008 拒绝）升级为可审计的 Flink 发布 profile 与独立词法核心：新增 `flink-2.3.0`（主 profile）、`flink-2.1.3`、`flink-1.20.5`（回归 profile），每个 profile 记录其真实 release 来源（tag/commit、校验和）、Calcite 版本与 parser 配置；Flink 输入获得与 Doris 完全独立的注释、引号、字面量、运算符、标识符与关键字分类行为，trivia/span 保留；冲突用例产出可解释快照而非 Doris 策略泄漏。本阶段不实现 Flink grammar（Phase 11）、不实现 Flink 工具链（Phase 13）、不建立全量 Flink corpus/parity（Phase 12）。

**Requirements:** FLINK-01（1 个）

</domain>

<decisions>
## Implementation Decisions

### Flink Profile 模型
- **D-01:** `FlinkProfile` 采用与 `DorisProfile` 同构的闭合枚举 + metadata 模式：`FlinkProfile::V2_3_0 | V2_1_3 | V1_20_5`，配套 `FlinkProfileMetadata`（id=`flink-2.3.0` 等、release_family、exact_release、calcite_version、parser_config、feature_introduction），经 `validate_dialect_profile` 统一校验；未知/不支持 profile 返回结构化错误。不引入 string-keyed 软校验。**Reversibility:** costly — FlinkProfile 类型名与 metadata 字段是代码内公共 API 与 wire metadata 契约，全量泛化需迁移所有调用点。
- **D-02:** 每个 profile 的 Calcite 版本/parser 配置**从钉住的 release 源码归档提取**（下载校验和匹配的 `flink-*-src.tgz`，读取 release POM 的 parser 配置与 Calcite 依赖版本），以可执行脚本/测试固化进 profile metadata；`flink-2.1.3` 的精确 Calcite pin 必须来自该 release 本身，禁止手写推断或 folklore。**Reversibility:** costly — metadata 字段是 wire contract（fathom.capabilities.v1 暴露），换 pin 需 schema 级记录。

### 词法核心
- **D-03:** Flink 词法行为以**可执行 release fixture** 为唯一事实源：从钉住 release 的 grammar（Calcite parser .ftl/.jj 相关文件与 parser 配置）提取注释（`--`、`/* */`，`#` 按 release 实际支持核验）、引号（单引号字符串、双引号/反引号标识符按 Flink 实际配置）、字面量（X/U&/B/E 前缀按 release 核验）、运算符（`||`、`=>`、`:` 等按 token 集）、标识符（大小写敏感性与 unicode 规则）行为，固化为 SQL 输入 + 期望分类快照；禁止以 Calcite folklore 或 Doris 行为推断 Flink。**Reversibility:** reversible — fixture 集可经注册表批准后增补。
- **D-04:** Flink 词法快照作为 **parity/ 内独立 flink-lexical 快照组**加入既有快照门禁（D-08 机制复用：approved-changes.md 注册 + baseline_diff.py diff）；冲突矩阵（comment/quote/literal/identifier/operator/unknown-profile × doris/flink 双方言）产出可解释快照；Doris 既有快照组保持字节级零漂移。**Reversibility:** one-way — D-07 冻结的 Doris baseline 是 Phase 12 PARITY-01 对比基准，任何 Doris 字节变更都需注册批准。

### 错误面与诊断
- **D-05:** 未知/不支持 Flink profile 的拒绝走既有 `FATHOM-SCHEMA-*` profile 错误族（与 Doris unknown profile 同族），dialect 不编码进 code 前缀（D-10 延续）；方言信息经 diagnostics/result 的 metadata 字段暴露。不新增 `FATHOM-FLINK-*` 命名空间。**Reversibility:** one-way — 诊断 code 是稳定公共契约，发布后变更需 schema 迁移。
- **D-06:** 词法冲突行为（如双引号在 Doris 与 Flink 下含义不同）以快照为裁决依据；同一输入在不同方言下允许不同 token 化，但每条路径必须可解释（快照 + 诊断/分类说明），禁止任一方向静默借用对方策略。**Reversibility:** reversible。

### Claude's Discretion
（未出现 "you decide"；所有灰区均已由既有决策链（D-01..D-11 + 本阶段 D-01..D-06）覆盖。）

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 需求与路线图
- `.planning/REQUIREMENTS.md` — v2.0 24 个 requirements；Phase 10 负责 FLINK-01
- `.planning/ROADMAP.md` §Phase 10 — 阶段 Goal/Success Criteria/Validation/Research flags（Calcite pin 提取、双引号/`#`/`//`/X/U&/B 字面量行为核验）
- `.planning/PROJECT.md` — 中立产品定位与 Current Milestone v2.0

### 研究文档（Phase 9 依据，延续到 Phase 10）
- `.planning/research/ARCHITECTURE.md` — dialect 分层、classification_rows 拆分、Calcite pin 与 flink corpus 归属
- `.planning/research/SUMMARY.md` — Phase 9/10 边界与 Flink pin 硬门禁（release 源码 + 校验和，禁 moving docs）
- `.planning/research/STACK.md` — 闭合 enum + match 路由结论
- `.planning/research/FEATURES.md` — 显式 dialect 表 stake 与 anti-feature（自动检测/静默回退）
- `.planning/research/PITFALLS.md` — 全局分类表污染、方言策略泄漏等陷阱

### 前一阶段决策与现状代码（迁移/扩展依据）
- `.planning/phases/09-dialect-boundary-and-neutral-naming/09-CONTEXT.md` — D-01..D-11（显式选择、D-05 FlinkProfile 新增、D-07/D-08 baseline 门禁、D-09/D-10 wire/诊断身份、D-11 CLI）
- `.planning/phases/09-dialect-boundary-and-neutral-naming/09-RESEARCH.md` — 86 行迁移映射表、baseline 冻结流程、命名门禁设计
- `.planning/phases/09-dialect-boundary-and-neutral-naming/09-PATTERNS.md` — dialect/ 层 analog、快照门禁模式
- `dialect/dialect.mbt` — Dialect/DialectContext 现状（dialect/flink.mbt 占位待填充）
- `dialect/doris.mbt` — DorisProfile/ProfileMetadata 模式（FlinkProfile 同构蓝本）
- `dialect/classification.mbt` — classification_of(context, raw) 查询入口
- `api/api.mbt` — ParseOptions::new(dialect_id, profile_id, mode_id) 校验链
- `parity/baseline_test.mbt`、`parity/__snapshot__/`、`scripts/baseline_diff.py`、`approved-changes.md` — 快照门禁机制复用
- `fathom-sql/args.mbt` — CLI --dialect/--profile 解析（flink profile 现全拒，Phase 10 解锁）

### 外部事实源（release 钉住）
- Apache Flink release 源码归档（`flink-2.3.0`/`flink-2.1.3`/`flink-1.20.5` 的 `-src.tgz` + 官方 SHA-512 校验和）— Calcite 版本/parser 配置提取源；URL 与校验和须随 corpus 元数据记录（禁 `dev`/`stable` 移动文档）
- 各 release 的 parser 配置/POM（`flink-table-common` 等模块内 Calcite 依赖与 SqlParser 配置）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `dialect/flink.mbt` 的 `FlinkProfile {}` 占位 + `flink_classification_rows = []` 骨架 — 本阶段直接填充
- `dialect/doris.mbt` 的 `DorisProfile` + `ProfileMetadata` + `ProfileMetadataError` 模式 — `FlinkProfile`/`FlinkProfileMetadata` 同构蓝本
- `dialect/classification.mbt` 的 `classification_of(context : DialectContext, raw : Bytes)` — Flink 行表挂接点
- `parity/baseline_test.mbt` + `@test.T::snapshot` + `scripts/baseline_diff.py` + `approved-changes.md` — flink-lexical 快照组复用
- `api/api.mbt` 的 `validate_dialect_profile` 校验链 — flink profile 解锁点（现 A1 全拒）
- corpus 工具（`corpus/tools/check_keywords.py` 模式）— fixture 校验脚本蓝本

### Established Patterns
- 闭合枚举 + metadata 校验 + 结构化错误（CORE-01 传统，D-01 延续）
- 快照/golden 纪律 + 注册表批准制（D-08）— flink-lexical 快照同制
- 方言策略完全隔离（DIALECT-02/03 禁止 union/泄漏）— 词法冲突矩阵快照化
- release 来源可审计（D-02：校验和 + POM 提取）— 禁 folklore

### Integration Points
- `dialect/flink.mbt` — FlinkProfile 枚举 + metadata + classification rows 填充
- `api/api.mbt` `validate_dialect_profile` — flink profile 从全拒改为按枚举校验
- `parity/` — 新增 flink-lexical 快照组与冲突矩阵
- `binding/schema.mbt` — fathom.capabilities.v1 profile 元数据暴露（calcite_version/parser_config 字段）
- `fathom-sql/args.mbt` — `--dialect flink --profile flink-2.3.0` 接受路径（现 exit 2 全拒）

</code_context>

<specifics>
## Specific Ideas

用户明确的命名/边界意图（来自 Phase 9 讨论链，延续）：
- Flink 是合法 dialect 值，profile 语义为 `flink-<version>`（与 Doris 的 `2.1`/`3.x`/`4.x` 完全不同形态，不得互相借用）
- `flink-2.3.0` 主 profile；`flink-2.1.3`/`flink-1.20.5` 回归 profile；不支持者显式拒绝
- Calcite pin 必须来自 release 本身（SC2 明文：2.1.3 的精确 pin 从该 release 提取，而非推断）
- 词法行为以可执行 release fixture 核验（Research flags 明文：双引号、`#`、`//`、X/U&/B 字面量行为用 fixture 而非 Calcite folklore）
- 不使用移动的 `dev`/`stable` 文档；不引入 Flink/Calcite 运行时

</specifics>

<deferred>
## Deferred Ideas

- Flink grammar（SELECT/CTE/JOIN/聚合等语句级解析）→ Phase 11（FLINK-02..05）
- Flink 工具链（formatter/analyzer/completion/LSP/CLI 方言分发）→ Phase 13（TOOL-01..05）
- 全量 Flink corpus 提取与跨后端 parity → Phase 12（CORPUS-01、PARITY-01/02）
- 自动方言检测（即使 opt-in）→ 未来阶段，不在 v2.0 默认范围
- 显式跨方言转换（transpile）→ CONVERT-FUTURE-01

</deferred>

---

*Phase: 10-Flink Release Profiles and Lexical Core*
*Context gathered: 2026-08-07*
