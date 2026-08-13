# Phase 6: Lint and Fingerprint — Pattern Map

**Mapped:** 2026-08-10
**Files analyzed:** 24（10 新增 / 14 修改）
**Analogs found:** 23 / 24（唯一无直接 analog 的是 `fingerprint/hash.mbt` —— 全新纯函数算法）

> 本映射基于对既有代码库的直接读源。所有代码摘录均来自当前仓库真实文件，行号已逐一定位。正文用中文，代码/路径/符号保留英文。

---

## File Classification

| 新/修改文件 | Role | Data Flow | Closest Analog | Match Quality |
|------------|------|-----------|----------------|---------------|
| `lint/moon.pkg` | config（包依赖声明） | — | `formatter/moon.pkg` | exact |
| `lint/rules.mbt` | model（规则元数据 + 枚举） | static-data | `formatter/options.mbt`（`KeywordCase` 枚举 + `from_id`，options.mbt:101-110） | role-match |
| `lint/registry.mbt` | service（默认注册表 + `LintOptions` 覆盖解析） | request-response（配置查找） | `formatter/options.mbt`（`FormatOptions::new` 校验模式）+ `binding/schema.mbt`（`validate_*` 返回 `Result` 模式） | role-match |
| `lint/engine.mbt` | service（CST 走查 + statement_family 分发） | transform | `formatter/format.mbt`（`format` 的 statement 分发循环，format.mbt:6-65）+ `formatter/layout.mbt`（`statement_family`，layout.mbt:329-335） | role-match |
| `lint/fixes.mbt` | service（最小 span edits + D-33 安全闸） | transform | `formatter/format.mbt`（`find_first_unsafe`/`refusal_diagnostic`，format.mbt:88-98,145-154）+ `formatter/refuse.mbt`（`first_unsafe_element`，refuse.mbt:6-17） | exact |
| `lint/lint_test.mbt` | test | — | `completion/completion_test.mbt`（包内白盒测试模式）+ `test/formatter_test.mbt`（快照纪律） | role-match |
| `fingerprint/moon.pkg` | config（包依赖声明） | — | `formatter/moon.pkg` | exact |
| `fingerprint/normalize.mbt` | service（CST → canonical bytes） | transform | `formatter/case.mbt`（`rewrite_keyword_case`/`ascii_case_fold`，case.mbt:21-50）+ `formatter/format.mbt`（`layout_document_trivia`，format.mbt:118-143） | role-match |
| `fingerprint/hash.mbt` | utility（FNV-1a 64-bit 纯函数） | transform | 无直接 analog（全新算法）；字节循环纯函数形状仿 `formatter/case.mbt` `ascii_case_fold`（case.mbt:35-50） | partial |
| `fingerprint/hash_test.mbt` | test | — | `source/source.mbt`（包内 `test` 块）+ `test/keyword_test.mbt:38-47`（ASCII fold 测试） | role-match |
| `api/api.mbt`（增补） | service facade（`lint_text`/`fix_text`/`fingerprint_text` + 类型再导出） | request-response | `api.mbt` `format_text`/`format_with_ids`（api.mbt:566-580,615-627）+ D-38 类型别名块（`pub type FormatOptions = @formatter.FormatOptions`） | exact |
| `binding/schema.mbt`（增补） | config/contract（schema v2 bump） | — | `binding/schema.mbt` `validate_schema_version`（schema.mbt:20-28） | exact |
| `binding/exports.mbt`（增补） | adapter（wire 导出） | request-response | `binding/exports.mbt` `fathom_parse_v1`（exports.mbt:31-34）+ `fathom_format_v1`（exports.mbt:39-75） | exact |
| `binding/json.mbt`（增补） | utility（序列化） | transform | `binding/json.mbt` `format_diagnostic_json`（json.mbt:41-53）+ `binding/schema.mbt` `format_result_json`（schema.mbt:116-140） | exact |
| `binding/moon.pkg`（增补） | config（exports 列表） | — | 当前 `binding/moon.pkg` js/wasm exports 列表 | exact |
| `fathom-sql/args.mbt`（增补） | controller（CLI 参数解析） | request-response | `fathom-sql/args.mbt` `parse_args` + `UsageError`（args.mbt:1-120） | exact |
| `fathom-sql/run.mbt`（增补） | controller（CLI 运行） | request-response | `fathom-sql/run.mbt` `run_format`/`run_parse` + `parse_error_outcome`（run.mbt:28-96,98-125） | exact |
| `fathom-sql/main.mbt`（增补） | controller（入口分发） | request-response | `fathom-sql/main.mbt` subcommand `match` | exact |
| `fathom-sql/cli_test.mbt`（增补） | test | — | `fathom-sql/cli_test.mbt`（`command_stdin` + 退出码矩阵） | exact |
| `parity/fingerprint_parity_test.mbt` | test（跨目标一致性） | — | `parity/parity_test.mbt`（`fixture_source`/`run_fixture` 模式）+ `parity/export_smoke_test.mbt`（envelope 断言） | exact |
| `parity/run_js.mbt`（增补） | adapter（js 冒烟） | — | 当前 `parity/run_js.mbt` | exact |
| `parity/run_wasm.mbt`（增补） | adapter（wasm 冒烟） | — | 当前 `parity/run_wasm.mbt` | exact |
| `docs/API.md` + `docs/zh-CN/API.md`（增补） | docs | — | `docs/API.md` 既有 "Formatting Entry Points" 与 "Wire Exports" 章节结构（API.md:200-260, 430-500） | exact |

---

## Pattern Assignments

### `lint/moon.pkg`（config）

**Analog:** `formatter/moon.pkg`（library 包依赖声明）

```moonbit
// formatter/moon.pkg（verbatim）
pkgtype(kind: "library")
import {
  "fathom/sql/source" @source,
  "fathom/sql/token" @token,
  "fathom/sql/syntax" @syntax,
  "fathom/sql/dialect" @dialect,
  "moonbitlang/core/buffer" @buffer,
  "moonbitlang/core/debug" @debug,
  "moonbitlang/core/encoding/utf8" @utf8,
}
```

`lint/moon.pkg` 依 D-01/D-21 import 面：`@syntax` + `@dialect` + `@source` + `@formatter`（复用 `first_unsafe_element`，D-33）+ 可选 `@analyzer`（增强规则）；**永不 import `@parser`**（D-21/D-27 单向纪律）。不需要的 `@token`/`@buffer` 不引入（依赖面最小化）。

### `lint/rules.mbt`（model）

**Analog:** `formatter/options.mbt`（枚举 + `from_id` + 默认值模式）

**枚举 + from_id 模式**（options.mbt:101-110，`KeywordCase::from_id` verbatim）：
```moonbit
/// String-id mapping for the CLI flag surface (plan 03-04) and the
/// option-combination test driver (plan 03-03), mirroring
/// DorisProfile::from_id (token.mbt:241-248). Unknown ids return None.
pub fn KeywordCase::from_id(id : String) -> KeywordCase? {
  match id {
    "upper" => Some(KeywordCase::Upper)
    "lower" => Some(KeywordCase::Lower)
    _ => None
  }
}
```

`LintSeverity`/`RuleSetting` 枚举与 `LintSeverity::from_id` 完全镜像此形状（RESEARCH Pattern 1 给出推荐签名，`error`/`warning`/`info`/`off` 映射，未知返回 `None`）。`LintRule` 结构体（`code`/`name`/`category`/`default_severity`/`fixable`/`applies_to`/`enabled`）用 `pub(all)` —— 与 `FormatDiagnostic` 一致，跨包字面量构造要求 all-public（error.mbt:20-24 注释：moon 0.1.20260724 上跨包 pub-struct 字面量需要 all-public）。

### `lint/registry.mbt`（service）

**Analog:** `formatter/options.mbt` 构造校验 + `binding/schema.mbt` `validate_*` 返回 `Result`

**构造 + 校验模式**（options.mbt:60-78，`FormatOptions::new` 形状 verbatim）：
```moonbit
pub fn FormatOptions::new(
  keyword_case : KeywordCase,
  indent : Int,
  line_width : Int,
  comma_style : CommaStyle,
  newline_style : NewlineStyle,
  trailing_newline : Bool,
) -> Result[FormatOptions, FormatError] {
  if indent < 0 || indent > MAX_INDENT {
    return Err(InvalidIndent(value=indent))
  }
  if line_width <= 0 {
    return Err(InvalidLineWidth(value=line_width))
  }
  Ok({ ... })
}
```

`registry.mbt` 的默认注册表 = 静态 `Array[LintRule]`（8 条规则，FATHOM-LINT-001..008，RESEARCH 表）；`LintOptions` 覆盖解析 = 校验优先的 `Result` 返回（镜像 `FormatOptions::new` 与 `validate_dialect_profile`，schema.mbt:46-53）——非法 `--rule <code>=<severity|off>` 值 → 结构化错误（CLI exit 2，D-04）。**注册表是公共契约**（D-02 costly）：规则码一经发布冻结。

### `lint/engine.mbt`（service）

**Analog:** `formatter/format.mbt` statement 分发循环 + `formatter/layout.mbt` `statement_family`

**语句族分发**（layout.mbt:329-335 verbatim）：
```moonbit
/// The first ChildNode under a Statement node that is not itself Statement.
fn statement_family(node : @syntax.SyntaxNode) -> @syntax.SyntaxKind? {
  for child in node.children() {
    match child {
      @syntax.SyntaxElement::ChildNode(child_node) => {
        if !(child_node.kind() is @syntax.SyntaxKind::Statement) {
          return Some(child_node.kind())
        }
      }
      @syntax.SyntaxElement::Leaf(_) => ()
    }
  }
  None
}
```

**引擎主循环**（format.mbt:45-66 的 Statement 遍历形状 verbatim）：
```moonbit
for child in root.children() {
  match child {
    @syntax.SyntaxElement::ChildNode(node) if node.kind() is @syntax.SyntaxKind::Statement => {
      match statement_family(node) {
        Some(family) => layout_statement(family, node, source, options, out)
        None => ()
      }
      ...
    }
    @syntax.SyntaxElement::Leaf(leaf) => { ... }
    @syntax.SyntaxElement::ChildNode(_) => ()
  }
}
```

`engine.mbt` 的 `run_rules(root, source, context, analysis?, overrides)` 按 `statement_family` 分发到各规则的判定函数；判定函数消费 leaf 序列（`leaf.kind`/`leaf.span`，syntax.mbt:55-58）+ `source.slice(span)`（source.mbt:96-104）+ `@dialect.classification_of(context, raw)`（classification.mbt:99-106，关键字判定的**唯一**来源，D-28）。可选 `AnalysisResult`（analysis.mbt:34-59）在无 catalog 时静默跳过（ANLY-01）——`AnalysisDiagnostic` 已带 `start_byte`/`end_byte`（analysis.mbt:40-46），映射到 FATHOM-LINT-004..007 时保留 span。

### `lint/fixes.mbt`（service）

**Analog:** `formatter/refuse.mbt` `first_unsafe_element`（安全闸）+ `formatter/format.mbt` `find_first_unsafe`/`refusal_diagnostic`（拒绝契约）

**安全闸直接复用**（refuse.mbt:6-17 verbatim）：
```moonbit
/// Recursive scan for material that must never be formatted (D-33): Error /
/// Skipped / Missing nodes and SourceError / SourceSkipped leaves
/// (syntax.mbt:30-37 predicates 123-137). Returns the first unsafe element in
/// document order, mirroring the printer's recursive element walk (printer.mbt:
/// 5-34) with a read-only verdict instead of byte emission.
pub fn first_unsafe_element(root : @syntax.SyntaxNode) -> @syntax.SyntaxElement? {
  for child in root.children() {
    let bad = match child {
      @syntax.SyntaxElement::ChildNode(node) =>
        node.is_error() || node.is_skipped() || node.is_missing() ||
        (first_unsafe_element(node) is Some(_))
      @syntax.SyntaxElement::Leaf(leaf) =>
        leaf.kind is @syntax.LeafKind::SourceError ||
        leaf.kind is @syntax.LeafKind::SourceSkipped
    }
    if bad {
      return Some(child)
    }
  }
  None
}
```

**拒绝诊断模板**（format.mbt:145-154 verbatim，`fixes.mbt` 的 `FATHOM-LINT-000` 拒绝诊断镜像此形状，severity/code 改为 `"error"`/`"FATHOM-LINT-000"`）：
```moonbit
fn refusal_diagnostic(span : @source.Span, statement_id : UInt) -> FormatDiagnostic {
  {
    severity: "error",
    code: "FATHOM-FORMAT-001",
    message: "refusing to format a tree containing error/missing/skipped material",
    expected_class: "format",
    start_byte: span.start_byte,
    end_byte: span.end_byte,
    statement_id: statement_id,
  }
}
```

**编辑安全：** edit span 只替换 `LeafKind::SourceToken` 的 span（trivia 是独立 leaf，天然不重叠，Pitfall 1）；`@source.Span::checked` 校验（source.mbt:15-20，ASVS V5）；重叠 edit 跳过并标记；`api/fix_text` 应用后**重新 parse 输出**做 round-trip 断言（D-03 防御纵深）。

### `lint/lint_test.mbt`（test）

**Analog:** `completion/completion_test.mbt`（包内白盒测试）+ `test/formatter_test.mbt`（快照纪律）

包内 `test "..."` 块 + `assert_eq`/`assert_true` 直接调包内函数（completion_test.mbt:19-46 形状）；规则判定用正反例锁定（`SELECT order` flag / `ORDER BY` 不 flag / `` SELECT `order` `` 不 flag，Pitfall 2）；autofix 用 round-trip 断言（fix 后 untouched 字节逐字节比对 + reparse 干净）。

### `fingerprint/moon.pkg`（config）

**Analog:** `formatter/moon.pkg`。依 D-01 import 面：`@syntax` + `@dialect` + `@source` 三包（**不 import analyzer，无 catalog 依赖**，D-01 明文）。`moon.pkg` 中 `pkgtype(kind: "library")` + 各 import 别名。

### `fingerprint/normalize.mbt`（service）

**Analog:** `formatter/case.mbt`（关键字折叠模板）+ `formatter/format.mbt` `layout_document_trivia`（trivia/BOM/注释处理）

**关键字折叠模板**（case.mbt:21-35 verbatim，fingerprint 关键字折叠 = `rewrite_keyword_case(context, raw, KeywordCase::Lower)` 语义）：
```moonbit
/// Case-selected keyword rewrite (D-26 keyword_case dimension): Upper renders
/// the canonical classification word (D-29), Lower renders its ASCII case-fold
/// (SQL keywords are ASCII; every classification word is uppercase by
/// construction). None is not a KeywordCase value, so every word is rewritten
/// to one of the two canonical spellings. Identifiers, quoted names, strings,
/// comments, and hints are never rewritten: classification_of only matches a
/// bare unquoted word, so any token whose raw bytes are not a plain word
/// (quoted `SELECT`, string literals, punctuation) passes through unchanged.
pub fn rewrite_keyword_case(context : @dialect.DialectContext, raw : Bytes, case : KeywordCase) -> Bytes {
  match case {
    KeywordCase::Upper => rewrite_keyword(context, raw)
    KeywordCase::Lower => {
      match @dialect.classification_of(context, raw) {
        Some(entry) => ascii_case_fold(entry.word)
        None => raw
      }
    }
  }
}
```

**ASCII fold 助手**（case.mbt:35-50 verbatim）：
```moonbit
fn ascii_case_fold(raw : Bytes) -> Bytes {
  let out : Array[Byte] = []
  let mut index = 0
  while index < raw.length() {
    let byte = raw[index].to_int()
    let folded = if byte >= 65 && byte <= 90 { byte + 32 } else { byte }
    out.push(folded.to_byte())
    index = index + 1
  }
  Bytes::from_array(out)
}
```

**trivia/BOM 分类**（format.mbt:118-143 `layout_document_trivia` 的 leaf 分类形状 verbatim——fingerprint 的 whitespace 折叠为单空格、Comment 整体剔除、Bom 剔除复用同一 leaf-kind 分派）：
```moonbit
fn layout_document_trivia(leaf : @syntax.SyntaxLeaf, source : @source.SourceText, out : Layout) -> Unit {
  let bytes = match source.slice(leaf.span) {
    Some(bytes) => bytes
    None => { out.failed = Some(@syntax.SyntaxElement::Leaf(leaf)); return }
  }
  if leaf.kind is @syntax.LeafKind::SourceToken {
    out.emit_token(bytes)
  } else if is_bom(bytes) {
    out.emit(bytes, false)
  } else if is_comment(bytes) { ... }
}
```

fingerprint 归一化（D-06）：`SourceTrivia` 中 `Comment` 整体剔除（不产生字节）；`Whitespace`/`Newline` 折叠为单 `0x20`（仅在两个已发射 token 之间发射一个；首/尾 trivia 不产生字节）；`Bom` 剔除。`SourceToken`：`classification_of` 命中 → 发射 ASCII 小写 canonical word；否则**原样发射**（标识符/字面量/引号风格全保留）。`SourceError`/`SourceSkipped` 原样发射（总函数，Open Question 3 推荐）。**绝不归一化序列化 JSON**（Pitfall V4）。

### `fingerprint/hash.mbt`（utility）

**无直接 analog**（全新纯函数）。形状仿 `ascii_case_fold` 的字节循环纯函数（case.mbt:35-50）+ RESEARCH Pattern 5 推荐签名。执行器首任务须核实 MoonBit `UInt64` 字面量后缀与环绕乘法语义（Open Question 1，`[ASSUMED]`），用空串/`b"a"` 测试向量锁快照（Open Question 2）。

### `fingerprint/hash_test.mbt`（test）

**Analog:** `source/source.mbt`（包内 `test` 块）+ `test/keyword_test.mbt:38-47`（ASCII fold 测试）。用 `test "..."` 块锁定：FNV-1a 测试向量（`fnv1a64(b"") = 0xcbf29ce484222325`、`fnv1a64(b"a") = 0xaf63dc4c8601ec8c`）+ 归一化不变量（`SELECT a, b` ≡ `select\n a , b` ≡ `SELECT /*c*/ a, b`；`SELECT "A"` ≠ `SELECT 'A'`、`SELECT a` ≠ `SELECT A`、`SELECT 'x'` ≠ `SELECT 'y'`）。

### `api/api.mbt`（增补 `lint_text`/`fix_text`/`fingerprint_text` + 类型再导出）

**Analog:** `api.mbt` `format_text`/`format_with_ids` + D-38 类型别名块

**共享核心入口模板**（api.mbt:566-580 `format_text` verbatim——`lint_text`/`fix_text`/`fingerprint_text` 复用同款内部 parse：`validate_limits` → `SourceText::new_with_limit` → `parser.parse_with_limits_context` → `is_valid` 门禁 → 核心调用）：
```moonbit
pub fn format_text(
  raw : Bytes,
  parse_options : ParseOptions,
  format_options : FormatOptions,
) -> Result[FormatResult, ParseError] {
  let limits = parse_options.limits
  match validate_limits(limits) { Ok(_) => (); Err(error) => return Err(error) }
  let source = match @source.SourceText::new_with_limit(raw, limits.max_bytes) {
    Ok(source) => source
    Err(@source.SourceError::InputTooLarge(requested_bytes~, max_bytes~)) => {
      return Err(InputTooLarge(requested_bytes~, max_bytes~))
    }
  }
  let parser_mode = match parse_options.mode { ... }
  let parser_limits = @parser.ParserLimits::new(...)
  let parsed = @parser.parse_with_limits_context(source, parse_options.dialect_context, parser_mode, parser_limits)
  if !parsed.root.is_valid(source.byte_length()) {
    return Err(InvalidSyntaxTree)
  }
  ...
}
```

**D-38 类型再导出模板**（api.mbt:463-472 形状 verbatim——`LintOptions`/`LintResult`/`FixResult`/`FingerprintResult` 类型别名走同一 facade）：
```moonbit
pub type FormatOptions = @formatter.FormatOptions
pub type FormatResult = @formatter.FormatResult
pub type FormatDiagnostic = @formatter.FormatDiagnostic
pub type FormatError = @formatter.FormatError
```

**诊断形状**（api.mbt:305-313 `PrimitiveDiagnostic` verbatim——`LintFinding`/`LintDiagnostic` 镜像同六字段扁平形状）：
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

### `binding/schema.mbt`（增补 schema v2 bump）

**Analog:** `binding/schema.mbt` `validate_schema_version`（schema.mbt:20-28 verbatim）
```moonbit
pub fn validate_schema_version(version : String) -> Result[Unit, SchemaError] {
  match version {
    PARSE_SCHEMA_VERSION |
    FORMAT_SCHEMA_VERSION |
    COMPLETE_SCHEMA_VERSION |
    "fathom.error.v1" |
    "fathom.capabilities.v1" => Ok(())
    _ => Err(UnsupportedSchemaVersion(version~))
  }
}
```

**推荐扩展（纯加法，Pitfall V6——加法非替换）：** 新增 `pub const LINT_SCHEMA_VERSION : String = "fathom.lint.v1"` 与 `pub const FINGERPRINT_SCHEMA_VERSION : String = "fathom.fingerprint.v1"`，在 match 中增加两常量分支；现有 5 个命名空间保持不变。`binding/export_smoke_test.mbt` 断言旧命名空间仍可用。

### `binding/exports.mbt`（增补 `fathom_lint_v1`/`fathom_fingerprint_v1`）

**Analog:** `binding/exports.mbt` `fathom_parse_v1`（exports.mbt:31-34）+ `fathom_format_v1`（exports.mbt:39-75，多参数 + 错误映射）

**单结果导出模板**（exports.mbt:31-34 verbatim）：
```moonbit
#export_name("fathom_parse_v1")
pub fn fathom_parse_v1(raw : Bytes, dialect : String, profile : String, mode : String) -> Bytes {
  match @api.parse_with_ids(raw, dialect, profile, mode) {
    Ok(result) => json_bytes(parse_result_json(result))
    Err(error) => parse_error_bytes(error)
  }
}
```

**多参数 + dialect-first 校验模板**（exports.mbt:45-58 `fathom_format_v1` 前半 verbatim——`fathom_lint_v1` 的 `overrides`/`fix` 参数与 `fathom_fingerprint_v1` 仿此）：
```moonbit
let selection = match @api.ParseOptions::new(dialect, profile, mode) {
  Ok(options) => options
  Err(error) => return parse_error_bytes(error)
}
let keyword_case_value = match @api.KeywordCase::from_id(keyword_case) {
  Some(value) => value
  None => return error_bytes("FATHOM-FORMAT-002", "unsupported keyword case: \{keyword_case}")
}
```

错误码映射沿用 `parse_error_json` 的 `match error` 到 code+message 形状（schema.mbt:173-215）；`#export_name` 必须在产出 artifact 的包（`binding/`）中声明（Pitfall 17），且必须在 `binding/moon.pkg` js+wasm `exports` 列表同时注册（exports 列表缺注册 = 编译通过但产物缺符号，docs/API.md Wire Exports 节明示）。

### `binding/json.mbt`（增补 `lint_result_json`/`fingerprint_result_json`）

**Analog:** `binding/json.mbt` `format_diagnostic_json`（json.mbt:41-53）+ `binding/schema.mbt` `format_result_json`（schema.mbt:116-140）

**诊断序列化模板**（json.mbt:41-53 verbatim）：
```moonbit
fn format_diagnostic_json(diagnostic : @api.FormatDiagnostic) -> Json {
  {
    "severity": Json::string(diagnostic.severity),
    "code": Json::string(diagnostic.code),
    "message": Json::string(diagnostic.message),
    "expected_class": Json::string(diagnostic.expected_class),
    "start_byte": Json::number(diagnostic.start_byte.to_double()),
    "end_byte": Json::number(diagnostic.end_byte.to_double()),
    "statement_id": Json::number(diagnostic.statement_id.to_double()),
  }
}
```

**字节数组序列化**（json.mbt:7-14 `byte_array_json` verbatim）：
```moonbit
fn byte_array_json(bytes : Bytes) -> Json {
  let values : Array[Json] = []
  for byte in bytes {
    values.push(Json::number(byte.to_int().to_double()))
  }
  Json::array(values)
}
```

**⚠️ `UInt64` 指纹序列化反模式（勿复制）：** 现 `schema.mbt` 的 `Json::number(result.source_byte_length.to_double())`（schema.mbt:107 附近）对 UInt64 **不安全**——`to_double()` 在 > 2^53 丢精度，JS 宿主读舍入值。`fingerprint_result_json` 必须 `"fingerprint": Json::string(result.fingerprint.to_string())`（十进制 string），`"normalized"` 走 `byte_array_json`（与 `source_bytes` 同约定）。这是本阶段**唯一无既有 analog 的序列化点**。

### `binding/moon.pkg`（增补 exports 列表）

**Analog:** 当前 `binding/moon.pkg`。`js` 与 `wasm` 两个 `exports` 数组各追加 `"fathom_lint_v1"`/`"fathom_fingerprint_v1"`；import 面增加 `fathom/sql/lint` @lint 与 `fathom/sql/fingerprint` @fingerprint（经 api 门面调用，避免 binding↔lint 直接依赖）。

### `fathom-sql/args.mbt`（增补 `lint`/`fingerprint` 子命令 + `--rule`/`--fix`/`--normalized`）

**Analog:** `fathom-sql/args.mbt` `parse_args` + `UsageError`（args.mbt:1-120）

**子命令白名单模板**（args.mbt:51-58 verbatim，白名单增加 `lint`/`fingerprint`）：
```moonbit
pub fn parse_args(args : Array[String]) -> Result[Command, UsageError] {
  if args.length() == 0 { return Err(MissingSubcommand) }
  let subcommand = args[0]
  if subcommand != "parse" && subcommand != "format" && subcommand != "lsp" {
    return Err(UnknownSubcommand(sub=subcommand))
  }
  ...
}
```

**可重复 flag 解析模板**（args.mbt:70-118 的 `--keyword-case` 分支形状——`--rule <code>=<severity|off>` 可重复，非法值 → `UnknownValue` → exit 2）：`Command` 结构新增 `overrides: Array[RuleOverride]` / `fix: Bool` / `normalized: Bool` 字段（字段保持 `pub(all)` 以便 cli_test.mbt 跨包构造，args.mbt:27-36 注释）。`usage_error_message` 同步新增分支（args.mbt:160-190 形状）。

### `fathom-sql/run.mbt`（增补 `run_lint`/`run_fingerprint`）

**Analog:** `fathom-sql/run.mbt` `run_format`/`run_parse` + `parse_error_outcome` + `render_diagnostics`

**D-39 退出码映射**（run.mbt:25-35 注释 verbatim——`run_lint`/`run_fingerprint` 沿用 0/1/2）：
```moonbit
/// D-39 exit mapping:
/// 0 = accepted — stdout carries the formatted SQL / serialized parse
///     envelope / (lsp) the server loop ran to completion, stderr empty;
/// 1 = parse failure or format refusal — stdout empty, diagnostics on stderr
///     (the api core prepends the parse diagnostics, so the FATHOM-FORMAT-001
///     refusal never masks them, T-03-20);
/// 2 = usage error (missing/unknown dialect, missing file, bad option value,
///     unknown profile) — stderr message only, no SQL output.
pub fn run_format(command : Command, stdin_bytes : Bytes) -> CliOutcome {
```

**输入读取 + 错误映射模板**（run.mbt:98-125 `run_parse` + `parse_error_outcome` 形状 verbatim）：
```moonbit
let input = match command.file {
  Some(path) if path != "-" => match read_file(path) {
    Some(bytes) => bytes
    None => return usage_error("cannot read file: \{path}")
  }
  _ => stdin_bytes
}
let result = match @api.parse_with_ids(input, command.dialect, command.profile, "strict") {
  Ok(result) => result
  Err(error) => return parse_error_outcome(command.dialect, error)
}
```

**stderr 渲染**（run.mbt:150-158 `render_diagnostics` verbatim——`run_lint` 的 findings 渲染仿此，`@buffer.Buffer` 逐行写）：
```moonbit
pub fn render_diagnostics(diagnostics : Array[@api.FormatDiagnostic]) -> Bytes {
  let out = @buffer.Buffer::Buffer(size_hint=256)
  for diagnostic in diagnostics {
    out.write_bytes(@utf8.encode("\{diagnostic.code}: \{diagnostic.message}\n"))
  }
  out.to_bytes()
}
```

lint 退出码：`--fix` 时 0 = 全部 fix 应用且 reparse 干净；1 = 拒绝（FATHOM-LINT-000）或残留不可 fix findings；2 = 用法错误。fingerprint：0 = 成功（stdout 指纹 UInt64 十进制 + 可选 `--normalized` 文本）；1 = parse 失败；2 = 用法错误（RESEARCH 例 5）。

### `fathom-sql/main.mbt`（增补分发）

**Analog:** `fathom-sql/main.mbt` subcommand `match`（main.mbt:37-59 verbatim 形状——`lint`/`fingerprint` 分支仿 `parse`/`format`，stdin 读取按 `command.file` 判断，`exit_process(outcome.exit_code)` 收尾）。

### `fathom-sql/cli_test.mbt`（增补退出码矩阵）

**Analog:** `fathom-sql/cli_test.mbt`（`command_stdin`/`command_flink` 构造 + D-39 退出码矩阵）。新增 `lint`/`fingerprint` 的 `command` 构造与 exit 0/1/2 断言（形状：cli_test.mbt:20-38 `command_stdin` + :150-165 `run_parse_subcommand_exit_0_envelope` + :67-81 `cli_usage_errors_are_named_usage_error_variants`）。`--rule` 非法值 → exit 2（仿 :245-270 `cli_bad_option_values_exit_2_via_run_format`）。

### `parity/fingerprint_parity_test.mbt`（增补）

**Analog:** `parity/parity_test.mbt`（`fixture_source`/`run_fixture` 三目标模式）+ `parity/export_smoke_test.mbt`（wire envelope 断言）

**fixture + 三目标跑批模板**（parity_test.mbt:7-64 verbatim 形状）：
```moonbit
fn fixture_source(id : String) -> Bytes {
  match id {
    "valid-2.1" => b"select 1"
    ...
  }
}

fn run_fixture(id : String) -> Unit raise {
  let source = fixture_source(id)
  let profile = fixture_profile(id)
  let parsed = json_text(@binding.fathom_parse_v1(source, "doris", profile, "editor"))
  ...
}
```

`fingerprint_parity_test.mbt` 复用 `compare_backends.py` 三目标机制（native/js/wasm 同一 fixture 产出**同一十进制 fingerprint string**，D-08/Pitfall 3），在 `parity/__snapshot__` 增加 fingerprint 命名空间（仿 flink-grammar 独立命名空间先例，A4）；`export_smoke_test.mbt` 追加 `fathom_lint_v1`/`fathom_fingerprint_v1` 的 schema-tag 断言（`fathom.lint.v1`/`fathom.fingerprint.v1` 出现、旧 5 命名空间仍可用，Pitfall V6）。

### `parity/run_js.mbt` / `parity/run_wasm.mbt`（增补冒烟）

**Analog:** 当前 `run_js.mbt`/`run_wasm.mbt`（verbatim 形状）：
```moonbit
fn main {
  let source = b"select /* js parity */ 1"
  let parsed = @binding.fathom_parse_v1(source, "doris", "4.x", "editor")
  ...
  ignore(@binding.fathom_capabilities_v1())
}
```

各追加 `ignore(@binding.fathom_lint_v1(...))` 与 `ignore(@binding.fathom_fingerprint_v1(...))`（无 println/env，linear-Wasm 保持 primitive-only，run_wasm.mbt:1 注释）；确认 Int/Bytes 参数 ABI（Pitfall 8）。

### `docs/API.md` + `docs/zh-CN/API.md`（增补章节）

**Analog:** `docs/API.md` 既有结构：新增 "Lint Entry Points"（仿 "Formatting Entry Points" 节，API.md:200-260：`pub fn` 签名 + `LintResult`/`LintFinding`/`LintOptions` 结构 + 拒绝码表 `FATHOM-LINT-000`）+ "Fingerprint Entry Points"（仿同节）+ Wire Exports 表新增两行（仿 API.md:430-460 表格）。`docs/zh-CN/API.md` 同步中文版（`docs/` 下有 `zh-CN/` 镜像）。

---

## Shared Patterns

### 1. D-33 拒绝绝对（autofix 安全闸）
**Source:** `formatter/refuse.mbt:6-17` `first_unsafe_element` + `formatter/format.mbt:88-98,145-154` `find_first_unsafe`/`refusal_diagnostic`
**Apply to:** `lint/fixes.mbt`、`api/fix_text`、`binding/exports.mbt` `fathom_lint_v1`
树含 error/missing/skipped → `accepted=false`、空输出、**恰好一个** `FATHOM-LINT-000` 拒绝诊断，绝不部分编辑。

### 2. 关键字单源（D-28，不建第二关键字表）
**Source:** `dialect/classification.mbt:99-106` `classification_of` + `formatter/case.mbt:21-50` `rewrite_keyword_case`/`ascii_case_fold`
**Apply to:** `lint/engine.mbt`（FATHOM-LINT-001 判定）、`fingerprint/normalize.mbt`（关键字折叠）
任何"关键字 vs 标识符"判定只走 `@dialect.classification_of(context, raw)`——`SourceToken` 叶子不携带 TokenKind（syntax.mbt:55-58），分类必须经 classification 表。

### 3. 统一内部 parse 入口（dialect-first + limits 门禁）
**Source:** `api/api.mbt:566-580` `format_text`（`validate_limits` → `SourceText::new_with_limit` → `parser.parse_with_limits_context` → `is_valid` 门禁）
**Apply to:** `api/api.mbt` 新增 `lint_text`/`fix_text`/`fingerprint_text`；lint/fingerprint 包内**不** import parser（D-01），解析职责留在 api。

### 4. wire 导出模板（A4 顺序：raw → dialect → profile + 错误映射 + moon.pkg 双注册）
**Source:** `binding/exports.mbt:31-34` `fathom_parse_v1` + `binding/moon.pkg` js/wasm exports 列表
**Apply to:** `fathom_lint_v1`/`fathom_fingerprint_v1`——`#export_name` 只在 `binding/` 声明（Pitfall 17），且必须同时在 moon.pkg 两个 exports 列表注册（缺注册编译通过但产物缺符号）。

### 5. schema v2 bump = 纯加法（Pitfall V6）
**Source:** `binding/schema.mbt:20-28` `validate_schema_version`
**Apply to:** `binding/schema.mbt`——保留现有 5 个命名空间，新增 `fathom.lint.v1`/`fathom.fingerprint.v1` 两个常量；`parity/export_smoke_test.mbt` 断言旧命名空间仍可用。

### 6. CLI D-39 退出码（0/1/2）
**Source:** `fathom-sql/run.mbt:25-35` 注释 + `parse_error_outcome` + `render_diagnostics`
**Apply to:** `fathom-sql/run.mbt` `run_lint`/`run_fingerprint`、`fathom-sql/main.mbt` 分发、`fathom-sql/cli_test.mbt` 退出码矩阵。

### 7. 跨目标 parity（compare_backends.py + `parity/__snapshot__`）
**Source:** `parity/parity_test.mbt` fixture 跑批 + `scripts/compare_backends.py` 三目标聚合
**Apply to:** `parity/fingerprint_parity_test.mbt`——同一 fixture 在 native/js/wasm 产出相同 fingerprint 十进制 string（Pitfall 3）。

---

## No Analog Found

| 文件 | Role | Data Flow | 原因（planner 用 RESEARCH.md Pattern 5 替代） |
|------|------|-----------|------|
| `fingerprint/hash.mbt` | utility | transform | FNV-1a 64-bit 是全新纯函数算法，仓库内无任何 64-bit 哈希先例（core 无 hash 包、`Hasher` 是 xxHash32——STACK.md 已核实）。形状仿 `ascii_case_fold` 字节循环（case.mbt:35-50）；`UInt64` 字面量后缀/环绕乘法语义 [ASSUMED]，执行器首任务须 `moon check` 探针核实（RESEARCH Open Question 1） |

另注：`binding/json.mbt` 的 `fingerprint_result_json` 中 `UInt64 → 十进制 string` 序列化亦无既有 analog——现 `Json::number(to_double())`（schema.mbt:107 模式）是**反模式**，本阶段明确不复制。

---

## Metadata

**Analog search scope:** `/opt/source/Fathom/{formatter, api, binding, fathom-sql, parity, dialect, syntax, source, analyzer, completion, docs}`
**Files scanned:** ~25（含全部关键 analog 源码 + 包配置 + 测试）
**Pattern extraction date:** 2026-08-10

**关键读源清单（行号已核实）：**
- `formatter/refuse.mbt:6-17`、`formatter/case.mbt:21-50`、`formatter/format.mbt:6-65,88-98,118-143,145-154`、`formatter/error.mbt:20-49`、`formatter/options.mbt:60-110`、`formatter/layout.mbt:329-335`
- `api/api.mbt:305-313,463-472,566-580,615-627`
- `binding/exports.mbt:31-34,39-75`、`binding/schema.mbt:20-28,46-53,116-140`、`binding/json.mbt:7-14,41-53`、`binding/moon.pkg`
- `fathom-sql/args.mbt:1-120`、`fathom-sql/run.mbt:25-125,150-158`、`fathom-sql/main.mbt`、`fathom-sql/cli_test.mbt`
- `parity/run_js.mbt`、`parity/run_wasm.mbt`、`parity/parity_test.mbt:7-64`、`parity/export_smoke_test.mbt`、`parity/moon.pkg`
- `dialect/classification.mbt:99-106`、`syntax/syntax.mbt:55-58`、`source/source.mbt:15-20,96-104`、`analyzer/analysis.mbt:34-59`
- `docs/API.md:200-260,430-500`、`completion/completion_test.mbt:19-46`

**依赖面核对（D-01）：** `lint/` import = `@syntax` + `@dialect` + `@source` + `@formatter`（安全闸）+ 可选 `@analyzer`；`fingerprint/` import = `@syntax` + `@dialect` + `@source`。两者均不 import `@parser`（D-21/D-27 单向纪律）；解析统一走 `api/` 门面（Shared Pattern 3）。
