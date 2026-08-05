#!/usr/bin/env python3
"""Deterministic source-level contract checks for the Doris IntelliJ plugin."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []

def require(path: str, pattern: str, description: str) -> None:
    text = (ROOT / path).read_text(encoding="utf-8")
    if not re.search(pattern, text, re.MULTILINE | re.DOTALL):
        errors.append(f"{path}: missing {description} ({pattern})")

build = (ROOT / "build.gradle.kts").read_text(encoding="utf-8")
for value, description in (("2.9.0", "IntelliJ Platform Gradle Plugin version"), ("2.2.0", "Kotlin JVM version"), ("0.20.1", "LSP4IJ version")):
    if value not in build:
        errors.append(f"build.gradle.kts: missing {description} {value}")
if re.search(r"org\\.eclipse\\.lsp4j|lsp4j\\s*[:\\\"]", build, re.IGNORECASE):
    errors.append("build.gradle.kts: independently declared LSP4J runtime")

plugin = (ROOT / "src/main/resources/META-INF/plugin.xml").read_text(encoding="utf-8")
require("src/main/resources/META-INF/plugin.xml", r'<depends>com\.redhat\.devtools\.lsp4ij</depends>', "LSP4IJ plugin dependency")
require("src/main/resources/META-INF/plugin.xml", r'<server\s+id="doris"[^>]*factoryClass="fathom\.jetbrains\.doris\.DorisLanguageServerFactory"', "Doris server factory")
require("src/main/resources/META-INF/plugin.xml", r'<fileNamePatternMapping\s+patterns="\*\.sql"\s+serverId="doris"\s+languageId="doris"', "SQL filename mapping")
require("src/main/resources/META-INF/plugin.xml", r'applicationConfigurable[^>]*instance="fathom\.jetbrains\.doris\.DorisSettingsConfigurable"', "application settings configurable")

for source in ("src/main/kotlin/fathom/jetbrains/doris/DorisSettings.kt", "src/main/kotlin/fathom/jetbrains/doris/DorisSettingsConfigurable.kt", "src/main/kotlin/fathom/jetbrains/doris/DorisLanguageServerFactory.kt"):
    if not (ROOT / source).exists():
        errors.append(f"{source}: source file missing")

require("src/main/kotlin/fathom/jetbrains/doris/DorisLanguageServerFactory.kt", r"LanguageServerFactory", "LanguageServerFactory API")
require("src/main/kotlin/fathom/jetbrains/doris/DorisLanguageServerFactory.kt", r"createConnectionProvider\(project:\s*Project\)", "createConnectionProvider(Project)")
require("src/main/kotlin/fathom/jetbrains/doris/DorisLanguageServerFactory.kt", r"OSProcessStreamConnectionProvider", "stdio process provider")
require("src/main/kotlin/fathom/jetbrains/doris/DorisLanguageServerFactory.kt", r"GeneralCommandLine", "GeneralCommandLine")
require("src/main/kotlin/fathom/jetbrains/doris/DorisLanguageServerFactory.kt", r"getInitializationOptions\(rootUri:\s*VirtualFile\)", "initialization options override")
require("src/main/kotlin/fathom/jetbrains/doris/DorisLanguageServerFactory.kt", r'"profile"', "profile initialization key")
require("src/main/kotlin/fathom/jetbrains/doris/DorisSettings.kt", r'DEFAULT_EXECUTABLE\s*=\s*"doris-lsp"', "default executable")
require("src/main/kotlin/fathom/jetbrains/doris/DorisSettings.kt", r'DEFAULT_PROFILE\s*=\s*"4\.x"', "default profile")
require("src/main/kotlin/fathom/jetbrains/doris/DorisSettings.kt", r'listOf\("2\.1",\s*"3\.x",\s*"4\.x"\)', "released profile set")

for path in ROOT.rglob("*"):
    if not path.is_file() or ".gradle" in path.parts or "build" in path.parts:
        continue
    if path.name in {"source-smoke.py", "README.md", "gradlew", "gradlew.bat", "plugin.xml"}:
        continue
    text = path.read_text(encoding="utf-8", errors="ignore")
    if re.search(r"org\.eclipse\.lsp4j|lsp4j\.jsonrpc|https?://|jdbc:|Doris FE|doris-fe", text, re.IGNORECASE):
        errors.append(f"{path.relative_to(ROOT)}: forbidden second transport/runtime or remote fallback text")

if errors:
    print("SOURCE SMOKE FAILED")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)
print("SOURCE SMOKE PASSED: plugin wiring, settings propagation, stdio provider, and dependency boundaries")
