# Differential Tooling (CORP-04)

This directory holds the differential harness that records disagreements
between the SDK's released-docs-based support claims and two external parse
references: SQLGlot (locally runnable) and Doris FE/Nereids (manual).

## Advisory-only contract (D-07 / D-20)

Every row in `corpus/differential.tsv` carries `advisory_only=true` and
`public_contract=released-docs`. Neither SQLGlot nor FE/Nereids is the public
contract:

- a SQLGlot or FE acceptance can **never promote** an unsupported fixture;
- a SQLGlot or FE rejection can **never demote** a supported fixture;
- support status is determined solely by the released-docs manifest
  (`corpus/manifest.tsv`) and the versioned keyword classification.

The coverage report (`corpus/coverage.tsv`, `CORPUS-REPORT.md`) never reads
differential observations; the generator's `--check` keeps them separate.

## SQLGlot differential (local, pinned)

SQLGlot is a pip-installable parser used purely as a parse-comparison
baseline. It is dev tooling only: it never enters the MoonBit dependency
graph and is never a runtime dependency.

### Setup (once)

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r corpus/requirements.txt    # pins sqlglot==30.14.0
```

### Run

```bash
python3 corpus/tools/sqlglot_diff.py
```

The script reads `corpus/manifest.tsv`, resolves each fixture's SQL file
(`corpus/doris-<profile>/<category>.sql`; the Phase 1 SELECT fixture lives at
`select-industrial.sql`), parses it with `sqlglot.parse(sql, read="doris")`,
and rewrites `corpus/differential.tsv` with one row per manifest fixture.

Columns:

| Column | Meaning |
|---|---|
| `fixture_id` | Manifest fixture id |
| `public_contract` | Always `released-docs` (D-07) |
| `fe_nereids_observation` | `accepted` / `rejected` / `not-run-offline` (filled only by the manual FE script) |
| `sqlglot_observation` | `accepted` / `rejected` / `not-run-offline` |
| `sqlglot_version` | Resolved `sqlglot.__version__` at run time |
| `resolution` | Version-specific explanation (agreement or recorded disagreement) |
| `advisory_only` | Always `true` |

Fallbacks (no fabricated observations, A8):

- sqlglot not installed -> every row degrades to `not-run-offline`; install
  with `pip install -r corpus/requirements.txt` and re-run.
- a manifest row whose SQL lives only inside MoonBit test code (boundary /
  recovery / encoding negatives, e.g. `*-boundary-*`, `*-recovery`,
  `*-invalid-encoding`, `2.1-merge`, `3.x-merge`) has no corpus SQL file and
  is recorded `not-run-offline` with that reason in the resolution.
- a parse that sqlglot accepts only via its generic `Command` fallback
  ("unsupported syntax" warning) is recorded `accepted` with the fallback
  noted in the resolution, so the row stays honest about parse quality.

Re-runs are idempotent and preserve existing `fe_nereids_observation` values,
so manual FE observations are never clobbered.

## FE/Nereids differential (manual, Java)

The official FE parser (`fe/fe-core/src/main/java/org/apache/doris/nereids/
parser/NereidsParser.java` in the apache/doris repository) requires a Java
build and is offline-unavailable in this environment. `fe_nereids_diff.sh` is
therefore a **documented manual script**: it is never executed in phase 02-06
and never wired into CI (D-20).

### Prerequisites (manual)

1. A checkout of <https://github.com/apache/doris>.
2. A built FE: `mvn -pl fe/fe-core -am package -DskipTests` (JDK version per
   the pinned FE release; see the apache/doris README).
3. A classpath: `FE_CLASSPATH` (preferred) or `DORIS_SRC` (auto-derived from
   `fe/fe-core/target/classes` plus FE jars).

### Run (manual, on a machine with the FE build)

```bash
FE_VERSION=4.1 DORIS_SRC=/path/to/doris bash corpus/tools/fe_nereids_diff.sh
```

- `FE_VERSION` pins the Doris release family matching the fixture set (the
  manifest profiles are 2.1 / 3.x / 4.x).
- The script generates a small `NereidsAcceptanceCheck` Java probe that calls
  `NereidsParser.parseSQL` on each fixture file — **parser-only, no cluster,
  no session, no SQL execution** (T-02-53).
- It updates `fe_nereids_observation` in `corpus/differential.tsv` by
  `fixture_id` (appending a row only for a fixture id that has no row yet),
  preserving `advisory_only=true` everywhere.

## Disagreement-resolution policy

When a reference disagrees with the released-docs manifest, the `resolution`
column records the disagreement with the reference's version (e.g.
`sqlglot 30.14.0` or the pinned `FE_VERSION`) and states that the released
docs win. Disagreements are evidence for gap analysis, never acceptance
criteria — the released-docs manifest is the sole authority (D-07/D-20).

## Pins & provenance

- `sqlglot==30.14.0` pinned in `corpus/requirements.txt` (dev tooling only,
  PyPI legitimacy audit OK in 02-RESEARCH.md); `sqlglot.__version__` is
  recorded per row at run time.
- FE/Nereids pin: `FE_VERSION` env var (default `4.1`), recorded per manual
  run; re-pin before each run.
- Both differential paths are deterministic and offline; nothing here
  executes SQL against a cluster or database.
