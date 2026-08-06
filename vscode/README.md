# Doris SQL Language Client

This extension is a thin standard `vscode-languageclient` host for the local Native
`doris-lsp` executable. It does not start a service, connect to Doris FE, use a
database, or provide a remote fallback.

## Configuration

Set these explicit settings before opening a Doris SQL document:

- `doris.profile`: `2.1`, `3.x`, or `4.x` (default `4.x`; there is no automatic profile).
- `doris.serverPath`: local executable path (default `doris-lsp`).

The selected profile is passed as `initializationOptions.profile` during standard
LSP initialization. Doris files use the `doris` language selector and receive
native Problems diagnostics, `Format Document`, and syntax-aware completion.

If the executable is missing or exits, the client shows:

> Doris language server unavailable. Check the local executable path and try again.

The document remains an ordinary editable text document; there is no HTTP or
network fallback.

## Local development

The package manifest pins `vscode-languageclient@10.1.0`, the release-only
`@vscode/vsce@3.9.2`, and `typescript@7.0.2` (build-only). Build/release
tooling must keep the Native `doris-lsp` executable separate from this
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
`@vscode/test-electron` against the local `doris-lsp` executable and asserts the
full standard-client contract end to end:

- **functional** (profile 4.x): structured diagnostics with stable code +
  UTF-16 ranges in Problems, comment-preserving `Format Document` edits,
  parser-known completion, and 4.x MERGE accepted.
- **profile** (profile 2.1): MERGE rejected with `DORIS-PARSE-006` — proves the
  configured profile reaches the server via `initialize`.
- **fallback** (nonexistent server path): the document stays editable and the
  fixed "Doris language server unavailable" message surfaces instead of a crash.

Prerequisites: a display for VS Code (headless CI uses `xvfb-run`), `node` with
the pinned devDependencies, and a local `doris-lsp` build. The VS Code binary is
downloaded once into `.vscode-test/` by `@vscode/test-electron`.

The client requires a **`LogOutputChannel`** (`createOutputChannel(name, { log: true })`)
because `vscode-languageclient@10.1.0` calls `.error()`/`.trace()`/`onDidChangeLogLevel`
on the channel it is given; a plain output channel makes server startup fail
immediately (caught by this host checkpoint).
