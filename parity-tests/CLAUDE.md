# parity-tests

> [根级 CLAUDE.md](../CLAUDE.md) › parity-tests

## 职责

跨后端一致性验证：在 native/js/wasm 三个后端运行同一测试套件，比较序列化诊断和 round-trip 输出是否字节一致。

## 关键文件

| 文件 | 职责 |
|---|---|
| `parity_test.mbt` | 跨后端一致性核心测试 |
| `baseline_test.mbt` | 基线快照比对（`__snapshot__/` 605 个 fixture） |
| `schema_test.mbt` | wire schema 验证 |
| `export_smoke_test.mbt` | 导出函数烟雾测试 |
| `flink_grammar_test.mbt` | Flink 语法一致性 |
| `flink_lexical_test.mbt` | Flink 词法一致性 |
| `flink_format_test.mbt` | Flink 格式化一致性 |
| `fingerprint_parity_test.mbt` | 指纹跨后端一致性 |
| `lineage_parity_test.mbt` | 血缘跨后端一致性 |
| `coordinates_test.mbt` | 坐标转换一致性 |

## 公开接口

无——测试库包。

## 依赖

- **测试**：`binding` `api` `completion` `source` `dialect` `parser` `printer` `syntax` `formatter` `encoding/utf8` `test`

## 注意事项

- 从原 `parity/` 包拆分：`parity/` 保留 `run_*.mbt` 可执行入口，测试逻辑独立为库包
- CI 中跨后端一致性是 release gate 的一部分
- 比较策略：序列化诊断 + round-trip 输出，字节级精确比对
- `moon test --update --package parity-tests` 重新生成 `__snapshot__/` 快照
