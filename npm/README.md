# @fathom-sql/sql

[![npm version](https://img.shields.io/npm/v/@fathom-sql/sql)](https://www.npmjs.com/package/@fathom-sql/sql)
[![License](https://img.shields.io/npm/l/@fathom-sql/sql)](https://github.com/tchivs/fathom-sql/blob/master/LICENSE)

A MoonBit-built parser and toolchain for **Apache Doris** and **Apache Flink**
SQL, exposed as a self-contained ES module. The package ships the built
JavaScript binding (`binding.js`), the linear-Wasm artifact (`binding.wasm`),
TypeScript declarations, and dialect/profile capability metadata — no native
dependencies, no network calls, no database connection.

## Features

- **Dual-dialect parsing** — Doris (`2.1` / `3.x` / `4.x`) and Flink
  (`flink-2.3.0` / `flink-2.1.3` / `flink-1.20.5`) with version-aware keyword
  classification and feature gating.
- **Lossless syntax tree** — Parse results preserve byte ranges for every
  token, comment, whitespace, and error node; the tree round-trips back to the
  original source.
- **Structured diagnostics** — Stable `FATHOM-PARSE-*` codes with severity,
  byte ranges, and statement IDs; never crashes on incomplete or malformed input.
- **Editor mode** — `strict` for validation, `editor` for error-recovery on
  half-typed SQL (IDE scenario).
- **CST formatting** — Keyword case, indentation, line width, comma style,
  newline style, trailing-newline policy; refuses to emit partial output on
  error trees.
- **SQL fingerprinting** — Deterministic content-normalized fingerprint for
  query caching and deduplication.
- **Column-level lineage** — Trace input/output columns from DML/DDL through a
  caller-injected `Catalog` (Doris only).

## Install

```bash
npm install @fathom-sql/sql
```

## Quick start (Node)

```js
import { parse, format, fingerprint, capabilities } from '@fathom-sql/sql';

// Parse — validate SQL and get structured diagnostics
const result = parse('SELECT 1', 'doris', '4.x', 'strict');
console.log(result.valid);          // true
console.log(result.diagnostics);    // []

// Format — canonical output preserving comments
const fmt = format('select 1', 'doris', '4.x', 'strict', { keyword_case: 'upper' });
console.log(new TextDecoder().decode(new Uint8Array(fmt.formatted)));  // "SELECT 1\n"

// Fingerprint — deterministic content hash
const fp = fingerprint('SELECT 1', 'doris', '4.x', 'strict');
console.log(fp.fingerprint);        // non-empty deterministic string

// Capabilities — discover supported dialects and profiles
console.log(capabilities());
// { dialects: [ { dialect: 'doris', profiles: [...] }, { dialect: 'flink', profiles: [...] } ] }

// Diagnostics carry byte offsets — convert to line/column for editor display
import { byteOffsetToLineColumn, withLineColumns } from '@fathom-sql/sql';

const result2 = parse('SELECT FROM', 'doris', '4.x', 'strict');
const pos = byteOffsetToLineColumn('SELECT FROM', result2.diagnostics[0].start_byte);
// { line: 0, column: 7 }

withLineColumns('SELECT FROM', result2.diagnostics); // adds start_line/column in-place
```

## Browser usage

The same ESM entry works in bundlers (Vite/webpack/Rollup) and modern browsers.
The binding is self-contained — no Node built-ins, no `fs`, no `path`.

```html
<script type="module">
  import { parse } from 'https://esm.sh/@fathom-sql/sql@1.0.2';

  const result = parse('SELECT * FROM t', 'doris', '4.x', 'strict');
  console.log(result.valid);
</script>
```

## API reference

All functions accept `string` or `Uint8Array` as the `raw` input and return
decoded JSON envelopes (the `fathom.*.v1` wire schema). See `index.d.ts` for
full TypeScript signatures.

| Function | Wire schema | Description |
|---|---|---|
| `parse(raw, dialect, profile, mode?)` | `fathom.parse.v1` | Parse SQL; returns `valid`, `diagnostics[]`, CST metadata |
| `format(raw, dialect, profile, mode?, options?)` | `fathom.format.v1` | Format SQL; returns `accepted`, `formatted` (byte array), `diagnostics[]` |
| `complete(raw, dialect, profile, cursorByte)` | `fathom.complete.v1` | Syntax-aware completion at cursor position |
| `lint(raw, dialect, profile, mode?)` | `fathom.lint.v1` | Lint SQL; returns diagnostics with lint-specific codes |
| `fingerprint(raw, dialect, profile, mode?)` | `fathom.fingerprint.v1` | Deterministic content-normalized fingerprint |
| `capabilities()` | `fathom.capabilities.v1` | Supported dialects and profiles metadata |
| `dialect(d)` | `fathom.dialect.v1` | Per-dialect profile and feature metadata |
| `byteOffsetToLineColumn(raw, byteOffset)` | — (JS helper) | Convert UTF-8 byte offset to 0-based `{ line, column }` |
| `lineColumnToByteOffset(raw, line, column)` | — (JS helper) | Convert 0-based `{ line, column }` to UTF-8 byte offset |
| `withLineColumns(raw, diagnostics)` | — (JS helper) | Attach `start_line`/`start_column`/`end_line`/`end_column` to diagnostics in-place |

### Types

```ts
type Dialect = 'doris' | 'flink';
type DorisProfile = '2.1' | '3.x' | '4.x';
type FlinkProfile = 'flink-2.3.0' | 'flink-2.1.3' | 'flink-1.20.5';
type Profile = DorisProfile | FlinkProfile;
type Mode = 'strict' | 'editor';
type Raw = string | Uint8Array;

interface FormatOptions {
  keyword_case?: 'upper' | 'lower';
  indent?: number;          // default 2
  line_width?: number;      // default 100
  comma_style?: 'trailing' | 'leading';
  newline_style?: 'follow' | 'lf' | 'crlf';
  trailing_newline?: boolean;
}
```

## Boundaries

- **Flink support is syntax-level only**: lexical and grammar coverage,
  diagnostics, and formatting — no planner, catalog resolution, type checking,
  or execution equivalence for the Flink engine.
- **Wasm GC is not a first-class target**: only linear Wasm and the JS backend
  are published.
- **Lineage is Doris-only**: `lineage()` rejects a Flink selection with a
  structured `FATHOM-SCHEMA-*` error.

See the [full release notes and boundary disclosure](https://github.com/tchivs/fathom-sql/releases/tag/v1.0.0)
in the GitHub repository.

## Building from source

```bash
git clone https://github.com/tchivs/fathom-sql.git
cd fathom-sql
node npm/build.mjs   # builds js+wasm binding, copies artifacts,
                     # regenerates capabilities.json, packs the tarball
```

Requires the MoonBit toolchain (pinned to `moon 0.1.20260819` via
`.github/moonbit-toolchain.json`).

## Links

- [GitHub repository](https://github.com/tchivs/fathom-sql)
- [Getting started](https://github.com/tchivs/fathom-sql/blob/master/docs/GETTING-STARTED.md)
- [Issue tracker](https://github.com/tchivs/fathom-sql/issues)

## License

Apache-2.0 — see [LICENSE](https://github.com/tchivs/fathom-sql/blob/master/LICENSE).
