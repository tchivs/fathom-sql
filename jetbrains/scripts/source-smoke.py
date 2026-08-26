#!/usr/bin/env python3
"""Deterministic source-level contract checks for the Fathom IntelliJ plugin."""
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
require(
    build_path,
    r'id\("org\.jetbrains\.intellij\.platform"\)\s+version\s+"2\.\d+\.\d+"',
    "IntelliJ Platform Gradle Plugin version",
)
require(
    build_path,
    r'id\("org\.jetbrains\.kotlin\.jvm"\)\s+version\s+"2\.\d+\.\d+"',
    "Kotlin JVM version",
)
require(build_path, r'plugin\("com\.redhat\.devtools\.lsp4ij",\s*"0\.20\.1"\)', "LSP4IJ version")
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
require(plugin_path, r"<id>fathom\.sql</id>", "stable Marketplace plugin ID")
require(plugin_path, r"<depends>com\.redhat\.devtools\.lsp4ij</depends>", "LSP4IJ plugin dependency")
require(plugin_path, r'<server\s+id="fathom-sql"[^>]*factoryClass="fathom\.jetbrains\.sql\.FathomLanguageServerFactory"', "Fathom server factory")
require(plugin_path, r'<fileNamePatternMapping\s+patterns="\*\.sql"\s+serverId="fathom-sql"\s+languageId="sql"', "SQL filename mapping")
require(plugin_path, r'applicationConfigurable[^>]*instance="fathom\.jetbrains\.sql\.FathomSettingsConfigurable"', "application settings configurable")
if re.search(r"until-build=", plugin):
    errors.append("plugin.xml: upper IDE bound must remain open")

for source in (
    "src/main/kotlin/fathom/jetbrains/sql/FathomSettings.kt",
    "src/main/kotlin/fathom/jetbrains/sql/FathomSettingsConfigurable.kt",
    "src/main/kotlin/fathom/jetbrains/sql/FathomLanguageServerFactory.kt",
    "src/main/kotlin/fathom/jetbrains/sql/FathomNativeDownloader.kt",
):
    source_path = ROOT / source
    if not source_path.exists():
        errors.append(f"{source}: source file missing")

factory_path = ROOT / "src/main/kotlin/fathom/jetbrains/sql/FathomLanguageServerFactory.kt"
require(factory_path, r"LanguageServerFactory", "LanguageServerFactory API")
require(factory_path, r"createConnectionProvider\(project:\s*Project\)", "createConnectionProvider(Project)")
require(factory_path, r"OSProcessStreamConnectionProvider", "stdio process provider")
require(factory_path, r"GeneralCommandLine", "GeneralCommandLine")
require(factory_path, r"getInitializationOptions\(rootUri:\s*VirtualFile\)", "initialization options override")
require(factory_path, r'"dialect"', "dialect initialization key")
require(factory_path, r'"profile"', "profile initialization key")
require(factory_path, r"resolveExecutable", "managed executable resolution")
settings_path = ROOT / "src/main/kotlin/fathom/jetbrains/sql/FathomSettings.kt"
require(settings_path, r'DEFAULT_EXECUTABLE\s*=\s*"fathom-lsp"', "default executable")
require(settings_path, r'@State\(name\s*=\s*"FathomSettings",\s*storages\s*=\s*\[Storage\("fathom\.xml"\)\]\)', "FathomSettings state + fathom.xml storage")
require(settings_path, r"ALLOWED_DIALECTS: List<String> = listOf\(\"doris\", \"flink\"\)", "dialect set")
require(settings_path, r"DEFAULT_USE_GITHUB_RELEASES\s*=\s*true", "managed Native default")
# D-05: per-dialect (dialect, profile) pairs replace the flat profile list —
# flink values appear only under flink (same-commit rule, Pitfall 5).
require(
    settings_path,
    r'PROFILES_BY_DIALECT: Map<String, List<String>> = mapOf\(\s*"doris" to listOf\("2\.1",\s*"3\.x",\s*"4\.x"\),\s*"flink" to listOf\("flink-2\.3\.0",\s*"flink-2\.1\.3",\s*"flink-1\.20\.5"\),?\s*\)',
    "per-dialect profile map",
)
require(settings_path, r"fun normalizeProfile\(dialect: String, value: String\?\): String\?", "per-dialect normalizeProfile signature")
settings_text = settings_path.read_text(encoding="utf-8")
if re.search(r"ALLOWED_PROFILES\s*[:=]", settings_text):
    errors.append("FathomSettings.kt: ALLOWED_PROFILES flat profile list must not exist (D-05, per-dialect PROFILES_BY_DIALECT)")
if re.search(r"DEFAULT_PROFILE\s*=", settings_text):
    errors.append("FathomSettings.kt: DEFAULT_PROFILE must not exist (D-02, no default profile)")
license_path = PROJECT_ROOT / "LICENSE"
if not license_path.exists():
    errors.append("LICENSE: Apache-2.0 license file missing")
else:
    require(license_path, r"Apache License", "Apache-2.0 license text")

workflow_path = PROJECT_ROOT / ".github/workflows/jetbrains-plugin.yml"
if not workflow_path.exists():
    errors.append(".github/workflows/jetbrains-plugin.yml: CI workflow missing")
else:
    require(workflow_path, r"setup-java@v6", "JDK setup")
    require(workflow_path, r"verifyPlugin", "Plugin Verifier CI step")
    require(workflow_path, r"buildPlugin", "plugin packaging CI step")

native_workflow_path = PROJECT_ROOT / ".github/workflows/fathom-native-release.yml"
if not native_workflow_path.exists():
    errors.append(".github/workflows/fathom-native-release.yml: Native release workflow missing")
else:
    require(native_workflow_path, r"linux-x86_64", "Linux Native asset")
    require(native_workflow_path, r"macos-aarch64", "macOS arm64 Native asset")
    require(native_workflow_path, r"windows-x86_64", "Windows Native asset")
    require(native_workflow_path, r"fathom-lsp-manifest\.json", "Native SHA-256 manifest")

allowed_remote_sources = {
    ROOT / "src/main/kotlin/fathom/jetbrains/sql/FathomNativeDownloader.kt",
    ROOT / "src/test/kotlin/fathom/jetbrains/sql/FathomNativeDownloaderTest.kt",
}

for path in ROOT.rglob("*"):
    if not path.is_file():
        continue
    # Exclude via ROOT-relative components only (MI-03): path.parts includes
    # ancestors above ROOT, so a checkout under a directory literally named
    # "build" would silently skip every plugin source file. __pycache__ is
    # this script's own py_compile bytecode (the naming-gate battery runs
    # py_compile on it) and must never be scanned as a plugin source.
    rel_parts = path.relative_to(ROOT).as_posix().split("/")
    if any(part in {".gradle", ".intellijPlatform", "build", "__pycache__"} for part in rel_parts):
        continue
    if path.name in {"source-smoke.py", "README.md", "CLAUDE.md", "gradlew", "gradlew.bat", "plugin.xml"}:
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
