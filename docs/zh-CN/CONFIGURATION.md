<!-- GSD:generated -->
English: [English configuration](../CONFIGURATION.md) | 简体中文
# 配置说明

Fathom 是一个以 MoonBit 实现的 Doris SQL 解析与格式化库。它没有运行时服务配置或环境变量；配置通过 MoonBit 模块清单以及 `api` 包中的解析、恢复和格式化选项显式传入。

## 环境变量

仓库中没有 `.env`、`.env.example` 或 `.env.sample` 文件，也没有发现 `process.env`、`os.environ`、`os.getenv`、`std::env::var` 等环境变量读取。运行库不依赖环境变量，因此不存在需要设置的环境变量。

| 变量 | 必需 | 默认值 | 说明 |
|---|---|---|---|
| 无 | — | — | 解析器和格式化器均通过 API 参数配置。 |

## 配置文件格式

项目使用 MoonBit 的 DSL 清单，不使用额外的 JSON、YAML、TOML 或部署平台配置文件。

### `moon.mod`

根目录的 `moon.mod` 定义模块身份和默认构建目标：

```moonbit
name = "fathom/sql"
version = "1.0.5"
preferred_target = "native"
```

当前清单还记录了 MoonBit 工具链政策注释：项目按官方 MoonBit v0.10.5 文档线维护，并记录了 `moon 0.1.20260724 (5f1406a 2026-07-24)` 的版本信息。修改工具链时，应同步更新该清单中的版本记录并在目标环境运行构建检查。

### `moon.pkg`

每个 MoonBit 包通过同目录的 `moon.pkg` 声明包类型和依赖方向。根目录和 `api/`、`analyzer/`、`formatter/`、`lexer/`、`parser/`、`printer/`、`source/`、`syntax/`、`token/` 等包均为库包；`test/` 通过 `moon.pkg` 声明测试所需的包导入。包清单不接受环境变量覆盖，依赖关系应在相应 `moon.pkg` 中直接修改。

根包的最小配置如下：

```moonbit
pkgtype(kind: "library")
```

`moon.mod` 的 `preferred_target = "native"` 只设置默认目标，不会限制显式选择其他受支持的 MoonBit 后端。

## 解析配置

解析 API 位于 `api/api.mbt`。`api.parse` 接受原始 `Bytes` 和 `ParseOptions`；`api.parse_with_ids`、`api.parse_with_metadata` 提供字符串 ID 入口。解析配置是调用级别的，不会写入全局状态。

### 必需的解析设置

每次构造 `ParseOptions` 都必须明确指定方言（dialect）、Doris profile 和解析模式：

- **方言（Dialect）**：只允许 `doris` 或 `flink`；未知值返回 `ParseError::UnknownDialect`。Flink 发布 profile 已锁定（Phase 10），并在所有工具链入口接受。
- **Profile**：profile 仅在其所属方言下有效——`doris` 接受 `2.1`、`3.x` 或 `4.x`；`flink` 接受 `flink-2.3.0`、`flink-2.1.3` 或 `flink-1.20.5`。未知或跨方言值返回 `ParseError::UnknownProfile`，不会回退到通用方言。
- **Mode**：只能是 `strict` 或 `editor`；未知值返回 `ParseError::UnknownMode`。
- **Manifest 元数据（可选入口）**：使用 `from_manifest` 时，`exact_release` 和 `feature_introduction` 必须与所选 profile 的内置元数据完全匹配，否则返回 `ProfileMetadataMismatch`；不受支持的 feature introduction 返回 `UnsupportedFeatureIntroduction`。

已发布 profile 的内置元数据如下：

| Profile ID | `exact_release` | `feature_introduction` |
|---|---|---|
| `2.1` | `2.1` | `2.1 baseline SELECT; DML/DDL released` |
| `3.x` | `3.x` | `2.1 baseline SELECT; DML/DDL released; 3.x window and QUALIFY` |
| `4.x` | `4.x` | `2.1 baseline SELECT; DML/DDL released; 4.x released SELECT` |
| `flink-2.3.0` | `flink-2.3.0` | `primary profile` |
| `flink-2.1.3` | `flink-2.1.3` | `flink-2.1.3 regression profile` |
| `flink-1.20.5` | `flink-1.20.5` | `flink-1.20.5 regression profile` |

示例：

```moonbit
let options = match @api.ParseOptions::new("doris", "4.x", "editor") {
  Ok(value) => value
  Err(error) => panic()
}
let result = @api.parse(b"SELECT * FROM orders", options)
```

### 资源限制

`ParseLimits::default()` 从 `parser.ParserLimits::default()` 获取以下默认值。需要隔离不可信或大型输入时，可使用 `ParseOptions::for_profile_with_limits` 传入自定义限制。

| 设置 | 默认值 | 作用 |
|---|---:|---|
| `max_bytes` | `8 * 1024 * 1024`（8 MiB） | 原始输入的最大字节数；超过后返回 `InputTooLarge`。 |
| `max_tokens` | `1_000_000` | 单次解析允许处理的 token 数上限。 |
| `max_recursion_depth` | `128` | 递归下降和表达式解析的最大递归深度。 |
| `max_recovery_steps` | `10_000` | Editor 模式错误恢复允许执行的最大步数。 |
| `max_diagnostics` | `100` | 单次解析保留的最大诊断数量。 |

所有自定义限制必须为非负整数。`api.parse` 和 `api.format_text` 会在开始处理输入前校验限制；负值返回 `ParseError::InvalidLimit`，不会静默修正。输入字节数超过 `max_bytes` 返回 `ParseError::InputTooLarge`。

## 格式化设置

格式化配置由 `formatter/options.mbt` 中的 `FormatOptions` 提供，并通过 `api.format_text`、`api.format_with_ids` 或 `api.format_with_metadata` 使用。`FormatOptions::default()` 的默认值为：

| 设置 | 默认值 | 可选值或约束 |
|---|---|---|
| `keyword_case` | `Upper` | `Upper`、`Lower`；字符串 ID 为 `upper`、`lower`。 |
| `indent` | `2` | 非负整数，表示缩进空格数。 |
| `line_width` | `100` | 正整数，表示目标行宽。 |
| `comma_style` | `Trailing` | `Trailing`、`Leading`；字符串 ID 为 `trailing`、`leading`。 |
| `newline_style` | `FollowInput` | `FollowInput`、`Lf`、`Crlf`；字符串 ID 为 `follow`、`lf`、`crlf`。 |
| `trailing_newline` | `true` | 是否在输出末尾保留换行。 |

`FormatOptions::new` 在构造时拒绝负 `indent`（`InvalidIndent`）和非正 `line_width`（`InvalidLineWidth`）。未知的字符串枚举 ID 应在调用方映射为对应枚举；`KeywordCase::from_id`、`CommaStyle::from_id` 和 `NewlineStyle::from_id` 对未知 ID 返回 `None`。

示例：

```moonbit
let parse_options = match @api.ParseOptions::new("doris", "3.x", "strict") {
  Ok(value) => value
  Err(error) => panic()
}
let format_options = @formatter.FormatOptions::default()
let formatted = @api.format_text(b"select id, name from users", parse_options, format_options)
```

格式化器遇到包含 `error`、`missing` 或 `skipped` 材料的语法树时会拒绝输出，返回 `accepted = false`、空输出以及 `FATHOM-FORMAT-001` 诊断；这不是可通过环境变量关闭的行为。

## 必需与可选设置

Fathom 是库而不是需要启动配置的常驻应用，因此不存在“缺少配置导致进程启动失败”的设置。必需设置只存在于 API 调用边界：

1. 解析和格式化必须选择有效的方言、profile 与模式（无隐式回退）。
2. 使用 manifest 入口时，release 和 feature introduction 元数据必须和 profile 一致。
3. 若提供自定义 `ParseLimits`，所有限制必须为非负值。
4. 若提供自定义 `FormatOptions`，`indent` 必须非负，`line_width` 必须大于零。

未提供自定义限制或格式化选项时，分别使用上文列出的默认值。解析器不会从输入内容推断 profile，也不会从外部目录、数据库或 Doris FE 加载配置。

## 按环境覆盖

仓库中没有 `.env.development`、`.env.production`、`.env.test`，也没有 `NODE_ENV` 条件分支或其他环境配置加载器。开发、测试和发布环境使用同一套源码及 MoonBit 清单；差异应通过调用方显式传入 `ParseOptions`、`ParseLimits` 和 `FormatOptions`，或通过构建命令显式选择目标。

例如，编辑器场景可以选择 `editor` 模式并降低资源上限，批处理场景可以选择 `strict` 模式并使用默认限制；这两种行为属于调用参数，不是环境变量覆盖。

## 编辑器宿主与 CLI 方言/Profile 选择

SDK 附带编辑器宿主（VS Code、IntelliJ）和 Web demo，它们按工作区/会话选择方言和已发布 profile，与 `api` 包完全一致：一个显式的 `(dialect, profile)` 对，无隐式回退。宿主常量镜像服务端的权威校验（`binding.validate_dialect_profile` / LSP `validate_selection`）；缺失、未知或跨方言的对都是显式配置错误，绝不会强制转换为默认值。

### 有效的 (dialect, profile) 对

| 方言 | Profile |
|---|---|
| `doris` | `2.1`、`3.x`、`4.x` |
| `flink` | `flink-2.3.0`、`flink-2.1.3`、`flink-1.20.5` |

profile 仅在其所属方言下有效：`flink` + `2.1` 和 `doris` + `flink-2.3.0` 均被拒绝。服务端保持权威——如果宿主接受了服务端拒绝的对，那是服务端错误，绝不是静默回退。

### 按宿主选择

| 宿主 | 选择入口 | Flink 选择示例 |
|---|---|---|
| VS Code | `fathom.dialect` + `fathom.profile` 设置（加上 `fathom.serverPath` 指向本地 `fathom-lsp` 可执行文件） | `fathom.dialect: "flink"`、`fathom.profile: "flink-2.3.0"` |
| IntelliJ | `FathomSettings` 应用设置——方言和 profile 下拉菜单；profile 列表会根据所选方言重新填充 | 方言 `flink`，profile `flink-2.3.0` |
| Web demo | `#dialect` 和 `#profile` 选择器；profile 选择器在方言变更时重新填充 | 方言 `flink`，profile `flink-2.3.0` |
| CLI | `fathom-sql parse|format|lsp --dialect <d> --profile <p>` | `--dialect flink --profile flink-2.3.0` |

Web/VS Code/IntelliJ 宿主各自维护按方言分组的静态 profile 映射（离线优先，PARITY-03）；它们从不动态拉取 profile，也不共享跨宿主的 JSON 定义。

### 按文件 LSP 覆盖

除上述工作区/会话默认值外，LSP 还通过 `didOpen`/`didChange` 扩展字段 `dialect` 和 `profile` 支持按文件覆盖。优先级为：文档 > 工作区/会话。不执行自动检测，也不根据文件扩展名猜测——flink 文件必须显式携带 flink 选择。

## 配置相关文件

| 文件 | 用途 |
|---|---|
| `moon.mod` | 模块名称、版本和默认目标。 |
| `moon.pkg` | 根包类型。 |
| `api/api.mbt` | `ParseOptions`、`ParseLimits`、解析入口和格式化入口。 |
| `parser/parser.mbt` | 解析资源限制及其默认值、校验逻辑。 |
| `formatter/options.mbt` | 格式化枚举、`FormatOptions` 默认值和校验。 |
| 各包目录下的 `moon.pkg` | 包类型和包间导入关系。 |
