# npm

> [根级 CLAUDE.md](../CLAUDE.md) › npm

## 职责

`@fathom-sql/sql` npm 包：MoonBit 编译产物的 JS ESM 包装层，提供类型化的公开 API 和 TypeScript 声明。

## 关键文件

| 文件 | 职责 |
|---|---|
| `index.mjs` | ESM 入口，UTF-8 编解码 + 类型化调用 |
| `index.d.ts` | TypeScript 类型声明 |
| `binding.js` | MoonBit JS 后端编译产物（~1.3MB） |
| `binding.wasm` | MoonBit Wasm 后端编译产物（~440KB） |
| `build.mjs` | 构建脚本：moon build + 拷贝产物 + capabilities.json + npm pack |
| `capabilities.json` | 方言/profile 元数据（构建时生成） |
| `smoke/smoke.mjs` | 消费者烟雾测试 |

## 公开接口

```ts
parse(raw, dialect, profile, mode?) → ParseEnvelope
format(raw, dialect, profile, mode?, options?) → FormatEnvelope
complete(raw, dialect, profile, cursorByte) → Envelope
lint(raw, dialect, profile, mode?) → Envelope
fingerprint(raw, dialect, profile, mode?) → FingerprintEnvelope
lineage(raw, dialect, profile, mode?) → Envelope
capabilities() → CapabilitiesEnvelope
dialect(d) → Envelope
byteOffsetToLineColumn(raw, byteOffset) → LineColumn
lineColumnToByteOffset(raw, line, column) → number
withLineColumns(raw, diagnostics) → PositionedDiagnostic[]
```

## 依赖

- 产物依赖：`binding.js`（MoonBit JS 后端）、`binding.wasm`（MoonBit Wasm 后端）
- 无运行时 npm 依赖

## 测试

`smoke/smoke.mjs`——消费者烟雾测试，覆盖 parse/format/fingerprint/lint/capabilities/lineColumn。

## 注意事项

- 包装层负责 UTF-8 编解码（`TextEncoder`/`TextDecoder`）和 JSON 解析
- binding 导出 `fathom.*_v1` 字节函数（raw bytes in, JSON bytes out）
- 构建流程：`node npm/build.mjs` → `moon build --target js/wasm --release binding` → 拷贝 → pack
- `lint()` 需传空 overrides + `fix=false`（issue #1 修复）
