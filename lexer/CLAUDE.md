# lexer

> [根级 CLAUDE.md](../CLAUDE.md) › lexer

## 职责

同步、源码回退（source-backed）的词法分析器。直接操作 `SourceText` 的 UTF-8 字节流，将 SQL 源码切分为 trivia + 词法 token 流（`TokenStream`），保留注释、空白、换行与 BOM，并在遇到非法字节时产生带诊断码的 `Error` token。每个分支要么消费字节要么终止，保证循环不会卡死。

## 关键文件

| 文件 | 行数 | 职责 |
|---|---|---|
| `lexer.mbt` | 1550 | 词法分析器全部实现：UTF-8 宽度校验、标识符/数字/字符串/注释/符号扫描、方言分支（Doris/Flink）、公共入口 `lex`/`lex_with_limit`、内联测试 |

## 公开接口

```moonbit
pub fn lex(
  source : @source.SourceText,
  context : @dialect.DialectContext,
) -> @token.TokenStream

pub fn lex_with_limit(
  source : @source.SourceText,
  context : @dialect.DialectContext,
  max_tokens : Int,            // <0 = 无限制；≥0 = 截断阈值
) -> @token.TokenStream
```

`lex` 即 `lex_with_limit(source, context, 1_000_000)`。返回 `@token.TokenStream`，其中 `truncated_at` 记录截断位置（未截断为 `None`）。模块无公开类型——所有数据结构来自 `source`/`token`/`dialect`。

## 依赖

- **上游（import）**：`fathom/sql/source`（`SourceText`、`Span`）、`fathom/sql/token`（`Token`、`TokenKind`、`TokenStream`）、`fathom/sql/dialect`（`DialectContext`、`Dialect::Doris`/`Dialect::Flink`）
- **下游（被 import）**：`parser`、`completion`

## 测试

无独立测试文件。由 `lexer.mbt` 内联 `test` 块（`lexer_preserves_trivia_literals_and_invalid_bytes`、`lexer_splits_invalid_utf8_inside_closed_literals_identifiers_and_comments`、`lexer_terminates_unterminated_material` 等）以及 `test/`、`parity/` 包覆盖。

## 注意事项

- **UTF-8 严格校验**：`utf8_width` 按首字节判定 1–4 字节序列并校验 continuation 字节与代理对边界；非法序列被聚合成连续的 `Error` token（`LEX_INVALID_UTF8`），不与合法 token 混合。
- **无损不变量**：所有 token 的 `span` 连续覆盖源码每个字节，`token.raw(source) == source.slice(token.span)`；trivia（`Whitespace`/`Newline`/`Comment`/`Bom`）与词法 token 一视同仁，保证 round-trip。
- **方言分支**：Doris 为基线；Flink 在注释（`#`→Error、`//`→Comment）、字符串（无反斜杠转义、双引号转义）、反tick 标识符、前缀字面量（`X'..'`/`N'..'`/`E'..'`/`U&'..'`/`_charset'..'`）、符号宽度（`||`/`=>`/`..`）等处分叉。分叉由 `context.dialect is @dialect.Dialect::Flink` 门控。
- **终止保证**：`scan_comment`/`scan_quoted`/`scan_number` 等扫描函数在到达 `bytes.length()` 时终止并返回当前 `index`，未闭合材料产生单个 `Error` token 覆盖剩余字节。
- **截断语义**：`max_tokens ≥ 0` 时达到阈值即停止，`truncated_at` 记录剩余起始偏移；调用方（parser）需据此处理不完整输入。
- **不保留文本副本**：token 仅存 `Span` + `kind`，实际字节通过 `source.slice(span)` 按需切片，避免逐 token 复制。
