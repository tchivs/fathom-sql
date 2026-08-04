# Phase 2: Doris Completeness and Corpus - Context

**Gathered:** 2026-08-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 2 expands the Phase 1 SELECT kernel into version-supported Doris scripts and warehouse DDL/DML: semicolon-separated multi-statement documents, INSERT/INSERT OVERWRITE/UPDATE/DELETE/MERGE, CREATE TABLE with keys/aggregation semantics/distribution/buckets/partitions/dynamic partitions/properties, views, CTAS/LIKE, indexes, and materialized views — each under an auditable versioned keyword classification. It also publishes a reproducible official-document corpus manifest with golden coverage, version/category coverage and failure reports, and recorded differential disagreements, while keeping syntax parsing free of catalog metadata and exposing an optional analyzer boundary.

</domain>

<decisions>
## Implementation Decisions

### DML/DDL 覆盖范围与优先级
- **D-09:** DML 覆盖顺序为 INSERT(含 OVERWRITE、VALUES/SELECT 数据源)优先,随后 UPDATE/DELETE,MERGE 最后 — 官方文档对 MERGE 支持有限,不与其争抢首轮资源。
- **D-10:** DDL 覆盖顺序为 CREATE TABLE 完整建表(keys、aggregation semantics、distribution、buckets、partitions、dynamic partitions、properties)优先,随后 CREATE VIEW / CTAS / CREATE TABLE LIKE,最后 CREATE INDEX / MATERIALIZED VIEW。
- **D-11:** 语句识别以关键字开头判定语句类型,分号终结语句;沿用 Phase 1 的语句级 panic-mode 与子句级尽力恢复,不引入新的同步机制。
- **D-12:** 版本支持范围外的语句在 editor 模式下产生显式 unsupported/error 节点与诊断,绝不静默跳过或当作普通标识符消费。

### 关键字分类体系 (DORIS-04)
- **D-13:** 官方发布文档的保留字/关键字清单为分类权威来源,FE/Nereids 词法作交叉核对;manifest 记录每条分类的来源与版本归属。
- **D-14:** 三层分类:reserved / non-reserved(可作未加引号标识符)/ contextual(仅特定子句);在 Phase 1 的 `is_clause_keyword`/`is_reserved_word`/`is_unquoted_identifier` 基础上扩展为可审计的版本化分类表。
- **D-15:** 版本化沿用 `introduced_profile` 门控模式(QUALIFY 先例):每个关键字标注 2.1/3.x/4.x 引入版本,按 profile 校验,版本不匹配即报 DORIS-PARSE 系列诊断。
- **D-16:** 生成关键字分类 TSV 报告(词、分类、引入版本、来源),纳入 corpus 报告交付,保证分类可审计。

### 语料库与验证报告 (CORP-01..03)
- **D-17:** 语料离线手工收录官方发布文档(2.1/3.x/4.x)SQL 示例;每 fixture 记录 URL、版本、类别、预期支持状态;延续 `unavailable-offline` 来源标注,不伪造 revision。
- **D-18:** fixture 形态沿用 manifest.tsv + 版本目录 SQL 文件 + snapshot golden;非法/恢复用例按 Phase 1 模式处理(TSV 内联字节或明确分类)。
- **D-19:** 报告交付为扩展后的 coverage.tsv 加 CORPUS-REPORT.md:按版本×类别的覆盖矩阵、失败清单、known-gaps 列表,不发布无保留的"完全兼容"声明。
- **D-20:** SQLGlot(pip 可安装)差分脚本本地可运行,记录 disagreements 及版本化 resolution;FE/Nereids 差分保留为手动运行脚本(需 Java 构建,离线环境不可用),两者都不成为公共契约。

### 分析器边界与脚本 API (ANLY-01)
- **D-21:** analyzer 作为独立 `analyzer/` moon 包,parser 核心对其零依赖;纯语法校验路径完全不动。
- **D-22:** catalog 最小形态为表→列名映射的 trait/record,仅支持名字解析级校验,不做类型推导或 FE 执行语义。
- **D-23:** 多语句文档暴露 statement 级入口:可按 statement_id 取节点与诊断,满足 DORIS-03"无效语句不丢弃后续语句"的验收路径。
- **D-24:** 本阶段 analyzer 交付接口+文档+最小实现;ANAL-01 的完整名字解析留在 v2,不在本阶段承诺。

### Claude's Discretion
- 具体语法函数分解、parser 内部结构、corpus 抓取脚本形态、报告生成方式,以及 Phase 2 的 plan 切分方式由 planner 决定,前提是上述 D-09..D-24 契约被保留。

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project and scope
- `.planning/PROJECT.md` — core value, MoonBit constraint, lossless CST decision, parser/analyzer boundary, and four-milestone scope.
- `.planning/REQUIREMENTS.md` § Doris Coverage / Corpus and Validation / Analysis Boundary — locked DORIS-01..04, CORP-01..04, ANLY-01 acceptance requirements for this phase.
- `.planning/ROADMAP.md` § Phase 2: Doris Completeness and Corpus — phase goal, dependencies, requirements, and success criteria.
- `.planning/STATE.md` — current project position and accumulated cross-phase decisions.

### Prior phase context
- `.planning/phases/01-core-kernel/01-CONTEXT.md` — locked D-01..D-08 contracts (byte coordinates, strict/editor dual mode, lossless CST, versioned doc authority, golden validation) that Phase 2 MUST preserve and build on.
- `.planning/phases/01-core-kernel/01-PATTERNS.md` — established module layout, parser/lexer patterns, and test conventions.
- `.planning/phases/01-core-kernel/01-RESEARCH.md` — implementation research from Phase 1 planning.

### Research and technical evidence
- `.planning/research/SUMMARY.md` — research-backed contracts, risks, and focused research flags.
- `.planning/research/STACK.md` — MoonBit v0.10.5 evidence, source-backed CST direction, testing commands, and cross-target boundary constraints.
- `.planning/research/ARCHITECTURE.md` — source/coordinate, lexer, parser, CST, recovery, and parser/analyzer component boundaries.
- `.planning/research/PITFALLS.md` — version drift, keyword classification, lossless spans, recovery cascades, and validation risks.

### Existing code (Phase 1 deliverables)
- `api/api.mbt` — public `parse`/`ParseResult`/`PrimitiveNode`/`PrimitiveDiagnostic` boundary with statement_id already present.
- `token/token.mbt` — `is_clause_keyword`/`is_reserved_word`/`is_unquoted_identifier`, `introduced_profile` gating (QUALIFY/TABLET precedent), `ValidatedProfileContext`.
- `parser/parser.mbt` — recursive descent + Pratt, statement-level panic-mode recovery.
- `syntax/syntax.mbt` — lossless CST node/leaf model.
- `corpus/manifest.tsv`, `corpus/coverage.tsv`, `corpus/differential.tsv`, `corpus/doris-{2.1,3.x,4.x}/` — existing fixture manifest and reports to extend.

No separate SPEC.md or ADR exists for Phase 2; the project, research, and prior-phase documents above are the canonical requirements and evidence.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Lossless CST 模型(`syntax/`)、递归下降+Pratt 解析器(`parser/parser.mbt`,1831 行)、`introduced_profile` 版本门控(token.mbt)、`ParseLimits` 资源上限、语句级恢复。
- corpus 管线已存在骨架:manifest.tsv(15 行,3 个 SELECT fixture)+ coverage.tsv + differential.tsv + 按版本目录。
- `ParseResult.statement_id` 与 `PrimitiveDiagnostic.statement_id` 已就位,为语句级 API 提供基础。

### Established Patterns
- 每 fixture 记录 profile/exact_release/feature_introduction/official_url/retrieval_date/pinned_source_revision/category/support_status/parse_mode/classification/provenance_status。
- 离线环境标注 `unavailable-offline` + `known-gap:` 描述,不伪造 commit。
- 测试:内联 test 块 + `_test.mbt` 黑盒/白盒 + snapshot golden;`moon test --update` 更新快照。

### Integration Points
- 新语句类型进入 parser.mbt 的语句分派与 syntax.mbt 的 SyntaxKind 枚举(目前仅有 Select)。
- 关键字分类扩展落在 token.mbt 的分类函数与 profile 门控表。
- 新 fixture 写入 corpus/{doris-2.1,doris-3.x,doris-4.x}/ 并登记 manifest.tsv。
- analyzer 包从零创建,仅依赖 `syntax/`(或 `api/`)的只读视图,禁止反向依赖。

</code_context>

<specifics>
## Specific Ideas

- 保持项目差异化:任何新增语句都必须满足 `parse(print(parse(x))) == x` 无损回放,包括注释、空白、未知文本与错误材料。
- 半成品多语句文档(如 `INSERT INTO t VALUES (1); SELECT * FR` )是 editor 一等输入,后续语句必须保留。
- 版本门控是硬约束:3.x 才有的语法在 2.1 profile 下必须报 DORIS-PARSE-006 类诊断,不允许静默接受。
- 语料库报告以"已知缺口"替代"完整兼容"声明,保持可审计的诚实性。

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within the Phase 2 boundary. Configurable formatting, CLI packaging, LSP, Wasm/JavaScript delivery remain in Phases 3/4; full catalog-backed name resolution (ANAL-01) and type inference remain v2.

</deferred>

---

*Phase: 2-Doris Completeness and Corpus*
*Context gathered: 2026-08-04*
