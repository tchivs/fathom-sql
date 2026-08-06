---
status: complete
created: 2026-08-06
completed: 2026-08-06
---

# GitHub Releases Native delivery summary

## Delivered

- Added `.github/workflows/doris-native-release.yml` for Linux x64, macOS x64, macOS arm64, and Windows x64 Native builds.
- Fixed the release asset contract and generated `doris-lsp-manifest.json` with exact tags and SHA-256 values.
- Added `DorisNativeDownloader` with bounded HTTPS transport, GitHub repository URL allowlisting, platform detection, manifest/tag validation, SHA-256 verification, atomic writes, executable permissions, 24-hour metadata caching, and stale-cache fallback.
- Added persisted `useGitHubReleases` settings, UI toggle, LSP provider resolution, and configured-command fallback.
- Updated plugin metadata, README release instructions, and source smoke checks.
- Added tests for platform mapping, verified cache reuse, hash mismatch rejection, and fallback behavior.

## Verification

- `./gradlew --no-daemon clean test buildPlugin`: passed; 10 tests passed, 0 failures; plugin ZIP produced.
- `python3 scripts/source-smoke.py`: passed.
- Native Release workflow YAML parsed successfully.
- `moon check --target native lsp`: passed with existing warnings only.
- `moon build --target native --release lsp`: passed; `_build/native/release/build/lsp/lsp.exe` exists.

## Release prerequisite

The workflow publishes assets when a `v*` tag is pushed or when manually dispatched with a tag. The first release still needs to be triggered so the downloader has a public `latest` release to consume.
