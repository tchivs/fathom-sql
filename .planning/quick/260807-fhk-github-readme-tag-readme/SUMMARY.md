---
phase: quick
plan: 260807-fhk-github-readme-tag-readme
subsystem: repository-identity
tags: [github, rename, readme, jetbrains, naming]
status: complete
---

# GitHub 仓库重命名与公开链接同步总结

已将公开产品链接和 JetBrains managed downloader 从旧仓库切换到 `tchivs/fathom-sql`，并通过 GitHub REST API 完成仓库重命名；未触碰解析器、工作流或既有用户未提交文件。

## 完成事项

- 根 README 英文/中文标题更新为 `Fathom SQL Parser SDK`，分别加入 `Repository` / `GitHub 仓库` 链接。
- JetBrains README 的 managed download、release workflow 和 Marketplace homepage 三处链接更新为 `tchivs/fathom-sql`。
- `FathomNativeDownloader.DEFAULT_REPOSITORY` 更新为 `tchivs/fathom-sql`，资产、manifest 校验、缓存和 fallback 行为未改动。
- `scripts/check_naming.py` 删除旧仓库 URL allowlist、相关说明及逐行替换分支；Doris 方言和 provenance 规则保留。
- 本地验证通过：`git diff --check`、`python3 scripts/check_naming.py`（349 个产品文件，0 个 forbidden remnants）、旧 URL 负向检查及新 URL 检查。

## GitHub 与发布事实

- `gh api --method PATCH repos/tchivs/doris-sql-parser-sdk -f name=fathom-sql` 成功返回 `tchivs/fathom-sql` / `https://github.com/tchivs/fathom-sql`。
- API 成功后 origin 已更新，fetch/push 均为 `https://github.com/tchivs/fathom-sql.git`。
- 新 origin 的 `refs/tags/v0.1.0` 仍解析为 `697e4e44fad964b74baf799dd68c077c3beb8b92`；本地 `v1.0` 未推送、未删除、未改写。
- `gh release view v0.1.0 --repo tchivs/fathom-sql` 成功读取现有 Release 及 assets；没有删除、重建、强推 tag 或重新运行 release workflow。
- 未 push master；README 等本地修改仅包含在本地提交中，不声称已推送。

## 变更边界

原有 `.github/workflows/jetbrains-plugin.yml`、`.planning/.omp-*`、历史 planning、构建输出等用户/历史变更均保留且未 stage。本次提交仅包含五个指定文件和本 SUMMARY 元数据。

## 验证限制

按计划未运行 formatter、lint、MoonBit 项目级测试、Gradle 测试或清理命令。

## Self-Check: PASSED

SUMMARY 文件已创建；五个目标文件存在且旧 URL 负向检查通过；GitHub rename、origin、tag 和 Release 均由真实命令确认。
