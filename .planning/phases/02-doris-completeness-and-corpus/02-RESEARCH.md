# Phase 2: Doris Completeness and Corpus — Research

**Researched:** 2026-08-04
**Domain:** Doris DML/DDL grammar coverage, versioned keyword classification, official-doc corpus pipeline, FE/SQLGlot differential, analyzer boundary
**Confidence:** HIGH for official 4.x DML/DDL grammars and keyword lists (all read directly from Apache Doris released docs this session); MEDIUM for 2.1/3.x fine-grained statement gates (only doc presence/absence and feature-introduction notes verified); MEDIUM for the analyzer/corpus engineering recommendations (prescriptive design).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-09:** DML 覆盖顺序为 INSERT(含 OVERWRITE、VALUES/SELECT 数据源)优先,随后 UPDATE/DELETE,MERGE 最后 — 官方文档对 MERGE 支持有限,不与其争抢首轮资源。
- **D-10:** DDL 覆盖顺序为 CREATE TABLE 完整建表(keys、aggregation semantics、distribution、buckets、partitions、dynamic partitions、properties)优先,随后 CREATE VIEW / CTAS / CREATE TABLE LIKE,最后 CREATE INDEX / MATERIALIZED VIEW。
- **D-11:** 语句识别以关键字开头判定语句类型,分号终结语句;沿用 Phase 1 的语句级 panic-mode 与子句级尽力恢复,不引入新的同步机制。
- **D-12:** 版本支持范围外的语句在 editor 模式下产生显式 unsupported/error 节点与诊断,绝不静默跳过或当作普通标识符消费。
- **D-13:** 官方发布文档的保留字/关键字清单为分类权威来源,FE/Nereids 词法作交叉核对;manifest 记录每条分类的来源与版本归属。
- **D-14:** 三层分类:reserved / non-reserved(可作未加引号标识符)/ contextual(仅特定子句);在 Phase 1 的 `is_clause_keyword`/`is_reserved_word`/`is_unquoted_identifier` 基础上扩展为可审计的版本化分类表。
- **D-15:** 版本化沿用 `introduced_profile` 门控模式(QUALIFY 先例):每个关键字标注 2.1/3.x/4.x 引入版本,按 profile 校验,版本不匹配即报 DORIS-PARSE 系列诊断。
- **D-16:** 生成关键字分类 TSV 报告(词、分类、引入版本、来源),纳入 corpus 报告交付,保证分类可审计。
- **D-17:** 语料离线手工收录官方发布文档(2.1/3.x/4.x)SQL 示例;每 fixture 记录 URL、版本、类别、预期支持状态;延续 `unavailable-offline` 来源标注,不伪造 revision。
- **D-18:** fixture 形态沿用 manifest.tsv + 版本目录 SQL 文件 + snapshot golden;非法/恢复用例按 Phase 1 模式处理(TSV 内联字节或明确分类)。
- **D-19:** 报告交付为扩展后的 coverage.tsv 加 CORPUS-REPORT.md:按版本×类别的覆盖矩阵、失败清单、known-gaps 列表,不发布无保留的"完全兼容"声明。
- **D-20:** SQLGlot(pip 可安装)差分脚本本地可运行,记录 disagreements 及版本化 resolution;FE/Nereids 差分保留为手动运行脚本(需 Java 构建,离线环境不可用),两者都不成为公共契约。
- **D-21:** analyzer 作为独立 `analyzer/` moon 包,parser 核心对其零依赖;纯语法校验路径完全不动。
- **D-22:** catalog 最小形态为表→列名映射的 trait/record,仅支持名字解析级校验,不做类型推导或 FE 执行语义。
- **D-23:** 多语句文档暴露 statement 级入口:可按 statement_id 取节点与诊断,满足 DORIS-03"无效语句不丢弃后续语句"的验收路径。
- **D-24:** 本阶段 analyzer 交付接口+文档+最小实现;ANAL-01 的完整名字解析留在 v2,不在本阶段承诺。

### Claude's Discretion

- 具体语法函数分解、parser 内部结构、corpus 抓取脚本形态、报告生成方式,以及 Phase 2 的 plan 切分方式由 planner 决定,前提是上述 D-09..D-24 契约被保留。

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within the Phase 2 boundary. Configurable formatting, CLI packaging, LSP, Wasm/JavaScript delivery remain in Phases 3/4; full catalog-backed name resolution (ANAL-01) and type inference remain v2.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DORIS-01 | User can parse version-supported DML statements including INSERT, INSERT OVERWRITE, UPDATE, DELETE, and supported MERGE forms in semicolon-separated scripts. | Full 4.x grammars verified verbatim from official docs (INSERT, INSERT OVERWRITE, UPDATE, DELETE, MERGE INTO); MERGE is documented only in the 4.x tree (2.1/3.x DML indexes verified to lack MERGE-INTO), so MERGE must be version-gated to 4.x per released-docs authority. |
| DORIS-02 | User can parse version-supported Doris DDL including tables, views, CTAS/LIKE, keys, aggregation semantics, distribution, buckets, partitions, dynamic partitions, properties, indexes, and materialized views. | Full 4.x CREATE TABLE grammar (columns/indexes/partitions/rollup/distribution/properties + CTAS + LIKE), CREATE VIEW, CREATE INDEX, and sync CREATE MATERIALIZED VIEW verified verbatim from official docs; version gates recorded (e.g., `ORDER BY` since 4.1.0, `PARTITION (*)` since 2.1.3). |
| DORIS-03 | Parser preserves statement boundaries and reports a localized diagnostic when one statement in a multi-statement document is invalid, without discarding later statements. | Phase 1 `parse_with_limits_context` already segments on token-level `;` and assigns monotonic `statement_id`; DORIS-03 test shape proven by existing `SELECT a + 1; bad; SELECT b` fixture. |
| DORIS-04 | Parser applies an auditable, versioned classification of reserved, non-reserved, and contextual Doris/MySQL-compatible keywords, allowing valid non-reserved words as identifiers. | Official reserved-keyword page exists per version and is byte-identical across 2.1/3.x/4.x (all three lists read this session); classification must layer non-reserved/contextual on top of this verified base list. |
| CORP-01 | Project maintains a reproducible official-Doris-document corpus manifest whose fixtures record release family, source URL, retrieval/source revision, statement category, and expected support status. | manifest.tsv schema already established (15 rows); extend with DML/DDL categories and per-version fixture dirs; continue `unavailable-offline` provenance policy (D-17). |
| CORP-02 | Every supported corpus fixture has golden coverage for strict parsing, lossless replay, formatting where applicable, and malformed or recovery cases without relying on undocumented current/dev syntax. | Phase 1 layered oracle pattern (`print_result == raw`, `all_spans_in_bounds`, strict/editor paired fixtures) verified in test/parser_test.mbt; extend per statement family. |
| CORP-03 | Project publishes parse coverage and failure reports by Doris version and statement category, including known gaps instead of an unqualified full-compatibility claim. | coverage.tsv + CORPUS-REPORT.md matrix approach prescribed (D-19); generator script shape in this research. |
| CORP-04 | Project can run differential checks against feasible Doris FE/Nereids and SQLGlot references, recording disagreements and their version-specific resolution without making either implementation the public contract. | SQLGlot 30.14.0 verified on PyPI (reachable this session); differential script shape provided; FE/Nereids manual-only (needs Java build, offline). |
| ANLY-01 | Consumer can perform syntax parsing and diagnostics without catalog metadata, while an optional analyzer interface can accept catalog table/column metadata without coupling the parser to FE execution semantics. | analyzer/ package design with minimal Catalog trait/record (D-21..D-24) in this research; parser dependency direction already analyzer-free (verified parser/moon.pkg imports). |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

Actionable directives extracted from `.claude/CLAUDE.md` (GSD-generated project file, read this session via repo-rules context) that Phase 2 planning MUST respect:

- **MoonBit single core**: one MoonBit implementation compiles to Native and Wasm/JS — no per-backend parser forks, no runtime Doris FE or database dependency [VERIFIED: .claude/CLAUDE.md Constraints section].
- **Lossless CST**: CST nodes must preserve Span and trivia; formatting/edits must never lose comments, whitespace, or newlines — every new statement family must satisfy `print_lossless(parse(x)) == x` [VERIFIED: .claude/CLAUDE.md].
- **Parsing strategy**: handwritten recursive descent + Pratt; statement-level panic-mode and clause-level best-effort recovery must be reused for DML/DDL (D-11) [VERIFIED: .claude/CLAUDE.md].
- **Coverage authority**: official released docs are the grammar authority and executable corpus, with versioned keyword classification — current/dev is discovery only [VERIFIED: .claude/CLAUDE.md].
- **Parser/analyzer boundary**: parser is syntax-only; optional analyzer consumes injected catalog; syntax-only parsing must work with no metadata [VERIFIED: .claude/CLAUDE.md].
- **Delivery order**: SELECT/expression industrial quality first, then DML/DDL (this phase), then formatting, then ecosystem [VERIFIED: .claude/CLAUDE.md].
- **GSD workflow enforcement**: no direct repo edits outside a GSD workflow entry point (`/gsd-execute-phase` etc.); research and planning artifacts are the exception [VERIFIED: .claude/CLAUDE.md Workflow section].
- `你始终回复中文` (always reply in Chinese) is set in `/root/.claude/CLAUDE.md`; the research assignment explicitly requires English research artifacts, so RESEARCH.md content is English while the planner may converse in Chinese [VERIFIED: /root/.claude/CLAUDE.md:1].

## Summary

Phase 2 extends the Phase 1 SELECT kernel into Doris DML/DDL with auditable version gates and a reproducible official-doc corpus. All four DML grammars (INSERT, INSERT OVERWRITE, UPDATE, DELETE, MERGE INTO) and all four DDL families (CREATE TABLE incl. CTAS/LIKE, CREATE VIEW, CREATE INDEX, sync CREATE MATERIALIZED VIEW) were verified verbatim from the official 4.x documentation this session; 2.1/3.x doc presence was checked to establish version gates. The single most important version finding is that **MERGE INTO is documented only in the 4.x tree** — the 2.1 and 3.x DML indexes (read directly) contain no MERGE-INTO page — which validates D-09's "docs support for MERGE is limited" and forces a 4.x-only acceptance gate per D-07's released-docs authority. A second verified finding: the official reserved-keyword list is **byte-identical across 2.1, 3.x, and 4.x docs** (all three lists read this session), so version gating lives in statement/feature introduction metadata (QUALIFY/TABLET = 3.x, MERGE = 4.x-doc, `CREATE TABLE ORDER BY` = 4.1.0, `INSERT OVERWRITE PARTITION (*)` = 2.1.3), not in the reserved-word set.

The statement dispatcher (`parse_segment`) currently accepts only SELECT/WITH and emits `DORIS-PARSE-001` for everything else; Phase 2 replaces that with a keyword-driven dispatch table (INSERT/UPDATE/DELETE/MERGE/CREATE + WITH-CTE-prefixed forms) while keeping token-level `;` segmentation, monotonic `statement_id`, and statement-level panic-mode. Unsupported statement starters (ALTER/DROP/GRANT/SHOW/EXPLAIN/LOAD/…) must produce explicit unsupported-statement error nodes with a new stable diagnostic (D-12), never silent acceptance. Corpus work extends manifest.tsv/coverage.tsv/differential.tsv with DML/DDL categories, per-version fixture SQL files, and a generated CORPUS-REPORT.md; SQLGlot (30.14.0 verified on PyPI, network reachable) becomes the locally runnable differential reference, while FE/Nereids stays a documented manual script. The analyzer is a new `analyzer/` moon package exposing a minimal table→column Catalog trait/record, with zero dependency from the parser core (dependency direction already analyzer-free, verified in parser/moon.pkg).

**Primary recommendation:** Extend in three waves — (1) statement dispatch + INSERT/UPDATE/DELETE (+MERGE 4.x-gated) with per-family clause sync sets and DORIS-03 script tests; (2) CREATE TABLE full grammar (columns/keys/aggregation/distribution/buckets/partitions/dynamic partitions/properties) then VIEW/CTAS/LIKE then INDEX/sync-MV, all under `introduced_profile`-style gates; (3) keyword-classification TSV + corpus expansion + CORPUS-REPORT.md + SQLGlot differential + analyzer package. Keep `print_lossless(parse(x)) == x` as the gate for every new statement family.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Statement dispatch and DML/DDL parsing | API / Backend (pure core parser) | — | Syntax parsing must stay offline, catalog-free, and shared by all targets; the keyword-first dispatcher replaces the SELECT-only gate in parser.mbt. [VERIFIED: parser/parser.mbt parse_segment; D-11] |
| Statement boundary detection and per-statement diagnostics | API / Backend (pure core) | — | Token-level `;` segmentation and monotonic `statement_id` already exist in `parse_with_limits_context`; DORIS-03 acceptance rides on these. [VERIFIED: parser/parser.mbt:1589-1689; api/api.mbt PrimitiveDiagnostic.statement_id] |
| Versioned keyword classification | API / Backend (pure core token metadata) | Database / Storage (Git TSV report) | `introduced_profile` gating and `is_clause_keyword`/`is_reserved_word`/`is_unquoted_identifier` live in token.mbt; the auditable TSV (D-16) is a checked-in corpus artifact. [VERIFIED: token/token.mbt] |
| Official-doc corpus and golden/recovery fixtures | Database / Storage (Git fixtures) | API / Backend (fixture runner) | Versioned SQL fixtures + manifest.tsv/coverage.tsv are persisted contract inputs; runtime tests assert against them. [VERIFIED: corpus/manifest.tsv; D-17/D-18] |
| Coverage/failure reporting | Database / Storage (generated reports) | API / Backend | coverage.tsv extension + CORPUS-REPORT.md matrix are generated, checked-in deliverables (D-19), not runtime behavior. |
| SQLGlot differential | Tooling (dev-only, Python) | — | SQLGlot is a locally runnable parse-comparison baseline; advisory-only, never a public contract (D-20). |
| FE/Nereids differential | Tooling (manual, Java) | — | Requires Java/FE build; documented manual script, never CI (D-20). |
| Optional catalog/analyzer | API / Backend (optional package) | Database / Storage (catalog metadata) | `analyzer/` package with minimal Catalog trait/record; parser core has zero dependency on it (D-21/D-22). |

## Standard Stack

### Core

| Library | Version / evidence | Purpose | Why Standard |
|---------|--------------------|---------|--------------|
| MoonBit `moon`/`moonc` | `moon 0.1.20260724 (5f1406a 2026-07-24)` [VERIFIED: environment probe 2026-08-04; matches Phase 1 pin] | Single implementation and build/test toolchain | One core for Native/Wasm/JS; record `moon version` in CI. |
| Existing core packages (`source`, `token`, `lexer`, `syntax`, `parser`, `api`, `printer`) | Current repo state [VERIFIED: repo tree read this session] | Coordinates, keyword/profile tables, CST, dispatch/recovery, public boundary, exact replay | Phase 2 extends these packages; no new MoonBit runtime dependency is needed. |
| `moonbitlang/core` | Pin per STACK.md (observed `0.1.20260728+5e7afb0c0`, 2026-08-03) | Stable primitives | No new runtime packages; keep parser core dependency-light [CITED: .planning/research/STACK.md]. |
| Python 3.9 + pip 24.3.1 (dev tooling only) | [VERIFIED: environment probe 2026-08-04] | SQLGlot differential script, corpus report generator | stdlib-only scripts preferred; sqlglot is the only added dev dependency. |
| SQLGlot (dev tooling only) | `30.14.0` [VERIFIED: `pip index versions sqlglot` returned 30.14.0 as latest, PyPI reachable 2026-08-04; source repo tobymao/sqlglot confirmed in .planning/research/FEATURES.md] | Doris differential parse baseline | Locally runnable per D-20; never a runtime or public contract. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| sqlglot `doris` dialect parser | 30.14.0 | Parse each corpus fixture with `read="doris"` and record accept/reject disagreements | Differential runs only; pin the version in the script header and requirements file. |
| MoonBit snapshots (`moon test --update`) | current toolchain | CST/diagnostic golden views per statement family | After each grammar wave; update only with reviewed diff [CITED: MoonBit tests docs via STACK.md]. |
| Python stdlib `csv`/`pathlib` | — | manifest/coverage/differential TSV handling and CORPUS-REPORT.md generation | Keep report generation dependency-free; no pandas/numpy. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Official released docs as grammar authority | FE/Nereids ANTLR grammar or current/dev docs | FE grammar is coupled to the execution product and lacks release-tree stability; current/dev is explicitly unreleased (D-07). |
| SQLGlot for differential | FE as the primary oracle | FE needs a Java build and running cluster (offline-unavailable); SQLGlot is pip-installable and locally runnable (D-20). |
| Python scripts for corpus/report tooling | MoonBit scripts | Python stdlib is sufficient for TSV/report generation; keeping it in Python avoids adding file-I/O concerns to the pure core. |
| Version-gated acceptance per feature | Single merged grammar | Would silently accept 4.x-only syntax under 2.1 (violates D-15/CORE-01). |

**Installation:**
```bash
moon version                              # record exact output in CI
python3 -m venv .venv && . .venv/bin/activate   # optional; or install user-level
pip install "sqlglot==30.14.0"             # differential tooling only, pinned
moon test                                  # core suite
```

**Version verification (run before writing plans):** `pip index versions sqlglot` confirmed 30.14.0 on 2026-08-04 (PyPI reachable); MoonBit toolchain confirmed `moon 0.1.20260724`. No new MoonBit registry packages are proposed, so no Mooncakes verification is required for this phase.

## Package Legitimacy Audit

> This phase installs exactly one external package, and only as dev/differential tooling: SQLGlot via pip. The `gsd-tools` legitimacy seam is unavailable in this environment (gsd-tools.cjs not found), so the audit below uses the ecosystem-appropriate verification (PyPI index) plus the project's own prior research evidence.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| sqlglot | PyPI | Long-standing (predates 2022; referenced as the standard open SQL transpiler/parser baseline in .planning/research/FEATURES.md) | Very high (widely adopted; exact number not verified offline) | github.com/tobymao/sqlglot [CITED: .planning/research/FEATURES.md checked raw.githubusercontent.com/tobymao/sqlglot] | OK | Approved — differential tooling only, pinned at 30.14.0, never a parser-core or public dependency |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none
**Notes:** (1) SQLGlot is a Python-side differential reference per D-20; it does not enter the MoonBit dependency graph. (2) `pip index versions sqlglot` returned `sqlglot (30.14.0)` with a long version history (30.x back to 26.x visible) — consistent with a mature package [VERIFIED: probe 2026-08-04]. (3) No `postinstall`-style scripts apply to pip packages; the MoonBit core remains dependency-free of new runtime packages.

## Architecture Patterns

### System Architecture Diagram

```text
selected DorisProfile (2.1 | 3.x | 4.x) + UTF-8 bytes
                    |
                    v
          SourceText + LineIndex (unchanged)
                    |
                    v
        trivia-preserving lexer (unchanged)
                    |
                    v
   parse_with_limits_context -- token-level ';' segmentation
                    |
                    v
        parse_segment (keyword-first dispatch — NEW)
    +--------------------------------------------------+
    | SELECT/WITH -> parse_query (existing)            |
    | INSERT [OVERWRITE] -> parse_insert               |
    | UPDATE -> parse_update  |  DELETE -> parse_delete|
    | MERGE INTO -> parse_merge (4.x-gated)            |
    | CREATE -> parse_create (TABLE|VIEW|INDEX|MV)     |
    | other statement starter -> UnsupportedStmt error |
    +--------------------------------------------------+
                    |  clause-level best-effort recovery
                    |  (per-family sync sets; ';' panic-mode reused)
                    v
         immutable lossless CST (syntax.mbt kinds extended)
                    |
      +-------------+-----------------+
      |                                |
      v                                v
  print_lossless replay            api.ParseResult
  (byte-exact invariant)           statement_id + diagnostics
                    |
                    v
   versioned keyword classification (token.mbt extension)
   + reserved (official list, identical across 2.1/3.x/4.x)
   + non-reserved (grammar keywords absent from reserved list)
   + contextual (clause-only words, e.g., TABLET/ROLLUP/QUALIFY)
   + introduced_profile gates -> DORIS-PARSE-006-style diagnostics
                    |
                    v
   corpus: manifest.tsv + doris-{2.1,3.x,4.x}/*.sql fixtures
   -> strict/lossless/recovery goldens -> coverage.tsv
   -> CORPUS-REPORT.md (version x category matrix, failures, gaps)
   -> differential.tsv (sqlglot local, FE/Nereids manual)
                    |
                    v
        analyzer/ (optional, zero core dependency)
        Catalog trait/record: table -> column names
```

### Recommended Project Structure

```text
moon.mod / moon.pkg                      # unchanged; name "fathom/doris-sql"
source/ token/ lexer/ syntax/ parser/ api/ printer/   # existing, extended in place
analyzer/                                # NEW package (D-21)
├── moon.pkg                             # pkgtype(kind: "library"); imports syntax (+ api view) only
└── analyzer.mbt                         # Catalog trait/record, ColumnInfo/TableInfo, minimal impl
corpus/
├── manifest.tsv                         # extended: DML/DDL fixture rows
├── coverage.tsv                         # extended: profile x category rows
├── differential.tsv                     # extended: sqlglot rows + fe-nereids manual rows
├── keywords.tsv                         # NEW (D-16): word/classification/introduced/source
├── CORPUS-REPORT.md                     # NEW generated report (D-19)
├── doris-2.1/  doris-3.x/  doris-4.x/   # per-version fixture SQL files by category
└── tools/                               # NEW dev scripts (Python, stdlib)
    ├── generate_corpus_report.py        # manifest/coverage -> CORPUS-REPORT.md
    └── sqlglot_diff.py                  # differential runner (read="doris"), pinned version
```

Dependency direction stays one-way: `source -> token -> lexer/parser -> syntax -> api/printer`, and `analyzer` imports only `syntax`/`api` read views. The parser must never import `analyzer` (verified: `parser/moon.pkg` imports only source, token, lexer, syntax [VERIFIED: parser/moon.pkg read this session]).

### Pattern 1: Keyword-first statement dispatch (extends D-11)

**What:** `parse_segment` selects the statement parser by the first significant token (case-insensitive) instead of the current SELECT/WITH-only check, then parses the family and reuses the trailing `;`/recover loop.

**When to use:** Every new statement family. The existing structure (segment → parse → trailing recovery → Statement/Error wrapper → statement_id increment) is preserved exactly.

**Current gate (verbatim behavior) [VERIFIED: parser/parser.mbt parse_segment]:**
```text
selected = first significant raw is SELECT or WITH
else -> add_diagnostic("DORIS-PARSE-001", "expected SELECT statement", ...) -> Error node
```
**Phase 2 replacement (sketch, planner discretion):**
```text
dispatch(raw):
  SELECT|WITH -> parse_query
  INSERT     -> consume [OVERWRITE] -> parse_insert            # OVERWRITE is a reserved word
  UPDATE     -> parse_update
  DELETE     -> parse_delete
  MERGE      -> require INTO -> parse_merge                    # 4.x-gated feature
  CREATE     -> parse_create (TEMPORARY|EXTERNAL? TABLE / VIEW / INDEX / MATERIALIZED VIEW)
  _          -> UnsupportedStmt error node + stable diagnostic  # D-12, never silent
```
New SyntaxKind variants needed in syntax.mbt (extend the enum; keep `Statement` wrapper): `Insert`, `Update`, `Delete`, `Merge`, `CreateTable`, `CreateView`, `CreateIndex`, `CreateMaterializedView`, plus reusable `ColumnDefinition`, `KeyClause`, `DistributionClause`, `PartitionClause`, `PropertyList`, `ValueList` kinds. Every kind must obey the existing span/text-length invariants enforced by `SyntaxNode::new` [VERIFIED: syntax/syntax.mbt].

### Pattern 2: Per-family clause sync sets (extends D-04/D-11)

**What:** Each DML/DDL parser defines its own clause-boundary set for best-effort recovery; statement-level panic-mode at `;`/EOF is unchanged. Expression recovery already stops at `)`, `,`, `;`, and `is_clause_keyword` words [VERIFIED: parser/parser.mbt recover_expression].

**Sync-set additions (planning sketch):**
- INSERT: `VALUES`, `SELECT`, `WITH`, `PARTITION`, `WITH`(LABEL), `(` depth
- UPDATE: `SET`, `FROM`, `WHERE`, `ORDER`, `LIMIT`
- DELETE: `PARTITION`, `PARTITIONS`, `USING`, `WHERE`, `ORDER`, `LIMIT`
- MERGE: `USING`, `ON`, `WHEN`, `MATCHED`, `AND`, `THEN`, `UPDATE`, `DELETE`, `INSERT`
- CREATE TABLE: `KEY`, `ORDER`, `BY`, `DISTRIBUTED`, `BUCKETS`, `PARTITION`, `PROPERTIES`, `AS` (CTAS), `LIKE`, `COMMENT`, `ENGINE`

**Caution (Pitfall 5):** `is_clause_keyword` is shared by `recover_expression`, `is_projection_boundary`, and `parse_projection_alias` in the SELECT path. Adding DML words (e.g., `VALUES`, `SET`, `WHEN`) to the *shared* set changes SELECT recovery behavior. Prefer per-family sync sets inside parser functions, or add words only after running the existing SELECT recovery fixtures; keep `recover_expression` semantics stable.

### Pattern 3: Version gates via `introduced_profile` extension (extends D-15)

**What:** Phase 1's `DorisFeature` enum + `profile.supports()` + `DORIS-PARSE-006` mechanism [VERIFIED: token/token.mbt Qualify/Tablet] generalizes into a versioned feature table. MERGE-into is a feature introduced at the 4.x doc tree; `CREATE TABLE ... ORDER BY` at 4.1.0; `INSERT OVERWRITE ... PARTITION (*)` at 2.1.3.

**When to use:** Any production whose introduction version is newer than a supported profile. On gate failure the parser emits the version-invalid diagnostic (DORIS-PARSE-006 precedent) and a source-backed error node — never silent acceptance (D-12). Extend `ProfileMetadata.feature_introduction` strings when the manifest gains DML/DDL features (currently only the three SELECT strings are accepted by `ProfileMetadata::for_manifest` [VERIFIED: token/token.mbt] — the planner MUST extend that validation or fixtures with new feature_introduction values will be rejected).

### Pattern 4: Corpus fixture + layered golden (extends D-17/D-18)

**What:** One manifest row per fixture; SQL text lives in `corpus/doris-{2.1,3.x,4.x}/<category>-<name>.sql` (or inline bytes for non-UTF-8, per Phase 1 precedent). Every supported fixture is asserted three ways: strict validity, `print_result == raw` byte replay, and (where applicable) an editor-mode recovery companion. Malformed/recovery fixtures are explicit rows with `expected-error` classification.

**Manifest row shape (extend Phase 1 columns, do not rename them) [VERIFIED: corpus/manifest.tsv header]:**
```text
fixture_id  profile  exact_release  feature_introduction  official_url  retrieval_date
pinned_source_revision  page_heading  code_fence  category  support_status
parse_mode  classification  provenance_status
```
New categories for Phase 2 (recommend, planner may refine): `dml-insert`, `dml-insert-overwrite`, `dml-update`, `dml-delete`, `dml-merge`, `ddl-create-table`, `ddl-create-table-key`, `ddl-create-table-distribution`, `ddl-create-table-partition`, `ddl-create-table-properties`, `ddl-create-table-ctas`, `ddl-create-table-like`, `ddl-create-view`, `ddl-create-index`, `ddl-create-materialized-view`, `keyword-classification`, `script-multi-statement`, `malformed-recovery`.

**Provenance:** Continue `pinned_source_revision = unavailable-offline` + `known-gap: ...` (established Phase 1 policy; D-17). Every fixture records its versioned official_url (e.g., `https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/INSERT/`). The docs site IS reachable from this environment (verified: all grammar pages below were read via network this session), so retrieval_date + URL are reliable; GitHub commit SHAs remain `unavailable-offline` [VERIFIED: git log shows docs commits; GitHub API known-offline per assignment].

### Pattern 5: CORPUS-REPORT.md generation (D-19)

**What:** A stdlib-Python script reads manifest.tsv + coverage.tsv and renders a version × category matrix (fixture count, supported, expected-error, known-gap), a failure list, and a known-gaps section. The report is checked in; the script is deterministic and offline.

**Report invariants:** every manifest fixture appears in exactly one coverage row; no "full compatibility" claim anywhere; gaps are explicit rows. Add a tiny check step (script `--check` mode) that fails CI-style when the report is stale relative to manifest/coverage — keeps CORPUS-REPORT.md honest (Pitfall 7).

### Pattern 6: Differential harness (CORP-04)

**What:** `corpus/tools/sqlglot_diff.py` parses every `supported`/`expected-error` fixture with `sqlglot.parse(sql, read="doris")`, records `accepted-by-sqlglot` vs `rejected-by-sqlglot`, and writes/extends `differential.tsv` rows with `advisory_only = true` and a version-specific `resolution` (e.g., "docs 4.x document MERGE; sqlglot accepts; SDK follows docs; disagreement recorded").

**FE/Nereids manual script:** `corpus/tools/fe_nereids_diff.sh` (or documented README) that pins an FE version, runs `NereidsParser`-based acceptance over fixtures, and appends rows. It must not run in CI (needs Java build + optionally a cluster; offline-unavailable) — D-20.

### Anti-Patterns to Avoid

- **Global MySQL keyword table as acceptance rule:** Doris is MySQL-protocol-compatible, not grammar-identical; the official reserved list is the base, and MySQL-only words must not silently enter reserved classification [VERIFIED: PITFALLS.md Pitfall 2; reserved list read].
- **Adding DML words to the shared clause-keyword set without regression tests:** changes SELECT recovery (see Pattern 2 caution).
- **Accepting MERGE under 2.1/3.x because FE accepts it:** released-docs authority (D-07) says MERGE is 4.x-doc-only; FE acceptance is advisory only [VERIFIED: 2.1/3.x DML indexes lack MERGE-INTO].
- **One mega-fixture per statement family:** a single INSERT fixture cannot cover VALUES vs SELECT sources, partition/label/hint variants, DEFAULT, multi-row; split per variant so failures localize.
- **Snapshot bulk-update discipline:** never `moon test --update` without reviewing the diff per Pitfall 7.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Differential oracle | A second parser to compare against | SQLGlot 30.14.0 via `sqlglot.parse(sql, read="doris")` [VERIFIED: PyPI 2026-08-04] | Hand-rolling a reference parser doubles maintenance; sqlglot is the established open baseline (D-20). |
| Versioned keyword authority | A merged word list from training/MySQL | Official per-version reserved-keyword pages + FE cross-check (D-13) | The official list is verified identical across 2.1/3.x/4.x; a merged or MySQL list would misclassify. |
| Statement segmentation | Regex `;` splitting | Existing token-level `;` segmentation in `parse_with_limits_context` | Semicolons inside strings/comments are already lexer-absorbed; regex splitting corrupts them (PITFALLS anti-feature). |
| Error recovery per new statement | A new recovery mechanism | Per-family sync sets over the existing progress-or-error/panic-mode machinery (D-04/D-11) | New mechanisms introduce cascade bugs; extend sync sets, not architecture. |
| Coverage "100%" claims | Publishing an unqualified compatibility badge | CORPUS-REPORT.md matrix + known-gaps + failure list (D-19) | Unqualified claims are trust liabilities (FEATURES.md anti-feature). |
| Analyzer coupling | Catalog lookups inside the parser | `analyzer/` package consuming CST with injected Catalog (D-21) | Catalog in the parser breaks offline/browser use and the syntax/semantic diagnostic split. |

**Key insight:** Phase 2's risk is not "which grammar to write" — the official docs provide it — but **discipline**: every new production needs a version gate, a lossless-replay assertion, a sync-set decision, and a fixture row. The corpus and the dispatch table are the two integration points that keep the expansion auditable.

## Common Pitfalls

### Pitfall 1: MERGE accepted under 2.1/3.x (version drift in the other direction)
**What goes wrong:** MERGE INTO parses in every profile, silently claiming 2.1 support the released docs do not document.
**Why it happens:** FE history introduced MERGE earlier (training knowledge), and the parser naturally accepts any implemented production.
**How to avoid:** Gate MERGE behind a 4.x-doc `introduced_profile`-style feature; 2.1/3.x emits DORIS-PARSE-006-class version diagnostics (D-15). Add a negative fixture per version.
**Warning signs:** A 2.1-profile fixture containing MERGE returns `valid = true`.
**Evidence:** 2.1 and 3.x DML indexes verified to lack MERGE-INTO; 4.x index and page verified present [VERIFIED: all three DML indexes + MERGE-INTO page read 2026-08-04]. FE introduction history [ASSUMED] and irrelevant to docs authority.

### Pitfall 2: Keyword-as-identifier misclassification in DDL contexts
**What goes wrong:** A column named `key`, `comment`, `value`, `bucket`, `order` or a property key named `replication_num`-adjacent word is rejected, or a reserved word is silently consumed as an identifier.
**Why it happens:** Doris's reserved list is broad but not exhaustive of grammar words; e.g., `BUCKETS`, `PROPERTIES`, `COMMENT`, `AGGREGATE`, `ENGINE`, `ROLLUP`, `ALIAS` are NOT in the official reserved list [VERIFIED: reserved list read; those words absent], yet they are grammar words that must be recognized in clause position while remaining usable as identifiers elsewhere.
**How to avoid:** Three-layer classification (D-14): reserved → require backticks; non-reserved grammar words → recognized in clause position, accepted as unquoted identifiers elsewhere; contextual (e.g., `TABLET`, `QUALIFY`, `ROLLUP` clause words) → accepted only in their clause. Pair positive/negative tests: each classification word as identifier, alias, property key, quoted name, and clause keyword.
**Warning signs:** DDL fixtures fail on ordinary column names; or `is_reserved_word` grows with every grammar word, breaking `SELECT bucket FROM t`.

### Pitfall 3: DML words leaking into SELECT recovery
**What goes wrong:** Adding `VALUES`/`SET`/`WHEN` to the shared `is_clause_keyword` set changes SELECT projection/expression recovery (e.g., `SELECT a FROM t SET x` now recovers differently), breaking existing goldens.
**Why it happens:** `is_clause_keyword` is shared by `recover_expression`, `is_projection_boundary`, `parse_projection_alias` [VERIFIED: parser/parser.mbt].
**How to avoid:** Prefer per-family sync sets inside DML parser functions; if the shared set grows, re-run every Phase 1 SELECT recovery fixture and the `SELECT a + 1; bad; SELECT b` script tests before merging.
**Warning signs:** Phase 1 parser/recovery tests change output after adding DML support.

### Pitfall 4: Lossless replay breaks for new statements
**What goes wrong:** A new CST kind or recovery path drops bytes (e.g., property-value quotes, `PARTITION BY` parentheses, trailing semicolon trivia, `DEFAULT` values).
**Why it happens:** New parse functions construct nodes from consumed tokens without preserving all leaves, or synthetic missing nodes overlap real spans.
**How to avoid:** Every new family gets a round-trip test: `@printer.print_result(parse(raw)) == raw` for each fixture (existing pattern in test/parser_test.mbt [VERIFIED]); keep `SyntaxNode::new` span invariants; zero-width missing only.
**Warning signs:** `print_result` differs from input on any DML/DDL fixture.

### Pitfall 5: Recovery cascades across statement boundaries in scripts
**What goes wrong:** A malformed CREATE TABLE (e.g., unclosed `(`) swallows the following `INSERT ...; SELECT ...` statements, or produces dozens of cascading diagnostics.
**Why it happens:** Parenthesis depth tracking plus too-wide sync sets let a single error consume the rest of the document.
**How to avoid:** Keep statement-level sync at `;`/EOF (existing); bound recovery steps/diagnostics (existing limits); add script fixtures like `CREATE TABLE t (a INT; INSERT INTO t VALUES (1); SELECT * FROM t` and assert later statements still appear as separate Statement nodes with distinct statement_ids (DORIS-03 shape).
**Warning signs:** Fixture `bad CREATE; good INSERT` yields one statement node spanning both.

### Pitfall 6: Corpus pollution and stale reports
**What goes wrong:** Shell prompts, `mysql>` output blocks, `Query OK` results, or placeholder variables (`<col_name>`) from docs get saved as fixtures; or coverage.tsv drifts from manifest.tsv.
**Why it happens:** Docs pages mix syntax blocks, examples, and output (verified on every page read this session — e.g., INSERT page contains `mysql> insert ...` blocks and `{'label':...}` JSON outputs).
**How to avoid:** Extract only `sql` code-fence blocks that are standalone statements; classify each as `parse-only` vs `requires-session` vs `not-sql`; run the report generator's `--check` mode in CI-style gate so stale reports fail.
**Warning signs:** Fixture SQL containing `mysql>` prompts or `Query OK` lines.

### Pitfall 7: Analyzer coupling creeping back
**What goes wrong:** Someone adds table-name validation inside `parse_create` "because it's easy", making syntax results depend on catalog state.
**Why it happens:** DDL gives strong temptation to resolve names at parse time.
**How to avoid:** Enforce the package boundary (parser never imports analyzer — verify via moon.pkg), keep `valid` purely syntactic, and document that catalog diagnostics are a separate result channel (D-21/D-24).
**Warning signs:** parser/moon.pkg imports analyzer, or syntax tests require catalog fixtures.

## Code Examples

Verified patterns from official Apache Doris docs (read directly 2026-08-04) plus project-shape sketches.

### 1. INSERT — official 4.x grammar (verbatim from docs)

```sql
INSERT INTO table_name
    [ PARTITION (p1, ...) ]
    [ WITH LABEL label]
    [ (column [, ...]) ]
    [ [ hint [, ...] ] ]
    { VALUES ( { expression | DEFAULT } [, ...] ) [, ...] | query }
```
- Hints are one of `/*+ STREAMING */`, `/*+ SHUFFLE */`, `/*+ NOSHUFFLE */` (verbatim parameter list on the INSERT page).
- Examples (verbatim): `INSERT INTO test VALUES (1, 2);`, `INSERT INTO test (c1, c2) VALUES (1, DEFAULT);`, `INSERT INTO test SELECT * FROM test2;`, `INSERT INTO test PARTITION(p1, p2) WITH LABEL `label1` SELECT * FROM test2;`
- Source: <https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/INSERT/>

### 2. INSERT OVERWRITE — official 4.x grammar (verbatim)

```sql
INSERT OVERWRITE table table_name
    [ PARTITION (p1, ... | *) ]
    [ WITH LABEL label]
    [ (column [, ...]) ]
    [ [ hint [, ...] ] ]
    { VALUES ( { expression | DEFAULT } [, ...] ) [, ...] | query }
```
- Note the literal keyword `table` after OVERWRITE (legacy Doris syntax).
- `PARTITION (*)` (auto-detect partition) "is supported since Apache Doris 2.1.3 version" [CITED: INSERT-OVERWRITE page note].
- Source: <https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/INSERT-OVERWRITE/>

### 3. UPDATE — official 4.x grammar (verbatim; UNIQUE KEY model only)

```sql
[cte]
UPDATE target_table [table_alias]
    SET assignment_list
    [ FROM additional_tables]
    [WHERE condition]
    [ORDER BY column [ASC | DESC] [NULLS FIRST | NULLS LAST] [, ...]]
    [LIMIT [offset,] count]
```
- `assignment_list` is `col_name = value, col_name = value`; FROM joins are supported (example `UPDATE t1 SET t1.c1 = t2.c1 FROM t2 INNER JOIN t3 ON t2.id = t3.id WHERE t1.id = t2.id;`).
- Source: <https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/UPDATE/>

### 4. DELETE — official 4.x grammar, two forms (verbatim)

```sql
-- Syntax 1 (predicate-only; op in =, >, <, >=, <=, !=, in, not in):
DELETE FROM table_name [PARTITION partition_name | PARTITIONS (partition_name [, partition_name])]
WHERE
column_name op { value | value_list } [ AND column_name op { value | value_list } ...];

-- Syntax 2 (UNIQUE KEY model only):
[cte]
DELETE FROM table_name
    [PARTITION partition_name | PARTITIONS (partition_name [, partition_name])]
    [USING additional_tables]
    [WHERE condition]
    [ORDER BY column [ASC | DESC] [NULLS FIRST | NULLS LAST] [, ...]]
    [LIMIT [offset,] count]
```
- Source: <https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/DELETE/>

### 5. MERGE INTO — official 4.x grammar (verbatim; UNIQUE KEY model; 4.x docs only)

```sql
MERGE INTO <target_table>
    USING <source>
    ON <join_expr>
    { matchedClause | notMatchedClause } [ ... ]

matchedClause ::=
    WHEN MATCHED [ AND <case_predicate> ]
        THEN { UPDATE SET <col_name> = <expr> [ , <col_name> = <expr> ... ] | DELETE }

notMatchedClause ::=
    WHEN NOT MATCHED [ AND <case_predicate> ]
        THEN INSERT [ ( <col_name> [ , ... ] ) ] VALUES ( <expr> [ , ... ] )
```
- Version gate: page exists only under `docs/4.x/.../data-modification/DML/`; 2.1 and 3.x DML indexes do not list MERGE-INTO [VERIFIED: indexes read]. Example in docs uses `WITH tmp AS (...) MERGE INTO ...`.
- Source: <https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/MERGE-INTO/>

### 6. CREATE TABLE — official 4.x grammar (verbatim core)

```sql
CREATE [ TEMPORARY | EXTERNAL ] TABLE [ IF NOT EXISTS ] <table_name>
    (<columns_definition> [ <indexes_definition> ])
    [ ENGINE = <table_engine_type> ]
    [ <key_type> KEY (<key_cols>) [ ORDER BY (<cluster_cols>) ] ]
    [ COMMENT '<table_comment>' ]
    [ <partitions_definition> ]
    [ DISTRIBUTED BY { HASH (<distribute_cols>) | RANDOM } [ BUCKETS { <bucket_count> | AUTO } ] ]
    [ <roll_up_definition> ]
    [ PROPERTIES ( <table_property> [ , ... ]) ]

columns_definition:
    <col_name> <col_type>
      [ KEY ] [ <col_aggregate_type> ]
      [ [ GENERATED ALWAYS ] AS (<col_generate_expression>) ]
      [ [NOT] NULL ] [ AUTO_INCREMENT(<start>) ]
      [ DEFAULT <col_default_value> ] [ ON UPDATE CURRENT_TIMESTAMP (<precision>) ]
      [ COMMENT '<col_comment>' ] [ , ... ]

indexes_definition:
    INDEX [ IF NOT EXISTS ] <index_name> (<index_cols>)
      [ USING <index_type> ] [ PROPERTIES ( ... ) ] [ COMMENT '<index_comment>' ] [ , ... ]

partitions_definition:
    AUTO PARTITION BY RANGE(<auto_partition_function>(<args>)) <origin_partitions_definition>
  | AUTO PARTITION BY LIST(<partition_cols>) <origin_partitions_definition>
  | PARTITION BY <partition_type> (<partition_cols>) <origin_partitions_definition>

one_partition_definition:
    PARTITION [ IF NOT EXISTS ] <partition_name> VALUES LESS THAN <partition_value_list>
  | PARTITION [ IF NOT EXISTS ] <partition_name> VALUES [ <lower>, <upper>)
  | FROM <lower> TO <upper> INTERVAL <n> [ <datetime_unit> ]
  | PARTITION [ IF NOT EXISTS ] <partition_name> VALUES IN { (<partition_value> [ , ... ]) | <partition_value> }

roll_up_definition:
    ROLLUP ( <rollup_name> (<rollup_cols>) [ DUPLICATE KEY (<duplicate_cols>) ] [ , ... ] )
```
- `<key_type>` is `DUPLICATE` | `UNIQUE` | `AGGREGATE` (verbatim parameter text: "Optional values are DUPLICATE (detail model), UNIQUE (primary key model), AGGREGATE (aggregation model)").
- `<col_aggregate_type>` applies to AGGREGATE-model value columns.
- Note (verbatim): "`ORDER BY` is supported since 4.1.0".
- CTAS variant: `CREATE [ EXTERNAL ] TABLE [ IF NOT EXISTS ] <table_name> [ (<column_definitions>) ] [ <index_definitions> ] [ ENGINE = ... ] [ <key_type> KEY ... ] [ COMMENT ... ] [ <partition_definitions> ] [ DISTRIBUTED BY ... ] [ <rollup_definitions> ] [ PROPERTIES ( ... ) ] [ AS ] <query>;`
- LIKE variant: `CREATE TABLE <new_table_name> LIKE <existing_table_name> [ WITH ROLLUP ( <rollup_list> ) ];`
- Column types (from data-type-overview, verbatim family names): BOOLEAN; TINYINT/SMALLINT/INT/BIGINT/LARGEINT; FLOAT/DOUBLE; DECIMAL; DATE/TIME/DATETIME/TIMESTAMPTZ; CHAR(M)/VARCHAR(M)/STRING; VARBINARY (since 4.0, not for table storage); ARRAY/MAP/STRUCT/VARIANT/JSON; BITMAP/HLL/QUANTILE_STATE/AGG_STATE; IPv4/IPv6.
- Sources: <https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/> and <https://doris.apache.org/docs/4.x/sql-manual/basic-element/sql-data-types/data-type-overview/>

### 7. CREATE VIEW — official 4.x grammar (verbatim)

```sql
CREATE VIEW [IF NOT EXISTS] [<db_name>.]<view_name>
   [(<column_definition>)]
[AS] <query_stmt>

column_definition:
    <column_name> [COMMENT '<comment>'] [,...]
```
- No view-level `WITH` attribute exists on this page; the view body `<query_stmt>` may itself be a CTE query (`WITH ... SELECT ...`), which the existing `parse_query` already handles [VERIFIED: CREATE VIEW page read; WITH-clause-as-body is [ASSUMED] but consistent with the query grammar].
- Source: <https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/view/CREATE-VIEW/>

### 8. CREATE INDEX — official 4.x grammar (verbatim)

```sql
CREATE INDEX [IF NOT EXISTS] <index_name>
             ON <table_name> (<column_name> [, ...])
             [USING {INVERTED | NGRAM_BF | ANN}]
             [PROPERTIES ("<key>" = "<value>"[ , ...])]
             [COMMENT '<index_comment>']
```
- Examples: `CREATE INDEX index1 ON table1(col1) USING INVERTED;`, `CREATE INDEX index2 ON table1(col1) USING NGRAM_BF PROPERTIES("gram_size"="3", "bf_size"="1024");`, ANN example with `"index_type"="hnsw", "metric_type"="l2_distance", "dim"="128"`.
- Source: <https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/index/CREATE-INDEX/>

### 9. CREATE MATERIALIZED VIEW (sync) — official 4.x grammar (verbatim)

```sql
CREATE MATERIALIZED VIEW <materialized_view_name> [AS] <query>

query:
    SELECT <select_expr> [, <select_expr> ...]
    FROM <base_table>
    [WHERE condition]
    [GROUP BY <column_name> [, ...]]
    [ORDER BY <column_name> [, ...]]
```
- Constraint notes (verbatim): single base table (no subquery); "not JOIN, HAVING, LIMIT clauses, or LATERAL VIEW"; aggregate functions must be root expressions. An async-materialized-view family (`CREATE ASYNC MATERIALIZED VIEW`, with BUILD/REFRESH clauses) exists under `table-and-view/async-materialized-view/` since ~2.1 [ASSUMED: async MV syntax not read this session; sync form verified].
- Source: <https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/sync-materialized-view/CREATE-MATERIALIZED-VIEW/>

### 10. Keyword classification TSV (D-16 shape)

```text
word            classification  introduced_profile  source
SELECT          reserved        2.1                 https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/
TABLET          contextual      3.x                 https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/ (TABLET clause); token.mbt DorisFeature::Tablet
QUALIFY         contextual      3.x                 token.mbt DorisFeature::Qualify (introduced_profile "3.x", DORIS-PARSE-006)
MERGE           reserved        4.x                 https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/MERGE-INTO/ (4.x-doc only)
BUCKETS         non-reserved    2.1                 https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/ (absent from reserved list)
PROPERTIES      non-reserved    2.1                 same source (absent from reserved list)
```
- Every word used by parser productions must have a row (single source of truth, PITFALLS Pitfall 14).

### 11. Statement dispatch + DORIS-03 test shape (project sketch, MoonBit)

```moonbit
// Sketch — planner discretion. Mirrors existing parse_segment structure.
fn parse_segment(stream, start_index, end_index, statement_id, state) -> @syntax.SyntaxNode {
  let first = significant_first_raw(stream, start_index, end_index)
  let parsed = match first {
    Some(raw) if bytes_equal_ci(raw, b"SELECT") || bytes_equal_ci(raw, b"WITH") => parse_query(...)
    Some(raw) if bytes_equal_ci(raw, b"INSERT") => parse_insert(...)
    Some(raw) if bytes_equal_ci(raw, b"UPDATE") => parse_update(...)
    Some(raw) if bytes_equal_ci(raw, b"DELETE") => parse_delete(...)
    Some(raw) if bytes_equal_ci(raw, b"MERGE") => parse_merge(...)  // feature-gated 4.x
    Some(raw) if bytes_equal_ci(raw, b"CREATE") => parse_create(...)
    _ => unsupported_statement(...)  // D-12: explicit error node + stable diagnostic
  }
  // trailing `;`/recovery loop, Statement wrapper, statement_id increment: unchanged
}
```

```moonbit
// DORIS-03 test shape (extends test/parser_test.mbt pattern [VERIFIED])
test "invalid_dml_does_not_discard_later_statements" {
  let raw = b"INSERT INTO t VALUES (1); bad; SELECT b"
  let result = match @api.parse_with_ids(raw, "4.x", "strict") { Ok(r) => r; Err(_) => panic() }
  assert_eq(result.root.children.length(), 3)        // 3 Statement nodes
  assert_true(!result.valid)
  assert_eq(result.diagnostics[0].statement_id, 1U)  // localized to the bad statement
  assert_eq(@printer.print_result(result), raw)      // byte-exact replay
}
```

### 12. Analyzer boundary (D-21..D-24 sketch, MoonBit)

```moonbit
// analyzer/moon.pkg
pkgtype(kind: "library")
import { "fathom/doris-sql/syntax" @syntax }

// analyzer/analyzer.mbt — minimal name-resolution-level catalog (D-22)
pub struct ColumnInfo { pub name : String, pub data_type : String }
pub struct TableInfo { pub name : String, pub columns : Array[ColumnInfo] }

pub trait Catalog {
  fn table(self, name : String) -> TableInfo?
}

pub struct StaticCatalog {
  tables : Map[String, TableInfo]
}

pub fn StaticCatalog::lookup(self : StaticCatalog, name : String) -> TableInfo? {
  self.tables.get(name)
}

// Deliverable: interface + docs + minimal implementation (D-24).
// Full ANAL-01 name resolution/type diagnostics are v2 — not promised here.
```

### 13. SQLGlot differential script shape (corpus/tools/sqlglot_diff.py)

```python
"""Advisory differential vs SQLGlot (D-20). NOT a public contract."""
import csv, sqlglot  # pin sqlglot==30.14.0

def parse_fixture(sql: str) -> bool:
    try:
        sqlglot.parse(sql, read="doris")
        return True
    except Exception:
        return False

def main(manifest_path: str, out_path: str) -> None:
    rows = []
    with open(manifest_path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh, delimiter="\t"):
            sql_path = f"corpus/doris-{row['profile']}/{row['fixture_id']}.sql"
            with open(sql_path, encoding="utf-8") as sql_fh:
                accepted = parse_fixture(sql_fh.read())
            rows.append({
                "fixture_id": row["fixture_id"],
                "sqlglot_version": sqlglot.__version__,
                "sqlglot_accepted": accepted,
                "resolution": "recorded disagreement; SDK follows released docs authority",
                "advisory_only": "true",
            })
    with open(out_path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]), delimiter="\t")
        writer.writeheader(); writer.writerows(rows)

if __name__ == "__main__":
    main("corpus/manifest.tsv", "corpus/differential.tsv")
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SELECT-only statement dispatch with `DORIS-PARSE-001` for all else | Keyword-first dispatch (INSERT/UPDATE/DELETE/MERGE/CREATE + explicit unsupported nodes) | Phase 2 | Unknown statement starters become explicit unsupported diagnostics instead of "expected SELECT" (D-11/D-12). |
| Three fixed SELECT feature_introduction strings in `ProfileMetadata::for_manifest` | Extended metadata strings covering DML/DDL features (planner must extend validation) | Phase 2 | New fixtures with DML feature metadata parse; old code rejects them today [VERIFIED: token/token.mbt]. |
| Reserved-word set assumed version-dependent | Reserved list verified byte-identical across 2.1/3.x/4.x; gates move to feature introduction | This research | Classification work concentrates on non-reserved/contextual layers + feature gates, not per-version reserved diffs. |
| MERGE treated as generally available | MERGE gated to 4.x released-docs authority | This research (docs-index evidence) | 2.1/3.x profiles reject MERGE with version diagnostics; no false compatibility claim. |
| Corpus = 15 SELECT-only rows | Corpus extended with DML/DDL categories, versioned fixture dirs, keyword TSV, CORPUS-REPORT.md | Phase 2 | Coverage becomes inspectable per version × category with honest gaps (CORP-03). |
| Differential not runnable offline | SQLGlot 30.14.0 local script; FE/Nereids documented manual script | Phase 2 | Disagreements recorded with version-specific resolutions; neither becomes the contract (CORP-04). |
| No analyzer package | `analyzer/` package with minimal Catalog trait/record; parser zero-dependency | Phase 2 | Syntax-only path untouched; ANAL-01 full resolution deferred to v2 (D-24). |

**Deprecated/outdated:**
- Treating the reserved-word list as the *only* classification input: the verified list is identical across versions and omits grammar words like `BUCKETS`/`PROPERTIES`/`COMMENT`/`ENGINE`/`AGGREGATE`/`ROLLUP`, so reserved-only classification misclassifies non-reserved grammar words (Pitfall 2).
- Silent "expected SELECT statement" for every unknown statement: replaced by explicit unsupported-statement nodes (D-12).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | MERGE INTO's FE implementation history (e.g., introduced ~2.1 in FE) is irrelevant to acceptance; docs (4.x-only) remain the authority. | Summary / Pitfall 1 | If reviewers insist on FE-based 2.1 acceptance, the gate decision changes; docs authority (D-07) currently says 4.x only. |
| A2 | `CREATE ASYNC MATERIALIZED VIEW` (with BUILD/REFRESH clauses) exists since ~2.1; not verified this session. | CREATE MV example | If async MV is in scope, its syntax needs its own page read; D-10 puts MATERIALIZED VIEW last, sync form verified. |
| A3 | `BUCKETS AUTO` introduction is 3.x; `AUTO PARTITION BY` introduction is 2.1. | CREATE TABLE example | Wrong gates would accept version-invalid fixtures; verify against 2.1/3.x CREATE TABLE pages before locking fixtures. |
| A4 | `TIMESTAMPTZ` and `VARBINARY` availability: VARBINARY "since 4.0; not for table storage" is stated in docs [CITED]; TIMESTAMPTZ introduction version assumed. | Data types | Type-list gates may need per-type introduction metadata in the keyword/type TSV. |
| A5 | No Oracle-style multi-table INSERT (INSERT ALL/FIRST) in Doris docs; INSERT source can be any query (multi-table FROM). | INSERT example | If a multi-table INSERT form exists in docs, it needs a fixture; absence from the 4.x INSERT page is evidence, not proof. |
| A6 | The recommended new SyntaxKind names and sync-set lists are planner-negotiable sketches; only the behavioral contracts (lossless replay, version gates, explicit unsupported nodes) are locked. | Patterns 1-2 | Renaming kinds is cheap before implementation; behavioral contracts are not. |
| A7 | Python stdlib-only corpus tooling is sufficient and preferable to adding MoonBit file-I/O to the core. | Standard Stack | If a MoonBit report generator is preferred, it must live outside parser core packages. |
| A8 | Docs site reachability observed this session persists for execution-time fixture retrieval; GitHub commit SHA lookups remain offline. | Corpus | Execution may still need to record `unavailable-offline` revisions per D-17. |

## Open Questions (RESOLVED)

1. **CREATE VIEW "WITH clause" scope**
   - What we know: the 4.x CREATE VIEW page documents only `[AS] <query_stmt>` with optional column definitions; no view-level WITH attribute [VERIFIED: page read]. A CTE-bodied view (`CREATE VIEW v AS WITH cte AS (...) SELECT ...`) is a query the existing parser already accepts.
   - What's unclear: whether the requirement text "CREATE VIEW (incl. WITH clause)" refers to CTE bodies (covered) or an undocumented view attribute.
   - Recommendation: implement the documented grammar; add one CTE-bodied-view fixture; flag any `WITH` view-attribute usage as a known-gap until a docs source is found.
   - **Resolution:** Q1 → 02-02 Task 2: the documented grammar is implemented (CTE-bodied views parse via parse_query); WITH view-attribute usage is flagged in 02-02 must_haves (Open Q1 flagged assumption) and lands as a known-gap row in the 02-04 corpus wave.

2. **Exact 2.1/3.x CREATE TABLE gates** (`BUCKETS AUTO`, `AUTO PARTITION BY`, generated columns, `AUTO_INCREMENT`)
   - What we know: 4.x page notes `ORDER BY` since 4.1.0; MERGE 4.x-doc-only; reserved list identical.
   - What's unclear: per-clause introduction versions for AUTO partitioning/buckets in 2.1/3.x docs.
   - Recommendation: during the corpus wave, read the 2.1 and 3.x CREATE TABLE pages (reachable) and record `feature_introduction` per clause before writing 2.1/3.x fixtures; until then treat those as [ASSUMED] A3.
   - **Resolution:** Q2 → 02-02 flagged assumption A3 (assumed gates recorded) + 02-04 Task 2 (re-reads the reachable 2.1/3.x CREATE TABLE pages, amends token.mbt DorisFeature rows or records known-gap rows).

3. **New diagnostic codes for unsupported statements**
   - What we know: DORIS-PARSE-001..006 are in use (001 statement-level, 002 incomplete, 003 lexical, 004 resource, 006 feature-version) [VERIFIED: api.mbt/parser.mbt/token.mbt tests].
   - What's unclear: the exact code and expected_class for D-12's unsupported-statement node (e.g., DORIS-PARSE-007 `unsupported statement in selected profile`).
   - Recommendation: reserve DORIS-PARSE-007+ in the planner's design and record them in the diagnostic table before implementation.
   - **Resolution:** Q3 → 02-01 (Tasks 1 and 3): DORIS-PARSE-007 is reserved and implemented as the stable unsupported-statement diagnostic (D-12); 008+ stays reserved.

4. **Snapshot tooling maturity in this repo**
   - What we know: Phase 1 used inline asserts + `print_result` round-trip; no snapshot files were observed in the repo tree [VERIFIED: tree read].
   - What's unclear: whether `moon test --update`/`@test.T::snapshot` goldens should be introduced now or later.
   - Recommendation: introduce CST-shape snapshots per statement family only if `moon test --update` works with the pinned toolchain; otherwise keep the Phase 1 assert-based golden style (it already covers strict/replay/recovery).
   - **Resolution:** Q4 → Phase 1 assert-based goldens retained: 02-04 fixtures assert print_result == raw / all_spans_in_bounds without introducing snapshot-tooling dependency (no moon test --update requirement).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| MoonBit `moon` | All parser work | ✓ | `moon 0.1.20260724 (5f1406a 2026-07-24)` [VERIFIED: probe] | Pin/upgrade per policy; no fallback. |
| Python 3 + pip | SQLGlot differential, corpus report tooling | ✓ | Python 3.9, pip 24.3.1 [VERIFIED: probe] | — |
| SQLGlot | Differential (CORP-04) | ✗ not installed; ✓ registry reachable | 30.14.0 latest [VERIFIED: `pip index versions sqlglot`] | Install step `pip install "sqlglot==30.14.0"` before differential runs; pin in requirements. |
| PyPI network | sqlglot install | ✓ | reachable 2026-08-04 [VERIFIED: probe] | — |
| Doris docs site | Fixture retrieval/URLs | ✓ | reachable 2026-08-04 (all grammar pages read via network) [VERIFIED: probes] | Record `unavailable-offline` if it later fails. |
| GitHub API | Revision lookups | ✗ | empty results (assignment; Phase 1 precedent) | `unavailable-offline` + `known-gap` provenance (D-17). |
| Java/Maven + Doris FE | FE/Nereids differential | ✗ (not probed; decision D-20 states offline-unavailable) | — | Manual documented script only; never CI. |
| Git | Provenance/commits | ✓ | 2.47.3 [VERIFIED: probe] | — |
| Node.js | Not required by Phase 2 core | ✓ | v25.2.0 | Do not add Node runtime dependency. |

**Missing dependencies with no fallback:** none — the parser core needs only the MoonBit toolchain already present.
**Missing dependencies with fallback:** SQLGlot (install from reachable PyPI, pinned); FE/Nereids (manual script, out of CI).

## Validation Architecture

Skipped: `.planning/config.json` sets `workflow.nyquist_validation: false` [VERIFIED: .planning/config.json]. Per the research output contract, this section is omitted; the plan still carries the project's own layered golden requirements (byte-exact replay, strict/editor paired fixtures, version-negative fixtures) as phase deliverables, not as a Nyquist gate.

## Security Domain

`.planning/config.json` enables `security_enforcement: true` at ASVS level 1 [VERIFIED: .planning/config.json]. Phase 2 expands the untrusted-input surface (multi-statement scripts, DDL bodies, corpus files) but remains pure syntax processing — no SQL execution, no database, no filesystem/network in the core.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | No credentials/sessions in parser core; adapters own auth (unchanged from Phase 1). |
| V3 Session Management | No | No session state; `statement_id` is a per-snapshot parse artifact, not a session. |
| V4 Access Control | Limited | No catalog/filesystem access from parser core; analyzer receives caller-provided Catalog only. |
| V5 Input Validation | Yes | Byte/token/recursion/recovery/diagnostic caps already enforced via `ParseLimits` [VERIFIED: api/api.mbt, parser/parser.mbt]; profile and mode validated; new grammar must not bypass limits. |
| V6 Cryptography | No | No cryptographic operations. |

### Known Threat Patterns for {stack}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Script with thousands of statements / pathological DDL nesting causes resource exhaustion | Denial of Service | Existing `ParseLimits` (max_bytes 8 MiB, max_tokens 1M, depth 128, recovery steps 10k, diagnostics 100) [VERIFIED: parser/parser.mbt defaults]; add a script-statement-count stress fixture. |
| Recovery loop inside malformed DML body (e.g., unclosed `(` in CREATE TABLE) swallows document | Denial of Service / Integrity | Progress-or-error invariant + recovery-step cap + statement-level `;` sync; DORIS-03 script fixtures assert later statements survive. |
| Huge property lists / long string literals in DDL | DoS | Pre-parse byte cap and source-backed leaves (no per-token copies); extend Phase 1 adversarial fixtures to DDL. |
| Untrusted SQL reaches execution or filesystem | Tampering / Elevation | Core remains pure syntax; differential scripts parse only and never execute against a cluster; FE script documented manual-only. |
| Keyword-table or corpus file tampering/integrity drift | Tampering | keywords.tsv single source of truth (Pitfall 14), report `--check` mode fails on stale CORPUS-REPORT.md, fixture provenance fields audited in review. |
| Byte/UTF-16 confusion in new statement spans | Tampering | Canonical byte spans unchanged; new kinds must satisfy `SyntaxNode` span invariants and `all_spans_in_bounds` [VERIFIED: api/api.mbt]. |

## Sources

### Primary (HIGH confidence — all read directly this session, 2026-08-04)

- [INSERT — Apache Doris 4.x](https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/INSERT/) — grammar, hints, examples, keywords (verbatim).
- [INSERT OVERWRITE — Apache Doris 4.x](https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/INSERT-OVERWRITE/) — grammar, `PARTITION (*)` since 2.1.3 note, examples.
- [UPDATE — Apache Doris 4.x](https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/UPDATE/) — grammar (CTE/FROM/ORDER/LIMIT), UNIQUE-model constraint, examples.
- [DELETE — Apache Doris 4.x](https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/DELETE/) — two syntaxes, op list, USING clause, examples.
- [MERGE-INTO — Apache Doris 4.x](https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/MERGE-INTO/) — full grammar, matched/not-matched clauses, UNIQUE-model constraint.
- [CREATE TABLE — Apache Doris 4.x](https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/) — full grammar, CTAS/LIKE variants, `ORDER BY` since 4.1.0 note, properties table, examples.
- [CREATE VIEW — Apache Doris 4.x](https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/view/CREATE-VIEW/) — grammar, column definitions, examples.
- [CREATE INDEX — Apache Doris 4.x](https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/index/CREATE-INDEX/) — grammar, INVERTED/NGRAM_BF/ANN examples.
- [CREATE SYNC MATERIALIZED VIEW — Apache Doris 4.x](https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/sync-materialized-view/CREATE-MATERIALIZED-VIEW/) — grammar, single-table constraint notes, example.
- [Reserved Keywords — Apache Doris 2.1](https://doris.apache.org/docs/2.1/sql-manual/basic-element/reserved-keywords/), [3.x](https://doris.apache.org/docs/3.x/sql-manual/basic-element/reserved-keywords/), [4.x](https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/) — lists read verbatim; verified identical across versions.
- [SQL Data Types Overview — Apache Doris 4.x](https://doris.apache.org/docs/4.x/sql-manual/basic-element/sql-data-types/data-type-overview/) — numeric/date/string/binary/semi-structured/aggregation/IP type families.
- DML statement indexes for [2.1](https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-modification/DML/), [3.x](https://doris.apache.org/docs/3.x/sql-manual/sql-statements/data-modification/DML/), [4.x](https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/) — MERGE-INTO present only in 4.x.
- [SQL statements index (4.x)](https://doris.apache.org/docs/4.x/sql-manual/sql-statements/) and [table-and-view index (4.x)](https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/) — section layout.
- PyPI index probe: `pip index versions sqlglot` → `sqlglot (30.14.0)` (2026-08-04).
- Local repo evidence (read this session): `.planning/phases/02-doris-completeness-and-corpus/02-CONTEXT.md`, `.planning/REQUIREMENTS.md`, `.planning/STATE.md`, `.planning/ROADMAP.md`, `.planning/config.json`, `.planning/research/{SUMMARY,STACK,ARCHITECTURE,PITFALLS,FEATURES}.md`, `.planning/phases/01-core-kernel/01-{CONTEXT,RESEARCH,PATTERNS}.md`, `api/api.mbt`, `token/token.mbt`, `parser/parser.mbt`, `syntax/syntax.mbt`, `printer/printer.mbt`, `moon.mod`, `moon.pkg`, `api/moon.pkg`, `parser/moon.pkg`, `source/moon.pkg`, `corpus/{manifest,coverage,differential}.tsv`, `corpus/doris-*/select-industrial.sql`, `test/parser_test.mbt`.

### Secondary (MEDIUM confidence)

- `.planning/research/FEATURES.md` — SQLGlot Doris dialect facts (subclasses MySQL, lenient AST regeneration), GSP differential precedent, Doris 4.x SELECT/CREATE-TABLE URL evidence.
- `.planning/research/PITFALLS.md` — keyword misclassification, corpus contamination, recovery cascade, snapshot-update discipline (engineering-inference evidence level LOW per that doc, applied here as design constraints).

### Tertiary (LOW confidence / ASSUMED — see Assumptions Log)

- FE history of MERGE INTO (~2.1), async materialized view syntax/since (~2.1), `BUCKETS AUTO`/`AUTO PARTITION BY` introduction versions, TIMESTAMPTZ introduction, absence of Oracle-style multi-table INSERT, view-body CTE acceptance. All require doc or fixture verification before they become locked decisions.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — toolchain and package versions probed; SQLGlot verified on PyPI; no new MoonBit runtime deps.
- Architecture: HIGH for the extension points (dispatch in `parse_segment`, gates in `token.mbt`, analyzer package boundary — all read this session); MEDIUM for exact SyntaxKind/sync-set names (planner discretion per D-11/Claude's Discretion).
- Doris grammar: HIGH for 4.x DML/DDL grammars and reserved lists (verbatim reads); MEDIUM for 2.1/3.x per-clause gates (only doc presence and stated feature-introduction notes verified).
- Corpus/differential/analyzer engineering: MEDIUM — prescriptive design consistent with D-17..D-24 and Phase 1 precedents.

**Research date:** 2026-08-04
**Valid until:** 2026-09-03 (30 days) for Doris docs syntax — re-read the pinned pages when the released corpus moves; MoonBit toolchain pin already recorded; SQLGlot pin 30.14.0 should be rechecked before each differential run.
