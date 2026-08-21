# fathom-sql

> [根级 CLAUDE.md](../CLAUDE.md) › fathom-sql

## 职责

Native CLI 可执行包：argv → stdin/file 字节 → run_parse/run_format/run_lsp → stdout/stderr/exit。轻量 IO 接线层。

## 关键文件

| 文件 | 行数 | 职责 |
|---|---|---|
| `main.mbt` | 89 | 入口：argv 解析、子命令分发、--help/--version |
| `run.mbt` | ~500 | 纯函数：run_parse/run_format/run_lsp 决策逻辑 |
| `args.mbt` | ~200 | 参数解析与验证 |
| `ffi.mbt` | ~150 | 原生 FFI 辅助（write_fd, exit_process, read stdin） |
| `cli_test.mbt` | ~50 | CLI 测试 |

## 公开接口

无 pub 导出——可执行入口 `fn main`。

## 依赖

- **上游**：`api` `binding` `lsp` `version` `buffer` `debug` `env` `encoding/utf8`
- **下游**：无（终端可执行 `fathom-sql.exe`）

## 测试

`cli_test.mbt`。

## 注意事项

- `main.mbt` 只做字节搬运，所有决策在 `run.mbt` 纯函数中
- `lsp` 子命令**不能预读 stdin**——`serve_stdio` 拥有 fd 0
- `--help` 优先级最高（stdout, exit 0）
- `--version` 仅在独立参数时触发（VER-02/D-02）
- stdout 用 `write_fd(1, ...)` 逐字节写入，不缓冲——`exit_process` 不丢输出
- 无 FFI 在此包之外（formatter/api 保持后端中性）
