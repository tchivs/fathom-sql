# api

> [根级 CLAUDE.md](../CLAUDE.md) › api

## 职责

统一公开门面：聚合所有核心包，提供版本化的 parse/format/lint/fingerprint/lineage/complete 入口。binding 和 lsp 通过此门面访问核心能力。

## 关键文件

| 文件 | 行数 | 职责 |
|---|---|---|
| `api.mbt` | 1374 | 全部公开 API、类型别名、入口函数 |

## 公开接口

### 解析

```moonbit
pub fn parse(raw, options : ParseOptions) -> ParseResult
pub fn parse_with_ids(raw, dialect, profile, mode) -> Result[ParseResult, ParseError]
pub fn parse_with_metadata(raw, selection, metadata) -> ParseResult
pub fn parse_flink(raw, profile, mode) -> ParseResult
pub struct ParseOptions  // dialect + profile + mode + limits
pub struct ParseResult  // valid + diagnostics + primitive tree
pub struct ParseLimits  // max_bytes/tokens/recursion/recovery/diagnostics
pub enum ParseMode { Strict, Editor }
```

### 格式化 / Lint / 指纹 / 血缘

```moonbit
pub fn format_text(raw, selection, options : FormatOptions) -> Result[FormatResult, FormatError]
pub fn format_with_ids(raw, dialect, profile, mode, options) -> ...
pub fn fingerprint_text(raw, selection) -> Result[FingerprintResult, ...]
pub fn lint_text(raw, selection, options : LintOptions) -> LintResult
pub fn fix_text(raw, selection, options : LintOptions) -> LintResult
pub fn lineage_text(raw, selection, catalog) -> Result[LineageResult, ...]
```

### 类型别名（re-export）

`FormatOptions` `FormatResult` `KeywordCase` `CommaStyle` `NewlineStyle` → `@formatter`
`LintOptions` `LintResult` `LintFinding` `RuleOverride` `LintSeverity` → `@lint`
`LineageResult` `LineageEdge` `LineageGap` → `@lineage`
`StaticCatalog` → `@analyzer`

## 依赖

- **上游**：`source` `parser` `syntax` `formatter` `dialect` `fingerprint` `lint` `analyzer` `lineage`
- **下游**：`binding` `lsp` `fathom-sql` `printer` `bench` `test` `parity`

## 测试

无独立测试文件，由 `test/` 包全面覆盖（parser_test, formatter_test, lint_test, fingerprint_test, lineage_test 等 15 个文件）。

## 注意事项

- `ParseOptions::new(dialect, profile, mode)` 是主入口，dialect/profile 先验证（Pitfall 6）
- `parse_with_ids` 供 binding 直接使用（字符串 ID 参数）
- Flink 请求返回显式 FATHOM-PARSE-008/009 拒绝，绝不回退 Doris 语法（DIALECT-03）
