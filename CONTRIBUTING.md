# 贡献指南

感谢参与 Fathom SQL Parser SDK！本文件规范提交信息与分支约定，保持项目历史清晰、可自动追踪。

## 提交信息规范

项目采用 [Conventional Commits](https://www.conventionalcommits.org/) 格式：

```
type(scope): 简短描述

可选正文，解释原因或细节

Fixes #N
```

### type（必填）

| type       | 用途                                         |
| ---------- | -------------------------------------------- |
| `feat`     | 新功能                                       |
| `fix`      | Bug 修复                                     |
| `docs`     | 文档变更（README、CHANGELOG、注释等）        |
| `test`     | 新增或修正测试                               |
| `chore`    | 构建、依赖、配置、脚本等非功能性变更         |
| `ci`       | CI / 工作流变更                              |
| `release`  | 版本发布操作（bump、打 tag 等）              |
| `refactor` | 重构（不改变外部行为）                        |
| `perf`     | 性能优化                                     |

### scope（可选）

影响的包或模块，小写。项目现有 scope 示例：

`lexer` `token` `parser` `syntax` `source` `analyzer` `binding` `api`
`formatter` `printer` `lint` `fingerprint` `lineage` `completion`
`dialect` `corpus` `parity` `npm` `vscode` `jetbrains` `lsp` `web`
`ci` `cli` `fathom-sql` `fathom-lsp`

> 没有 scope 也可以：`docs: 更新 README`。但涉及具体模块时建议带上。

### 示例

```
fix(npm): lint() 传递空 overrides 给 fathom_lint_v1

修复 lint() 未传 overrides 参数导致 TypeError 的崩溃。

Fixes #1
```

```
feat(lexer): 支持 Doris BITMAP 类型字面量
```

```
docs: 补充 LSP 适配器架构说明
```

## 自动关闭 Issue

提交推送到 `master` 后，若 commit message 包含以下关键词之一
（紧贴 `#编号`，不区分大小写），GitHub 会自动关闭对应 issue：

| 关键词                                      |
| ------------------------------------------- |
| `close` / `closes` / `closed`              |
| `fix` / `fixes` / `fixed`                   |
| `resolve` / `resolves` / `resolved`         |

**正确写法**（会自动关闭）：

```
fix(npm): lint() 崩溃修复 Fixes #1
```

```
fix(npm): lint() 崩溃修复

正文说明...

Fixes #1
```

**不会自动关闭**（仅引用，不触发关闭）：

```
fix(npm): lint() 崩溃修复 (issue #1)
fix(npm): 修复 issue 1 的 lint 崩溃
```

> 关键词和 `#编号` 之间不能有其他文字；`#` 前必须有空格或行首。

## CHANGELOG

用户可见的行为变更（`feat`、`fix`、`release`）应同步更新
[`CHANGELOG.md`](./CHANGELOG.md) 对应版本条目。纯内部重构、测试、
CI 变更无需记录。

## 分支与提交

- 默认分支为 `master`，直接推送即可触发 CI。
- 提交前确保 `moon test` 通过（本地或 CI 均可）。
- 一个提交聚焦一件事；大改动拆成多个小提交。
