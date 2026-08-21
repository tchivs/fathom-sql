# lsp

> [根级 CLAUDE.md](../CLAUDE.md) › lsp

## 职责

LSP 3.17 stdio 适配器：将 Doris/Flink SQL 解析、格式化、补全能力通过 JSON-RPC over stdio 暴露给编辑器。本模块只负责协议传输与映射，不直接做语法分析——所有解析/格式化委托 `api` facade，UTF-16 位置转换委托 `binding`。`serve_stdio` 是全模块唯一的 stdio 入口（D-01 seam），`fathom-sql` CLI 的 `lsp` 子命令与独立 `fathom-lsp` 可执行文件都调用它。

方言选择遵循三级优先级（D-01）：文档级显式配置（didOpen/didChange 扩展字段）> workspace/session 默认（serve_stdio 参数 / initializationOptions）> 用户配置的 languageId 映射。缺失、未知或冲突的选择是结构化配置错误（FATHOM-SCHEMA-007 / -32602），绝不隐式回退到 languageId 猜测。

## 关键文件

- `serve.mbt` — `serve_stdio` 主循环，唯一的 stdio 入口；读取帧 → 解析消息 → 分发到 handlers → 写回帧。
- `handlers.mbt` — LSP 生命周期与编辑器方法处理器（initialize/shutdown/didOpen/didChange/didClose/formatting/completion）。定义 `DialectSelection`、`SelectionError`、`ServerState`，实现三级选择解析与诊断发布。
- `framing.mbt` — Content-Length 帧编解码，含 `read_frame`/`write_frame`、`FrameSource`（跨帧字节 pushback）、头/体大小上限校验、native fd 读写。
- `protocol.mbt` — JSON-RPC 2.0 最小适配：`RpcId`、`RpcMessage`、`parse_message`、`response`/`error_response`/`notification`，及字段提取辅助函数。JSON 解析委托 `@json`。
- `documents.mbt` — `DocumentStore`：按 URI 管理版本化全文档快照，每个文档携带已解析的 dialect/profile 上下文（`selection_source` 记录优先级来源），支持 `update_selection` 做配置变更后重解析（D-03）。
- `coordinates.mbt` — LSP 位置门面：`full_document_range`/`diagnostic_range` 统一走 `range_or_none` → `@binding.span_to_range`，确保只有一条 UTF-16 转换路径（D-07）。

## 公开接口

- `serve_stdio(initial_dialect : String?, initial_profile : String?) -> Unit` — 唯一 stdio 服务器入口。
- `DialectSelection` — 一组显式 dialect+profile 选择（dialect 闭枚举 id，profile 发布版本 id）。
- `SelectionError` — 选择解析失败的结构化类型（MissingSelection / MissingDocumentField / UnknownDialect / UnknownProfile / ConflictingSelection）。
- `ServerState` / `ServerState::new()` — 会话状态：文档存储、workspace 默认、language 映射、初始化/关闭标志。
- `DocumentStore` 及其 `open`/`change`/`close`/`get`/`update_selection`/`documents` — 文档生命周期管理。
- 帧层：`decode_frame`/`frame`/`read_frame`/`FrameSource`、`MAX_FRAME_BYTES`/`MAX_HEADER_BYTES`、`FrameError`。
- 协议层：`parse_message`/`response`/`error_response`/`notification`、`RpcId`/`RpcMessage`、字段提取函数。
- 坐标层：`source`/`full_document_range`/`diagnostic_range`。

## 依赖

- **内部包**：`api`（解析/格式化/补全 facade）、`binding`（UTF-16 范围转换）、`completion`（补全数据）、`source`（SourceText 构造）。
- **moonbitlang/core**：`buffer`、`debug`、`encoding/utf8`、`json`。
- **下游消费者**：`fathom-sql`（CLI lsp 子命令）、`fathom-lsp`（独立可执行文件）。

## 测试

8 个测试文件：

- `framing_test.mbt` / `framing_wbtest.mbt` — 帧编解码、大小上限、截断、跨帧 pushback。
- `protocol_test.mbt` — JSON-RPC 消息解析与响应序列化。
- `lifecycle_test.mbt` — initialize/shutdown/exit 生命周期与诊断发布。
- `selection_test.mbt` / `selection_wbtest.mbt` — DialectSelection 三级优先级解析与错误路径。
- `completion_test.mbt` — 补全请求到 LSP 补全列表的映射。
- `diagnostics_formatting_test.mbt` — 诊断与格式化结果的 JSON 构造。

## 注意事项

- **D-01 seam**：`serve_stdio` 是唯一 stdio 入口，不要在模块内新建第二个 server main。
- **D-02 no-guess**：选择不可解析时发布单条 `FATHOM-SCHEMA-007` 诊断且不解析文档，绝不隐式 languageId 回退。
- **D-03 过期守卫**：异步诊断发布前必须在 `publish_diagnostics_current` 中校验文档 version 与 dialect/profile 仍匹配，过期结果丢弃。
- **D-07 单转换路径**：所有 UTF-16 范围转换必须经 `coordinates.range_or_none` → `@binding.span_to_range`，禁止手写第二条转换器。
- flink 文档走 `@api.parse_flink`（Phase 11 D-06 真实 Flink 语法），不走 Doris 路径（DIALECT-03）。
- 帧头/体大小上限在分配前校验（`MAX_HEADER_BYTES` 16 KB / `MAX_FRAME_BYTES` 8 MB）；`FrameSource.pending` 保证跨帧过读字节不丢失。
