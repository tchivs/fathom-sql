# Fathom SQL IntelliJ Plugin

This directory contains a Kotlin/Gradle IntelliJ Platform plugin that connects the Fathom SQL language server through [LSP4IJ](https://github.com/redhat-developer/lsp4ij). It does not contain a parser or a second LSP transport.

## Installation and settings

Build the plugin ZIP with `./gradlew buildPlugin`, then install it from **Settings | Plugins | Gear | Install Plugin from Disk**. The plugin has a hard dependency on LSP4IJ `0.20.1`; install that dependency from JetBrains Marketplace first.

Configure **Settings | Tools | Fathom SQL**:

- **fathom-lsp executable**: local executable path or command name; defaults to `fathom-lsp` and is used as the fallback when a managed release cannot be downloaded.
- **Dialect**: `doris` or `flink`; no default — an explicit selection is required (D-02).
- **Profile**: exactly `2.1`, `3.x`, or `4.x`; no default — an explicit selection is required.
- **Download managed fathom-lsp binaries from GitHub Releases**: enabled by default. Disable it to use only the configured executable.

Settings are read when a new LSP4IJ server connection starts. Applying settings does not mutate an already-running process; restart the server for changes to take effect. SQL files are mapped by filename (`*.sql`) and receive language id `sql`. The dialect and profile are forwarded as LSP `initializationOptions` (`{"dialect": ..., "profile": ...}`); an empty selection is surfaced as an explicit server-side configuration error, never an implicit fallback.

When managed downloads are enabled, the plugin detects Linux x64, macOS arm64, and Windows x64, downloads the matching `fathom-lsp-*` asset from the latest release of `tchivs/fathom-sql`, verifies the SHA-256 listed in `fathom-lsp-manifest.json`, and caches the executable under the platform cache directory. Network errors, unsupported platforms (including macOS Intel), missing releases, and hash mismatches fall back to the configured executable.

## Build and verification

The project uses the checked-in Gradle 9.6.1 wrapper, IntelliJ Platform Gradle Plugin 2.18.1, Kotlin JVM 2.4.10, IntelliJ IDEA Community 2025.2 as the compile baseline, and JDK 21. The plugin descriptor leaves the upper IDE bound open; Plugin Verifier selects stable IntelliJ IDEA releases from build 252 through 261 for the current compatibility matrix.

```bash
./gradlew --no-daemon test
./gradlew --no-daemon compileKotlin compileTestKotlin
python3 scripts/source-smoke.py
./gradlew --no-daemon clean test verifyPlugin buildPlugin
```

The resulting ZIP is written to `build/distributions/`. The CI workflow runs the source smoke, Kotlin tests, Plugin Verifier, and packaging, then uploads the ZIP as a workflow artifact.

## Native release assets

The root workflow `.github/workflows/fathom-native-release.yml` builds the `fathom-lsp/` executable on three runners and publishes these exact assets:

| Platform key | Release asset |
| --- | --- |
| `linux-x86_64` | `fathom-lsp-linux-x86_64` |
| `macos-aarch64` | `fathom-lsp-macos-aarch64` |
| `windows-x86_64` | `fathom-lsp-windows-x86_64.exe` |

Every release also contains `fathom-lsp-manifest.json` with `schemaVersion`, the exact release `tag`, and the SHA-256 for each binary. Tag pushes (`v*`) and manual dispatches publish through the `tchivs/fathom-sql` repository.

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

The first Marketplace publication must be uploaded manually. Before that upload, complete a fresh-IDE check with LSP4IJ installed and verify diagnostics, formatting, completion, dialect/profile propagation, and managed Native fallback behavior. Native release assets are published separately by the root GitHub Actions workflow.

The Marketplace metadata uses the public project homepage `https://github.com/tchivs/fathom-sql` and the monitored vendor contact `maintainers@fathom.dev`.

## CI

`.github/workflows/jetbrains-plugin.yml` runs on JetBrains plugin changes and performs:

1. JDK 21 setup;
2. source contract smoke;
3. Kotlin tests;
4. IntelliJ Plugin Verifier compatibility checks;
5. plugin ZIP packaging and artifact upload.

`.github/workflows/fathom-native-release.yml` runs on `v*` tag pushes or manual dispatch, builds and verifies the three Native assets, generates the signed-by-hash manifest, and uploads the release assets. Marketplace publishing remains manual until the first listing and signing secrets are approved.

## External release links

- [IntelliJ Platform publishing guide](https://plugins.jetbrains.com/docs/intellij/publishing-plugin.html)
- [Plugin signing guide](https://plugins.jetbrains.com/docs/intellij/plugin-signing.html)
- [Plugin compatibility verification](https://plugins.jetbrains.com/docs/intellij/verifying-plugin-compatibility.html)
