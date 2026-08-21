# lineage

> [根级 CLAUDE.md](../CLAUDE.md) › lineage

## 职责
基于解析后的 CST 与 analyzer 绑定结果，推导 Doris SQL 的列级血缘（column lineage）：产出 source→target 的边（edge）与诚实缺口（gap），永不伪造无法解析的来源。

## 关键文件
| 文件 | 行数 | 职责 |
|---|---|---|
| `model.mbt` | 60 | `LineageEdge` / `LineageGap` / `LineageResult` 数据模型与 gap 常量 |
| `edges.mbt` | 801 | 血缘边推导主体：公共入口 `derive_lineage` / `derive_lineage_without_catalog`，遍历文档语句、重解析 SELECT body、按 span 关联绑定并逐引用产边 |
| `views.mbt` | 236 | 文档内 `CREATE VIEW` 注册表与 `ViewCatalog[T]` 包装器（视图优先于 catalog 同名表） |
| `gaps.mbt` | 70 | `map_diagnostic_gaps`：将 analyzer 诊断映射为 lineage gap |
| `insert.mbt` | 466 | `INSERT ... SELECT` 位置映射血缘与 FROM/JOIN 来源表解析 |
| `lineage_wbtest.mbt` | 836 | 白盒测试：直接构造 SelectModel/Binding 锁定推导语义 |
| `moon.pkg` | 7 | 包配置：library，仅依赖 analyzer + syntax + debug |

## 公开接口
```moonbit
pub fn[T : @analyzer.Catalog] derive_lineage(
  root : @syntax.SyntaxNode, source_bytes : Bytes, catalog : T,
) -> LineageResult

pub fn derive_lineage_without_catalog(
  root : @syntax.SyntaxNode, source_bytes : Bytes,
) -> LineageResult

pub(all) struct LineageEdge {
  source_name : String
  source_resolved_to : String
  source_start_byte : Int
  source_end_byte : Int
  target_name : String
  target_start_byte : Int
  target_end_byte : Int
} derive(Eq, @debug.Debug)

pub(all) struct LineageGap {
  code : String
  message : String
  start_byte : Int
  end_byte : Int
} derive(Eq, @debug.Debug)

pub(all) struct LineageResult {
  edges : Array[LineageEdge]
  gaps : Array[LineageGap]
} derive(Eq, @debug.Debug)

pub struct ViewCatalog[T]
// ViewCatalog 实现 @analyzer.Catalog（table/table_in_db/function）

pub const GAP_REQUIRES_CATALOG : String = "requires-catalog"
pub const GAP_UNRESOLVED_REFERENCE : String = "unresolved-reference"
pub const GAP_REQUIRES_COMPLETE_PARSE : String = "requires-complete-parse"
```

## 依赖
- **上游（import）**: `fathom/sql/analyzer`, `fathom/sql/syntax`, `moonbitlang/core/debug`
- **下游（被 import）**: `api`, `binding`, `test`

## 测试
- `lineage_wbtest.mbt`（白盒）：直接构造 `SelectModel`/`Binding` 值，测试包私有纯推导函数（`derive_select_body` 等），不 import parser；锁定 D-01 表达式透传、单引用/函数参数、CTE 限定边、UNION 位置映射等语义。

## 注意事项
- **D-21 导入契约**：本包仅依赖 `analyzer` + `syntax` + `debug`，不 import parser；故含本地 `utf8_to_string` / `identifier_text` / `bytes_equal_ci` 等镜像实现。
- **span 全部是扁平字节偏移**，从不使用 `@source.Span`，与 analyzer 的 Binding/AnalysisDiagnostic 一致（D-06）。
- **edge/gap 排序是公开契约**（Pattern 6）：文档语句序 → SelectModel 分支/CTE 序 → SelectItem 序 → refs 序；star 展开遵循 scope-entry 序 × catalog 列序（LinkedHashMap 确定性）。跨后端确定。
- **gaps 与 edges 严格分离**（D-06）：gap 永不被标记为 edge；未解析来源只产 gap，永不伪造 edge（SC2 / D-05）。
- **不重新实现名字解析**（Pitfall）：复用 analyzer 绑定 + `split_select_model`；INSERT 追踪 body 独立用空 scope 重解析（Open Question 4）。
- **引用标识符规则（D-03）**：反引号/双引号引用标识符返回内部文本；`ViewCatalog` 与 INSERT 目标表对引用名做字节精确再校验（WR-02 / Pitfall V1）。
- **视图阴影（Pitfall 4 / A3）**：同名视图阴影 catalog 表；视图仅存在于 default-db 命名空间，db 限定查询委托内部 catalog。
- **toolchain 偏差**：`moon 0.1.20260724` 不支持 trait object，故无 catalog 场景用专用 `derive_lineage_without_catalog` 入口而非可选参数（Rule 3）。
