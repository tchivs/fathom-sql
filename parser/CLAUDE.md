# parser

> [根级 CLAUDE.md](../CLAUDE.md) › parser

## 职责
手写递归下降 SQL 解析器，输出无损 CST。支持 Doris 与 Flink 两种方言的语法路径，提供 Pratt 表达式解析、语句级 panic-mode 错误恢复与子句级尽力恢复，并通过 ParserLimits 防止资源耗尽。

## 关键文件
| 文件 | 行数 | 职责 |
|---|---|---|
| parser.mbt | 7325 | 核心解析器：ParseMode、ParserLimits、ParsedDocument、Cursor/RecoveryState 内部结构、parse 入口、Doris 语法产生式（SELECT/INSERT/DDL/表达式）、错误恢复 |
| flink_grammar.mbt | 4126 | Flink 方言语法扩展：parse_flink_query、parse_flink_select_core、parse_flink_insert 等 Flink-safe 产生式，复用共享骨架但拒绝 Doris-only 构造（FATHOM-PARSE-009） |

## 公开接口

```moonbit
/// 解析模式
pub(all) enum ParseMode {
  Strict   // 严格模式：遇到错误即停止，不做恢复
  Editor   // 编辑器模式：启用 panic-mode 恢复，处理半成品 SQL
}

/// 资源限制错误
pub(all) enum ParserLimitError {
  MaxBytes(Int)
  MaxTokens(Int)
  MaxRecursionDepth(Int)
  MaxRecoverySteps(Int)
  MaxDiagnostics(Int)
}

/// 解析器资源限制
pub struct ParserLimits {
  max_bytes : Int              // 默认 8 MiB
  max_tokens : Int             // 默认 1,000,000
  max_recursion_depth : Int    // 默认 128
  max_recovery_steps : Int    // 默认 10,000
  max_diagnostics : Int        // 默认 100
}

/// 解析诊断
pub struct ParserDiagnostic {
  severity : String
  code : String            // 如 "FATHOM-PARSE-002"
  message : String
  expected_class : String  // 如 "keyword"
  span : @source.Span
  statement_id : UInt
}

/// 解析结果文档
pub struct ParsedDocument {
  source : @source.SourceText
  mode : ParseMode
  root : @syntax.SyntaxNode
  diagnostics : Array[ParserDiagnostic]
  valid : Bool             // 无诊断时为 true
  recovered : Bool         // Editor 模式下有诊断时为 true
}

/// 默认限制
pub fn ParserLimits::default() -> ParserLimits
/// 自定义限制
pub fn ParserLimits::new(...) -> ParserLimits
/// 验证限制非负
pub fn ParserLimits::validate(self) -> Result[Unit, ParserLimitError]
/// 将负值归零
pub fn ParserLimits::normalized(self) -> ParserLimits

/// 完整解析入口（含限制 + 方言上下文）
pub fn parse_with_limits_context(
  source, context, mode, limits
) -> ParsedDocument

/// 带限制的解析（parse_with_limits_context 的薄封装）
pub fn parse_with_limits(source, context, mode, limits) -> ParsedDocument

/// 默认限制的便捷入口
pub fn parse(source, context, mode) -> ParsedDocument
```

## 依赖
- **上游**: `source`（SourceText/Span）、`token`（TokenStream）、`lexer`（lex_with_limit）、`syntax`（SyntaxNode/SyntaxKind/SyntaxElement）、`dialect`（DialectContext/Dialect）
- **下游**: `api`、`printer`、`bench`、`test`、`parity`

## 测试
无独立测试文件，由 `test/` 包覆盖：
- `parser_test.mbt` — 基础解析行为
- `recovery_test.mbt` — 错误恢复策略
- `dml_test.mbt` — DML 语句
- `ddl_test.mbt` — DDL 语句
- `keyword_test.mbt` — 关键字分类
- `corpus_test.mbt` — 语料覆盖与 round-trip

parser.mbt 内部含少量内联 `test` 块（如 `parser_flink_context_parses_select`）。

## 注意事项
- **ParseMode**: `Strict` 模式不做恢复，诊断即终止；`Editor` 模式启用 panic-mode 恢复，`recovered` 字段标记是否发生过恢复。
- **错误恢复策略**: 语句级 panic-mode 跳过到下一个分号边界；子句级尽力恢复在语句内部跳到已知子句关键字。恢复始终消费输入或创建零宽 ERROR 节点，绝不静默丢弃 token。
- **ParserLimits**: 所有五个维度（字节/token/递归深度/恢复步数/诊断数）均有默认上限，超限时截断输入并发出 `FATHOM-PARSE-003` 资源诊断，防止恶意或超大输入耗尽资源。
- **Pratt 表达式解析**: 表达式通过单一 Pratt 路径处理，`ExpressionContext` 区分 Ordinary / ProjectionItem / CountArgument 上下文以控制通配符等边界行为。
- **Flink 隔离**: flink_grammar.mbt 复用 parser.mbt 的共享骨架（parse_select_core / parse_table_ref / parse_cte_prefix），但 Doris-only 构造在 Flink 路径下以 `FATHOM-PARSE-009` 拒绝，绝不跨方言混用产生式。
- **Cursor 深度增量维护 (WR-03)**: 括号嵌套深度在 `advance` 中增量维护，避免每次表达式上下文的 O(n) 重扫。
- **禁止依赖 analyzer (D-21)**: parser 不得 import analyzer 包；语义分析是独立阶段。
