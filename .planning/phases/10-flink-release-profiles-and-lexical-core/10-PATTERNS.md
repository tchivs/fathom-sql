# Phase 10: Flink Release Profiles and Lexical Core - Pattern Map

**Mapped:** 2026-08-07
**Files analyzed:** 12 个唯一目标文件（8 个修改 + 4 个新增）
**Analogs found:** 12 / 12

> 本阶段的性质：把 Phase 9 的 Flink **占位面**升级为可审计的 release profile 与独立词法核心。
> analog 分三类：(1) **同构填充** —— `dialect/flink.mbt` 从 `dialect/doris.mbt` 拷贝
> DorisProfile/ProfileMetadata/行表形态（D-01 明文同构）；(2) **自身解锁** —— api/binding/
> lexer/args 的 Flink 分支从「全拒」改为「按枚举校验/按方言分支」，pattern 是「保持既有骨架、
> 只改 flink 臂」，拷贝文件内既有约定；(3) **机制复用** —— parity flink-lexical 快照组从
> `parity/baseline_test.mbt` + `approved-changes.md` + `scripts/baseline_diff.py` 复用既有快照门禁，
> 提取脚本从 `corpus/tools/check_keywords.py` 复用 stdlib 校验循环。
>
> **硬约束（贯穿全部 pattern）：** Doris 既有 213 个 parity 快照与 `doris_classification_rows`
> 116 行保持字节级零漂移（D-07/D-08）；`flink_classification_rows` 与 `doris_classification_rows`
> 是两个独立 module-level 数组，只按 `context.dialect` 选择，无全局 union（DIALECT-02，Pitfall 4）。

## File Classification

### A. 新增文件（从现有 analog 拷贝模式）

| New File | Role | Data Flow | Closest Analog | Match Quality |
|----------|------|-----------|----------------|---------------|
| `parity/flink_lexical_test.mbt` | test（snapshot） | batch（冻结） | `parity/baseline_test.mbt:25-29,351-354`（BaselineFixture + snapshot_test + `@test.T::snapshot`） | exact |
| `parity/fixtures/flink-lexical/manifest.tsv` | fixture（provenance 数据） | batch | `corpus/manifest.tsv`（TSV provenance 行形态） | role-match |
| `parity/__snapshot__/flink-lexical.{fixture}.{profile}.{mode}.json` | fixture（golden） | batch | `parity/__snapshot__/*.strict.json`（213 个既有快照字节形态） | exact |
| `scripts/extract_flink_lexical.py` | utility（研究时提取 + 校验） | batch（transform） | `corpus/tools/check_keywords.py:45-106`（stdlib 校验循环形态） | exact |

### B. 核心 MoonBit 改造（analog = 自身，按枚举/方言分支填充 flink 臂）

| Modified File | Role | Data Flow | Analog（拷贝自） | Match Quality |
|---------------|------|-----------|------------------|---------------|
| `dialect/flink.mbt`（填充占位） | model（policy 权威） | CRUD→lookup（行表 + metadata 查询） | `dialect/doris.mbt:13-26,113-127,183-190,275-462`（DorisProfile/ProfileMetadata/metadata()/from_id/doris_classification_rows） | exact（同构蓝本） |
| `api/api.mbt`（Flink 分支解锁） | facade | request-response | 自身（`ParseOptions::new` `:79-100` 的 Doris 臂 `:88-99`；flink 臂现 `Err(UnknownProfile)`） | self-rename |
| `binding/schema.mbt`（validate + wire 解锁） | schema | serialization | 自身（`validate_dialect_profile` `:40-51` flink 臂、`dialect_json` `:169-211`/`capabilities_json` `:213-246` flink `[]`） | self-rename |
| `lexer/lexer.mbt`（方言词法分支） | service | streaming（tokenize） | 自身（`lex_with_limit` `:250-363` 的 `#`/`//`/引号分支 `:277-313`；Doris 臂保持原字节） | self-rename |
| `token/token.mbt`（字面量 token 面） | model | lookup | 自身（`TokenKind` enum `:5-17`；Flink 字面量前缀如需新 kind 按此扩展） | self-rename |
| `dialect/classification.mbt`（测试更新） | model | lookup | 自身（`classification_is_dialect_independent_and_flink_rows_are_empty` `:118-143` 断言 flink 空表 → 按 release 断言行数） | self-rename |
| `fathom-sql/args.mbt`（flink profile 接受） | CLI | request-response | 自身（`is_valid_dialect_profile` `:150-156`） | self-rename |
| `fathom-sql/run.mbt`（flink 错误文案） | CLI | request-response | 自身（`parse_error_outcome`/`usage_error_message` 的 flink 文案 `"no released profiles yet (Phase 9)"` → Phase 10 实际值） | self-rename |

## Pattern Assignments

### `dialect/flink.mbt`（填充，model，policy 权威）

**Analog:** `dialect/doris.mbt`（D-01 明文同构蓝本）。

**闭合枚举 + metadata 形态**（dialect/doris.mbt:13-26）:
```moonbit
pub(all) enum DorisProfile {
  V2_1
  V3_X
  V4_X
} derive(Eq, @debug.Debug)

pub struct ProfileMetadata {
  pub id : String
  pub release_family : String
  pub exact_release : String
  pub feature_introduction : String
  // Kept as the compact, parser-facing label for existing consumers.
  pub introduced_features : String
}
```
新建形态（RESEARCH §Pattern 1 骨架；FlinkProfileMetadata 增 `calcite_version`/`parser_config` 维度，字段形态沿用 DorisProfile 的 `pub` 字段惯例）:
```moonbit
pub(all) enum FlinkProfile {
  V2_3_0
  V2_1_3
  V1_20_5
} derive(Eq, @debug.Debug)

pub struct FlinkProfileMetadata {
  pub id : String              // "flink-2.3.0"
  pub release_family : String  // "2.x" | "1.x"
  pub exact_release : String   // "flink-2.3.0"
  pub calcite_version : String // "1.36.0"（从 release POM 提取，D-02）
  pub parser_config : String   // "Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT"
  pub feature_introduction : String
}
```

**逐变体 metadata 分发形态**（dialect/doris.mbt:113-127，`FlinkProfile::metadata()` 按此逐变体返回）:
```moonbit
pub fn DorisProfile::metadata(self : DorisProfile) -> ProfileMetadata {
  match self {
    V2_1 => {
      id: "2.1",
      release_family: "2.1",
      exact_release: "2.1",
      feature_introduction: "2.1 baseline SELECT; DML/DDL released",
      introduced_features: "baseline",
    }
    V3_X => { ... }
    V4_X => { ... }
  }
}
```
Flink 侧每个变体填 `calcite_version`/`parser_config`——事实源见 RESEARCH §7/§8（`flink-2.3.0`→1.36.0、`flink-2.1.3`→1.34.0、`flink-1.20.5`→1.32.0；parser 配置三版本一致）。

**结构化拒绝错误 + 校验入口**（dialect/doris.mbt:24-33 ProfileMetadataError + :63-112 ProfileMetadata::for_manifest/validate_metadata）:
```moonbit
pub enum ProfileMetadataError {
  UnknownProfile(profile_id~ : String)
  ProfileMetadataMismatch(profile_id~ : String, expected_release~ : String, actual_release~ : String, expected_feature_introduction~ : String, actual_feature_introduction~ : String)
  UnsupportedFeatureIntroduction(feature_introduction~ : String)
} derive(Eq, @debug.Debug)
```
FlinkProfileMetadata 校验（`from_id` + 逐字段比对 + 未知 → UnknownProfile）沿用该骨架；不引入 string-keyed 软校验（D-01）。

**from_id 精确匹配**（dialect/doris.mbt:183-190）:
```moonbit
pub fn DorisProfile::from_id(id : String) -> DorisProfile? {
  match id {
    "2.1" => Some(V2_1)
    "3.x" => Some(V3_X)
    "4.x" => Some(V4_X)
    _ => None
  }
}
```
Flink 侧为 `"flink-2.3.0" => Some(V2_3_0)` / `"flink-2.1.3"` / `"flink-1.20.5"`（Pitfall 6：形态与 Doris `2.1`/`3.x`/`4.x` 绝不互借）。

**行表形态 + 行数冻结测试**（dialect/doris.mbt:275-280 行首 + :457-466 测试）:
```moonbit
let doris_classification_rows : Array[KeywordEntry] = [
  { word: b"SELECT", classification: Reserved, introduced_profile: "2.1", source: reserved_keywords_url },
  { word: b"WITH", classification: Reserved, introduced_profile: "2.1", source: reserved_keywords_url },
  ...
]

test "doris_classification_rows_match_the_frozen_v1_table" {
  // 116 rows, content byte-identical to the v1 classification_rows (D-08)
  let rows = doris_classification_rows
  assert_eq(rows.length(), 116)
  ...
}
```
`flink_classification_rows` 现为 `[]`（dialect/flink.mbt:17），Phase 10 填充为 release 提取的常量行。`source` 列对 Flink 用 release grammar 路径 + token 行号（如 `flink-sql-parser codegen/templates/Parser.jj:8640 (VARIANT)`），不用 docs URL。行数测试从 `classification_entries(flink).length() == 0` 改为按 release 断言行数（Pitfall 4 警告信号）。

**占位现状（待填充，dialect/flink.mbt:10-17）**:
```moonbit
/// Flink released-profile placeholder. Empty by design in Phase 9; ...
pub enum FlinkProfile {}

/// Flink keyword rows: intentionally empty in Phase 9 (DIALECT-02). ...
let flink_classification_rows : Array[KeywordEntry] = []
```

---

### `api/api.mbt`（Flink 分支解锁，facade）

**Analog:** 自身。`ParseOptions::new`（api/api.mbt:79-100）现 flink 臂全拒；Doris 臂的 `from_id → metadata → DialectContext` 三步形态是 flink 解锁的拷贝蓝本。`dialect_from_id`（:71-77）已返回 `Dialect::Flink`，无需改。

**解锁点现状（api/api.mbt:79-100）**:
```moonbit
pub fn ParseOptions::new(dialect_id : String, profile_id : String, mode_id : String) -> Result[ParseOptions, ParseError] {
  let dialect = match dialect_from_id(dialect_id) {
    Ok(dialect) => dialect
    Err(error) => return Err(error)
  }
  let dialect_context : @dialect.DialectContext = match dialect {
    @dialect.Dialect::Doris => {
      let profile = match @dialect.DorisProfile::from_id(profile_id) {
        Some(profile) => profile
        None => return Err(UnknownProfile(profile_id~))
      }
      let metadata = profile.metadata()
      {
        dialect: dialect,
        profile_id: profile_id,
        exact_release: metadata.exact_release,
        feature_introduction: metadata.feature_introduction,
      }
    }
    @dialect.Dialect::Flink => return Err(UnknownProfile(profile_id~))   // ← Phase 10 解锁点
  }
  ...
}
```
Phase 10 把 `@dialect.Dialect::Flink` 臂改为 `FlinkProfile::from_id(profile_id)` → `FlinkProfileMetadata`（含 calcite_version/parser_config）→ 构造 `DialectContext`（与 Doris 臂同构）；未知 flink profile 仍 `Err(UnknownProfile)` → `FATHOM-SCHEMA-003`（D-05，不新增 `FATHOM-FLINK-*`）。

**flink context 构造形态（已有，api/api.mbt:446-464 `parse_flink_not_implemented`）**——Phase 10 后该路径被真实 profile 取代，但 context 字段构造形态沿用:
```moonbit
let context : @dialect.DialectContext = {
  dialect: @dialect.Dialect::Flink,
  profile_id: profile_id,
  exact_release: profile_id,
  feature_introduction: "",
}
```

**metadata 访问器（供 wire 暴露，api/api.mbt:213-216）**:
```moonbit
pub fn ParseOptions::profile_metadata(self : ParseOptions) -> @dialect.ProfileMetadata {
  match self.profile() {
    Some(profile) => profile.metadata()
    None => panic()
  }
}
```
Flink 侧新增等价的 `FlinkProfileMetadata` 访问器（binding/schema.mbt 的 `dialect_json` 用它取 calcite_version/parser_config）。

---

### `binding/schema.mbt`（validate + wire 解锁，schema）

**Analog:** 自身。`validate_dialect_profile`（binding/schema.mbt:40-51）flink 臂现全拒；`dialect_json`/`capabilities_json`（:169-246）flink profiles 现 `[]`。code 映射（:138-150）`UnsupportedProfile → FATHOM-SCHEMA-003` 已就位，无需新增 code（D-05）。

**解锁点现状（binding/schema.mbt:40-51）**:
```moonbit
pub fn validate_dialect_profile(dialect : String, profile : String) -> Result[Unit, SchemaError] {
  match dialect {
    "doris" => match profile {
      "2.1" | "3.x" | "4.x" => Ok(())
      _ => Err(UnsupportedProfile(profile~))
    }
    "flink" => Err(UnsupportedProfile(profile~))     // ← Phase 10 解锁点
    _ => Err(UnknownDialect(dialect~))
  }
}
```
Phase 10 改为 `"flink" => match profile { "flink-2.3.0" | "flink-2.1.3" | "flink-1.20.5" => Ok(()) _ => Err(UnsupportedProfile(profile~)) }`。`UnsupportedProfile` 的 code/message 映射（:139,:150）复用不改。

**wire 暴露现状（binding/schema.mbt:169-211 `dialect_json` flink 臂）**:
```moonbit
"flink" => {
  stringify({
    "schema_version": Json::string("fathom.dialect.v1"),
    "dialect": Json::string("flink"),
    "source_transport": Json::string(SOURCE_TRANSPORT),
    "profiles": Json::array([]),        // ← Phase 10 填入 3 个 profile + calcite_version/parser_config
    "modes": Json::array([Json::string("strict"), Json::string("editor")]),
  })
}
```
Doris 臂的 profile 条目构造形态（binding/schema.mbt:173-188）是 flink 侧新增条目的蓝本——每个条目从 `ParseOptions::new` → `profile_metadata()` 取 exact_release/feature_introduction（T-09-18 provenance 纪律，不手写）。Phase 10 flink 条目增 `calcite_version`/`parser_config` 字段。

**capabilities 现状（binding/schema.mbt:213-246，flink profiles `[]`）**:
```moonbit
Json::object({
  "dialect": Json::string("flink"),
  "profiles": Json::array([]),        // ← 填入 "flink-2.3.0"|"flink-2.1.3"|"flink-1.20.5"
}),
```

---

### `lexer/lexer.mbt`（方言词法分支，service）

**Analog:** 自身。`lex_with_limit`（lexer/lexer.mbt:250-363）已把 `context : @dialect.DialectContext` 传进每个 `push_token`（:134-150）；D-06 冲突条目（`#`、`//`、`"`、字面量前缀）的**唯一实现点**是扫描分支，Doris 臂保持原字节（Pitfall 1 零漂移）。

**词法分支现状（lexer/lexer.mbt:277-313，Doris 行为，字节冻结）**:
```moonbit
} else if (byte == 45 && index + 1 < source_length && bytes[index + 1].to_int() == 45) || byte == 35 {
  // -- 与 # 都是行注释（Doris）——Flink 下 # 是 lexical error
  let start = index
  let (end, code) = scan_comment(bytes, if byte == 35 { index } else { index + 1 })
  ...
} else if byte == 47 && index + 1 < source_length && bytes[index + 1].to_int() == 42 {
  // /* */ 块注释（双方言共享）
  ...
} else if byte == 39 {
  // '...' 单引号字符串（scan_quoted；Flink 无反斜杠转义、Doris 有）
  ...
} else if byte == 34 || byte == 96 {
  // "..." 与 `...` 都是 Quoted（Doris）——Flink 下 " 是 DOUBLE_QUOTE symbol（parse error）
  ...
}
```
Phase 10 在每个分支处 `if context.dialect is Flink { ... } else { 原字节路径 }`。RESEARCH §9 词法矩阵给出逐字 token 证据（`SINGLE_LINE_COMMENT: ("//"|"--")` Parser-calcite-1.36.0.jj:8901；`DOUBLE_QUOTE: "\""` :8797；`BINARY_STRING_LITERAL: ["x","X"]<QUOTE>...` :8708；`UNICODE_STRING_LITERAL: "U" "&" <QUOTED_STRING>` :8719；`C_STYLE_ESCAPED_STRING_LITERAL` 1.36.0:8721/1.34.0:8469/1.32.0 无）。

**共享 scanner 辅助（保持不变）**（lexer/lexer.mbt:229-252）:
```moonbit
fn scan_comment(bytes : Bytes, start : Int) -> (Int, String?) {
  // /* */ 块注释 vs 行注释（到 \n 或 \r）
  ...
}

fn scan_quoted(bytes : Bytes, start : Int, quote : Int) -> (Int, String?) {
  // 双写转义 + 反斜杠转义（Doris 现有语义）
  ...
}
```
Flink 引号差异（`''` 双写、无反斜杠）在分支内用 Flink 专用扫描路径或 policy 开关实现；span/trivia/进度/`push_scanned_with_invalid`（:184-227）保证共享（DIALECT-02）。

**测试 context 构造（lexer/lexer.mbt:488-490，新增 flink 变体）**:
```moonbit
fn test_doris_context(profile_id : String) -> @dialect.DialectContext {
  { dialect: @dialect.Dialect::Doris, profile_id: profile_id, exact_release: profile_id, feature_introduction: "" }
}
```

---

### `token/token.mbt`（字面量 token 面，model）

**Analog:** 自身。`TokenKind`（token/token.mbt:5-17）现无 Flink 字面量专用 kind；Flink 前缀字面量（X/U&/N/E）在 Flink 下应成为单一 literal token（而非 Doris 的 identifier + string）。若新增 kind 按现有 enum 扩展:
```moonbit
pub(all) enum TokenKind {
  Whitespace
  Newline
  Comment
  Bom
  Identifier
  Number
  Quoted
  StringLiteral
  Symbol
  Unknown
  Error
}
```
RESEARCH §9 结论：`X'..'`→BINARY_STRING_LITERAL、`U&'..'`→UNICODE_STRING_LITERAL、`N'..'`/`_charset'..'`→PREFIXED_STRING_LITERAL、`E'..'`→C_STYLE_ESCAPED_STRING_LITERAL（2.3.0/2.1.3 支持、1.20.5 不支持）、`B'..'` 无 BIT_STRING_LITERAL token（按 identifier+string 处理）。Token 已携带 `context`（:9）与 `diagnostic_code`（:10），kind 扩展不影响既有字节。**注意**：TokenKind 是公共 API，新增 kind 属 schema 级决策——是否新增由 planner 按 fixture 需求定稿（RESEARCH Open Question 2）。

---

### `parity/flink_lexical_test.mbt`（新增，test，snapshot）

**Analog:** `parity/baseline_test.mbt`。

**Fixture 数据结构**（parity/baseline_test.mbt:25-29）:
```moonbit
pub(all) struct BaselineFixture {
  pub fixture_id : String
  pub profile : String
  pub raw : Bytes
}
```
flink-lexical 组 fixture 是「SQL 输入 + 期望分类」，命名 `flink-lexical.{fixture}.{profile}.{strict,editor}.json`（D-04 独立命名，绝不与 Doris 组重叠——Pitfall 7）。fixture 数组形态（parity/baseline_test.mbt:32-33）沿用：每个冲突条目（comment/quote/literal/identifier/operator/unknown-profile × doris/flink）一条 fixture。

**快照写入机制（parity/baseline_test.mbt:351-354）**:
```moonbit
fn snapshot_test(t : @test.Test, content : String, filename : String) -> Unit raise SnapshotError {
  t.write(content)
  t.snapshot(filename=filename)
}

test "parse 2.1-industrial strict" {
  let t = @test.Test("parse 2.1-industrial strict")
  snapshot_test(t, parse_json("2.1-industrial", "strict"), "2.1-industrial.2.1.strict.json")
}
```
flink_lexical_test.mbt 用同一 `@test.T::snapshot`（`moon test --update --package parity` 生成；无 `--update` 时字节级失败）。Doris 组 213 个快照保持零漂移——flink 组是**独立命名空间**，与 Doris 组同目录但互不影响（D-04）。

**冲突矩阵断言形态**：每条 D-06 冲突（双引号 `"x"`、`#`、`//`、`E'..'` 版本差异、`QUALIFY`/`VARIANT` 版本差异）断言「同一输入在 doris 与 flink 下不同 token 化」——用 `@api.ParseOptions::new` + `@parser.parse_with_limits_context` 或直接 `@binding.fathom_parse_v1` 在双方言下跑同一 raw，快照各自冻结（D-06：允许不同、禁止静默借用）。

---

### `parity/fixtures/flink-lexical/manifest.tsv`（新增，fixture，provenance）

**Analog:** `corpus/manifest.tsv`（TSV provenance 行形态）。Doris 侧列：`fixture_id profile exact_release feature_introduction official_url retrieval_date pinned_source_revision page_heading code_fence category support_status parse_mode classification provenance_status`。

flink manifest 记录 SC2 要求的 release 事实源（RESEARCH §7 表逐字值）：每个 profile 一行——`fixture_id  profile  exact_release  calcite_version  parser_config  source_archive_url  sha512  git_tag  git_commit`。URL/SHA-512/tag/commit 全部来自钉住 release 归档（`archive.apache.org/dist/flink/flink-{v}/flink-{v}-src.tgz`），禁止 moving `dev`/`stable` 文档（Pitfall 3）。

### `parity/__snapshot__/flink-lexical.*.json`（新增，golden）

**Analog:** `parity/__snapshot__/*.strict.json`（213 个既有快照字节形态）。样例 `2.1-boundary-single.2.1.strict.json`:
```json
{"schema_version":"fathom.parse.v1","source_transport":"inline-root-v1","dialect":"doris","profile":"2.1","exact_release":"2.1","feature_introduction":"2.1 baseline SELECT; DML/DDL released","mode":"strict","valid":true,"recovered":false,"source_bytes":[...],"source_byte_length":8,"root":{...},"diagnostics":[]}
```
flink 组命名 `flink-lexical.{fixture}.{profile}.{strict,editor}.json`（如 `flink-lexical.double-quote.flink-2.3.0.strict.json`、`flink-lexical.hash-comment.flink-2.3.0.editor.json`）。

---

### `scripts/extract_flink_lexical.py`（新增，utility，研究时提取）

**Analog:** `corpus/tools/check_keywords.py:45-106`——**stdlib 校验循环形态**：problems 列表 + 逐行报告 + 非零 exit + 尾部 `ok: ...` 成功行。D-02 提取管线（release 归档 → POM/grammar → metadata/fixture）复用该形态:
```python
problems = []
...
for lineno, line in enumerate(lines[1:], start=2):
    ...
    if <rule fails>:
        problems.append("line %d: ..." % lineno)
...
if problems:
    for problem in problems:
        print("error: " + problem, file=sys.stderr)
    return 1
print("ok: %d ..." % (len(seen), ...))
return 0
```
提取动作（RESEARCH §Pattern 5）：读 `flink-table/pom.xml:81`（calcite.version）、`flink-sql-parser/pom.xml`（calcite-core dep）、`PlannerContext.java:256-260`（parser 配置）、`Parser-calcite-{v}.jj`（词法 token）、`Parser-release-{v}.tdd`（关键字），生成 profile metadata 常量 + reserved/nonreserved 清单 + 词法 fixture。**归档是研究 fixture，不 ship**；产物固化进 `dialect/flink.mbt` 与 `parity/fixtures/flink-lexical/manifest.tsv`。

**校验脚本蓝本（check_keywords.py:10-20 常量 + HEADER/VALID_*）**:
```python
HEADER = ["word", "classification", "introduced_profile", "source"]
VALID_CLASSIFICATIONS = {"reserved", "non-reserved", "contextual"}
VALID_PROFILES = {"2.1", "3.x", "4.x"}
```
flink 侧 `VALID_PROFILES` 改为 `{"flink-2.3.0", "flink-2.1.3", "flink-1.20.5"}`（Pitfall 6：不与 Doris 形态互借）。

---

### `fathom-sql/args.mbt`（flink profile 接受，CLI）

**Analog:** 自身。`is_valid_dialect_profile`（fathom-sql/args.mbt:150-156）现 `_ => false` 全拒 flink:
```moonbit
pub fn is_valid_dialect_profile(dialect : String, id : String) -> Bool {
  match dialect {
    "doris" => id == "2.1" || id == "3.x" || id == "4.x"
    _ => false
  }
}
```
Phase 10 加 `"flink" => id == "flink-2.3.0" || id == "flink-2.1.3" || id == "flink-1.20.5"`。`parse_args` 的 `--profile` 解析（:90-100）不改——值验证走 `is_valid_dialect_profile`（Dialect-first，Pitfall 6）。`UsageError::UnknownProfile`（:15）与 exit-2 映射（:121-133）已就位，仅 message 文案更新。

### `fathom-sql/run.mbt`（flink 文案，CLI）

**Analog:** 自身。`parse_error_outcome`/`usage_error_message` 的 flink 文案现为 `"flink has no released profiles yet (Phase 9)"`（run.mbt）与 `"...(Phase 9)\n"`（args.mbt `usage_error_message`）。Phase 10 解锁后改为列出实际支持值（`flink-2.3.0|flink-2.1.3|flink-1.20.5`），未知 profile 仍 exit 2（D-39 矩阵不变）。

### `dialect/classification.mbt`（测试更新，model）

**Analog:** 自身。`classification_is_dialect_independent_and_flink_rows_are_empty`（dialect/classification.mbt:118-143）现断言 `classification_entries(flink).length() == 0` 与 `classification_of(flink, b"SELECT") is None`。Phase 10 填充 flink 行表后：改为按 release 断言行数非空 + 抽查关键词（如 `SELECT` reserved、`VARIANT` 2.3.0 reserved / 1.20.5 无），并保留「doris/flink 互不影响」的独立性断言（Pitfall 4）。`classification_rows_for`（:56-61）/`classification_of`（:64-74）/`is_reserved_word`（:90-96）的 context 路由形态**不改**——这是 flink 行表挂接点，填充行表即可自动生效。

## Shared Patterns

### 快照门禁 + 注册表批准制（D-04/D-08）
**Source:** `parity/baseline_test.mbt`（@test.T::snapshot）+ `.planning/phases/09-dialect-boundary-and-neutral-naming/approved-changes.md`（machine-readable register）+ `scripts/baseline_diff.py`。
**Apply to:** `parity/flink_lexical_test.mbt`、`parity/__snapshot__/flink-lexical.*.json`。
**机制：** `moon test --update --package parity` 生成快照；无 `--update` 时任何字节差异失败；`baseline_diff.py --left --right --approve` 把 diff 分为 approved（匹配 register）vs unexpected（exit 1）。register 行形态：
```
key:schema_version: doris.parse.v1 -> fathom.parse.v1
prefix: DORIS- -> FATHOM-
field: dialect
```
flink-lexical 组**独立命名**，任何 Doris 快照 diff 必须经 register 注册（Pitfall 7）；Doris 213 个快照字节零漂移。

### 结构化错误面（FATHOM-SCHEMA-003/007，D-05）
**Source:** `binding/schema.mbt:138-150`（schema_error_code/message）+ `api/api.mbt` `ParseError::UnknownProfile`。
**Apply to:** `api/api.mbt`、`binding/schema.mbt`、`fathom-sql/args.mbt`、`fathom-sql/run.mbt`。
**机制：** 未知/不支持 flink profile → `Err(UnknownProfile)` → `FATHOM-SCHEMA-003`；未知 dialect → `FATHOM-SCHEMA-007`。**不新增 `FATHOM-FLINK-*` 命名空间**；方言信息经 diagnostics/result 的 metadata 字段暴露（`dialect`/`profile`/`exact_release`）。

### 方言策略完全隔离（DIALECT-02，Pitfall 4）
**Source:** `dialect/classification.mbt:56-61`（classification_rows_for 只按 context.dialect 选行）。
**Apply to:** `dialect/flink.mbt`、`dialect/classification.mbt`、`lexer/lexer.mbt`。
**机制：** `doris_classification_rows`/`flink_classification_rows` 为独立 module-level 数组，无共享 mutable state；lexer 分支 `if context.dialect is Flink` 时 Doris 臂保持原字节路径。

### release 来源可审计（D-02，SC2）
**Source:** `corpus/manifest.tsv`（provenance 列形态）+ `scripts/extract_flink_lexical.py`。
**Apply to:** `dialect/flink.mbt`（metadata 常量）、`parity/fixtures/flink-lexical/manifest.tsv`。
**机制：** calcite_version/parser_config 只从钉住 release POM/grammar 提取（RESEARCH §7/§8 逐字值），禁手写推断或 folklore；manifest 记录 URL + SHA-512 + tag/commit；`sha512sum -c` 校验。

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `parity/fixtures/flink-lexical/`（fixture 目录本体） | fixture | batch | 仓库尚无 flink fixture 目录；类比 `corpus/doris-{2.1,3.x,4.x}/` 的目录形态，但 flink 组是「SQL 输入 + 期望分类」小集合，planner 按 RESEARCH §Pattern 4 定 fixture 清单 |
| `parity/__snapshot__/flink-lexical.*`（快照文件本体） | fixture | batch | 属新生成 golden 文件（由 `flink_lexical_test.mbt` 的 `--update` 生成），无既有文件可拷贝；命名规则由 D-04 锁定 |
| `dialect/flink.mbt` 的 `lex_policy()` 数据源（如 planner 采用 Open Question 2 的 policy 常量） | model | lookup | Doris 无对应物（Doris 行为硬编码于 lexer）；若采用「policy 数据源放 dialect/flink.mbt」，从 `DorisProfile::metadata()` 的逐变体 match 形态类推 |

## Metadata

**Analog search scope:** `dialect/`、`api/`、`binding/`、`lexer/`、`token/`、`parity/`、`scripts/`、`corpus/tools/`、`fathom-sql/`（全仓库读相关文件）。
**Files scanned:** 14 个源文件（doris.mbt/classification.mbt/flink.mbt/dialect.mbt/token.mbt/api.mbt/schema.mbt/lexer.mbt/baseline_test.mbt/baseline_diff.py/check_keywords.py/args.mbt/run.mbt/exports.mbt + corpus/manifest.tsv + 快照样例 + approved-changes.md）
**Pattern extraction date:** 2026-08-07
**行号依据:** 10-RESEARCH.md §7-§10 的 `[VERIFIED: 路径:行]` 与本 session 直接读取交叉核验一致。
