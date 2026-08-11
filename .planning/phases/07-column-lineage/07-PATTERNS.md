# Phase 7: Column Lineage (LINE-01) — Pattern Map

**Mapped:** 2026-08-11
**Files analyzed:** 20（8 新增 / 12 修改）
**Analogs found:** 19 / 20（唯一无直接 analog 的是 `lineage/views.mbt` 的 `ViewCatalog[T]` 泛型包装 —— 仓库无既有 catalog 包装先例，形状由 `analyzer/analyzer.mbt` Catalog trait + lint `run_rules` 注入模式推导）

> 本映射基于对既有代码库的直接读源。所有代码摘录均来自当前仓库真实文件（`moon 0.1.20260724`，模块名 `fathom/sql`，`moon.mod:3-5`）。正文用中文，代码/路径/符号保留英文。
>
> **关键事实（Phase 7 与 Phase 6 的交付面差异）：** Phase 6 的 `lint/`/`fingerprint/` 消费 `syntax` read views（已公开），而 Phase 7 的 `lineage/` 消费 `analyzer/` 的**结构化 SelectModel —— 当前全部包私有**（`select_model.mbt:11-107` 无 `pub`）。因此本阶段比 Phase 6 多一个 **Wave 0：在 analyzer 打开 lineage-facing 公开面**（`pub(all)` select-model 类型 + 公开 `split_select_model`/`source_tokens`/CREATE VIEW 体重解析入口）。这是 planner 必须排进计划的第一批改动。

---

## File Classification

| 新/修改文件 | Role | Data Flow | Closest Analog | Match Quality |
|------------|------|-----------|----------------|---------------|
| `lineage/moon.pkg`（新增） | config（包依赖声明） | — | `lint/moon.pkg`（library 包，D-01 依赖面） | exact |
| `lineage/model.mbt`（新增） | model（`LineageEdge`/`LineageGap`/`LineageResult`） | transform（纯数据） | `lint/rules.mbt` `LintFinding`/`LintResult`（pub(all) + 平铺 span + derive） | exact |
| `lineage/views.mbt`（新增） | service（视图注册表 + `ViewCatalog[T]` 包装） | transform | `analyzer/analyzer.mbt` Catalog trait/StaticCatalog（泛型包装推导）+ `lint/engine.mbt` 注入面 | partial |
| `lineage/edges.mbt`（新增） | service（边派生：模型走查 × Binding 按 span 关联） | transform | `analyzer/resolve.mbt` `resolve_select_item`（ref → Column 绑定映射，resolve.mbt:796-875） | role-match |
| `lineage/gaps.mbt`（新增） | service（gap 派生：star 未展开 / 诊断映射 / has_error_missing） | transform | `analyzer/resolve.mbt` `expand_star`（resolve.mbt:388-460）+ `has_error_missing`（resolve.mbt:69-90）+ `lint/fixes.mbt` D-33 拒绝 | role-match |
| `lineage/insert.mbt`（新增） | service（INSERT 位置列映射 + 尾 SELECT 重解析） | transform | `analyzer/resolve.mbt` `analyze_dml_body` Insert 臂（resolve.mbt:1256-1264）+ `analyze_create_view_body`（resolve.mbt:1295-1314） | role-match |
| `lineage/lineage_test.mbt`（新增） | test | — | `lint/lint_test.mbt`（白盒判定正反例）+ `fingerprint/hash_test.mbt`（确定性向量） | role-match |
| `binding/catalog_json.mbt`（新增） | adapter/service（catalog JSON → StaticCatalog） | transform | `binding/exports.mbt` `parse_overrides`（exports.mbt:158-221，JSON parse → 结构化错误） | exact |
| `analyzer/select_model.mbt`（修改，Wave 0） | model（pub(all) 公开面） | — | 自身（当前私有 → 加 `pub(all)`，仿 analysis.mbt 已 pub(all) 数据模型） | exact |
| `analyzer/select_parser.mbt`（修改，Wave 0） | service（公开 `split_select_model`/`source_tokens`） | transform | 自身（`fn` → `pub fn`，仿 resolve.mbt `pub fn analyze`） | exact |
| `analyzer/resolve.mbt`（修改，Wave 0） | service（公开 CREATE VIEW 体切片 / INSERT 尾 SELECT 定位） | transform | 自身（`analyze_create_view_body`/`analyze_dml_body` 内已有逻辑 → 公开薄包装） | exact |
| `api/api.mbt`（修改） | service facade（`lineage_text` + 类型再导出） | request-response | `api.mbt` `fingerprint_text`/`lint_text`/`parse_document`（api.mbt:677-782）+ D-38 类型别名块 | exact |
| `api/moon.pkg`（修改） | config（+ analyzer + lineage import） | — | 当前 `api/moon.pkg`（+ `@fingerprint`/`@lint` 先例） | exact |
| `binding/schema.mbt`（修改） | config/contract（第 8 命名空间 `fathom.lineage.v1`） | — | `binding/schema.mbt` `validate_schema_version`（schema.mbt:20-28，纯增分支） | exact |
| `binding/exports.mbt`（修改） | adapter（`fathom_lineage_v1` wire 导出） | request-response | `binding/exports.mbt` `fathom_lint_v1`（exports.mbt:205-252） | exact |
| `binding/json.mbt`（修改） | utility（`lineage_result_json` edges/gaps 序列化） | transform | `binding/json.mbt` `lint_result_json`（json.mbt:150-205）+ `fingerprint_result_json` | exact |
| `binding/moon.pkg`（修改） | config（js/wasm exports 列表 + `fathom_lineage_v1`） | — | 当前 `binding/moon.pkg` 七导出列表（第 8 个追加） | exact |
| `fathom-sql/args.mbt`（修改） | controller（subcommand 白名单 + `lineage` + `--catalog`） | request-response | `fathom-sql/args.mbt` `parse_args` + `UsageError`（args.mbt:14-135） | exact |
| `fathom-sql/run.mbt`（修改） | controller（`run_lineage` D-39 0/1/2） | request-response | `fathom-sql/run.mbt` `run_lint`/`run_fingerprint` + `parse_options`（run.mbt:142-225） | exact |
| `fathom-sql/main.mbt`（修改） | controller（subcommand 分发） | request-response | `fathom-sql/main.mbt` subcommand `match`（main.mbt:31-63） | exact |
| `fathom-sql/cli_test.mbt`（修改） | test | — | `fathom-sql/run.mbt` 内 `test "run_*_stdin_happy_path"`（Command 字面量构造） | exact |
| `parity/lineage_parity_test.mbt`（新增） | test（跨目标字节一致） | — | `parity/fingerprint_parity_test.mbt`（硬编码期望值断言）+ `parity/export_smoke_test.mbt` `schema_v2_bump_is_additive` | exact |
| `parity/run_js.mbt` / `run_wasm.mbt`（修改） | adapter（冒烟调用 `fathom_lineage_v1`） | — | 当前 `parity/run_js.mbt`/`run_wasm.mbt`（`ignore(@binding.fathom_lint_v1(...))` 先例） | exact |
| `test/lineage_test.mbt`（新增） | test（parse → lineage 集成 + 快照 golden） | — | `test/analyzer_anal01_test.mbt`（`analyze_sql` 助手 + `analyzer_snapshot_test` + 快照 golden，analyzer_anal01_test.mbt:9-90） | exact |
| `test/moon.pkg`（修改） | config（+ lineage import） | — | 当前 `test/moon.pkg`（analyzer/api/parser 已 import） | exact |
| `docs/API.md` + `docs/zh-CN/API.md`（修改） | docs | — | `docs/API.md` "Lint Entry Points" / "Wire Exports" 章节结构（API.md:257-330, 502-518） | exact |

---

## Pattern Assignments

### 1. 新分析包模式：`lineage/` 独立库（D-07/D-21）

**Analog:** `lint/moon.pkg`（library 包依赖声明）+ `lint/rules.mbt`（pub(all) 结果模型）+ `lint/engine.mbt`（注入面入口）

**`lint/moon.pkg`（verbatim，全 9 行）：**
```moonbit
pkgtype(kind: "library")
import {
  "fathom/sql/syntax" @syntax,
  "fathom/sql/dialect" @dialect,
  "fathom/sql/source" @source,
  "fathom/sql/formatter" @formatter,
  "fathom/sql/analyzer" @analyzer,
  "moonbitlang/core/buffer" @buffer,
  "moonbitlang/core/debug" @debug,
}
```

**`lineage/moon.pkg` 依 D-21 依赖面（比 lint 更窄）：** 直接 import 仅 `"fathom/sql/analyzer" @analyzer` + `"fathom/sql/syntax" @syntax`（公开入口签名需要 `@syntax.SyntaxNode` 参数，与 `analyzer.analyze` 一致）。**永不 import `@parser` / `@source` / `@dialect`**（D-21 单向纪律 + RESEARCH Pitfall 8：边/gap span 用平铺 Int，不引入 `@source.Span`）。`pkgtype(kind: "library")` + `@debug`（derive 需要）。

**模型类型模板（`lint/rules.mbt` `LintFinding` + `lint/fixes.mbt` `LintResult`，verbatim）：**
```moonbit
/// One lint finding. `severity` is the serialized string ("error"/"warning"/
/// "info"); `fix` is the candidate edit for fixable rules, None otherwise.
pub(all) struct LintFinding {
  pub code : String
  pub severity : String
  pub message : String
  pub start_byte : Int
  pub end_byte : Int
  pub statement_id : UInt
  pub fix : LintEdit?
} derive(Eq, @debug.Debug)

pub(all) struct LintResult {
  pub accepted : Bool
  pub findings : Array[LintFinding]
  pub output : Bytes
  pub diagnostics : Array[LintDiagnostic]
} derive(Eq, @debug.Debug)
```

**`lineage/model.mbt` 应镜像：** `pub(all)` + 全 `pub` 字段 + `derive(Eq, @debug.Debug)`（跨包字面量构造要求 all-public，moon 0.1.20260724 教训，lint/rules.mbt:13 注释）。RESEARCH Pattern 5 给出的边/gap 形状：
```moonbit
pub(all) struct LineageEdge {
  pub source_name : String
  pub source_resolved_to : String
  pub source_start_byte : Int
  pub source_end_byte : Int
  pub target_name : String
  pub target_start_byte : Int
  pub target_end_byte : Int
} derive(Eq, @debug.Debug)

pub(all) struct LineageGap {
  pub code : String          // "requires-catalog" | "unresolved-reference" | "requires-complete-parse"
  pub message : String
  pub start_byte : Int
  pub end_byte : Int
} derive(Eq, @debug.Debug)

pub(all) struct LineageResult {
  pub edges : Array[LineageEdge]
  pub gaps : Array[LineageGap]
} derive(Eq, @debug.Debug)
```

**注入面入口（`lint/engine.mbt` `run_rules` 签名，verbatim——lineage 的公开入口仿此形状但消费 `@analyzer` 结果）：**
```moonbit
pub fn run_rules(
  root : @syntax.SyntaxNode,
  source : @source.SourceText,
  context : @dialect.DialectContext,
  analysis : @analyzer.AnalysisResult?,
  options : LintOptions,
) -> Array[LintFinding]
```
lineage 的公开入口（`lineage/model.mbt` 或 `edges.mbt` 的 `derive_lineage`）仿此：`pub fn derive_lineage(root : @syntax.SyntaxNode, source_bytes : Bytes, catalog : @analyzer.Catalog?) -> LineageResult`——与 `analyzer.analyze(node, source_bytes, catalog)`（resolve.mbt:1382-1386）的 `[T : Catalog]` 泛型一致；可选 catalog 语义 = `ViewCatalog[T]` 包装（Pattern 2）。

---

### 2. analyzer 包私有模型公开面（Wave 0，本阶段特有）

**Analog:** `analyzer/analysis.mbt`（已 `pub(all)` 数据模型）+ `analyzer/analyzer.mbt`（Catalog trait）+ `analyzer/resolve.mbt` `pub fn analyze`（公开入口先例）

**核心结论（RESEARCH RQ1 直接读源验证）：** `analyze`（resolve.mbt:1382-1406）已对文档内每个语句体做完整解析与名字解析，产出扁平 `Binding` 数组 + 独立 `AnalysisDiagnostic` 通道。**血缘不重写解析**，但 `SelectModel`/`SelectItem`/`NameRef`/`TokenSlice` 全部包私有（select_model.mbt 无 `pub`），`split_select_model`/`source_tokens`/`qualified_ref_at`/`find_word_at_depth0`/`slice_tokens`/`matching_paren` 全部 `fn`（私有）。Wave 0 = 在 analyzer 打开最小 lineage-facing 公开面，**只增不改既有行为**（不触碰 parser，无 frozen-baseline 风险）。

**已公开的数据模型（`analyzer/analysis.mbt:22-59` verbatim——lineage 直接消费，无需改动）：**
```moonbit
/// The kind of a resolved name binding (D-06).
pub(all) enum BindingKind {
  Table
  Column
  Function
  Cte
  Alias
} derive(Eq, @debug.Debug)

pub(all) struct Binding {
  kind : BindingKind
  name : String
  resolved_to : String
  data_type : String
  start_byte : Int
  end_byte : Int
} derive(Eq, @debug.Debug)

pub(all) struct AnalysisDiagnostic {
  code : String
  message : String
  start_byte : Int
  end_byte : Int
} derive(Eq, @debug.Debug)

pub(all) struct AnalysisResult {
  bindings : Array[Binding]
  diagnostics : Array[AnalysisDiagnostic]
} derive(Eq, @debug.Debug)
```

**Catalog 契约（`analyzer/analyzer.mbt:23-47` verbatim——`lineage/views.mbt` 的 `ViewCatalog[T]` 直接依赖此 trait）：**
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
  table_in_db(Self, db : String, name : String) -> TableInfo?
  function(Self, String) -> FunctionInfo?
}
```

**需公开的 SELECT 模型（`analyzer/select_model.mbt:11-107`，当前私有——Wave 0 加 `pub(all)`；verbatim 关键结构）：**
```moonbit
struct NameRef {
  parts : Array[TokenSlice]
  star : Bool
  is_call : Bool
  call_args : Array[TokenSlice]
  start_byte : Int
  end_byte : Int
}

struct SelectItem {
  tokens : Array[TokenSlice]
  alias : String?
  alias_slice : TokenSlice?
  star : Bool
  star_qualifier : NameRef?
  refs : Array[NameRef]
}

struct FromItem {
  name : NameRef?
  alias : String?
  alias_slice : TokenSlice?
  is_subquery : Bool
  subquery : SelectModel?
  join : String?
  depth : Int
}

struct CteDef {
  name : String
  alias : String?
  body : SelectCore
}

struct SelectCore {
  select_list : Array[SelectItem]
  from : Array[FromItem]
  joins : Array[FromItem]
  where_refs : Array[NameRef]
  group_by : Array[NameRef]
  having : Array[NameRef]
  qualify : Array[NameRef]
  order_by : Array[NameRef]
  limit : Array[TokenSlice]
  window : Array[TokenSlice]
  set_op : String?
}

struct SelectModel {
  ctes : Array[CteDef]
  branches : Array[SelectCore]
}
```
**注意（Phase 7 对 SelectItem 的可能扩展）：** `SelectItem` 当前**不承载 `EXCEPT (cols)` 排除列**（`build_select_item` 剥离后丢弃，select_parser.mbt:408-434）——若执行器选 RESEARCH Pitfall 3 选项 (a)（诚实展开 `* EXCEPT`），需给 `SelectItem` 增 `except_cols : Array[TokenSlice]` 并让 `expand_star` 应用排除（analyzer 内部改动，不动 parser）。选 (b) 则 `* EXCEPT` 产 `requires-catalog` gap，不改 SelectItem。

**需公开的 re-parser 入口（`analyzer/select_parser.mbt`，当前私有——Wave 0 `fn` → `pub fn`）：**
```moonbit
// source_tokens（select_parser.mbt:25-44）：node → (token_bytes, start_byte, end_byte) 三元组
fn source_tokens(node : @syntax.SyntaxNode, source_bytes : Bytes) -> Array[(Bytes, Int, Int)]

// split_select_model（select_parser.mbt:1150-1152）：token 流 → SelectModel，括号深度溢出返回 None
fn split_select_model(tokens : Array[(Bytes, Int, Int)]) -> SelectModel?

// 辅助（lineage 侧 INSERT 尾 SELECT 定位需要）：select_parser.mbt:168, 210, 1045, 1081, 1106
fn matching_paren(tokens : Array[(Bytes, Int, Int)], open : Int) -> Int
fn collect_refs(tokens : Array[TokenSlice]) -> Array[NameRef]
fn qualified_ref_at(tokens : Array[(Bytes, Int, Int)], index : Int) -> (NameRef, Int)?
fn find_word_at_depth0(tokens : Array[(Bytes, Int, Int)], start : Int, end : Int, word : Bytes) -> Int
fn slice_tokens(tokens : Array[(Bytes, Int, Int)], start : Int, end : Int) -> Array[TokenSlice]
```

**需公开的体切片/INSERT 尾 SELECT 定位（`analyzer/resolve.mbt`——lineage 侧调用，Wave 0 公开薄包装）：**
- `has_error_missing(node)`（resolve.mbt:69-90）：error/missing 拒绝扫描，gap `requires-complete-parse` 直接复用（D-33）。公开为 `pub fn has_error_missing`（或经 analyzer 的 `requires-complete-parse` 诊断映射）。
- `analyze_create_view_body`（resolve.mbt:1295-1314）：已有"CREATE VIEW 名后定位 `(` 列清单 / `AS` / query_start → `analyze_select_tokens`"完整逻辑——Wave 0 公开其**定位辅助**（view 名后 query_start 计算），让 lineage 侧重解析视图体得到 `SelectModel`。
- `analyze_dml_body` Insert 臂（resolve.mbt:1256-1264，verbatim）——**只解析括号列清单，不分析尾 SELECT 体**：
```moonbit
@syntax.SyntaxKind::Insert => {
  if next < tokens.length() && tokens[next].0 == b"(" {
    let close = matching_paren(tokens, next)
    if close < tokens.length() {
      resolve_token_refs(
        slice_tokens(tokens, next + 1, close),
        scope,
        catalog,
        0,
        bindings,
        diagnostics,
      )
    }
  }
}
```
Wave 0 公开一个 `insert_body_location(tokens, prefix) -> (col_list: (Int, Int)?, body_start: Int)?` 辅助（复用 `matching_paren` + `find_word_at_depth0` 定位 `VALUES`/`SELECT`/`WITH`），lineage 侧对 body 走公开 `split_select_model` 重解析后做位置映射（RESEARCH Pattern 3）。**保持 `analyze_dml_body` 行为不变**（不改 ANAL-01 契约，one-way 边界）。

**公开入口先例（`analyzer/resolve.mbt:1382-1406` verbatim——Wave 0 的 `pub fn` 写法）：**
```moonbit
pub fn[T : Catalog] analyze(
  node : @syntax.SyntaxNode,
  source_bytes : Bytes,
  catalog : T,
) -> AnalysisResult {
  let bindings : Array[Binding] = []
  let diagnostics : Array[AnalysisDiagnostic] = []
  for element in node.children() {
    match element {
      @syntax.SyntaxElement::ChildNode(statement_node) => {
        if statement_node.kind() is @syntax.SyntaxKind::Statement {
          for inner in statement_node.children() {
            match inner {
              @syntax.SyntaxElement::ChildNode(body) => {
                analyze_body(body, source_bytes, catalog, bindings, diagnostics)
              }
              @syntax.SyntaxElement::Leaf(_) => ()
            }
          }
        }
      }
      @syntax.SyntaxElement::Leaf(_) => ()
    }
  }
  ...
}
```

---

### 3. api 序列化入口：`lineage_text`

**Analog:** `api.mbt` `fingerprint_text` / `lint_text` / `parse_document` + D-38 类型别名块

**共享内部解析（`api.mbt` `parse_document` verbatim——`lineage_text` 直接复用，零改动）：**
```moonbit
/// Shared internal parse for the analysis entry points (lint/fix). Mirrors the
/// parse half of `format_text`/`fingerprint_text`: validate_limits ->
/// SourceText::new_with_limit -> parse_with_limits_context -> is_valid gate.
fn parse_document(
  raw : Bytes,
  parse_options : ParseOptions,
) -> Result[(@parser.ParsedDocument, @source.SourceText), ParseError] {
  let limits = parse_options.limits
  match validate_limits(limits) { Ok(_) => (); Err(error) => return Err(error) }
  let source = match @source.SourceText::new_with_limit(raw, limits.max_bytes) {
    Ok(source) => source
    Err(@source.SourceError::InputTooLarge(requested_bytes~, max_bytes~)) => {
      return Err(InputTooLarge(requested_bytes~, max_bytes~))
    }
  }
  let parser_mode = match parse_options.mode {
    ParseMode::Strict => @parser.ParseMode::Strict
    ParseMode::Editor => @parser.ParseMode::Editor
  }
  let parser_limits = @parser.ParserLimits::new(
    limits.max_bytes,
    limits.max_tokens,
    limits.max_recursion_depth,
    limits.max_recovery_steps,
    limits.max_diagnostics,
  )
  let parsed = @parser.parse_with_limits_context(
    source,
    parse_options.dialect_context,
    parser_mode,
    parser_limits,
  )
  if !parsed.root.is_valid(source.byte_length()) {
    return Err(InvalidSyntaxTree)
  }
  Ok((parsed, source))
}
```

**核心入口模板（`api.mbt` `fingerprint_text` verbatim——`lineage_text` 仿此，加可选 catalog 参数）：**
```moonbit
pub fn fingerprint_text(
  raw : Bytes,
  parse_options : ParseOptions,
) -> Result[FingerprintResult, ParseError] {
  let limits = parse_options.limits
  match validate_limits(limits) { Ok(_) => (); Err(error) => return Err(error) }
  let source = match @source.SourceText::new_with_limit(raw, limits.max_bytes) {
    Ok(source) => source
    Err(@source.SourceError::InputTooLarge(requested_bytes~, max_bytes~)) => {
      return Err(InputTooLarge(requested_bytes~, max_bytes~))
    }
  }
  let parser_mode = match parse_options.mode {
    ParseMode::Strict => @parser.ParseMode::Strict
    ParseMode::Editor => @parser.ParseMode::Editor
  }
  let parser_limits = @parser.ParserLimits::new(
    limits.max_bytes,
    limits.max_tokens,
    limits.max_recursion_depth,
    limits.max_recovery_steps,
    limits.max_diagnostics,
  )
  let parsed = @parser.parse_with_limits_context(
    source,
    parse_options.dialect_context,
    parser_mode,
    parser_limits,
  )
  if !parsed.root.is_valid(source.byte_length()) {
    return Err(InvalidSyntaxTree)
  }
  let canonical = @fingerprint.normalize(parsed.root, source, parse_options.dialect_context)
  Ok({ fingerprint: @fingerprint.fnv1a64(canonical), normalized: canonical })
}
```

**`lint_text` 的 parse_document 复用（api.mbt:757-782 verbatim——`lineage_text` 的同款骨架 + 注入点）：**
```moonbit
pub fn lint_text(
  raw : Bytes,
  parse_options : ParseOptions,
  lint_options : LintOptions,
) -> Result[LintResult, ParseError] {
  let (parsed, source) = match parse_document(raw, parse_options) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let findings = @lint.run_rules(
    parsed.root,
    source,
    parse_options.dialect_context,
    None,
    lint_options,
  )
  Ok({ accepted: true, findings: findings, output: b"", diagnostics: [] })
}
```

**`lineage_text` 推荐签名（RESEARCH Pattern 5 / D-05）：**
```moonbit
pub fn lineage_text(
  raw : Bytes,
  parse_options : ParseOptions,
  catalog : @analyzer.StaticCatalog?,
) -> Result[LineageResult, ParseError]
```
骨架 = `parse_document` → flink 门禁（D-08：`parse_options` 的 dialect 为 flink → 结构化 `ParseError` 拒绝，绝不静默空结果）→ `@analyzer.analyze(parsed.root, source.bytes(), catalog)` → `@lineage.derive_lineage(parsed.root, source.bytes(), catalog)` → `Ok(result)`。**库面直接接受 `Catalog` trait**（与 `analyze` 一致，泛型）；`StaticCatalog?` 是 api 面可选参数的具体化。

**类型再导出（`api.mbt:539-557` D-38 别名块 verbatim——`lineage_text` 后追加 `LineageResult`/`LineageEdge`/`LineageGap`）：**
```moonbit
pub type LintOptions = @lint.LintOptions
pub type LintResult = @lint.LintResult
pub type LintFinding = @lint.LintFinding
pub type LintEdit = @lint.LintEdit
pub type LintDiagnostic = @lint.LintDiagnostic
pub type RuleOverride = @lint.RuleOverride
pub type LintSeverity = @lint.LintSeverity
pub type RuleSetting = @lint.RuleSetting
```
追加：`pub type LineageResult = @lineage.LineageResult` / `LineageEdge` / `LineageGap` / `pub type StaticCatalog = @analyzer.StaticCatalog`（catalog 面经 api 暴露）。

**`api/moon.pkg`（verbatim——追加 `"fathom/sql/analyzer" @analyzer,` + `"fathom/sql/lineage" @lineage,`）：**
```moonbit
pkgtype(kind: "library")
import {
  "fathom/sql/source" @source,
  "fathom/sql/parser" @parser,
  "fathom/sql/syntax" @syntax,
  "fathom/sql/formatter" @formatter,
  "fathom/sql/dialect" @dialect,
  "fathom/sql/fingerprint" @fingerprint,
  "fathom/sql/lint" @lint,
}
```

---

### 4. wire 导出 + schema bump：`fathom.lineage.v1`（第 8 命名空间）

**Analog:** `binding/schema.mbt` `validate_schema_version` + `binding/exports.mbt` `fathom_lint_v1` + `parse_overrides` + `binding/json.mbt` `lint_result_json`

**schema v2 bump 点（`binding/schema.mbt:6-28` verbatim——追加 `LINEAGE_SCHEMA_VERSION` 为第 8 分支，纯增 Pitfall V6）：**
```moonbit
pub const PARSE_SCHEMA_VERSION : String = "fathom.parse.v1"
pub const FORMAT_SCHEMA_VERSION : String = "fathom.format.v1"
pub const COMPLETE_SCHEMA_VERSION : String = "fathom.complete.v1"
pub const LINT_SCHEMA_VERSION : String = "fathom.lint.v1"
pub const FINGERPRINT_SCHEMA_VERSION : String = "fathom.fingerprint.v1"
pub const SOURCE_TRANSPORT : String = "inline-root-v1"

pub fn validate_schema_version(version : String) -> Result[Unit, SchemaError] {
  match version {
    PARSE_SCHEMA_VERSION |
    FORMAT_SCHEMA_VERSION |
    COMPLETE_SCHEMA_VERSION |
    LINT_SCHEMA_VERSION |
    FINGERPRINT_SCHEMA_VERSION |
    "fathom.error.v1" |
    "fathom.capabilities.v1" => Ok(())
    _ => Err(UnsupportedSchemaVersion(version~))
  }
}
```
追加：`pub const LINEAGE_SCHEMA_VERSION : String = "fathom.lineage.v1"` + 分支 `LINEAGE_SCHEMA_VERSION`。**既有 7 分支一行不动**（Pitfall V6；`parity/schema_test.mbt` 既有断言不破）。

**wire 导出模板（`binding/exports.mbt` `fathom_lint_v1` verbatim——`fathom_lineage_v1` 仿此，`catalog_json` 空 bytes = 无 catalog）：**
```moonbit
#export_name("fathom_lint_v1")
pub fn fathom_lint_v1(
  raw : Bytes,
  dialect : String,
  profile : String,
  mode : String,
  overrides : Bytes,
  fix : Bool,
) -> Bytes {
  // Dialect/profile validated FIRST (Pitfall 6, T-09-10): unknown dialect /
  // unsupported profile map to the fathom.error.v1 envelope before any lint
  // work. ParseOptions also supplies exact_release for the envelope (D-09).
  let selection = match @api.ParseOptions::new(dialect, profile, mode) {
    Ok(options) => options
    Err(error) => return parse_error_bytes(error)
  }
  let rule_overrides = match parse_overrides(overrides) {
    Ok(value) => value
    Err(message) => return error_bytes("FATHOM-SCHEMA-004", message)
  }
  let lint_options = match @api.LintOptions::new(rule_overrides) {
    Ok(options) => options
    Err(_) => return error_bytes("FATHOM-SCHEMA-004", "unknown rule code in lint overrides")
  }
  let result = if fix {
    @api.fix_text(raw, selection, lint_options)
  } else {
    @api.lint_text(raw, selection, lint_options)
  }
  match result {
    Ok(result) => {
      json_bytes(
        lint_result_json(raw, result, dialect, profile, selection.exact_release()),
      )
    }
    Err(error) => parse_error_bytes(error)
  }
}
```
`fathom_lineage_v1` 差异点：签名加 `catalog_json : Bytes`（空 bytes / `"{}"` = 无 catalog，D-05）；flink 门禁在 `ParseOptions::new` 后显式检查 dialect 为 flink → `error_bytes("FATHOM-SCHEMA-003", "lineage is Doris-only")`（D-08，RESEARCH A6）；`catalog_json` 解析走 `catalog_json.mbt`（见下）。

**catalog JSON 解析模板（`binding/exports.mbt` `parse_overrides` verbatim——`binding/catalog_json.mbt` 完全镜像此形状：空 bytes 默认 / try-catch @utf8.decode + @json.parse / 结构化错误，never silent fallback，T-06-03-01 / ASVS V5）：**
```moonbit
fn parse_overrides(overrides : Bytes) -> Result[Array[@api.RuleOverride], String] {
  if overrides.length() == 0 {
    return Ok([])
  }
  let text = try {
    @utf8.decode(overrides)
  } catch {
    _ => return Err("invalid UTF-8 in lint overrides")
  }
  let value = try {
    @json.parse(text)
  } catch {
    _ => return Err("malformed JSON in lint overrides")
  }
  match value {
    Json::Array(items) => {
      let out : Array[@api.RuleOverride] = []
      for item in items {
        let obj = match item {
          Json::Object(obj) => obj
          _ => return Err("lint override must be an object")
        }
        let code = match obj.get("code") {
          Some(Json::String(s)) => s
          _ => return Err("lint override missing string code")
        }
        ...
      }
      Ok(out)
    }
    _ => Err("lint overrides must be a JSON array")
  }
}
```
`catalog_json.mbt`：JSON 形状 `{tables[], db_tables[], functions[]}`（RESEARCH A5）→ `@api.StaticCatalog::new` + `with_db` + `with_function`（analyzer.mbt:58-90 构造器）；非法 JSON / 未知字段 → `Err(String)` → wire 层 `error_bytes("FATHOM-SCHEMA-004", ...)`（RESEARCH Open Question 5 推荐）。

**envelope 序列化模板（`binding/json.mbt` `lint_result_json` verbatim——`lineage_result_json` 仿此：dialect/profile/exact_release 元数据 D-09 + edges/gaps 数组）：**
```moonbit
pub fn lint_result_json(
  source : Bytes,
  result : @api.LintResult,
  dialect : String,
  profile : String,
  exact_release : String,
) -> String {
  let findings : Array[Json] = []
  for finding in result.findings {
    let fix_json = match finding.fix {
      Some(edit) => Json::object({ ... })
      None => Json::object({})
    }
    findings.push(Json::object({
      "code": Json::string(finding.code),
      "severity": Json::string(finding.severity),
      "message": Json::string(finding.message),
      "start_byte": Json::number(finding.start_byte.to_double()),
      "end_byte": Json::number(finding.end_byte.to_double()),
      "statement_id": Json::number(finding.statement_id.to_double()),
      "fix": fix_json,
    }))
  }
  stringify({
    "schema_version": Json::string("fathom.lint.v1"),
    "source_transport": Json::string(SOURCE_TRANSPORT),
    "dialect": Json::string(dialect),
    "profile": Json::string(profile),
    "exact_release": Json::string(exact_release),
    "source_bytes": byte_array_json(source),
    "source_byte_length": Json::number(source.length().to_double()),
    "accepted": Json::boolean(result.accepted),
    "findings": Json::array(findings),
    "output": byte_array_json(result.output),
    "diagnostics": Json::array(diagnostics),
  })
}
```
`lineage_result_json`：`"schema_version": "fathom.lineage.v1"` + `edges`（每条 `{source_name, source_resolved_to, source_start_byte, source_end_byte, target_name, target_start_byte, target_end_byte}`）+ `gaps`（每条 `{code, message, start_byte, end_byte}`）。span Int ≤ 2^53 时 `Json::number(x.to_double())` 安全（json.mbt:7-12 既有模式；RESEARCH Pitfall 6）。

**`binding/moon.pkg`（verbatim——js 与 wasm 两处 exports 列表各追加 `"fathom_lineage_v1",`，第 8 个）：**
```moonbit
options(
  link: {
    "js": {
      "format": "esm",
      "exports": [
        "fathom_parse_v1",
        "fathom_format_v1",
        "fathom_complete_v1",
        "fathom_lint_v1",
        "fathom_fingerprint_v1",
        "fathom_dialect_v1",
        "fathom_capabilities_v1",
        // + "fathom_lineage_v1",
      ],
    },
    "wasm": {
      "exports": [ ... 同 js ... ],
    },
  },
)
```
**两处注册（Pitfall 5 / docs/API.md:504 明文）：** 漏注册 `binding/moon.pkg` exports 列表会静默缺符号（编译通过但 artifact 无 `fathom_lineage_v1`）。

---

### 5. CLI 子命令：`fathom-sql lineage --catalog <file>`

**Analog:** `fathom-sql/args.mbt` `parse_args` + `fathom-sql/run.mbt` `run_lint`/`run_fingerprint` + `fathom-sql/main.mbt` 分发

**subcommand 白名单（`fathom-sql/args.mbt:62-64` verbatim——加 `"lineage"`）：**
```moonbit
if subcommand != "parse" && subcommand != "format" && subcommand != "lsp" &&
  subcommand != "lint" && subcommand != "fingerprint" {
  return Err(UnknownSubcommand(sub=subcommand))
}
```

**`--catalog <file>` 标志（仿 `args.mbt` `--rule`/`--normalized` 解析块）：**
```moonbit
} else if arg == "--catalog" {
  index = index + 1
  if index >= args.length() { return Err(MissingValue(flag="--catalog")) }
  catalog = Some(args[index])
} else if arg == "--normalized" {
  normalized = true
}
```
`Command` 结构体（args.mbt:32-50）追加 `pub catalog : String?` 字段（`pub(all)` + 全 pub 字段——跨包字面量构造要求，args.mbt:28-31 注释教训）。`UsageError`（args.mbt:14-24）无需新增变体（`--catalog` 缺值/坏路径复用 `MissingValue`/`UnknownValue`；坏 catalog JSON 在 run.mbt 映射 exit 2）。

**run 层（`fathom-sql/run.mbt` `run_lint` verbatim——`run_lineage` 仿此 + 读 `--catalog` 文件 + D-39）：**
```moonbit
/// D-39 lint exit mapping:
///   0 = no findings (report mode) OR all fixes applied + reparse clean ...;
///   1 = findings rendered on stderr (report mode) OR D-33 refusal ...;
///   2 = usage/config error (invalid --rule value, unknown rule code).
pub fn run_lint(command : Command, stdin_bytes : Bytes) -> CliOutcome {
  let selection = match parse_options(command) {
    Ok(options) => options
    Err(outcome) => return outcome
  }
  let lint_options = match @api.LintOptions::new(command.overrides) {
    Ok(options) => options
    Err(_) => return usage_error("unknown rule code in --rule")
  }
  let input = match command.file {
    Some(path) if path != "-" => match read_file(path) {
      Some(bytes) => bytes
      None => return usage_error("cannot read file: \{path}")
    }
    _ => stdin_bytes
  }
  if command.fix {
    match @api.fix_text(input, selection, lint_options) { ... }
  } else {
    match @api.lint_text(input, selection, lint_options) {
      Ok(result) => {
        if result.findings.length() == 0 {
          { exit_code: 0, stdout: b"", stderr: b"" }
        } else {
          { exit_code: 1, stdout: b"", stderr: render_lint_findings(result.findings) }
        }
      }
      Err(error) => parse_error_outcome(command.dialect, error)
    }
  }
}
```

**`run_lineage` 推荐（RESEARCH Pattern 5 / D-39）：**
```moonbit
/// D-39 lineage exit mapping:
///   0 = envelope on stdout（fathom.lineage.v1，edges+gaps，含 catalog 注入结果）;
///   1 = parse 失败 / flink 门禁（结构化 FATHOM-SCHEMA 错误）;
///   2 = 用法/配置错误（缺 dialect/profile、坏 --catalog 路径、catalog JSON 非法）。
pub fn run_lineage(command : Command, stdin_bytes : Bytes) -> CliOutcome {
  let selection = match parse_options(command) { ... }
  // --catalog <file>: 读文件；坏路径 -> usage_error (exit 2)
  // 空 bytes / "{}" -> None (无 catalog, D-05)
  // 非空非法 JSON -> usage_error (exit 2, FATHOM-SCHEMA-004 message)
  // flink 门禁：selection dialect 为 flink -> usage_error exit 2（D-08）
  match @api.lineage_text(input, selection, catalog) {
    Ok(result) => {
      { exit_code: 0, stdout: @utf8.encode(@binding.lineage_result_json(input, result, command.dialect, command.profile, selection.exact_release()) + "\n"), stderr: b"" }
    }
    Err(error) => parse_error_outcome(command.dialect, error)
  }
}
```
`parse_options`（run.mbt:125-135）与 `parse_error_outcome`（run.mbt:250-290）**直接复用**（D-39 0/1/2 映射：UnknownDialect/UnknownProfile/UnknownMode → exit 2；InputTooLarge 等 → exit 1）。`render_*` 系列不适用（lineage 的 edges/gaps 走 envelope，不是 stderr 行）。

**main 分发（`fathom-sql/main.mbt:31-63` verbatim——加 `"lineage"` 臂）：**
```moonbit
let outcome = match command.subcommand {
  "lsp" => run_lsp(command)
  "parse" => { let stdin_bytes = match command.file { Some(path) if path != "-" => b""; _ => read_stdin() }; run_parse(command, stdin_bytes) }
  "lint" => { let stdin_bytes = ...; run_lint(command, stdin_bytes) }
  "fingerprint" => { let stdin_bytes = ...; run_fingerprint(command, stdin_bytes) }
  _ => { let stdin_bytes = ...; run_format(command, stdin_bytes) }
}
```
加 `"lineage" => { let stdin_bytes = ...; run_lineage(command, stdin_bytes) }`。`usage_text()`（run.mbt:295-299）与 `usage_error_message`（run.mbt:302-325）追加 `lineage` 到 subcommand 枚举列表。

**cli_test.mbt 模板（`run.mbt` 内 `test "run_parse_stdin_happy_path"` verbatim——`Command` 全字段字面量 + `run_lineage` 断言退出码）：**
```moonbit
test "run_parse_stdin_happy_path" {
  let command : Command = {
    subcommand: "parse",
    dialect: "doris",
    profile: "4.x",
    keyword_case: None,
    indent: None,
    line_width: None,
    comma_style: None,
    newline_style: None,
    trailing_newline: true,
    file: Some("-"),
    overrides: [],
    fix: false,
    normalized: false,
  }
  let outcome = run_parse(command, b"SELECT 1")
  assert_eq(outcome.exit_code, 0)
  assert_true(outcome.stdout.to_string().contains("fathom.parse.v1"))
  assert_eq(outcome.stderr.length(), 0)
}
```

---

### 6. parity 跨目标：三目标字节一致

**Analog:** `parity/fingerprint_parity_test.mbt`（硬编码期望值）+ `parity/export_smoke_test.mbt` `schema_v2_bump_is_additive` + `parity/run_js.mbt`/`run_wasm.mbt`（冒烟）+ `parity/moon.pkg`（targets 配置）

**硬编码期望值断言（`parity/fingerprint_parity_test.mbt:10-21` verbatim——`lineage_parity_test.mbt` 仿此：同 fixture 在三目标产出相同 edges/gaps 字节）：**
```moonbit
test "fingerprint_export_stable_cross_target_decimal_string" {
  let text = @utf8.decode_lossy(
    @binding.fathom_fingerprint_v1(b"SELECT 1", "doris", "4.x", "strict")[:],
  )
  assert_true(text.contains("fathom.fingerprint.v1"))
  assert_true(text.contains("\"dialect\":\"doris\""))
  assert_true(text.contains("\"profile\":\"4.x\""))
  assert_true(text.contains("\"fingerprint\":\"214897735614764786\""))
  ...
}
```

**schema bump 纯增断言（`parity/export_smoke_test.mbt:1-29` `schema_v2_bump_is_additive` verbatim——追加 `fathom_lineage_v1` 到"新命名空间"断言 + 保留既有七命名空间断言）：**
```moonbit
test "schema_v2_bump_is_additive" {
  let lint = @utf8.decode_lossy(@binding.fathom_lint_v1(b"SELECT 1", "doris", "4.x", "strict", b"[]", false)[:])
  let fingerprint = @utf8.decode_lossy(@binding.fathom_fingerprint_v1(b"SELECT 1", "doris", "4.x", "strict")[:])
  assert_true(lint.contains("fathom.lint.v1"))
  assert_true(fingerprint.contains("fathom.fingerprint.v1"))
  // Original five namespaces still usable (no removal).
  let parsed = @utf8.decode_lossy(@binding.fathom_parse_v1(b"SELECT 1", "doris", "4.x", "strict")[:])
  ...
}
```

**冒烟调用（`parity/run_js.mbt` / `run_wasm.mbt` 的 `fn main` verbatim——追加 `ignore(@binding.fathom_lineage_v1(...))`）：**
```moonbit
fn main {
  let source = b"select /* js parity */ 1"
  let parsed = @binding.fathom_parse_v1(source, "doris", "4.x", "editor")
  ...
  let linted = @binding.fathom_lint_v1(b"SELECT 1", "doris", "4.x", "strict", b"[]", false)
  let fingerprinted = @binding.fathom_fingerprint_v1(b"SELECT 1", "doris", "4.x", "strict")
  ignore(parsed); ignore(formatted); ignore(completed); ignore(linted); ignore(fingerprinted)
  ignore(@binding.fathom_capabilities_v1())
}
```
追加 `let lineaged = @binding.fathom_lineage_v1(b"SELECT a FROM t", "doris", "4.x", "strict", b"")` + `ignore(lineaged)`（冒烟 Bytes+String 参数 ABI，无 println/env 主机 IO——linear-Wasm 可移植性，run_wasm.mbt 头注释纪律）。

**`parity/moon.pkg`（verbatim——targets 配置不动，`lineage_parity_test.mbt` 自动纳入三目标）：**
```moonbit
options(
  targets: {
    "run_native.mbt": ["native"],
    "run_js.mbt": ["js"],
    "run_wasm.mbt": ["wasm"],
  },
)
```

**`scripts/compare_backends.py`：** 无需改动——`PACKAGE = "parity"`、`DEFAULT_TARGETS = ("native", "js", "wasm")` 自动跑 `moon test --target {t} --package parity`，`lineage_parity_test.mbt` 加入即纳入 digest 比较。RESEARCH Pitfall 6：edges/gaps 数组顺序是公共契约（文档语句序 → SelectModel 分支/CTE 序 → SelectItem 序 → refs 序；`Map` = LinkedHashMap 确定性迭代，STACK.md 核实）。

---

### 7. 测试/快照：边/gap 快照 golden + 集成测试

**Analog:** `test/analyzer_anal01_test.mbt`（analyze 集成测试 + 快照 golden）+ `lint/lint_test.mbt`（白盒正反例）

**快照 golden 模式（`test/analyzer_anal01_test.mbt:9-90` verbatim——`test/lineage_test.mbt` 的 `lineage_result_to_json` + `lineage_snapshot_test` 镜像）：**
```moonbit
/// Deterministic JSON rendering of an AnalysisResult for the snapshot golden.
fn analysis_result_to_json(result : @analyzer.AnalysisResult) -> String {
  fn kind_id(kind : @analyzer.BindingKind) -> String { ... }
  fn json_string(s : String) -> String { ... }
  let mut out = "{\n  \"bindings\": ["
  ...
}

fn analyze_sql(raw : Bytes, catalog : @analyzer.StaticCatalog) -> @analyzer.AnalysisResult {
  let source = match @source.SourceText::new_with_limit(raw, 8 * 1024 * 1024) {
    Ok(source) => source
    Err(_) => panic()
  }
  let parsed = @parser.parse_with_limits(
    source,
    doris_context("4.x"),
    @parser.ParseMode::Strict,
    @parser.ParserLimits::default(),
  )
  if !parsed.valid { panic() }
  @analyzer.analyze(parsed.root, source.bytes(), catalog)
}

/// Snapshot helper (parity/flink_grammar_test.mbt:677-680): `moon test
/// --update` is the only write path.
fn analyzer_snapshot_test(t : @mtest.Test, content : String, filename : String) -> Unit raise SnapshotError {
  t.write(content)
  t.snapshot(filename=filename)
}

test "analyzer-anal01 select-basic doris-4.x" {
  let t = @mtest.Test("analyzer-anal01 select-basic doris-4.x")
  let raw = b"SELECT a, b FROM t"
  let catalog = @analyzer.StaticCatalog::new([
    { name: "t", columns: [ { name: "a", data_type: "INT" }, { name: "b", data_type: "VARCHAR(10)" } ] },
  ])
  let result = analyze_sql(raw, catalog)
  assert_eq(result.bindings.length(), 3)
  ...
  analyzer_snapshot_test(t, analysis_result_to_json(result), "analyzer.select-basic.doris-4.x.json")
}
```
`test/lineage_test.mbt` 差异：`lineage` 不能 import parser（D-21），集成测试放 `test/`（已 import parser/analyzer/api，test/moon.pkg verbatim）——`analyze_sql` 等价助手 parse 后调 `@api.lineage_text` 或 `@lineage.derive_lineage`；快照 golden 锁定 edges/gaps 结构与顺序（`moon test --update` 唯一写路径）。**测试用例覆盖（RESEARCH Pitfalls 1-4）：** 表达式直通（`SELECT a + b AS x` → 两条边）、`*` 无 catalog → `requires-catalog` gap、有 catalog `*` 展开为真实边、CTE/UNION/INSERT 位置映射、`* EXCEPT`（选 (a) 则诚实展开 / 选 (b) 则 gap）、视图注册表（`CREATE VIEW v AS SELECT a FROM t; SELECT * FROM v`）。

**白盒测试模式（`lint/lint_test.mbt` 手建 CST——`lineage/lineage_test.mbt` 仿此但不需要手建 CST，因为 lineage 消费 `@analyzer` 结构化模型 + 真实 parse 出的 `SyntaxNode`）：**
```moonbit
fn doris_ctx(profile : String) -> @dialect.DialectContext {
  { dialect: @dialect.Dialect::Doris, profile_id: profile, exact_release: profile, feature_introduction: "test" }
}

test "rule_003_select_star_without_limit_positive" {
  let (doc, src) = lint_doc(b"SELECT * FROM t", @syntax.SyntaxKind::Select, [...])
  let findings = run_rules(doc, src, doris_ctx("4.x"), None, LintOptions::default())
  ...
}
```
`lineage/lineage_test.mbt` 白盒直接构造 `SelectModel`/`Binding`/`StaticCatalog` 输入（模型已 pub(all)，Wave 0 后跨包可构造），正反例锁定边/gap 派生——确定性向量优先（仿 `fingerprint/hash_test.mbt` 的 FNV-1a 测试向量纪律）。

**`test/moon.pkg`（verbatim——追加 `"fathom/sql/lineage" @lineage,`）：**
```moonbit
import {
  "fathom/sql/analyzer" @analyzer,
  "fathom/sql/api" @api,
  "fathom/sql/parser" @parser,
  ...
}
```

---

## Shared Patterns

### 单向依赖纪律（D-21/D-27）——所有新文件
- `lineage/` 只 import `@analyzer` + `@syntax`（签名需要 `SyntaxNode`），**永不 import `@parser`/`@source`/`@dialect`**（RESEARCH Pitfall 8：边/gap span 用平铺 Int，不引入 `@source.Span`）。parser 永不反向 import lineage（`parser/moon.pkg` 负门禁维持）。
- **来源：** `lint/moon.pkg` + `analyzer/moon.pkg`（后者 verbatim：`pkgtype(kind: "library") import { "fathom/sql/syntax" @syntax }`）。

### 可选 catalog 纪律（ANLY-01 / T-02-42）——api、binding、CLI
- 无 catalog 时结果字节不变；wire/CLI 面缺省无 catalog → 全 gap，绝不伪造边（SC2）。
- `lineage_text` 的 `catalog` 参数为可选；`fathom_lineage_v1` 的 `catalog_json` 空 bytes = 无 catalog。
- **来源：** `api.mbt` `lint_text`（`None` 注入）+ `binding/exports.mbt` `parse_overrides`（空 bytes 默认）。

### 平铺 span（D-01/D-06）——model、api、binding、test
- 所有边/gap span = `start_byte`/`end_byte` Int 字节偏移（与 `Binding`/`AnalysisDiagnostic` 一致，analysis.mbt:34-42）。序列化 `Json::number(x.to_double())`（≤ 2^53 安全）。
- **来源：** `binding/json.mbt` `lint_result_json` + `binding/fingerprint_result_json`（UInt64 例外用 string，lineage 无 UInt64）。

### schema v2 bump 纯增（Pitfall V6）——binding
- 第 8 命名空间 `fathom.lineage.v1` 追加分支，既有 7 分支不动；`binding/moon.pkg` js/wasm 两处 exports 列表注册。
- **来源：** `binding/schema.mbt:20-28` + `parity/export_smoke_test.mbt` `schema_v2_bump_is_additive`。

### D-39 退出码 0/1/2——fathom-sql
- 0 = envelope；1 = parse 失败；2 = 用法/配置错误（含坏 catalog JSON、flink 门禁）。
- **来源：** `run.mbt` `run_lint`/`run_fingerprint` + `parse_error_outcome` + `usage_error`。

### 方言门禁（D-08）——api、binding、CLI
- flink 选择 → 结构化 FATHOM-SCHEMA 错误（推荐 `FATHOM-SCHEMA-003` + message "lineage is Doris-only"），绝不静默空结果。不新建 `FATHOM-LINE-*`、不建 `fathom.lineage.flink` 命名空间。
- **来源：** `binding/schema.mbt` `validate_dialect_profile`（UnsupportedProfile → FATHOM-SCHEMA-003）+ `fathom_format_v1` 的 dialect-first 校验注释（exports.mbt:41-45）。

---

## No Analog Found

Files with no close match in the codebase（planner 应使用 RESEARCH Pattern 2 / A3-A4 推导）：

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `lineage/views.mbt`（`ViewCatalog[T]` 泛型包装） | service | transform | 仓库无既有 catalog 包装先例。形状由 `analyzer.mbt` `pub(open) trait Catalog`（analyzer.mbt:44-47）+ `pub struct StaticCatalog` 私有字段（无枚举访问器，无法合并条目）推导——泛型 `T : Catalog` 包装（先查视图注册表后委托 inner）是唯一通用方案（RESEARCH RQ3）。`table_in_db`/`function` 委托 inner（视图只在默认库命名空间，A3 保守假设）。执行器首任务须核实 `ViewCatalog[T]` 泛型 trait 包装在 `moon 0.1.20260724` 上编译（RESEARCH A3/A4 标注）。 |

---

## Metadata

**Analog search scope:** `/opt/source/Fathom/{lint,fingerprint,analyzer,api,binding,fathom-sql,parity,test,scripts,docs}`
**Files scanned:** 26（directly read: lint/moon.pkg, lint/rules.mbt, lint/engine.mbt, lint/fixes.mbt, lint/lint_test.mbt, fingerprint/moon.pkg, fingerprint/hash.mbt, fingerprint/normalize.mbt, analyzer/moon.pkg, analyzer/analysis.mbt, analyzer/analyzer.mbt, analyzer/select_model.mbt, analyzer/select_parser.mbt, analyzer/resolve.mbt, api/moon.pkg, api/api.mbt, binding/moon.pkg, binding/schema.mbt, binding/exports.mbt, binding/json.mbt, fathom-sql/moon.pkg, fathom-sql/args.mbt, fathom-sql/run.mbt, fathom-sql/main.mbt, parity/moon.pkg, parity/fingerprint_parity_test.mbt, parity/export_smoke_test.mbt, parity/run_js.mbt, parity/run_wasm.mbt, scripts/compare_backends.py, test/moon.pkg, test/analyzer_anal01_test.mbt, test/lint_test.mbt, moon.mod, docs/API.md）
**Pattern extraction date:** 2026-08-11
**Toolchain:** `moon 0.1.20260724`（moon.mod:5-6），模块 `fathom/sql`
