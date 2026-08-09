# Phase 12: Cross-Dialect Corpus and Parity Gates - Research

**Researched:** 2026-08-09
**Domain:** 跨方言（Doris 2.1/3.x/4.x + Flink 2.3.0/2.1.3/1.20.5）corpus manifest、frozen baseline diff harness、跨后端（Native/JS/linear-Wasm）字节级 parity、离线门禁与 parser-接受 vs 引擎-语义 区分
**Confidence:** HIGH（现状 inventory 全部由本 session 磁盘测量 + 逐字引用；三目标 570/570 parity 实测通过）；MEDIUM（6 类分类的具体 fixture 归属是设计裁决，见 Assumptions Log；统一 manifest 目录落点由 planner 定稿）

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Flink corpus manifest 采用统一 release-pinned 格式：每个 fixture 记录 release/tag/commit、Calcite 版本/config、来源 URL/文档标题、检索日期、hash、期望状态，以及 6 类分类（positive / negative / recovery / known-limitation / catalog-prerequisite / planner-prerequisite）。分类语义在 fixture 层面固化：**generic SQL 被解析器接受 ≠ Flink 引擎支持** — 一个 SQL 即使语法可解析，若依赖 catalog/planner/引擎语义仍按其前置分类标注，绝不把语法接受报告为引擎支持（research flags 明文）。**Reversibility:** costly — manifest 是公共审计契约，字段语义变更需全量重标。
- **D-02:** 现有 flink-lexical（Phase 10）与 flink-grammar（Phase 11）fixture/快照迁入统一 corpus 结构，按 6 类重新归类；不丢任何现有 fixture。**Reversibility:** reversible。

### Doris 冻结 Diff Harness（PARITY-01）
- **D-03:** 复用 Phase 9 的 baseline 门禁（D-07/D-08：213 快照 + approved-changes 注册表 + baseline_diff），形式化为显式 diff harness：任何共享/方言改造后输出「冻结 vs 当前」差异报告；故意变更须经注册表批准流，docs-vs-parser 冲突显式可见，绝不静默批量更新快照。**Reversibility:** reversible — harness 可增补，但一旦 CI 接线即成为契约。
- **D-04:** PARITY-01 覆盖 Doris 2.1/3.x/4.x 的 valid/invalid/recovery/CST/span/diagnostic/formatter/completion 全部既有快照面；Phase 10/11 的 flink 改造不得引入未记录 Doris 变更（已由零漂移保证，本阶段形式化验证）。**Reversibility:** one-way — 冻结 baseline 是 Phase 9 起确立的公共契约。

### 跨后端 Parity（PARITY-02）
- **D-05:** 同一 fixture 集在 Native/JS/linear-Wasm 三目标上序列化结果、诊断、span、lossless replay 字节级一致；CI 增加三目标矩阵并比对字节。**Reversibility:** one-way — 跨后端字节一致性是 SDK 核心承诺，任何后端偏差都是契约破坏。

### 离线门禁与语义区分（PARITY-03）
- **D-06:** 离线 manifest/hash 验证器（纯本地，无网络/Doris-FE/Flink-cluster/DB 运行时访问）；release 钉住工件（归档 + 校验和）为唯一事实源，禁移动 docs。覆盖报告区分 parser 接受 vs catalog/planner/引擎语义前置，双方言同制。**Reversibility:** one-way — CI 门禁形态是发布契约。

### 冲突可见性
- **D-07:** docs/source/Calcite 三方冲突（fixture 期望 vs 实现 vs release 事实）显式报告 + 人工裁决入口；任何「更新快照以匹配实现」的批量动作须经注册表批准并记录理由。**Reversibility:** reversible。

### Claude's Discretion
（未出现 "you decide"；所有灰区由既有决策链 + 本阶段 D-01..D-07 明确覆盖。）

### Deferred Ideas (OUT OF SCOPE)
- Flink 工具链（format/completion/analyzer 方言分发）→ Phase 13（TOOL-01..03）
- 新 Flink grammar/词法能力 → 不在 Phase 12（Phase 10/11 已完成语法面）
- planner/执行等价、catalog 注入的语义解析 → 不在 v2.0 SDK 范围
- 自动方言检测（即使 opt-in）→ 未来阶段
- 显式跨方言转换（transpile）→ CONVERT-FUTURE-01
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CORPUS-01 | Maintainer can inspect a release-pinned Flink corpus whose manifest records release/tag/commit, Calcite version/config, URL, heading, retrieval date, hash, expected status, and categories for positive, negative, recovery, known limitation, catalog prerequisite, and planner prerequisite cases. | §5 统一 manifest schema（flink-grammar manifest 97 行已含 release/tag/commit/Calcite/config/url/sha512；缺 retrieval_date/source_url/heading/category/expected_status 五列 → §5.2 补列）；§5.3 6 类分类语义 + §5.4 现有 97+13 fixture 映射表；§5.5 离线 hash 验证器 |
| PARITY-01 | Doris 2.1, 3.x, and 4.x valid/invalid/recovery/CST/span/diagnostic/formatter/completion behavior remains equal to a frozen baseline after dialect and naming refactors, unless an intentional change is explicitly recorded. | §6 frozen diff harness：213 快照（§4.2 全量盘点）+ `scripts/baseline_diff.py`（approved-vs-unexpected 引擎）+ 三份 approved-changes 注册表；「冻结 vs 当前」报告设计 + 批准流 + docs-vs-parser 冲突可见（D-03/D-04/D-07） |
| PARITY-02 | The same fixture produces byte-identical serialized results, diagnostics, spans, and lossless replay across Native, JavaScript, and linear-Wasm targets. | §7 跨后端 parity：MoonBit `@test.T::snapshot` 已是跨目标字节门禁（native/js/wasm 三目标 570/570 实测通过，§4.2）；补 `scripts/compare_backends.py` + CI js 运行时 job（现状 CI 只跑 native+wasm，§4.5） |
| PARITY-03 | CI and release checks run from pinned offline artifacts without Doris FE, Flink cluster, database, or network access, and coverage reports distinguish parser acceptance from engine semantic support across both dialects. | §8 离线门禁：`scripts/verify_corpus.py`（纯 stdlib，只读 pinned 归档/manifest，无网络）；§8.3 语义区分覆盖报告（复用 `corpus/tools/generate_corpus_report.py` 模式 + 6 类分类）；generic-acceptance ≠ engine-support 规则（D-01/D-06） |
</phase_requirements>

## Summary

Phase 12 把 Phase 9（Doris baseline 冻结 + approved-changes 注册表）、Phase 10（flink-lexical manifest + Calcite pin 提取）、Phase 11（flink-grammar fixtures + 生产行号溯源）已经建好的分散门禁整合为可审计的跨方言覆盖与 parity 契约。本 session 对磁盘现状做了全量盘点（§4）：**parity 包共 570 个测试、433 个快照文件** —— Doris baseline 213（44 fixture × parse 双模式 = 88，+ format 35 + cli 35 + lsp 27 + completion 27 + cross-target 1）、flink-lexical 26（13 fixture × 双模式）、flink-grammar 194（97 fixture × 双模式）；`moon test --package parity` 在 **native / js / wasm 三目标均为 570/570 通过**（本 session 实测）。已有三个 Python stdlib 脚本（`baseline_diff.py` / `extract_flink_lexical.py` / `extract_flink_grammar.py`）与两份 per-fixture manifest（flink-lexical 4 行 release 级、flink-grammar 97 行 fixture 级）。

核心发现：**(1)** 跨后端字节一致在机制上已被 MoonBit 官方 snapshot 机制保证（同一 committed 快照文件被三目标逐一比对），缺的是 CI 的 JS 运行时 job 与一个显式 `compare_backends.py` 报告工具；(2) `baseline_diff.py` 已是 approved-vs-unexpected diff 引擎（§6.3 逐字核验），「冻结 vs 当前」harness 只需把「当前」树生成出来（copy + `moon test --update` 到 temp）+ 已注册表比对；(3) 统一 manifest 缺 5 列（retrieval_date / source_url / heading / category / expected_status）——flink-grammar manifest 现有列已覆盖 release/tag/commit/Calcite/config/url/sha512，flink-lexical manifest 是 release 级而非 fixture 级，需按 fixture 展开；(4) 现有 4 类（positive/negative/incomplete/recovery）到 6 类的映射是核心语义裁决，关键规则是 **generic SQL 接受 ≠ Flink 引擎支持**：所有 Window TVF 与 MATCH_RECOGNIZE fixture 语法可解析但执行依赖 planner，应标 planner-prerequisite；CREATE FUNCTION/CATALOG class 字符串解析依赖 catalog/registry，应标 catalog-prerequisite；SUBSET/PERMUTE/{- -}/负 offset 是已知子集缺口，应标 known-limitation。

**Primary recommendation:** 按「统一 manifest + 6 类重标（§5）→ frozen diff harness 形式化（§6）→ compare_backends.py + CI js job（§7）→ verify_corpus.py 离线门禁 + 语义覆盖报告（§8）→ 冲突可见流（§9）」实施；不新增任何外部运行时依赖，全部工具为 Python stdlib；reuse `/tmp/flink-research/` 作为 release 证据（本 session 确认存在：3 个 `flink-*-src.tgz` + sha512 + 解包树 + 3 个生成版 `Parser-calcite-*.jj`）。

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| 统一 Flink corpus manifest（release-pinned 字段 + 6 类分类） | `parity/fixtures/flink/`（或 `corpus/flink/`，planner 定稿）— 数据目录 | `scripts/verify_corpus.py` — 校验 | manifest 是公共审计契约（D-01 one-way）；数据与校验分离，数据只读 |
| 6 类分类语义权威（positive/negative/recovery/known-limitation/catalog/planner-prerequisite） | manifest `category` 列 + `corpus/flink-coverage.tsv` | `scripts/verify_corpus.py` 枚举校验 + 覆盖报告 | 分类是 fixture 层面固化的事实（D-01）；generic-acceptance ≠ engine-support 规则编码进枚举与报告 |
| Doris frozen baseline diff harness | `scripts/baseline_diff.py`（复用）+ 新 `scripts/diff_parity.py`（or 扩展） | `parity/__snapshot__/` + 各阶段 `approved-changes.md` | D-03：approved-vs-unexpected 引擎已存在；补「冻结 vs 当前」报告生成与 CI 接线 |
| 跨后端字节 parity（Native/JS/linear-Wasm） | `parity/`（`@test.T::snapshot` 跨目标门禁）+ `parity/moon.pkg` targets | CI（新增 js 运行时 job）+ 新 `scripts/compare_backends.py` | D-05：快照文件是跨目标比对物；CI 矩阵 + 报告工具补缺口 |
| 离线 manifest/hash 验证器 | 新 `scripts/verify_corpus.py`（stdlib only） | `/tmp/flink-research/`（release 证据，非 ship） | D-06：纯本地，无网络/FE/cluster/DB；pinned 工件为唯一事实源 |
| 语义区分覆盖报告（parser 接受 vs 引擎前置） | `corpus/tools/generate_corpus_report.py`（扩展双方言）+ `corpus/flink-coverage.tsv` | CI `corpus` job | 复用现有报告模式；禁止把 catalog/planner-prerequisite 报为 engine support（D-01/D-06） |
| docs/source/Calcite 冲突可见 + 人工裁决 | 各阶段 `approved-changes.md` 注册表 + manifest `expected_status`/`known-limitation` | `baseline_diff.py` 报告 + CI 门禁 | D-07：任何「更新快照匹配实现」的批量动作须注册批准并记录理由 |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| MoonBit toolchain (`moon`, `moonc`) | `moon 0.1.20260724 (5f1406a 2026-07-24)`（本 session `moon version` 实测） | 快照门禁、三目标测试、`@test.T::snapshot` | 唯一实现语言；本阶段零新增运行时依赖（全部改动为 parity/ 测试 + scripts/ 工具 + CI） |
| `moonbitlang/core` | 既有锁定（`moon test` 通过） | String/Bytes/JSON/utf8/debug/test | 项目约束：core 是 parser 唯一必需运行时依赖 |
| `@test.T::snapshot` | 官方快照机制（`__snapshot__/` + `moon test --update`） | 跨后端字节门禁 + 冻结快照 | 已三目标验证（native/js/wasm 570/570）；PARITY-02 直接复用 |
| Python 3 stdlib（本机 3.9.23） | — | `verify_corpus.py` / `compare_backends.py` / 扩展 `baseline_diff.py` / `extract_flink_*.py` / `generate_corpus_report.py` | 全部 gate 脚本 stdlib only，零 CI 依赖（沿用 `corpus/tools/check_keywords.py` 的 problems-list + `ok:` 模式） |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `sha256sum` / `sha512sum` | coreutils | fixture/归档校验和（`parity/baseline-hashes.txt` 现有模式） | verify_corpus.py 的 hash 校验后端 |
| `/tmp/flink-research/` release 证据 | 2026-08-07 会话缓存（本 session 确认存在） | 三 release 归档 + 生成版 Parser.jj 逐字核验 | 离线验证器的 release-pinned 事实源（研究 fixture，不 ship） |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| 统一 manifest 放 `parity/fixtures/flink/` | `corpus/flink/` 独立目录 | 两条路都可行；CONTEXT code_context 指向 `parity/` 统一结构（D-02「迁入统一 corpus 结构」），且 corpus/ 现为 Doris 专有 provenance 语义（NAME-03）；planner 定稿 |
| `compare_backends.py` 跑三目标 + 汇总 | 只补 CI 三个 `moon test` job | 显式脚本能产出 per-fixture/per-target 报告并校验快照树 digest，CI job 只给 pass/fail；报告是维护者审计入口（SC1） |
| 提交 fixture `.sql` 文件 + manifest `fixture_sha256` | 只 pin 归档 sha512 | D-01 要求每 fixture 有 hash；不提交 `.sql` 文件则 verifier 无法 stdlib 校验嵌入字节（MoonBit 源码难解析）。提交 `.sql` 沿袭 `corpus/doris-*/` + `baseline-hashes.txt` 既有模式（D-08 embedded-raw provenance） |
| `verify_corpus.py` 单脚本 | 拆 `verify_manifest.py` + `verify_hashes.py` | 单一入口 + `--check` 模式更贴近现有 `generate_corpus_report.py --check`；拆开增加 CI 维护面 |

**Installation:**
```bash
# 本阶段不安装任何新外部包。既有依赖已锁定（moonbitlang/core）；工具为 Python stdlib。
```

**Version verification:** 本阶段零新增 npm/pypi/crates 依赖；`moon 0.1.20260724`、Python 3.9.23、node v25.2.0（`/root/.nvm` 路径）均为本机探测。parity 套件三目标 570/570 实测通过。

## Package Legitimacy Audit

> 本阶段不安装任何外部包（约束：核心 parser 只用 `moonbitlang/core`；gate/提取/对比工具为 Python stdlib）。因此无需运行 package-legitimacy seam；下表为显式确认。

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| （无新增包） | — | — | — | — | — | N/A — 零外部依赖 |

**Packages removed due to [SLOP] verdict:** none（无候选包）
**Packages flagged as suspicious [SUS]:** none（无候选包）

## Current-State Inventory（现状盘点）

> 全部计数为 2026-08-09 本 session 磁盘实测（`ls`/`wc -l`/`moon test`）。快照文件名分组：Doris baseline 以 `{profile}.{fixture}` 或 `{fixture}.{profile}.{mode}.json` 命名；flink-lexical 以 `flink-lexical.{fixture}.{profile}.{mode}.json`；flink-grammar 以 `flink-grammar.{fixture}.flink-2.3.0.{mode}.json`。

### 4.1 parity/ 包文件与测试面

| 文件 | 大小/行数 | 测试块 | 作用 |
|------|-----------|--------|------|
| `parity/baseline_test.mbt` | 66.0KB / 1443 行 | 213 | D-07/D-08 Doris 全量冻结快照（44 fixture × 双模式 parse + cli/format/completion/lsp homomorph） |
| `parity/flink_grammar_test.mbt` | 130.2KB / 2603 行 | 310 | D-05 flink-grammar 快照 + 双向方言负门禁（`flink_grammar_bidirectional`，`[VERIFIED: parity/flink_grammar_test.mbt:817-820]`）+ lossless 断言 |
| `parity/flink_lexical_test.mbt` | 20.6KB / 409 行 | 32 | D-04 flink-lexical 冲突矩阵（双引号/`#`/`//`/E-literal/backtick/unknown-profile） |
| `parity/parity_test.mbt` | 5.7KB | 4 | 跨目标 ABI 回归（fixture `parity/fixtures/corpus.json`） |
| `parity/schema_test.mbt` / `coordinates_test.mbt` / `export_smoke_test.mbt` | 4.0/2.4/7.4KB | 3/4/4 | schema 信封 / 坐标 / export 面 |
| `parity/run_native.mbt` / `run_js.mbt` / `run_wasm.mbt` | 346/342/420B | — | 三目标 smoke runner（target-scoped，`parity/moon.pkg` targets 块 `[VERIFIED: parity/moon.pkg:15-20]`） |
| `parity/baseline-hashes.txt` | 3.3KB | — | 44 corpus 文件 SHA-256 pin（T-09-03，`sha256sum -c`） |
| `parity/moon.pkg` | 482B | — | `pkgtype(kind: "executable")` + 8 个 import + test import + targets 块 |

**实测：** `moon test --package parity` → `Total tests: 570, passed: 570, failed: 0`（native）；`--target js` 与 `--target wasm` 同样 570/570。⚠️ 三目标均输出一条 blackbox-only 警告（未来 `moon` 版本 main package 将停止生成黑盒测试）——记录为已知边界，非本次阻塞。

### 4.2 快照文件盘点（`parity/__snapshot__/`，共 433）

| 组 | 计数 | 构成 |
|----|------|------|
| **Doris baseline** | **213** | parse 双模式 88（44 fixture × {strict,editor}）+ format 35 + cli 35 + lsp 27 + completion 27 + cross-target 1 |
| — 2.1 组 | 60 | parse 13×2 + format 10 + cli 10 + lsp 7 + completion 7（`[VERIFIED: 本 session ls | sed 提取末段]`） |
| — 3.x 组 | 60 | parse 13×2 + format 10 + cli 10 + lsp 7 + completion 7 |
| — 4.x 组 | 92 | parse 18×2 + format 15 + cli 15 + lsp 13 + completion 13 |
| — cross-target | 1 | `cross-target.4.x-industrial.strict.json`（任一 target 写入，其余 target 必须字节复现，`[VERIFIED: parity/baseline_test.mbt:18-22]` 注释） |
| **flink-lexical** | **26** | 13 fixture × 2 模式（hash-comment 2、double-quote 2、slash-comment 2、e-literal 4、backtick-escape 2、unknown-profile 1 → 各 ×2） |
| **flink-grammar** | **194** | 97 fixture × 2 模式（全部 flink-2.3.0） |

**Doris 快照类型细分（文件名末段提取，`[VERIFIED: 本 session ls | sed -E 's/.*\.([a-z]+)\.json$/\1/']`）：** parse strict 44（2.1:13 + 3.x:13 + 4.x:18）、parse editor 44（同）、format 35（10+10+15）、cli 35（10+10+15）、lsp 27（7+7+13）、completion 27（7+7+13）= 212 + cross-target 1 = **213**。

### 4.3 fixture 数据与 manifest

| 数据源 | 行数/文件数 | 说明 |
|--------|-------------|------|
| `parity/fixtures/flink-grammar/manifest.tsv` | 98 行（1 header + **97 fixture 行**） | per-fixture release-pinned provenance + `grammar_path`/`line_range`（生产行号溯源） |
| `parity/fixtures/flink-lexical/manifest.tsv` | 5 行（1 header + **4 行**：3 flink release + 1 doris-4.x） | **release 级** provenance（非 per-fixture） |
| `parity/fixtures/flink-lexical/*-{reserved,nonreserved}.txt` | 6 文件 | 三 release 全量关键字清单（443/334、430/324、412/323） |
| `parity/fixtures/corpus.json` / `target-matrix.json` / `lsp-tracer.json` | 3 文件 | ABI 用例 / 三目标矩阵元数据 / LSP tracer fixture |
| `corpus/manifest.tsv` | 45 行（1 header + **44 数据行**） | Doris 官方文档语料 manifest（含 `retrieval_date`/`page_heading`/`code_fence`/`category`/`support_status`/`provenance_status` 列，`[VERIFIED: corpus/manifest.tsv:1]`） |
| `corpus/doris-{2.1,3.x,4.x}/*.sql` | 31 文件 | 8 + 8 + 15 |
| `corpus/keywords.tsv` / `coverage.tsv` / `differential.tsv` | 3 文件 | 关键字分类 / 覆盖矩阵 / 差分观察 |

**flink-grammar 现有 4 类分布（测试文件 `category` 字段，`[VERIFIED: parity/flink_grammar_test.mbt:23-27 结构 + 本 session grep]`）：** positive 62、negative 18、incomplete 12、recovery 5 = **97**。**缺失**的语义维度：catalog-prerequisite、planner-prerequisite、known-limitation（后三者目前只在 manifest `grammar_path` 注释里以「known-limitation (structural)」字样存在，不是结构化字段）。

**flink-lexical fixture 结构：** `FlinkLexicalFixture { fixture_id; dialect; profile; raw }`（`[VERIFIED: parity/flink_lexical_test.mbt:30-34]`）——**没有 category 字段**，13 个 fixture 条目中 6 个 doris-4.x、5 个 flink-2.3.0、1 个 flink-2.1.3、1 个 flink-1.20.5。

### 4.4 scripts/ 工具

| 脚本 | 行数 | 作用 | 状态 |
|------|------|------|------|
| `scripts/baseline_diff.py` | 270 | D-08 快照 shape-diff：左/右目录 + `--approve` 注册表 → approved vs unexpected；exit 0/1/2。`[VERIFIED: scripts/baseline_diff.py:1-17,44-63,182-270]` | 现役；CI parity-gate 自比对（left==right） |
| `scripts/extract_flink_lexical.py` | 602 | D-02 Calcite pin + parser-config + 关键字行表 + manifest sha512 复验（`/tmp/flink-research` 存在时）。`[VERIFIED: scripts/extract_flink_lexical.py:1-60]` | 现役；CI 未接线（需 research 归档，属离线可复现研究工具） |
| `scripts/extract_flink_grammar.py` | 337 | D-05 生产行号溯源校验：Parser-calcite 行 + Calcite-base reserved 行 + 97 manifest 行。`[VERIFIED: scripts/extract_flink_grammar.py:1-103,200-330]` | 现役；CI 未接线 |
| `scripts/check_naming.py` | 189 | NAME-04 命名 gate（`corpus/` 与 `.planning/` 整目录豁免，`[VERIFIED: scripts/check_naming.py:104-112]`） | 现役；CI naming-gate job |

### 4.5 CI（`.github/workflows/ci.yml`，6 个 job）

| Job | 命令 | 现状 |
|-----|------|------|
| `check` | `moon fmt --check` + `moon check --target native` + `moon check --target js` + `moon check --target wasm` | ✅ |
| `test` | `moon test --target native --package {test,parity,lsp,api,source,token,lexer,parser,printer,syntax,completion,analyzer}` | ✅ native 全包 |
| `linear-wasm-parity` | `moon build --target wasm binding parity` + `moon test --target wasm --package parity` + `moon test --target native --package parity` | ✅ wasm+native 运行时 parity（CLOSE-02） |
| `parity-gate` | `moon test --package parity`（**无 `--update`**）+ `baseline_diff.py --left __snapshot__ --right __snapshot__ --approve …/09/approved-changes.md` + `sha256sum -c parity/baseline-hashes.txt` | ✅ byte 门禁 + 自比对 + hash pin |
| `corpus` | `generate_corpus_report.py --check` + `check_keywords.py` | ✅ Doris corpus |
| `naming-gate` | `check_naming.py` | ✅ NAME-04 |

**缺口（PARITY-02/D-05 直接目标）：** CI **没有 `moon test --target js --package parity` 运行时 job**（js 只有 `moon check`）。三目标矩阵缺 JS。另：`linear-wasm-parity` 与 `parity-gate` 重复跑 native parity（无害但可整合）。

### 4.6 release 证据缓存（`/tmp/flink-research/`）

本 session 确认存在（`ls`）：`flink-{2.3.0,2.1.3,1.20.5}-src.tgz` + 各自 `.sha512`、解包树 `src/flink-{v}/`（含 `flink-table/pom.xml`、`flink-sql-parser/src/main/codegen/{data/Parser.tdd,templates/Parser.jj}`）、生成版 `Parser-calcite-{1.36.0,1.34.0,1.32.0}.jj`、三 release 的 reserved/nonreserved 清单、POM 提取物、`flink-git/`。这是 verify_corpus.py 的 release-pinned 事实源（研究 fixture，不 ship）。

### 4.7 approved-changes 注册表（D-08 批准制）

三份：`09/approved-changes.md`（Doris baseline + 命名迁移）、`10/approved-changes.md`（flink-lexical 组 + `field: calcite_version` / `field: parser_config` 机器可读行，`[VERIFIED: .planning/phases/10-…/approved-changes.md:1-63]`）、`11/approved-changes.md`（flink-grammar 组 + FATHOM-PARSE-008 退役 + 009 mint + flink-lexical 再生成 + Doris 零漂移确认）。`baseline_diff.py` 的 `--approve` 解析这三种行：`key:<key>: <old> -> <new>` / `prefix: <old> -> <new>` / `field: <name>`（`[VERIFIED: scripts/baseline_diff.py:44-63]`）。

## Unified Flink Corpus Manifest（CORPUS-01 / D-01/D-02）

### 5.1 目标形态与现状差距

现有两份 manifest 已覆盖大部分 CORPUS-01 字段，缺 5 列。**flink-grammar manifest 现有 header（逐字引用 `[VERIFIED: parity/fixtures/flink-grammar/manifest.tsv:1]`）：**

```
fixture_id	profile	exact_release	calcite_version	parser_config	source_archive_url	sha512	git_tag	git_commit	grammar_path	line_range
```

**Doris corpus manifest header（逐字引用 `[VERIFIED: corpus/manifest.tsv:1]`）——它已经示范了 URL/检索日期/标题/分类/期望状态列：**

```
fixture_id	profile	exact_release	feature_introduction	official_url	retrieval_date	pinned_source_revision	page_heading	code_fence	category	support_status	parse_mode	classification	provenance_status
```

**统一 Flink manifest 建议 schema（planner 定稿，两 manifest 合并 + 补列）：**

| 列 | 来源 | 说明 |
|----|------|------|
| `fixture_id` | 既有 | `flink-grammar.*` / `flink-lexical.*` 前缀（命名空间不相交） |
| `dialect` | 新增（flink-grammar 隐式为 flink；flink-lexical 现无） | 显式 `flink`；flink-lexical 的 doris 对照行标 `doris`（D-06 同输入双方言冻结） |
| `profile` / `exact_release` / `calcite_version` / `parser_config` | 既有 | 值必须与 `dialect/flink.mbt` `FlinkProfileMetadata` 一致（`[VERIFIED: dialect/flink.mbt:22-29]`；parser_config 逐字 `"Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT"` `[VERIFIED: dialect/flink.mbt:38]`） |
| `source_archive_url` / `sha512` / `git_tag` / `git_commit` | 既有 | release 归档钉住（`archive.apache.org` + sha512 + `release-*` tag + peeled commit） |
| `source_url` + `heading` | **新增（D-01）** | fixture SQL 的文档/grammar 来源 URL + 标题（flink-grammar 的 `grammar_path` 注释已含生产名；补文档 URL/标题；flink-lexical 补 token 来源） |
| `retrieval_date` | **新增（D-01）** | 钉住检索日期（Doris corpus 已有此列，直接对齐） |
| `category` | **新增（6 类）** | `positive | negative | recovery | known-limitation | catalog-prerequisite | planner-prerequisite`（§5.3） |
| `expected_status` | **新增（D-01）** | `valid | error | recovered`（或 `expected-error`/`expected-recovered`，与 Doris `support_status` 语义对齐） |
| `fixture_sha256` | **新增（hash）** | 每个 fixture 的 raw SQL 字节 hash（须提交 `.sql` fixture 文件方可 stdlib 校验，§5.5） |
| `grammar_path` / `line_range` | 既有（flink-grammar） | 生产行号溯源；flink-lexical 行可为 token 级来源 |
| `mode` | 新增 | `strict/editor`（D-07 双模式快照均存在） |

### 5.2 现有 fixture → 统一结构的迁入（D-02：不丢任何 fixture）

- **flink-grammar 97 fixture**：已是 per-fixture 行，补 5 列；`fixture_id` 前缀 `flink-grammar.` 保留。
- **flink-lexical 13 fixture 条目**：现有 manifest 只有 4 行 release 级 provenance → **按 fixture 展开为 13 行**（每行带 dialect/profile/来源 token 行号/6 类）；release 级 URL/sha512/tag/commit 折叠进每行（flink-grammar manifest 已示范此形态）。26 个快照文件逐一对应。
- **Doris 44 fixture**：不迁入 Flink manifest；Doris 侧由 `corpus/manifest.tsv` + 213 快照 + `baseline-hashes.txt` 继续承载（PARITY-01 对比基准）。

### 5.3 6 类分类语义（D-01 核心契约）

分类是 **fixture 层面**的单一枚举，编码「该 fixture 证明 parser 的什么能力」以及「是否依赖引擎语义」。规则：**generic SQL 被解析器接受 ≠ Flink 引擎支持**。

| 类别 | 语义 | parser 接受？ | 报告口径 |
|------|------|--------------|----------|
| **positive** | 语法自洽、可解析、无 catalog/planner/引擎前置 | valid=true | 可报「parser 支持」 |
| **negative** | 语法在该 dialect/profile 下非法，出预期诊断（含 FATHOM-PARSE-009 方言门禁拒绝） | valid=false（expected error） | 可报「parser 拒绝（符合预期）」 |
| **recovery** | 半成品/截断/畸形输入，parser 产出有界 error/missing/skipped 恢复 CST（editor 模式），lossless replay 成立 | valid=false / recovered=true | 可报「parser 有界恢复」 |
| **known-limitation** | parser 结构化接受但存在已记录子集缺口（如 SUBSET/PERMUTE/{- -} 无列作用域校验、负 offset、RANDOM 分布） | valid=true（结构） | **只报「parser 结构接受，语义/子集缺口已知」** |
| **catalog-prerequisite** | 语法可解析但名字/类型/函数解析依赖 catalog 或 registry（如 CREATE FUNCTION class 字符串、RAW('class')、结构化类型名、MATCH_RECOGNIZE 模式变量作用域） | valid=true | **绝不报「引擎支持」；报「语法接受，catalog 前置」** |
| **planner-prerequisite** | 语法可解析但执行/语义依赖 planner 或引擎（如 Window TVF 的 window_start/end/time、INTERVAL 语义、ON CONFLICT 语义、MATCH_RECOGNIZE 匹配语义） | valid=true | **绝不报「引擎支持」；报「语法接受，planner/引擎前置」** |

**判定优先级（一个 fixture 同时命中多类时）：** `negative` > `recovery` > `known-limitation` > `planner-prerequisite` > `catalog-prerequisite` > `positive`。即：只要依赖引擎语义就绝不让它落在 `positive`；known-limitation 与 prerequisite 可叠加为 `category=known-limitation, prerequisite=catalog|planner` 的补充列（planner 定稿是单列 6 值还是 `category + prerequisite` 双列——本文件推荐**单列 6 值 + 可选 `prerequisite_note` 列**，保持 D-01「6 类分类」字面）。

### 5.4 现有 fixture → 6 类映射表（推荐，planner 按快照核对落盘）

**flink-grammar 97 fixture：**

| 现有类别（计数） | → 6 类 | 依据（manifest `grammar_path` 注释/测试注释） |
|-----------------|--------|-----------------------------------------------|
| positive 62 | 拆分：**positive ~43** / **planner-prerequisite ~13** / **catalog-prerequisite ~3** / **known-limitation ~3** | 见下分类清单 |
| negative 18 | **negative 18**（全部保留；其中 7 个是 FATHOM-PARSE-009 方言门禁拒绝 = negative-dialect-gate：`insert-distributed`/`update-comment`/`delete-partition`/`analyze-buckets`/`create-table-doris-key`/`create-table-doris-engine`/`create-table-doris-properties`，manifest `line_range` 列记 `009`；其余 11 个为 localized-002 期望错） | `[VERIFIED: parity/fixtures/flink-grammar/manifest.tsv D-04 gate: 行（7 行）]` |
| incomplete 12 | **recovery 12**（截断输入 → 有界 Missing/Error，均带 lossless 断言） | `[VERIFIED: flink_grammar_test.mbt category:"incomplete" + _lossless 测试]` |
| recovery 5 | **recovery 5**（`;` 边界恢复，trailing SELECT 独立语句） | 同上 |

**positive 62 的具体拆分（推荐；标 ⚠ 的为判断点，见 Assumptions A2-A5）：**

- **planner-prerequisite（13）**：`tvf-tumble-day`、`tvf-hop-four-arg`、`tvf-cumulate`、`tvf-session`、`tvf-table-wrapper`、`tvf-offset-interval`、`tvf-named-arg`（Window TVF 输出列/区间语义依赖流 planner；`tvf-offset-interval` 另带负 offset known-limitation 注记）⚠ A2；`match-recognize-full`、`match-recognize-anchors`、`match-recognize-within-interval`、`match-recognize-all-rows`、`match-recognize-measures-time`、`match-recognize-skip-last`（MATCH_RECOGNIZE 匹配语义依赖引擎，FLINK-06 明文「不声称 planner/执行等价」）⚠ A3。
- **known-limitation（3）**：`match-recognize-subset`、`match-recognize-permute`、`match-recognize-exclude`（manifest 注释「known-limitation (structural)」——结构接受、无列作用域校验）⚠ A4。
- **catalog-prerequisite（3）**：`create-function`、`create-function-python`（class 字符串 + LANGUAGE 解析，UDF 注册依赖 registry）⚠ A5；`create-catalog`（connector 类型存在性依赖 catalog/engine）。
- **positive（其余 ~43）**：SELECT/CTE/JOIN/集合运算、INSERT/UPSERT 语法面、UPDATE/DELETE、EXPLAIN/SHOW/DESCRIBE/ANALYZE、USE/SET/RESET、表达式/类型构造、CREATE/DROP/ALTER DATABASE/VIEW/FUNCTION、CREATE TABLE 复杂形式（四类列/WATERMARK/PK/分区分发/WITH/LIKE/AS）。

**flink-lexical 13 fixture → 6 类（词法级冲突矩阵，类别跟 parse 状态）：**

| fixture × dialect/profile | → 6 类 | 依据 |
|---------------------------|--------|------|
| `hash-comment.flink-2.3.0` | **negative** | `#` 是 Flink lexical error（FATHOM-PARSE-003 + 007） |
| `hash-comment.doris-4.x` | **negative** | `#` 是 Doris 注释，裸 `a` → 007 unsupported |
| `double-quote.flink-2.3.0` | **negative** | `"a"` DOUBLE_QUOTE symbol → 002 表达式错 |
| `double-quote.doris-4.x` | **positive** | `"a"` 是 Quoted 标识符，真实 SELECT |
| `slash-comment.flink-2.3.0` | **positive** | `//` SINGLE_LINE_COMMENT trivia，valid=true |
| `slash-comment.doris-4.x` | **negative** | `//` 是两个 SLASH symbol → 002 |
| `e-literal.flink-2.3.0` / `.flink-2.1.3` | **positive** | E'..' C_STYLE_ESCAPED_STRING_LITERAL 字面量 |
| `e-literal.flink-1.20.5` | **negative** | Calcite 1.32.0 无 E 前缀 → E 标识符 + 字符串错 |
| `e-literal.doris-4.x` | **negative** | Doris 无 E 前缀 → 表达式错 |
| `backtick-escape.flink-2.3.0` | **positive** | BTID 双反引号转义，valid=true |
| `backtick-escape.doris-4.x` | **positive** | scan_quoted 双写，valid=true |
| `unknown-profile.flink-4x` | **negative** | FATHOM-SCHEMA-003 拒绝信封（profile 校验，不进 parser） |

> 词法 fixture 的 6 类是「该输入在（dialect, profile）下的 parse 状态」；语义前置不适用于纯词法行。

### 5.5 hash 验证设计（D-01「hash」+ D-06 离线）

每个 fixture 需两个 hash 层次：
1. **release 归档 sha512**（已存在）：`sha512` 列 + `/tmp/flink-research/*.tgz` 本地复验（`extract_flink_lexical.py` 已实现归档存在时的 manifest sha512 比对，`[VERIFIED: scripts/extract_flink_lexical.py:1-60 文档串]`）。
2. **fixture raw SQL sha256**（新增）：须将 flink-grammar 的 97 个嵌入 raw 落成 `parity/fixtures/flink/{profile}/{fixture_id}.sql` 文件（沿袭 `corpus/doris-*/` 模式），`fixture_sha256` 列 pin 之；`verify_corpus.py` 对文件算 sha256 比对。flink-lexical 13 行同理。**嵌入字节 vs `.sql` 文件一致性**由 `extract_flink_grammar.py` 扩展（解析 MoonBit `b"..."` 字面量）在校验时比对——沿袭 `baseline-hashes.txt` 的 embedded-raw provenance（D-08）。

## Doris Frozen Diff Harness（PARITY-01 / D-03/D-04）

### 6.1 现状机制（已存在，逐字核验）

- **冻结物**：`parity/__snapshot__/` 213 个 Doris 快照（§4.2）+ `parity/baseline-hashes.txt` pin 44 corpus 文件 SHA-256。
- **门禁**：CI `parity-gate` job 跑 `moon test --package parity`（**无 `--update`**，字节级失败）+ `baseline_diff.py --left __snapshot__ --right __snapshot__ --approve …/09/approved-changes.md`（自比对）+ `sha256sum -c baseline-hashes.txt`（`[VERIFIED: .github/workflows/ci.yml parity-gate job]`）。
- **批准流**：三份 `approved-changes.md` 注册表，机器可读行 `key:`/`prefix:`/`field:`（`[VERIFIED: scripts/baseline_diff.py:44-63]`）。
- **零漂移纪律**：Phase 11 每波后 `moon test --package parity` 无 `--update` 先跑；`git diff --name-only -- parity/__snapshot__` 只应出现 flink-* 文件（`[VERIFIED: 11/approved-changes.md §6]`）。

### 6.2 形式化为显式 diff harness（D-03）

现状 CI 的 `baseline_diff.py` 是 **left==right 自比对**（稳态恒 0 diff），只验证注册表可解析 + 快照树自洽；真正的冻结门禁是 `moon test` 的字节失败。D-03 要求输出「**冻结 vs 当前**」差异报告。设计：

```
scripts/diff_parity.py（新，stdlib；或扩展 baseline_diff.py 加 --frozen 模式）
  1. frozen = 当前 committed 快照树（git 干净态 copy 到 temp/frozen）
  2. current = 运行 `moon test --update --package parity` 在 temp/current 生成（不碰工作树）
     —— MoonBit snapshot 写路径固定到包 __snapshot__/，故需：cp -r parity/__snapshot__ temp/frozen，
        mv parity/__snapshot__ temp/current_base，moon test --update --package parity，
        mv parity/__snapshot__ temp/current，再 mv 回 temp/current_base（工作树零残留）
  3. baseline_diff.py --left temp/frozen --right temp/current --approve <register>
     → approved（注册表已批准）+ unexpected（未记录，exit 1）
  4. 输出「frozen vs current」报告：变更文件清单 + 逐 path 值 diff + 归类
```

- **本地/开发用途**：`scripts/diff_parity.py --approve <register>` 在任意改造后生成可读报告；unexpected>0 → exit 1。
- **CI 用途（推荐接线）**：`parity-gate` job 在 `moon test --package parity` 通过后加一步 `diff_parity.py --frozen-only`（即校验 committed 树 == `moon test --update` 再生成树，逐字节 + 逐 path shape 双通道）。`--frozen-only` 模式下脚本跑 `moon test --update` 到 temp 再与 committed 比对，任何差异 exit 1——这比当前自比对强（当前自比对恒 0）。
- **批准流（不变）**：任何故意的快照变更先向注册表追加 `field:`/`key:`/`prefix:` 行并 commit，再允许 `moon test --update`（single-use 批准路径，`[VERIFIED: 09/10/11 approved-changes.md 各 register header]`）。

### 6.3 docs-vs-parser 冲突可见（D-03/D-07）

冲突 = 快照期望（冻结的 docs/grammar 事实）与实现（新 parser 输出）不一致。**绝不静默批量 `--update`**：

```
冲突发现 → moon test --package parity 失败（具体快照文件）
   → diff_parity.py 报告归类：
       (a) approved 已注册 → 允许，走 --update（单次）
       (b) unexpected + 属 docs-vs-parser 冲突 → 人工裁决：
             · docs 权威方变更（如 Doris 4.x 文档新增语法）→ 注册表 + 新快照（记录理由）
             · parser 回归 → 修 parser，不动快照
             · release 事实（Calcite 行为）与 docs 不一致 → 以钉住 release 为准，注册表记录（D-07 三方裁决）
```

**现状先例**：`differential.tsv` 已示范「sqlglot 拒绝但 released-docs 权威 → 记录 disagreement, advisory only」（`[VERIFIED: corpus/differential.tsv:1-23]`）。flink-grammar 的 `tvf-offset-interval`（负 offset）、`create-table-random-distribution`（Flink 测试 `.fails`）是 Calcite 测试 vs 语法结构的冲突先例（manifest 注释已记录）。

## Cross-Backend Parity（PARITY-02 / D-05）

### 7.1 现状机制（已验证可用）

- **字节比对物**：MoonBit `@test.T::snapshot` 写 `parity/__snapshot__/` 的 committed 文件；`moon test --target {native,js,wasm} --package parity` 各 target 用**同一批 committed 快照文件**比对——任一 target 输出字节不同则 `moon test` 失败。
- **cross-target 显式物**：`cross-target.4.x-industrial.strict.json`（任一 target 写、其余 target 必须字节复现，`[VERIFIED: parity/baseline_test.mbt:18-22]`）。
- **实测**：本 session `moon test --target native/js/wasm --package parity` 三目标均 570/570（§4.2）。
- **CI**：`linear-wasm-parity` job 跑 wasm + native；**缺 js 运行时 job**（§4.5）。

### 7.2 补三目标矩阵 + 报告工具

1. **CI 增 js 运行时 parity job**（或并入 `linear-wasm-parity`）：`moon test --target js --package parity`。三目标矩阵齐（check 已三目标，现补 runtime）。
2. **新 `scripts/compare_backends.py`**（stdlib）：
   ```
   对 target in {native, js, wasm}:
     rc = run("moon test --target {t} --package parity")
     捕获 per-fixture 失败（moon 输出中的快照文件名）
     记录 {t}: rc, 失败清单, 快照树 sha256（对 committed __snapshot__/ 算确定性 digest）
   报告:
     per-target: pass/fail + 失败 fixture 清单
     树 digest 三 target 必须一致（同一 committed 树）
     若任一 target 的 `moon test --update` 试运行（temp）产生不同字节 → 列出分歧 fixture
   exit 0 iff 三 target 全绿且 digest 一致
   ```
3. **序列化结果/诊断/span/lossless replay 的跨 target 显式比对**：已由同一批快照文件天然覆盖（快照就是序列化信封，含 `source_bytes`/`diagnostics`/`root`/span）。`compare_backends.py` 额外对代表性 fixture 集（覆盖 6 类）做 `git diff --name-only parity/__snapshot__` 校验，确保 `moon test` 在 temp `--update` 下零漂移。
4. **禁止 float/字节序分歧**：序列化信封全为整数/字符串/字节数组（`fathom.parse.v1` 无 float 字段，`source_bytes` 是整数数组，`[VERIFIED: parity/__snapshot__/cross-target.4.x-industrial.strict.json 结构]`）——cross-target 无 float 序列化风险；JS 的 `Uint8Array` 由 binding 层统一转整数数组（`target-matrix.json` 注记 `"source_bytes is an explicit JSON byte array; JS uses Uint8Array"`）。

## Offline Gate + 语义区分（PARITY-03 / D-06）

### 8.1 离线 manifest/hash 验证器：`scripts/verify_corpus.py`

纯 stdlib、纯本地、无网络/Doris-FE/Flink-cluster/DB。职责（`--check` 模式 exit 非零）：

```
1. manifest 结构校验：header 精确匹配；每行列数一致；fixture_id 前缀合法；无重复 fixture_id
2. 字段一致性：profile/exact_release/calcite_version/parser_config 与
   dialect/flink.mbt FlinkProfileMetadata（或内嵌 pin 表）逐字一致
3. category 枚举校验：∈ {positive, negative, recovery, known-limitation,
   catalog-prerequisite, planner-prerequisite}
4. expected_status 一致性：category 与 expected_status 逻辑自洽
   （positive→valid；negative→error；recovery→recovered；其余→valid+note）
5. hash 校验：
   a. fixture_sha256：对 parity/fixtures/flink/{profile}/{fixture_id}.sql 算 sha256，比 manifest
   b. 归档 sha512：若 /tmp/flink-research/{exact_release}-src.tgz 存在 → sha512sum 比对；
      不存在 → 报 "archive-not-present (research fixture)" 状态（不 fail，不伪造）
6. 快照完整性：manifest 每行对应 2 个快照文件（strict+editor）存在于 parity/__snapshot__/；
   快照文件数 > 0 且与 manifest 行数 × 2 一致（flink-grammar 194 = 97×2）
7. 覆盖报告输入：为 generate_corpus_report.py 生成 corpus/flink-coverage.tsv 输入
```

`--offline` 语义（D-06）：**绝不发起网络**；只读 pinned 工件 + 本地缓存。归档缺失是「研究 fixture 未随仓库 ship」的已知状态，不是失败——沿用 `extract_flink_lexical.py` 的「归档存在时复验、缺失时跳过」行为（`[VERIFIED: scripts/extract_flink_lexical.py:1-60]`）。

### 8.2 CI 接线

新 CI job（或并入 `corpus` job）：
```
- name: Flink corpus offline verifier
  run: python3 scripts/verify_corpus.py --check
- name: Cross-dialect coverage report --check
  run: python3 corpus/tools/generate_corpus_report.py --check   # 扩展支持 flink
```
`generate_corpus_report.py` 扩展为读 `corpus/flink-coverage.tsv`（新）并渲染双方言报告。`extract_flink_grammar.py` / `extract_flink_lexical.py` 的 release 行号/关键字校验保留为**离线可复现研究工具**（CI 不依赖 /tmp/flink-research；本地维护者跑）。

### 8.3 语义区分覆盖报告（parser 接受 vs 引擎前置）

复用 Doris `corpus/coverage.tsv` + `CORPUS-REPORT.md` 模式（`[VERIFIED: corpus/tools/generate_corpus_report.py:1-63]`），新增 `corpus/flink-coverage.tsv`：

| profile | category | fixture_count | parser_accepted | parser_rejected | recovery | prerequisite | 覆盖说明 |
|---------|----------|---------------|-----------------|-----------------|----------|--------------|----------|
| flink-2.3.0 | positive | 43 | 43 | 0 | 0 | none | 自洽语法面 |
| flink-2.3.0 | planner-prerequisite | 13 | 13 | 0 | 0 | planner | **引擎支持=0**（显式列） |
| flink-2.3.0 | catalog-prerequisite | 3 | 3 | 0 | 0 | catalog | **引擎支持=0** |
| flink-2.3.0 | known-limitation | 3 | 3 | 0 | 0 | structural | 子集缺口，**引擎支持=0** |
| flink-2.3.0 | negative | 18 | 0 | 18 | 0 | none | 期望拒绝（含 7 个 009 方言门禁 + 11 个 localized 期望错） |
| flink-2.3.0 | recovery | 17 | 0 | 0 | 17 | none | 有界恢复 + lossless（incomplete 12 + recovery 5） |

**报告硬规则（--check 强制）：**
- 任何 `catalog-prerequisite`/`planner-prerequisite`/`known-limitation` 行不得计入「engine supported」。
- 报告输出两类合计：**parser 接受（valid）** vs **引擎语义前置（prerequisite）**——双方言同制（Doris 侧沿用现有 `supported`/`expected-error` 口径，但 Doris `4.x-merge` 等行已示范「released-docs 权威」口径）。
- 禁止 `"100%"`/`"full compatibility"` 字样（`generate_corpus_report.py` 已含此 invariant，`[VERIFIED: corpus/tools/generate_corpus_report.py:20-25]`）。

## Conflict Visibility Flow（D-07）

**三方冲突定义**：fixture 期望（docs/grammar 权威）vs 实现（parser 当前输出）vs release 事实（钉住 Calcite/Flink 行为）。显式报告 + 人工裁决入口，绝不静默批量更新快照：

```
┌─ moon test --package parity 失败（某快照字节漂移）
│
├─ diff_parity.py（或 baseline_diff.py）归类：
│     approved  → 已注册批准 → 单次 --update
│     unexpected → 进入冲突裁决
│
├─ 冲突裁决（人工入口 = approved-changes.md 注册表追加记录）：
│    A. docs-vs-parser：docs 新增/变更语法，parser 未跟上
│         → 决策：补 parser（不动快照）| 或注册 expected 变更 + 重标 category
│    B. release 事实 vs docs/parser：钉住 Calcite 行为与 docs 描述不一致
│         → 以钉住 release 归档为准（D-02 禁 folklore），注册表记录理由
│    C. 实现改变（parser 有意变更方言接受面）
│         → FATHOM-PARSE-009/007/001 变更注册 + 快照重标（如 Phase 11 的 008 退役/009 mint）
│
└─ 批准后：注册表 commit → moon test --update --package parity（单次）→ 重跑全部 gate
```

**现状先例**：Phase 11 的 `approved-changes.md` §3/§4 就是三方裁决产物（008 退役、009 mint、flink-lexical 再生成、`match-recognize-subset` 快照重写因为 Parser.jj:3182 子句顺序——docs/实现冲突经裁决）。`differential.tsv` 的 `advisory_only=true` 行示范「第三方 oracle 分歧记录不阻塞」。

## Implementation Surface（实施面，file-by-file）

> 全部为新增/扩展脚本 + parity 数据重组 + CI job；**零 MoonBit 核心代码改动**（本阶段不新增 grammar/词法能力，D-01 边界）。`commit_docs` 已开（config.json），research 文件先写盘。

### 9.1 新增文件

| 文件 | 类型 | 内容 |
|------|------|------|
| `scripts/verify_corpus.py` | 新增（stdlib） | §8.1 离线 manifest/hash 验证器；`--check` 模式；`ok:` 尾行 |
| `scripts/compare_backends.py` | 新增（stdlib） | §7.2 三目标运行 + digest 比对 + per-fixture 报告 |
| `scripts/diff_parity.py` | 新增（stdlib） | §6.2 冻结 vs 当前 harness（temp copy + `moon test --update` + baseline_diff 归类）；`--frozen-only` 供 CI |
| `parity/fixtures/flink/{flink-2.3.0,flink-2.1.3,flink-1.20.5,doris-4.x}/{fixture_id}.sql` | 新增（~110 文件） | 现有嵌入 raw 落盘（flink-grammar 97 + flink-lexical 13）——manifest `fixture_sha256` 的可校验物 |
| `parity/fixtures/flink/manifest.tsv` | 新增（合并） | §5.1 统一 schema：flink-grammar 97 行 + flink-lexical 13 行（展开） |
| `corpus/flink-coverage.tsv` | 新增 | §8.3 语义区分覆盖矩阵（双方言同制） |
| `corpus/CORPUS-REPORT.md` 增补 | 扩展 | 渲染 flink 段（by `generate_corpus_report.py`） |

### 9.2 修改文件

| 文件 | 改动 |
|------|------|
| `scripts/baseline_diff.py` | 可选：加 `--frozen`/`--current` 别名以被 diff_parity.py 复用（现接口已够，最小改） |
| `scripts/extract_flink_grammar.py` | 扩展：解析 flink_grammar_test.mbt 的 `b"..."` 字面量，比对 `parity/fixtures/flink/**/*.sql` 字节（embedded-raw provenance）；manifest 校验加 6 类枚举 |
| `scripts/extract_flink_lexical.py` | 扩展：13 行 flink-lexical fixture 的 6 类 + token 来源列校验 |
| `corpus/tools/generate_corpus_report.py` | 扩展：读 `corpus/flink-coverage.tsv`，渲染双方言报告；`--check` 加 prerequisite 硬规则 |
| `parity/flink_grammar_test.mbt` / `flink_lexical_test.mbt` | 仅注释/结构对齐（fixture raw 不动；`category` 字段若单列 6 值则需重命名枚举——**建议保留测试内 4 类、6 类放 manifest**，避免 310 个测试断言大改） |
| `.github/workflows/ci.yml` | ① `linear-wasm-parity` 或新 job 增 `moon test --target js --package parity`；② `parity-gate` 增 `diff_parity.py --frozen-only`（或独立 job）；③ `corpus` job 增 `verify_corpus.py --check` + 扩展后报告 `--check`；④ `compare_backends.py` 三 target 汇总 job |
| `.planning/phases/12-…/approved-changes.md` | 新建：预声明 Phase 12 允许的快照变更（统一 manifest 迁移若导致 flink 快照路径/文件名变化 → 注册；**Doris 213 零漂移**） |
| `parity/moon.pkg` | 无改动必要（targets 块已三目标；若加 dump 入口才需改） |

### 9.3 显式不做（Deferred / 边界）

- 不新增 MoonBit 核心 parser/lexer/语法能力（Phase 10/11 已完成）。
- 不实现 catalog/planner/引擎语义（Phase 13 TOOL-03 + FLINK-FUTURE-01）。
- 不引入网络、Doris FE、Flink cluster、数据库运行时访问（SC4/D-06 明文禁止）。
- 不改 Doris 213 快照字节（PARITY-01 硬门禁）。

## Common Pitfalls

### Pitfall 1: 静默批量 `--update` 吸收快照漂移
**What goes wrong:** 实现改动导致 Doris 或 flink 快照漂移后，维护者直接 `moon test --update --package parity` 把新输出「吸收」为 baseline，docs-vs-parser 冲突被抹平。
**Why:** `--update` 是无差别重写；CI `parity-gate` 的 `moon test --package parity`（无 `--update`）能抓住漂移，但本地一次 `--update` 就静默通过。
**How to avoid:** D-08 single-use 批准路径：任何 `--update` 前必须先 commit 注册表条目；`diff_parity.py` 把漂移归类为 approved/unexpected，unexpected 一律走人工裁决。**Never add `--update` to CI**（ci.yml parity-gate 注释已明示）。
**Warning signs:** `git status --short parity/__snapshot__` 出现未登记文件；`moon test` 本地过但 CI 挂。

### Pitfall 2: 类别误标 —— 语法接受报成引擎支持
**What goes wrong:** 一个 Flink SQL 被 parser 接受（valid=true）就被报告为「Flink 支持」，掩盖 catalog/planner 前置。
**Why:** 现有 4 类（positive/negative/incomplete/recovery）只有 parser 接受维度，没有引擎语义维度；`positive` 会天然吞掉 TVF/MATCH_RECOGNIZE 等 planner-prerequisite fixture。
**How to avoid:** 6 类分类把 TVF/MATCH_RECOGNIZE 标 planner-prerequisite、CREATE FUNCTION 标 catalog-prerequisite；`verify_corpus.py` 枚举校验 + 覆盖报告硬规则（prerequisite 不计入 engine supported）。**generic acceptance ≠ engine support** 是 D-01 research-flags 明文。
**Warning signs:** flink-coverage.tsv 里 positive 计数偏高而 prerequisite 为空；报告出现「引擎支持 = 全部 parser 接受」。

### Pitfall 3: hash 漂移 / 归档缺失被当失败或伪造
**What goes wrong:** release 归档不在仓库（研究 fixture），verify_corpus.py 若把「归档不存在」当 error 会常红；或反过来，维护者为过 gate 伪造 hash。
**Why:** `/tmp/flink-research/` 是本地研究缓存，不随 CI checkout；manifest sha512 需要归档在才能复验。
**How to avoid:** 归档缺失 → `archive-not-present (research fixture)` 状态（不 fail）；fixture_sha256（提交的 `.sql` 文件）是 CI 可校验的常驻 hash。沿用 `extract_flink_lexical.py` 的「存在即复验、缺失即跳过」行为。**绝不伪造 commit/hash**（STATE.md 既有纪律：`unavailable-offline` + `known-gap`，不造假 SHA）。
**Warning signs:** CI 依赖 /tmp/flink-research 导致红；manifest 里 sha256 与文件不符。

### Pitfall 4: 跨后端 float/字节序/编码分歧
**What goes wrong:** 同一 fixture 在 native/js/wasm 产生不同字节（float 序列化、字节序、UTF-8 vs UTF-16、JSON 键序）。
**Why:** 序列化信封若含 float 或依赖宿主编码，三 target 会分歧；JS `Uint8Array` 与 native 字节数组若不归一也会分歧。
**How to avoid:** 序列化信封保持整数/字符串/字节数组（`fathom.parse.v1` 现无 float，`source_bytes` 是整数数组，已示范）；binding 层统一 `Uint8Array → int[]`；`compare_backends.py` 三 target digest 比对 + `moon test --target js` CI job 常驻。
**Warning signs:** `moon test --target js` 与 native 结果不同；digest 三 target 不一致。

### Pitfall 5: CI 网络访问 creep
**What goes wrong:** release-pinned 门禁悄悄引入网络（如 `curl` 拉移动 docs、`pip install`、git ls-remote）。
**Why:** 维护者想「自动核对最新 release」，违背 D-06 离线语义。
**How to avoid:** `verify_corpus.py` 无任何网络调用（stdlib，只读本地文件）；CI 只跑本地脚本 + `moon test`（moon 安装例外是既有工具链引导）；manifest URL 仅作审计元数据不访问。
**Warning signs:** CI 日志出现 `curl`/`pip`/`git ls-remote`；`verify_corpus.py` 带 socket 调用。

### Pitfall 6: 破坏既有 passing gates
**What goes wrong:** 统一 manifest 重组、快照路径/命名变更、`.sql` 文件落盘意外触碰 Doris 213 快照或 flink 快照字节。
**Why:** 重构 parity/fixtures 时若改 `flink_grammar_test.mbt` 的 snapshot filename（`flink-grammar.{fixture}.flink-2.3.0.{strict,editor}.json`），现有 194 个文件路径漂移触发全量失败。
**How to avoid:** 统一 manifest 只增列不改 fixture_id/快照文件名；`.sql` 落盘是新增物（不替换嵌入字节）；每步改完先跑 `moon test --package parity`（三目标）再提交；Doris 213 零漂移是硬门禁（§4.5 parity-gate）。
**Warning signs:** `git diff --name-only -- parity/__snapshot__` 出现 doris 命名文件；重构后 570 测试骤降。

### Pitfall 7: 6 类分类在 fixture 间不一致（同类不同语义）
**What goes wrong:** 同一类别在不同 fixture 语义漂移（如 `positive` 混入 prerequisite、`negative` 混入 known-limitation）。
**Why:** 分类无权威枚举 + 无自动校验。
**How to avoid:** `verify_corpus.py` 枚举校验 + expected_status 一致性检查 + 覆盖报告 prerequisite 硬规则；新 fixture 必须先在 manifest 登记 6 类再落快照（D-01 costly reversibility —— 字段语义变更需全量重标）。
**Warning signs:** verify_corpus.py `--check` 报 category 枚举/一致性错。

### Pitfall 8: 单一入口脚本与 `ok:` 模式的 CI 盲区
**What goes wrong:** 新 gate 脚本「跑过但什么都没检查」（如 0 文件扫描、manifest 空、快照树缺失仍 exit 0）。
**Why:** 照搬 `check_naming.py`/`generate_corpus_report.py` 的 `ok:` 模式时忽略「空输入」守卫。
**How to avoid:** 每脚本带**非空守卫**：manifest 至少 1 行、快照文件数 == manifest 行数 × 2、`.sql` 文件数匹配（仿 `check_naming.py` 的 `scanned == 0 → fail`，`[VERIFIED: scripts/check_naming.py:145-151]`）。
**Warning signs:** gate 绿但 corpus 目录被清空仍过。

## Code Examples

### Common Operation 1: 离线验证器骨架（`scripts/verify_corpus.py`，stdlib）

```python
#!/usr/bin/env python3
"""Offline Flink corpus manifest/hash verifier (Phase 12, D-06; stdlib only)."""
import argparse, csv, hashlib, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "parity" / "fixtures" / "flink" / "manifest.tsv"
SNAPSHOT_DIR = ROOT / "parity" / "__snapshot__"
CATEGORIES = {
    "positive", "negative", "recovery", "known-limitation",
    "catalog-prerequisite", "planner-prerequisite",
}
# Mirrors dialect/flink.mbt FlinkProfileMetadata (verified in-repo).
PINS = {
    "flink-2.3.0":  ("1.36.0", "Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT"),
    "flink-2.1.3":  ("1.34.0", "Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT"),
    "flink-1.20.5": ("1.32.0", "Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT"),
}

def sha256_file(p: pathlib.Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

def main(argv):
    problems = []
    rows = []
    with MANIFEST.open(encoding="utf-8") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        header = reader.fieldnames or []
        if header[:5] != ["fixture_id", "dialect", "profile", "exact_release", "calcite_version"]:
            problems.append("manifest header mismatch: %r" % header)
            return 1
        rows = list(reader)
    if not rows:
        problems.append("manifest is empty")  # non-empty guard (Pitfall 8)
        return 1
    for r in rows:
        calcite, cfg = PINS.get(r["profile"], (None, None))
        if calcite is None:
            problems.append("%s: unknown profile %r" % (r["fixture_id"], r["profile"])); continue
        if r["calcite_version"] != calcite or r["parser_config"] != cfg:
            problems.append("%s: calcite/config drift %s/%s" % (r["fixture_id"], r["calcite_version"], r["parser_config"]))
        if r["category"] not in CATEGORIES:
            problems.append("%s: bad category %r" % (r["fixture_id"], r["category"]))
        sql = ROOT / "parity" / "fixtures" / "flink" / r["profile"] / (r["fixture_id"] + ".sql")
        if not sql.is_file():
            problems.append("%s: missing fixture sql %s" % (r["fixture_id"], sql)); continue
        if sha256_file(sql) != r["fixture_sha256"]:
            problems.append("%s: fixture_sha256 mismatch" % r["fixture_id"])
        # snapshot completeness: strict + editor must exist.
        # Snapshot segment mirrors the test's filename:
        #   flink rows:      {fixture_id}.{profile}.{mode}.json  (profile = flink-2.3.0)
        #   doris rows:      {fixture_id}.doris-{profile}.{mode}.json (profile = 4.x)
        # (the flink-lexical doris-side rows use the dialect-prefixed segment).
        seg = r["profile"] if r["dialect"] == "flink" else "doris-" + r["profile"]
        for mode in ("strict", "editor"):
            snap = SNAPSHOT_DIR / ("%s.%s.%s.json" % (r["fixture_id"], seg, mode))
            if not snap.is_file():
                problems.append("%s: missing snapshot %s" % (r["fixture_id"], snap.name))
    if problems:
        for p in problems: print("error: " + p, file=sys.stderr)
        return 1
    print("ok: %d flink corpus rows verified offline (6-category, pins, hashes, snapshots)" % len(rows))
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

### Common Operation 2: 冻结 vs 当前 diff harness 调用链

```bash
# 开发/审查用途（不碰工作树快照）：
python3 scripts/diff_parity.py --approve .planning/phases/12-cross-dialect-corpus-and-parity-gates/approved-changes.md
# CI parity-gate 增强：
python3 scripts/diff_parity.py --frozen-only
```

### Common Operation 3: compare_backends.py 三目标报告

```python
# 骨架：对 native/js/wasm 依次运行 moon test --target {t} --package parity
# 捕获退出码与失败快照名；对 parity/__snapshot__/ 算三 target 一致的确定性 sha256
# 报告 per-target 状态 + 分歧 fixture 清单；任一 target 非 0 或 digest 不一致 → exit 1
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| 单方言（Doris）corpus + 213 快照（v1.0，Phase 2/9） | 跨方言（Doris + Flink 3 profile）release-pinned corpus + 6 类分类（Phase 10-12） | Phase 10/11/12（v2.0） | 覆盖从「Doris 官方 docs 语料」扩展到「钉住 Flink release 归档 + Calcite 行号」；manifest 成为公共审计契约 |
| 快照自比对（`baseline_diff.py --left X --right X`） | 冻结 vs 当前 diff harness（`diff_parity.py --frozen-only`，approved-vs-unexpected 双通道） | Phase 12 | 「冻结」从恒真变为可证（重生成树逐字节+逐 path 比对），docs-vs-parser 冲突显式可见 |
| CI 只跑 native + wasm parity | native + js + wasm 三目标 runtime 矩阵 + compare_backends.py 报告 | Phase 12（D-05） | JS 后端字节一致成为常驻 CI 承诺 |
| 归档 sha512 校验需本地 `/tmp/flink-research` | `verify_corpus.py`：fixture `.sql` sha256 常驻 + 归档 sha512 存在即验 | Phase 12（D-06） | 离线门禁不依赖研究缓存；release 钉住为唯一事实源 |

**Deprecated/outdated:**
- `moon.mod.json`/`moon.pkg.json`（v0.10.4 deprecated）：仓库已用新 `moon.mod`/`moon.pkg` DSL（`[VERIFIED: parity/moon.pkg:1]` `pkgtype(kind: "executable")`），本阶段不引入旧格式。
- `FATHOM-PARSE-008`（Phase 9/10 的 flink not-implemented 占位）：Phase 11 已退役保持空缺（`11/approved-changes.md §1`）；本阶段不得复用。

## Assumptions Log

> 所有 `[ASSUMED]` 声明。planner/discuss-phase 需在锁定时确认；`[VERIFIED]` 声明见正文各节。

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | 统一 manifest 落点建议 `parity/fixtures/flink/`（CONTEXT code_context 指向 parity 统一结构）；planner 可改 `corpus/flink/` | §5.1 | 目录落点与 Phase 13 消费方耦合，错则迁移成本 |
| A2 | 7 个 Window TVF positive fixture 归 **planner-prerequisite**（输出列/区间语义依赖流 planner）——FLINK-05 明文不声称 planner 等价 | §5.4 | 若误标 positive，覆盖报告会把「语法接受」报成「引擎支持」（Pitfall 2 核心） |
| A3 | MATCH_RECOGNIZE positive fixture 归 **planner-prerequisite**（匹配语义依赖引擎，FLINK-06 明文） | §5.4 | 同上 |
| A4 | `match-recognize-subset/permute/exclude` 归 **known-limitation**（结构接受、无列作用域校验）；`tvf-offset-interval` 亦为 known-limitation（负 offset） | §5.4 | 若归 positive，掩盖子集缺口 |
| A5 | `create-function`/`create-function-python`/`create-catalog` 归 **catalog-prerequisite**（UDF/connector 注册依赖 registry/catalog） | §5.4 | 若归 positive，UDF class 字符串解析被报为引擎支持 |
| A6 | 提交 97+13 个 `.sql` fixture 文件（沿袭 `corpus/doris-*/` + `baseline-hashes.txt`）使 `fixture_sha256` 可被 stdlib 校验 | §5.5 | 若不落盘，D-01「hash」只能 pin 归档 sha512，fixture 级 hash 无法离线校验 |
| A7 | 测试内保留 4 类（positive/negative/incomplete/recovery）、6 类放 manifest/coverage（避免 310 个测试断言大改） | §9.2 | 若强行改测试内枚举，重构成本高且无行为收益 |
| A8 | `compare_backends.py` 用 `moon test --target {t}` 退出码 + 快照树 digest 作为比对（wasm 无法 stdout dump，`run_wasm.mbt` 注释「No println/env/host IO」） | §7.2 | 若需逐 fixture 显式 dump，需新增 target-scoped dump 入口（超出 snapshot 机制） |
| A9 | `diff_parity.py` 的 temp `--update` 工作流（copy + move + restore）在 CI runner 上可安全执行 | §6.2 | 若 MoonBit 不支持目录重定向，需退化为「git clean + `--update` + git diff 还原」 |
| A10 | CI 增 js 运行时 job 并入现有 `linear-wasm-parity` job 而非新 job | §7.2 | 纯 CI 组织选择，无行为风险 |

## Open Questions (RESOLVED)

1. **(RESOLVED) 6 类是单列枚举还是 `category + prerequisite` 双列？**
   - What we know: D-01 字面「6 类分类」；部分 fixture 天然命中两类（如 `match-recognize-full` = planner-prerequisite 且无列作用域 = known-limitation 成分）。
   - What's unclear: 单列强制互斥 vs 双列（category 主类 + prerequisite 补充）的取舍。
   - Recommendation: 本文件推荐**单列 6 值 + 可选 `prerequisite_note` 列**（保持 D-01 字面，冲突用优先级规则 §5.3 消解）；planner 定稿后 `verify_corpus.py` 枚举随动。
   - **RESOLVED (2026-08-09):** 定稿为**单列 6 值 `category`**（positive | negative | recovery | known-limitation | catalog-prerequisite | planner-prerequisite）+ 可选 `prerequisite_note` 补充列（见 §5.3）。

2. **(RESOLVED) fixture `.sql` 落盘规模（97+13 文件）是否接受？**
   - What we know: 无 `.sql` 文件则 `fixture_sha256` 无法被 stdlib 校验；D-01 要求每 fixture hash。
   - What's unclear: 是否可接受 110 个新增小文件，或改用「manifest 级 sha256 文件」（如 `parity/fixtures/flink/manifest.sha256`）替代。
   - Recommendation: 接受落盘（沿袭 corpus/doris-* 先例）；若 team 反对，退化为 manifest 级 hash 文件 + embedded-raw 提取校验。
   - **RESOLVED (2026-08-09):** 定稿为提交 110 个 `.sql` fixture 文件（97 flink-grammar + 13 flink-lexical，沿袭 `corpus/doris-*/` 先例），使 `fixture_sha256` 可被 stdlib 校验。

3. **(RESOLVED) CI js 运行时 job 并入现有 job 还是独立 job？**
   - What we know: 三 target 均已本地实测 570/570；CI 缺 js runtime。
   - What's unclear: 并入 `linear-wasm-parity`（同名改三目标）vs 独立 `js-parity` job。
   - Recommendation: 并入 `linear-wasm-parity`（一次 checkout/安装，矩阵语义一致），`compare_backends.py` 独立汇总报告。
   - **RESOLVED (2026-08-09):** 定稿为并入 `linear-wasm-parity` job（三目标矩阵），`compare_backends.py` 独立汇总报告。

4. **(RESOLVED) `extract_flink_grammar.py`/`extract_flink_lexical.py` 是否进 CI？**
   - What we know: 它们依赖 `/tmp/flink-research/`（研究 fixture），CI checkout 无此缓存。
   - What's unclear: 是否把归档校验作为「有缓存才跑」的可选 CI 步。
   - Recommendation: **不进 CI**（离线门禁由 `verify_corpus.py` 承担）；归档校验保留为本地维护者工具，manifest 行号由 `verify_corpus.py` 的结构校验 + 提交时 `extract_*` 手动跑覆盖。
   - **RESOLVED (2026-08-09):** 定稿为**不进 CI**；`extract_*` 保留为本地维护者工具，离线门禁由 `verify_corpus.py` 承担。

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `moon` / `moonc` | 三目标 parity、快照门禁 | ✓ | `moon 0.1.20260724 (5f1406a 2026-07-24)` / moonc v0.10.5+5e7afb0c0 | — |
| `moonbitlang/core` + `@test` | parity 包测试 | ✓ | 既有锁定 | — |
| Python 3 | 全部 gate 脚本 | ✓ | 3.9.23 | — |
| `sha256sum`/`sha512sum` | hash 校验 | ✓ | coreutils | Python `hashlib` |
| node | JS 目标测试（`moon test --target js`） | ✓ | v25.2.0 | — |
| `/tmp/flink-research/`（3 归档 + 生成版 Parser.jj） | release 证据核验 | ✓（本 session 确认） | 2026-08-07 缓存 | 缺失时 `verify_corpus.py` 报 `archive-not-present`（不 fail） |
| Doris FE / Flink cluster / DB / 网络 | — | ✗（**禁止**，D-06/SC4） | — | 不依赖，离线语义 |

**Missing dependencies with no fallback:** 无（全部门禁本地可跑；release 归档是可选研究证据）。
**Missing dependencies with fallback:** `/tmp/flink-research/` 缺失时 → `verify_corpus.py` 跳过归档 sha512（报 research-fixture-not-present 状态），fixture `.sql` sha256 常驻校验不受影响。

## Validation Architecture

> **Skipped.** `.planning/config.json` 显式 `"nyquist_validation": false`（本 session 读取 `[VERIFIED: .planning/config.json workflow.nyquist_validation]`），故按输出格式规则省略本段。Phase 12 的验证由既有 parity 三目标套件（570 测试）+ 新 gate 脚本的 `--check` 模式承担，验证协议仍走标准 CI 门禁。

## Security Domain

> 本阶段不引入网络/Doris-FE/Flink-cluster/DB 依赖，威胁面为**离线工件完整性**与**供应链 pin 验证**（D-06）。`security_enforcement` 未显式 false → 包含本节。

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | 无用户/凭据面（离线工具） |
| V3 Session Management | no | 无会话 |
| V4 Access Control | no | 无授权面 |
| V5 Input Validation | yes | manifest/`.sql`/快照路径的输入校验（`verify_corpus.py` 枚举 + 非空守卫 + header 精确匹配，Pitfall 8） |
| V6 Cryptography | yes | SHA-256（fixture）/SHA-512（release 归档）校验和；**不手写 hash**（stdlib `hashlib`） |

### Known Threat Patterns for {stdlib gate + MoonBit snapshot}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| 供应链：release 归档被替换 | Tampering | 归档 sha512 与 manifest `sha512` 列比对（`/tmp/flink-research` 本地复验）；fixture `.sql` sha256 常驻 pin |
| 供应链：manifest 篡改掩盖来源 | Tampering | `verify_corpus.py` 字段一致性（calcite/config 与 `dialect/flink.mbt` pin 表逐字比对）+ 快照完整性（行数 × 2） |
| 路径穿越：manifest fixture_id 注入路径 | Tampering | fixture `.sql` 路径由固定前缀 `parity/fixtures/flink/{profile}/{fixture_id}.sql` + fixture_id 白名单（`flink-grammar.`/`flink-lexical.` 前缀）构成；`verify_corpus.py` 不得接受含 `/`/`..` 的 fixture_id |
| 门禁盲区：空输入 / 0 文件扫描 | Spoofing | 非空守卫（manifest ≥1 行、快照数 == 行数×2、`.sql` 数匹配；仿 `check_naming.py:145-151`） |
| 伪造 commit/hash | Repudiation | 既有纪律：`unavailable-offline` + `known-gap`，绝不造假 SHA（STATE.md Deferred Items） |

## Sources

### Primary (HIGH confidence)
- `parity/` 全量盘点（本 session `ls`/`wc -l`/`moon test` 实测）：baseline_test.mbt / flink_lexical_test.mbt / flink_grammar_test.mbt / parity_test.mbt / run_*.mbt / moon.pkg / __snapshot__（433）/ fixtures / baseline-hashes.txt
- `scripts/baseline_diff.py`、`scripts/extract_flink_lexical.py`、`scripts/extract_flink_grammar.py`、`scripts/check_naming.py`（本 session 逐字读取）
- `.github/workflows/ci.yml`（6 job 逐字读取）
- `parity/fixtures/flink-grammar/manifest.tsv`（97 行）、`parity/fixtures/flink-lexical/manifest.tsv`（4 行）、`corpus/manifest.tsv`（44 行）
- `dialect/flink.mbt` FlinkProfileMetadata（pin 表）
- `.planning/phases/09/10/11 approved-changes.md`（D-08 注册表格式）
- `/tmp/flink-research/` 目录清单（2026-08-09 确认存在）

### Secondary (MEDIUM confidence)
- `.planning/phases/09-RESEARCH.md`（baseline 冻结流程、快照门禁设计）、`10-RESEARCH.md`（Calcite pin 表、flink-lexical manifest）、`11-RESEARCH.md`（flink-grammar fixtures、生产行号）
- `.planning/REQUIREMENTS.md` / `ROADMAP.md` / `STATE.md` / `12-CONTEXT.md`

### Tertiary (LOW confidence)
- 无（本阶段无 WebSearch/folklore 来源；全部 claims 来自磁盘核验或 [ASSUMED] 显式标注）

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — 零新增依赖；全部工具 stdlib/既有；`moon 0.1.20260724` + Python 3.9.23 实测
- Architecture: HIGH — 现状 inventory 全部磁盘测量；设计（manifest/diff-harness/compare_backends/verify_corpus）基于已核验的既有机制（snapshot 跨目标门禁、baseline_diff approved 引擎、corpus 报告模式）
- Pitfalls: HIGH — 8 个 pitfall 均从仓库既有注释/State 决策/先例提取（如 `--update` 禁令、differential.tsv 冲突先例）

**Research date:** 2026-08-09
**Valid until:** 2026-09-08（稳定域：Doris/Flink release 钉住 + manifest 契约；归档/版本如有变化需重验）
