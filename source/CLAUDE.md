# source

> [根级 CLAUDE.md](../CLAUDE.md) › source

## 职责
提供不可变的源码快照（`SourceText`）以及全局共享的字节坐标原语（`Span`、`LineIndex`）。这是整个解析器的基石包：所有模块的源码位置、切片和行号查询都回到这里。

## 关键文件
| 文件 | 行数 | 职责 |
|---|---|---|
| `source.mbt` | 257 | `SourceText` 快照、`Span` 校验、`LineIndex` 行列映射、输入大小限制 |
| `moon.pkg` | 2 | 包配置，`pkgtype(kind: "library")`，无外部依赖 |

## 公开接口

```moonbit
pub const DEFAULT_MAX_BYTES : Int          // 8 * 1024 * 1024（8 MB）

pub struct Span { start_byte : Int; end_byte : Int }

pub enum SpanError {
  OutOfBounds(start_byte~, end_byte~, source_length~)
  Reversed(start_byte~, end_byte~)
}

pub fn Span::checked(start_byte, end_byte, source_length) -> Result[Span, SpanError]
pub fn Span::length(self : Span) -> Int

pub enum SourceError {
  InputTooLarge(requested_bytes~, max_bytes~)
}

pub struct LineIndex                        // 行起始偏移表
pub fn LineIndex::line_starts(self) -> Array[Int]
pub fn LineIndex::line_count(self) -> Int
pub fn LineIndex::line_col(self, byte_offset) -> (Int, Int)?   // (line, col)，col 为字节偏移

pub struct SourceText { bytes : Bytes; lines : LineIndex }
pub fn SourceText::new(raw : Bytes) -> Result[SourceText, SourceError]
pub fn SourceText::new_with_limit(raw, max_bytes) -> Result[SourceText, SourceError]
pub fn SourceText::byte_length(self) -> Int
pub fn SourceText::bytes(self) -> Bytes
pub fn SourceText::line_index(self) -> LineIndex
pub fn SourceText::span(self, start_byte, end_byte) -> Result[Span, SpanError]
pub fn SourceText::slice(self, span : Span) -> Bytes?
pub fn SourceText::same_bytes(self, other : Bytes) -> Bool
```

## 依赖
- **上游**：无（基石包，仅依赖 MoonBit 核心库）
- **下游**：token、lexer、syntax、printer、formatter、parser、fingerprint、lint、api、binding、lsp、completion、test、parity、bench

## 测试
`source.mbt` 内含 6 个内联 `test` 块，覆盖：输入超限拒绝、Span 校验（反转/越界）、LF/CRLF/混合换行与 BOM 行索引、空源码零宽行、精确边界与相邻空 Span、Unicode/emoji 字节保持、EOF 偏移拒绝。无独立测试文件。

## 注意事项
- **字节偏移而非字符偏移**：`Span`、`LineIndex`、`slice` 全部基于字节偏移（`Bytes` 索引），不进行 UTF-8 解码。Unicode/emoji 字节原样保留，`same_bytes` 可验证 round-trip。
- **输入限制先于快照**：`new_with_limit` 在构建 `LineIndex` 之前检查 `requested_bytes > limit`，超大输入直接返回 `InputTooLarge` 而不分配行索引。
- **DEFAULT_MAX_BYTES = 8 MB**：`SourceText::new` 使用此默认上限；调用方可通过 `new_with_limit` 自定义。
- **Span 允许零宽**：`start_byte == end_byte` 合法，`length()` 返回 0，`slice` 返回空 `Bytes`。
- **换行处理**：`build_line_index` 同时识别 `\n`（LF）和 `\r\n`（CRLF）以及单独 `\r`，每行起始偏移记录在 `starts` 数组中；BOM（`\xEF\xBB\xBF`）不特殊跳过，计入字节流。
- **`line_col` 边界**：`byte_offset == source_length` 返回最后一行的行尾位置；超过则返回 `None`。
