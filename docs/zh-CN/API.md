<!-- GSD:generated -->
English: [English API reference](../API.md) | 简体中文
# API 参考

Fathom 是一个 MoonBit 库，不是 HTTP 服务。这里的 `api/` 目录是 `fathom/sql/api` library package，提供 Doris SQL 的解析与格式化 facade；调用方通过函数参数传入源字节、Doris profile、模式和限制，不需要启动服务器、连接 Doris FE 或配置认证凭据。

## 认证

不适用。当前仓库没有 HTTP 服务、中间件、API key、JWT、OAuth、session 或 `Authorization` header 处理。所有 API 都是进程内同步函数；调用方只需导入 MoonBit 包并直接传参。

```moonbit
import {
  "fathom/sql/api" @api,
}
```

解析器也不访问数据库或外部 catalog。名字解析是独立的 `analyzer` 包能力，catalog 由调用方注入，且不会改变 `ParseResult.valid` 或语法诊断。

## Endpoint 概览

本项目没有 HTTP endpoint，也没有 HTTP base URL、请求路由或部署服务。下表中的“入口”是库函数，而不是网络 endpoint。

| 入口 | 所属包 | 用途 | 认证 |
|---|---|---|---|
| `parse` | `fathom/sql/api` | 使用已构造的 `ParseOptions` 解析原始 SQL 字节 | 不需要 |
| `parse_with_ids` | `fathom/sql/api` | 用 dialect/profile/mode 字符串快捷构造选项并解析 | 不需要 |
| `parse_with_metadata` | `fathom/sql/api` | 校验 profile 的 release 与 feature metadata 后解析 | 不需要 |
| `format_text` | `fathom/sql/api` | 解析并按 `FormatOptions` 格式化 SQL | 不需要 |
| `format_with_ids` | `fathom/sql/api` | 用 profile/mode 字符串快捷格式化 | 不需要 |
| `format_with_metadata` | `fathom/sql/api` | 校验 profile metadata 后格式化 | 不需要 |
| `resolve_table_references` | `fathom/sql/analyzer` | 使用调用方 catalog 解析已支持 DML/DDL 的目标表名 | 不需要 |
| `lint_text` | `fathom/sql/api` | 对解析后的文档运行 Doris Lint 规则集；返回带候选修复的 findings | 不需要 |
| `fix_text` | `fathom/sql/api` | 应用安全无损 autofix（最小 span edits）；对 error 树以 `FATHOM-LINT-000` 拒绝 | 不需要 |
| `fingerprint_text` | `fathom/sql/api` | 生成稳定 UInt64 SQL 指纹与归一化形式 | 不需要 |

## 请求与响应格式

### 通用输入约定

- SQL 输入类型是 `Bytes`，不是 `String`。源字节只在结果根部保存一次，节点和诊断通过字节 offset 引用它。
- `start_byte` 和 `end_byte` 是半开区间 `[start_byte, end_byte)` 的字节偏移，不是 Unicode 字符索引；所有 span 都应落在输入长度内。
- `dialect` 必须明确选择 `"doris"` 或 `"flink"`；`profile` 对 doris 必须是 `"2.1"`、`"3.x"` 或 `"4.x"`，对 flink 必须是 `"flink-2.3.0"`、`"flink-2.1.3"` 或 `"flink-1.20.5"`；不会静默回退到通用 MySQL 方言。
- `mode` 必须是 `"strict"` 或 `"editor"`。两种模式共享 CST 与诊断形状；`editor` 可以生成 `missing`、`error`、`skipped` 节点来保留半成品输入。

### 解析选项

```moonbit
pub(all) enum ParseMode {
  Strict
  Editor
}

pub struct ParseLimits {
  pub max_bytes : Int
  pub max_tokens : Int
  pub max_recursion_depth : Int
  pub max_recovery_steps : Int
  pub max_diagnostics : Int
}

pub struct ParseOptions {
  // profile/mode/limits 通过构造器和 accessor 使用
}
```

构造方式：

| 构造器 | 说明 |
|---|---|
| `ParseOptions::new(dialect_id, profile_id, mode_id)` | 接收 `"doris"`/`"flink"`、`"2.1"`/`"3.x"`/`"4.x"`（或 flink 的 `"flink-2.3.0"`/`"flink-2.1.3"`/`"flink-1.20.5"`）和 `"strict"`/`"editor"`，使用默认限制。 |
| `ParseOptions::for_profile(profile, mode)` | 使用 `@token.DorisProfile` 和 `ParseMode`，使用默认限制。 |
| `ParseOptions::for_profile_with_limits(profile, mode, limits)` | 使用枚举 profile/mode 和调用方提供的 `ParseLimits`。 |
| `ParseOptions::for_profile_with_metadata(profile, metadata, mode)` | 校验完整 `ProfileMetadata` 后创建选项。 |
| `ParseOptions::from_manifest(profile_id, exact_release, feature_introduction, mode_id)` | 用 manifest 字符串校验 profile 元数据后创建选项。 |

`ParseLimits::default()` 的当前值如下：

| 字段 | 默认值 | 约束 |
|---|---:|---|
| `max_bytes` | `8 * 1024 * 1024`（8 MiB） | 非负；输入超过它返回 `InputTooLarge`。 |
| `max_tokens` | `1_000_000` | 非负；限制单次词法/解析处理的 token 数。 |
| `max_recursion_depth` | `128` | 非负；限制递归下降和表达式递归深度。 |
| `max_recovery_steps` | `10_000` | 非负；限制 editor 模式恢复步数。 |
| `max_diagnostics` | `100` | 非负；限制结果保留的诊断数量。 |

### 解析入口

#### `parse`

```moonbit
pub fn parse(
  raw : Bytes,
  options : ParseOptions,
) -> Result[ParseResult, ParseError]
```

这是完整入口：先校验 limits 和源输入大小，再执行 lexer/parser，最后检查 CST span 不变量并返回 primitive 结果。

#### `parse_with_ids`

```moonbit
pub fn parse_with_ids(
  raw : Bytes,
  dialect_id : String,
  profile_id : String,
  mode_id_value : String,
) -> Result[ParseResult, ParseError]
```

适合 dialect、profile 和模式来自配置或 CLI 参数的场景。它等价于先调用 `ParseOptions::new(dialect_id, profile_id, mode_id_value)`，再调用 `parse`。

#### `parse_with_metadata`

```moonbit
pub fn parse_with_metadata(
  raw : Bytes,
  dialect_id : String,
  profile_id : String,
  exact_release : String,
  feature_introduction : String,
  mode_id_value : String,
) -> Result[ParseResult, ParseError]
```

该入口先调用 `ParseOptions::from_manifest`。`exact_release` 和 `feature_introduction` 必须与 profile 内置 metadata 完全匹配，否则在解析前返回错误。

### `ParseResult`

```moonbit
pub struct ParseResult {
  pub schema_version : String
  pub source_transport : String
  pub dialect : String
  pub profile : String
  pub exact_release : String
  pub feature_introduction : String
  pub mode : String
  pub valid : Bool
  pub recovered : Bool
  pub source_bytes : Bytes
  pub source_byte_length : Int
  pub root : PrimitiveNode
  pub diagnostics : Array[PrimitiveDiagnostic]
}
```

当前结果协议字段为：

- `schema_version`：当前为 `"fathom.parse.v1"`。
- `source_transport`：当前为 `"inline-root-v1"`，表示源字节内嵌在结果根部。
- `profile`、`exact_release`、`feature_introduction`、`mode`：本次调用实际使用的 profile metadata 和模式。
- `valid`：语法结果是否有效。存在语法、词法、资源或 profile feature 诊断时通常为 `false`；editor 恢复不会把错误结果提升为有效。
- `recovered`：是否使用 editor 恢复路径生成了可继续消费的树。
- `source_bytes`、`source_byte_length`：原始源字节及其长度；注释、空白、换行、BOM、Unicode 和非法字节都按原始字节保留。
- `root`：`document` 根 `PrimitiveNode`。
- `diagnostics`：按源顺序排列的结构化诊断数组。

结果方法：

| 方法 | 返回值 | 说明 |
|---|---|---|
| `has_root_only_source()` | `Bool` | 检查源字节是否只由根结果保存一次，即 `source_byte_length == source_bytes.length()`。 |
| `statement(statement_id)` | `PrimitiveNode?` | 按从零开始的 statement id 取对应 statement；不存在时返回 `None`。 |
| `statement_diagnostics(statement_id)` | `Array[PrimitiveDiagnostic]` | 只返回指定 statement 的诊断。 |
| `all_spans_in_bounds()` | `Bool` | 递归验证节点 span、text length 和子节点顺序。 |

### `PrimitiveNode`

```moonbit
pub struct PrimitiveNode {
  pub kind : String
  pub start_byte : Int
  pub end_byte : Int
  pub text_len : Int
  pub children : Array[PrimitiveNode]
}
```

`kind` 是稳定的字符串节点标识。当前实现包含：`document`、`statement`、`select`、`insert`、`update`、`delete`、`merge`、`value_list`、`create_table`、`create_view`、`create_index`、`create_materialized_view`、`column_definition`、`key_clause`、`distribution_clause`、`partition_clause`、`property_list`、`expression`、`token`、`trivia`、`error`、`skipped` 和 `missing`。

`missing` 节点可以是零宽 span，因此不会向无损打印结果中伪造字节；`error` 与 `skipped` 节点保留无法正常解析但属于输入的材料。

### `PrimitiveDiagnostic`

```moonbit
pub struct PrimitiveDiagnostic {
  pub severity : String
  pub code : String
  pub message : String
  pub expected_class : String
  pub start_byte : Int
  pub end_byte : Int
  pub statement_id : UInt
}
```

`statement_id` 是当前输入快照内从 `0U` 开始、按源顺序递增的 statement 标识。它不是跨调用稳定的数据库 ID；每次 parse 都从零重新编号。

### 格式化入口

`api` facade 重新导出 formatter 的类型别名，因此可以从 `@api` 使用 `FormatOptions`、`FormatResult`、`FormatDiagnostic`、`FormatError`、`KeywordCase`、`CommaStyle` 和 `NewlineStyle`。

```moonbit
pub fn format_text(
  raw : Bytes,
  parse_options : ParseOptions,
  format_options : FormatOptions,
) -> Result[FormatResult, ParseError]

pub fn format_with_ids(
  raw : Bytes,
  dialect_id : String,
  profile_id : String,
  mode_id_value : String,
  format_options : FormatOptions,
) -> Result[FormatResult, ParseError]

pub fn format_with_metadata(
  raw : Bytes,
  dialect_id : String,
  profile_id : String,
  exact_release : String,
  feature_introduction : String,
  mode_id_value : String,
  format_options : FormatOptions,
) -> Result[FormatResult, ParseError]
```

格式化入口会先走同一套解析流程，因此 parse 级 `ParseError` 会直接返回。解析诊断会被带入 `FormatResult.diagnostics`；如果 CST 包含 `error`、`missing` 或 `skipped` 材料，formatter 拒绝输出部分结果，返回 `accepted = false` 和空 `output`。

`FormatOptions::default()`：

| 字段 | 默认值 |
|---|---|
| `keyword_case` | `KeywordCase::Upper` |
| `indent` | `2` |
| `line_width` | `100` |
| `comma_style` | `CommaStyle::Trailing` |
| `newline_style` | `NewlineStyle::FollowInput` |
| `trailing_newline` | `true` |

`FormatOptions::new` 拒绝负 `indent` 和非正 `line_width`。字符串枚举转换器接受：`KeywordCase::from_id("upper"/"lower")`、`CommaStyle::from_id("trailing"/"leading")` 和 `NewlineStyle::from_id("follow"/"lf"/"crlf")`；未知 ID 返回 `None`。

```moonbit
pub(all) struct FormatResult {
  pub accepted : Bool
  pub output : Bytes
  pub diagnostics : Array[FormatDiagnostic]
  pub statement_offsets : Array[Int]
}
```

`statement_offsets` 记录每个 statement 在最终格式化输出中的字节起点，顺序与 statement 顺序一致。拒绝格式化时输出为空且 offsets 为空。

### Lint 入口

`fathom/sql/lint` 是独立库（D-01），只消费 syntax 只读视图、dialect 关键字分类，以及可选的 analyzer `AnalysisResult`；它不属于语法有效性通道。`api` facade 重新导出 lint 类型（`LintOptions`、`LintResult`、`LintFinding`、`LintEdit`、`LintDiagnostic`、`RuleOverride`、`LintSeverity`、`RuleSetting`）。

```moonbit
pub fn lint_text(raw : Bytes, parse_options : ParseOptions, lint_options : LintOptions) -> Result[LintResult, ParseError]

pub fn fix_text(raw : Bytes, parse_options : ParseOptions, lint_options : LintOptions) -> Result[LintResult, ParseError]
```

`lint_text` 对解析后的文档运行已配置规则集，返回按源码顺序排序的 findings。`fix_text` 以最小 span edits 应用安全无损 autofix；树含 error/missing/skipped 材料时按 D-33 拒绝，返回 `accepted=false`、空输出、恰好一条 `FATHOM-LINT-000` 诊断——绝不部分编辑。

```moonbit
pub(all) struct LintOptions { overrides : Array[RuleOverride] }
pub(all) enum LintSeverity { Error, Warning, Info }
pub(all) enum RuleSetting { Disabled, Severity(LintSeverity) }
pub(all) struct RuleOverride { code : String, setting : RuleSetting }
```

`LintOptions::new` 会对照注册表校验每个 override；未知规则码返回结构化错误（CLI 映射为 exit 2）。`LintSeverity::from_id` 接受 `"error"`/`"warning"`/`"info"`，未知返回 `None`。

| Code | 名称 | 类别 | 默认 severity | 可修复 |
|---|---|---|---|---|
| `FATHOM-LINT-001` | `unquoted-reserved-word` | style | warning | 是（反引号包裹） |
| `FATHOM-LINT-002` | `version-gated-syntax` | advisory | info | 否 |
| `FATHOM-LINT-003` | `select-star-without-limit` | safety | warning | 否 |
| `FATHOM-LINT-004` | `unknown-table` | correctness | error | 否 |
| `FATHOM-LINT-005` | `unknown-column` | correctness | error | 否 |
| `FATHOM-LINT-006` | `ambiguous-reference` | correctness | warning | 否 |
| `FATHOM-LINT-007` | `function-arity` | correctness | error | 否 |
| `FATHOM-LINT-008` | `deprecated-syntax` | deprecation | info | 否 |

规则 004–007 是 analyzer 增强规则：只有调用方注入 `AnalysisResult`（即提供 catalog）时才触发。无 catalog 时静默跳过（ANLY-01）——因此 wire/CLI 面（无 catalog）只运行规则 001/002/003/008，绝不虚构语义 findings（Pitfall 6）。

**拒绝码：** `FATHOM-LINT-000` 保留为 autofix 引擎级拒绝（D-33）：树含 error/missing/skipped 材料时 `accepted=false`、空输出、恰好一条 `FATHOM-LINT-000` 诊断——镜像 formatter 的 `FATHOM-FORMAT-001`。

### 指纹入口

`fathom/sql/fingerprint` 是独立库（D-01）：把解析后的 CST 归一化为 canonical 字节，再用本地 FNV-1a 64-bit 实现哈希。`api` facade 暴露：

```moonbit
pub(all) struct FingerprintResult {
  pub fingerprint : UInt64
  pub normalized : Bytes
}

pub fn fingerprint_text(raw : Bytes, parse_options : ParseOptions) -> Result[FingerprintResult, ParseError]
```

归一化只折叠 syntactic trivia（D-06）：空白折叠为单空格、关键字大小写经方言分类表转 ASCII 小写、注释剔除；**保留**标识符拼写与大小写、字面量内容、引号风格——仅在这些方面不同的两个查询保证产生不同指纹。

指纹跨空白/关键字大小写/注释稳定，且是 **UInt64**（在 Native、JS、linear-Wasm 上固定 64-bit），因此三目标值一致（FING-01 SC4）。wire 信封把指纹序列化为**十进制 JSON string**（绝不用 number）以避免 JS 宿主 2^53 精度丢失。

> **非加密边界：** FNV-1a 是公开非加密哈希。指纹只用于缓存/差异/CI 标识——**不是** MAC，绝不可用于防篡改、认证或抗碰撞。

### 无损打印

需要精确重放输入时，使用 `fathom/sql/printer`：

```moonbit
import {
  "fathom/sql/api" @api,
  "fathom/sql/printer" @printer,
}

let parsed = @api.parse_with_ids(b"-- note\r\nselect 1", "doris", "4.x", "editor")
match parsed {
  Ok(result) => {
    let raw_again = @printer.print_result(result)
    // raw_again 与输入字节完全相同
  }
  Err(error) => println(error.to_string())
}
```

打印器还提供 `print_transport(ParseResult)`（直接取根部 `source_bytes`）、`print_lossless(SyntaxNode, SourceText)` 和 `print_bytes(SyntaxNode, SourceText)`。打印不会执行格式化，也不会修改 CST。

### 可选名字解析 API

`fathom/sql/analyzer` 不属于解析语法有效性通道。它只消费 `syntax.SyntaxNode`、调用方提供的源字节和 catalog：

```moonbit
pub(all) struct ColumnInfo {
  name : String
  data_type : String
}

pub(all) struct TableInfo {
  name : String
  columns : Array[ColumnInfo]
}

pub(open) trait Catalog {
  table(Self, String) -> TableInfo?
}

pub fn StaticCatalog::new(entries : Array[TableInfo]) -> StaticCatalog
pub fn StaticCatalog::lookup(self : StaticCatalog, name : String) -> TableInfo?
pub fn[T : Catalog] resolve_table_references(
  node : @syntax.SyntaxNode,
  source_bytes : Bytes,
  catalog : T,
) -> Array[String]
```

当前 `resolve_table_references` 只返回 catalog 中存在的、已支持 DML/DDL statement 的目标表名；缺少的表名被省略，不生成 parser 诊断，不做类型推断或 Doris FE 执行语义分析。自 Phase 13（D-03）起，已支持的 statement 族覆盖相同表级 kind 的 Flink 形态：`INSERT`/`UPSERT INTO` 与 `INSERT OVERWRITE`（表名位于可选 `PARTITION` 之前）、`UPDATE`、`DELETE`、`CREATE TABLE`、`CREATE VIEW`，均通过同一就地走查解析，无独立 Flink 入口。范围为表级：column/identifier 级引用解析与类型诊断按 D-24 顺延 v2；`CREATE VIEW`/`INSERT ... SELECT` 查询体不会被走查；表缺失或无可注入 catalog 时结果缺省/为空，且不改变 parser validity（ANLY-01）。`StaticCatalog` 的表名 key 当前区分大小写，重复表名采用最后一项覆盖前一项。

## 错误码与错误响应

### 调用级 `ParseError`

调用级失败通过 `Result` 的 `Err(ParseError)` 返回，通常表示输入尚未进入可消费的 parse result：

| 错误构造 | 触发条件 |
|---|---|
| `UnknownProfile(profile_id~)` | profile 不是 doris 的 `2.1`/`3.x`/`4.x` 或 flink 的 `flink-2.3.0`/`flink-2.1.3`/`flink-1.20.5`。 |
| `UnknownMode(mode_id~)` | mode 不是 `strict` 或 `editor`。 |
| `ProfileMetadataMismatch(...)` | manifest 或 metadata 的 release、profile identity 或 feature introduction 与内置 profile 不一致。 |
| `UnsupportedFeatureIntroduction(feature_introduction~)` | feature introduction 字符串不在当前支持的 metadata 集合中。 |
| `InputTooLarge(requested_bytes~, max_bytes~)` | 输入字节数超过 `ParseLimits.max_bytes`。 |
| `InvalidLimit(limit_name~, value~)` | 任一 parse limit 为负数。 |
| `InvalidSyntaxTree` | parser 生成的 CST 未通过 span、text length 或子节点顺序不变量检查。 |

### 结果内 parser 诊断

语法能够生成 `ParseResult` 时，错误不会以网络状态码返回，而是放在 `result.diagnostics` 中，并保留源字节与 CST：

| code | 含义 |
|---|---|
| `FATHOM-PARSE-001` | statement 末尾存在不符合预期的 trailing material。 |
| `FATHOM-PARSE-002` | 通用语法错误，例如缺少 keyword、symbol、expression、identifier 或 clause。 |
| `FATHOM-PARSE-003` | 非法源编码或未闭合的词法材料。 |
| `FATHOM-PARSE-004` | 达到 parser 资源限制，例如 token、递归、恢复或诊断预算。 |
| `FATHOM-PARSE-006` | 选定 profile 不支持的 Doris feature，例如较早 profile 中的 `QUALIFY`、`TABLET` 或 `MERGE`。 |
| `FATHOM-PARSE-007` | 选定 profile 中未实现/不支持的 statement。 |

这些 code 应作为字符串处理。诊断消息和 `expected_class` 用于展示与定位，具体定位通过 `start_byte`/`end_byte` 和 `statement_id` 获取。代码 `FATHOM-PARSE-005` 目前没有在 parser 实现中作为公开诊断生成。

### Formatter 诊断与错误

格式化入口的 parse 级失败仍使用 `ParseError`。能返回 `FormatResult` 时，formatter 诊断使用与 parser 相同的字段形状：

```moonbit
pub(all) struct FormatDiagnostic {
  pub severity : String
  pub code : String
  pub message : String
  pub expected_class : String
  pub start_byte : Int
  pub end_byte : Int
  pub statement_id : UInt
}
```

当前 formatter refusal code 为：

| code | 含义 |
|---|---|
| `FATHOM-FORMAT-001` | CST 含有 `error`、`missing` 或 `skipped` 材料，formatter 拒绝生成部分输出。 |

直接使用 formatter package 的 `FormatError` 还可能返回：`InvalidIndent`、`InvalidLineWidth`、`UnknownKeywordCase`、`UnknownCommaStyle`、`UnknownNewlineStyle` 和 `InvalidSyntaxTree`。通过 `api.format_text` 时，格式选项应先使用有效枚举和 `FormatOptions::new` 构造；parse 相关错误则按上面的 `ParseError` 返回。

## Wire 导出（JS ESM / linear-Wasm）

`binding` 包（`fathom/sql/binding`）是一个 `foreign_library` facade，把稳定的原始类型 wire 契约暴露给 JavaScript ESM 与 linear-Wasm 宿主。每个导出都返回 UTF-8 编码的 JSON `Bytes`；MoonBit ADT、对象句柄或宿主内存地址都不会跨过这个边界。全部七个导出同时登记在 `binding/moon.pkg` 的 `js`/`wasm` `exports` 列表与 `binding/exports.mbt` 的 `#export_name` 中——缺少任一登记都会编译成功但构建产物静默缺少该符号（Pitfall 3/8）。

| 导出 | 签名 | 结果信封 |
|---|---|---|
| `fathom_parse_v1` | `(raw: Bytes, dialect: String, profile: String, mode: String) -> Bytes` | `fathom.parse.v1` |
| `fathom_format_v1` | `(raw, dialect, profile, mode, keyword_case, indent, line_width, comma_style, newline_style, trailing_newline) -> Bytes` | `fathom.format.v1` |
| `fathom_complete_v1` | `(raw: Bytes, dialect: String, profile: String, cursor_byte: Int) -> Bytes` | `fathom.complete.v1` |
| `fathom_lint_v1` | `(raw: Bytes, dialect: String, profile: String, mode: String, overrides: Bytes, fix: Bool) -> Bytes` | `fathom.lint.v1` |
| `fathom_fingerprint_v1` | `(raw: Bytes, dialect: String, profile: String, mode: String) -> Bytes` | `fathom.fingerprint.v1` |
| `fathom_dialect_v1` | `(dialect: String) -> Bytes` | `fathom.dialect.v1`（元数据查询） |
| `fathom_capabilities_v1` | `() -> Bytes` | `fathom.capabilities.v1`（元数据查询） |

A4 导出顺序让 parse/format/complete/lint/fingerprint 原始类型的 `dialect` 紧跟 `raw`，与 `ParseOptions::new` 和 CLI 保持一致。schema v2 bump 是**纯加法**（Pitfall V6）：新增 `fathom.lint.v1` 与 `fathom.fingerprint.v1`，原有五个命名空间（parse/format/complete/error/capabilities）保持不变，既有消费者不受影响。

`fathom_lint_v1` 接收 UTF-8 JSON `overrides` 数组（`{"code": "<FATHOM-LINT-0xx>", "setting": "off|error|warning|info"}`）；`[]` 或空字节即默认注册表。畸形 JSON 或未知 code/severity 返回结构化 `fathom.error.v1` 错误（绝不静默回退）。`fix=false` 报告 findings，`fix=true` 应用安全 autofix（D-33 拒绝时 `accepted=false` 且恰好一条 `FATHOM-LINT-000`）。`fathom_fingerprint_v1` 返回 `fathom.fingerprint.v1` 信封，其 `fingerprint` 字段是**十进制 JSON string**（绝不用 number，2^53 精度），`normalized` 字段携带 canonical 字节。

### 补全信封（`fathom.complete.v1`）

`fathom_complete_v1` 返回编辑器快照在 UTF-8 字节 `cursor_byte` 处的有界语法补全候选。结果信封携带与 parse/format 信封相同的 `dialect`/`profile` 选择元数据，外加补全项：

```json
{
  "schema_version": "fathom.complete.v1",
  "source_transport": "inline-root-v1",
  "dialect": "flink",
  "profile": "flink-2.3.0",
  "is_incomplete": false,
  "items": [
    {
      "label": "FROM",
      "detail": "SQL syntax keyword",
      "start_byte": 7,
      "end_byte": 9,
      "new_text": "FROM"
    }
  ]
}
```

- `start_byte`/`end_byte` 是半开区间 `[start_byte, end_byte)` 的 UTF-8 字节偏移；替换区间覆盖已输入的词缀，`end_byte` 等于光标字节。
- 补全项文本是方言中立的（D-10/D-28）：`detail` 恒为 `"SQL syntax keyword"`，补全项内容不出现方言名——方言只存在于信封元数据中。
- 补全有界为 `MAX_CANDIDATES = 32` 项。

补全错误响应使用 `fathom.error.v1` 信封：

| code | 触发条件 |
|---|---|
| `FATHOM-SCHEMA-003` | `profile` 未知/不支持（例如在 `flink` 下使用 Doris profile）。 |
| `FATHOM-SCHEMA-007` | `dialect` 未知。 |
| `FATHOM-COMPLETE-001` | `cursor_byte` 超出 `[0, raw.length()]`（`InvalidCursor`）。 |
| `FATHOM-COMPLETE-002` | 无效的源输入。 |
| `FATHOM-COMPLETE-003` | 输入超过 8 MiB 源大小限制。 |

## 速率限制

没有 HTTP 速率限制、连接配额或服务端窗口。Fathom 是纯库，调用方自行决定并发和生命周期。

为防止单次不可信输入消耗无限资源，解析器提供的是**单次调用资源预算**，不是网络 rate limit：`max_bytes`、`max_tokens`、`max_recursion_depth`、`max_recovery_steps` 和 `max_diagnostics`。它们必须是非负整数；超过预算时会保留有界的错误/跳过材料并生成 `FATHOM-PARSE-004`，而不是等待外部服务或静默丢弃源字节。

## 完整示例

```moonbit
import {
  "fathom/sql/api" @api,
  "fathom/sql/formatter" @formatter,
  "fathom/sql/printer" @printer,
}

fn main {
  let raw = b"select id, name from users"
  let options = match @api.ParseOptions::new("doris", "4.x", "strict") {
    Ok(value) => value
    Err(error) => panic()
  }
  let parsed = match @api.parse(raw, options) {
    Ok(value) => value
    Err(error) => panic()
  }
  println(parsed.valid.to_string())
  println(parsed.diagnostics.length().to_string())

  let formatted = @api.format_text(
    raw,
    options,
    @formatter.FormatOptions::default(),
  )
  match formatted {
    Ok(result) if result.accepted => {
      println(result.output.to_string())
      assert_eq(@printer.print_result(parsed), raw)
    }
    Ok(result) => println(result.diagnostics[0].code)
    Err(error) => println(error.to_string())
  }
}
```

该示例展示了同一份源字节如何先生成带诊断的 `ParseResult`，再生成格式化结果；原始输入的精确重放通过 `printer.print_result` 完成，而不是读取格式化输出。
