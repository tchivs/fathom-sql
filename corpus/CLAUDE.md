# corpus

> [根级 CLAUDE.md](../CLAUDE.md) › corpus

## 职责

Doris/Flink SQL 语料库与覆盖报告：按版本组织的 `.sql` fixture 文件，供 `test/corpus_test.mbt` 做 round-trip 验证。

## 关键文件

| 文件/目录 | 职责 |
|---|---|
| `doris-2.1/` | Doris 2.1 版本语料 |
| `doris-3.x/` | Doris 3.x 版本语料 |
| `doris-4.x/` | Doris 4.x 版本语料（DDL/DML/查询等 .sql 文件） |
| `coverage.tsv` | 语法覆盖率报告 |
| `flink-coverage.tsv` | Flink 语法覆盖率 |
| `keywords.tsv` | 关键字分类表 |
| `differential.tsv` | 差异比对结果 |
| `manifest.tsv` | 语料清单（URL、版本、预期状态） |
| `requirements.txt` | 差异工具依赖（sqlglot 30.14.0，仅本地比对基准） |
| `CORPUS-REPORT.md` | 语料覆盖报告 |
| `tools/` | 语料提取/验证脚本 |

## 依赖

- 被引用：`test/corpus_test.mbt`（round-trip 测试）、`scripts/verify_corpus.py`
- `sqlglot` 仅用于差异比对，非 parser 依赖（D-07/D-20）

## 注意事项

- 每个 fixture 记录源 URL、文档版本、预期解析状态
- 核心不变量：`print_lossless(parse(fixture)) == fixture`
- 语料以官方文档为语法权威，非 g4 或薄方言
- `sqlglot` 是本地可运行的 parse 比对基准，永不作为公共契约或运行时依赖
