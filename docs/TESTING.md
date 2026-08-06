<!-- GSD:generated -->
English | [简体中文](zh-CN/TESTING.md)
# Testing Guide

Fathom uses MoonBit's built-in test runner to verify Doris SQL parsing, recovery, lossless replay, formatting, analysis, and versioned corpus contracts. Tests run offline: they do not connect to Doris FE, a database, or a SQL cluster; test inputs are represented primarily by embedded `Bytes` values and Git-tracked corpus metadata.

## Test Framework and Setup

### MoonBit Tests

- **Test framework**: MoonBit's built-in `test "name" { ... }` test blocks and built-in assertions such as `assert_true`, `assert_eq`, and `panic`.
- **Toolchain**: The repository's `moon.mod` records `moon 0.1.20260724 (5f1406a 2026-07-24)` as the toolchain; run `moon version` to confirm the current environment. `moon.mod` sets `native` as the preferred target.
- **Test package**: `test/moon.pkg` imports `api`, `parser`, `printer`, `source`, `syntax`, `token`, `formatter`, and `analyzer`; test files are concentrated under `test/`.
- **Dependency installation**: MoonBit tests have no additional runtime test dependencies. Install a MoonBit CLI compatible with the repository, then run `moon check` from the project root to complete module checking.
- **Environment requirements**: The test package does not read environment variables and does not require a database, Doris FE, a network, or a resident service. All core tests can run offline.

### Optional Differential Tools

The differential scripts under `corpus/tools/` are not required dependencies for MoonBit tests and cannot change the support conclusion in the released-docs manifest. A Python virtual environment with the pinned version is needed only when running the SQLGlot baseline:

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r corpus/requirements.txt  # sqlglot==30.14.0
```

`corpus/tools/generate_corpus_report.py` and `corpus/tools/check_keywords.py` use only the Python standard library; the FE/Nereids scripts are manual, advisory-only checks that require an external Doris FE build and are not part of the regular test setup or CI gates.

## Running Tests

### Full Test Suite

Run from the repository root:

```bash
moon test
```

To explicitly select the Native target:

```bash
moon test --target native
```

> **Note (pinned toolchain):** bare `moon test` triggers MoonBit error 4219 because the
> `binding` package is a `foreign_library` whose `#export_name` cannot appear in a
> test-target build — a documented boundary since v1 (04-03). Run the per-package
> invocation from DEVELOPMENT.md for the full behavioral suite, and
> `moon test --target wasm --package parity` for the linear-Wasm runtime parity gate.

`moon test` compiles and runs the `test/` test package. The current test code is divided by domain as follows:

| File | Coverage |
|---|---|
| `test/source_test.mbt` | Empty input, newlines, BOM, Unicode, invalid bytes, source-length and span boundaries, and raw-byte replay. |
| `test/parser_test.mbt` | SELECT/expressions, statement order and statement IDs, profile gates, diagnostics, recovery nodes, spans, and replay; also provides shared parsing helper structures used by corpus tests. |
| `test/recovery_test.mbt` | strict/editor recovery, invalid encoding, unterminated lexical material, byte/token/recursion/recovery/diagnostic limits, and source-backed replay after truncation. |
| `test/keyword_test.mbt` | reserved/non-reserved/contextual classifications, profile metadata, and bidirectional consistency between the runtime keyword table and `corpus/keywords.tsv`. |
| `test/dml_test.mbt` | DML such as INSERT, UPDATE, DELETE, and MERGE; version gates, error recovery, multi-statement input, and lossless replay. |
| `test/ddl_test.mbt` | DDL such as CREATE TABLE/VIEW/INDEX/MATERIALIZED VIEW; version gates, recovery, spans, and replay. |
| `test/analyzer_test.mbt` | Injected `Catalog` lookup, table-reference resolution, syntax results unaffected by the catalog, and node/diagnostic lookup by statement ID. |
| `test/formatter_test.mbt` | Formatting goldens, keyword/indentation/newline options, `format(format(x)) == format(x)` idempotence, output reparsing, and rejection of error trees. |
| `test/corpus_test.mbt` | Embedded manifest fixtures organized by Doris profile and statement category, the expected-error oracle, statement IDs, and whole-input replay. |

### Individual Files and Subsets

MoonBit's `PATH` argument selects a test file; `-f` filters by test-name glob; `-i` runs a test by index within the selected file:

```bash
# Run the parser test file
moon test test/parser_test.mbt

# Run only parser tests whose names start with industrial_select
moon test test/parser_test.mbt -f 'industrial_select*'

# Run the test at a specified index in the recovery test file (indexes start at 0)
moon test test/recovery_test.mbt -i 1
```

A single-file command still compiles the packages it needs. If a test name, file name, or test index changes, first confirm the target test with the single-file command without `-i`.

### Corpus and Audit Checks

Corpus-test support status is determined by `corpus/manifest.tsv` and `corpus/coverage.tsv`; `corpus/CORPUS-REPORT.md` is an offline-generated report. Run the consistency gates:

```bash
python3 corpus/tools/generate_corpus_report.py --check
python3 corpus/tools/check_keywords.py corpus/keywords.tsv
```

The first command checks that the report agrees with the manifest/coverage, that every fixture corresponds to exactly one coverage row, that known gaps exist, and that corpus text contains no non-compliant all-compatible claims. The second command checks keyword TSV fields, duplicates, classification/profile values, documentation URLs, and production-keyword coverage.

To update the report rather than only check it:

```bash
python3 corpus/tools/generate_corpus_report.py
```

SQLGlot differential testing is an optional, advisory-only baseline:

```bash
. .venv/bin/activate
python3 corpus/tools/sqlglot_diff.py
```

It writes observations to `corpus/differential.tsv`, but SQLGlot acceptance or rejection cannot raise or lower the SDK's public support status. The FE/Nereids differential script `corpus/tools/fe_nereids_diff.sh` requires an external Doris checkout, a built FE classpath, and `FE_VERSION`; run it manually only when these prerequisites are available. It is not a default test command.

## Writing New Tests

### Test Files and Naming

Place tests in the `.mbt` file for the corresponding domain under `test/`, using snake_case names that describe the behavior:

```moonbit
test "malformed_expression_keeps_source_bytes" {
  let raw = b"SELECT 1 +"
  let result = match @api.parse_with_ids(raw, "4.x", "editor") {
    Ok(value) => value
    Err(_) => panic()
  }
  assert_true(!result.valid)
  assert_true(result.recovered)
  assert_eq(@printer.print_result(result), raw)
  assert_true(result.all_spans_in_bounds())
}
```

Existing tests should prefer validating observable behavior through the public `@api.parse_with_ids`/`@api.format_with_ids` APIs; call `parser`, `source`, or other lower-level packages directly only when verifying an underlying limit or package boundary. Tests should avoid depending on test execution order, mutable global state, the current filesystem directory, or external services.

### Behavioral Contracts That Must Be Protected

Parser regression tests generally check all of the following layers rather than asserting only that parsing succeeds:

1. Whether `valid`, `recovered`, and the diagnostic count/code match expectations for strict or editor mode.
2. Diagnostic `DORIS-PARSE-###` codes, severity, expected class, byte spans, and snapshot-local `statement_id`.
3. Byte-level lossless replay via `@printer.print_result(result) == raw`, including comments, whitespace, LF/CRLF, BOM, Unicode, invalid bytes, and error material.
4. `result.all_spans_in_bounds()`, statement order, node kinds, and the `missing`/`error`/`skipped` recovery structure.
5. Acceptance or explicit rejection of version features under the `2.1`, `3.x`, and `4.x` profiles, without a generic dialect fallback.

Formatting tests should provide a complete `expected_golden` for accepted input and verify that the formatted result reparses without diagnostics and that formatting it again produces exactly the same bytes; error trees must verify `accepted == false` and produce no partial output. Existing formatter fixtures store embedded raw bytes and goldens rather than loading runtime fixtures from disk.

### Adding Corpus Fixtures

When adding official corpus material, keep the manifest, coverage, fixture, and executable oracle synchronized:

1. Put the SQL file in the appropriate `corpus/doris-2.1/`, `corpus/doris-3.x/`, or `corpus/doris-4.x/` directory, and record the profile, release, feature introduction, official URL, retrieval date, source revision, category, mode, and expected status.
2. Add one fixture record to `corpus/manifest.tsv` and update the corresponding profile/category summary in `corpus/coverage.tsv`; do not treat SQLGlot or FE observations as public support conclusions.
3. Add the corresponding raw bytes, metadata, parse mode, and `expected_valid` to the embedded fixture lists such as `dml_ddl_corpus_fixtures` in `test/corpus_test.mbt`, so that `dml_ddl_corpus_oracle_replays_every_manifest_fixture` covers the row.
4. Run `moon test`, `python3 corpus/tools/generate_corpus_report.py --check`, and the keyword check (if `corpus/keywords.tsv` was modified), then review replay, diagnostics, spans, and report differences.

Do not hide dropped trivia, incorrect profile gates, incorrect recovery states, or span changes by batch-updating goldens; golden updates must be reviewed together with the code and source metadata.

## Coverage Requirements

The repository contains no Jest/Vitest/Pytest configuration, `.nycrc`, coverage-threshold configuration, or CI coverage gate. Therefore, there is currently no minimum threshold specified for lines, branches, functions, or statements: **No coverage threshold configured.** Use MoonBit coverage as diagnostic information; it cannot replace corpus coverage measured by Doris profile/category.

Use MoonBit's built-in coverage tools:

```bash
moon coverage analyze
moon coverage report -f summary
```

For machine-readable or HTML reports, select a format supported by the MoonBit command, such as `-f coveralls`, `-f cobertura`, or `-f html`. Read coverage reports alongside the behavioral assertions from `moon test`; in particular, continue checking lossless round-trip, error/recovery nodes, version negative cases, and resource limits. These contracts must not be replaced by a single branch-coverage number.

`corpus/coverage.tsv` and `corpus/CORPUS-REPORT.md` describe SQL syntax feature/corpus coverage, not MoonBit source coverage. They record fixtures, supported, expected-error, and known-gap status for each profile/category and are checked for consistency by `generate_corpus_report.py --check`.

## CI Integration

`.github/workflows/ci.yml` runs on push to `master` and pull requests:

- **check** — `moon fmt --check`; `moon check` for native, JS, and linear-Wasm targets.
- **test** — `moon test` (native, full suite).
- **linear-wasm-parity** — `moon build --target wasm binding` and `moon build --target wasm parity`, then `moon test --target wasm --package parity` (executes the parity corpus **on the linear-Wasm backend**) plus `moon test --target native --package parity` for the byte-parity cross-check.
- **corpus** — `generate_corpus_report.py --check` and `check_keywords.py corpus/keywords.tsv`.

`.github/workflows/doris-native-release.yml` gates the GitHub Release job on the same `linear-wasm-parity` step (in addition to the native multi-platform build), so a release cannot publish without the linear-Wasm runtime execution parity passing.

There is no automatic coverage upload or automatic FE/Nereids differential testing (the FE script is deliberately manual-only, D-20). Before submitting, run at least the following from the repository root:

```bash
moon check
moon test
python3 corpus/tools/generate_corpus_report.py --check
```

If `corpus/keywords.tsv` was modified, also run:

```bash
python3 corpus/tools/check_keywords.py corpus/keywords.tsv
```

Release or cross-backend validation requires an explicitly selected target and separately recorded result, such as `moon test --target native` or the linear-Wasm parity job above; do not treat external-service or deployment-platform behavior not declared in repository CI as a test-pass condition.
