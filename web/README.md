# @fathom-sql/sql-web-demo

[![MoonBit](https://img.shields.io/badge/MoonBit-0.1.20260819-2f80ed)](https://www.moonbitlang.com/)
[![Targets](https://img.shields.io/badge/targets-js%20%7C%20wasm-555555)](moon.mod)
[![Doris](https://img.shields.io/badge/Doris-2.1%20%7C%203.x%20%7C%204.x-blue)](https://doris.apache.org/)
[![Flink](https://img.shields.io/badge/Flink-1.20.5%20%7C%202.1.3%20%7C%202.3.0-blue)](https://flink.apache.org/)
[![License](https://img.shields.io/github/license/tchivs/fathom-sql?color=blue)](https://github.com/tchivs/fathom-sql/blob/master/LICENSE)

> Part of [Fathom SQL Parser SDK](https://github.com/tchivs/fathom-sql) — see the [root README](https://github.com/tchivs/fathom-sql#readme) for the full feature list and architecture.

Offline Monaco editor host for the Fathom SQL parser facade. This demo loads
`@fathom-sql/sql` in the browser, wires parse/format/diagnostics to a Monaco
editor instance, and runs entirely client-side — no server, no network calls to
Doris or Flink.

## Quick start

```bash
npm install
npm start   # serves index.html on a local port
```

## Build

```bash
npm run build   # offline smoke test
npm test        # node --test
```

## Architecture

- `src/main.ts` — Monaco editor initialization and Fathom API wiring
- `src/monaco-adapter.ts` — adapts Fathom diagnostics/edits to Monaco markers/edits

The demo depends on `monaco-editor@0.56.0` and the published `@fathom-sql/sql`
npm package. It is a private package (`@fathom-sql/sql-web-demo`) and not
published to any registry.

## License

Apache-2.0 — see [LICENSE](https://github.com/tchivs/fathom-sql/blob/master/LICENSE).
