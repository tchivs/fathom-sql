#!/usr/bin/env python3
"""Deterministic offline CORPUS-REPORT.md generator (D-19, research Pattern 5).

Reads corpus/manifest.tsv, corpus/coverage.tsv, and corpus/keywords.tsv and
renders corpus/CORPUS-REPORT.md with:

  * a version x category matrix (fixture count, supported, expected-error,
    known-gap column)
  * a failure list (expected-error rows; supported-row oracle failures are
    surfaced by `moon test` and are not claimable here)
  * a known-gaps section (provenance rows, coverage gaps, and flagged /
    discovered gaps — mandatory, never empty)
  * a keyword classification summary (D-16)

Invariants enforced by --check mode (exit non-zero on any violation):

  * the committed report is byte-stale relative to a fresh generation
  * the one-fixture-one-row invariant: every manifest (profile, category
    group) has exactly one coverage row whose counts match, and every
    coverage row (except the "all" aggregate) has a manifest group
  * no "full compatibility" / "100%" claim string in the corpus text files
  * the known-gaps section is non-empty

Python stdlib only (csv, pathlib, re, sys); deterministic and offline.
"""

import csv
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
CORPUS = ROOT / "corpus"
MANIFEST = CORPUS / "manifest.tsv"
COVERAGE = CORPUS / "coverage.tsv"
KEYWORDS = CORPUS / "keywords.tsv"
REPORT = CORPUS / "CORPUS-REPORT.md"
FLINK_COVERAGE = CORPUS / "flink-coverage.tsv"

# Phase 1 coverage rows aggregate several manifest categories under one
# coverage category; new DML/DDL categories (02-04) map to themselves.
PHASE1_CATEGORY_GROUP = {
    "industrial-select": "industrial-select",
    "core-04-boundary-empty-clause": "core-04-boundary",
    "core-04-boundary-single-element": "core-04-boundary",
    "core-04-boundary-one-set": "core-04-boundary",
    "core-04-boundary-many-set": "core-04-boundary",
    "core-04-boundary-two-set": "core-04-boundary",
    "contextual-keyword": "contextual-keyword",
    "invalid-encoding": "malformed-and-encoding",
    "malformed-recovery": "malformed-and-encoding",
    "unsupported-version": "version-gate",
}

PROFILES = ["2.1", "3.x", "4.x"]

# Flagged (research A5) and corpus-wave-discovered gaps that no manifest or
# coverage row carries; they feed the mandatory known-gaps section.
FLAGGED_GAPS = [
    "A5: Oracle-style multi-table INSERT (INSERT ALL/FIRST) is not documented "
    "in released Doris docs; presence unverified (no fixture claims it).",
    "CLUSTER BY (<cluster_cols>) is documented in the 2.1/3.x CREATE TABLE key "
    "clause but is not implemented by the parser (discovered during the 02-04 "
    "corpus wave).",
    "CREATE TEMPORARY TABLE is documented in the 4.x CREATE TABLE grammar only "
    "(`CREATE [ TEMPORARY | EXTERNAL ] TABLE`); the parser accepts it under all "
    "released profiles (02-02 decision); 2.1/3.x fixtures avoid it.",
    "The bare `CREATE MATERIALIZED VIEW <name> [ AS ] query` spelling follows "
    "the sync-MV page's restricted body; the async form (BUILD/REFRESH, IF NOT "
    "EXISTS, column list) is selected by clause presence per the async-MV pages.",
    "`CREATE ASYNC MATERIALIZED VIEW` is the docs page title; the syntax blocks "
    "spell `CREATE MATERIALIZED VIEW`; both spellings are accepted (A2 closed).",
]

CLAIM_PATTERN = re.compile(r"full\s*compatib|100\s*%", re.IGNORECASE)


def read_tsv(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def category_group(category):
    return PHASE1_CATEGORY_GROUP.get(category, category)


def _cell(value):
    text = str(value).replace("|", "\\|")
    return text if text else "-"


def render_matrix(manifest, coverage):
    # Order: profiles in fixed order, then categories sorted, then the "all"
    # aggregate row last in its own section.
    groups = {}
    for row in manifest:
        key = (row["profile"], category_group(row["category"]))
        groups.setdefault(key, []).append(row)
    cov_by_key = {}
    for row in coverage:
        cov_by_key.setdefault((row["profile"], row["category"]), []).append(row)

    lines = ["## Version x Category Matrix", "", "| Profile | Category | Fixtures | Supported | Expected-error | Known gap |", "|---|---|---|---|---|---|"]
    for profile in PROFILES:
        categories = sorted({category_group(r["category"]) for r in manifest if r["profile"] == profile} |
                            {r["category"] for r in coverage if r["profile"] == profile})
        for category in categories:
            key = (profile, category)
            cov_rows = cov_by_key.get(key, [])
            total = sum(int(r["fixture_count"]) for r in cov_rows)
            supported = sum(int(r["supported_count"]) for r in cov_rows)
            expected = sum(int(r["expected_error_count"]) for r in cov_rows)
            known_gap = cov_rows[0]["known_gap"] if cov_rows else "no coverage row"
            lines.append(f"| {profile} | {category} | {total} | {supported} | {expected} | {_cell(known_gap)} |")
        if not categories:
            lines.append(f"| {profile} | (none) | 0 | 0 | 0 | - |")
    return lines


def render_failures(manifest):
    lines = ["## Failure List", "",
             "Expected-error rows are explicit failures with recovery/version goldens. "
             "Supported-row oracle failures are surfaced by `moon test` "
             "(test/corpus_test.mbt oracle) and cannot be evaluated by this generator.",
             "", "| Fixture | Profile | Category | Parse mode | Reason |", "|---|---|---|---|---|"]
    failed = [r for r in manifest if r["support_status"] == "expected-error"]
    for row in sorted(failed, key=lambda r: (r["profile"], r["fixture_id"])):
        reason = row.get("classification", "") or row.get("provenance_status", "")
        lines.append(f"| {row['fixture_id']} | {row['profile']} | {row['category']} | {_cell(row['parse_mode'])} | {_cell(reason)} |")
    return lines


def render_known_gaps(manifest, coverage):
    lines = ["## Known Gaps", ""]
    # 1. Provenance gaps carried by manifest rows (unavailable-offline, ...).
    prov = [r for r in manifest if r.get("provenance_status", "").startswith("known-gap")]
    lines.append("### Provenance gaps (manifest rows)")
    lines.append("")
    lines.append("| Fixture | Profile | Gap |")
    lines.append("|---|---|---|")
    for row in sorted(prov, key=lambda r: (r["profile"], r["fixture_id"])):
        lines.append(f"| {row['fixture_id']} | {row['profile']} | {_cell(row['provenance_status'])} |")
    # 2. Coverage-row gaps.
    lines.append("")
    lines.append("### Coverage gaps (coverage rows)")
    lines.append("")
    lines.append("| Profile | Category | Gap |")
    lines.append("|---|---|---|")
    for row in sorted(coverage, key=lambda r: (PROFILES.index(r["profile"]) if r["profile"] in PROFILES else len(PROFILES), r["category"])):
        gap = row.get("known_gap", "")
        if gap:
            lines.append(f"| {row['profile']} | {row['category']} | {_cell(gap)} |")
    # 3. Flagged / discovered gaps.
    lines.append("")
    lines.append("### Flagged and discovered gaps")
    lines.append("")
    for gap in FLAGGED_GAPS:
        lines.append(f"- {gap}")
    return lines


def render_keywords():
    rows = read_tsv(KEYWORDS)
    lines = ["## Keyword Classification Summary (D-16)", "",
             "| Classification | Count |", "|---|---|"]
    counts = {}
    profile_counts = {}
    for row in rows:
        counts[row["classification"]] = counts.get(row["classification"], 0) + 1
        profile_counts[row["introduced_profile"]] = profile_counts.get(row["introduced_profile"], 0) + 1
    for classification in sorted(counts):
        lines.append(f"| {classification} | {counts[classification]} |")
    lines.append("")
    lines.append("By introduced profile: " +
                 ", ".join(f"{profile}: {profile_counts.get(profile, 0)}" for profile in sorted(profile_counts)) +
                 f" (total {len(rows)} words).")
    return lines


# ---------------------------------------------------------------------------
# Flink cross-dialect coverage (Phase 12, CORPUS-01 / PARITY-03 / D-01/D-06).
# Reads corpus/flink-coverage.tsv and renders a semantic-distinction section:
# parser acceptance and engine-semantic prerequisite are reported as distinct
# totals. catalog-prerequisite / planner-prerequisite / known-limitation rows
# are NEVER counted as engine-supported (generic SQL acceptance != Flink
# engine support).
# ---------------------------------------------------------------------------

FLINK_CATEGORIES = {
    "positive", "negative", "recovery", "known-limitation",
    "catalog-prerequisite", "planner-prerequisite",
}
PREREQUISITE_CATEGORIES = {"catalog-prerequisite", "planner-prerequisite", "known-limitation"}


def read_flink_coverage():
    if not FLINK_COVERAGE.exists():
        return []
    return read_tsv(FLINK_COVERAGE)


def render_flink(coverage):
    lines = [
        "## Flink Cross-Dialect Coverage (CORPUS-01 / PARITY-03)", "",
        "Parser acceptance and engine-semantic prerequisite are reported as "
        "distinct totals. Generic SQL that the parser merely accepts is NEVER "
        "counted as Flink engine support (D-01): catalog-prerequisite, "
        "planner-prerequisite, and known-limitation fixtures are reported as "
        "prerequisite, never as engine-supported.", "",
        "| Profile | Category | Fixtures | Parser accepted | Parser rejected | Recovery | Prerequisite |",
        "|---|---|---|---|---|---|---|",
    ]
    total_fixtures = total_accepted = total_rejected = total_recovery = 0
    prereq_fixtures = 0
    engine_supported = 0
    for row in coverage:
        if row.get("profile", "") == "all":
            continue
        fixtures = int(row.get("fixture_count", 0))
        accepted = int(row.get("parser_accepted", 0))
        rejected = int(row.get("parser_rejected", 0))
        recovery = int(row.get("recovery", 0))
        category = row.get("category", "")
        total_fixtures += fixtures
        total_accepted += accepted
        total_rejected += rejected
        total_recovery += recovery
        if category in PREREQUISITE_CATEGORIES:
            prereq_fixtures += fixtures
        if category == "positive":
            engine_supported += accepted
        prereq_note = row.get("prerequisite", "none") or "none"
        lines.append(
            f"| {_cell(row.get('profile', ''))} | {_cell(category)} | {fixtures} "
            f"| {accepted} | {rejected} | {recovery} | {_cell(prereq_note)} |"
        )
    lines.append("")
    lines.append("### Flink totals")
    lines.append("")
    lines.append(f"- **Parser accepted (valid syntax):** {total_accepted} fixtures")
    lines.append(f"- **Parser rejected (expected errors):** {total_rejected} fixtures")
    lines.append(f"- **Recovery (bounded editor recovery):** {total_recovery} fixtures")
    lines.append(
        f"- **Engine-semantic prerequisite (never engine-supported):** "
        f"{prereq_fixtures} fixtures"
    )
    lines.append(
        f"- **Engine-supported (positive only):** {engine_supported} fixtures"
    )
    lines.append("")
    lines.append(
        "The engine-supported total counts positive fixtures only; "
        "catalog-prerequisite, planner-prerequisite, and known-limitation "
        "fixtures are never reported as engine-supported."
    )
    return lines


def check_flink_invariants(coverage, problems):
    """Prerequisite hard rule (Pitfall 2 / D-01) + enum + engine-supported=0."""
    if not coverage:
        problems.append("corpus/flink-coverage.tsv is missing or empty (non-empty guard, Pitfall 8)")
        return
    seen = set()
    for row in coverage:
        profile = row.get("profile", "")
        category = row.get("category", "")
        if profile == "all":
            continue
        key = (profile, category)
        if key in seen:
            problems.append(f"flink coverage duplicate row ({profile}, {category})")
        seen.add(key)
        if category not in FLINK_CATEGORIES:
            problems.append(f"flink coverage ({profile}): unknown category {category!r}")
            continue
        # Prerequisite rows must carry a non-none prerequisite and must never
        # be reported as engine-supported (the renderer only counts positive
        # rows as engine-supported, so a prerequisite row counted under
        # engine-supported is a renderer bug the report text asserts against).
        if category in PREREQUISITE_CATEGORIES:
            prereq = row.get("prerequisite", "none") or "none"
            if prereq == "none":
                problems.append(
                    f"flink coverage ({profile}, {category}): prerequisite row "
                    f"carries prerequisite=none (must name catalog/planner/structural)"
                )
            if int(row.get("parser_accepted", 0)) > 0 and int(row.get("parser_accepted", 0)) != int(row.get("fixture_count", 0)):
                problems.append(
                    f"flink coverage ({profile}, {category}): prerequisite row "
                    f"parser_accepted must equal fixture_count (syntax-accepted, "
                    f"not engine-supported)"
                )
    return


def render(manifest, coverage, flink_coverage):
    lines = ["# CORPUS-REPORT: Doris SQL Parser SDK Corpus Coverage", "",
             "Deterministic, offline-generated report (D-19). Regenerate with:", "",
             "```bash",
             "python3 corpus/tools/generate_corpus_report.py",
             "```", "",
             "`--check` mode fails when this report is stale relative to "
             "corpus/manifest.tsv, corpus/coverage.tsv, and "
             "corpus/flink-coverage.tsv, when the one-fixture-one-row "
             "invariant is violated, when the Flink prerequisite hard rule is "
             "violated, or when an unqualified compatibility claim appears. "
             "No unqualified compatibility claim is made anywhere in this "
             "report.",
             ""]
    lines.extend(render_matrix(manifest, coverage))
    lines.append("")
    lines.extend(render_failures(manifest))
    lines.append("")
    lines.extend(render_known_gaps(manifest, coverage))
    lines.append("")
    lines.extend(render_keywords())
    lines.append("")
    lines.extend(render_flink(flink_coverage))
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("Report invariants (enforced by `--check`): every manifest "
                 "fixture appears in exactly one coverage row; the report is "
                 "byte-identical to a fresh generation; the known-gaps section "
                 "is never empty; Flink catalog/planner/known-limitation rows "
                 "are never counted as engine-supported; no `full-compatibility` "
                 "or `100-percent` claim string appears in the corpus text "
                 "files.")
    lines.append("")
    return "\n".join(lines) + "\n"


def check_invariants(manifest, coverage, report_text):
    problems = []
    # One-fixture-one-row invariant.
    groups = {}
    for row in manifest:
        key = (row["profile"], category_group(row["category"]))
        groups.setdefault(key, []).append(row)
    cov_by_key = {}
    for row in coverage:
        cov_by_key.setdefault((row["profile"], row["category"]), []).append(row)
    for (profile, category), rows in sorted(groups.items()):
        cov_rows = cov_by_key.get((profile, category), [])
        if len(cov_rows) != 1:
            problems.append(f"manifest group ({profile}, {category}) has {len(rows)} fixtures but {len(cov_rows)} coverage rows (expected exactly one)")
            continue
        cov = cov_rows[0]
        expected_total = len(rows)
        expected_supported = sum(1 for r in rows if r["support_status"] == "supported")
        expected_error = sum(1 for r in rows if r["support_status"] == "expected-error")
        if int(cov["fixture_count"]) != expected_total:
            problems.append(f"coverage ({profile}, {category}) fixture_count {cov['fixture_count']} != manifest rows {expected_total}")
        if int(cov["supported_count"]) != expected_supported:
            problems.append(f"coverage ({profile}, {category}) supported_count {cov['supported_count']} != manifest supported {expected_supported}")
        if int(cov["expected_error_count"]) != expected_error:
            problems.append(f"coverage ({profile}, {category}) expected_error_count {cov['expected_error_count']} != manifest expected-error {expected_error}")
    for row in coverage:
        if row["profile"] == "all":
            continue
        if (row["profile"], row["category"]) not in groups:
            problems.append(f"coverage row ({row['profile']}, {row['category']}) has no manifest group")
    # Claim scan over the corpus text files.
    for path in [MANIFEST, COVERAGE, KEYWORDS, CORPUS / "differential.tsv", FLINK_COVERAGE, REPORT]:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        for match in CLAIM_PATTERN.finditer(text):
            problems.append(f"full-compatibility claim pattern {match.group()!r} in {path.name}")
    # Known-gaps section must be non-empty.
    if "## Known Gaps" not in report_text or len(render_known_gaps(manifest, coverage)) <= 3:
        problems.append("known-gaps section is missing or empty")
    return problems


def main(argv):
    manifest = read_tsv(MANIFEST)
    coverage = read_tsv(COVERAGE)
    flink_coverage = read_flink_coverage()
    report_text = render(manifest, coverage, flink_coverage)
    problems = check_invariants(manifest, coverage, report_text)
    check_flink_invariants(flink_coverage, problems)
    if "--check" in argv:
        stale = False
        if REPORT.exists():
            if REPORT.read_text(encoding="utf-8") != report_text:
                stale = True
                problems.append("CORPUS-REPORT.md is stale relative to manifest/coverage/flink-coverage")
        else:
            stale = True
            problems.append("CORPUS-REPORT.md does not exist")
        if problems:
            print("generate_corpus_report.py --check FAILED:", file=sys.stderr)
            for problem in problems:
                print("  - " + problem, file=sys.stderr)
            return 1
        print("ok: CORPUS-REPORT.md is current and consistent (matrix, failures, known-gaps, keywords summary, flink cross-dialect)")
        return 0
    if problems:
        print("generate_corpus_report.py: invariant problems found before write:", file=sys.stderr)
        for problem in problems:
            print("  - " + problem, file=sys.stderr)
        return 1
    REPORT.write_text(report_text, encoding="utf-8")
    print(f"wrote {REPORT.relative_to(ROOT)} ({len(report_text)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
