# analyzer

> [根级 CLAUDE.md](../CLAUDE.md) › analyzer

## 职责

可选名称解析层：消费 CST 读视图 + 调用者注入的 Catalog 元数据，提供 table→column 查找和 DML/DDL 目标表解析。无类型推断，无 FE 执行语义。

## 关键文件

| 文件 | 行数 | 职责 |
|---|---|---|
| `analyzer.mbt` | 519 | Catalog 接口、StaticCatalog、TableInfo |
| `resolve.mbt` | ~1300 | 名称解析、引用提取 |
| `analysis.mbt` | ~400 | 分析结果模型 |
| `select_model.mbt` | ~800 | SELECT 语句结构模型 |
| `select_parser.mbt` | ~700 | SELECT token 序列解析 |

## 公开接口

```moonbit
pub trait Catalog { fn table(name) -> TableInfo?; fn table_in_db(db, name) -> TableInfo?; fn function(name) -> FunctionInfo? }
pub struct StaticCatalog  // 实现 Catalog
pub fn StaticCatalog::new(entries : Array[TableInfo]) -> StaticCatalog
pub fn resolve_table_references[T : Catalog](catalog : T, node : SyntaxNode) -> AnalysisResult
```

## 依赖

- **上游**：`syntax` `debug`
- **下游**：`api` `lint` `lineage` `binding` `test`

## 测试

- `analyzer_wbtest.mbt`（白盒）
- `test/analyzer_test.mbt`、`test/analyzer_anal01_test.mbt`、`test/analyzer_public_surface_test.mbt`（黑盒）

## 注意事项

- **边界契约**：仅消费 `@syntax.SyntaxNode` 读视图 + 调用者源码字节；**不** import parser/token/lexer/api/source（D-21）
- **parser 不得 import 此包**（Pitfall 7，由 `parser/moon.pkg` 负向门控）
- Catalog 元数据由调用者注入且不受信（T-02-42）
- 无 Catalog 时语法校验通道不受影响（ANLY-01）
- 当前阶段：table→column 查找 + 目标表解析；完整类型诊断为 v2
