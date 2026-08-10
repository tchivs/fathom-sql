# Phase 9: Dialect Boundary and Neutral Naming - Context

**Gathered:** 2026-08-06
**Status:** Ready for planning

<domain>
## Phase Boundary

本阶段把单方言 Doris 解析器升级为显式多方言架构：新增 `dialect/` 层（`Dialect`、`DialectContext`、per-dialect 关键字分类），让 API、CLI、LSP、JS/Wasm、Web、VS Code、IntelliJ 都能显式选择 `doris`/`flink` 及 profile；完成产品层 clean cutover 命名中立化（`fathom/sql`、`fathom-sql`、`fathom-lsp`、`fathom.*.v1`、`FATHOM-*`）；并冻结 Doris v1 baseline 作为字节级 parity 门禁。本阶段不实现 Flink grammar（Phase 11）、不实现 Flink 工具链（Phase 13）。

**Requirements:** DIALECT-01..04, NAME-01..04（8 个）

</domain>

<decisions>
## Implementation Decisions

### Dialect 选择优先级
- **D-01:** 方言选择优先级为 **文档级显式配置 > workspace/session 显式默认 > languageId 显式映射**；来自同一优先级来源的冲突选择直接报结构化配置错误，绝不静默猜测、绝不自动检测。**Reversibility:** one-way — 这是 DIALECT-01 公共契约的一部分，发布后变更需 schema 迁移。
- **D-02:** 文档与 workspace 都没有显式选择时，返回配置错误；不允许隐式 languageId 兜底。languageId 只有在用户显式配置了映射时才参与解析。**Reversibility:** costly — 影响所有宿主首次打开 `.sql` 文件的默认行为。
- **D-03:** 切换文档 dialect/profile 后立即按新 context 重解析当前 revision，刷新 diagnostics/format/completion，并丢弃旧 context 的异步结果（document revision/stale-response 防护）。**Reversibility:** reversible。

### 命名清理边界
- **D-04:** 命名 gate 豁免历史归档：`milestones/v1.0-*`、`milestones/v1.0-research/`、已归档的 ROADMAP/REQUIREMENTS 历史段保持原样（记录历史事实），gate 只覆盖现行源码、配置、CI、扩展和文档。**Reversibility:** reversible。
- **D-05:** 保留方言类型名：`DorisProfile`、`DorisFeature`、`ValidatedProfileContext` 等 Doris 方言自身类型名原样保留；新增 `Dialect`、`DialectContext`、`FlinkProfile`。产品层只改包名、export、schema、错误码、二进制、LSP server identity、扩展和文档标题。**Reversibility:** costly — 类型名是代码内公共 API，全量泛化需迁移所有调用点。
- **D-06:** 产品层 clean cutover：`fathom/doris-sql` → `fathom/sql`（模块/import）、`doris-sql` → `fathom-sql`（CLI）、`doris-lsp` → `fathom-lsp`、`doris_parse_v1` → `fathom_parse_v1` 等 export、`doris.*.v1` → `fathom.*.v1`、`DORIS-*` → `FATHOM-*`、LSP `serverInfo`/`source`、VS Code/IntelliJ/Web 配置键与包名、文档标题。不保留旧名 alias。**Reversibility:** one-way — 无向后兼容别名是明确产品决策。

### Doris Baseline
- **D-07:** baseline 全量冻结完整 public 行为：CST 形状/span、diagnostics code/span/statement_id、strict/editor 双模式、formatter 输出、completion、CLI exit code、LSP 协议输出、wire schema 输出，全部字节级/形状级比较。**Reversibility:** one-way — 冻结的 baseline 是后续 Phase 12 PARITY-01 的对比基准。
- **D-08:** baseline 采用**快照 diff 门禁**：利用现有 corpus + 快照机制建立 baseline 快照目录（CST/diagnostics/formatter/completion/CLI/LSP 输出），Phase 9 每步改造后跑 diff；字节级一致或经批准并记录的变更才通过。**Reversibility:** reversible。

### Schema 与诊断身份
- **D-09:** wire schema 统一中立 `fathom.parse.v1`/`fathom.format.v1`/`fathom.error.v1`/`fathom.capabilities.v1`；dialect、profile、exact release 作为 result/diagnostic 的 metadata 字段。**Reversibility:** one-way — 这是公共 wire contract，发布后变更需 schema 迁移。
- **D-10:** 诊断 code 统一 `FATHOM-PARSE-NNN`/`FATHOM-FORMAT-NNN`/`FATHOM-SCHEMA-NNN` 等，dialect 不编码进 code 前缀；方言信息通过 diagnostics 的 metadata 字段暴露。**Reversibility:** one-way — 诊断 code 是稳定公共契约。

### CLI 参数
- **D-11:** CLI 采用 `fathom-sql parse|format|lsp --dialect doris|flink --profile <id>`，dialect 与 profile 分开且必选；缺失或未知值返回 exit 2 和结构化错误，无默认方言。**Reversibility:** costly — CLI 参数是脚本化接口，改变形态需更新所有调用脚本和文档。

### Claude's Discretion
（未出现 "you decide"；所有灰区均由用户明确选择。）

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 需求与路线图
- `.planning/REQUIREMENTS.md` — v2.0 24 个 requirements；Phase 9 负责 DIALECT-01..04、NAME-01..04
- `.planning/ROADMAP.md` §Phase 9 — 阶段 Goal/Success Criteria/Validation/Research flags
- `.planning/PROJECT.md` — 中立产品定位与 Current Milestone v2.0

### 研究文档（Phase 9 依据）
- `.planning/research/ARCHITECTURE.md` — Dialect 分层、classification_rows 拆分、parse_segment 路由、命名迁移映射表、组件结构建议
- `.planning/research/SUMMARY.md` — Phase 9 边界/命名/Doris baseline 的硬门禁与依赖顺序
- `.planning/research/STACK.md` — 闭合 enum + match 路由结论、命名 clean cutover 约定
- `.planning/research/FEATURES.md` — 显式 dialect table stake 与 anti-feature（自动检测/静默回退）
- `.planning/research/PITFALLS.md` — 全局分类表污染、命名半迁移、Doris 回归等 Phase 9 陷阱

### 现状代码（迁移依据）
- `token/token.mbt` — DorisProfile/DorisFeature/classification_rows 现状（需拆分为 dialect policy）
- `lexer/lexer.mbt` — profile 透传到 token 的现状
- `parser/parser.mbt` §3327-3547 — parse_segment 按 verb 分发（需加 dialect 路由）
- `api/api.mbt` — ParseOptions/ParseError 现状（需加 dialect 参数）
- `binding/schema.mbt`、`binding/exports.mbt` — doris.*.v1 schema 与 doris_*_v1 export 现状
- `lsp/handlers.mbt` — ServerState.profile 全局状态（需改 document-level context）
- `doris-sql/args.mbt` — CLI --profile 现状
- `vscode/package.json`、`web/package.json`、`jetbrains/build.gradle.kts` — 扩展/包名现状

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `token/token.mbt` 的 `classification_rows` 数组结构与 ASCII case-insensitive lookup 算法可拆为 `doris_classification_rows`/`flink_classification_rows` 的公共 `KeywordEntry` 结构
- `ValidatedProfileContext` 的 profile+metadata 校验模式（ProfileMetadataError）可泛化为 `DialectContext` 校验
- `parse_segment` 的语句分发 + `finish_statement` trailing 消费是共享骨架，可加 `match context.dialect` 路由
- formatter 的 refusal-first 契约与 binding 的 primitive JSON boundary 均方言无关，直接复用

### Established Patterns
- 显式 profile 校验、未知值返回结构化错误（CORE-01 传统）——延续到 dialect
- D-14/D-15：关键字分类层与 feature gate 层分离——方言化后保持两层独立
- 快照/golden 测试纪律——baseline 快照沿用

### Integration Points
- `api.ParseOptions::new(profile_id, mode_id)` → 加 dialect 维度（`ParseOptions::new(dialect_id, profile_id, mode_id)` 或新构造器）
- `lsp.ServerState.profile` → 拆为 workspace 默认 + per-document `DialectContext`
- `binding.validate_profile` → `validate_dialect_profile`
- `binding/exports.mbt` `doris_parse_v1` 等 → `fathom_parse_v1` 等，签名加 dialect 参数
- `completion.complete(raw, profile_id, cursor)` → 加 dialect
- `moon.mod` name `fathom/doris-sql` → `fathom/sql`，全仓 import 更新

</code_context>

<specifics>
## Specific Ideas

用户明确的命名意图（来自讨论）：
- 保留 `Dialect::Doris`、`DorisProfile`、doris-* corpus 目录、Doris provenance 作为语义标识
- 产品层不得残留 `doris-sql`/`doris-lsp`/`doris.*`/`DORIS-*`（现行文件），历史归档豁免
- 无向后兼容：不提供旧名 alias

</specifics>

<deferred>
## Deferred Ideas

- Flink grammar/工具链细节 → Phase 10/11/13
- Flink corpus 提取与 Calcite pin → Phase 10/12
- 自动方言检测（即使 opt-in）→ 未来阶段，不在 v2.0 默认范围
- 显式跨方言转换（transpile）→ CONVERT-FUTURE-01

</deferred>

---

*Phase: 9-Dialect Boundary and Neutral Naming*
*Context gathered: 2026-08-06*
