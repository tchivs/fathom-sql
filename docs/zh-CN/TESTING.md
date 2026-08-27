<!-- GSD:generated -->
English: [English testing guide](../TESTING.md) | 简体中文
# 测试说明

Fathom 使用 MoonBit 内置测试运行器验证 Doris SQL 的解析、恢复、无损重放、格式化、分析和版本语料契约。测试是离线的，不连接 Doris FE、数据库或 SQL 集群；测试输入主要以内嵌 `Bytes` 和 Git 跟踪的 corpus 元数据表示。

## 测试框架与设置

### MoonBit 测试

- **测试框架**：MoonBit 内置 `test "name" { ... }` 测试块以及 `assert_true`、`assert_eq`、`panic` 等内置断言。
- **工具链**：仓库 `moon.mod` 记录的工具链为 `moon 0.1.20260724 (5f1406a 2026-07-24)`；运行 `moon version` 可确认当前环境。`moon.mod` 将 `native` 设为首选目标。
- **测试包**：`test/moon.pkg` 导入 `api`、`parser`、`printer`、`source`、`syntax`、`formatter`、`analyzer`、`binding`、`dialect` 和 `lineage`，测试文件集中在 `test/`。
- **依赖安装**：MoonBit 测试没有额外的运行时测试依赖。安装与仓库兼容的 MoonBit CLI 后，在项目根目录运行 `moon check` 即可完成模块检查。
- **环境要求**：测试包不读取环境变量，也不需要数据库、Doris FE、网络或常驻服务。所有核心测试可离线运行。

### 可选差分工具

`corpus/tools/` 下的差分脚本不是 MoonBit 测试的必需依赖，也不能改变 released-docs manifest 的支持结论。只有运行 SQLGlot 基线时才需要 Python 虚拟环境和固定版本：

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r corpus/requirements.txt  # sqlglot==30.14.0
```

`corpus/tools/generate_corpus_report.py` 和 `corpus/tools/check_keywords.py` 仅使用 Python 标准库；FE/Nereids 脚本是需要外部 Doris FE 构建的手动、advisory-only 检查，不属于常规测试设置或 CI 门禁。

## 运行测试

### 完整测试套件

从仓库根目录运行：

```bash
moon test
```

需要显式指定 Native 目标时运行：

```bash
moon test --target native
```

> **注意（固定工具链）：** 直接运行 `moon test` 会触发 MoonBit 错误 4219，因为
> `binding` 包是 `foreign_library`，其 `#export_name` 不能出现在 test-target 构建中
> — 这是自 v1 (04-03) 起的已知边界。请使用 DEVELOPMENT.md 中的逐包命令运行完整
> 行为套件，并使用 `moon test --target wasm --package parity-tests` 执行线性 Wasm
> 运行时 parity 门禁。

`moon test` 会编译并执行 `test/` 测试包。当前测试代码按领域拆分如下：

| 文件 | 覆盖范围 |
|---|---|
| `test/source_test.mbt` | 空输入、换行、BOM、Unicode、非法字节、源码长度和 span 边界、原始字节重放。 |
| `test/parser_test.mbt` | SELECT/表达式、语句顺序与 statement id、profile gate、诊断、恢复节点、span 和 replay；同时提供 corpus 测试使用的共享解析辅助结构。 |
| `test/recovery_test.mbt` | strict/editor 恢复、非法编码、未闭合词法材料、字节/token/递归/恢复/诊断上限，以及截断后的 source-backed replay。 |
| `test/keyword_test.mbt` | reserved/non-reserved/contextual 分类、profile 元数据，以及运行时关键字表与 `corpus/keywords.tsv` 的双向一致性。 |
| `test/dml_test.mbt` | INSERT、UPDATE、DELETE、MERGE 等 DML、版本门控、错误恢复、multi-statement 和无损 replay。 |
| `test/ddl_test.mbt` | CREATE TABLE/VIEW/INDEX/MATERIALIZED VIEW 等 DDL、版本门控、恢复、span 和 replay。 |
| `test/analyzer_test.mbt` | 注入式 `Catalog` 查找、表引用解析、语法结果不受 catalog 影响，以及按 statement id 查询节点和诊断。 |
| `test/analyzer_anal01_test.mbt` | ANAL-01 端到端 tracer 测试：在真实 parser 上 parse 到 analyze，断言带扁平化字节 span 的 binding、独立分析器诊断通道 (ANLY-01) 和引号/精确匹配；通过 snapshot golden 冻结 select-basic AnalysisResult。 |
| `test/analyzer_public_surface_test.mbt` | 公共接口端到端测试：在真实 parser 上 parse 到 `@analyzer.source_tokens` 和 `@analyzer.split_select_model`，断言跨包可读的 SelectModel 结构、空文档全函数和公共 `has_error_missing` 扫描。 |
| `test/formatter_test.mbt` | 格式化 golden、关键字/缩进/换行选项、`format(format(x)) == format(x)` 幂等性、输出重解析和错误树拒绝。 |
| `test/fingerprint_test.mbt` | `@api.fingerprint_text` 集成测试：公共 API 背后的 raw → parse → normalize → hash 完整管线 (FING-01)。 |
| `test/lineage_test.mbt` | LINE-01 端到端集成测试：在真实 parser 上 parse 到 lineage 以及 `@api.lineage_text` facade，断言带扁平化字节 span 的 edge/gap 结构和通过 snapshot golden 的确定性排序。 |
| `test/lint_test.mbt` | `@api.lint_text`/`@api.fix_text` 集成测试：公共 API 背后的 raw → parse → lint → fix 管线，包括 D-33 拒绝路径 (LINT-01)。 |
| `test/binding_wire_test.mbt` | binding 包 wire 测试：在集成测试包中验证 `foreign_library` 导出面 (`#export_name`)，因为 `binding` 不能作为 native 测试构建的直接目标 (错误 4219)。 |
| `test/corpus_test.mbt` | 按 Doris profile 和语句类别组织的内嵌 manifest fixture、expected-error oracle、statement id 和整体 replay。 |

### 单文件和子集

MoonBit 的 `PATH` 参数可以选择一个测试文件；`-f` 可以按测试名 glob 过滤；`-i` 可以在选定单文件中按索引运行测试：

```bash
# 运行 parser 测试文件
moon test test/parser_test.mbt

# 只运行名称以 industrial_select 开头的 parser 测试
moon test test/parser_test.mbt -f 'industrial_select*'

# 运行 recovery 测试文件中指定索引的一个测试（索引从 0 开始）
moon test test/recovery_test.mbt -i 1
```

单文件命令仍会编译其所需的包；测试名称、文件名或测试索引改变后，应先用不带 `-i` 的单文件命令确认目标测试。

### 语料和审计检查

语料测试的支持状态由 `corpus/manifest.tsv` 和 `corpus/coverage.tsv` 决定；`corpus/CORPUS-REPORT.md` 是离线生成的报告。运行一致性门禁：

```bash
python3 corpus/tools/generate_corpus_report.py --check
python3 corpus/tools/check_keywords.py corpus/keywords.tsv
```

第一条命令检查报告是否与 manifest/coverage 一致、每个 fixture 是否恰好对应一条 coverage row、known-gaps 是否存在以及 corpus 文本是否含有不合规的全兼容声明。第二条命令检查关键字 TSV 的字段、重复项、分类/profile 值、文档 URL 和生产关键字覆盖。

如需更新报告而不是只检查：

```bash
python3 corpus/tools/generate_corpus_report.py
```

SQLGlot 差分是可选的 advisory-only 基线：

```bash
. .venv/bin/activate
python3 corpus/tools/sqlglot_diff.py
```

它将观察结果写入 `corpus/differential.tsv`，但 SQLGlot 的接受或拒绝不能提升或降低 SDK 的公开支持状态。FE/Nereids 差分脚本 `corpus/tools/fe_nereids_diff.sh` 需要外部 Doris checkout、构建后的 FE classpath 和 `FE_VERSION`，仅在具备这些前置条件时手动运行，不是默认测试命令。

## 编写新测试

### 测试文件和命名

将测试放在 `test/` 下对应领域的 `.mbt` 文件中，并使用描述行为的 snake_case 名称：

```moonbit
test "malformed_expression_keeps_source_bytes" {
  let raw = b"SELECT 1 +"
  let result = match @api.parse_with_ids(raw, "4.x", "editor") {
    Ok(value) => value
    Err(_) => panic()
  }
  assert_true(!result.valid)
  assert_true(result.recovered)
  assert_eq(@printer.print_result(result), raw)
  assert_true(result.all_spans_in_bounds())
}
```

现有测试优先通过公共 `@api.parse_with_ids`/`@api.format_with_ids` 验证可观察行为；只有需要验证底层限制或包边界时才直接调用 `parser`、`source` 或其他底层包。测试应避免依赖测试执行顺序、可变全局状态、文件系统当前目录或外部服务。

### 必须保护的行为契约

解析器回归测试通常同时检查以下层次，而不是只断言“解析成功”：

1. `valid`、`recovered` 和诊断数量/代码是否符合 strict 或 editor 模式预期。
2. 诊断的 `FATHOM-PARSE-###` code、严重级别、expected class、字节 span 和 snapshot-local `statement_id`。
3. `@printer.print_result(result) == raw` 的字节级无损重放，包括注释、空白、LF/CRLF、BOM、Unicode、非法字节和错误材料。
4. `result.all_spans_in_bounds()`、statement 顺序、节点 kind 以及 `missing`/`error`/`skipped` 恢复结构。
5. 版本特性在 `2.1`、`3.x`、`4.x` profile 下的接受或明确拒绝；不使用通用方言回退。

格式化测试应为接受的输入提供完整 `expected_golden`，并验证格式化结果再次解析无诊断、重复格式化字节完全相同；错误树必须验证 `accepted == false` 且不产生部分输出。现有 formatter fixture 以内嵌原始字节和 golden 保存，不从磁盘加载运行时 fixture。

### 添加 corpus fixture

新增官方语料时，应保持 manifest、coverage、fixture 和可执行 oracle 同步：

1. 将 SQL 文件放在对应的 `corpus/doris-2.1/`、`corpus/doris-3.x/` 或 `corpus/doris-4.x/` 目录，并记录 profile、release、feature introduction、官方 URL、抓取日期、来源 revision、类别、模式和预期状态。
2. 在 `corpus/manifest.tsv` 增加一条 fixture 记录，并在 `corpus/coverage.tsv` 更新对应 profile/category 汇总；不要把 SQLGlot 或 FE 观察当成公开支持结论。
3. 在 `test/corpus_test.mbt` 的 `dml_ddl_corpus_fixtures` 等嵌入 fixture 列表中加入对应 raw bytes、metadata、parse mode 和 `expected_valid`，使 `dml_ddl_corpus_oracle_replays_every_manifest_fixture` 覆盖该行。
4. 运行 `moon test`、`python3 corpus/tools/generate_corpus_report.py --check` 和关键字检查（若修改了 `corpus/keywords.tsv`），审查 replay、diagnostics、span 和报告差异。

不要通过批量更新 golden 来掩盖 dropped trivia、错误的 profile gate、错误恢复状态或 span 变化；golden 更新必须与代码和来源元数据一起审查。

## 覆盖率要求

仓库没有发现 Jest/Vitest/Pytest 配置、`.nycrc`、覆盖率阈值配置或 CI 覆盖率门禁。因此当前没有按 lines、branches、functions 或 statements 规定的最低阈值：**No coverage threshold configured.** MoonBit 覆盖率应作为诊断信息使用，不能替代按 Doris profile/category 统计的语料覆盖。

使用 MoonBit 内置覆盖率工具：

```bash
moon coverage analyze
moon coverage report -f summary
```

需要机器可读或 HTML 报告时，可按 MoonBit 命令支持的格式选择 `-f coveralls`、`-f cobertura` 或 `-f html`。覆盖率报告应与 `moon test` 的行为断言配合阅读；尤其要继续检查无损 round-trip、错误/恢复节点、版本负例和资源上限，这些契约不应由单一分支覆盖率数字替代。

`corpus/coverage.tsv` 和 `corpus/CORPUS-REPORT.md` 是 SQL 语法 feature/corpus coverage，不是 MoonBit 源码覆盖率。它们分别记录各 profile/category 的 fixture、supported、expected-error 和 known-gap，并通过 `generate_corpus_report.py --check` 校验一致性。

## CI 集成

`.github/workflows/ci.yml` 在 push 到 `master` 和 PR 时运行：

- **check** — `moon fmt --check`;native、JS、线性 Wasm 目标的 `moon check`。
- **test** — `moon test`(native,通过逐包调用运行完整套件)。
- **linear-wasm-parity** — `moon build --target wasm binding` 与 `moon build --target wasm parity-tests`,然后 `moon test --target wasm --package parity-tests`(在**线性 Wasm 后端**上执行 parity 语料)加 `moon test --target native --package parity-tests` 和 `moon test --target js --package parity-tests` 做三后端字节级 parity 交叉校验,随后运行 `compare_backends.py`。
- **parity-gate** — baseline snapshot 门禁(`moon test --package parity-tests`)、baseline diff 自检、baseline corpus 哈希固定,以及 frozen-vs-current 重生成证明(`diff_parity.py --frozen-only`)。
- **corpus** — 离线 Flink corpus 验证器(`verify_corpus.py --check`)、`generate_corpus_report.py --check` 与 `check_keywords.py corpus/keywords.tsv`。
- **naming-gate** — `check_naming.py` 拒绝源码、配置、CI、扩展和文档中的旧产品身份残留。
- **host-packaging-smoke** — 构建原生 `fathom-lsp` 和 JS `binding`,然后离线运行 Web Chromium、VS Code 扩展宿主 (Xvfb) 和 JetBrains 插件冒烟测试。

`.github/workflows/fathom-native-release.yml` 将 GitHub Release job 门禁在等效的 `release-gates` job 上(native、JavaScript 和线性 Wasm parity 加 `compare_backends` 和 `diff_parity`),外加原生多平台构建,因此发布前必须通过线性 Wasm 运行时执行 parity。

没有自动上传覆盖率或自动运行 FE/Nereids 差分(FE 脚本刻意保持手动,D-20)。提交前至少应在仓库根目录执行：

```bash
moon check
moon test
python3 corpus/tools/generate_corpus_report.py --check
```

若改动了 `corpus/keywords.tsv`，再执行：

```bash
python3 corpus/tools/check_keywords.py corpus/keywords.tsv
```

发布或跨后端验证需要额外明确目标并单独记录结果，例如 `moon test --target native`；不要把未在仓库 CI 中声明的外部服务或部署平台行为当作测试通过条件。
