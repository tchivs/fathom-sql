# Phase 5: Closeout and Analysis Foundation — Pattern Map

**Mapped:** 2026-08-10
**Files analyzed:** 12（6 modified / 6 new）
**Analogs found:** 10 / 12（2 partial — net-new composite，见 No Analog Found）

> 本 pattern map 供 `gsd-planner` 使用：每个 planned file 映射到仓库内最接近的 analog，给出逐字引用（verbatim）+ 行号。planner 在 plan action 中直接引用这些 excerpt，而不是抽象描述。
>
> 命名纪律：本阶段零新增依赖（D-21）；新文件全部落在既有 MoonBit package 内（`analyzer/`、`test/`），共享各自的 `moon.pkg` import 契约。文档风格沿用仓库双语惯例（中文说明 + 英文技术术语/代码）。

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `analyzer/analyzer.mbt` | model + service（catalog 契约 + 表级解析走查） | request-response（只读 syntax 走查 + 内存查找） | 自身（被扩展的现状实现） | exact |
| `analyzer/moon.pkg` | config（D-21 import 契约） | N/A | 自身 + `parser/moon.pkg` 负门禁 | exact |
| `analyzer/analysis.mbt` **[NEW]** | model（plain records，可序列化） | transform | `api/api.mbt` `PrimitiveDiagnostic`/`PrimitiveNode`（api.mbt:297-313） | exact |
| `analyzer/select_model.mbt` **[NEW]** | model（枚举 + 结构体：ClauseKind/SelectCore/SelectModel/CteDef） | transform | `syntax/syntax.mbt` `SyntaxKind`/`SyntaxLeaf` 枚举形状（syntax.mbt:2-77） | partial — 无 Select 子模型先例（见 No Analog Found） |
| `analyzer/select_parser.mbt` **[NEW]** | service（字节级二次解析 + 括号深度子句切分） | transform（token 流 → 子句切片） | `completion/completion.mbt` `word_is`/`bytes_equal_ci`（27-43）+ `analyzer.mbt` `source_token_texts`（147-165）/`leading_prefix_end`（171-269）+ `parser.mbt` `parse_select_core`（1613-1720） | role-match（复合逻辑 net-new，见 No Analog Found） |
| `analyzer/resolve.mbt` **[NEW]** | service（作用域栈 + catalog 查找 + binding + 类型诊断） | request-response（独立诊断通道） | `analyzer.mbt` `resolve_table_references`（295-336）+ `formatter/format.mbt` D-33 refusal（1-4） | role-match（作用域栈逻辑 net-new） |
| `analyzer/analyzer_wbtest.mbt` **[NEW, 可选]** | test（白盒 helper 单测） | N/A | `lsp/selection_wbtest.mbt`（`_wbtest.mbt` 白盒惯例） | role-match |
| `test/analyzer_test.mbt` | test（集成 + 边界） | N/A | 自身（既有 parse→analyze 断言惯例） | exact |
| `test/analyzer_anal01_test.mbt` **[NEW]** | test（parse→analyze 集成 + @test 快照） | N/A | `parity/flink_grammar_test.mbt:677-680` 快照 + `test/analyzer_test.mbt` 集成 setup | exact |
| `docs/API.md` | docs（§Optional Name-Resolution API 更新） | N/A | 自身（docs/API.md:275-303 既有 § 结构） | exact |
| `.planning/REQUIREMENTS.md` | docs/traceability（CLOSE-01/02 正式核实条目） | N/A | 自身（REQUIREMENTS.md Traceability 表 + CLOSE-01/02 VERIFIED 行） | exact |
| `.planning/STATE.md` | docs/traceability（Deferred Items 证据记录） | N/A | 自身（STATE.md Deferred Items 2026-08-06 记录行） | exact |

---

## Pattern Assignments

### `analyzer/analyzer.mbt`（model + service，request-response）— **Modified**

**Analog:** 自身（D-05 扩展基线 + D-03 语义更新 + D-01 孪生 helper）。

**Doc-comment / boundary contract pattern（头注，analyzer.mbt:1-20）** — 新 `AnalysisResult`/db 作用域说明沿用同一「边界契约」头注风格：
```moonbit
/// Optional name-resolution-level analyzer package (D-21..D-24).
///
/// Boundary contract:
/// - This package consumes ONLY syntax read views (`@syntax.SyntaxNode`) plus
///   caller-provided source bytes. It never imports parser, token, lexer, api,
///   or source — and the parser package must never import this package
///   (D-21, research Pitfall 7; enforced by a negative gate on parser/moon.pkg).
/// - Catalog metadata is caller-injected and untrusted (T-02-42). It is
///   consumed only by this package and NEVER reaches the parser or the
///   syntax-only valid/diagnostic channel: parsing a document without a
///   catalog yields byte-identical syntax results (ANLY-01).
```

**Catalog trait + StaticCatalog pattern（D-05 one-way 门，analyzer.mbt:40-67）** — 保留 `table`、新增 `table_in_db` + `function`，与唯一实现者同提交迁移：
```moonbit
/// Minimal table -> columns lookup contract (D-22). Implementors answer
/// whether a table exists and what its columns are; they never influence
/// syntax parsing or the syntax-only valid channel. `open` so consumers can
/// implement it for their own metadata sources.
pub(open) trait Catalog {
  table(Self, String) -> TableInfo?
}

/// Concrete in-memory catalog backed by a name-keyed map. Keys are
/// case-sensitive for now (documented): "t" and "T" are distinct tables.
pub struct StaticCatalog {
  tables : Map[String, TableInfo]
}

/// Builds a catalog from the given entries; later entries with the same name
/// overwrite earlier ones (last-wins, documented).
pub fn StaticCatalog::new(entries : Array[TableInfo]) -> StaticCatalog {
  let tables : Map[String, TableInfo] = Map([])
  for entry in entries {
    tables.set(entry.name, entry)
  }
  { tables: tables }
}

/// Direct map lookup: returns the entry for `name` or None when absent.
pub fn StaticCatalog::lookup(self : StaticCatalog, name : String) -> TableInfo? {
  self.tables.get(name)
}

pub impl Catalog for StaticCatalog with table(self, name) {
  self.lookup(name)
}
```
> **D-05 迁移点：** `pub(open) trait Catalog` 无默认方法（仓库实证：唯一实现者是 StaticCatalog，analyzer.mbt:65-67）。本阶段一次定形（加 `table_in_db`/`function`），`test/analyzer_test.mbt:10-12` 的 trait-dispatch helper `catalog_lookup` 同提交迁移。`StaticCatalog` 的 doc 注释（analyzer.mbt:45「case-sensitive for now」）随 D-03 改为 case-insensitive 匹配语义。

**ASCII case-fold（D-03，analyzer.mbt:87-101）** — 解析时折叠比较的直接实现，`resolve.mbt`/`select_parser.mbt` 直接复用：
```moonbit
/// Case-folded byte comparison (ASCII), mirroring parser.mbt `bytes_equal_ci`.
fn bytes_equal_ci(actual : Bytes, expected : Bytes) -> Bool {
  if actual.length() != expected.length() {
    false
  } else {
    let mut index = 0
    let mut equal = true
    while index < actual.length() {
      let left = actual[index].to_int()
      let right = expected[index].to_int()
      let folded_left = if left >= 97 && left <= 122 { left - 32 } else { left }
      let folded_right = if right >= 97 && right <= 122 { right - 32 } else { right }
      if folded_left != folded_right {
        equal = false
      }
      index = index + 1
    }
    equal
  }
}
```

**Token 字节恢复（D-01 孪生 helper 基线，analyzer.mbt:147-165）** — 新增 `source_tokens` 返回 `(Bytes, @source.Span)` 对，逻辑与现实现一致（只收 `LeafKind::SourceToken`，跳过 trivia/error/skipped）：
```moonbit
/// Source-token leaf texts of a node in source order (trivia, error, and
/// skipped leaves are ignored; only SourceToken leaves carry grammar tokens).
fn source_token_texts(node : @syntax.SyntaxNode, source_bytes : Bytes) -> Array[Bytes] {
  let texts : Array[Bytes] = []
  for element in node.children() {
    match element {
      @syntax.SyntaxElement::Leaf(leaf) => {
        if leaf.kind is @syntax.LeafKind::SourceToken {
          let start = leaf.span.start_byte
          let end = leaf.span.end_byte
          if start >= 0 && start <= end && end <= source_bytes.length() {
            texts.push(source_bytes[start:end].to_owned())
          }
        }
      }
      @syntax.SyntaxElement::ChildNode(_) => ()
    }
  }
  texts
}
```

**字节式关键字消费（select_parser.mbt 的 in-repo 类比，analyzer.mbt:171-269 `leading_prefix_end`）** — 按整 token 字节 `bytes_equal_ci` 判定关键字、可选词逐个消费，与 D-01 子句切分的判定纪律一致（节选 Insert arm）：
```moonbit
fn leading_prefix_end(kind : @syntax.SyntaxKind, tokens : Array[Bytes]) -> Int {
  let length = tokens.length()
  let mut position = 0
  match kind {
    @syntax.SyntaxKind::Insert => {
      if position < length && (bytes_equal_ci(tokens[position], b"INSERT") ||
        bytes_equal_ci(tokens[position], b"UPSERT")) {
        position = position + 1
      }
      if position < length && bytes_equal_ci(tokens[position], b"OVERWRITE") {
        position = position + 1
        if position < length && bytes_equal_ci(tokens[position], b"TABLE") {
          position = position + 1
        }
      } else {
        if position < length && bytes_equal_ci(tokens[position], b"INTO") {
          position = position + 1
        }
      }
    }
    // ... (Update/Delete/Merge/CreateTable/CreateView arms)
    _ => ()
  }
  position
}
```

**只读 syntax 走查入口（resolve.mbt 的直接 analog，analyzer.mbt:295-336 `resolve_table_references`）** — Statement → body kind 分派 → `target_table_name` → `Catalog::table`：
```moonbit
pub fn[T : Catalog] resolve_table_references(
  node : @syntax.SyntaxNode,
  source_bytes : Bytes,
  catalog : T,
) -> Array[String] {
  let resolved : Array[String] = []
  for element in node.children() {
    match element {
      @syntax.SyntaxElement::ChildNode(statement_node) => {
        if statement_node.kind() is @syntax.SyntaxKind::Statement {
          for inner in statement_node.children() {
            match inner {
              @syntax.SyntaxElement::ChildNode(body) => {
                match body.kind() {
                  @syntax.SyntaxKind::Insert | @syntax.SyntaxKind::Update |
                  @syntax.SyntaxKind::Delete | @syntax.SyntaxKind::Merge |
                  @syntax.SyntaxKind::CreateTable |
                  @syntax.SyntaxKind::CreateView => {
                    match target_table_name(body, source_bytes) {
                      Some(name) => {
                        match Catalog::table(catalog, name) {
                          Some(_) => resolved.push(name)
                          None => ()
                        }
                      }
                      None => ()
                    }
                  }
                  _ => ()
                }
              }
              @syntax.SyntaxElement::Leaf(_) => ()
            }
          }
        }
      }
      @syntax.SyntaxElement::Leaf(_) => ()
    }
  }
  resolved
}
```

**错误处理/边界：** analyzer 现有走查对 missing table 只是「缺席」，不产诊断（D-22/D-24）。ANAL-01 新增独立诊断通道（`AnalysisDiagnostic`），**绝不 panic**：body kind 非 Select/DML 族则跳过；Error/Missing 树产出空 bindings + 一条「requires complete parse」诊断（镜像 formatter D-33 refusal，见 Shared Patterns）。

---

### `analyzer/moon.pkg`（config，D-21 负门禁）— **Modified（字节保持）**

**Analog:** 自身 + `parser/moon.pkg` 负门禁。本阶段不新增 import；`source_tokens`/`select_parser.mbt`/`resolve.mbt`/`analysis.mbt` 全部落在同一 package，共享该 import 契约。

**Import 契约（analyzer/moon.pkg 全文）— D-01「不 import parser/token/lexer/api/source」的锁定面：**
```
pkgtype(kind: "library")
import {
  "fathom/sql/syntax" @syntax,
}
```

**负门禁参照（parser/moon.pkg 全文，parser 永不 import analyzer）：**
```
pkgtype(kind: "library")
import {
  "fathom/sql/source" @source,
  "fathom/sql/token" @token,
  "fathom/sql/lexer" @lexer,
  "fathom/sql/syntax" @syntax,
  "fathom/sql/dialect" @dialect,
}
```
> **关键推论（研究结论 D-01/D-06 交互）：** 公共 API 若命名 `@source.Span` 类型必须 `import "fathom/sql/source"`，违反 D-01。`AnalysisResult` 用 `start_byte`/`end_byte` Int 平铺（即 `@source.Span` 两个字段值），与 `api.PrimitiveDiagnostic` 一致。**plan 不得为此修改 moon.pkg。**

---

### `analyzer/analysis.mbt`（model，transform）— **[NEW]**

**Analog:** `api/api.mbt` `PrimitiveDiagnostic`/`PrimitiveNode`（api.mbt:297-313）— 平铺 Int span 的可序列化 record 形状；`analyzer.mbt` `ColumnInfo`/`TableInfo`（23-34）— `pub(all)` 可构造 record 先例。

**Record 形状（D-06 对齐基线，api.mbt:305-313 verbatim）：**
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
```moonbit
pub struct PrimitiveNode {
  pub kind : String
  pub start_byte : Int
  pub end_byte : Int
  pub text_len : Int
  pub children : Array[PrimitiveNode]
}
```

**`pub(all)` 构造 record 先例（analyzer.mbt:23-34 verbatim）— `AnalysisResult`/`Binding`/`AnalysisDiagnostic`/`FunctionInfo` 沿用：**
```moonbit
pub(all) struct ColumnInfo {
  name : String
  data_type : String
}

pub(all) struct TableInfo {
  name : String
  columns : Array[ColumnInfo]
}
```
> 仓库先例注释（analyzer.mbt:22）：`pub(all)` 使 catalog 消费者可从自有元数据构造条目（repo precedent: `pub(all) struct Token` in token/token.mbt）。

**推荐结果形状（research 例 2，供 planner 参考——bindings/diagnostics 平铺 span、独立诊断 code）：**
```moonbit
pub(all) enum BindingKind { Table, Column, Function, Cte, Alias }
pub(all) struct Binding {
  kind : BindingKind
  name : String            // 源码拼写（保留大小写，D-03）
  resolved_to : String     // catalog/作用域中的解析目标（作者 display 名）
  data_type : String       // D-04：列 → ColumnInfo.data_type；函数 → FunctionInfo.return_type
  start_byte : Int
  end_byte : Int
}
pub(all) struct AnalysisDiagnostic {
  code : String            // 独立 analyzer 诊断 code（不进入 FATHOM-PARSE/语法通道）
  message : String
  start_byte : Int
  end_byte : Int
}
pub(all) struct AnalysisResult {
  bindings : Array[Binding]
  diagnostics : Array[AnalysisDiagnostic]
}
```

**诊断 code 命名（研究 Open Question 3）：** 本阶段仅 MoonBit library 返回结构化诊断（无 wire），code 用 analyzer 内部稳定字符串（`"unknown-table"`/`"unknown-column"`/`"unknown-function"`/`"ambiguous-reference"`/`"function-arity"`），Phase 6 wire 化再决定 `FATHOM-ANALYZE-*` 编码。

---

### `analyzer/select_model.mbt`（model，transform）— **[NEW]**

**Analog（partial）:** `syntax/syntax.mbt` 枚举/结构体形状（syntax.mbt:2-77）— `derive(Eq, @debug.Debug)` 闭合枚举 + 结构体字段约定。**Select 子模型（ClauseKind/SelectCore/SelectModel/CteDef）在仓库无先例**（见 No Analog Found）。

**枚举/结构体形状（syntax.mbt:2-77 verbatim 节选）：**
```moonbit
pub(all) enum SyntaxKind {
  Document
  Statement
  Select
  // ...
} derive(Eq, @debug.Debug)

pub(all) enum LeafKind {
  SourceToken
  SourceTrivia
  SourceError
  SourceSkipped
} derive(Eq, @debug.Debug)

pub struct SyntaxLeaf {
  pub kind : LeafKind
  pub span : @source.Span
  pub text_len : Int
}

pub(all) enum SyntaxElement {
  ChildNode(SyntaxNode)
  Leaf(SyntaxLeaf)
}

pub struct SyntaxNode {
  kind : SyntaxKind
  span : @source.Span
  text_len : Int
  children : Array[SyntaxElement]
}
```
> **复用纪律：** `ClauseKind`/`SelectCore`/`SelectModel`/`CteDef` 是 analyzer 内部模型（D-01「在 analyzer 内部建立自己的分析模型」），**不新增 `SyntaxKind`、不改 `syntax/syntax.mbt`**（Phase 12 冻结硬门禁）。`derive(Eq, @debug.Debug)` 枚举 + 闭合变体（无 `Some`/`None` 漂移）沿用 syntax.mbt 风格。

---

### `analyzer/select_parser.mbt`（service，transform）— **[NEW]**

**Analog:** `completion/completion.mbt` `word_is`/`bytes_equal_ci`（27-43）+ `analyzer.mbt` `source_token_texts`（147-165）/`leading_prefix_end`（171-269）+ `parser.mbt` `parse_select_core`（1613-1720）子句顺序 + `parse_query`（1850-1868）UNION 链。**复合逻辑（paren-depth 子句切分）net-new，见 No Analog Found。**

**字节式关键字检测（completion.mbt:27-43 verbatim）— 二次解析的 `clause_break` 直接镜像：**
```moonbit
fn bytes_equal_ci(left : Bytes, right : Bytes) -> Bool {
  if left.length() > right.length() { return false }
  let mut index = 0
  while index < left.length() {
    let left_byte = left[index].to_int()
    let right_byte = right[index].to_int()
    let folded_left = if left_byte >= 97 && left_byte <= 122 { left_byte - 32 } else { left_byte }
    let folded_right = if right_byte >= 97 && right_byte <= 122 { right_byte - 32 } else { right_byte }
    if folded_left != folded_right { return false }
    index = index + 1
  }
  true
}

fn word_is(word : Bytes, expected : Bytes) -> Bool {
  word.length() == expected.length() && bytes_equal_ci(word, expected)
}
```

**Doris SELECT 子句顺序（parser.mbt:1613-1720 `parse_select_core` verbatim 节选）— 二次解析切分的权威顺序基准：**
```moonbit
fn parse_select_core(
  cursor : Cursor,
  context : @dialect.DialectContext,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !expect_word(cursor, b"SELECT", state, source, statement_id, "expected SELECT statement") { return false }
  // SELECT [DISTINCT|DISTINCTROW|ALL] select_list [* EXCEPT (...)]
  // (EXCEPT 是 Doris 投影修饰符，:1174-1183; Flink 下是 CompoundQuery 集合词)
  if consume_word(cursor, b"FROM") { valid = parse_from(cursor, context, state, source, statement_id) && valid }
  if consume_word(cursor, b"WHERE") { valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid }
  if consume_word(cursor, b"GROUP") { valid = parse_group_by(cursor, state, source, statement_id) && valid }
  if consume_word(cursor, b"HAVING") { valid = parse_expression(cursor, 1, 1, state, source, statement_id) && valid }
  if consume_word(cursor, b"WINDOW") { /* window defs */ }
  if consume_word(cursor, b"QUALIFY") { /* Doris-only feature gate */ }
  if consume_word(cursor, b"ORDER") { valid = parse_order_by(cursor, state, source, statement_id) && valid }
  if consume_word(cursor, b"LIMIT") { valid = parse_limit(cursor, state, source, statement_id) && valid }
  // INTO OUTFILE (Doris-only)
  valid
}
```
> **Pitfall 2 实证（research）：** `GROUP`/`ORDER` 需看后继是否 `BY`；`EXCEPT` 在冻结 parser 中是投影修饰符（parser.mbt:1637-1645, 1767-1770），`INTERSECT` 不在当前接受集——二次解析只切 `UNION [ALL|DISTINCT]` 分支，越界词按「无法分析/requires-verification」处理。

**UNION 顶层链（parser.mbt:1850-1868 `parse_query` verbatim 节选）：**
```moonbit
fn parse_query(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let context = cursor.stream.context
  let mut valid = true
  if raw_at(cursor) is Some(raw) && bytes_equal_ci(raw, b"WITH") {
    valid = parse_cte_prefix(cursor, state, source, statement_id) && valid
  }
  valid = parse_select_core(cursor, context, state, source, statement_id) && valid
  while consume_word(cursor, b"UNION") {
    ignore(consume_word(cursor, b"ALL"))
    ignore(consume_word(cursor, b"DISTINCT"))
    valid = parse_select_core(cursor, context, state, source, statement_id) && valid
  }
  valid
}
```

**平铺 token-leaf CST 实证（parser.mbt:3851-3858 `leaf_for_token` verbatim）— 为什么 analyzer 必须做二次解析：**
```moonbit
fn leaf_for_token(token : @token.Token) -> @syntax.SyntaxElement {
  let kind = match token.kind {
    @token.TokenKind::Whitespace | @token.TokenKind::Newline |
    @token.TokenKind::Comment | @token.TokenKind::Bom => @syntax.LeafKind::SourceTrivia
    @token.TokenKind::Error => @syntax.LeafKind::SourceError
    @token.TokenKind::Unknown => @syntax.LeafKind::SourceSkipped
    _ => @syntax.LeafKind::SourceToken
  }
  @syntax.SyntaxElement::Leaf(@syntax.SyntaxLeaf::new(kind, token.span))
}
```
> **关键事实：** `SyntaxLeaf` 只携带 `LeafKind` + span，**不携带 TokenKind**（syntax.mbt:55-58）；Select 节点是平铺 token-leaf 流（`finish_statement`/`segment_children_for_events`，parser.mbt:3777-3958）。因此 analyzer 只能按 token 原始字节分类——这正是 D-01 二次解析的实证。

**安全边界（research Anti-Patterns/Pitfall 1）：** 只对**整 token 字节**做 `word_is` 判定，`'` 开头叶子归字面量、`` ` ``/`"` 开头归 quoted 标识符（永不作关键字、永不计括号）；括号深度只对整 token 字节等于 `(`/`)` 的叶子计数——**永不重扫 leaf 内部字节**，天然免疫「关键字在字符串内」陷阱。

---

### `analyzer/resolve.mbt`（service，request-response）— **[NEW]**

**Analog:** `analyzer.mbt` `resolve_table_references`（295-336，上文引用）+ `formatter` D-33 refusal 哲学（formatter/format.mbt:1-4、formatter/refuse.mbt:1-4）。

**作用域栈入口纪律（沿用 resolve_table_references 的只读入口模式，analyzer.mbt:295-298）：**
```moonbit
pub fn[T : Catalog] resolve_table_references(
  node : @syntax.SyntaxNode,
  source_bytes : Bytes,
  catalog : T,
) -> Array[String]
```
新入口（建议 `pub fn[T : Catalog] analyze(node, source_bytes, catalog) -> AnalysisResult`）沿用同一签名形状：只消费 `@syntax.SyntaxNode` + 调用方 bytes + 注入 catalog，走作用域栈 + 解析时 ASCII case-fold 查找（D-03），产出 `AnalysisResult`。

**D-33 refusal 哲学（formatter/format.mbt:1-4 verbatim）— Pitfall 7「对错误/恢复树直接分析」的镜像处理：**
```moonbit
/// Refusal-first format entry (D-33, research Pattern 5): a tree containing
/// error/missing/skipped material returns accepted=false with empty output and
/// exactly one FATHOM-FORMAT-001 diagnostic — never partial bytes. The
/// function never panics: every source.slice failure becomes a refusal
```
> ANAL-01 对应语义：入口先检查 body kind 非 Select/DML 族则跳过；解析出 Error/Missing 的语句产出空 bindings + 一条「requires complete parse」诊断（镜像 D-33 refusal），绝不 panic。refuse 扫描实现见 formatter/refuse.mbt:1-4（递归找 Error/Skipped/Missing 节点 + SourceError/SourceSkipped leaf）。

**span 基础设施（source/source.mbt:15-20 `Span::checked` verbatim）— binding 保留源码 span 的语义来源：**
```moonbit
pub fn Span::checked(start_byte : Int, end_byte : Int, source_length : Int) -> Result[Span, SpanError] {
  if start_byte < 0 || end_byte < start_byte || end_byte > source_length {
    if end_byte < start_byte {
      Err(Reversed(start_byte~, end_byte~))
    } else {
      Err(OutOfBounds(start_byte~, end_byte~, source_length~))
    }
  } else {
    Ok({ start_byte: start_byte, end_byte: end_byte })
  }
}
```
> `leaf.span` 已是 `@source.Span`；`resolve.mbt` 从叶子取 `start_byte`/`end_byte` 平铺进 Binding/Diagnostic，**不命名 `@source.Span` 类型、不 import source**（D-01）。

**安全边界（research Security Domain）：** 二次解析加括号深度上限（超限产出「requires complete parse」诊断而非递归）；catalog 的 `data_type`/`name` 一律作不透明 String 处理（T-02-42），绝不执行、绝不格式化进语法通道。

---

### `analyzer/analyzer_wbtest.mbt`（test，白盒）— **[NEW, 可选]**

**Analog:** `lsp/selection_wbtest.mbt`（`_wbtest.mbt` 白盒惯例：直接测内部函数，黑盒面无法触发的路径）。**注意：`analyzer/` 目前没有任何测试文件**（目录仅 `analyzer.mbt` + `moon.pkg`）——这是本仓库第一个 analyzer 内测试，需新建，无既有文件可扩展。

**白盒测试惯例（lsp/selection_wbtest.mbt:1-17 verbatim 节选）：**
```moonbit
// White-box companion to selection_test.mbt: the D-03 stale-response guard
// (test i) exercises the internal version-guarded publication path directly,
// which the black-box surface cannot trigger in a synchronous server.

fn message(text : String) -> RpcMessage {
  match parse_message(@utf8.encode(text)) {
    Ok(value) => value
    Err(_) => panic()
  }
}

test "stale_publication_attempt_is_dropped_by_version_guard" {
  // (i) D-03: a publication computed for a document revision older than the
  // stored version is dropped — the response stream contains no
  // publishDiagnostics for the stale version.
  let state = ServerState::new()
  state.initialized = true
  // ...
}
```
> **适用面（research）：** 纯 helper 白盒单测（子句切分 `clause_break`、case-fold、标识符解码）不依赖 parser，放 `analyzer/` 内 `analyzer_wbtest.mbt`。依赖 parser 产 CST 的测试必须放 `test/`（analyzer 自身不能 import parser）。

---

### `test/analyzer_test.mbt`（test，集成）— **Modified**

**Analog:** 自身（既有 parse→analyze 断言惯例）。**D-03 断言更新点 + ANAL-01 新集成测试落点。**

**trait-dispatch helper（test/analyzer_test.mbt:10-12 verbatim）— D-05 扩展时同提交迁移：**
```moonbit
/// Trait-dispatch helper: resolves `table` through the Catalog trait itself so
/// the trait object path (used by resolve_table_references) is exercised.
fn catalog_lookup[T : @analyzer.Catalog](catalog : T, name : String) -> @analyzer.TableInfo? {
  @analyzer.Catalog::table(catalog, name)
}
```

**D-03 断言更新点（test/analyzer_test.mbt:32-34 verbatim）— 从 case-sensitive 改为 case-insensitive 匹配断言：**
```moonbit
  assert_true(@analyzer.StaticCatalog::lookup(catalog, "missing") is None)
  // Keys are case-sensitive for now (documented): "T" is not "t".
  assert_true(@analyzer.StaticCatalog::lookup(catalog, "T") is None)
}
```
> 随 D-03 更新：`lookup("T")` 命中 `t`（解析时 case-fold），并新增 quoted 精确匹配用例（`` `T` `` 不折叠）。

**ANLY-01 字节一致性负门禁（test/analyzer_test.mbt:51-63 verbatim 节选）— ANAL-01 必须继续锁定：**
```moonbit
test "analyzer_syntax_only_path_is_unchanged_by_catalog" {
  let raw = b"INSERT INTO t VALUES (1); SELECT * FROM t"
  let first = match @api.parse_with_ids(raw, "doris", "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  // Building a catalog and looking tables up must never touch the parser.
  let catalog = @analyzer.StaticCatalog::new([{ name: "t", columns: [{ name: "id", data_type: "INT" }] }])
  assert_true(@analyzer.StaticCatalog::lookup(catalog, "t") is Some(_))
  let second = match @api.parse_with_ids(raw, "doris", "4.x", "strict") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(first.valid)
  assert_eq(first.valid, second.valid)
  assert_eq(first.diagnostics.length(), second.diagnostics.length())
  // ...
}
```

**集成测试 setup（resolve_table_references 测试，test/analyzer_test.mbt:152-180 verbatim 节选）— parse→analyze 断言风格：**
```moonbit
  let raw = b"INSERT INTO t VALUES (1); UPDATE t2 SET a = 1; DELETE FROM t4 WHERE a = 1; MERGE INTO t5 USING src ON t5.id = src.id WHEN MATCHED THEN UPDATE SET t5.v = src.v; CREATE TABLE t3 (a INT)"
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
  assert_true(parsed.valid)
  assert_eq(parsed.diagnostics.length(), 0)
  let catalog = @analyzer.StaticCatalog::new([
    { name: "t", columns: [{ name: "id", data_type: "INT" }] },
    // ...
  ])
  let resolved = @analyzer.resolve_table_references(parsed.root, source.bytes(), catalog)
  assert_eq(resolved, ["t", "t4", "t5"])
```

**DialectContext helper（test/recovery_test.mbt:4-6 verbatim）— 集成测试统一入口：**
```moonbit
fn doris_context(profile_id : String) -> @dialect.DialectContext {
  { dialect: @dialect.Dialect::Doris, profile_id: profile_id, exact_release: profile_id, feature_introduction: "" }
}
```

**test/ 包 import 契约（test/moon.pkg verbatim）— ANAL-01 集成测试所需 alias 已全部就位：**
```
import {
  "fathom/sql/analyzer" @analyzer,
  "fathom/sql/api" @api,
  "fathom/sql/parser" @parser,
  "fathom/sql/printer" @printer,
  "fathom/sql/source" @source,
  "fathom/sql/syntax" @syntax,
  "fathom/sql/token" @token,
  "fathom/sql/formatter" @formatter,
  "fathom/sql/dialect" @dialect,
}
```

---

### `test/analyzer_anal01_test.mbt`（test，集成 + 快照）— **[NEW]**

**Analog:** `parity/flink_grammar_test.mbt:677-680` 快照模式 + `test/analyzer_test.mbt` 集成 setup（上文引用）。

**快照 helper（parity/flink_grammar_test.mbt:677-680 verbatim）— `moon test --update` 是唯一写路径，CI 无 `--update`：**
```moonbit
fn flink_grammar_snapshot_test(t : @test.Test, content : String, filename : String) -> Unit raise SnapshotError {
  t.write(content)
  t.snapshot(filename=filename)
}
```
**推荐（research 例 3）：**
```moonbit
test "analyzer-anal01 select-basic doris-4.x" {
  let t = @test.Test("analyzer-anal01 select-basic doris-4.x")
  analyzer_snapshot_test(t, analyze_json(b"SELECT a, b FROM db.t", catalog), "analyzer.select-basic.json")
}
```

**快照命名惯例（parity/__snapshot__ 目录实证）：** `<suite>.<fixture-id>.<profile>.<mode>.json`（如 `flink-grammar.select-cte-join-agg.flink-2.3.0.strict.json`）。ANAL-01 建议 `analyzer.<fixture-id>.doris-<profile>.json`。

**CI 执行面（ci.yml:66-67 verbatim 节选）— `test/` 包全量在 native target 跑：**
```yaml
      - name: moon test (native)
        run: |
          moon test --target native \
            --package test --package parity --package lsp --package api \
            --package source --package token --package lexer --package parser \
            --package printer --package syntax --package completion --package analyzer
```
> `analyzer` package 已在 native 测试矩阵内；`test/analyzer_anal01_test.mbt` 随 `--package test` 执行。

---

### `docs/API.md`（docs）— **Modified**

**Analog:** 自身 §Optional Name-Resolution API（docs/API.md:275-303）。更新点：新公共 API（`AnalysisResult`/`Binding`/`FunctionInfo`/db 作用域）、D-03 case policy（case-insensitive 匹配 + quoted 精确）、D-04 类型诊断范围、移除「deferred to v2 (D-24)」表述。

**现文档结构（docs/API.md:275-303 verbatim 节选）— 保持「代码块 + 散文」双轨：**
```markdown
### Optional Name-Resolution API

`fathom/sql/analyzer` is not part of the syntax-validity path. It consumes only `syntax.SyntaxNode`, caller-provided source bytes, and a catalog:

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

Currently, `resolve_table_references` returns only target table names that exist in the catalog and belong to supported DML/DDL statements; missing table names are omitted, no parser diagnostics are generated, and no type inference or Doris FE execution-semantics analysis is performed. ...
```
> 端点一览表（docs/API.md:31）中 `resolve_table_references` 行保持「Not required」语义；新增 analyzer API 行时沿用同表格式。

---

### `.planning/REQUIREMENTS.md`（docs/traceability）— **Modified（D-07 closeout）**

**Analog:** 自身 Traceability 表 + CLOSE-01/02 VERIFIED 行。D-07 只做正式核实记录 + traceability 升级，不重跑。

**CLOSE-01/02 已核实记录（REQUIREMENTS.md:13-14 verbatim）：**
```markdown
- [x] **CLOSE-01**: User can verify the shipped VS Code extension ... — **VERIFIED 2026-08-06**: `vscode/scripts/host-verify.mjs` launched real VS Code 1.132.0 extension hosts; 3 modes passed (diagnostics/format/completion/4.x-merge, 2.1 MERGE profile propagation, unavailable-server fallback). Fixed the client's `LogOutputChannel` requirement bug.
- [x] **CLOSE-02**: Release gate includes a linear-Wasm runtime execution step in CI ... — **VERIFIED 2026-08-06**: `.github/workflows/ci.yml` + release gate run `moon test --target wasm --package parity` (12/12, linear-Wasm runtime execution) + native cross-check.
```
**Traceability 表（REQUIREMENTS.md:66-69 verbatim）：**
```markdown
| Requirement | Phase | Status |
|-------------|-------|--------|
| CLOSE-01 | Phase 5 | Complete (verified 2026-08-06) |
| CLOSE-02 | Phase 5 | Complete (verified 2026-08-06) |
| ANAL-01 | Phase 5 | Pending |
```
> **D-07 最小工作：** Traceability 表 CLOSE-01/02 从「Complete (verified 2026-08-06)」升级为正式核实条目（引用 host-verify.mjs、ci.yml job 名、脚本路径、2026-08-06 记录行）。无新代码、无新测试。

---

### `.planning/STATE.md`（docs/traceability）— **Modified（D-07 closeout）**

**Analog:** 自身 Deferred Items 表（STATE.md:247-259）。D-07 在阶段验证文档中记录「证据已核实 + 引用路径」，不重跑。

**既有 Deferred Items 记录行（STATE.md:254, 257 verbatim 节选）— 本阶段 traceability 引用锚点：**
```markdown
| verification_override | Phase 04 ECO-07 human-hosted VS Code launch (04-04 Task 4, blocking-human; requires a machine with VS Code) | **verified 2026-08-06** — installed VS Code 1.132.0 + @vscode/test-electron host harness (vscode/scripts/host-verify.mjs); 3 real-extension-host modes passed (diagnostics/format/completion/4.x-merge; 2.1 MERGE DORIS-PARSE-006 profile propagation; unavailable-server fallback). Fixed real bug: client requires LogOutputChannel `{log:true}` (plain channel crashed startup). |
| ci_recommendation | linear-Wasm runtime execution parity step before release | **addressed 2026-08-06** — CI workflow `.github/workflows/` added with `moon build --target wasm` + parity fixture execution step (CLOSE-02) |
```

---

## Shared Patterns

### 1. D-21 边界纪律（所有 analyzer 文件）
**Source:** `analyzer/moon.pkg:1-3` + `parser/moon.pkg:1-7` + `analyzer/analyzer.mbt:1-20` 头注
**Apply to:** `analyzer.mbt`/`analysis.mbt`/`select_model.mbt`/`select_parser.mbt`/`resolve.mbt`
- analyzer 只 import `fathom/sql/syntax` + 调用方 source bytes；**不 import parser/token/lexer/api/source**。
- parser 永不 import analyzer（`parser/moon.pkg` 负门禁现状保持；`test/moon.pkg` 断言负门禁）。
- 公共 API 用 `start_byte`/`end_byte` Int 平铺 span（D-01/D-06 交互结论）——plan 不得为此修改 `analyzer/moon.pkg`。

### 2. 平铺 span 可序列化记录
**Source:** `api/api.mbt:305-313` `PrimitiveDiagnostic`；`analyzer.mbt:23-34` `pub(all)` 先例
**Apply to:** `analysis.mbt`（`Binding`/`AnalysisDiagnostic`/`AnalysisResult`/`FunctionInfo`）
- `code`/`message`/`start_byte`/`end_byte` 字段与 `api.PrimitiveDiagnostic` 同构；bindings 加 `name`/`resolved_to`/`kind`/`data_type`。
- `pub(all)` 使调用方可从自有元数据构造（`ColumnInfo`/`TableInfo` 先例，analyzer.mbt:22）。
- 独立诊断 code（`"unknown-table"` 等稳定字符串），不进入 `FATHOM-PARSE` 语法通道。

### 3. 解析时 ASCII case-fold（D-03）
**Source:** `analyzer/analyzer.mbt:87-101` `bytes_equal_ci`；`completion/completion.mbt:27-43` `word_is`/`bytes_equal_ci`
**Apply to:** `select_parser.mbt`（子句切分关键字判定）、`resolve.mbt`（catalog 查找）、`analyzer.mbt`（StaticCatalog doc 语义更新 + 测试断言更新）
- catalog key/display 名保持作者原样、不构造期归一化；解析时折叠比较；binding 保留源码拼写 + span。
- 带引号（backtick/双引号）标识符精确匹配、保留大小写（ROADMAP SC4）。

### 4. 快照/golden 测试（D-06）
**Source:** `parity/flink_grammar_test.mbt:677-680`；`parity/__snapshot__/` 命名惯例；`ci.yml:66-67`
**Apply to:** `test/analyzer_anal01_test.mbt`、`analyzer/analyzer_wbtest.mbt`（如有断言级快照）
- `@test.Test("...")` + `t.write(content)` + `t.snapshot(filename)`；`moon test --update` 是唯一写路径，CI 无 `--update`。
- 快照名 `<suite>.<fixture-id>.<profile>.<mode>.json`；`test/` 包在 native target 全量执行（ci.yml）。

### 5. D-33 refusal 哲学（错误/恢复树处理）
**Source:** `formatter/format.mbt:1-4`；`formatter/refuse.mbt:1-4`
**Apply to:** `resolve.mbt`（Pitfall 7）
- body kind 非 Select/DML 族则跳过；Error/Missing 树产出空 bindings + 一条「requires complete parse」诊断，绝不 panic。
- 二次解析加括号深度上限（防病态嵌套栈溢出，research Security Domain V5）。

### 6. 只读 syntax-view 走查入口
**Source:** `analyzer/analyzer.mbt:295-336` `resolve_table_references`
**Apply to:** `resolve.mbt` 新 `analyze` 入口
- 只消费 `@syntax.SyntaxNode` + 调用方 bytes + 注入 catalog；catalog 不可信（T-02-42）、只被 analyzer 消费。
- 无 catalog 时语法结果字节不变（ANLY-01）——`test/analyzer_test.mbt:51-63` 持续断言。

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `analyzer/select_parser.mbt` | service | transform | **无完整先例：** 仓库没有任何「对恢复 token 流做括号深度感知的二次结构切分」实现。现有 building block（`completion.mbt` `word_is`、`analyzer.mbt` `source_token_texts`/`leading_prefix_end`、`parser.mbt` `parse_select_core` 子句顺序）各自是类比，但**复合逻辑（paren-depth 子句切分 + 限定名/别名解析）是 net-new**——planner 用 RESEARCH.md Pattern 2 的推荐实现，而非复制单一文件。 |
| `analyzer/select_model.mbt` | model | transform | **无 Select 子模型先例：** `syntax/syntax.mbt` 只有粗粒度 `SyntaxKind::Select`（syntax.mbt:5），无子句/表项/限定名细分节点（D-01 实证）。`ClauseKind`/`SelectCore`/`SelectModel`/`CteDef` 是 analyzer 内部首创结构；planner 用 RESEARCH.md Pattern 1-3 推荐形状 + `syntax.mbt` 枚举风格。 |
| `analyzer/analyzer_wbtest.mbt` | test | N/A | **`analyzer/` 目前无任何测试文件**（目录仅 `analyzer.mbt` + `moon.pkg`）。白盒测试惯例可从 `lsp/selection_wbtest.mbt` 复制，但这是 analyzer 首个内测文件，需新建（`_wbtest.mbt` 命名 + 内部 helper 直测）。 |

> 其余 10/12 文件均有 exact 或 role-match analog（多为「自身扩展」或「同形状记录/同模式快照」）。两个 partial 文件的核心新增量正是 D-01 的「analyzer 内部二次解析结构层」——仓库给不出该层的现成 analog，这是本阶段设计的预期净新增，planner 应以 RESEARCH.md 的推荐实现为准并锁定测试。

---

## Metadata

**Analog search scope:** `analyzer/`、`syntax/`、`parser/`、`api/`、`completion/`、`parity/`、`test/`、`source/`、`formatter/`、`lsp/`、`docs/`、`.planning/`、`.github/workflows/`
**Files scanned:** 18（12 planned + 6 辅助：parser.mbt 四段、source.mbt、formatter 三段、lsp selection_wbtest、recovery_test、ci.yml、host-verify.mjs、moon.mod、moon.pkg×4）
**Pattern extraction date:** 2026-08-10
**Verification basis:** 全部 excerpt 本 session 直接 `read`/`grep` 源文件核对（verbatim + 行号）；行号引用准确到函数边界。

---

## PATTERN MAPPING COMPLETE
