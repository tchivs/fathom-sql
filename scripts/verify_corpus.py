#!/usr/bin/env python3
"""Offline Flink corpus manifest/hash verifier (Phase 12, D-06; stdlib only).

Single-entry offline gate: `python3 scripts/verify_corpus.py --check`.

Pure stdlib, pure local — no network, no Doris FE, no Flink cluster, no DB.
Read-only over pinned artifacts: an interrupted or concurrent run leaves no
partial state (the script never writes). Exit 0 only when all of the
following hold:

  1. Manifest structure: the 19-column header matches exactly; every row has
     the same field count; fixture_id uses a whitelisted prefix
     (flink-grammar. / flink-lexical.) and carries no path separator or
     dot-dot (T-12-01-03); no duplicate (fixture_id, dialect, profile).
  2. Field consistency: every flink-release row's calcite_version/parser_config
     match the in-repo PINS table (dialect/flink.mbt FlinkProfileMetadata);
     doris control rows and the unknown-profile slot are exempt (N/A).
  3. Category enum: category is exactly one of the 6 values
     positive | negative | recovery | known-limitation |
     catalog-prerequisite | planner-prerequisite (D-01, Pitfall 2).
  4. expected_status consistency: positive -> valid, negative -> error,
     recovery -> recovered, known-limitation/catalog-prerequisite/
     planner-prerequisite -> valid (Pitfall 7).
  5. Hash:
     a. fixture_sha256: sha256 of the committed
        parity/fixtures/flink/{dir}/{fixture_id}.sql bytes must match the
        manifest column (resident CI-checkable hash — D-06, Pitfall 3).
     b. archive sha512: when /tmp/flink-research/{release}-src.tgz is present,
        its sha512 must match the manifest sha512 column; when absent the row
        is reported as archive-not-present (research fixture) and is NOT a
        failure — no hash is ever fabricated (Pitfall 3).
  6. Snapshot completeness: every row has both strict and editor snapshots in
     parity-tests/__snapshot__ with the dialect-correct segment (flink rows
     {fixture_id}.{profile}.{mode}.json; doris rows
     {fixture_id}.doris-{profile}.{mode}.json; unknown-profile slot
     {fixture_id}.flink-4x.{mode}.json).
  7. Non-empty guard: manifest has at least 1 row; coverage file has at least
     1 data row (Pitfall 8).

Usage:
  python3 scripts/verify_corpus.py --check

Exit 0 with a single "ok:" line; exit 1 with "error:" lines otherwise.
"""

import argparse
import csv
import hashlib
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "parity" / "fixtures" / "flink" / "manifest.tsv"
FLINK_FIXTURES = ROOT / "parity" / "fixtures" / "flink"
SNAPSHOT_DIR = ROOT / "parity-tests" / "__snapshot__"
FLINK_COVERAGE = ROOT / "corpus" / "flink-coverage.tsv"

# Research-time release archive cache (never shipped / never a CI dependency).
RESEARCH_SRC = pathlib.Path(os.environ.get("FLINK_RESEARCH_SRC", "/tmp/flink-research"))

# Unified 19-column header (D-01 / RESEARCH S5.1, planner-定稿).
MANIFEST_HEADER = [
    "fixture_id",
    "dialect",
    "profile",
    "exact_release",
    "calcite_version",
    "parser_config",
    "source_archive_url",
    "sha512",
    "git_tag",
    "git_commit",
    "source_url",
    "heading",
    "retrieval_date",
    "category",
    "expected_status",
    "fixture_sha256",
    "grammar_path",
    "line_range",
    "mode",
]

# 6-category enum (D-01). generic-acceptance is never engine-support.
CATEGORIES = {
    "positive",
    "negative",
    "recovery",
    "known-limitation",
    "catalog-prerequisite",
    "planner-prerequisite",
}

# expected_status <-> category consistency (RESEARCH S5.3).
EXPECTED_STATUS = {
    "positive": "valid",
    "negative": "error",
    "recovery": "recovered",
    "known-limitation": "valid",
    "catalog-prerequisite": "valid",
    "planner-prerequisite": "valid",
}

# Mirrors dialect/flink.mbt FlinkProfileMetadata (verified in-repo).
PINS = {
    "flink-2.3.0": (
        "1.36.0",
        "Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT",
    ),
    "flink-2.1.3": (
        "1.34.0",
        "Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT",
    ),
    "flink-1.20.5": (
        "1.32.0",
        "Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT",
    ),
}

# fixture_id whitelist prefixes (T-12-01-03 path traversal).
FIXTURE_PREFIXES = ("flink-grammar.", "flink-lexical.")


def sha256_file(path):
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def sha512_file(path):
    h = hashlib.sha512()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def sql_dir(profile):
    """Directory for a fixture's .sql file: profile 4.x lives in doris-4.x."""
    return "doris-4.x" if profile == "4.x" else profile


def snapshot_segment(row):
    """Dialect-correct snapshot filename segment (mirrors the test file)."""
    if row["dialect"] == "doris":
        return "doris-" + row["profile"]
    if row["profile"].startswith("flink-"):
        return row["profile"]
    # unknown-profile slot: flink dialect, Doris-shaped 4.x profile -> flink-4x.
    return "flink-" + row["profile"].replace(".", "")


def validate_header(lines, problems):
    header = lines[0].split("\t")
    if header != MANIFEST_HEADER:
        problems.append(
            "manifest header mismatch: got %d columns %r, expected %d %r"
            % (len(header), header, len(MANIFEST_HEADER), MANIFEST_HEADER)
        )
        return False
    return True


def validate_row_shape(lines, problems):
    ncols = len(MANIFEST_HEADER)
    bad = 0
    for lineno, line in enumerate(lines[1:], start=2):
        if not line.strip():
            continue
        if len(line.split("\t")) != ncols:
            bad += 1
            if bad <= 10:
                problems.append(
                    "manifest line %d: %d fields, expected %d"
                    % (lineno, len(line.split("\t")), ncols)
                )
    return bad


def validate_fixture_id(fixture_id, problems):
    if "/" in fixture_id or "\\" in fixture_id or ".." in fixture_id:
        problems.append("fixture_id %r contains a path separator or dot-dot" % fixture_id)
        return False
    if not fixture_id.startswith(FIXTURE_PREFIXES):
        problems.append("fixture_id %r does not start with a whitelisted prefix" % fixture_id)
        return False
    return True


def check_archive_sha512(row, problems, verified_refs):
    """Present-verify / absent-archive-not-present for the release archive.

    The archive is a research-time fixture: when present under the research
    root its sha512 must match the manifest column; when absent the row is
    reported as archive-not-present and is NOT a failure (Pitfall 3 — never
    fabricate a hash).
    """
    sha = row.get("sha512", "")
    url = row.get("source_archive_url", "")
    if sha == "N/A" or not url or url == "N/A":
        return
    archive_name = os.path.basename(url)
    if not archive_name:
        return
    candidates = [
        RESEARCH_SRC / archive_name,
        RESEARCH_SRC / "src" / archive_name,
    ]
    present = [p for p in candidates if p.is_file()]
    if not present:
        # Not a failure — the archive is a research fixture, not shipped.
        return
    digest = sha512_file(present[0])
    if digest != sha:
        problems.append(
            "%s: archive %s sha512 %s does not match manifest sha512 column"
            % (row["fixture_id"], present[0], digest[:16])
        )
    else:
        verified_refs[0] += 1


def validate_rows(rows, problems):
    seen = set()
    row_count = 0
    for row in rows:
        row_count += 1
        fixture_id = row.get("fixture_id", "")
        dialect = row.get("dialect", "")
        profile = row.get("profile", "")
        key = (fixture_id, dialect, profile)
        if key in seen:
            problems.append("duplicate (fixture_id, dialect, profile): %r" % (key,))
        seen.add(key)
        validate_fixture_id(fixture_id, problems)

        category = row.get("category", "")
        if category not in CATEGORIES:
            problems.append(
                "%s: category %r is not one of %s"
                % (fixture_id, category, sorted(CATEGORIES))
            )

        expected = EXPECTED_STATUS.get(category)
        if expected is not None and row.get("expected_status", "") != expected:
            problems.append(
                "%s: expected_status %r inconsistent with category %r (expected %r)"
                % (fixture_id, row.get("expected_status", ""), category, expected)
            )

        # Field consistency vs PINS (doris control rows / unknown-profile exempt).
        pin = PINS.get(profile)
        if pin is not None:
            calcite, cfg = pin
            if row.get("calcite_version", "") != calcite:
                problems.append(
                    "%s: calcite_version %r != PINS %r"
                    % (fixture_id, row.get("calcite_version", ""), calcite)
                )
            if row.get("parser_config", "") != cfg:
                problems.append(
                    "%s: parser_config drift vs dialect/flink.mbt" % fixture_id
                )
        else:
            # Not a pinned flink release: doris rows and the unknown-profile
            # slot must declare N/A calcite/config.
            if row.get("calcite_version", "") != "N/A":
                problems.append(
                    "%s: profile %r not in PINS but calcite_version is not N/A"
                    % (fixture_id, profile)
                )

        # fixture_sha256 over the committed .sql bytes.
        sql_path = FLINK_FIXTURES / sql_dir(profile) / (fixture_id + ".sql")
        if not sql_path.is_file():
            problems.append("%s: missing fixture sql %s" % (fixture_id, sql_path))
        else:
            actual = sha256_file(sql_path)
            if actual != row.get("fixture_sha256", ""):
                problems.append(
                    "%s: fixture_sha256 mismatch (file %s != manifest %s)"
                    % (fixture_id, actual[:16], row.get("fixture_sha256", "")[:16])
                )

        # Archive sha512 present-verify / absent-archive-not-present.
        check_archive_sha512(row, problems, _sha_verified)

        # Snapshot completeness: strict + editor with dialect-correct segment.
        seg = snapshot_segment(row)
        for mode in ("strict", "editor"):
            snap = SNAPSHOT_DIR / ("%s.%s.%s.json" % (fixture_id, seg, mode))
            if not snap.is_file():
                problems.append(
                    "%s: missing snapshot %s" % (fixture_id, snap.name)
                )
    return row_count


_sha_verified = [0]


def main(argv):
    problems = []

    if not MANIFEST.is_file():
        print("error: missing manifest %s" % MANIFEST, file=sys.stderr)
        return 1
    lines = [line.rstrip("\r\n") for line in MANIFEST.open(encoding="utf-8")]
    if not lines:
        problems.append("manifest is empty (non-empty guard, Pitfall 8)")
    else:
        if validate_header(lines, problems):
            validate_row_shape(lines, problems)
        rows = list(csv.DictReader(lines, delimiter="\t"))
        # DictReader consumes the header; re-derive rows from the header line.
        if rows:
            validate_rows(rows, problems)

    # Non-empty guard: at least 1 data row (header alone must fail).
    data_lines = [l for l in lines[1:] if l.strip()] if len(lines) > 1 else []
    if not data_lines:
        problems.append("manifest has no data rows (non-empty guard, Pitfall 8)")

    # Coverage file non-empty guard.
    if not FLINK_COVERAGE.is_file():
        problems.append("missing corpus/flink-coverage.tsv")
    else:
        cov_lines = [l for l in FLINK_COVERAGE.open(encoding="utf-8") if l.strip()]
        if len(cov_lines) < 2:
            problems.append("corpus/flink-coverage.tsv has no data rows (non-empty guard)")

    if problems:
        for p in problems:
            print("error: " + p, file=sys.stderr)
        return 1

    print(
        "ok: %d flink corpus rows verified offline (header, pins, 6-category, "
        "expected-status, fixture sha256, snapshot completeness); %d archive "
        "sha512 re-verified"
        % (len(data_lines), _sha_verified[0])
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
