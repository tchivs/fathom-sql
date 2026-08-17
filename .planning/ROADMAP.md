# Roadmap: Fathom SQL Parser SDK

## Overview

v1.0 shipped the lossless CST core, Doris DML/DDL + corpus, configurable formatting + CLI, and Native LSP / JS-Wasm facade / Web-Monaco / VS Code integration (27/27 requirements). v2.0 (redefined 2026-08-06) turned the single-dialect Doris parser into a multi-dialect SQL SDK: a dialect abstraction layer, a Flink SQL dialect across the whole toolchain, and product-neutral naming (binaries/schema/error codes/extensions/docs). v3.0 (Analysis and Intelligence, 2026-08-13) delivered catalog-backed analysis (ANAL-01), Doris lint (LINT-01), stable fingerprints (FING-01), column lineage (LINE-01), and benchmark-gated incremental parsing — EDIT-01 descoped with `moon bench` evidence. v4.0 (Release Readiness, 2026-08-13) turns the SDK into a formally releasable 1.0 product: pinned release toolchain, corrected docs, product versioning (semver 1.0.0), npm / VS Code / IntelliJ publication, and a formal 1.0.0 release.

## Milestones

- ✅ **v1.0 — Doris SQL Parser SDK MVP** — Phases 1-4 (shipped 2026-08-05)
- ✅ **v2.0 — Multi-Dialect: Flink SQL & Neutral Naming** — Phases 9-13 (shipped 2026-08-10)
- ✅ **v3.0 — Analysis and Intelligence** — Phases 5-8 (shipped 2026-08-13)
- 🔄 **v4.0 — Release Readiness** — Phases 14-20 (planning 2026-08-13)

## Phases

<details>
<summary>✅ v1.0 — Doris SQL Parser SDK MVP (Phases 1-4) — SHIPPED 2026-08-05</summary>

- **Archive:** [v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md) · [v1.0-REQUIREMENTS.md](milestones/v1.0-REQUIREMENTS.md) · [v1.0-MILESTONE-AUDIT.md](v1.0-MILESTONE-AUDIT.md)
- **Status:** SHIPPED (override_closeout — 5 documented verification overrides in STATE.md Deferred Items)

- [x] Phase 1: Core Kernel — lossless CST, SELECT/Pratt expressions, round-trip
- [x] Phase 2: Doris Completeness and Corpus — DML/DDL + versioned corpus
- [x] Phase 3: Formatting and Safe Edits — CST printer + format CLI
- [x] Phase 4: Ecosystem and Multi-Target Delivery — Native LSP / JS-Wasm / Web / VS Code

</details>

<details>
<summary>✅ v2.0 — Multi-Dialect: Flink SQL & Neutral Naming (Phases 9-13) — SHIPPED 2026-08-10</summary>

- **Archive:** [v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md) · [v2.0-REQUIREMENTS.md](milestones/v2.0-REQUIREMENTS.md) · [v2.0-phases](milestones/v2.0-phases/)
- **Status:** SHIPPED (verified_closeout — artifact audit clear, all 5 phases verified, 24/24 requirements complete, threats_open 0)

- [x] Phase 9: Dialect Boundary and Neutral Naming (7 plans)
- [x] Phase 10: Flink Release Profiles and Lexical Core (3 plans)
- [x] Phase 11: Flink Grammar and Recoverable CST (4 plans)
- [x] Phase 12: Cross-Dialect Corpus and Parity Gates (3 plans)
- [x] Phase 13: Toolchain and Editor Packaging (7 plans; verified 28/28)

</details>

<details>
<summary>✅ v3.0 — Analysis and Intelligence (Phases 5-8) — SHIPPED 2026-08-13</summary>

- **Archive:** [v3.0-ROADMAP.md](milestones/v3.0-ROADMAP.md) · [v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md) · [v3.0-phases](milestones/v3.0-phases/)
- **Research:** [v1.0-research/SUMMARY.md](milestones/v1.0-research/SUMMARY.md) — v1/v2 analysis-feature research (archived 2026-08-06)
- **Status:** SHIPPED (verified_closeout — artifact audit clear; 6/7 requirements delivered, EDIT-01 descoped with benchmark evidence)

- [x] Phase 5: Closeout and Analysis Foundation (4 plans) — CLOSE-01/02 verified, ANAL-01 delivered
- [x] Phase 6: Lint and Fingerprint (4 plans) — LINT-01 + FING-01 delivered
- [x] Phase 7: Column Lineage (5 plans) — LINE-01 delivered
- [x] Phase 8: Incremental Parsing (Benchmark-Gated) (4 plans, 2 executed) — EDIT-01 DESCoped with `moon bench` evidence

</details>

## Current Milestone: v4.0 — Release Readiness (Phases 14-20)

**Status:** Planning — 19 requirements across 8 categories (see [REQUIREMENTS.md](REQUIREMENTS.md))

| # | Phase | Goal | Requirements | Success Criteria |
|---|-------|------|--------------|------------------|
| 14 | Release Hygiene & Toolchain Pinning | 干净工作树 + 钉版发布工具链 | HYG-01/02/03, TC-01/02 | 5 |
| 15 | Product Versioning & Binary `--version` | semver 策略 + 二进制版本报告 | VER-01/02 | 3 |
| 16 | Documentation Truthfulness & Install Guide | 文档失实修正 + Release 安装指引 | DOC-01/02 | 3 |
| 17 | Changelog & Release Disclosure | CHANGELOG + 发布披露 | VER-03, DIS-01/02 | 3 |
| 18 | JS SDK npm Publication | `@fathom/sql` 发布到 npm | NPM-01/02 | 3 |
| 19 | Editor Extension Publication | VS Code + IntelliJ 发布 | VSC-01/02, JBR-01/02 | 3 |
| 20 | Formal 1.0.0 Release & Verification | 正式发布 + 产物冒烟 | VER-04 | 3 |

### Phase Details

### Phase 14: Release Hygiene & Toolchain Pinning

**Goal**: 提交未提交 CI 变更、生成物纳入 gitignore、清理 `.planning` 杂项；release 管线钉版 moon 工具链并跑通发布门禁矩阵。
**Depends on**: Phase 13
**Requirements**: HYG-01, HYG-02, HYG-03, TC-01, TC-02
**Success Criteria** (what must be TRUE):

1. `git status --porcelain` 无未提交产品文件、无 untracked 生成物；`jetbrains-plugin.yml` 升级已提交
2. `fathom-sql/pkg.generated.mbti` 及同类 `moon info` 产物被 `.gitignore` 覆盖，`git status` 不再列出
3. `.planning/research/.cache/`、quick 计划目录、`milestones/v1.0-research/` 已清理或归档
4. `fathom-native-release.yml` 以钉住的 moon 版本构建（无 `latest`），并记录精确版本到发布工件
5. 发布门禁矩阵（native/js/wasm parity、`diff_parity --frozen-only`、`check_naming`、corpus `--check`）可运行且通过

**Plans**: 2/5 plans executed

Plans:
**Wave 1**

- [ ] 14-01-PLAN.md — Signed four-native-runner freeze with exact-set verifier, atomic lock, and blocking evidence approval

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 14-02-PLAN.md — Behavior-tested Unix/PowerShell installers migrate every ordinary CI MoonBit bootstrap to the lock

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 14-03-PLAN.md — Real nine-command release-gates run plus behavior-tested four-record aggregation block publication

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 14-04-PLAN.md — Exact JetBrains action-only delta and generated-interface/research-cache hygiene

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 14-05-PLAN.md — Quick/archive preservation and executable final porcelain readiness classifier/matrix

> 2026-08-14 用户批准拆分执行：HYG waves 4-5 先行；14-01..14-03 因官方 MoonBit 渠道无 darwin-x86_64 工件、无静态版本渠道、无 core 官方校验和（全部 403 实测证据）按 D-01/D-03 fail-closed 阻塞。同日用户进一步批准修订 D-01/D-03 为三平台内容锁定（linux-x86_64 / darwin-aarch64 / windows-x86_64），TC 已解冻执行中。

### Phase 15: Product Versioning & Binary `--version`

**Goal**: 定义产品 semver 策略并为发布二进制实现 `--version` 版本报告。
**Depends on**: Phase 14
**Requirements**: VER-01, VER-02
**Success Criteria** (what must be TRUE):

1. semver 策略已记录（首个公开版本 1.0.0；`fathom.*.v1` 契约稳定承诺；破坏性变更须 bump 契约版本）
2. `fathom-sql --version` 与 `fathom-lsp --version` 退出码 0 并输出产品版本字符串，与发布 tag 一致
3. 测试覆盖 `--version`（退出码 0 + 正确版本字符串）

**Plans**: TBD

Plans:

- [ ] 15-01: TBD

### Phase 16: Documentation Truthfulness & Install Guide

**Goal**: 修正 README/GETTING-STARTED 失实声明，新增 Release 安装指引。
**Depends on**: Phase 15
**Requirements**: DOC-01, DOC-02
**Success Criteria** (what must be TRUE):

1. README 链接存在且可用的 Apache-2.0 LICENSE；README/GETTING-STARTED 无 `<repository-url>` 占位符、无"无 LICENSE"假声明，remote 为 `tchivs/fathom-sql`
2. README 含「从 GitHub Release 安装 `fathom-lsp`」章节（平台资产、SHA-256 校验、安装位置、`fathom-lsp --version` 验证）
3. 文档核对（docs tmp verify-*.json 工作流）通过

**Plans**: TBD

Plans:

- [ ] 16-01: TBD

### Phase 17: Changelog & Release Disclosure

**Goal**: 新增 CHANGELOG 与发布披露文档，使 1.0 边界在发布前可见。
**Depends on**: Phase 16
**Requirements**: VER-03, DIS-01, DIS-02
**Success Criteria** (what must be TRUE):

1. CHANGELOG.md 存在，1.0.0 条目涵盖自 v0.1.0 Release 以来的用户可见变更
2. RELEASE-NOTES.md（或等价）披露 Flink 语法级范围、Wasm GC 非一等、corpus provenance 缺口、5 项验证 override、工具链版本策略
3. 发布模板/管线引用披露文档（DIS-02），Release notes 在下载前可见边界

**Plans**: TBD

Plans:

- [ ] 17-01: TBD

### Phase 18: JS SDK npm Publication

**Goal**: 将 `@fathom/sql` 作为公开 npm 包发布。
**Depends on**: Phase 15
**Requirements**: NPM-01, NPM-02
**Success Criteria** (what must be TRUE):

1. `@fathom/sql@1.0.0` 发布到 npm，含 binding.js/binding.wasm + `.d.ts` 类型声明
2. 全新消费方冒烟：临时目录 `npm install @fathom/sql@1.0.0`，Node 加载并成功 parse/format 示例 SQL
3. 包内 dialect/profile 能力元数据正确

**Plans**: TBD

Plans:

- [ ] 18-01: TBD

### Phase 19: Editor Extension Publication

**Goal**: 将 VS Code 扩展与 IntelliJ 插件发布到各自市场。
**Depends on**: Phase 15
**Requirements**: VSC-01, VSC-02, JBR-01, JBR-02
**Success Criteria** (what must be TRUE):

1. VS Code 扩展发布到 Open VSX（及/或 VS Code Marketplace），可从市场安装
2. IntelliJ 插件发布到 JetBrains Marketplace，可从 IDE 插件市场安装
3. 两个扩展 README 均为发布版安装说明（非从源码构建），含 fathom-lsp 获取与路径配置

**Plans**: TBD

Plans:

- [ ] 19-01: TBD

### Phase 20: Formal 1.0.0 Release & Verification

**Goal**: 正式打 `v1.0.0` tag 发布并验证发布产物。
**Depends on**: Phases 17, 18, 19
**Requirements**: VER-04
**Success Criteria** (what must be TRUE):

1. `v1.0.0` tag 触发 `fathom-native-release`，4 平台资产 + SHA-256 manifest 上传 GitHub Release
2. Release notes 引用披露文档
3. 发布后冒烟：下载各平台资产校验 SHA-256，`fathom-lsp --version` 报告 1.0.0

**Plans**: TBD

Plans:

- [ ] 20-01: TBD

**Phase 15: Product Versioning & Binary `--version`**
Goal: 定义产品 semver 策略并为发布二进制实现 `--version` 版本报告。
Requirements: VER-01, VER-02
Success criteria:

1. semver 策略已记录（首个公开版本 1.0.0；`fathom.*.v1` 契约稳定承诺；破坏性变更须 bump 契约版本）
2. `fathom-sql --version` 与 `fathom-lsp --version` 退出码 0 并输出产品版本字符串，与发布 tag 一致
3. 测试覆盖 `--version`（退出码 0 + 正确版本字符串）

**Phase 16: Documentation Truthfulness & Install Guide**
Goal: 修正 README/GETTING-STARTED 失实声明，新增 Release 安装指引。
Requirements: DOC-01, DOC-02
Success criteria:

1. README 链接存在且可用的 Apache-2.0 LICENSE；README/GETTING-STARTED 无 `<repository-url>` 占位符、无"无 LICENSE"假声明，remote 为 `tchivs/fathom-sql`
2. README 含「从 GitHub Release 安装 `fathom-lsp`」章节（平台资产、SHA-256 校验、安装位置、`fathom-lsp --version` 验证）
3. 文档核对（docs tmp verify-*.json 工作流）通过

**Phase 17: Changelog & Release Disclosure**
Goal: 新增 CHANGELOG 与发布披露文档，使 1.0 边界在发布前可见。
Requirements: VER-03, DIS-01, DIS-02
Success criteria:

1. CHANGELOG.md 存在，1.0.0 条目涵盖自 v0.1.0 Release 以来的用户可见变更
2. RELEASE-NOTES.md（或等价）披露 Flink 语法级范围、Wasm GC 非一等、corpus provenance 缺口、5 项验证 override、工具链版本策略
3. 发布模板/管线引用披露文档（DIS-02），Release notes 在下载前可见边界

**Phase 18: JS SDK npm Publication**
Goal: 将 `@fathom/sql` 作为公开 npm 包发布。
Requirements: NPM-01, NPM-02
Success criteria:

1. `@fathom/sql@1.0.0` 发布到 npm，含 binding.js/binding.wasm + `.d.ts` 类型声明
2. 全新消费方冒烟：临时目录 `npm install @fathom/sql@1.0.0`，Node 加载并成功 parse/format 示例 SQL
3. 包内 dialect/profile 能力元数据正确

**Phase 19: Editor Extension Publication**
Goal: 将 VS Code 扩展与 IntelliJ 插件发布到各自市场。
Requirements: VSC-01, VSC-02, JBR-01, JBR-02
Success criteria:

1. VS Code 扩展发布到 Open VSX（及/或 VS Code Marketplace），可从市场安装
2. IntelliJ 插件发布到 JetBrains Marketplace，可从 IDE 插件市场安装
3. 两个扩展 README 均为发布版安装说明（非从源码构建），含 fathom-lsp 获取与路径配置

**Phase 20: Formal 1.0.0 Release & Verification**
Goal: 正式打 `v1.0.0` tag 发布并验证发布产物。
Requirements: VER-04
Success criteria:

1. `v1.0.0` tag 触发 `fathom-native-release`，4 平台资产 + SHA-256 manifest 上传 GitHub Release
2. Release notes 引用披露文档
3. 发布后冒烟：下载各平台资产校验 SHA-256，`fathom-lsp --version` 报告 1.0.0

## Backlog

No unmapped v2.0 requirements remain: all 24 active requirements map exactly once to Phases 9-13. Post-v2 candidates remain deliberately outside this roadmap: `FLINK-FUTURE-01` (planner/catalog/type/execution equivalence), `TOOL-FUTURE-01` (semantic editor intelligence), `DIALECT-FUTURE-01` (third-party dialect registry), `EDIT-FUTURE-01` (benchmark-gated incremental CST/refactors), `TARGET-FUTURE-01` (Wasm GC first-class support), and `CONVERT-FUTURE-01` (explicit opt-in transpilation). The deferred v3.0 analysis requirements remain archived below and are not v2.0 mappings.

## Dependency and Ordering Rationale

1. **Phase 9 first** — every lexer, parser route, public schema, host, and naming surface needs one explicit immutable dialect/profile context; freezing the Doris baseline before refactoring prevents new tests from hiding regressions.
2. **Phase 10 before grammar** — Flink release/source/Calcite pins and lexical policy determine what “supported” means; the 2.1.3 Calcite gap and quote/comment/literal behavior must be resolved before accepting grammar.
3. **Phase 11 after lexical contract** — shared source/token/CST/Pratt/recovery mechanics can then route to separate Flink productions for core SQL, DDL, Window TVF, and MATCH_RECOGNIZE without a Doris fallback; the frozen Doris baseline remains a hard gate.
4. **Phase 12 after parser behavior** — pinned corpus metadata, acceptance/recovery categories, Doris parity, and Native/JS/linear-Wasm comparisons need stable CST and serialized results; this is a release gate, not cleanup.
5. **Phase 13 last** — formatter/completion/analyzer and CLI/LSP/Web/VS Code/IntelliJ adapters consume the stable dialect-aware API/schema. Real host and ABI smoke tests validate that no adapter silently chooses a dialect or maintains a second parser.

**Execution order:** Phase 9 → Phase 10 → Phase 11 → Phase 12 → Phase 13. No phase may replace explicit selection with automatic detection, generic MySQL fallback, Flink runtime/planner dependencies, default transpilation, or an unbenchmarked incremental parser.

**v4.0 ordering:** Phase 14 → 15 → 16 → 17 → 18 → 19 → 20.

1. **Phase 14 first** — every downstream artifact build and the release itself needs a clean tree and a pinned toolchain; the release gate matrix proves the tree is releasable before packaging anything.
2. **Phase 15 before 16/17** — install guide and changelog reference the version string and semver policy, so versioning must land first.
3. **Phase 16 before 17** — disclosure/changelog build on corrected docs and the real install surface.
4. **Phase 17 before 20** — release notes need CHANGELOG + disclosure material.
5. **Phases 18/19 after 15** — published packages must carry the 1.0.0 version; the two tracks are independent of each other.
6. **Phase 20 last** — the formal release consumes every prior artifact and gate.

## Next Milestone

v4.0 Release Readiness is the current milestone (Phases 14-20, see above). The v5.0 milestone is not yet defined — rerun `/gsd:new-milestone` after v4.0 ships.

**Coverage (v4.0):** 19/19 requirements mapped exactly once — Phase 14: 5 (HYG-01/02/03, TC-01/02), Phase 15: 2 (VER-01/02), Phase 16: 2 (DOC-01/02), Phase 17: 3 (VER-03, DIS-01/02), Phase 18: 2 (NPM-01/02), Phase 19: 4 (VSC-01/02, JBR-01/02), Phase 20: 1 (VER-04).
