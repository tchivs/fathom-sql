---
status: complete
created: 2026-08-06
completed: 2026-08-06
---

# GitHub Releases Native delivery

## Goal

Ship the approved GitHub Releases distribution path for `doris-lsp` in the JetBrains plugin and publish reproducible Native release assets for `tchivs/doris-sql-parser-sdk`.

## Contract

- Release assets use four exact platform keys: `linux-x86_64`, `macos-x86_64`, `macos-aarch64`, and `windows-x86_64`.
- Asset names are `doris-lsp-linux-x86_64`, `doris-lsp-macos-x86_64`, `doris-lsp-macos-aarch64`, and `doris-lsp-windows-x86_64.exe`.
- Each release contains `doris-lsp-manifest.json` with `schemaVersion: 1`, the exact release tag, and SHA-256 values.
- Managed download is enabled by default, cached for 24 hours, verified before installation, and falls back to the configured local executable on every failure.

## Changes

1. Add a four-runner GitHub Actions Native release workflow, pinned to the recorded MoonBit version, including Windows installation and manifest generation.
2. Add a bounded HTTPS GitHub asset downloader with platform detection, URL/repository validation, manifest/tag validation, SHA-256 verification, atomic cache writes, executable permissions, and stale-cache fallback.
3. Add a persisted settings toggle and wire resolution into the LSP4IJ process provider.
4. Add deterministic downloader/settings tests, update source smoke contracts, plugin metadata, and release documentation.

## Verification

- `./gradlew --no-daemon clean test buildPlugin` — passed.
- `python3 scripts/source-smoke.py` — passed.
- `moon check --target native lsp` — passed with pre-existing warnings.
- `moon build --target native --release lsp` — passed; `_build/native/release/build/lsp/lsp.exe` exists.
- Native downloader tests cover four platform mappings, verified cache reuse, hash mismatch rejection, and configured-command fallback.
- `.github/workflows/doris-native-release.yml` parses as YAML.
