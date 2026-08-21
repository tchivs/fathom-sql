# token

> [根级 CLAUDE.md](../CLAUDE.md) › token

## 职责

无损 Token 数据结构：定义 `TokenKind` 枚举与携带 `DialectContext` 的 `Token` 记录，提供 Trivia 分类与字节切片查询。本模块是词法分析器（lexer）与解析器（parser）之间的数据契约层，不负责关键字分类——分类查询由 `dialect` 包提供。

## 关键文件

| 文件 | 行数 | 职责 |
|---|---|---|
| `token.mbt` | 71 | `TokenKind` 枚举、`Token` / `TokenStream` 结构体及查询方法 |
| `moon.pkg` | 6 | 包配置，依赖 `source` + `dialect` |

## 公开接口

```moonbit
pub(all) enum TokenKind {
  Whitespace | Newline | Comment | Bom   // Trivia（保留无损 round-trip）
  Identifier | Number | Quoted | StringLiteral | Symbol  // 实质 Token
  Unknown | Error                         // 异常 Token
}

pub(all) struct Token {
  kind : TokenKind
  span : @source.Span
  context : @dialect.DialectContext       // 词法分析时的不可变方言上下文
  diagnostic_code : String?              // 错误码（Error 类时填入）
}

pub fn Token::raw(self, source : @source.SourceText) -> Bytes?
pub fn Token::is_trivia(self) -> Bool     // Whitespace | Newline | Comment => true
pub fn Token::is_error(self) -> Bool

pub(all) struct TokenStream {
  source : @source.SourceText
  context : @dialect.DialectContext
  tokens : Array[Token]
  truncated_at : Int?                     // 截断位置（超长输入保护）
}

pub fn TokenStream::length(self) -> Int
pub fn TokenStream::at(self, index : Int) -> Token?
pub fn TokenStream::raw(self, index : Int) -> Bytes?
```

## 依赖

- **上游**：`fathom/sql/source`（`Span`、`SourceText`）、`fathom/sql/dialect`（`DialectContext`）
- **下游**：`lexer`、`parser`、`printer`、`completion`

## 测试

无独立测试。Token 结构的契约由 `lexer`、`parser` 及 `test` 包的集成测试覆盖（round-trip 不变量 `print_lossless(parse(input)) == input`）。

## 注意事项

1. **Token 不做关键字判断** — 所有关键字/保留字分类通过 `@dialect.classification_of` 查询，本模块 re-export 任何 dialect 符号（Pitfall 1）。Dialect 类型名（如 Doris 关键字枚举）的家在 `dialect/doris.mbt`，token 仅持有 `DialectContext` 引用。
2. **Trivia 是无损 CST 的基石** — `Whitespace`、`Newline`、`Comment` 三类被 `is_trivia()` 识别为 Trivia；解析器与 printer 必须保留这些 span 才能保证 round-trip。
3. **`context` 字段不可变** — Token 携带其被词法分析时的 `DialectContext` 快照，确保下游解析阶段不会因方言切换产生不一致（研究迁移行 8-9）。
4. **`Bom` 单列** — BOM（字节顺序标记）作为独立 Trivia 类型，不归入 `Whitespace`，便于 printer 精确回放。
5. **`truncated_at`** — `TokenStream` 可标记截断点，用于超长输入的保护性处理；下游消费者应检查此字段以避免在截断后继续解析。
