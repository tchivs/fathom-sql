#!/usr/bin/env python3
"""Flink release provenance extractor/validator (Phase 10, D-02).

Python stdlib only (mirrors corpus/tools/check_keywords.py's problems-list +
per-line report + non-zero exit + trailing "ok: N ..." shape). It reads the
pinned Flink release source archives under /tmp/flink-research/src/
(research-time fixtures — never shipped) and validates the three Calcite pins
and the shared parser configuration that scripts/extract_flink_lexical.py's
consumer (dialect/flink.mbt FlinkProfileMetadata + parity/fixtures/flink-lexical/
manifest.tsv) freezes. Calcite pins and parser-config metadata are taken ONLY
from the sha512-verified pinned release archives (D-02) — never hand-written
inference or Calcite folklore (Pitfall 3).

10-03 extends the validator to the keyword layer (RESEARCH §10):
  * the six committed full per-release reserved/nonreserved list files under
    parity/fixtures/flink-lexical/ are checked against the §10 counts
    (443/334, 430/324, 412/323) and the §10 release deltas;
  * every inlined flink_classification_rows word (dialect/flink.mbt) is
    checked for presence in the matching release list — a deliberately wrong
    word must make the script exit 1 (T-10-13/T-10-14);
  * the reserved ∩ nonreserved overlap words are reported, never silently
    resolved (probe FLINK-01 adjacency);
  * when the pinned archive is present, the Parser-release-{v}.tdd keyword /
    nonReservedKeywords inputs and the codegen/templates/Parser.jj VARIANT
    token are cross-checked against the committed lists.

The manifest.tsv provenance record is re-verified too (MN-03): every flink
row's calcite_version/parser_config must equal the code values, and when the
release archive is present under the research root its sha512 must match the
manifest sha512 column — a tampered manifest fails the gate.

Usage: python3 scripts/extract_flink_lexical.py
Exit 0 with an "ok:" line when every check matches; exit 1 with "error:" lines
otherwise (a deliberately wrong pin or row word must make it exit 1).
"""

import hashlib
import os
import re
import sys

# RESEARCH §7 pin table (2026-08-07 session-verified from each release POM).
# exact_release -> expected <calcite.version> from flink-table/pom.xml:81.
CALCITE_PINS = {
    "2.3.0": "1.36.0",
    "2.1.3": "1.34.0",
    "1.20.5": "1.32.0",
}

# RESEARCH §8 parser configuration — identical across the three releases
# (PlannerContext.java:256-260). The metadata string serialized into
# FlinkProfileMetadata.parser_config and the manifest parser_config column.
PARSER_CONFIG = "Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT"

# The PlannerContext.java parser-config construction lines (RESEARCH §8).
PARSER_CONFIG_LINES = [
    "SqlParser.config()",
    ".withParserFactory(FlinkSqlParserFactories.create(conformance))",
    ".withConformance(conformance)",
    ".withLex(Lex.JAVA)",
    ".withIdentifierMaxLength(256)",
]

# RESEARCH_SRC is the session-verified archive extraction root. /tmp is the
# research-time fixture cache; the archives are never shipped.
RESEARCH_SRC = os.environ.get("FLINK_RESEARCH_SRC", "/tmp/flink-research/src")

# Vanilla calcite-core dependency (non-fork) in flink-sql-parser/pom.xml.
CALCITE_CORE_GROUP = "org.apache.calcite"
CALCITE_CORE_ARTIFACT = "calcite-core"

# ---------------------------------------------------------------------------
# 10-03 keyword provenance (RESEARCH §10): committed lists + inlined rows.
# ---------------------------------------------------------------------------

# Repo layout: scripts/extract_flink_lexical.py -> repo root.
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FLINK_FIXTURES_DIR = os.path.join(
    REPO_ROOT, "parity", "fixtures", "flink-lexical"
)
FLINK_MBT = os.path.join(REPO_ROOT, "dialect", "flink.mbt")

# RESEARCH §10 counts: release -> (reserved count, nonreserved count).
KEYWORD_COUNTS = {
    "2.3.0": (443, 334),
    "2.1.3": (430, 324),
    "1.20.5": (412, 323),
}

# RESEARCH §10 release deltas: (newer, older) -> (reserved +N, nonreserved +M).
RELEASE_DELTAS = {
    ("2.3.0", "2.1.3"): (13, 10),
    ("2.1.3", "1.20.5"): (18, 2),
}

# RESEARCH §10 VARIANT template token line (codegen/templates/Parser.jj).
VARIANT_TOKEN_LINES = {"2.3.0": 8640, "2.1.3": 8374}

# Relative paths inside each pinned release tree.
PARSER_TDD_REL = os.path.join(
    "flink-table", "flink-sql-parser", "src", "main", "codegen", "data",
    "Parser.tdd",
)
PARSER_JJ_REL = os.path.join(
    "flink-table", "flink-sql-parser", "src", "main", "codegen", "templates",
    "Parser.jj",
)


def find_calcite_pin(pom_text):
    """Extract the <calcite.version> property value from a flink-table/pom.xml."""
    marker = "<calcite.version>"
    start = pom_text.find(marker)
    if start < 0:
        return None
    value_start = start + len(marker)
    end = pom_text.find("</calcite.version>", value_start)
    if end < 0:
        return None
    return pom_text[value_start:end]


def has_vanilla_calcite_core(pom_text):
    """flink-sql-parser/pom.xml must declare vanilla org.apache.calcite:calcite-core."""
    return (
        CALCITE_CORE_GROUP in pom_text
        and CALCITE_CORE_ARTIFACT in pom_text
    )


def has_parser_config_lines(planner_text):
    """PlannerContext.java must contain every parser-config construction line."""
    return all(line in planner_text for line in PARSER_CONFIG_LINES)


def read_list_words(path):
    """Words from a committed keyword-list file, skipping `#` header lines."""
    words = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            word = line.strip()
            if word and not word.startswith("#"):
                words.append(word)
    return words


def parse_tdd_keywords(tdd_text):
    """Extract (keywords, nonReservedKeywords) word lists from a Parser.tdd."""
    keywords = []
    nonreserved = []
    section = None
    for line in tdd_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("keywords:"):
            section = "keywords"
            continue
        if stripped.startswith("nonReservedKeywords:"):
            section = "nonreserved"
            continue
        if stripped == "]":
            section = None
            continue
        if section is not None and stripped.startswith('"'):
            word = stripped.split('"')[1]
            if section == "keywords":
                keywords.append(word)
            else:
                nonreserved.append(word)
    return keywords, nonreserved


def parse_flink_rows(mbt_text):
    """Extract (word, classification, introduced_profile) from flink_classification_rows."""
    rows = []
    pattern = re.compile(
        r'word:\s*b"([A-Z_]+)"\s*,\s*classification:\s*(\w+)\s*,\s*'
        r'introduced_profile:\s*"([^"]+)"'
    )
    for line in mbt_text.splitlines():
        match = pattern.search(line)
        if match:
            rows.append((match.group(1), match.group(2), match.group(3)))
    return rows


def validate_keyword_lists(problems):
    """Validate the six committed list files: counts, deltas, overlaps, rows."""
    lists = {}
    for release in sorted(KEYWORD_COUNTS):
        for kind in ("reserved", "nonreserved"):
            path = os.path.join(
                FLINK_FIXTURES_DIR, "flink-%s-%s.txt" % (release, kind)
            )
            if not os.path.isfile(path):
                problems.append(
                    "missing committed keyword list: %s" % path
                )
                continue
            words = read_list_words(path)
            lists[(release, kind)] = set(words)
            expected = KEYWORD_COUNTS[release][0 if kind == "reserved" else 1]
            if len(words) != expected:
                problems.append(
                    "flink-%s %s: count %d != RESEARCH S10 expected %d"
                    % (release, kind, len(words), expected)
                )

    # Release-delta report (RESEARCH §10).
    for (newer, older), (reserved_delta, nonreserved_delta) in RELEASE_DELTAS.items():
        if (newer, "reserved") not in lists or (older, "reserved") not in lists:
            continue
        actual_res = len(lists[(newer, "reserved")] - lists[(older, "reserved")])
        if actual_res != reserved_delta:
            problems.append(
                "flink-%s reserved over flink-%s: %d new != RESEARCH S10 expected %d"
                % (newer, older, actual_res, reserved_delta)
            )
        actual_non = len(
            lists[(newer, "nonreserved")] - lists[(older, "nonreserved")]
        )
        if actual_non != nonreserved_delta:
            problems.append(
                "flink-%s nonreserved over flink-%s: %d new != RESEARCH S10 expected %d"
                % (newer, older, actual_non, nonreserved_delta)
            )

    # Overlap report (probe FLINK-01 adjacency): reserved ∩ nonreserved is
    # reported explicitly, never silently resolved by the lookup.
    overlap_report = []
    for release in sorted(KEYWORD_COUNTS):
        if (release, "reserved") in lists and (release, "nonreserved") in lists:
            overlap = sorted(
                lists[(release, "reserved")] & lists[(release, "nonreserved")]
            )
            overlap_report.append(
                "flink-%s reserved∩nonreserved overlap: %s"
                % (release, ", ".join(overlap) if overlap else "(none)")
            )
    return lists, overlap_report


# Calcite base reserved tokens (Pitfall 9, Phase 11): generated Calcite base
# token-list words that ARE reserved in the pinned Parser.jj files but are
# ABSENT from the Parser.tdd keyword extraction (the source of the committed
# reserved/nonreserved lists). scripts/extract_flink_grammar.py validates these
# against the pinned Parser-calcite-{v}.jj token lines directly.
CALCITE_BASE_ONLY_RESERVED = {"MATCH_RECOGNIZE", "MATCH_NUMBER"}


def validate_flink_rows(problems, lists):
    """Validate every inlined flink_classification_rows word against the lists."""
    if not os.path.isfile(FLINK_MBT):
        problems.append("missing dialect/flink.mbt: %s" % FLINK_MBT)
        return 0
    with open(FLINK_MBT, encoding="utf-8") as fh:
        mbt_text = fh.read()
    rows = parse_flink_rows(mbt_text)
    if not rows:
        problems.append("no inlined flink_classification_rows found in dialect/flink.mbt")
        return 0
    for word, classification, profile in rows:
        # profile is "flink-2.3.0" -> release "2.3.0"; unknown profile ids must
        # never match (Pitfall 6).
        if not profile.startswith("flink-"):
            problems.append(
                "flink row %s: bad introduced_profile %r" % (word, profile)
            )
            continue
        release = profile[len("flink-"):]
        if release not in KEYWORD_COUNTS:
            problems.append(
                "flink row %s: unknown introduced_profile %r" % (word, profile)
            )
            continue
        if classification not in ("Reserved", "NonReserved", "Contextual"):
            problems.append(
                "flink row %s: unknown classification %r" % (word, classification)
            )
            continue
        # Calcite base reserved tokens are validated by
        # scripts/extract_flink_grammar.py against the pinned Parser.jj token
        # lines instead of the Parser.tdd-derived lists (Pitfall 9).
        if word in CALCITE_BASE_ONLY_RESERVED:
            if classification != "Reserved":
                problems.append(
                    "flink row %s: Calcite base token must classify Reserved, got %r"
                    % (word, classification)
                )
            continue
        if classification == "Reserved":
            candidates = [lists.get((release, "reserved"), set())]
        elif classification == "NonReserved":
            candidates = [lists.get((release, "nonreserved"), set())]
        else:  # Contextual — word must be present in one of the release lists.
            candidates = [
                lists.get((release, "reserved"), set()),
                lists.get((release, "nonreserved"), set()),
            ]
        if not any(word in candidate for candidate in candidates):
            problems.append(
                "flink row %s (%s, %s): word not present in the flink-%s "
                "%s release list"
                % (
                    word,
                    classification,
                    profile,
                    release,
                    "reserved/nonreserved" if classification == "Contextual"
                    else classification.lower(),
                )
            )
    return len(rows)


def validate_grammar_crosscheck(problems, release_paths, lists):
    """Cross-check the pinned Parser.tdd/Parser.jj against the committed lists."""
    if not release_paths:
        return
    for release in release_paths:
        base = release_paths[release]
        tdd_path = os.path.join(base, PARSER_TDD_REL)
        jj_path = os.path.join(base, PARSER_JJ_REL)
        if not os.path.isfile(tdd_path):
            problems.append("flink-%s: missing Parser.tdd at %s" % (release, tdd_path))
            continue
        if not os.path.isfile(jj_path):
            problems.append("flink-%s: missing Parser.jj at %s" % (release, jj_path))
            continue
        with open(tdd_path, encoding="utf-8") as fh:
            tdd_text = fh.read()
        with open(jj_path, encoding="utf-8") as fh:
            jj_text = fh.read()
        keywords, nonreserved = parse_tdd_keywords(tdd_text)
        # VARIANT is a template-level token, not a Parser.tdd keyword
        # (RESEARCH §10: Parser.jj:8640 for 2.3.0, :8374 for 2.1.3; absent in
        # 1.20.5).
        expected_variant_line = VARIANT_TOKEN_LINES.get(release)
        variant_lines = [
            i
            for i, line in enumerate(jj_text.splitlines(), start=1)
            if 'VARIANT: "VARIANT"' in line
        ]
        if expected_variant_line is not None:
            if not variant_lines:
                problems.append(
                    "flink-%s: VARIANT template token missing from Parser.jj "
                    "(RESEARCH S10 expects line %d)"
                    % (release, expected_variant_line)
                )
            elif expected_variant_line not in variant_lines:
                problems.append(
                    "flink-%s: VARIANT token line %s != RESEARCH S10 line %d"
                    % (release, variant_lines, expected_variant_line)
                )
        else:
            if variant_lines:
                problems.append(
                    "flink-%s: VARIANT template token present but RESEARCH S10 "
                    "says absent for 1.20.5" % release
                )
        # Every Parser.tdd keyword must appear in the committed reserved or
        # nonreserved list (a Flink-specific keyword token is classified).
        for word in keywords:
            if word not in (
                lists[(release, "reserved")] | lists[(release, "nonreserved")]
            ):
                problems.append(
                    "flink-%s: Parser.tdd keyword %s absent from committed lists"
                    % (release, word)
                )
        # Every nonReservedKeyword must appear in the committed nonreserved list.
        for word in nonreserved:
            if word not in lists[(release, "nonreserved")]:
                problems.append(
                    "flink-%s: Parser.tdd nonReservedKeyword %s absent from "
                    "committed nonreserved list" % (release, word)
                )


def parse_manifest(problems):
    """Parse parity/fixtures/flink-lexical/manifest.tsv into {fixture_id: row}.

    Only flink-* rows are returned (the doris-4.x provenance row is a
    docs-grammar record with N/A calcite/sha512 columns and is not part of the
    Calcite-pin surface). TSV header: fixture_id, profile, exact_release,
    calcite_version, parser_config, source_archive_url, sha512, git_tag,
    git_commit.
    """
    manifest_path = os.path.join(FLINK_FIXTURES_DIR, "manifest.tsv")
    if not os.path.isfile(manifest_path):
        problems.append("missing flink-lexical manifest: %s" % manifest_path)
        return {}
    rows = {}
    with open(manifest_path, encoding="utf-8") as fh:
        lines = [line.rstrip("\r\n") for line in fh]
    if not lines:
        problems.append("flink-lexical manifest is empty: %s" % manifest_path)
        return rows
    header = lines[0].split("\t")
    for line in lines[1:]:
        if not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) != len(header):
            problems.append(
                "flink-lexical manifest row has %d fields, expected %d: %s"
                % (len(fields), len(header), line)
            )
            continue
        row = dict(zip(header, fields))
        fixture_id = row.get("fixture_id", "")
        if fixture_id.startswith("flink-"):
            rows[fixture_id] = row
    return rows


def validate_manifest(problems):
    """Re-verify the committed manifest against the pinned releases (MN-03).

    The manifest is the committed provenance record (D-02): url/sha512/tag/
    commit frozen next to the code values. This pass closes the gap where
    nothing mechanically cross-checked the manifest against either the code
    values or the actual archive bytes. It (a) asserts every flink row's
    calcite_version/parser_config equal CALCITE_PINS/PARSER_CONFIG, and
    (b) when the sha512-verified release archive is present under the research
    root, re-hashes the archive and compares it to the manifest sha512 column
    — a tampered manifest fails the gate. Returns the number of flink rows
    whose sha512 was re-verified (0 when no archives are cached).
    """
    rows = parse_manifest(problems)
    if not rows:
        return 0
    verified = 0
    # Archives sit beside the extraction root (research-time fixture cache);
    # also check inside RESEARCH_SRC itself for alternate layouts.
    archive_root = os.path.dirname(RESEARCH_SRC)
    for fixture_id in sorted(rows):
        row = rows[fixture_id]
        release = fixture_id[len("flink-"):]
        expected_pin = CALCITE_PINS.get(release)
        if expected_pin is None:
            problems.append(
                "flink-lexical manifest row %s: unknown release %r"
                % (fixture_id, release)
            )
            continue
        if row.get("calcite_version") != expected_pin:
            problems.append(
                "flink-lexical manifest %s: calcite_version %r != CALCITE_PINS %r"
                % (fixture_id, row.get("calcite_version"), expected_pin)
            )
        if row.get("parser_config") != PARSER_CONFIG:
            problems.append(
                "flink-lexical manifest %s: parser_config %r != PARSER_CONFIG %r"
                % (fixture_id, row.get("parser_config"), PARSER_CONFIG)
            )
        archive_name = os.path.basename(row.get("source_archive_url", ""))
        archive_candidates = []
        if archive_name:
            archive_candidates = [
                os.path.join(archive_root, archive_name),
                os.path.join(RESEARCH_SRC, archive_name),
            ]
        present = [path for path in archive_candidates if os.path.isfile(path)]
        if not present:
            # Research-time fixture only — the archive is never shipped, so a
            # missing archive skips the hash check but keeps the metadata
            # assertions above.
            continue
        archive_path = present[0]
        with open(archive_path, "rb") as fh:
            digest = hashlib.sha512(fh.read()).hexdigest()
        expected_sha = row.get("sha512", "")
        if expected_sha != "N/A" and digest != expected_sha:
            problems.append(
                "flink-lexical manifest %s: sha512 of %s does not match the "
                "manifest column" % (fixture_id, archive_path)
            )
        else:
            verified += 1
    return verified


# ---------------------------------------------------------------------------
# Phase 12 (12-01) extension: flink-lexical fixture expansion validation.
# Parses the flink_lexical_test.mbt fixture array (13 entries), byte-compares
# each against the committed parity/fixtures/flink/**/*.sql file, and
# validates the unified manifest's lexical rows: 6-category enum, expected
# status, token-source column, fixture_sha256.
# ---------------------------------------------------------------------------

# Unified 19-column manifest (Phase 12, D-01).
UNIFIED_MANIFEST = os.path.join(REPO_ROOT, "parity", "fixtures", "flink", "manifest.tsv")
FLINK_SQL_ROOT = os.path.join(REPO_ROOT, "parity", "fixtures", "flink")
LEXICAL_TEST_MBT = os.path.join(REPO_ROOT, "parity", "flink_lexical_test.mbt")

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

# Expected lexical 6-category mapping: (fixture_id, dialect, profile) -> category.
LEXICAL_CATEGORY_MAP = {
    ("hash-comment", "flink", "flink-2.3.0"): "negative",
    ("hash-comment", "doris", "4.x"): "negative",
    ("double-quote", "flink", "flink-2.3.0"): "negative",
    ("double-quote", "doris", "4.x"): "positive",
    ("slash-comment", "flink", "flink-2.3.0"): "positive",
    ("slash-comment", "doris", "4.x"): "negative",
    ("e-literal", "flink", "flink-2.3.0"): "positive",
    ("e-literal", "flink", "flink-2.1.3"): "positive",
    ("e-literal", "flink", "flink-1.20.5"): "negative",
    ("e-literal", "doris", "4.x"): "negative",
    ("backtick-escape", "flink", "flink-2.3.0"): "positive",
    ("backtick-escape", "doris", "4.x"): "positive",
    ("unknown-profile", "flink", "4.x"): "negative",
}

# Lexical rows must carry a token-source reference in grammar_path.
TOKEN_SOURCE_PREFIXES = (
    "Parser-calcite-",
    "Doris ",
    "FATHOM-",
    "absent in Calcite ",
)


def decode_lexical_bytes(literal):
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


def parse_embedded_lexical_fixtures(problems):
    """Parse the flink_lexical_test.mbt fixture array -> {(id,dialect,profile): bytes}."""
    if not os.path.isfile(LEXICAL_TEST_MBT):
        problems.append("missing parity/flink_lexical_test.mbt: %s" % LEXICAL_TEST_MBT)
        return {}
    with open(LEXICAL_TEST_MBT, encoding="utf-8") as fh:
        text = fh.read()
    pattern = re.compile(
        r'fixture_id:\s*"([^"]+)"\s*,\s*'
        r'dialect:\s*"([^"]+)"\s*,\s*'
        r'profile:\s*"([^"]+)"\s*,\s*'
        r'(?://[^\n]*\n\s*)*'
        r'raw:\s*b"((?:[^"\\]|\\.)*)"',
        re.S,
    )
    fixtures = {}
    for m in pattern.finditer(text):
        fixture_id, dialect, profile, raw_literal = m.groups()
        raw = decode_lexical_bytes(raw_literal)
        fixtures[(fixture_id, dialect, profile)] = raw
    return fixtures


def sql_dir(profile):
    return "doris-4.x" if profile == "4.x" else profile


def validate_embedded_lexical_bytes(problems, fixtures):
    verified = 0
    for (fixture_id, dialect, profile), raw in sorted(fixtures.items()):
        fid = "flink-lexical." + fixture_id
        sql_path = os.path.join(FLINK_SQL_ROOT, sql_dir(profile), fid + ".sql")
        if not os.path.isfile(sql_path):
            problems.append(
                "embedded-raw %s: missing committed .sql file %s" % (fid, sql_path)
            )
            continue
        with open(sql_path, "rb") as fh:
            on_disk = fh.read()
        if on_disk != raw:
            problems.append(
                "embedded-raw %s: committed .sql bytes do not match the "
                "flink_lexical_test.mbt b\"...\" literal (D-08)" % fid
            )
            continue
        verified += 1
    return verified


def validate_unified_lexical_rows(problems):
    """Validate the unified manifest's 13 flink-lexical rows."""
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
    for line in lines[1:]:
        if not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) != len(header):
            continue
        rows.append(dict(zip(header, fields)))
    lexical_rows = [r for r in rows if r["fixture_id"].startswith("flink-lexical.")]
    if len(lexical_rows) != 13:
        problems.append(
            "unified manifest has %d flink-lexical rows, expected 13"
            % len(lexical_rows)
        )
    verified = 0
    for row in lexical_rows:
        fid = row["fixture_id"]
        fixture_id = fid[len("flink-lexical."):]
        key = (fixture_id, row["dialect"], row["profile"])
        expected_category = LEXICAL_CATEGORY_MAP.get(key)
        if expected_category is None:
            problems.append(
                "%s: (fixture_id, dialect, profile) %r not in the expected "
                "13-row lexical map" % (fid, key)
            )
            continue
        category = row["category"]
        if category != expected_category:
            problems.append(
                "%s: category %r != expected lexical category %r"
                % (fid, category, expected_category)
            )
        if row["expected_status"] != EXPECTED_STATUS.get(category, "?"):
            problems.append(
                "%s: expected_status %r inconsistent with category %r"
                % (fid, row["expected_status"], category)
            )
        grammar_path = row.get("grammar_path", "")
        if not grammar_path.startswith(TOKEN_SOURCE_PREFIXES):
            problems.append(
                "%s: grammar_path %r does not carry a token-source reference "
                "(Parser-calcite / Doris / FATHOM / absent-in-Calcite)" % (fid, grammar_path)
            )
        sql_path = os.path.join(FLINK_SQL_ROOT, sql_dir(row["profile"]), fid + ".sql")
        if os.path.isfile(sql_path):
            with open(sql_path, "rb") as fh:
                digest = hashlib.sha256(fh.read()).hexdigest()
            if digest != row["fixture_sha256"]:
                problems.append(
                    "%s: fixture_sha256 drift (%s != %s)"
                    % (fid, digest[:16], row["fixture_sha256"][:16])
                )
        verified += 1
    return verified


def main(argv):
    problems = []
    release_paths = {}
    for release in CALCITE_PINS:
        base = os.path.join(RESEARCH_SRC, "flink-" + release)
        if not os.path.isdir(base):
            problems.append(
                "missing pinned release source tree for flink-%s: %s" % (release, base)
            )
            continue
        release_paths[release] = base

    # ---- 10-03 keyword-list validation (committed files + inlined rows) ----
    lists, overlap_report = validate_keyword_lists(problems)
    for line in overlap_report:
        print(line)
    row_count = validate_flink_rows(problems, lists)
    # ---- MN-03: manifest provenance re-verification ----
    manifest_verified = validate_manifest(problems)
    # ---- Phase 12: embedded-raw + unified lexical rows ----
    fixtures = parse_embedded_lexical_fixtures(problems)
    embedded_verified = validate_embedded_lexical_bytes(problems, fixtures)
    unified_lexical_verified = validate_unified_lexical_rows(problems)

    # ---- pinned-archive validation (pins, parser config, grammar cross-check)
    verified_pins = 0
    if not release_paths:
        if not problems:
            problems.append(
                "no pinned release source trees available under %s" % RESEARCH_SRC
            )
    else:
        for release, expected_pin in CALCITE_PINS.items():
            base = release_paths[release]
            table_pom = os.path.join(base, "flink-table", "pom.xml")
            parser_pom = os.path.join(
                base, "flink-table", "flink-sql-parser", "pom.xml"
            )
            planner_java = os.path.join(
                base,
                "flink-table",
                "flink-table-planner",
                "src",
                "main",
                "java",
                "org",
                "apache",
                "flink",
                "table",
                "planner",
                "delegation",
                "PlannerContext.java",
            )
            for label, path in [
                ("flink-table/pom.xml", table_pom),
                ("flink-sql-parser/pom.xml", parser_pom),
                ("PlannerContext.java", planner_java),
            ]:
                if not os.path.isfile(path):
                    problems.append(
                        "flink-%s: missing %s at %s" % (release, label, path)
                    )
            if problems:
                continue

            with open(table_pom, encoding="utf-8") as fh:
                table_text = fh.read()
            with open(parser_pom, encoding="utf-8") as fh:
                parser_text = fh.read()
            with open(planner_java, encoding="utf-8") as fh:
                planner_text = fh.read()

            actual_pin = find_calcite_pin(table_text)
            if actual_pin != expected_pin:
                problems.append(
                    "flink-%s: calcite.version pin mismatch: expected %s, got %s"
                    % (release, expected_pin, actual_pin)
                )
            else:
                verified_pins += 1

            if not has_vanilla_calcite_core(parser_text):
                problems.append(
                    "flink-%s: flink-sql-parser/pom.xml lacks vanilla calcite-core dependency"
                    % release
                )

            if not has_parser_config_lines(planner_text):
                problems.append(
                    "flink-%s: PlannerContext.java parser-config construction differs from RESEARCH S8"
                    % release
                )
        validate_grammar_crosscheck(problems, release_paths, lists)

    if problems:
        for problem in problems:
            print("error: " + problem, file=sys.stderr)
        return 1

    counts_summary = ", ".join(
        "%s=%d/%d" % (release, KEYWORD_COUNTS[release][0], KEYWORD_COUNTS[release][1])
        for release in sorted(KEYWORD_COUNTS)
    )
    print(
        "ok: %d calcite pins verified against pinned release POMs (%s), "
        "parser config verified (%s), keyword counts verified (%s), "
        "%d inlined flink rows present in the matching release lists, "
        "%d flink manifest rows re-verified against manifest.tsv, "
        "%d embedded b\"...\" literals byte-match committed .sql files "
        "(embedded-raw provenance, D-08), %d unified flink-lexical rows pass "
        "6-category + token-source + fixture_sha256"
        % (
            verified_pins,
            ", ".join("%s=%s" % (k, v) for k, v in sorted(CALCITE_PINS.items())),
            PARSER_CONFIG,
            counts_summary,
            row_count,
            manifest_verified,
            embedded_verified,
            unified_lexical_verified,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
