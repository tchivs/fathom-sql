# version

> [根级 CLAUDE.md](../CLAUDE.md) › version

## 职责

产品版本标识单一来源：提供 `--version` 输出。moon.mod 模块版本（1.0.5）与产品 semver 对齐。

## 关键文件

| 文件 | 行数 | 职责 |
|---|---|---|
| `version.mbt` | 52 | product_version()、version_line()、print_and_exit() |

## 公开接口

```moonbit
pub fn product_version() -> String  // "1.0.5"
pub fn version_line(name : String) -> String  // "<name> 1.0.5\n"
pub fn print_and_exit(name : String) -> Unit  // native-only, #cfg
```

## 依赖

- **上游**：`encoding/utf8`
- **下游**：`fathom-sql` `fathom-lsp`

## 测试

有独立测试：`product_version_is_1_0_4` 和 `version_line_format` 覆盖版本输出。

## 注意事项

- moon.mod 的模块版本与产品 semver 对齐为 `1.0.5`，产品 semver 仅在此处维护
- FFI helpers 用 `#cfg` 限定 native only——js/wasm 构建不引入此包
- 升级版本需编辑 `product_version()` 并遵循 `docs/VERSIONING.md`（tag + CHANGELOG）
