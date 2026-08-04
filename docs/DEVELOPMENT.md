<!-- GSD:generated -->
# 开发指南

本指南说明如何在本地开发 Fathom、运行 MoonBit 检查和测试，以及维护按 Doris 版本组织的 SQL 语料。Fathom 由 MoonBit library packages 和 `doris-sql/` native CLI 适配器组成；仓库没有部署服务，Python 工具只用于语料校验和可选的差异分析。

## 本地开发设置

### 前置条件

- MoonBit CLI。`moon.mod` 将默认目标设为 `native`，并记录当前项目使用的 CLI 输出为 `moon 0.1.20260724 (5f1406a 2026-07-24)`。项目注释按官方 MoonBit v0.10.5 文档线维护，但实际使用时应以本机 `moon version` 输出和项目维护者指定的版本为准。
- Python 3。仅在运行 `corpus/tools/` 下的 Python 校验器或差异工具时需要；当前开发环境验证为 Python 3.9.23。
- 可选：Python 虚拟环境。只有运行 SQLGlot 差异工具时才需要安装 `corpus/requirements.txt` 中锁定的开发依赖；SQLGlot 不进入 MoonBit 运行时依赖图。
- Git。用于获取源码和提交变更。

### 获取源码

仓库当前没有记录 Git remote，因此无法从仓库内容确认 canonical clone URL。<!-- VERIFY: 请从项目托管页面取得实际远程 URL。 -->

```bash
git clone <repository-url>
cd Fathom
```

如果已经在工作区中，直接进入项目根目录即可：

```bash
cd /opt/source/Fathom
```

### 安装与首次检查

MoonBit 依赖由 `moon.mod` 和各包目录的 `moon.pkg` 声明；当前清单没有需要额外安装的 MoonBit 包。安装与开发检查步骤如下：

```bash
moon version
moon check
```

`moon check` 会检查根模块及其库包，但不生成对象文件。构建产物写入 `_build/`，该目录已被 `.gitignore` 忽略。

### 开发环境配置

项目没有 `.env` 文件、环境变量读取或按环境的配置加载器。解析配置在调用点通过 `api.ParseOptions`、`api.ParseLimits` 和 `formatter.FormatOptions` 显式传入；无需复制 `.env.example` 或设置服务端口。需要修改模块身份、版本或默认目标时编辑 `moon.mod`；需要调整包依赖时编辑对应目录的 `moon.pkg`。

公共库开发通常从 `api/` 门面开始；底层实现按 `source → token → lexer → parser → syntax` 的依赖方向组织。格式化功能位于 `formatter/`，原样重放位于 `printer/`，可选的 catalog 名字解析位于 `analyzer/`。新增语法时，应同时考虑相应的 profile、CST 节点、诊断、恢复行为和 `test/` 中的回归用例。

## 构建与开发命令

仓库没有 `package.json` 的 `scripts` 字段，也没有 Makefile；下面的命令是由当前 MoonBit 工具链和仓库中的 Python 工具直接提供的命令。

| 命令 | 说明 |
|---|---|
| `moon version` | 输出当前 MoonBit CLI 版本；提交或排查构建差异时先记录该输出。 |
| `moon check` | 检查当前模块，不生成对象文件。用于快速反馈类型、导入和包清单问题。 |
| `moon check --fmt` | 在检查模块的同时验证 MoonBit 源文件格式。 |
| `moon build` | 按 `moon.mod` 的默认 `native` 目标构建当前模块。 |
| `moon build --target native --release` | 以 Native release 模式构建库包和 `doris-sql` executable package。 |
| `moon build --target js` | 显式检查 JavaScript 后端兼容性。 |
| `moon build --target wasm` | 显式检查线性 WebAssembly 后端兼容性。 |
| `moon build --target wasm-gc` | 在工具链支持时检查 Wasm GC 后端；它不是当前默认目标。 |
| `moon test` | 运行 `test/` 中的 MoonBit 行为测试以及各库包测试。 |
| `moon test --filter '名称模式'` | 只运行匹配名称的测试；适合定位单个回归行为。 |
| `moon test --package <package>` | 只运行指定 MoonBit 包的测试。 |
| `moon test --update` | 按 MoonBit 的快照测试机制更新快照；更新前必须确认变更是预期的。 |
| `moon fmt` | 使用 MoonBit 内置 formatter 格式化源文件。 |
| `moon fmt --check` | 只检查格式，不修改文件。 |
| `moon clean` | 清理本地 `_build/` 构建输出；不会修改源码或语料。 |
| `python3 corpus/tools/generate_corpus_report.py --check` | 检查 `manifest.tsv`、`coverage.tsv`、`keywords.tsv` 与提交的 `CORPUS-REPORT.md` 是否一致。 |
| `python3 corpus/tools/check_keywords.py corpus/keywords.tsv` | 校验关键词 TSV 的表头、分类、profile、来源 URL、重复项和生产关键词覆盖。 |

完成语法或格式化改动后，建议至少依次运行：

```bash
moon fmt --check
moon check
moon test
python3 corpus/tools/generate_corpus_report.py --check
python3 corpus/tools/check_keywords.py corpus/keywords.tsv
```

如果改动只涉及 MoonBit 包，语料 Python 校验仍可作为提交前的完整一致性检查；如果改动涉及 `corpus/manifest.tsv`、`corpus/coverage.tsv` 或 `corpus/keywords.tsv`，则必须运行对应的校验命令。

### 可选 SQLGlot 差异工具

差异工具是开发辅助，不是 Fathom 的运行时依赖。首次使用时在项目根目录创建虚拟环境并安装锁定版本：

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r corpus/requirements.txt
python3 corpus/tools/sqlglot_diff.py
```

脚本读取 `corpus/manifest.tsv`，使用 Doris 方言解析可落盘的 fixture，并更新 `corpus/differential.tsv`。SQLGlot 或某个 fixture 不可用时，工具记录 `not-run-offline`，不会伪造观察结果；差异结果也不能改变 released-docs manifest 定义的公开支持范围。

## 代码风格

### MoonBit

- 使用 MoonBit 内置 formatter；仓库没有发现 `.editorconfig`、ESLint、Prettier、Biome 或其他独立格式配置。
- 提交前运行 `moon fmt --check`；需要自动修复时运行 `moon fmt`，然后检查生成的差异。
- 以现有包边界为准：公共跨包 API 放在 `api/`，源码坐标放在 `source/`，词法和 profile 事实放在 `token/`，语法产生式和恢复放在 `parser/`。不要在 formatter 中复制第二套关键字分类表，应复用 `token` 的分类。
- 保持源码保真不变量：节点引用 `Span` 而不是复制源文本；`printer` 的无损输出必须保持原始字节；格式化器遇到 `error`、`missing` 或 `skipped` 材料时必须遵守拒绝输出契约。
- 新增公共类型或函数时，遵循现有的 `pub(all)`、构造器和访问器风格，并补充稳定的 profile、诊断、字节范围和错误恢复测试。

### Python 工具

`corpus/tools/` 下的脚本使用 Python 标准库（差异工具另依赖锁定的 SQLGlot），仓库没有 Python formatter 或 lint 配置。保持现有脚本的模块级常量、`main(argv)` 返回退出码、`if __name__ == "__main__"` 入口和面向错误的 stderr 输出风格；修改后至少直接运行受影响的脚本。

### 测试风格

测试位于 `test/`，使用 MoonBit 的 `test "..." { ... }` 形式。文件按行为领域划分，包括 `parser_test.mbt`、`recovery_test.mbt`、`formatter_test.mbt`、`ddl_test.mbt`、`dml_test.mbt`、`analyzer_test.mbt`、`source_test.mbt`、`keyword_test.mbt` 和 `corpus_test.mbt`。测试应断言可观察契约，例如：

- `printer.print_result(result)` 与输入字节完全相等；
- `valid`、`recovered`、诊断 code、statement id 和 span 边界符合 profile/mode；
- 格式化输出可重复（`format(format(x)) == format(x)`）且能重新解析；
- `corpus` manifest 与覆盖报告保持一对一和版本分类一致。

不要依赖 `_build/` 中生成的文件，也不要让运行时测试从磁盘 fixture 隐式读取；现有测试将关键 fixture 和 golden 嵌入 MoonBit 源码中。

## 分支约定

仓库没有 `CONTRIBUTING.md`、Pull Request 模板或 CI 配置，因此没有已文档化的分支命名规范。当前检出的分支为 `master`，最近提交标题采用了 `feat(...)` 和 `docs(...)` 等 Conventional Commits 风格前缀；这些是当前仓库观察到的实践，不是强制规范。

建议新工作从最新 `master` 创建短生命周期分支，并使用能表达目的的前缀，例如：

- `feat/<scope>`：新增 parser、formatter 或 API 行为；
- `fix/<scope>`：修复解析、恢复或输出回归；
- `docs/<scope>`：只修改文档；
- `test/<scope>`：补充回归测试或 corpus 校验。

若项目托管平台或维护者另有要求，以其要求为准。

## Pull Request 流程

仓库当前没有项目专用的 PR 模板或 CI 门禁。提交 PR 前，建议按以下清单准备：

1. 从最新 `master` 创建分支，保持每个提交聚焦于一个行为或文档主题；提交标题可沿用现有的 `feat(scope): ...`、`fix(scope): ...` 或 `docs(scope): ...` 格式。
2. 在 PR 描述中说明变更的 Doris profile（`2.1`、`3.x`、`4.x`）、解析模式（`strict` 或 `editor`）和受影响的包；若变更语法覆盖，注明对应的 corpus fixture 或 released-docs 来源。
3. 运行 `moon fmt --check`、`moon check` 和受影响的 `moon test`；涉及完整解析行为时运行 `moon test`，涉及 corpus 清单或关键词表时同时运行相应的 Python `--check` 命令。
4. 对格式化器变更确认无损打印、错误树拒绝、输出幂等性和重新解析行为；对 parser 变更确认诊断字节范围、statement id、profile gate 和 editor 恢复行为。
5. 在 PR 中列出实际运行的命令及结果，并说明任何未运行的后端、外部差异工具或已知 corpus provenance gap；不要把 SQLGlot/FE 的 advisory 结果写成公开兼容性承诺。

审查时应重点看跨包依赖方向、源码字节是否被复制或丢失、错误恢复是否突破资源上限、诊断是否稳定，以及测试是否保护真实用户可观察的 API 契约。

## 相关文档

- [README.md](../README.md)：项目定位、公共 API 示例、包结构和当前验证入口。
- [ARCHITECTURE.md](ARCHITECTURE.md)：组件关系、数据流、关键抽象和目录职责。
- [CONFIGURATION.md](CONFIGURATION.md)：`ParseOptions`、资源限制和 `FormatOptions` 的完整配置说明。
- `corpus/CORPUS-REPORT.md`：按 Doris profile 和类别组织的语料覆盖与已知缺口。
- `corpus/tools/README.md`：SQLGlot 与 Doris FE/Nereids 差异工具的开发说明。
