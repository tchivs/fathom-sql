# formatter

> [根级 CLAUDE.md](../CLAUDE.md) › formatter

## 职责

格式化引擎：将 CST 按用户配置重新排版，保持注释和结构不变。拒绝优先——含 error/missing/skipped 的树返回 `accepted=false`。

## 关键文件

| 文件 | 行数 | 职责 |
|---|---|---|
| `format.mbt` | 168 | 拒绝优先格式化入口 |
| `layout.mbt` | ~600 | 布局引擎（缩进、换行、对齐） |
| `options.mbt` | ~200 | FormatOptions、KeywordCase、CommaStyle、NewlineStyle |
| `error.mbt` | ~100 | FormatError、FormatDiagnostic |
| `refuse.mbt` | ~100 | 不安全节点检测与拒绝逻辑 |
| `case.mbt` | ~50 | 关键字大小写转换 |

## 公开接口

```moonbit
pub fn format(root, source, options : FormatOptions, context : DialectContext) -> FormatResult
pub struct FormatOptions { keyword_case, indent, line_width, comma_style, newline_style, trailing_newline }
pub enum FormatError { ... }
pub const MAX_INDENT : Int = 64
```

## 依赖

- **上游**：`source` `syntax` `dialect` `buffer` `debug` `encoding/utf8`
- **下游**：`api` `lint` `test` `parity`

## 测试

无独立测试文件，由 `test/formatter_test.mbt` 覆盖。

## 注意事项

- **拒绝优先**：含 error/missing/skipped 的树返回 `accepted=false` + 空 output + FATHOM-FORMAT-001 诊断，永不输出部分字节
- **幂等性**：`format(format(x)) == format(x)` 是测试契约
- 关键字大小写通过 `@dialect.classification_of` 判断（单一关键字源，Pitfall 14）
