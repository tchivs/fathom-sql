# parity

> [根级 CLAUDE.md](../CLAUDE.md) › parity

## 职责

跨后端可执行入口：`run_native.mbt`/`run_js.mbt`/`run_wasm.mbt` 在三个后端分别执行 binding 导出的烟雾测试。测试逻辑在 `parity-tests/` 库包中。

## 关键文件

| 文件 | 职责 |
|---|---|
| `run_native.mbt` | Native 后端执行入口（`targets: ["native"]`） |
| `run_js.mbt` | JS 后端执行入口（`targets: ["js"]`） |
| `run_wasm.mbt` | Wasm 后端执行入口（`targets: ["wasm"]`） |

## 公开接口

无——可执行包，仅有 `fn main`。

## 依赖

- **运行时**：`binding` `encoding/utf8`

## 注意事项

- 从原 `parity/` 包拆分：测试逻辑移至 `parity-tests/` 库包，本包仅保留后端特定入口
- `moon.pkg` 用 `targets:` 将 `run_*.mbt` 分别限定到单一后端
- 每个入口调用 `@binding.fathom_*_v1` 函数验证导出 ABI
