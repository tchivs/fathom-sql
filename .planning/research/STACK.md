# Stack Research

**Domain:** MoonBit 无损 CST 的多方言 SQL Parser SDK（Doris + Flink SQL）  
**Researched:** 2026-08-06  
**Confidence:** HIGH（MoonBit 与 Apache 官方文档/源码、版本和本地 v1 约束已交叉核对；Flink 某些未单独文档化的词法行为按 Calcite 版本源码保守处理）

## 结论先行

1. **方言路由选闭合 `enum` + `match`，不要用 `pub(open) trait`。** Doris 与 Flink 是当前产品明确支持的有限集合，需要在新增方言时让所有 lexer、keyword、statement、formatter、diagnostic、completion 和 adapter 路由获得编译器的穷尽性检查。MoonBit 文档定义普通 `enum` 为闭合构造集合，`match` 可覆盖所有 constructor；`pub(open) trait` 则允许包外实现，适合开放的 Catalog/host extension 接口，不适合作为静态方言集合的唯一判别器（[MoonBit enum/match](https://docs.moonbitlang.com/en/latest/language/fundamentals.html#enum)、[MoonBit trait visibility](https://docs.moonbitlang.com/en/latest/language/packages.html#traits)）。
2. **推荐以 Flink 2.3.0 作为当前主语料 profile，并同时锁定 2.1.3、1.20.5 作为发布线回归 profile。** Apache 下载页在本次研究中列出 2.3.0 为最新稳定版本，以及 2.2.1、2.1.3、1.20.5；不要使用 `dev`、`stable` 或 moving `release-2.3` branch 作为长期 fixture 入口（[Flink Downloads](https://flink.apache.org/downloads/)）。
3. **权威性采用三层而不是单一来源：** 发布版 Flink SQL 文档决定用户可见支持面；对应发布源码的 `flink-sql-parser` 与测试决定 Flink-specific productions；源码中锁定的 Calcite 版本及 `Parser.jj` 决定共享 SQL lexical/grammar 基线。Flink 2.3 的 `flink-table/pom.xml` 锁定 Calcite 1.36.0，Flink 1.20 锁定 Calcite 1.32.0；因此不能拿当前 Calcite `main` 直接替代 Flink 的 parser oracle（[Flink 2.3 table POM](https://raw.githubusercontent.com/apache/flink/release-2.3/flink-table/pom.xml)、[Flink 1.20 table POM](https://raw.githubusercontent.com/apache/flink/release-1.20/flink-table/pom.xml)、[Calcite Parser template](https://github.com/apache/calcite/blob/calcite-1.36.0/core/src/main/codegen/templates/Parser.jj)）。
4. **lexer 必须变成 profile-specific，而不是在 Doris lexer 上继续堆条件。** Doris v1 当前把 `--`、`#`、`/*…*/` 都识别为 comment，并把 `"…"` 与 `` `…` `` 都识别为 quoted token（[本地 `lexer/lexer.mbt:277-307`](../../lexer/lexer.mbt#L277-L307)）。Calcite 基线只定义 `--`/`//` 单行注释和 block/formal comment，并将 `#` 留为非法/未知字符；它还定义 X binary string 与 U& Unicode string，而 B bit-string 并未出现在该模板的 literal token 定义中（[Calcite lexical template](https://github.com/apache/calcite/blob/calcite-1.36.0/core/src/main/codegen/templates/Parser.jj#L9430-L9750)）。Flink profile 应明确测试并锁定这些行为，不能继承 Doris 的宽松接受面。
5. **命名采用一次性 clean cutover。** 公开 module/import 统一为 `fathom/sql`，Native 可执行文件为 `fathom-sql`/`fathom-lsp`，wire schema 为 `fathom.parse.v1`、`fathom.format.v1`、`fathom.error.v1`、`fathom.capabilities.v1`，错误码为 `FATHOM-*`；dialect 作为 schema/API 字段保留 `doris` 与 `flink`。不保留 `doris-*`、`doris.*`、`DORIS-*` 的兼容 alias，因为本 milestone 明确不考虑向后兼容。MoonBit module 名允许 `/`、`-`，发布到 Mooncakes 时需 username 前缀且使用 SemVer；package 名由目录决定，executable/foreign_library 要用 `pkgtype`（[MoonBit module config](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html)、[package config/export](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html)）。

## Recommended Stack

### Core Technologies

| Technology | Version / pin | Purpose | Why Recommended |
|------------|---------------|---------|-----------------|
| MoonBit compiler/toolchain | **项目锁定：moon 0.1.20260724，v0.10.5 policy**；每个 CI/release artifact 记录完整 `moon version` | 单一 parser/CST 实现，输出 Native、JS、linear Wasm | 现有 module 已记录 exact toolchain 与 `preferred_target = "native"`（[本地 `moon.mod:1-8`](../../moon.mod#L1-L8)）。官方文档明确支持 `wasm`、`wasm-gc`、`js`、`native`，适合保持一份 lexer/parser。不要因本次研究的 v0.10.6 文档页面就无审查升级 compiler。 |
| Handwritten lexer + recursive descent + Pratt expressions | 项目内部技术，不引入版本化 parser runtime | 共享 SQL core、方言 token/keyword 表、方言 statement route、无损 CST 和 editor recovery | v1 已证明 source-backed byte spans、trivia、bounded recovery 与 round-trip 合同；Flink 需要 TABLE/DESCRIPTOR、window TVF、watermark/metadata column、MATCH_RECOGNIZE 等扩展，手写路由比生成 parser 更容易保持错误节点与原字节。保留 `source → token → syntax/parser → api/binding → adapters` 依赖方向（[本地 `api/api.mbt:1-120`](../../api/api.mbt#L1-L120)）。 |
| Closed `Dialect` enum + exhaustive route table | 新增 v2 API；建议 constructor 至少 `Doris`、`Flink` | 所有静态方言分发的单一判别值 | 普通 enum 是闭合集合，`match` 在新增构造时产生遗漏警告；不会因为第三方实现而改变词法或语法。为开放扩展保留独立 trait，而不是把 dialect 本身建模成 open trait。可选的 `extenum` 也不适合作为核心 route：官方文档要求 wildcard，因为未来 constructor 可在包外增加。 |
| Versioned primitive wire schema | `fathom.parse.v1`、`fathom.format.v1`、`fathom.error.v1`、`fathom.capabilities.v1` | Native/JS/Wasm/LSP/CLI 之间稳定传输 CST view、trivia、span、diagnostics、dialect | 当前 binding 是 schema 单一生产者但仍硬编码 `doris.*` 与 `DORIS-*`（[本地 `binding/schema.mbt:1-105`](../../binding/schema.mbt#L1-L105)）。schema v1 应做 clean cutover，保留 `dialect`、`exact_release`、`feature_introduction`、byte spans 和 source transport 字段；不要跨 ABI 暴露 MoonBit 内部 ADT。 |
| Released Flink SQL corpus profiles | **主 profile：Flink 2.3.0**；回归 profiles：2.1.3、1.20.5 | 发布版 SQL examples、DDL/DML/query 语法、keyword snapshot、negative cases | 2.3.0 是官方下载页列出的最新 stable；2.1.3 与 1.20.5 覆盖 2.x/1.x 发布线。每个 profile 绑定 source tarball、SHA-512/PGP 校验、docs path、source commit/tag、文件 hash 和抽取日期。 |
| Flink SQL parser source + matching Calcite source | Flink 2.3.0 → **Calcite 1.36.0**；Flink 1.20.5 → **Calcite 1.32.0** | 差分 oracle、keyword/grammar 变更审计、未在 docs 单独成页的语法 | Flink 的 `flink-sql-parser` 通过 `config.fmpp`/`parserImpls.ftl` 定制从 Calcite template 生成 parser；2.3 POM 的 Calcite 版本是 1.36.0，1.20 POM 是 1.32.0。将 Flink-specific includes 与对应 Calcite tag 一起锁定，不运行 Java FE 作为 SDK 依赖。 |

### Supporting Libraries / Packages

| Library / boundary | Version / pin | Purpose | When to Use |
|-------------------|---------------|---------|-------------|
| `moonbitlang/core` | 与当前 MoonBit lock 一起 pin；不在本研究中升级 | Array/Bytes/String/Map、debug、UTF-8、buffer | 始终作为 parser core 唯一必需 runtime dependency；继续使用 byte offsets，保持 source ownership 一次。 |
| `moonbitlang/x` | 仅 edge evaluation，当前仓库已有历史研究建议 `0.4.47`；不得进入 lexer/CST | JSON 或 adapter utility | 只有在跨 backend smoke test 证明 API/Unicode/size 行为稳定后才用于 LSP/binding 边缘；核心不依赖实验包。 |
| LSP 3.17 JSON-RPC adapter | LSP 3.17 baseline | Native `fathom-lsp`，dialect-aware diagnostics/formatting/completion | 保持 transport 在边缘；`initialize`/document sync/diagnostics/formatting 先复用同一 `fathom/sql` API。UTF-16 只在 adapter 做转换（[LSP 3.17](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)）。 |
| Generated JS ESM + linear Wasm facade | MoonBit backend output；首发不承诺 Wasm GC | Browser/Monaco/Web SDK | 用 primitive `Bytes`/UTF-8 JSON wrappers；`foreign_library` 包只导出稳定 wrapper。官方 package docs 将 `#export_name` 限制为 public、non-generic、C-symbol-compatible 且 package-local unique，故使用 `fathom_parse_v1` 等稳定导出名而非导出内部 CST（[MoonBit package exports](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html#package-type)）。 |
| npm/VS Code/JetBrains package tooling | npm wrappers 与扩展各自锁 package manager；不进入 MoonBit core | 分发 `fathom-sql` JS facade、VS Code/IntelliJ adapters | 扩展只传 `dialect`、schema v1 和 `fathom-lsp` path；语言配置/command/configuration key 全部使用 `fathom` 前缀。当前扩展仍硬编码 `doris` language id、`doris.profile` 与 `doris-lsp`（[本地 `vscode/package.json:1-58`](../../vscode/package.json#L1-L58)），因此必须在命名迁移时整体改名而非加一个新入口。 |

## 方言路由决策：`enum + match` 优于 `pub(open) trait`

### 推荐形状

```moonbit
pub(all) enum Dialect {
  Doris
  Flink
}

fn keyword_table(dialect : Dialect) -> KeywordTable {
  match dialect {
    Dialect::Doris => @doris_keywords.table()
    Dialect::Flink => @flink_keywords.table()
  }
}
```

这里的 `Dialect` 不是可由用户实现的策略对象，而是产品支持矩阵的一部分。`ParseOptions`、CLI `--dialect`、LSP initialization/configuration、serialized schema 和 completion context 都携带它；每个 route function 对 enum 做一次穷尽 `match`，禁止全局 `classification_rows` 再次成为跨方言隐式状态。

### 为什么不以 `pub(open) trait Dialect` 为核心

- `pub(open) trait` 的语义是允许包外新增 implementation；这正是可扩展 Catalog、host capability 或 analyzer provider 所需的开放性，不是 Doris/Flink 这种有限集合的产品合同。
- trait 的 coherent implementation 规则仍允许类型/trait 所属包添加实现；它提供的是行为抽象而不是 `match` 的 constructor exhaustiveness。若将 route 改为 trait，新增 Flink production 可能只实现部分方法，编译器不会像闭合 enum 那样强制所有 route 都更新。
- trait dispatch 会使路由配置、ABI 和测试矩阵分散到 implementations；对无损 parser 更重要的是 token kind/classification/grammar/recovery/diagnostics 处于同一个 selected dialect context。
- `extenum` 也不是替代方案：官方文档明确指出 open enum 的 pattern match 必须有 wildcard。wildcard 会掩盖新方言未接入某个 route 的错误。

### trait 的保留边界

可以定义 `pub(open) trait Catalog`、`pub(open) trait AnalyzerProvider` 或 `pub(open) trait HostTransport`，由用户包外实现；trait 的输入输出应是中立 primitive/CST view，不得把 `Dialect` route 交给用户实现。当前 analyzer 已作为独立包、不反向污染 parser 的边界（[本地 `analyzer/moon.pkg`](../../analyzer/moon.pkg) 与项目约束 [`.claude/CLAUDE.md:19-22`](../../.claude/CLAUDE.md#L19-L22)）。

## Flink 权威来源与可 pin 版本

### Source precedence

| 层级 | 权威材料 | 用途 | 锁定方法 |
|------|----------|------|----------|
| 1 | Flink 发布版 SQL docs | 用户可见 feature/support 面、示例、DDL/DML/query 语法 | 只从 `flink-docs-release-2.3`/对应 release path 抽取；拒绝 `dev`、`stable`、nightly。 |
| 2 | 对应 release source 的 `flink-table/flink-sql-parser` | Flink 自定义 statement、DDL、window/TVF、keyword addition 和 parser tests | 以 `flink-2.3.0-src.tgz`（或 release tag 对应 commit）为输入，记录 source commit + path + hash；不要只引用 moving branch。 |
| 3 | Flink POM 锁定的 Calcite | shared SQL grammar、token/quoted/comment/literal 基线和 MATCH_RECOGNIZE | Flink 2.3 → Calcite 1.36.0；Flink 1.20 → Calcite 1.32.0；从对应 Calcite release tag/source artifact 抽取，不用 `main`。 |
| 4 | Apache Calcite `Parser.jj` 与 parser tests | 当 Flink docs 不单列某语法（例如 MATCH_RECOGNIZE）时的 grammar oracle | 仅在 Flink release 的 Calcite 版本范围内解释；Fathom 自己仍实现 CST，不引入 Calcite/Java runtime。 |

### Recommended pin set

| Fathom profile | Official release | Docs URL root | Source / parser URL | Calcite pin |
|----------------|------------------|---------------|---------------------|-------------|
| `flink-2.3.0` | Flink 2.3.0 | [`/flink-docs-release-2.3/docs/sql/reference/overview/`](https://nightlies.apache.org/flink/flink-docs-release-2.3/docs/sql/reference/overview/) | [`release-2.3/flink-table/flink-sql-parser`](https://github.com/apache/flink/tree/release-2.3/flink-table/flink-sql-parser)；manifest 中再记录 release tag commit | 1.36.0，见 [`flink-table/pom.xml`](https://raw.githubusercontent.com/apache/flink/release-2.3/flink-table/pom.xml) |
| `flink-2.1.3` | Flink 2.1.3 | [`/flink-docs-release-2.1/`](https://nightlies.apache.org/flink/flink-docs-release-2.1/) | 对应 source release/tag；不得从 2.3 docs 回填 | 与该 release POM 一起锁定 |
| `flink-1.20.5` | Flink 1.20.5 | [`/flink-docs-release-1.20/docs/dev/table/sql/overview/`](https://nightlies.apache.org/flink/flink-docs-release-1.20/docs/dev/table/sql/overview/) | [`release-1.20/flink-table/flink-sql-parser`](https://github.com/apache/flink/tree/release-1.20/flink-table/flink-sql-parser) | 1.32.0，见 [`flink-table/pom.xml`](https://raw.githubusercontent.com/apache/flink/release-1.20/flink-table/pom.xml) |

Apache 下载页提供 source archive、`.asc` 和 `.sha512` 链接；corpus 更新脚本必须先验证签名/sha512，再抽取 SQL 文档。release branch URL 可供人工审计，但不能写入没有 commit/hash 的长期 manifest（[Flink Downloads](https://flink.apache.org/downloads/)）。

## Flink corpus 提取与锁定

1. **先选 release profile，再下载 source archive。** 默认只接受 `flink-2.3.0`；每个旧 profile 由明确的 release ticket 加入，不设 `flink-dev` 或 `latest` fallback。
2. **验证来源。** 下载 `flink-X.Y.Z-src.tgz`、`.sha512`、`.asc`，使用 Apache KEYS/PGP 与 SHA-512 验证；manifest 写入 archive URL、验证结果、release tag/commit、retrieved_at、archive digest。
3. **抽取两套输入。**
   - docs positives：只抽取 release docs 中 SQL reference 的 query/DDL/DML/utility 页面和 fenced SQL examples；保留 page path、heading、anchor、source URL、release profile、原文 hash。
   - parser oracle：抽取 `flink-sql-parser` 的 `parserImpls.ftl`、`config.fmpp`、`data/Parser.tdd`、tests，以及对应 Calcite `Parser.jj`；保留 source path、commit、Calcite version、文件 hash。不要把 Java AST 输出当作 Fathom 的 CST contract。
4. **规范化但不改源码。** fixture 文件可归一化行尾和 metadata，但 SQL bytes、注释、大小写、反引号、`=>`、interval literal 和错误样本另存 raw source；每行 manifest 至少含 `fixture_id, dialect, flink_release, source_url, source_path, source_commit, calcite_version, category, expected_status, sha256`。
5. **按 release 分组，禁止跨版本静默合并。** 目录建议 `corpus/flink-2.3.0/{ddl,dml,query,window,match-recognize,negative}`、`corpus/flink-2.1.3/...`、`corpus/flink-1.20.5/...`。相同 SQL 若在多个 release 出现，保留多条 provenance；仅由测试明确证明等价时共享 fixture 内容。
6. **处理漂移与冲突。** CI 重新下载同一 archive/commit 后校验 digest；如果 URL 页面内容变化但 release digest 不变，报告 docs mirror drift；如果 docs 与 parser source 冲突，保留 conflict record 和两类测试，不以 moving docs 自动覆盖已发布行为。
7. **禁止 dev 文档进入 release gate。** `doris` 现有 corpus 已采用 release family/profile metadata 与 manifest 校验（[本地 `token/token.mbt:55-104`](../../token/token.mbt#L55-L104)）；Flink 应复用该“exact release + feature introduction mismatch 必须拒绝”的模式，而不是把 `dev` 当作隐式未来方言。

## Flink SQL 对栈的影响

### Lexer compatibility matrix

| Input | Doris v1 当前行为 | Flink/Calcite baseline | Fathom 栈影响 |
|------|-------------------|------------------------|----------------|
| `--` / `/*…*/` | comment，保留 trivia | comment；Calcite 还声明 `//` 单行 comment | shared scanner 可复用 comment span，但 Flink profile 要加入 `//`（若目标 release 测试确认）；formatter 必须原样保留。 |
| `# comment` | `#` 从 `lexer/lexer.mbt:277` 进入 Comment | Calcite lexical block 没有 `#` 单行 comment；`#` 不属于 identifier/token | Flink 不应继承 Doris `#` comment；将它 lex 为 `Unknown/Error` 并给稳定 `FATHOM-LEX-*` 诊断，除非某个明确 Flink release fixture 证明 SQL client 另有预处理。 |
| `"name"` | `Quoted`，与 backtick 同路径（[本地 lexer:300-307](../../lexer/lexer.mbt#L300-L307)） | Calcite 有 DQID lexical state 的 double-quoted identifier；同时也有 BigQuery-specific double-quoted string state；实际行为依 selected `Lex` 配置 | Flink adapter 必须固定 release parser 的 lexical configuration；不要把 Doris “双引号永远是 identifier”复制到共享 lexer。用 positive/negative fixtures 验证 quoted identifier、string alias 和 formatter round-trip。 |
| `` `name` `` | `Quoted` | Flink docs 示例明确使用 backticks；Calcite BTID/BQID 有 backtick identifier states | Flink keyword table 及 identifier classification 应以 backtick 为首选文档表现；escape 规则按 release fixture 锁定。 |
| `X'AB'` | v1 lexer 只有 `'...'` string 路径，`X` 会先成为 identifier | Calcite `BINARY_STRING_LITERAL` 明确定义 `X`/`x` + quote | Flink token kind 增加 binary literal，保留 raw bytes 和 source span；Doris profile 不因共享 code 而误接受。 |
| `B'0101'` | v1 无 prefixed literal token | Calcite 1.36 `Parser.jj` 的 literal token section 没有 `BINARY/BIT_STRING_LITERAL` 的 `B'...'` token | 不把 “SQL 标准通常有 B literal”当作 Flink 事实。默认 Flink 2.3 栈只锁定 X 与 U&；若 Flink release test corpus 证实 B，增加 `FlinkBitStringLiteral`，否则产生 unsupported/error CST，且不能改 Doris。 |
| `U&'...'` | v1 无 Unicode-prefixed literal token | Calcite 定义 `UNICODE_STRING_LITERAL`（`U&` + quoted string）；另有 `U&` quoted identifier | Flink lexer/parser 要区分 Unicode string 与 Unicode quoted identifier；保留 escape character/source bytes，不能把 `U` 当普通 identifier 后再由 parser 猜测。 |

### Grammar/statement matrix

| Flink feature | Official evidence | Parser/CST consequence |
|---------------|------------------|------------------------|
| `CREATE TABLE` physical/metadata/computed columns, `WATERMARK`, `PRIMARY KEY NOT ENFORCED`, `PARTITIONED BY`, `DISTRIBUTED`, `WITH`, `LIKE`, `AS` | [Flink 2.3 CREATE](https://nightlies.apache.org/flink/flink-docs-release-2.3/docs/sql/reference/ddl/create/)；1.20 对应页也有 CREATE grammar | column declaration 不能复用 Doris 的 column/engine/property node；metadata `FROM`、`VIRTUAL`、watermark expression、connector properties 必须有 source-backed CST nodes。 |
| Window TVF `TUMBLE`, `HOP`, `CUMULATE`, `SESSION` | [Flink 2.3 Window TVF](https://nightlies.apache.org/flink/flink-docs-release-2.3/docs/sql/reference/queries/window-tvf/) | `FROM` 中 table function/`TABLE` argument、`DESCRIPTOR(timecol)`、interval literal、named argument `=>` 和 subsequent window columns 需要明确 productions；不能只把 TVF 当普通 function call。 |
| `MATCH_RECOGNIZE` | Calcite `Parser.jj` 的 `SqlMatchRecognize`/`AFTER MATCH SKIP` productions（[pinned template](https://github.com/apache/calcite/blob/calcite-1.36.0/core/src/main/codegen/templates/Parser.jj)）；Flink overview 未提供稳定独立页面 | 按 Flink release 的 parser/test evidence 建 grammar fixtures；CST 必须保留 `PATTERN`, `DEFINE`, `MEASURES`, `AFTER MATCH SKIP`, quantifier 和 pattern variable，不从 docs 缺页推断“不支持”。 |
| DML/utility | [Flink 2.3 overview](https://nightlies.apache.org/flink/flink-docs-release-2.3/docs/sql/reference/overview/) 列出 SELECT、CREATE/DROP/ALTER、ANALYZE、INSERT/UPDATE/DELETE、DESCRIBE/EXPLAIN/USE/SHOW/LOAD/UNLOAD | statement entry route 必须按 dialect 分发；不能让 Doris DDL fallback 接住未知 Flink statement，否则会破坏 diagnostics 和 lossless recovery。 |
| Flink 2.3 additions | 2.3 CREATE 页还列出 MATERIALIZED TABLE、MODEL；这类页面在 1.20 不同 | feature metadata 应绑定 exact Flink release，selected profile mismatch 产生结构化 diagnostic；不要把新 DDL 无条件加入 1.20 profile。 |
| Doris-specific | 当前 `DorisFeature`/`DorisProfile` 是显式版本门控（[本地 `token/token.mbt:133-247`](../../token/token.mbt#L133-L247)） | 迁移时将 Doris feature gates 置于 `Doris` dialect namespace；Flink 的 keyword classification/feature introduction 独立存放，禁止共享 `classification_rows`。 |

## Naming-neutralization and release conventions

| Surface | Required convention | Integration point / gate |
|---------|---------------------|--------------------------|
| MoonBit module/import | root module `fathom/sql`；package dirs `source`, `token`, `lexer`, `parser`, `api`, `binding`, `formatter`, `completion`, `analyzer`; no public `fathom/doris-sql` imports | `moon.mod` module name allows `/` and `-`; package name comes from directory, so directory rename must happen before rewriting imports ([module](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html#name), [package](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html#name)). |
| Native CLI/LSP | binaries `fathom-sql` and `fathom-lsp`; commands `parse`, `format`, `lsp` accept required `--dialect doris|flink` plus dialect-specific release/profile | Current CLI package is `doris-sql` executable and imports `fathom/doris-sql/api` ([本地 `doris-sql/moon.pkg:1-13`](../../doris-sql/moon.pkg#L1-L13)); rename package and executable in one cutover; do not silently default to Doris. |
| Wire schema | `fathom.parse.v1`, `fathom.format.v1`, `fathom.error.v1`, `fathom.capabilities.v1` with `dialect` field; `source_transport` remains explicit | binding remains sole schema producer; all wrappers compare serialized results byte-for-byte across native/js/wasm. Existing `doris.*` literals are migration inventory ([本地 `binding/schema.mbt:3-5,43-67`](../../binding/schema.mbt#L3-L67)). |
| Diagnostics | `FATHOM-PARSE-###`, `FATHOM-LEX-###`, `FATHOM-FORMAT-###`, `FATHOM-SCHEMA-###`, `FATHOM-LSP-###`; messages may mention selected dialect, codes never use dialect brand | Code mapping is a closed enum `match`; no `DORIS-*` alias. Keep `dialect`, `statement_id`, byte span and expected class stable. |
| JS/Wasm exports | `fathom_parse_v1`, `fathom_format_v1`, `fathom_capabilities_v1`, `fathom_profile_v1`; primitive UTF-8 JSON/Bytes only | `foreign_library` + `#export_name` on non-generic wrappers; export names must be C-symbol-compatible and unique within producing package ([MoonBit package config](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html#package-type)). |
| VS Code | extension/package `fathom-sql-language-client`; language id `fathom-sql` or neutral `sql` with dialect setting; config keys `fathom.sql.dialect`, `fathom.sql.serverPath`; command `fathom.restartLanguageServer` | Current extension hardcodes `doris` in displayName, activation, settings and command ([本地 `vscode/package.json:1-58`](../../vscode/package.json#L1-L58)); change language-configuration, tests, server downloader and docs together. |
| JetBrains/Web/docs | artifact/display names `fathom-sql`; docs use “Doris dialect”/“Flink dialect” only when describing syntax, never as product name | Update README, API docs, schemas, release workflow artifact names and examples in one migration; no compatibility aliases per milestone requirement. |
| Release metadata | SemVer module/package version; corpus manifest records SQL release and Fathom parser schema separately; release notes state supported Flink profile matrix | Mooncakes publication requires module name username prefix and SemVer ([MoonBit module version](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html#version)); native assets remain OS/arch named and checksummed. |

## Development Tools and CI Gates

| Tool | Purpose | Notes |
|------|---------|-------|
| `moon check` / `moon build` | Compile core and adapters per backend | Run native, JS and linear Wasm for shared code; use exact compiler recorded in `moon.mod`. Keep Wasm GC optional until runtime matrix is verified. |
| Corpus extraction script | Fetch, verify, extract, hash, and manifest Flink release docs/source | Must accept an explicit release identifier; fail on `dev`/`stable`/unrecognized URL; never use network at parser runtime. |
| Differential fixture harness | Compare Fathom acceptance/recovery/round-trip with source evidence | Flink parser source/Calcite is an oracle, not a runtime dependency; record `accepted_by_docs`, `accepted_by_source`, `fathom_status`, and conflicts independently. |
| Cross-backend parity harness | Verify serialized schema, diagnostics, source bytes and formatter output | All dialects and profiles must exercise Native/JS/Wasm wrappers; compare JSON/Bytes, not internal MoonBit ADTs. |
| Package/release checks | Audit neutral names and public artifacts | Fail if public source contains `doris-sql`, `doris-lsp`, `doris.*.v1`, or `DORIS-*` outside historical corpus provenance; allow `Dialect::Doris` and docs references to Doris dialect. |

## Installation

```bash
# Pin and verify the existing MoonBit toolchain; do not silently upgrade.
moon version

# Check shared implementation for each promised target.
moon check --target native
moon check --target js
moon check --target wasm

# Build only after the release/profile and corpus manifest are selected.
moon build --target native --release
moon build --target js --release
moon build --target wasm --release

# Optional edge tooling, never a parser-core dependency.
# moon add moonbitlang/x@0.4.47
```

No npm, Java, Flink cluster, Doris FE, Calcite runtime, ANTLR runtime or sqlglot installation belongs in the parser core. npm is only for generated JS consumers and editor extensions; Apache Flink/Calcite are source/corpus authorities, not production dependencies.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Closed `Dialect` enum + `match` | `pub(open) trait Dialect` | Use an open trait only for genuinely user-implemented extension boundaries such as Catalog/host/analyzer provider; never for the finite built-in dialect route. |
| Closed enum | `extenum` | Use `extenum` only when third-party constructors are a product requirement; its wildcard requirement weakens compile-time route completeness. |
| Handwritten MoonBit parser | Apache Calcite JavaCC parser runtime | Use Calcite source as grammar/keyword oracle and version comparator; adopt runtime only if the product abandons MoonBit single-core and lossless CST constraints, which is out of scope. |
| Flink release docs + pinned source + matching Calcite | `flink-docs-stable`, `nightlies`, `dev` | Use moving docs for discovery only; never use them in reproducible fixture/gate inputs. |
| Flink 2.3.0 + matching Calcite 1.36.0 | Latest Calcite `main` | Use Calcite `main` only for exploratory future-syntax research; a Flink profile must use the Calcite version in its own POM. |
| Local MoonBit JSON/primitive adapter | `moonbitlang/x` JSON in parser core | Use `moonbitlang/x` at adapter edge after target-specific verification; keep lexer/CST/backend parity independent of experimental packages. |
| JS ESM + linear Wasm first | Wasm GC-only distribution | Use Wasm GC after a concrete browser/runtime matrix passes; it is not the first compatibility promise. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `pub(open) trait` as the dialect registry | Open implementations and non-exhaustive behavior can leave a route partially wired; it is the wrong semantic contract for exactly two built-in dialects | `pub(all) enum Dialect` + centralized exhaustive route functions; separate open traits only for extension interfaces |
| `#` comments in Flink lexer by copying Doris | Local Doris lexer explicitly treats `#` as comment, while Calcite lexical definitions do not; accepting it creates Flink false positives and corrupts recovery boundaries | Flink-specific comment table (`--`, `//`, block as release evidence supports), with `#` unknown/error fixture unless release parser proves pre-processing |
| Blindly accepting all X/B/U prefixes | Calcite 1.36 template visibly defines X binary and U& Unicode forms but not B bit-string token; generic SQL folklore is not Flink release evidence | Implement X and U& from pinned Calcite; gate B by Flink release fixture and report unsupported otherwise |
| `doris-sql`, `doris-lsp`, `doris.*.v1`, `DORIS-*` public names after cutover | Leaves product identity and serialized contracts dialect-specific; contradicts neutral naming and no-backward-compatibility milestone | `fathom-sql`, `fathom-lsp`, `fathom.*.v1`, `FATHOM-*`; keep `doris` only as a dialect value/provenance label |
| `dev`/`stable` URLs or unpinned `release-*` branch as corpus | Documentation and source move; the same fixture can silently change | Apache source archive + `.asc`/`.sha512` + release tag/commit + per-file hash |
| Flink/Doris FE or Calcite Java at runtime | Breaks offline Native/JS/Wasm SDK, adds deployment coupling and violates parser/analyzer separation | Pure MoonBit parser; use official source/docs only for corpus/differential evidence |
| Parser generator/runtime fork beside the handwritten parser | Creates a second grammar/CST/error-recovery behavior and loses the single source of truth | Extend existing source-backed lexer/CST/parser with dialect tables and productions |

## Stack Patterns by Variant

**If the selected dialect is Doris:**
- Use `Dialect::Doris`, an explicit Doris release profile (`2.1`, `3.x`, `4.x`), Doris keyword classification and existing Doris feature gates.
- Preserve byte-level parity as a non-negotiable gate; do not change Doris lexer semantics merely to make Flink implementation convenient.

**If the selected dialect is Flink:**
- Use `Dialect::Flink` plus exact Flink release profile (`flink-2.3.0`, `flink-2.1.3`, or `flink-1.20.5`), per-release keyword table and matching Calcite version metadata.
- Route window TVF, `MATCH_RECOGNIZE`, Flink DDL/DML and Flink lexical forms explicitly; never fall through to Doris productions.

**If the code is a public host adapter:**
- Expose only primitive UTF-8/Bytes serialized results with `dialect` and schema version; perform UTF-16 conversion in LSP/host code.
- Use MoonBit `foreign_library`/`#export_name` wrappers and JS ESM; do not export internal CST enums/structs.

**If adding a user extension:**
- Use `pub(open) trait` for Catalog/analyzer/host capabilities, with explicit coherent implementation and primitive API boundaries.
- Do not add a third built-in dialect through a trait implementation without first adding its `Dialect` enum constructor, release/profile metadata, keyword/grammar tables and every route match.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `fathom/sql@0.1.x` (v2 development line) | MoonBit `0.1.20260724` / v0.10.5 policy | Keep `moon.mod`/`moon.pkg` new DSL; official docs currently render v0.10.6, but compiler pin must remain explicit and upgrade separately. |
| `Flink 2.3.0` | `Calcite 1.36.0` | Read from Flink 2.3 `flink-table/pom.xml`; parser grammar must use this Calcite template, not latest `main`. |
| `Flink 1.20.5` | `Calcite 1.32.0` | Read from Flink 1.20 `flink-table/pom.xml`; keep 1.20 docs path under `/docs/dev/table/sql/`. |
| `Flink 2.1.3` | Its release POM's Calcite version | Add only after extracting exact source/POM; do not infer from 2.3 or 1.20. |
| `fathom.parse.v1` | Native, JS ESM, linear Wasm, LSP 3.17 | All targets use the same primitive field names/byte spans; host-specific UTF-16 is not part of parser schema. |
| `fathom-sql` / `fathom-lsp` | VS Code/JetBrains clients using `fathom.*` settings | Release artifacts must include SHA-256 manifest and exact schema/capability metadata; no old binary aliases. |

## Sources

### Local project evidence

- [`moon.mod:1-8`](../../moon.mod#L1-L8) — current root module `fathom/doris-sql`, exact recorded MoonBit toolchain, native preferred target; migration source of truth.
- [`lexer/lexer.mbt:208-247,277-307`](../../lexer/lexer.mbt#L208-L307) — Doris comment, string, double-quote/backtick behavior.
- [`token/token.mbt:3-247`](../../token/token.mbt#L3-L247) — closed Doris profile/feature enum, metadata validation and profile gates to preserve under `Dialect::Doris`.
- [`token/token.mbt:297-464`](../../token/token.mbt#L297-L464) — current global `classification_rows`; must be split per dialect.
- [`api/api.mbt:1-120`](../../api/api.mbt#L1-L120) — explicit profile/mode and primitive parse boundary.
- [`binding/schema.mbt:1-105`](../../binding/schema.mbt#L1-L105) — current `doris.*` schema/error naming to replace with `fathom.*`.
- [`doris-sql/moon.pkg:1-13`](../../doris-sql/moon.pkg#L1-L13) — current executable package/import path.
- [`vscode/package.json:1-58`](../../vscode/package.json#L1-L58) — current extension’s Doris-specific public names requiring clean cutover.

### Apache Flink (official)

- [Flink Downloads](https://flink.apache.org/downloads/) — current stable release list, source archives, `.asc` and `.sha512` links; 2.3.0, 2.1.3 and 1.20.5 pins.
- [Flink 2.3 SQL overview](https://nightlies.apache.org/flink/flink-docs-release-2.3/docs/sql/reference/overview/) — release-version SQL surface, statement families, Calcite relationship and reserved-keyword list.
- [Flink 2.3 CREATE statements](https://nightlies.apache.org/flink/flink-docs-release-2.3/docs/sql/reference/ddl/create/) — physical/metadata/computed columns, watermark, constraints, distribution, properties, newer materialized/model DDL.
- [Flink 2.3 Window TVF](https://nightlies.apache.org/flink/flink-docs-release-2.3/docs/sql/reference/queries/window-tvf/) — TUMBLE/HOP/CUMULATE/SESSION syntax and `TABLE`/`DESCRIPTOR`/interval/named-argument forms.
- [Flink 1.20 SQL overview](https://nightlies.apache.org/flink/flink-docs-release-1.20/docs/dev/table/sql/overview/) — versioned older SQL surface and reserved-keyword evidence.
- [Flink 2.3 table POM](https://raw.githubusercontent.com/apache/flink/release-2.3/flink-table/pom.xml) — Calcite 1.36.0 property and parser module list.
- [Flink 1.20 table POM](https://raw.githubusercontent.com/apache/flink/release-1.20/flink-table/pom.xml) — Calcite 1.32.0 property and parser module list.
- [Flink 2.3 `config.fmpp`](https://raw.githubusercontent.com/apache/flink/release-2.3/flink-table/flink-sql-parser/src/main/codegen/config.fmpp) — confirms Flink extends Calcite’s packaged `Parser.jj` through codegen configuration.
- [Flink 2.3 `parserImpls.ftl`](https://raw.githubusercontent.com/apache/flink/release-2.3/flink-table/flink-sql-parser/src/main/codegen/includes/parserImpls.ftl) — Flink-specific DDL/utility/parser productions.

### Apache Calcite (official)

- [Calcite SQL language reference](https://calcite.apache.org/docs/reference.html) — baseline BNF for query, DML, window and table expressions.
- [Calcite 1.36 Parser template](https://github.com/apache/calcite/blob/calcite-1.36.0/core/src/main/codegen/templates/Parser.jj) — pinned keyword/non-reserved-keyword generation, `MATCH_RECOGNIZE`, X binary literal, U& Unicode literal, lexical states and comment rules.
- [Calcite current Parser template](https://github.com/apache/calcite/blob/main/core/src/main/codegen/templates/Parser.jj) — discovery only; not a release oracle for Flink profiles.

### MoonBit (official)

- [MoonBit language fundamentals](https://docs.moonbitlang.com/en/latest/language/fundamentals.html#enum) — closed enum constructors, `match`, `extenum`, and wildcard requirement for open enums.
- [MoonBit methods and traits](https://docs.moonbitlang.com/en/latest/language/methods.html#trait-system) — `pub(open) trait`, implementations and method constraints.
- [MoonBit package visibility/trait implementations](https://docs.moonbitlang.com/en/latest/language/packages.html#traits) — private/abstract/readonly/open trait semantics and coherence restrictions.
- [MoonBit module configuration](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html) — module naming, SemVer/Mooncakes username requirement, dependencies, preferred target and include/exclude.
- [MoonBit package configuration](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html) — package-derived names, `pkgtype`, foreign libraries, `#export_name`, JS ESM/CJS exports.
- [MoonBit FFI](https://docs.moonbitlang.com/en/latest/language/ffi.html) — backend set and stable primitive ABI guidance.

---
*Stack research for: Fathom v2.0 Multi-Dialect (Flink SQL + neutral naming)*  
*Researched: 2026-08-06*
