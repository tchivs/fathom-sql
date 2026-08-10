# Phase 11: Flink Grammar and Recoverable CST - Research

**Researched:** 2026-08-09
**Domain:** Apache Flink SQL 语句级 grammar（flink-sql-parser Parser.tdd/parserImpls.ftl/Parser.jj 模板）、Flink 语句族 → 共享无损 CST 映射、strict/editor 可恢复 CST（CST-01）、双向方言负门禁、Window TVF 与 MATCH_RECOGNIZE 支持/限制子集冻结
**Confidence:** HIGH（外部 grammar 事实全部由本 session 直接核验的钉住 release 源码/缓存 grammar 文件支撑，含逐字引用 + 行号；in-repo 契约由 `[VERIFIED: 路径:行]` 支撑）；MEDIUM（少量 planner 决策点：新 SyntaxKind 命名、FATHOM-PARSE-009 是否新建、parse_flink 文件拆分粒度）

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Grammar 作用域与子集
- **D-01:** Flink grammar 覆盖 FLINK-02..06 全部枚举范围：核心查询（SELECT/CTE/JOIN/聚合/集合运算/表达式/类型）、INSERT/UPDATE/DELETE、EXPLAIN/SHOW/DESCRIBE/ANALYZE、Catalog/DATABASE/TABLE/VIEW/FUNCTION DDL、CREATE TABLE 物理/元数据/计算列/WATERMARK/PRIMARY KEY NOT ENFORCED/PARTITIONED BY/分布/WITH 选项/LIKE/AS、Window TVF（TUMBLE/HOP/CUMULATE/SESSION 的 TABLE/DESCRIPTOR/区间字面量/命名参数/窗口输出列）、MATCH_RECOGNIZE（PATTERN/DEFINE/MEASURES/skip policy/模式变量/量词）。Window TVF 与 MATCH_RECOGNIZE 的 supported/known-limitation 子集由研究阶段从钉住 release 的 flink-sql-parser grammar + 对应 Calcite 测试定义并冻结（research flags 明文），语法级即可、不声称 planner/执行等价。**Reversibility:** costly — CST 形状是公共契约，后续扩展需保持兼容。

#### CST 与恢复
- **D-02:** Flink 复用 Doris 同一无损 CST 节点体系（source-backed Statement/Clause/Expr + error/missing/skipped 节点 + span/trivia 保留），不建独立 AST；新增 Flink 特有语句族节点（CREATE TABLE 物理/元数据/计算列、WATERMARK、Window TVF 输出列、MATCH_RECOGNIZE 块）。打印 lossless 树字节级复原输入（CST-01）。**Reversibility:** one-way — CST 形状是核心产品契约，无损 round-trip 依赖它。
- **D-03:** 恢复纪律与 Doris 一致：语句级 panic-mode + 子句级尽力恢复，strict/editor 双模式；错误/missing/skipped 节点有界（边界明确、来源字节可回溯），编辑模式对半成品输入持续产出可解析子树，不无限推进。**Reversibility:** reversible。

#### 方言路由与负门禁
- **D-04:** 保持单一 `parse_segment` 路由（parser.mbt:3336），Flink 分支从 FATHOM-PARSE-008 换成真实 grammar；实现**双向方言负门禁**：Flink-only 语法在 Doris 模式拒绝、Doris-only 语法在 Flink 模式拒绝，各自稳定诊断码（FATHOM-PARSE-NNN，dialect 不进 code 前缀，D-10 延续）；诊断经 metadata 携带方言信息。**Reversibility:** one-way — 诊断码是稳定公共契约。
- **D-05:** Flink grammar 事实源 = 钉住 release 的 flink-sql-parser grammar（Parser.tdd/Parser.jj + Calcite 测试），延续 Phase 10 的 release 提取纪律（禁 folklore/移动文档）；fixture 分 positive/negative/incomplete/recovery 四类，冻结为 parity/flink-grammar 快照；任何共享 parser/CST 改动前先重跑冻结 Doris baseline（213 快照，无 --update）。**Reversibility:** reversible — fixture/快照可经注册批准制更新。

#### 语句覆盖与交付顺序
- **D-06:** `parse_flink_segment` 的 FATHOM-PARSE-008 not-implemented 路径退役（Phase 10 已声明 Phase 11 落地 grammar，属预期行为变更）；FATHOM-PARSE-008 不再用于合法 flink SQL。**Reversibility:** costly — 行为变更影响依赖旧拒绝行为的消费者，但符合既定路线图。
- **D-07:** 按 vertical slice 顺序交付（每片含 recoverable CST + strict/editor 双模式 + 快照）：FLINK-02 核心查询 → FLINK-03 Catalog/DDL → FLINK-04 CREATE TABLE 复杂形式 → FLINK-05 Window TVF → FLINK-06 MATCH_RECOGNIZE。**Reversibility:** reversible。

### Claude's Discretion
（未出现 "you decide"；所有灰区由既有决策链 + 本阶段 D-01..D-07 明确覆盖。）

### Deferred Ideas (OUT OF SCOPE)
- Flink 工具链（format/completion/analyzer 方言分发）→ Phase 13（TOOL-01..03）
- 全量 Flink corpus 提取与跨后端 parity → Phase 12（CORPUS-01、PARITY-01/02）
- planner/执行等价、catalog 依赖的语义解析 → 不在 v2.0 SDK 范围（FLINK-06 明确不声称）
- 自动方言检测（即使 opt-in）→ 未来阶段
- 显式跨方言转换（transpile）→ CONVERT-FUTURE-01
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FLINK-02 | Consumer can parse Flink core queries and everyday statements including SELECT, CTE, JOIN, aggregation, set operations, expressions, types, INSERT, UPDATE, DELETE, EXPLAIN, SHOW, DESCRIBE, and ANALYZE with recoverable diagnostics. | §5 语句族→生产映射（base SqlStmt 分发 + RichSqlInsert/SqlUpdate/SqlDelete/SqlRichExplain/SqlShow*/SqlRichDescribe/SqlAnalyzeTable 逐字行）；§6.2 共享 query skeleton 复用边界；§7.3 表达式/类型覆盖 |
| FLINK-03 | Consumer can parse Flink Catalog and DDL entry points including CREATE/ALTER/DROP CATALOG, DATABASE, TABLE, VIEW, and FUNCTION as structured CST statement families. | §5.3 Catalog/DDL 生产逐字行（SqlCreateExtended/SqlDropExtended 分发、SqlCreateCatalog/SqlCreateDatabase/SqlCreateFunction/SqlCreateView/SqlDrop*）；§6.1 新增 CST 语句族 |
| FLINK-04 | Consumer can parse Flink CREATE TABLE physical, metadata, and computed columns; WATERMARK; PRIMARY KEY NOT ENFORCED; PARTITIONED BY; distribution; WITH connector options; LIKE; and AS forms while retaining token spelling, trivia, and spans. | §5.4 SqlCreateTable 全子形式逐字行（TableColumn 四类列、Watermark、TableConstraint、SqlDistribution、Properties、SqlTableLike、AS）；§7.4 Flink 类型解析（ExtendedDataType + dataTypeParserMethods） |
| FLINK-05 | Consumer can parse Window TVF forms for TUMBLE, HOP, CUMULATE, and SESSION, including TABLE/DESCRIPTOR arguments, interval literals, named arguments, and window output columns. | §5.5 TVF 语法结构（TUMBLE/HOP/SESSION/DESCRIPTOR 非保留字证据、TableFunctionCall、TVF SQL 示例）；§8 supported/known-limitation 子集冻结 |
| FLINK-06 | Consumer can inspect syntax-level MATCH_RECOGNIZE CST and diagnostics covering PATTERN, DEFINE, MEASURES, skip policy, pattern variables, and quantifiers; the SDK does not claim planner or execution equivalence. | §5.6 MatchRecognize 生产逐字行（Parser.jj:3062-3346：PARTITION/ORDER/MEASURES/ONE ROW/ALL ROWS/AFTER MATCH SKIP/PATTERN/DEFINE/WITHIN INTERVAL）；§8.2 子集冻结 |
| CST-01 | Consumer can parse Flink input in strict or editor mode into a recoverable lossless CST where comments, whitespace, newlines, unknown material, error nodes, missing nodes, skipped material, source bytes, and spans round-trip without loss. | §6.3 恢复+CST-01（复用 error/missing/skipped + finish_statement + recover_to_clause_boundary；新增 Flink 子语言同步点）；§6.4 lossless replay 保持 |
</phase_requirements>

## Summary

Phase 11 把 Phase 10 已就绪的 Flink 词法核心扩展为真实 Flink 语句级 grammar。本 session 对 `/tmp/flink-research/` 缓存的钉住 release（主 profile `flink-2.3.0`/Calcite 1.36.0，回归 `flink-2.1.3`/1.34.0、`flink-1.20.5`/1.32.0）的 **flink-sql-parser 模板 grammar 做了直接逐字核验**：语句入口由 `codegen/data/Parser.tdd` 的 `statementParserMethods`（`:651-727`，51 个 Flink 自定义语句方法）叠加 Calcite base `SqlStmt`（`codegen/templates/Parser.jj:1140-1185`：SqlAlter/SqlCreate/SqlDrop/SqlExplain/SqlDescribe/SqlInsert/SqlDelete/SqlUpdate/SqlMerge/SqlProcedureCall/OrderedQueryOrExpr）构成；全部 FLINK-02..06 构造都能映射到具体的 production 与行号（§5 给出逐字引用）。关键发现：(1) `TUMBLE/HOP/SESSION/CUMULATE/DESCRIPTOR` 全部是**非保留字**（`Parser.tdd` nonReservedKeywords），Window TVF 走的是通用 table-function 调用路径 `FROM TUMBLE(TABLE t, DESCRIPTOR(ts), INTERVAL '1' SECOND)`（`TableFunctionCall`，`Parser.jj:2443-2460`），因此 TVF 不需要专用 dispatch，只需要 FROM 子句的 table-ref 识别 + 表达式层支持 `TABLE(...)`/`DESCRIPTOR(...)`/`INTERVAL` 字面量；(2) **MATCH_RECOGNIZE 是 Calcite base 生产**（`Parser.jj:3062-3346`，`SqlMatchRecognize`），语法完整含 PARTITION/ORDER/MEASURES/rows-per-match/AFTER MATCH SKIP/PATTERN/DEFINE/WITHIN INTERVAL；(3) Flink 的 `CREATE TABLE` 与 Doris 形态差异巨大（`SqlCreateTable` 子句顺序 `[COMMENT][DISTRIBUTED][PARTITIONED BY][WITH][LIKE|AS]`，列体含 TypedColumn/MetadataColumn/ComputedColumn/Watermark/TableConstraint），需要独立 Flink CREATE TABLE parser，不能复用 Doris `parse_create_table`。

In-repo 侧确认：`parse_segment`（`parser/parser.mbt:3336-3351`）是唯一 dialect router，`parse_flink_segment`（`:3405-3429`）现返回 FATHOM-PARSE-008；共享表达式/Pratt/query skeleton 已带 `context` 参数，但 `precedence()`（`:263-274`）是纯原文函数（无 `||`/`=>`），Doris 查询/类型/表引用路径含大量 Doris-only 构造（`parse_table_ref` 的 PARTITION/TABLET/SAMPLE/TABLESAMPLE、`parse_column_type` 的 Doris 类型集）——这些**不能**被 Flink 复用，需独立 Flink 路径。新增 CST 语句族（`syntax/syntax.mbt:2-26` 的 SyntaxKind + `api/api.mbt:331-357` 的 kind_id）是 D-02 的 one-way 契约。

**Primary recommendation:** 按 D-07 的 vertical slice 顺序，把 `parse_flink_segment` 从 008 占位改为真实关键字分发；SELECT/CTE/聚合/集合运算复用共享 query skeleton（但 Flink 分支禁止走进 Doris-only 的 table_ref/type/投影边界），INSERT/UPDATE/DELETE/EXPLAIN/SHOW/DESCRIBE/ANALYZE 与全部 DDL 写**独立 Flink 生产函数**（新 `parser/flink_grammar.mbt`，同 package 可访问私有原语）；表达式层把 `precedence` 参数化为 `precedence(context, cursor)` 并为 Flink 增补 `||`/`=>`（Doris 分支字节不变）；双向负门禁在 parse_flink_segment / parse_doris_segment 的每个 Doris-only / Flink-only 构造点加诊断（Flink-only 用新 FATHOM-PARSE-009 或复用 007，Doris-only 用 007，planner 定稿）；`parity/` 新增 flink-grammar 快照组 + 双向负门禁 fixture，任何共享改动前重跑冻结 Doris baseline（213 快照）。

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Flink 语句入口分发（`parse_flink_segment` 真实 grammar） | `parser/`（新 `flink_grammar.mbt`，同 package 复用私有原语） | `api/`（ParseResult 自动携带新语句族） | `parse_segment`（`parser.mbt:3336`）已按 dialect 路由（D-04）；Flink 分支替换 008 占位（D-06） |
| SELECT/CTE/JOIN/聚合/集合运算（FLINK-02 核心查询） | `parser/`（共享 query skeleton：`parse_query`/`parse_select_core`/`parse_cte_prefix`/`parse_from` 的 Flink 安全子集） | `dialect/`（is_clause_keyword 已方言化） | 共享骨架带 `context`；Flink 分支必须跳过 Doris-only 构造（TABLET/SAMPLE/INTO OUTFILE/QUALIFY gate） |
| Flink 表达式/类型（`||`、`=>`、`INTERVAL`、ROW/ARRAY/MAP、`TIMESTAMP_LTZ` 等） | `parser/`（共享 Pratt engine + `precedence(context, cursor)` 方言策略表） | `dialect/`（Flink 运算符/关键字策略） | `precedence()`（`:263`）现为纯原文函数；Flink 需要 `||`(CONCAT)/`=>`(NAMED_ARGUMENT_ASSIGNMENT)——必须方言参数化，禁止改共享表污染 Doris（Pitfall 7） |
| INSERT/UPDATE/DELETE（FLINK-02 DML） | `parser/`（独立 `parse_flink_insert`/`parse_flink_update`/`parse_flink_delete`） | — | Flink `RichSqlInsert`（`parserImpls.ftl:2306-2379`）含 UPSERT/OVERWRITE/PARTITION/ON CONFLICT DO，与 Doris `parse_insert` 形态不同 |
| EXPLAIN/SHOW/DESCRIBE/ANALYZE（FLINK-02 辅助语句） | `parser/`（独立 Flink 生产，`SqlRichExplain`/`SqlShow*`/`SqlRichDescribe*`/`SqlAnalyzeTable` 映射） | `syntax/`（新增 ShowStatement/DescribeStatement/ExplainStatement/AnalyzeStatement kind） | Flink SHOW 语法（`LIKE`/`ILIKE`/`NOT LIKE`/`FROM|IN db`）与 Doris 完全不同，需独立 parser |
| Catalog/DATABASE/TABLE/VIEW/FUNCTION DDL（FLINK-03） | `parser/`（独立 Flink DDL parser，`SqlCreateExtended`/`SqlDropExtended`/`SqlAlter*` 分发映射） | `syntax/`（新增 CreateCatalog/CreateDatabase/CreateFunction/Drop*/Alter* kind） | Flink `CREATE CATALOG/DATABASE/FUNCTION/VIEW` 语法与 Doris 差异大（WITH option 形态、FUNCTION ... AS 'class' [LANGUAGE]） |
| CREATE TABLE 复杂形式（FLINK-04） | `parser/`（独立 `parse_flink_create_table`，四类列/Watermark/Constraint/Distribution/Properties/Like/As） | `syntax/`（新增 WatermarkClause/ComputedColumn/MetadataColumn/PrimaryKeyClause/TableLikeClause kind） | Flink 列体/子句顺序与 Doris 完全不同，禁止复用 Doris `parse_create_table`/`parse_column_definition`/`parse_distribution_clause` |
| Window TVF（FLINK-05） | `parser/`（FROM 子句 table-ref 增 TVF 识别 + 表达式层 `TABLE(...)`/`DESCRIPTOR(...)`/`INTERVAL` 字面量） | `dialect/`（TUMBLE/HOP/SESSION/DESCRIPTOR 非保留字行已就绪） | TVF 是通用 table-function 调用（`TableFunctionCall`，`Parser.jj:2443`）；`window_start/end/time` 输出列是普通标识符 |
| MATCH_RECOGNIZE（FLINK-06） | `parser/`（独立 `parse_match_recognize` 子语言，语法级 CST） | `syntax/`（新增 MatchRecognize kind + PATTERN/DEFINE/MEASURES 子树节点） | 嵌套子语言（`Parser.jj:3062-3346`）；独立同步点防恢复吞 token（Pitfall 4/8） |
| 双向方言负门禁（SC4） | `parser/`（Flink-only/Doris-only 构造点的拒绝诊断） | `binding/schema.mbt`（诊断码稳定映射） | D-04：Flink-only 语法在 Doris 拒绝、Doris-only 在 Flink 拒绝；dialect 不进 code 前缀 |
| flink-grammar 快照门禁 + 双向负门禁 fixture | `parity/`（独立 flink-grammar 快照组 + 冲突矩阵 fixture） | CI（`moon test` 无 `--update` 门禁 + baseline_diff.py） | D-05/D-08 同门禁分组复用；Doris 213 快照字节零漂移 |

## 5. Statement-Family → Production Mapping

> 行号事实源：`/tmp/flink-research/src/flink-2.3.0/flink-table/flink-sql-parser/src/main/codegen/{data/Parser.tdd,includes/parserImpls.ftl,templates/Parser.jj}`（Flink 模板）与 `/tmp/flink-research/Parser-calcite-1.36.0.jj`（Calcite base 生成版）。回归 profile 的行号以 2.1.3/1.20.5 对应文件为准（本表以 2.3.0 标行号，2.1.3/1.20.5 需按各自文件核对偏移）。

### 5.1 核心查询（FLINK-02：SELECT/CTE/JOIN/聚合/集合运算）

**生产（Calcite base，Flink 直接继承）：** `SqlStmt` 中 `OrderedQueryOrExpr(ExprContext.ACCEPT_QUERY)`（`codegen/templates/Parser.jj:1180-1181` 在 SqlStmt 分发内）→ `SqlSelect`（`Parser-calcite-1.36.0.jj:1322`）、`WithList`（`:3485`）、`QueryOrExpr`（`:3395`）、`SqlOrderBy`/`CompoundQuery`（UNION/INTERSECT/EXCEPT 经 `:3395` 的集合运算分支）。`SqlSelect` 含 SELECT 修饰符（DISTINCT/ALL）、投影、FROM、WHERE、GROUP BY、HAVING、WINDOW、ORDER BY、LIMIT/OFFSET/FETCH（标准 Calcite）。

**In-repo 复用决策：** `parse_query`（`parser/parser.mbt:1363-1382`）、`parse_select_core`（`:1154-1228`）、`parse_cte_prefix`（`:1325-1361`）、`parse_from`/`parse_table_ref`（`:909-1047`）的**骨架**是方言中立 SQL。但 Flink 分支必须跳过 Doris-only 构造：
- `parse_select_core` 的 `INTO OUTFILE`（`:1218-1226`）、`QUALIFY` gate（`:1212-1219`，DorisFeature::Qualify）→ Flink 分支不进入；
- `parse_table_ref` 的 `PARTITION`/`TABLET`/`SAMPLE`/`TABLESAMPLE`/`REPEATABLE`（`:917-975`）→ Flink 分支不进入；Flink 的 `PARTITION` 表选项仅 INSERT（`RichSqlInsert`）非 SELECT；
- `parse_cte_prefix` 的 `WITH RECURSIVE` feature 诊断（`:1334-1337`）→ Flink 下 Calcite base 支持 `WITH RECURSIVE`（`WithList`），语法级接受（[ASSUMED] A1 同族，见 §Assumptions）。

**建议实现：** 复用共享 query 函数，但以 `context.dialect is Flink` 门控 Doris-only 分支（最小侵入）；或抽一个 Flink 专用 `parse_flink_select_core` 薄封装跳过 Doris-only 分支。planner 定稿（§Open Question 2 同族）。

### 5.2 DML（FLINK-02：INSERT/UPDATE/DELETE）

| 语句 | Flink 生产 | 逐字行 | In-repo 现状 | 建议 |
|------|-----------|--------|-------------|------|
| INSERT/UPSERT | `RichSqlInsert()`（`statementParserMethods` 首位，`Parser.tdd:652`） | `parserImpls.ftl:2306-2379`：`(INSERT\|UPSERT) (INTO\|OVERWRITE)` + `SqlInsertKeywords` + `CompoundTableIdentifier` + `TableHints`/`ExtendTable` + `[PARTITION PartitionSpecCommaList]` + `[column list]` + `source = OrderedQueryOrExpr` + `[ON CONFLICT DO (ERROR\|NOTHING\|DEDUPLICATE)]` | Doris `parse_insert`（`parser.mbt:1502-1559`）仅 `INSERT [INTO] t [WITH LABEL] [(cols)] source` | **独立** `parse_flink_insert`（UPSERT/OVERWRITE/PARTITION/ON CONFLICT 是 Flink-only） |
| UPDATE | Calcite base `SqlUpdate()`（`Parser-calcite-1.36.0.jj:1794`） | `:1794-1832`：`UPDATE tableRef [alias] SET assignment_list [WHERE expr]` | Doris `parse_update`（`parser.mbt:1627-1678`）`SET ... WHERE` | 复用共享骨架（Flink 无 Doris 的 `WITH LABEL`/`COMMENT`）；负门禁拒绝 Doris-only |
| DELETE | Calcite base `SqlDelete()`（`:1768`） | `:1768-1789`：`DELETE FROM tableRef [AS alias] [WHERE expr]` | Doris `parse_delete`（`parser.mbt:1680-1737`）含 `PARTITION`/`USING` | 复用共享骨架；Flink 无 `PARTITION`/`USING`（负门禁） |

### 5.3 Catalog / DDL 入口（FLINK-03）

**分发生产：** `SqlCreateExtended`/`SqlDropExtended`（`parserImpls.ftl:2850-2920`，挂 `createStatementParserMethods`/`dropStatementParserMethods`，`Parser.tdd:738-746`）→ 逐类型：

| 语句 | 生产 | 逐字行 | 关键语法 |
|------|------|--------|---------|
| CREATE CATALOG | `SqlCreateCatalog` | `parserImpls.ftl:142-188` | `<CATALOG> [IF NOT EXISTS] name [COMMENT '...'] [WITH Properties()]` |
| DROP CATALOG | `SqlDropCatalog` | `:173-188` | `<CATALOG> [IF EXISTS] name` |
| ALTER CATALOG | `SqlAlterCatalog` | `:192-`（`statementParserMethods:659`） | `SET (...)`/`RESET (...)`/`COMMENT '...'` |
| CREATE DATABASE | `SqlCreateDatabase` | `:301-372` | `<DATABASE> [IF NOT EXISTS] name [COMMENT] [WITH Properties()]` |
| DROP DATABASE | `SqlDropDatabase` | `:351-372` | `[IF EXISTS] name [RESTRICT\|CASCADE]` |
| ALTER DATABASE | `SqlAlterDatabase` | `statementParserMethods:664` | `SET (...)` |
| CREATE TABLE | `SqlCreateTable` | `:1585-1712`（见 §5.4） | — |
| DROP TABLE | `SqlDropTable` | `:1777-1792` | `<TABLE> [IF EXISTS] name` |
| CREATE VIEW | `SqlCreateView` | `:2414-2439` | `<VIEW> [IF NOT EXISTS] name [(field_list)] [COMMENT] [AS query]`（`SqlCreateView(s.pos(), viewName, fieldList, query, replace, isTemporary, ifNotExists, comment, null)`） |
| DROP VIEW | `SqlDropView` | `statementParserMethods` 内 | `<VIEW> [IF EXISTS] name` |
| ALTER VIEW | `SqlAlterView` | `statementParserMethods:692` | `RENAME TO`/`AS query` |
| CREATE FUNCTION | `SqlCreateFunction` | `:390-480` | `<FUNCTION> [IF NOT EXISTS] name AS 'class' [LANGUAGE JAVA\|SCALA\|PYTHON]`（`[TEMPORARY [SYSTEM]]` 前缀经 `SqlCreateExtended`） |
| DROP FUNCTION | `SqlDropFunction` | 同族 | `[IF EXISTS] name` |
| ALTER FUNCTION | `SqlAlterFunction` | `statementParserMethods:665` | `AS 'class' [LANGUAGE ...]` |

**In-repo 现状：** Doris `parse_create`（`parser.mbt:1872-1928`）只认 `TABLE/VIEW/INDEX/MATERIALIZED`，无 CATALOG/DATABASE/FUNCTION。**建议**：独立 `parse_flink_create`（按第二词分派 CATALOG/DATABASE/TABLE/VIEW/FUNCTION/TEMPORARY），`parse_flink_alter`/`parse_flink_drop` 同构。Flink `CREATE FUNCTION ... AS 'class' [LANGUAGE]` 的 class 字符串 + LANGUAGE 是 Flink-only，Doris 负门禁。

### 5.4 CREATE TABLE 复杂形式（FLINK-04）

**主生产：** `SqlCreateTable`（`parserImpls.ftl:1585-1712`，逐字见 §Code Examples 3）。子形式全部在本生产内：

| 子形式 | 生产 | 逐字行 |
|--------|------|--------|
| 列体（物理列/计算列/元数据列/约束/Watermark 混合） | `TableColumnsOrIdentifiers` → `TableColumn` | `:1794-1830` / `:1103-1130` |
| 物理列 `name type [constraint] [COMMENT '...']` | `TypedColumn` + `RegularColumn` | `:1146-1128` / `:1278-1300` |
| 计算列 `name AS expr [COMMENT '...']` | `ComputedColumn` | `:1150-1176` |
| 元数据列 `name type METADATA [FROM 'alias'] [VIRTUAL] [COMMENT '...']` | `MetadataColumn` | `:1176-1210` |
| 列约束 / 表约束 | `ColumnConstraint` / `TableConstraint` | `:1420-1450` / `:1432-1460` |
| `PRIMARY KEY (cols) NOT ENFORCED` / `UNIQUE` | `UniqueSpec` + `ConstraintEnforcement` | `:1461-1504` |
| `WATERMARK FOR col AS expr` | `Watermark` | `:1121-1140`（`context.watermark` 单实例，多 Watermark 抛错 `multipleWatermarksUnsupported`） |
| `DISTRIBUTED [BY [HASH\|RANGE](cols)] [INTO n BUCKETS]` | `SqlDistribution` + `IntoBuckets` | `:1560-1600` / `:1556-1570`（`INTO n BUCKETS`，`n` 须正整数；`RANDOM` 不支持——测试 `testCreateTableWithRandomDistribution` `.fails`） |
| `PARTITIONED BY (cols)` | 主生产内 | `:1600-1610`（`<PARTITIONED> <BY> ParenthesizedSimpleIdentifierList()`） |
| `WITH ( 'k' = 'v', ... )` connector 选项 | `Properties` + `TableOption` | `:1520-1556` / `:1506-1520` |
| `LIKE table [(INCLUDING\|EXCLUDING\|OVERWRITING <feature> ...)]` | `SqlTableLike` + `SqlTableLikeOption` | `:1714-1790`（feature 含 ALL/CONSTRAINTS/DISTRIBUTION/GENERATED/METADATA/OPTIONS/PARTITIONS/WATERMARKS） |
| `AS query`（CTAS） | 主生产 `AS` 分支 | `:1650-1690`（`SqlCreateTableAs`/`SqlReplaceTableAs`） |
| `[COMMENT '...']` 表注释 | 主生产 `[COMMENT]` | `:1600-1610` |

**In-repo 现状：** Doris `parse_create_table`（`parser.mbt:2426-2529`）+ `parse_column_definition`（`:2570-2665`）+ `parse_distribution_clause`（`:2983-3030`）与 Flink 形态完全不同（Doris 的 `DUPLICATE KEY`/`ENGINE=`/`AUTO_INCREMENT`/`ROLLUP`/`BUCKETS n|AUTO`/`PROPERTIES`/`AUTO PARTITION BY` 均是 Flink 下非法）。**建议**：独立 `parse_flink_create_table`（列体用 Flink 四类列分派 + 表级子句按 `[COMMENT][DISTRIBUTED][PARTITIONED BY][WITH][LIKE|AS]` 顺序），新增 CST 节点见 §6.1。

### 5.5 Window TVF（FLINK-05）

**语法结构（钉住 release 证据）：**
- `TUMBLE`/`HOP`/`SESSION`/`DESCRIPTOR` 都是 **nonReservedKeywords**（`Parser.tdd`：`"TUMBLE"`:587、`"HOP"`:384、`"SESSION"`:509、`"DESCRIPTOR"`:351）；`CUMULATE` **无 keyword token**（三 release grep 均无，纯标识符）——因此 `FROM TUMBLE(TABLE t, DESCRIPTOR(ts), INTERVAL '1' SECOND)` 走通用 table-function 调用路径，**不需要专用 dispatch**。
- table-function 调用：`TableFunctionCall`（`codegen/templates/Parser.jj:2443-2460`）：`<TABLE> <LPAREN> [SPECIFIC] NamedRoutineCall(USER_DEFINED_TABLE_FUNCTION, ...) <RPAREN>` → `COLLECTION_TABLE`；`TABLE(...)` 在 FROM 中也是标准 Calcite `ExtendedTableRef`/`TableFunctionCall` 机制。
- 参数：`TABLE t`（第一个参数是表引用）、`DESCRIPTOR(col)`（时间列描述，非保留字函数调用）、`INTERVAL 'n' UNIT`（区间字面量，Calcite `IntervalLiteral`，`Parser-calcite-1.36.0.jj:4943`）、可选第 4 参数（offset 区间，如 `INTERVAL '8' HOUR`）、命名参数 `=>`（`NAMED_ARGUMENT_ASSIGNMENT`，`:8794`）。
- 窗口输出列：`window_start`/`window_end`/`window_time`（`WindowAggregateITCase.scala:250-263`）——普通标识符，随投影解析。

**真实 SQL（钉住 release 的 planner 测试）：**
```sql
-- TUMBLE TVF with offset（WindowAggregateITCase.scala:228-240）
SELECT window_start, window_end, SUM(...)
FROM TUMBLE(TABLE T1, DESCRIPTOR(rowtime), INTERVAL '1' DAY, INTERVAL '8' HOUR)
GROUP BY `name`, window_start, window_end;

-- 也可写 FROM TABLE(TUMBLE(TABLE T, DESCRIPTOR(col), INTERVAL '3' SECOND))（MatchRecognizeTest.scala:141-148）
```

**In-repo 现状：** `parse_table_ref`（`parser.mbt:909-947`）只认 `(subquery)` 或限定名；`TABLE(...)`/`TUMBLE(...)` 会被当 Doris table-ref 误消费或报错。**建议**：Flink FROM 分支的 `parse_table_ref` 增加「`TABLE(` 或 `TUMBLE/HOP/CUMULATE/SESSION(` 开头 → 解析 table-function 调用 + 括号参数（表引用 + `DESCRIPTOR(...)` + INTERVAL 字面量）」；`DESCRIPTOR(...)` 在表达式层作为普通函数调用（非保留字）自然解析。Doris 分支不进入（负门禁，见 §9）。

### 5.6 MATCH_RECOGNIZE（FLINK-06）

**生产：** Calcite base `MatchRecognize(SqlNode tableRef)`（`codegen/templates/Parser.jj:3062-3183`，逐字见 §Code Examples 5；`Parser-calcite-1.36.0.jj:3018-3300` 生成版同构）。挂接点：`tableRef = MatchRecognize(tableRef)`（`codegen/templates/Parser.jj:2206-2219`，FROM 表引用后缀，`LOOKAHEAD(3)`）。

| 子语言 | 生产 | 逐字行 |
|--------|------|--------|
| `MATCH_RECOGNIZE (` 入口 | `MatchRecognize` | `:3089` `<MATCH_RECOGNIZE> { s = span(); checkNotJoin(tableRef); } <LPAREN>` |
| `PARTITION BY expr_list` | 可选 | `:3091-3093` |
| `ORDER BY order_item_list` | 可选 | `:3095` |
| `MEASURES measure_column_comma_list` | `MeasureColumnCommaList` | `:3101-3103` |
| rows-per-match `ONE ROW PER MATCH`/`ALL ROWS PER MATCH` | 可选 | `:3108-3115` |
| `AFTER MATCH SKIP { TO NEXT ROW \| TO [FIRST\|LAST] var \| PAST LAST ROW }` | `AfterOption` | `:3123-3154` |
| `PATTERN ( [^] pattern_expr [$] )` | `PatternExpression` | `:3157-3176`（`<CARET>` 起始锚 `:3160`、`<DOLLAR>` 结束锚 `:3166`） |
| `WITHIN INTERVAL literal` | `IntervalLiteral` | `:3170` |
| `DEFINE var AS expr_comma_list` | `PatternDefinitionCommaList` | `:3177-3178` |
| pattern 组合 `\|`（ALTER） | `PatternExpression` | `:3218-3222`（`PATTERN_ALTER`） |
| pattern 串联 | `PatternTerm` | `:3236-3240`（`PATTERN_CONCAT`） |
| 量词 `{n}`/`{n,}`/`{n,m}`/`{,m}`/`+`/`*`/`?`（reluctant 后缀 `?`） | `PatternFactor`/`PatternQuantifier` | `:3314-3317`（`PATTERN_QUANTIFIER` startNum/endNum/reluctant） |
| `{- ... -}`（exclude） | `PatternExclude` | `:3294-3335`（`PATTERN_EXCLUDE`） |
| `PERMUTE(...)` | `PatternPermute` | `:3337-3346`（`PATTERN_PERMUTE`） |

**保留字 token（MATCH_RECOGNIZE 相关）：** `MATCH_RECOGNIZE`:8274、`MATCH_NUMBER`:8273、`MEASURES`:8277、`PATTERN`:8365、`DEFINE`:8103（`codegen/templates/Parser.jj`）。**注意**：`MATCH_RECOGNIZE` 不在 Phase 10 行表（Pitfall 9）——Phase 11 必须补 `dialect/flink.mbt` 行。

**In-repo 现状：** 无任何 MATCH_RECOGNIZE 路径。**建议**：独立 `parse_match_recognize`（table-ref 后缀，FROM 表引用后 `LOOKAHEAD` `MATCH_RECOGNIZE`），子语言内用独立同步点（`PARTITION`/`ORDER`/`MEASURES`/`ONE ROW`/`ALL ROWS`/`AFTER MATCH`/`PATTERN`/`DEFINE`/`)`），表达式层解析 `MEASURES`/`DEFINE` 内容（共享 Pratt）。**语法级 CST，不做 planner 等价**（FLINK-06）。

## 6. CST Statement Families, Recovery & CST-01

### 6.1 CST 语句族映射（复用/新增）

> D-02：Flink 复用同一无损 CST 节点体系，新增 Flink 特有语句族节点。`SyntaxKind` 现枚举（`syntax/syntax.mbt:2-26`）与 wire `kind_id`（`api/api.mbt:331-357`）是 one-way 契约（D-02）。

| FLINK 语句族 | 现有 SyntaxKind（复用） | 新增 SyntaxKind（建议，planner 定稿） |
|--------------|------------------------|--------------------------------------|
| SELECT/CTE/集合运算 | `Select`、`Expression`、`Token`、`Trivia` | — |
| INSERT/UPDATE/DELETE | `Insert`、`Update`、`Delete`、`ValueList` | — |
| EXPLAIN/SHOW/DESCRIBE/ANALYZE | `Statement`（容器） | `ShowStatement`、`DescribeStatement`、`ExplainStatement`、`AnalyzeStatement` |
| CREATE/DROP/ALTER CATALOG/DATABASE/FUNCTION | `Statement`、`PropertyList` | `CreateCatalog`、`CreateDatabase`、`CreateFunction`、`DropCatalog`、`DropDatabase`、`DropTable`、`DropView`、`DropFunction`、`AlterTable` |
| CREATE TABLE 复杂形式 | `CreateTable`、`ColumnDefinition`、`DistributionClause`、`PartitionClause`、`PropertyList` | `WatermarkClause`、`ComputedColumn`、`MetadataColumn`、`PrimaryKeyClause`、`TableLikeClause` |
| Window TVF | `Expression`、`Token` | `WindowTvf`（可选——若 TVF 仅作为 table-ref 表达式，可复用 `Expression` + span） |
| MATCH_RECOGNIZE | `Expression`、`Token`、`Error` | `MatchRecognize`（块容器）+ 子节点（PatternExpr/DefineList/MeasuresList 可折叠进 `Expression`/`Token` 子节点） |
| USE/SET/RESET | `Statement` | `SetOption`、`UseStatement` |

**约束：** 新 kind 追加到 `SyntaxKind` 枚举末尾（不重排既有变体，避免 `kind_id` 序号漂移）；`kind_id` 增新条目；`node_invariants_hold`（`syntax.mbt:57-75`）与 `is_valid`（`:96-127`）对新增 kind 无需改动（kind 不参与校验）。

### 6.2 共享 query skeleton 复用边界

**可复用（Flink 安全子集，已验证共享函数带 `context`）：** `parse_query` 的 WITH/UNION 骨架、`parse_select_core` 的 DISTINCT/投影/WHERE/GROUP/HAVING/WINDOW/ORDER/LIMIT 主路径、`parse_expression`/`parse_expression_postfix`（Pratt）、`parse_cte_prefix`、`finish_statement`（`:3129-3161`，含 trailing 001 与 Missing 节点）。

**不可复用（Doris-only，Flink 分支必须跳过或负门禁）：**
- `parse_select_core`：`EXCEPT` 投影修饰符（`:1174-1183`）、`QUALIFY` gate（`:1212-1219`）、`INTO OUTFILE`（`:1218-1226`）；
- `parse_table_ref`：`PARTITION`/`TABLET`/`SAMPLE`/`TABLESAMPLE`/`REPEATABLE`（`:917-975`）；
- `parse_column_type`（`:2656-2686`）：Doris 类型集（`LARGEINT`/`BITMAP`/`HLL`/`DATETIME` 等）+ `parse_type_params`（`:2688-2770`）；
- `parse_group_by` 的 Doris grouping 语法（`:1072-1119`）——Flink 用 Calcite 标准 GROUP BY（含 GROUPING SETS/CUBE/ROLLUP，Calcite base 支持）；
- `create_form_kind`/`parse_create`（`:1848-1928`）：只认 Doris 的 TABLE/VIEW/INDEX/MATERIALIZED。

**零漂移纪律：** 上述共享函数若因 Flink 而改动，Doris 分支必须字节不变；建议用 `context.dialect is Flink` 门控最小改动，或抽薄封装（`parse_flink_select_core` 调用共享子函数但跳过 Doris-only 分支）。

### 6.3 恢复 + CST-01

**复用机制（D-03，双方言同一纪律）：**
- 语句级 panic-mode：`finish_statement` 的 trailing 消费（`parser.mbt:3129-3161`）——Flink 语句同样在 `;`/段尾停，trailing 出 FATHOM-PARSE-001；
- 子句级尽力恢复：`recover_to_clause_boundary`（`:1583-1608`）+ per-family 边界谓词（Doris 的 `is_update_clause_boundary`/`is_delete_clause_boundary`/`is_merge_clause_boundary`/`is_create_table_clause_boundary`，`:1561-1580,2350-2359`）→ **Flink 需要新谓词**：`is_flink_create_table_clause_boundary`（COMMENT/DISTRIBUTED/PARTITIONED/WITH/LIKE/AS）、`is_flink_match_recognize_boundary`（MEASURES/ONE ROW/ALL ROWS/AFTER MATCH/PATTERN/DEFINE/`)`）、`is_flink_insert_boundary`（PARTITION/ON CONFLICT/SELECT/VALUES/`)`）；
- 有界性：`consume_recovery_step`（`:226-238`，recovery_steps cap）+ `depth_allowed`（`:252-261`，max_recursion_depth）+ `resource_diagnostic`（`:181-199`）——Flink 语句族共享同一预算；嵌套 MATCH_RECOGNIZE/PATTERN 用独立同步点防无限推进（Pitfall 4/8）；
- error/missing/skipped 节点：`SyntaxNode::error/missing/skipped`（`syntax.mbt:134-148`）+ `append_skipped`/`append_skipped_span`/`append_trivia_segment`（`parser.mbt:3431-3485`）——Flink 复用同一节点工厂；
- strict/editor：`ParseMode` 双模式经 `parse_with_limits_context`（`:3487`）透传；Flink 不做新模式，只保证两种模式都产出 source-backed 有界 CST。

**新增 error/missing/skipped 变体（建议，planner 定稿）：** 无需新 LeafKind（`SourceToken/SourceTrivia/SourceError/SourceSkipped` 已覆盖）；需要的是新**语句族容器 kind** 内嵌 error/missing/skipped 子节点（如 `MatchRecognize` 块内 `DEFINE` 缺失 → `Missing` 子节点；`WATERMARK FOR` 缺 `AS expr` → `Error` 子节点）。CST-01 的「unknown material / skipped material」由 `Skipped` 节点 + `append_skipped` 保证（半成品 `CREATE TABLE t (` 后接非法 → skipped 到段尾）。

### 6.4 lossless replay 保持

`print_lossless(parse(input)) == input` 由 CST 结构不变量保证（`node_invariants_hold`：子节点 span 连续覆盖父 span，`:57-75`）；Flink 新增语句族节点只要遵守同一「span 连续 + source-backed 叶子」不变量，replay 自动保持。**fixture 断言：** 每个 positive/recovery fixture 双模式都断言 `print_lossless(parse(x)) == x`（CST-01 SC4）。

### 6.5 FATHOM-PARSE-008 退役（D-06）

- **现状：** `parse_flink_segment`（`parser.mbt:3405-3429`）是唯一 008 生产者；测试 `parser.mbt:3624-3628` 断言 `code == "FATHOM-PARSE-008"`。
- **处置：** 替换 008 路径为真实 grammar（Pattern 1）；删除/改写 008 测试；**008 code 保留空缺不复用**（同 `DORIS-PARSE-005` 空缺惯例，避免与历史上见过 008 的消费者混淆）。
- **Phase 11 真正不支持的 Flink 语句**（不在 FLINK-02..06 范围）：`CREATE MATERIALIZED TABLE`、`CREATE CONNECTION`、`CREATE MODEL`、`STATEMENT SET BEGIN...END`、`EXECUTE`/`COMPILE`/`EXECUTE PLAN`、`LOAD/UNLOAD MODULE`、`ADD/REMOVE JAR`、`SHOW JOBS/JARS`、`STOP JOB`、`BEGIN/END STATEMENT SET`——这些走既有 `unsupported_statement`（FATHOM-PARSE-007，`:3163-3175`），source-backed Error 节点（同 Doris 的 async-MV 处理）。

## 7. Expression / Type Coverage

### 7.1 表达式范围（FLINK-02 表达式）

**In scope（语法级，全部有 Flink grammar 依据）：**
- 字面量：数字、字符串、`NULL/TRUE/FALSE`、`X'..'`/`U&'..'`/`N'..'`/`E'..'`（按 profile gate）、`INTERVAL 'n' UNIT`（`IntervalLiteral`，`Parser-calcite-1.36.0.jj:4943`）；
- 标识符/限定名/反引号标识符（Flink 下保留字须反引号）；
- 函数调用（含 `CASE`/`CAST`/`COALESCE`/`NULLIF`/聚合函数/窗口函数 `OVER`）、`COUNT(*)`；
- 构造器：`ROW(...)`、`ARRAY[...]`/`ARRAY(...)`、`MAP[...]`、`[ROW] (subquery)` 行子查询；
- 运算符：算术 `+ - * / %`、比较 `= < > <= >= <> !=`、逻辑 `AND OR NOT`、`||`（CONCAT，需 Flink precedence）、`IS [NOT] NULL`/`IS [NOT] DISTINCT FROM`、`[NOT] IN`/`[NOT] BETWEEN`/`[NOT] LIKE`/`[NOT] SIMILAR`、`EXISTS`、`AT TIME ZONE`（Calcite base）、`=>`（命名参数，TVF/函数调用）；
- 集合运算 / 子查询表达式（`(SELECT ...)`）。

**Deferred（known-limitation 或规划外）：** pattern 变量的列作用域解析（MATCH_RECOGNIZE 内 `A.price` 的作用域校验 → 语法级只保结构）；streaming 专属时间函数语义（`TUMBLE_ROWTIME()` 等 legacy 窗口函数按普通函数解析）；catalog/类型推断。

**In-repo 现状：** 共享 Pratt `parse_expression`（`parser.mbt:697-799`）+ `parse_expression_postfix`（`:588-670`）处理 CASE/CAST/函数/窗口/谓词；但 `precedence()`（`:263-274`）无 `||`/`=>`。**建议**：Pattern 4 的 `precedence(context, cursor)` 方言策略表；`||` 在 Flink 分支给 CONCAT 优先级（A3）；`=>` 在函数/调用参数层处理（非二元优先级）。

### 7.2 类型范围（FLINK-02 类型 / FLINK-04 列类型）

**In scope（语法级，`dataTypeParserMethods`，`Parser.tdd:759-765`）：**
- 基本类型（`ExtendedSqlBasicTypeName`）：`BOOLEAN`、`TINYINT/SMALLINT/INT/INTEGER/BIGINT`、`FLOAT/DOUBLE/REAL`、`DECIMAL(p,s)/NUMERIC(p,s)`、`CHAR(n)/CHARACTER(n)/VARCHAR(n)/STRING`、`BYTES/BINARY(n)/VARBINARY(n)`、`DATE/TIME(p)/TIMESTAMP(p)/TIMESTAMP_LTZ(p)/TIMESTAMP(p) WITH [LOCAL] TIME ZONE`、`INTERVAL`；
- 集合/嵌套类型：`ARRAY<T>`、`MAP<K,V>`、`MULTISET<T>`（`CustomizedCollectionsTypeName`）、`ROW<f1 T1, f2 T2>`（`ExtendedSqlRowTypeName`）、结构化类型（`SqlStructuredTypeName`）、`RAW('class'[, 'snapshot'])`（`SqlRawTypeName`）、`BITMAP`（`SqlBitmapTypeName`）、`VARIANT`（2.1.3+）。

**Deferred：** 类型精度/长度的语义校验（`DECIMAL(38,10)` 超精度 → 语法级不校验）；`RAW` 的 class 字符串内容校验；catalog 内结构化类型解析。

**In-repo 现状：** Doris `parse_column_type`（`parser.mbt:2656-2686`）+ `parse_type_params`（`:2688-2770`）是 Doris 类型集（`LARGEINT`/`BITMAP`/`HLL`/`DATETIME`/`DECIMAL` 等）。**建议**：独立 `parse_flink_data_type` 映射 Flink 类型（`TIMESTAMP_LTZ`、`ROW<>`/`MAP<>`/`ARRAY<>`/`MULTISET`、`<...>` 泛型括号），Doris 分支不动（Pitfall 7）。

### 7.3 表达式生产映射（逐字行）

| 表达式 | Flink 生产 | 逐字行 |
|--------|-----------|--------|
| `CASE WHEN ... THEN ... ELSE ... END` | Calcite base `Case` 分支 | `Parser-calcite-1.36.0.jj`（`SqlCase`） |
| `CAST(x AS type)` | `Cast` 分支 | 同上（`SqlCast`） |
| `INTERVAL 'n' UNIT` | `IntervalLiteral` | `Parser-calcite-1.36.0.jj:4943-4990` |
| `ROW(a, b)` / 行构造 | `Row` 分支 | 同上（`SqlRow`） |
| `ARRAY[...]` / `MAP[...]` | `Collection`/`Map` 分支 | 同上（`SqlCollectionTypeNameSpec`/`SqlMapTypeNameSpec`） |
| `||` CONCAT | `CONCAT` token | `codegen/templates/Parser.jj:8793`（token）；优先级需 Flink 策略表（A3） |
| `=>` 命名参数 | `NAMED_ARGUMENT_ASSIGNMENT` | `:8794`（token） |
| `IS [NOT] DISTINCT FROM` | Calcite base `IsDistinctFrom` | `Parser-calcite-1.36.0.jj` |
| `x AT TIME ZONE 'UTC'` | `AtTimeZone` | 同上 |

### 7.4 类型解析映射（逐字行）

| 类型 | Flink 生产 | 逐字行 |
|------|-----------|--------|
| 基本类型 + nullable 后缀 | `ExtendedDataType` | `parserImpls.ftl:1395-1420`（`[ NULL | NOT NULL ]` 后缀，集合元素与整体各自 nullable） |
| `ARRAY<T>`/`MULTISET<T>` | `CustomizedCollectionsTypeName` | `dataTypeParserMethods:761` |
| `MAP<K,V>` | `SqlMapTypeName` | `:762` |
| `ROW<...>` | `ExtendedSqlRowTypeName` | `:764` |
| `TIMESTAMP_LTZ(p)` | `SqlTimestampLtzTypeName` | `type/SqlTimestampLtzTypeNameSpec.java`（java 目录） |
| `RAW('class')` | `SqlRawTypeName` | `:763` |
| `BITMAP` | `SqlBitmapTypeName` | `:766` |
| 结构化类型（catalog 前缀） | `SqlStructuredTypeName` | `:765` |

## 8. Window TVF + MATCH_RECOGNIZE Supported / Known-Limitation Subsets

> 研究 flags 明文要求研究阶段从钉住 release 定义并冻结子集（D-01）。下表为**建议冻结**，planner 按 fixture 落盘。

### 8.1 Window TVF 子集（FLINK-05）

**IN scope（语法级）：**
| 形式 | 示例 | 证据 |
|------|------|------|
| `TUMBLE(TABLE t, DESCRIPTOR(ts), INTERVAL 'size')` | `TUMBLE(TABLE T1, DESCRIPTOR(rowtime), INTERVAL '5' SECOND)` | `WindowAggregateITCase.scala:228` |
| `TUMBLE(...)` + offset 第 4 参 | `TUMBLE(TABLE T1, DESCRIPTOR(rowtime), INTERVAL '1' DAY, INTERVAL '8' HOUR)` | `:240` |
| `HOP(TABLE t, DESCRIPTOR(ts), INTERVAL 'slide', INTERVAL 'size')` | `HOP(TABLE T1, DESCRIPTOR(rowtime), INTERVAL '30' SECONDS, INTERVAL '15' SECONDS)` | `:261` |
| `CUMULATE(TABLE t, DESCRIPTOR(ts), INTERVAL 'step', INTERVAL 'size')` | （CUMULATE 无 keyword token，通用函数路径） | `Parser.tdd` 无 CUMULATE；`WindowAggregateITCase.scala` 注释 |
| `SESSION(TABLE t, DESCRIPTOR(ts), INTERVAL 'gap')` | （SESSION 非保留字） | `Parser.tdd:509` |
| `FROM TABLE(TVF(...))` 显式 TABLE 包装 | `FROM TABLE(TUMBLE(TABLE T, DESCRIPTOR(matchRowtime), INTERVAL '3' second))` | `MatchRecognizeTest.scala:141-148` |
| 窗口输出列 `window_start/window_end/window_time` | 投影/别名/聚合引用 | `WindowAggregateITCase.scala:250-263` |
| 命名参数 `data => ...` / `timecol => ...` | `=>` token 已存在 | `Parser.jj:8794`（A3/A4 关联） |

**known-limitation（语法级接受结构，不做语义校验 / 或显式 007 拒绝）：**
| 形式 | 处置 |
|------|------|
| TVF 的 offset 参数为负区间（`INTERVAL '-8' HOUR`） | 语法级接受（INTERVAL 字面量解析），语义校验 defer（`WindowAggregateITCase.scala:290` 有负 offset 用例，语法上合法） |
| TVF 在 Doris 模式 | **负门禁拒绝**（Flink-only，§9） |
| TVF 的 planner 语义（事件时间/水印/窗口聚合类型推断） | 明确不实现（FLINK-05 语法级） |

### 8.2 MATCH_RECOGNIZE 子集（FLINK-06）

**IN scope（语法级 CST，全部有生产逐字行）：**
| 特性 | 证据（`codegen/templates/Parser.jj`） |
|------|--------------------------------------|
| `PARTITION BY expr_list` | `:3091-3093` |
| `ORDER BY order_item_list` | `:3095` |
| `MEASURES`（含 `MATCH_ROWTIME()`/`MATCH_PROCTIME()`/`MATCH_NUMBER()` 作为普通函数调用） | `:3101-3103`（`MeasureColumnCommaList`） |
| rows-per-match：`ONE ROW PER MATCH` / `ALL ROWS PER MATCH` | `:3108-3115` |
| skip policy：`AFTER MATCH SKIP TO NEXT ROW` / `TO FIRST var` / `TO LAST var` / `PAST LAST ROW` | `:3123-3154` |
| `PATTERN (...)`：模式变量、`\|`（ALTER）、串联（CONCAT）、`^`/`$` 锚 | `:3157-3176`、`:3218-3240` |
| 量词：`{n}`/`{n,}`/`{,m}`/`{n,m}`/`+`/`*`/`?` + reluctant `?` | `:3314-3317` |
| `DEFINE var AS expr` 列表 | `:3177-3178` |
| `WITHIN INTERVAL literal` | `:3170` |
| 真实 SQL 形态（release planner 测试） | `MatchRecognizeTest.scala:60-163`（`FROM Ticker MATCH_RECOGNIZE ( PARTITION BY symbol ORDER BY ts MEASURES ... ONE ROW PER MATCH PATTERN (A) DEFINE A AS A.price > 0 ) AS T`） |

**known-limitation（语法级结构可解析但标注已知限制 / 或 defer）：**
| 特性 | 处置 |
|------|------|
| `SUBSET`（subsetList） | 生产接受 `subsetList`（`:3182` 构造入参）但 Flink planner 支持有限——语法级解析结构，fixture 分类 known-limitation |
| `{- ... -}`（PatternExclude）与 `PERMUTE(...)` | 语法级可解析（`:3294-3346`）；fixture 分类 known-limitation（Flink 文档声明仅标准子集） |
| pattern 变量列作用域/类型校验（`A.price`、`DEFINE A AS A.price > 0` 的列存在性） | **不实现**（planner 前置，FLINK-06 明确不声称）；语法级只保变量名/表达式结构 |
| 嵌套 recovery（`MATCH_RECOGNIZE (` 未闭合 + 后续语句） | 独立同步点 + 共享恢复预算（Pitfall 4）；recovery fixture 覆盖 |
| MATCH_RECOGNIZE 在 Doris 模式 | **负门禁拒绝**（Flink-only，§9） |

## 9. Bidirectional Dialect-Negative Gate Matrix

> D-04/SC4：Flink-only 语法在 Doris 模式拒绝、Doris-only 语法在 Flink 模式拒绝，各自稳定诊断码（FATHOM-PARSE-NNN，dialect 不进 code 前缀）。**code 建议：** 新建 `FATHOM-PARSE-009`「syntax is not supported in the selected dialect」用于构造点负门禁（007 语义偏宽，Open Question 1）；整句 unsupported 仍用 007。**gate 位置：** `parse_segment`（`parser.mbt:3336`）→ `parse_flink_segment`/`parse_doris_segment` 的每个构造点。

| Flink-only 构造 | 示例 | Flink 证据 | Doris 模式处置 |
|-----------------|------|-----------|----------------|
| `WATERMARK FOR col AS expr` | `WATERMARK FOR ts AS ts - INTERVAL '1' SECOND` | `parserImpls.ftl:1121-1140` | 009（列体/表级子句点） |
| 计算列 `col AS expr`（CREATE TABLE 内） | `log_ts AS PROCTIME()` | `:1150-1176` | 009 |
| 元数据列 `col T METADATA [FROM] [VIRTUAL]` | `x STRING METADATA FROM 'a' VIRTUAL` | `:1176-1210` | 009 |
| `PRIMARY KEY (cols) NOT ENFORCED` / `UNIQUE` | `PRIMARY KEY (id) NOT ENFORCED` | `:1432-1504` | 009 |
| `DISTRIBUTED [BY [HASH\|RANGE](cols)] [INTO n BUCKETS]` | `DISTRIBUTED BY HASH(a) INTO 6 BUCKETS` | `:1560-1600` | 009（Doris 的 DISTRIBUTED 形态是 `BY HASH(...) BUCKETS n`，子形态不同，Flink 形态拒绝） |
| `PARTITIONED BY (cols)`（CREATE TABLE 表级） | `PARTITIONED BY (dt)` | 主生产 `:1600` | 009 |
| `WITH ( 'k' = 'v' )` connector 选项（CREATE TABLE） | `WITH ('connector' = 'kafka')` | `:1520-1556` | 009（Doris CREATE TABLE 用 `PROPERTIES`，不认 `WITH`） |
| `LIKE table [(INCLUDING/EXCLUDING/OVERWRITING ...)]` | `CREATE TABLE t2 LIKE t1 (INCLUDING ALL)` | `:1714-1790` | 009 |
| `CREATE TABLE ... AS query`（CTAS 在 Doris 是 `PROPERTIES ... AS` 或独立 `CREATE TABLE AS`，形态不同） | `CREATE TABLE t WITH ('k'='v') AS SELECT * FROM b` | `:1650-1690` | 009（Doris CTAS 语法不同） |
| `CREATE CATALOG/DATABASE/FUNCTION` 全族 | `CREATE CATALOG c WITH (...)` | `:142-480` | 007（Doris 无此语句） |
| `SHOW CATALOGS/TABLES/COLUMNS/FUNCTIONS/CREATE ...` 全族 | `SHOW TABLES FROM db1 LIKE '%'` | `:233-760` | 007（Doris SHOW 语法不同） |
| `DESCRIBE [EXTENDED] TABLE/FUNCTION/DATABASE/CATALOG` | `DESCRIBE TABLE t` | `:867-880` | 007/009（Doris `DESC` 语法不同） |
| `EXPLAIN [PLAN FOR ...]` | `EXPLAIN PLAN FOR SELECT ...` | `:3079-3117` | 007 |
| `ANALYZE TABLE t [PARTITION(...)]` | `ANALYZE TABLE t` | `:3413-3443` | 007 |
| `INSERT OVERWRITE` / `UPSERT` / `INSERT ... PARTITION(...)` / `ON CONFLICT DO` | `INSERT OVERWRITE t PARTITION (dt='1') SELECT ...` | `:2306-2379` | 009 |
| `MATCH_RECOGNIZE` | `FROM t MATCH_RECOGNIZE (PATTERN (A) DEFINE A AS ...)` | `Parser.jj:3062-3346` | 009（table-ref 后缀点） |
| Window TVF | `FROM TUMBLE(TABLE t, DESCRIPTOR(ts), INTERVAL '1' MINUTE)` | `Parser.jj:2443-2460` + 非保留字 | 009（table-ref 点） |
| `SET`/`RESET`/`USE` | `SET 'k' = 'v'; USE CATALOG c` | `:3294-3333` | 007 |
| `//` 行注释 | `// comment` | Phase 10 词法（`Parser-calcite-1.36.0.jj:8901`） | 词法层已隔离（Phase 10） |
| `E'..'` 字面量 | `E'\\n'` | Phase 10（`:8721`，1.34.0+） | 词法层已隔离 |
| `=>`/`||` 运算符 | `f(a => 1)`, `a || b` | Phase 10（`:8794/:8793`） | 词法 token 已隔离；表达式层 Flink-only |

| Doris-only 构造 | 示例 | Doris 证据 | Flink 模式处置 |
|-----------------|------|-----------|----------------|
| `DISTRIBUTED BY HASH(cols) BUCKETS n\|AUTO` / `RANDOM` | `DISTRIBUTED BY HASH(k) BUCKETS 10` | `parser.mbt:2983-3030` | 009（Flink `INTO n BUCKETS` 形态） |
| `DUPLICATE KEY` / `UNIQUE KEY` / `AGGREGATE KEY` | `DUPLICATE KEY (id)` | `:2362-2369` | 009 |
| `ENGINE = ...` | `ENGINE = OLAP` | `:2455-2470` | 009 |
| `AUTO_INCREMENT` | `id INT AUTO_INCREMENT` | `:2600-2615` | 009 |
| `ROLLUP (...)` | `ROLLUP (r1 (k))` | `:3032-3068` | 009 |
| `AUTO PARTITION BY` / `PARTITION BY RANGE\|LIST (...) (...)` | `PARTITION BY RANGE(dt) (...)`, `AUTO PARTITION BY LIST(city) (...)` | `:2837-2981` | 009 |
| `PROPERTIES ( "k" = "v" )`（Doris DDL 属性） | `PROPERTIES ("replication_num" = "3")` | `:3070-3123` | 009（Flink 用 `WITH`；`PROPERTIES` 非 Flink CREATE TABLE 子句） |
| `TABLET (id)` 表选项 | `TABLET (1001)` | `:917-940` | 009 |
| `SAMPLE` / `TABLESAMPLE` / `REPEATABLE` | `FROM t TABLESAMPLE(10)` | `:940-970` | 009 |
| `INTO OUTFILE` | `SELECT ... INTO OUTFILE 'x'` | `:1218-1226` | 009 |
| `WITH LABEL`（INSERT） | `INSERT INTO t WITH LABEL 'x'` | `:1537-1541` | 009 |
| `LATERAL VIEW` | `FROM t LATERAL VIEW explode(x) e` | Doris DDL/DML 族 | 009 |
| `#` 行注释 | `# comment` | `lexer.mbt:277`（Doris=comment） | 词法层已隔离（Phase 10：Flink=lexical error） |
| `QUALIFY` 子句 | `SELECT ... QUALIFY ROW_NUMBER() OVER(...) = 1` | `parser.mbt:1212-1219` | 009（Flink 2.1.3+ 保留词但无子句生产，A1） |
| `MERGE INTO`（Doris 支持，Flink 语法存在但 planner 不支持） | `MERGE INTO t USING s ON ...` | `:1739-1845` | 语法级 [ASSUMED]：Calcite base 有 `SqlMerge`（`Parser-calcite-1.36.0.jj:1837`），Flink 语法层可能接受；fixture 实测后定（A1 同族） |

**fixture 断言（§10）：** 每个 Flink-only 构造 × doris-4.x 严格/编辑器 → 期望 FATHOM-PARSE-009 + `valid=false`；每个 Doris-only 构造 × flink-2.3.0 严格/编辑器 → 期望 FATHOM-PARSE-009 + `valid=false`；同输入 × 对方方言 → 期望有效或已定义的正例。

## 10. Fixture Plan（positive / negative / incomplete / recovery × strict / editor）

> D-05：fixture 分 positive/negative/incomplete/recovery 四类，冻结为 parity/flink-grammar 快照；来源 = 钉住 release 的 flink-sql-parser grammar + 对应 Calcite 测试。快照命名复用 flink-lexical 形态：`flink-grammar.{fixture}.{profile}.{strict,editor}.json`；Doris 组命名不变。

| 类别 | 内容 | 来源 | 断言 |
|------|------|------|------|
| **positive** | FLINK-02..06 每个语句族 ≥1 条合法 SQL：SELECT（含 CTE/JOIN/聚合/集合运算/`||`/INTERVAL）、INSERT/UPSERT/OVERWRITE、UPDATE/DELETE、EXPLAIN、SHOW CATALOGS/TABLES/COLUMNS/FUNCTIONS/CREATE、DESCRIBE、ANALYZE、CREATE CATALOG/DATABASE/TABLE/VIEW/FUNCTION、CREATE TABLE 全子形式（物理/计算/元数据列、WATERMARK、PRIMARY KEY NOT ENFORCED、PARTITIONED BY、DISTRIBUTED ... INTO n BUCKETS、WITH、LIKE、AS）、Window TVF（TUMBLE/HOP/CUMULATE/SESSION）、MATCH_RECOGNIZE（PATTERN/DEFINE/MEASURES/skip/量词） | `FlinkSqlParserImplTest.java` 的 `.ok(...)` 用例；`MatchRecognizeTest.scala:60-163`；`WindowAggregateITCase.scala:228-297` | `valid=true`；`print_lossless(parse(x))==x`；CST 含目标语句族 kind；strict/editor 形状一致 |
| **negative** | 语法错误 SQL：`SHOW TABLES ^db1^`、`CREATE TABLE t DISTRIBUTED BY ^RANDOM^`、`DISTRIBUTED INTO ^-^3 BUCKETS`、`MATCH_RECOGNIZE (` 缺 DEFINE、`WATERMARK FOR ts` 缺 AS、未知语句 | `FlinkSqlParserImplTest.java` 的 `.fails(...)` 用例（`^...^` 标记期望 error token 位置）；自造 | `valid=false`；诊断 span 定位到 error token；有界恢复步数；strict=精确报错、editor=持续产出可解析子树 |
| **incomplete** | 半成品输入（editor 场景）：`CREATE TABLE t (`, `SELECT * FROM t MATCH_RECOGNIZE (`, `WATERMARK FOR ts AS `, `INSERT INTO t (a,` | 自造（按 grammar 半写） | strict/editor 都产出 Missing/Error/Skipped 节点；`print_lossless==x`；不无限推进（recovery-step cap） |
| **recovery** | 嵌套未闭合 + 后续语句：`SELECT * FROM t MATCH_RECOGNIZE ( PATTERN (A+` + `; SELECT 2`；`CREATE TABLE t (a INT, b` + 下一语句；`TUMBLE(TABLE t, DESCRIPTOR(ts)` 未闭合 | 自造（research flags 明文的 nested recovery 用例） | 恢复停在子语言同步点/`;`；后续语句独立 statement_id 解析；error/skipped span 来源字节可回溯；bounded（depth/recovery cap） |
| **双向负门禁** | §9 矩阵每行 × 双方言：Flink-only 构造 × doris-4.x；Doris-only 构造 × flink-2.3.0（及回归 profile 抽样） | §9 矩阵 | 拒绝方言 → FATHOM-PARSE-009/007 + `valid=false`；对方言 → 已定义正例 |

**快照组：** `parity/fixtures/flink-grammar/`（四类 fixture + manifest.tsv 记录 release/sha512/grammar 行号）+ `parity/__snapshot__/flink-grammar.*.{profile}.{mode}.json`；`parity/flink_grammar_test.mbt` 生成 + 断言（复用 `@test.T::snapshot` + baseline_diff.py + approved-changes.md）。**Doris baseline：** 任何共享 parser/CST 改动前 `moon test --package parity`（无 `--update`）213 快照字节级通过（D-05）。

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| MoonBit toolchain (`moon`, `moonc`) | `moon 0.1.20260724 (5f1406a 2026-07-24)`（Phase 10 本机核验） | Flink grammar/CST/恢复实现 | 唯一实现语言；本阶段零新增运行时依赖 |
| `moonbitlang/core` | 既有锁定版本 | String/Bytes/JSON/utf8/debug | 项目约束：core 是 parser 唯一必需运行时依赖 |
| `@test.T::snapshot` | 官方快照机制（`__snapshot__/` + `moon test --update`） | flink-grammar 快照组 | D-08 门禁复用；字节级失败语义 |
| Python 3 stdlib（本机 3.9.23） | — | 研究时工具：grammar 提取/行号核对、fixture manifest 校验（`scripts/extract_flink_lexical.py` 模式） | release 归档是研究 fixture 而非交付物；stdlib only，零 CI 依赖 |
| git | 2.47.3 | release tag→commit 审计（既有） | Phase 10 已记录 release-2.3.0→`c0f8d1a1...` 等 |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `bash`/`grep`/`comm` | — | 在 `/tmp/flink-research/` 提取 production 行号、对比三 release 语法增量 | 一次性提取/复核；不进入 SDK 运行时或 CI 常驻路径 |
| `parity/baseline_diff.py` | 既有（stdlib） | flink-grammar 快照 shape-diff 报告 | D-04 注册表批准制 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| 独立 Flink 生产函数（同 package 新文件） | 复用/扩展 Doris parser 分支 | Doris 的 table_ref/type/DDL 路径含 Doris-only 构造（PARTITION/TABLET/SAMPLE/OUTFILE/DUPLICATE KEY），扩展必然污染 Doris 接受性（Pitfall 1）；独立生产是唯一零漂移方案 |
| `precedence(context, cursor)` 方言策略表 | 直接往共享 precedence 表加 `||`/`=>` | 加进共享表会改变 Doris 表达式接受（`||` 在 Doris 下现为 symbol 序列），Doris baseline 漂移；策略表让 Doris 分支字节不变 |
| 复用 Doris `parse_query` 全路径 | Flink 重写完整 query parser | `parse_query`/`parse_select_core`/`parse_from` 的骨架（SELECT/CTE/UNION/JOIN 主路径）是方言中立 SQL；但 `parse_table_ref` 的 PARTITION/TABLET/SAMPLE 与 `parse_select_core` 的 INTO OUTFILE/QUALIFY 必须 Flink 分支跳过 |
| 新增 FATHOM-PARSE-009（dialect-negative 诊断） | 复用 FATHOM-PARSE-007 | 007 语义是「unsupported statement in the selected profile」，对「clause/construct 仅其他方言合法」的本地化负门禁语义偏宽；009 更精确，但需 planner 锁定（新 code 是稳定契约，D-04/D-10） |

**Installation:**
```bash
# 本阶段不安装任何新外部包。既有依赖已锁定；release 归档（/tmp/flink-research/）是研究 fixture，不进入交付物。
```

**Version verification:** 本阶段零新增 npm/pypi/crates 依赖；外部事实源为钉住的 release 归档（`/tmp/flink-research/src/flink-{2.3.0,2.1.3,1.20.5}/`，Phase 10 已校验和复核）——三 release 的 Calcite pin（1.36.0/1.34.0/1.32.0）与 parser 配置（Lex.JAVA + identifierMaxLength 256 + FlinkSqlConformance.DEFAULT）见 Phase 10 RESEARCH §7/§8，本 session 复用不改写。

## Package Legitimacy Audit

> 本阶段不安装任何外部包（约束：核心 parser 只用 `moonbitlang/core`；提取工具为 Python stdlib）。无需运行 package-legitimacy seam；下表为显式确认。

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| （无新增包） | — | — | — | — | — | N/A — 零外部依赖 |

**Packages removed due to [SLOP] verdict:** none（无候选包）
**Packages flagged as suspicious [SUS]:** none（无候选包）

## Architecture Patterns

### System Architecture Diagram

```text
Public boundary: fathom-sql parse|format|lsp --dialect flink --profile flink-2.3.0 / fathom-lsp / JS-Wasm
                              │ fathom.parse.v1 / fathom.error.v1（dialect/profile 在 metadata）
┌─────────────────────────────▼──────────────────────────────┐
│ api/  ParseOptions(dialect_id, profile_id, mode_id)         │
│       Flink branch 解锁（Phase 10）；ParseResult.root 自动携带新语句族 │
└─────────────────────────────┬──────────────────────────────┘
                              │ context
┌─────────────────────────────▼──────────────────────────────┐
│ parser/parser.mbt  parse_with_limits_context → parse_segment(:3336) │
│   match context.dialect { Doris → parse_doris_segment       │
│                           Flink → parse_flink_segment }     │  ← Phase 11 替换 008
│  parse_flink_segment：关键字分发                              │
│   ├─ SELECT/WITH → 共享 query skeleton（Flink 安全子集）       │
│   ├─ INSERT/UPSERT → parse_flink_insert（RichSqlInsert 映射） │
│   ├─ UPDATE/DELETE → parse_flink_update/delete              │
│   ├─ EXPLAIN → parse_flink_explain；SHOW → parse_flink_show  │
│   ├─ DESCRIBE/DESC → parse_flink_describe                   │
│   ├─ ANALYZE → parse_flink_analyze                          │
│   ├─ CREATE → parse_flink_create（catalog/database/table/view/function）│
│   ├─ ALTER/DROP → parse_flink_alter/drop                    │
│   └─ USE/SET/RESET → parse_flink_use/set/reset              │
└──────────────┬───────────────────────────────┬──────────────┘
               │ 共享原语（同 package，字节不变）  │ 新增 Flink 生产
┌──────────────▼───────────────┐  ┌────────────▼──────────────┐
│ expression.mbt（Pratt engine）│  │ parser/flink_grammar.mbt  │
│ precedence(context, cursor)   │  │ CREATE TABLE 四类列/      │
│   Doris 分支：现表不变         │  │  Watermark/Constraint/    │
│   Flink 分支：+ || =>         │  │  Distribution/Like/As     │
│ query skeleton（Flink 子集）  │  │ MATCH_RECOGNIZE 子语言    │
│ recovery/sync/budgets 共享     │  │ Window TVF table-ref      │
└──────────────┬───────────────┘  └────────────┬──────────────┘
               │ context                        │
┌──────────────▼───────────────────────────────▼──────────────┐
│ syntax/（SyntaxKind 增 Flink 语句族） + source/（span/trivia）│
│ error/missing/skipped + lossless replay（CST-01）             │
└──────────────┬───────────────────────────────┬──────────────┘
               │ context                        │
┌──────────────▼───────────────┐  ┌────────────▼──────────────┐
│ dialect/flink.mbt            │  │ parity/ flink-grammar 快照 │
│ FlinkProfile + 分类行（+MATCH_RECOGNIZE 行）│  fixtures（pos/neg/incomplete/recovery × strict/editor）
│ + 双向负门禁 fixture 冲突矩阵  │  │ baseline 213 快照零漂移    │
└──────────────────────────────┘  └───────────────────────────┘
```

### Recommended Project Structure（新增/变更部分）

```text
parser/
├── parser.mbt                  # 共享：parse_segment 路由（不变）、parse_flink_segment 改真实分发、
│                               #   precedence(context, cursor) 方言策略表、共享 query/expression 原语
├── flink_grammar.mbt           # 新增：Flink 语句族生产（DML/辅助/DDL/CREATE TABLE/TVF/MATCH_RECOGNIZE）
│                               #   + Flink 子语言同步点/恢复边界谓词
syntax/
├── syntax.mbt                  # SyntaxKind 增：CreateCatalog/CreateDatabase/CreateFunction/Drop*/Alter*/
│                               #   ShowStatement/DescribeStatement/ExplainStatement/AnalyzeStatement/
│                               #   WatermarkClause/ComputedColumn/MetadataColumn/PrimaryKeyClause/
│                               #   TableLikeClause/WindowTvf/MatchRecognize（命名由 planner 定稿）
api/
├── api.mbt                     # kind_id（:331-357）增新 kind 的 wire 字符串（D-02 one-way 契约）
dialect/
├── flink.mbt                   # 增 MATCH_RECOGNIZE 等缺失保留字行（见 §4 发现）；可选 FlinkFeature（版本 gate）
parity/
├── fixtures/flink-grammar/     # positive/negative/incomplete/recovery 四类 fixture + manifest.tsv
├── fixtures/flink-negative/    # 双向负门禁冲突矩阵 fixture（flink-only × doris / doris-only × flink）
├── __snapshot__/               # flink-grammar.{fixture}.{profile}.{strict,editor}.json（独立命名，与 Doris 组不重叠）
└── flink_grammar_test.mbt      # 快照生成 + 双向负门禁断言
scripts/
└── extract_flink_grammar.py    # （研究时）release 归档 → production 行号/关键字/fixture 提取（stdlib）
```

### Pattern 1: `parse_flink_segment` 真实关键字分发（D-04/D-06）

**What:** 把 `parse_flink_segment`（`parser/parser.mbt:3405-3429`，现全量 FATHOM-PARSE-008）改为按首 significant token 分发到 Flink 语句族生产；未知 starter 走 `unsupported_statement`（FATHOM-PARSE-007，`:3163-3175`）。**When to use:** 这是 Flink grammar 的唯一语句级入口；与 `parse_doris_segment`（`:3354-3403`）并列，绝不散落 `if dialect == Flink`（Pitfall 2）。

```moonbit
// 骨架 — 具体语句族由 planner 按 §5 映射拆任务；同 package 可访问 parser.mbt 私有原语
fn parse_flink_segment(stream, start_index, end_index, statement_id, state, context) -> @syntax.SyntaxNode {
  let span = segment_span(stream, start_index, end_index)
  let indices = significant_indices(stream, start_index, end_index)
  let cursor = { stream, indices, position: 0, depth: 0 }
  match indices.get(0) { None => /* trivia-only segment */; Some(first) =>
    match stream.raw(first) {
      // FLINK-02 核心查询：共享 query skeleton 的 Flink 安全子集（Pitfall 7 防污染）
      Some(raw) if bytes_equal_ci(raw, b"SELECT") => finish_statement(..., parse_flink_query(...), ..., SyntaxKind::Select, ...)
      Some(raw) if bytes_equal_ci(raw, b"WITH") => /* with_prefix_verb 后按 SELECT/UPDATE/DELETE 分发 */
      // FLINK-02 DML/辅助
      Some(raw) if bytes_equal_ci(raw, b"INSERT") || bytes_equal_ci(raw, b"UPSERT") => parse_flink_insert(...)
      Some(raw) if bytes_equal_ci(raw, b"UPDATE") => parse_flink_update(...)
      Some(raw) if bytes_equal_ci(raw, b"DELETE") => parse_flink_delete(...)
      Some(raw) if bytes_equal_ci(raw, b"EXPLAIN") => parse_flink_explain(...)
      Some(raw) if bytes_equal_ci(raw, b"SHOW") => parse_flink_show(...)
      Some(raw) if bytes_equal_ci(raw, b"DESCRIBE") || bytes_equal_ci(raw, b"DESC") => parse_flink_describe(...)
      Some(raw) if bytes_equal_ci(raw, b"ANALYZE") => parse_flink_analyze(...)
      // FLINK-03 DDL
      Some(raw) if bytes_equal_ci(raw, b"CREATE") => parse_flink_create(...)   // catalog/database/table/view/function
      Some(raw) if bytes_equal_ci(raw, b"ALTER") => parse_flink_alter(...)
      Some(raw) if bytes_equal_ci(raw, b"DROP") => parse_flink_drop(...)
      Some(raw) if bytes_equal_ci(raw, b"USE") => parse_flink_use(...)
      Some(raw) if bytes_equal_ci(raw, b"SET") || bytes_equal_ci(raw, b"RESET") => parse_flink_set_reset(...)
      _ => unsupported_statement(stream, start_index, end_index, span, state, statement_id)
    }
  }
}
```

### Pattern 2: Flink CREATE TABLE（FLINK-04）独立生产

**What:** 按 `SqlCreateTable`（`parserImpls.ftl:1585-1712`）子句顺序实现独立 parser，Doris `parse_create_table`（`parser.mbt:2426-2529`）与 `parse_column_definition`（`:2570-2665`）不共享。**When to use:** FLINK-04；列体四类列 + 表级子句。

```text
CREATE [TEMPORARY] TABLE [IF NOT EXISTS] name
  [ ( column_defs ) ]
  [ COMMENT '...' ]
  [ DISTRIBUTED [ BY [HASH|RANGE] (cols) ] [ INTO n BUCKETS ] ]   ← SqlDistribution(:1560)
  [ PARTITIONED BY (cols) ]                                          ← ParenthesizedSimpleIdentifierList
  [ WITH ( 'k' = 'v', ... ) ]                                        ← Properties(:1520)
  [ LIKE table [ ( INCLUDING|EXCLUDING|OVERWRITING <feature> ... ) ] ← SqlTableLike(:1714)
  | AS query ]                                                       ← SqlCreateTableAs/SqlReplaceTableAs
column_defs := TypedColumn | MetadataColumn | ComputedColumn | TableConstraint | Watermark   ← TableColumn(:1103)
```

### Pattern 3: MATCH_RECOGNIZE 子语言独立 parser（FLINK-06）

**What:** 实现 `parse_match_recognize`（table-ref 后缀，对应 Calcite `MatchRecognize(SqlNode tableRef)`，`Parser.jj:3062-3183`），产生语法级 CST（PATTERN/DEFINE/MEASURES/skip/变量/量词），不解析为 planner 语义。**When to use:** FLINK-06；独立同步点与恢复边界（Pitfall 4/8）。

```text
MATCH_RECOGNIZE (
  [ PARTITION BY expr_list ]                                        ← :3091
  [ ORDER BY order_item_list ]                                      ← :3095
  [ MEASURES measure_column_comma_list ]                            ← :3101-3103
  [ ONE ROW PER MATCH | ALL ROWS PER MATCH ]                        ← :3108-3115
  [ AFTER MATCH SKIP [ TO NEXT ROW | TO FIRST var | TO LAST var | PAST LAST ROW ] ] ← :3123-3154
  PATTERN ( pattern_expr )                                          ← :3157-3176（含 ^ 起始/结束锚）
  [ WITHIN INTERVAL literal ]                                       ← :3170
  DEFINE var AS expr_comma_list                                     ← :3177-3178
)
pattern_expr := pattern_concatenation ('|' pattern_concatenation)*     ← :3218 PATTERN_ALTER
              := pattern_factor (pattern_factor)*                      ← :3236 PATTERN_CONCAT
              := var [ quantifier ] | ( pattern_expr ) | {...} | <-...> ← PatternFactor/PatternQuantifier(:3314)
quantifier   := {n} | {n,} | {n,m} | {,m} | + | * | ?   [ 后缀 ? 表示 reluctant ]  ← :3314-3317
```

### Pattern 4: `precedence(context, cursor)` 方言表达式策略表

**What:** 把共享 Pratt 的 `precedence()`（`parser.mbt:263-274`）改为按 `context.dialect` 选择策略；Doris 分支返回现有表（字节不变），Flink 分支增补 `||`（CONCAT，Flink token `Parser.jj:8793`）、`=>`（NAMED_ARGUMENT_ASSIGNMENT，`:8794`）等。**When to use:** 表达式解析（FLINK-02 表达式）；这是「共享 Pratt engine + dialect policy table」的落地（ARCHITECTURE.md 结论）。

```moonbit
// 骨架 — Doris 分支逐字保持现有 precedence 表（Pitfall 7：禁止改共享表）
fn precedence(context : @dialect.DialectContext, cursor : Cursor) -> Int? {
  match context.dialect {
    @dialect.Dialect::Doris => /* 现表逐字不变（:263-274） */
    @dialect.Dialect::Flink => match raw_at(cursor) {
      Some(raw) if bytes_equal_ci(raw, b"OR") => Some(1)
      Some(raw) if bytes_equal_ci(raw, b"AND") => Some(2)
      Some(raw) if raw == b"||" => Some(3)          // CONCAT（Calcite 优先级介于比较与算数之间）
      Some(raw) if raw == b"=" || ... => Some(4)     // 比较
      Some(raw) if raw == b"+" || raw == b"-" => Some(5)
      Some(raw) if raw == b"*" || raw == b"/" || raw == b"%" => Some(6)
      _ => None
    }
  }
}
```

### Anti-Patterns to Avoid

- **把 Flink 语句塞进 Doris parser 分支**：`parse_doris_segment` 的 SELECT/INSERT/CREATE 分支各自是冻结行为，任何共享分支改动都需 213 快照证明零漂移（Pitfall 1）。
- **给 Flink 复用 Doris 的 `parse_table_ref`/`parse_column_type`**：两者含 TABLET/SAMPLE/TABLESAMPLE/OUTFILE/DUPLICATE KEY 等 Doris-only 构造；复用会把 Doris 接受性泄漏给 Flink（Pitfall 2）。
- **在共享 precedence 表直接加 `||`**：`||` 在 Doris 下现为两个 symbol token；改共享表会改变 Doris 表达式 token 消费（Pitfall 7）。
- **MATCH_RECOGNIZE 全量 planner 化**：FLINK-06 明文「不声称 planner/执行等价」；pattern 变量的列作用域解析（`A.price` 需知道 A 是模式变量、price 是列）是 planner 前置，语法级只保结构不校验作用域（Pitfall 6）。
- **对半成品 MATCH_RECOGNIZE/PATTERN 做无限推进恢复**：嵌套括号 + 量词组合易触发恢复无限循环；必须用 `consume_recovery_step`/`depth_allowed` 预算（Pitfall 8）。

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| 表达式运算符优先级（`||`/`=>`/比较/算数） | 为 Flink 另写一个表达式 parser | 共享 Pratt engine + `precedence(context, cursor)` 方言策略表 | 一个 engine 保持 span/trivia/恢复保证一致；策略表只改 Flink 分支，Doris 字节不变 |
| 恢复预算（recovery-step cap、depth cap、max_diagnostics） | 为 Flink 复制一套恢复状态机 | 共享 `RecoveryState`/`consume_recovery_step`/`depth_allowed`/`finish_statement` | CST-01/D-03 要求双方言同一有界纪律；恢复步数与诊断上限共享 |
| 分号分段/statement_id/trivia segment/root 装配 | 为 Flink 重写文档分段 | 共享 `parse_with_limits_context`（`:3487`） | 分段/root/statement_id 是方言中立；Flink 只替换 `parse_segment` 内部分发 |
| 无损回放（lossless replay） | 为 Flink 新写 printer | 共享 `print_lossless`（syntax/source） | CST-01 要求字节级 round-trip；CST 结构不变则 printer 不变 |
| 关键字分类/保留字判定 | 在 parser 内散落 Flink 词表 | `dialect/classification.mbt` 的 `classification_of(context, raw)` + flink 行表 | DIALECT-02 独立行表；禁止 parser 内第二份词表 |

**Key insight:** Flink 与 Doris 共享的应是「机制」（token/CST/Pratt 引擎/恢复预算/分段/回放），而非「语法决策」（table-ref 选项、类型集、DDL 子句、运算符优先级）。机制共享保证 CST-01 与恢复纪律一致；语法决策隔离保证 DIALECT-03 双向负门禁与 Doris 零漂移。

## Runtime State Inventory

> Phase 11 含一个明确的行为变更点：`parse_flink_segment` 的 FATHOM-PARSE-008 退役（D-06）。该变更影响诊断 code 面与既有测试，需显式清点；其余五类显式回答。

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — 无数据库/键值存储涉及 Flink 语句族 | none |
| Live service config | None — SDK 无外部服务；`fathom.capabilities.v1` 的 flink profile 面已在 Phase 10 填充 | none |
| OS-registered state | None — 无 Task Scheduler/pm2/systemd 注册项涉及 flink grammar | none |
| Secrets/env vars | None — 无 .env/CI 变量以 flink 语句族命名 | none |
| Build artifacts / 代码内行为契约 | **FATHOM-PARSE-008 退役（D-06）**：`parse_flink_segment`（`parser/parser.mbt:3405-3429`）现为唯一 008 生产者；`parser.mbt:3624-3628` 的测试断言 `parsed.diagnostics[0].code == "FATHOM-PARSE-008"`（`flink` 分支 not-implemented 测试）。008 不再用于合法 flink SQL。**处置建议**：移除 008 生产路径与对应测试（clean cutover，D-06）；**008 code 保留空缺不复用**（避免与历史上已见 008 的消费者混淆，同 `DORIS-PARSE-005` 空缺惯例）；Phase 11 中真正不支持的 Flink 语句（MATERIALIZED TABLE/CONNECTION/MODEL/STATEMENT SET/EXECUTE/COMPILE/LOAD/UNLOAD MODULE/JAR/Job）走既有 FATHOM-PARSE-007 unsupported-statement 路径（`:3163-3175`） | code edit（删 008 路径 + 更新测试）+ 诊断 code 面记录 |

**Nothing found in category:** Stored data / Live service config / OS-registered state / Secrets（显式「None」如上）。

## Common Pitfalls

### Pitfall 1: Doris 回归零漂移被 Flink grammar 改造打破
**What goes wrong:** 共享 `parse_query`/`parse_from`/`parse_expression`/`precedence` 的改动误改 Doris 路径；或 `doris_classification_rows` 116 行被触碰；或 `syntax.mbt` SyntaxKind 枚举扩展后 `kind_id` 映射错位导致 Doris wire 输出变化。
**Why it happens:** 多方言重构「顺手统一」最易在共享函数内改分支；Doris 213 个 parity 快照 + `kind_id`（`api/api.mbt:331-357`）是敏感面。
**How to avoid:** 每个共享函数改动都显式 `match context.dialect`，Doris 分支保持原字节路径；`moon test --package parity`（无 `--update`）字节级门禁；任何 Doris 变更走 approved-changes.md 注册（D-08）。**Warning signs:** Doris 快照 diff 出现非注册变更；`kind_id` 增加/重排了既有 kind 的 wire 字符串。

### Pitfall 2: 用 Flink grammar 污染 Doris 或反之（DIALECT-03 负门禁失效）
**What goes wrong:** `WATERMARK FOR ts AS ...`、`MATCH_RECOGNIZE`、`FROM TUMBLE(...)`、`PRIMARY KEY NOT ENFORCED` 在 Doris 模式被误接受；`DISTRIBUTED BY HASH(...) BUCKETS n`、`DUPLICATE KEY`、`INTO OUTFILE`、`TABLET` 在 Flink 模式被误接受。
**Why it happens:** 共享 `parse_table_ref`/`parse_select_core`/`parse_create_table` 被 Flink 分支复用，Doris-only 构造点未设负门禁。
**How to avoid:** 每个 Flink-only / Doris-only 构造点在各自 parser 显式拒绝（双向负门禁矩阵见 §9）；fixture 覆盖双方言 × 正/负四类（§10）。**Warning signs:** 同一 SQL 在两种方言都 valid；负门禁 fixture 缺某一方向。

### Pitfall 3: release 间 grammar 分歧被忽略（回归 profile）
**What goes wrong:** flink-1.20.5（Calcite 1.32.0）与 2.1.3/2.3.0 的 grammar 差异被当作「同一 Flink」：`E'..'` 仅 1.34.0+（Phase 10 已核验）；`QUALIFY`/`VARIANT` 仅 2.1.3+；MATCH_RECOGNIZE/WINDOW TVF 的 production 行号三 release 偏移。
**Why it happens:** 以 flink-2.3.0 为主实现后，回归 profile 的 fixture 期望复用主 profile。
**How to avoid:** 每个 Flink 语句族按 profile 记录 grammar 差异（本文件 §5 行号均标 release）；fixture 命名含 profile（`flink-grammar.{fixture}.{profile}.{mode}.json`）；`E'..'` 走 `FlinkProfile::supports_escape_literal` 已有 gate。**Warning signs:** 1.20.5 fixture 与 2.3.0 共用同一 grammar 断言而无 profile 分支。

### Pitfall 4: MATCH_RECOGNIZE/PATTERN 恢复无限循环或吞 token
**What goes wrong:** 半成品 `MATCH_RECOGNIZE (` 或 `PATTERN (A+` 在恢复时找不到子语言边界，一路吞到语句尾/下一语句，恢复步数爆掉或产生非有界 CST。
**Why it happens:** MATCH_RECOGNIZE 是嵌套子语言（`Parser.jj:3062-3346`），`DEFINE`/`MEASURES` 内又是完整表达式；缺少独立同步点。
**How to avoid:** 独立 `parse_match_recognize` 生产 + 子语言 clause 边界谓词（`MEASURES`/`ONE ROW`/`ALL ROWS`/`AFTER MATCH`/`PATTERN`/`DEFINE`/`)`）；共享 `consume_recovery_step`/`depth_allowed` 预算；recovery fixture 覆盖嵌套未闭合（§10）。**Warning signs:** `SELECT * FROM t MATCH_RECOGNIZE (` 挂起或消耗超限；恢复步数诊断频繁触发。

### Pitfall 5: 用移动文档/folklore 替代钉住 release grammar
**What goes wrong:** 从 `nightlies`/`dev` 文档抄 SHOW/DESCRIBE/TVF 语法，或凭「我记得 Flink 支持 X」实现。
**Why it happens:** 钉住 grammar 文件大（`parserImpls.ftl` 97.5KB / `Parser.jj` 245.3KB），提取耗力。
**How to avoid:** 每个 production 从 `/tmp/flink-research/src/flink-2.3.0/flink-table/flink-sql-parser/src/main/codegen/`（`data/Parser.tdd`/`includes/parserImpls.ftl`/`templates/Parser.jj`）逐字引用行号（§5）；Calcite base 生产从 `/tmp/flink-research/Parser-calcite-1.36.0.jj` 引用。**Warning signs:** RESEARCH 中的 production 无行号或行号不对应；fixture 期望来自「我记得」。

### Pitfall 6: MATCH_RECOGNIZE planner 前置过度实现
**What goes wrong:** 对 pattern 变量做列作用域/类型校验（`A.price` 中 A 是模式变量、price 是列），把 planner 语义塞进语法 parser。
**Why it happens:** MATCH_RECOGNIZE 的 `MEASURES`/`DEFINE` 表达式看起来可校验；FLINK-06 明文禁止 planner 等价。
**How to avoid:** 语法级只解析结构（变量名、量词、表达式语法）并保留 source-backed 节点；作用域/类型留给未来 analyzer（TOOL-03/FLINK-FUTURE-01）。**Warning signs:** parser 因「未定义模式变量」拒绝语法上合法的 MATCH_RECOGNIZE。

### Pitfall 7: 共享表达式/类型解析被 Flink 污染
**What goes wrong:** `precedence()` 直接加 `||`/`=>`；或 `parse_column_type` 加 Flink 类型（`TIMESTAMP_LTZ`/`ROW<>`/`MAP<>`）导致 Doris 接受性变化。
**Why it happens:** 共享 Pratt/类型 parser 是单一函数，最易「顺手扩展」。
**How to avoid:** `precedence(context, cursor)` 方言策略表（Pattern 4）；Flink 类型走独立 `parse_flink_data_type`（映射 `dataTypeParserMethods`，`Parser.tdd:759-765`：ExtendedSqlBasicTypeName/CustomizedCollectionsTypeName/SqlMapTypeName/SqlRawTypeName/ExtendedSqlRowTypeName/SqlStructuredTypeName/SqlBitmapTypeName）。**Warning signs:** Doris 表达式/类型 fixture 增加非注册接受；`||` 在 Doris 下被当作单个 CONCAT token 消费。

### Pitfall 8: Window TVF 输出列与 legacy 分组窗口混淆
**What goes wrong:** 把 `TUMBLE_START()/TUMBLE_ROWTIME()`（legacy grouped windowing 函数）当成 Window TVF 输出列；TVF 输出列是 `window_start/window_end/window_time`（`WindowAggregateITCase.scala:250-263`）。
**Why it happens:** 两者都含 TUMBLE；文档/示例混用。
**How to avoid:** TVF 是 FROM 子句 table-function（`FROM TUMBLE(TABLE t, DESCRIPTOR(ts), INTERVAL '1' SECOND)`），输出列 `window_start/end/time` 是普通标识符；`TUMBLE_START/ROWTIME` 是表达式层的函数调用（legacy，非本阶段范围，若出现在 SELECT 按普通函数解析）。**Warning signs:** fixture 把 `TUMBLE_START(rowtime, interval '3' second)` 当作 TVF 输出列断言。

### Pitfall 9: 遗漏的关键字行导致 Flink 保留字被当标识符
**What goes wrong:** `MATCH_RECOGNIZE` 是 Calcite base 保留字 token（`Parser-calcite-1.36.0.jj:8214`），但**不在 Phase 10 的 `flink-2.3.0-reserved.txt` 中**（本 session 核验：grep 无 `MATCH_RECOGNIZE`/`RECOGNIZE` 命中，且 `flink.mbt` 行表无该行）——`classification_of(flink, "MATCH_RECOGNIZE")` 返回 None，会被当作普通标识符接受，与 Flink parser 的保留字行为不一致。
**Why it happens:** Phase 10 行表是「production/conflict 词 + 冲突词」子集（142 行），提取范围未覆盖 Calcite base 的多词/下划线 token。
**How to avoid:** Phase 11 在 `dialect/flink.mbt` 补 `MATCH_RECOGNIZE`（Reserved，source=`flink-sql-parser Parser-calcite-1.36.0.jj:8214 (MATCH_RECOGNIZE)`）及 parser 实际消费的其它缺失词（对照 `flink-2.3.0-reserved.txt` 全表差集，逐词核验）；保留字词必须能反引号引用（`SELECT \`MATCH_RECOGNIZE\``）。**Warning signs:** `MATCH_RECOGNIZE` 作为列名被 Flink 接受；`classification_of` 对保留字返回 None。

## Code Examples

### 1. Flink 语句入口（`codegen/data/Parser.tdd:651-727`，statementParserMethods 前 20 行逐字）

```text
  statementParserMethods: [
    "RichSqlInsert()"
    "SqlBeginStatementSet()"
    "SqlEndStatementSet()"
    "SqlLoadModule()"
    "SqlShowCatalogs()"
    "SqlShowCurrentCatalogOrDatabase()"
    "SqlDescribeCatalog()"
    "SqlUseCatalog()"
    "SqlShowDatabases()"
    "SqlUseDatabase()"
    "SqlAlterCatalog()"
    "SqlAlterDatabase()"
    "SqlDescribeDatabase()"
    "SqlAlterFunction()"
    "SqlShowFunctions()"
    "SqlShowModels()"
    "SqlShowConnections()"
    "SqlShowTables()"
    ...
```
`[VERIFIED: /tmp/flink-research/src/flink-2.3.0/flink-table/flink-sql-parser/src/main/codegen/data/Parser.tdd:651-669 — 上述逐字（完整列表至 :727，含 SqlRichDescribeTable 在最后）]`

### 2. Calcite base `SqlStmt` 分发（`codegen/templates/Parser.jj:1140-1185` 逐字节选）

```java
SqlNode SqlStmt() :
{
    SqlNode stmt;
}
{
    (
<#-- Add methods to parse additional statements here -->
<#list (parser.statementParserMethods!default.parser.statementParserMethods) as method>
        LOOKAHEAD(2) stmt = ${method}
    |
</#list>
        stmt = SqlSetOption(Span.of(), null)
    |
        stmt = SqlAlter()
    |
<#if (parser.createStatementParserMethods!default.parser.createStatementParserMethods)?size != 0>
        stmt = SqlCreate()
    |
</#if>
<#if (parser.dropStatementParserMethods!default.parser.dropStatementParserMethods)?size != 0>
        stmt = SqlDrop()
    |
</#if>
<#if (parser.truncateStatementParserMethods!default.parser.truncateStatementParserMethods)?size != 0>
        LOOKAHEAD(2)
        stmt = SqlTruncate()
    |
</#if>
        stmt = OrderedQueryOrExpr(ExprContext.ACCEPT_QUERY)
    |
        stmt = SqlExplain()
    |
        stmt = SqlDescribe()
    |
        stmt = SqlInsert()
    |
        stmt = SqlDelete()
    |
        stmt = SqlUpdate()
    |
        stmt = SqlMerge()
    |
        stmt = SqlProcedureCall()
    )
    {
        return stmt;
    }
}
```
`[VERIFIED: /tmp/flink-research/src/flink-2.3.0/flink-table/flink-sql-parser/src/main/codegen/templates/Parser.jj:1140-1185 — 上述逐字]`

### 3. Flink CREATE TABLE 主生产（`parserImpls.ftl:1585-1712` 逐字节选）

```java
SqlCreate SqlCreateTable(Span s, boolean replace, boolean isTemporary) :
{
    ...
}
{
    <TABLE>

    ifNotExists = IfNotExistsOpt()

    tableName = CompoundIdentifier()
    [
        <LPAREN> { pos = getPos(); TableSchemaContext ctx = new TableSchemaContext();}
        TableColumnsOrIdentifiers(pos, ctx)
        {
            pos = pos.plus(getPos());
            isColumnsIdentifiersOnly = ctx.isColumnsIdentifiersOnly();
            columnList = new SqlNodeList(ctx.columnList, pos);
            constraints = ctx.constraints;
            watermark = ctx.watermark;
        }
        <RPAREN>
    ]
    [ <COMMENT> <QUOTED_STRING> {
          comment = Comment();
    }]
    [
        <DISTRIBUTED>
        distribution = SqlDistribution(getPos())
    ]

    [
        <PARTITIONED> <BY>
        partitionColumns = ParenthesizedSimpleIdentifierList()
    ]
    [
        <WITH>
        propertyList = Properties()
    ]
    [
        <LIKE>
        tableLike = SqlTableLike(getPos())
        {
            ...
            return new SqlCreateTableLike(startPos.plus(getPos()), ...);
        }
    |
        <AS>
        asQuery = OrderedQueryOrExpr(ExprContext.ACCEPT_QUERY)
        {
            ...
            return new SqlCreateTableAs(startPos.plus(getPos()), ...);
        }
    ]
    ...
}
```
`[VERIFIED: /tmp/flink-research/src/flink-2.3.0/flink-table/flink-sql-parser/src/main/codegen/includes/parserImpls.ftl:1585-1712 — 上述逐字；子句顺序 `[COMMENT][DISTRIBUTED][PARTITIONED BY][WITH][LIKE|AS]` 是 FLINK-04 的权威顺序]`

### 4. Flink 列体四类列 + Watermark（`parserImpls.ftl:1103-1145` 逐字节选）

```java
void TableColumn(TableSchemaContext context) :
{
    SqlTableConstraint constraint;
}
{
    (
        LOOKAHEAD(2)
        TypedColumn(context)
    |
        constraint = TableConstraint() {
            context.constraints.add(constraint);
        }
    |
        ComputedColumn(context)
    |
        Watermark(context)
    )
}

void Watermark(TableSchemaContext context) :
{
    SqlIdentifier eventTimeColumnName;
    SqlParserPos pos;
    SqlNode watermarkStrategy;
}
{
    <WATERMARK> {pos = getPos();} <FOR>
    eventTimeColumnName = CompoundIdentifier()
    <AS>
    watermarkStrategy = Expression(ExprContext.ACCEPT_NON_QUERY) {
        if (context.watermark != null) {
            throw SqlUtil.newContextException(pos,
                ParserResource.RESOURCE.multipleWatermarksUnsupported());
        } else {
            context.watermark = new SqlWatermark(pos, eventTimeColumnName, watermarkStrategy);
        }
    }
}
```
`[VERIFIED: /tmp/flink-research/src/flink-2.3.0/flink-table/flink-sql-parser/src/main/codegen/includes/parserImpls.ftl:1103-1140 — 上述逐字；TypedColumn/MetadataColumn/ComputedColumn/RegularColumn 生产在 :1146-1330]`

### 5. MATCH_RECOGNIZE 生产（`codegen/templates/Parser.jj:3062-3183` 逐字节选）

```java
/**
 * Parses a MATCH_RECOGNIZE clause following a table expression.
 */
SqlMatchRecognize MatchRecognize(SqlNode tableRef) :
{
    ...
}
{
    ...
    <MATCH_RECOGNIZE> { s = span(); checkNotJoin(tableRef); } <LPAREN>
    (
        <PARTITION> { s2 = span(); } <BY>
        partitionList = ExpressionCommaList(s2, ExprContext.ACCEPT_NON_QUERY)
        |
        { partitionList = SqlNodeList.EMPTY; }
    )
    ...
    (
        <MEASURES>
        measureList = MeasureColumnCommaList(span())
    |
        { measureList = SqlNodeList.EMPTY; }
    )
    ...
        <ONE> { s0 = span(); } <ROW> <PER> <MATCH> { rowsPerMatch = ...ONE_ROW...; }
    |
        <ALL> { s0 = span(); } <ROWS> <PER> <MATCH> { rowsPerMatch = ...ALL_ROWS...; }
    |   { rowsPerMatch = null; }
    ...
        <AFTER> <MATCH> <SKIP>
        ( ... <NEXT> <ROW> { after = ...SKIP_TO_NEXT_ROW...; }
          | ... <FIRST> var = SimpleIdentifier() { after = ...SKIP_TO_FIRST...; }
          | ... <LAST> var = SimpleIdentifier() { after = ...SKIP_TO_LAST...; }
          | ... <PAST> <LAST> <ROW> { after = ...SKIP_PAST_LAST_ROW...; } )
    ...
    <PATTERN>
    <LPAREN>
    ( <CARET> { isStrictStarts = SqlLiteral.createBoolean(true, getPos()); } )?
    pattern = PatternExpression()
    ( <DOLLAR> { isStrictEnds = ...; } )?
    <RPAREN>
    [ <WITHIN> interval = IntervalLiteral() ]
    <DEFINE>
    patternDefList = PatternDefinitionCommaList(span())
    <RPAREN> {
        return new SqlMatchRecognize(s.end(this), tableRef,
            pattern, isStrictStarts, isStrictEnds, patternDefList, measureList,
            after, subsetList, rowsPerMatch, partitionList, orderList, interval);
    }
    ...
}
```
`[VERIFIED: /tmp/flink-research/src/flink-2.3.0/flink-table/flink-sql-parser/src/main/codegen/templates/Parser.jj:3062-3183 — 上述逐字（含 `:3170 <WITHIN> interval = IntervalLiteral()`、`:3177 <DEFINE>`）；Calcite base 生成版 `Parser-calcite-1.36.0.jj:3018-3300` 同构]`

### 6. Window TVF 真实 SQL（钉住 release 的 planner 测试，非 parser 测试）

```scala
// WindowAggregateITCase.scala — TUMBLE TVF with offset
verifyWindowAgg("TUMBLE(TABLE T1, DESCRIPTOR(rowtime), INTERVAL '1' DAY, INTERVAL '8' HOUR)", expected)
// HOP TVF
"TUMBLE(TABLE T1, DESCRIPTOR(rowtime), INTERVAL '30' SECONDS, INTERVAL '15' SECONDS)"
// TVF output columns
|  window_start,
|  window_end,
|    GROUP BY `name`, window_start, window_end
```
`[VERIFIED: /tmp/flink-research/src/flink-2.3.0/flink-table/flink-table-planner/src/test/scala/org/apache/flink/table/planner/runtime/stream/sql/WindowAggregateITCase.scala:228-263 — TUMBLE/HOP TVF 参数（TABLE + DESCRIPTOR + 一个/两个 INTERVAL 参数）与 `window_start/window_end` 输出列]`

```scala
// MatchRecognizeTest.scala — FROM t MATCH_RECOGNIZE (...) AS T 后接 Window TVF
SELECT *
FROM TABLE(TUMBLE(TABLE T, DESCRIPTOR(matchRowtime), INTERVAL '3' second))
```
`[VERIFIED: /tmp/flink-research/src/flink-2.3.0/flink-table/flink-table-planner/src/test/scala/org/apache/flink/table/planner/plan/stream/sql/MatchRecognizeTest.scala:141-148 — MATCH_RECOGNIZE 结果表作为 TVF 输入；`MATCH_RECOGNIZE` 块含 PARTITION BY/ORDER BY/MEASURES/ONE ROW PER MATCH/PATTERN/DEFINE（:60-163）]`

### 7. 现状 `parse_flink_segment`（`parser/parser.mbt:3405-3429`，Phase 11 替换目标）

```moonbit
fn parse_flink_segment(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
  statement_id : UInt,
  state : RecoveryState,
  context : @dialect.DialectContext,
) -> @syntax.SyntaxNode {
  let span = segment_span(stream, start_index, end_index)
  add_diagnostic(
    state,
    "FATHOM-PARSE-008",
    "flink grammar is not yet implemented in this release",
    "statement",
    span,
    statement_id,
  )
  let error = require_node(@syntax.SyntaxNode::new(
    @syntax.SyntaxKind::Error,
    span,
    segment_children(stream, start_index, end_index),
  ))
  require_node(@syntax.SyntaxNode::new(@syntax.SyntaxKind::Statement, span, [@syntax.SyntaxElement::ChildNode(error)]))
}
```
`[VERIFIED: /opt/source/Fathom/parser/parser.mbt:3405-3429 — 上述逐字；`parse_segment` 路由在 :3336-3351，`parse_doris_segment` 在 :3354-3403]`

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `parse_flink_segment` 全量 FATHOM-PARSE-008 拒绝（Phase 9/10 占位） | 真实 Flink 语句级 grammar（Phase 11，D-06） | Phase 11 | Flink 分支从「全拒」变为「真实解析 + 双向负门禁」；008 退役 |
| Flink 关键字分类只覆盖 production/conflict 词（Phase 10 142 行） | 补 MATCH_RECOGNIZE 等 Calcite base 保留字（Phase 11，Pitfall 9） | Phase 11 | 保留字判定与 Flink parser 一致；负门禁可靠 |
| 共享 `precedence()` 纯原文函数（无 `||`/`=>`） | `precedence(context, cursor)` 方言策略表（Flink + CONCAT/NAMED_ARGUMENT_ASSIGNMENT） | Phase 11 | Flink 表达式覆盖 `||`/`=>`；Doris 分支字节不变 |
| Window TVF 依赖 Doris 通用 table-ref 路径（会误消费） | Flink FROM 子句 TVF table-ref 识别 + 表达式层 `TABLE(...)`/`DESCRIPTOR(...)`/`INTERVAL` | Phase 11 | FLINK-05 语法级覆盖；Doris 不接受 TVF（负门禁） |
| MATCH_RECOGNIZE 无 parser 路径 | 独立 `parse_match_recognize` 子语言（语法级 CST） | Phase 11 | FLINK-06 语法级 CST + 诊断；不声称 planner 等价 |

**Deprecated/outdated:**
- **FATHOM-PARSE-008**：`flink grammar is not yet implemented in this release`（`parser.mbt:3405-3429`）——D-06 退役；不再用于合法 flink SQL，code 保留空缺不复用。
- **Doris `parse_create_table`/`parse_column_definition`/`parse_distribution_clause` 用于 Flink**：Doris 版子句/列体形态与 Flink 差异大（`DUPLICATE KEY`/`ENGINE=`/`ROLLUP`/`BUCKETS AUTO`/`AUTO PARTITION`），Phase 11 起 Flink 用独立 `parse_flink_create_table`。

## Assumptions Log

> 本表列出所有 `[ASSUMED]` 标注的声明；planner/discuss-phase 需在锁定前确认。

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Flink 下 `QUALIFY` 是保留字但无 QUALIFY 子句生产（`SELECT ... QUALIFY ...` 在 Flink 是 parse error，Doris-only 负门禁） | §9 负门禁矩阵 | 若 Calcite 1.34+/1.36+ 实际支持 QUALIFY 子句，则 Flink 模式应接受，负门禁方向反转；需 fixture 实测 |
| A2 | Window TVF 的 `CUMULATE` 无 keyword token（非保留也非非保留，纯标识符），靠通用 table-function 路径解析 | §5.5 | 若某 release 把 CUMULATE 加入 keyword，保留字判定变化；当前三 release 均无 CUMULATE token（已核验） |
| A3 | Flink 表达式需补 `||`（CONCAT）优先级介于比较与算术之间；具体优先级数值需按 Calcite `SqlStdOperatorTable.CONCAT` 语义对齐 | §7.3/Pattern 4 | 优先级数值若与 Calcite 不一致，`a || b = c` 结合性差异；用 fixture 校验 |
| A4 | `INTERVAL '3' SECOND` 区间字面量在共享表达式层走 `INTERVAL` 关键字 + 字符串 + 单位，不需要专用 token | §7.3 | Doris 的 `INTERVAL` 处理（日期函数参数）可能与 Flink 区间字面量冲突；需 Flink 表达式路径独立处理 |
| A5 | Flink 负门禁的新诊断码建议为 FATHOM-PARSE-009（007 语义偏宽）；具体 code 由 planner 锁定 | §6.3/§9 | 若 planner 复用 007，诊断语义「unsupported statement」与「clause 仅其他方言合法」混用；若新建 009，需 schema/文档登记 |
| A6 | `TUMBLE_ROWTIME/TUMBLE_START`（legacy grouped windowing 函数）在 Phase 11 按普通函数调用解析，不做专门 CST | §8 | 若 fixture 把它们当作 TVF 输出列断言，形状错误；本文件已区分（Pitfall 8） |

## Open Questions (RESOLVED)

1. **负门禁新诊断码：FATHOM-PARSE-009 新建 vs 复用 007**
   - What we know: 007 语义为「unsupported statement in the selected profile」（`parser.mbt:3163-3175`）；负门禁拒绝的往往是 clause/construct（`WATERMARK FOR ...`、`MATCH_RECOGNIZE`、`DISTRIBUTED BY ... BUCKETS`）而非整句。
   - What's unclear: 用 007（语义偏宽但零新 code）还是新建 009（精确但新增稳定契约）。
   - Recommendation: 建议新建 FATHOM-PARSE-009「syntax is not supported in the selected dialect」，与 007 并存；planner 定稿并登记。
   - **RESOLVED:** 11-01 checkpoint D-04 (Task 1) mints FATHOM-PARSE-009「syntax is not supported in the selected dialect」(option-a) for construct-level rejection; FATHOM-PARSE-007 stays whole-statement unsupported; the new code is registered in approved-changes.md (D-04 one-way door).
2. **新 SyntaxKind 的精确命名与 kind_id wire 字符串**
   - What we know: D-02 要求新增 Flink 语句族节点；`kind_id`（`api/api.mbt:331-357`）是 one-way wire 契约。
   - What's unclear: 是每种语句一个 kind（`ShowStatement`/`DescribeStatement`…）还是粒度更细（`ShowTables`/`ShowCatalogs`…）；watermark/computed 列是独立 kind 还是挂在 `ColumnDefinition` 下。
   - Recommendation: 建议粗粒度 kind（`ShowStatement`/`DescribeStatement`/`AlterTable`/`WatermarkClause`/`ComputedColumn`/`MetadataColumn`/`PrimaryKeyClause`/`TableLikeClause`/`WindowTvf`/`MatchRecognize`），语句子类型放 metadata/span；planner 定稿。
   - **RESOLVED:** 11-01 checkpoint D-02 (Task 2) confirms coarse per-statement-family kinds (option-a) appended to the SyntaxKind enum end with snake_case kind_id wire strings; statement sub-types (SHOW TABLES vs SHOW CATALOGS) ride in node metadata/span.
3. **MATCH_RECOGNIZE 的 supported/known-limitation 精确边界（语法级）**
   - What we know: 生产支持 PARTITION BY/ORDER BY/MEASURES/rows-per-match/AFTER MATCH SKIP（TO NEXT ROW/TO FIRST var/TO LAST var/PAST LAST ROW）/PATTERN（锚 ^$、`|`、串联、`{n,m}` 量词、`+`/`*`/`?`、reluctant `?`）/WITHIN INTERVAL/DEFINE（`:3062-3346`）。
   - What's unclear: 哪些语法组合在**语法级**应明确 known-limitation（如 `SUBSET`、`^...$` 锚、`{-` exclude 语法、`PERMUTE`、pattern variable 的列引用作用域校验）。
   - Recommendation: 语法级实现 PATTERN/DEFINE/MEASURES/skip/变量/量词全结构；`SUBSET`、`PERMUTE`、`{- ... -}`（PatternExclude，`:3294-3335`）按生产可实现但标注 known-limitation（fixture 分类）；planner 按研究 flags 冻结子集。
   - **RESOLVED:** 11-04 Task 3 freezes the supported/known-limitation subset — syntax-level PATTERN/DEFINE/MEASURES/skip/variables/quantifiers fully implemented; SUBSET/PERMUTE/{- ... -} parse structurally and are classified known-limitation in fixtures; no pattern-variable scope/type validation (Pitfall 6).
4. **Window TVF 的命名参数（named arguments）形态**
   - What we know: TVF SQL 示例用位置参数 `TUMBLE(TABLE T1, DESCRIPTOR(rowtime), INTERVAL '5' SECOND)`；`=>`（NAMED_ARGUMENT_ASSIGNMENT，`:8794`）token 已存在。
   - What's unclear: `data => ...`/`timecol => ...` 命名参数在语法级是否需专门解析（Calcite 的 NamedRoutineCall 支持 named args）。
   - Recommendation: 表达式层支持 `=>` 后，`TUMBLE(data => TABLE T1, ...)` 自然解析；fixture 覆盖命名参数形式；若超出语法级范围则标 known-limitation。
   - **RESOLVED:** 11-04 Task 1 covers named-argument TVF (`TUMBLE(data => TABLE T1, ...)`) via the 11-02 named-arg `=>` support in the function-call argument layer (NAMED_ARGUMENT_ASSIGNMENT Parser.jj:8794); the TVF fixture asserts the named-argument form parses.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `moon`/`moonc` | 核心构建/测试/快照 | ✓ | moon 0.1.20260724 (5f1406a 2026-07-24)（Phase 10 核验） | CI 安装 `latest` 并记录版本 |
| Python 3 | release 提取/清单/fixture 校验脚本（stdlib） | ✓ | 3.9.23 | — |
| Flink release 归档（研究 fixture） | grammar 提取/行号引用（本 session 全部复用） | ✓（Phase 10 已校验和复核） | `/tmp/flink-research/src/flink-{2.3.0,2.1.3,1.20.5}/` + `Parser-calcite-*.jj` + `Parser-release-*.tdd` | 重新下载（URL 已记录）+ 校验和比对 |
| git | release tag→commit 审计（既有） | ✓ | 2.47.3 | — |
| Calcite `SqlParserTest` 源码（MATCH_RECOGNIZE 正/负例源） | FLINK-06 fixture 权威 | ✗（**不在 Flink release 归档内**） | — | 用钉住 grammar 生产（`Parser.jj:3062-3346`）+ `MatchRecognizeTest.scala` + `FlinkSqlParserImplTest.java` 定义 fixture；Phase 12 corpus 可另引 calcite-core 源码（离线 pin） |

**Missing dependencies with no fallback:** none（本阶段全部依赖可用）。
**Missing dependencies with fallback:** Calcite `SqlParserTest` 源码不在 Flink 归档——MATCH_RECOGNIZE 正/负例用 release 内 planner 测试 SQL + grammar 生产替代（已在上文引用）；planner 不应引入 calcite-core 源码下载。

## Validation Architecture

> **SKIPPED** — `.planning/config.json` `"workflow": { "nyquist_validation": false }`。验证架构（Test Framework / Phase Requirements → Test Map / Sampling Rate / Wave 0 Gaps）按配置豁免。本阶段验证策略以 §Architecture Patterns 的 parity/flink-grammar 快照门禁 + 双向负门禁 fixture + 冻结 Doris baseline（213 快照）取代；测试沿用仓库既有 `moon test --target native --package parity ...` 矩阵。

## Security Domain

> `security_enforcement: true`（`.planning/config.json`）——本阶段无网络/凭据，但 Flink 语句接受与双向负门禁是新的攻击面（错误方言接受 = 错误有效性判定）。

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | 无认证面（纯前端库 + stdio LSP） |
| V3 Session Management | no | 无会话；LSP document version 单调性沿用 Phase 9 |
| V4 Access Control | no | 无资源/角色 |
| V5 Input Validation | **yes** | Flink 语句按钉住 grammar 解析；未知/不支持构造显式 007 拒绝；双向负门禁（Flink-only 在 Doris 拒绝、Doris-only 在 Flink 拒绝）用本地化诊断；恢复预算共享（`consume_recovery_step`/`depth_allowed`） |
| V6 Cryptography | no | 无加密需求；release 归档 SHA-512 属完整性校验而非加密 |

### Known Threat Patterns for {stack}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Flink 保留字误接受为标识符（MATCH_RECOGNIZE 等缺行 → `classification_of` 返回 None） | Tampering | 补全 `dialect/flink.mbt` 行表（Pitfall 9）；`is_reserved_word` 对保留字返回 true，反引号才可作标识符 |
| 方言负门禁失效：Flink-only 语法在 Doris 模式 valid | Tampering | 每个 Flink-only 构造点（WATERMARK/TVF/MATCH_RECOGNIZE/PRIMARY KEY NOT ENFORCED/computed/metadata 列）在 Doris 路径显式拒绝 + 双向负门禁 fixture（§9/§10） |
| 恢复无限推进：半成品 MATCH_RECOGNIZE/PATTERN 吞 token 或无界 CST | DoS | 独立子语言同步点 + 共享 recovery-step/depth 预算；嵌套未闭合 fixture（§10） |
| release 伪造/漂移：fixture 期望与钉住 grammar 不一致 | Tampering | 每个 production 行号引用钉住 release（§5）；manifest 记录 release/sha512；D-05 注册批准制 |

## Sources

### Primary (HIGH confidence — 本 session 直接读取/核验)

**外部 release grammar 事实（/tmp/flink-research/ 缓存，全部本 session 复核）：**
- `src/flink-2.3.0/flink-table/flink-sql-parser/src/main/codegen/data/Parser.tdd:651-727` — `statementParserMethods`（51 个 Flink 语句方法完整列表）
- `src/flink-2.3.0/flink-table/flink-sql-parser/src/main/codegen/templates/Parser.jj:1140-1185` — Calcite base `SqlStmt` 分发；`:2443-2460` `TableFunctionCall`；`:3062-3346` `MatchRecognize`（含 `:3170 WITHIN interval`、`:3314-3317` PatternQuantifier）
- `src/flink-2.3.0/flink-table/flink-sql-parser/src/main/codegen/includes/parserImpls.ftl` — `SqlCreateCatalog:142-188`、`SqlCreateDatabase:301-372`、`SqlCreateFunction:390-480`、`SqlShowTables:674-714`、`SqlRichDescribeTable:867-880`、`TableColumn/Watermark:1103-1145`、`TypedColumn/MetadataColumn/ComputedColumn/RegularColumn:1146-1330`、`TableConstraint/UniqueSpec/ConstraintEnforcement:1432-1504`、`TableOption/Properties:1506-1556`、`SqlDistribution:1560-1600`、`SqlCreateTable:1585-1712`、`SqlTableLike:1714-1790`、`TableColumnsOrIdentifiers:1794-1830`、`RichSqlInsert:2306-2379`、`SqlCreateView:2414-2439`、`SqlCreateExtended/SqlDropExtended:2850-2920`、`SqlRichExplain:3079-3117`、`SqlSet/SqlReset:3294-3333`、`SqlAnalyzeTable:3413-3443`
- `Parser-calcite-1.36.0.jj:8214` — `MATCH_RECOGNIZE` 保留字 token（Calcite base）；`:3018-3300` MatchRecognize 生成版
- `Parser-release-2.3.0.tdd` — `keywords`/`nonReservedKeywords`（TUMBLE:587/HOP:384/SESSION:509/DESCRIPTOR:351 非保留）
- `flink-table-planner/src/test/.../WindowAggregateITCase.scala:228-263` — Window TVF SQL（TABLE + DESCRIPTOR + INTERVAL）+ `window_start/window_end` 输出列
- `flink-table-planner/src/test/.../plan/stream/sql/MatchRecognizeTest.scala:60-163` — MATCH_RECOGNIZE SQL（PARTITION/ORDER/MEASURES/ONE ROW/PATTERN/DEFINE）+ TVF 组合（:141-148）
- `flink-table/flink-sql-parser/src/test/.../FlinkSqlParserImplTest.java` — DDL/SHOW/DESCRIBE/ANALYZE 正/负例（`testCreateTable*`、`testShowTables`、`testDescribeDatabase`、`.fails(...)` 负例）

**In-repo（`[VERIFIED: 路径:行]`）：**
- `parser/parser.mbt:3336-3351` — `parse_segment` 路由；`:3354-3403` `parse_doris_segment`；`:3405-3429` `parse_flink_segment`（FATHOM-PARSE-008）；`:263-274` `precedence()`；`:3163-3175` `unsupported_statement`（007）；`:3487-3583` `parse_with_limits_context`；`:3624-3628` 008 测试断言
- `syntax/syntax.mbt:2-26` — `SyntaxKind` 枚举（Document..Missing）
- `api/api.mbt:331-357` — `kind_id` wire 映射；`:297-303` `PrimitiveNode`
- `dialect/flink.mbt` — `FlinkProfile` 枚举 + `flink_classification_rows`（142 行，source 逐行 release grammar 引用）；`:17` 无 MATCH_RECOGNIZE 行
- `dialect/classification.mbt:56-100` — `classification_rows_for`/`classification_of`/`is_clause_keyword`/`is_reserved_word`
- `lexer/lexer.mbt:412-424` — `symbol_width_flink`（`||`/`=>`/`..` 单 token）
- `binding/schema.mbt:40-51` — `validate_dialect_profile`
- `.planning/config.json` — `nyquist_validation: false`、`security_enforcement: true`
- `parity/__snapshot__/` — 213 个 Doris 快照 + flink-lexical 组（`flink-lexical.*.{profile}.{mode}.json` 命名形态）

### Secondary (MEDIUM confidence)
- `[CITED: /tmp/flink-research/flink-2.3.0-reserved.txt]` — 443 词保留字清单（缺 MATCH_RECOGNIZE，见 Pitfall 9——Phase 10 提取范围限制）
- `[CITED: /tmp/flink-research/flink-2.1.3-reserved.txt]` / `flink-1.20.5-reserved.txt` — 回归 profile 保留字清单

### Tertiary (LOW confidence / validation required)
- §Assumptions Log A1-A6（QUALIFY 子句生产、CUMULATE token、`||` 优先级数值、INTERVAL 字面量共享、009 code、legacy 窗口函数）
- §Open Questions (RESOLVED) 1-4（负门禁 code、SyntaxKind 命名、MATCH_RECOGNIZE 子集边界、TVF 命名参数 — 已由 11-01 checkpoint D-04/D-02 与 11-04 Task 3/Task 1 计划决策定稿）

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — 零新增外部包；全部 grammar 事实来自钉住 release 逐字引用；复用 Phase 10 工具链模式
- Architecture: HIGH — 语句族→生产映射、CST 复用/新增、恢复扩展、负门禁矩阵、实现表面全部有 release 行号 + in-repo 行号支撑
- Pitfalls: HIGH — 9 条陷阱每条都有定义点/调用点/release 证据；Doris 回归严重度由 213 快照门禁量化

**Research date:** 2026-08-09
**Valid until:** 2026-09-06（release 归档不可变；若 Apache 变更归档布局或 Flink 发布新 release 需重核 grammar 行号）

---
*Phase: 11-Flink Grammar and Recoverable CST*
*Research completed: 2026-08-09*
