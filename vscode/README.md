# Fathom SQL Language Client

This extension is a thin standard `vscode-languageclient` host for the local Native
`fathom-lsp` executable. It does not start a service, connect to a database, or
provide a remote fallback.

## Install

1. Install this extension from the **VS Code Marketplace** or **Open VSX**
   (search "Fathom SQL Language Client").
2. Acquire the `fathom-lsp` language server from a **GitHub Release**
   (<https://github.com/tchivs/fathom-sql/releases>) — see the repository
   README's "Install `fathom-lsp` from GitHub Release" section: pick the
   asset for your platform (`fathom-lsp-linux-x86_64`,
   `fathom-lsp-macos-aarch64`, or `fathom-lsp-windows-x86_64.exe`), verify its
   SHA-256 against `fathom-lsp-manifest.json`, and place it on your `PATH`
   (recommended: `~/.fathom/bin`).
3. Verify the server: `fathom-lsp --version` must print `fathom-lsp 1.0.0`.
4. Set `fathom.serverPath` to the installed executable if it is not on
   `PATH`, and set the required `fathom.dialect` / `fathom.profile` settings
   (see Configuration below).

## Configuration

Set these explicit settings before opening a SQL document:

- `fathom.dialect`: `doris` or `flink` (no default; a missing selection is an
  explicit configuration error — there is no implicit fallback).
- `fathom.profile`: `2.1`, `3.x`, or `4.x` (no default; a missing selection is an
  explicit configuration error).
- `fathom.serverPath`: local executable path (default `fathom-lsp`).

The selected dialect and profile are passed as `initializationOptions.dialect`
and `initializationOptions.profile` during standard LSP initialization. SQL files
use the `sql` language selector and receive native Problems diagnostics,
`Format Document`, and syntax-aware completion.

If the executable is missing or exits, the client shows:

> Fathom SQL language server unavailable. Check the local executable path and try again.

The document remains an ordinary editable text document; there is no HTTP or
network fallback.

## Local development

The package manifest pins `vscode-languageclient@10.1.0`, the release-only
`@vscode/vsce@3.9.2`, and `typescript@7.0.2` (build-only). Build/release
tooling must keep the Native `fathom-lsp` executable separate from this
JavaScript client package.

## Build

The extension host loads the compiled CommonJS entry `dist/extension.js`
(`"main"` in the manifest), so TypeScript sources must be compiled before the
extension can run or be packaged:

- `npm run compile` — `tsc -p .`, emitting `dist/` from `src/` (test files
  are excluded; they run directly on the TS sources via Node type stripping).
- `npm run package` — compile, then `vsce package`.

The TypeScript devDependency resolves from the npm cache, so the build works
offline (`npm ci --offline && npm run compile`).

## Host verification (ECO-07)

`npm run host-verify` launches three real VS Code extension hosts via
`@vscode/test-electron` against the local `fathom-lsp` executable and asserts the
full standard-client contract end to end:

- **functional** (dialect doris, profile 4.x): structured diagnostics with stable
  code + UTF-16 ranges in Problems, comment-preserving `Format Document` edits,
  parser-known completion, and 4.x MERGE accepted.
- **profile** (dialect doris, profile 2.1): MERGE rejected with
  `FATHOM-PARSE-006` — proves the configured profile reaches the server via
  `initialize`.
- **fallback** (nonexistent server path): the document stays editable and the
  fixed "Fathom SQL language server unavailable" message surfaces instead of a
  crash.

Prerequisites: a display for VS Code (headless CI uses `xvfb-run`), `node` with
the pinned devDependencies, and a local `fathom-lsp` build. The VS Code binary is
downloaded once into `.vscode-test/` by `@vscode/test-electron`.

The client requires a **`LogOutputChannel`** (`createOutputChannel(name, { log: true })`)
because `vscode-languageclient@10.1.0` calls `.error()`/`.trace()`/`onDidChangeLogLevel`
on the channel it is given; a plain output channel makes server startup fail
immediately (caught by this host checkpoint).
