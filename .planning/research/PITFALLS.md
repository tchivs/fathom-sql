# Domain Pitfalls

**Domain:** Fathom v2.0 多方言无损 SQL Parser SDK（Doris + Flink、MoonBit、CST、Native/JS/Wasm、CLI/LSP）  
**Researched:** 2026-08-06  
**Confidence:** HIGH（仓库耦合点和 v1 约束直接由本地文件核验；Flink/Calcite 语法边界由 Apache 官方文档与 Calcite 官方 API/源码核验；“会导致回归”的部分是基于这些事实的工程推论，标明验证门。）

## 研究结论

本里程碑不是“再加一套关键字和几个 Flink 语句”。v1 的 profile、分类表、parser 路由、诊断码、序列化 schema、CLI、LSP、Web、VS Code 与 JetBrains 发布流程都把 Doris 写进了公共边界。目标明确要求 Dialect、Flink 全链和中立命名（`.planning/PROJECT.md:72-81`），因此任何只修改 `parser/` 的实现都会留下跨层不一致。最危险的结果不是少支持一条语法，而是：Doris 原有输入的接受性、CST 字节回放或诊断坐标悄悄改变，用户无法区分是方言错误还是 SDK 回归。

Flink 也不是 Doris 的“同义词”。Apache Flink SQL 明确基于 Apache Calcite、单独列出 DDL/DML/Query 语句和大量预留关键字（[Flink SQL overview](https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/overview/)）；Windowing TVF 是 `FROM` 中的 polymorphic table function，包含 `TABLE`、`DESCRIPTOR`、命名参数等结构（[Windowing TVF](https://nightlies.apache.org/flink/flink-docs-release-1.20/docs/dev/table/sql/queries/window-tvf/)）；`MATCH_RECOGNIZE` 具有 `PATTERN`、`DEFINE`、`MEASURES`、`AFTER MATCH SKIP` 等嵌套子语言，且官方明确声明仅实现标准子集（[Pattern Recognition](https://nightlies.apache.org/flink/flink-docs-release-1.20/docs/dev/table/sql/queries/match_recognize/)）。这些构造必须走显式方言/语句路由，而不是污染共享 Doris 产生式。

## Critical Pitfalls

### Pitfall 1：把全局 Doris keyword 分类表升级成“所有方言共用表”

**What goes wrong:**

`token/token.mbt` 目前只有 `DorisProfile`（`V2_1/V3_X/V4_X`，`token/token.mbt:3-7`），并以一个全局 `classification_rows` 为运行时真相（`token/token.mbt:307-325`）。`classification_of`、`is_reserved_word` 和 `is_unquoted_identifier` 都没有方言参数（`token/token.mbt:449-493`）。直接把 Flink 词加入该数组会造成至少三类错误：

- Flink 保留/未来保留词在 Doris 中被错误拒绝为未引用 identifier，或 Doris 的 contextual/non-reserved 词被 Flink 误用；同一个原词在两个方言中可能具有不同的 reserved、non-reserved、contextual 和语境含义。
- `is_reserved_word` 被 lexer、identifier 解析和 formatter 间接复用后，方言选择会被隐式全局状态吞掉；解析同一文本的结果可能取决于上一次调用或某个默认 profile。
- 只添加“语句中看到的词”仍会漏掉数据类型、窗口 TVF、MATCH_RECOGNIZE 子语句、未来保留词和 recovery 边界词。Flink 官方说明即使功能未实现，字符串组合也可能已经 reserved；把“当前可解析”当作“关键词全集”会漏词（Flink overview 的 Reserved Keywords 段）。

**Why it happens:**

v1 的审计工具把 runtime table 与 Doris production inventory 绑定：`check_keywords.py` 固定 `VALID_PROFILES = {2.1, 3.x, 4.x}`，并要求覆盖 Doris DML/DDL 词（`corpus/tools/check_keywords.py:23-41`）。开发者容易把这一套机制横向复制为一份表，而没有先提升抽象层。更隐蔽的是，分类和产生式 gate 在 v1 已明确是两层：`DorisFeature` 负责版本功能，分类负责 identifier 接受（`token/token.mbt:297-306`）；若新方言沿用 `DorisFeature`，两套语义会纠缠。

**How to avoid:**

1. 在 Phase 9（Dialect Boundary）先定义 `DialectId`/`DialectProfile` 和不可变 `KeywordTable`，所有分类查询签名必须接收 Dialect；禁止保留无参数的公共 `is_reserved_word`，或将其限制为 Doris 专用内部 helper。
2. 每个方言维护独立的 `KeywordEntry`：原词、分类、语境、引入/移除版本、引用规则、来源 URL；共享层只保留词法形状和原文，不共享分类结论。
3. 将“产生式 inventory”和“分类 inventory”分开校验：Flink 的 reserved/future-reserved 清单来自其锁定版本文档或 Calcite 源码；每条生产规则使用的词必须有方言行，未覆盖词必须显式 unknown/error，而不是自动降级为 identifier。
4. 为每个冲突词写成对测试：作为 clause keyword、未引用列/表名、反引号标识符、函数名、字符串和 recovery token；测试 Doris 与 Flink 的结果及 lossless replay。

**Warning signs:**

- 新增 Flink 词只改 `token/token.mbt`，没有 `dialect` 参数或 Flink 独立 TSV。
- 同一 `classification_of(raw)` 被 Doris 与 Flink parser 共同调用；测试只能在单一默认方言下通过。
- keyword rows 数量增加但 production inventory 没有差异报告；错误输入被“更多接受”却没有误接受率。
- `QUALIFY`、`TABLE`、`MATCH`、`DEFINE`、`DESCRIPTOR` 在不同上下文中出现 identifier/keyword 结果不一致。

**Phase to address:**

**Phase 9：Dialect Boundary and Neutral Naming** 必须先隔离表和 API；**Phase 10：Flink Lexical/Grammar Core** 完成 Flink inventory 与冲突矩阵；**Phase 12：Cross-dialect Corpus/Parity** 运行双方言 acceptance/rejection 与分类 gate。

**Evidence:** `token/token.mbt:3-7,133-141,297-306,307-325,449-493`; `corpus/tools/check_keywords.py:23-41,93-103`; [Flink SQL overview — Reserved Keywords](https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/overview/#reserved-keywords)。

---

### Pitfall 2：Flink 文法污染 Doris，或用 DorisFeature 冒充 Dialect/语句路由

**What goes wrong:**

当前 `parser/parser.mbt` 是单一 Doris recursive-descent + Pratt 路径：入口按裸 token 直接分派 `SELECT/WITH/INSERT/UPDATE/DELETE/MERGE/CREATE`（`parser/parser.mbt:3342-3370`），表达式 precedence 也直接对原文词做判断（`parser/parser.mbt:265-275`）。如果把 Flink 的特殊语法塞进这些分支：

- Flink 的 `SELECT * FROM TABLE(TUMBLE(TABLE data, DESCRIPTOR(ts), ...))` 可能被 Doris 的普通 table/query 路径部分消费，随后产生错误 span 或错误 recovery，而不是在 Flink 规则中形成明确 CST。
- `MATCH_RECOGNIZE` 的 `PATTERN` 正则样式、pattern variable、`DEFINE`/`MEASURES` 表达式会被普通 Pratt parser 当成 identifier/operator；一处缺失括号可能吞掉后续 statement。
- Flink 的 DDL/DML 语句集合与 Doris 的 CREATE/INSERT/UPDATE/DELETE 细节不同。共享 `CREATE` 或 `INSERT` 分支会把 Flink 接受性错误地扩大到 Doris，或让 Doris 的 `MERGE`/properties/partition 版本 gate 失效。
- `DorisFeature::Qualify/Tablet/MergeInto/...` 与 `Dialect` 混用后，代码可能检查“当前 profile 支持 feature”而没有检查“当前 parser 是 Doris”，导致 Flink 获得 Doris 诊断码/版本信息，或 Doris 被迫依赖 Flink feature enum。

Flink 官方还明确 `MATCH_RECOGNIZE` 只支持文档定义的标准子集，不能用“通用 SQL pattern”误接受未支持特性（官方文档的 subset/known limitations 说明）。

**Why it happens:**

v1 已经把“profile gate”做成 `ValidatedProfileContext::supports(DorisFeature)`（`token/token.mbt:47-53`），parser 的 recovery state 也持有该 context（`parser/parser.mbt:118-124`）。这是 Doris 版本功能抽象，不是多方言抽象。为了少改函数签名，最容易的短期方案是继续塞 `if feature_allowed`；该方案会把 dialect、release profile、grammar capability 和 diagnostic namespace 混成一个布尔条件。

**How to avoid:**

1. Phase 9 先建立 `Dialect` 作为最外层不可变 parse context：`dialect_id`、该方言的 keyword table、statement router、expression policy、feature registry、diagnostic namespace。Doris 的 `DorisFeature` 只能存在 Doris 模块内并由 `DorisDialect` 实现，不能出现在共享 CST/lexer/parser trait 的公共签名中。
2. 语句入口先做 `Dialect::route_statement`，再进入 dialect-specific statement parser；共享表达式只共享“字面量/标识符/括号/通用运算符”的 token/CST 机制，方言差异通过显式 `ExpressionPolicy`/扩展节点处理。
3. 对 Window TVF、MATCH_RECOGNIZE 等 Flink 子语言使用独立 parser rule 和 CST node；其未知/部分实现必须保留 source-backed error/skipped nodes，不能让 Doris recovery 集合替代它们。
4. 为每个路由建立负向 gate：`parse(doris, flink-only syntax)` 和 `parse(flink, doris-only syntax)` 都要有明确预期；同一 SQL 的语句 kind、诊断 code、feature metadata 必须包含 dialect。

**Warning signs:**

- `parser/parser.mbt` 出现 `if dialect == Flink` 的散布式条件，而没有单一 router。
- Flink 代码 import `@token.DorisFeature` 或生成 `DORIS-PARSE-*`；共享 Pratt precedence 开始包含 `PATTERN/DEFINE/DESCRIPTOR`。
- Flink corpus 在没有修改 fixture 的情况下 acceptance 或 CST kind 变化；Flink-only grammar 在 Doris mode 返回 valid。
- 某个 `CREATE`/`SELECT` rule 同时持有 Flink 和 Doris 的 clauses，却没有 dialect-specific test matrix。

**Phase to address:**

**Phase 9：Dialect Boundary** 固化 context/router/feature registry；**Phase 10：Flink Grammar** 实现独立 Window TVF 与 MATCH_RECOGNIZE；**Phase 11：Doris Regression/Parity Gate** 证明共享表达式重构不改变 Doris；**Phase 12：Flink full toolchain** 消费 dialect capability，不再直接依赖 Doris enum。

**Evidence:** `parser/parser.mbt:265-275,118-124,3342-3370`; `token/token.mbt:47-53,133-141,230-235`; `.planning/PROJECT.md:76-81`; [Flink overview](https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/overview/); [Windowing TVF](https://nightlies.apache.org/flink/flink-docs-release-1.20/docs/dev/table/sql/queries/window-tvf/); [MATCH_RECOGNIZE](https://nightlies.apache.org/flink/flink-docs-release-1.20/docs/dev/table/sql/queries/match_recognize/)。

---

### Pitfall 3：Doris CST、诊断或接受性发生隐性回归，parity 只测“能编译”

**What goes wrong:**

任何 lexer 分类、共享 Pratt、CST kind 或 parser recovery 的改动，都可能改变 Doris v1 的公开行为：注释/空白/未知 token 丢失，节点 span/text length 改变，`DORIS-PARSE-*` code 或 statement id 改变，严格/编辑模式边界变化，或者本来在 2.1 被拒绝的 4.x-only feature 被接受。单看 parser 返回 `valid` 或 CLI exit code 无法发现这些回归。

v1 的公共结果包含 `schema_version/profile/exact_release/feature_introduction/mode/valid/recovered/source_bytes/root/diagnostics`（`api/api.mbt:180-193`），并要求 root-only source bytes 与 primitive descendants。`ParseResult` 在 API 入口还会验证 syntax tree（`api/api.mbt:273-310`）。这意味着 Doris parity 必须是字节、树、诊断、版本 gate 四维，而非“解析成功率”。

**Why it happens:**

多方言重构通常会先改 token enum/`SyntaxKind`，再批量更新 snapshot；如果 snapshot 只包含新 Flink 语料，旧 Doris fixtures 便不会阻止变化。当前仓库已有 44 行 Doris manifest，但其中很多 provenance 是 `unavailable-offline`（`corpus/manifest.tsv:1-14`），且项目自身记录 FE/Nereids 差分仍待人工执行（`.planning/PROJECT.md:67-70`）。这使“绿 CI”不能自动等价于外部 Doris parity。

**How to avoid:**

1. Phase 11 建立 frozen Doris oracle：锁定 v1 corpus/fixture、`corpus/keywords.tsv`、关键 malformed/recovery cases，并在方言重构前生成 immutable baseline（source hash、CST normalized view、all spans/text_len、diagnostics、format output、profile acceptance）。
2. 每次改动跑 `print_lossless(parse_doris(x)) == x`；比较完整 serialized result，不只比较 `valid`。保留 statement kind/order、diagnostic code/span/message/statement_id、strict/editor、2.1/3.x/4.x acceptance/rejection。
3. 对 formatter、completion、binding、LSP、Native/JS/Wasm 使用同一 Doris parity fixtures；schema 迁移测试应同时验证旧行为的中立字段映射和新 dialect 字段。
4. FE/Nereids 可作为 differential oracle，但不能将离线不可得的 FE 结果伪造为 PASS；每个 unavailable/offline gap 必须在报告中可见。

**Warning signs:**

- PR 只有新 Flink 测试，没有 Doris baseline diff。
- snapshot 批量更新但没有 source hash、语法设计说明或“哪些字段允许变化”的审阅记录。
- 只比较 parser `valid`，不比较 bytes、spans、diagnostic code、recovery nodes。
- Native 通过而 JS/Wasm/LSP 只做编译；Doris 2.1 MERGE、QUALIFY 和 unknown statement 的负例消失。

**Phase to address:**

**Phase 9** 在改 API 前冻结 baseline；**Phase 11：Doris Regression/Parity Gate** 作为 Flink parser 合并的硬门禁；**Phase 13：Cross-backend and Editor Parity** 覆盖 binding、CLI、LSP、Web、VS Code、IntelliJ。

**Evidence:** `api/api.mbt:162-193,273-310`; `binding/schema.mbt:3-5,69-83`; `corpus/manifest.tsv:1-14`; `.planning/PROJECT.md:67-70`; `.planning/milestones/v1.0-REQUIREMENTS.md:14-18,29-32,49-53`; [MoonBit tests/snapshots](https://docs.moonbitlang.com/en/latest/language/tests.html)（测试工具只能验证声明的 oracle，不能代替 corpus 设计）。

---

### Pitfall 4：中立命名迁移遗漏，导致产品出现两套公共身份

**What goes wrong:**

目标要求 clean cutover 为 `fathom-sql`/`fathom-lsp`、`fathom/sql`、`FATHOM-*`、`fathom.*.v1`，不保留兼容别名（`.planning/PROJECT.md:74-80`）。若只改 README 或模块名，用户会遇到：

- MoonBit import 仍是 `fathom/doris-sql`（`moon.mod:5-7`、`lsp/moon.pkg:3-5`），CLI 仍叫 `doris-sql`，发布产物/下载 manifest 仍叫 `doris-lsp`（`.github/workflows/doris-native-release.yml:93-107`）。
- binding 仍导出 `doris_parse_v1`/`doris_format_v1`，schema 仍为 `doris.parse.v1`/`doris.format.v1`，错误仍为 `DORIS-*`（`binding/exports.mbt:25-80`；`binding/schema.mbt:3-5,43-57,107-148`）。JS/Web/Monaco 与测试会继续传播旧名称。
- LSP `serverInfo.name`, diagnostic `source`, fallback code/message 仍是 Doris（`lsp/handlers.mbt:36-46,78-89,152-161`），VS Code activation/languageId/settings/command 仍是 `doris`（`vscode/package.json:15-57`）。新 Flink 文件若复用 `.sql` 但没有 dialect 语义，会显示为错误语言。
- JetBrains workflow 和 artifact 名称仍带 Doris（`.github/workflows/jetbrains-plugin.yml:19-46`），文档和配置还会要求用户输入 “Doris profile”。

**Why it happens:**

v1 的命名跨越编译模块、符号 ABI、JSON schema、错误码、二进制、LSP source、编辑器 languageId、扩展设置和发布脚本；没有单一 registry 时，机械替换会漏掉字符串、快照、包路径和下载文件名。并且 `doris` 既是旧产品名又是 Dialect 标识，盲目全局替换会错误地删除必须保留的 Doris 方言标识（目标明确“Doris 作为方言标识必须保留”）。

**How to avoid:**

1. Phase 9 建立命名迁移矩阵，区分三类：产品/协议 namespace（必须改）、Doris dialect id（必须保留）、历史 corpus/source URL（按 provenance 保留）。列出 module import、binary/export、schema/error code、LSP source/serverInfo、languageId/config、VS Code/IntelliJ artifact、docs/tests。
2. 定义单一 `ProductIdentity`/schema constants 生产者；binding、CLI、LSP、JS/Wasm 和扩展只消费常量/生成 manifest，不各自拼接字符串。schema 和 error code 做版本化 clean cutover，不提供隐式旧 namespace alias。
3. 用 repository-wide forbidden/allowlist gate：产品边界禁止 `doris-*`/`DORIS-*`/`doris.*`，语料 URL、`Dialect::Doris`、Doris profile、官方名称列入允许位置；逐项检查生成产物、快照和发布 workflow。
4. 命名迁移完成后再接 Flink UI；同时要求同一产品可列出 `Doris`、`Flink` 两个 dialect，避免中立化把 Doris 选择器删除。

**Warning signs:**

- `grep` 仍发现 `doris.parse.v1`, `DORIS-`, `doris-lsp`, `doris-sql` 出现在 binding/LSP/CLI/extension 代码而不在 allowlist。
- JS export 名改了但 `moon.pkg` exports、Wasm runner、parity fixture 仍调用旧符号。
- UI 文案变成 “SQL” 却没有 dialect selector，或者把 `Doris` 误当产品 brand 删除。
- 发布 workflow 产出名称、README 安装命令和实际 binary 不一致；JetBrains/VS Code 只改一方。

**Phase to address:**

**Phase 9：Dialect Boundary and Neutral Naming** 完成一次性矩阵迁移；**Phase 13：Cross-platform Packaging** 验证 Native/JS/Wasm/VS Code/IntelliJ 实际 artifact 和文档；不要把命名迁移拆成“最后清理”。

**Evidence:** `.planning/PROJECT.md:72-81`; `moon.mod:5-7`; `api/api.mbt:298-310`; `binding/exports.mbt:25-80`; `binding/schema.mbt:3-5,43-57,69-83,107-148`; `lsp/handlers.mbt:36-46,78-89,152-161`; `vscode/package.json:15-57`; `.github/workflows/doris-native-release.yml:93-107`; `.github/workflows/jetbrains-plugin.yml:19-46`。

---

### Pitfall 5：Flink corpus 未 pin、dev/nightly 文档污染，或 Calcite keyword/parser 漂移未被发现

**What goes wrong:**

Flink 文档的 `release-1.20` 页面明确标记为 out-of-date 并指向 stable；`release-2.0` 页面也可能继续变化。若抓 stable/nightly/current 页面而不锁 Flink release、Calcite 版本、源码 commit、页面 heading 和抓取日期：

- 同一 fixture 在重新抓取后语法、关键字、支持状态或示例会改变，golden 结果不再可复现。
- 文档中的 SQL Client prompt、输出表、注释、legacy grouped window 示例被当成 SQL 语句，造成通过率虚高或 parser 误报。
- Flink 语法文档与实际 Calcite parser 的 keyword/conformance 演进不同步；只抄文档 keyword list 会漏 future-reserved 或误纳入已废弃语法。
- Window TVF 和 MATCH_RECOGNIZE 的语义限制被当成 parser 必须执行的 catalog/streaming validation，或反过来把未支持标准子集误接受为合法 Flink SQL。

Calcite 官方 `SqlParser.Config` 暴露 `parserFactory`、`conformance`、`quoting`、`caseSensitive`、quoted/unquoted casing 等可变配置（[SqlParser.Config](https://calcite.apache.org/javadocAggregate/org/apache/calcite/sql/parser/SqlParser.Config.html)）；Calcite `Parser.jj` 又明确 `IGNORE_CASE = true`、`UNICODE_INPUT = true` 并由模板生成 parser（[Parser.jj](https://github.com/apache/calcite/blob/main/core/src/main/codegen/templates/Parser.jj)）。因此 “Flink SQL keyword” 不是一份永恒字符串数组，而是 release + Calcite config/conformance 的组合。

**Why it happens:**

当前 Doris corpus 已有 manifest 设计（`corpus/manifest.tsv:1-14`），但 revision 仍记录 `unavailable-offline`；v1 研究也明确 current/dev 是未发布输入，不能静默接受（`.claude/CLAUDE.md:103-110`）。复制 Doris 抽取器时，如果只把 `doris-2.1` 替成 `flink-stable`，就会把 moving URL 当版本号。

**How to avoid:**

1. Phase 12 设立 Flink corpus contract：每行记录 Flink release、Calcite dependency/version、官方 URL、仓库 commit/tag、retrieval date、页面 heading、code-fence language、fixture category、expected parser status、known limitations。
2. 发布 corpus 只允许 pinned release/tag；stable/nightly/dev 只能进入 discovery 队列，不能进入 release/golden gate。抓取必须保存原始 block 和清洗后的 SQL，并生成 add/remove/change diff。
3. 从同一 release 的 Flink docs、Flink source 和 Calcite source 交叉核验 keywords；保留 “文档声明支持”“parser 可语法接受”“需要 planner/catalog 才可验证” 三种状态，不能混成一个 `supported`。
4. 对 Calcite drift 建立 lockfile/compatibility note：记录 parser conformance/quoting/case policy；升级 Calcite/Flink 时先生成 keyword、CST、diagnostic 和 acceptance diff，再决定是否更新 golden。
5. 语料分类至少区分 `parse-only`、`requires-catalog`、`requires-streaming`、`expected-error/known-limitation`、`not-sql`；MATCH_RECOGNIZE subset 负例必须存在。

**Warning signs:**

- manifest 的 `official_url` 含 `stable`/`nightlies`/`dev` 但没有 commit/tag；source revision 是 `latest` 或为空。
- corpus 数量随抓取日期改变，变更报告无法指出文档行/heading；示例中出现 `Flink SQL>`、输出表或省略号。
- Calcite dependency 升级没有 keyword/conformance diff；reserved list 与 parser 实际 token acceptance 不一致。
- Flink feature 通过 parser，但没有说明 catalog/streaming/planner 前置条件；或把 docs “known limitations” 当成 lexer error。

**Phase to address:**

**Phase 12：Flink Corpus and Calcite Compatibility** 必须在 Flink grammar 合并前完成 pin、分类和差分；**Phase 13：CI/Parity** 把 lockfile、fixture manifest、source hash 和 cross-backend snapshots 设为发布门禁。

**Evidence:** `corpus/manifest.tsv:1-14`; `.claude/CLAUDE.md:98-110`; [Flink 2.0 SQL overview](https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/overview/)（页面版本/过期提示、语句列表、reserved keywords）；[Windowing TVF](https://nightlies.apache.org/flink/flink-docs-release-1.20/docs/dev/table/sql/queries/window-tvf/); [MATCH_RECOGNIZE](https://nightlies.apache.org/flink/flink-docs-release-1.20/docs/dev/table/sql/queries/match_recognize/); [Calcite SqlParser.Config](https://calcite.apache.org/javadocAggregate/org/apache/calcite/sql/parser/SqlParser.Config.html); [Calcite Parser.jj](https://github.com/apache/calcite/blob/main/core/src/main/codegen/templates/Parser.jj)。

---

### Pitfall 6：CLI/LSP 未强制 dialect，languageId 与配置/profile 互相覆盖

**What goes wrong:**

v1 的 CLI 只接受 `format --profile <2.1|3.x|4.x>`，且没有 dialect 字段（`doris-sql/args.mbt:23-39,110-127`）；运行时只调用 `@api.format_with_ids(input, command.profile, ...)`（`doris-sql/run.mbt:72-87`）。LSP 的 `ServerState` 只有一个 `profile : String`（`lsp/handlers.mbt:4-14`），初始化只读取 `initializationOptions.profile`（`lsp/handlers.mbt:144-150,297-310`），随后所有 parse/format/completion 都复用该字符串（`lsp/handlers.mbt:78-89,164-170,248-271`）。迁移时若仅把 `profile` 改成 Flink release 或让 CLI 根据文件扩展名猜测，会出现：

- `--dialect flink --profile 4.x` 的参数被错误解释，或缺少 dialect 时静默落到 Doris；Flink 文档被当 Doris 解析并给出误导性的 `DORIS-*` 诊断。
- LSP `languageId = flink`、`languageId = sql`、`initializationOptions.dialect = flink`、用户配置 `fathom.dialect = doris` 冲突时，没有确定的 precedence；同一个打开文档的诊断可能在重连/配置变更后换方言。
- 当前 VS Code manifest 把所有 `.sql` 激活为 `doris`，settings 只提供 `doris.profile`，而 server 名称/diagnostic source 也写死 Doris（`vscode/package.json:15-57`; `lsp/handlers.mbt:44-46,152-161`）。若直接加 Flink extension，会造成两个扩展争抢 `.sql`，或用户看到 Flink 文档却仍发送 Doris profile。
- IntelliJ/LSP4IJ 等客户端若只传 profile、没有 dialect/capabilities handshake，会与 Native CLI/JS/Wasm 的显式 dialect contract 不一致。

**Why it happens:**

v1 的设计有意拒绝隐式 profile：文档要求 ParseOptions 显式选择 Doris 版本且未知值不回退（`docs/CONFIGURATION.md:43-61`）。多方言迁移若把这个已有强制性简单地扩展为“profile 字符串可取任意值”，就失去 dialect/profile 的正交性和校验边界。另一方面 LSP protocol 本身只知道 document URI/languageId 和客户端能力，业务 dialect 是产品 contract，不能靠 extension id 或文件名隐式推断。

**How to avoid:**

1. Phase 9 定义 `DialectSelection { dialect, profile, source }`，dialect 必填；profile 只在对应方言 namespace 内校验。默认不得自动检测；缺失、未知或冲突必须是结构化 usage/config error。
2. 统一 precedence 并持久化到文档 revision：显式 request/document configuration > server initialization config > 客户端 languageId 映射；若两者冲突，拒绝初始化/打开或发明确诊断，不静默覆盖。每个 `Document` 记录 dialect + profile，而不是 ServerState 只有一个 profile。
3. CLI API 为 `fathom-sql parse/format --dialect <doris|flink> --profile <...>`；LSP initialization/capabilities、didOpen、completion/formatting 请求使用相同 schema；JS/Wasm facade 也必须传同一字段。
4. 扩展不要让 `.sql` 自动决定方言：提供显式 language IDs/configuration 或按工作区设置选择，并在 `initialize` 做 capability echo；VS Code、IntelliJ、Web Monaco 都要有冲突和重连测试。
5. diagnostics 使用中立 `FATHOM-*`，payload 同时携带 dialect/profile/Document version；不得依靠错误 code 猜方言。

**Warning signs:**

- parser API 已有 `dialect`，但 `Document`/`Command`/`ParseResult`/LSP state 仍只有 `profile`。
- `languageId`、CLI flag、initializationOptions 和 workspace config 没有单元矩阵；缺字段时测试仍期待默认 Doris。
- Flink request 的错误 code/source 中出现 `DORIS`；同一 URI 改方言后旧 diagnostics 仍可覆盖新结果。
- VS Code/IntelliJ 端到端只测试 Doris `.sql`；没有 Flink languageId、显式冲突、未知 dialect、profile 不适用的负例。

**Phase to address:**

**Phase 9：Dialect Boundary and Neutral Naming** 冻结 selection/precedence/schema；**Phase 13：CLI/LSP/Editor Integration** 实现并验证强制 dialect、languageId/config 冲突和 revision-safe diagnostics。Flink parser 不能先以 Doris CLI/LSP 包装器“临时接入”。

**Evidence:** `doris-sql/args.mbt:23-39,110-127`; `doris-sql/run.mbt:17-24,72-87,102-125`; `lsp/handlers.mbt:4-14,44-46,78-89,144-161,164-170,248-271,297-310`; `lsp/documents.mbt:1-35`; `docs/CONFIGURATION.md:43-61`; `vscode/package.json:15-57`; [LSP 3.17 specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)。

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|---|---|---|---|
| 在 `classification_rows` 里追加 Flink 词，保留无参数 `is_reserved_word` | 改动小、旧测试易复用 | 方言交叉污染、隐式全局状态、漏词难审计；Doris/Flink 不能独立升级 | **从不**；Phase 9 必须先参数化并隔离表 |
| 用 `Dialect::Flink` 分支散落在 Doris `parser/parser.mbt` | 很快让几个 Flink 示例通过 | 路由不可证明、recovery/diagnostic 互相吞 token，后续无法删除 Doris 耦合 | 仅用于短期 spike，不能进入 release branch |
| 以 `stable`/`nightlies` URL 作为 corpus 版本 | 无需维护下载 pin | golden 随日期漂移，无法复现或定位 Calcite/Flink 变化 | discovery-only；release corpus **never** |
| 全局替换 `DORIS` 为 `FATHOM` | 机械迁移快 | 删除必须保留的 Doris dialect 标识，破坏历史 corpus provenance 和用户选择 | 只允许在命名矩阵/allowlist 驱动的 Phase 9 迁移 |
| 用文件扩展名或 languageId 自动推断 dialect | UI 不需新增控件 | `.sql`、多客户端和 workspace 配置冲突时静默解析错方言 | 可作为显示建议，不可作为 parser contract |
| 批量更新 snapshots 以“修复”Doris parity | 一次性清理大量 diff | 把真实 CST/diagnostic 回归永久锁死 | 只有 baseline 生成且逐字段审核后才可更新 |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|---|---|---|
| MoonBit module / package | 只改 `moon.mod` 名称，遗漏每个 `moon.pkg` import、`#export_name`、JS/Wasm exports | 先生成 module/import/export inventory；Native、JS、linear-Wasm 逐个调用同一 serialized API，见 `moon.mod:5-7`、`binding/exports.mbt:25-80` |
| Serialized schema | 仅改 schema 字符串，保留 Doris field/error message 或让旧/new namespace 同时可用 | clean cutover：`dialect` 与 profile 正交、schema/error constants 单一生产者、binding/parity/LSP/fixtures 同步；见 `binding/schema.mbt:3-5,69-83,107-148` |
| Flink + Calcite | 把 Flink docs keyword list 当 parser 的永久权威，忽略 `SqlParser.Config` conformance/quoting/casing | 锁 Flink release + Calcite version/config，docs/source 交叉校验并审阅 diff；见 [Calcite Config](https://calcite.apache.org/javadocAggregate/org/apache/calcite/sql/parser/SqlParser.Config.html) |
| LSP client | 用 `languageId` 代替 dialect，或只把全局 profile 放在 ServerState | document-level `DialectSelection`，初始化协商、显式冲突拒绝、revision 绑定；见 `lsp/handlers.mbt:4-14,144-161` |
| VS Code / IntelliJ | 只改显示名称，忘记 activation event、`.sql` selector、settings、artifact/workflow | 运行真实宿主 smoke：Doris/Flink/冲突/缺失配置/服务器不可用；见 `vscode/package.json:15-57`、`.github/workflows/jetbrains-plugin.yml:19-46` |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|---|---|---|---|
| 每个 token 在多方言表中线性扫描 | 大 SQL 或 completion 延迟随 keyword rows × token 数增长 | 构造 dialect-local immutable lookup/index；保留小表时先 benchmark，勿复制 source bytes | Flink keyword + recovery inventory 增长、IDE 连续输入时可见 |
| Window TVF/MATCH_RECOGNIZE 每次失败都回退整个 Doris statement | 单字符编辑造成全文件 diagnostics 抖动，恢复步数爆炸 | 独立子语言同步点、bounded recovery、共享全量 parse oracle；沿用 `ParserLimits` 边界 | 半成品 pattern、深层括号或长脚本 |
| 为实现 parity 在每个 backend 重复序列化/CST source | Native/JS/Wasm 内存和输出时间不同，source bytes 多份 | root-only source transport、primitive schema 单一生产者；保持 `api.ParseResult` contract | 大 corpus、浏览器 worker、多文档 LSP |
| 将 corpus 抓取和每次 CI 构建混在一起 | CI 时间和结果取决于网络/文档变化 | 抓取离线预生成 pinned artifact，CI 只校验 hash/manifest 并运行 fixtures | 发布或无网络环境；当前 manifest 已记录 offline gaps（`corpus/manifest.tsv:1-14`） |

## Security Mistakes

| Mistake | Risk | Prevention |
|---|---|---|
| 通过 `.sql` 扩展名、languageId 或未验证 `profile` 自动选择 dialect | 攻击者/用户可诱导工具以错误语法接受输入，诊断/格式化结果不可信 | dialect/profile 必填、枚举校验、冲突拒绝；结果携带实际 selection |
| 为了“兼容”把 unknown Flink keyword 全部降级成 identifier | 错误 acceptance，后续 analyzer/formatter 产生危险的错误编辑 | dialect-local inventory + explicit unknown/error node；不以宽松 parser 隐藏覆盖缺口 |
| 让 corpus 抓取直接执行示例或把 planner/catalog 结论写入 parser | 语料中的命令/输出/恶意文本进入执行边界，且破坏离线 parser 纯度 | `parse-only` 默认、原始 block 隔离、无 FE/database 执行；参照 `docs/API.md:5-17` 的纯前端边界 |
| 允许过期 LSP response 以另一方言/配置覆盖当前文档 | 编辑器显示错误诊断或错误格式化 edit | 每个 Document 保存 version+dialect，response 带 revision，拒绝 stale；`lsp/documents.mbt:17-35` 已有版本单调性，可扩展 selection |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---|---|---|
| UI 只显示 “SQL” 或 “Doris profile”，不显示 dialect | Flink 用户不知道解析器为何拒绝 Window TVF/MATCH_RECOGNIZE | 顶层显示 `Dialect: Flink` + release/profile + source（config/languageId），冲突显示可操作错误 |
| 缺少 dialect 时悄悄默认 Doris | 用户看到看似精确但实际错误的 diagnostics | 明确要求选择 dialect；CLI exit 2/LSP initialize error；不要牺牲 v1 的显式 profile 原则 |
| 错误文案仍为 `unsupported Doris profile`/`DORIS-LSP-001` | 中立产品下诊断和文档自相矛盾，Flink 支持看起来是假功能 | FATHOM namespace + dialect/profile fields；保留 Doris 作为值而不是产品前缀 |
| 只有成功样例，没有 Flink subset/冲突/缺 profile 的负例 | 用户无法理解 parser 语法覆盖与 planner/catalog 限制 | UI/文档展示 supported/known limitation/semantic prerequisite，并用官方负例 fixture 驱动 |

## "Looks Done But Isn't" Checklist

- [ ] **Keyword isolation:** 每个 `classification_of`/`is_reserved_word` 调用都经过 Dialect-local table；Doris 与 Flink 冲突词有双向 identifier/keyword 测试。
- [ ] **Statement routing:** `SELECT/CREATE/INSERT` 先经过显式 dialect router；Window TVF、MATCH_RECOGNIZE 不在 Doris fallback 中解析。
- [ ] **Doris parity:** 所有 v1 corpus、malformed/recovery、2.1/3.x/4.x feature gates 的 bytes/CST/spans/diagnostics/format 输出均与冻结 baseline 相同。
- [ ] **Dialect/profile contract:** API、serialized schema、CLI、LSP、JS/Wasm、DocumentStore 都显式携带 dialect；缺失或冲突不自动 Doris。
- [ ] **Neutral naming:** module/import、binary/export、schema、error code、LSP source/serverInfo、VS Code/IntelliJ artifacts、docs、snapshots 均按迁移矩阵完成；允许保留项仅为 Doris dialect/provenance。
- [ ] **Flink corpus provenance:** 每个 fixture 有 release、Calcite version/config、source URL、commit/tag、heading、retrieval date、分类和 known limitation；没有 stable/nightly/dev 漂移输入。
- [ ] **Cross-target/editor parity:** Native/JS/linear-Wasm、VS Code、IntelliJ、Web Monaco 的同一 dialect/profile fixture 输出一致，stale response 与 languageId/config 冲突有真实宿主测试。

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---|---|---|
| 全局 keyword 表已混入 Flink | HIGH | 从 git/冻结 Doris baseline 恢复旧表；建立 dialect-local tables；重新生成分类 inventory；逐词跑 Doris/Flink acceptance 与 formatter parity，不保留全局兼容 alias |
| Flink rule 已污染 Doris parser | HIGH | 以 router 为切点拆出 Flink module；保留共享 token/CST 原语；为每个 statement 重新指定 sync/recovery 集合；重跑 Doris strict/editor baseline |
| Doris CST/diagnostic parity 回归 | HIGH | 锁定首个失败 fixture/source hash；比较 lexer→CST→serialized→printer 分层 diff；禁止更新 snapshot，修复后重跑全量 v1 baseline 与 cross-backend gate |
| 命名迁移漏掉公共边界 | MEDIUM/HIGH | 运行 forbidden/allowlist inventory，按 module/ABI/schema/error/LSP/extension/docs 分类修复；重新生成 release artifacts 与 client package；确保 Doris dialect/provenance allowlist 未被误删 |
| Flink corpus 漂移 | MEDIUM | 停止更新 golden；恢复最近 pinned release/commit；对新文档生成 diff queue；重新记录 Calcite lock/config 和 fixture categories，再决定是否提升规范 |
| LSP/CLI 解析错 dialect | MEDIUM/HIGH | 拒绝受影响的 selection/config，清空旧 revision diagnostics；加入 explicit `DialectSelection`；复现 languageId/config/init 三方矩阵，验证新/旧文档不会交叉覆盖 |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---|---|---|
| 全局 keyword/classification 冲突或漏词 | **Phase 9 — Dialect Boundary**；**Phase 10 — Flink Lexical Core** | 静态禁止无 dialect 分类调用；逐词 inventory 无重复/无漏项；冲突词双 dialect fixture |
| Flink 文法污染 Doris、路由错误、DorisFeature 混用 | **Phase 9 — Router/Capability Contract**；**Phase 10 — Flink Grammar** | Doris/Flink 双向 negative gate；每条 statement kind 由 router 唯一决定；共享 parser 包不 import DorisFeature |
| Doris CST/diagnostic/parity 回归 | **Phase 11 — Doris Regression/Parity Gate** | 冻结 v1 baseline；字节级 replay、CST spans、diagnostic fields、profile gates、formatter 和 native/JS/Wasm 全部 diff 为零或有批准变更 |
| 命名迁移遗漏 | **Phase 9 — Neutral Naming**；**Phase 13 — Packaging/Editors** | module/export/schema/error/LSP/CLI/VS Code/IntelliJ/docs inventory；forbidden/allowlist gate；真实 artifact/install smoke |
| Flink corpus/dev/Calcite 漂移 | **Phase 12 — Corpus and Calcite Compatibility** | pinned release+commit+Calcite lock；source hash、manifest diff、known limitation 和 nightly exclusion 检查 |
| CLI/LSP dialect 未强制、languageId/config/profile 冲突 | **Phase 9 — Selection Contract**；**Phase 13 — CLI/LSP/Editor Integration** | 缺失/未知/冲突均拒绝；document-level revision selection；VS Code/IntelliJ/Web/Native E2E 与 stale-response 测试 |

## Sources

### Local project evidence

- `/.planning/PROJECT.md:72-81` — v2.0 目标、Dialect/Flink/中立命名/语料 CI 要求。
- `/token/token.mbt:3-7,133-141,297-306,307-325,449-493` — v1 Doris profile、DorisFeature、全局分类表和无参数分类查询。
- `/parser/parser.mbt:118-124,265-275,3342-3370` — 单一 Doris recovery context、Pratt precedence、语句入口路由。
- `/api/api.mbt:42-75,162-193,273-310` — 显式 Doris ParseOptions、primitive result、syntax tree 校验。
- `/binding/schema.mbt:3-5,29-57,69-83,107-148`、`/binding/exports.mbt:25-80` — Doris schema/error namespace 和 ABI exports。
- `/corpus/manifest.tsv:1-14`、`/corpus/tools/check_keywords.py:23-41,93-103` — v1 corpus provenance 与 Doris keyword inventory gate。
- `/doris-sql/args.mbt:23-39,110-127`、`/doris-sql/run.mbt:17-24,72-87` — CLI 只有 Doris profile，运行时直达 `format_with_ids`。
- `/lsp/handlers.mbt:4-14,36-46,78-89,144-161,164-170,248-271,297-310`、`/lsp/documents.mbt:1-35` — LSP 单一 profile、Doris source/code、version store。
- `/moon.mod:5-7`、`/vscode/package.json:15-57`、`/.github/workflows/doris-native-release.yml:93-107`、`/.github/workflows/jetbrains-plugin.yml:19-46` — module、VS Code、Native 和 IntelliJ 发布命名耦合。
- `/docs/CONFIGURATION.md:43-61`、`/docs/API.md:5-17,35-40` — 显式 Doris profile 和 parser/analyzer/offline 边界。

### Apache Flink / Calcite official evidence

- [Apache Flink SQL overview, release 2.0](https://nightlies.apache.org/flink/flink-docs-release-2.0/docs/dev/table/sql/overview/) — Flink SQL 基于 Calcite；DDL/DML/query 语句列表；reserved/future-reserved keywords；版本页面的 stable/out-of-date 提示。
- [Apache Flink Windowing TVF, release 1.20](https://nightlies.apache.org/flink/flink-docs-release-1.20/docs/dev/table/sql/queries/window-tvf/) — TUMBLE/HOP/CUMULATE/SESSION、`TABLE`/`DESCRIPTOR`/命名参数和 FROM 中 PTF 结构。
- [Apache Flink Pattern Recognition / MATCH_RECOGNIZE, release 1.20](https://nightlies.apache.org/flink/flink-docs-release-1.20/docs/dev/table/sql/queries/match_recognize/) — PATTERN、DEFINE、MEASURES、AFTER MATCH SKIP、subset/known limitations。
- [Apache Calcite `SqlParser.Config`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/sql/parser/SqlParser.Config.html) — parserFactory、conformance、quoting、case sensitivity、quoted/unquoted casing 等 release/config 变量。
- [Apache Calcite `Lex`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/config/Lex.html) — lexical policy、quoting/casing/case-sensitive 组合，不应被误当作一个全局 SQL keyword 表。
- [Apache Calcite `Parser.jj`](https://github.com/apache/calcite/blob/main/core/src/main/codegen/templates/Parser.jj) — 官方 parser 模板显示 `IGNORE_CASE = true`、`UNICODE_INPUT = true` 和生成式 parser 边界。
- [Language Server Protocol 3.17 specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/) — language/client capability、document synchronization、position encoding 和 revision 语义的协议边界。

---
*Pitfalls research for: Fathom v2.0 Multi-Dialect: Flink SQL & Neutral Naming*
*Researched: 2026-08-06*
