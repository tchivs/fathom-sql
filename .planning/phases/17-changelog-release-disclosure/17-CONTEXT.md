# Phase 17: Changelog & Release Disclosure - Context

**Gathered:** 2026-08-17
**Status:** Ready for planning
**Mode:** auto（灰区全部采用推荐方案，见 Claude's Discretion）

<domain>
## Phase Boundary

本阶段为 1.0.0 发布准备消费者可见的变更记录与边界披露：新增 `CHANGELOG.md` 的 1.0.0 条目（VER-03，覆盖自 v0.1.0 以来用户可见变更）；新增发布披露文档（DIS-01，诚实声明 Flink 语法级覆盖、Wasm GC 非一等公民、corpus 溯源缺口、5 项验证覆盖、工具链版本策略）；并接线 GitHub Release notes 引用披露文档（DIS-02）。

本阶段不创建 `v1.0.0` tag / GitHub Release（Phase 20 触发并执行发布后冒烟）、不发布 npm/编辑器市场包（Phases 18–19）、不改产品代码。

**Requirements:** VER-03, DIS-01, DIS-02

## 现状事实（2026-08-17）
- Git tags：`v0.1.0`、`v1.0`、`v2.0`、`v3.0` 存在；"自 v0.1.0 以来" = v1.0 无损 CST 内核 + Doris DML/DDL/corpus + 格式化 + CLI、v2.0 方言抽象 + Flink 方言 + 中性命名、v3.0 catalog 分析、v4.0 发布就绪（本里程碑：工具链钉版、版本化、文档、CHANGELOG、npm、编辑器、正式发布）。
- 披露边界事实（STATE/计划决策）：
  1. **Flink 为语法级覆盖**——无 planner/catalog/type/execution 等价（FLINK-05/06）；SDK 是 parser-and-toolchain-only（REQUIREMENTS 风险表）。
  2. **Wasm GC 非一等公民**——仅广告 linear Wasm（STATE 决策）；STACK.md 将 wasm-gc 列为可选评估目标。
  3. **corpus 溯源缺口**——corpus revisions 保持 `unavailable-offline`/`known-gap`，不伪造 SHA（STATE Blockers）。
  4. **5 项已记录验证覆盖**——"Known verification overrides: 5 (see STATE.md Deferred Items)"。
  5. **工具链版本策略**——Phase 14 三平台内容锁定 `moon 0.1.20260807`（官方 sidecar；core 记录式摘要；macOS Intel 退出发布目标，D-01/D-03 修订）；Phase 15 产品版本 `1.0.0` 与 moon.mod `0.1.0` 解耦。
- Release workflow（Phase 14/15）：release job 用 `gh release create --generate-notes`；Phase 20 将正式触发。

</domain>

<decisions>
## Implementation Decisions

### Changelog (VER-03)
- **D-01（CHANGELOG.md）:** 仓库根新增 `CHANGELOG.md`，格式采用 Keep-a-Changelog 风格：`## [1.0.0] - 2026-08-17` 条目，分 Added/Changed/Fixed 小节，覆盖自 v0.1.0 以来的用户可见变更（无损 CST 核心、Doris 2.1/3.x/4.x profile、严格/编辑器双模式、格式化、CLI parse/format/lsp/lint/fingerprint/lineage、方言抽象 + Flink 语法级支持、catalog 注入分析、fathom.*.v1 wire 契约、三平台原生发布资产、工具链内容锁定、`--version`）；条目首部注明 v0.1.0 为上一公开基线。— **Reversibility:** costly — CHANGELOG 是消费者与审计历史。
- **D-02（披露文档）:** 仓库根新增 `RELEASE-NOTES.md`（DIS-01 指定的名称），固定五段边界披露：Flink 语法级覆盖（无 planner/catalog/type/execution 等价）、Wasm GC 非一等公民（仅 linear Wasm）、corpus 溯源 `unavailable-offline` 缺口、5 项验证覆盖（引用 `.planning/STATE.md` Deferred Items）、工具链版本策略（三平台内容锁定 `moon 0.1.20260807`、core 记录式摘要、macOS Intel 非发布目标、产品/模块版本解耦）；文档头部声明"下载资产前请阅读本披露"。— **Reversibility:** one-way — 披露是消费者信任与合规边界。

### Release Notes Wiring (DIS-02)
- **D-03（workflow 接线）:** `fathom-native-release.yml` release job 的创建步骤把 `--generate-notes` 替换为 `--notes-file RELEASE-NOTES.md`，使 Release notes 直接呈现披露文档（消费者在下载前看到边界）；`--clobber` 上传逻辑不变。Phase 20 触发时即生效。— **Reversibility:** one-way — Release notes 内容是发布契约。

### Verification
- **D-04（可执行核对）:** python 断言：`CHANGELOG.md` 含 `[1.0.0]` 条目与关键用户可见项（Doris/Flink/CLI/`--version`/三平台）；`RELEASE-NOTES.md` 含五段边界全部要点（Flink 语法级、Wasm GC、unavailable-offline、5 overrides、工具链策略）；workflow 含 `--notes-file RELEASE-NOTES.md` 且不含 `--generate-notes`。— **Reversibility:** one-way — 核对是发布证据。

### Claude's Discretion
`--auto` 模式下上述灰区全部采用推荐方案。规划者可决定 CHANGELOG 条目措辞与披露文档小节结构，但不得改变 D-01..D-04 的边界。

</decisions>

<canonical_refs>
## Canonical References

- `.planning/ROADMAP.md` §Phase 17 — goal、VER-03/DIS-01/DIS-02、成功标准。
- `.planning/REQUIREMENTS.md` §VER/DIS — 需求原文与风险表（Flink planner 边界行）。
- `.planning/STATE.md` §Blockers/Concerns 与 §Deferred Items — corpus 缺口与 5 项验证覆盖。
- `.planning/phases/14-release-hygiene-toolchain-pinning/14-CONTEXT.md` — D-01/D-03 三平台工具链修订。
- `.planning/phases/15-product-versioning-binary-version/15-CONTEXT.md` + `docs/VERSIONING.md` — 产品版本策略。
- `.github/workflows/fathom-native-release.yml` — release notes 接线点。
- ROADMAP 概述行 — v1.0/v2.0/v3.0/v4.0 里程碑用户可见能力。

</canonical_refs>

<deferred>
## Deferred Ideas

- 正式 `v1.0.0` tag/Release 与发布后冒烟（下载资产校验 SHA-256 + `fathom-lsp --version`）→ Phase 20。
- npm/编辑器市场包发布与版本披露 → Phases 18–19。
- 文档安装章节 → Phase 16（已完成）。

</deferred>

---

*Phase: 17-Changelog & Release Disclosure*
*Context gathered: 2026-08-17*
