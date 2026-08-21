# test

> [根级 CLAUDE.md](../CLAUDE.md) › test

## 职责

黑盒集成测试包：覆盖所有核心包的公开 API，通过 `@mtest` 框架运行。

## 关键文件

| 文件 | 职责 |
|---|---|
| `parser_test.mbt` | 解析器核心测试 |
| `recovery_test.mbt` | 错误恢复测试 |
| `dml_test.mbt` | DML 语句测试（SELECT/INSERT/UPDATE/DELETE） |
| `ddl_test.mbt` | DDL 语句测试（CREATE TABLE/VIEW/INDEX） |
| `keyword_test.mbt` | 关键字分类测试 |
| `formatter_test.mbt` | 格式化幂等性与输出测试 |
| `lint_test.mbt` | Lint 规则测试 |
| `fingerprint_test.mbt` | 指纹确定性测试 |
| `lineage_test.mbt` | 列级血缘测试 |
| `analyzer_test.mbt` | 名称解析测试 |
| `analyzer_anal01_test.mbt` | ANLY-01 无 catalog 降级测试 |
| `analyzer_public_surface_test.mbt` | 分析器公开 API 契约测试 |
| `binding_wire_test.mbt` | FFI 导出 wire 格式测试 |
| `corpus_test.mbt` | 语料库 round-trip 测试 |
| `source_test.mbt` | 源码/SPAN 测试 |

## 公开接口

无——测试包。

## 依赖

- **上游**：`analyzer` `api` `binding` `parser` `printer` `source` `syntax` `formatter` `dialect` `lineage` `encoding/utf8` `test(@mtest)`

## 注意事项

- `import ... for "test"` — 测试依赖与运行时依赖分离
- 语料测试消费 `corpus/` 目录下的 Doris/Flink fixture
- binding wire 测试验证 JSON envelope schema 正确性
