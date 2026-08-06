# Feature Research

**Domain:** Flink SQL 多方言解析、编辑器与 SDK 工具链（Fathom v2.0）  
**Researched:** 2026-08-06  
**Confidence:** MEDIUM-HIGH

## Feature Landscape

本清单把“table stakes”定义为：在现有 Doris v1 SDK 已经提供的同类能力上，Flink 用户如果不能得到，就无法安全地把结果用于 CI、格式化器或编辑器；而不是把 Flink 引擎的全部运行时语义误当成 parser SDK 的承诺。Flink 官方文档明确把 SQL 建立在 Apache Calcite 上，并列出 SELECT、DDL、DML、诊断类语句及关键字；CREATE TABLE 和 Window TVF 页面进一步显示，Flink 的语法差异不只是关键字，而包括 metadata/computed column、WATERMARK、connector options、DISTRIBUTED、`TABLE`/`DESCRIPTOR` 参数和流式窗口结构。证据：<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/overview/>、<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/create/>、<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/queries/window-tvf/>。

### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Dependencies | Evidence |
|---|---|---:|---|---|
| **显式 `Dialect::Flink` 选择、独立关键字/词法表与 parser 路由** | 同一段 SQL 的关键字、引用符、保留/非保留类别和语法入口会随方言变化；用户必须知道到底按哪个规则解析，不能把 Doris 的 profile 参数伪装成 Flink。 | HIGH | `Dialect` 标识；每方言 keyword classification、quoted identifier/literal 规则；lexer/parser dispatcher；公共 API、schema、completion、LSP 的 dialect 参数 | v2 目标要求 Dialect、关键字表隔离和 parser 路由：`.planning/PROJECT.md:72-81`；当前 API 仍只接受 Doris profile：`api/api.mbt:42-75`；Flink 官方 reserved-keyword 列表：<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/overview/>；可验证的组织参考是 SQLFluff 以 ANSI `copy_as("flink")` 后扩展集合和 lexer：<https://raw.githubusercontent.com/sqlfluff/sqlfluff/main/src/sqlfluff/dialects/dialect_flink.py>`。 |
| **Flink SQL 核心解析覆盖**（SELECT/CTE/JOIN/聚合/集合运算/表达式/类型/脚本边界） | 这是 SQL 编辑、诊断和格式化的日常路径；官方 Flink 页面将 SELECT 定为 SQL 支持的核心查询入口。必须保留半成品的可恢复树，而不是只接受完整提交给引擎的语句。 | HIGH | 共享递归下降 + Pratt 核心；Flink-specific clause table；语句边界和恢复同步点；CST 节点 | 官方语句总览：<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/overview/>；项目已确定手写递归下降/Pratt 与 editor recovery：`.planning/PROJECT.md:43-50`。Calcite 的 `parseQuery`/`parseStmtList` 也证明语句与语句列表是独立 parser 操作：<https://raw.githubusercontent.com/apache/calcite/main/core/src/main/java/org/apache/calcite/sql/parser/SqlParser.java>`。 |
| **Flink DDL/DML 解析**（CREATE/ALTER/DROP、CATALOG/DATABASE/VIEW/FUNCTION、INSERT/UPDATE/DELETE、ANALYZE/SHOW/DESCRIBE/EXPLAIN 等） | Flink SQL 用户管理 catalog、表和 connector，并提交 INSERT 等作业；只有 SELECT 会让 SDK 对真实 Flink SQL 工作流不完整。 | HIGH | statement dispatcher；DDL/DML CST families；catalog/table schema；connector option list；版本/feature gates | 官方 overview 列举这些语句：<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/overview/>；CREATE 页明确列出 CREATE TABLE/OR REPLACE TABLE/CATALOG/DATABASE/VIEW/FUNCTION：<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/create/>；本项目 v2 目标明确要求 Flink DDL/DML：`.planning/PROJECT.md:76-81`。 |
| **Flink CREATE TABLE 专用结构**（physical/metadata/computed columns、WATERMARK、PRIMARY KEY NOT ENFORCED、PARTITIONED BY、DISTRIBUTION、`WITH` options、LIKE/AS） | 这些是 Flink 与普通 MySQL/ANSI 解析最容易分叉的真实语法；连接器配置和事件时间定义必须进入 CST，不能把括号内容当成未知字符串后丢失。 | HIGH | DDL CST；嵌套 column definitions；option key/value token 保留；时间属性和 constraint 节点；恢复点 | 官方 CREATE TABLE grammar 和示例包含这些结构：<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/create/>；SQLFluff 的可验证实现也分别定义 connector options、watermark、computed/metadata column、constraint、partition/distribution segments：<https://raw.githubusercontent.com/sqlfluff/sqlfluff/main/src/sqlfluff/dialects/dialect_flink.py>`。 |
| **窗口 TVF**（TUMBLE/HOP/CUMULATE/SESSION、`TABLE`/`DESCRIPTOR` 调用与后续窗口聚合路径） | 流式 SQL 的窗口不是普通 `OVER` 子句的别名。官方文档定义四个 TVF、参数顺序/命名参数和 `window_start/window_end/window_time` 产出；无法解析会直接阻塞 Flink 作业编辑。 | HIGH | table-valued function/`TABLE` argument；`DESCRIPTOR`；interval literal；FROM 关系节点；formatter/completion 上下文 | 官方 Window TVF 页面列出四类函数并给出完整 grammar/示例：<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/queries/window-tvf/>；v2 目标点名窗口 TVF：`.planning/PROJECT.md:76-81`。 |
| **`MATCH_RECOGNIZE` CST 与诊断（至少语法层）** | CEP 查询需要 PATTERN、MEASURES、DEFINE、skip policy 等结构；不能用泛化函数调用吞掉它们，否则 completion、formatter 和错误范围都会失真。语义执行不属于 parser。 | HIGH | table reference extension；pattern/quantifier grammar；nested expression；recoverable error nodes；明确“experimental/unsupported semantic”状态 | Calcite 官方 reference 说明 `MATCH_RECOGNIZE` 用于 CEP、目前 experimental/not fully implemented，并列出 grammar：<https://calcite.apache.org/docs/reference.html#match_recognize>（页面 `### MATCH_RECOGNIZE` 段）；本项目 v2 目标明确点名该语法：`.planning/PROJECT.md:76-81`。 |
| **结构化、方言感知诊断**（severity/code/message/expected class/span/statement id；strict/editor 两种结果） | CI 需要可靠失败，IDE 需要在缺括号、未闭引号、错误方言关键字和半成品输入上继续工作；“解析失败”或 generic MySQL error 不足以指导修复。 | HIGH | parser context；recoverable CST；source byte/line/UTF-16 mapping；稳定 `FATHOM-*` code；dialect/profile metadata | 当前公共 API 已有机器可读 diagnostics 字段和 strict/editor mode：`api/api.mbt:1-5,42-62,162-193`；当前 LSP 把 severity/code/range/source/data 映射到协议：`lsp/handlers.mbt:36-59`；Flink 官方关键字/grammar 是诊断 expected-class 的权威来源：<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/overview/>。 |
| **Lossless CST 与 no-op round-trip**（注释、空白、换行、token text、span、未知/错误节点均可回放） | 这是 Fathom 的核心信任边界：parse-only 或未改变的编辑不能改写用户 SQL；Flink connector options、注释和 `MATCH_RECOGNIZE` pattern 若被 AST 重生成，会造成不可接受的 diff。 | HIGH | trivia-preserving lexer；immutable CST；source ownership/span；lossless printer；跨方言 node schema | 项目核心价值和约束：`.planning/PROJECT.md:5-11,43-50`；当前 `ParseResult` 保留 source bytes/root/diagnostics：`api/api.mbt:180-193`。对比事实：SQLGlot 明确 AST regeneration 不保证 formatting/casing/quoting，comments 仅 best effort：<https://raw.githubusercontent.com/tobymao/sqlglot/main/README.md>`。 |
| **Flink-aware deterministic formatter**（canonical formatting 与 lossless replay 分开；错误树拒绝格式化） | 用户会在保存、CI 或 pre-commit 中调用 formatter；formatter 必须认识 Flink-specific DDL/TVF/pattern，并在不安全的错误树上拒绝产生部分输出，而不是默默丢 token。 | HIGH | stable CST；comment/trivia ownership；dialect formatting policies；safe edit/refusal diagnostics；CLI/LSP text edits | 当前 formatter 明确遇到 error/missing/skipped material 返回拒绝诊断、不输出部分 bytes：`formatter/format.mbt:1-20,49-65,127-137`；Flink-specific syntax evidence：<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/create/>、<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/queries/window-tvf/>。 |
| **方言感知 syntax completion**（关键字/子句/DDL/TVF/contextual candidates，按 cursor span 返回 edit） | 用户在 `SELECT ... FROM`、CREATE TABLE、WATERMARK、窗口 TVF 和 pattern 结构中依赖候选；只复用 Doris keyword rows 会产生错误候选并隐藏 Flink 可用语法。 | HIGH | lexer token stream；CST/editor recovery；每方言 classification/context table；UTF-8 byte→LSP UTF-16 conversion；bounded candidates | 当前 completion 是 syntax-only、profile-gated、最多 32 个候选并返回 replacement bytes：`completion/completion.mbt:1-24,129-175`；其 context 仍硬编码 Doris `QUALIFY` 等：`completion/completion.mbt:87-99`；Flink keywords/constructs：<https://raw.githubusercontent.com/sqlfluff/sqlfluff/main/src/sqlfluff/dialects/dialect_flink_keywords.py>`、<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/queries/window-tvf/>。 |
| **Flink dialect 的 Native LSP**（initialize 宣告 dialect/capabilities、didOpen/didChange/didClose、diagnostics、formatting、completion，UTF-16） | 编辑器把 LSP 当实时前端；解析器不提供同步、位置编码和 text edit 映射，Flink 工具链仍不可用。 | HIGH | shared API；JSON-RPC framing；document store；dialect in initialization/config; diagnostics/format/completion adapters | 现有 LSP 已实现 document parsing、publishDiagnostics、formatting、completion capability 和 UTF-16：`lsp/handlers.mbt:1-10,78-90,152-196,200-245`；目标重命名和 dialect 参数列于 `.planning/PROJECT.md:72-81`。LSP protocol baseline：<https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/>。 |
| **中立命名的 CLI**（`fathom-sql parse/format`，显式 `--dialect flink|doris`，稳定 schema/error code 和可脚本化 exit codes） | Flink 用户需要离线 CI/pre-commit/脚本入口；CLI 若仍叫 `doris-sql` 或默认 Doris，会让 dialect 选择不可见且与产品中立化目标冲突。 | MEDIUM-HIGH | public API dialect selection；formatter/diagnostics schema；stdin/file IO；exit code policy；Native executable packaging | 当前 CLI 是 thin adapter executable、只导入 API：`doris-sql/moon.pkg:1-13`；中立命名目标：`.planning/PROJECT.md:72-81`；Flink SQL CLI 是官方文档中的实际执行入口示例：<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/create/>。 |
| **Web/Monaco facade**（JS/linear-Wasm 同一 dialect API、诊断 markers、formatter edits、无网络/数据库依赖） | 浏览器用户需要在输入时看到 Flink diagnostics/formatting；输出必须是稳定序列化 schema，而非 MoonBit 内部对象。不同 backend 不能给出不同 keyword 或 span 结果。 | HIGH | serializable neutral schema；JS/Wasm wrapper；UTF-8 byte/UTF-16 mapping；Monaco adapter；artifact loading/error handling | 当前 adapter 用显式 profile、`doris_parse_v1`/`doris_format_v1` 并解码 schema：`web/src/monaco-adapter.ts:1-4,76-100`；Monaco model/markers/debounce parse 路径：`web/src/main.ts:26-47,83-108,150-175`；线性 Wasm parity 是已验证约束：`.planning/REQUIREMENTS.md:10-13`；SQLFluff/Tree-sitter 只能证明多方言/错误容忍组织，不替代本 SDK ABI。 |
| **IntelliJ 集成复用同一个中立 LSP**（Flink 文件语言映射、显式 dialect 设置、诊断/格式化/补全可用） | IntelliJ 不应再维护第二个 Flink parser 或第二套 transport；v1 插件已经以 LSP4IJ 连接 Native server，因此 v2 的最低期望是切换到 neutral server/schema 后功能不回退。 | MEDIUM-HIGH | `fathom-lsp` executable；LSP4IJ provider；per-project dialect setting；plugin language mapping；release/download parity | 插件明确“不含 parser 或第二个 LSP transport”：`jetbrains/README.md:1-7`；当前 server 通过 initialization options 传 profile：`jetbrains/src/main/kotlin/fathom/jetbrains/doris/DorisLanguageServerFactory.kt:11-23,42-43`；现有 profile 校验/默认值：`jetbrains/src/main/kotlin/fathom/jetbrains/doris/DorisSettings.kt:30-59`。v2 中需把这些 Doris-only surface 改成 neutral/dialect-aware。 |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Dependencies | Evidence |
|---|---|---:|---|---|
| **显式 dialect 是所有层的必填/可追踪输入，不静默 fallback** | 让 parse result、diagnostic、completion、format output 和 LSP session 都能回答“按什么规则产生”；避免 Flink SQL 被 Doris/MySQL 接受后生成错误结果。 | HIGH | dialect enum/metadata；unknown dialect hard error；wire schema carries dialect；CLI/LSP/Web/IDE config propagation；Doris parity gate | SQLGlot README 的可验证建议是已知 source dialect 时显式传 `dialect`；未指定时使用 superset dialect：<https://raw.githubusercontent.com/tobymao/sqlglot/main/README.md>`。本项目 v1 profile 已在 unknown profile 时返回错误而非猜测：`api/api.mbt:48-75`；v2 目标要求显式 dialect：`.planning/PROJECT.md:72-81`。 |
| **按方言分发且可定位来源的 diagnostics** | 同一 token 在 Doris 与 Flink 中可能是 keyword、identifier 或 unsupported construct；诊断中带 dialect、feature/grammar class、source span 和稳定 `FATHOM-*` code，用户可以修复而不是猜。 | HIGH | dialect-specific keyword/grammar metadata；diagnostic schema；strict/editor recovery；official corpus links | 当前 Doris feature metadata 已把 introduced profile、diagnostic code、recovery kind/message 绑定在一起：`token/token.mbt:133-160`；当前 LSP diagnostics carries code/source/data：`lsp/handlers.mbt:36-59`；Flink official reserved list/grammar：<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/overview/>。 |
| **Lossless CST/round-trip 作为公共能力，而非 AST 的附属 token 列表** | SQLGlot 公开承认 AST 重生成会改变格式/casing/quoting、comments 仅 best effort；Fathom 可在 Flink connector options、comments、pattern 和未知节点上进行安全 range edit 与 no-op replay。 | HIGH | stable CST node/span contract；trivia ownership；safe edit/refusal policy；formatter modes；schema versioning | SQLGlot AST/format limitation：<https://raw.githubusercontent.com/tobymao/sqlglot/main/README.md>`；当前 Fathom source bytes + CST root：`api/api.mbt:180-193`；formatter refusal：`formatter/format.mbt:1-20,127-137`。 |
| **Native/JS/linear-Wasm byte-level parity gate** | 用户可在 CLI、LSP、Monaco 和其他 host 间迁移同一文档，不因 backend 使用不同 lexer、Unicode span 或 serialization 而得到不同 diagnostics/round-trip。 | HIGH | pure MoonBit core；primitive wire schema；UTF-8 byte spans；per-target runtime fixture；CI comparison | v1 已将 Wasm runtime parity 作为 release gate：`.planning/REQUIREMENTS.md:10-13`；核心约束要求同一实现编译 Native 与 Wasm/JS：`.planning/PROJECT.md:43-50`；Web adapter 的 byte position conversion：`web/src/monaco-adapter.ts:29-73`。 |
| **中立命名和版本化 schema 同时覆盖 CLI/LSP/Web/IDE** | `fathom-sql`/`fathom-lsp`、`fathom/sql`、`FATHOM-*` 和 `fathom.*.v1` 使同一个 Flink/Doris core 不再把 Doris 当产品品牌；schema 版本独立于 dialect grammar version，便于跨 host parity。 | MEDIUM-HIGH | package/module rename；wire schema migration；release assets；VS Code/IntelliJ/Monaco configuration; no compatibility shim per milestone decision | v2 naming target：`.planning/PROJECT.md:76-81`；现有 Web facade 仍是 `doris.error.v1` / `doris_parse_v1`：`web/src/monaco-adapter.ts:16-22,88-100`；当前 LSP serverInfo/source 仍写 `doris-lsp`/`doris`：`lsp/handlers.mbt:41-47,152-161`，证明改名必须覆盖所有边界。 |
| **文档驱动且可审计的 Flink corpus/parity 报告** | Flink stable/release docs 与 Calcite grammar 会演进；每个语法功能、版本、诊断和 round-trip 结果都有 URL/commit/fixture metadata，才不会把“解析成功”夸大为引擎兼容。 | MEDIUM-HIGH | official docs source manifest；positive/negative/recovery fixtures；snapshot runner；cross-target parity；differential comparisons | Flink release page明确提示 release-2.0 文档过时并推荐 stable：<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/overview/>；Tree-sitter SQL README 也要求插件固定 generated parser revision：<https://raw.githubusercontent.com/DerekStride/tree-sitter-sql/master/README.md>`；v1 项目已用官方语料和版本 profile：`.planning/PROJECT.md:17-22,40-41`。 |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative | Evidence |
|---|---|---|---|---|
| **默认自动检测 dialect** | 用户希望输入一段 `.sql` 就“自动工作”。 | SQL 的关键字、引用符和 connector 结构存在歧义；first-success parser 会把 Doris/Flink 的有效性误判成另一个方言，诊断和 formatter 结果也无法解释。 | 默认要求显式 `Dialect`；可提供 opt-in detector，但返回候选集合、置信度和 ambiguity diagnostic，绝不替换用户选择。 | SQLGlot 官方 README 说明不指定 source dialect 时采用 superset dialect，并建议已知时显式传入：<https://raw.githubusercontent.com/tobymao/sqlglot/main/README.md>`；本项目 v1 明确拒绝多方言/静默 MySQL fallback：`.planning/REQUIREMENTS.md:47-56`。 |
| **单一 Doris 文法硬塞 Flink 特性** | 看起来可以复用现有 149KB parser，短期减少文件数。 | Flink 的 metadata/computed/WATERMARK、`TABLE`/`DESCRIPTOR`、窗口 TVF 和 `MATCH_RECOGNIZE` 会污染 Doris recovery、keyword classification 和 formatter；最终既不能保证 Doris parity，也不能给 Flink 精确诊断。 | 保持 shared core（token/CST/span/Pratt/recovery），在 statement/clause/keyword/format/completion 层按 dialect 路由；以差异最小的共享 grammar helper 复用。 | 当前 parser 是单一 Doris 入口且 API 强耦合 profile：`api/api.mbt:64-75`、`.planning/PROJECT.md:72-81`；SQLFluff 的可验证模式是方言复制基线后单独扩展 lexer、sets、segments：<https://raw.githubusercontent.com/sqlfluff/sqlfluff/main/src/sqlfluff/dialects/dialect_flink.py>`。 |
| **方言静默转换/formatter 自动改写到另一方言** | 用户想把 SQL“顺便迁移”到 Flink 或 Doris。 | 转换可能改变 connector options、quoted identifier、时间属性、窗口 semantics 或未实现语法；在保存动作中静默重写会造成数据作业风险和大范围 diff。 | `format` 只在所选 dialect 内格式化；另设显式 `transpile/convert` API，默认拒绝 unsupported construct，输出转换 diagnostics 和 opt-in edits。 | SQLGlot 将 source/target dialect 显式分成 `read` 与 `write`，并在 unsupported translation 时可 warning 或 raise：<https://raw.githubusercontent.com/tobymao/sqlglot/main/README.md>`；Fathom formatter 对 error/missing/skipped tree 已采取 refusal-first：`formatter/format.mbt:1-20,127-137`。 |
| **未知 Flink 语法 generic MySQL/ANSI 兜底** | 可以让更多输入“parse 成功”，并借用通用 SQL 生态。 | generic 接受不代表 Flink engine 接受，会造成 false-negative CI、错误 completion、错误格式化和错误 source span；还会掩盖 Flink release 差异。 | 在选定 dialect 下保留 unknown/error CST 节点并发出稳定诊断；允许 editor mode 继续树化，strict mode 失败；将 Calcite/SQLGlot 仅用于差分调查。 | Flink 官方明确有独立 reserved keywords 和 Calcite-based SQL：<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/overview/>；SQLGlot 自称 parser intentionally lenient、不是 validator：<https://raw.githubusercontent.com/tobymao/sqlglot/main/README.md>`；项目当前错误恢复/strict-editor boundary：`api/api.mbt:1-5,48-62`。 |
| **用 generic CST/AST 替掉 Flink-specific lossless nodes** | 共享一个“标准 SQL AST”会显得 API 简洁。 | 它会丢掉 metadata/computed column distinction、WATERMARK、connector option spelling、TVF named arguments、pattern text 和 comments，无法安全 formatter/edit。 | CST 保留原始 token/trivia 和 Flink node kind；再提供可选语义/通用 AST projection，且 projection 不能成为回放来源。 | Flink CREATE grammar explicitly distinguishes these definitions：<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/create/>；Tree-sitter 官方目标也是 concrete syntax tree、error-tolerant editing：<https://tree-sitter.github.io/tree-sitter/>；当前 Fathom `ParseResult` retains source bytes/root：`api/api.mbt:180-193`。 |
| **在 parser SDK 内实现完整 Flink planner/catalog/execution semantics** | 用户可能要求“和 Flink SQL Client 一样验证”。 | connector、catalog、watermark、stream/batch mode、type inference 和 planner rules 需要运行时环境；嵌入这些依赖会破坏 Native/Wasm/JS 离线与独立发布边界，且远超语法工具。 | parser 负责 syntax/recovery；analyzer 通过可选 catalog/feature metadata 注入；engine differential check 只在 corpus/CI 外部执行。 | Flink 官方页面将 SQL 作为 TableEnvironment/SQL CLI 执行语言：<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/create/>；项目已明确 parser/analyzer separation 与无 FE runtime：`.planning/PROJECT.md:19-22,43-50`。 |
| **用 Tree-sitter/SQLFluff/sqlglot 的 permissive 结果直接宣称 Flink engine compatibility** | 成熟生态可快速扩大“支持语法”数字。 | Tree-sitter SQL README 称其 grammar general/permissive；SQLGlot 明确 lenient；SQLFluff 是 linter/parser 组织参考而不是 Flink planner oracle。直接把 parse success 当 engine acceptance 会误导用户。 | 以 Flink 官方 release docs/source 为 grammar authority；竞品只用于组织模式、负例和 differential signal；发布 per-feature/per-version coverage。 | Tree-sitter SQL README：<https://raw.githubusercontent.com/DerekStride/tree-sitter-sql/master/README.md>`；SQLGlot README：<https://raw.githubusercontent.com/tobymao/sqlglot/main/README.md>`；Flink official overview：<https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/overview/>。 |
| **错误树上强行 formatter/autofix 或无限恢复** | 编辑器希望“永远有输出”。 | 无限恢复会把任意文本误报为 valid；对 error/missing/skipped material 生成部分格式会破坏注释和未知 Flink clause，CI 与 save action 都不安全。 | editor mode 返回 recoverable CST + hard diagnostics；strict mode 拒绝；formatter 在 unsafe node 上返回空 output 和单一 refusal diagnostic。 | Fathom 当前 formatter refusal contract：`formatter/format.mbt:1-20,49-65,127-137`；当前 API 明确区分 Strict/Editor：`api/api.mbt:1-5,69-75`。 |

## Feature Dependencies

```text
Explicit Dialect + neutral schema/error-code contract
    ├──> per-dialect lexer/keyword table
    │       └──> Flink statement/clause parser routing
    │               ├──> DDL/DML + CREATE TABLE structures
    │               ├──> Window TVF
    │               └──> MATCH_RECOGNIZE pattern CST
    ├──> dialect-aware diagnostics + strict/editor recovery
    └──> dialect-aware completion

Lossless trivia/span CST + source coordinate map
    ├──> no-op replay / round-trip
    ├──> safe Flink formatter
    ├──> LSP diagnostics + UTF-16 text edits
    └──> Web/Monaco markers + IntelliJ LSP integration

Stable neutral wire schema + shared core
    ├──> Native fathom-sql / fathom-lsp
    ├──> JS + linear-Wasm Web facade
    ├──> VS Code/Monaco adapter
    └──> IntelliJ LSP4IJ provider

Official Flink corpus + negative/recovery fixtures
    └──> Doris parity gate + Native/JS/Wasm byte-level parity report
```

### Dependency Notes

- **Dialect routing requires keyword isolation first:** lexical classification drives parser branch selection, expected-token diagnostics and completion. The existing `DorisProfile`/global classification model is therefore not a safe shared default (`token/token.mbt:3-7,133-160`; `.planning/PROJECT.md:76-81`).
- **Flink-specific DDL/TVF/MATCH_RECOGNIZE require CST before formatter/completion:** formatter and completion must inspect structure and spans, not regex-match source text. Official grammar evidence is the Flink CREATE, Window TVF and Calcite MATCH_RECOGNIZE references above.
- **Diagnostics precede LSP, CLI, Web and IntelliJ:** all four consumers serialize the same severity/code/span contract. Existing LSP and Web code demonstrate this boundary (`lsp/handlers.mbt:36-59`; `web/src/monaco-adapter.ts:69-73`).
- **Lossless CST precedes formatter/autofix:** no-op replay is independent of canonical formatting; the formatter must refuse unsafe trees before it gains Flink-specific layout rules (`formatter/format.mbt:1-20`).
- **LSP is the IntelliJ integration boundary:** the plugin already contains no parser/second transport and passes profile via initialization options (`jetbrains/README.md:1-7`; `DorisLanguageServerFactory.kt:11-23,42-43`). Neutral naming should change the adapter contract, not duplicate parsing.
- **`MATCH_RECOGNIZE` syntax and semantic support must be separately labeled:** Calcite documents the syntax as experimental/not fully implemented, so Fathom can provide syntax CST/diagnostics without claiming planner/execution equivalence (<https://calcite.apache.org/docs/reference.html#match_recognize>). 

## MVP Definition

### Launch With (v1)

- [ ] **Explicit Flink/Doris dialect contract and isolated keyword tables** — without this, every other Flink result is ambiguous and Doris parity cannot be gated.
- [ ] **Flink lexer + core SELECT/DML/DDL + CREATE TABLE + Window TVF + syntax-level MATCH_RECOGNIZE** — validates the requested language surface against official docs while keeping semantic execution out of scope.
- [ ] **Lossless recoverable CST, structured dialect-aware diagnostics, and byte-exact replay** — preserves Fathom’s core value and supports malformed editor input.
- [ ] **Flink-aware formatter and bounded completion** — makes the parser useful beyond batch parsing and reuses the same CST/keyword metadata.
- [ ] **Neutral Native CLI/LSP plus JS/linear-Wasm schema facade** — exercises all public boundaries and enables Monaco/IntelliJ reuse.
- [ ] **Doris byte-level parity and official Flink corpus snapshots on every backend** — prevents a successful Flink implementation from regressing the shipped Doris behavior.

### Add After Validation (v1.x)

- [ ] **Richer Flink completion from optional catalog metadata** — add after syntax-only candidates and dialect routing are stable; trigger is measured editor feedback showing keyword-only completion is insufficient.
- [ ] **Semantic tokens, symbols and dialect-aware hover in LSP/Web/IntelliJ** — add after span/schema parity fixtures cover Flink-specific nodes.
- [ ] **Expanded release matrix and feature-introduction metadata** — add when official Flink stable/release docs expose incompatible grammar changes that require more than one Flink profile.
- [ ] **Explicit opt-in SQL conversion tool** — only after source/target dialect diagnostics and refusal behavior are specified; never as formatter default.

### Future Consideration (v2+)

- [ ] **Catalog-backed type/planner validation equivalent to Flink runtime** — defer because it introduces catalog/connectors/stream-batch semantics and conflicts with standalone SDK boundaries.
- [ ] **Benchmark-gated incremental CST reuse** — defer until whole-document reparse is measured as a real editor bottleneck; preserve the invariant that incremental and full parse replay byte-identically (`.planning/REQUIREMENTS.md:31-33`).
- [ ] **Third-party dialect/plugin marketplace** — defer until built-in Doris/Flink schema, keyword table, diagnostics and cross-backend contract are stable.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---|---|---|---|
| Explicit dialect + isolated keyword/grammar route | HIGH | HIGH | P1 |
| Flink lexer/parser core and DDL/DML | HIGH | HIGH | P1 |
| Lossless CST/replay + structured diagnostics/recovery | HIGH | HIGH | P1 |
| Window TVF + CREATE TABLE structures | HIGH | HIGH | P1 |
| MATCH_RECOGNIZE syntax CST | MEDIUM-HIGH | HIGH | P1 |
| Formatter refusing unsafe trees | HIGH | HIGH | P1 |
| Syntax completion | HIGH | MEDIUM-HIGH | P1 |
| Neutral CLI/LSP | HIGH | HIGH | P1 |
| JS/linear-Wasm Web/Monaco facade | HIGH | HIGH | P1 |
| IntelliJ via neutral LSP | MEDIUM-HIGH | MEDIUM | P1 |
| Cross-backend parity + official corpus report | HIGH | HIGH | P1 |
| Catalog-backed completion/hover | MEDIUM | HIGH | P2 |
| Semantic tokens/symbols | MEDIUM | MEDIUM | P2 |
| Explicit opt-in transpilation | MEDIUM | HIGH | P2 |
| Runtime-equivalent type/planner analysis | LOW for parser SDK | VERY HIGH | P3 |
| Incremental parsing | MEDIUM | VERY HIGH | P3 (benchmark-gated) |

**Priority key:**
- P1: Must have for the Multi-Dialect launch.
- P2: Should follow once language and public schemas are stable.
- P3: Future consideration; do not let it compromise the parser contract.

## Competitor Feature Analysis

| Feature | SQLGlot | SQLFluff | tree-sitter SQL / Tree-sitter | Fathom approach |
|---|---|---|---|---|
| Multi-dialect organization | `Dialect` registry/classes; explicit source/target dialect arguments; dialect modules such as `doris.py` are separate files. | Flink dialect is a copy/extension of ANSI, then separately patches keyword sets, lexer and segments. | Tree-sitter runtime is a generic incremental parser; `tree-sitter-sql` describes itself as a general/permissive SQL grammar. | Use their separation ideas only: shared CST/recovery primitives, explicit `Dialect`, per-dialect lexer/grammar/formatter/completion tables, no default superset parser. |
| Validation and errors | Explicit parse errors exist, but parser is intentionally lenient and not a validator; unsupported translation may warn or raise. | Linter/auto-fix is the product boundary; dialect grammar is useful reference for rule parsing, not Flink engine acceptance. | Robust useful results with syntax errors is an explicit runtime goal; generated tree is not proof of SQL engine validity. | Keep strict/editor distinction, stable `FATHOM-*` diagnostics, recoverable CST, and official Flink corpus as acceptance oracle. |
| Source fidelity | AST regeneration changes cosmetic details; comments best effort. | Segment/trivia-oriented linter/formatter model is a useful organization reference. | Concrete syntax tree and edit-aware ranges support editor use cases. | Make lossless CST and `print_lossless(parse(x)) == x` a public invariant, then derive formatter/LSP/Web/IDE views from it. |
| Flink evidence | Do not treat a generic or lenient parse as Flink runtime support. | `dialect_flink.py` visibly contains Flink keyword/lexer/connector/watermark/computed/metadata/distribution structures. | `tree-sitter-sql` references generic SQL sources and labels grammar permissive. | Flink official docs and Calcite grammar determine required fixtures; competitors only inform decomposition and negative tests. |

## Sources

### Official Flink / Calcite / protocol

- Apache Flink SQL overview, supported statements and reserved keywords: <https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/overview/> (directly read; page warns release-2.0 is out of date and links stable).
- Apache Flink CREATE statements and CREATE TABLE grammar: <https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/create/> (directly read).
- Apache Flink Windowing TVF (`TUMBLE`, `HOP`, `CUMULATE`, `SESSION`, `TABLE`/`DESCRIPTOR`): <https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/queries/window-tvf/> (directly read).
- Apache Calcite `SqlParser` configuration and parse entry points: <https://raw.githubusercontent.com/apache/calcite/main/core/src/main/java/org/apache/calcite/sql/parser/SqlParser.java> (directly read).
- Apache Calcite SQL grammar and `MATCH_RECOGNIZE` experimental status/grammar: <https://calcite.apache.org/docs/reference.html#match_recognize> (directly read; `MATCH_RECOGNIZE` section and syntax).
- Language Server Protocol 3.17 specification: <https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/>.

### Multi-dialect/parser ecosystem

- SQLGlot README: explicit dialect selection, lenient parser, AST regeneration/comment limitations, unsupported conversion behavior: <https://raw.githubusercontent.com/tobymao/sqlglot/main/README.md>.
- SQLGlot dialect base/registry and parser/tokenizer/generator class composition: <https://raw.githubusercontent.com/tobymao/sqlglot/main/sqlglot/dialects/dialect.py>.
- SQLFluff Flink dialect: ANSI inheritance, keyword sets, lexer patches, and Flink-specific segments: <https://raw.githubusercontent.com/sqlfluff/sqlfluff/main/src/sqlfluff/dialects/dialect_flink.py>.
- SQLFluff Flink keyword table: <https://raw.githubusercontent.com/sqlfluff/sqlfluff/main/src/sqlfluff/dialects/dialect_flink_keywords.py>.
- Tree-sitter official introduction: concrete syntax tree, incremental updates and useful results with syntax errors: <https://tree-sitter.github.io/tree-sitter/>.
- `tree-sitter-sql` README: general/permissive grammar and generated parser revision requirement: <https://raw.githubusercontent.com/DerekStride/tree-sitter-sql/master/README.md>.
- `tree-sitter-sql` grammar: shared extras/comments, precedence, statement modules and conflict declarations: <https://raw.githubusercontent.com/DerekStride/tree-sitter-sql/master/grammar.js>.

### Local project evidence

- v2 Multi-Dialect goal, Flink feature list and neutral names: `.planning/PROJECT.md:72-81`.
- Core value, lossless CST, parser/recovery and backend constraints: `.planning/PROJECT.md:5-11,43-50`.
- Current API still Doris-profile based and exposes strict/editor, result source bytes/root/diagnostics: `api/api.mbt:1-5,42-75,162-193`.
- Current Doris profile/feature metadata and profile-introduced diagnostics: `token/token.mbt:3-7,47-77,133-160`.
- Current syntax-only bounded completion: `completion/completion.mbt:1-24,129-175`.
- Current refusal-first formatter contract: `formatter/format.mbt:1-20,49-65,127-137`.
- Current LSP diagnostics, formatting, completion, UTF-16 and profile state: `lsp/handlers.mbt:1-10,36-59,78-90,144-196,200-245`.
- Current CLI package as Native executable thin adapter: `doris-sql/moon.pkg:1-13`.
- Current Web/Monaco profile facade and byte positions: `web/src/monaco-adapter.ts:1-4,29-73,76-100`; `web/src/main.ts:26-47,83-108,150-175`.
- Current IntelliJ plugin reuses Native LSP and passes profile initialization options: `jetbrains/README.md:1-17`; `jetbrains/src/main/kotlin/fathom/jetbrains/doris/DorisLanguageServerFactory.kt:11-23,42-43`; `DorisSettings.kt:30-59`.
- Existing cross-backend parity acceptance: `.planning/REQUIREMENTS.md:10-13`; incremental parsing benchmark gate: `.planning/REQUIREMENTS.md:31-33`.

---
*Feature research for: Fathom v2.0 Multi-Dialect (Flink SQL & Neutral Naming)*  
*Researched: 2026-08-06*
