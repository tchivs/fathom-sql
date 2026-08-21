# completion

> [根级 CLAUDE.md](../CLAUDE.md) › completion

## 职责

后端中性、纯语法补全：基于 parser 的 token 和 profile 表提供补全建议，不查询 catalog、filesystem 或 host 运行时。

## 关键文件

| 文件 | 行数 | 职责 |
|---|---|---|
| `completion.mbt` | 494 | 补全引擎核心、CompletionItem/CompletionList |

## 公开接口

```moonbit
pub fn complete(raw : Bytes, dialect : String, profile : String, cursor_byte : Int) -> Result[CompletionList, CompletionError]
pub struct CompletionItem { label, detail, start_byte, end_byte, new_text }
pub struct CompletionList { is_incomplete, items }
pub enum CompletionError { UnknownDialect, UnknownProfile, InvalidCursor, InvalidSource, InputTooLarge }
```

## 依赖

- **上游**：`api` `lexer` `source` `token` `dialect` `encoding/utf8`
- **下游**：`binding` `lsp` `test` `parity`

## 测试

`completion_test.mbt`（黑盒）。

## 注意事项

- 纯语法补全，不依赖 catalog 或 analyzer——无元数据降级问题
- cursor 边界检查在核心层做一次（`InvalidCursor`），导出层不重复检查（single-source, T-13-04-03）
- 方言/profile 验证优先于补全逻辑（Pitfall 6）
