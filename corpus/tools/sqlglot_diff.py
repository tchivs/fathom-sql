#!/usr/bin/env python3
"""Local SQLGlot differential runner for the Doris SQL Parser SDK corpus (CORP-04, D-20).

Reads corpus/manifest.tsv, parses each disk-backed fixture SQL file with
SQLGlot (read="doris"), and rewrites corpus/differential.tsv with one
advisory row per manifest fixture.

Advisory-only contract (D-07/D-20, research Pattern 6):
  - public_contract is always "released-docs"; a SQLGlot acceptance can never
    promote an unsupported fixture and a rejection can never demote a
    supported one; the coverage report never consumes these rows.
  - sqlglot_observation records accepted / rejected / not-run-offline.
    Missing sqlglot, or a manifest row whose SQL lives only inside MoonBit
    test code (no corpus SQL file), degrades to not-run-offline -- an
    observation is never fabricated (A8 fallback, T-02-54).

Deterministic and offline (T-02-52): the version is pinned in
corpus/requirements.txt, the resolved sqlglot.__version__ is recorded on
every row, and regeneration is idempotent. Existing fe_nereids_observation
values are preserved by fixture_id so manual FE script runs are never
clobbered by a sqlglot re-run.
"""

import csv
import pathlib
import sys

CORPUS = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = CORPUS / "manifest.tsv"
DIFFERENTIAL = CORPUS / "differential.tsv"
PINNED = "30.14.0"

# Phase 1 landed the SELECT fixture under its own file name; every later
# category (02-04 naming) uses <category>.sql inside corpus/doris-<profile>/.
FIXTURE_FILE_OVERRIDES = {"industrial-select": "select-industrial.sql"}

HEADER = [
    "fixture_id",
    "public_contract",
    "fe_nereids_observation",
    "sqlglot_observation",
    "sqlglot_version",
    "resolution",
    "advisory_only",
]


def read_tsv(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def fixture_sql_path(row):
    profile = row["profile"]
    category = row["category"]
    name = FIXTURE_FILE_OVERRIDES.get(category, category + ".sql")
    return CORPUS / ("doris-" + profile) / name


def resolve_sqlglot():
    """Import sqlglot lazily; a missing installation must not crash the run.

    The sqlglot logger's "unsupported syntax ... falling back to Command"
    warnings are suppressed because that fallback is already recorded per row
    in the resolution column (Command fallback detail).
    """
    try:
        import logging

        import sqlglot

        logging.getLogger("sqlglot").setLevel(logging.ERROR)
        return sqlglot
    except ImportError:
        return None


def observe_fixture(sqlglot, sql):
    """Return (observation, detail) for one fixture's SQL text.

    observation is one of "accepted" / "rejected". sqlglot raises
    ParseError (error_level=RAISE) when any statement fails; a successful
    parse that falls back to a generic Command node is still an acceptance,
    but the fallback is recorded as detail so the advisory row is honest
    about the parse quality (T-02-54).
    """
    from sqlglot.errors import ErrorLevel, ParseError

    try:
        expressions = sqlglot.parse(
            sql, read="doris", error_level=ErrorLevel.RAISE
        )
    except ParseError as exc:
        detail = " ".join(str(exc).split())[:120].replace('"', "'")
        return "rejected", "ParseError: " + detail
    except Exception as exc:  # defensive: any unexpected parse failure is a rejection
        return "rejected", "unexpected error: %s" % type(exc).__name__
    if not expressions or any(expr is None for expr in expressions):
        return "rejected", "parse returned no complete expression"
    if any(isinstance(expr, sqlglot.exp.Command) for expr in expressions):
        return (
            "accepted",
            "accepted via generic Command fallback (unsupported-syntax warning)",
        )
    return "accepted", ""


def build_resolution(row, observation, detail):
    profile = row["profile"]
    category = row["category"]
    status = row["support_status"]
    if observation == "not-run-offline":
        if detail == "no-file":
            return (
                "fixture SQL is embedded in MoonBit test code, not a corpus SQL "
                "file; differential skipped for this row; public support is "
                "determined only by the released-docs manifest (D-07)"
            )
        return (
            "sqlglot not installed; install the pinned version with "
            "`pip install -r corpus/requirements.txt`; no observation fabricated (A8 fallback)"
        )
    if status == "supported":
        if observation == "accepted":
            msg = (
                "released docs %s document %s; sqlglot %s accepts the fixture; "
                "SDK supports it per the released-docs manifest; agreement"
                % (profile, category, PINNED)
            )
        else:
            msg = (
                "released docs %s document %s; sqlglot %s rejects the fixture; "
                "SDK follows the released-docs authority; disagreement recorded, "
                "advisory only" % (profile, category, PINNED)
            )
    else:  # support_status == expected-error
        if observation == "accepted":
            msg = (
                "released docs %s mark %s expected-error; sqlglot %s accepts the "
                "fixture; the released-docs manifest wins; disagreement recorded, "
                "advisory only" % (profile, category, PINNED)
            )
        else:
            msg = (
                "released docs %s mark %s expected-error; sqlglot %s also rejects; "
                "agreement, advisory only" % (profile, category, PINNED)
            )
    if detail:
        msg = msg + "; " + detail
    return msg


def clean_cell(value):
    """Keep TSV fields single-line and tab-free."""
    return " ".join(str(value).split())


def main():
    sqlglot = resolve_sqlglot()
    sqlglot_version = sqlglot.__version__ if sqlglot is not None else "not-run-offline"

    existing = {}
    if DIFFERENTIAL.exists():
        for old in read_tsv(DIFFERENTIAL):
            existing[old["fixture_id"]] = old.get("fe_nereids_observation", "not-run-offline")

    counts = {"accepted": 0, "rejected": 0, "not-run-offline": 0}
    out_rows = []
    for row in read_tsv(MANIFEST):
        path = fixture_sql_path(row)
        if not path.exists():
            observation, detail, version = "not-run-offline", "no-file", sqlglot_version
        elif sqlglot is None:
            observation, detail, version = "not-run-offline", "no-sqlglot", sqlglot_version
        else:
            sql = path.read_text(encoding="utf-8")
            observation, detail = observe_fixture(sqlglot, sql)
            version = sqlglot_version
        counts[observation] += 1
        out_rows.append(
            {
                "fixture_id": row["fixture_id"],
                "public_contract": "released-docs",
                "fe_nereids_observation": existing.get(
                    row["fixture_id"], "not-run-offline"
                ),
                "sqlglot_observation": observation,
                "sqlglot_version": version,
                "resolution": clean_cell(build_resolution(row, observation, detail)),
                "advisory_only": "true",
            }
        )

    with open(DIFFERENTIAL, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=HEADER, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(out_rows)

    print(
        "sqlglot_diff: wrote %d rows to %s (sqlglot %s; accepted=%d, rejected=%d, "
        "not-run-offline=%d); every row advisory_only=true"
        % (
            len(out_rows),
            DIFFERENTIAL.relative_to(CORPUS.parent),
            sqlglot_version,
            counts["accepted"],
            counts["rejected"],
            counts["not-run-offline"],
        )
    )
    if sqlglot is None:
        print(
            "WARNING: sqlglot is not installed; run `pip install -r corpus/requirements.txt` "
            "to populate accepted/rejected observations (A8 fallback in effect).",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
