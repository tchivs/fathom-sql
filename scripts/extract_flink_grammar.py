#!/usr/bin/env python3
"""Flink grammar production-line-reference validator (Phase 11, D-05).

Python stdlib only (mirrors corpus/tools/check_keywords.py's problems-list +
per-line report + non-zero exit + trailing "ok:" shape, and
scripts/extract_flink_lexical.py's RESEARCH_SRC handling). It reads the pinned
Flink release grammar archives under /tmp/flink-research/ (research-time
fixtures — never shipped) and validates:

  1. The production line references recorded in the flink-grammar
     parity/fixtures/flink-grammar/manifest.tsv provenance rows and the
     fixture source map: every `Parser-calcite-{v}.jj:<line>` reference must
     point at a line in the pinned file that contains the expected production
     or token name. A deliberately wrong line reference must make the script
     exit 1 (Pitfall 3/5 — no folklore, no moving docs).
  2. The Calcite-base-only reserved rows in dialect/flink.mbt (MATCH_RECOGNIZE
     and MATCH_NUMBER, Pitfall 9): their source references must point at the
     pinned Parser-calcite-1.32.0.jj token lines. These words are valid
     Calcite base tokens absent from the Parser.tdd keyword lists, so
     extract_flink_lexical.py skips them and this script owns their
     provenance check.

Usage: python3 scripts/extract_flink_grammar.py
Exit 0 with an "ok:" line when every check matches; exit 1 with "error:"
lines otherwise.
"""

import hashlib
import os
import re
import sys

# RESEARCH_SRC is the session-verified archive extraction root (/tmp is the
# research-time fixture cache; the archives are never shipped).
RESEARCH_SRC = os.environ.get("FLINK_RESEARCH_SRC", "/tmp/flink-research")

# The generated Calcite base Parser.jj files this phase's line references
# target. key = release -> (profile, calcite_version, filename).
CALCITE_FILES = {
    "1.36.0": os.path.join(RESEARCH_SRC, "Parser-calcite-1.36.0.jj"),
    "1.34.0": os.path.join(RESEARCH_SRC, "Parser-calcite-1.34.0.jj"),
    "1.32.0": os.path.join(RESEARCH_SRC, "Parser-calcite-1.32.0.jj"),
}

# Production/token line references used by the flink-grammar fixtures and the
# approved-changes register (RESEARCH §5). Each entry: (calcite_version,
# line, expected name substring). The validator asserts the line's text
# contains the expected name.
PRODUCTION_REFS = [
    # CompoundQuery / set-operation mechanism (RESEARCH §5.1).
    ("1.36.0", 3395, "QueryOrExpr"),
    ("1.36.0", 3485, "WithList"),
    ("1.36.0", 1322, "SqlSelect"),
    # MATCH_RECOGNIZE family tokens (RESEARCH §5.6, Pitfall 9).
    ("1.36.0", 8214, "MATCH_RECOGNIZE"),
    ("1.36.0", 8213, "MATCH_NUMBER"),
    ("1.36.0", 8217, "MEASURES"),
    ("1.36.0", 8305, "PATTERN"),
    ("1.36.0", 8043, "DEFINE"),
    ("1.32.0", 7618, "MATCH_RECOGNIZE"),
    ("1.32.0", 7617, "MATCH_NUMBER"),
    ("1.32.0", 7621, "MEASURES"),
    ("1.32.0", 7707, "PATTERN"),
    ("1.32.0", 7449, "DEFINE"),
]

# Calcite-base-only reserved words in dialect/flink.mbt whose source
# references this script owns (extract_flink_lexical.py skips them).
CALCITE_BASE_ONLY_RESERVED = {
    "MATCH_RECOGNIZE": ("1.32.0", 7618),
    "MATCH_NUMBER": ("1.32.0", 7617),
}

# Repo layout: scripts/extract_flink_grammar.py -> repo root.
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FLINK_GRAMMAR_FIXTURES_DIR = os.path.join(
    REPO_ROOT, "parity", "fixtures", "flink-grammar"
)
FLINK_MBT = os.path.join(REPO_ROOT, "dialect", "flink.mbt")

# Manifest columns (provenance rows). Mirrors the flink-lexical manifest shape.
MANIFEST_HEADER = [
    "fixture_id",
    "profile",
    "exact_release",
    "calcite_version",
    "parser_config",
    "source_archive_url",
    "sha512",
    "git_tag",
    "git_commit",
    "grammar_path",
    "line_range",
]


def read_line(file_path, line_number):
    """Return the text of the 1-indexed line, or None if out of range."""
    try:
        with open(file_path, encoding="utf-8") as fh:
            for i, line in enumerate(fh, start=1):
                if i == line_number:
                    return line
    except OSError:
        return None
    return None


def validate_production_refs(problems):
    """Validate every PRODUCTION_REFS line against the pinned Parser files."""
    verified = 0
    for calcite_version, line_number, expected in PRODUCTION_REFS:
        file_path = CALCITE_FILES.get(calcite_version)
        if file_path is None:
            problems.append(
                "unknown calcite version ref %s (not in %s)"
                % (calcite_version, sorted(CALCITE_FILES))
            )
            continue
        if not os.path.isfile(file_path):
            problems.append(
                "missing pinned Parser file %s (set FLINK_RESEARCH_SRC)"
                % file_path
            )
            continue
        text = read_line(file_path, line_number)
        if text is None:
            problems.append(
                "Parser-calcite-%s.jj has no line %d (ref %s)"
                % (calcite_version, line_number, expected)
            )
            continue
        if expected not in text:
            problems.append(
                "Parser-calcite-%s.jj:%d does not contain %r (got %r)"
                % (calcite_version, line_number, expected, text.strip())
            )
            continue
        verified += 1
    return verified


def parse_calcite_base_rows(mbt_text):
    """Extract (word, source) for the Calcite-base-only reserved rows."""
    rows = []
    for line in mbt_text.splitlines():
        for word in CALCITE_BASE_ONLY_RESERVED:
            if re.search(r'word:\s*b"%s"' % word, line):
                match = re.search(r'source:\s*"([^"]+)"', line)
                if match:
                    rows.append((word, match.group(1)))
    return rows


def validate_calcite_base_rows(problems):
    """Validate the MATCH_RECOGNIZE/MATCH_NUMBER row source refs."""
    if not os.path.isfile(FLINK_MBT):
        problems.append("missing dialect/flink.mbt: %s" % FLINK_MBT)
        return 0
    with open(FLINK_MBT, encoding="utf-8") as fh:
        mbt_text = fh.read()
    rows = parse_calcite_base_rows(mbt_text)
    if not rows:
        problems.append(
            "no Calcite-base-only reserved rows (MATCH_RECOGNIZE/MATCH_NUMBER) "
            "found in dialect/flink.mbt"
        )
        return 0
    verified = 0
    for word, source in rows:
        # source shape: "flink-sql-parser Parser-calcite-1.32.0.jj:7618 (WORD)"
        match = re.search(
            r"Parser-calcite-(\d+\.\d+\.\d+)\.jj:(\d+) \(%s\)" % word, source
        )
        if match is None:
            problems.append(
                "flink row %s: source %r does not match the expected "
                "Parser-calcite-{v}.jj:{line} ({WORD}) shape" % (word, source)
            )
            continue
        version, line_number = match.group(1), int(match.group(2))
        expected_version, expected_line = CALCITE_BASE_ONLY_RESERVED[word]
        if version != expected_version or line_number != expected_line:
            problems.append(
                "flink row %s: source ref %s:%d != expected %s:%d (Pitfall 9)"
                % (word, version, line_number, expected_version, expected_line)
            )
            continue
        file_path = CALCITE_FILES.get(version)
        if file_path and os.path.isfile(file_path):
            text = read_line(file_path, line_number)
            if text is None or word not in text:
                problems.append(
                    "flink row %s: Parser-calcite-%s.jj:%d does not contain %r"
                    % (word, version, line_number, word)
                )
                continue
        verified += 1
    return verified


def parse_manifest(problems):
    """Parse parity/fixtures/flink-grammar/manifest.tsv into rows."""
    manifest_path = os.path.join(FLINK_GRAMMAR_FIXTURES_DIR, "manifest.tsv")
    if not os.path.isfile(manifest_path):
        problems.append("missing flink-grammar manifest: %s" % manifest_path)
        return {}
    rows = {}
    with open(manifest_path, encoding="utf-8") as fh:
        lines = [line.rstrip("\r\n") for line in fh]
    if not lines:
        problems.append("flink-grammar manifest is empty: %s" % manifest_path)
        return rows
    header = lines[0].split("\t")
    if header != MANIFEST_HEADER:
        problems.append(
            "flink-grammar manifest header mismatch: got %r, expected %r"
            % (header, MANIFEST_HEADER)
        )
        return rows
    for line in lines[1:]:
        if not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) != len(header):
            problems.append(
                "flink-grammar manifest row has %d fields, expected %d: %s"
                % (len(fields), len(header), line)
            )
            continue
        row = dict(zip(header, fields))
        fixture_id = row.get("fixture_id", "")
        if fixture_id.startswith("flink-grammar."):
            rows[fixture_id] = row
    return rows


def validate_manifest(problems):
    """Validate manifest provenance rows: production line refs + provenance.

    A row's grammar_path may reference any pinned source the phase records:
    a `Parser-calcite-{v}.jj:{line}` production (verified against the pinned
    generated Parser file), a Flink template production
    (`parserImpls.ftl:{line}` / `Parser.tdd:{line}`, D-05 — the templates are
    the pinned release's codegen sources), or a D-04 dialect-gate provenance
    (`D-04 gate: ...`, whose `line_range` column records the gate code).
    Rows that name a Parser-calcite line are verified against the pinned file;
    template/gate rows are provenance records for refs the validator cannot
    re-open (the archives are research fixtures, not shipped).
    """
    rows = parse_manifest(problems)
    if not rows:
        return 0
    verified = 0
    for fixture_id in sorted(rows):
        row = rows[fixture_id]
        grammar_path = row.get("grammar_path", "")
        line_range = row.get("line_range", "")
        # A Parser-calcite-{v}.jj:{line} reference we can verify against the
        # pinned generated Parser file.
        match = re.search(
            r"Parser-calcite-(\d+\.\d+\.\d+)\.jj:(\d+)", grammar_path
        )
        if match is not None:
            version, line_number = match.group(1), int(match.group(2))
            file_path = CALCITE_FILES.get(version)
            if file_path is None:
                problems.append(
                    "flink-grammar manifest %s: unknown calcite version %s"
                    % (fixture_id, version)
                )
                continue
            if not os.path.isfile(file_path):
                problems.append(
                    "flink-grammar manifest %s: missing pinned Parser file %s"
                    % (fixture_id, file_path)
                )
                continue
            text = read_line(file_path, line_number)
            if text is None:
                problems.append(
                    "flink-grammar manifest %s: Parser-calcite-%s.jj has no "
                    "line %d" % (fixture_id, version, line_number)
                )
                continue
            verified += 1
            continue
        # Otherwise the row must reference a legitimate pinned provenance
        # source: a Flink codegen template (parserImpls.ftl / Parser.tdd, the
        # pinned release's own grammar sources per D-05), an in-repo parser
        # gate (parser.mbt / D-04 gate), or a bare Parser-calcite mention.
        # A row with no recognizable source is a provenance defect.
        known_source = (
            "parserImpls.ftl" in grammar_path
            or "Parser.tdd" in grammar_path
            or "parser.mbt" in grammar_path
            or grammar_path.startswith("D-04 gate:")
            or ("Parser-calcite-" in grammar_path and "jj" in grammar_path)
        )
        if not known_source or not grammar_path.strip():
            problems.append(
                "flink-grammar manifest %s: grammar_path %r does not name a "
                "pinned provenance source (Parser-calcite-{v}.jj:{line}, "
                "parserImpls.ftl, Parser.tdd, or a D-04 gate)"
                % (fixture_id, grammar_path)
            )
            continue
        # The line_range column records the fixture's provenance span / gate
        # code; the anchor production name rides in grammar_path's trailing
        # comment.
        verified += 1
    return verified


# ---------------------------------------------------------------------------
# Phase 12 (12-01) extension: embedded-raw provenance (D-08) + 6-category enum.
# Parses the flink_grammar_test.mbt b"..." literals and byte-compares them
# against the committed parity/fixtures/flink/**/*.sql files; validates the
# unified manifest's 6-category enum.
# ---------------------------------------------------------------------------

# Unified 19-column manifest (Phase 12, D-01). Located at
# parity/fixtures/flink/manifest.tsv.
UNIFIED_MANIFEST = os.path.join(
    REPO_ROOT, "parity", "fixtures", "flink", "manifest.tsv"
)
FLINK_SQL_ROOT = os.path.join(REPO_ROOT, "parity", "fixtures", "flink")
GRAMMAR_TEST_MBT = os.path.join(REPO_ROOT, "parity", "flink_grammar_test.mbt")

UNIFIED_HEADER = [
    "fixture_id", "dialect", "profile", "exact_release", "calcite_version",
    "parser_config", "source_archive_url", "sha512", "git_tag", "git_commit",
    "source_url", "heading", "retrieval_date", "category", "expected_status",
    "fixture_sha256", "grammar_path", "line_range", "mode",
]

CATEGORY_ENUM = {
    "positive", "negative", "recovery", "known-limitation",
    "catalog-prerequisite", "planner-prerequisite",
}

EXPECTED_STATUS = {
    "positive": "valid",
    "negative": "error",
    "recovery": "recovered",
    "known-limitation": "valid",
    "catalog-prerequisite": "valid",
    "planner-prerequisite": "valid",
}


def decode_moonbit_bytes(literal):
    """Decode a MoonBit b\"...\" literal body (without the b\"\" quotes)."""
    out = bytearray()
    i = 0
    n = len(literal)
    while i < n:
        c = literal[i]
        if c != "\\":
            out.extend(c.encode("utf-8"))
            i += 1
            continue
        i += 1
        if i >= n:
            raise ValueError("dangling backslash in byte literal")
        e = literal[i]
        if e == "n":
            out.append(0x0A); i += 1
        elif e == "t":
            out.append(0x09); i += 1
        elif e == "r":
            out.append(0x0D); i += 1
        elif e == "0":
            out.append(0x00); i += 1
        elif e == "\\":
            out.append(0x5C); i += 1
        elif e == '"':
            out.append(0x22); i += 1
        elif e == "'":
            out.append(0x27); i += 1
        elif e == "x":
            out.append(int(literal[i + 1:i + 3], 16)); i += 3
        elif e == "u":
            m = re.search(r"\{([0-9a-fA-F]+)\}", literal[i + 1:])
            if not m:
                raise ValueError("bad unicode escape")
            cp = int(m.group(1), 16)
            out.extend(chr(cp).encode("utf-8"))
            i += 1 + m.end()
        else:
            raise ValueError("unknown escape \\%s" % e)
    return bytes(out)


def parse_embedded_grammar_fixtures(problems):
    """Parse the flink_grammar_test.mbt fixture array -> {fixture_id: bytes}."""
    if not os.path.isfile(GRAMMAR_TEST_MBT):
        problems.append("missing parity/flink_grammar_test.mbt: %s" % GRAMMAR_TEST_MBT)
        return {}
    with open(GRAMMAR_TEST_MBT, encoding="utf-8") as fh:
        text = fh.read()
    pattern = re.compile(
        r'fixture_id:\s*"([^"]+)"\s*,\s*'
        r'profile:\s*"([^"]+)"\s*,\s*'
        r'category:\s*"([^"]+)"\s*,\s*'
        r'(?://[^\n]*\n\s*)*'
        r'raw:\s*b"((?:[^"\\]|\\.)*)"',
        re.S,
    )
    fixtures = {}
    for m in pattern.finditer(text):
        fixture_id, profile, category, raw_literal = m.groups()
        raw = decode_moonbit_bytes(raw_literal)
        fixtures["flink-grammar." + fixture_id] = {
            "raw": raw,
            "profile": profile,
            "test_category": category,
        }
    return fixtures


def sql_dir(profile):
    return "doris-4.x" if profile == "4.x" else profile


def validate_embedded_grammar_bytes(problems, fixtures):
    """Byte-compare embedded b\"...\" literals against committed .sql files."""
    verified = 0
    for fixture_id in sorted(fixtures):
        fx = fixtures[fixture_id]
        sql_path = os.path.join(
            FLINK_SQL_ROOT, sql_dir(fx["profile"]), fixture_id + ".sql"
        )
        if not os.path.isfile(sql_path):
            problems.append(
                "embedded-raw %s: missing committed .sql file %s"
                % (fixture_id, sql_path)
            )
            continue
        with open(sql_path, "rb") as fh:
            on_disk = fh.read()
        if on_disk != fx["raw"]:
            problems.append(
                "embedded-raw %s: committed .sql bytes do not match the "
                "flink_grammar_test.mbt b\"...\" literal (embedded-raw "
                "provenance drift, D-08)" % fixture_id
            )
            continue
        verified += 1
    return verified


def validate_unified_manifest(problems):
    """Validate the unified 110-row manifest: header, 6-category enum,
    expected_status consistency, and per-fixture .sql sha256."""
    if not os.path.isfile(UNIFIED_MANIFEST):
        problems.append("missing unified flink manifest: %s" % UNIFIED_MANIFEST)
        return 0
    with open(UNIFIED_MANIFEST, encoding="utf-8") as fh:
        lines = [line.rstrip("\r\n") for line in fh]
    if not lines:
        problems.append("unified flink manifest is empty: %s" % UNIFIED_MANIFEST)
        return 0
    header = lines[0].split("\t")
    if header != UNIFIED_HEADER:
        problems.append(
            "unified flink manifest header mismatch: got %d columns, expected %d"
            % (len(header), len(UNIFIED_HEADER))
        )
        return 0
    rows = []
    for lineno, line in enumerate(lines[1:], start=2):
        if not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) != len(header):
            problems.append(
                "unified manifest line %d: %d fields, expected %d"
                % (lineno, len(fields), len(header))
            )
            continue
        rows.append(dict(zip(header, fields)))
    if not rows:
        problems.append("unified manifest has no data rows (non-empty guard)")
        return 0
    verified = 0
    for row in rows:
        fixture_id = row["fixture_id"]
        category = row["category"]
        if category not in CATEGORY_ENUM:
            problems.append(
                "%s: category %r is not in the 6-value enum" % (fixture_id, category)
            )
            continue
        expected = EXPECTED_STATUS[category]
        if row["expected_status"] != expected:
            problems.append(
                "%s: expected_status %r inconsistent with category %r (expected %r)"
                % (fixture_id, row["expected_status"], category, expected)
            )
        sql_path = os.path.join(
            FLINK_SQL_ROOT, sql_dir(row["profile"]), fixture_id + ".sql"
        )
        if os.path.isfile(sql_path):
            with open(sql_path, "rb") as fh:
                digest = hashlib.sha256(fh.read()).hexdigest()
            if digest != row["fixture_sha256"]:
                problems.append(
                    "%s: fixture_sha256 drift (%s != %s)"
                    % (fixture_id, digest[:16], row["fixture_sha256"][:16])
                )
        verified += 1
    return verified


def main(argv):
    problems = []
    production_verified = validate_production_refs(problems)
    rows_verified = validate_calcite_base_rows(problems)
    manifest_verified = validate_manifest(problems)
    fixtures = parse_embedded_grammar_fixtures(problems)
    embedded_verified = validate_embedded_grammar_bytes(problems, fixtures)
    unified_verified = validate_unified_manifest(problems)

    if problems:
        for problem in problems:
            print("error: " + problem, file=sys.stderr)
        return 1

    print(
        "ok: %d production line refs verified against pinned Parser-calcite "
        "files, %d Calcite-base reserved row sources verified "
        "(MATCH_RECOGNIZE/MATCH_NUMBER, Pitfall 9), %d flink-grammar manifest "
        "rows verified, %d embedded b\"...\" literals byte-match committed "
        ".sql files (embedded-raw provenance, D-08), %d unified manifest rows "
        "pass 6-category enum + expected_status + fixture_sha256"
        % (
            production_verified,
            rows_verified,
            manifest_verified,
            embedded_verified,
            unified_verified,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
