# Phase 7: Column Lineage - Context

**Gathered:** 2026-08-11
**Status:** Ready for planning

<domain>
## Phase Boundary

本阶段交付 **LINE-01 列级血缘**：基于 ANAL-01（Phase 5）的解析结果，构建 source→target 列级血缘图，跨 SELECT/INSERT/CTE/集合运算/视图展开，边的每个端点携带源码位置；无 catalog 时对未解析引用与 `*` 展开**诚实报告 "requires catalog" gap，绝不伪造边**（SC2 明文）。

**Requirements:** LINE-01（ROADMAP Phase 7 SC1/SC2）

**不在范围：** 跨库/跨 catalog 血缘联邦（LINE-02）、完整类型推导（ANAL-02）、LSP 语义智能/补全/hover（TOOL-FUTURE-01）、增量解析（EDIT-01 → Phase 8，benchmark-gated）、Flink 血缘（本阶段 Doris-only，D-05）、视图定义持久化/物化（无 catalog 运行时，视图注册表为本阶段内存模型）。

</domain>

<decisions>
## Implementation Decisions

### 血缘边模型与表达式语义（LINE-01 核心）
- **D-01:** 血缘边为**列级 source→target 边**，投影表达式按**表达式直通**建模：输出列的表达式内**每个已解析列引用**各自贡献一条边到该输出列。`SELECT a + b AS x FROM t` → 两条边 `t.a → x`、`t.b → x`；`SELECT a AS x FROM t` → 一条边 `t.a → x`。函数调用表达式同样按实参列引用展开（`upper(c) AS u` → `t.c → u`）。不做表达式级 taint/中间表达式节点（区别于 "column→expression→column" 图，那是 LINE-02 级扩展）。每条边携带**源列引用 span + 目标输出列 span**（平铺 Int 字节偏移，D-01/D-06 纪律）。**Reversibility:** costly — 边语义是公共契约；若后续改为中间表达式节点图需迁移既有消费方。
- **D-02:** 表达式中的列引用通过 ANAL-01 的 `NameRef`/绑定复用：`SelectItem.refs` 已含每个引用；血缘边复用 Binding 的 `resolved_to` 归属表。未解析的列引用（unknown-column 诊断）→ 对应位置产生 `unresolved-reference` gap（D-07），不产生边。

### 视图解析与 CTE/集合运算
- **D-03:** 视图展开采用**同文档 CREATE VIEW 体解析 → 内存视图注册表**（view → 输出列映射），兑现 Phase 5 D-05 顺延；基表/外部列元数据来自注入 catalog。不在文档内定义的视图：有 catalog 列元数据（视图作为表）则展开，否则产生 `requires-catalog` gap。CTE 展开复用 analyzer 现有作用域栈（CteDef 已解析），不新写 CTE 引擎。**Reversibility:** one-way — 视图注册表语义决定 `INSERT INTO ... SELECT ... FROM v` 的边；若后续改为外部视图服务需迁移。
- **D-04:** 集合运算（UNION/EXCEPT/INTERSECT）按**位置列映射**：输出列 i 继承各分支第 i 列（UNION 输出列名取首分支，Phase 5 `SelectModel.branches` 既有约定）。INSERT 形态：`INSERT INTO t(c1,c2) SELECT ...` 目标列列表与 SELECT 输出按位置对齐；`INSERT INTO t VALUES (...)`/无列列表形式按目标表列序；`INSERT INTO t SET` 按列名。所有 INSERT 目标表来自 `resolve_table_references` 既有走查。**Reversibility:** costly — 列映射规则是公开语义；改动影响既有血缘结果。

### Catalog 注入与 `*` 展开 / Gap 政策
- **D-05:** catalog 注入延续 T-02-42（调用方拥有元数据、analyzer 只消费）：`lineage_text`/wire 导出接受**可选 catalog 参数**，CLI `lineage` 子命令加 `--catalog <file>`（JSON）；缺省/未提供时**所有 `*` 展开与外部视图按 gap 报告**，绝不合成边（SC2）。MoonBit 库 API 直接接受 catalog trait（与 `analyze` 一致）。**Reversibility:** one-way — wire 签名是公开 ABI；发布后增删 catalog 参数需迁移宿主。
- **D-06:** Gap 模型为**独立 gaps 列表**（与 edges 分离）：codes = `requires-catalog`（`*`/`table.*` 无 catalog 列元数据、外部视图无元数据）、`unresolved-reference`（unknown-table/column 的引用）、`requires-complete-parse`（error/missing 树，D-33 拒绝哲学，复用 `has_error_missing`）。每个 gap 携带 span。有 catalog 时 `*` 展开为真实边；`table.*` 仅当该表已解析且 catalog 提供列元数据才展开，否则 `requires-catalog` gap。**Reversibility:** one-way — gap codes 是公共契约；重命名破坏下游过滤。

### 交付面与方言门禁
- **D-07:** 交付面完整对齐 Phase 6 模式：新 `lineage/` MoonBit 包（D-21：只 import `analyzer/`，永不 import parser）+ `api.lineage_text` 序列化入口 + `fathom.lineage.v1` wire 导出（envelope 含 dialect/profile 元数据，D-09 纪律；`validate_schema_version` 增加第 8 命名空间）+ `fathom-sql lineage` 子命令（D-39 退出码 0/1/2）+ `parity/` 跨目标一致性（native/js/linear-wasm 字节一致）+ `docs/API.md` 章节。**Reversibility:** one-way — wire 命名空间是公开 ABI。
- **D-08:** 方言门禁：本阶段 **Doris-only**（LINE-01 按 Doris 需求定义）。flink 选择 → 显式不支持错误（FATHOM-SCHEMA 族，复用 D-04/D-05 纪律——不新造 `FATHOM-LINE-*`、不建 `fathom.lineage.flink` 命名空间），绝不静默空结果。**Reversibility:** reversible — 后续加 Flink 血缘为增量。

### Claude's Discretion
（`--auto` 模式：全部灰区由 Claude 依据既有决策链——D-21（analyzer 依赖纪律）、Phase 5 D-01/D-06（AnalysisResult/平铺 span）、Phase 5 D-05（视图展开顺延）、Phase 6 D-04/D-05/D-06（wire 命名空间 + schema v2 bump + 无 catalog 面纪律）、ANLY-01（语法 valid 通道不变）、T-02-42（catalog 调用方注入）、ROADMAP SC2（无 catalog 诚实 gap）、研究 Pitfall V1/V3/V6（catalog 大小写、视图/CTE/`*` 断裂、schema bump）——选择推荐项；D-01..D-08 覆盖全部灰区，无 "you decide"。）

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 需求与路线图
- `.planning/ROADMAP.md` §Phase 7 — Goal / Success Criteria（SC1：跨 SELECT/INSERT/CTE/集合运算/视图展开的列级血缘 + 边带源码位置；SC2：无 catalog 时 `*`/未解析引用 → 显式 gap，不伪造边）
- `.planning/REQUIREMENTS.md` — LINE-01 全文（"across supported queries and views ... view expansion ... explicit 'requires catalog' gaps rather than fabricated edges"）
- `.planning/milestones/v3.0-REQUIREMENTS.md` — 归档需求定义与 traceability
- `.planning/PROJECT.md` — Core Value、Constraints、Key Decisions（D-21..D-24 analyzer 边界）

### 前序阶段决策（延续依据）
- `.planning/STATE.md` §Accumulated Context Decisions — D-21（analyzer 独立库只 import syntax）、D-05（Catalog 契约：table/table_in_db/function）、ANLY-01（analyzer 独立诊断通道，语法 valid 不变）、T-02-42（catalog 元数据不可信、只被 analyzer 消费）、D-39（CLI 退出码 0/1/2）、D-04/D-09（fathom.*.v1 命名空间纪律）、Pitfall V6（schema v2 bump 纯增）
- `.planning/phases/05-closeout-and-analysis-foundation/05-CONTEXT.md` — D-01（SELECT 二次解析模型）、D-05（视图定义展开顺延 LINE-01）、D-06（AnalysisResult/Binding 平铺 span、可序列化）
- `.planning/phases/06-lint-and-fingerprint/06-CONTEXT.md` — D-04/D-05/D-06（lint/fingerprint wire + CLI + schema v2 bump + parity 交付模板）、D-01（包布局与单向依赖纪律）

### 研究（设计依据）
- `.planning/milestones/v1.0-research/ARCHITECTURE.md` §Analysis 包布局 — `lineage/` 新包依赖 `analyzer/`（永不 parser）；`binding/` schema v2 bump；`api/` 增 `lineage_text`；Phase C 构建顺序（LINE-01 需 ANAL-01）
- `.planning/milestones/v1.0-research/FEATURES.md` §Table Stakes / Dependency — LINE-01 column lineage（HIGH demand）with source positions + view/CTE expansion；LINE-01 依赖 ANAL-01（lineage edges need resolved column refs）
- `.planning/milestones/v1.0-research/PITFALLS.md` §Pitfall V1/V3 — 视图/CTE/`INSERT INTO ... SELECT` 跨语句展开；`*` 无 catalog 不健全 → 显式 "requires catalog" gap（D-17 诚实 provenance）；§Pitfall V6 — 新结果类型 append 到 binding schema 需 v2 bump、新 kind 视为 optional/unknown
- `.planning/milestones/v1.0-research/SUMMARY.md` — LINE-01（HIGH）依赖 ANAL-01；`*` requires catalog else explicit gap；`lineage/` imports `analyzer/`（never parser）
- `.planning/milestones/v1.0-research/STACK.md` — 无新运行时依赖；Map=LinkedHashMap 确定性迭代（稳定序列化）

### 现状代码（扩展依据）
- `analyzer/resolve.mbt` — `analyze`（文档级入口，返回 AnalysisResult）、`resolve_model`/`resolve_from_item`（作用域栈 + CTE/别名/限定名/星号）、`has_error_missing`（D-33 拒绝扫描，gap 复用）
- `analyzer/analysis.mbt` — `AnalysisResult`/`Binding`/`BindingKind`/`AnalysisDiagnostic`（平铺 span，可序列化）
- `analyzer/select_model.mbt` — `SelectModel`/`SelectCore`/`SelectItem.refs`/`FromItem`/`CteDef`/`NameRef`（二次解析模型，血缘直接复用）
- `analyzer/analyzer.mbt` — `Catalog` trait / `StaticCatalog` / `TableInfo` / `ColumnInfo` / `FunctionInfo`（D-05 契约）
- `api/api.mbt` — `lint_text`/`fingerprint_text`/`format_text` 共享入口模式（`lineage_text` 仿此，含可选 catalog 参数）；`parse_document` 内部解析辅助
- `binding/schema.mbt` + `binding/exports.mbt` — `validate_schema_version` 七命名空间（第 8 个 `fathom.lineage.v1` bump 点）、`#export_name` ABI 模式、envelope JSON 模式
- `fathom-sql/args.mbt` + `run.mbt` + `main.mbt` — CLI 子命令分发（parse/format/lsp/lint/fingerprint + D-39 退出码；`lineage` 仿此 + `--catalog <file>` 标志）
- `parity/`（`run_js.mbt`/`run_wasm.mbt`/`compare_backends.py`）— 跨目标一致性测试机制
- `docs/API.md` — 公共 API 文档（新增 lineage 章节）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `analyzer/resolve.mbt` `analyze`（文档级分析入口，`AnalysisResult`）：血缘直接调用它获取 bindings，再据 `SelectModel` 关联输出列 → 无需重写解析
- `analyzer/select_model.mbt` `SelectItem.refs` + `SelectItem.alias` + `FromItem` + `CteDef`：投影表达式列引用、输出别名、CTE 体已结构化，血缘边构造零成本复用
- `analyzer/resolve.mbt` `has_error_missing`：error/missing 树拒绝逻辑，gap `requires-complete-parse` 直接复用（D-33 哲学）
- `analyzer/analysis.mbt` `Binding`/`BindingKind`：边端点（source 列引用 + resolved 归属）与 span 载体
- `analyzer/analyzer.mbt` `Catalog`/`StaticCatalog`/`TableInfo.columns`：`*` 展开的列元数据来源；`StaticCatalog::lookup_in_db` 支持限定表
- `api/api.mbt` `parse_document` + `lint_text` 骨架：`lineage_text` 的解析/校验/序列化模板（增加可选 catalog 参数）
- `binding/schema.mbt`/`exports.mbt` envelope + `#export_name`：`fathom.lineage.v1` 的 JSON 结构与 ABI 模板
- `fathom-sql/run.mbt` D-39 映射：`lineage` 子命令沿用 0/1/2
- `parity/` compare_backends.py：跨目标字节一致性底座

### Established Patterns
- 单向依赖纪律（D-21/D-27）：`lineage/` 只 import `analyzer/`（+ `syntax`/`source` 间接），parser 永不反向 import；`parser/moon.pkg` 负门禁维持
- 可选 catalog 纪律（ANLY-01/T-02-42）：无 catalog 时结果字节不变；wire/CLI 面缺省无 catalog → 全 gap，不伪造边（SC2）
- 序列化 envelope（fathom.*.v1 + dialect/profile metadata，D-09）：`fathom.lineage.v1` 仿 parse/format/lint/fingerprint
- 快照/golden + 跨目标 parity 纪律（Phase 12 D-03/D-08）：血缘 edges/gaps 用 `_test.mbt` 快照 + parity 测试锁定
- 诚实 gap（D-17/研究 Pitfall V3）：`*` 无 catalog → 显式 gap 而非推测边
- schema v2 bump 纯增（Pitfall V6）：新增第 8 命名空间，既有七命名空间分支保留

### Integration Points
- `binding/schema.mbt` `validate_schema_version` + `binding/exports.mbt` — 新增 `fathom.lineage.v1` 命名空间与 `fathom_lineage_v1` 导出（第 8 个，Pitfall V6 纯增）
- `api/api.mbt` — 新增 `lineage_text(raw, parse_options, catalog?)` 共享核心入口（仿 `lint_text` + 可选 catalog 参数）
- `fathom-sql/args.mbt` + `run.mbt` + `main.mbt` — 新增 `lineage` 子命令（D-39 退出码；`--catalog <file>` 标志注入）
- 新 `lineage/` MoonBit 包 — `moon.pkg` import 契约（仅 analyzer + 间接依赖）
- `parity/` — 新增 lineage 跨目标一致性测试（edges/gaps 字节一致）
- `docs/API.md` — 新增 Lineage 公共 API 文档章节

</code_context>

<specifics>
## Specific Ideas

既有边界意图（延续 Phase 5/6 决策链与 v3.0 研究，本阶段 `--auto` 无逐条新输入）：
- Phase 5 D-05：视图定义展开（view body → 列）顺延 LINE-01 —— 本阶段以同文档 CREATE VIEW 体解析为视图注册表
- Phase 6 D-06：wire/CLI 面在有真实宿主消费时兑现 —— 本阶段 `fathom.lineage.v1` + CLI `lineage` 子命令 + parity 全对齐
- 研究 Pitfall V3：视图/CTE/`INSERT INTO ... SELECT` 跨语句展开需 resolved bindings；`*` 需 catalog 否则显式 gap
- SC2 明文：未解析引用与无 catalog 的 `*` 展开 → "requires catalog" gap，绝不合成边
- 诚实 provenance 纪律（D-17）：gap 必须显式区分 edges，不可混合为带标记边

</specifics>

<deferred>
## Deferred Ideas

- 跨库/跨 catalog 血缘联邦 → LINE-02（backlog）
- 表达式级 taint / column→expression→column 中间节点图 → LINE-02 级扩展（D-01 反面）
- Flink 血缘 → 后续阶段（本阶段 Doris-only，D-08）
- LSP 血缘可视化 / semantic tokens / hover → TOOL-FUTURE-01（backlog）
- 视图定义持久化 / 外部视图服务 → catalog 演进（无 catalog 运行时纪律）

---

*Phase: 7-Column Lineage*
*Context gathered: 2026-08-11*
