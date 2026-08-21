# bench

> [根级 CLAUDE.md](../CLAUDE.md) › bench

## 职责

性能基准测试：测量解析器吞吐量和延迟，使用 `moonbitlang/core/bench` 框架。

## 关键文件

| 文件 | 行数 | 职责 |
|---|---|---|
| `bench.mbt` | ~200 | 基准测试主体（parse/format 吞吐量） |

## 公开接口

无——基准包。

## 依赖

- **上游**：`api` `parser` `source` `dialect` `bench` `buffer`

## 注意事项

- 基准测试通过 `moonbitlang/core/bench` 运行
- 测量 parse 路径的吞吐量（bytes/ms）和延迟
- 结果用于回归检测，非 release gate
