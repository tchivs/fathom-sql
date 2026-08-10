# Phase 5: Closeout and Analysis Foundation - Context

**Gathered:** 2026-08-10
**Status:** Ready for planning

<domain>
## Phase Boundary

本阶段交付两块内容：

1. **Closeout（CLOSE-01/CLOSE-02，v1.0 遗留验证收尾）** — 两项遗留验证已在 2026-08-06 核实完毕（STATE.md Deferred Items / v3.0-REQUIREMENTS 均已记录）：CLOSE-01 的 `vscode/scripts/host-verify.mjs` 真 extension-host 验证、CLOSE-02 的 `.github/workflows/ci.yml` linear-wasm-parity job（`moon test --target wasm --package parity`）均在仓库内。本阶段**只做正式记录/核实证据并更新 traceability，不重跑、不新实现**。

2. **ANAL-01（Analysis and Resolution）** — 把 `analyzer/` 从最小 catalog 边界（D-22：表级 `resolve_table_references`、无类型、无诊断）扩展为**可用的 catalog 名字解析与类型诊断**：Doris 表/列/函数/作用域的引用解析（限定/非限定引用、别名、CTE、子查询、带 catalog 的星号展开），大小写不敏感匹配遵循 Doris 语义并保留源码拼写与 span（每个 binding 携带 source span）。

**Requirements:** CLOSE-01（已验）、CLOSE-02（已验）、ANAL-01（本阶段主体）

**不在范围：** 完整 FE 等价类型推导（ANAL-02）、视图定义展开/血缘（LINE-01，Phase 7）、Lint（LINT-01，Phase 6）、指纹（FING-01，Phase 6）、增量解析（EDIT-01，Phase 8）、wire 导出新命名空间（本阶段无宿主消费）。

</domain>

<decisions>
## Implementation Decisions

### 分析模型与覆盖范围（ANAL-01 结构）
- **D-01:** ANAL-01 的分析模型在 **analyzer 侧对恢复的 token 流做轻量二次解析**，在 `analyzer/` 内部建立自己的分析模型，而不是依赖 CST 的细分节点。依据：`parser.mbt` `finish_statement`/`segment_children_for_events` 产出的 Select 节点是**平铺 token-leaf 流**（每个 token 一个 `SyntaxLeaf`，无子句/表项/限定名细分节点），`syntax/syntax.mbt` 的 `SyntaxKind` 只有粗粒度语句族。二次解析需覆盖：顶层子句切分（SELECT 列表 / FROM+JOIN / WHERE / GROUP BY / HAVING / QUALIFY / ORDER BY / LIMIT）、括号深度感知（子查询、CTE 体、函数实参）、`AS` 别名、限定名 `db.table.col`、`*` 与 `table.*`。**不新增 `SyntaxKind`、不改 parser**（Phase 12 冻结 Doris parser/线缆契约硬门禁 + D-21 边界）。保持 D-21 纪律：analyzer 只 import `syntax` + 调用方 source bytes，不 import parser/token/lexer/api/source；parser 永不 import analyzer；`parser/moon.pkg` 负门禁维持。**Reversibility:** costly — 分析模型是 analyzer 内部结构；若后续要求改由语法层提供细分节点，需重写二次解析并迁移既有结果结构。

- **D-02:** ANAL-01 语句覆盖以 **SELECT 为核心**（SELECT 列表表达式、FROM/JOIN 表引用与别名、WHERE/GROUP BY/HAVING/ORDER BY/QUALIFY 内的列引用、CTE（WITH）作用域、子查询作用域、集合运算 UNION/EXCEPT/INTERSECT），**DML 沿用既有走查并扩展**：INSERT/UPDATE/DELETE/MERGE 的目标表引用已在 `resolve_table_references` 覆盖，本阶段把列级引用扩展到 SET/WHERE/VALUES；**CREATE VIEW 体的表引用**纳入解析。其他语句族（DDL 其余、SHOW 等）不在 ANAL-01 解析范围。**Reversibility:** costly — 覆盖范围是公共能力承诺；收窄已承诺的语句族需兼容处理。

### 标识符大小写与类型诊断
- **D-03:** 标识符大小写不敏感匹配采用**解析时 ASCII case-fold**（镜像 `parser.mbt` `bytes_equal_ci` 与 analyzer 现有实现）：catalog 的 key/display 名保持作者原样，不构造期归一化；解析时折叠比较，binding 保留**源码拼写 + span**；带引号（backtick/双引号）标识符精确匹配、保留大小写（ROADMAP SC4：case policy documented；quoted identifiers keep exact case）。StaticCatalog 现有 case-sensitive 文档标注随本决策更新为 case-insensitive 匹配语义。**Reversibility:** reversible — 纯匹配策略，由测试锁定；后续如需 per-dialect 策略再扩展。

- **D-04:** 类型诊断深度（ANAL-01 要求 "type diagnostics"，但完整推导是 ANAL-02 出界）：**binding 携带类型**（列 → `ColumnInfo.data_type`；函数调用 → catalog 函数签名返回类型），诊断覆盖**未知表/未知列/未知函数、歧义非限定引用、函数实参数目不匹配**。**不做表达式级类型合一/推导/字面量类型传播**（那是 ANAL-02）。类型诊断作为 analyzer 独立的诊断通道输出，不进入语法诊断通道（语法 `valid` 与 catalog 无关，ANLY-01 不变）。**Reversibility:** costly — 诊断结果语义是公共契约；后续加深类型检查需兼容已有返回。

### Catalog 模型扩展
- **D-05:** Catalog 契约从扁平表扩展为：**(a) namespace 维度**——`db.table` / `db.table.column` 限定名解析，`Catalog` trait 增加 db 作用域查询路径，StaticCatalog 获得 db 作用域表；(b) **函数注册表**——`FunctionInfo`（name、param types、return type），支持函数调用的名字解析与元数检查。视图定义展开（view body → 列）**顺延 LINE-01（Phase 7）**，本阶段不做。现有 `Catalog::table(Self, String) -> TableInfo?` 走查 API 保留（`resolve_table_references` 行为不变）。**Reversibility:** one-way — `Catalog` trait 是公共接口；扩展 trait 方法会破坏既有实现者，发布后需迁移。

### 公共消费面
- **D-06:** ANAL-01 以 **MoonBit library API** 交付：`fathom/sql/analyzer` 返回结构化 `AnalysisResult`（bindings + 带 span 的诊断），配套文档与测试（`_test.mbt` 快照）。结果记录设计为**可序列化**（plain records + `@source.Span`），使后续 wire 导出成本低。**本阶段不新增 `fathom.analyze.v1` wire 导出、不新增 CLI 子命令**——wire/CLI/LSP 面在 Phase 6（Lint 消费同一结果模型）有真实宿主消费时再接。**Reversibility:** costly — 公共 API 形状（`AnalysisResult` 结构）发布后改动影响调用方。

### Closeout 范围
- **D-07:** CLOSE-01/02 本阶段**仅正式核实并记录证据 + 更新 traceability**（REQUIREMENTS/STATE/验证文档），不重跑 VS Code host 验证、不重跑 wasm parity（已在 2026-08-06 核实并在 CI 中持续执行）。**Reversibility:** reversible。

### Claude's Discretion
（`--auto` 模式：所有灰区由 Claude 依据既有决策链（D-21..D-24、Phase 12 冻结基线、ANLY-01）选择推荐项，无用户自由输入；D-01..D-07 覆盖全部灰区，无 "you decide"。）

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 需求与路线图
- `.planning/ROADMAP.md` §Phase 5 — Goal / Success Criteria（4 条：CLOSE-01、CLOSE-02、ANAL-01 解析能力、case-insensitive 语义与 span 保留）
- `.planning/REQUIREMENTS.md` — v3.0 需求（CLOSE-01/02 已验、ANAL-01 全文）
- `.planning/milestones/v3.0-REQUIREMENTS.md` — 归档需求定义与 traceability 表
- `.planning/PROJECT.md` — Core Value、Constraints、Key Decisions（D-21..D-24 analyzer 边界）

### 前序阶段决策（延续依据）
- `.planning/STATE.md` §Accumulated Context Decisions — D-21（analyzer 独立库只 import syntax）、D-22（最小 catalog 结构）、D-23（statement 入口）、D-24（scope：analyzer 先接口+最小实现，完整 ANAL-01 顺延 v3.0 Phase 5）
- `.planning/STATE.md` §Deferred Items — CLOSE-01/CLOSE-02 2026-08-06 验证记录（evidence in-repo）
- `.planning/phases/04-ecosystem-and-multi-target-delivery/04-CONTEXT.md`（归档于 `.planning/milestones/v1.0-phases/`）— ECO-07 VS Code 宿主验证、ECO-05/ECO-06 多目标交付

### 现状代码（扩展依据）
- `analyzer/analyzer.mbt` — 当前 analyzer：`ColumnInfo`/`TableInfo`/`Catalog`/`StaticCatalog`、`resolve_table_references`、`source_token_texts`/`bytes_equal_ci`/`utf8_to_string`（D-21/D-22/D-24 纪律）
- `analyzer/moon.pkg` — import 契约（仅 `fathom/sql/syntax`）
- `syntax/syntax.mbt` — `SyntaxNode`/`SyntaxElement`/`SyntaxLeaf`/`SyntaxKind` read-view API（平铺 token 叶子；粗粒度语句族）
- `parser/parser.mbt` §`finish_statement`/`segment_children_for_events` — CST 平铺结构依据（Select 节点无子句细分）
- `docs/API.md` §Optional Name-Resolution API — 已文档化 analyzer 契约（`resolve_table_references` 现状与 D-24 顺延说明）
- `vscode/scripts/host-verify.mjs` — CLOSE-01 证据（真 extension-host 3 模式）
- `.github/workflows/ci.yml` §`linear-wasm-parity` — CLOSE-02 证据（`moon test --target wasm --package parity` + native/js 交叉核对 + compare_backends digest）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `analyzer/analyzer.mbt` 的 `source_token_texts`（从 SyntaxNode 叶子恢复 token 字节）、`bytes_equal_ci`（ASCII case-fold 比较）、`utf8_to_string`（无依赖 UTF-8 解码）— ANAL-01 二次解析直接复用，无需新增 import
- `syntax/syntax.mbt` 的 `SyntaxNode::children()`/`span()`/`kind()` 只读视图 + `@source.Span`（checked half-open byte span）— analyzer 唯一输入与 binding span 载体
- `analyzer/` 现有 `StaticCatalog`/`Catalog` trait / `resolve_table_references` — D-05 扩展基础与 DML 走查复用
- `source` 模块 `@source.Span::checked` — 每个 binding 保留源码位置的基础设施

### Established Patterns
- D-21 边界纪律（analyzer 只 import syntax + source bytes）+ `parser/moon.pkg` 负门禁 — 本阶段继续遵守，新增分析模型内置在 analyzer 内部
- 只读 syntax-view 走查（现有 `resolve_table_references` 模式）— 新 SELECT 分析沿用同一入口纪律
- 闭合枚举 + 结构化错误 + 快照/golden 纪律（Phase 12 D-08 机制）— AnalysisResult 测试用 `_test.mbt` 快照锁定
- ASCII case-fold 比较（`bytes_equal_ci`）— D-03 大小写策略的现成实现
- 无 catalog 时语法结果字节不变（ANLY-01）— 类型/名字诊断是独立通道，绝不进入语法 valid 通道

### Integration Points
- `analyzer/analyzer.mbt` — 新增 SELECT 分析模型、`AnalysisResult`、db 作用域 Catalog 扩展、函数注册表（D-01/D-02/D-04/D-05）
- `docs/API.md` §Optional Name-Resolution API — 更新 analyzer 文档（新 API、case policy、类型诊断范围）
- `analyzer/` 测试（`_test.mbt` / 快照）— 绑定与诊断的 golden 测试
- Phase 6（Lint）— 消费 `AnalysisResult` 模型（D-06 预留）

</code_context>

<specifics>
## Specific Ideas

用户既有边界意图（延续 Phase 2/4 讨论链，本阶段 `--auto` 无逐条新输入）：
- D-21：analyzer 独立库，只 import syntax + source bytes；parser 永不 import analyzer
- D-22：最小 catalog（ColumnInfo/TableInfo/StaticCatalog），case-sensitive keys 文档标注（本阶段升级为 case-insensitive 匹配语义）
- D-24：完整 ANAL-01 顺延至 v3.0 Phase 5（现已是本阶段）
- CLOSE-01/02 已核实（2026-08-06，STATE Deferred Items 明文）
- 大小写不敏感匹配保留源码拼写与 span；带引号标识符精确匹配（ROADMAP SC4 明文）
- 无 catalog 时 parser validity 字节不变（ANLY-01）；catalog 元数据不可信、只被 analyzer 消费（T-02-42）

</specifics>

<deferred>
## Deferred Ideas

- 视图定义展开（view body → 列解析）→ LINE-01（Phase 7 血缘前置）
- 完整类型推导 / 表达式级类型合一 / 字面量传播 → ANAL-02（出界）
- wire 导出 `fathom.analyze.v1` / CLI 子命令 → Phase 6（Lint 消费同一模型）或首个宿主消费时
- catalog 感知补全、hover、语义 tokens → TOOL-FUTURE-01（backlog）
- 增量解析与定向 CST 重构 → EDIT-01（Phase 8，benchmark-gated）

---

*Phase: 5-Closeout and Analysis Foundation*
*Context gathered: 2026-08-10*
