# Phase 9: Dialect Boundary and Neutral Naming - Research

**Researched:** 2026-08-06
**Domain:** MoonBit 多方言 SQL parser 边界（dialect 抽象层、显式选择契约、产品命名中立化、Doris baseline 冻结）
**Confidence:** HIGH（仓库耦合点与迁移方向全部由本地文件直接核验）；MEDIUM（LSP/宿主层的 dialect 传输细节与 Flink profile 表面需宿主 smoke 或 Phase 10 再锁）

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** 方言选择优先级为 **文档级显式配置 > workspace/session 显式默认 > languageId 显式映射**；来自同一优先级来源的冲突选择直接报结构化配置错误，绝不静默猜测、绝不自动检测。**Reversibility:** one-way — 这是 DIALECT-01 公共契约的一部分，发布后变更需 schema 迁移。
- **D-02:** 文档与 workspace 都没有显式选择时，返回配置错误；不允许隐式 languageId 兜底。languageId 只有在用户显式配置了映射时才参与解析。**Reversibility:** costly — 影响所有宿主首次打开 `.sql` 文件的默认行为。
- **D-03:** 切换文档 dialect/profile 后立即按新 context 重解析当前 revision，刷新 diagnostics/format/completion，并丢弃旧 context 的异步结果（document revision/stale-response 防护）。**Reversibility:** reversible。
- **D-04:** 命名 gate 豁免历史归档：`milestones/v1.0-*`、`milestones/v1.0-research/`、已归档的 ROADMAP/REQUIREMENTS 历史段保持原样（记录历史事实），gate 只覆盖现行源码、配置、CI、扩展和文档。**Reversibility:** reversible。
- **D-05:** 保留方言类型名：`DorisProfile`、`DorisFeature`、`ValidatedProfileContext` 等 Doris 方言自身类型名原样保留；新增 `Dialect`、`DialectContext`、`FlinkProfile`。产品层只改包名、export、schema、错误码、二进制、LSP server identity、扩展和文档标题。**Reversibility:** costly — 类型名是代码内公共 API，全量泛化需迁移所有调用点。
- **D-06:** 产品层 clean cutover：`fathom/doris-sql` → `fathom/sql`（模块/import）、`doris-sql` → `fathom-sql`（CLI）、`doris-lsp` → `fathom-lsp`、`doris_parse_v1` → `fathom_parse_v1` 等 export、`doris.*.v1` → `fathom.*.v1`、`DORIS-*` → `FATHOM-*`、LSP `serverInfo`/`source`、VS Code/IntelliJ/Web 配置键与包名、文档标题。不保留旧名 alias。**Reversibility:** one-way — 无向后兼容别名是明确产品决策。
- **D-07:** baseline 全量冻结完整 public 行为：CST 形状/span、diagnostics code/span/statement_id、strict/editor 双模式、formatter 输出、completion、CLI exit code、LSP 协议输出、wire schema 输出，全部字节级/形状级比较。**Reversibility:** one-way — 冻结的 baseline 是后续 Phase 12 PARITY-01 的对比基准。
- **D-08:** baseline 采用**快照 diff 门禁**：利用现有 corpus + 快照机制建立 baseline 快照目录（CST/diagnostics/formatter/completion/CLI/LSP 输出），Phase 9 每步改造后跑 diff；字节级一致或经批准并记录的变更才通过。**Reversibility:** reversible。
- **D-09:** wire schema 统一中立 `fathom.parse.v1`/`fathom.format.v1`/`fathom.error.v1`/`fathom.capabilities.v1`；dialect、profile、exact release 作为 result/diagnostic 的 metadata 字段。**Reversibility:** one-way — 这是公共 wire contract，发布后变更需 schema 迁移。
- **D-10:** 诊断 code 统一 `FATHOM-PARSE-NNN`/`FATHOM-FORMAT-NNN`/`FATHOM-SCHEMA-NNN` 等，dialect 不编码进 code 前缀；方言信息通过 diagnostics 的 metadata 字段暴露。**Reversibility:** one-way — 诊断 code 是稳定公共契约。
- **D-11:** CLI 采用 `fathom-sql parse|format|lsp --dialect doris|flink --profile <id>`，dialect 与 profile 分开且必选；缺失或未知值返回 exit 2 和结构化错误，无默认方言。**Reversibility:** costly — CLI 参数是脚本化接口，改变形态需更新所有调用脚本和文档。

### Claude's Discretion
（未出现 "you decide"；所有灰区均由用户明确选择。）

### Deferred Ideas (OUT OF SCOPE)
- Flink grammar/工具链细节 → Phase 10/11/13
- Flink corpus 提取与 Calcite pin → Phase 10/12
- 自动方言检测（即使 opt-in）→ 未来阶段，不在 v2.0 默认范围
- 显式跨方言转换（transpile）→ CONVERT-FUTURE-01
</user_constraints>

## Summary

Phase 9 把已交付的单方言 Doris SDK 升级为显式多方言架构，并完成产品层 clean cutover。仓库现状证实了三个核心事实：(1) `DorisProfile`/`DorisFeature` 与唯一的 `classification_rows` 全在 `token/token.mbt`（`token/token.mbt:3-6,133-141,307`），lexer 把 profile 复制到每个 token（`lexer/lexer.mbt:134-155,250`），parser 通过 `TokenStream.profile` 与 `RecoveryState.profile_context` 消费（`parser/parser.mbt:121,1365`），因此 dialect 层的正确切口是「把 profile/keyword/dispatch 变成显式 dialect policy」，而不是复制 parser；(2) 产品命名横跨 16 个 `moon.pkg` import、binding export/schema、LSP source/serverInfo、CLI、VS Code/Web/IntelliJ 与 3 个 CI workflow，需要文件级迁移矩阵（本文件第 6 节给出）而不是全局字符串替换；(3) `DORIS-*` 诊断码共 4 个 namespace（PARSE-001..007 / FORMAT-001..007 / SCHEMA-001..006 / LSP-001），全部映射到 `FATHOM-*`（D-10）。

**Primary recommendation:** 按「先冻结 baseline → 再建 dialect 层 → 再迁移命名 → 最后接宿主」的顺序执行。D-08 baseline 用 MoonBit 官方 `@test.T::snapshot`（`__snapshot__/` 目录 + `moon test --update` 生成、`moon test` 字节级失败）建立冻结快照门禁；dialect 层新增 `dialect/` package 承载 `Dialect`/`DialectContext`/`KeywordEntry` 与 `doris_classification_rows`/`flink_classification_rows`，所有分类查询签名加 context 参数；命名迁移以本文件第 6 节映射表为唯一清单，NAME-04 gate 参照 `corpus/tools/check_keywords.py` 的 stdlib 校验模式实现为 CI 脚本。本阶段不引入任何新外部依赖——核心仍只用 `moonbitlang/core`。

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DIALECT-01 | Consumer can explicitly select `doris` or `flink` and its profile through the public API, CLI, LSP, JS/Wasm facade, Web, VS Code, and IntelliJ; missing, unknown, or conflicting selection returns a structured configuration error with no automatic dialect detection or generic fallback. | §3 explicit-selection 契约（D-01/D-02/D-11 优先级 + 错误面设计）；§4.2 `validate_dialect_profile` 泛化；§6 迁移表逐边界加 dialect 维度 |
| DIALECT-02 | Parser uses independent Doris and Flink lexical/keyword policies for reserved, non-reserved, and contextual words, quoted identifiers, comments, literals, operators, and feature metadata; no global union of dialect keyword rows can affect identifier acceptance. | §4.1 dialect 层设计：`classification_rows` → `doris_classification_rows`/`flink_classification_rows`（共享 `KeywordEntry`），所有分类查询签名加 `DialectContext` 参数 |
| DIALECT-03 | Shared source, token, CST, Pratt, and recovery mechanics route statement and clause grammar explicitly by dialect; Doris-only syntax is rejected in Flink mode and Flink-only syntax is rejected in Doris mode with localized diagnostics rather than try-all parsing. | §4.3 `parse_segment` 显式 `match context.dialect` 路由（`parser/parser.mbt:3327`）；Phase 9 内 Flink 路由为显式 not-implemented 路径（见 Open Question 1），Doris 路径字节不变（baseline 门禁） |
| DIALECT-04 | Parse, format, completion, LSP, and serialized results carry dialect, profile, and exact-release metadata; strict/editor mode, byte spans, statement identity, and structured `FATHOM-*` diagnostics remain stable across the public boundary. | §3 metadata 字段设计（`ParseResult.dialect`、schema `fathom.parse.v1` 增 `dialect` 字段）；§5 `FATHOM-*` 全量 code 映射表 |
| NAME-01 | Consumer-facing module imports, Native binaries, and public exports complete a clean cutover to `fathom/sql`, `fathom-sql`, and `fathom-lsp`; no old public aliases remain. | §6 迁移表（moon.mod、16 个 moon.pkg import、`doris-sql/` → `fathom-sql/`、`doris_*_v1` → `fathom_*_v1`）；D-06 无 alias |
| NAME-02 | Machine-readable wire contracts use `fathom.parse.v1`, `fathom.format.v1`, `fathom.error.v1`, and `fathom.capabilities.v1`, with `FATHOM-*` diagnostics and explicit dialect/profile fields. | §6.3 schema/error 迁移表（`binding/schema.mbt:3-5,43-49,107-146`）；§5 code 映射 |
| NAME-03 | VS Code, IntelliJ, Web/npm, CI/release assets, configuration keys, LSP server identity, README, and project documentation use neutral product naming; Doris remains only as a dialect/profile/corpus/provenance semantic identifier. | §6.4-6.7 宿主迁移表（vscode/package.json、jetbrains Kotlin、web、CI）；§7.4 allowlist 设计 |
| NAME-04 | CI includes a naming inventory/allowlist gate that rejects product-level remnants of `doris-sql`, `doris-lsp`, `doris.*`, and `DORIS-*`; the allowlist is limited to Doris dialect semantics and provenance. | §7 命名 gate 设计（forbidden/allowlist 精确正则 + 文件作用域 + D-04 豁免路径） |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Dialect 身份（`Dialect` enum、`DialectContext`） | `dialect/`（新增低层 policy package） | `api/` | 无运行时副作用的纯 policy 层；parser/API/LSP/宿主只消费 context，不持有 dialect 判断逻辑 |
| 关键字分类（reserved/non-reserved/contextual） | `dialect/`（`doris_classification_rows`/`flink_classification_rows`） | `token/`（lookup 代理） | 分类是方言权威数据；token 保留 `classification_of(context, raw)` 代理避免扩散三份表 |
| Feature gate（DorisFeature/FlinkFeature） | `dialect/`（Doris 模块内保留 `DorisFeature`） | `parser/`（consumes `supports`） | D-14/D-15 两层分离：分类管 identifier 接受，feature gate 管 production 版本 |
| 词法策略（quote/comment/literal/operator） | `lexer/`（共享 scanner + `DorisLexPolicy`/`FlinkLexPolicy`） | `dialect/`（policy 数据源） | scanner/span/进度保证共享；策略按 context 选择（DIALECT-02 词法独立性） |
| Statement/clause 路由 | `parser/`（`parse_segment` 显式 `match context.dialect`） | `dialect/`（router 常量） | 单一 router，禁止散落 `if dialect == Flink`（Pitfall 2） |
| 显式选择校验（missing/unknown/conflict → 结构化错误） | `api/`（`ParseError::UnknownDialect` 等） | `binding/`（`validate_dialect_profile`、schema codes） | 所有宿主共享同一错误面；CLI/LSP/Web 只做传输 |
| Result/diagnostic 方言 metadata | `api/`（`ParseResult.dialect` 等字段） | `binding/`（`fathom.parse.v1` schema 序列化） | 单一 envelope 生产者；JS/Wasm/native 输出一致 |
| LSP document 级 context 与 stale-response 防护 | `lsp/`（`Document` 增 dialect/profile；`ServerState` 拆默认+映射） | `api/`（context 校验） | D-01/D-02/D-03 由 LSP 状态机实现 |
| 产品命名 cutover 与 gate | 仓库级（迁移映射表 + CI gate） | CI（`scripts/check_naming.py` 作业） | 无单一 registry，必须由清单驱动（Pitfall 4） |
| Doris baseline 冻结 | `parity/`（扩展为 baseline snapshot 包） | CI（`moon test` 无 `--update` 门禁） | D-07/D-08：冻结输出在重构前生成 |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| MoonBit toolchain (`moon`, `moonc`) | `moon 0.1.20260724 (5f1406a 2026-07-24)` / `moonc v0.10.5+5e7afb0c0`（本机核验 `moon --version`；CI 记录 `MOONBIT_INSTALL_VERSION: "latest"` 并打日志） | 模块/包重命名、`#export_name`、多后端构建 | 唯一实现语言；本阶段无新技术选择（research flags 明确） |
| `moonbitlang/core` | 既有锁定版本（`_build/packages.json`） | String/Bytes/JSON/utf8/buffer/debug | 项目约束：core 是 parser 唯一必需运行时依赖，Phase 9 不新增任何包 |
| 新 `moon.mod`/`moon.pkg` DSL | `rr_moon_mod,rr_moon_pkg` feature flags 已启用（`moon version` 输出） | 模块名、package kind、link exports | `moon.mod.json`/`moon.pkg.json` 自 v0.10.4 deprecated，仓库已用新 DSL |

**关键 MoonBit 机制（本阶段直接依赖，官方文档核验）：**
- 模块名可含字母、数字、`_`、`-`、`/`，因此 `fathom/sql` 是合法模块名（`name = "user/example"` 语法，[VERIFIED: https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html — "The module name can contain letters, numbers, `_`, `-`, and `/`."]）。
- **包名不可配置，由目录名决定**：重命名 `doris-sql/` 目录为 `fathom-sql/` 即重命名包与可执行输出（[VERIFIED: https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html — "The package name is not configurable; it is determined by the directory name of the package."]；仓库内 `doris-sql/moon.pkg:2-3` 注释已 probe-verified「包目录名 doris-sql/ 构建出 doris-sql.exe」，release workflow 也按 `_build/native/release/build/lsp/lsp.exe` 复制 [VERIFIED: .github/workflows/doris-native-release.yml:93-107]）。
- `#export_name` 为 public、non-generic 函数在 Wasm/JS/C 输出中赋稳定符号名；export 名必须是合法 C 符号标识符且包内唯一；**新 export 优先用 `#export_name` 而不是后端 `exports` link 配置**（[VERIFIED: https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html — "#export_name assigns a stable symbol name to a public, non-generic function in generated Wasm, JavaScript, or C output… Prefer `#export_name` over backend-specific `exports` link configuration for new exports."]）。`binding/moon.pkg` 当前同时用了 `#export_name` 与 js/wasm `exports` 列表 [VERIFIED: binding/moon.pkg:14-28]，重命名 export 时两者必须同步更新（Pitfall：export 半迁移）。
- `link` 选项对 native backend 不生效；`pkgtype(kind: "foreign_library")` 取代 legacy `options(link: true)`（[VERIFIED: package.html — "Currently, `link` does not work for the native backend."]）。native 后端当前不支持把 foreign_library 作为 library artifact 导出（binding 的 native 侧只通过 JS/Wasm facade 消费）。
- 快照测试：`@test.T::snapshot(filename=...)` 写入该包 `__snapshot__/` 目录；`moon test --update` 插入/更新；`moon test` 在内容不一致时失败（[VERIFIED: https://docs.moonbitlang.com/en/latest/language/tests.html — "This will create a file under `__snapshot__` of that package with the given filename"、"All of which can be inserted or updated automatically using `moon test --update`."]）。这是 D-08 baseline 门禁的官方机制。
- 测试 import：`import { ... } for "test"` / `for "wbtest"`（package.html），黑盒 `_test.mbt` 需要 `pub(all)` 类型（仓库 03-01 教训，`doris-sql/args.mbt:20-22` 注释）。

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Python 3 stdlib（本机 3.9.23） | — | `scripts/check_naming.py`（NAME-04 gate）、既有 `corpus/tools/check_keywords.py` 模式 | CI gate 脚本；stdlib only，零新增依赖 |
| `moonbitlang/core/json` | 既有 | binding schema 序列化、LSP JSON-RPC | 已在使用（binding/moon.pkg、lsp/moon.pkg），不加替代 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| 新增 `dialect/` package | 把 `Dialect`/`KeywordEntry` 塞进 `token/` | token 只该持有 token/span 数据结构；dialect 是 policy 权威，独立包可被 analyzer/formatter 无环引用（ARCHITECTURE.md 结论） |
| 手写 `scripts/check_naming.py` | ripgrep/专门 lint 工具 | 与 `check_keywords.py` 同模式、stdlib only、零 CI 依赖；正则清单显式可审 |
| `@test.T::snapshot` baseline | 外部 golden 文件 + 自定义 diff 脚本 | 官方快照机制自带 `__snapshot__` 管理、`--update` 工作流、字节级失败语义；外部脚本仍可叠加形状 diff 报告 |

**Installation:**
```bash
# 本阶段不安装任何新外部包。既有依赖已锁定于 _build/packages.json 与 node_modules。
```

**Version verification:** 本阶段零新增 npm/pypi/crates 依赖；运行环境核验见 §Environment Availability（moon 0.1.20260724 / node v25.2.0 / python 3.9.23 均已本机探测）。

## Package Legitimacy Audit

> 本阶段不安装任何外部包（约束：核心 parser 只用 `moonbitlang/core`；命名 gate 脚本为 stdlib Python）。因此无需运行 package-legitimacy seam；下表为显式确认。

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| （无新增包） | — | — | — | — | — | N/A — 零外部依赖 |

**Packages removed due to [SLOP] verdict:** none（无候选包）
**Packages flagged as suspicious [SUS]:** none（无候选包）

## Architecture Patterns

### System Architecture Diagram

```text
Hosts (thin adapters, all pass explicit {dialect, profile})
  fathom-sql CLI      fathom-lsp       VS Code      IntelliJ      Web/Monaco
  --dialect --profile init+didChange   settings     settings      selects
        └───────────────┴───────────────┴─────────────┴───────────────┘
                                    │ fathom.parse.v1 / fathom.error.v1
┌───────────────────────────────────▼───────────────────────────────────┐
│ api/  ParseOptions(dialect_id, profile_id, mode_id) → ParseResult     │
│       ParseError::UnknownDialect/UnknownProfile/… ; dialect metadata   │
└───────┬───────────────────────────────┬───────────────────────────────┘
        │                               │
┌───────▼────────┐             ┌────────▼────────┐
│ parser/        │             │ formatter/      │
│ document+      │             │ shared layout + │
│ recovery core  │             │ refusal         │
└───────┬────────┘             └────────┬────────┘
        │  parse_segment: match context.dialect
┌───────▼───────────────────────────────▼───────────────────────────────┐
│ dialect/  (新增 policy authority — 无 parser/api 依赖)                │
│  Dialect(Doris|Flink) · DialectContext(dialect,profile_id,exact_…)   │
│  KeywordEntry · doris_classification_rows / flink_classification_rows│
│  DorisProfile/DorisFeature 迁入 doris.mbt · FlinkProfile 预留 flink.mbt│
└───────┬───────────────────────────────────────────────────────────────┘
        │ context
┌───────▼────────┐     ┌────────▼────────┐
│ token/         │     │ lexer/          │
│ Token.context  │◄────│ lex(source,     │
│ TokenStream    │     │  DialectContext)│
└────────────────┘     └─────────────────┘
        │ context（贯穿 completion/formatter/binding 查询）
┌────────────────────────────────────────────────────────────────────────┐
│ source/ + syntax/ — 方言中立（不动）；baseline 冻结在重构前            │
└────────────────────────────────────────────────────────────────────────┘

LSP 文档级 context:
  ServerState { default_selection?, language_mapping, docs }
  Document { uri, version, text, dialect, profile }   ← 新增字段（D-03）
  didChange/didOpen → parse_with_dialect(document) → publishDiagnostics
  dialect 切换 → 立即按新 context 重解析当前 revision；version 守卫丢弃旧结果
```

### Recommended Project Structure（新增/变更部分）

```text
dialect/                     # 新增：统一 DialectContext 与两套 policy
├── dialect.mbt              # Dialect enum、DialectContext、FeatureId
├── classification.mbt       # KeywordEntry、ClassificationKind、lookup API
├── doris.mbt                # DorisProfile/DorisFeature/doris_classification_rows（自 token/ 迁入）
└── flink.mbt                # FlinkProfile（Phase 9 预留空/未定义值）、flink rows 占位（Phase 10 填充）
token/                       # Token.context / TokenStream.context；classification_of(context, raw)
lexer/                       # lex(source, context)；scanner 共享
parser/                      # parse_segment 显式 dispatch；RecoveryState.context
api/                         # ParseOptions 加 dialect 维度；ParseError::UnknownDialect；ParseResult.dialect
binding/                     # fathom_*_v1 exports；fathom.*.v1 schema；validate_dialect_profile
lsp/                         # ServerState 默认+映射；Document.dialect/profile；FATHOM-LSP-*
fathom-sql/                  # 由 doris-sql/ 改名（包名=目录名 → 二进制名）
parity/                      # 扩展 baseline snapshot 包（__snapshot__/）
scripts/                     # 新增 check_naming.py（NAME-04 gate）
corpus/doris-*/              # 保持原名（provenance，D-04 允许）；keywords.tsv/manifest.tsv 保持
```

### Pattern 1: Dialect 层（policy authority）与 `DialectContext`

**What:** 新增 `dialect/` 低层 package，作为 `Dialect`、`DialectContext`、关键字分类与 feature metadata 的唯一权威；`source`/`syntax` 不依赖它，`token`/`lexer`/`parser`/`api`/`completion`/`formatter` 向下消费 context。
**When to use:** 任何需要「按方言选择词法/语法/格式化策略」的调用点；禁止在 parser 内散落 `if dialect == Flink`。
**Example（设计骨架，来源: .planning/research/ARCHITECTURE.md「Layer placement: Dialect hierarchy」+ 现状 `token/token.mbt:271-287,450`）:**

```moonbit
// dialect/dialect.mbt — 闭合 enum（STACK.md 结论：闭合 enum + 穷尽 match）
pub enum Dialect { Doris; Flink }

pub struct DialectContext {
  pub dialect : Dialect
  pub profile_id : String
  pub exact_release : String
  pub feature_introduction : String
}

// dialect/classification.mbt — 共享结构 + 按 dialect 路由的查找
pub struct KeywordEntry {
  pub word : Bytes
  pub classification : ClassificationKind   // 复用 token.mbt 的 Reserved/NonReserved/Contextual（D-05 保留）
  pub introduced_profile : String
  pub source : String
}
// 现状分类行是 let classification_rows : Array[ClassificationEntry] = [ … ]（token/token.mbt:307）
// 拆分后：let doris_classification_rows : Array[KeywordEntry] = [ … ]（内容逐行迁移）
//         let flink_classification_rows : Array[KeywordEntry] = []  // Phase 10 填充
pub fn classification_of(context : DialectContext, raw : Bytes) -> KeywordEntry?
// 按 context.dialect 选择 doris/flink rows，复用 token_bytes_equal_ci 的 ASCII case-insensitive 算法
```

**关键迁移约束（D-05）：** `DorisProfile`（`token/token.mbt:3-6`）、`DorisFeature`（`token/token.mbt:133-141`）、`ClassificationKind`（`token/token.mbt:271-274`）、`ClassificationEntry`（`token/token.mbt:281-287`）**保留原名**；`Token.profile : DorisProfile`（`token/token.mbt:513`）与 `TokenStream.profile`（`token/token.mbt:535`）改为 `context : DialectContext`（ARCHITECTURE.md 推荐「不可变的 `Dialect` + profile id」形态，具体字段形态由 planner 定）。`classification_of(raw)`/`is_clause_keyword(raw)`/`is_reserved_word(raw)`/`is_unquoted_identifier(raw)`（`token/token.mbt:450,471,485,492`）签名加 `context` 参数——Pitfall 1 要求「禁止保留无参数公共 `is_reserved_word`」。

### Pattern 2: 显式选择契约（DialectSelection）与结构化错误面

**What:** 每个公共边界（API/CLI/LSP/JS-Wasm/Web/VS Code/IntelliJ）都要求显式 `dialect` + `profile`；缺失、未知、冲突返回结构化配置错误，绝不静默 fallback。
**When to use:** 所有宿主入口；这是 DIALECT-01 的公共契约。

- **API（`api/api.mbt:42-62`）**：`ParseOptions` 加 `dialect` 维度；`ParseOptions::new(profile_id, mode_id)`（`api/api.mbt:64`）扩展为 `ParseOptions::new(dialect_id, profile_id, mode_id)`；`ParseError` 增 `UnknownDialect(dialect_id~ : String)`；`UnknownProfile` 消息从 `"unsupported Doris profile"`（`binding/schema.mbt` 侧）改为中性 `"unsupported \{dialect} profile"`。冲突选择（同一优先级来源）新增结构化错误变体（如 `ConflictingSelection`，具体形态见 Open Question 3）。
- **binding/schema（`binding/schema.mbt:29-35`）**：`validate_profile(profile)` → `validate_dialect_profile(dialect : String, profile : String)`；`SchemaError` 增 `UnknownDialect`；code 增 `FATHOM-SCHEMA-00N`（见 §5 表）。
- **CLI（D-11，`doris-sql/args.mbt:8-19`）**：`fathom-sql parse|format|lsp --dialect doris|flink --profile <id>`；`--dialect` 与 `--profile` 均必选；`MissingDialect`/`UnknownDialect` 进 `UsageError` → exit 2。
- **LSP（D-01/D-02）**：initialize 的 `initializationOptions` 现只读 `profile`（`lsp/handlers.mbt:144-150`）→ 改为 `{ dialect, profile }`（workspace/session 显式默认）；`didChangeConfiguration` 提供文档级显式配置；languageId 显式映射（用户配置）为第三优先级。三者都缺失 → `initialize` 返回结构化错误（现行为 `-32602 "initialize requires initializationOptions.profile"`，`lsp/handlers.mbt:304-309`）；同源冲突 → 结构化错误。
- **JS/Wasm（`binding/exports.mbt:25-26`）**：`doris_parse_v1(raw, profile, mode)` → `fathom_parse_v1(raw, dialect, profile, mode)`（参数顺序见 Open Question 2）。
- **Web/VS Code/IntelliJ**：见 §6.4-6.6 逐宿主字段。

### Pattern 3: `parse_segment` 显式方言路由

**What:** `parse_segment`（`parser/parser.mbt:3327`）当前按首词硬编码 Doris starters（`SELECT/WITH/INSERT/UPDATE/DELETE/MERGE/CREATE`，`parser/parser.mbt:3336-3376`）。Phase 9 在函数签名加 `context : DialectContext`，入口先 `match context.dialect` 再分派。
**When to use:** 语句级路由唯一入口；`WITH` lookahead（`with_prefix_verb`）保持共享但每个 dialect 的 grammar 各自解释；未知 starter 继续走 `unsupported_statement`（`parser/parser.mbt:3158-3169`，DORIS-PARSE-007 → FATHOM-PARSE-007）。
**Example（来源: ARCHITECTURE.md「parse_segment routing」）：**

```moonbit
fn parse_segment(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
  statement_id : UInt,
  state : RecoveryState,
  context : DialectContext,
) -> @syntax.SyntaxNode {
  match context.dialect {
    Dialect::Doris => parse_doris_segment(stream, start_index, end_index, statement_id, state, context)
    Dialect::Flink => parse_flink_segment(stream, start_index, end_index, statement_id, state, context)
  }
}
```

**Phase 9 的 Flink 路由边界（见 Open Question 1）：** Phase 9 不实现 Flink grammar（Phase 11）。`parse_flink_segment` 在 Phase 9 必须是**显式 not-implemented 路径**——对任何输入返回结构化诊断（如 `FATHOM-PARSE-00N` "flink grammar is not yet implemented in this release"），绝不回退 Doris。这样 DIALECT-03 的「Doris-only syntax 在 Flink mode 被拒绝」在 Phase 9 就成立（Flink mode 拒绝一切），且无 stub 式静默成功。Doris 路径保持 v1 字节行为，由 baseline 门禁证明。

## Diagnostic Code Mapping (D-10: DORIS-* → FATHOM-*)

> 仓库现状全量 inventory（grep 统计 + 定义点核验）。D-10 规则：dialect 不编码进 code 前缀；方言信息走 diagnostics 的 metadata 字段。

| Old Code | New Code | 定义点（现状） | 语义 |
|----------|----------|----------------|------|
| `DORIS-PARSE-001` | `FATHOM-PARSE-001` | `parser/parser.mbt:3149` | trailing tokens（finish_statement 内） |
| `DORIS-PARSE-002` | `FATHOM-PARSE-002` | `parser/parser.mbt:1333` 等 133 处 | expected X（标识符/子句/属性等） |
| `DORIS-PARSE-003` | `FATHOM-PARSE-003` | `parser/parser.mbt:3468-3476`（parse_with_limits_context 内） | invalid source encoding / unterminated lexical material |
| `DORIS-PARSE-004` | `FATHOM-PARSE-004` | `parser/parser.mbt:189` | parser resource limit reached（单一 resource diagnostic） |
| `DORIS-PARSE-006` | `FATHOM-PARSE-006` | `token/token.mbt:144-196`（`DorisFeature::metadata`） | feature unavailable in selected released profile |
| `DORIS-PARSE-007` | `FATHOM-PARSE-007` | `parser/parser.mbt:3166` | unsupported statement in the selected profile |
| `DORIS-FORMAT-001` | `FATHOM-FORMAT-001` | `formatter/format.mbt:131` | refusal（error/missing/skipped 树） |
| `DORIS-FORMAT-002` | `FATHOM-FORMAT-002` | `binding/exports.mbt:47` | unsupported keyword case |
| `DORIS-FORMAT-003` | `FATHOM-FORMAT-003` | `binding/exports.mbt:51` | unsupported comma style |
| `DORIS-FORMAT-004` | `FATHOM-FORMAT-004` | `binding/exports.mbt:55` | unsupported newline style |
| `DORIS-FORMAT-005` | `FATHOM-FORMAT-005` | `binding/schema.mbt:144` | invalid indent |
| `DORIS-FORMAT-006` | `FATHOM-FORMAT-006` | `binding/schema.mbt:145` | invalid line width |
| `DORIS-FORMAT-007` | `FATHOM-FORMAT-007` | `binding/schema.mbt:146` | formatter received invalid syntax tree |
| `DORIS-SCHEMA-001` | `FATHOM-SCHEMA-001` | `binding/schema.mbt:45` | unsupported schema version |
| `DORIS-SCHEMA-002` | `FATHOM-SCHEMA-002` | `binding/schema.mbt:46` | unsupported source transport |
| `DORIS-SCHEMA-003` | `FATHOM-SCHEMA-003` | `binding/schema.mbt:47` + `:109` | unsupported profile（+ UnknownDialect 新增映射） |
| `DORIS-SCHEMA-004` | `FATHOM-SCHEMA-004` | `binding/schema.mbt:48` + `:110` | unsupported parse mode |
| `DORIS-SCHEMA-005` | `FATHOM-SCHEMA-005` | `binding/schema.mbt:111` | profile metadata mismatch |
| `DORIS-SCHEMA-006` | `FATHOM-SCHEMA-006` | `binding/schema.mbt:112` | unsupported feature introduction |
| `DORIS-LSP-001` | `FATHOM-LSP-001` | `lsp/handlers.mbt:84` | document could not be parsed（LSP 适配层 fallback） |

**注意：** `DORIS-PARSE-005` 在仓库中无使用（grep 无匹配），保持空缺，不要新建。诊断 message 中 `"unsupported Doris profile"`（`binding/schema.mbt:63` 附近 schema_error_message、`binding/schema.mbt:117` parse_error_json、`lsp/handlers.mbt:309`）改为中性措辞（如 `"unsupported profile for dialect doris"`），dialect 由 metadata/字段表达。

## Migration Mapping Table（NAME-01/02/03 核心清单）

> 本节是命名迁移的**唯一清单**（D-06 clean cutover，无 alias）。逐文件 old → new；「保留」行是 D-04/D-05 允许保留的 Doris 方言语义/来源标识。所有行均有 `[VERIFIED: 文件:行]` 引用与逐字引用。

### 6.1 MoonBit 模块/包/import（NAME-01）

| # | 文件 | Old | New | 引用与逐字 |
|---|------|-----|-----|-----------|
| 1 | `moon.mod` | `name = "fathom/doris-sql"` | `name = "fathom/sql"` | [VERIFIED: moon.mod:5 — `name = "fathom/doris-sql"`；版本 `0.1.0`（v2.0 是否 bump 见 Open Question 7）] |
| 2 | 全部 15 个 `moon.pkg` import 块（api/token/lexer/parser/syntax/source/printer/formatter/completion/analyzer/binding/lsp/doris-sql/parity/test + 根 moon.pkg） | `"fathom/doris-sql/<pkg>" @alias` | `"fathom/sql/<pkg>" @alias`（alias 不变） | [VERIFIED: api/moon.pkg:3-8 — `import { "fathom/doris-sql/source" @source, "fathom/doris-sql/token" @token, "fathom/doris-sql/parser" @parser, "fathom/doris-sql/syntax" @syntax, "fathom/doris-sql/formatter" @formatter }`；其余 14 个 moon.pkg 的 import 串均为 `fathom/doris-sql/...`（§前置 dump 全量核验）] |
| 3 | `doris-sql/` 目录（含 moon.pkg/main.mbt/args.mbt/run.mbt/ffi.mbt/cli_test.mbt） | 包名/二进制 `doris-sql` | `fathom-sql/` → 二进制 `fathom-sql.exe` | [VERIFIED: doris-sql/moon.pkg:2-3 — 「the package dir name doris-sql/ builds the binary doris-sql.exe (probe-verified on moon 0.1.20260724)」；官方文档「package name is not configurable; it is determined by the directory name」] |
| 4 | `lsp/moon.pkg` 内注释/路径引用 | `doris-sql` 字样 | `fathom-sql` | [VERIFIED: lsp/moon.pkg:1-11 import 块] |
| 5 | `parity/moon.pkg` | `"fathom/doris-sql/api" @api` 等 | `"fathom/sql/api"` 等 | [VERIFIED: parity/moon.pkg:3-6] |
| 6 | `test/moon.pkg` | 9 个 `"fathom/doris-sql/..."` import | `"fathom/sql/..."` | [VERIFIED: test/moon.pkg:2-10] |
| 7 | `README.md`/`README.zh-CN.md`/`docs/*.md`+`docs/zh-CN/*` | `fathom/doris-sql/api` 导入示例、`doris-sql/` CLI 引用 | `fathom/sql/api`、`fathom-sql` | [VERIFIED: README.md:35-39,49-51（import 示例）; docs/GETTING-STARTED.md:14,49,66; docs/API.md:5,11-12,27-28] |

### 6.2 核心代码：token / lexer / parser / api / completion / formatter

| # | 文件 | Old | New | 引用与逐字 |
|---|------|-----|-----|-----------|
| 8 | `token/token.mbt:513` | `pub profile : DorisProfile`（Token 字段） | `pub context : DialectContext`（或 `Dialect`+profile id，ARCHITECTURE.md 建议） | [VERIFIED: token/token.mbt:510-515 — `pub(all) struct Token { pub kind : TokenKind, pub span : @source.Span, pub profile : DorisProfile, pub diagnostic_code : String? }`] |
| 9 | `token/token.mbt:535` | `pub profile : DorisProfile`（TokenStream 字段） | `pub context : DialectContext` | [VERIFIED: token/token.mbt:533-538 — `pub(all) struct TokenStream { pub source : @source.SourceText, pub profile : DorisProfile, pub tokens : Array[Token], pub truncated_at : Int? }`] |
| 10 | `token/token.mbt:307` | `let classification_rows : Array[ClassificationEntry]` | 迁至 `dialect/doris.mbt`：`let doris_classification_rows : Array[KeywordEntry]`（内容逐行保留 word/classification/introduced_profile/source） | [VERIFIED: token/token.mbt:307 — `let classification_rows : Array[ClassificationEntry] = [`；`ClassificationEntry` 定义 token/token.mbt:281-287] |
| 11 | `token/token.mbt:450,471,485,492` | `classification_of(raw)` / `is_clause_keyword(raw)` / `is_reserved_word(raw)` / `is_unquoted_identifier(raw)` | 加 `context : DialectContext` 参数；实现路由到 `doris_classification_rows`/`flink_classification_rows` | [VERIFIED: token/token.mbt:450 — `pub fn classification_of(raw : Bytes) -> ClassificationEntry?`；:471 `pub fn is_clause_keyword(raw : Bytes) -> Bool`；:485 `pub fn is_reserved_word(raw : Bytes) -> Bool`；:492 `pub fn is_unquoted_identifier(raw : Bytes) -> Bool`] |
| 12 | `lexer/lexer.mbt:250,378` | `lex_with_limit(source, profile : @token.DorisProfile, max_tokens)` / `lex(source, profile)` | `lex_with_limit(source, context : @token.DialectContext, max_tokens)` / `lex(source, context)` | [VERIFIED: lexer/lexer.mbt:250 — `pub fn lex_with_limit(source : @source.SourceText, profile : @token.DorisProfile, max_tokens : Int) -> @token.TokenStream`；:378 `pub fn lex(source : @source.SourceText, profile : @token.DorisProfile) -> @token.TokenStream`] |
| 13 | `lexer/lexer.mbt:134-155` | `push_token(…, profile : @token.DorisProfile, …)` | profile 参数改 context | [VERIFIED: lexer/lexer.mbt:134-155 — push_token 签名含 `profile : @token.DorisProfile`；每个 token 复制 profile] |
| 14 | `parser/parser.mbt:3327` | `fn parse_segment(stream, start_index, end_index, statement_id, state)` 无 dialect | 加 `context : DialectContext`；`match context.dialect` 分派 | [VERIFIED: parser/parser.mbt:3327-3385 — Doris starters 硬编码于 3336-3376] |
| 15 | `parser/parser.mbt:3430-3434` | `parse_with_limits_context(source, context : @token.ValidatedProfileContext, mode, limits)` | `context : @token.DialectContext` | [VERIFIED: parser/parser.mbt:3430-3434] |
| 16 | `parser/parser.mbt:3531-3536,3548-3556` | `parse_with_limits(source, profile : @token.DorisProfile, …)` / `parse(source, profile, …)` | profile 参数改 context（或保留 Doris 便捷重载，见 Open Question 5） | [VERIFIED: parser/parser.mbt:3531-3536,3548-3556] |
| 17 | `parser/parser.mbt:118-124` | `RecoveryState.profile_context : @token.ValidatedProfileContext` | `RecoveryState.context : DialectContext` | [VERIFIED: parser/parser.mbt:118-124 — `struct RecoveryState { … profile_context : @token.ValidatedProfileContext … }`] |
| 18 | `parser/parser.mbt:1365` | `let profile = cursor.stream.profile` | `let context = cursor.stream.context` | [VERIFIED: parser/parser.mbt:1365 — `let profile = cursor.stream.profile`；`parse_select_core` 签名 1149-1152 也带 `profile : @token.DorisProfile`] |
| 19 | `parser/parser.mbt:189,1330,3149,3166` 等 | `DORIS-PARSE-001/002/003/004/006/007` | `FATHOM-PARSE-001/002/003/004/006/007`（见 §5 表） | [VERIFIED: 上表] |
| 20 | `api/api.mbt:42-45` | `ParseOptions { profile_context : @token.ValidatedProfileContext; mode; limits }` | 加 `dialect_context : @token.DialectContext`（字段名 planner 定） | [VERIFIED: api/api.mbt:42-45] |
| 21 | `api/api.mbt:64` | `ParseOptions::new(profile_id : String, mode_id : String)` | `ParseOptions::new(dialect_id : String, profile_id : String, mode_id : String)` | [VERIFIED: api/api.mbt:64] |
| 22 | `api/api.mbt:48-62` | `ParseError { UnknownProfile; UnknownMode; ProfileMetadataMismatch; UnsupportedFeatureIntroduction; InputTooLarge; InvalidLimit; InvalidSyntaxTree }` | 增 `UnknownDialect(dialect_id~ : String)`（及冲突变体，Open Question 3） | [VERIFIED: api/api.mbt:48-62] |
| 23 | `api/api.mbt:180-205` | `ParseResult { schema_version; source_transport; profile; exact_release; feature_introduction; mode; valid; recovered; source_bytes; source_byte_length; root; diagnostics }` | 增 `dialect : String` 字段；schema_version 改 `"fathom.parse.v1"` | [VERIFIED: api/api.mbt:180-205；:298 — `schema_version: "doris.parse.v1"`] |
| 24 | `api/api.mbt:327-337,418-433` | `parse_with_ids(raw, profile_id, mode_id)` / `format_with_ids(raw, profile_id, mode_id, …)` | 加 `dialect_id` 参数（顺序见 Open Question 2） | [VERIFIED: api/api.mbt:327-337,418-433] |
| 25 | `api/api.mbt:313-326,431-453` | `parse_with_metadata` / `format_with_metadata` | 加 dialect 维度 | [VERIFIED: api/api.mbt:313-326,431-453] |
| 26 | `completion/completion.mbt:131` | `complete(raw : Bytes, profile_id : String, cursor_byte : Int)` | `complete(raw, dialect_id, profile_id, cursor_byte)` | [VERIFIED: completion/completion.mbt:131] |
| 27 | `completion/completion.mbt:44-51,165` | `profile_allows(profile : @token.DorisProfile, …)`；`detail: "Doris syntax keyword"` | 改为按 context 路由 + dialect 参数；detail 中性化 `"SQL syntax keyword"` | [VERIFIED: completion/completion.mbt:44-51,165 — `detail: "Doris syntax keyword"`] |
| 28 | `formatter/case.mbt:5-11` | `rewrite_keyword(raw)` 调 `@token.classification_of(raw)` | 加 context：`rewrite_keyword(context, raw)`；`format(root, source, options)` 入口加 context（`formatter/format.mbt:6-9`） | [VERIFIED: formatter/case.mbt:5-11 — 「the classification table is the single keyword authority」；formatter/format.mbt:6-9 — `pub fn format(root, source, options) -> FormatResult`] |
| 29 | `formatter/format.mbt:131` | `code: "DORIS-FORMAT-001"` | `FATHOM-FORMAT-001` | [VERIFIED: formatter/format.mbt:127-137 — refusal_diagnostic] |
| 30 | `analyzer/analyzer.mbt`（侧通道） | 只导入 `fathom/doris-sql/syntax`（D-21 负向 gate） | import 改 `fathom/sql/syntax`；不新增 dialect 依赖（catalog 不得进 parser validity channel） | [VERIFIED: analyzer/moon.pkg:3 — `import { "fathom/doris-sql/syntax" @syntax }`] |

### 6.3 binding：export / schema / error（NAME-02）

| # | 文件 | Old | New | 引用与逐字 |
|---|------|-----|-----|-----------|
| 31 | `binding/exports.mbt:25-26` | `#export_name("doris_parse_v1")` / `pub fn doris_parse_v1(raw, profile, mode)` | `#export_name("fathom_parse_v1")` / `pub fn fathom_parse_v1(raw, dialect, profile, mode)` | [VERIFIED: binding/exports.mbt:25-26 — `#export_name("doris_parse_v1")\npub fn doris_parse_v1(raw : Bytes, profile : String, mode : String) -> Bytes`] |
| 32 | `binding/exports.mbt:33-34` | `#export_name("doris_format_v1")` / `doris_format_v1(raw, profile, mode, …)` | `fathom_format_v1`（签名加 dialect） | [VERIFIED: binding/exports.mbt:33-34] |
| 33 | `binding/exports.mbt:74-75` | `#export_name("doris_profile_v1")` / `doris_profile_v1(profile)` | `fathom_dialect_v1`（或并入 capabilities，见 Open Question 4） | [VERIFIED: binding/exports.mbt:74-75] |
| 34 | `binding/exports.mbt:79-80` | `#export_name("doris_capabilities_v1")` / `doris_capabilities_v1()` | `fathom_capabilities_v1()`（内容增 dialects/profiles 列表） | [VERIFIED: binding/exports.mbt:79-80] |
| 35 | `binding/moon.pkg:14-28` | js/wasm `exports: [doris_parse_v1, doris_format_v1, doris_profile_v1, doris_capabilities_v1]` | 同步改名（与 `#export_name` 一致，Pitfall：export 半迁移） | [VERIFIED: binding/moon.pkg:14-28 — js/wasm 两处 exports 列表] |
| 36 | `binding/schema.mbt:3-5` | `PARSE_SCHEMA_VERSION = "doris.parse.v1"` / `FORMAT_SCHEMA_VERSION = "doris.format.v1"` / `SOURCE_TRANSPORT = "inline-root-v1"` | `"fathom.parse.v1"` / `"fathom.format.v1"`（SOURCE_TRANSPORT 不变） | [VERIFIED: binding/schema.mbt:3-5] |
| 37 | `binding/schema.mbt:63,101,154,165` | `"doris.error.v1"` / `"doris.profile.v1"` / `"doris.capabilities.v1"` | `"fathom.error.v1"` / `"fathom.dialect.v1"`（或按 D-09 命名）/ `"fathom.capabilities.v1"` | [VERIFIED: binding/schema.mbt:63 — `"schema_version": Json::string("doris.error.v1")`；:101 同；:154 `"doris.profile.v1"`；:165 `"doris.capabilities.v1"`] |
| 38 | `binding/schema.mbt:29-35` | `validate_profile(profile)` 仅 `"2.1"\|"3.x"\|"4.x"` | `validate_dialect_profile(dialect, profile)`；dialect ∈ {doris, flink}；profile 按 dialect 校验 | [VERIFIED: binding/schema.mbt:29-35 — `pub fn validate_profile(profile : String) -> Result[Unit, SchemaError] { match profile { "2.1" \| "3.x" \| "4.x" => Ok(()) … }`] |
| 39 | `binding/schema.mbt:43-49,107-115,131-146` | `DORIS-SCHEMA-00N` / `DORIS-PARSE-00N` / `DORIS-FORMAT-00N` code 映射 | `FATHOM-*`（§5 表）；`UnknownDialect` 新 code | [VERIFIED: binding/schema.mbt:43-49（schema_error_code）、107-115（parse_error_json）、131-146（format_error_json）] |
| 40 | `binding/schema.mbt:117` | `"unsupported Doris profile: \{profile_id}"` | 中性措辞 | [VERIFIED: binding/schema.mbt:117-119 — `@api.ParseError::UnknownProfile(profile_id~) => "unsupported Doris profile: \{profile_id}"`] |

### 6.4 LSP（NAME-03 + D-01/D-02/D-03）

| # | 文件 | Old | New | 引用与逐字 |
|---|------|-----|-----|-----------|
| 41 | `lsp/handlers.mbt:4-10` | `ServerState { docs; profile : String; initialized; shutdown; exited }` | `ServerState { docs; default_selection?; language_mapping?; initialized; … }`（workspace 默认 + 显式映射） | [VERIFIED: lsp/handlers.mbt:4-10 — `pub(all) struct ServerState { pub mut docs : DocumentStore, pub mut profile : String, … }`] |
| 42 | `lsp/documents.mbt:3-8` | `Document { uri; version; text }` | 增 `dialect : String` / `profile : String`（document 级 context，D-03） | [VERIFIED: lsp/documents.mbt:3-8 — `pub(all) struct Document { pub uri : String, pub version : Int, pub text : Bytes }`] |
| 43 | `lsp/handlers.mbt:144-150` | `initialize_profile(params)` 只读 `initializationOptions.profile` | `initialize_selection(params)` 读 `{dialect, profile}` | [VERIFIED: lsp/handlers.mbt:144-150] |
| 44 | `lsp/handlers.mbt:45,85` | `"source": Json::string("doris")` | `"source": Json::string("fathom")` | [VERIFIED: lsp/handlers.mbt:45,85] |
| 45 | `lsp/handlers.mbt:84` | `"code": Json::string("DORIS-LSP-001")` | `FATHOM-LSP-001` | [VERIFIED: lsp/handlers.mbt:84] |
| 46 | `lsp/handlers.mbt:160` | `"serverInfo": { "name": "doris-lsp", "version": "0.1" }` | `"name": "fathom-lsp"` | [VERIFIED: lsp/handlers.mbt:160] |
| 47 | `lsp/handlers.mbt:309` | `-32602 "unsupported Doris profile"` | `-32602 结构化「missing/unknown/conflicting dialect or profile」` | [VERIFIED: lsp/handlers.mbt:309] |
| 48 | `lsp/handlers.mbt:79,169,269` | `parse_with_ids(document.text, state.profile, …)` / `format_with_ids(…, state.profile, …)` / `complete(document.text, state.profile, …)` | 全部改用 document 的 `{dialect, profile}` context | [VERIFIED: lsp/handlers.mbt:79,169,269] |
| 49 | `lsp/handlers.mbt:78-90` | `parse_document` 无 context 参数 | `parse_document(state, document)` 按 `document.dialect/profile` 解析；解析失败 fallback 诊断 code/source 同步改 | [VERIFIED: lsp/handlers.mbt:78-90] |
| 50 | `lsp/*_test.mbt` | initialize JSON `{"initializationOptions":{"profile":"4.x"}}`（protocol_test.mbt:10 等） | 加 `"dialect":"doris"`；schema 断言 `"doris.parse.v1"`（diagnostics_formatting_test.mbt:2-6,14-19）改 `fathom.parse.v1` | [VERIFIED: lsp/protocol_test.mbt:10,29,49; lsp/diagnostics_formatting_test.mbt:2-19] |

### 6.5 CLI（D-11）

| # | 文件 | Old | New | 引用与逐字 |
|---|------|-----|-----|-----------|
| 51 | `doris-sql/args.mbt:8-19` | `UsageError { MissingSubcommand; UnknownSubcommand; MissingProfile; UnknownProfile; … }` | 增 `MissingDialect` / `UnknownDialect` | [VERIFIED: doris-sql/args.mbt:8-19] |
| 52 | `doris-sql/args.mbt:40-42` | `parse_args` 仅接受 `"format"` 子命令 | `parse|format|lsp` 三个子命令；`--dialect <doris\|flink>` + `--profile <id>` 均必选 | [VERIFIED: doris-sql/args.mbt:40-42 — `if args[0] != "format" { return Err(UnknownSubcommand(sub=args[0])) }`] |
| 53 | `doris-sql/args.mbt:125-127` | `is_valid_profile` = `"2.1"\|"3.x"\|"4.x"` | 按 dialect 校验（doris: 2.1/3.x/4.x；flink: Phase 10 前全部拒绝） | [VERIFIED: doris-sql/args.mbt:125-127 — `fn is_valid_profile(id : String) -> Bool { id == "2.1" \|\| id == "3.x" \|\| id == "4.x" }`] |
| 54 | `doris-sql/run.mbt:144` | `usage: doris-sql format --profile <2.1\|3.x\|4.x> …` | `usage: fathom-sql parse\|format\|lsp --dialect <doris\|flink> --profile <id> …` | [VERIFIED: doris-sql/run.mbt:144] |
| 55 | `doris-sql/run.mbt:148-155` | usage_error_message（`"missing required flag: --profile <2.1\|3.x\|4.x>"` 等） | 加 MissingDialect/UnknownDialect 消息；exit 2 语义不变 | [VERIFIED: doris-sql/run.mbt:148-155] |
| 56 | `doris-sql/run.mbt:79` | `@api.format_with_ids(input, command.profile, "strict", format_options)` | `@api.format_with_ids(input, command.dialect, command.profile, "strict", …)`（或新 DialectOptions 入口） | [VERIFIED: doris-sql/run.mbt:79] |
| 57 | `doris-sql/cli_test.mbt` | `Command { profile: "4.x", … }` 构造 | Command 增 dialect 字段；测试同步 | [VERIFIED: doris-sql/cli_test.mbt:22-31 — command_stdin 构造] |

### 6.6 宿主：VS Code / Web / IntelliJ（NAME-03）

| # | 文件 | Old | New | 引用与逐字 |
|---|------|-----|-----|-----------|
| 58 | `vscode/package.json:1-2` | `"name": "doris-sql-language-client"` / `"displayName": "Doris SQL Language Client"` | `fathom-sql-language-client` / `Fathom SQL Language Client` | [VERIFIED: vscode/package.json:1-2] |
| 59 | `vscode/package.json:15-17` | `"activationEvents": ["onLanguage:doris", "onCommand:doris.restartLanguageServer"]` | `onLanguage:sql` 或新 language id + `fathom.restartLanguageServer` | [VERIFIED: vscode/package.json:15-17] |
| 60 | `vscode/package.json:20-32` | language `"id": "doris"`、aliases `["Doris SQL", "doris-sql"]`、extensions `[".sql"]` | 中立 `"id": "sql"`（或按 dialect 拆分 `doris`/`flink`，Open Question 6）；Doris 只作 dialect 语义 | [VERIFIED: vscode/package.json:20-32] |
| 61 | `vscode/package.json:33-55` | `"doris.profile"`（enum 2.1/3.x/4.x, default 4.x）、`"doris.serverPath"`（default `"doris-lsp"`） | `fathom.dialect`（enum doris/flink）+ `fathom.profile` + `fathom.serverPath`（default `fathom-lsp`）；可加 language-specific 覆盖 | [VERIFIED: vscode/package.json:33-55 — `"doris.profile": { …, "default": "4.x", "description": "Explicit Doris release profile sent to doris-lsp." }` / `"doris.serverPath": { "default": "doris-lsp", … }`] |
| 62 | `vscode/package.json:56-60` | `"command": "doris.restartLanguageServer"`, title `"Doris SQL: Restart Language Server"` | `fathom.restartLanguageServer` / `"Fathom SQL: Restart Language Server"` | [VERIFIED: vscode/package.json:56-60] |
| 63 | `vscode/src/extension.ts:20-24,33-37,44-52` | `getConfiguration('doris')`、`LanguageClient('doris', 'Doris SQL Language Server', …)`、`documentSelector [{ language: 'doris' }]`、`initializationOptions: { profile }`、命令 `doris.restartLanguageServer` | `'fathom'`、`'Fathom SQL Language Server'`、language 映射、`initializationOptions: { dialect, profile }` | [VERIFIED: vscode/src/extension.ts:20-24,33-37,44-52] |
| 64 | `vscode/src/extension-contract.ts:1-8` | `SUPPORTED_PROFILES`、`normalizeProfile` fallback `'4.x'` | 加 `SUPPORTED_DIALECTS`；**无默认 dialect**（缺失即错误，D-02） | [VERIFIED: vscode/src/extension-contract.ts:1-8 — `export const SUPPORTED_PROFILES = Object.freeze(['2.1', '3.x', '4.x'])`、`normalizeProfile` 兜底 `'4.x'`] |
| 65 | `web/package.json:1-4` | `"name": "@fathom/doris-web-demo"` / `"description": "Offline Monaco host for the Doris SQL parser facade"` | `@fathom/sql-web-demo` / 中性描述 | [VERIFIED: web/package.json:1-4] |
| 66 | `web/index.html:6-7,18-19,26-27` | `<title>Doris SQL — offline parser demo</title>`、`<h1>Doris SQL diagnostics</h1>`、`Doris profile 4.x` | 中性 Fathom 标题 + dialect 选择器 | [VERIFIED: web/index.html:6-7,18-19,26-27] |
| 67 | `web/src/monaco-adapter.ts:3,16-22,76-100` | `PROFILES = ['2.1','3.x','4.x']`、`schema_version === 'doris.error.v1'`、`module.doris_parse_v1(…, profile, 'editor')`、`module.doris_format_v1(…)`、`'Choose a supported Doris profile.'` | `DIALECTS`+`PROFILES`、`'fathom.error.v1'`、`fathom_parse_v1(raw, dialect, profile, mode)`、中性文案 | [VERIFIED: web/src/monaco-adapter.ts:3,16-22,76-100] |
| 68 | `web/src/main.ts:12-16,26-31` | `'Doris demo markup is incomplete.'`、`monaco.languages.register({ id: 'doris' })`、`profileSelect` 默认 `'4.x'` | 中立语言 id + dialect/profile 双选择器 | [VERIFIED: web/src/main.ts:12-16,26-31 — `monaco.languages.register({ id: 'doris' })`；`profileSelect.value = '4.x'`] |
| 69 | `jetbrains/src/main/kotlin/fathom/jetbrains/doris/`（4 文件 + 2 测试） | package `fathom.jetbrains.doris`；类名 `Doris*` | 目录/包改 `fathom.jetbrains`（或 `fathom.jetbrains.sql`）；类名 `Fathom*`（或保持 factory 中性名，Open Question 6） | [VERIFIED: DorisLanguageServerFactory.kt:1,8 — `package fathom.jetbrains.doris` / `class DorisLanguageServerFactory`] |
| 70 | `jetbrains/.../DorisLanguageServerFactory.kt:40-43` | `initializationOptions(profile) = mapOf("profile" to profile)` | `mapOf("dialect" to dialect, "profile" to profile)` | [VERIFIED: DorisLanguageServerFactory.kt:40-43] |
| 71 | `jetbrains/.../DorisSettings.kt:8-11,20-22,42-47` | `@State(name = "DorisSettings", storages = [Storage("doris.xml")])`；`DEFAULT_EXECUTABLE = "doris-lsp"`；`DEFAULT_PROFILE = "4.x"`；`ALLOWED_PROFILES = listOf("2.1","3.x","4.x")` | `FathomSettings` / `fathom.xml`；`DEFAULT_EXECUTABLE = "fathom-lsp"`；增 dialect 维度 | [VERIFIED: DorisSettings.kt:8-11,42-47 — `@State(name = "DorisSettings", storages = [Storage("doris.xml")])`、`const val DEFAULT_EXECUTABLE = "doris-lsp"`、`const val DEFAULT_PROFILE = "4.x"`、`val ALLOWED_PROFILES: List<String> = listOf("2.1", "3.x", "4.x")`] |
| 72 | `jetbrains/.../DorisSettingsConfigurable.kt:11-24` | UI 标签 `"doris-lsp executable:"` / `"Doris profile:"`、`getDisplayName() = "Doris SQL"` | `fathom-lsp executable:` + dialect selector；`"Fathom SQL"` | [VERIFIED: DorisSettingsConfigurable.kt:11-24] |
| 73 | `jetbrains/.../DorisNativeDownloader.kt:46-58,268-270,305-315` | `DorisNativePlatform`（assetName `doris-lsp-{platform}`）；`DEFAULT_REPOSITORY = "tchivs/doris-sql-parser-sdk"`；`MANIFEST_ASSET_NAME = "doris-lsp-manifest.json"`；缓存目录 `Fathom/doris-sql` | `FathomNativePlatform` assetName `fathom-lsp-{platform}`；manifest `fathom-lsp-manifest.json`；缓存目录 `Fathom/fathom-sql`；repository 名（release 仓库，Open Question 8） | [VERIFIED: DorisNativeDownloader.kt:46-58,268-270,305-315 — `LINUX_X86_64("linux-x86_64", "doris-lsp-linux-x86_64")` 等、`const val DEFAULT_REPOSITORY = "tchivs/doris-sql-parser-sdk"`、`const val MANIFEST_ASSET_NAME = "doris-lsp-manifest.json"`] |
| 74 | `jetbrains/scripts/source-smoke.py:44-48,53-56,62-71,89-101` | 契约检查：`fathom\.doris\.sql` 插件 ID、`server id="doris"`、`DorisSettings`/`DorisNativeDownloader` 路径、`DEFAULT_EXECUTABLE = "doris-lsp"`、`doris-lsp-manifest\.json` | 全部同步到中立名（此脚本本身是命名 gate 的 jetbrains 部分，随迁移更新） | [VERIFIED: jetbrains/scripts/source-smoke.py:44-48,53-56,62-71,89-101] |
| 75 | `jetbrains/build.gradle.kts:4-7,22-25` | `group = "fathom.jetbrains"`；`changeNotes = "Initial Doris SQL LSP4IJ integration."` | 中性 changeNotes；group 不变（已是 fathom.jetbrains） | [VERIFIED: jetbrains/build.gradle.kts:4-7,22-25] |
| 76 | `jetbrains/settings.gradle.kts:12` | `rootProject.name = "fathom-doris-intellij"` | `fathom-sql-intellij` | [VERIFIED: jetbrains/settings.gradle.kts:12] |

### 6.7 CI / release assets / corpus / docs（NAME-03/04）

| # | 文件 | Old | New | 引用与逐字 |
|---|------|-----|-----|-----------|
| 77 | `.github/workflows/doris-native-release.yml:2,93-107` | workflow name `Doris Native Release`；asset `dist/doris-lsp-${{ matrix.platform }}` / `doris-lsp-{platform}.exe`；manifest `doris-lsp-manifest.json` | `Fathom Native Release`；`dist/fathom-lsp-{platform}`；`fathom-lsp-manifest.json` | [VERIFIED: .github/workflows/doris-native-release.yml:2 — `name: Doris Native Release`；:93-107 — `cp _build/native/release/build/lsp/lsp.exe "dist/doris-lsp-${{ matrix.platform }}.exe"`、`name: doris-lsp-${{ matrix.platform }}`、`"doris-lsp-manifest.json"`] |
| 78 | `.github/workflows/jetbrains-plugin.yml:44-46` | artifact `fathom-doris-intellij` | `fathom-sql-intellij` | [VERIFIED: .github/workflows/jetbrains-plugin.yml:44-46 — `name: fathom-doris-intellij`] |
| 79 | `.github/workflows/ci.yml` | 无命名残留（checks 用 package 名） | 增 NAME-04 gate 作业（`python3 scripts/check_naming.py`） | [VERIFIED: ci.yml — corpus 作业已有 `python3 corpus/tools/check_keywords.py corpus/keywords.tsv` 模式可参照] |
| 80 | `parity/fixtures/lsp-tracer.json:1-2,11-12` | `"schema_version": "doris.parse.v1"` / `"schema_version": "doris.format.v1"` / `"profile": "4.x"` | `fathom.parse.v1` / `fathom.format.v1`；增 `"dialect": "doris"` | [VERIFIED: parity/fixtures/lsp-tracer.json:1-2,11-12] |
| 81 | `parity/fixtures/target-matrix.json` | 含 `doris` 字符串的 schema 断言 | 同步 | [VERIFIED: parity/fixtures/target-matrix.json（grep 命中 `doris`）] |
| 82 | `parity/export_smoke_test.mbt:4-11,15-21` | `@binding.doris_parse_v1(b"select 1", "4.x", "strict")` 等；断言 `"doris.parse.v1"`/`"doris.format.v1"`/`"doris.profile.v1"`/`"doris.capabilities.v1"` | `fathom_*_v1` + dialect 参数；断言 `fathom.*.v1` | [VERIFIED: parity/export_smoke_test.mbt:4-21] |
| 83 | `parity/parity_test.mbt`、`schema_test.mbt:15-18` | `parse_with_ids(b"SELECT /* note */ 1", "4.x", "editor")`；`validate_schema_version("doris.parse.v1")`；`validate_profile("mysql")` | 加 dialect 参数；`fathom.parse.v1`；`validate_dialect_profile` | [VERIFIED: parity/schema_test.mbt:15-18 — `assert_true(@binding.validate_schema_version("doris.parse.v1") is Ok(_))`、`validate_profile("mysql") is Err(…)`] |
| 84 | `corpus/`（`manifest.tsv`、`keywords.tsv`、`doris-2.1/`、`doris-3.x/`、`doris-4.x/`、`tools/check_keywords.py`、`differential.tsv`、`coverage.tsv`） | Doris 语义/来源标识 | **保留**（D-04 provenance；profile 列值 `2.1/3.x/4.x` 与 feature_introduction 字符串不变） | [VERIFIED: corpus/manifest.tsv:1 — header 含 `profile/exact_release/feature_introduction/official_url`，值 `2.1/3.x/4.x`；corpus/tools/check_keywords.py:23-27 — `VALID_PROFILES = {"2.1", "3.x", "4.x"}`（Doris 生产词 inventory gate，Phase 10 再加 Flink）] |
| 85 | `.planning/milestones/**`、`.planning/ROADMAP.md`/`REQUIREMENTS.md` 历史段 | v1.0/v3.0 归档含旧名 | **保留**（D-04 豁免：历史事实） | [VERIFIED: .planning/milestones/ 含 v1.0-REQUIREMENTS.md、v1.0-ROADMAP.md、v1.0-phases、v1.0-research、v3.0-REQUIREMENTS.md；ROADMAP.md v1.0 段 `<details>` 归档] |
| 86 | `docs/API.md`、`docs/CONFIGURATION.md`、`docs/GETTING-STARTED.md`、`docs/TESTING.md`、`docs/DEVELOPMENT.md`、`docs/ARCHITECTURE.md` + `zh-CN/` | `fathom/doris-sql/api`、`doris-sql/`、Doris profile 表 | `fathom/sql/api`、`fathom-sql`、dialect+profile 表；Doris 仅作 dialect/profile 语义 | [VERIFIED: docs/CONFIGURATION.md:17-20 — `name = "fathom/doris-sql"`；docs/API.md:5,11-12,27-28 — 导入与 entry point 表] |

## Naming Gate Design (NAME-04)

**目标：** CI 中有一道 inventory/allowlist gate，拒绝产品层残留的 `doris-sql`、`doris-lsp`、`doris.*`（schema/export/package）、`DORIS-*`；allowlist 只允许 Doris 方言语义与 provenance（D-04/D-05）。

### 7.1 实现形态

新脚本 `scripts/check_naming.py`（Python stdlib，完全镜像 `corpus/tools/check_keywords.py` 的校验模式：逐行检查、汇总 problems、非零退出）。CI 在 `ci.yml` 新增作业：

```yaml
  naming-gate:
    name: neutral naming inventory gate (NAME-04)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: python3 scripts/check_naming.py
```

### 7.2 扫描范围与 D-04 豁免

- **扫描文件集**（product files）：`**/*.mbt`、`**/*.ts`、`**/*.mjs`、`**/*.js`（排除 `node_modules/`）、`**/*.kt`、`**/*.kts`、`**/*.gradle*`、`**/*.json`（排除 `package-lock.json`/`tsconfig`/`_build/`）、`**/*.yml`、`**/*.yaml`、`**/*.mod`、`**/*.pkg`、`**/*.py`（排除 `corpus/tools/`）、`README*.md`、`docs/**`、`web/**`（排除 node_modules）、`vscode/**`、`jetbrains/**`（排除 build/、.gradle/）。
- **豁免路径（D-04）**：`milestones/v1.0-*`、`milestones/v1.0-research/`、`.planning/milestones/**`、`.planning/research/**`（v1 证据记录）、`.planning/phases/**`（历史 phase 文档含旧名引用）、`.planning/ROADMAP.md`/`REQUIREMENTS.md` 中标记 archived 的历史段（v1.0 `<details>` 与 v3.0 段）。
- **provenance 豁免**：`corpus/**`（含 `doris-2.1/` 等目录名、`manifest.tsv` 的 profile 列、`doris.apache.org` URL、`corpus/tools/check_keywords.py` 的 Doris 生产词 inventory）——Doris 语料/来源标识按 D-04 保留。

### 7.3 forbidden 模式（product 文件内出现即失败）

| 模式 | 覆盖 | 示例命中（现状） |
|------|------|------------------|
| `doris-sql` | CLI/包/模块名残留 | `moon.mod:5`、各 moon.pkg import、`doris-sql/` 目录名、`DEFAULT_REPOSITORY` |
| `doris-lsp` | LSP 二进制/serverInfo/配置残留 | `lsp/handlers.mbt:160`、`vscode/package.json:46,53`、`DorisSettings.kt:42`、`DorisNativeDownloader.kt` |
| `doris_(parse\|format\|profile\|capabilities)_v1` | binding export 残留 | `binding/exports.mbt:25-80`、`binding/moon.pkg:14-28`、web/monaco-adapter、parity tests |
| `doris\.(parse\|format\|error\|profile\|capabilities)\.v1` | wire schema 残留 | `api/api.mbt:298`、`binding/schema.mbt:3-4,63,101,154,165`、`parity/fixtures/lsp-tracer.json` |
| `DORIS-` | 诊断 code 残留 | §5 表全部（PARSE/FORMAT/SCHEMA/LSP） |
| `fathom/doris-sql` | 模块 import 残留 | 全部 15 个 moon.pkg + docs |
| `doris-sql-language-client` / `@fathom/doris-web-demo` / `fathom-doris-intellij` | 包名残留 | `vscode/package.json:1`、`web/package.json:2`、`jetbrains/settings.gradle.kts:12` |
| `fathom\.doris\.sql` | IntelliJ 插件 ID 残留 | `jetbrains/build/tmp/...searchableOptions`（构建产物，scan 排除 build/）、source-smoke.py 契约 |
| `"id": "doris"` / `onLanguage:doris` / `server id="doris"` | 语言 ID 残留 | `vscode/package.json:20-24`、`web/src/main.ts:26`、source-smoke.py |
| `doris\.profile` / `doris\.serverPath` / `doris\.restartLanguageServer` / `"DorisSettings"` / `doris\.xml` | 配置键/状态名残留 | `vscode/package.json:33-60`、`vscode/src/extension.ts:20`、`DorisSettings.kt:8-11` |
| `Doris SQL Language (Client\|Server)` / `"Doris SQL"`（display/title 语境） | 产品显示名残留 | `vscode/package.json:2`、`extension.ts:33-37`、`web/index.html`、`DorisSettingsConfigurable.kt:11-24` |

### 7.4 allowlist（出现允许，不计入失败）

| 允许模式 | 语义依据 |
|----------|----------|
| `Dialect::Doris`、`DorisProfile`、`DorisFeature`、`ValidatedProfileContext`、`ProfileMetadata`、`ClassificationEntry`（若保留） | D-05：Doris 方言自身类型名保留 |
| `"doris"` 作为 `dialect_id` 枚举值（CLI `--dialect doris`、LSP `"dialect":"doris"`、schema metadata 字段值） | DIALECT-01：doris 是合法 dialect 值 |
| `"2.1"`/`"3.x"`/`"4.x"` profile id 与 `feature_introduction` 字符串 | profile 值本身，非产品名 |
| `doris.apache.org` 与 `token/token.mbt:289-296` 的 `*_docs_url` 常量、`corpus/manifest.tsv` official_url 列 | 官方来源 provenance |
| `corpus/doris-2.1\|3.x\|4.x` 路径、`keywords.tsv` 分类值 | 语料 provenance |
| README/docs 中 "Apache Doris SQL"（引擎名）与 "Doris profile"（dialect 语义）的说明性文字 | 语义标识，非产品品牌 |
| `.planning/**`、`milestones/**`、`corpus/**`、`jetbrains/build/**`、`_build/**`、`node_modules/**` | D-04 豁免 + 构建产物 |
| `tchivs/doris-sql-parser-sdk`（GitHub release 仓库名，若保留） | release 仓库标识（Open Question 8：是否随产品改名） |

**Key insight:** `doris` 同时是旧产品名与方言标识（PITFALLS.md Pitfall 4），机械全局替换会错误删除必须保留的 `Dialect::Doris`/corpus provenance。gate 必须按「模式 + 文件作用域」双维度工作，而不是一个全局字符串黑名单。

## Runtime State Inventory

> 本阶段为 rename/refactor 阶段，5 类全部显式回答（D-07 之前的「仓库改名后，还有什么运行时系统仍持有旧字符串」问题）。

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | **None — verified by repo inspection**。项目无数据库/无 KV 存储/无 Redis；解析器是纯内存组件。唯一持久化数据是 git 内的 corpus 与快照（见 Build artifacts 行）。 | 无数据迁移 |
| Live service config | **GitHub Releases 已发布的 v0.1.0 资产**：release 中 `doris-lsp-{platform}` 二进制与 `doris-lsp-manifest.json` 已发布（STATE.md「GitHub Releases Native doris-lsp delivery」确认）。这些是历史 release，D-04 语义下保持原名；**新 release 使用 `fathom-lsp-*` 资产名**（workflow 77 行）。JetBrains 客户端缓存目录 `Fathom/doris-sql`（`DorisNativeDownloader.kt:305-315`）是客户端本地缓存，随新版本代码改名为 `Fathom/fathom-sql`；旧缓存目录为遗留数据（无害，可手动清理）。 | 代码编辑（workflow/下载器改名）+ 发布流程操作（新 tag 用新资产名）；旧 release 不动 |
| OS-registered state | **None — verified by inspection**。无 systemd/launchd/Windows Task Scheduler 注册、无 pm2/守护进程（项目为库 + 用户调用的 CLI/LSP 二进制，无安装注册步骤）。 | 无 |
| Secrets/env vars | **None — verified by inspection**。CONFIGURATION.md 显式验证无 `.env`/`process.env` 读取；CI env（MOONBIT_INSTALL_VERSION、GH_TOKEN、CERTIFICATE_CHAIN、PRIVATE_KEY、PRIVATE_KEY_PASSWORD、PUBLISH_TOKEN）均不引用产品名，改名无需变更任何 key。 | 无 |
| Build artifacts | **`_build/`（gitignored）**：`_build/native/release/build/lsp/lsp.exe`、`_build/js/debug/build/binding/binding.js`、`_build/wasm/` 等。模块/包改名后旧路径产物 stale，`moon build` 自动重建（改名后首次构建会生成新路径）；CI 从零构建，不受影响。`jetbrains/build/` 与 `.gradle/`：插件 ID 改名后 `buildSearchableOptions/p-fathom.doris.sql-*.json` 残留，`./gradlew clean build` 重建。`web/node_modules`/`vscode/node_modules`：package.json name 变更不影响已安装依赖（private 包）。 | 重命名后运行 `moon clean && moon build`、`./gradlew clean build` 验证新产物名；无数据迁移 |

**Canonical question 回答：** 仓库全部文件更新后，仍持有旧字符串的运行时系统 = 已发布的 GitHub Release 资产（历史，保留）+ JetBrains 客户端旧缓存目录（无害遗留）+ 本机 `_build/`（自动重建）。均无需数据迁移。

## Doris v1 Baseline Freeze Procedure (D-07/D-08)

### 9.1 冻结范围（D-07 全量 public 行为）

| 输出类别 | 来源（现状 inventory） | 比较维度 |
|----------|------------------------|----------|
| corpus fixtures | `corpus/manifest.tsv`（45 行含 header，44 数据行；实测 `wc -l` = 45）、`corpus/doris-2.1|3.x|4.x/` SQL 文件、`corpus/keywords.tsv` | 字节一致 + sha256 记录 |
| CST 形状/span | `test/corpus_test.mbt`（embedded oracle，357 行）、`parser_test.mbt`、`ddl_test.mbt`、`dml_test.mbt`、`keyword_test.mbt`、`recovery_test.mbt`、`source_test.mbt` | 序列化 `ParseResult.root` 的 normalized view（kind/start_byte/end_byte/text_len）+ `print_lossless(parse(x)) == x` |
| diagnostics | 上述测试 + `api/api.mbt` 内嵌测试（`:520-575`） | code/span/statement_id/severity/message/expected_class |
| strict/editor 双模式 | `api/api.mbt:552-563`（modes share shape）、recovery_test | 同输入两模式形状一致 |
| formatter 输出 | `test/formatter_test.mbt`（75.6KB）、`formatter/format.mbt` refusal | output 字节 + refusal（accepted=false, 空 output, 单 FATHOM-FORMAT-001）+ statement_offsets |
| completion | `completion/completion.mbt` 测试 + `lsp/completion_test.mbt` | items（label/detail/start/end/new_text）+ is_incomplete |
| CLI exit code/stdout/stderr | `doris-sql/cli_test.mbt`（exit 0/1/2 全矩阵） | `CliOutcome` 字节 |
| LSP 协议输出 | `lsp/protocol_test.mbt`、`framing_test.mbt`、`lifecycle_test.mbt`、`diagnostics_formatting_test.mbt`、`parity/fixtures/lsp-tracer.json`、`target-matrix.json` | 序列化 JSON 字节（initialize/didOpen/diagnostics/format/completion 响应） |
| wire schema 输出 | `parity/schema_test.mbt`、`export_smoke_test.mbt`、`parity_test.mbt`、`coordinates_test.mbt` | `binding.parse_result_json/format_result_json/error_json/capabilities_json` 字节 |

### 9.2 快照 diff 门禁机制（D-08）

**机制（官方核验）：** MoonBit `@test.T::snapshot(filename=...)` 把整段输出写入该包 `__snapshot__/` 目录；`moon test --update` 生成/更新；`moon test` 在内容不一致时失败（[VERIFIED: https://docs.moonbitlang.com/en/latest/language/tests.html]）。

**执行步骤：**

1. **Wave 0（任何重构之前）**：在 `parity/`（或新增 `baseline/` package）建立 baseline snapshot 包。每个 fixture × profile × mode 组合调用现有共享入口（`@binding.parse_result_json`、`format_result_json`、CLI `run_format` 同构、LSP handler 同构），把完整序列化输出写入 `@test.T::snapshot(filename="<fixture>.<profile>.<mode>.json")`。
   - 同时记录 fixture 来源哈希：`sha256sum corpus/manifest.tsv corpus/keywords.tsv corpus/doris-*/**.sql` 写入 `parity/baseline-hashes.txt`（提交到 git）。
2. **提交 baseline**：`moon test --update --package parity` 生成 `parity/__snapshot__/` → 提交。此后 `moon test --package parity`（无 `--update`）对任何字节差异失败。
3. **每步重构后**：跑 `moon test --target native --package parity`（基线门禁）+ `moon test --target native --package test --package api --package lsp --package doris-sql(fathom-sql)`（全部行为测试）。任何失败 = 回归，必须修复或经批准记录（D-08「字节级一致或经批准并记录的变更才通过」——批准记录写入 phase 变更日志）。
4. **形状 diff 报告（可选叠加）**：`scripts/baseline_diff.py`（stdlib）解析 `__snapshot__/` 前后两份树，输出按 category 分组的结构化 diff（schema_version namespace 变更、新增 `dialect` 字段等预期差异单独列出），让「预期变更」与「意外回归」可区分。Phase 9 的 schema 字段增删（`fathom.*.v1`、`dialect` 字段）是有意变更，必须在报告中标注批准。
5. **跨后端一致性**：`parity/run_native.mbt`/`run_js.mbt`/`run_wasm.mbt`（`parity/moon.pkg:7-11` targets 映射）已有 per-target 运行骨架；baseline 快照的序列化字节必须跨 Native/JS/linear-Wasm 一致（PARITY-02 的 Phase 12 门禁，Phase 9 先在 baseline 包内断言三 target 输出相等）。

**顺序依赖（不可颠倒）：** baseline 冻结 → dialect 层重构（每步 diff）→ 命名迁移（每步 diff）→ 宿主改造（每步 diff）。任何「先改代码再补 baseline」都会让 baseline 记录的是重构后的行为（PITFALLS.md Pitfall 3）。

### 9.3 变更审批路径（D-08 例外）

预期变更（schema namespace、`dialect` 字段、error code 前缀）在 plan 中预先声明为 approved-change 清单；实现中出现的任何未声明差异 = 回归，回到修复循环。`moon test --update` 只允许在「approved-change 已落地 + 变更记录已写」时使用一次。

## Common Pitfalls

### Pitfall 1: 全局分类表污染（DIALECT-02 主风险）
**What goes wrong:** 把 Flink 词加进现有 `classification_rows`（`token/token.mbt:307`），或保留无参数 `classification_of(raw)`/`is_reserved_word(raw)`（`:450,485`）——同一个词在 Doris/Flink 中可能是 reserved/non-reserved/contextual 不同类别；formatter（`formatter/case.mbt:5-11`）与 completion（`completion/completion.mbt:131`）复用后隐式全局状态泄漏。
**Why it happens:** v1 只有一张表，横向追加最省事（PITFALLS.md Pitfall 1 证据链）。
**How to avoid:** Phase 9 先行拆分 `doris_classification_rows`/`flink_classification_rows`（共享 `KeywordEntry` 结构与 ASCII case-insensitive 算法 `token_bytes_equal_ci`）；所有分类查询签名加 `DialectContext`；禁止保留无参数公共 `is_reserved_word`（可留 Doris 内部私有 helper）。
**Warning signs:** 新 Flink 词只改 `token/token.mbt`；`classification_of(raw)` 无 context 参数；`QUALIFY/TABLE/MATCH/DEFINE/DESCRIPTOR` 在不同上下文出现 identifier/keyword 结果不一致。

### Pitfall 2: 用 `DorisFeature` 冒充 Dialect 或散落 `if dialect == Flink`
**What goes wrong:** 检查「当前 profile 支持 feature」而没检查「当前 parser 是 Doris」（PITFALLS.md Pitfall 2）。`DorisFeature::Qualify` 等（`token/token.mbt:133-141`）是 Doris 版本功能抽象，不是多方言抽象；Flink 代码不得 import `@token.DorisFeature` 或产出 `DORIS-*` 诊断。
**How to avoid:** 单一 `parse_segment` router（`parser/parser.mbt:3327`）先 `match context.dialect`；DorisFeature 只存在于 `dialect/doris.mbt`；共享表达式只共享字面量/标识符/括号/通用运算符机制。
**Warning signs:** `parser/parser.mbt` 出现散落的 `if dialect == Flink`；Flink 分支生成 `DORIS-PARSE-*`。

### Pitfall 3: Doris 隐性回归且 parity 只测「能编译」（D-07 主风险）
**What goes wrong:** 任何 lexer 分类、Token struct、共享 Pratt、recovery 改动都可能改变 Doris v1 的 CST span、diagnostic code/statement_id、strict/editor 边界或 2.1/3.x/4.x feature gate 接受性（PITFALLS.md Pitfall 3）。
**How to avoid:** 按 §9 顺序：先冻结 baseline（`@test.T::snapshot` 全量），每步重构跑 `moon test --package parity`（字节级）+ 全部行为测试；比较完整 serialized result 而非只看 `valid`。
**Warning signs:** PR 只有新 dialect 测试没有 Doris baseline diff；`moon test --update` 被无审批使用；Native 通过而 JS/Wasm/LSP 只编译。

### Pitfall 4: 命名半迁移（NAME-01..03 主风险）
**What goes wrong:** 只改 README 或模块名，漏掉 `binding/moon.pkg` 的 js/wasm exports 列表（`:14-28`）、`#export_name`（`binding/exports.mbt:25-80`）、parity fixture（`lsp-tracer.json`）、web 测试 mock（`web/src/main.test.ts:16-26`）、CI workflow 资产名、JetBrains source-smoke 契约（PITFALLS.md Pitfall 4 证据链）。
**How to avoid:** 以 §6 迁移表为唯一清单逐行执行；`#export_name` 与 `moon.pkg exports` 列表必须同步改（官方文档：exports 是 export 名的另一入口）；parity/web/CI 测试调用点（`parity/export_smoke_test.mbt:4-11`、`web/src/monaco-adapter.ts:88,96`）与生产代码同 PR 更新；NAME-04 gate 兜底。
**Warning signs:** JS export 名改了但 moon.pkg exports/Wasm runner/parity fixture 仍调旧符号；发布 workflow 产出名与 README 安装命令不一致；JetBrains/VS Code 只改一方。

### Pitfall 5: LSP 方言切换的 stale-response 与全局 profile 状态（D-03）
**What goes wrong:** `ServerState.profile`（`lsp/handlers.mbt:6`）是单一全局字符串；若只把它改成「新 dialect 字符串」而不做 document 级绑定，切换 dialect 后旧 context 的 diagnostics 会覆盖新结果，或语言映射/配置冲突时静默选错方言（PITFALLS.md Pitfall 6）。
**How to avoid:** `Document` 增 `dialect/profile`（`lsp/documents.mbt:3-8` 已保证 version 单调性，`DocumentStore::open/change` 拒绝旧版本）；每次 parse/format/completion 用 document 自身 context；配置变更时按新 context 重解析当前 revision 并只发布 ≥ 当前 version 的结果；completion 的 stale 检查（`lsp/handlers.mbt:253-257`）模式推广到 diagnostics。
**Warning signs:** 同一 URI 改 dialect 后旧 diagnostics 仍可覆盖新结果；`languageId`/config/init 三者冲突无拒绝路径；测试只有 Doris `.sql` 无 dialect 切换负例。

### Pitfall 6: profile 校验错误形状复用与 `"unsupported Doris profile"` 泄漏
**What goes wrong:** `validate_profile`（`binding/schema.mbt:29-35`）只认 `2.1/3.x/4.x`；泛化时若只把字符串集合扩大，会丢失「dialect 与 profile 正交」校验，且错误消息继续写 `"unsupported Doris profile: ..."`（`binding/schema.mbt:117`）与 `"unsupported Doris profile"`（`lsp/handlers.mbt:309`）——Flink 请求会看到 Doris 措辞。
**How to avoid:** `validate_dialect_profile(dialect, profile)` 先校验 dialect（未知 → `UnknownDialect` 结构化错误），再按 dialect 校验 profile；消息中性化，dialect 由字段表达（D-10）。
**Warning signs:** Flink request 的错误 code/source 中出现 `DORIS`；`--dialect flink --profile 4.x` 被错误接受。

### Pitfall 7: 大小写不敏感查找的方言独立性问题
**What goes wrong:** `token_bytes_equal_ci`（`token/token.mbt:221-236`）是纯 ASCII fold，算法可共享；但若查找函数内部仍引用单个全局 rows 数组，Flink 查找会误中 Doris 行。
**How to avoid:** 拆分后的 `classification_of(context, raw)` 在函数内按 `context.dialect` 选择 rows 数组；两个数组各自维护（同词仍分别拥有 row/source/profile metadata，ARCHITECTURE.md 明确）。
**Warning signs:** 测试只验证默认方言；同词在两方言下无成对 identifier/keyword 用例。

### Pitfall 8: 导出/二进制名与包目录名不同步
**What goes wrong:** 二进制名 = 包目录名（官方文档 + 仓库 probe）；只改 `moon.mod` name 不改 `doris-sql/` 目录，或反之，导致 release workflow 复制的路径（`_build/native/release/build/lsp/lsp.exe` → `doris-lsp-*`）与实际产物不一致。
**How to avoid:** `git mv doris-sql fathom-sql` 一次性完成（目录 + import + 文档）；release workflow 的资产名/清单名同步（§6.7 行 77-78）。
**Warning signs:** README 安装命令与二进制名不一致；`_build/native/release/build/` 下产物名与 workflow 期望不符。

## Code Examples

### Common Operation 1: dialect 层查找 API（拆分 classification_rows 后）
```moonbit
// dialect/classification.mbt（示意 — 最终形态由 planner 按 token.mbt:450-494 迁移）
pub fn classification_of(context : DialectContext, raw : Bytes) -> KeywordEntry? {
  let rows = match context.dialect {
    Dialect::Doris => doris_classification_rows
    Dialect::Flink => flink_classification_rows
  }
  let mut index = 0
  while index < rows.length() {
    let entry = rows[index]
    if token_bytes_equal_ci(raw, entry.word) { return Some(entry) }
    index = index + 1
  }
  None
}
pub fn is_reserved_word(context : DialectContext, raw : Bytes) -> Bool {
  match classification_of(context, raw) {
    Some(entry) => entry.classification is Reserved
    None => false
  }
}
```
来源：[VERIFIED: token/token.mbt:450-494（现状算法逐行保留）+ ARCHITECTURE.md「dialect/ 层」设计]

### Common Operation 2: parse_segment 显式路由（DIALECT-03）
```moonbit
fn parse_segment(stream, start_index, end_index, statement_id, state, context : DialectContext) -> SyntaxNode {
  match context.dialect {
    Dialect::Doris => parse_doris_segment(stream, start_index, end_index, statement_id, state, context)
    Dialect::Flink => parse_flink_segment(stream, start_index, end_index, statement_id, state, context)
  }
}
```
来源：ARCHITECTURE.md「parse_segment routing」；现状 `parser/parser.mbt:3327-3385`（Doris starters 迁移进 `parse_doris_segment` 原样保留）。

### Common Operation 3: baseline 快照测试（D-08 门禁载体）
```moonbit
// parity/baseline_test.mbt（示意 — 复用 @test.T::snapshot 官方机制）
test "baseline 2.1-industrial strict parse" (t : @test.Test) {
  let fixture = corpus_fixture("2.1-industrial")  // 读 corpus/doris-2.1/ 内嵌字节
  let result = @binding.fathom_parse_v1(fixture, "doris", "2.1", "strict")
  t.write(@utf8.decode_lossy(result))
  t.snapshot(filename="2.1-industrial.doris.strict.json")
}
```
来源：[VERIFIED: https://docs.moonbitlang.com/en/latest/language/tests.html — `t.snapshot(filename=...)` 写入 `__snapshot__/`；`moon test --update` 管理]

### Common Operation 4: validate_dialect_profile（DIALECT-01 错误面）
```moonbit
pub fn validate_dialect_profile(dialect : String, profile : String) -> Result[Unit, SchemaError] {
  match dialect {
    "doris" => match profile {
      "2.1" | "3.x" | "4.x" => Ok(())
      _ => Err(UnsupportedProfile(profile~))
    }
    "flink" => match profile {
      // Phase 10 填充 flink-2.3.0 / flink-2.1.3 / flink-1.20.5；Phase 9 全部拒绝
      _ => Err(UnsupportedProfile(profile~))
    }
    _ => Err(UnknownDialect(dialect~))
  }
}
```
来源：现状 `binding/schema.mbt:29-35`（`validate_profile` 形状保留）+ D-11。

### Common Operation 5: 命名 gate 核心循环（NAME-04）
```python
# scripts/check_naming.py（stdlib，镜像 corpus/tools/check_keywords.py 模式）
FORBIDDEN = [
    r"doris-sql", r"doris-lsp", r"doris_(parse|format|profile|capabilities)_v1",
    r"doris\.(parse|format|error|profile|capabilities)\.v1", r"DORIS-",
    r"fathom/doris-sql", r"doris\.profile", r"doris\.serverPath",
]
ALLOWLIST_PATHS = ("corpus/", ".planning/", "milestones/", "_build/", "node_modules/")
ALLOWLIST_PATTERNS = (r"Dialect::Doris", r"DorisProfile", r"DorisFeature",
                      r"doris\.apache\.org", r"--dialect doris", r'"dialect"\s*:\s*"doris"')
# 扫描 product 文件，逐行：命中 FORBIDDEN 且不在 allowlist 路径/模式内 → problem
```
来源：`corpus/tools/check_keywords.py:10-13,56-90`（校验模式）与 §7.3/7.4 表。

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `classification_rows` 全局单表 + 无参数分类查询（`token/token.mbt:307,450`） | 按 dialect 拆分的 rows + `classification_of(context, raw)` | Phase 9 | 方言词法独立性（DIALECT-02）；formatter/completion 不再隐式共享 Doris 表 |
| `Token.profile : DorisProfile` / `TokenStream.profile`（`token/token.mbt:513,535`） | `Token.context : DialectContext` | Phase 9 | token 层不再猜测方言；lexer 共享 scanner + per-dialect policy |
| `parse_segment` 硬编码 Doris starters（`parser/parser.mbt:3336-3376`） | `match context.dialect` 显式 dispatch | Phase 9 | DIALECT-03 显式路由；Phase 11 接入 FlinkGrammar 不改入口 |
| `ServerState.profile` 全局字符串（`lsp/handlers.mbt:6`） | document 级 `{dialect, profile}` + workspace 默认 + languageId 映射 | Phase 9 | D-01/D-02/D-03；stale-response 防护 |
| `doris.*.v1` / `DORIS-*` / `doris_*_v1` / `doris-sql`/`doris-lsp` | `fathom.*.v1` / `FATHOM-*` / `fathom_*_v1` / `fathom-sql`/`fathom-lsp` | Phase 9（D-06/D-09/D-10） | 单一中立产品身份；无 alias |
| 内联 assert 测试（无快照文件） | `@test.T::snapshot` baseline（`__snapshot__/`） | Phase 9（D-08） | 字节级回归门禁；Phase 12 PARITY-01 的对比基准 |

**Deprecated/outdated:**
- `moon.mod.json`/`moon.pkg.json`：自 v0.10.4 deprecated 并计划移除，仓库已用新 DSL（模块名/包名/export 迁移只在 `.mod`/`.pkg` 上进行）。
- `options(link: true)` 布尔形态与 `"is-main": true`：被 `pkgtype(kind: ...)` 取代（官方 package.html；`binding/moon.pkg` 已用 `foreign_library` + `link: { js/wasm }` 对象形态）。
- 后端 `exports` link 配置：官方建议新 export 优先 `#export_name`；但 `binding/moon.pkg` 的 js/wasm `exports` 列表当前仍在用，改名时必须与 `#export_name` 同步（不可只改一处）。

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Phase 9 内 `flink` 作为合法 dialect 值全链可用，但所有 Flink profile 返回结构化「未知 profile」错误（Phase 10 才锁定 `flink-2.3.0` 等），Flink 语句路由为显式 not-implemented 诊断 | §4.3、Open Question 1 | 若用户/评审希望 Phase 9 接受某个占位 Flink profile，需要讨论确认；反之若 Flink mode 静默返回「空文档」，会违反 DIALECT-03 的显式拒绝 |
| A2 | LSP 的「文档级显式配置」通过 `workspace/didChangeConfiguration` + `initializationOptions` 扩展 + 客户端显式 languageId 映射承载（LSP 3.17 无标准 per-document dialect 字段） | §4.2 | VS Code/IntelliJ 具体传输形态需真实宿主 smoke；实现前需与 host 约定字段名 |
| A3 | VS Code/IntelliJ 配置键采用 `fathom.dialect`/`fathom.profile`（及语言作用域覆盖），JetBrains state 名 `fathom.xml` | §6.6 | 配置键是公共契约（NAME-03），改名成本高；命名需在实现前确认 |
| A4 | `fathom_parse_v1(raw, dialect, profile, mode)` 参数顺序为 dialect 在 profile 前（与 CLI `--dialect --profile` 一致） | §6.3、Open Question 2 | ABI 顺序是公共契约，发布后不可改；实现前需确认 |
| A5 | 已发布的 GitHub Release v0.1.0（`doris-lsp-*` 资产）保持原名，新 release 用 `fathom-lsp-*` | §Runtime State Inventory | 若用户要求历史 release 改名（GitHub 不允许重命名已发布资产），需记录替代方案 |
| A6 | `DorisProfile`/`DorisFeature`/`ValidatedProfileContext` 类型名保留在 `dialect/doris.mbt`，`ClassificationKind` 保留在 token 或 dialect 公共层 | §4.1（D-05） | D-05 已锁定类型名；仅「放哪个文件/包」是自由度 |
| A7 | baseline 快照放入 `parity/` 包扩展（而非新 `baseline/` 包） | §9.2 | 放置位置是工程选择；若放在新包需新增 moon.pkg + CI 包列表 |
| A8 | `moon.mod` version 保持 `0.1.0` 或按 v2.0 里程碑决定 bump | §6.1、Open Question 7 | SemVer 决定 npm/GitHub release 兼容语义；需在发布前确认 |
| A9 | 命名 gate 的 `scripts/check_naming.py` 只扫描 product 文件（源码/配置/CI/扩展/文档）；豁免按 §7.2 细粒度列表（`corpus/**` provenance、`milestones/v1.0-*`、`.planning/milestones/**`、`.planning/research/**`、`.planning/phases/**` 历史文档、ROADMAP/REQUIREMENTS 归档段、构建产物），不整目录豁免 `.planning`（D-04 只豁免归档） | §7.2（D-04） | 已按 checker I-2 收窄：ALLOWLIST_PATHS 与 §7.2 一致，现行（非归档）`.planning` 内容按 product 规则扫描；A9 原「`.planning/**` 全豁免」表述作废 |

## Open Questions (RESOLVED)

> 全部 8 个开放问题已在规划中解决（adoption 位置见各条 RESOLVED 标记）：OQ1→09-02 Task 1/2（FATHOM-PARSE-008）、OQ2→09-02（A4 参数序）、OQ3→09-02/09-05/09-06（FATHOM-SCHEMA-007）、OQ4→09-05（fathom_dialect_v1）、OQ5→09-02（context 化）、OQ6→09-06/09-07（sql languageId）、OQ7→09-04（version 0.1.0）、OQ8→09-04/09-07（仓库名保留）。

1. **Flink 在 Phase 9 的 profile/grammar 表面**
   - What we know: DIALECT-01 要求 flink 可选；D-05 要求新增 `FlinkProfile`；Phase 10 才锁定 `flink-2.3.0`/`2.1.3`/`1.20.5`；Phase 11 才实现 grammar。
   - What's unclear: Phase 9 的 `flink` 请求返回什么——(a) 所有 profile 结构化拒绝（推荐，A1）；(b) 接受 `flink-dev` 占位 profile；(c) 空 enum `FlinkProfile`（MoonBit 空 enum 的匹配语义需 probe）。
   - Recommendation: (a)。`flink` 作为合法 dialect 值全链可传，profile 校验全部拒绝直到 Phase 10；`parse_flink_segment` 返回稳定 `FATHOM-PARSE-00N` not-implemented 诊断。planner 需在 Wave 0 定 code 号（建议预留 `FATHOM-PARSE-008`）。
   - **RESOLVED:** (a) 采纳 — 09-02 Task 1 checkpoint 确认 + Task 2 tracer 实现 `FATHOM-PARSE-008`（09-01 approved-changes.md 已记录 mint）；flink profile 校验 Phase 9 全部拒绝。
2. **`fathom_parse_v1` 等 binding export 的 dialect 参数位置**
   - What we know: 现状 `doris_parse_v1(raw, profile, mode)`（`binding/exports.mbt:26`）。
   - What's unclear: `(raw, dialect, profile, mode)`（推荐，与 CLI 顺序一致）还是 `(raw, profile, dialect, mode)`。
   - Recommendation: dialect 紧跟 raw 之后；与 `ParseOptions::new(dialect_id, profile_id, mode_id)`、CLI `--dialect ... --profile ...` 全链一致（A4）。
   - **RESOLVED:** A4 参数序采纳 — `fathom_parse_v1(raw, dialect, profile, mode)`，dialect 紧跟 raw；09-02 Task 1 checkpoint option-a + Task 2 tracer，api/CLI/binding 全链一致。
3. **冲突选择的错误变体形态（D-01 同源冲突）**
   - What we know: `ParseError` 现有 `UnknownProfile`/`UnknownMode`（`api/api.mbt:48-62`）；LSP/CLI 各自的错误面存在。
   - What's unclear: 冲突（如 document 配置 `doris` vs languageId 映射 `flink` 同一来源）是新增 `ParseError::ConflictingSelection` 变体，还是复用 schema 的 `FATHOM-SCHEMA-00N` code + 消息。
   - Recommendation: 在 `api` 增 `ConflictingSelection`（结构化字段带两个来源），binding 映射新 code（如 `FATHOM-SCHEMA-007`）；LSP 在 initialize/didChange 拒绝并返回结构化错误。
   - **RESOLVED:** `ParseError::ConflictingSelection` + `FATHOM-SCHEMA-007` 采纳 — 09-02 Task 2（api 变体）、09-05 Task 1（code 映射）、09-06 Task 3（LSP 错误面）。
4. **`doris_profile_v1` 的去留（D-09 只列 parse/format/error/capabilities）**
   - What we know: `doris_profile_v1`（`binding/exports.mbt:74-75`）现返回 `doris.profile.v1`（`schema.mbt:154`）。
   - What's unclear: 改成 `fathom_dialect_v1`（返回 dialect 列表 + per-dialect profiles）还是并入 `fathom_capabilities_v1`。
   - Recommendation: 改为 `fathom_dialect_v1(dialect)`（返回该 dialect 的可用 profiles + 版本元数据），capabilities 返回全局列表；ARCHITECTURE.md 也建议 `fathom_dialect_v1`。
   - **RESOLVED:** `fathom_dialect_v1(dialect)`（per-dialect）+ `fathom_capabilities_v1()`（全局列表）采纳 — 09-05 Task 1。
5. **parser 层 Doris 便捷入口的去留**
   - What we know: `parse(source, profile : DorisProfile, mode)` / `parse_with_limits(source, profile, ...)`（`parser/parser.mbt:3531-3556`）被 test 包大量调用（`ValidatedProfileContext|DorisProfile` 共 93 处引用，集中在 token/parser/api）。
   - What's unclear: 全部改 context（推荐，Pitfall 1 要求无参数公共查询消失）还是保留 Doris-only 便捷重载。
   - Recommendation: 全部改为 `context : DialectContext`；test 包调用同步更新。D-05 保留的是类型名，不是 profile 参数形态。
   - **RESOLVED:** 全部 context 化采纳 — 09-02 Task 2（parser/api 入口）+ Task 3（test 包调用点 sweep，含 lsp/handlers.mbt 机械更新）。
6. **VS Code/IntelliJ 语言 ID 与 dialect 的关系**
   - What we know: 现状 languageId `doris` + `.sql` 扩展（`vscode/package.json:20-32`）；D-01/D-02 禁止 languageId 隐式兜底。
   - What's unclear: 中立后是单一 `sql` languageId + 显式配置选 dialect，还是 `doris`/`flink` 两个 languageId（用户显式映射时 languageId 才参与）。
   - Recommendation: 单一中立 languageId（如 `sql`）+ `fathom.dialect` 配置 + 可选的 languageId→dialect 显式映射表；真实宿主 smoke 确认（Phase 13 验证）。
   - **RESOLVED:** 单一中立 `sql` languageId + `fathom.dialect` 配置 + 可选显式映射采纳 — 09-06 Task 3（language_mapping 仅用户配置时参与）、09-07 Task 1 checkpoint + Task 2（vscode/web）；真实宿主 smoke 延后 Phase 13。
7. **module version bump（v2.0 发布语义）**
   - What we know: `moon.mod` version `0.1.0`；schema namespace 从 `doris.*.v1` → `fathom.*.v1` 是破坏性公共契约变更（D-06/D-09 one-way）。
   - What's unclear: 是否 bump `0.2.0`/`1.0.0`，以及 CLI/扩展 version 对齐。
   - Recommendation: 与 release 规划一起决定；至少 module/CLI/extension version 保持一致并记录在发布 manifest。
   - **RESOLVED:** 本阶段 version 保持 `0.1.0`，bump 交由 release 规划决定 — 09-04 Task 1 checkpoint（为 release manifest 记录）。
8. **GitHub release 仓库名 `tchivs/doris-sql-parser-sdk`（`DorisNativeDownloader.kt:268`）**
   - What we know: JetBrains 下载器按该 repository 名拉取 release 资产；仓库重命名会改变 URL 路径。
   - What's unclear: 是否随产品改名为 `tchivs/fathom-sql-parser-sdk`（GitHub 重命名会 301 旧 URL，旧 release 资产保留）。
   - Recommendation: 与用户确认仓库重命名；若改名，`DEFAULT_REPOSITORY` 与 README 同步更新，旧 URL 301 兜底。
   - **RESOLVED:** 本阶段仓库名 `tchivs/doris-sql-parser-sdk` 保持不变（GitHub 重命名是用户操作），命名 gate 将其 allowlist 为仓库标识 — 09-04 Task 1 checkpoint + 09-07 Task 4。

## Environment Availability

> 本阶段无网络/服务依赖（全部离线可构建）；下列为已探测的工具与宿主构建环境。

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `moon`/`moonc` | 核心构建/测试/快照 | ✓ | moon 0.1.20260724 / moonc v0.10.5+5e7afb0c0（`moon --version`） | CI 安装 `latest` 并记录版本 |
| Node.js / npm | web、vscode 扩展构建与测试 | ✓ | v25.2.0 / 11.6.2 | — |
| Python 3 | `check_keywords.py`、新 `check_naming.py`、corpus 工具 | ✓ | 3.9.23（stdlib only） | — |
| git | 仓库操作、`git mv` 重命名 | ✓ | 2.47.3 | — |
| web/node_modules + vscode/node_modules | Web/Monaco、VS Code 构建 | ✓ | 已安装（离线 npm cache 锁定：monaco-editor、vscode-languageclient、@vscode/vsce） | `npm install`（离线 cache） |
| JDK（JetBrains 构建） | `./gradlew build`（IntelliJ plugin） | ⚠️ 本机 java 1.8.0_381 | — | CI 用 temurin 21（`jetbrains-plugin.yml` setup-java）；本地 gradle wrapper 可能需自动下载 toolchain；JetBrains 构建以 CI 为准 |
| `@vscode/test-electron` 宿主验证 | VS Code 真实宿主 smoke | 需宿主机器（Phase 4 已人工验证一次） | VS Code 1.132.0（历史记录） | `vscode/scripts/host-verify.mjs` 按需重跑 |

**Missing dependencies with no fallback:** none（本阶段全部依赖可用；JetBrains 本地 JDK 版本不匹配有 CI 兜底）。

## Security Domain

> `security_enforcement: true`（.planning/config.json:46）——本阶段虽无网络/凭据，但 dialect 选择是新的攻击面（错误方言接受 = 错误有效性判定）。

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | 无认证面（纯前端库 + stdio LSP） |
| V3 Session Management | no | 无会话；LSP document version 单调性（`lsp/documents.mbt:13-39`）即状态一致性控制 |
| V4 Access Control | no | 无资源/角色 |
| V5 Input Validation | **yes** | dialect/profile/mode 闭合枚举 + 结构化错误（`UnknownDialect`/`UnknownProfile`）；每个边界（API/CLI/LSP/JS-Wasm/Web/VS Code/IntelliJ）独立校验，禁止隐式默认（D-02/D-11） |
| V6 Cryptography | no | 无加密需求（离线解析；发布资产 SHA-256 manifest 属完整性而非加密） |

### Known Threat Patterns for {stack}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| 方言混淆注入：攻击者控制 dialect/profile 字符串诱导以错误方言接受/拒绝输入 | Tampering | 闭合 `Dialect` enum + `validate_dialect_profile`（`binding/schema.mbt:29-35` 泛化）；未知/缺失/冲突全结构化拒绝；结果携带实际 selection metadata（DIALECT-04） |
| 旧 dialect 的 stale LSP 结果覆盖新文档 | Spoofing / DoS | `Document.dialect/profile` + version 单调守卫（D-03）；completion stale 检查模式（`lsp/handlers.mbt:253-257`）推广到 diagnostics/format |
| 命名 gate 绕过：新旧身份并存导致消费方按旧 schema 解析 | Tampering | NAME-04 CI gate（§7）+ 无 alias 政策（D-06）；`#export_name` 与 moon.pkg exports 同步（Pitfall 8） |
| unknown Flink keyword 降级为 identifier 造成错误接受 | Tampering | dialect-local inventory + 显式 unknown/error 节点；Phase 9 内 Flink 全拒绝（A1），Phase 10 起独立 inventory（PITFALLS.md Security Mistakes） |

## Validation Architecture

> **SKIPPED** — `.planning/config.json:39` 显式 `"nyquist_validation": false`。验证架构（Test Framework / Phase Requirements → Test Map / Sampling Rate / Wave 0 Gaps）按配置豁免。本阶段验证策略以 §9 baseline 快照门禁（D-07/D-08）与 §7 NAME-04 gate 取代；测试仍沿用仓库既有 `moon test --target native --package test --package parity --package lsp --package api ...`（`ci.yml` test 作业）矩阵。

## Sources

### Primary (HIGH confidence — 本 session 直接读取核验)

**In-repo（迁移依据，全部 `[VERIFIED: 路径:行]`）：**
- `moon.mod:5` — 模块名 `fathom/doris-sql`；`moon version` 输出 `moon 0.1.20260724` + `rr_moon_mod,rr_moon_pkg`
- 全部 16 个 `moon.pkg`（api/token/lexer/parser/syntax/source/printer/formatter/completion/analyzer/binding/lsp/doris-sql/parity/test/根）— import 路径、pkgtype、binding js/wasm exports 列表（`binding/moon.pkg:14-28`）
- `token/token.mbt:3-6,18-27,30-33,133-141,144-196,221-236,271-287,307-447,450-494,510-538` — DorisProfile/ProfileMetadataError/ValidatedProfileContext/DorisFeature/FeatureMetadata/token_bytes_equal_ci/ClassificationKind/ClassificationEntry/classification_rows/查找 API/Token/TokenStream
- `lexer/lexer.mbt:134-155,167-203,250,378` — push_token profile 复制、lex_with_limit/lex 签名
- `parser/parser.mbt:100-135,1149-1152,1319-1377,3122-3169,3327-3385,3430-3537,3531-3556` — ParsedDocument/RecoveryState/parse_query/parse_segment/finish_statement/unsupported_statement/parse_with_limits_context/parse 便捷入口
- `api/api.mbt:2-6,8-13,42-62,64-82,84-104,106-135,137-160,162-205,273-310,313-337,342-350,364-453,458-503,520-575` — ParseMode/ParseLimits/ParseOptions/ParseError/构造器/PrimitiveNode/PrimitiveDiagnostic/ParseResult/parse 系/format 系/statement 系/内嵌测试
- `binding/exports.mbt:25-82`、`binding/schema.mbt:3-5,7-13,29-35,43-49,61-72,69-86,99-107,107-127,131-146,148-160,162-176` — export/schema/code/消息全量
- `lsp/handlers.mbt:4-10,36-50,78-90,144-161,164-170,248-283,287-310`、`lsp/documents.mbt:3-39`、`lsp/protocol_test.mbt`、`lsp/diagnostics_formatting_test.mbt:2-19` — ServerState/Document/initialize/parse/format/completion/测试
- `doris-sql/args.mbt:8-19,22-34,40-42,125-127`、`doris-sql/run.mbt:24,79,144-155`、`doris-sql/main.mbt`、`doris-sql/moon.pkg:2-3`、`doris-sql/cli_test.mbt:22-31` — CLI 全部
- `completion/completion.mbt:44-51,131-176`、`formatter/case.mbt:5-27`、`formatter/format.mbt:6-9,127-137`、`formatter/error.mbt` — completion/formatter
- `vscode/package.json:1-2,15-17,20-32,33-55,56-60`、`vscode/src/extension.ts:20-24,33-37,44-52`、`vscode/src/extension-contract.ts:1-8` — VS Code
- `web/package.json:1-4`、`web/index.html:6-7,18-19,26-27`、`web/src/monaco-adapter.ts:3,16-22,76-100`、`web/src/main.ts:12-16,26-31`、`web/src/main.test.ts:16-26` — Web/Monaco
- `jetbrains/.../DorisLanguageServerFactory.kt:8,40-43`、`DorisSettings.kt:8-11,20-22,42-47`、`DorisSettingsConfigurable.kt:11-24`、`DorisNativeDownloader.kt:46-58,268-270,305-315`、`build.gradle.kts:4-7,22-25`、`settings.gradle.kts:12`、`scripts/source-smoke.py:44-48,53-56,62-71,89-101` — IntelliJ
- `.github/workflows/ci.yml`、`doris-native-release.yml:2,93-107`、`jetbrains-plugin.yml:44-46` — CI/release
- `parity/export_smoke_test.mbt:4-21`、`parity/schema_test.mbt:15-18`、`parity/moon.pkg:7-11`、`parity/fixtures/lsp-tracer.json:1-2,11-12` — parity
- `corpus/manifest.tsv:1-14`、`corpus/tools/check_keywords.py:10-13,23-27,56-90` — corpus/provenance
- `docs/API.md:5,11-12,27-28`、`docs/CONFIGURATION.md:17-20,43-61`、`docs/GETTING-STARTED.md:14,49,66`、`README.md:35-39,49-51` — 文档命名
- `.planning/config.json:39,46` — nyquist_validation=false / security_enforcement=true

**MoonBit 官方文档（本 session 直接读取）：**
- [Module Configuration — MoonBit v0.10.6](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html) — 模块名合法字符、`name = "user/example"`、moon.mod 新 DSL
- [Package Configuration — MoonBit v0.10.6](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html) — 包名=目录名、`pkgtype`、`#export_name`、link/exports、supported_targets、test import
- [Writing Tests — MoonBit v0.10.6](https://docs.moonbitlang.com/en/latest/language/tests.html) — `@test.T::snapshot`/`__snapshot__`/`moon test --update` 快照机制

**Planning/研究输入：**
- `.planning/phases/09-.../09-CONTEXT.md` — D-01..D-11（用户锁定决策，本文件 User Constraints 逐字复制）
- `.planning/REQUIREMENTS.md` — DIALECT-01..04 / NAME-01..04
- `.planning/ROADMAP.md` — Phase 9 Goal/Success Criteria/Validation
- `.planning/STATE.md` — v1.0 历史决策、GitHub Releases doris-lsp 交付、moon.mod label 披露
- `.planning/research/ARCHITECTURE.md`、`SUMMARY.md`、`STACK.md`、`FEATURES.md`、`PITFALLS.md` — 阶段前研究（本文件架构/陷阱判断的部分依据，以本 session 仓库核验为准）

### Secondary (MEDIUM confidence)
- `.planning/milestones/v1.0-REQUIREMENTS.md`、`v1.0-ROADMAP.md` — 历史归档（D-04 豁免对象，未作为现行契约）
- `docs/TESTING.md`、`docs/DEVELOPMENT.md` — 测试/开发流程文档（命名迁移覆盖范围，未逐一核实行号）

### Tertiary (LOW confidence / validation required)
- 本文件 §Assumptions Log A1-A9 与 §Open Questions 1-8 — 需 planner/discuss 确认的产品决策
- LSP 3.17 per-document 配置传输形态（A2）— 需真实 VS Code/IntelliJ smoke（Phase 13）

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — 零新增外部包；MoonBit 重命名/export/快照机制由官方文档直接核验 + 仓库 probe 注释佐证
- Architecture: HIGH — 仓库耦合点（token/lexer/parser/api/binding/lsp/CLI/宿主/CI）全部本 session 打开核验并逐字引用；dialect 层设计沿用研究阶段 ARCHITECTURE.md 结论
- Pitfalls: HIGH — 8 条陷阱每条都有定义点/调用点证据；回归严重度由 §9 baseline 门禁量化

**Research date:** 2026-08-06
**Valid until:** 2026-09-05（稳定仓库 + 官方文档线；若 MoonBit 工具链或仓库结构大改需重核）

---
*Phase: 9-Dialect Boundary and Neutral Naming*
*Research completed: 2026-08-06*
