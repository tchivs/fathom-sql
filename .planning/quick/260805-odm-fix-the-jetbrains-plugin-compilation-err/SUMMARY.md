---
quick_task: 260805-odm-fix-the-jetbrains-plugin-compilation-err
status: complete
completed: 2026-08-05
---

# JetBrains Plugin Compilation Fixes

JetBrains plugin compilation, verification, and packaging fixes are recorded for the verified IntelliJ IC 2025.2 build.

## Changes

- Imported `com.intellij.openapi.ui.ComboBox` in `DorisSettingsConfigurable.kt`, replacing the non-compiling UI package import.
- Added JUnit 4.13.2 test runtime support, configured IC 2025.2 plugin verification, and switched the IntelliJ platform dependency to `create("IC", "2025.2")` in `build.gradle.kts`; retained LSP4IJ 0.20.1 and Kotlin 2.2.0.
- Changed the plugin ID from `fathom.doris.intellij` to `fathom.doris.sql` in `plugin.xml`, satisfying JetBrains verifier ID validation.

## Verification

The supplied verification evidence reports success for:

- `JAVA_HOME=/usr/lib/jvm/java-21-openjdk-21.0.9.0.10-2.el9.alma.1.x86_64 ./gradlew --no-daemon test --console=plain`
- `JAVA_HOME=/usr/lib/jvm/java-21-openjdk-21.0.9.0.10-2.el9.alma.1.x86_64 JAVA_TOOL_OPTIONS='-Dhttp.proxyHost=192.168.29.53 -Dhttp.proxyPort=1081 -Dhttps.proxyHost=192.168.29.53 -Dhttps.proxyPort=1081' ./gradlew --no-daemon test verifyPlugin buildPlugin --console=plain`
- `python3 scripts/source-smoke.py`

The resulting ZIP is `jetbrains/build/distributions/fathom-doris-intellij-0.1.0.zip`, and the verifier report marks `fathom.doris.sql:0.1.0` compatible for IC 252.23892.409.

## Scope and Artifacts

Only the three JetBrains implementation files and this summary are included in the commit. Generated `jetbrains/build/`, `jetbrains/.gradle/`, and `jetbrains/.intellijPlatform/` artifacts are excluded. The user-local `/root/.gradle/gradle.properties` proxy configuration is not part of the repository changes or commit.


## Self-Check: PASSED

- Summary and all three target implementation files exist.
- Commit contains exactly the summary and three target implementation files.
- No proxy configuration, build output, or Gradle cache artifact is included.