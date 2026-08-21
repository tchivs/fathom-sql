# fathom-lsp

> [根级 CLAUDE.md](../CLAUDE.md) › fathom-lsp

## 职责

独立 LSP 服务器可执行包：启动共享的 `serve_stdio` 循环，不传 workspace 默认值。

## 关键文件

| 文件 | 行数 | 职责 |
|---|---|---|
| `main.mbt` | 14 | 入口：--version 处理 + 启动 serve_stdio |

## 公开接口

无 pub 导出——可执行入口 `fn main`。

## 依赖

- **上游**：`lsp` `version` `env`
- **下游**：无（终端可执行 `fathom-lsp.exe`）

## 测试

无。LSP 逻辑测试在 `lsp/` 包中。

## 注意事项

- `serve_stdio(None, None)`——无 workspace 默认（缺失选择是配置错误，D-02）
- `--version` 在进入 server 循环前单独处理（否则 stdin 阻塞）
- 构建产物为 `fathom-lsp.exe`
- 与 `fathom-sql lsp` 子命令共享同一个 `serve_stdio` 实现（D-01 seam）
