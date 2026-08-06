#!/usr/bin/env python3
"""NAME-04 neutral-naming inventory gate (Python stdlib only).

Usage: python3 scripts/check_naming.py

Scans product files (source, config, CI, extensions, docs) for forbidden
product-level remnants of the legacy Doris product identity and exits non-zero
on any hit outside the D-04/D-05 exemptions. The allowlist is limited to Doris
dialect semantics and provenance (D-05); historical archives are exempt (D-04).

Mirror of corpus/tools/check_keywords.py: stdlib problems loop, non-zero exit,
ok line. The gate is mode+file-scope dual-dimension (research §7 / Pitfall 4):
only the FORBIDDEN product-surface patterns fail, so the required dialect
semantics (Dialect::Doris, DorisProfile, doris as a dialect value,
doris.apache.org, corpus provenance, the tchivs/doris-sql-parser-sdk release
repository identifier) are never destroyed by a mechanical global rename.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# ---------------------------------------------------------------------------
# Forbidden product-surface patterns (research §7.3). Each entry is
# (regex, description). Matching is case-sensitive: the legacy product names
# are case-sensitive identifiers; `doris` as a bare dialect value is legal
# (DIALECT-01) and is NOT in this list.
# ---------------------------------------------------------------------------
FORBIDDEN = [
    (r"doris-sql", "legacy CLI/module/package name (doris-sql)"),
    (r"doris-lsp", "legacy LSP binary/server identity (doris-lsp)"),
    (r"doris_(parse|format|profile|capabilities)_v1", "legacy binding export symbol (doris_*_v1)"),
    (r"doris\.(parse|format|error|profile|capabilities)\.v1", "legacy wire schema (doris.*.v1)"),
    # D-10 diagnostic code families. The historical requirement identifiers
    # DORIS-01..09 (Phase 2/3 comments) are exempt via the negative lookahead.
    (r"DORIS-(?!0\d)", "legacy diagnostic code prefix (DORIS-)"),
    (r"fathom/doris-sql", "legacy module import path (fathom/doris-sql)"),
    (r"fathom\.doris\.sql", "legacy IntelliJ plugin id (fathom.doris.sql)"),
    (r"onLanguage:doris", "legacy language activation (onLanguage:doris)"),
    (r'"id": "doris"', 'legacy language id ("id": "doris")'),
    (r'server id="doris"', 'legacy LSP4IJ server id (server id="doris")'),
    (r"language: 'doris'", "legacy documentSelector language (language: 'doris')"),
    (r"doris\.profile", "legacy VS Code config key (doris.profile)"),
    (r"doris\.serverPath", "legacy VS Code config key (doris.serverPath)"),
    (r"doris\.restartLanguageServer", "legacy VS Code command (doris.restartLanguageServer)"),
    (r'"DorisSettings"', 'legacy JetBrains state name ("DorisSettings")'),
    (r"doris\.xml", "legacy JetBrains state storage (doris.xml)"),
    (r"\bDoris(?:LanguageServerFactory|Settings|SettingsConfigurable|NativeDownloader|NativePlatform)\b", "legacy JetBrains class name (Doris*)"),
    (r"fathom\.jetbrains\.doris", "legacy JetBrains package (fathom.jetbrains.doris)"),
    (r"Doris SQL Language (Client|Server)", "legacy product display title (Doris SQL Language ...)"),
    (r'"Doris SQL"', 'legacy product display title ("Doris SQL")'),
]

# Semantic identifiers that may legally contain a forbidden token (D-05 /
# OQ8). They are stripped from the line before the corresponding pattern runs
# so only the product-surface usage is reported.
ALLOWLIST_CONTEXTS = {
    "doris-sql": ["tchivs/doris-sql-parser-sdk"],  # release repository identifier (OQ8)
}

# ---------------------------------------------------------------------------
# Scan scope (research §7.2): product source/config/CI/extension/docs files.
# ---------------------------------------------------------------------------
SCAN_SUFFIXES = (
    ".mbt", ".ts", ".mjs", ".js", ".kt", ".kts", ".json",
    ".yml", ".yaml", ".mod", ".pkg", ".py",
)

EXCLUDED_DIRS = {
    ".git",
    "node_modules",
    "_build",
    ".gradle",
    ".intellijPlatform",
    ".vscode-test",
}

# Generated build-output directories that are scanned by extension but must be
# skipped as artifacts (research §7.2 / Runtime State Inventory): gradle
# output under jetbrains/build, the tsc output under vscode/dist, and the
# MoonBit build output target/ (IN-04b — local `moon build` runs leave
# target/**/*.js that must never be treated as product source).
BUILD_OUTPUT_DIRS = {"build", "dist", "target"}


def is_scannable(path: Path) -> bool:
    rel = path.relative_to(ROOT).as_posix()
    name = path.name
    # Match exclusion sets against ROOT-relative components only (MI-03):
    # path.parts includes ancestors above ROOT, so a checkout under any
    # directory literally named build/dist/.git/... would silently exclude
    # EVERY file and the gate would pass with "0 files scanned".
    rel_parts = rel.split("/")
    if any(part in EXCLUDED_DIRS or part in BUILD_OUTPUT_DIRS for part in rel_parts):
        return False
    if name == "package-lock.json" or name.startswith("tsconfig"):
        return False
    if name == "check_naming.py":
        return False
    if name.endswith(".gradle") or name.endswith(".gradle.kts"):
        return True
    if name.endswith(SCAN_SUFFIXES):
        if name.endswith((".mjs", ".js")) and "/node_modules/" in "/" + rel + "/":
            return False
        return True
    # Markdown: only README*.md and docs/** are product docs (research §7.2);
    # .planning/** markdown is planning documentation, not product surface.
    if name.endswith(".md"):
        return name.startswith("README") or rel.startswith("docs/")
    return False


def exempted(path: Path) -> bool:
    """D-04 historical archives + harness/tooling state + embedded provenance."""
    rel = path.relative_to(ROOT).as_posix()
    for prefix in (
        "corpus/",                 # provenance (D-04): fixtures, manifests, tools
        ".planning/milestones/",   # archived milestone evidence (D-04)
        ".planning/research/",     # archived research evidence (D-04)
        ".planning/phases/",       # historical phase documents (D-04)
    ):
        if rel.startswith(prefix):
            return True
    if rel.startswith(".planning/.omp-"):
        return True  # OMP harness state, not product surface
    return False


# Files whose DORIS- family text lives only inside byte-embedded corpus
# fixture literals (provenance per D-04/D-08: parity/baseline_test.mbt embeds
# the exact corpus .sql bytes pinned by parity/baseline-hashes.txt;
# test/formatter_test.mbt embeds the same fixtures). These two files are
# exempt from the DORIS- pattern ONLY; all other patterns still apply.
# The exemption is deliberately file-scoped and coarse (IN-03): any NEW
# DORIS- text added OUTSIDE fixture literals in these files would silently
# pass, so the files' headers carry an explicit NAMING-GATE CONSTRAINT
# comment — keep that constraint in force when editing them.
EMBEDDED_FIXTURE_FILES = {
    "parity/baseline_test.mbt",
    "test/formatter_test.mbt",
}


def main() -> int:
    problems = []
    scanned = 0
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or not is_scannable(path) or exempted(path):
            continue
        rel = path.relative_to(ROOT).as_posix()
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeDecodeError):
            problems.append("%s: cannot read as UTF-8 text" % rel)
            continue
        for lineno, line in enumerate(lines, start=1):
            for pattern, description in FORBIDDEN:
                if pattern == "doris-sql" and ALLOWLIST_CONTEXTS["doris-sql"]:
                    for context in ALLOWLIST_CONTEXTS["doris-sql"]:
                        line = line.replace(context, "")
                if re.search(pattern, line):
                    if pattern == r"DORIS-(?!0\d)" and rel in EMBEDDED_FIXTURE_FILES:
                        continue
                    problems.append(
                        "%s:%d: %s matches %r" % (rel, lineno, description, pattern)
                    )
        scanned += 1
    # MI-03: a scan that matches zero product files proves nothing — the gate
    # must fail loudly rather than print "ok: 0 product files scanned". This
    # is the blind-spot guard for a misconfigured ROOT or an over-broad
    # exclusion set.
    if scanned == 0:
        print(
            "naming gate failed: 0 product files scanned — scan scope is empty "
            "(check ROOT, EXCLUDED_DIRS, and BUILD_OUTPUT_DIRS)",
            file=sys.stderr,
        )
        return 1
    if problems:
        for problem in problems:
            print("error: " + problem, file=sys.stderr)
        print(
            "naming gate failed: %d problem(s) in %d scanned product file(s)"
            % (len(problems), scanned),
            file=sys.stderr,
        )
        return 1
    print("ok: %d product files scanned, zero forbidden naming remnants" % scanned)
    return 0


if __name__ == "__main__":
    sys.exit(main())
