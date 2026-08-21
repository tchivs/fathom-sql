# web

> [根级 CLAUDE.md](../CLAUDE.md) › web

## 职责

离线 Monaco 编辑器演示页，在浏览器中加载本地 Wasm/JS 解析器 artifact 并提供
解析、诊断、格式化与补全能力。不依赖网络服务器或数据库——artifact 从本地构建产物动态 import。

## 关键文件

- `src/main.ts` — Monaco 入口；创建编辑器模型、注册 SQL 语言、绑定 UI 事件与解析/格式化流程
- `src/monaco-adapter.ts` — `ParserAdapter` 封装 `fathom_parse_v1` / `fathom_format_v1` / `fathom_complete_v1` wire 导出；含 UTF-8 字节↔位置映射
- `src/main.test.ts` — 使用 `node:test` 的单元测试，验证适配器调用与字节映射
- `src/styles.css` — 演示页样式
- `package.json` — 私有包 `@fathom-sql/sql-web-demo`

## 公开接口

| 符号 | 说明 |
|---|---|
| `ParserAdapter` | 动态 import artifact 并暴露 `parse`/`format`/`complete` |
| `ParserAdapter.load()` | 懒加载本地 binding 模块 |
| `byteToPosition(sourceBytes, byteOffset)` | UTF-8 字节偏移 → Monaco `{line, character}`（UTF-16 code unit） |
| `diagnosticRange(sourceBytes, diagnostic)` | 诊断的 `start_byte`/`end_byte` → Monaco Range |
| `DIALECTS` / `PROFILES_BY_DIALECT` | 与 vscode/jetbrains 共享的方言与 profile 常量 |
| `DEFAULT_ARTIFACT_URL` | 默认指向 `../../_build/js/debug/build/binding/binding.js` |

## 依赖

- `monaco-editor` 0.56.0 — 浏览器编辑器组件
- 本地构建产物 `_build/js/debug/build/binding/binding.js`（由 MoonBit JS 后端生成）

## 测试

`npm test` 运行 `node --test` 执行 `src/main.test.ts`。
`npm run build` 运行离线冒烟脚本 `scripts/offline-smoke.mjs --offline`。
`npm start` 启动 `scripts/serve.mjs` 本地服务器。

## 注意事项

- artifact 通过 `import()` 动态加载，默认从本地构建目录读取——无需网络
- dialect/profile 无预选值（D-02）；必须显式选择有效配对后才能解析
- 格式化调用使用固定参数：`strict` 模式、`upper` 关键字、缩进 2、行宽 100、trailing 换行
- 解析结果若 `schema_version === 'fathom.error.v1'` 则抛出带 `code`/`payload` 的错误
