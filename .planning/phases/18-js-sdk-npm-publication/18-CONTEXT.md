# Phase 18: JS SDK npm Publication - Context

**Gathered:** 2026-08-17
**Status:** Ready for planning
**Mode:** auto（灰区全部采用推荐方案，见 Claude's Discretion）

<domain>
## Phase Boundary

本阶段构建并本地验证 `@fathom/sql` npm 包（NPM-01：binding.js/binding.wasm + TypeScript 声明，Node/浏览器可调用 parse/format/complete/fingerprint/lineage/lint），随包提供最小冒烟测试与 dialect/profile 能力元数据（NPM-02）。

实际 `npm publish` 需要 registry 凭据——当前环境 `npm whoami` 返回 ENEEDAUTH（无凭据），因此发布动作按认证门处理：包与本地验证（npm pack + 消费者安装 + Node 冒烟）完整交付，注册表推送在取得 NPM_TOKEN 后执行（或并入 Phase 20 正式发布）。

本阶段不建 VS Code 扩展（Phase 19）、不打 v1.0.0 tag/Release（Phase 20）、不改产品核心。

**Requirements:** NPM-01, NPM-02

## 现状事实（2026-08-17）
- `binding/moon.pkg`：`pkgtype(kind: "foreign_library")`，js+wasm 均导出 8 个 `fathom_*_v1`（parse/format/complete/lint/fingerprint/lineage/dialect/capabilities），js format `esm`。
- 构建产物约定（web/scripts/offline-smoke.mjs）：`_build/js/debug/build/binding/binding.js`；release 构建为 `_build/js/release/build/binding/binding.js`，wasm 为 `_build/wasm/release/build/binding/binding.wasm`。
- `web/` 为私有 demo（`@fathom/sql-web-demo` 0.1.0，monaco）；npm SDK 包应独立于 `web/`。
- 产品版本 `1.0.0`（Phase 15）；`fathom_capabilities_v1()` 返回 dialect 列表与 per-dialect profile（doris 2.1/3.x/4.x，flink 三个 pinned releases）。
- 无 npm registry 凭据（ENEEDAUTH）；GitHub Actions 凭据可用（Phase 14/15 已证）。

</domain>

<decisions>
## Implementation Decisions

### Package
- **D-01（包结构与身份）:** 新目录 `npm/`，包名 `@fathom/sql`，版本 `1.0.0`（产品版本，Phase 15），`"type": "module"`（ESM-only），`files` 仅含构建产物与薄包装；`exports` 映射 "." → `{ types: "./index.d.ts", import: "./index.mjs" }`；`engines.node >= 18`。— **Reversibility:** one-way — 包名/版本是 npm 公开契约。
- **D-02（内容）:** `binding.js`（js target release 构建）+ `binding.wasm`（wasm target release 构建）+ `index.mjs`（ESM 薄包装：parse/format/complete/lint/fingerprint/lineage/dialects/capabilities 8 个类型化函数，调用 fathom_*_v1 字节函数并 JSON 解码，UTF-8 处理）+ `index.d.ts`（完整类型声明）+ `capabilities.json`（能力元数据：dialects + per-dialect profiles，由构建后脚本调用 fathom_capabilities_v1 生成）+ `README.md`（Node/浏览器用法）。— **Reversibility:** costly — 导出面是 JS 消费者契约。
- **D-03（构建管线）:** `npm/build.mjs`：`moon build --target js binding`（release）+ `moon build --target wasm binding`（release）→ 复制产物到 `npm/` 根 → 生成 `capabilities.json`（node 运行 built binding 的 `fathom_capabilities_v1`）→ `npm pack` 输出 tarball 供冒烟。— **Reversibility:** one-way — 构建/打包是发布管线。

### Verification
- **D-04（冒烟测试，NPM-02）:** `npm/smoke/` 独立消费者工程：`npm install <tarball>`（file: 路径）后 node 脚本：`parse("SELECT 1", "doris", "4.x", "strict")` 断言 valid + 无诊断；`fingerprint` 非空；`format` round-trip；`capabilities` 含 doris 2.1/3.x/4.x 与 flink pinned profiles。— **Reversibility:** one-way — 冒烟是发布门禁。
- **D-05（发布认证门）:** 无 NPM_TOKEN 时执行 `npm publish --dry-run` 验证打包正确，并把实际推送记录为认证门（blocking-human/auth）：提供 NPM_TOKEN 后运行 `npm publish`；否则并入 Phase 20 正式发布。— **Reversibility:** one-way — 注册表发布不可撤销。

### Claude's Discretion
`--auto` 模式下上述灰区全部采用推荐方案。规划者可决定包装函数命名、类型声明细节与冒烟断言清单，但不得改变 D-01..D-05 的边界。

</decisions>

<canonical_refs>
## Canonical References

- `.planning/ROADMAP.md` §Phase 18 — goal、NPM-01/02、成功标准。
- `.planning/REQUIREMENTS.md` §NPM — 需求原文。
- `binding/moon.pkg` — js/wasm 导出清单与 esm 配置。
- `web/scripts/offline-smoke.mjs` — 构建产物路径约定与字节函数 A4 顺序。
- `.planning/phases/15-product-versioning-binary-version/15-CONTEXT.md` — 产品版本 1.0.0。
- `docs/VERSIONING.md` — semver 策略（npm 包版本遵循产品版本）。

</canonical_refs>

<deferred>
## Deferred Ideas

- VS Code 扩展发布（VSC-01/02）→ Phase 19。
- 正式 v1.0.0 tag/Release 与全资产冒烟 → Phase 20。
- IntelliJ 插件市场发布 → 里程碑后续。

</deferred>

---

*Phase: 18-JS SDK npm Publication*
*Context gathered: 2026-08-17*
