# CORPUS-REPORT: Doris SQL Parser SDK Corpus Coverage

Deterministic, offline-generated report (D-19). Regenerate with:

```bash
python3 corpus/tools/generate_corpus_report.py
```

`--check` mode fails when this report is stale relative to corpus/manifest.tsv, corpus/coverage.tsv, and corpus/flink-coverage.tsv, when the one-fixture-one-row invariant is violated, when the Flink prerequisite hard rule is violated, or when an unqualified compatibility claim appears. No unqualified compatibility claim is made anywhere in this report.

## Version x Category Matrix

| Profile | Category | Fixtures | Supported | Expected-error | Known gap |
|---|---|---|---|---|---|
| 2.1 | contextual-keyword | 1 | 1 | 0 | pinned revision unavailable offline |
| 2.1 | core-04-boundary | 2 | 1 | 1 | pinned revision unavailable offline |
| 2.1 | ddl-create-index | 1 | 1 | 0 | pinned revision unavailable offline |
| 2.1 | ddl-create-table | 1 | 1 | 0 | pinned revision unavailable offline |
| 2.1 | ddl-create-view | 1 | 1 | 0 | pinned revision unavailable offline |
| 2.1 | dml-delete | 1 | 1 | 0 | pinned revision unavailable offline |
| 2.1 | dml-insert-select | 1 | 1 | 0 | pinned revision unavailable offline |
| 2.1 | dml-insert-values | 1 | 1 | 0 | pinned revision unavailable offline |
| 2.1 | dml-merge | 1 | 0 | 1 | MERGE INTO documented only in the 4.x docs tree |
| 2.1 | dml-update | 1 | 1 | 0 | pinned revision unavailable offline |
| 2.1 | industrial-select | 1 | 1 | 0 | pinned revision unavailable offline |
| 2.1 | malformed-and-encoding | 1 | 0 | 1 | invalid bytes are inline |
| 2.1 | version-gate | 1 | 0 | 1 | no public fallback |
| 3.x | core-04-boundary | 2 | 2 | 0 | pinned revision unavailable offline |
| 3.x | ddl-create-index | 1 | 1 | 0 | pinned revision unavailable offline |
| 3.x | ddl-create-table | 1 | 1 | 0 | pinned revision unavailable offline |
| 3.x | ddl-create-view | 1 | 1 | 0 | pinned revision unavailable offline |
| 3.x | dml-delete | 1 | 1 | 0 | pinned revision unavailable offline |
| 3.x | dml-insert-select | 1 | 1 | 0 | pinned revision unavailable offline |
| 3.x | dml-insert-values | 1 | 1 | 0 | pinned revision unavailable offline |
| 3.x | dml-merge | 1 | 0 | 1 | MERGE INTO documented only in the 4.x docs tree |
| 3.x | dml-update | 1 | 1 | 0 | pinned revision unavailable offline |
| 3.x | industrial-select | 1 | 1 | 0 | pinned revision unavailable offline |
| 3.x | malformed-and-encoding | 1 | 0 | 1 | pinned revision unavailable offline |
| 4.x | core-04-boundary | 1 | 1 | 0 | pinned revision unavailable offline |
| 4.x | ddl-create-index | 1 | 1 | 0 | pinned revision unavailable offline |
| 4.x | ddl-create-materialized-view | 1 | 1 | 0 | pinned revision unavailable offline |
| 4.x | ddl-create-table | 1 | 1 | 0 | pinned revision unavailable offline |
| 4.x | ddl-create-table-ctas | 1 | 1 | 0 | pinned revision unavailable offline |
| 4.x | ddl-create-table-like | 1 | 1 | 0 | pinned revision unavailable offline |
| 4.x | ddl-create-view | 1 | 1 | 0 | pinned revision unavailable offline |
| 4.x | dml-delete | 1 | 1 | 0 | pinned revision unavailable offline |
| 4.x | dml-insert-overwrite | 1 | 1 | 0 | pinned revision unavailable offline |
| 4.x | dml-insert-select | 1 | 1 | 0 | pinned revision unavailable offline |
| 4.x | dml-insert-values | 1 | 1 | 0 | pinned revision unavailable offline |
| 4.x | dml-merge | 1 | 1 | 0 | pinned revision unavailable offline |
| 4.x | dml-update | 1 | 1 | 0 | pinned revision unavailable offline |
| 4.x | industrial-select | 1 | 1 | 0 | pinned revision unavailable offline |
| 4.x | malformed-and-encoding | 3 | 0 | 3 | invalid bytes are inline |
| 4.x | script-multi-statement | 1 | 1 | 0 | pinned revision unavailable offline |

## Failure List

Expected-error rows are explicit failures with recovery/version goldens. Supported-row oracle failures are surfaced by `moon test` (test/corpus_test.mbt oracle) and cannot be evaluated by this generator.

| Fixture | Profile | Category | Parse mode | Reason |
|---|---|---|---|---|
| 2.1-boundary-empty | 2.1 | core-04-boundary-empty-clause | editor | expected-error |
| 2.1-invalid-encoding | 2.1 | invalid-encoding | editor | expected-error |
| 2.1-merge | 2.1 | dml-merge | strict | expected-error |
| 3.x-unsupported-profile | 2.1 | unsupported-version | strict | expected-error |
| 3.x-merge | 3.x | dml-merge | strict | expected-error |
| 3.x-recovery | 3.x | malformed-recovery | editor | expected-error |
| 4.x-invalid-encoding | 4.x | invalid-encoding | editor | expected-error |
| 4.x-malformed-recovery | 4.x | malformed-recovery | editor | expected-error |
| 4.x-recovery | 4.x | malformed-recovery | editor | expected-error |

## Known Gaps

### Provenance gaps (manifest rows)

| Fixture | Profile | Gap |
|---|---|---|
| 2.1-boundary-empty | 2.1 | known-gap: GitHub revision lookup returned an empty API result |
| 2.1-boundary-single | 2.1 | known-gap: GitHub revision lookup returned an empty API result |
| 2.1-contextual-keyword | 2.1 | known-gap: GitHub revision lookup returned an empty API result |
| 2.1-create-index | 2.1 | known-gap: GitHub revision lookup returned an empty API result |
| 2.1-create-table | 2.1 | known-gap: GitHub revision lookup returned an empty API result |
| 2.1-create-view | 2.1 | known-gap: GitHub revision lookup returned an empty API result |
| 2.1-delete | 2.1 | known-gap: GitHub revision lookup returned an empty API result |
| 2.1-industrial | 2.1 | known-gap: GitHub revision lookup returned an empty API result |
| 2.1-insert-select | 2.1 | known-gap: GitHub revision lookup returned an empty API result |
| 2.1-insert-values | 2.1 | known-gap: GitHub revision lookup returned an empty API result |
| 2.1-invalid-encoding | 2.1 | known-gap: bytes are inline because TSV is UTF-8 text |
| 2.1-merge | 2.1 | known-gap: MERGE INTO is documented only in the 4.x docs tree; 2.1/3.x emit DORIS-PARSE-006 per released-docs authority |
| 2.1-update | 2.1 | known-gap: GitHub revision lookup returned an empty API result |
| 3.x-unsupported-profile | 2.1 | known-gap: source page is released 3.x, selected profile is intentionally 2.1 |
| 3.x-boundary-set-many | 3.x | known-gap: GitHub revision lookup returned an empty API result |
| 3.x-boundary-set-one | 3.x | known-gap: GitHub revision lookup returned an empty API result |
| 3.x-create-index | 3.x | known-gap: GitHub revision lookup returned an empty API result |
| 3.x-create-table | 3.x | known-gap: GitHub revision lookup returned an empty API result |
| 3.x-create-view | 3.x | known-gap: GitHub revision lookup returned an empty API result |
| 3.x-delete | 3.x | known-gap: GitHub revision lookup returned an empty API result |
| 3.x-industrial | 3.x | known-gap: GitHub revision lookup returned an empty API result |
| 3.x-insert-select | 3.x | known-gap: GitHub revision lookup returned an empty API result |
| 3.x-insert-values | 3.x | known-gap: GitHub revision lookup returned an empty API result |
| 3.x-merge | 3.x | known-gap: MERGE INTO is documented only in the 4.x docs tree; 2.1/3.x emit DORIS-PARSE-006 per released-docs authority |
| 3.x-recovery | 3.x | known-gap: GitHub revision lookup returned an empty API result |
| 3.x-update | 3.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-boundary-set-two | 4.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-create-index | 4.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-create-materialized-view | 4.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-create-table | 4.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-create-table-ctas | 4.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-create-table-like | 4.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-create-view | 4.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-delete | 4.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-industrial | 4.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-insert-overwrite | 4.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-insert-select | 4.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-insert-values | 4.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-invalid-encoding | 4.x | known-gap: bytes are inline because TSV is UTF-8 text |
| 4.x-malformed-recovery | 4.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-merge | 4.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-recovery | 4.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-script-multi-statement | 4.x | known-gap: GitHub revision lookup returned an empty API result |
| 4.x-update | 4.x | known-gap: GitHub revision lookup returned an empty API result |

### Coverage gaps (coverage rows)

| Profile | Category | Gap |
|---|---|---|
| 2.1 | contextual-keyword | pinned revision unavailable offline |
| 2.1 | core-04-boundary | pinned revision unavailable offline |
| 2.1 | ddl-create-index | pinned revision unavailable offline |
| 2.1 | ddl-create-table | pinned revision unavailable offline |
| 2.1 | ddl-create-view | pinned revision unavailable offline |
| 2.1 | dml-delete | pinned revision unavailable offline |
| 2.1 | dml-insert-select | pinned revision unavailable offline |
| 2.1 | dml-insert-values | pinned revision unavailable offline |
| 2.1 | dml-merge | MERGE INTO documented only in the 4.x docs tree |
| 2.1 | dml-update | pinned revision unavailable offline |
| 2.1 | industrial-select | pinned revision unavailable offline |
| 2.1 | malformed-and-encoding | invalid bytes are inline |
| 2.1 | version-gate | no public fallback |
| 3.x | core-04-boundary | pinned revision unavailable offline |
| 3.x | ddl-create-index | pinned revision unavailable offline |
| 3.x | ddl-create-table | pinned revision unavailable offline |
| 3.x | ddl-create-view | pinned revision unavailable offline |
| 3.x | dml-delete | pinned revision unavailable offline |
| 3.x | dml-insert-select | pinned revision unavailable offline |
| 3.x | dml-insert-values | pinned revision unavailable offline |
| 3.x | dml-merge | MERGE INTO documented only in the 4.x docs tree |
| 3.x | dml-update | pinned revision unavailable offline |
| 3.x | industrial-select | pinned revision unavailable offline |
| 3.x | malformed-and-encoding | pinned revision unavailable offline |
| 4.x | core-04-boundary | pinned revision unavailable offline |
| 4.x | ddl-create-index | pinned revision unavailable offline |
| 4.x | ddl-create-materialized-view | pinned revision unavailable offline |
| 4.x | ddl-create-table | pinned revision unavailable offline |
| 4.x | ddl-create-table-ctas | pinned revision unavailable offline |
| 4.x | ddl-create-table-like | pinned revision unavailable offline |
| 4.x | ddl-create-view | pinned revision unavailable offline |
| 4.x | dml-delete | pinned revision unavailable offline |
| 4.x | dml-insert-overwrite | pinned revision unavailable offline |
| 4.x | dml-insert-select | pinned revision unavailable offline |
| 4.x | dml-insert-values | pinned revision unavailable offline |
| 4.x | dml-merge | pinned revision unavailable offline |
| 4.x | dml-update | pinned revision unavailable offline |
| 4.x | industrial-select | pinned revision unavailable offline |
| 4.x | malformed-and-encoding | invalid bytes are inline |
| 4.x | script-multi-statement | pinned revision unavailable offline |
| all | known-gaps | exact website commit SHA unavailable from offline lookup |

### Flagged and discovered gaps

- A5: Oracle-style multi-table INSERT (INSERT ALL/FIRST) is not documented in released Doris docs; presence unverified (no fixture claims it).
- CLUSTER BY (<cluster_cols>) is documented in the 2.1/3.x CREATE TABLE key clause but is not implemented by the parser (discovered during the 02-04 corpus wave).
- CREATE TEMPORARY TABLE is documented in the 4.x CREATE TABLE grammar only (`CREATE [ TEMPORARY | EXTERNAL ] TABLE`); the parser accepts it under all released profiles (02-02 decision); 2.1/3.x fixtures avoid it.
- The bare `CREATE MATERIALIZED VIEW <name> [ AS ] query` spelling follows the sync-MV page's restricted body; the async form (BUILD/REFRESH, IF NOT EXISTS, column list) is selected by clause presence per the async-MV pages.
- `CREATE ASYNC MATERIALIZED VIEW` is the docs page title; the syntax blocks spell `CREATE MATERIALIZED VIEW`; both spellings are accepted (A2 closed).

## Keyword Classification Summary (D-16)

| Classification | Count |
|---|---|
| contextual | 26 |
| non-reserved | 6 |
| reserved | 84 |

By introduced profile: 2.1: 112, 3.x: 2, 4.x: 2 (total 116 words).

## Flink Cross-Dialect Coverage (CORPUS-01 / PARITY-03)

Parser acceptance and engine-semantic prerequisite are reported as distinct totals. Generic SQL that the parser merely accepts is NEVER counted as Flink engine support (D-01): catalog-prerequisite, planner-prerequisite, and known-limitation fixtures are reported as prerequisite, never as engine-supported.

| Profile | Category | Fixtures | Parser accepted | Parser rejected | Recovery | Prerequisite |
|---|---|---|---|---|---|---|
| doris-4.x | positive | 1 | 1 | 0 | 0 | none |
| flink-2.3.0 | catalog-prerequisite | 1 | 1 | 0 | 0 | catalog |
| flink-2.3.0 | known-limitation | 1 | 1 | 0 | 0 | structural |
| flink-2.3.0 | negative | 1 | 0 | 1 | 0 | none |
| flink-2.3.0 | planner-prerequisite | 1 | 1 | 0 | 0 | planner |
| flink-2.3.0 | positive | 1 | 1 | 0 | 0 | none |
| flink-2.3.0 | recovery | 1 | 0 | 0 | 1 | none |

### Flink totals

- **Parser accepted (valid syntax):** 5 fixtures
- **Parser rejected (expected errors):** 1 fixtures
- **Recovery (bounded editor recovery):** 1 fixtures
- **Engine-semantic prerequisite (never engine-supported):** 3 fixtures
- **Engine-supported (positive only):** 2 fixtures

The engine-supported total counts positive fixtures only; catalog-prerequisite, planner-prerequisite, and known-limitation fixtures are never reported as engine-supported.

---

Report invariants (enforced by `--check`): every manifest fixture appears in exactly one coverage row; the report is byte-identical to a fresh generation; the known-gaps section is never empty; Flink catalog/planner/known-limitation rows are never counted as engine-supported; no `full-compatibility` or `100-percent` claim string appears in the corpus text files.

