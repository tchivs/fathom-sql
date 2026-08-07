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

Usage: python3 scripts/extract_flink_lexical.py
Exit 0 with an "ok:" line when every pin matches; exit 1 with "error:" lines
otherwise (a deliberately wrong pin must make it exit 1).
"""

import os
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

    if problems:
        for problem in problems:
            print("error: " + problem, file=sys.stderr)
        return 1

    verified_pins = 0
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

    if problems:
        for problem in problems:
            print("error: " + problem, file=sys.stderr)
        return 1

    print(
        "ok: %d calcite pins verified against pinned release POMs (%s), parser config verified (%s)"
        % (
            verified_pins,
            ", ".join("%s=%s" % (k, v) for k, v in sorted(CALCITE_PINS.items())),
            PARSER_CONFIG,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
