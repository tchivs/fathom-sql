# Doris SQL IntelliJ Plugin

This directory contains a Kotlin/Gradle IntelliJ Platform plugin that connects the Doris SQL language server through [LSP4IJ](https://github.com/redhat-developer/lsp4ij). It does not contain a parser or a second LSP transport.

## Installation and settings

Build the plugin ZIP with `./gradlew buildPlugin`, then install it from **Settings | Plugins | Gear | Install Plugin from Disk**. The plugin has a hard dependency on LSP4IJ `0.20.1`; install that dependency from JetBrains Marketplace first.

Configure **Settings | Tools | Doris SQL**:

- **doris-lsp executable**: local executable path or command name; defaults to `doris-lsp`.
- **Doris profile**: exactly `2.1`, `3.x`, or `4.x`; defaults to `4.x`.

Settings are read when a new LSP4IJ server connection starts. Applying settings does not mutate an already-running process; restart the server for changes to take effect. SQL files are mapped by filename (`*.sql`) and receive language id `doris`.

The current ZIP uses the explicit local-executable path contract. Automatic download from GitHub Releases is a release follow-up and must not be enabled until the public repository owner/name, release asset names, and SHA-256 manifest are fixed. No remote fallback is used.

## Build and verification

The project uses the checked-in Gradle 9.0.0 wrapper, IntelliJ Platform Gradle Plugin 2.9.0, Kotlin JVM 2.2.0, IntelliJ IDEA Community 2025.2 as the compile baseline, and JDK 21. The plugin descriptor leaves the upper IDE bound open; Plugin Verifier selects stable IntelliJ IDEA releases from build 252 through 261 for the current compatibility matrix.

```bash
./gradlew --no-daemon test
./gradlew --no-daemon compileKotlin compileTestKotlin
python3 scripts/source-smoke.py
./gradlew --no-daemon clean test verifyPlugin buildPlugin
```

The resulting ZIP is written to `build/distributions/`. The CI workflow runs the source smoke, Kotlin tests, Plugin Verifier, and packaging, then uploads the ZIP as a workflow artifact.

## Marketplace release preparation

The repository is licensed under Apache-2.0. Keep signing keys and the Marketplace token outside Git. Configure these environment variables only in a local shell or CI secret store:

```text
CERTIFICATE_CHAIN
PRIVATE_KEY
PRIVATE_KEY_PASSWORD
PUBLISH_TOKEN
```

After the first manual upload is accepted by JetBrains Marketplace, a signed release can be published with:

```bash
./gradlew --no-daemon signPlugin verifyPluginSignature publishPlugin
```

The first Marketplace publication must be uploaded manually. Before that upload, complete a fresh-IDE check with LSP4IJ installed, verify diagnostics/formatting/completion/profile propagation, and publish compatible `doris-lsp` Native binaries separately for Linux x64, macOS x64, macOS arm64, and Windows x64. The automatic GitHub Releases downloader remains blocked until the public repository coordinates and release manifest are supplied.

The final Marketplace metadata must use the real public project homepage and a monitored vendor contact; the source repository currently has no configured remote, so no repository URL is fabricated here.

## CI

`.github/workflows/jetbrains-plugin.yml` runs on JetBrains plugin changes and performs:

1. JDK 21 setup;
2. source contract smoke;
3. Kotlin tests;
4. IntelliJ Plugin Verifier compatibility checks;
5. plugin ZIP packaging and artifact upload.

Publishing is intentionally not automatic in CI until the first Marketplace listing, signing secrets, and Native release source are approved.

## External release links

- [IntelliJ Platform publishing guide](https://plugins.jetbrains.com/docs/intellij/publishing-plugin.html)
- [Plugin signing guide](https://plugins.jetbrains.com/docs/intellij/plugin-signing.html)
- [Plugin compatibility verification](https://plugins.jetbrains.com/docs/intellij/verifying-plugin-compatibility.html)
