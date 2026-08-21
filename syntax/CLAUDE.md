# syntax

> [根级 CLAUDE.md](../CLAUDE.md) › syntax

## 职责
定义无损 CST 的不可变节点结构：`SyntaxKind` 语句族枚举、`SyntaxNode` / `SyntaxLeaf` / `SyntaxElement`，以及在构造时强制校验 span 连续性与包含关系的节点不变量。节点永不拥有源码字节，仅持有 `@source.Span` 和 `text_len`。

## 关键文件
| 文件 | 行数 | 职责 |
|---|---|---|
| syntax.mbt | 381 | `SyntaxKind` / `LeafKind` 枚举，`SyntaxNode` / `SyntaxLeaf` / `SyntaxElement` 结构与构造器，span 不变量校验，内联测试 |
| moon.pkg | 6 | 包声明 `pkgtype(kind: "library")`，依赖 `moonbitlang/core/debug` 与 `fathom/sql/source` |

## 公开接口

### 枚举
```moonbit
pub(all) enum SyntaxKind   // Document · Statement · Select · Insert · … · Missing · Flink 族（ShowStatement … UseStatement）
pub(all) enum LeafKind     // SourceToken · SourceTrivia · SourceError · SourceSkipped
pub(all) enum SyntaxElement // ChildNode(SyntaxNode) | Leaf(SyntaxLeaf)
```

### 结构
```moonbit
pub struct SyntaxNode { kind : SyntaxKind; span : @source.Span; text_len : Int; children : Array[SyntaxElement] }
pub struct SyntaxLeaf { kind : LeafKind; span : @source.Span; text_len : Int }
```

### 构造器（均返回 `SyntaxNode?`，校验失败返回 `None`）
```moonbit
SyntaxNode::new(kind, span, children) -> SyntaxNode?
SyntaxNode::with_text_len(kind, span, text_len, children) -> SyntaxNode?
SyntaxNode::missing(at, source_length) -> SyntaxNode?      // 零宽 Missing 节点
SyntaxNode::error(span, children) -> SyntaxNode?
SyntaxNode::skipped(span, children) -> SyntaxNode?
SyntaxLeaf::new(kind, span) -> SyntaxLeaf
```

### 查询
```moonbit
SyntaxNode::{kind, span, text_len, children} -> …
SyntaxNode::is_valid(source_length) -> Bool   // 递归校验 span 连续性与包含关系
SyntaxNode::is_missing / is_error / is_skipped -> Bool
SyntaxNode::leaf_count() -> Int
SyntaxLeaf::is_zero_width() -> Bool
SyntaxElement::span() / text_len() -> …
```

## 依赖
- **上游**：`fathom/sql/source`（`Span` 及其 `checked` / `length`），`moonbitlang/core/debug`（`Debug` derive）
- **下游**：parser（构造 CST）、printer、formatter、analyzer、lint、fingerprint、lineage、api

## 测试
内联 `test` 块位于 syntax.mbt 末尾（286–380 行），覆盖：相邻 span 与零宽 Missing 保留、源码顺序与 touching leaf span、负 `text_len` / 越界 span 被拒、error/skipped 拒绝畸形子 span。无独立 `*_test.mbt` / `*_wbtest.mbt` 文件。

## 注意事项
- **节点永不拥有源码字节**：仅记录 `Span` + `text_len`，文本由 `Source` 快照统一持有；打印需 round-trip 还原源码而非重写。
- **`SyntaxNode::new` / `with_text_len` 是失败即 `None` 的受检构造器**：`node_invariants_hold` 要求子 span 单调递增、不重叠、且全部落在父 span `[start_byte, end_byte]` 内；`text_len` 必须等于 `span.length()`。调用方须用 `checked_node` 或 match 处理 `None`，静默忽略会丢失错误恢复信息。
- **Flink kind 追加在枚举末尾、永不重排**（Pitfall 1 / Phase 11 D-02 one-way 契约）：`ShowStatement` 起的 Flink 语句族族必须位于 `SyntaxKind` 末尾，以保证冻结的 Doris wire output `kind_id` 序数不被打乱。语句子类型（SHOW TABLES vs SHOW CATALOGS）通过节点 metadata/span 区分，而非新增 kind。
- **`children` 在构造时被 `.copy()`**：构造后对外通过 `children()` 亦返回 copy，节点对外表现不可变；但 copy 成本随子节点数线性增长，大 CST 场景注意分配。
