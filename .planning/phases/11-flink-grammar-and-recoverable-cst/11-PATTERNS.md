# Phase 11: Flink Grammar and Recoverable CST - Pattern Map

**Mapped:** 2026-08-09
**Files analyzed:** 12 个唯一目标文件（7 个修改 + 5 个新增）
**Analogs found:** 11 / 12（1 个「无既有 analog」：MATCH_RECOGNIZE 子语言）

> 本阶段把 Phase 10 的 Flink **词法核心**扩展为真实语句级 grammar（D-04/D-06），
> analog 分四类：(1) **同构分发** —— `parse_flink_segment` 从 `parse_doris_segment`
> 拷贝 keyword-first dispatch + `finish_statement` trailing 消费骨架；(2) **自身参数化** ——
> `precedence()` 改为 `precedence(context, cursor)` 方言策略表，Doris 臂逐字不变；
> (3) **同文件独立生产** —— 新 `parser/flink_grammar.mbt` 从 parser.mbt 各 Doris 生产函数
> 拷贝函数骨架（`depth_allowed` → `expect_word`/`consume_word`/`advance` → 子句消费 →
> `recover_to_clause_boundary` → `finish_statement`），但**内容按 Flink grammar 独立写**
> （禁止复用 Doris table_ref/type/DDL 内容，Pitfall 1/2/7）；(4) **机制复用** ——
> parity flink-grammar 快照组从 `parity/flink_lexical_test.mbt`（Phase 10）+ 
> `baseline_test.mbt` 复用 fixture/snapshot 门禁；dialect 行表从自身 `flink_classification_rows`
> 追加 MATCH_RECOGNIZE 行（Pitfall 9）。
>
> **硬约束（贯穿全部 pattern）：** Doris 既有 213 个 parity 快照 + `doris_classification_rows`
> 116 行字节级零漂移（D-05/D-08）；FATHOM-PARSE-008 退役后 code 保留空缺不复用（D-06，
> 同 `DORIS-PARSE-005` 空缺惯例）；dialect 不进诊断 code 前缀（D-10）；新 SyntaxKind
> 追加到枚举末尾不重排（避免 `kind_id` 序号漂移，D-02）。

## File Classification

### A. 修改文件（analog = 自身或同文件既有函数）

| Modified File | Role | Data Flow | Analog（拷贝自） | Match Quality |
|---------------|------|-----------|------------------|---------------|
| `parser/parser.mbt`（`parse_flink_segment` 008→真实分发） | parser（路由/分发） | request-response | 自身 `parse_doris_segment` `:3354-3403`（keyword-first dispatch + `finish_statement`） | exact |
| `parser/parser.mbt`（`precedence()` 方言参数化） | parser（表达式策略） | request-response | 自身 `precedence` `:263-274` + 两个调用点 `:686-691`/`:770-778` | self-rename |
| `parser/parser.mbt`（新增 Flink 子句边界谓词 + 负门禁） | parser（恢复/诊断） | request-response | 自身 `is_update_clause_boundary` `:1561-1565` + `recover_to_clause_boundary` `:1583-1608` + `is_create_table_clause_boundary` `:2350-2359` + `add_feature_diagnostic` `:362-380` | exact |
| `parser/parser.mbt`（008 测试改写） | test | batch | 自身 `parser_flink_context_rejects_every_input_as_not_implemented` `:3607-3631` | self-rename |
| `syntax/syntax.mbt`（SyntaxKind 追加 Flink 语句族） | model（CST kind） | lookup | 自身 `SyntaxKind` 枚举 `:2-26` + `kind_id` 对侧契约 | exact |
| `api/api.mbt`（`kind_id` 新 wire 字符串） | facade（wire） | serialization | 自身 `kind_id` `:331-357` | exact |
| `dialect/flink.mbt`（补 MATCH_RECOGNIZE 等保留字行） | model（关键字策略） | lookup | 自身 `flink_classification_rows`（142 行，source 逐行 release grammar） | exact |
| `dialect/classification.mbt`（测试覆盖新保留字） | model | lookup | 自身 `classification_is_reserved` + `classification_is_dialect_independent_and_release_aware` 测试 | self-rename |

### B. 新增文件（从现有 analog 拷贝模式）

| New File | Role | Data Flow | Closest Analog | Match Quality |
|----------|------|-----------|----------------|---------------|
| `parser/flink_grammar.mbt` | parser（语句族生产） | request-response | `parser.mbt` 的 `parse_insert` `:1502-1559` / `parse_create` `:1872-1928` / `parse_create_table` `:2426-2529` / `parse_column_definition` `:2570-2665` / `parse_distribution_clause` `:2983-3030`（函数骨架） | role-match（骨架复用、内容独立） |
| `parity/flink_grammar_test.mbt` | test（snapshot） | batch（冻结） | `parity/flink_lexical_test.mbt`（FlinkLexicalFixture + flink_snapshot_test + 每 fixture 测试块）+ `parity/baseline_test.mbt:25-29,351-354` | exact |
| `parity/fixtures/flink-grammar/manifest.tsv` | fixture（provenance 数据） | batch | `parity/fixtures/flink-lexical/manifest.tsv`（Phase 10 provenance 行形态） | exact |
| `parity/__snapshot__/flink-grammar.{fixture}.{profile}.{strict,editor}.json` | fixture（golden） | batch | `parity/__snapshot__/flink-lexical.*.{profile}.{mode}.json`（26 个既有快照字节形态） | exact |
| `scripts/extract_flink_grammar.py` | utility（研究时提取 + 校验） | batch（transform） | `scripts/extract_flink_lexical.py` + `corpus/tools/check_keywords.py:45-106`（stdlib 校验循环） | exact |
| `.planning/phases/11-*/approved-changes.md` | register（D-08 批准制） | batch | `.planning/phases/10-flink-release-profiles-and-lexical-core/approved-changes.md`（注册表行形态） | exact |

> **不变文件（显式确认）：** `binding/schema.mbt`（FATHOM-PARSE-* 是 parser 内 `add_diagnostic`
> 直发，不经 schema 映射；`dialect`/`profile`/`exact_release` metadata 已由 parse envelope 携带，
> D-04「诊断经 metadata 携带方言信息」已满足）；`lexer/lexer.mbt`（`symbol_width_flink` `:412-424`
> 已 tokenize `||`/`=>`/`..`，本阶段无需词法改动）；`source/`、`token/`、`binding/schema.mbt`
> 的诊断 code 映射均无改动。

## Pattern Assignments

### `parser/parser.mbt` — `parse_flink_segment` 真实关键字分发（D-04/D-06）

**Analog:** 自身 `parse_doris_segment`（`parser/parser.mbt:3354-3403`）。这是 Flink 分支挂接
真实 grammar 的蓝本：keyword-first dispatch + `finish_statement` trailing 消费 + `unsupported_statement`
兜底。**替换目标** `parse_flink_segment`（`:3405-3429`）现为全量 FATHOM-PARSE-008（D-06 退役）。

**分发骨架（拷贝自 parse_doris_segment `:3362-3401`，逐字形态）**:
```moonbit
fn parse_doris_segment(
  stream : @token.TokenStream,
  start_index : Int,
  end_index : Int,
  statement_id : UInt,
  state : RecoveryState,
  context : @dialect.DialectContext,
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
        Some(next) if bytes_equal_ci(next, b"SELECT") => finish_statement(... @syntax.SyntaxKind::Select, ...)
        Some(next) if bytes_equal_ci(next, b"UPDATE") => finish_statement(... @syntax.SyntaxKind::Update, ...)
        Some(next) if bytes_equal_ci(next, b"DELETE") => finish_statement(... @syntax.SyntaxKind::Delete, ...)
        _ => unsupported_statement(stream, start_index, end_index, span, state, statement_id)
      }
    }
    Some(raw) if bytes_equal_ci(raw, b"CREATE") => {
      let kind = create_form_kind(stream, indices, 0)
      finish_statement(stream, cursor, start_index, end_index, span, parse_create(cursor, state, stream.source, statement_id), state, statement_id, kind, "unexpected tokens after CREATE statement")
    }
    _ => unsupported_statement(stream, start_index, end_index, span, state, statement_id)
  }
}
```
Flink 分支逐臂替换成 RESEARCH §Pattern 1 骨架：`SELECT`/`WITH` → `parse_flink_query`（共享
query skeleton 的 Flink 安全子集）、`INSERT`/`UPSERT` → `parse_flink_insert`、`UPDATE`/`DELETE`、
`EXPLAIN`/`SHOW`/`DESCRIBE`/`DESC`/`ANALYZE`、`CREATE`/`ALTER`/`DROP`（catalog/database/table/
view/function）、`USE`/`SET`/`RESET`，未知 starter → `unsupported_statement`（007）。**每个
`finish_statement` 调用的 kind 参数**对应 §6.1 语句族（`Select`/`Insert`/`CreateTable`/新 kind）。

**finish_statement trailing 消费骨架（`:3129-3161`，Flink 语句同样在 `;`/段尾停）**:
```moonbit
fn finish_statement(
  stream : @token.TokenStream,
  cursor : Cursor,
  start_index : Int,
  end_index : Int,
  span : @source.Span,
  parsed : Bool,
  state : RecoveryState,
  statement_id : UInt,
  kind : @syntax.SyntaxKind,
  trailing_message : String,
) -> @syntax.SyntaxNode {
  let mut trailing = false
  while cursor.position < cursor.indices.length() {
    match raw_at(cursor) {
      Some(raw) if raw == b";" => advance(cursor)
      Some(_) => {
        let before = cursor.position
        trailing = true
        recover_expression(cursor, state, stream.source, statement_id)
        if cursor.position == before { advance(cursor) }
      }
      None => cursor.position = cursor.indices.length()
    }
  }
  if trailing { add_diagnostic(state, "FATHOM-PARSE-001", trailing_message, "statement", span, statement_id) }
  let children = segment_children_for_events(stream, start_index, end_index, state.feature_events)
  if !parsed || trailing { children.push(@syntax.SyntaxElement::ChildNode(require_node(@syntax.SyntaxNode::missing(span.end_byte, stream.source.byte_length())))) }
  let statement_node = require_node(@syntax.SyntaxNode::new(kind, span, children))
  require_node(@syntax.SyntaxNode::new(@syntax.SyntaxKind::Statement, span, [@syntax.SyntaxElement::ChildNode(statement_node)]))
}
```

**008 退役（D-06）**：删除 `:3405-3429` 的 008 生产路径 + 改写测试
`parser_flink_context_rejects_every_input_as_not_implemented`（`:3607-3631`，断言
`code == "FATHOM-PARSE-008"`）——改为按真实 grammar 断言合法 Flink 语句
`valid=true`、无 008；**008 code 保留空缺不复用**。

**with_prefix_verb（`:1381-1441`，Flink WITH 分发复用）**：`parse_doris_segment` 用它在
WITH 前缀后取语句动词（SELECT/UPDATE/DELETE/MERGE）。Flink 分支同样用它区分
`WITH c AS (...) SELECT|UPDATE|DELETE`——直接复用同一函数，无需改动（Doris 零漂移）。

---

### `parser/parser.mbt` — `precedence(context, cursor)` 方言策略表（Pattern 4）

**Analog:** 自身 `precedence`（`parser/parser.mbt:263-274`）。当前是纯原文函数，无
`||`（CONCAT）/`=>`（NAMED_ARGUMENT_ASSIGNMENT）。改为按 `context.dialect` 选策略：
Doris 臂逐字返回现有表（Pitfall 7：禁止改共享表污染 Doris）。

**现状（`:263-274`，Doris 臂逐字保持）**:
```moonbit
fn precedence(cursor : Cursor) -> Int? {
  match raw_at(cursor) {
    Some(raw) if bytes_equal_ci(raw, b"OR") => Some(1)
    Some(raw) if bytes_equal_ci(raw, b"AND") => Some(2)
    Some(raw) if raw == b"=" || raw == b"<" || raw == b">" || raw == b"<=" ||
      raw == b">=" || raw == b"<>" || raw == b"!=" || raw == b"<=>" => Some(3)
    Some(raw) if raw == b"+" || raw == b"-" => Some(4)
    Some(raw) if raw == b"*" || raw == b"/" || raw == b"%" => Some(5)
    Some(raw) if raw == b"|" || raw == b"&" => Some(4)
    _ => None
  }
}
```
**改动点（RESEARCH Pattern 4 骨架）**：签名加 `context`；`match context.dialect` 后
Flink 臂增 `||` → CONCAT（A3：优先级介于比较与算数之间，Calcite `SqlStdOperatorTable.CONCAT`
语义）、`=>` 在函数/调用参数层处理（非二元优先级，`:8794`）。**两个调用点同步改**：
`wildcard_has_invalid_continuation`（`:686-691` 的 `let operator = match precedence(cursor)`）与
`parse_expression_context` 二元循环（`:770-778` 的 `match precedence(cursor)`）。`=>` 的消费点
在 Flink 函数调用参数层（`parse_expression_postfix` 的 `(` 分支，`:610-618`）——注意该分支现
`consume_symbol(cursor, b"(")` 后直接 `parse_expression_list_context`，Flink 需在此识别
`name => expr` 命名参数（RESEARCH Open Question 4 同族，语法级）。

---

### `parser/parser.mbt` — 新增 Flink 子句边界谓词 + 双向负门禁

**Analog:** 自身 per-family 边界谓词 + `recover_to_clause_boundary` + `add_feature_diagnostic`。

**recover_to_clause_boundary 骨架（`:1583-1608`，Flink 新谓词挂接同一函数）**:
```moonbit
fn recover_to_clause_boundary(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  boundary : (Bytes) -> Bool,
) -> Unit {
  let mut consumed = false
  let mut done = false
  while !done {
    match raw_at(cursor) {
      None => done = true
      Some(raw) if raw == b";" || boundary(raw) => done = true
      Some(_) => {
        let span = match token_at(cursor) { Some(token) => token.span; None => make_span(source, source.byte_length(), source.byte_length()) }
        if consume_recovery_step(state, span, statement_id) { advance(cursor); consumed = true } else { done = true }
      }
    }
  }
  if !consumed && raw_at(cursor) is Some(_) {
    match raw_at(cursor) {
      Some(raw) if raw == b";" || boundary(raw) => ()
      _ => advance(cursor)
    }
  }
}
```
**新谓词（RESEARCH §6.3 明文，`Bytes -> Bool` 形态同 `:1561-1565`）**：
- `is_flink_create_table_clause_boundary`（`COMMENT`/`DISTRIBUTED`/`PARTITIONED`/`WITH`/`LIKE`/`AS`）——骨架拷贝 `is_create_table_clause_boundary`（`:2350-2359`）:
```moonbit
fn is_create_table_clause_boundary(raw : Bytes) -> Bool {
  bytes_equal_ci(raw, b"ENGINE") || bytes_equal_ci(raw, b"KEY") ||
    bytes_equal_ci(raw, b"ORDER") || bytes_equal_ci(raw, b"BY") ||
    bytes_equal_ci(raw, b"COMMENT") || bytes_equal_ci(raw, b"PARTITION") ||
    ...
    bytes_equal_ci(raw, b"IF") || bytes_equal_ci(raw, b"NOT")
}
```
- `is_flink_match_recognize_boundary`（`MEASURES`/`ONE ROW`/`ALL ROWS`/`AFTER MATCH`/`PATTERN`/`DEFINE`/`)`，Pitfall 4/8）
- `is_flink_insert_boundary`（`PARTITION`/`ON CONFLICT`/`SELECT`/`VALUES`/`)`）

**负门禁诊断机制（双向，D-04）**：构造点本地化拒绝。拷贝 `add_feature_diagnostic`（`:362-380`）
的「record span → 查 metadata → add_diagnostic」形态，但**新诊断码用 FATHOM-PARSE-009**
（建议，Open Question 1；007 语义「unsupported statement」偏宽）：
```moonbit
fn add_feature_diagnostic(
  state : RecoveryState,
  feature : @dialect.DorisFeature,
  span : @source.Span,
  statement_id : UInt,
) -> Unit {
  record_feature_event(state, span)
  let metadata = feature.metadata()
  add_diagnostic(state, metadata.diagnostic_code, metadata.diagnostic_message, "released-version", span, statement_id)
}
```
Flink 侧仿此写 `add_dialect_gate_diagnostic(state, span, statement_id)` → `FATHOM-PARSE-009`
「syntax is not supported in the selected dialect」。**门禁位置**：每个 Flink-only / Doris-only
构造点（§9 矩阵）：Doris 路径的 `parse_select_core` QUALIFY gate（`:1212-1219`）与 INTO OUTFILE
（`:1218-1226`）在 Flink 分支不进入或 009 拒绝；`parse_table_ref` 的
PARTITION/TABLET/SAMPLE/TABLESAMPLE（`:917-975`）在 Flink 分支跳过；`parse_create_table` 的
`DUPLICATE KEY`/`ENGINE=`/`ROLLUP`/`AUTO PARTITION`（Doris-only）在 Flink 下 009。**同输入 ×
对方方言** fixture 断言（§10）覆盖双向。

---

### `parser/flink_grammar.mbt`（新增，语句族生产）

**Analog:** parser.mbt 的 Doris 生产函数（role-match：拷贝函数骨架，内容按 Flink grammar 独立写）。
同 package（`parser/moon.pkg` 无文件清单，包内自动编译）可访问所有 `priv` 原语（`Cursor`/
`RecoveryState`/`consume_word`/`expect_word`/`advance`/`raw_at`/`make_span`/`finish_statement`/
`recover_to_clause_boundary`/`significant_indices`）。

**每个生产函数的统一骨架（拷贝自 `parse_create_table` `:2426-2440` 头部 + 子句消费形态）**:
```moonbit
fn parse_create_table(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"TABLE", state, source, statement_id, "expected TABLE after CREATE")
  if consume_word(cursor, b"IF") {
    valid = expect_word(cursor, b"NOT", state, source, statement_id, "expected NOT after IF") && valid
    valid = expect_word(cursor, b"EXISTS", state, source, statement_id, "expected EXISTS after IF NOT") && valid
  }
  valid = parse_qualified_name(cursor, state, source, statement_id, "table name") && valid
  // LIKE variant
  if consume_word(cursor, b"LIKE") { ... return valid }
  let mut has_body = false
  if raw_at(cursor) is Some(b"(") {
    advance(cursor)
    has_body = true
    valid = parse_create_table_body(cursor, state, source, statement_id) && valid
    let closed = expect_symbol(cursor, b")", state, source, statement_id, "expected closing table body parenthesis")
    if !closed { recover_to_clause_boundary(cursor, state, source, statement_id, is_create_table_clause_boundary) }
    valid = closed && valid
  }
  // 子句顺序（Doris）：ENGINE → KEY → COMMENT → PARTITION → DISTRIBUTED → ROLLUP → PROPERTIES → AS
  if consume_word(cursor, b"ENGINE") { ... }
  ...
}
```
Flink 版（RESEARCH Pattern 2）子句顺序换成权威顺序 `[COMMENT][DISTRIBUTED][PARTITIONED BY][WITH][LIKE|AS]`，
列体用四类列分派（TypedColumn/MetadataColumn/ComputedColumn/TableConstraint/Watermark，`parserImpls.ftl:1103-1145`）。

**列体四类列分派骨架（拷贝自 `parse_create_table_body` `:2557-2599` 的 while-comma 循环）**:
```moonbit
fn parse_create_table_body(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = true
  let mut any = false
  let mut done = false
  while !done {
    if raw_at(cursor) is Some(b")") { done = true } else {
      any = true
      if is_index_definition_start(cursor) { valid = parse_create_table_index(...) && valid }
      else { valid = parse_column_definition(cursor, state, source, statement_id) && valid }
      if consume_symbol(cursor, b",") {
        if raw_at(cursor) is Some(b")") { ... valid = false; done = true }
      } else { done = true }
    }
  }
  if !any { ... valid = false }
  valid
}
```
Flink 分派条件换成「`WATERMARK FOR` → `parse_flink_watermark`；`PRIMARY KEY`/`UNIQUE` →
`parse_flink_table_constraint`；`name AS expr` → `parse_flink_computed_column`；
`name type METADATA [FROM] [VIRTUAL]` → `parse_flink_metadata_column`；否则
`parse_flink_typed_column`」。

**分布子句骨架（拷贝自 `parse_distribution_clause` `:2983-3030`，Flink `INTO n BUCKETS` 形态）**:
```moonbit
fn parse_distribution_clause(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  let mut valid = expect_word(cursor, b"BY", state, source, statement_id, "expected BY after DISTRIBUTED")
  if consume_word(cursor, b"HASH") { valid = parse_identifier_option(...) && valid }
  else if consume_word(cursor, b"RANDOM") { () }
  else { ... valid = false }
  if consume_word(cursor, b"BUCKETS") { ... }
  valid
}
```
Flink：`DISTRIBUTED [BY [HASH|RANGE](cols)] [INTO n BUCKETS]`（n 须正整数；`RANDOM` 不支持——
`testCreateTableWithRandomDistribution` `.fails`，`parserImpls.ftl:1560-1600`）。

**INSERT 骨架（拷贝自 `parse_insert` `:1502-1559`，Flink `RichSqlInsert` 形态不同需独立）**:
```moonbit
fn parse_insert(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
) -> Bool {
  if !depth_allowed(cursor, state, source, statement_id) { return false }
  let mut valid = expect_word(cursor, b"INSERT", state, source, statement_id, "expected INSERT statement")
  if consume_word(cursor, b"OVERWRITE") { ... } else { valid = expect_word(cursor, b"INTO", ...) && valid }
  valid = parse_qualified_name(cursor, state, source, statement_id, "table name") && valid
  ...
  if consume_word(cursor, b"VALUES") { valid = parse_values_rows(...) && valid }
  else if is_query_start(cursor) { valid = parse_query(...) && valid }
  ...
  valid
}
```
Flink `parse_flink_insert` 覆盖 `(INSERT|UPSERT) (INTO|OVERWRITE)` + `[PARTITION ...]` +
`[column list]` + `OrderedQueryOrExpr` + `[ON CONFLICT DO (ERROR|NOTHING|DEDUPLICATE)]`
（`parserImpls.ftl:2306-2379`）。

**CREATE 分发骨架（拷贝自 `parse_create` `:1872-1928` + `create_form_kind` `:1848-1870`）**:
Flink `parse_flink_create` 按第二词分派 `CATALOG/DATABASE/TABLE/VIEW/FUNCTION/TEMPORARY`
（Doris 版只认 TABLE/VIEW/INDEX/MATERIALIZED，`create_form_kind` 只作分发形状参考）。
`[TEMPORARY [SYSTEM]]` 前缀 + `CREATE FUNCTION ... AS 'class' [LANGUAGE ...]` 是 Flink-only。

**共享 query skeleton 复用边界（`parse_query` `:1363-1382` / `parse_select_core` `:1154-1228` /
`parse_cte_prefix` `:1325-1361`）**：骨架方言中立，但 Flink 分支**禁止进入** Doris-only 构造
（EXCEPT 投影修饰符 `:1174-1183`、QUALIFY gate `:1212-1219`、INTO OUTFILE `:1218-1226`、
table_ref 的 PARTITION/TABLET/SAMPLE/TABLESAMPLE `:917-975`）。建议 `match context.dialect`
门控或抽 `parse_flink_select_core` 薄封装。`parse_cte_prefix` 的 WITH RECURSIVE 诊断
（`:1334-1337`，FATHOM-PARSE-006）在 Flink 下**不触发**（Calcite base `WithList` 支持，
A1）——用 `cursor.stream.context.dialect is Flink` 门控。

---

### `syntax/syntax.mbt`（SyntaxKind 追加）

**Analog:** 自身。`SyntaxKind`（`syntax/syntax.mbt:2-26`）是 D-02 one-way 契约——**新 kind
追加到枚举末尾，绝不重排既有变体**（避免 `kind_id` 序号漂移，Pitfall 1）。新增语句族
（RESEARCH §6.1 建议粗粒度，planner 定稿命名）：`ShowStatement`/`DescribeStatement`/
`ExplainStatement`/`AnalyzeStatement`/`CreateCatalog`/`CreateDatabase`/`CreateFunction`/
`DropCatalog`/`DropDatabase`/`DropTable`/`DropView`/`DropFunction`/`AlterTable`/
`WatermarkClause`/`ComputedColumn`/`MetadataColumn`/`PrimaryKeyClause`/`TableLikeClause`/
`WindowTvf`/`MatchRecognize`/`SetOption`/`UseStatement`。

**现状（`:2-26`）**:
```moonbit
pub(all) enum SyntaxKind {
  Document
  Statement
  Select
  Insert
  Update
  Delete
  Merge
  ValueList
  CreateTable
  CreateView
  CreateIndex
  CreateMaterializedView
  ColumnDefinition
  KeyClause
  DistributionClause
  PartitionClause
  PropertyList
  Expression
  Token
  Trivia
  Error
  Skipped
  Missing
} derive(Eq, @debug.Debug)
```
**无需改动**：`node_invariants_hold`（`:57-75`）、`is_valid`（`:96-127`）不参与 kind 校验——
新 kind 自动满足（kind 不参与不变量）。**error/missing/skipped 节点工厂不变**
（`SyntaxNode::missing/error/skipped`，`:95-111`）——Flink 复用同一节点工厂（D-02/D-03）。

---

### `api/api.mbt`（`kind_id` 新 wire 字符串）

**Analog:** 自身 `kind_id`（`api/api.mbt:331-357`）。每个新 SyntaxKind 增一条
`SyntaxKind::X => "x"`（snake_case wire 字符串）。这是 D-02 one-way 契约的另一半。

**现状（`:331-357`）**:
```moonbit
fn kind_id(kind : @syntax.SyntaxKind) -> String {
  match kind {
    @syntax.SyntaxKind::Document => "document"
    @syntax.SyntaxKind::Statement => "statement"
    @syntax.SyntaxKind::Select => "select"
    ...
    @syntax.SyntaxKind::Missing => "missing"
  }
}
```
**无需改动**：`ParseResult` 构造（`api/api.mbt:409-446`）与 `primitive_node`（`:345-363`）自动
携带新语句族——dialect/profile/mode 已透传（CONTEXT.md Integration Points 明文「无新参数」）。

---

### `dialect/flink.mbt`（补 MATCH_RECOGNIZE 等保留字行，Pitfall 9）

**Analog:** 自身 `flink_classification_rows`（142 行，`source` 逐行 release grammar 引用）。
`MATCH_RECOGNIZE` 是 Calcite base 保留字 token（`Parser-calcite-1.36.0.jj:8214`）但**不在
Phase 10 行表**——`classification_of(flink, "MATCH_RECOGNIZE")` 返回 None，会被当普通标识符
接受，与 Flink parser 保留字行为不一致。

**行形态（拷贝自 `dialect/flink.mbt` 2.3.0 Reserved delta 块）**:
```moonbit
{ word: b"MATCH_RECOGNIZE", classification: Reserved, introduced_profile: "flink-2.3.0", source: "flink-sql-parser Parser-calcite-1.36.0.jj:8214 (MATCH_RECOGNIZE)" },
```
**位置**：追加到 2.3.0 Reserved delta 段（`CONFLICT`/`DEDUPLICATE`/`NOTHING` 等行旁）或按
release 归属。同一批次对照 `flink-2.3.0-reserved.txt` 全表差集补 parser 实际消费的其它缺失
Calcite base 多词/下划线 token（每词逐行核验 source）。**保留字必须能反引号引用**
（`SELECT \`MATCH_RECOGNIZE\``）。`is_reserved_word`（`dialect/classification.mbt:90-96`）
自动生效，无需改 classification.mbt 函数。

---

### `dialect/classification.mbt`（测试覆盖新保留字）

**Analog:** 自身。现有测试 `classification_is_dialect_independent_and_release_aware` 断言
`flink_230` 下 `VARIANT`/`QUALIFY`/`SAFE_CAST` reserved、`flink_120` 下 ABSENT。补
`MATCH_RECOGNIZE`：`flink_230`/`flink_213`/`flink_120` 均 reserved（Calcite base 三 release
都有该 token，`:8214`/对应 1.34/1.32 行）；`classification_is_reserved(flink_230, b"MATCH_RECOGNIZE")`
为 true。**Doris 侧断言不变**（`MATCH_RECOGNIZE` 不是 Doris 保留字——负门禁 fixture 覆盖）。

---

### `parity/flink_grammar_test.mbt`（新增，snapshot + 双向负门禁）

**Analog:** `parity/flink_lexical_test.mbt`（Phase 10）——fixture 结构 + snapshot 写入 + 每
fixture 测试块；底层 `@test.T::snapshot` 机制同 `parity/baseline_test.mbt:351-354`。

**Fixture 结构（拷贝 flink_lexical_test.mbt `:44-52` 形态，换为 flink-grammar）**:
```moonbit
pub(all) struct FlinkLexicalFixture {
  pub fixture_id : String
  pub dialect : String
  pub profile : String
  pub raw : Bytes
}
```
新 `FlinkGrammarFixture { fixture_id, profile, raw }`（同 baseline `BaselineFixture`
`baseline_test.mbt:25-29`），四类 fixture（positive/negative/incomplete/recovery ×
strict/editor）内嵌 raw bytes（D-05）。

**Snapshot 写入（拷贝 flink_lexical_test.mbt `:94-101`）**:
```moonbit
fn flink_lexical_parse_json(id : String, dialect : String, profile : String, mode : String) -> String {
  let fixture = flink_lexical_fixture(id, dialect, profile)
  @utf8.decode_lossy(@binding.fathom_parse_v1(fixture.raw, dialect, profile, mode)[:])
}

fn flink_snapshot_test(t : @test.Test, content : String, filename : String) -> Unit raise SnapshotError {
  t.write(content)
  t.snapshot(filename=filename)
}

test "flink-lexical hash-comment flink-2.3.0 strict" {
  let t = @test.Test("flink-lexical hash-comment flink-2.3.0 strict")
  flink_snapshot_test(t, flink_lexical_parse_json("hash-comment", "flink", "flink-2.3.0", "strict"), "flink-lexical.hash-comment.flink-2.3.0.strict.json")
}
```
新组命名 `flink-grammar.{fixture}.{profile}.{strict,editor}.json`（**独立命名空间**，与
Doris 213 组 + flink-lexical 26 组互不重叠，Pitfall 7）。**断言**：positive →
`valid=true` + `print_lossless(parse(x))==x` + CST 含目标语句族 kind；negative → `valid=false`
+ 诊断 span 定位 error token；incomplete/recovery → Missing/Error/Skipped 节点 + 有界步数
（CST-01）。`moon test --update --package parity` 生成；CI 无 `--update` 字节级失败。

**双向负门禁 fixture（D-04，flink-negative 矩阵）**：拷贝 flink_lexical_test.mbt 的
`flink_lexical_*_is_dialect_routed_and_independent` 断言形态——同一 raw 在双方言下跑
`fathom_parse_v1`，拒绝方言期望 `FATHOM-PARSE-009`/`007` + `valid=false`，对方言期望已定义
正例；同输入不出现双方言都 valid（Pitfall 2 警告信号）。

---

### `parity/fixtures/flink-grammar/manifest.tsv`（新增，provenance）

**Analog:** `parity/fixtures/flink-lexical/manifest.tsv`（Phase 10）。列记录 release 事实源：
`fixture_id  profile  exact_release  calcite_version  parser_config  grammar_path  line_range  source_archive_url  sha512  git_tag  git_commit`。每个 production 行号引用钉住 release
（RESEARCH §5），禁 folklore/moving 文档（Pitfall 5）。

---

### `parity/__snapshot__/flink-grammar.*.json`（新增，golden）

**Analog:** `parity/__snapshot__/flink-lexical.*.{profile}.{mode}.json`（26 个既有快照字节
形态，`fathom.parse.v1` envelope + `flink-grammar.` 前缀）。由 `flink_grammar_test.mbt` 的
`--update` 生成，非手写。

---

### `scripts/extract_flink_grammar.py`（新增，研究时提取）

**Analog:** `scripts/extract_flink_lexical.py`（Phase 10）+ `corpus/tools/check_keywords.py:45-106`
（stdlib 校验循环形态：problems 列表 + 逐行报告 + 非零 exit + 尾部 `ok:` 行）。提取动作：
读钉住 release 的 `Parser.tdd`/`parserImpls.ftl`/`Parser.jj` 生产行号 + `flink-2.3.0-reserved.txt`
差集，生成 fixture/manifest 校验。**归档是研究 fixture，不 ship**。

---

### `.planning/phases/11-*/approved-changes.md`（新增，D-08 注册表）

**Analog:** Phase 10 `approved-changes.md`（注册表行形态 + machine-readable patterns 段）。
Phase 11 注册：(1) **FATHOM-PARSE-008 退役**（code 保留空缺不复用，D-06）；(2) **FATHOM-PARSE-009
minting**（双向负门禁本地化诊断，Open Question 1，若 planner 采纳）；(3) **flink-grammar 快照组**
独立命名空间（`flink-grammar.{fixture}.{profile}.{strict,editor}.json`）；(4) **Doris 213 快照
零漂移**确认。Machine-readable 段无既有 `prefix:`/`key:` 迁移适用（全为新文件 + 新 code）。

## Shared Patterns

### 快照门禁 + 注册表批准制（D-05/D-08）
**Source:** `parity/baseline_test.mbt`（`@test.T::snapshot`，`:351-354`）+ `parity/flink_lexical_test.mbt`
（fixture + snapshot_test）+ `approved-changes.md`（machine-readable register）+ `scripts/baseline_diff.py`。
**Apply to:** `parity/flink_grammar_test.mbt`、`parity/__snapshot__/flink-grammar.*.json`、
`.planning/phases/11-*/approved-changes.md`。
**机制:** `moon test --update --package parity` 前必须先提交注册表条目（single-use 批准路径）；
无 `--update` 时任何字节差异失败；`baseline_diff.py --left --right --approve` 分 approved vs
unexpected。**任何共享 parser/CST 改动前重跑冻结 Doris baseline（213 快照，无 `--update`）**
（D-05 明文）。

### 恢复预算与有界性（D-03/CST-01）
**Source:** `parser/parser.mbt` `consume_recovery_step` `:226-238` + `depth_allowed` `:252-261` +
`resource_diagnostic` `:181-199` + `recover_to_clause_boundary` `:1583-1608`。
**Apply to:** `parser/flink_grammar.mbt`（每个 Flink 生产 + MATCH_RECOGNIZE 子语言同步点）。
**机制:** 双方言共享同一预算（recovery_steps cap / max_recursion_depth / max_diagnostics）；
Flink 新子语言（MATCH_RECOGNIZE/PATTERN）用**独立同步点**（`MEASURES`/`ONE ROW`/`ALL ROWS`/
`AFTER MATCH`/`PATTERN`/`DEFINE`/`)`）防无限推进（Pitfall 4/8）。

### 无损 CST 节点工厂（CST-01）
**Source:** `syntax/syntax.mbt` `SyntaxNode::new/missing/error/skipped`（`:95-111`）+
`node_invariants_hold`（`:57-75`：子节点 span 连续覆盖父 span）。
**Apply to:** `parser/flink_grammar.mbt`（新语句族节点）、`syntax/syntax.mbt`（新 kind）。
**机制:** Flink 新增语句族节点遵守同一「span 连续 + source-backed 叶子」不变量 → lossless
replay 自动保持（`print_lossless(parse(x))==x`）。每个 positive/recovery fixture 双模式断言该
等式（RESEARCH §6.4）。

### 诊断码稳定契约（D-04/D-10）
**Source:** `parser/parser.mbt` `add_diagnostic`（`:199-224`，code 直发）+ `unsupported_statement`
（`:3163-3175`，007）+ 新 009。
**Apply to:** `parser/parser.mbt`、`parser/flink_grammar.mbt`、`approved-changes.md`。
**机制:** dialect 不进 code 前缀（D-10）；方言信息经 parse envelope 的
`dialect`/`profile`/`exact_release` metadata 携带（D-04）。FATHOM-PARSE-008 退役后空缺不复用
（D-06）；整句 unsupported 走 007，clause/construct 负门禁走 009。

### 方言策略完全隔离（DIALECT-02，Pitfall 7）
**Source:** `dialect/classification.mbt` `classification_rows_for` `:56-61`（只按
`context.dialect` 选行）+ `lexer/lexer.mbt` `symbol_width_flink` `:412-424`（`||`/`=>`/`..` 单 token）。
**Apply to:** `dialect/flink.mbt`（行表）、`parser/parser.mbt`（`precedence(context, cursor)`）。
**机制:** `doris_classification_rows`/`flink_classification_rows` 独立 module-level 数组；
Flink 行表按 `introduced_profile` release 顺序过滤（`flink_row_visible`）；`precedence` 的 Doris
臂逐字不变；`parse_table_ref`/`parse_column_type` 的 Doris-only 构造 Flink 分支不进入。

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `parser/flink_grammar.mbt` 的 `parse_match_recognize` 子语言 | parser | request-response | 仓库无任何 MATCH_RECOGNIZE 路径；嵌套子语言（`Parser.jj:3062-3346`）+ 独立同步点是全新形态。**planner 用 RESEARCH §5.6/Pattern 3 语法骨架**（PARTITION/ORDER/MEASURES/ONE ROW/ALL ROWS/AFTER MATCH/PATTERN/WITHIN/DEFINE + `^$` 锚/`|`/串联/`{n,m}` 量词/reluctant `?`），表达式内容复用共享 Pratt |
| `parser/flink_grammar.mbt` 的 Window TVF table-ref（`FROM TUMBLE(TABLE t, DESCRIPTOR(ts), INTERVAL '1' SECOND)`） | parser | request-response | Doris `parse_table_ref`（`:909-947`）只认 subquery/限定名；TVF 走通用 table-function 调用（`TableFunctionCall`，`Parser.jj:2443-2460`）+ 非保留字（TUMBLE/HOP/SESSION/DESCRIPTOR）。**planner 用 RESEARCH §5.5/§8 子集**；`TABLE(...)`/`DESCRIPTOR(...)`/`INTERVAL` 字面量在表达式层自然解析 |
| `parser/flink_grammar.mbt` 的 `parse_flink_data_type` | parser | request-response | Doris `parse_column_type`（`:2656-2686`）+ `parse_type_params`（`:2688-2770`）是 Doris 类型集（LARGEINT/BITMAP/HLL）；Flink 类型（`TIMESTAMP_LTZ`/`ROW<>`/`MAP<>`/`ARRAY<>`/`MULTISET`/`RAW`/`BITMAP`/`VARIANT`）需独立映射 `dataTypeParserMethods`（`Parser.tdd:759-765`）——**骨架可参考** Doris 版但内容独立（Pitfall 7） |
| `parity/fixtures/flink-grammar/`、`parity/fixtures/flink-negative/`（fixture 目录本体） | fixture | batch | 仓库尚无 flink-grammar fixture 目录；类比 flink-lexical fixture 目录形态，内容按 RESEARCH §10 四类 fixture + §9 矩阵 |

## Metadata

**Analog search scope:** `parser/`、`syntax/`、`api/`、`dialect/`、`lexer/`、`parity/`、`scripts/`、
`binding/`、`corpus/tools/`、`.planning/phases/09-*`、`.planning/phases/10-*`（全仓库读相关文件）。
**Files scanned:** 16 个源文件（parser.mbt 3757 行 / syntax.mbt / api.mbt / dialect.mbt /
flink.mbt / classification.mbt / doris.mbt / lexer.mbt / schema.mbt / flink_lexical_test.mbt /
baseline_test.mbt / parity_test.mbt / check_keywords.py / extract_flink_lexical.py /
baseline_diff.py / 09+10 approved-changes.md + 239 个快照清单）。
**Pattern extraction date:** 2026-08-09
**行号依据:** 11-RESEARCH.md 的 `[VERIFIED: 路径:行]` 与本 session 直接读取交叉核验一致。
