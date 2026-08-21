# binding

> [根级 CLAUDE.md](../CLAUDE.md) › binding

## 职责

MoonBit 与外部宿主（JavaScript ESM / 线性 Wasm / Native）之间的 FFI 边界层。将 `api`、`completion` 等核心能力封装为 8 个 `#export_name` 原语函数，输入与输出均为 UTF-8 编码的 JSON `Bytes`，不泄露任何 MoonBit ADT 或对象句柄。同时负责 wire-schema 校验、JSON 信封序列化、catalog JSON 解析，以及 LSP UTF-16 坐标与权威字节偏移之间的双向转换。

## 关键文件

| 文件 | 职责 |
|---|---|
| `exports.mbt` | 8 个 `#export_name` 导出函数 + lint overrides 解析 |
| `schema.mbt` | wire-schema 版本常量、方言/模式校验、各结果/错误信封 JSON 序列化（parse/format/fingerprint/lint/complete/lineage/dialect/capabilities） |
| `json.mbt` | 节点/诊断/偏移等 `Json` 辅助序列化函数 + `stringify` |
| `catalog_json.mbt` | 宿主 catalog JSON → `StaticCatalog` 解析（tables/db_tables/functions） |
| `coordinates.mbt` | UTF-8 字节偏移 ↔ LSP UTF-16 `Position`/`Range` 双向转换 |
| `moon.pkg` | `pkgtype(kind: "foreign_library")`，声明 JS/Wasm 导出列表 |

## 公开接口

8 个导出函数（签名）：

```moonbit
#export_name("fathom_parse_v1")
pub fn fathom_parse_v1(raw : Bytes, dialect : String, profile : String, mode : String) -> Bytes

#export_name("fathom_format_v1")
pub fn fathom_format_v1(raw : Bytes, dialect : String, profile : String, mode : String,
  keyword_case : String, indent : Int, line_width : Int,
  comma_style : String, newline_style : String, trailing_newline : Bool) -> Bytes

#export_name("fathom_complete_v1")
pub fn fathom_complete_v1(raw : Bytes, dialect : String, profile : String, cursor_byte : Int) -> Bytes

#export_name("fathom_lint_v1")
pub fn fathom_lint_v1(raw : Bytes, dialect : String, profile : String, mode : String,
  overrides : Bytes, fix : Bool) -> Bytes

#export_name("fathom_fingerprint_v1")
pub fn fathom_fingerprint_v1(raw : Bytes, dialect : String, profile : String, mode : String) -> Bytes

#export_name("fathom_lineage_v1")
pub fn fathom_lineage_v1(raw : Bytes, dialect : String, profile : String, mode : String,
  catalog_json : Bytes) -> Bytes

#export_name("fathom_dialect_v1")
pub fn fathom_dialect_v1(dialect : String) -> Bytes

#export_name("fathom_capabilities_v1")
pub fn fathom_capabilities_v1() -> Bytes
```

schema/坐标层 pub 函数：`validate_schema_version`、`validate_dialect_profile`、`validate_mode`、`schema_error_*`、`parse_result_json`、`format_result_json`、`fingerprint_result_json`、`lint_result_json`、`completion_result_json`、`lineage_result_json`、`dialect_json`、`capabilities_json`、`error_json`、`stringify`、`byte_to_position`、`span_to_range`、`position_to_byte`、`parse_catalog_json`。

## 依赖

- `fathom/sql/api` — 解析/格式化/lint/fingerprint/lineage 核心 API 与选项类型
- `fathom/sql/source` — `SourceText`、行索引
- `fathom/sql/completion` — 补全 API 与错误类型
- `fathom/sql/analyzer` — `StaticCatalog`、`TableInfo`、`FunctionInfo`
- `moonbitlang/core/debug` — `SchemaError` 的 Debug 派生
- `moonbitlang/core/json` — JSON 解析与序列化
- `moonbitlang/core/encoding/utf8` — `Bytes` ↔ `String` 编解码

下游消费者：`fathom-sql`（CLI）、`lsp`、`parity`、`test`（wire 测试）。

## 测试

binding 包内无独立测试文件。FFI 导出的正确性由 `test/binding_wire_test.mbt`（wire 级 JSON 信封契约）和 `parity/`（跨后端字节一致性）覆盖。

## 注意事项

- **Pitfall 6（方言优先）**：`fathom_format_v1`/`fathom_fingerprint_v1`/`fathom_lineage_v1`/`fathom_lint_v1` 在任何业务逻辑前先 `ParseOptions::new` 验证 dialect/profile，未知方言 → `FATHOM-SCHEMA-007`，不支持 profile → `FATHOM-SCHEMA-003`，绝不静默回退到 Doris。
- **Lineage 限制**：`fathom_lineage_v1` 对 flink 方言返回结构化 `FATHOM-SCHEMA-003 "lineage is Doris-only"`，不返回空结果（D-08）。
- **Catalog JSON**：空字节 / `"{}"` → `Ok(None)`（无 catalog，star 展开报告诚实 gap）；任何 UTF-8/JSON/结构错误 → `FATHOM-SCHEMA-004` 结构化错误，绝不静默回退（T-06-03-01, ASVS V5）。
- **Fingerprint 精度**：UInt64 指纹序列化为十进制 `Json::string`，绝不用 `Json::number`（2^53 以上精度丢失，Pitfall 3）。
- **坐标转换**：`coordinates.mbt` 中 CRLF 计为一行；无效 UTF-8 按每字节 1 单位保守计算；Native JSON 边界在调用此适配器前已拒绝无效 UTF-8。
- **Schema 版本**：v2 为纯增量（Pitfall V6），8 个 `fathom.*.v1` 命名空间并存，原命名空间分支不受影响。
