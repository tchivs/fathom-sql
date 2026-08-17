# Phase 16: Documentation Truthfulness & Install Guide - Context

**Gathered:** 2026-08-17
**Status:** Ready for planning
**Mode:** auto（灰区全部采用推荐方案，见 Claude's Discretion）

<domain>
## Phase Boundary

本阶段修正 README 与 GETTING-STARTED 的失实声明（DOC-01），并新增「从 GitHub Release 安装 `fathom-lsp`」指引（DOC-02），使文档核对（docs tmp verify-*.json）通过。

本阶段不写 CHANGELOG（Phase 17）、不发布 npm/编辑器市场包（Phases 18–19）、不打 v1.0.0 tag / 不建 Release（Phase 20）、不改产品代码。

**Requirements:** DOC-01, DOC-02

## 现状事实（2026-08-17 侦察）
- `LICENSE` 文件存在且为 Apache-2.0（head 确认），但 `README.md` License 段写着「The repository currently does not include a `LICENSE` file; the license type and link are to be confirmed.」——**失实**。
- `README.md` 与 `README.zh-CN.md`：badge 与 Installation 引用 `moon 0.1.20260724`——**过时**（Phase 14 已三平台内容锁定 `moon 0.1.20260807`，见 `.github/moonbit-toolchain.json`）。
- `docs/GETTING-STARTED.md`：`git clone <repository-url>` 占位符 + 「the current working copy does not have a verifiable Git remote configured」——**失实**（origin 为 `https://github.com/tchivs/fathom-sql.git`）；MoonBit 前置版本仍写 0.1.20260724。
- `.planning/tmp/verify-*.json`：文档 claims 验证记录（README 11/11 通过），LICENSE 假声明未被列为 claim；`docs-work-manifest.json` 为文档生成清单（2026-08-04）。
- Phase 14 产物：release 资产命名 `fathom-lsp-linux-x86_64` / `fathom-lsp-macos-aarch64` / `fathom-lsp-windows-x86_64.exe` + `fathom-lsp-manifest.json`（SHA-256）+ `moon-toolchain-manifest.json`；Phase 15 已实现 `fathom-lsp --version` → `fathom-lsp 1.0.0`（exit 0）。
- docs/zh-CN/GETTING-STARTED.md 与 README.zh-CN.md 镜像同样的失实声明。

</domain>

<decisions>
## Implementation Decisions

### Documentation Truthfulness (DOC-01)
- **D-01（工具链引用修正）:** `README.md`/`README.zh-CN.md` 与 `docs/GETTING-STARTED.md`/`docs/zh-CN/GETTING-STARTED.md` 中所有 `moon 0.1.20260724` 引用与 badge 更新为 Phase 14 锁定的 `moon 0.1.20260807`，并说明工具链由 `.github/moonbit-toolchain.json`（官方 sidecar 校验 + 内容锁定）钉版；`moon.mod` 记录模块身份（name/version 0.1.0/preferred target），其版本注释保持既有 policy 语义。— **Reversibility:** costly — 版本引用是外部读者信任点。
- **D-02（LICENSE 声明修正）:** README（en+zh）License 段改为「Apache-2.0，见 [LICENSE](LICENSE)」，删除「无 LICENSE 文件/待确认」假声明。— **Reversibility:** one-way — 失实声明是发布阻塞项。
- **D-03（占位符与 remote 修正）:** GETTING-STARTED（en+zh）`git clone` 使用真实地址 `https://github.com/tchivs/fathom-sql.git`，删除「无可验证 remote」句。

### Install Guide (DOC-02)
- **D-04（Release 安装章节）:** README（en+zh）新增「Install `fathom-lsp` from GitHub Release」章节：按平台资产表（`fathom-lsp-linux-x86_64` / `fathom-lsp-macos-aarch64` / `fathom-lsp-windows-x86_64.exe`，来自 `https://github.com/tchivs/fathom-sql/releases`）；SHA-256 校验（下载 `fathom-lsp-manifest.json`，`sha256sum -c` 语义逐资产比对）；推荐安装位置 `~/.fathom/bin`（chmod +x、PATH 导出）；验证 `fathom-lsp --version` 输出 `fathom-lsp 1.0.0`（Phase 15 契约）。GETTING-STARTED（en+zh）增加指向该章节的一行。— **Reversibility:** one-way — 安装指引是发布消费者路径。

### Verification
- **D-05（verify-*.json 核对）:** 重生成被修改文档的 claims 记录（`verify-README.md.json`、`verify-GETTING-STARTED.md.json`），将「LICENSE 链接存在且为 Apache-2.0」「无 `<repository-url>` 占位符」「安装章节存在且含资产/SHA-256/安装位置/--version 验证」列为 claim 并全部通过；`docs-work-manifest.json` 状态保持 verified。核对以可执行 python 断言实现（en+zh 一致性一并断言）。— **Reversibility:** one-way — 核对记录是发布证据。
- **D-06（范围）:** 仅改 `README.md`、`README.zh-CN.md`、`docs/GETTING-STARTED.md`、`docs/zh-CN/GETTING-STARTED.md` 与 `.planning/tmp/` 核对记录；API/CONFIGURATION/ARCHITECTURE/DEVELOPMENT/TESTING 及其 verify JSON（均已 verified）不改。

### Claude's Discretion
`--auto` 模式下上述灰区全部采用推荐方案。规划者可决定章节标题、资产表格式与 claim 列表细节，但不得改变 D-01..D-06 的边界。

</decisions>

<canonical_refs>
## Canonical References

- `.planning/ROADMAP.md` §Phase 16 — goal、DOC-01/02、成功标准。
- `.planning/REQUIREMENTS.md` §DOC — DOC-01/02 原文。
- `.planning/phases/14-release-hygiene-toolchain-pinning/14-RELEASE-READINESS.md` — 三平台资产命名与 manifest 契约。
- `.planning/phases/15-product-versioning-binary-version/15-01-SUMMARY.md` — `fathom-lsp --version` 1.0.0 契约。
- `README.md` / `README.zh-CN.md` — 待修正文档。
- `docs/GETTING-STARTED.md` / `docs/zh-CN/GETTING-STARTED.md` — 待修正文档。
- `LICENSE` — Apache-2.0 现状。
- `.github/moonbit-toolchain.json` — 锁定工具链（moon 0.1.20260807）。
- `.planning/tmp/verify-README.md.json`、`.planning/tmp/verify-GETTING-STARTED.md.json`、`.planning/tmp/docs-work-manifest.json` — 核对记录格式。
- `.github/workflows/fathom-native-release.yml` — release 资产/清单命名（安装章节依据）。

</canonical_refs>

<deferred>
## Deferred Ideas

- CHANGELOG.md 与 1.0.0 条目（VER-03）→ Phase 17。
- npm/编辑器市场包安装文档 → Phases 18–19。
- 正式 v1.0.0 tag/Release 与发布后冒烟（含按本指引下载资产验证）→ Phase 20。

</deferred>

---

*Phase: 16-Documentation Truthfulness & Install Guide*
*Context gathered: 2026-08-17*
