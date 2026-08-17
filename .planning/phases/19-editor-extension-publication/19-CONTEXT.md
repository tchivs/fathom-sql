# Phase 19: Editor Extension Publication - Context

**Gathered:** 2026-08-17
**Status:** Ready for planning
**Mode:** auto（灰区全部采用推荐方案，见 Claude's Discretion）

<domain>
## Phase Boundary

本阶段把 VS Code 扩展从源码使用推进到市场发布形态（VSC-01：发布到 Open VSX 与/或 VS Code Marketplace），并更新扩展 README 为 release 版本安装指引（VSC-02：`fathom-lsp` 获取 + `fathom.serverPath` 配置）。

实际市场发布需要发布者凭据（Open VSX 的 OVSX_TOKEN、Marketplace 的 Azure DevOps PAT + 已注册 publisher）；当前环境无凭据，因此打包验证完整交付，推送动作以认证门呈现。

本阶段不打 v1.0.0 tag/Release（Phase 20）、不发布 IntelliJ 市场（里程碑后续）、不改核心产品。

**Requirements:** VSC-01, VSC-02

## 现状事实（2026-08-17）
- `vscode/package.json`：name `fathom-sql-language-client`、displayName "Fathom SQL Language Client"、**version 0.1.0**、**`private: true`**（发布前置必须移除）、publisher `fathom`、engines.vscode ^1.91.0、main ./dist/extension.js、配置 `fathom.dialect`/`fathom.profile`/`fathom.serverPath`（默认 `fathom-lsp`）。
- scripts：compile / package（`npm run compile && vsce package`）/ host-verify（Phase 4 已关闭证据）。
- 依赖：@vscode/vsce 3.9.2（release-only 钉版）、vscode-languageclient 10.1.0；无 ovsx CLI（Open VSX 发布需 `ovsx` 或 vsce 对 Marketplace）。
- Phase 16 安装指引：`fathom-lsp` 从 GitHub Release 获取 + SHA-256 校验 + `fathom-lsp --version` 验证（`npm/` 与 README 已有）。
- 产品版本 1.0.0（Phase 15）。

</domain>

<decisions>
## Implementation Decisions

### Manifest and README (VSC-02)
- **D-01（发布化 manifest）:** `vscode/package.json` version 0.1.0 → **1.0.0**（产品版本）；移除 `private: true`（市场发布前置）；其余字段（publisher `fathom`、engines、activation、配置）不变。— **Reversibility:** one-way — 扩展版本/发布元数据是市场契约。
- **D-02（扩展 README 发布指引）:** `vscode/README.md` 更新为 release 版安装指引：从 VS Code Marketplace / Open VSX 安装扩展；`fathom-lsp` 从 GitHub Release 获取（Phase 16 指引：资产 + SHA-256 校验 + 安装位置 + `fathom-lsp --version` 验证）；`fathom.serverPath` 配置为本地可执行路径；`fathom.dialect`/`fathom.profile` 必填说明。— **Reversibility:** one-way — 安装指引是用户获取路径。

### Publication (VSC-01)
- **D-03（打包验证）:** `npm run package`（compile + `vsce package`）产出有效 .vsix；`vsce ls` 校验包内容（dist/extension.js、package.json、README、language-configuration）。— **Reversibility:** one-way — vsix 内容是发布载体。
- **D-04（发布认证门）:** 无凭据时不执行推送：Open VSX 需 `OVSX_TOKEN`（+ 发布者命名空间 `fathom` 注册），Marketplace 需 Azure DevOps PAT + publisher `fathom` 注册（vsce login）。打包验证后以认证门记录；不伪造发布。— **Reversibility:** one-way — 市场发布不可撤销。

### Claude's Discretion
`--auto` 模式下上述灰区全部采用推荐方案。规划者可决定 README 指引措辞与 vsix 校验命令细节，但不得改变 D-01..D-04 的边界。

</decisions>

<canonical_refs>
## Canonical References

- `.planning/ROADMAP.md` §Phase 19 — goal、VSC-01/02、成功标准。
- `.planning/REQUIREMENTS.md` §VSC — 需求原文。
- `vscode/package.json` — manifest 现状。
- `vscode/README.md` — 待更新指引。
- `.planning/phases/16-documentation-truthfulness-install-guide/16-01-SUMMARY.md` — fathom-lsp 获取指引。
- `.planning/phases/15-product-versioning-binary-version/15-CONTEXT.md` — 产品版本 1.0.0。

</canonical_refs>

<deferred>
## Deferred Ideas

- 正式 v1.0.0 tag/Release → Phase 20。
- IntelliJ 插件市场上传自动化 → 里程碑后续。

</deferred>

---

*Phase: 19-Editor Extension Publication*
*Context gathered: 2026-08-17*
