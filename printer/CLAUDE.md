# printer

> [根级 CLAUDE.md](../CLAUDE.md) › printer

## 职责

无损字节回放：从 CST 节点按原始 span 逐叶子拼接源码字节，保证 `print_lossless(parse(input)) == input`。

## 关键文件

| 文件 | 行数 | 职责 |
|---|---|---|
| `printer.mbt` | 184 | 无损回放核心 + 传输载荷序列化 |

## 公开接口

```moonbit
pub fn print_lossless(root : @syntax.SyntaxNode, source : @source.SourceText) -> Bytes
pub fn print_transport(result : @api.ParseResult) -> Bytes
pub fn print_result(result : @api.ParseResult) -> Bytes
pub fn print_bytes(result : @api.ParseResult) -> Bytes
```

## 依赖

- **上游**：`source` `syntax` `token` `lexer` `api` `dialect`
- **下游**：`test` `parity`

## 测试

无独立测试文件，由 `test/` 包的 round-trip 测试覆盖（`print_lossless(parse(input)) == input`）。

## 注意事项

- Missing 节点无叶子，因此不输出字节——回放是安全的
- 节点永不拥有源码字节，只通过 `source.slice(span)` 读取
- `print_lossless` 是无损 round-trip 不变量的核心验证点
