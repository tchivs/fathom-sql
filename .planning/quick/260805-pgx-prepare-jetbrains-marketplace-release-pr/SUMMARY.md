---
phase: quick
plan: 260805-pgx-prepare-jetbrains-marketplace-release-pr
subsystem: jetbrains-marketplace-release
tags: [jetbrains, marketplace, intellij, gradle, ci, signing, publishing]
status: complete
created: 2026-08-05
completed: 2026-08-05
dependency_graph:
  requires: [LSP4IJ 0.20.1, IntelliJ IDEA Community 2025.2, JDK 21]
  provides: [Marketplace-ready IntelliJ plugin metadata, release DSL, CI packaging workflow]
  affects: [jetbrains plugin distribution and release documentation]
tech_stack:
  added: [Apache-2.0 license, IntelliJ Platform Plugin Verifier release matrix, GitHub Actions JDK 21 workflow]
  patterns: [open plugin descriptor range, environment-backed signing and publishing secrets, manual first Marketplace upload]
key_files:
  created:
    - LICENSE
    - .github/workflows/jetbrains-plugin.yml
  modified:
    - jetbrains/build.gradle.kts
    - jetbrains/src/main/resources/META-INF/plugin.xml
    - jetbrains/scripts/source-smoke.py
    - jetbrains/README.md
decisions:
  - Keep the plugin descriptor open above since-build 252 and use Plugin Verifier's stable IntelliJ IDEA release channel for builds 252 through 261.
  - Keep IntelliJ IDEA Community 2025.2 as the compile baseline and LSP4IJ at 0.20.1.
  - Read signing values from CERTIFICATE_CHAIN, PRIVATE_KEY, and PRIVATE_KEY_PASSWORD, and Marketplace publishing from PUBLISH_TOKEN; CI publishing remains intentionally disabled.
  - Require the first Marketplace upload to be manual before enabling the signed publishing flow.
  - Preserve GitHub Releases plus four-platform Native doris-lsp auto-download as an explicit blocker until the public owner/repository, exact asset names, and a signed SHA-256 manifest are supplied.
metrics:
  duration: session
  tasks: 1
  files: 7
---

# Quick Task: JetBrains Marketplace Release Preparation Summary

Prepared the IntelliJ plugin for Marketplace release without enabling an unverifiable Native binary downloader or automatic Marketplace publishing.

## What Changed

- Added the user-selected Apache License 2.0 text at the repository root.
- Updated the Gradle release DSL to keep the plugin descriptor open above build 252, verify stable IntelliJ IDEA releases from build 252 through 261, retain the IC 2025.2 compile baseline and LSP4IJ 0.20.1, and configure signing/publishing from environment variables.
- Removed the stale plugin descriptor upper bound and incorrect Apache Doris vendor URL while retaining stable ID `fathom.doris.sql` and existing vendor contact text.
- Expanded the source smoke contract to cover release metadata, signing/publishing DSL, open descriptor range, Apache license, and CI workflow in addition to runtime wiring and dependency boundaries.
- Documented Apache-2.0 licensing, release secrets, manual first upload, compatibility coverage, CI behavior, metadata requirements, and the Native auto-download blocker.
- Added JDK 21 GitHub Actions source-smoke, test, Plugin Verifier, packaging, and ZIP artifact upload steps. Publishing is not automatic.

## Evidence

- `python3 jetbrains/scripts/source-smoke.py` — PASS.
- `JAVA_HOME=/opt/usr.../java-21-openjdk-21.0.9... ./gradlew --no-daemon clean test buildPlugin` — PASS after the release configuration.
- `./gradlew --no-daemon tasks --all` — PASS after the DSL configuration.
- `verifyPlugin` with the 252–261 product matrix timed out after 1800 seconds while downloading/resolving the multi-IDE verification matrix; no final matrix pass is claimed. The previous single IC 252.23892.409 verification passed.
- GitHub account discovery found no Fathom repository under `tchivs`; no release URL or repository coordinate was fabricated.

## Native Auto-Download Blocker

The plugin continues to use the explicit local `doris-lsp` executable contract. GitHub Releases auto-download remains blocked until all of the following are provided and approved:

1. Public GitHub owner and repository coordinates.
2. Exact release asset names for Linux x64, macOS x64, macOS arm64, and Windows x64 Native binaries.
3. A signed SHA-256 manifest covering those assets.

Until then, the plugin must not add a remote fallback or claim a downloadable release source.

## Release Procedure Decision

Keep signing and publishing credentials outside Git and provide them through `CERTIFICATE_CHAIN`, `PRIVATE_KEY`, `PRIVATE_KEY_PASSWORD`, and `PUBLISH_TOKEN`. Perform the first Marketplace upload manually, validate the fresh-IDE experience with LSP4IJ and the supported profiles, then use the signed `signPlugin verifyPluginSignature publishPlugin` flow only after Marketplace listing and Native release inputs are approved.

## Scope Guard

Only the seven requested release-preparation files are intended for the atomic commit. Generated Gradle/IntelliJ caches, build outputs, proxy settings, unrelated planning files, and unrelated worktree changes remain unstaged.
