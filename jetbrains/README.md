# Doris SQL IntelliJ Plugin

This directory contains a Kotlin/Gradle IntelliJ Platform plugin that connects the existing local `doris-lsp` Native executable through [LSP4IJ](https://github.com/redhat-developer/lsp4ij). It does not contain a parser or a second LSP transport.

## Installation and settings

Build the plugin ZIP with `./gradlew buildPlugin`, then install the ZIP from **Settings | Plugins | Gear | Install Plugin from Disk**. The plugin depends on LSP4IJ `0.20.1`, which must be installed/resolved by the IntelliJ plugin build.

Configure **Settings | Tools | Doris SQL**:

- **doris-lsp executable**: local executable path or command name; defaults to `doris-lsp`.
- **Doris profile**: exactly `2.1`, `3.x`, or `4.x`; defaults to `4.x`.

Settings are read when a new LSP4IJ server connection starts. Applying settings does not mutate an already-running process; restart the server for changes to take effect. SQL files are mapped by filename (`*.sql`) and receive language id `doris`.

## Build and verification

The project uses the checked-in Gradle 8.14 wrapper, IntelliJ Platform Gradle Plugin `2.9.0`, Kotlin JVM `2.2.0`, IntelliJ IDEA Community `2025.2`, and JDK 21.

```bash
./gradlew --no-daemon test
./gradlew --no-daemon compileKotlin compileTestKotlin
python3 scripts/source-smoke.py
./gradlew --no-daemon clean test verifyPlugin buildPlugin
./gradlew --offline --no-daemon test verifyPlugin buildPlugin
```

The final two commands require the IntelliJ SDK, Kotlin, and LSP4IJ artifacts to be available from configured Gradle caches/repositories. If an offline build cannot resolve an artifact, retain the exact Gradle coordinate in the task report rather than weakening or replacing the pinned dependency.
