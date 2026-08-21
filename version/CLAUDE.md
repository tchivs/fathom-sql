# version

> [根级 CLAUDE.md](../CLAUDE.md) › version

## 职责

产品版本标识单一来源：提供 `--version` 输出。moon.mod 模块版本（0.1.0）与产品 semver 解耦。

## 关键文件

| 文件 | 行数 | 职责 |
|---|---|---|
| `version.mbt` | 52 | product_version()、version_line()、print_and_exit() |

## 公开接口

```moonbit
pub fn product_version() -> String  // "1.0.0"
pub fn version_line(name : String) -> String  // "<name> 1.0.0\n"
pub fn print_and_exit(name : String) -> Unit  // native-only, #cfg
```

## 依赖

- **上游**：`encoding/utf8`
- **下游**：`fathom-sql` `fathom-lsp`

## 测试

无独立测试。`--version` 行为由 CLI 测试覆盖。

## 注意事项

- moon.mod 的模块版本保持 `0.1.0`（Phase 13 决策），产品 semver 仅在此处维护
- FFI helpers 用 `#cfg` 限定 native only——js/wasm 构建不引入此包
- 升级版本需编辑 `product_version()` 并遵循 `docs/VERSIONING.md`（tag + CHANGELOG）
