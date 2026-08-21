# fingerprint

> [根级 CLAUDE.md](../CLAUDE.md) › fingerprint

## 职责
将无损 CST 规范化为确定性的字节序列，再通过 FNV-1a 64-bit 哈希计算 SQL 指纹。指纹用于缓存键、diff 与 CI 标识，非密码学用途。

## 关键文件
| 文件 | 行数 | 职责 |
|---|---|---|
| normalize.mbt | 142 | CST → 规范字节：折叠 trivia、关键字小写、标识符/字面量保留 |
| hash.mbt | 37 | FNV-1a 64-bit 哈希：规范字节 → UInt64 |
| hash_test.mbt | 177 | FNV-1a 标准向量、normalize 不变量、UInt64 探针断言 |
| moon.pkg | 9 | 包配置：library，依赖声明 |

## 公开接口
```moonbit
pub fn normalize(
  root : @syntax.SyntaxNode,
  source : @source.SourceText,
  context : @dialect.DialectContext,
) -> Bytes

pub fn fnv1a64(bytes : Bytes) -> UInt64
```

常量：`FNV1A_OFFSET_BASIS`、`FNV1A_PRIME`（私有）。

## 依赖
- **上游**：`fathom/sql/syntax`（CST 节点/叶子/种类）、`fathom/sql/dialect`（关键字分类）、`fathom/sql/source`（源文本与切片）、`moonbitlang/core/buffer`（字节缓冲）、`moonbitlang/core/debug`
- **下游**：`api`、`test`

## 测试
- `hash_test.mbt`：
  - `fnv1a64_standard_vectors` — 空串/`a`/`foobar` 参考值
  - `fnv1a64_is_sensitive_to_content_and_order` — 内容与顺序敏感性
  - `uint64_probe_assertions` — UInt64 字面量后缀 `UL`、wrap 乘法、`^` 异或、`Byte::to_uint64` 零扩展
  - `normalize_folds_whitespace_keyword_case_and_comments` — 空白折叠、关键字大小写归一、注释丢弃
  - `normalize_preserves_quote_style_identifier_case_literal_content` — 引号风格、标识符大小写、字面量内容保留
  - `normalize_is_total_on_empty_and_error_material` — 空文档与错误/skipped 材料的全函数性

## 注意事项
- **FING-01 保留契约**：normalize 保留标识符拼写/大小写/引号风格、字面量内容；仅折叠 syntactic trivia。
- **关键字规范化**：通过 `@dialect.classification_of`（D-28 单一关键字表，Pitfall 14）判定关键字后 ASCII 小写；非关键字原样输出。`ascii_case_fold` 是字节折叠，不是第二张分类表。
- **Trivia 折叠规则**：注释（`/* */`、`--`、`#`）与 BOM 完全丢弃；空白/换行折叠为至多一个 0x20 分隔符，仅在两个已发射 token 之间且缓冲非空时发射（无前导空格）。
- **全函数性**：`normalize` 对任意输入（含空树/错误节点）都返回确定性结果；`SourceError`/`SourceSkipped` 原样输出。语义仅在有效语句上有意义。
- **哈希跨后端稳定性**：使用 `UInt64`（Native/JS/线性 Wasm 均为 64 位），非 `Int`（Wasm/C 32 位、JS number）。FNV-1a 为非密码学哈希，仅作标识符。
- **UInt64 探针**（Open Question 1）：字面量后缀 `UL`、`^` 为异或中缀、`Byte::to_uint64()` 零扩展、`*` 为 64 位 wrap 乘法。
