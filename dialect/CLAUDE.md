# dialect

> [根级 CLAUDE.md](../CLAUDE.md) › dialect

## 职责
方言策略权威层。定义 `Dialect` 枚举（Doris / Flink）和 `DialectContext` 选择上下文，维护每个方言的已发布 profile 元数据与关键字分类表，为 token / lexer / parser / api 层提供统一的方言策略查询入口。

## 关键文件
| 文件 | 行数 | 职责 |
|---|---|---|
| dialect.mbt | 31 | `Dialect` 枚举、`DialectContext` 不可变选择上下文（dialect + profile_id + exact_release + feature_introduction） |
| classification.mbt | 299 | 三层关键字分类（Reserved / NonReserved / Contextual）、`classification_of` 查询、Flink release 过滤、clause/reserved 判定函数 |
| doris.mbt | 1172 | `DorisProfile` 枚举（V2_1 / V3_X / V4_X）、`ProfileMetadata` / `ValidatedProfileContext` / `DorisFeature` 特性门控、Doris 关键字分类表 |
| flink.mbt | 1206 | `FlinkProfile` 枚举（V2_3_0 / V2_1_3 / V1_20_5）、`FlinkProfileMetadata`（含 calcite_version / parser_config）、Flink 关键字分类表（142 行） |

## 公开接口

```moonbit
// dialect.mbt
pub(all) enum Dialect { Doris; Flink }
pub(all) struct DialectContext { dialect, profile_id, exact_release, feature_introduction }

// classification.mbt
pub enum ClassificationKind { Reserved; NonReserved; Contextual }
pub struct KeywordEntry { word, classification, introduced_profile, source }
pub fn classification_of(context : DialectContext, raw : Bytes) -> KeywordEntry?
pub fn classification_entries(context : DialectContext) -> Array[KeywordEntry]
pub fn is_clause_keyword(context : DialectContext, raw : Bytes) -> Bool
pub fn is_reserved_word(context : DialectContext, raw : Bytes) -> Bool
pub fn is_unquoted_identifier(context : DialectContext, raw : Bytes) -> Bool

// doris.mbt
pub(all) enum DorisProfile { V2_1; V3_X; V4_X }
pub enum DorisFeature { Qualify; Tablet; PartitionStar; MergeInto; OrderByClause; BucketsAuto; AutoPartitionBy }
pub struct ProfileMetadata { id, release_family, exact_release, feature_introduction, introduced_features }
pub struct ValidatedProfileContext { profile, metadata }
pub enum ProfileMetadataError { UnknownProfile; ProfileMetadataMismatch; UnsupportedFeatureIntroduction }
pub fn DorisProfile::metadata(self) -> ProfileMetadata
pub fn DorisProfile::supports(self, feature : DorisFeature) -> Bool
pub fn DorisProfile::from_id(id : String) -> DorisProfile?
pub fn DorisProfile::id(self) -> String
pub fn ValidatedProfileContext::canonical(profile) -> ValidatedProfileContext
pub fn ValidatedProfileContext::supports(self, feature : DorisFeature) -> Bool
pub fn ProfileMetadata::for_manifest(profile_id, exact_release, feature_introduction) -> Result[ValidatedProfileContext, ProfileMetadataError]

// flink.mbt
pub(all) enum FlinkProfile { V2_3_0; V2_1_3; V1_20_5 }
pub struct FlinkProfileMetadata { id, release_family, exact_release, calcite_version, parser_config, feature_introduction }
pub fn FlinkProfile::metadata(self) -> FlinkProfileMetadata
pub fn FlinkProfile::from_id(id : String) -> FlinkProfile?
pub fn FlinkProfile::id(self) -> String
pub fn FlinkProfile::supports_escape_literal(self) -> Bool
```

## 依赖
- **上游**: `moonbitlang/core/debug`（Debug trait derive）
- **下游**: token, lexer, parser, formatter, fingerprint, lint, api, completion, printer

## 测试
classification.mbt 内联两个 `test` 块：
- `released_identifier_classification_is_case_insensitive_and_contextual` — Doris 大小写不敏感、TABLET 非 reserved
- `classification_is_dialect_independent_and_release_aware` — Flink 三 profile 版本过滤、Doris/Flink 独立性无泄漏

## 注意事项
- **DIALECT-02 结构独立性**：Doris 与 Flink 关键字表是两个独立模块级数组，无共享可变状态，Flink 关键字永远不影响 Doris 验收，反之亦然（Pitfall 4/7）。
- **classification_of 是关键字判断唯一来源**（Pitfall 14）：所有 reserved / contextual / clause 判定最终都路由至此函数，token/lexer/parser 不得绕过它自建关键字判断。
- **Flink 版本敏感过滤**：Flink 关键字按 `introduced_profile` 与所选 profile 的 release rank 过滤（flink-1.20.5 < flink-2.1.3 < flink-2.3.0），2.1.3 引入的词在 1.20.5 下不可见，2.3.0 引入的词在 2.1.3 和 1.20.5 下均不可见（T-10-13）。
- **Flink parse 在 Phase 10 返回 FATHOM-PARSE-008**：Flink 是合法选择值但语法在 Phase 11 落地，Phase 10 的每次 Flink 解析显式拒绝，绝不回退到 Doris 语法（DIALECT-03）。
- **DorisFeature 门控 ≠ 关键字分类门控**（D-14/D-15）：`classification_of` / `is_reserved_word` 门控标识符接受性（reserved 词需反引号），`DorisFeature` + `ValidatedProfileContext::supports` 门控语法产生式可用性并发出 FATHOM-PARSE-006。一个词可自 2.1 起 reserved，而使用它的子句被特性门控（如 ORDER → DorisFeature::OrderByClause "4.x"）。
- **FlinkProfile.from_id 严格精确匹配**（Pitfall 6）：仅三个 pinned release id 解析，不支持前缀/后缀/版本比较，不支持借入 Doris profile。
- **关键字分类行 source 字段**：Doris 行来源为官方文档 URL，Flink 行来源为 pinned release 语法文件路径 + token 行号，不得使用移动文档 URL 或 Calcite 口头知识（Pitfall 3）。
