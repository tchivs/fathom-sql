# Phase 9: Dialect Boundary and Neutral Naming - Pattern Map

**Mapped:** 2026-08-06
**Files analyzed:** 51 个唯一目标文件（86 行迁移映射表去重后）+ 5 个新增文件
**Analogs found:** 49 / 51（其余 2 个为纯占位/数据文件，见 No Analog Found）

> 本阶段的性质：dialect 层是**新建 policy package**，命名 cutover 是**对现有文件的 clean rename**。
> 因此 analog 分两类：(1) 新文件从「同角色同数据流」的现有文件拷贝模式（下表 Match Quality = exact/role-match）；
> (2) 被改名的现有文件，其 analog 就是它自己——pattern 是「保持结构、按迁移表改名/加参」，
> 这类行标注 `self-rename`，拷贝的是文件内既有约定（import 串、错误面、快照机制）。

## File Classification

### A. 新增文件（从现有 analog 拷贝模式）

| New File | Role | Data Flow | Closest Analog | Match Quality |
|----------|------|-----------|----------------|---------------|
| `dialect/dialect.mbt` | model（policy 权威） | request-response（纯查询） | `token/token.mbt:3-41`（DorisProfile/ProfileMetadata/ValidatedProfileContext） | exact |
| `dialect/classification.mbt` | model（查找 API） | transform（lookup） | `token/token.mbt:271-494`（ClassificationKind/ClassificationEntry/classification_rows/classification_of/is_reserved_word + token_bytes_equal_ci:221-236） | exact |
| `dialect/doris.mbt` | model（数据迁移） | batch（逐行迁移） | `token/token.mbt:133-196`（DorisFeature/FeatureMetadata/metadata()） | exact |
| `dialect/flink.mbt` | model（占位） | — | `token/token.mbt:3-6`（闭合 enum 形态） | partial |
| `scripts/check_naming.py` | utility（CI gate） | batch（文件扫描） | `corpus/tools/check_keywords.py`（stdlib 校验循环） | exact |
| `parity/baseline_test.mbt` | test（snapshot） | batch（冻结） | `parity/export_smoke_test.mbt:4-21` + `parity/schema_test.mbt:15-18` + `@test.T::snapshot` | exact |
| `parity/baseline-hashes.txt` | fixture（数据） | batch | `corpus/manifest.tsv`（provenance 记录形态） | partial |
| `scripts/baseline_diff.py`（可选） | utility（diff 报告） | batch | `corpus/tools/check_keywords.py` 逐行循环 | partial |

### B. 核心 MoonBit 改造（analog = 自身，按迁移表改名/加 dialect 维度）

| Modified File | Role | Data Flow | Analog（拷贝自） | Match Quality |
|---------------|------|-----------|------------------|---------------|
| `token/token.mbt` | model | CRUD→lookup | 自身（classification_rows 拆出、查询签名加 context） | self-rename |
| `lexer/lexer.mbt` | service | streaming（tokenize） | 自身（`lex_with_limit`/`lex`/`push_token` profile→context） | self-rename |
| `parser/parser.mbt` | service | request-response | 自身（`parse_segment` 加 dialect 路由、`RecoveryState.context`） | self-rename |
| `api/api.mbt` | facade | request-response | 自身（`ParseOptions::new(dialect_id, profile_id, mode_id)`、`ParseError::UnknownDialect`、`ParseResult.dialect`） | self-rename |
| `completion/completion.mbt` | service | request-response | 自身（`complete(raw, dialect_id, profile_id, cursor_byte)`） | self-rename |
| `formatter/case.mbt` | utility | transform | 自身（`rewrite_keyword(context, raw)`） | self-rename |
| `formatter/format.mbt` | service | transform | 自身（`format(root, source, options)` 入口加 context、`FATHOM-FORMAT-001`） | self-rename |
| `moon.mod` | config | — | 自身（`name = "fathom/sql"`） | self-rename |
| 16 个 `moon.pkg`（api/token/lexer/parser/syntax/source/printer/formatter/completion/analyzer/binding/lsp/doris-sql/parity/test/根） | config | — | 自身（import 串 `fathom/doris-sql/<pkg>` → `fathom/sql/<pkg>`，alias 不变） | self-rename |
| `test/*.mbt`（10 个测试文件） | test | batch | 自身（import 改名 + dialect 参数） | self-rename |

### C. binding / CLI / LSP（改名 mirror，analog = 自身）

| Modified File | Role | Data Flow | Analog（拷贝自） | Match Quality |
|---------------|------|-----------|------------------|---------------|
| `binding/exports.mbt` | exports（ABI） | request-response | 自身（`doris_*_v1` → `fathom_*_v1`，签名加 dialect） | self-rename |
| `binding/schema.mbt` | schema | serialization | 自身（`doris.*.v1` → `fathom.*.v1`、`validate_profile` → `validate_dialect_profile`） | self-rename |
| `binding/moon.pkg` | config | — | 自身（js/wasm `exports` 列表同步改名） | self-rename |
| `doris-sql/` → `fathom-sql/`（moon.pkg/main.mbt/args.mbt/run.mbt/ffi.mbt/cli_test.mbt） | CLI | request-response | 自身（`git mv` + `--dialect --profile`、`UsageError` 增 MissingDialect/UnknownDialect） | self-rename |
| `lsp/handlers.mbt` | controller | event-driven | 自身（`ServerState.profile` → 默认+映射+document 级 context、`FATHOM-LSP-001`、`fathom-lsp`） | self-rename |
| `lsp/documents.mbt` | model | CRUD | 自身（`Document` 增 dialect/profile） | self-rename |
| `lsp/*_test.mbt`（protocol/diagnostics_formatting/completion/lifecycle/framing） | test | batch | 自身（initialize JSON 加 `"dialect":"doris"`、schema 断言 `fathom.parse.v1`） | self-rename |

### D. 宿主 / CI / docs（命名 cutover，analog = 自身）

| Modified File | Role | Data Flow | Analog（拷贝自） | Match Quality |
|---------------|------|-----------|------------------|---------------|
| `vscode/package.json` | config | — | 自身（name/displayName/activationEvents/language id/配置键/command） | self-rename |
| `vscode/src/extension.ts` | controller | event-driven | 自身（`getConfiguration('fathom')`、`initializationOptions: {dialect, profile}`） | self-rename |
| `vscode/src/extension-contract.ts` | utility | — | 自身（`SUPPORTED_DIALECTS` 增、无默认 dialect） | self-rename |
| `web/package.json` | config | — | 自身（`@fathom/sql-web-demo`） | self-rename |
| `web/index.html` | UI | — | 自身（中性标题 + dialect 选择器） | self-rename |
| `web/src/monaco-adapter.ts` | adapter | request-response | 自身（`DIALECTS`+`PROFILES`、`fathom_parse_v1(raw, dialect, profile, mode)`、`'fathom.error.v1'`） | self-rename |
| `web/src/main.ts` + `main.test.ts` | UI / test | — | 自身（语言 id 中立、双选择器、mock 同步） | self-rename |
| `jetbrains/.../doris/`（DorisLanguageServerFactory.kt/DorisSettings.kt/DorisSettingsConfigurable.kt/DorisNativeDownloader.kt + 2 测试） | controller/config/UI/service | — | 自身（包名 `fathom.jetbrains`、类名 `Fathom*`、配置键/state/asset 名） | self-rename |
| `jetbrains/scripts/source-smoke.py` | CI gate | batch | 自身 + `corpus/tools/check_keywords.py` 校验形态（正则 require 循环） | self-rename |
| `jetbrains/build.gradle.kts` / `settings.gradle.kts` | config | — | 自身（changeNotes、`fathom-sql-intellij`） | self-rename |
| `.github/workflows/ci.yml` | CI config | — | 自身（增 NAME-04 gate 作业，仿 corpus 作业） | self-rename |
| `.github/workflows/doris-native-release.yml` | CI config | — | 自身（workflow/资产/manifest 名） | self-rename |
| `.github/workflows/jetbrains-plugin.yml` | CI config | — | 自身（artifact 名） | self-rename |
| `parity/fixtures/lsp-tracer.json` / `target-matrix.json` | fixture | — | 自身（`fathom.parse.v1` + `"dialect":"doris"`） | self-rename |
| `parity/export_smoke_test.mbt` / `schema_test.mbt` / `parity_test.mbt` / `coordinates_test.mbt` | test | batch | 自身（`fathom_*_v1` + dialect 参数、`validate_dialect_profile`） | self-rename |
| `docs/*.md` + `docs/zh-CN/*` + `README.md` + `README.zh-CN.md` | docs | — | 自身（`fathom/sql/api`、`fathom-sql`、dialect+profile 表） | self-rename |
| `corpus/**`、`.planning/milestones/**` | — | — | **保留**（D-04/D-05 provenance 豁免，gate 不扫） | keep |

## Pattern Assignments

### `dialect/dialect.mbt`（model，policy 权威）

**Analog:** `token/token.mbt:3-41`（`DorisProfile` enum + `ProfileMetadata` + `ValidatedProfileContext`）— 闭合 enum + context struct 的既有形态逐字沿用。

**Imports/type pattern**（token/token.mbt:3-7、18-27）:
```moonbit
/// Explicit released Doris profile metadata and source-backed lexical leaves.

pub(all) enum DorisProfile {
  V2_1
  V3_X
  V4_X
} derive(Eq, @debug.Debug)

pub struct ProfileMetadata {
  pub id : String
  pub release_family : String
  pub exact_release : String
  pub feature_introduction : String
  // Kept as the compact, parser-facing label for existing consumers.
  pub introduced_features : String
}
```
新建形态（RESEARCH §Pattern 1 骨架；`Dialect`/`DialectContext` 的字段形态沿用 `ProfileMetadata` 的 `pub` 字段惯例）:
```moonbit
pub enum Dialect { Doris; Flink }

pub struct DialectContext {
  pub dialect : Dialect
  pub profile_id : String
  pub exact_release : String
  pub feature_introduction : String
}
```

**Validation pattern**（token/token.mbt:30-41，`ValidatedProfileContext` 的「profile+metadata 校验 → 结构化错误」骨架，泛化为 `DialectContext` 校验）:
```moonbit
pub struct ValidatedProfileContext {
  profile : DorisProfile
  metadata : ProfileMetadata
}

pub fn ValidatedProfileContext::canonical(profile : DorisProfile) -> ValidatedProfileContext {
  { profile: profile, metadata: profile.metadata() }
}

pub fn ValidatedProfileContext::supports(
  self : ValidatedProfileContext,
  feature : DorisFeature,
) -> Bool {
  self.profile.supports(feature) &&
    self.metadata.feature_introduction == self.profile.metadata().feature_introduction
}
```

**D-05 约束:** `DorisProfile`/`DorisFeature`/`ValidatedProfileContext`/`ClassificationKind`/`ClassificationEntry` 类型名保留原样迁入 `dialect/doris.mbt`（或公共层），只改文件位置，不改名。

---

### `dialect/classification.mbt`（model，查找 API）

**Analog:** `token/token.mbt:271-494` — 共享 `KeywordEntry` 结构 = `ClassificationEntry` 加 `classification` 复用；ASCII case-insensitive 算法原样搬。

**Shared row struct**（token/token.mbt:271-287，`ClassificationEntry` 即 `KeywordEntry` 前身，字段逐字保留）:
```moonbit
/// Three-layer keyword classification (D-14): reserved words require backticks
/// as identifiers, non-reserved grammar words stay usable as unquoted
/// identifiers, and contextual words are clause-only (identifiers elsewhere).
pub(all) enum ClassificationKind {
  Reserved
  NonReserved
  Contextual
} derive(Eq, @debug.Debug)

/// One classified keyword row: word spelling, classification, the released
/// profile that introduced the classification-relevant usage, and the official
/// docs source row. Every word the parser productions use has a row
/// (D-13/D-16 single source of truth).
pub struct ClassificationEntry {
  pub word : Bytes
  pub classification : ClassificationKind
  pub introduced_profile : String
  pub source : String
} derive(Eq, @debug.Debug)
```

**Rows array**（token/token.mbt:307-311，`classification_rows` → `doris_classification_rows`；行内容逐行保留 word/classification/introduced_profile/source）:
```moonbit
let classification_rows : Array[ClassificationEntry] = [
  // Phase 1 reserved words, re-encoded with byte-identical answers. The
  // official reserved-keyword list (identical across 2.1/3.x/4.x) is the
  // classification authority (D-13); words absent from it but reserved by the
  // Phase 1 clause/operator contract (QUALIFY, WINDOW, RECURSIVE, GROUPING,
  // ROLLUP, DISTINCTROW, SAMPLE, OVER, NULLS, FIRST, LAST, GROUPS, OFFSET)
  // stay reserved so is_reserved_word / is_unquoted_identifier behavior is
  // preserved exactly.
  { word: b"SELECT", classification: Reserved, introduced_profile: "2.1", source: reserved_keywords_url },
  { word: b"WITH", classification: Reserved, introduced_profile: "2.1", source: reserved_keywords_url },
  ...
```

**Lookup core（加 context 路由）**（token/token.mbt:450-494，逐行保留 + `match context.dialect` 选 rows；`token_bytes_equal_ci` 从 token.mbt:221-236 原样搬入共享层）:
```moonbit
/// Case-insensitive lookup of a word's classification row (D-13/D-14).
pub fn classification_of(raw : Bytes) -> ClassificationEntry? {
  let mut index = 0
  while index < classification_rows.length() {
    let entry = classification_rows[index]
    if token_bytes_equal_ci(raw, entry.word) {
      return Some(entry)
    }
    index = index + 1
  }
  None
}

/// Released-profile reserved words: table-backed (D-14) — true iff a Reserved
/// row exists (case-insensitive). Answers match the Phase 1 clause/operator
/// set exactly; TABLET remains contextual.
pub fn is_reserved_word(raw : Bytes) -> Bool {
  match classification_of(raw) {
    Some(entry) => entry.classification is Reserved
    None => false
  }
}

pub fn is_unquoted_identifier(raw : Bytes) -> Bool {
  !is_reserved_word(raw)
}
```
改造后（RESEARCH Common Operation 1; Pitfall 1 禁止保留无参数公共查询）:
```moonbit
pub fn classification_of(context : DialectContext, raw : Bytes) -> KeywordEntry? {
  let rows = match context.dialect {
    Dialect::Doris => doris_classification_rows
    Dialect::Flink => flink_classification_rows
  }
  // while 循环 + token_bytes_equal_ci 原样保留
  ...
}
pub fn is_reserved_word(context : DialectContext, raw : Bytes) -> Bool {
  match classification_of(context, raw) {
    Some(entry) => entry.classification is Reserved
    None => false
  }
}
```

**is_clause_keyword 注意**（token/token.mbt:471-483）: 现为硬编码 bytes_equal_ci 链，DIALECT-02 要求随 dialect 独立——先加 context 参数，是否改为表驱动由 planner 定，行为以 baseline 门禁锁定。

---

### `dialect/doris.mbt`（model，DorisFeature 迁入）

**Analog:** `token/token.mbt:133-196`（`DorisFeature` enum + `FeatureMetadata` + `metadata()`）— 整体搬入 dialect/doris.mbt，**类型名与字段名不动**（D-05），仅 diagnostic_code 值 `"DORIS-PARSE-006"` → `"FATHOM-PARSE-006"`。

```moonbit
pub(all) enum DorisFeature {
  Qualify
  Tablet
  PartitionStar
  MergeInto
  OrderByClause
  BucketsAuto
  AutoPartitionBy
} derive(Eq, @debug.Debug)

pub struct FeatureMetadata {
  pub name : String
  pub keyword : Bytes
  pub introduced_profile : String
  pub diagnostic_code : String
  pub recovery_kind : String
  pub diagnostic_message : String
}

pub fn DorisFeature::metadata(self : DorisFeature) -> FeatureMetadata {
  match self {
    Qualify => {
      name: "QUALIFY",
      keyword: b"QUALIFY",
      introduced_profile: "3.x",
      diagnostic_code: "DORIS-PARSE-006",   // → FATHOM-PARSE-006（§5 code 映射）
      recovery_kind: "error",
      diagnostic_message: "feature QUALIFY is unavailable in the selected released profile",
    }
    ...
  }
}
```
`DorisProfile::metadata()`/`from_id`/`supports`（token/token.mbt:52-133、198-219）一并迁入。`doris_classification_rows` 与 Doris 的 `*_docs_url` 常量（token/token.mbt:289-296）同文件放置。

---

### `dialect/flink.mbt`（model，Phase 9 占位）

**Analog:** `token/token.mbt:3-6` 闭合 enum 形态（无 rows）。`FlinkProfile` 在 Phase 9 为**空 enum 或未定义值**（Open Question 1，推荐 (a)：flink 是合法 dialect 值、所有 profile 结构化拒绝）。`flink_classification_rows : Array[KeywordEntry] = []`（Phase 10 填充）。

---

### `token/token.mbt`（改造：Token.context / TokenStream.context / 查询加参）

**自 analog。** 结构字段改名（迁移表 #8/#9，token/token.mbt:510-515、533-538）:
```moonbit
pub(all) struct Token {
  pub kind : TokenKind
  pub span : @source.Span
  pub profile : DorisProfile        // → pub context : DialectContext
  pub diagnostic_code : String?
}

pub(all) struct TokenStream {
  pub source : @source.SourceText
  pub profile : DorisProfile        // → pub context : DialectContext
  pub tokens : Array[Token]
  pub truncated_at : Int?
}
```
注意 `lexer.push_token`（lexer/lexer.mbt:134-155）逐 token 复制 profile 的调用点随字段改名同步；`classification_rows` 本体迁出后，`classification_entry_count`/`classification_entry_at`（token/token.mbt:456-463）被 completion 使用（completion/completion.mbt:160-161），需改为按 context 路由或由 dialect 层提供等价 API。

---

### `lexer/lexer.mbt`（改造：lex 签名加 context）

**自 analog。** 入口签名（迁移表 #12，lexer/lexer.mbt:250、378）:
```moonbit
pub fn lex_with_limit(source : @source.SourceText, profile : @token.DorisProfile, max_tokens : Int) -> @token.TokenStream {
  ...
}
```
→ `lex_with_limit(source, context : @token.DialectContext, max_tokens)` / `lex(source, context)`；`push_token` 的 `profile : @token.DorisProfile` 参数（lexer/lexer.mbt:134）改 `context`。scanner 主体（scan_comment/scan_quoted/scan_number，lexer/lexer.mbt:166-245）方言无关，**不动**；DIALECT-02 的 per-dialect 词法策略（quote/comment/literal）由 `DorisLexPolicy`/`FlinkLexPolicy` 数据源按 context 选择，不复制 scanner。

---

### `parser/parser.mbt`（改造：parse_segment 显式 dialect 路由）

**自 analog。** 语句分发骨架（迁移表 #14，parser/parser.mbt:3327-3385）——Doris starters 整段迁入 `parse_doris_segment`，入口改为 match 分派（RESEARCH Common Operation 2）:
```moonbit
fn parse_segment(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
  statement_id : UInt,
  state : RecoveryState,
) -> @syntax.SyntaxNode {
  let span = segment_span(stream, start_index, end_index)
  let indices = significant_indices(stream, start_index, end_index)
  let cursor = { stream: stream, indices: indices, position: 0, depth: 0 }
  let verb = match indices.get(0) {
    Some(first_index) => stream.raw(first_index)
    None => None
  }
  match verb {
    Some(raw) if bytes_equal_ci(raw, b"SELECT") =>
      finish_statement(stream, cursor, start_index, end_index, span, parse_query(cursor, state, stream.source, statement_id), state, statement_id, @syntax.SyntaxKind::Select, "unexpected tokens after SELECT query")
    Some(raw) if bytes_equal_ci(raw, b"WITH") => {
      match with_prefix_verb(stream, indices, 0) {
        Some(next) if bytes_equal_ci(next, b"SELECT") => ...
        _ => unsupported_statement(stream, start_index, end_index, span, state, statement_id)
      }
    }
    ...
    _ => unsupported_statement(stream, start_index, end_index, span, state, statement_id)
  }
}
```
改造后: 签名加 `context : DialectContext`，入口 `match context.dialect { Dialect::Doris => parse_doris_segment(...)（现有 match 体原样迁入）; Dialect::Flink => parse_flink_segment(...)（Phase 9 显式 not-implemented 诊断，禁止回退 Doris） }`。

**RecoveryState 字段改名**（迁移表 #17，parser/parser.mbt:118-124）:
```moonbit
struct RecoveryState {
  diagnostics : Array[ParserDiagnostic]
  limits : ParserLimits
  profile_context : @token.ValidatedProfileContext   // → context : @token.DialectContext
  feature_events : Array[FeatureEvent]
  mut recovery_steps : Int
  mut resource_emitted : Bool
}
```
消费点 `let profile = cursor.stream.profile`（parser/parser.mbt:1365）→ `let context = cursor.stream.context`；`parse_with_limits_context(source, context : @token.ValidatedProfileContext, ...)`（parser.mbt:3430-3434）→ `context : @token.DialectContext`；便捷入口 `parse(source, profile : @token.DorisProfile, mode)`（parser.mbt:3531-3556）按 Open Question 5 全改 context（test 包 93 处调用点同步）。

**诊断 code 替换**（迁移表 #19）: `DORIS-PARSE-001/002/003/004/006/007` → `FATHOM-PARSE-*`，定义点如 `finish_statement` 内 `"DORIS-PARSE-001"`（parser.mbt:3149）、`unsupported_statement` 内 `"DORIS-PARSE-007"`（parser.mbt:3166）、lexical 错误 `"DORIS-PARSE-003"`（parser.mbt:3468-3476）。`DORIS-PARSE-005` 保持空缺不新建。

---

### `api/api.mbt`（改造：ParseOptions 加 dialect 维度）

**自 analog。** 显式校验 + 结构化错误骨架（迁移表 #20-22，api/api.mbt:42-84）:
```moonbit
pub struct ParseOptions {
  profile_context : @token.ValidatedProfileContext   // 增 dialect_context（或并入 context）
  mode : ParseMode
  limits : ParseLimits
}

pub enum ParseError {
  UnknownProfile(profile_id~ : String)
  UnknownMode(mode_id~ : String)
  ProfileMetadataMismatch(...)
  UnsupportedFeatureIntroduction(feature_introduction~ : String)
  InputTooLarge(requested_bytes~ : Int, max_bytes~ : Int)
  InvalidLimit(limit_name~ : String, value~ : Int)
  InvalidSyntaxTree
} derive(Eq, @debug.Debug)

pub fn ParseOptions::new(profile_id : String, mode_id : String) -> Result[ParseOptions, ParseError] {
  let profile = match @token.DorisProfile::from_id(profile_id) {
    Some(profile) => profile
    None => return Err(UnknownProfile(profile_id~))
  }
  let mode = match mode_id {
    "strict" => ParseMode::Strict
    "editor" => ParseMode::Editor
    _ => return Err(UnknownMode(mode_id~))
  }
  Ok({ profile_context: @token.ValidatedProfileContext::canonical(profile), mode: mode, limits: ParseLimits::default() })
}
```
→ `ParseOptions::new(dialect_id : String, profile_id : String, mode_id : String)`；`ParseError` 增 `UnknownDialect(dialect_id~ : String)` 与 `ConflictingSelection`（Open Question 3）；校验顺序**先 dialect 后 profile**（Pitfall 6）。`ParseResult`（api.mbt:180-205）增 `dialect : String` 字段，`schema_version: "doris.parse.v1"`（api.mbt:298）→ `"fathom.parse.v1"`。`parse_with_ids`/`format_with_ids`（api.mbt:327-337、418-433）加 dialect_id 参数（顺序 `(raw, dialect_id, profile_id, mode_id, ...)`，与 CLI `--dialect --profile` 一致，A4）。

---

### `fathom-sql/`（由 `doris-sql/` 改名：CLI）

**Analog:** `doris-sql/` 全包（自身 rename，`git mv doris-sql fathom-sql` 一次完成，Pitfall 8）。包名=目录名 → 二进制 `fathom-sql.exe`（doris-sql/moon.pkg:2-3 probe 注释即证据）。

**UsageError + 参数校验骨架**（迁移表 #51-53，doris-sql/args.mbt:8-19、40-42、125-127）:
```moonbit
/// Usage errors map to exit 2 (D-39).
pub enum UsageError {
  MissingSubcommand
  UnknownSubcommand(sub~ : String)
  MissingProfile
  UnknownProfile(profile_id~ : String)
  UnknownFlag(flag~ : String)
  MissingValue(flag~ : String)
  UnknownValue(flag~ : String, value~ : String)
  MissingFile
} derive(Eq, @debug.Debug)
```
→ 增 `MissingDialect`/`UnknownDialect`；`parse_args` 增 `--dialect <doris|flink>`（与 `--profile` 均必选，D-11）；`is_valid_profile` 改为按 dialect 校验:
```moonbit
fn is_valid_profile(id : String) -> Bool {
  id == "2.1" || id == "3.x" || id == "4.x"
}
```
→ `is_valid_dialect_profile(dialect, id)`（doris: 2.1/3.x/4.x；flink: Phase 10 前全部拒绝）。`Command` 结构（args.mbt:22-34）增 `dialect : String` 字段。

**usage 文本 + 错误消息**（迁移表 #54-55，doris-sql/run.mbt:144、148-155）:
```moonbit
pub fn usage_text() -> String {
  "usage: doris-sql format --profile <2.1|3.x|4.x> [--keyword-case upper|lower] ...\n"
}
```
→ `"usage: fathom-sql parse|format|lsp --dialect <doris|flink> --profile <id> ..."`；`usage_error_message` 增 MissingDialect/UnknownDialect 分支，exit 2 语义不变。核心调用 `@api.format_with_ids(input, command.profile, "strict", format_options)`（run.mbt:79）→ 加 `command.dialect`。`main.mbt`（--help 优先、stdin 只读一次的 IO 骨架）与 `ffi.mbt` 不动。`cli_test.mbt` 的 `command_stdin(profile)` 构造（cli_test.mbt:22-31）增 dialect 字段。

---

### `binding/exports.mbt`（改造：fathom_*_v1 export）

**自 analog。** ABI 骨架（迁移表 #31-34，binding/exports.mbt:25-80）——`#export_name` + pub fn + JSON bytes 边界原样保留，仅改名/加参:
```moonbit
#export_name("doris_parse_v1")
pub fn doris_parse_v1(raw : Bytes, profile : String, mode : String) -> Bytes {
  match @api.parse_with_ids(raw, profile, mode) {
    Ok(result) => json_bytes(parse_result_json(result))
    Err(error) => parse_error_bytes(error)
  }
}

#export_name("doris_format_v1")
pub fn doris_format_v1(
  raw : Bytes, profile : String, mode : String, keyword_case : String,
  indent : Int, line_width : Int, comma_style : String, newline_style : String,
  trailing_newline : Bool,
) -> Bytes { ... }

#export_name("doris_profile_v1")
pub fn doris_profile_v1(profile : String) -> Bytes {
  json_bytes(profile_json(profile))
}

#export_name("doris_capabilities_v1")
pub fn doris_capabilities_v1() -> Bytes {
  json_bytes(capabilities_json())
}
```
→ `#export_name("fathom_parse_v1")` / `pub fn fathom_parse_v1(raw : Bytes, dialect : String, profile : String, mode : String)`；`doris_format_v1` → `fathom_format_v1`（同样加 dialect）；`doris_profile_v1` → `fathom_dialect_v1(dialect)`（Open Question 4 推荐，返回该 dialect 的 profiles + 版本元数据）；`doris_capabilities_v1` → `fathom_capabilities_v1()`（内容增 dialects/profiles 列表）。format 选项错误码 `"DORIS-FORMAT-002/003/004"`（exports.mbt:47,51,55）→ `FATHOM-FORMAT-*`。

---

### `binding/schema.mbt`（改造：fathom.*.v1 wire schema）

**自 analog。** schema 常量与校验（迁移表 #36-40，binding/schema.mbt:3-5、29-35、43-49）:
```moonbit
pub const PARSE_SCHEMA_VERSION : String = "doris.parse.v1"      // → "fathom.parse.v1"
pub const FORMAT_SCHEMA_VERSION : String = "doris.format.v1"    // → "fathom.format.v1"
pub const SOURCE_TRANSPORT : String = "inline-root-v1"          // 不变

pub fn validate_profile(profile : String) -> Result[Unit, SchemaError] {
  match profile {
    "2.1" | "3.x" | "4.x" => Ok(())
    _ => Err(UnsupportedProfile(profile~))
  }
}
```
→ `validate_dialect_profile(dialect : String, profile : String)`（RESEARCH Common Operation 4；`SchemaError` 增 `UnknownDialect`；flink 分支 Phase 9 全拒绝）。`schema_error_code`（schema.mbt:43-49）`DORIS-SCHEMA-001..006` → `FATHOM-SCHEMA-*`；`schema_error_json` 的 `"doris.error.v1"`（schema.mbt:63）→ `"fathom.error.v1"`；`parse_error_json`（schema.mbt:107-127）`DORIS-SCHEMA-003..006`/`DORIS-PARSE-001..003` → `FATHOM-*`，消息 `"unsupported Doris profile: \{profile_id}"`（schema.mbt:117）→ 中性措辞；`format_error_json`（schema.mbt:131-146）`DORIS-FORMAT-002..007` → `FATHOM-FORMAT-*`；`profile_json`（schema.mbt:148-160）`"doris.profile.v1"` → `"fathom.dialect.v1"`；`capabilities_json`（schema.mbt:162-176）`"doris.capabilities.v1"` → `"fathom.capabilities.v1"` 且 profiles 表按 dialect 分组。`parse_result_json`（schema.mbt:69-86）增 `"dialect"` 字段（DIALECT-04 metadata）。

**注意（Pitfall 8）:** `#export_name` 与 `binding/moon.pkg:14-28` 的 js/wasm `exports` 列表必须同步改，缺一即半迁移。

---

### `lsp/handlers.mbt`（改造：document 级 DialectContext）

**自 analog。** ServerState/Document 状态机（迁移表 #41-49，lsp/handlers.mbt:4-10、documents.mbt:3-39）:
```moonbit
pub(all) struct ServerState {
  pub mut docs :  DocumentStore
  pub mut profile : String          // → default_selection? + language_mapping?（D-01 三级优先级）
  pub mut initialized : Bool
  pub mut shutdown : Bool
  pub mut exited : Bool
}

pub(all) struct Document {
  pub uri : String
  pub version : Int
  pub text : Bytes                  // 增 pub dialect : String / pub profile : String（D-03）
}
```
**DocumentStore version 守卫模式推广（D-03 stale 防护）**（documents.mbt:13-39）:
```moonbit
pub fn DocumentStore::open(self : DocumentStore, uri : String, version : Int, text : Bytes) -> Bool {
  if version < 0 { return false }
  match self.docs.get(uri) {
    Some(document) if version <= document.version => false
    _ => {
      self.docs[uri] = { uri: uri, version: version, text: text }
      true
    }
  }
}
```
dialect 切换时按新 context 重解析当前 revision，并复用 completion 的 stale 检查模式（lsp/handlers.mbt:253-257 `"completion document version is stale"`）推广到 diagnostics（Pitfall 5）。

**initialize 显式选择校验**（迁移表 #43、#47，lsp/handlers.mbt:144-150、304-313）:
```moonbit
fn initialize_profile(params : Json) -> String? {
  let options = match  object_field(params, "initializationOptions") {
    Some(options) => options
    None => return None
  }
   string_field(options, "profile")
}
```
→ `initialize_selection(params)` 读 `{dialect, profile}`；缺失/未知/冲突 → 结构化 `-32602`（现 `"unsupported Doris profile"` 于 handlers.mbt:309，改中性措辞）。调用点 `@api.parse_with_ids(document.text, state.profile, "editor")`（handlers.mbt:79）→ 用 document 自身 context。

**命名 cutover**（迁移表 #44-46）: `"source": Json::string("doris")`（handlers.mbt:45,85）→ `"fathom"`；`"code": Json::string("DORIS-LSP-001")`（handlers.mbt:84）→ `FATHOM-LSP-001`；`"serverInfo": { "name": "doris-lsp", ... }`（handlers.mbt:160）→ `"fathom-lsp"`。LSP 测试的 initialize JSON（protocol_test.mbt:10,29,49 等）加 `"dialect":"doris"`；diagnostics_formatting_test.mbt 的 `"doris.parse.v1"` 断言 → `fathom.parse.v1`。

---

### `scripts/check_naming.py`（新增：NAME-04 gate）

**Analog:** `corpus/tools/check_keywords.py` — stdlib only、逐行/逐文件检查、problems 汇总、非零退出、`print("ok: ...")` 成功行。常量与主循环形态:
```python
HEADER = ["word", "classification", "introduced_profile", "source"]
VALID_CLASSIFICATIONS = {"reserved", "non-reserved", "contextual"}
VALID_PROFILES = {"2.1", "3.x", "4.x"}
```
```python
def main(argv):
    if len(argv) != 2:
        print("usage: check_keywords.py keywords.tsv", file=sys.stderr)
        return 2
    ...
    problems = []
    seen = {}
    words = set()
    for lineno, line in enumerate(lines[1:], start=2):
        ...
        if problems:
            for problem in problems:
                print("error: " + problem, file=sys.stderr)
            return 1
    print("ok: %d keyword rows, %d production words covered" % (len(seen), len(PRODUCTION_WORDS)))
    return 0
```
`check_naming.py` 按 RESEARCH §7 形态：`FORBIDDEN` 正则清单（`doris-sql`/`doris-lsp`/`doris_(parse|format|profile|capabilities)_v1`/`doris\.(parse|format|error|profile|capabilities)\.v1`/`DORIS-`/`fathom/doris-sql`/`doris\.profile`/`doris\.serverPath` 等）+ `ALLOWLIST_PATHS`（corpus/、.planning/、milestones/、_build/、node_modules/，D-04 豁免）+ `ALLOWLIST_PATTERNS`（`Dialect::Doris`/`DorisProfile`/`DorisFeature`/`doris\.apache\.org`/`--dialect doris`/`"dialect"\s*:\s*"doris"`，D-05/DIALECT-01 允许值）。扫描范围 = product 文件（`**/*.mbt|ts|js|kt|kts|json|yml|mod|pkg|py` + README/docs/web/vscode/jetbrains），排除 `corpus/tools/`、`package-lock.json`、构建产物。

**CI 接入**（仿 ci.yml 现有 corpus 作业）:
```yaml
  corpus:
    name: corpus report + keyword check
    runs-on: ubuntu-latest
    steps:
      - name: Keyword classification check
        run: python3 corpus/tools/check_keywords.py corpus/keywords.tsv
```
→ 新增 `naming-gate` 作业：`actions/checkout@v7` + `run: python3 scripts/check_naming.py`（RESEARCH §7.1 给出完整 YAML 骨架）。

---

### `parity/`（扩展：baseline 冻结快照）

**Analog:** `parity/export_smoke_test.mbt:4-21`（primitive 断言形态）+ `parity/schema_test.mbt:15-18`（schema fixture）+ `parity/moon.pkg:7-11`（三 target 运行骨架）+ `@test.T::snapshot`（官方快照机制）。

**快照测试形态**（RESEARCH Common Operation 3）:
```moonbit
// parity/baseline_test.mbt（示意 — 复用 @test.T::snapshot 官方机制）
test "baseline 2.1-industrial strict parse" (t : @test.Test) {
  let fixture = corpus_fixture("2.1-industrial")  // 读 corpus/doris-2.1/ 内嵌字节
  let result = @binding.fathom_parse_v1(fixture, "doris", "2.1", "strict")
  t.write(@utf8.decode_lossy(result))
  t.snapshot(filename="2.1-industrial.doris.strict.json")
}
```
- 生成：`moon test --update --package parity` → `parity/__snapshot__/`；门禁：`moon test --target native --package parity`（无 `--update`，字节不一致即失败）。
- 顺序硬依赖（Pitfall 3）: baseline 冻结 → 每步重构跑 diff → 命名迁移 → 宿主改造。
- 跨后端一致性：`parity/moon.pkg:7-11` 的 `targets` 映射已有 `run_native.mbt`/`run_js.mbt`/`run_wasm.mbt` 骨架，baseline 断言三 target 序列化字节相等。
- fixture 更新点（迁移表 #80-83）: `parity/fixtures/lsp-tracer.json:1-2,11-12` `"doris.parse.v1"` → `fathom.parse.v1` + 增 `"dialect":"doris"`；`export_smoke_test.mbt` 的 `@binding.doris_parse_v1(b"select 1", "4.x", "strict")` → `fathom_parse_v1(..., "doris", "4.x", "strict")`；`schema_test.mbt:15-18` `validate_schema_version("doris.parse.v1")`/`validate_profile("mysql")` → `fathom.parse.v1`/`validate_dialect_profile("doris", "mysql")`。

---

### `vscode/` / `web/` / `jetbrains/`（宿主命名 cutover）

**自 analog，全部为机械改名 + 增 dialect 维度。** 关键锚点:

- `vscode/package.json:1-2` `"name": "doris-sql-language-client"` / `"displayName": "Doris SQL Language Client"` → `fathom-sql-language-client` / `Fathom SQL Language Client`；`:15-17` activationEvents `onLanguage:doris`/`onCommand:doris.restartLanguageServer` → `onLanguage:sql` + `fathom.restartLanguageServer`；`:20-32` language id `"doris"` → 中立 `"sql"`；`:33-55` 配置键 `doris.profile`/`doris.serverPath`（default `doris-lsp`）→ `fathom.dialect`/`fathom.profile`/`fathom.serverPath`（default `fathom-lsp`）；`:56-60` command/title → `fathom.restartLanguageServer` / `"Fathom SQL: Restart Language Server"`。
- `vscode/src/extension.ts:20-24,33-37,44-52` `getConfiguration('doris')`、`LanguageClient('doris', 'Doris SQL Language Server', ...)`、`documentSelector [{ language: 'doris' }]`、`initializationOptions: { profile }`、命令 `doris.restartLanguageServer` → `'fathom'`/`'Fathom SQL Language Server'`/`initializationOptions: { dialect, profile }`。`extension-contract.ts:1-8` 增 `SUPPORTED_DIALECTS`，**删除** `normalizeProfile` 的 `'4.x'` 兜底（D-02 无默认）。
- `web/src/monaco-adapter.ts:3,76-100` `PROFILES = ['2.1','3.x','4.x']` → 增 `DIALECTS`；`schema_version === 'doris.error.v1'` → `'fathom.error.v1'`；`module.doris_parse_v1(utf8Bytes(source), profile, 'editor')` → `module.fathom_parse_v1(utf8Bytes(source), dialect, profile, 'editor')`（参数顺序 A4）；`'Choose a supported Doris profile.'` 中性化。`web/src/main.ts:26-31` `monaco.languages.register({ id: 'doris' })` → 中立 id + dialect/profile 双选择器。
- `jetbrains/.../doris/` 包 → `fathom.jetbrains`（或 `fathom.jetbrains.sql`）：`DorisLanguageServerFactory.kt:40-43` `initializationOptions(profile) = mapOf("profile" to profile)` → `mapOf("dialect" to dialect, "profile" to profile)`；`DorisSettings.kt:8-11` `@State(name = "DorisSettings", storages = [Storage("doris.xml")])` → `FathomSettings`/`fathom.xml`，`:42-47` `DEFAULT_EXECUTABLE = "doris-lsp"` → `"fathom-lsp"`、`DEFAULT_PROFILE = "4.x"` → 删除默认（D-02）或按 Open Question 6；`DorisNativeDownloader.kt` assetName `doris-lsp-{platform}` → `fathom-lsp-{platform}`、manifest `doris-lsp-manifest.json` → `fathom-lsp-manifest.json`、缓存目录 `Fathom/doris-sql` → `Fathom/fathom-sql`、`DEFAULT_REPOSITORY` 按 Open Question 8。
- `jetbrains/scripts/source-smoke.py:44-48,53-56,62-71,89-101` 的 `require(...)` 正则契约（`<id>fathom\.doris\.sql</id>`、`server id="doris"`、`DEFAULT_EXECUTABLE\s*=\s*"doris-lsp"`、`doris-lsp-manifest\.json` 等）全部同步到中立名——该脚本本身是 jetbrains 侧的命名 gate，随迁移更新。
- CI: `doris-native-release.yml:2,93-107` workflow name `Doris Native Release` → `Fathom Native Release`；`dist/doris-lsp-${{ matrix.platform }}` → `dist/fathom-lsp-...`；manifest `doris-lsp-manifest.json` → `fathom-lsp-manifest.json`（platforms 字典与 download-artifact pattern 同步）。`jetbrains-plugin.yml:44-46` artifact `fathom-doris-intellij` → `fathom-sql-intellij`。`settings.gradle.kts:12` `rootProject.name = "fathom-doris-intellij"` → `fathom-sql-intellij`。
- `web/index.html:6-7,18-19,26-27` `<title>Doris SQL — offline parser demo</title>`/`<h1>Doris SQL diagnostics</h1>`/`Doris profile 4.x` → 中性 Fathom 标题 + dialect 选择器；`web/package.json:1-4` `@fathom/doris-web-demo` → `@fathom/sql-web-demo`。

---

### `moon.mod` + 16 个 `moon.pkg`（import 改名）

**自 analog。** `moon.mod:5` `name = "fathom/doris-sql"` → `name = "fathom/sql"`（version 是否 bump 见 Open Question 7，默认保持 0.1.0 由 release 规划决定）。16 个 `moon.pkg` import 串统一替换 `"fathom/doris-sql/<pkg>" @alias` → `"fathom/sql/<pkg>" @alias`（alias 不变）。典型块（api/moon.pkg:3-8、test/moon.pkg:2-10、binding/moon.pkg、doris-sql/moon.pkg、parity/moon.pkg:3-6、lsp/moon.pkg）:
```moonbit
import {
  "fathom/doris-sql/source" @source,
  "fathom/doris-sql/token" @token,
  "fathom/doris-sql/parser" @parser,
  "fathom/doris-sql/syntax" @syntax,
  "fathom/doris-sql/formatter" @formatter,
}
```
→ 全部前缀换 `fathom/sql/`。`pkgtype(kind: ...)`、`options(targets: ...)`、`options(link: { "js"/"wasm": { "exports": [...] } })`（binding/moon.pkg:14-28，export 名与 `#export_name` 同步改）结构不动。`doris-sql/moon.pkg` 目录改名后 `pkgtype(kind: "executable")` 不变，二进制名自动变为 `fathom-sql.exe`（Pitfall 8: `git mv` 一次性完成，勿只改 moon.mod）。

---

## Shared Patterns

### 1. 显式选择校验：string-id → enum → 结构化错误（CORE-01 传统，延续到 dialect）
**Source:** `api/api.mbt:64-84`（ParseOptions::new）、`binding/schema.mbt:29-35`（validate_profile）、`doris-sql/args.mbt:125-127`（is_valid_profile）、`lsp/handlers.mbt:304-313`（initialize）
**Apply to:** api、binding、fathom-sql CLI、lsp、web/monaco-adapter、vscode、jetbrains（DIALECT-01 全边界）
```moonbit
let profile = match @token.DorisProfile::from_id(profile_id) {
  Some(profile) => profile
  None => return Err(UnknownProfile(profile_id~))
}
```
规则：未知 → `UnknownDialect`/`UnknownProfile`；缺失 → CLI `MissingDialect`/`MissingProfile`（exit 2）、LSP `-32602`；同源冲突 → `ConflictingSelection`；**绝不静默 fallback**（D-02 删除 VS Code/IntelliJ/Web 的 `'4.x'` 默认兜底）。校验顺序先 dialect 后 profile（Pitfall 6）。

### 2. 错误面：code + message JSON envelope
**Source:** `binding/schema.mbt:61-63`（schema_error_json）、`:99-107`（error_json）、`:107-127`（parse_error_json）、`formatter/format.mbt:127-137`（refusal_diagnostic）
**Apply to:** binding schema、formatter、lsp diagnostics、CLI stderr 渲染（`doris-sql/run.mbt:148-155` usage_error_message）
```moonbit
pub fn error_json(code : String, message : String) -> String {
  stringify({
    "schema_version": Json::string("doris.error.v1"),   // → "fathom.error.v1"
    "code": Json::string(code),
    "message": Json::string(message),
  })
}
```
code 前缀 `DORIS-*` → `FATHOM-*`（§5 全表：PARSE-001..007 / FORMAT-001..007 / SCHEMA-001..006 / LSP-001；PARSE-005 空缺不建）；消息中 `"unsupported Doris profile"` 中性化（schema.mbt:117、lsp/handlers.mbt:309），dialect 由 metadata/字段表达（D-10）。

### 3. 快照/golden 纪律：`@test.T::snapshot` + 字节级门禁
**Source:** `parity/export_smoke_test.mbt`、`parity/schema_test.mbt`、`parity/moon.pkg:7-11`；官方机制（`__snapshot__/` + `moon test --update`）
**Apply to:** parity/（baseline 冻结）、test/、lsp/（协议输出 fixture）
- 生成 `moon test --update --package parity`，门禁 `moon test --target native --package parity`（无 `--update`）。
- 顺序不可颠倒：baseline 冻结 → dialect 层（每步 diff）→ 命名迁移（每步 diff）→ 宿主（每步 diff）（Pitfall 3）。
- `moon test --update` 仅在 approved-change 落地 + 变更记录写入后使用一次（D-08 审批路径）。

### 4. CI gate 脚本形态：stdlib Python + 逐行扫描 + 非零退出
**Source:** `corpus/tools/check_keywords.py`（HEADER/VALID_* 常量 + main() problems 循环 + `print("ok: ...")`）
**Apply to:** `scripts/check_naming.py`（NAME-04，FORBIDDEN/ALLOWLIST 双维度）、`scripts/baseline_diff.py`（可选）
```python
    problems = []
    ...
    if problems:
        for problem in problems:
            print("error: " + problem, file=sys.stderr)
        return 1
    print("ok: %d keyword rows, %d production words covered" % (len(seen), len(PRODUCTION_WORDS)))
    return 0
```
gate 必须按「模式 + 文件作用域」双维度工作（`doris` 同时是旧产品名与方言标识——机械全局替换会误删 `Dialect::Doris`/corpus provenance，Pitfall 4）。

### 5. import 改名与 export 同步
**Source:** 16 个 `moon.pkg` import 块 + `binding/moon.pkg:14-28` exports 列表
**Apply to:** 全仓 moon.pkg、binding exports、parity/web/CI 调用点
- `#export_name`（binding/exports.mbt:25-80）与 moon.pkg 的 js/wasm `exports` 列表**必须同 PR 同步改**（官方文档：exports 是 export 名的另一入口；Pitfall 8）。
- `git mv doris-sql fathom-sql` 一次性完成（目录 + import + 文档），二进制名=目录名。

### 6. DialectContext 贯穿查询链
**Source:** `token/token.mbt:450-494` 查找 API、`lexer/lexer.mbt:250,378` 入口、`parser/parser.mbt:3327` parse_segment、`formatter/case.mbt:5-11`、`completion/completion.mbt:131`
**Apply to:** token/lexer/parser/formatter/completion/lsp（DIALECT-02/03）
所有分类查询签名加 `context : DialectContext`；禁止保留无参数公共 `is_reserved_word`（Pitfall 1）；禁止 parser 内散落 `if dialect == Flink`——单一 `parse_segment` router（Pitfall 2）。

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `dialect/flink.mbt` | model | — | 仓库无任何 Flink 代码；Phase 9 仅为闭合 enum 占位（`flink_classification_rows = []`，Phase 10 填充）。形态照 `token/token.mbt:3-6` 闭合 enum。 |
| `parity/baseline-hashes.txt` | fixture | — | 新数据文件（sha256 记录 corpus provenance）；形态参照 `corpus/manifest.tsv` 的 header/行式记录，无代码 analog。 |

其余 49 个文件均有 exact / role-match / self-rename analog（见 File Classification）。`scripts/baseline_diff.py`（可选）以 `check_keywords.py` 循环为 partial analog。

## Metadata

**Analog search scope:** 全仓（token/lexer/parser/api/completion/formatter/binding/lsp/doris-sql/parity/test/corpus/tools/vscode/web/jetbrains/.github/workflows + 16 个 moon.pkg + moon.mod）
**Files scanned:** 约 60（直接 Read：token.mbt 全量、api.mbt 全量、lexer/parser 目标段、exports/schema/moon.pkg、lsp handlers/documents、doris-sql 全量、parity 测试、check_keywords.py、vscode/web/jetbrains 配置与源码、ci.yml/doris-native-release.yml、moon.mod、12 个 moon.pkg）
**Pattern extraction date:** 2026-08-06
**行号依据:** RESEARCH.md §6 迁移表 `[VERIFIED: 路径:行]` 与本 session 直接读取交叉核验一致。
