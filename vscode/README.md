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

The package manifest pins `vscode-languageclient@10.1.0` and the release-only
`@vscode/vsce@3.9.2`. Build/release tooling must keep the Native `doris-lsp`
executable separate from this JavaScript client package.

A final host checkpoint still requires a machine with VS Code and a local
`doris-lsp`; this repository does not claim that manual checkpoint passed.
