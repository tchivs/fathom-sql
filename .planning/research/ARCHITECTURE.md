# Architecture Research

**Domain:** MoonBit 无损、多方言 SQL CST parser 与编辑器工具链（Fathom v2.0）  
**Researched:** 2026-08-06  
**Confidence:** HIGH（现有 Doris 代码边界与迁移方向）；MEDIUM（Flink 的具体版本语法，需在 Flink grammar 阶段以选定版本文档冻结）

## 结论摘要

Fathom v2.0 应在 `source` 与 `token` 之间增加一个无运行时副作用的 `dialect` 层。该层只负责 `Dialect`、方言 profile、版本元数据、关键字分类和 feature capability；它不依赖 parser、API、LSP 或任何宿主。`token` 保留 token/trivia/span 数据结构，`lexer` 共享扫描和 source-backed 叶子机制，但通过 `DialectContext` 选择 Doris/Flink 的词法策略；`parser` 共享文档分段、CST、Pratt 基础、进度保证和恢复预算，并把 statement/clauses 路由到方言 grammar。

当前实现的核心事实是：`DorisProfile`、`DorisFeature` 和唯一的 `classification_rows` 全在 `token/token.mbt`（`token/token.mbt:3-7,133-141,268-447`）；lexer 只接收该 profile 并将其复制到每个 token（`lexer/lexer.mbt:134-152,250-275`），实际 reserved/contextual 判断由 parser 通过 token helper 完成（`token/token.mbt:449-494`）。parser 仍是单一 Doris grammar，`parse_segment` 根据首词直接分派（`parser/parser.mbt:3327-3370`）。因此迁移的正确切口不是为 Flink 复制整个 parser，而是先把 profile/keyword/dispatch 变为显式 dialect policy，再保持 source/CST/recovery 的不变量。

产品层应一次性改为 `fathom-sql`、`fathom-lsp`、`fathom/sql`、`fathom.*.v1` 和 `FATHOM-*`，不提供旧名兼容别名。Doris 作为**方言标识和语法事实**必须保留：`Dialect::Doris`、`DorisProfile`、Doris feature/官方来源/fixture metadata 仍使用 Doris；但产品包名、二进制名、schema 前缀、diagnostic namespace、LSP source、编辑器设置和文档标题不再以 Doris 命名。这样能让一个 transport 同时承载 Doris 与 Flink，又不会把 Doris 语法身份抹掉。

---

## Standard Architecture

### System Overview

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ Host / Product adapters                                                       │
│  fathom-sql CLI       fathom-lsp      VS Code      IntelliJ      Web/Monaco   │
│  file/stdin + exit    JSON-RPC/stdio  LanguageClient  LSP4IJ      JS/Wasm     │
└───────────────┬──────────────┬──────────┬──────────────┬──────────────┬───────┘
                │              │          │              │              │
                └──────────────┴──────────┴──────────────┴──────────────┘
                                       │ primitive FATHOM schema
┌──────────────────────────────────────▼───────────────────────────────────────┐
│ api/                                                                          │
│ DialectOptions / ParseResult / FormatResult / limits / mode / schema facade  │
└──────────────────────┬───────────────────────────────┬───────────────────────┘
                       │                               │
              ┌────────▼────────┐             ┌────────▼────────┐
              │ parser/         │             │ formatter/       │
              │ document +      │             │ shared layout +  │
              │ recovery core   │             │ dialect policy   │
              └────────┬────────┘             └────────┬────────┘
                       │                               │
       ┌───────────────▼───────────────────────────────▼───────────────────────┐
       │ Dialect-aware grammar                                                   │
       │ ┌──────────────────────────┐       ┌─────────────────────────────────┐ │
       │ │ DorisGrammar              │       │ FlinkGrammar                    │ │
       │ │ SELECT/DML/DDL + profiles  │       │ SELECT/DML/DDL + Flink profiles │ │
       │ └─────────────┬────────────┘       └───────────────┬─────────────────┘ │
       └───────────────┼────────────────────────────────────┼───────────────────┘
                       │                                    │
┌──────────────────────▼────────────────────────────────────▼──────────────────┐
│ lexer/ + token/ + dialect/                                                     │
│ shared scanner, spans, trivia, TokenKind; per-dialect lexical policy/tables   │
└──────────────────────┬────────────────────────────────────┬───────────────────┘
                       │                                    │
┌──────────────────────▼────────────────────────────────────▼───────────────────┐
│ source/ + syntax/                                                              │
│ owned source bytes, checked half-open byte spans, immutable CST, error leaves  │
└──────────────────────────────────────────────────────────────────────────────┘

Optional side path (never feeds back into parser validity):
syntax view + caller source bytes + DialectContext + Catalog → analyzer results

Editor path:
LSP UTF-16 position ↔ source byte offset → completion/formatter/parser → FATHOM LSP values
```

**关键约束：** 所有宿主调用同一个 `api`；没有 Doris/Flink 两套 CST 或 JS/Native 两套 parser。只有 dialect-specific policy/grammar/formatter hooks 可以分叉。source bytes 只在 result envelope 持有一次，CST 叶子仍只有 span；这延续 `api.ParseResult` 当前的 root-owned source contract（`api/api.mbt:180-193,273-310`）和 binding 的 primitive JSON boundary（`binding/exports.mbt:1-7,25-82`）。

### Layer placement: Dialect hierarchy

推荐新增如下层次：

```text
source
  ↓  （不依赖任何 SQL 方言）
dialect  ← Dialect, DialectContext, profiles, KeywordTable, feature capability
  ↓
token    ← TokenKind, Token, TokenStream, trivia/span; 持有 DialectContext
  ↓
lexer    ← 通用扫描器 + DorisLexPolicy / FlinkLexPolicy
  ↓
syntax   ← 方言中立 CST node/leaf kinds；只保存结构和 source spans
  ↓
parser   ← shared document/recovery/Pratt + DorisGrammar / FlinkGrammar
  ↓
api      ← public options/result/error/formatter facade
  ↓
binding / lsp / completion / analyzer / CLI / formatter hosts
```

`dialect/` 应是低层 policy package，而不是 parser 内的 `match` 常量集合：

```moonbit
pub enum Dialect { Doris; Flink }

pub struct DialectContext {
  pub dialect : Dialect
  pub profile_id : String
  pub exact_release : String
  pub feature_introduction : String
}

pub struct KeywordEntry {
  pub word : Bytes
  pub classification : ClassificationKind
  pub introduced_profile : String
  pub source : String
}

pub fn classification_of(context : DialectContext, raw : Bytes) -> KeywordEntry?
pub fn is_clause_keyword(context : DialectContext, raw : Bytes) -> Bool
pub fn supports(context : DialectContext, feature : FeatureId) -> Bool
```

实际实现可在 `dialect/doris.mbt` 保留 `DorisProfile`、`DorisFeature`，在 `dialect/flink.mbt` 增加 `FlinkProfile`、Flink feature IDs；`DialectContext` 是两者进入 parser/API 的统一值。不要把两套 keyword 数组合并成一张全局 union：同一个词在 Doris 与 Flink 中可能是 reserved、non-reserved 或 contextual 的不同类别。`classification_rows` 应拆为 `doris_classification_rows` 和 `flink_classification_rows`（若确有相同词，仍分别拥有 row/source/profile metadata）；共享的只是 `KeywordEntry` 结构与 ASCII case-insensitive lookup 算法。

`token.Token` 的 `profile : DorisProfile` 应迁移为 `context : DialectContext`（或不可变的 `Dialect` + profile id），`TokenStream` 同样保存 context。这样 parser、completion、formatter 不会在 token 层再次猜测 dialect；lexer 的扫描器仍可共享，但 identifier quote、comment、numeric literal、multi-character operator 等策略由 context 选择。当前 lexer 将 profile 复制到每个 token 的证据是 `lexer/lexer.mbt:134-152,167-203,250-275,370-379`。

### Component Responsibilities

| 组件 | v2 职责 | 共享部分 | 方言专属部分 |
|---|---|---|---|
| `source/` | 原始 bytes、checked half-open byte span、line index | 全部共享 | 无 |
| `dialect/`（新增） | `Dialect`、profile/context、分类表、feature gate、dialect metadata | `ClassificationKind`、entry lookup 契约 | Doris/Flink rows、release/profile、feature availability |
| `token/` | token/trivia kind、source span、TokenStream、分类查询代理 | TokenKind、Token/Stream 内存形状 | `context` 和 dialect-aware classification |
| `lexer/` | 保留 trivia 的同步 scanner、词法诊断、token cap | 消费/进度保证、span、invalid UTF-8、source-backed error | quote/comment/identifier/operator 规则、Flink keyword-sensitive lexical modes |
| `syntax/` | immutable CST、leaf/token/trivia/error/skipped/missing | node kinds、source order、span/replay invariant | 只有必要的新增通用 node kind；不放 Doris/Flink semantic state |
| `parser/` | document 分段、statement IDs、Pratt、recovery、CST 构造 | 分号分段、root assembly、progress guards、limits、strict/editor | grammar dispatch、statement families、clause sync sets、profile feature gates |
| `formatter/` | lossless/canonical output、six options、safe refusal | flat leaf walk、measure-then-break、comment/trivia、idempotence | keyword table、clause/list layout、dialect-specific canonical spacing |
| `analyzer/` | syntax-only catalog/name resolution side channel | `Catalog` trait、source bytes + syntax view、no parser import | target-table extraction、dialect-specific identifier rules/semantic checks |
| `completion/` | bounded syntax-only candidate list | cursor byte range、context ranking、max candidates | candidate table、profile gating、dialect clause contexts |
| `api/` | cross-package stable typed facade | parse/format modes, limits, primitive nodes/diagnostics | dialect/profile validation and envelope metadata |
| `binding/` | JS/Wasm/native primitive UTF-8 JSON ABI | bytes-only exports、schema validation、source bytes once | dialect/profile request fields and capabilities list |
| `lsp/` | JSON-RPC stdio、document lifecycle、diagnostic/format/completion mapping | framing, UTF-16 conversion, document store, lifecycle | dialect negotiation, FATHOM source/codes, per-dialect capabilities |
| `fathom-sql` | file/stdin, parse/format/lsp subcommands, exit codes | thin IO adapter over API | `--dialect doris|flink`, profile selection |

### Shared versus dialect-specific grammar layout

| 语法/功能 | 共享设计 | Doris 专属 | Flink 专属 |
|---|---|---|---|
| SELECT skeleton | `parse_query_core`、projection/from/where/group/having/order/limit/union 的公共骨架和 source-backed CST | Doris hints、`PARTITION`/`TABLET`/`SAMPLE`、`INTO OUTFILE`、`QUALIFY` profile gate | Flink streaming/table clauses、窗口/水位线/连接等以选定 Flink 版本 grammar 定义 |
| 表达式 | 一个 Pratt precedence engine、literal/identifier/parentheses/call/postfix/recovery | Doris operators/functions/feature words | Flink operators/functions/interval/time semantics；若 precedence 不同，使用 policy table，不复制 engine |
| CTE | `parse_cte_prefix` 的 comma/parenthesis/recovery 骨架可共享 | 当前 `WITH RECURSIVE` 明确报 feature diagnostic（`parser/parser.mbt:1319-1355`） | 是否允许 recursive/materialized/streaming CTE 由 Flink grammar/profile 决定 |
| statement entry | `parse_document` 统一分号切分、statement_id、root children | Doris `INSERT/UPDATE/DELETE/MERGE/CREATE` 分派和 DDL | Flink statement starters、`WITH` lookahead 和 DDL/DML/streaming statements |
| recovery | strict/editor、MISSING/ERROR/SKIPPED、recovery/diagnostic limits 共享 | Doris clause sync/`FATHOM-PARSE` messages | Flink clause sync/feature messages；不能共用 Doris keyword boundary |
| CST | node/leaf kind、source span、lossless replay 共享 | 仅新增必要 Doris node kinds或 metadata | 仅新增通用 SQL/streaming node kinds，避免把 dialect 名塞入每个 leaf |
| formatter layout | Layout buffer、newline、comma、measure-then-break、refusal 共享 | Doris canonical keyword/list/clause layout | Flink keyword/list/clause layout；dialect hook 在 statement family 级别 |

当前 Doris parser 已证明 SELECT、表达式、CTE 可以共用一个递归下降/Pratt 路径：`parse_select_core` 调用表达式列表、FROM、WHERE、GROUP/HAVING、WINDOW、QUALIFY、ORDER/LIMIT（`parser/parser.mbt:1149-1222`），`parse_query` 在同一路径处理 CTE 和 UNION（`parser/parser.mbt:1319-1377`）。迁移时保留这个行为，但把 `profile = cursor.stream.profile` 改为 `context`，并允许 `DorisGrammar`/`FlinkGrammar` 在共享 skeleton 的扩展点中覆盖差异。

### `parse_segment` routing

当前 `parse_segment` 的签名没有 dialect 参数，并按首 token硬编码 Doris starters（`parser/parser.mbt:3327-3370`）。v2 应改为：

```text
parse_document(source, context, mode, limits)
  ├─ lex_with_limit(source, context, limits.max_tokens)
  ├─ common semicolon segmentation / trivia segments / statement_id
  └─ parse_segment(stream, context, start, end, state)
       ├─ first significant verb = SELECT / WITH / INSERT / ...
       └─ match context.dialect
            ├─ Doris → DorisGrammar.parse_statement(...)
            └─ Flink → FlinkGrammar.parse_statement(...)
```

建议使用显式分派而不是动态反射或隐式“尝试所有方言然后取成功者”：

```moonbit
fn parse_segment(..., context : DialectContext, ...) -> SyntaxNode {
  match context.dialect {
    Dialect::Doris => parse_doris_segment(..., context, ...)
    Dialect::Flink => parse_flink_segment(..., context, ...)
  }
}
```

`WITH` 必须由每个 grammar 的 `with_prefix_verb`/statement lookahead 处理，不能假定第二个词只可能是 Doris 的 SELECT/UPDATE/DELETE/MERGE。未知 starter 继续产生显式 `Error`/`FATHOM-PARSE-007`，不能静默作为 generic identifier；现有错误节点行为见 `parser/parser.mbt:3156-3169`。`finish_statement` 的 trailing-token 消费、feature-event 替换和 Statement wrapper 保持共享（`parser/parser.mbt:3122-3153`）。

---

## Recommended Project Structure

```text
source/                         # bytes, Span, LineIndex
 dialect/                       # 新增：统一 DialectContext 与两套 policy
 ├── dialect.mbt                # Dialect, DialectContext, FeatureId
 ├── classification.mbt        # KeywordEntry/ClassificationKind/lookup API
 ├── doris.mbt                 # DorisProfile/DorisFeature/Doris rows
 └── flink.mbt                 # FlinkProfile/FlinkFeature/Flink rows
 token/                         # TokenKind, Token, TokenStream(context-aware)
 lexer/
 ├── scanner.mbt               # trivia/string/number/symbol/span 通用扫描
 ├── doris.mbt                 # Doris lexical policy
 └── flink.mbt                 # Flink lexical policy
 syntax/                        # dialect-neutral immutable CST
 parser/
 ├── document.mbt              # segmentation/root/statement ids
 ├── expression.mbt            # shared Pratt engine
 ├── recovery.mbt              # shared progress/sync/budgets
 ├── query_common.mbt          # SELECT/CTE/UNION shared skeleton
 ├── doris.mbt                 # Doris statement/clause grammar
 ├── flink.mbt                 # Flink statement/clause grammar
 └── parser.mbt                # explicit dialect dispatch/public parse
 api/                           # DialectOptions and generic FATHOM facade
 formatter/
 ├── layout.mbt                # shared layout/measure/replay
 ├── common.mbt                # shared token/trivia rules
 ├── doris.mbt                 # Doris formatting policy
 └── flink.mbt                 # Flink formatting policy
 analyzer/                      # syntax + source bytes + dialect + Catalog
 completion/                    # dialect-aware bounded syntax completion
 binding/                       # fathom_* primitive JSON ABI and schema
 lsp/                           # generic FATHOM LSP transport and handlers
 fathom-sql/                    # executable: parse/format/lsp
 parity/                        # cross-target + Doris parity fixtures
 corpus/
 ├── doris/                    # 2.1/3.x/4.x versioned fixtures
 └── flink/                    # selected Flink release fixtures
 vscode/                       # generic Fathom SQL client
 jetbrains/                    # generic Fathom SQL LSP4IJ plugin
 web/                           # generic Fathom SQL Monaco host
```

### Structure Rationale

- **`dialect/` 是唯一关键字/feature authority：** 防止 formatter、completion、parser 各自维护 keyword list。当前 formatter 已依赖 `@token.classification_of` 而不复制表（`formatter/case.mbt:1-27`）；v2 应把 authority 下移到 dialect，而不是再造第三份表。
- **`parser/query_common.mbt` 与 `parser/{doris,flink}.mbt` 分离：** 共享结构减少重复，方言专属代码仍能使用清晰的 sync set 和 feature gate。
- **`syntax/` 不拥有 dialect-specific semantic objects：** CST 只保证 source order/spans/trivia/error nodes；API envelope 才携带 dialect/profile metadata。
- **`analyzer/` 继续旁路：** 当前 analyzer 只导入 syntax，并明确禁止 parser/token/lexer/api/source 依赖（`analyzer/analyzer.mbt:1-17`、`analyzer/moon.pkg:1-4`）。新增 dialect 依赖只能用于 policy，不得让 catalog 进入 parser validity channel。
- **适配器只消费 API/binding：** LSP 当前把解析和格式化委托给 API（`lsp/handlers.mbt:1-3,78-90,164-198`），CLI 当前也是 `run_format → api.format_with_ids` 的薄层（`doris-sql/run.mbt:1-5,79-87`）；迁移应扩大 API，而不是让 LSP/CLI 直接调用 Doris/Flink grammar。

---

## Public interface and data-flow migration

### New types

| 新类型 | 所在层 | 用途 |
|---|---|---|
| `Dialect` | `dialect` | 仅包含 `Doris`、`Flink`，是所有入口的必选身份 |
| `DorisProfile` | `dialect/doris` | 保留 `2.1`、`3.x`、`4.x`，仍是 Doris 方言 profile |
| `FlinkProfile` | `dialect/flink` | 选定并冻结的 Flink release/profile；未知 profile 必须结构化拒绝 |
| `DialectContext` | `dialect` | dialect + profile + exact release + feature introduction 的不可变快照 |
| `KeywordEntry` | `dialect` | word/classification/introduction/source；每个 dialect 有独立 rows |
| `FeatureId` / `FeatureMetadata` | `dialect` | generic feature gate；DorisFeature/FlinkFeature 可作为 dialect-specific enum |
| `DialectOptions` | `api` | `DialectContext` + `ParseMode` + `ParseLimits` |
| `DialectCapabilities` | `api/binding` | 返回可用 dialect/profile/mode/target 和 schema 版本 |
| `DialectDiagnostic`（可选） | `api` | 当错误需要显式携带 dialect/profile 时使用；普通 diagnostic 保持通用字段 |

### Old → new API and data flow

| 层 | v1 现状（证据） | v2 新接口/数据流 |
|---|---|---|
| token | `DorisProfile`/`DorisFeature` 和一张 `classification_rows`（`token/token.mbt:3-7,133-141,307-447`）；`Token.profile`、`TokenStream.profile`（`token/token.mbt:510-538`） | `DialectContext` 进入 `Token`/`TokenStream`；`classification_of(context, raw)` 路由到 `doris_rows` 或 `flink_rows`；Doris 类型保留在 `dialect/doris` |
| lexer | `lex(source, DorisProfile)`（`lexer/lexer.mbt:250-279,378-379`），通用扫描但 profile 类型是 Doris | `lex(source, DialectContext)`；通用 scanner 保留 trivia/invalid bytes；`DialectLexPolicy` 选择 quote/comment/operator/identifier 细节 |
| parser | `parse_with_limits_context(source, ValidatedProfileContext, mode, limits)`（`parser/parser.mbt:3430-3537`）；`parse_segment` 单 Doris routing | `parse_with_limits_context(source, DialectContext, mode, limits)`；document/recovery 共用，`parse_segment` 显式 `DorisGrammar`/`FlinkGrammar` dispatch |
| API parse | `ParseOptions` 内藏 `@token.ValidatedProfileContext`（`api/api.mbt:42-45`）；`parse_with_ids(raw, profile_id, mode)`（`api/api.mbt:327-337`） | `DialectOptions`；`parse(raw, options)` 保留 typed path；字符串 convenience 改为 `parse_with_ids(raw, dialect_id, profile_id, mode)` 或 `parse_with_dialect`；`ParseResult` 增加 `dialect`，schema 改 `fathom.parse.v1` |
| API errors | `UnknownProfile`、`ProfileMetadataMismatch` 等均假定 Doris（`api/api.mbt:48-62`） | 增加 `UnknownDialect`；profile validation 先按 dialect 再按 profile；错误 code 为 `FATHOM-SCHEMA-*`/`FATHOM-PARSE-*` |
| formatter | `api` re-export `FormatOptions/Result`，并调用 `formatter.format(parsed.root, source, options)`（`api/api.mbt:339-345,364-415`）；keyword rewrite 读 token 表（`formatter/case.mbt:1-27`） | `formatter.format(root, source, context, options)`；shared `Layout` + dialect formatting policy；`FATHOM-FORMAT-001` refusal；keyword case 必须查 context 的表 |
| analyzer | `ColumnInfo`/`TableInfo`/open `Catalog`，只读 syntax + caller bytes，当前只识别 DML/DDL target table（`analyzer/analyzer.mbt:19-83,257-303`） | `resolve_table_references(node, bytes, context, catalog)` 或 `analyze(..., DialectContext, Catalog)`；结果带 dialect；仍不导入 parser/API，catalog diagnostics 与 syntax validity 分离 |
| completion | `complete(raw, profile_id, cursor_byte)`，直接 lex + context candidate，候选来自 token classification rows（`completion/completion.mbt:129-176`） | `complete(raw, dialect_id, profile_id, cursor_byte)`；按 context 的 dialect table、feature gate、Flink/Doris clause policy 生成 bounded items；detail 文案通用为 `SQL syntax keyword` |
| LSP | `ServerState.profile : String`，initialize 只取 `initializationOptions.profile`（`lsp/handlers.mbt:4-14,144-160,287-310`）；诊断 source=`doris`（`lsp/handlers.mbt:36-50`）；调用 `api.parse_with_ids`/`completion.complete`（`lsp/handlers.mbt:78-90,248-283`） | `ServerState.context : DialectContext`；initialize 要求 `dialect` + `profile`；parse/format/completion 全传 context；source=`fathom`，serverInfo=`fathom-lsp`，能力声明列出 dialect/profile |
| CLI | `doris-sql` executable，`format --profile`，调用 `api.format_with_ids`（`doris-sql/moon.pkg:1-11`、`doris-sql/args.mbt:19-40`、`doris-sql/run.mbt:79-87`） | `fathom-sql parse|format|lsp --dialect doris|flink --profile ...`；`--dialect` 必填或由明确产品默认策略提供，不能隐式 fallback；exit 0/1/2 语义保持 |
| binding | `doris_parse_v1`/`doris_format_v1`/`doris_profile_v1`/`doris_capabilities_v1`（`binding/exports.mbt:25-82`），只返回 UTF-8 JSON bytes | `fathom_parse_v1`/`fathom_format_v1`/`fathom_dialect_v1`/`fathom_capabilities_v1`；输入带 dialect/profile，输出 `fathom.*.v1`；继续 primitive bytes-only，禁止 MoonBit ADT/handle 越过 ABI |

### End-to-end parse flow

```text
Host text + {dialect, profile, mode, limits}
  → api validates DialectContext and limits
  → SourceText owns raw bytes once
  → lexer(shared scanner, dialect policy) emits Token/Trivia/Error spans
  → parser.parse_document segments semicolon/trivia and allocates statement_id
  → parse_segment routes to DorisGrammar or FlinkGrammar
  → shared query/Pratt/recovery + dialect clause productions
  → immutable SyntaxNode(Document → Statement → body + source leaves)
  → parser diagnostics (FATHOM-PARSE-###) + valid/recovered
  → api PrimitiveNode/ParseResult envelope (source_bytes only at root)
  → binding JSON / LSP diagnostics / CLI rendering / Web result
```

### Formatter flow

```text
api.format_text(raw, DialectOptions, FormatOptions)
  → one parse with selected dialect/mode
  → reject unsafe ERROR/MISSING/SKIPPED tree with one FATHOM-FORMAT-001
  → shared Layout reads leaf spans/trivia
  → dialect policy rewrites only matching unquoted keywords
  → measure-then-break list/layout decisions
  → FATHOM FormatResult(output, diagnostics, statement_offsets)
```

Formatter 不能把 Flink grammar 的 unknown material 当作 Doris token，也不能因为格式化成功而改变 parser 的 dialect validity。当前 refusal 和 parse diagnostics 顺序契约在 `api/api.mbt:364-415` 与 `formatter/format.mbt:3-42` 已有明确形状，应只改 namespace/context 参数。

### LSP/editor flow

```text
initialize({dialect, profile})
  → ServerState.context
  → didOpen/didChange full text → DocumentStore
  → api.parse(... Editor) → FATHOM diagnostics
  → UTF-8 byte spans → binding coordinate helper → LSP UTF-16 ranges
  → completion(text, dialect, profile, cursor_byte)
  → formatting(text, context, strict) → WorkspaceEdit
```

LSP transport、UTF-16 和 document version 检查是共享边界；语法选择必须只通过 context。当前 LSP 已声明 `positionEncoding=utf-16`、full sync、formatting/completion（`lsp/handlers.mbt:152-161`），v2 不应把 UTF-16 arithmetic 放进 parser。

---

## Naming migration and Doris boundary

| 旧名/位置 | 新名/策略 | Doris 保留边界 |
|---|---|---|
| `fathom/doris-sql/*` MoonBit imports | `fathom/sql/*` | `Doris` 只出现在 `fathom/sql/dialect/doris` 和 `Dialect::Doris` |
| `doris-sql` CLI/package/binary | `fathom-sql` | `--dialect doris` 是合法显式值，不是产品名 |
| `doris-lsp` binary/release asset | `fathom-lsp` | server 可处理 `Dialect::Doris`，但 executable 不以 Doris 命名 |
| `doris.parse.v1`, `doris.format.v1`, `doris.error.v1`, `doris.capabilities.v1` | `fathom.parse.v1`, `fathom.format.v1`, `fathom.error.v1`, `fathom.capabilities.v1` | envelope 的 `dialect:"doris"`、`profile:"2.1"|"3.x"|"4.x"` 保留 |
| `doris_parse_v1`, `doris_format_v1`, `doris_profile_v1`, `doris_capabilities_v1` | `fathom_parse_v1`, `fathom_format_v1`, `fathom_dialect_v1`, `fathom_capabilities_v1` | `DorisProfile` metadata 可由 `fathom_dialect_v1("doris", ...)` 返回 |
| `DORIS-PARSE-*`, `DORIS-FORMAT-*`, `DORIS-SCHEMA-*`, `DORIS-LSP-*` | `FATHOM-PARSE-*`, `FATHOM-FORMAT-*`, `FATHOM-SCHEMA-*`, `FATHOM-LSP-*` | diagnostic message/expected class 可说 “Doris feature QUALIFY”；code namespace 不保留 DORIS |
| `DorisProfile`, `DorisFeature` | 仍为 `dialect.DorisProfile`、`dialect.DorisFeature`；新增 generic `FeatureId` | 这是语法身份，不是产品品牌 |
| `doris-sql-language-client`，display “Doris SQL Language Client” | `fathom-sql-language-client`，display “Fathom SQL Language Client” | settings 用 `fathom.dialect`/`fathom.profile`，值可以是 `doris`；不再把 language id 固定为 `doris` |
| VS Code `onLanguage:doris`、`doris.restartLanguageServer`、`doris.serverPath` | `onLanguage:fathom-sql`、`fathom.restartLanguageServer`、`fathom.serverPath`，增加 `fathom.dialect` enum | `.sql` extension 仍可用；选择 Doris 后用户看到 Doris profile |
| `@fathom/doris-web-demo` | `@fathom/sql-web-demo`（或最终发布的 `@fathom/sql-web`） | Web demo 的 dialect selector 显示 Doris/Flink；描述改为 Fathom SQL facade |
| JetBrains README “Doris SQL IntelliJ Plugin”、`doris-lsp` setting/default、language id `doris` | “Fathom SQL IntelliJ Plugin”、`fathom-lsp`、`fathom.dialect`/`fathom.profile`、language id `fathom-sql` | plugin 可提供 Doris profile 选项，但插件名/id generic |
| JetBrains Gradle group `fathom.jetbrains` | 继续使用 generic group，可将 plugin/module id 迁为 `fathom.sql`/`fathom-sql-intellij` | 当前 `group = "fathom.jetbrains"` 已是中立边界（`jetbrains/build.gradle.kts:9-10`）；change notes 改为 Fathom SQL |
| 文档标题、README、release manifest、CI asset、docs URL | 全部改为 Fathom SQL/Fathom LSP；文档按 “Doris dialect” 和 “Flink dialect” 分节 | Doris 官方 URL、profile release names、feature names、fixture provenance 不能被产品重命名 |

证据显示当前 VS Code 包和设置完全 Doris-coupled：package name/display、`onLanguage:doris`、`doris.profile`、`doris.serverPath`、`doris-lsp` 均在 `vscode/package.json:2-5,15-18,20-50`；Web package/description 也写死 Doris（`web/package.json:1-13`）；JetBrains README 当前标题、设置和 language id 写死 Doris（`jetbrains/README.md:1-17`），而 Gradle 的 group 已是 `fathom.jetbrains`，只有 change notes 仍为 Doris（`jetbrains/build.gradle.kts:9-10,23-30`）。

**不做兼容别名：** 不保留 `doris_*` exports、旧 schema、旧 error code、旧 VS Code command 或旧 CLI 入口。迁移必须同步更新所有调用方、package manifests、docs、release workflows、fixture manifests、host tests；否则同一仓库会出现两个 schema authority。

---

## Architectural patterns

### Pattern 1: Explicit context, not global dialect state

**What:** 每个 parse/format/completion 调用都携带一个不可变 `DialectContext`。  
**When:** 所有 public API、LSP document、CLI invocation、Web worker。  
**Trade-offs:** 参数更多，但可重入、并发安全、snapshot 可复现；避免一个全局 profile 污染不同文档。

### Pattern 2: Shared skeleton + dialect policy hooks

**What:** `parse_document`、CST、Pratt、recovery 和 formatter layout 是共享基础；statement starters、keyword classes、sync sets、feature gates 和 clause writers 从 dialect policy 取得。  
**When:** 两个方言拥有相同结构但词汇/部分 clauses 不同。  
**Trade-offs:** 需要稳定 hook 接口；比复制 parser 初期稍慢，但能保持 Doris parity，并避免 Flink 修复漂移出共享 recovery/CST contract。

### Pattern 3: Source-backed lossless CST with primitive ABI

**What:** raw bytes 只由 `SourceText`/result root 持有；nodes/leaves 用 spans，trivia/error/skipped 保留；binding 只传 primitive UTF-8 JSON bytes。  
**When:** formatter、LSP、Web 和 Native 必须 byte-exact round-trip。  
**Trade-offs:** host 需要做 span 到编辑器坐标的转换；换来的收益是跨 backend ABI 稳定和不丢注释/空白。

### Pattern 4: Classification table as single source of truth per dialect

**What:** formatter keyword rewrite、completion candidates、parser identifier acceptance 都调用当前 context 的 `classification_of`。  
**When:** 任何 keyword/reserved/contextual 行为。  
**Trade-offs:** lookup 可能是线性扫描；v2 先保持 auditable rows，若 profiling 证明需要再为每个 dialect 建 index，但不得复制第二张语义表。

### Pattern 5: Shared recovery mechanics, dialect-specific synchronization

**What:** `advance`、recovery budget、diagnostic cap、MISSING/ERROR/SKIPPED node 共享；`is_*_clause_boundary` 和 expected classes 按 dialect/grammar family 提供。  
**When:** editor mode、半成品 SQL、多个 statement 的局部错误。  
**Trade-offs:** sync set 漏词会导致错误吞噬后续 clauses；每个新增 grammar 必须配 boundary fixtures。

### Pattern 6: Analyzer side-channel

**What:** analyzer 读取 `SyntaxNode + source bytes + DialectContext + Catalog`，输出独立结果，不改变 `ParseResult.valid` 或 parser diagnostics。  
**When:** table/column resolution、后续 lint/lineage。  
**Trade-offs:** 调用者要显式传 catalog/context；但 parser 仍可无 metadata 运行，并保持 parser → analyzer 依赖单向隔离。

---

## Scaling and operational considerations

| 规模/场景 | 架构调整 |
|---|---|
| 单文件、CLI、<1K documents | 同步 parse，单 `DialectContext`，线性 keyword rows 足够；优先保持 source/span invariant |
| 10K 编辑器文档或多 worker Web | 每文档持有 context，避免共享可变 parser；缓存 immutable dialect tables；LSP DocumentStore 按 URI/version 丢弃 stale completion |
| 大型 corpus/CI | Doris/Flink manifests 按 dialect/profile/release 分目录；跨 target 比较 serialized FATHOM schema、diagnostics 和 replay bytes |
| 百万级 SQL/长-lived LSP | 只有在 profiling 后引入 token/classification indexes、incremental parse/tree reuse；先保证 parser limits、recovery cap 和 memory ownership |

**优先级：** 先防止 dialect cross-contamination 和 source duplication；其次测量 keyword lookup、formatter layout、LSP reparse；最后才考虑 incremental CST。Tree-sitter 文档指出其 parser 是可设置 language 的 stateful object，tree 可 edit 后重新 parse（https://tree-sitter.github.io/tree-sitter/using-parsers/1-getting-started.html）；这是后续增量优化的参考，不是把 Tree-sitter runtime 引入 MoonBit core 的理由。

---

## Anti-Patterns and risks

### 1. 全局 keyword union

**错误：** 将 Doris/Flink rows 合并后由一个 `is_reserved_word` 判断。  
**后果：** 一个 dialect 的 reserved word 会错误拒绝另一个 dialect 的合法 identifier；completion 和 formatter 也会互相泄漏。  
**替代：** `classification_of(context, raw)`，两套 rows、同一 entry schema；增加每 dialect classification parity fixtures。

### 2. Parser 复制一份 Flink 全实现

**错误：** 复制 `parser.mbt` 再替换几个关键字。  
**后果：** CTE/Pratt/recovery/CST 修复无法同步，Doris parity 和 editor behavior 漂移。  
**替代：** shared document/query/expression/recovery + explicit grammar modules；只有真正不同的 production 和 sync set 放 dialect module。

### 3. 用尝试解析结果猜 dialect

**错误：** 不要求 dialect，先 Doris parse、失败再 Flink parse。  
**后果：** 接受边界不确定，错误诊断不稳定，Flink input 可能被 Doris 误接受。  
**替代：** dialect/profile 在 API、LSP initialize、CLI 入口显式必选；未知 dialect/profile 结构化拒绝。

### 4. 把 dialect 放进 syntax node 的每个 leaf

**错误：** 为每个 token 复制 Doris/Flink metadata 或 source text。  
**后果：** CST 变大，ABI/formatter 复杂，破坏 root-only source contract。  
**替代：** document/result/context 携带 dialect；leaf 只保留 kind/span/trivia/error。

### 5. 让 formatter/analyzer 直接导入某个 grammar

**错误：** formatter 或 analyzer `match DorisProfile`，绕过 API/context。  
**后果：** Flink support 不完整，parser/analyzer 依赖环重新出现。  
**替代：** formatter 使用 `DialectFormatPolicy`；analyzer 只消费 syntax/source/context；parser 仍不导入 analyzer。

### 6. 只改错误码或 package 名的一半

**错误：** binding 改成 `fathom.*`，LSP 仍发 `doris` source，VS Code 仍启动 `doris-lsp`。  
**后果：** host capability negotiation、diagnostic filters、release assets 和文档互不兼容。  
**替代：** boundary phase 建立命名清单，一次迁移 exports/schema/errors/settings/CI/docs，并删除旧路径。

### 7. 把 Flink 具体语法当作“与 Doris 基本相同”

**错误：** 只添加 Flink keywords，不建立版本化 grammar/corpus。  
**后果：** streaming/table/window/time semantics、DDL/DML 边界会被错误接受或恢复。  
**替代：** Flink lexer/keywords 单独阶段；随后 grammar 阶段先冻结 release/profile 和 unsupported diagnostics，再扩展 formatter/completion/analyzer。

### 8. 把 Tree-sitter/sqlglot 当运行时替代

**错误：** 直接把 SQLGlot AST 或 Tree-sitter generated tree 当作 Fathom CST。  
**后果：** 失去 MoonBit 单核心、source trivia contract 或跨 Native/JS/Wasm ABI 控制。  
**替代：** 将其作为结构比较/差分 oracle；Fathom 继续 handwritten recursive descent + Pratt + source-backed CST。

---

## Architecture comparison evidence

### SQLGlot

SQLGlot 的 dialect 目录本身是按文件拆分的（目录中同时有 `mysql.py`、`doris.py`、`spark.py`、`trino.py` 等）：  
<https://github.com/tobymao/sqlglot/tree/main/sqlglot/dialects>

当前 Doris 实现很薄，`Doris(MySQL)` 继承 MySQL，并只替换 `Parser = DorisParser`、`Generator = DorisGenerator`，另设日期格式常量：  
<https://github.com/tobymao/sqlglot/blob/main/sqlglot/dialects/doris.py>（读取到的源码为 `class Doris(MySQL)`、`Parser = DorisParser`、`Generator = DorisGenerator`）。

**可借鉴：** 方言入口可按文件/模块隔离，公共基类承载共享 SQL 形状。  
**不能照搬：** Fathom 的产品契约是 lossless CST、trivia、byte spans、editor recovery；因此应共享低层 parser/layout mechanics，而不是让一个通用 MySQL AST 成为接受边界，也不能以 Doris 子类继承掩盖 profile/keyword classification 差异。

### Tree-sitter

官方入门文档将 `TSLanguage`、`TSParser`、`TSTree`、`TSNode` 作为四个核心对象；parser 被设置一个 language 后生成整棵 tree，tree 可被 edit 后重新 parse，并且 nodes 跟踪 start/end positions：  
<https://tree-sitter.github.io/tree-sitter/using-parsers/1-getting-started.html>

**可借鉴：** language/parser/tree/node 的边界，以及未来 incremental tree/reparse 的演进方向。  
**不能照搬：** v2 需要 MoonBit Native 与 JS/Wasm 单实现、source trivia 与自定义 FATHOM primitive ABI；引入 generated C runtime 会增加 backend/FFI/grammar build 边界。指定的 `tree-sitter-sql` URL 当前读取为 404：  
<https://github.com/tree-sitter/tree-sitter-sql>。因此这里不把该仓库的 grammar 内容当作已核验事实；只采用可直接读取的 Tree-sitter 官方 parser model 作为架构比较证据。

---

## Build order and dependencies

严格按以下顺序实施，阶段之间以可观察的 boundary contract 连接：

### 1. Boundary + Doris parity

**依赖：** 当前 source/token/lexer/syntax/parser/api/formatter/binding/lsp/CLI。  
**产出：** 新 `dialect/`；`DialectContext` 贯穿 token → parser → API → binding/LSP/CLI；Doris rows 从 `classification_rows` 拆到 Doris module；`fathom/sql` imports、`fathom.*.v1` schemas、`FATHOM-*` errors、`fathom-sql`/`fathom-lsp` 和产品 adapter names 完成 clean cutover。  
**门槛：** Doris 2.1/3.x/4.x 的 valid/invalid/recovery、CST spans、lossless replay、formatter output、completion candidates、LSP diagnostics、CLI exit behavior 在新 dialect 字段下 byte/shape parity；不得用旧 alias 通过。

### 2. Flink lexer / keywords

**依赖：** 第 1 阶段的 `DialectContext`、generic scanner、独立 rows 和 binding schema。  
**产出：** Flink profile metadata；`FlinkLexPolicy`；Flink classification rows；quote/comment/identifier/operator 差异；lexer diagnostics 和 candidate metadata。  
**门槛：** 选定 Flink release/profile，未知 profile 拒绝；Doris rows 不被改变；相同 source 在两个 dialect 下 token classification 差异可解释、可 snapshot；所有 keyword rows 有来源和 introduced metadata。

### 3. Flink grammar

**依赖：** Flink lexer/keywords、shared CST/Pratt/recovery、Doris parity gate。  
**产出：** `parse_segment` explicit routing；Flink statement starters、SELECT/CTE/window/DDL/DML grammar；Flink-specific clause sync sets、feature diagnostics、CST kinds（只在需要时新增）。  
**门槛：** strict/editor 都保持相同 primitive shape；恢复永远前进并尊重 limits；Doris grammar 和 corpus 无回归；Flink unsupported input 产生明确 `FATHOM-PARSE-007` 或 feature diagnostic，不静默接受。

### 4. Toolchain

**依赖：** 两个 dialect 的 parser/API 结果已经稳定。  
**产出：** formatter policy、dialect-aware analyzer/completion、generic FATHOM LSP、`fathom-sql` parse/format/lsp、binding JS/linear-Wasm exports、VS Code/IntelliJ/Web generic products。  
**门槛：** 每个 host 传 dialect/profile；schema/codes/source names 全为 FATHOM；同一 fixture 的 Native/JS/Wasm serialized result 一致；LSP UTF-16 只在 adapter 层转换。

### 5. Corpus

**依赖：** 最终 grammar、formatter、adapter schema 和明确的 Flink profile。  
**产出：** `corpus/doris/{2.1,3.x,4.x}` 和 `corpus/flink/<release>` manifests；官方来源、retrieval date、revision/provenance、support status、expected diagnostics；cross-dialect differential/advisory reports。  
**门槛：** corpus 不读取网络/FE 作为 parser runtime；每个 fixture 标明 dialect/profile；Doris parity fixture 持续作为回归门；Flink known gaps 明确记录，不能用“generic SQL accepted”代替覆盖声明。

依赖图：

```text
Boundary + Doris parity
          ↓
Flink lexer/keywords
          ↓
Flink grammar
          ↓
formatter/analyzer/completion + LSP/CLI/binding/hosts
          ↓
versioned Doris/Flink corpus + cross-target/cross-dialect gates
```

---

## Integration Points

### External and reference services

| 来源 | 用法 | 限制 |
|---|---|---|
| Doris versioned official docs | Doris profile/feature/classification/corpus authority | `dev`/moving docs 不应改变已冻结 fixture；metadata 必须带 release/source |
| Doris FE/Nereids source | 可选 differential oracle | 不进入 parser runtime 或 SDK dependency |
| SQLGlot Doris dialect | advisory comparison/gap investigation | `Doris(MySQL)` 继承结构不等于 Fathom lossless CST contract |
| Tree-sitter official parser docs | parser/tree/language/incremental architecture comparison | 不作为 MoonBit runtime dependency；指定 tree-sitter-sql URL 读取失败 |
| LSP 3.17 | JSON-RPC lifecycle、UTF-16 positions、diagnostic/edit shapes | transport remains edge adapter |

### Internal boundaries

| Boundary | Communication | v2 contract |
|---|---|---|
| `source ↔ dialect` | no call; pure metadata | dialect 不依赖 source |
| `dialect ↔ token/lexer` | typed `DialectContext`/policy | no global tables; each stream carries context |
| `lexer ↔ parser` | `TokenStream` + source spans | trivia/error/truncation retained; dialect is explicit |
| `parser ↔ syntax` | immutable nodes/leaves | shared CST kinds and span bounds |
| `parser ↔ api` | `ParsedDocument` → primitive result | source once at root; FATHOM diagnostics |
| `api ↔ formatter` | typed context/options | formatter never guesses dialect |
| `syntax ↔ analyzer` | syntax view + caller bytes + context + Catalog | side-channel only; no parser import |
| `api ↔ binding` | primitive bytes/JSON | `fathom.*.v1`, explicit dialect/profile |
| `api ↔ lsp/completion/CLI` | typed public calls | host naming generic; dialect remains data |
| `lsp ↔ editor` | JSON-RPC stdio / LSP 3.17 | `fathom` source, UTF-16 ranges, dialect initialization |

---

## Evidence index (file:line)

- `token/token.mbt:3-7,30-104,133-235` — Doris profile/metadata/feature gate currently owns version semantics。
- `token/token.mbt:268-447` — `ClassificationKind`、`ClassificationEntry` 与单一 `classification_rows`；`token/token.mbt:449-494` — lookup/reserved/clause helpers。
- `token/token.mbt:510-538` — Token/TokenStream 当前携带 `DorisProfile`。
- `lexer/lexer.mbt:134-152,167-203,250-279,317-379` — source-backed scanner、invalid-byte handling、profile 参数和 token emission。
- `parser/parser.mbt:88-125,228-260` — diagnostics、limits、recovery state；`parser/parser.mbt:692-789` — shared Pratt path。
- `parser/parser.mbt:1149-1222,1319-1377` — SELECT/expressions/CTE/UNION shared path；`parser/parser.mbt:1576-1655` — per-family recovery boundary。
- `parser/parser.mbt:3122-3370` — finish/recovery/unsupported statement/`parse_segment` current Doris routing；`parser/parser.mbt:3430-3529` — common document segmentation and root assembly。
- `api/api.mbt:42-126,273-337` — current `ParseOptions`/Doris profile API；`api/api.mbt:339-448` — formatter facade and parse→format flow。
- `binding/schema.mbt:1-18,29-67,69-185` — current `doris.*.v1` schema, profile validation and `DORIS-*` codes。
- `binding/exports.mbt:1-7,25-82` — current bytes-only `doris_*` exports。
- `formatter/case.mbt:1-27` — formatter consumes token classification table；`formatter/format.mbt:3-42` — safe refusal/layout entry。
- `analyzer/analyzer.mbt:1-17,19-83,257-303` — syntax-only Catalog side channel；`analyzer/moon.pkg:1-4` — parser-independent import boundary。
- `completion/completion.mbt:1-22,44-99,129-176` — syntax-only profile-aware completion and token-table candidate source。
- `lsp/handlers.mbt:4-14,36-50,78-90,144-161,248-283,287-420` — current profile-only state, Doris source/codes, API/LSP routing。
- `doris-sql/moon.pkg:1-11`, `doris-sql/args.mbt:19-40`, `doris-sql/run.mbt:1-5,17-87` — current executable and thin format CLI。
- `vscode/package.json:2-5,15-18,20-50,53-73` — current package/language/settings/command/`doris-lsp` coupling。
- `web/package.json:1-13` — current `@fathom/doris-web-demo` and Doris description。
- `jetbrains/build.gradle.kts:9-10,23-30` — neutral group but Doris change note；`jetbrains/README.md:1-17,34-43` — plugin title, settings, language id, binary/release names。

## Sources

- [SQLGlot dialect directory](https://github.com/tobymao/sqlglot/tree/main/sqlglot/dialects) — directly readable GitHub tree; per-file dialect organization (HIGH).
- [SQLGlot Doris dialect](https://github.com/tobymao/sqlglot/blob/main/sqlglot/dialects/doris.py) — directly read raw source; `Doris(MySQL)` with `DorisParser`/`DorisGenerator` (HIGH for the observed implementation).
- [Tree-sitter Getting Started](https://tree-sitter.github.io/tree-sitter/using-parsers/1-getting-started.html) — directly readable official docs; `TSLanguage`/`TSParser`/`TSTree`/`TSNode`, parser language assignment and editable trees (HIGH).
- [指定 Tree-sitter SQL repository URL](https://github.com/tree-sitter/tree-sitter-sql) — direct read returned HTTP 404; no repository-specific claim is made from it (LOW/none).
- [Apache Doris SQL manual](https://doris.apache.org/docs/dev/sql-manual/) — current SQL sections and discovery authority, with released profile URLs frozen separately (HIGH per existing project evidence).
- [LSP 3.17 specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/) — editor transport/position contract (HIGH per existing project evidence).

---
*Architecture research for: Fathom v2.0 multi-dialect lossless SQL parser*  
*Researched: 2026-08-06*
