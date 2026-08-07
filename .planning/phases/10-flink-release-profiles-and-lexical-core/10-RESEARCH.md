# Phase 10: Flink Release Profiles and Lexical Core - Research

**Researched:** 2026-08-07
**Domain:** Apache Flink release 钉住（source archive + SHA-512）、Calcite 版本 pin 提取、Flink 词法核心（注释/引号/字面量/运算符/标识符/关键字分类）、flink-lexical 快照组
**Confidence:** HIGH（外部事实全部由本 session 直接核验的 release 源码归档/POM/grammar 文件支撑，含逐字引用）；MEDIUM（`fathom.dialect.v1`/schema 的 calcite_version/parser_config 字段 wire 形态需 planner 定稿）

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Flink Profile 模型
- **D-01:** `FlinkProfile` 采用与 `DorisProfile` 同构的闭合枚举 + metadata 模式：`FlinkProfile::V2_3_0 | V2_1_3 | V1_20_5`，配套 `FlinkProfileMetadata`（id=`flink-2.3.0` 等、release_family、exact_release、calcite_version、parser_config、feature_introduction），经 `validate_dialect_profile` 统一校验；未知/不支持 profile 返回结构化错误。不引入 string-keyed 软校验。**Reversibility:** costly — FlinkProfile 类型名与 metadata 字段是代码内公共 API 与 wire metadata 契约，全量泛化需迁移所有调用点。
- **D-02:** 每个 profile 的 Calcite 版本/parser 配置**从钉住的 release 源码归档提取**（下载校验和匹配的 `flink-*-src.tgz`，读取 release POM 的 parser 配置与 Calcite 依赖版本），以可执行脚本/测试固化进 profile metadata；`flink-2.1.3` 的精确 Calcite pin 必须来自该 release 本身，禁止手写推断或 folklore。**Reversibility:** costly — metadata 字段是 wire contract（fathom.capabilities.v1 暴露），换 pin 需 schema 级记录。

#### 词法核心
- **D-03:** Flink 词法行为以**可执行 release fixture** 为唯一事实源：从钉住 release 的 grammar（Calcite parser .ftl/.jj 相关文件与 parser 配置）提取注释（`--`、`/* */`，`#` 按 release 实际支持核验）、引号（单引号字符串、双引号/反引号标识符按 Flink 实际配置）、字面量（X/U&/B/E 前缀按 release 核验）、运算符（`||`、`=>`、`:` 等按 token 集）、标识符（大小写敏感性与 unicode 规则）行为，固化为 SQL 输入 + 期望分类快照；禁止以 Calcite folklore 或 Doris 行为推断 Flink。**Reversibility:** reversible — fixture 集可经注册表批准后增补。
- **D-04:** Flink 词法快照作为 **parity/ 内独立 flink-lexical 快照组**加入既有快照门禁（D-08 机制复用：approved-changes.md 注册 + baseline_diff.py diff）；冲突矩阵（comment/quote/literal/identifier/operator/unknown-profile × doris/flink 双方言）产出可解释快照；Doris 既有快照组保持字节级零漂移。**Reversibility:** one-way — D-07 冻结的 Doris baseline 是 Phase 12 PARITY-01 对比基准，任何 Doris 字节变更都需注册批准。

#### 错误面与诊断
- **D-05:** 未知/不支持 Flink profile 的拒绝走既有 `FATHOM-SCHEMA-*` profile 错误族（与 Doris unknown profile 同族），dialect 不编码进 code 前缀（D-10 延续）；方言信息经 diagnostics/result 的 metadata 字段暴露。不新增 `FATHOM-FLINK-*` 命名空间。**Reversibility:** one-way — 诊断 code 是稳定公共契约，发布后变更需 schema 迁移。
- **D-06:** 词法冲突行为（如双引号在 Doris 与 Flink 下含义不同）以快照为裁决依据；同一输入在不同方言下允许不同 token 化，但每条路径必须可解释（快照 + 诊断/分类说明），禁止任一方向静默借用对方策略。**Reversibility:** reversible。

### Claude's Discretion
（未出现 "you decide"；所有灰区均已由既有决策链（D-01..D-11 + 本阶段 D-01..D-06）覆盖。）

### Deferred Ideas (OUT OF SCOPE)
- Flink grammar（SELECT/CTE/JOIN/聚合等语句级解析）→ Phase 11（FLINK-02..05）
- Flink 工具链（formatter/analyzer/completion/LSP/CLI 方言分发）→ Phase 13（TOOL-01..05）
- 全量 Flink corpus 提取与跨后端 parity → Phase 12（CORPUS-01、PARITY-01/02）
- 自动方言检测（即使 opt-in）→ 未来阶段，不在 v2.0 默认范围
- 显式跨方言转换（transpile）→ CONVERT-FUTURE-01
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FLINK-01 | Consumer can select pinned Flink release profiles with auditable source and parser contracts: `flink-2.3.0` as the primary profile plus `flink-2.1.3` and `flink-1.20.5` regression profiles; each profile records its actual release Calcite version/config, and unsupported profiles are rejected explicitly. | §7 Per-release Calcite pin table（2.1.3→1.34.0 从 release POM 提取，非推断）；§8 Parser 配置矩阵（三 release 一致：Lex.JAVA + identifierMaxLength 256 + FlinkSqlConformance.DEFAULT）；§9 Lexical 行为矩阵（X/U&/E 字面量按版本、`#`/`//`/双引号核验）；§10 关键字分类 + 冲突矩阵；§12 Pitfalls（folklore、moving docs、union 泄漏） |
</phase_requirements>

## Summary

Phase 10 把 Phase 9 的 Flink 占位面升级为可审计的 Flink release profile 与独立词法核心。本 session 对 /tmp/flink-research/ 缓存的 release 证据做了直接复核，关键结论：三个 release 的 Calcite pin 全部从各自的 release POM 提取并逐字引用（`flink-2.3.0`→Calcite **1.36.0**、`flink-2.1.3`→**1.34.0**、`flink-1.20.5`→**1.32.0**，`src/flink-{v}/flink-table/pom.xml:81`）；三者 parser 配置**完全一致**——`SqlParser.config().withParserFactory(FlinkSqlParserFactories.create(conformance)).withConformance(conformance).withLex(Lex.JAVA).withIdentifierMaxLength(256)`（`PlannerContext.java:256-260`），即 backtick 引号、UNCHANGED/UNCHANGED 大小写、caseSensitive=true、conformance=FlinkSqlConformance.DEFAULT（`isLiberal()=false`、`allowCharLiteralAlias()=false`）。

词法层面的三个可执行事实源核验：**注释** — Calcite 的 `SINGLE_LINE_COMMENT` 同时接受 `//` 与 `--`（`Parser-calcite-1.36.0.jj:8901`），`/* */`/`/** */`/`/*+` 为块注释/hint；`#` **不是** Calcite 注释 token（全 token 表无 `#`，Doris 的 `#` 行注释是 Flink 下的 lexical error）。**字面量** — `X'..'`（BINARY_STRING_LITERAL）、`U&'..'`（UNICODE_STRING_LITERAL + UESCAPE）、`N'..'`/`_charset'..'`（PREFIXED_STRING_LITERAL）三个版本均存在；**`E'..'`（C_STYLE_ESCAPED_STRING_LITERAL）在 1.36.0 与 1.34.0 均存在、仅 1.32.0 缺失**（修正先前「1.36.0 独有」的说法）；**`B'..'` 无 BIT_STRING_LITERAL token**（三个版本均无，`B` 按 identifier + string literal 处理）。**引号** — Flink 用 `Lex.JAVA`（`Quoting.BACK_TICK`），反引号标识符按 BTID 状态（双反引号转义）；双引号在 Flink 下是 `DOUBLE_QUOTE` symbol token 且无消费 production（`"x"` 是 parse error），而 Doris 把 `"` 与 `` ` `` 同视为 Quoted——这是 D-06 冲突矩阵的核心条目。**关键字** — `VARIANT` 是 Flink 自有 Parser.jj 模板直接追加的唯一 token（2.3.0:8640 / 2.1.3:8374，1.20.5 无）；reserved/nonreserved 清单按 release 提取（2.3.0: 443/334、2.1.3: 430/324、1.20.5: 412/323），与 Doris 116 行的冲突矩阵已计算（75 词交集、19 词 Doris-reserved-but-Flink-identifier、23 词 Doris-only、`QUALIFY` 仅 1.20.5 非 reserved、`VARIANT` 仅 2.1.3+ reserved）。

**Primary recommendation:** 按「FlinkProfile 枚举 + FlinkProfileMetadata（calcite_version/parser_config 从钉住 release 提取）→ validate_dialect_profile 解锁 → lexer 按 context.dialect 分支 → parity/ flink-lexical 快照组 + fixture manifest」的顺序实施。Doris 既有快照组（parity/__snapshot__/ 213 个文件）保持字节级零漂移，Flink 词法行为全部以 release fixture + 快照固化，禁 folklore。

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| FlinkProfile 枚举 + FlinkProfileMetadata（id/release_family/exact_release/calcite_version/parser_config/feature_introduction） | `dialect/`（`flink.mbt`，DorisProfile 同构） | `binding/`（wire 序列化） | D-01 闭合枚举 + metadata；类型名/字段是公共 API 与 wire contract，禁止 string-keyed 软校验 |
| Calcite pin / parser 配置提取（release 归档 → POM/grammar → metadata） | 研究时工具链（Python stdlib + 归档，D-02） | `dialect/flink.mbt`（固化常量）+ parity fixture manifest | 提取是一次性审计动作，产物固化进 metadata 与 manifest；不引入运行时依赖 |
| 词法策略（`#`/`//`/`--`、单/双/反引号、X/U&/B/E 字面量、运算符、标识符） | `lexer/`（共享 scanner，按 context.dialect 分支） | `dialect/`（policy 数据源：profile 驱动的开关） | scanner/span/进度/trivia 保证共享（DIALECT-02 词法独立性）；行为差异由 fixture 固化 |
| 关键字分类（reserved/non-reserved/contextual） | `dialect/`（`flink_classification_rows` 填充） | `token/`（lookup 代理 `classification_of(context, raw)`） | D-14 三层分类；行表按 release 提取，禁全局 union（DIALECT-02） |
| 未知/不支持 profile 拒绝 | `api/`（`ParseError::UnknownProfile`）+ `binding/`（`validate_dialect_profile`，FATHOM-SCHEMA-003/007） | CLI/LSP 传输层 | D-05 复用 `FATHOM-SCHEMA-*` 错误族，dialect 不进 code 前缀（D-10） |
| flink-lexical 快照门禁 + 冲突矩阵快照 | `parity/`（独立 flink-lexical 快照组） | CI（`moon test` 无 `--update` 门禁 + baseline_diff.py） | D-04/D-08 同门禁分组；Doris 组字节零漂移 |
| 词法冲突裁决（双引号、`#`、QUALIFY/VARIANT 等） | 快照 + 诊断 metadata | `parity/` 冲突矩阵 fixture | D-06 同输入不同方言允许不同 token 化，但必须可解释 |
| feature_introduction / calcite_version 元数据暴露 | `binding/schema.mbt`（`fathom.dialect.v1`/`fathom.capabilities.v1`） | `api/`（`ParseResult` metadata 字段） | SC2 要求 profile 报告 release source/tag/commit、Calcite 版本、parser 配置 |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| MoonBit toolchain (`moon`, `moonc`) | `moon 0.1.20260724 (5f1406a 2026-07-24)`（本机核验 `moon --version`） | 实现 FlinkProfile 枚举/metadata、lexer 方言分支、快照 | 唯一实现语言；本阶段零新增运行时依赖 |
| `moonbitlang/core` | 既有锁定版本 | String/Bytes/JSON/utf8/debug | 项目约束：core 是 parser 唯一必需运行时依赖 |
| `@test.T::snapshot` | 官方快照机制（`__snapshot__/` + `moon test --update`） | flink-lexical 快照组 | D-08 门禁复用；字节级失败语义 |
| Python 3 stdlib（本机 3.9.23） | — | 研究时工具：release 归档/POM 提取、reserved/nonreserved 清单生成、fixture manifest 校验（`corpus/tools/check_keywords.py` 模式） | release 归档是**研究 fixture 而非交付物**；stdlib only，零 CI 依赖 |
| git | 2.47.3 | release tag→commit 审计（`git ls-remote`） | SC2 要求 profile 记录 release tag/commit |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `bash`/`curl` + `sha512sum` | — | release 归档校验和验证、archive.apache.org 目录清单 | 一次性提取/复核；不进入 SDK 运行时或 CI 常驻路径 |
| `parity/baseline_diff.py` | 既有（stdlib） | flink-lexical 快照 shape-diff 报告 | D-04 注册表批准制 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| 从钉住 release 归档 + POM 提取 Calcite pin | 手写常量 / Calcite folklore | D-02/SC2 明文禁止推断；release POM 是唯一可审计来源 |
| 用 Flink/Calcite 运行时生成期望 | 只读 grammar/配置 + 快照 | Validation 明文「不使用 Flink/Calcite runtime」；离线可复现 |
| 独立 flink corpus 目录 + 独立 gate | parity/ 内 flink-lexical 快照组 | D-04 已锁同门禁分组；独立 gate 引入额外 CI 维护 |
| 移动 `dev`/`stable` 文档 | 钉住的 release 归档 | Validation 禁 moving docs；归档不可变 |

**Installation:**
```bash
# 本阶段不安装任何新外部包。既有依赖已锁定；release 归档是研究 fixture（/tmp/flink-research/），不进入交付物。
```

**Version verification:** 本阶段零新增 npm/pypi/crates 依赖；外部事实源为钉住的 release 归档（`/tmp/flink-research/src/flink-{2.3.0,2.1.3,1.20.5}/`，校验和已本 session 复核）。

## Package Legitimacy Audit

> 本阶段不安装任何外部包（约束：核心 parser 只用 `moonbitlang/core`；提取工具为 Python stdlib）。因此无需运行 package-legitimacy seam；下表为显式确认。

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| （无新增包） | — | — | — | — | — | N/A — 零外部依赖 |

**Packages removed due to [SLOP] verdict:** none（无候选包）
**Packages flagged as suspicious [SUS]:** none（无候选包）

## Architecture Patterns

### System Architecture Diagram

```text
Public boundaries (all pass explicit {dialect, profile})
  fathom-sql --dialect flink --profile flink-2.3.0    fathom-lsp    JS/Wasm
        └──────────────┴──────────────────┴──────────────┘
                             │ fathom.parse.v1 / fathom.error.v1
┌────────────────────────────▼────────────────────────────┐
│ api/  ParseOptions::new(dialect_id, profile_id, mode_id) │
│   dialect_from_id: "flink" → Dialect::Flink             │
│   Flink branch: FlinkProfile::from_id → metadata        │  ← Phase 10 解锁
│   unknown → UnknownProfile (FATHOM-SCHEMA-003)          │
└───────┬─────────────────────────────────────────────────┘
        │ dialect_context (profile_id/exact_release/calcite_version/parser_config)
┌───────▼─────────────────────────────────────────────────┐
│ dialect/  (policy authority)                            │
│  flink.mbt: FlinkProfile(V2_3_0|V2_1_3|V1_20_5)         │
│             FlinkProfileMetadata{calcite_version,       │
│               parser_config, feature_introduction,...}  │
│  flink_classification_rows ← Phase 10 填充（release 提取）│
└───────┬─────────────────────────────────────────────────┘
        │ context
┌───────▼────────┐      ┌────────▼────────┐
│ token/         │      │ lexer/          │
│ classification_│      │ lex(source,     │
│ of(context,raw)│◄─────│  DialectContext)│
└───────┬────────┘      │  #///-分支      │
        │               │  quote-分支     │
┌───────▼────────┐      │  literal-分支   │
│ parser/        │      └─────────────────┘
│ parse_segment  │
│ (Phase 11)     │
└────────────────┘
        │
┌───────▼─────────────────────────────────────────────────┐
│ parity/  flink-lexical 快照组（D-04）                   │
│  fixtures/ + manifest.tsv（URL+sha512+tag/commit）      │
│  __snapshot__/flink-lexical.*.{strict,editor}.json      │
│  baseline_diff.py diff（approved-changes.md 注册）      │
└─────────────────────────────────────────────────────────┘
```

### Recommended Project Structure（新增/变更部分）

```text
dialect/
├── flink.mbt          # FlinkProfile enum + FlinkProfileMetadata + flink_classification_rows（Phase 10 填充）
dialect/
├── doris.mbt          # ProfileMetadata 模式蓝本（不动，D-05）
api/
├── api.mbt            # ParseOptions::new Flink 分支解锁；FlinkProfileMetadata 校验链
binding/
├── schema.mbt         # validate_dialect_profile 增 flink profile 集合；fathom.dialect.v1/capabilities 增 calcite_version/parser_config
lexer/
├── lexer.mbt          # lex_with_limit 按 context.dialect 分支（#、//、引号、字面量前缀）
parity/
├── fixtures/flink-lexical/     # release 词法 fixture（SQL 输入）+ manifest.tsv（URL+sha512+tag/commit）
├── __snapshot__/               # flink-lexical.{fixture}.{profile}.{strict,editor}.json（与 Doris 组同目录但独立命名）
└── flink_lexical_test.mbt      # 快照生成 + 冲突矩阵断言
scripts/
└── extract_flink_lexical.py    # （研究时）release 归档 → POM/grammar → metadata/fixture 的 stdlib 提取器
corpus/flink/                   # （Phase 12 全量 corpus；本阶段只用 parity fixtures 的小集合）
```

### Pattern 1: `FlinkProfile` 闭合枚举 + `FlinkProfileMetadata`（DorisProfile 同构）

**What:** 与 `DorisProfile`（`dialect/doris.mbt:14-17`）+ `ProfileMetadata`（`dialect/doris.mbt:15-22`）同构的闭合枚举 + metadata，字段含 `calcite_version`/`parser_config`（D-01 新增维度）。**When to use:** 所有需要「flink profile 身份 + 可审计 release 契约」的边界（api 校验、wire metadata、fixture manifest）。

```moonbit
// 骨架 — 与 DorisProfile/ProfileMetadata 同构（D-01），具体字段形态由 planner 定稿
pub(all) enum FlinkProfile {
  V2_3_0
  V2_1_3
  V1_20_5
} derive(Eq, @debug.Debug)

pub struct FlinkProfileMetadata {
  pub id : String              // "flink-2.3.0"
  pub release_family : String  // "2.x" | "1.x"
  pub exact_release : String   // "flink-2.3.0"（归档/tag 名）
  pub calcite_version : String // "1.36.0"（从 release POM 提取）
  pub parser_config : String   // 序列化 parser 配置（Lex.JAVA + identifierMaxLength 256 + FlinkSqlConformance.DEFAULT）
  pub feature_introduction : String
}
```

### Pattern 2: `validate_dialect_profile` 解锁 + `FATHOM-SCHEMA-003` 拒绝路径

**What:** `binding/schema.mbt:40-51` 现状 `"flink" => Err(UnsupportedProfile(profile~))`（全拒）。Phase 10 把 `"flink"` 分支改为 `match profile { "flink-2.3.0" | "flink-2.1.3" | "flink-1.20.5" => Ok(()) _ => Err(UnsupportedProfile) }`；`api/api.mbt:79-100` 的 `ParseOptions::new` Flink 分支同样解锁（`FlinkProfile::from_id` → metadata）。未知 profile 继续走 `FATHOM-SCHEMA-003`（`binding/schema.mbt:46,139,150`），未知 dialect 走 `FATHOM-SCHEMA-007`（`:64,138`）——D-05 不新增 `FATHOM-FLINK-*`。**When to use:** 所有 profile 进入点（API/CLI/LSP/JS-Wasm）共享同一校验链；CLI `--dialect flink --profile flink-2.3.0` 从「exit 2 全拒」变为接受（`fathom-sql/args.mbt` 的 `is_valid_profile` 需按 dialect 分支，Phase 9 06-05 已预留）。

### Pattern 3: Lexer 按 `context.dialect` 参数化词法分支

**What:** `lexer/lexer.mbt` 的 `lex_with_limit`（`:250`）已把 `context : @dialect.DialectContext` 传进每个 `push_token`（`:137,150`）。Phase 10 在扫描分支处按 `context.dialect` 选择策略：`#`（Doris=comment `:277-283` vs Flink=lexical error）、`//`（Flink=comment，Doris=两个 SLASH symbol）、`"`（Doris=Quoted `:300-306` vs Flink=DOUBLE_QUOTE symbol）、`` ` ``（两方言都是 Quoted，但 Flink 双反引号转义语义需对齐 BTID）、字面量前缀（X/U&/E 在 Flink 下为字面量 token，Doris 现按 identifier+quoted 处理）。**When to use:** 词法行为差异的唯一实现点；span/trivia/进度保证保持共享（DIALECT-02）。

```moonbit
// 骨架 — 分支点示意（flink.mbt 的 policy 数据源 + lexer 分支；具体形态 planner 定）
let flink_lex_policy = @dialect.FlinkProfile::V2_3_0.lex_policy()
// lex_with_limit 内：
//   if context.dialect is Flink { /* # → error, // → comment, " → Symbol, E/X/U& → literal */ }
//   else { /* 现有 Doris 行为字节不变 */ }
```

### Pattern 4: parity/ flink-lexical 快照组 + fixture manifest（D-04）

**What:** 复用 `parity/baseline_test.mbt` 的 `@test.T::snapshot` + `baseline_diff.py` + `approved-changes.md` 机制，新增独立 flink-lexical 快照组（与 Doris 组同名 `__snapshot__/` 目录但独立 fixture 命名，如 `flink-lexical.flink-2.3.0.strict.json`）。fixture 是「SQL 输入 + 期望分类」，manifest 记录 release/tag/commit/URL/sha512/Calcite 版本/parser 配置（SC2/CORPUS-01 前身）。**When to use:** 每个词法冲突条目（comment/quote/literal/identifier/operator/unknown-profile × doris/flink）都有一条 fixture + 快照；Doris 组 213 个快照字节零漂移。

### Pattern 5: 研究时提取管线（release 归档 → metadata/fixture）

**What:** `scripts/extract_flink_lexical.py`（Python stdlib，仿 `corpus/tools/check_keywords.py` 校验形态）：从钉住 `flink-*-src.tgz` 读取 `flink-table/pom.xml`（calcite.version）、`flink-sql-parser/pom.xml`（calcite-core dep）、`PlannerContext.java`（parser 配置）、`Parser.tdd`/`codegen/templates/Parser.jj`（关键字/字面量/运算符 token）、`FlinkSqlConformance.java`（conformance flags），生成 profile metadata 常量 + reserved/nonreserved 清单 + 词法 fixture。产物固化进 `dialect/flink.mbt` 与 `parity/fixtures/flink-lexical/manifest.tsv`；**归档本身是研究 fixture，不 ship**。

## Per-Release Calcite Pin Table

> 三个 release 的 Calcite 版本均从**该 release 自身**的 `flink-table/pom.xml` `<calcite.version>` 属性提取并逐字引用（D-02：2.1.3 的 pin 从 release 提取，非推断）；`flink-sql-parser/pom.xml` 的 calcite-core 依赖确认是 vanilla `org.apache.calcite:calcite-core`（非 fork）。

| Release | 归档日期（archive.apache.org 目录清单） | Git tag | Git commit（peeled） | Calcite（`flink-table/pom.xml:81` 逐字） | Source archive URL + SHA-512 |
|---------|----------------------------------------|---------|----------------------|------------------------------------------|------------------------------|
| **flink-2.3.0** | 2026-06-14 18:20 `[CITED: https://archive.apache.org/dist/flink/flink-2.3.0/ 目录清单]` | `release-2.3.0` | `c0f8d1a1e09f209885a88f9c19ceb9d9e9870283` `[VERIFIED: git ls-remote https://github.com/apache/flink.git (2026-08-07)]` | `1.36.0` `[VERIFIED: /tmp/flink-research/src/flink-2.3.0/flink-table/pom.xml:81 — `<calcite.version>1.36.0</calcite.version>`]` | `https://archive.apache.org/dist/flink/flink-2.3.0/flink-2.3.0-src.tgz` `[VERIFIED: /tmp/flink-research/flink-2.3.0-src.tgz.sha512 — `b189214e5b8b45c3f76bb296550f5ae49f711541d70ce2054787571dcbd026bf539b3b90ac902917523a6e894619c0df93210315f64bd0d6244c8328eb5d1cbd`]` |
| **flink-2.1.3** | 2026-06-08 06:51 `[CITED: https://archive.apache.org/dist/flink/flink-2.1.3/ 目录清单]` | `release-2.1.3` | `6cda56b084d5c337b36d2f8ed464bc92093b0a34` `[VERIFIED: git ls-remote https://github.com/apache/flink.git (2026-08-07)]` | `1.34.0` `[VERIFIED: /tmp/flink-research/src/flink-2.1.3/flink-table/pom.xml:81 — `<calcite.version>1.34.0</calcite.version>`]` | `https://archive.apache.org/dist/flink/flink-2.1.3/flink-2.1.3-src.tgz` `[VERIFIED: /tmp/flink-research/flink-2.1.3-src.tgz.sha512 — `a1a35ee35d5d417b7445de1648510060d2c3281f7185eefe4d2fc74b9c77821b89bbc9de55f47dbf2053d20d87fbc4c5d90af9bba4fd9d9c75d0f3ce44d8b3fe`]` |
| **flink-1.20.5** | 2026-06-08 11:28 `[CITED: https://archive.apache.org/dist/flink/flink-1.20.5/ 目录清单]` | `release-1.20.5` | `0980485040c6dbec3a1b32da05c4b655cf01ad2b` `[VERIFIED: git ls-remote https://github.com/apache/flink.git (2026-08-07)]` | `1.32.0` `[VERIFIED: /tmp/flink-research/src/flink-1.20.5/flink-table/pom.xml:81 — `<calcite.version>1.32.0</calcite.version>`]` | `https://archive.apache.org/dist/flink/flink-1.20.5/flink-1.20.5-src.tgz` `[VERIFIED: /tmp/flink-research/flink-1.20.5-src.tgz.sha512 — `ce11ae5a81a2ba16d1c5f22e5025a743bccff4f54a3b9836e58956ac98720c73db5a1c4ab7c87436c6fecc2c5dd8dca2514acc29d5e1c36334c41265729e3add`]` |

**vanilla calcite-core 依赖（flink-sql-parser POM，非 fork）：**
- `[VERIFIED: /tmp/flink-research/src/flink-2.3.0/flink-table/flink-sql-parser/pom.xml:65-68 — `<groupId>org.apache.calcite</groupId> / <artifactId>calcite-core</artifactId> / <version>${calcite.version}</version>`（`:73` 依赖树 `[INFO] +- org.apache.calcite:calcite-core:jar:1.36.0:compile`）]`
- `[VERIFIED: /tmp/flink-research/src/flink-2.1.3/flink-table/flink-sql-parser/pom.xml:65-68 — 同上，`:73` `calcite-core:jar:1.34.0:compile`]`
- `[VERIFIED: /tmp/flink-research/src/flink-1.20.5/flink-table/flink-sql-parser/pom.xml:59-62 — 同上（行号偏移），`:67` `calcite-core:jar:1.32.0:compile`]`

**校验和复核（本 session）：** `sha512sum -c flink-{2.3.0,2.1.3,1.20.5}-src.tgz.sha512` 全部 `OK`。

## Parser Configuration Matrix

> 三个 release 的 parser 配置**完全一致**——`PlannerContext.java` 的 `getSqlParserConfig()` 默认路径逐字相同（`:252-260`）；差异只在 Calcite 版本与 Flink 关键字清单（§10）。

| 配置项 | flink-2.3.0 / flink-2.1.3 / flink-1.20.5（三 release 一致） | 证据 |
|--------|------------------------------------------------------------|------|
| parser factory | `FlinkSqlParserFactories.create(conformance)`（仅接受 `FlinkSqlConformance.DEFAULT`，否则 `TableException`） | `[VERIFIED: src/flink-2.3.0/.../FlinkSqlParserFactories.java:33-37 — `if (conformance == FlinkSqlConformance.DEFAULT) { return FlinkSqlParserImpl.FACTORY; } else { throw new TableException("Unsupported SqlConformance: " + conformance); }`]` |
| quoting | `Quoting.BACK_TICK`（反引号标识符，双反引号转义） | `[VERIFIED: /tmp/flink-research/Lex-1.36.0.java:77-79 — `JAVA(Quoting.BACK_TICK, Casing.UNCHANGED, Casing.UNCHANGED, true, CharLiteralStyle.STANDARD)`]` |
| unquoted casing | `Casing.UNCHANGED` | 同上（Lex.JAVA 第二个参数） |
| quoted casing | `Casing.UNCHANGED` | 同上（Lex.JAVA 第三个参数） |
| caseSensitive | `true` | 同上（Lex.JAVA 第四个参数） |
| identifier max length | `256`（Calcite 默认 128） | `[VERIFIED: src/flink-{2.3.0,2.1.3,1.20.5}/.../PlannerContext.java:260 — `.withIdentifierMaxLength(256)`]` |
| conformance | `FlinkSqlConformance.DEFAULT` | `[VERIFIED: src/flink-{v}/.../PlannerContext.java:256-258 — `SqlParser.config().withParserFactory(FlinkSqlParserFactories.create(conformance)).withConformance(conformance)`]` |
| 配置构造注释 | "we use Java lex because back ticks are easier than double quotes in programming and cases are preserved" | `[VERIFIED: src/flink-{v}/.../PlannerContext.java:252-254 — `// we use Java lex because back ticks are easier than double quotes in`（三 release 同）]` |

**FlinkSqlConformance.DEFAULT 关键 flags（`src/flink-2.3.0/flink-table/flink-sql-parser/src/main/java/org/apache/flink/sql/parser/validate/FlinkSqlConformance.java`，三 release 同）：**
- `[VERIFIED: :31-33 — `public boolean isLiberal() { return false; }`]`
- `[VERIFIED: :36-38 — `public boolean allowCharLiteralAlias() { return false; }`]`
- `[VERIFIED: :86-88 — `public boolean isBangEqualAllowed() { return false; }`]`（`!=` 不被 conformance 放行）
- `[VERIFIED: :91-93 — `public boolean isPercentRemainderAllowed() { return true; }`]`（`%` 放行）
- `[VERIFIED: :56-58 — `public boolean isSortByOrdinal() { return true; }`]`、`[VERIFIED: :61-63 — `public boolean isSortByAlias() { return true; }`]`

**Calcite SqlParser.Config 默认值（Flink 不用，仅对照；`/tmp/flink-research/SqlParser-calcite-1.36.0.java`，1.34.0/1.32.0 同）：**
- `[VERIFIED: :52 — `public static final int DEFAULT_IDENTIFIER_MAX_LENGTH = 128;`]`
- `[VERIFIED: :278-279 — `return Casing.UNCHANGED;`（quotedCasing）]、`:285-286 — `return Casing.TO_UPPER;`（unquotedCasing）]、`:292-293 — `return Quoting.DOUBLE_QUOTE;`]`、`:299 — `return true;`（caseSensitive）]、`:306 — `return SqlConformanceEnum.DEFAULT;`]`
- 结论：Flink 通过 `withLex(Lex.JAVA)` 覆盖 Calcite 默认（DOUBLE_QUOTE/TO_UPPER），并 `withIdentifierMaxLength(256)` 覆盖 128。

## Lexical Behavior Matrix

> 行为以 release grammar（`Parser-calcite-{1.36.0,1.34.0,1.32.0}.jj` 与 Flink 自有 `codegen/templates/Parser.jj`）逐字核验；注释/引号/字面量 token 三版本除 `E'..'` 外一致。对照列为当前 Doris lexer（`lexer/lexer.mbt`）行为——两者差异即 D-06 冲突矩阵。

### 注释（Calcite 三版本一致）

| 语法 | Calcite/Flink token | 证据 | Doris 现状 | 冲突 |
|------|---------------------|------|-----------|------|
| `--` 行注释 | `SINGLE_LINE_COMMENT: ("//"\|"--")(~["\n","\r"])* ("\n"\|"\r"\|"\r\n")?` | `[VERIFIED: /tmp/flink-research/Parser-calcite-1.36.0.jj:8901 — `SINGLE_LINE_COMMENT: ("//"|"--")(~["\n","\r"])* ("\n"|"\r"|"\r\n")?`]` | `--` 是 comment（`lexer.mbt:277`） | 无（双方言都支持 `--`） |
| `//` 行注释 | 同上（`"//"` 与 `"--"` 同一 token） | 同上 | **Doris 把 `//` 当两个 SLASH symbol**（`:277` 只测 `--` 与 `#`） | **Flink-only**：`// x` 在 Doris 下是符号序列 |
| `/* */` 块注释 | `MULTI_LINE_COMMENT`（`"/*" { pushState(); } : IN_MULTI_LINE_COMMENT` → `<MULTI_LINE_COMMENT: <COMMENT_END> >`） | `[VERIFIED: Parser-calcite-1.36.0.jj:8894-8896,8910-8913]` | `/* */` 是 comment（`lexer.mbt:283-290`） | 无 |
| `/** */` 正式注释 | `FORMAL_COMMENT`（`<"/**" ~["/"]> { pushState(); } : IN_FORMAL_COMMENT`） | `[VERIFIED: Parser-calcite-1.36.0.jj:8889-8892]` | 同上（按 `/*` 处理） | 低 |
| `/*+ */` hint | `HINT_BEG: "/*+"` | `[VERIFIED: Parser-calcite-1.36.0.jj:8883,8885]` | 同上 | 低 |
| `#` 行注释 | **无 token** — `#` 不在任何注释/符号 token 集，lexical error | 全文件 grep 无 `#` token；`[VERIFIED: Parser-calcite-1.36.0.jj:500 — 注释示例 `Lexical error at line 3, column 24. Encountered "#" after "a".`（说明 `#` 触发 lexical error）]` | **Doris 把 `#` 当行注释**（`lexer.mbt:277` `byte == 35`） | **Flink-only error**：`#` 在 Flink 下是 lexical error，Doris 下是注释——D-06 核心冲突条目 |

### 引号

| 语法 | Calcite/Flink | 证据 | Doris 现状 | 冲突 |
|------|---------------|------|-----------|------|
| `'...'` 单引号字符串 | `QUOTED_STRING: <QUOTE> ( (~["'"]) \| ("''"))* <QUOTE>`（单引号转义为双写 `''`，**无反斜杠转义**） | `[VERIFIED: Parser-calcite-1.36.0.jj:8715]` | Doris 单引号用 `scan_quoted`（双写 + 反斜杠 `\` 都转义，`lexer.mbt:292-298,221-233`） | 中等：Flink 标准模式无反斜杠转义；Doris 支持 `\'` |
| `` `...` `` 反引号标识符 | BTID 状态 `BACK_QUOTED_IDENTIFIER: "\`" ( (~["\`","\n","\r"]) \| ("\`\`"))+ "\`"`（双反引号转义） | `[VERIFIED: Parser-calcite-1.36.0.jj:8951-8962 — `<BTID> TOKEN : { < BACK_QUOTED_IDENTIFIER: "\`" ( (~["\`","\n","\r"]) | ("\`\`") )+ "\`" > }`]`；`:8844-8845` 状态注释 `BTID: Identifiers are enclosed in back-ticks, escaped using back-ticks` | Doris 把 `` ` `` 当 Quoted（`lexer.mbt:300`），双写 `\`\`` 语义需对齐 | 无重大冲突（双方言都支持反引号标识符）；转义细节以 fixture 核验 |
| `"..."` 双引号 | **不是标识符引号**（DQID 状态在 Lex.JAVA 下不激活）；`"` 是 `DOUBLE_QUOTE` symbol token（`:8797` `< DOUBLE_QUOTE: "\"" >`），DEFAULT 状态无消费 production → `"x"` 是 parse error；双引号字符串仅 BigQuery 风格（BQID/BQHID，Flink 不用） | `[VERIFIED: Parser-calcite-1.36.0.jj:8797,8733-8734（BIG_QUERY_DOUBLE_QUOTED_STRING 仅在 BQID/BQHID）]` | **Doris 把 `"` 当 Quoted**（`lexer.mbt:300` `byte == 34`），DDL 示例 `DEFAULT "10.5"` 合法 | **Flink-only error**：`"x"` 在 Flink 下 parse error，Doris 下是 Quoted——D-06 冲突矩阵第一条目（Research flags 明文核验双引号） |

### 字面量（按 Calcite 版本）

| 字面量 | token | Calcite 1.36.0 / 1.34.0 / 1.32.0 | 证据 | 说明 |
|--------|-------|----------------------------------|------|------|
| `X'..'` | `BINARY_STRING_LITERAL` | 三版本均存在 | `[VERIFIED: Parser-calcite-1.36.0.jj:8708 — `< BINARY_STRING_LITERAL: ["x","X"] <QUOTE> ( (~["'"]) | ("''"))* <QUOTE> >`]`；生产 `:4534` `SqlLiteral.createBinaryString` | 十六进制字节串 |
| `U&'..'` | `UNICODE_STRING_LITERAL` | 三版本均存在 | `[VERIFIED: Parser-calcite-1.36.0.jj:8719 — `< UNICODE_STRING_LITERAL: "U" "&" <QUOTED_STRING> >`]`；生产 `:4577` 设 `unicodeEscapeChar = BACKSLASH; charSet = "UTF16"`；`[VERIFIED: :4615 — `[ <UESCAPE> <QUOTED_STRING> ]`]` | 默认反斜杠转义，`UESCAPE` 可覆盖 |
| `N'..'` / `_charset'..'` | `PREFIXED_STRING_LITERAL` | 三版本均存在 | `[VERIFIED: Parser-calcite-1.36.0.jj:8717 — `< PREFIXED_STRING_LITERAL: ("_" <CHARSETNAME> | "N") <QUOTED_STRING> >`]` | 字符集前缀 |
| `E'..'` | `C_STYLE_ESCAPED_STRING_LITERAL` | **1.36.0 ✓ / 1.34.0 ✓ / 1.32.0 ✗** | `[VERIFIED: Parser-calcite-1.36.0.jj:8721 — `< C_STYLE_ESCAPED_STRING_LITERAL: "E" <QUOTE> ( (~["'", "\\"]) | ("\\" ~[]) | "''")* <QUOTE> >`]`；1.34.0 同 `:8469`；**1.32.0 grep 0 命中** | **修正先前记录**：`E'..'` 非 1.36.0 独有，1.34.0 也有；仅 1.20.5（calcite 1.32.0）不支持 |
| `B'..'` | `BIT_STRING_LITERAL` | **三版本均无** | grep 三版本 Parser.jj 均无 `BIT_STRING` 命中；`B` 不是字面量前缀（PREFIXED 只接受 `_charset`/`N`） | `B'101'` 在 Flink 下 = identifier `B` + string `'101'`，非 bit 字面量（Research flags 明文核验 B） |

### 运算符（Calcite 1.36.0 token 集；1.34.0/1.32.0 对应行号偏移，内容一致）

| 运算符 | token | 证据 |
|--------|-------|------|
| `=` `>` `<` `?` `:` | `EQ` `GT` `LT` `HOOK` `COLON` | `[VERIFIED: Parser-calcite-1.36.0.jj:8790-8791（EQ/GT/LT）]` |
| `<=` `>=` `<>` `!=` | `LE` `GE` `NE` `NE2` | `[VERIFIED: Parser-calcite-1.36.0.jj:8792-8793]` |
| `+` `-` `*` `/` `%` | `PLUS` `MINUS` `STAR` `SLASH` `PERCENT_REMAINDER` | `[VERIFIED: Parser-calcite-1.36.0.jj:8792,8791,8796]` |
| `\|\|` | `CONCAT` | `[VERIFIED: Parser-calcite-1.36.0.jj:8793 — `< CONCAT: "\|\|" >`]` |
| `=>` | `NAMED_ARGUMENT_ASSIGNMENT` | `[VERIFIED: Parser-calcite-1.36.0.jj:8794 — `< NAMED_ARGUMENT_ASSIGNMENT: "=>" >`]` |
| `..` | `DOUBLE_PERIOD` | `[VERIFIED: Parser-calcite-1.36.0.jj:8795 — `< DOUBLE_PERIOD: ".." >`]` |
| `'` `"` | `QUOTE` `DOUBLE_QUOTE` | `[VERIFIED: Parser-calcite-1.36.0.jj:8796-8797]` |
| `\|` `^` `$` | `VERTICAL_BAR` `CARET` `DOLLAR` | `[VERIFIED: Parser-calcite-1.36.0.jj:8798-8800]` |
| Flink 自定义 binary operators | `binaryOperatorsTokens: []`（**空**）；`includePosixOperators: false`；`includeBraces: true` | `[VERIFIED: /tmp/flink-research/Parser-release-2.3.0.tdd:755-757（`binaryOperatorsTokens: [` 后空），:765 `includePosixOperators: false`，:767 `includeBraces: true`]` |

### 标识符

| 属性 | 值 | 证据 |
|------|-----|------|
| 标识符 token | `IDENTIFIER: <LETTER> (<LETTER>\|<DIGIT>)*`；`LETTER` 含 `$`、`_`、A-Z/a-z 及 unicode 范围（`\u00c0`-`\u00d6` 等） | `[VERIFIED: Parser-calcite-1.36.0.jj:8986-9013（`< IDENTIFIER: <LETTER> (<LETTER>|<DIGIT>)* >`；`< #LETTER: [ "\u0024", "\u0041"-"\u005a", "\u005f", "\u0061"-"\u007a", "\u00c0"-"\u00d6", ... ] >`）]` |
| 大小写 | caseSensitive=true；unquoted/quoted casing 均 UNCHANGED | §8（Lex.JAVA） |
| unicode 引用标识符 | `UNICODE_QUOTED_IDENTIFIER: "U" "&" <QUOTED_IDENTIFIER>`（U&"..."） | `[VERIFIED: Parser-calcite-1.36.0.jj:8995-8997]` |
| 括号引用（DEFAULT 状态） | `BRACKET_QUOTED_IDENTIFIER: "[...]"`（双 `]]` 转义） | `[VERIFIED: Parser-calcite-1.36.0.jj:8925-8937]` — Flink 用 BTID 状态，括号标识符按 quote 处理与否以 fixture 核验 |

## Keyword Classification

### Per-Release 关键字清单（release 生成 parser 提取）

> reserved/nonreserved 清单由钉住 release 的生成 parser 关键字 token 集提取（Calcite base + Flink Parser.tdd `keywords` 叠加，经 `nonReservedKeywords` 解析）；缓存文件 `/tmp/flink-research/flink-{2.3.0,2.1.3,1.20.5}-{reserved,nonreserved}.txt`。

| Release | reserved 词数 | nonreserved 词数 | 合计 |
|---------|---------------|------------------|------|
| flink-2.3.0 | 443 | 334 | 777 |
| flink-2.1.3 | 430 | 324 | 754 |
| flink-1.20.5 | 412 | 323 | 735 |

**Reserved 集增量（release 间）：**
- **2.3.0 比 2.1.3 新增 13 词**：`BITMAP, CONFLICT, CONNECTIONS, CONTAINS_SUBSTR, DATETIME_TRUNC, DEDUPLICATE, DO, JSON_SCOPE, NOTHING, ORDINAL, SAFE_CAST, SAFE_OFFSET, SAFE_ORDINAL` `[VERIFIED: comm -23 flink-2.3.0-reserved.txt flink-2.1.3-reserved.txt]`
- **2.1.3 比 1.20.5 新增 18 词**：`DATETIME, DATE_TRUNC, FRIDAY, MONDAY, QUALIFY, QUARTERS, SATURDAY, STRUCTURED, SUNDAY, THURSDAY, TIMESTAMP_DIFF, TIMESTAMP_TRUNC, TIME_DIFF, TIME_TRUNC, TUESDAY, VARIANT, WEDNESDAY, WEEKS` `[VERIFIED: comm -23 flink-2.1.3-reserved.txt flink-1.20.5-reserved.txt]`
- **Nonreserved 2.3.0 比 2.1.3 新增 10 词**：`ARTIFACT, DAYOFWEEK, DAYOFYEAR, FROM_BEGINNING, FROM_NOW, FROM_TIMESTAMP, RESUME_OR_FROM_BEGINNING, RESUME_OR_FROM_NOW, RESUME_OR_FROM_TIMESTAMP, START_MODE`

**VARIANT（Flink 模板级关键字增量）：**
- VARIANT 是 Flink 自有 `codegen/templates/Parser.jj`（非 Parser.tdd 数据）**直接追加的唯一关键字 token**：`[VERIFIED: /tmp/flink-research/src/flink-2.3.0/flink-table/flink-sql-parser/src/main/codegen/templates/Parser.jj:8640 — `|   < VARIANT: "VARIANT" >`]`、`[VERIFIED: src/flink-2.1.3/.../codegen/templates/Parser.jj:8374 — 同]`；1.20.5 模板 grep 无命中。
- VARIANT 是 reserved（`[VERIFIED: /tmp/flink-research/flink-2.3.0-reserved.txt:424 — `VARIANT`]`、`flink-2.1.3-reserved.txt:411`）；**1.20.5 完全没有 VARIANT**（reserved/nonreserved 均无）。
- 其余 74 个 Flink 关键字（Parser.tdd `keywords`）经 `nonReservedKeywords` 解析：55 个保留为 reserved（`ANALYZE, BUCKETS, WATERMARK, ...`），19 个变为 nonreserved。VARIANT 之外的 55 个 Flink reserved 词全部来自 Parser.tdd 配置机制，非模板硬编码。

### 冲突矩阵（Doris 116 行 vs Flink reserved 集）

> Doris 侧 = `dialect/doris.mbt` 的 `doris_classification_rows` 116 个唯一词（`[VERIFIED: dialect/doris.mbt:275-462，116 行；test `doris_classification_rows_match_the_frozen_v1_table` 断言 `assert_eq(rows.length(), 116)`（:460）]`）。计算方式：本 session 从 `doris.mbt` 逐行提取 word+classification 与 flink reserved/nonreserved 清单做集合比较。

| 类别 | flink-2.3.0 / 2.1.3 | flink-1.20.5 | 说明 |
|------|---------------------|--------------|------|
| **交集（双方言都 reserved，行为一致）** | **75 词**：ALL AND AS BETWEEN BUCKETS BY COMMENT COMMIT CREATE CROSS CUBE CURRENT CURRENT_TIMESTAMP DELETE DISTINCT DISTRIBUTED EVERY EXCEPT EXISTS EXTERNAL FALSE FROM FULL GROUP GROUPING GROUPS HASH HAVING IF IN INNER INSERT INTO IS JOIN LEFT LIKE LIMIT MATERIALIZED MERGE NATURAL NOT NULL OFFSET ON OR ORDER OUTER OVER OVERWRITE PARTITION PARTITIONS QUALIFY RANGE RECURSIVE REFRESH RIGHT ROLLUP ROW ROWS SELECT SET TABLE TABLESAMPLE THEN TRUE UNION UNIQUE UPDATE USING VALUES WHEN WHERE WINDOW WITH | **74 词**（同左 **减 QUALIFY**） | 双方言都需要反引号引用；`MERGE/ORDER/PARTITION/QUALIFY` 等都在列 |
| **Doris-reserved 但 Flink-identifier（19 词，两版本同）** | ASC AUTO DEFAULT DESC DISTINCTROW DUPLICATE FIRST FOLLOWING INDEX KEY LAST LIST NULLS OUTFILE PRECEDING REGEXP SAMPLE SETS UNBOUNDED | 同左 | Doris 下需反引号，Flink 下是普通 identifier（多数在 Flink nonreserved，如 ASC/DESC/KEY/FIRST/LAST/NULLS；少数完全缺席，如下） |
| **Doris-only（完全不在 Flink 关键字表，23 词）** | AGGREGATE ASYNC AUTO AUTO_INCREMENT BUILD COMPLETE DEFAULT DISTINCTROW DUPLICATE ENGINE INDEX LESS LIST MANUAL OUTFILE PROPERTIES RANDOM REGEXP SAMPLE SCHEDULE STARTS TABLET THAN | 同左 | Flink 下是普通 identifier；含 Doris 专有词（TABLET/OUTFILE/DISTINCTROW/REGEXP/AUTO_INCREMENT） |
| **Flink-reserved 但 Doris 无此词（Flink-only reserved，2.3.0 为 368 词）** | 368 词（Calcite base + Flink 关键字，如 ALLOCATE ARRAY AVG BEGIN BIGINT CASE CAST CHAR ... 及 ANALYZE BUCKETS WATERMARK VARIANT） | 1.20.5 略少（VARIANT 等缺席） | Flink 下需反引号；Doris 下是普通 identifier——`SELECT \`analyze\`` 在 Flink 合法、Doris 是 Quoted 也合法，但 unquoted `analyze` 在 Flink 是 error、Doris 是 identifier |
| **版本敏感词** | `QUALIFY`：2.1.3+ reserved，Doris-reserved → 双方言一致 | 1.20.5 中 QUALIFY **完全缺席**（reserved/nonreserved 均无）→ Flink 下是 identifier，Doris 下 reserved | **flink-1.20.5 回归 profile 的专属冲突** |
| | `VARIANT`：2.1.3+ reserved；Doris 无此词 | 1.20.5 无 VARIANT | `VARIANT` 在 flink-2.3.0/2.1.3 需反引号，在 flink-1.20.5 与 doris 是 identifier |

**D-06 裁决要点：** 上述冲突（双引号、`#`、`//`、`E'..'` 版本差异、`QUALIFY`/`VARIANT` 版本差异、Doris-only reserved 词）每条都需一条「SQL 输入 + 双方言期望分类」fixture 快照；同一输入在 doris 与 flink 下允许不同 token 化，但快照 + 诊断/分类说明使其可解释，禁止任一方向借用对方策略。

## Runtime State Inventory

> 本阶段不是 rename/refactor/migration phase（Phase 9 已完成命名 cutover 并冻结 Doris baseline）；以下按五类显式回答。**核心约束：Doris 既有 213 个 parity 快照与 `doris_classification_rows` 116 行保持字节级零漂移（D-07/D-08）。**

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — 本阶段不新增数据库/键值存储；`dialect/flink.mbt` 的 `flink_classification_rows` 现为 `[]`（`:17`），Phase 10 填充为 release 提取的常量行 | code edit（新增行表 + metadata 常量）；Doris 行表不动 |
| Live service config | None — SDK 无外部服务；`fathom.dialect.v1`/`fathom.capabilities.v1`（`binding/schema.mbt:169-211,213-246`）的 flink profiles 现为 `[]`，Phase 10 填入 `flink-2.3.0/2.1.3/1.20.5` | code edit（`dialect_json`/`capabilities_json` 的 flink 分支） |
| OS-registered state | None — 无 Task Scheduler/pm2/systemd 等注册项涉及 flink profile 名 | none |
| Secrets/env vars | None — 无 .env/CI 环境变量以 `flink-2.x` 命名；release 归档校验和固化进 parity fixture manifest（非运行时 secret） | none |
| Build artifacts | 研究期 fixture：`/tmp/flink-research/src/flink-{2.3.0,2.1.3,1.20.5}/`（约 727MB）与 `flink-*-src.tgz` — 本 session 已校验和复核；**不 ship**。交付物内无旧名构建产物残留（Phase 9 命名 gate 已保证） | 归档留在 /tmp 供 Phase 12 corpus 复用；不复制进仓库（仓库只放 manifest 元数据 + 小 fixture） |

**Nothing found in category:** Stored data / Live service config / OS-registered state / Secrets（显式「None」如上）。

## Common Pitfalls

### Pitfall 1: Doris 回归零漂移被 Flink 改造打破
**What goes wrong:** lexer 按 dialect 分支时误改 Doris 扫描路径（如把 `#` 从 comment 改成 error 会影响 Doris）；或 `doris_classification_rows` 行序/内容被意外触碰。
**Why it happens:** lexer/lexer.mbt 的 `lex_with_limit`（`:250`）是共享 scanner，`#`（`:277`）与引号（`:292-306`）分支在 Doris 下是既有行为；一次「顺手统一」就可能漂移。
**How to avoid:** 每个 lexer 分支显式 `match context.dialect`，Doris 分支保持原字节路径；`moon test --package parity`（无 `--update`）对 213 个 Doris 快照做字节级门禁；任何 Doris 变更走 approved-changes.md 注册（D-08）。
**Warning signs:** Doris parity 快照 diff 出现非注册变更；`doris_classification_rows` 测试 `assert_eq(rows.length(), 116)` 失败。

### Pitfall 2: 用 Calcite/Doris folklore 替代 release fixture
**What goes wrong:** 手写「Flink 一定支持 X」或「`#` 一定是注释」——本 session 已证伪多个此类假设（`E'..'` 实际 1.34.0 也有、`B'..'` 实际无 BIT 字面量 token、`#` 实际非 Calcite 注释）。
**Why it happens:** 常识与 release 事实源脱节；Calcite 版本间词法行为有差异。
**How to avoid:** 每个词法条目（双引号、`#`、`//`、X/U&/B/E、运算符）都从钉住 release 的 `Parser.jj`/`Lex.java`/`Parser.tdd` 引逐字行并固化进 fixture（D-03）；fixture 是唯一事实源。
**Warning signs:** metadata/常量的 calcite 版本与 release POM 不一致；fixture 期望来自「我记得」。

### Pitfall 3: 依赖移动的 `dev`/`stable` 文档
**What goes wrong:** `dev`/`stable` 文档随时变化，calcite pin 或词法描述不可复现。
**Why it happens:** Validation 明文禁止 moving docs；release 归档不可变。
**How to avoid:** 只用钉住 release 的 `flink-*-src.tgz`（校验和匹配）+ archive.apache.org 目录清单；manifest 记录 URL + sha512 + tag/commit（SC2）。
**Warning signs:** 引用 URL 含 `docs/.../dev/` 或 `stable/`；校验和无来源。

### Pitfall 4: 关键字 union 泄漏（DIALECT-02）
**What goes wrong:** 把 Flink reserved 词并进 Doris 行表或反之，导致一方言的 identifier 接受受另一方言影响。
**Why it happens:** `classification_rows_for`（`dialect/classification.mbt:56-61`）按 `context.dialect` 选行，但若实现时把两表合并成单一数组或共享 mutable state，即泄漏。
**How to avoid:** 保持 `doris_classification_rows`/`flink_classification_rows` 为独立 module-level 数组（`classification.mbt` 现有结构）；测试断言 `classification_entries(flink).length() == 0` 在 Phase 10 改为按 release 断言行数。
**Warning signs:** `classification_of` 对另一方言的词返回 `Some(_)`；`is_reserved_word(flink, word)` 受 doris 行影响。

### Pitfall 5: profile metadata 半填充（SC2 未满足）
**What goes wrong:** `FlinkProfileMetadata` 的 `calcite_version`/`parser_config` 字段留空或填错（如 2.1.3 填成 1.36.0）。
**Why it happens:** pin 手写推断而非 release 提取；或只填了 2.3.0 忘记回归 profile。
**How to avoid:** D-02 提取脚本从 release POM 逐版本生成 metadata；测试断言三 profile 的 calcite_version == `1.36.0/1.34.0/1.32.0` 且 parser_config 相等（§8 矩阵）；未知 profile 走 `FATHOM-SCHEMA-003`。
**Warning signs:** `fathom.capabilities.v1` flink profiles 缺 calcite_version；2.1.3 pin 与 release POM 不一致。

### Pitfall 6: profile-id 形态混淆（`flink-2.3.0` vs doris `2.1`）
**What goes wrong:** 把 Doris 的 `2.1`/`3.x`/`4.x` 形态借给 Flink（或反之），CLI/LSP/JS 边界按错误形态校验。
**Why it happens:** 两方言 profile 形态不同（D-01 specifics 明文「不得互相借用」）；`validate_dialect_profile`（`binding/schema.mbt:40-51`）是唯一校验点，若只改 doris 分支则 flink 仍全拒。
**How to avoid:** flink 分支独立 `match profile { "flink-2.3.0" | "flink-2.1.3" | "flink-1.20.5" }`；`fathom-sql/args.mbt` 的 `is_valid_profile` 按 dialect 分支；CLI 测试覆盖 `--dialect flink --profile flink-2.3.0` 与 `--profile 2.1`（错误形态拒绝）。
**Warning signs:** `flink-2.3.0` 被当作 doris profile 拒绝；`2.1` 被 flink 接受。

### Pitfall 7: 快照门禁把 Flink 组并入 Doris 组导致注册表污染
**What goes wrong:** flink-lexical 快照与 Doris baseline 快照混在同一 fixture 命名空间，Doris 变更被 Flink fixture 掩盖或反之。
**Why it happens:** `__snapshot__/` 是共享目录；若新 fixture 命名与 Doris 重叠或 approved-changes.md 条目混淆。
**How to avoid:** D-04 独立 flink-lexical 命名（`flink-lexical.{fixture}.{profile}.{mode}.json`）；Doris 组命名不变；baseline_diff.py 按组分别 diff。
**Warning signs:** Doris 快照 diff 条目被标注为「flink 变更」；`moon test --update` 误更新 Doris 组。

## Code Examples

### 1. `KeywordEntry` 结构（`dialect/classification.mbt:24-32`，flink 行表复用同一结构）

```moonbit
pub struct KeywordEntry {
  pub word : Bytes
  pub classification : ClassificationKind
  pub introduced_profile : String
  pub source : String
} derive(Eq, @debug.Debug)
```
`[VERIFIED: /opt/source/Fathom/dialect/classification.mbt:24-32 — 上述逐字]`

### 2. `ProfileMetadata` 模式（`dialect/doris.mbt:15-22`，FlinkProfileMetadata 同构蓝本）

```moonbit
pub struct ProfileMetadata {
  pub id : String
  pub release_family : String
  pub exact_release : String
  pub feature_introduction : String
  // Kept as the compact, parser-facing label for existing consumers.
  pub introduced_features : String
}
```
`[VERIFIED: /opt/source/Fathom/dialect/doris.mbt:15-22 — 上述逐字]`

### 3. `DorisProfile::metadata()` 形态（`dialect/doris.mbt:113-127`，FlinkProfile 的 `calcite_version`/`parser_config` 按此逐变体返回）

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
    ...
  }
}
```
`[VERIFIED: /opt/source/Fathom/dialect/doris.mbt:113-120 — 上述逐字]`

### 4. Flink 配置构造（`src/flink-{v}/.../PlannerContext.java:256-260`，metadata 的 parser_config 事实源）

```java
return SqlParser.config()
        .withParserFactory(FlinkSqlParserFactories.create(conformance))
        .withConformance(conformance)
        .withLex(Lex.JAVA)
        .withIdentifierMaxLength(256);
```
`[VERIFIED: /tmp/flink-research/src/flink-2.3.0/flink-table/flink-table-planner/src/main/java/org/apache/flink/table/planner/delegation/PlannerContext.java:256-260 — 上述逐字]`

### 5. 快照测试模式（`parity/baseline_test.mbt`，flink-lexical 组复用）

```moonbit
// parity/baseline_test.mbt 现用 @test.T::snapshot(filename=...) 冻结每个 fixture×profile×mode
// 组合的序列化输出（D-07/D-08）；`moon test --update --package parity` 生成，
// `moon test --package parity` 无 --update 时字节级失败。
// flink-lexical 组：同机制，新 fixture 命名 flink-lexical.{fixture}.{profile}.{mode}.json
```
`[VERIFIED: /opt/source/Fathom/parity/baseline_test.mbt:1-33 — 文件头注释描述快照门禁机制；`parity/__snapshot__/` 213 个快照文件（2.1-boundary-empty.2.1.strict.json 等形态）]`

### 6. `validate_dialect_profile` 现状（`binding/schema.mbt:40-51`，Phase 10 解锁点）

```moonbit
pub fn validate_dialect_profile(dialect : String, profile : String) -> Result[Unit, SchemaError] {
  match dialect {
    "doris" => match profile {
      "2.1" | "3.x" | "4.x" => Ok(())
      _ => Err(UnsupportedProfile(profile~))
    }
    "flink" => Err(UnsupportedProfile(profile~))
    _ => Err(UnknownDialect(dialect~))
  }
}
```
`[VERIFIED: /opt/source/Fathom/binding/schema.mbt:40-51 — 上述逐字]`

## Open Questions (RESOLVED)

1. **`FlinkProfileMetadata` 的精确字段形态与 wire 序列化（D-01 的 parser_config/calcite_version 承载）**
   - What we know: D-01 要求 id/release_family/exact_release/calcite_version/parser_config/feature_introduction；`fathom.dialect.v1`/`fathom.capabilities.v1`（`binding/schema.mbt:169-211,213-246`）现 flink profiles 为 `[]`；SC2 要求 profile 报告 release source/tag/commit、Calcite 版本、parser 配置。
   - What's unclear: `parser_config` 的序列化形态（字符串快照 vs 结构化字段）；tag/commit/sha512 是否进 wire metadata 或只进 manifest。
   - Recommendation: metadata 携带 calcite_version + 紧凑 parser_config 字符串（如 `"Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT"`）；tag/commit/sha512 放 parity fixture manifest 而非 wire 字段（wire 只暴露消费方需要的事实）。**RESOLVED:** planner 采用「metadata 字段进 wire + manifest 承载完整 provenance」——具体字段名由 planner 按 §7 表定稿。
2. **lexer 方言分支的实现粒度（`#`/`//`/引号/字面量前缀的开关位置）**
   - What we know: `lex_with_limit`（`lexer/lexer.mbt:250`）已携带 `context`；`#`/`//`/引号分支在 `:277-306`。
   - What's unclear: 是 `match context.dialect` 内联分支，还是抽 `FlinkLexPolicy` 数据源（`dialect/flink.mbt` 提供布尔开关）。
   - Recommendation: 最小改动 = 扫描分支 `if context.dialect is Flink { ... }`，策略常量放 `dialect/flink.mbt`（DIALECT-02 policy authority）；避免在 lexer 内散落方言字符串比较。**RESOLVED:** 分支在 lexer、policy 数据源在 `dialect/flink.mbt`，由 planner 拆任务。
3. **`flink_classification_rows` 的规模与 source 列取值**
   - What we know: 三 release reserved 合计 443/430/412 词；Doris 行表 116 行（含 `source` 官方文档 URL）。
   - What's unclear: Phase 10 是填全部 reserved 词（约 440 行/版本）还是只填 parser 实际消费的 production 词（D-13 纪律：parser 用词须有行）；`source` 列对 Flink 用 release grammar 引用而非 docs URL。
   - Recommendation: 按 D-13/D-16 纪律，填 parser/lexer 实际消费 + 冲突矩阵需要的词；source 用「release grammar 路径 + token 行号」如 `flink-sql-parser codegen/templates/Parser.jj:8640 (VARIANT)`。**RESOLVED:** 全量 reserved 清单作 manifest 附件，行表填 production 词 + 冲突词（约 120-180 行），由 planner 按 fixture 集定稿。
4. **`E'..'` 版本可用性（原记录需修正）**
   - What we know: `C_STYLE_ESCAPED_STRING_LITERAL` 在 Calcite 1.36.0（`Parser-calcite-1.36.0.jj:8721`）与 **1.34.0**（`:8469`）均存在，**1.32.0 无**。
   - What's unclear: 无（已核验）。
   - Recommendation: flink-2.3.0 与 flink-2.1.3 profile 支持 `E'..'`，flink-1.20.5 不支持；fixture 断言三版本差异。**RESOLVED**（修正先前「1.36.0 独有」说法）。
5. **`#` 与双引号在 Flink 下的确切 token 化**
   - What we know: `#` 无 token → lexical error（`Parser-calcite-1.36.0.jj:500` 注释佐证）；`"` 是 `DOUBLE_QUOTE` symbol 且 DEFAULT 状态无消费 production → parse error；Doris 下 `#` 是注释、`"` 是 Quoted。
   - What's unclear: 无（token 层面已核验）；最终以 fixture 快照固化「输入 → 期望诊断/token 序列」。
   - Recommendation: 冲突矩阵快照覆盖 `#` 与 `"x"` 在双方言下的不同结果（D-06）。**RESOLVED**（Research flags 已核验）。

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `moon`/`moonc` | 核心构建/测试/快照 | ✓ | moon 0.1.20260724 (5f1406a 2026-07-24) | CI 安装 `latest` 并记录版本 |
| Python 3 | release 提取/清单/fixture 校验脚本（stdlib） | ✓ | 3.9.23 | — |
| git | release tag→commit 审计（`git ls-remote https://github.com/apache/flink.git`） | ✓ | 2.47.3 | 归档文件内 version 属性 + archive 目录清单 |
| Node.js | 既有 web/vscode 构建 | ✓ | v25.2.0 | — |
| Flink release 归档（研究 fixture） | Calcite pin/parser 配置/词法提取 | ✓（本 session 已校验和复核） | `/tmp/flink-research/src/flink-{2.3.0,2.1.3,1.20.5}/`（约 727MB）+ `flink-*-src.tgz` + `.sha512` | 重新下载（URL 已记录）+ 校验和比对 |
| archive.apache.org 目录清单 | release 日期审计 | ✓ | 2026-06-14 / 2026-06-08 等（本 session 读取） | 离线时以 tag 日期近似（标注） |

**Missing dependencies with no fallback:** none（本阶段全部依赖可用；release 归档已缓存且校验和匹配）。
**Missing dependencies with fallback:** Flink/Calcite runtime（Validation 禁用的运行时）— 用 grammar/配置 fixture 替代，不引入。

## Validation Architecture

> **SKIPPED** — `.planning/config.json` `"workflow": { "nyquist_validation": false }`。验证架构（Test Framework / Phase Requirements → Test Map / Sampling Rate / Wave 0 Gaps）按配置豁免。本阶段验证策略以 §Architecture Patterns Pattern 4（parity/ flink-lexical 快照门禁 + approved-changes.md 注册 + baseline_diff.py diff）与 SC1-SC3 冲突矩阵快照取代；测试仍沿用仓库既有 `moon test --target native --package parity ...` 矩阵（`ci.yml`）。

## Security Domain

> `security_enforcement: true`（`.planning/config.json` `"workflow": { "security_enforcement": true }`）——本阶段无网络/凭据，但 Flink profile 接受与词法错误接受是新的攻击面（错误方言/词法接受 = 错误有效性判定）。

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | 无认证面（纯前端库 + stdio LSP） |
| V3 Session Management | no | 无会话；LSP document version 单调性沿用 Phase 9 |
| V4 Access Control | no | 无资源/角色 |
| V5 Input Validation | **yes** | dialect/profile 闭合枚举（`FlinkProfile::V2_3_0|V2_1_3|V1_20_5`）+ `validate_dialect_profile` 结构化拒绝（FATHOM-SCHEMA-003/007）；词法输入按 dialect 分支（未知字符 → 显式错误而非静默接受） |
| V6 Cryptography | no | 无加密需求；release 归档 SHA-512 属完整性校验而非加密 |

### Known Threat Patterns for {stack}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Flink profile 字符串注入：攻击者传 `flink-2.3.0; DROP...` 诱导错误 profile 接受 | Tampering | 闭合 `FlinkProfile` 枚举 + `from_id` 精确匹配（`flink-2.3.0`/`flink-2.1.3`/`flink-1.20.5`），未知 → UnknownProfile；结果携带实际 selection metadata（DIALECT-04） |
| 词法方言混淆：`#`/`"`/`//` 在错误方言下被接受为注释/标识符造成错误有效性判定 | Tampering | lexer 按 `context.dialect` 分支（Flink 下 `#` 是 lexical error、`"` 是 symbol）；冲突矩阵快照固化每路径期望 |
| 关键字 union 泄漏：Flink 词影响 Doris 接受或反之 | Tampering | 独立行表（`classification.mbt` 结构）+ 行数断言（Doris 116 / Flink 按 release）；无共享 mutable state |
| release provenance 伪造：metadata 声称的 Calcite 版本与实际不符 | Tampering | D-02 从钉住 release POM 提取 + parity fixture manifest 记录 URL/sha512/tag/commit；校验和不匹配即拒绝 |

## Sources

### Primary (HIGH confidence — 本 session 直接读取/核验)

**外部 release 事实（/tmp/flink-research/ 缓存，全部本 session 复核）：**
- `src/flink-{2.3.0,2.1.3,1.20.5}/flink-table/pom.xml:81` — `<calcite.version>1.36.0|1.34.0|1.32.0</calcite.version>`
- `src/flink-{v}/flink-table/flink-sql-parser/pom.xml:59-68` — vanilla `org.apache.calcite:calcite-core:${calcite.version}` 依赖
- `src/flink-{v}/flink-table/flink-table-planner/src/main/java/org/apache/flink/table/planner/delegation/PlannerContext.java:252-260` — parser 配置（Lex.JAVA + identifierMaxLength 256）
- `src/flink-{v}/flink-table/flink-sql-parser/src/main/java/org/apache/flink/sql/parser/validate/FlinkSqlConformance.java:31-38,56-63,86-93` — conformance flags
- `src/flink-{2.3.0,2.1.3}/flink-table/flink-sql-parser/src/main/codegen/templates/Parser.jj:8640/8374` — VARIANT token
- `Parser-calcite-{1.36.0,1.34.0,1.32.0}.jj` — 注释/引号/字面量/运算符/标识符 token（`BINARY_STRING_LITERAL:8708`、`UNICODE_STRING_LITERAL:8719`、`C_STYLE_ESCAPED_STRING_LITERAL:8721/8469/无`、`SINGLE_LINE_COMMENT:8901`、`BTID:8951-8962`、`DOUBLE_QUOTE:8797`、运算符 `:8790-8800`）
- `Lex-1.36.0.java:77-79` — Lex.JAVA 定义（BACK_TICK/UNCHANGED/UNCHANGED/true）
- `SqlParser-calcite-{1.36.0,1.34.0,1.32.0}.java:52,278-306` — SqlParser.Config 默认值
- `Parser-release-{2.3.0,2.1.3,1.20.5}.tdd` — keywords/nonReservedKeywords/binaryOperatorsTokens/includePosixOperators
- `flink-{2.3.0,2.1.3,1.20.5}-{reserved,nonreserved}.txt` — 关键字清单（443/334、430/324、412/323）
- `flink-{v}-src.tgz.sha512` + 本 session `sha512sum -c` 全部 OK
- `git ls-remote https://github.com/apache/flink.git`（2026-08-07）— release-2.3.0→`c0f8d1a1...`、release-2.1.3→`6cda56b0...`、release-1.20.5→`09804850...`
- archive.apache.org 目录清单（2026-08-07）— 归档日期 2026-06-14 / 2026-06-08

**In-repo（`[VERIFIED: 路径:行]`）：**
- `dialect/dialect.mbt:12-24` — Dialect/DialectContext
- `dialect/flink.mbt:11,17` — `FlinkProfile {}` 占位 / `flink_classification_rows = []`
- `dialect/classification.mbt:24-32,56-72` — KeywordEntry / classification_rows_for / classification_of
- `dialect/doris.mbt:14-22,113-127,275-462` — DorisProfile/ProfileMetadata/metadata()/116 行行表
- `api/api.mbt:71-100,162` — dialect_from_id / ParseOptions::new（Flink 全拒）/ Flink 分支
- `binding/schema.mbt:40-51,138-150,169-246` — validate_dialect_profile / code 映射 / dialect_json+capabilities_json
- `lexer/lexer.mbt:137-152,250,277-306` — context 传参 / lex_with_limit / `#`/引号分支
- `parity/baseline_test.mbt:1-33`、`parity/__snapshot__/`（213 文件）— 快照门禁
- `scripts/baseline_diff.py`、`corpus/tools/check_keywords.py` — diff/校验工具模式
- `.planning/config.json` — nyquist_validation=false、security_enforcement=true

### Secondary (MEDIUM confidence)
- [archive.apache.org/dist/flink/flink-2.3.0/](https://archive.apache.org/dist/flink/flink-2.3.0/)（及 2.1.3/1.20.5）— release 归档日期目录清单（`[CITED]`）
- [github.com/apache/flink](https://github.com/apache/flink) — release tag refs（`[VERIFIED]` via `git ls-remote`）

### Tertiary (LOW confidence / validation required)
- §Open Questions 中标记 RESOLVED 的 planner 决策（FlinkProfileMetadata 字段形态、行表规模、parser_config 序列化）——需 planner/plan-check 确认
- Flink/Calcite 真实 runtime 的词法细节（Validation 禁用运行时，行为以 grammar fixture 为准）

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — 零新增外部包；release 归档是研究 fixture；提取工具 Python stdlib 与既有 `check_keywords.py` 同模式
- Architecture: HIGH — FlinkProfile/FlinkProfileMetadata/validate 解锁/lexer 分支/快照组全部有现状代码行号与 release 证据支撑；§7-§10 每表逐字引用
- Pitfalls: HIGH — 7 条陷阱每条都有定义点/调用点/release 证据；Doris 回归严重度由 parity 快照门禁量化

**Research date:** 2026-08-07
**Valid until:** 2026-09-06（release 归档不可变；若 Apache 变更归档布局或 Flink 发布新 release 需重核 pin）

---
*Phase: 10-Flink Release Profiles and Lexical Core*
*Research completed: 2026-08-07*
