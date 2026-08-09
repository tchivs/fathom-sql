# Phase 11: Flink Grammar and Recoverable CST - Context

**Gathered:** 2026-08-07
**Status:** Ready for planning

<domain>
## Phase Boundary

本阶段把 Phase 10 的 Flink 词法核心（已解锁 profile + 独立词法/关键字分类）扩展为真实 Flink 语句级 grammar，产出无损、有界、可恢复的 CST：覆盖 FLINK-02（核心查询/日常语句）、FLINK-03（Catalog 与 DDL 入口）、FLINK-04（CREATE TABLE 复杂形式）、FLINK-05（Window TVF）、FLINK-06（MATCH_RECOGNIZE 语法级）、CST-01（严格/编辑器双模式 recoverable lossless CST）；同时保持 Doris 接受行为与诊断零漂移，并实现双向方言负门禁（Flink-only 语法在 Doris 模式拒绝、Doris-only 语法在 Flink 模式拒绝）。本阶段不实现 Flink 工具链（format/completion/analyzer → Phase 13 TOOL-01..03）、不建立全量 Flink corpus/parity（Phase 12）、不做 planner 或执行等价声明。

**Requirements:** FLINK-02, FLINK-03, FLINK-04, FLINK-05, FLINK-06, CST-01（6 个）

</domain>

<decisions>
## Implementation Decisions

### Grammar 作用域与子集
- **D-01:** Flink grammar 覆盖 FLINK-02..06 全部枚举范围：核心查询（SELECT/CTE/JOIN/聚合/集合运算/表达式/类型）、INSERT/UPDATE/DELETE、EXPLAIN/SHOW/DESCRIBE/ANALYZE、Catalog/DATABASE/TABLE/VIEW/FUNCTION DDL、CREATE TABLE 物理/元数据/计算列/WATERMARK/PRIMARY KEY NOT ENFORCED/PARTITIONED BY/分布/WITH 选项/LIKE/AS、Window TVF（TUMBLE/HOP/CUMULATE/SESSION 的 TABLE/DESCRIPTOR/区间字面量/命名参数/窗口输出列）、MATCH_RECOGNIZE（PATTERN/DEFINE/MEASURES/skip policy/模式变量/量词）。Window TVF 与 MATCH_RECOGNIZE 的 supported/known-limitation 子集由研究阶段从钉住 release 的 flink-sql-parser grammar + 对应 Calcite 测试定义并冻结（research flags 明文），语法级即可、不声称 planner/执行等价。**Reversibility:** costly — CST 形状是公共契约，后续扩展需保持兼容。

### CST 与恢复
- **D-02:** Flink 复用 Doris 同一无损 CST 节点体系（source-backed Statement/Clause/Expr + error/missing/skipped 节点 + span/trivia 保留），不建独立 AST；新增 Flink 特有语句族节点（CREATE TABLE 物理/元数据/计算列、WATERMARK、Window TVF 输出列、MATCH_RECOGNIZE 块）。打印 lossless 树字节级复原输入（CST-01）。**Reversibility:** one-way — CST 形状是核心产品契约，无损 round-trip 依赖它。
- **D-03:** 恢复纪律与 Doris 一致：语句级 panic-mode + 子句级尽力恢复，strict/editor 双模式；错误/missing/skipped 节点有界（边界明确、来源字节可回溯），编辑模式对半成品输入持续产出可解析子树，不无限推进。**Reversibility:** reversible。

### 方言路由与负门禁
- **D-04:** 保持单一 `parse_segment` 路由（parser.mbt:3336），Flink 分支从 FATHOM-PARSE-008 换成真实 grammar；实现**双向方言负门禁**：Flink-only 语法在 Doris 模式拒绝、Doris-only 语法在 Flink 模式拒绝，各自稳定诊断码（FATHOM-PARSE-NNN，dialect 不进 code 前缀，D-10 延续）；诊断经 metadata 携带方言信息。**Reversibility:** one-way — 诊断码是稳定公共契约。
- **D-05:** Flink grammar 事实源 = 钉住 release 的 flink-sql-parser grammar（Parser.tdd/Parser.jj + Calcite 测试），延续 Phase 10 的 release 提取纪律（禁 folklore/移动文档）；fixture 分 positive/negative/incomplete/recovery 四类，冻结为 parity/flink-grammar 快照；任何共享 parser/CST 改动前先重跑冻结 Doris baseline（213 快照，无 --update）。**Reversibility:** reversible — fixture/快照可经注册批准制更新。

### 语句覆盖与交付顺序
- **D-06:** `parse_flink_segment` 的 FATHOM-PARSE-008 not-implemented 路径退役（Phase 10 已声明 Phase 11 落地 grammar，属预期行为变更）；FATHOM-PARSE-008 不再用于合法 flink SQL。**Reversibility:** costly — 行为变更影响依赖旧拒绝行为的消费者，但符合既定路线图。
- **D-07:** 按 vertical slice 顺序交付（每片含 recoverable CST + strict/editor 双模式 + 快照）：FLINK-02 核心查询 → FLINK-03 Catalog/DDL → FLINK-04 CREATE TABLE 复杂形式 → FLINK-05 Window TVF → FLINK-06 MATCH_RECOGNIZE。**Reversibility:** reversible。

### Claude's Discretion
（未出现 "you decide"；所有灰区由既有决策链 + 本阶段 D-01..D-07 明确覆盖。）

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 需求与路线图
- `.planning/REQUIREMENTS.md` — v2.0 需求；Phase 11 负责 FLINK-02..06、CST-01
- `.planning/ROADMAP.md` §Phase 11 — Goal/Success Criteria/Validation/Research flags（Window TVF/MATCH_RECOGNIZE 子集、双向负门禁、lossless replay）
- `.planning/PROJECT.md` — 中立产品定位与 Current Milestone v2.0

### 前一阶段决策与研究（延续依据）
- `.planning/phases/10-flink-release-profiles-and-lexical-core/10-CONTEXT.md` — D-01..D-06（FlinkProfile、Calcite pin、词法 fixture、profile-aware 分类、FATHOM-SCHEMA 家族）
- `.planning/phases/10-flink-release-profiles-and-lexical-core/10-RESEARCH.md` — Flink release grammar（Parser.tdd/Parser.jj 行号引用）、词法矩阵、关键字清单（flink-2.3.0/2.1.3/1.20.5）
- `.planning/phases/09-dialect-boundary-and-neutral-naming/09-CONTEXT.md` — D-01..D-11（dialect 路由、baseline 门禁 D-07/D-08、诊断身份 D-10）
- `.planning/research/ARCHITECTURE.md`、`STACK.md`、`FEATURES.md`、`PITFALLS.md` — 分层与陷阱

### 现状代码（扩展依据）
- `parser/parser.mbt` §3327-3547 — parse_segment 语句分发（Flink 分支现为 FATHOM-PARSE-008，本阶段替换）；CST 语句族节点
- `dialect/` — Dialect/DialectContext/FlinkProfile/profile-aware classification（Phase 10 完成）
- `lexer/lexer.mbt`、`token/token.mbt` — Flink 词法分支（注释/引号/字面量/运算符）
- `parity/` — flink-lexical 快照组 + baseline 门禁 + approved-changes.md 注册表
- `corpus/` — manifest.tsv + tools/check_keywords.py（fixture 工具模式）

### 外部事实源（研究期钉住）
- `/tmp/flink-research/` — 三个 release 源码归档 + 校验和 + 提取的 Parser.jj/Parser.tdd（Phase 10 已下载并验证）；研究阶段复用于 grammar 提取
- 各 release 的 flink-sql-parser codegen templates + 对应 Calcite 测试（`ParserTest`/`SqlParserTest`）— 支持/限制子集定义与 fixture 来源

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `parser/parser.mbt` 的 `parse_segment` 单一路由 + `finish_statement` trailing 消费骨架 — Flink 分支挂接真实 grammar
- Doris 的语句/子句/表达式 Pratt 解析器与 CST 节点（error/missing/skipped + span/trivia）— Flink 复用同一节点体系
- Phase 10 的 Flink 词法分支（注释/引号/字面量/运算符/关键字）— grammar 消费的 token 层已就绪
- profile-aware 分类（classification_of）— 关键字保留/非保留判定
- parity/ 快照门禁 + approved-changes.md 注册 + baseline_diff.py — flink-grammar 快照复用

### Established Patterns
- 无损 CST + lossless replay 纪律（round-trip 字节级）
- 语句级 panic + 子句级尽力恢复 + editor/strict 双模式
- 快照/golden 测试 + 注册批准制（D-08）
- release 钉住 + 可审计来源（Phase 10 D-02）
- dialect 不进诊断 code 前缀（D-10）

### Integration Points
- `parser/parser.mbt` `parse_flink_segment` — FATHOM-PARSE-008 → 真实 grammar（D-06）
- 共享 CST 类型定义 — 新增 Flink 语句族节点（CREATE TABLE/WATERMARK/Window TVF/MATCH_RECOGNIZE）
- `parity/` — flink-grammar 快照组 + 双向负门禁 fixture
- `api/api.mbt` — 无新参数（dialect/profile 已透传）；诊断码复用 FATHOM-PARSE-*
- `binding/schema.mbt` — fathom.parse.v1 输出自动携带新语句族（无需 schema 变更，除非新错误形态）

</code_context>

<specifics>
## Specific Ideas

用户明确的边界意图（来自 Phase 9/10 讨论链延续）：
- Flink-only 语法在 Doris 模式拒绝、Doris-only 在 Flink 模式拒绝（双向负门禁，SC4 明文）
- 无损 CST：注释/空白/换行/未知/错误/缺失/跳过材料/源码字节/span 全部 round-trip（CST-01）
- MATCH_RECOGNIZE 仅语法级 CST + 诊断，不声称 planner/执行等价（FLINK-06 明文）
- 任何共享 parser/CST 改动前重跑冻结 Doris baseline（Validation 明文）
- Window TVF/MATCH_RECOGNIZE 的 supported/known-limitation 子集由研究定义并冻结

</specifics>

<deferred>
## Deferred Ideas

- Flink 工具链（format/completion/analyzer 方言分发）→ Phase 13（TOOL-01..03）
- 全量 Flink corpus 提取与跨后端 parity → Phase 12（CORPUS-01、PARITY-01/02）
- planner/执行等价、catalog 依赖的语义解析 → 不在 v2.0 SDK 范围（FLINK-06 明确不声称）
- 自动方言检测（即使 opt-in）→ 未来阶段
- 显式跨方言转换（transpile）→ CONVERT-FUTURE-01

</deferred>

---

*Phase: 11-Flink Grammar and Recoverable CST*
*Context gathered: 2026-08-07*
