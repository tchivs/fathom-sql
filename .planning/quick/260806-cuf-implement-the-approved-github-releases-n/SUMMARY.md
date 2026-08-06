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
- Known release constraint: the public MoonBit installer no longer serves the historical `0.1.20260724` archive used by the checkout, so the workflow selects `latest` and records the resolved `moon version` in its build log. Pinning can be restored when the exact archive is republished.
- `moon check --target native lsp`: passed with existing warnings only.
- `moon build --target native --release lsp`: passed; `_build/native/release/build/lsp/lsp.exe` exists.

## Release verification

- GitHub Actions run `31077474356` passed all four build jobs and the publish job.
- Public release `v0.1.0` is non-draft/non-prerelease and contains all four binaries plus `doris-lsp-manifest.json`.
- Downloaded release assets locally and confirmed every binary SHA-256 equals the published manifest.
- A later local Gradle rerun against unrelated uncommitted Kotlin `2.4.10`/IntelliJ Platform `2.18.1` updates failed because `kotlin-compiler-embeddable:2.4.10` was unavailable from the configured Maven cache; the committed plugin verification passed before those external updates.
