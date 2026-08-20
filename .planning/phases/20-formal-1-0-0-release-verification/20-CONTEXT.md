# Phase 20: Formal 1.0.0 Release & Verification - Context

**Gathered:** 2026-08-17/20
**Status:** Ready for planning
**Mode:** auto（灰区全部采用推荐方案，见 Claude's Discretion）

<domain>
## Phase Boundary

正式打 `v1.0.0` tag 并推送，触发 `fathom-native-release` 管线（三平台资产 + SHA-256 manifest + GitHub Release，notes 引用 `RELEASE-NOTES.md`），同时触发 `@fathom/sql` npm 发布与 VS Code 扩展发布；随后执行发布后冒烟（下载各平台资产校验 SHA-256、`fathom-lsp --version` 报告 1.0.0）。

**Requirements:** VER-04

## 现状事实（2026-08-20）
- master 已推送远端（`6bc675b`），全部 Phase 14–19 工作就位；`fathom-native-release.yml` 注册 active（post-cutover 已验）。
- release 管线（Phase 14/15/17）：tag push 触发 → 三平台 build（lock-driven 安装器 + 每平台 `moon-toolchain.json` 证据）→ `release-gates`（九命令）→ `release` job（`needs:[build, release-gates]`，evidence 聚合验证、`fathom-lsp-manifest.json` + `moon-toolchain-manifest.json`、`--notes-file RELEASE-NOTES.md`、`contents:write`）。
- 注：路线图成功标准写「4 平台」，Phase 14 D-01/D-03 修订后实际为**三平台**（linux-x86_64 / macos-aarch64 / windows-x86_64；macOS Intel 无官方构建）。
- npm：`npm-publish.yml` 已接线（`NPM_TOKEN`，tag `v*` 触发）→ `@fathom/sql@1.0.0`。
- VS Code：`vsce-publish.yml` 已接线（`VSCODE_MARKETPLACE_PAT`，tag `v*` 触发）→ `fathom-sql.sql` v1.0.0 **已手动发布成功**（Phase 19 注记）；tag 再触发需幂等跳过（同版本已存在）。
- `fathom-lsp --version` → `fathom-lsp 1.0.0`（Phase 15）；发布后冒烟可在本机 Linux 直接运行 linux 资产。
- gh 已认证（tchivs，repo scope，含 workflow/tag 权限）。

</domain>

<decisions>
## Implementation Decisions

- **D-01（打 tag）:** 在 master HEAD 打 `v1.0.0` 并推送（annotated tag），触发三条发布管线。— **Reversibility:** one-way — 正式发布不可撤销。
- **D-02（三平台资产）:** 以 Phase 14 修订的三平台为准（路线图"4 平台"文本过时）；资产 `fathom-lsp-linux-x86_64` / `fathom-lsp-macos-aarch64` / `fathom-lsp-windows-x86_64.exe` + `fathom-lsp-manifest.json` + `moon-toolchain-manifest.json`。
- **D-03（vsce 幂等）:** `vsce-publish.yml` 发布前用画廊 API 检查 `fathom-sql.sql` 同版本是否已存在，存在则跳过发布（Phase 19 已发布 1.0.0）。
- **D-04（npm 验证）:** tag 触发 npm 发布后，用 `npm view @fathom/sql@1.0.0` 验证注册表可见。
- **D-05（发布后冒烟）:** 从 `v1.0.0` Release 下载 linux 资产 + `fathom-lsp-manifest.json`，SHA-256 比对，运行 `fathom-lsp --version` 断言 `fathom-lsp 1.0.0`（本机 Linux 可执行）。

### Claude's Discretion
`--auto` 模式下上述灰区全部采用推荐方案。

</decisions>

<canonical_refs>
## Canonical References

- `.planning/ROADMAP.md` §Phase 20 — VER-04、成功标准（含过时"4 平台"表述，以 D-01/D-03 修订为准）。
- `.planning/REQUIREMENTS.md` §VER-04。
- `.github/workflows/fathom-native-release.yml` / `npm-publish.yml` / `vsce-publish.yml` — 三条发布管线。
- `RELEASE-NOTES.md` — Release notes 披露（Phase 17）。
- `.planning/phases/14-release-hygiene-toolchain-pinning/14-RELEASE-READINESS.md` — 三平台证据与 dry-run 先例。
- `.planning/phases/19-editor-extension-publication/19-01-SUMMARY.md` — 扩展已发布注记。

</canonical_refs>

<deferred>
## Deferred Ideas

- IntelliJ 插件市场发布 → 里程碑后续。
- Open VSX 发布（需 OVSX_TOKEN + 注册 `fathom-sql` 命名空间）→ 可选跟进。

</deferred>

---

*Phase: 20-Formal 1.0.0 Release & Verification*
*Context gathered: 2026-08-20*
