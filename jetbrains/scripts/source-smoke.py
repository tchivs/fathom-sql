#!/usr/bin/env python3
"""Deterministic source-level contract checks for the Doris IntelliJ plugin."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = ROOT.parent
errors: list[str] = []


def require(path: Path, pattern: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    if not re.search(pattern, text, re.MULTILINE | re.DOTALL):
        errors.append(f"{path.relative_to(PROJECT_ROOT)}: missing {description} ({pattern})")


build_path = ROOT / "build.gradle.kts"
build = build_path.read_text(encoding="utf-8")
for value, description in (
    ("2.9.0", "IntelliJ Platform Gradle Plugin version"),
    ("2.2.0", "Kotlin JVM version"),
    ("0.20.1", "LSP4IJ version"),
):
    if value not in build:
        errors.append(f"{build_path.relative_to(PROJECT_ROOT)}: missing {description} {value}")
if re.search(r"org\\.eclipse\\.lsp4j|lsp4j\\s*[:\\\"]", build, re.IGNORECASE):
    errors.append("build.gradle.kts: independently declared LSP4J runtime")
require(build_path, r"sinceBuild\s*=\s*\"252\"", "minimum IntelliJ build")
require(build_path, r"select\s*\{", "Plugin Verifier product matrix")
require(build_path, r"signing\s*\{", "signing configuration")
require(build_path, r"publishing\s*\{", "Marketplace publishing configuration")
if re.search(r"ideaVersion\s*\{[^}]*untilBuild", build):
    errors.append("build.gradle.kts: plugin descriptor upper IDE bound must remain open")

plugin_path = ROOT / "src/main/resources/META-INF/plugin.xml"
plugin = plugin_path.read_text(encoding="utf-8")
require(plugin_path, r"<id>fathom\.doris\.sql</id>", "stable Marketplace plugin ID")
require(plugin_path, r"<depends>com\.redhat\.devtools\.lsp4ij</depends>", "LSP4IJ plugin dependency")
require(plugin_path, r'<server\s+id="doris"[^>]*factoryClass="fathom\.jetbrains\.doris\.DorisLanguageServerFactory"', "Doris server factory")
require(plugin_path, r'<fileNamePatternMapping\s+patterns="\*\.sql"\s+serverId="doris"\s+languageId="doris"', "SQL filename mapping")
require(plugin_path, r'applicationConfigurable[^>]*instance="fathom\.jetbrains\.doris\.DorisSettingsConfigurable"', "application settings configurable")
if re.search(r"until-build=", plugin):
    errors.append("plugin.xml: upper IDE bound must remain open")

for source in (
    "src/main/kotlin/fathom/jetbrains/doris/DorisSettings.kt",
    "src/main/kotlin/fathom/jetbrains/doris/DorisSettingsConfigurable.kt",
    "src/main/kotlin/fathom/jetbrains/doris/DorisLanguageServerFactory.kt",
    "src/main/kotlin/fathom/jetbrains/doris/DorisNativeDownloader.kt",
):
    source_path = ROOT / source
    if not source_path.exists():
        errors.append(f"{source}: source file missing")

factory_path = ROOT / "src/main/kotlin/fathom/jetbrains/doris/DorisLanguageServerFactory.kt"
require(factory_path, r"LanguageServerFactory", "LanguageServerFactory API")
require(factory_path, r"createConnectionProvider\(project:\s*Project\)", "createConnectionProvider(Project)")
require(factory_path, r"OSProcessStreamConnectionProvider", "stdio process provider")
require(factory_path, r"GeneralCommandLine", "GeneralCommandLine")
require(factory_path, r"getInitializationOptions\(rootUri:\s*VirtualFile\)", "initialization options override")
require(factory_path, r'"profile"', "profile initialization key")
require(factory_path, r"resolveExecutable", "managed executable resolution")
settings_path = ROOT / "src/main/kotlin/fathom/jetbrains/doris/DorisSettings.kt"
require(settings_path, r'DEFAULT_EXECUTABLE\s*=\s*"doris-lsp"', "default executable")
require(settings_path, r'DEFAULT_PROFILE\s*=\s*"4\.x"', "default profile")
require(settings_path, r"DEFAULT_USE_GITHUB_RELEASES\s*=\s*true", "managed Native default")
require(settings_path, r'listOf\("2\.1",\s*"3\.x",\s*"4\.x"\)', "released profile set")
license_path = PROJECT_ROOT / "LICENSE"
if not license_path.exists():
    errors.append("LICENSE: Apache-2.0 license file missing")
else:
    require(license_path, r"Apache License", "Apache-2.0 license text")

workflow_path = PROJECT_ROOT / ".github/workflows/jetbrains-plugin.yml"
if not workflow_path.exists():
    errors.append(".github/workflows/jetbrains-plugin.yml: CI workflow missing")
else:
    require(workflow_path, r"setup-java@v4", "JDK setup")
    require(workflow_path, r"verifyPlugin", "Plugin Verifier CI step")
    require(workflow_path, r"buildPlugin", "plugin packaging CI step")

native_workflow_path = PROJECT_ROOT / ".github/workflows/doris-native-release.yml"
if not native_workflow_path.exists():
    errors.append(".github/workflows/doris-native-release.yml: Native release workflow missing")
else:
    require(native_workflow_path, r"linux-x86_64", "Linux Native asset")
    require(native_workflow_path, r"macos-aarch64", "macOS arm64 Native asset")
    require(native_workflow_path, r"windows-x86_64", "Windows Native asset")
    require(native_workflow_path, r"doris-lsp-manifest\.json", "Native SHA-256 manifest")

allowed_remote_sources = {
    ROOT / "src/main/kotlin/fathom/jetbrains/doris/DorisNativeDownloader.kt",
    ROOT / "src/test/kotlin/fathom/jetbrains/doris/DorisNativeDownloaderTest.kt",
}

for path in ROOT.rglob("*"):
    if not path.is_file() or ".gradle" in path.parts or "build" in path.parts:
        continue
    if path.name in {"source-smoke.py", "README.md", "gradlew", "gradlew.bat", "plugin.xml"}:
        continue
    if path in allowed_remote_sources:
        continue
    text = path.read_text(encoding="utf-8", errors="ignore")
    if re.search(r"org\.eclipse\.lsp4j|lsp4j\.jsonrpc|https?://|jdbc:|Doris FE|doris-fe", text, re.IGNORECASE):
        errors.append(f"{path.relative_to(ROOT)}: forbidden second transport/runtime or remote fallback text")

if errors:
    print("SOURCE SMOKE FAILED")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)
print("SOURCE SMOKE PASSED: runtime wiring, release metadata, signing/publishing DSL, CI, and dependency boundaries")
