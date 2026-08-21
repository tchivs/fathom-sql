# @fathom-sql/sql

Fathom SQL Parser SDK — a MoonBit-built parser and toolchain for Apache Doris
and Flink SQL, exposed as an ES module. The package ships the built
JavaScript binding (`binding.js`), the linear-Wasm artifact (`binding.wasm`),
typed declarations, and dialect/profile capability metadata.

## Install

```bash
npm install @fathom-sql/sql
```

## Usage (Node)

```js
import { parse, format, fingerprint, capabilities } from '@fathom-sql/sql';

const result = parse('SELECT 1', 'doris', '4.x', 'strict');
console.log(result.valid);          // true
console.log(result.diagnostics);    // []

const fmt = format('select 1', 'doris', '4.x', 'strict', { keyword_case: 'upper' });
console.log(fmt.accepted);          // true

const fp = fingerprint('SELECT 1', 'doris', '4.x', 'strict');
console.log(fp.fingerprint);        // non-empty deterministic fingerprint

console.log(capabilities());        // dialect/profile capability metadata
```

## Usage (browser)

The same ESM entry works in bundlers (Vite/webpack) and modern browsers; the
binding is self-contained (no Node built-ins).

## API surface

`parse`, `format`, `complete`, `lint`, `fingerprint`, `lineage`,
`capabilities`, `dialect` — see `index.d.ts` for signatures and the
`fathom.*.v1` envelope shapes in `docs/API.md`.

## Boundaries

Flink support is syntax-level only (no planner/catalog/type/execution
equivalence); Wasm GC is not first-class. See `RELEASE-NOTES.md` in the
repository for the full disclosure.

## Building from source

```bash
node npm/build.mjs   # runs moon build (js+wasm binding), copies artifacts,
                     # regenerates capabilities.json, and packs the tarball
```
