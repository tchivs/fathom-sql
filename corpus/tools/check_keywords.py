#!/usr/bin/env python3
"""D-16 keyword classification TSV integrity check (Python stdlib only).

Usage: python3 corpus/tools/check_keywords.py corpus/keywords.tsv

Validates the auditable keyword report that mirrors the runtime classification
table in token/token.mbt:
  * exact header (word, classification, introduced_profile, source)
  * exactly four tab-delimited fields per row
  * no duplicate words (case-insensitive)
  * classification in {reserved, non-reserved, contextual}
  * introduced_profile in {2.1, 3.x, 4.x}
  * source is a docs URL
  * full coverage of the production-keyword inventory the DML/DDL parsers
    consume (extracted from the 02-01 DML and 02-02 DDL plan actions)

Exits non-zero when any rule fails so the audit artifact cannot drift from the
runtime table or lose production words (D-13/D-16, T-02-21..T-02-23).
"""

import sys

HEADER = ["word", "classification", "introduced_profile", "source"]
VALID_CLASSIFICATIONS = {"reserved", "non-reserved", "contextual"}
VALID_PROFILES = {"2.1", "3.x", "4.x"}

# Production-word inventory extracted from the 02-01 (DML) and 02-02 (DDL)
# parser actions. Every word the DML/DDL productions consume must have a row.
PRODUCTION_WORDS = {
    "INSERT", "UPDATE", "DELETE", "MERGE", "OVERWRITE", "VALUES", "INTO",
    "SET", "WHEN", "MATCHED", "USING", "THEN", "LABEL", "DEFAULT",
    "AUTO_INCREMENT", "CURRENT_TIMESTAMP", "GENERATED", "ALWAYS",
    "CREATE", "TABLE", "VIEW", "INDEX", "MATERIALIZED", "TEMPORARY",
    "EXTERNAL", "IF", "NOT", "EXISTS", "ENGINE", "KEY", "DUPLICATE",
    "UNIQUE", "AGGREGATE", "DISTRIBUTED", "HASH", "RANDOM", "BUCKETS",
    "PARTITION", "PARTITIONS", "AUTO", "RANGE", "LIST", "LESS", "THAN",
    "ROLLUP", "PROPERTIES", "COMMENT", "LIKE", "AS", "ORDER", "BY",
    # Async materialized view clause words (02-04 A2 closure).
    "ASYNC", "BUILD", "REFRESH", "IMMEDIATE", "DEFERRED", "COMPLETE",
    "MANUAL", "SCHEDULE", "EVERY", "STARTS", "COMMIT",
}


def main(argv):
    if len(argv) != 2:
        print("usage: check_keywords.py keywords.tsv", file=sys.stderr)
        return 2
    path = argv[1]
    try:
        with open(path, encoding="utf-8") as fh:
            lines = [line.rstrip("\n") for line in fh]
    except OSError as exc:
        print("error: cannot read %s: %s" % (path, exc), file=sys.stderr)
        return 1
    if not lines:
        print("error: empty keyword file", file=sys.stderr)
        return 1
    header = lines[0].split("\t")
    if header != HEADER:
        print("error: header mismatch: %r != %r" % (header, HEADER), file=sys.stderr)
        return 1
    problems = []
    seen = {}
    words = set()
    for lineno, line in enumerate(lines[1:], start=2):
        if line == "":
            problems.append("line %d: empty row" % lineno)
            continue
        fields = line.split("\t")
        if len(fields) != 4:
            problems.append(
                "line %d: expected 4 tab-delimited fields, got %d" % (lineno, len(fields))
            )
            continue
        word, classification, introduced_profile, source = fields
        key = word.upper()
        if key in seen:
            problems.append(
                "line %d: duplicate word %r (first at line %d)" % (lineno, word, seen[key])
            )
        seen[key] = lineno
        if not word:
            problems.append("line %d: empty word" % lineno)
        if classification not in VALID_CLASSIFICATIONS:
            problems.append("line %d: invalid classification %r" % (lineno, classification))
        if introduced_profile not in VALID_PROFILES:
            problems.append(
                "line %d: invalid introduced_profile %r" % (lineno, introduced_profile)
            )
        if not source.startswith("http"):
            problems.append("line %d: source must be a docs URL, got %r" % (lineno, source))
        words.add(key)
    missing = sorted(PRODUCTION_WORDS - words)
    if missing:
        problems.append("missing production words: %s" % ", ".join(missing))
    if problems:
        for problem in problems:
            print("error: " + problem, file=sys.stderr)
        return 1
    print(
        "ok: %d keyword rows, %d production words covered"
        % (len(seen), len(PRODUCTION_WORDS))
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
