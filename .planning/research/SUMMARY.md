# Project Research Summary

**Project:** Fathom v2.0 Multi-Dialect（Flink SQL 与 Neutral Naming）
**Domain:** MoonBit 无损 CST 多方言 SQL Parser SDK、编辑器与跨后端工具链
**Researched:** 2026-08-06
**Confidence:** HIGH（边界与工程风险）；MEDIUM-HIGH（Flink 具体版本语法需按锁定 release 再验证）

## Executive Summary

Fathom v2.0 是一个以无损 CST 为核心的 SQL 前端 SDK：同一份 MoonBit 实现需要同时服务 Doris 与 Flink，输出 Native CLI/LSP、JavaScript/linear-Wasm facade，并保留注释、空白、换行、未知节点、错误节点和 byte span，使 no-op replay、诊断、格式化和编辑器增量体验可信。研究一致建议保留 handwritten lexer + recursive-descent + Pratt + bounded recovery；新增低层 `dialect` policy 层，用闭合 `Dialect` enum（`Doris`、`Flink`）和穷尽 `match` 路由，而不是把两个方言压入一个全局 keyword 表或用开放 trait 猜测方言。共享 source/token/CST/恢复/表达式机制，方言分别拥有 lexical policy、keyword classification、statement/clause grammar、feature gates、formatter/completion policy。

Flink 支持面必须由发布版文档、对应 `flink-sql-parser` 源码及其锁定的 Calcite 版本三层证据共同定义。当前推荐主 profile 为 Flink 2.3.0，回归 profile 为 2.1.3 与 1.20.5；Flink 2.3 对应 Calcite 1.36.0，Flink 1.20 对应 Calcite 1.32.0。先锁 release/source/Calcite/config 和 corpus provenance，再实现 Flink lexical 与 grammar，尤其是 CREATE TABLE 的 metadata/computed columns、WATERMARK、connector options、Window TVF 与 `MATCH_RECOGNIZE`。产品身份则必须 clean cutover 到 `fathom/sql`、`fathom-sql`、`fathom-lsp`、`fathom.*.v1`、`FATHOM-*`；Doris 只作为显式方言值、profile 和 provenance 保留，不提供旧公共 alias。

最大风险不是遗漏单个 Flink production，而是跨层不一致：全局分类表会让方言互相污染，Flink 分支会破坏 Doris recovery/CST/diagnostic parity，moving docs 或错误 Calcite 版本会使 corpus 漂移，命名半迁移会制造两套公共身份，CLI/LSP/Web/IDE 还可能静默选择错误方言。路线图必须把 dialect/context/schema/naming 与冻结的 Doris baseline 放在最前面，并把 byte-level Doris parity、版本化 Flink corpus、strict/editor recovery、跨 Native/JS/Wasm 结果一致性作为硬门禁。

## Key Findings

### Recommended Stack

Stack 研究的详细证据见 [STACK.md](./STACK.md)。核心结论如下：

**Core technologies:**
- **MoonBit（项目锁定 `moon 0.1.20260724`，遵循 v0.10.5 policy）**：单一实现编译 Native、JS 与 linear Wasm；CI/release 必须记录完整 `moon version`，不要因文档页面更新而无审查升级 compiler。
- **新式 `moon.mod`/`moon.pkg` DSL + `moonbitlang/core`**：使用非 deprecated 配置；core 是 parser 的唯一必需运行时依赖。`moonbitlang/x` 仅可在 LSP/binding 边缘评估，不得进入 lexer/CST。
- **Handwritten lexer + recursive descent + Pratt**：保留 source-backed byte spans、trivia、错误恢复和 incomplete SQL 控制；不引入 parser-generator runtime、Calcite Java runtime、ANTLR 或 sqlglot 作为生产核心。
- **闭合 `Dialect` enum + exhaustive `match`**：方言是有限产品集合，所有 lexer/keyword/grammar/formatter/diagnostic/completion/adapter route 都获得编译期遗漏检查；`pub(open) trait` 仅留给 Catalog、AnalyzerProvider、HostTransport 等真正开放的扩展边界。
- **Flink release/profile + matching Calcite pins**：主 profile `flink-2.3.0`；回归 profiles `flink-2.1.3`、`flink-1.20.5`。2.3 POM 锁定 Calcite 1.36.0，1.20 POM 锁定 1.32.0；2.1.3 的 Calcite 版本必须从其 release POM 提取，不能推断。
- **Primitive versioned wire schema**：`fathom.parse.v1`、`fathom.format.v1`、`fathom.error.v1`、`fathom.capabilities.v1`；通过 UTF-8/Bytes 传递 source/诊断/CST view，source bytes 只在 root 持有一次，不能跨 ABI 暴露 MoonBit 内部 ADT。
- **LSP 3.17 edge adapter 与 JS ESM/linear-Wasm facade**：UTF-16 只在 LSP/host 边界转换；Native `fathom-lsp`、CLI `fathom-sql`、Web/Monaco、VS Code/IntelliJ 都消费同一 API/schema。Wasm GC 首发只作可选评估，不作为首个兼容承诺。
- **Pinned corpus + CI parity**：下载 Flink source archive 时验证 `.asc`/`.sha512`，记录 release tag/commit、Calcite version/config、URL、heading、文件 hash 与 expected status；CI 使用离线 pinned artifact，不依赖网络、FE、Flink cluster 或数据库。

关键 lexer 约束也会影响 roadmap：Doris 当前接受 `#` comment、双引号/反引号 quoted token；Calcite baseline 使用 `--`/`//`/block comment，并定义 `X'...'` 与 `U&'...'`，不应依据 SQL folklore 自动接受 `B'...'`。Flink 需独立 fixture 锁定 `#`、双引号、backtick、X/U& literal 与 escape 行为。

### Expected Features

Features 研究以“能安全用于 CI、formatter、IDE”为 table stakes，而不是把 Flink planner/runtime 误包装成 parser 能力。

**Must have (table stakes):**
- **显式 `Dialect::Flink`、独立 keyword/lexical table 与 parser route**：禁止缺失 dialect 时静默落到 Doris；API、schema、CLI、LSP、Web、completion 都传递同一选择。
- **Flink 核心 SELECT/CTE/JOIN/聚合/集合/表达式/类型与 DDL/DML/utility**：覆盖 CREATE/ALTER/DROP、CATALOG/DATABASE/VIEW/FUNCTION、INSERT/UPDATE/DELETE、ANALYZE/SHOW/DESCRIBE/EXPLAIN 等日常入口。
- **Flink CREATE TABLE 专用 CST**：physical/metadata/computed columns、`WATERMARK`、`PRIMARY KEY NOT ENFORCED`、`PARTITIONED BY`、`DISTRIBUTED`、`WITH` options、`LIKE`/`AS`。
- **Window TVF**：`TUMBLE`、`HOP`、`CUMULATE`、`SESSION`，以及 `TABLE`、`DESCRIPTOR`、interval literal、`=>` named argument 和窗口产出列。
- **语法级 `MATCH_RECOGNIZE`**：保留 `PATTERN`、`DEFINE`、`MEASURES`、`AFTER MATCH SKIP`、pattern variable/quantifier；不宣称 planner/execution 等价。
- **lossless recoverable CST 与结构化 dialect-aware diagnostics**：strict/editor 双模式、稳定 `FATHOM-*` code、severity/span/statement id/profile，未知和错误材料可回放。
- **Flink-aware formatter 与 bounded syntax completion**：canonical format 与 lossless replay 分离；unsafe error/missing/skipped tree 由 formatter refusal，而不是部分输出。
- **Neutral CLI/LSP/Web/IDE 全链**：`fathom-sql parse|format|lsp --dialect ...`、`fathom-lsp`、JS/linear-Wasm facade、Monaco、VS Code 和 IntelliJ 复用同一中立 LSP/schema。
- **Doris parity + official Flink corpus + cross-backend parity**：Native/JS/Wasm 的序列化结果、诊断、span 与 round-trip 必须一致，Doris v1 既有行为不得因共享重构改变。

**Should have (competitive):**
- **端到端可追踪的显式 dialect/profile**：每个 parse result、diagnostic、format output、completion 和 LSP document 都能回答“按哪一方言/版本产生”。
- **source-backed dialect-specific diagnostics**：将 feature/grammar class、来源和稳定 code 关联，区分“文档支持”“parser 可接受”“需 catalog/planner”。
- **损失无关的公共 CST 能力**：在 connector option 拼写、comments、pattern 和未知节点上仍可安全 range edit/no-op replay，优于会改变 casing/quoting 的 AST regeneration。
- **可审计 Flink corpus/parity 报告**：按 release、feature、positive/negative/recovery、known limitation 输出覆盖，不以 generic parse success 宣称 Flink engine compatibility。
- **后续 P2**：catalog-backed completion/hover、semantic tokens/symbols、扩展 release matrix；仅在基础 schema/span parity 稳定后加入。

**Defer (v2+):**
- **完整 Flink planner/catalog/type/execution 语义验证**：需要 connectors、catalog、stream/batch 与运行时，不符合独立 Native/JS/Wasm parser 边界。
- **无基准支持的 incremental CST/tree reuse**：只有在测量 whole-document reparse 成为真实 editor 瓶颈后推进，并保持 incremental/full replay byte-identical。
- **第三方 dialect/plugin marketplace**：先稳定 Doris/Flink 的闭合 schema、keyword、diagnostic、跨后端合同。
- **隐式自动 dialect detection、formatter 默认 transpile/convert**：如未来需要，只能是显式 opt-in，并返回 ambiguity/unsupported diagnostics 和 edits。

### Architecture Approach

Architecture 研究建议在 `source` 与 `token` 之间加入无副作用 `dialect/` 层。`DialectContext`（dialect、profile、exact release、feature metadata）由 API 创建并贯穿 token stream、parser、formatter、completion、binding 与每个 LSP document；不存在全局可变方言状态。共享 scanner、source span、trivia、immutable CST、document segmentation、Pratt、progress guard、recovery budget 和 layout；Doris/Flink 各自提供 lexical policy、classification rows、statement/clause grammar、sync sets、feature gates 与 formatting policy。Analyzer 仍是 side-channel，只读取 syntax + source + context + optional Catalog，不改变 parser validity。

**Major components:**
1. **`source/` + `syntax/`** — 只拥有原始 bytes、half-open byte spans、line index 与方言中立 immutable CST；错误、missing、skipped、trivia 都是 source-backed leaf/node。
2. **`dialect/`** — 唯一的 `Dialect`、profile/context、keyword classification、feature capability authority；Doris/Flink rows 分离，开放 trait 不承担内置方言 registry。
3. **`token/` + `lexer/`** — 共享 token/trivia/span/storage 与扫描进度保证，由 `DorisLexPolicy`/`FlinkLexPolicy` 决定 comment、quote、literal、operator、identifier 行为。
4. **`parser/`** — 共享 document/recovery/Pratt/query skeleton，`parse_segment` 先 `match context.dialect` 再调用 `DorisGrammar` 或 `FlinkGrammar`；Window TVF、`MATCH_RECOGNIZE` 等子语言有独立 rule/CST/sync set。
5. **`api/` + `binding/`** — 校验 `DialectOptions`，返回带 dialect/profile/schema 的 primitive result；binding 是中立 wire schema 唯一生产者，JS/Wasm/native 只导出稳定 bytes wrapper。
6. **`formatter/` + `completion/` + `analyzer/`** — 分别复用 context 分类表做安全格式化、bounded syntax candidates 与语义 side-channel；禁止直接 import 某个 dialect grammar 或重新维护 keyword 表。
7. **`lsp/`、`fathom-sql` 与宿主** — LSP 3.17 JSON-RPC、CLI IO/exit code、VS Code/IntelliJ/Web/Monaco 均为薄适配层；UTF-16 只在 LSP 边界完成，document 保存 dialect/profile/revision 以拒绝 stale response。
8. **`corpus/` + parity harness** — Doris/Flink 按 profile/release 分目录，manifest 保留 provenance/status/hash；比较 serialized schema、diagnostics、CST views、formatter output 与 lossless bytes。

### Critical Pitfalls

1. **全局 Doris classification union**：会把 reserved/contextual/identifier 行为跨方言泄漏。Phase 9 必须参数化所有分类 API、拆出 dialect-local rows 和来源 metadata；Phase 10 加冲突词双向 keyword/identifier/quote/recovery fixtures。
2. **Flink grammar 污染 Doris 或混用 `DorisFeature`**：Window TVF/MATCH_RECOGNIZE 可能被普通 Pratt 或 Doris recovery 吞掉。先建立单一 router，再用独立 Flink productions/sync sets；Doris/Flink-only 输入必须有双向 negative gate。
3. **Doris CST/诊断/接受性隐性回归**：不能只测 compile 或 `valid`。Phase 9 冻结 v1 baseline，Phase 11 对 source bytes、CST spans/text、diagnostic code/span/statement id、strict/editor、formatter、completion 和 profile gates 做完整 diff。
4. **Neutral naming 半迁移**：`fathom.*`、`FATHOM-*`、binary/export、LSP source、VS Code/IntelliJ artifact 若只改一部分，会产生两套 schema authority。Phase 9 建立 rename inventory/allowlist，Phase 13 做真实 artifact/install smoke；只允许 `Dialect::Doris` 和 provenance 中保留 Doris。
5. **Flink corpus/dev/nightly/Calcite 漂移**：moving `stable`/`dev`/nightly 或错误 Calcite `main` 会让 golden 不可复现。必须 lock release archive、commit/tag、Calcite version/config、hash 和分类；将 docs support、parser acceptance、catalog requirement 分开记录。
6. **CLI/LSP/Editor 静默错误选择方言**：profile 不能替代 dialect，languageId 不能独自决定 parser。实现 document-level `DialectSelection` 与明确 precedence；缺失、未知、冲突全部结构化拒绝，response 绑定 version+dialect 以防旧结果覆盖新文档。

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 9: Dialect Boundary, Neutral Naming & Doris Baseline
**Rationale:** 所有 Flink 工作依赖显式 context、独立分类、schema 和 route；命名迁移不能留到最后，否则新增 Flink API 会继续传播 Doris identity。先冻结 Doris v1 行为，避免重构后用新测试掩盖回归。
**Delivers:** `dialect/` package；`Dialect::Doris|Flink` 与 `DialectContext`；DialectOptions/selection precedence；Doris profile/feature 迁入 dialect namespace；dialect-local classification API；`fathom/sql` imports、`fathom.*.v1`、`FATHOM-*`、`fathom-sql`/`fathom-lsp`、binding exports、LSP/VS Code/IntelliJ/Web naming matrix；immutable Doris 2.1/3.x/4.x baseline。
**Addresses:** 显式 dialect、isolated keyword route、中立 CLI/LSP/schema、Doris parity foundation。
**Avoids:** 全局 keyword 污染、DorisFeature 冒充 Dialect、命名双身份、缺失 dialect 默认为 Doris。
**Hard gate:** 每个公共入口都传 dialect/profile；旧 alias 删除而非兼容；Doris valid/invalid/recovery/CST/diagnostics/formatter/completion 的 frozen baseline 可比较。

### Phase 10: Flink Release/Calcite Contract & Lexical Core
**Rationale:** grammar 不能先于语料和 lexical oracle；Flink 的 quote/comment/literal/conformance 行为不是 Doris 的小补丁。先从官方 release 建立 profile/manifest，再实现可审计的 token/classification。
**Delivers:** `flink-2.3.0` 主 profile、`2.1.3`/`1.20.5` 回归 profile；source archive SHA-512/PGP、commit/tag、Calcite pin/config lock；docs/source/Calcite 三层 provenance；Flink keyword rows、reserved/future-reserved/contextual inventory；`FlinkLexPolicy` 与 X/U&/quote/comment/identifier/operator 规则及负例。
**Addresses:** Flink lexer/keywords table stakes、corpus auditability、Doris/Flink conflict matrix。
**Uses:** MoonBit shared scanner、source-backed token/CST、官方 Flink Downloads/SQL docs、Flink POM、Calcite `Parser.jj`。
**Avoids:** `#` comment 误继承、B literal folklore、stable/nightly/dev 漂移、把 docs keyword list 当永久 oracle。
**Hard gate:** unknown profile/unsupported lexical input 显式拒绝或生成 error CST；每个 keyword 有 release/source/introduction metadata；相同 source 在两方言下的差异有 snapshot 和负例。

### Phase 11: Flink Grammar Core & Recovery
**Rationale:** lexical contract 稳定后，才能安全加入有真实结构差异的语法；共享 parser skeleton 必须通过单一 route 使用，而不是复制 149KB Doris parser 或散落 `if dialect == Flink`。
**Delivers:** explicit `parse_segment` dialect dispatch；Flink SELECT/CTE/JOIN/aggregate/query、DDL/DML/utility；CREATE TABLE physical/metadata/computed columns、WATERMARK、constraints/options；Window TVF；syntax-level `MATCH_RECOGNIZE`；Flink-specific sync/recovery/feature diagnostics/CST nodes。
**Addresses:** Flink core parser、CREATE TABLE、Window TVF、MATCH_RECOGNIZE、strict/editor recovery、lossless CST table stakes。
**Implements:** shared query/Pratt/recovery mechanics + `FlinkGrammar`/Flink sublanguage modules。
**Avoids:** Flink-only syntax 在 Doris mode valid、普通 function call 吞 TABLE/DESCRIPTOR/PATTERN、error recovery 跨 statement 吞 token、把 Calcite experimental semantic 当 execution support。
**Hard gate:** strict/editor 对同一 input 维持一致 primitive shape；recovery 有 bounded progress；Flink unsupported/known limitation 有明确 `FATHOM-*` diagnostics；Phase 9 Doris baseline 不变。

### Phase 12: Cross-Dialect Corpus, Doris Parity & Coverage Gates
**Rationale:** 新 grammar 必须用 release-pinned corpus 和 frozen Doris oracle 验证，而不是以通过几个 positive example 结束；此阶段将 Phase 10 的 lock/manifest 变成可持续发布门禁。
**Delivers:** `corpus/doris/{2.1,3.x,4.x}` 与 `corpus/flink/{2.3.0,2.1.3,1.20.5}`；positive/negative/recovery/parse-only/requires-catalog/requires-streaming/known-limitation 分类；docs/source/Calcite conflict records；cross-dialect acceptance/rejection、keyword inventory、CST/diagnostic/format snapshots 和 coverage report。
**Addresses:** Doris parity、官方 Flink corpus、版本/feature introduction metadata、MATCH_RECOGNIZE subset negative cases。
**Avoids:** generic SQL success 被宣传为 engine compatibility、网络抓取进入 CI/runtime、snapshot 批量更新掩盖 regression、不可解释的 docs/parser source conflict。
**Hard gate:** 每 fixture 有 release、Calcite version/config、URL、commit/tag、heading、retrieval date、hash、expected status；Doris bytes/CST/spans/diagnostics/formatter/completion 与 baseline 持续为零差异或有批准变更。

### Phase 13: Formatter/Completion, CLI-LSP & Cross-Backend/Editor Packaging
**Rationale:** parser/API/schema 稳定后再扩展宿主，才能让所有消费者共享同一 dialect-aware diagnostics，而不把 adapter 临时绑到 Doris profile。此阶段也是 clean-cutover 是否真实完成的运行时验证。
**Delivers:** Flink formatter policy（unsafe tree refusal）、bounded syntax completion、dialect-aware analyzer side-channel；`fathom-sql parse|format|lsp`、`fathom-lsp` LSP 3.17；`fathom_parse_v1`/format/capability JS/linear-Wasm/native primitive wrappers；VS Code/IntelliJ/Web/Monaco neutral naming、dialect settings、document revision/stale-response handling；Native/JS/Wasm byte-level parity artifacts and release checks。
**Addresses:** formatter/completion、CLI/LSP/Web/IDE table stakes，neutral naming differentiator，cross-target parity。
**Uses:** shared `api` and FATHOM schema；LSP UTF-16 adapter；MoonBit `foreign_library`/`#export_name`；existing refusal-first formatter and LSP4IJ architecture。
**Avoids:** formatter 在 error tree 上部分输出、languageId 偷换 dialect、全局 ServerState.profile、旧 export/schema/source/asset 残留、不同 backend 产生不同 span/diagnostic。
**Hard gate:** 每个 host 明确传 dialect/profile；缺失/冲突/未知拒绝；同一 fixture 的 Native/JS/linear-Wasm serialized result 与 replay bytes 一致；真实 VS Code/IntelliJ/Monaco/CLI smoke 与 forbidden/allowlist naming gate 通过。

### Phase Ordering Rationale

- **Boundary first:** keyword classification、grammar route、wire schema、CLI/LSP/Web/IDE 都依赖 DialectContext；若先写 Flink grammar，会把旧 Doris coupling 带入新代码。
- **Corpus lock before grammar acceptance:** Flink docs、Flink parser source 和 Calcite config/version 决定“支持”含义；Phase 10 先锁 oracle，Phase 12 完成可持续 manifest/parity gate。
- **Shared mechanics, separate policy:** source/token/CST/Pratt/recovery/layout 只实现一次；真正不同的 lexical rule、statement/clause、sync set、formatter/completion policy 放进各 dialect module，维持 Doris parity。
- **Adapters last:** 诊断/schema 必须先稳定；LSP/CLI/Web/IDE 只消费 API/binding，不绕过 parser 调用 Flink/Doris grammar。
- **Parity is a release constraint, not cleanup:** Phase 9 freeze、Phase 12 corpus/parity、Phase 13 cross-backend parity 共同防止“编译通过”被误当作完成。

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 10:** 需要按 Flink 2.3.0/2.1.3/1.20.5 提取 source archive、确认 2.1.3 Calcite pin，并冻结 `Lex`/`SqlParser.Config`、quote/case/comment/literal 行为；现有 FEATURES/PITFALLS 使用部分 2.0/1.20 页面，不能直接替代发布线证据。
- **Phase 11:** Window TVF 与 `MATCH_RECOGNIZE` 是复杂嵌套子语言；需要逐 production 对照对应 release `flink-sql-parser`/Calcite tests，明确 Flink subset 与 unsupported diagnostics。
- **Phase 12:** 需要设计可审计 corpus 抽取、manifest/hash/diff、docs-vs-parser conflict 和 semantic prerequisite 分类；不能把自动抓取的示例直接当 valid SQL。
- **Phase 13:** 需要验证 MoonBit JS/linear-Wasm ABI、JSON codec Unicode/size/malformed behavior、LSP UTF-16/revision/initialization precedence，以及真实 VS Code/IntelliJ/Web artifact smoke。

Phases with standard patterns (skip research-phase where local contract is sufficient):
- **Phase 9 的共享 CST/Source ownership 与 enum+match 路由**：MoonBit 官方 enum/trait/module/package 文档与现有 v1 边界已充分说明；仍需工程迁移盘点，但无需重新选择技术路线。
- **Phase 12 的 Doris baseline comparison**：v1 已有 manifest、strict/editor、formatter refusal、source-root parity 形状；重点是冻结和扩大 oracle，而非探索新 parser 方案。
- **Phase 13 的 LSP4IJ 复用**：JetBrains 已明确不维护第二 parser/transport；实现应延续现有 LSP boundary，不引入新协议框架。

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | MoonBit backend/module/package/FFI/test 文档、Flink Downloads/POM、Calcite template 与本地 v1 约束交叉核验；Wasm GC 最终部署矩阵仍待验证。 |
| Features | MEDIUM-HIGH | Flink overview/CREATE/Window TVF、Calcite `MATCH_RECOGNIZE` 与现有 SDK 能力支持 table stakes；具体 release support 需从 2.3.0 等 pinned docs/source 再确认。 |
| Architecture | HIGH | 现有 source/token/lexer/parser/api/binding/LSP/extension 边界已直接核验；Flink node/prod 的细节留给 grammar phase。 |
| Pitfalls | HIGH | 主要风险都有本地调用点、命名耦合、现有 parity contract 或 Apache protocol/grammar 证据；回归严重度仍需执行阶段的 baseline diff 量化。 |

**Overall confidence:** HIGH for sequencing, boundaries and non-negotiable constraints; MEDIUM-HIGH for exact Flink grammar coverage.

### Gaps to Address

- **Flink 2.1.3 的 Calcite 版本与配置尚未在研究中给出精确值**：Phase 10 必须读取对应 release POM/source，写入 lockfile；在此之前不得把 2.1.3 作为完整 grammar oracle。
- **研究文件部分引用 release-2.0/1.20 文档，而 stack 推荐 2.3.0 主 profile**：规划时应将 2.0 页面只作为背景/负例线索，所有 release gate 改用 2.3.0、2.1.3、1.20.5 对应路径和 commit。
- **Flink lexical configuration（双引号、`#`、`//`、X/U&/B、case/quoting）需要 executable fixture 验证**：不能由 Calcite template 单独推断 Flink SQL Client 的最终行为。
- **`MATCH_RECOGNIZE` 的 Flink subset 与语义边界**：parser 只承诺语法 CST；需要建立 accepted/known-limitation/requires-planner 分类，不做 runtime planner 等价声明。
- **MoonBit primitive ABI 与 JSON codec 的跨 target 细节**：在 Phase 13 做小规模 Native/JS/linear-Wasm smoke，验证 Unicode、byte span、malformed input、输出稳定性后再锁公共 export。
- **CLI/LSP dialect precedence 与 extension mapping 的产品决策**：建议 request/document configuration > server initialization > languageId 映射；冲突拒绝，且每 Document 保存 context/revision；需在真实宿主确认 UX。
- **Doris v1 corpus 中部分 provenance 标记为 unavailable-offline**：不得伪造 FE differential PASS；缺口应在 parity 报告显式列出，并区分 byte baseline 与外部 oracle。
- **是否在 v2.0 承诺 Wasm GC、catalog-backed completion、incremental parsing**：默认不承诺，分别以 runtime matrix、用户反馈/性能 benchmark 为进入条件。

## Sources

### Primary (HIGH confidence)

**Local project evidence:**
- [`STACK.md`](./STACK.md)、[`FEATURES.md`](./FEATURES.md)、[`ARCHITECTURE.md`](./ARCHITECTURE.md)、[`PITFALLS.md`](./PITFALLS.md) — 本 SUMMARY 的四份完整研究输入。
- `.planning/PROJECT.md:5-11,43-50,72-81` — 无损 CST、MoonBit 单实现、parser/analyzer 边界、v2 Dialect/Flink/neutral naming 目标。
- `token/token.mbt`、`lexer/lexer.mbt`、`parser/parser.mbt`、`api/api.mbt` — 现有 Doris profile/classification、scanner、单方言 route、CST/recovery/API evidence。
- `binding/schema.mbt`、`binding/exports.mbt`、`lsp/handlers.mbt`、`doris-sql/*`、`vscode/package.json`、`jetbrains/*`、`web/*` — Doris 命名及 schema/CLI/LSP/Web/IDE coupling inventory。
- `corpus/manifest.tsv`、`corpus/tools/check_keywords.py` — v1 corpus provenance 与 keyword gate。

**MoonBit official:**
- [MoonBit enum/match](https://docs.moonbitlang.com/en/latest/language/fundamentals.html#enum) — closed enum constructors与穷尽 match。
- [MoonBit traits/packages](https://docs.moonbitlang.com/en/latest/language/packages.html#traits) — `pub(open) trait` 的开放实现语义。
- [Module configuration](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html) — module naming、SemVer、preferred target与依赖。
- [Package configuration/exports](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html) — `pkgtype`、foreign library、`#export_name`、JS exports。
- [MoonBit FFI](https://docs.moonbitlang.com/en/latest/language/ffi.html) — backend/ABI/host portability边界。
- [MoonBit tests](https://docs.moonbitlang.com/en/latest/language/tests.html) 与 [coverage](https://docs.moonbitlang.com/en/latest/toolchain/moon/coverage.html) — snapshot/coverage能力（本任务未运行测试）。

**Apache Flink/Calcite/protocol:**
- [Flink Downloads](https://flink.apache.org/downloads/) — 2.3.0、2.1.3、1.20.5 release/source archive、签名与 hash。
- [Flink 2.3 SQL overview](https://nightlies.apache.org/flink/flink-docs-release-2.3/docs/sql/reference/overview/) — release SQL surface、statement families、reserved keywords。
- [Flink 2.3 CREATE](https://nightlies.apache.org/flink/flink-docs-release-2.3/docs/sql/reference/ddl/create/) — CREATE TABLE/DDL 专用结构。
- [Flink 2.3 Window TVF](https://nightlies.apache.org/flink/flink-docs-release-2.3/docs/sql/reference/queries/window-tvf/) — TUMBLE/HOP/CUMULATE/SESSION、TABLE/DESCRIPTOR/named args。
- [Flink 2.3 table POM](https://raw.githubusercontent.com/apache/flink/release-2.3/flink-table/pom.xml) — Calcite 1.36.0 pin。
- [Flink 1.20 table POM](https://raw.githubusercontent.com/apache/flink/release-1.20/flink-table/pom.xml) — Calcite 1.32.0 pin。
- [Flink 2.3 `config.fmpp`](https://raw.githubusercontent.com/apache/flink/release-2.3/flink-table/flink-sql-parser/src/main/codegen/config.fmpp) 与 [`parserImpls.ftl`](https://raw.githubusercontent.com/apache/flink/release-2.3/flink-table/flink-sql-parser/src/main/codegen/includes/parserImpls.ftl) — Flink 对 Calcite parser 的定制边界。
- [Calcite 1.36 `Parser.jj`](https://github.com/apache/calcite/blob/calcite-1.36.0/core/src/main/codegen/templates/Parser.jj) — lexical/literal/MATCH_RECOGNIZE grammar oracle。
- [Calcite `SqlParser.Config`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/sql/parser/SqlParser.Config.html) 与 [Calcite `Lex`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/config/Lex.html) — conformance、quoting、casing配置。
- [LSP 3.17 specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/) — JSON-RPC lifecycle、position encoding、diagnostic/edit contracts。

### Secondary (MEDIUM confidence)

- [SQLGlot README](https://raw.githubusercontent.com/tobymao/sqlglot/main/README.md) 与 [dialect registry](https://github.com/tobymao/sqlglot/tree/main/sqlglot/dialects) — 显式 dialect 参数、lenient parser、AST/comment fidelity 限制和方言模块组织参考，不是 Flink engine oracle。
- [SQLFluff Flink dialect](https://raw.githubusercontent.com/sqlfluff/sqlfluff/main/src/sqlfluff/dialects/dialect_flink.py) 与 [keyword table](https://raw.githubusercontent.com/sqlfluff/sqlfluff/main/src/sqlfluff/dialects/dialect_flink_keywords.py) — lexer/connector/watermark/computed/metadata/distribution decomposition 参考。
- [Tree-sitter official parser model](https://tree-sitter.github.io/tree-sitter/using-parsers/1-getting-started.html) — concrete tree/editable parser 的架构比较；不作为 Fathom runtime 依赖。

### Tertiary (LOW confidence / validation required)

- `release-2.0`/`release-1.20` Flink docs 中过时或版本差异页面 — 仅用于发现 feature/负例线索；release gate 必须迁移到锁定版本。
- [指定 `tree-sitter/tree-sitter-sql` URL](https://github.com/tree-sitter/tree-sitter-sql) — Architecture 研究记录直接读取为 404，不据此作 grammar 事实。
- Calcite current `main` parser template — 仅 discovery，不得替代 Flink profile 对应的 Calcite release。

---
*Research completed: 2026-08-06*
*Ready for roadmap: yes*
