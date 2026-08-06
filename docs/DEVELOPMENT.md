<!-- GSD:generated -->
English | [简体中文](zh-CN/DEVELOPMENT.md)
# Development Guide

This guide explains how to develop Fathom locally, run MoonBit checks and tests, and maintain SQL corpus data organized by Doris version. Fathom consists of MoonBit library packages and the `fathom-sql/` native CLI adapter; the repository has no deployment service, and the Python tools are used only for corpus validation and optional differential analysis.

## Local Development Setup

### Prerequisites

- MoonBit CLI. `moon.mod` sets the default target to `native` and records the CLI output currently used by the project as `moon 0.1.20260724 (5f1406a 2026-07-24)`. Project comments follow the official MoonBit v0.10.5 documentation line, but in practice use the output of the local `moon version` and the version specified by the project maintainers.
- Python 3. Required only when running the Python validators or differential tools under `corpus/tools/`; the current development environment has been verified as Python 3.9.23.
- Optional: Python virtual environment. The locked development dependencies in `corpus/requirements.txt` need to be installed only when running the SQLGlot differential tool; SQLGlot is not part of the MoonBit runtime dependency graph.
- Git. Used to obtain the source code and commit changes.

### Obtaining the Source

The repository currently has no recorded Git remote, so its canonical clone URL cannot be confirmed from repository contents. <!-- VERIFY: Obtain the actual remote URL from the project hosting page. -->

```bash
git clone <repository-url>
cd Fathom
```

If you are already in the workspace, go directly to the project root:

```bash
cd /opt/source/Fathom
```

### Installation and First Check

MoonBit dependencies are declared by `moon.mod` and the `moon.pkg` files in the package directories; the current manifest has no additional MoonBit packages that need to be installed. The installation and development check steps are:

```bash
moon version
moon check
```

`moon check` checks the root module and its library packages but does not generate object files. Build artifacts are written to `_build/`, which is ignored by `.gitignore`.

### Development Environment Configuration

The project has no `.env` file, environment-variable reads, or environment-specific configuration loader. Parser configuration is passed explicitly at call sites through `api.ParseOptions`, `api.ParseLimits`, and `formatter.FormatOptions`; there is no need to copy `.env.example` or set a service port. Edit `moon.mod` to change the module identity, version, or default target; edit the `moon.pkg` in the corresponding directory to adjust package dependencies.

Public-library development normally starts at the `api/` facade; the lower-level implementation is organized along the `source → token → lexer → parser → syntax` dependency direction. Formatting is located in `formatter/`, lossless replay in `printer/`, and optional catalog name resolution in `analyzer/`. When adding syntax, consider the corresponding profile, CST nodes, diagnostics, recovery behavior, and regression cases in `test/` together.

## Build and Development Commands

The repository has no `scripts` field in `package.json` and no Makefile; the commands below are provided directly by the current MoonBit toolchain and the Python tools in the repository.

| Command | Description |
|---|---|
| `moon version` | Prints the current MoonBit CLI version; record this output first when committing or investigating build differences. |
| `moon check` | Checks the current module without generating object files. Provides quick feedback on type, import, and package-manifest issues. |
| `moon check --fmt` | Checks MoonBit source formatting while checking the module. |
| `moon build` | Builds the current module using the default `native` target from `moon.mod`. |
| `moon build --target native --release` | Builds the library packages and the `fathom-sql` executable package in Native release mode. |
| `moon build --target js` | Explicitly checks compatibility with the JavaScript backend. |
| `moon build --target wasm` | Explicitly checks compatibility with the linear WebAssembly backend. |
| `moon build --target wasm-gc` | Checks the Wasm GC backend when supported by the toolchain; it is not the current default target. |
| `moon test` | Runs MoonBit behavior tests in `test/` and tests for each library package. |
| `moon test --filter 'name-pattern'` | Runs only tests whose names match the pattern; useful for isolating a single regression behavior. |
| `moon test --package <package>` | Runs tests only for the specified MoonBit package. |
| `moon test --update` | Updates snapshots using MoonBit's snapshot-testing mechanism; confirm that the changes are expected before updating. |
| `moon fmt` | Formats source files with MoonBit's built-in formatter. |
| `moon fmt --check` | Checks formatting only; does not modify files. |
| `moon clean` | Removes local `_build/` build output; does not modify source code or corpus data. |
| `python3 corpus/tools/generate_corpus_report.py --check` | Checks that `manifest.tsv`, `coverage.tsv`, and `keywords.tsv` are consistent with the committed `CORPUS-REPORT.md`. |
| `python3 corpus/tools/check_keywords.py corpus/keywords.tsv` | Validates the keyword TSV header, categories, profiles, source URLs, duplicates, and production-keyword coverage. |

After completing a syntax or formatting change, it is recommended to run at least the following in order:

```bash
moon fmt --check
moon check
moon test --target native --package test --package parity --package lsp --package api --package source --package token --package lexer --package parser --package printer --package syntax --package completion --package analyzer
python3 corpus/tools/generate_corpus_report.py --check
python3 corpus/tools/check_keywords.py corpus/keywords.tsv
```

> Bare `moon test` currently triggers MoonBit error 4219 (the `binding` `foreign_library`
> `#export_name` in a test-target build) on the pinned toolchain — a documented boundary
> since v1 (04-03). Use the per-package invocation above for the full behavioral suite;
> run `moon test --target wasm --package parity` for the linear-Wasm runtime parity gate.

If the change affects only MoonBit packages, the corpus Python checks can still serve as a complete pre-commit consistency check; if the change affects `corpus/manifest.tsv`, `corpus/coverage.tsv`, or `corpus/keywords.tsv`, the corresponding validation command must be run.

### Optional SQLGlot Differential Tool

The differential tool is a development aid, not an Fathom runtime dependency. On first use, create a virtual environment in the project root and install the locked version:

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r corpus/requirements.txt
python3 corpus/tools/sqlglot_diff.py
```

The script reads `corpus/manifest.tsv`, parses fixtures that can be persisted using the Doris dialect, and updates `corpus/differential.tsv`. If SQLGlot or a fixture is unavailable, the tool records `not-run-offline` rather than fabricating an observation; differential results also cannot change the public support scope defined by the released-docs manifest.

## Code Style

### MoonBit

- Use MoonBit's built-in formatter; no `.editorconfig`, ESLint, Prettier, Biome, or other independent formatting configuration was found in the repository.
- Run `moon fmt --check` before committing; when automatic fixes are needed, run `moon fmt` and then inspect the generated diff.
- Follow the existing package boundaries: public cross-package APIs belong in `api/`, source coordinates in `source/`, lexical and profile facts in `token/`, and grammar productions and recovery in `parser/`. Do not copy a second keyword-classification table into `formatter`; reuse the classification from `token`.
- Preserve the source-fidelity invariant: nodes reference `Span` rather than copying source text; lossless output from `printer` must preserve the original bytes; when the formatter encounters `error`, `missing`, or `skipped` material, it must follow the reject-output contract.
- When adding public types or functions, follow the existing `pub(all)`, constructor, and accessor style, and add stable profile, diagnostic, byte-range, and error-recovery tests.

### Python Tools

Scripts under `corpus/tools/` use the Python standard library (the differential tool additionally depends on the locked SQLGlot version); the repository has no Python formatter or lint configuration. Preserve the existing style of module-level constants, `main(argv)` returning an exit code, the `if __name__ == "__main__"` entry point, and error-oriented stderr output; after changes, run each affected script directly at a minimum.

### Test Style

Tests are located in `test/` and use MoonBit's `test "..." { ... }` form. Files are organized by behavior domain, including `parser_test.mbt`, `recovery_test.mbt`, `formatter_test.mbt`, `ddl_test.mbt`, `dml_test.mbt`, `analyzer_test.mbt`, `source_test.mbt`, `keyword_test.mbt`, and `corpus_test.mbt`. Tests should assert observable contracts such as:

- `printer.print_result(result)` is exactly equal to the input bytes;
- `valid`, `recovered`, diagnostic code, statement ID, and span boundaries match the profile/mode;
- formatted output is repeatable (`format(format(x)) == format(x)`) and can be parsed again;
- the `corpus` manifest and coverage report remain one-to-one and consistent in their version classification.

Do not depend on generated files in `_build/`, and do not have runtime tests implicitly read fixtures from disk; existing tests embed key fixtures and goldens in MoonBit source code.

## Branch Conventions

The repository has no `CONTRIBUTING.md` or pull request template, so no branch-naming convention is documented. CI gates live in `.github/workflows/ci.yml` (moon check/fmt, native test, linear-Wasm runtime execution parity, corpus checks) and `.github/workflows/fathom-native-release.yml` (release). The currently checked-out branch is `master`, and recent commit titles use Conventional Commits-style prefixes such as `feat(...)` and `docs(...)`; these are practices observed in the current repository, not mandatory conventions.

It is recommended to start new work from the latest `master` in a short-lived branch using a purpose-expressing prefix, for example:

- `feat/<scope>`: add parser, formatter, or API behavior;
- `fix/<scope>`: fix a parsing, recovery, or output regression;
- `docs/<scope>`: modify documentation only;
- `test/<scope>`: add regression tests or corpus validation.

If the project hosting platform or maintainers specify otherwise, follow their requirements.

## Pull Request Process

The repository has no project-specific PR template. PRs run `.github/workflows/ci.yml` (moon check/fmt, native tests, linear-Wasm runtime execution parity, corpus checks). Before submitting a PR, prepare it using the following checklist:

1. Create a branch from the latest `master`, keep each commit focused on one behavior or documentation topic, and optionally follow the existing `feat(scope): ...`, `fix(scope): ...`, or `docs(scope): ...` title format.
2. In the PR description, state the affected Doris profile (`2.1`, `3.x`, or `4.x`), parsing mode (`strict` or `editor`), and packages; when syntax coverage changes, identify the corresponding corpus fixture or released-docs source.
3. Run `moon fmt --check`, `moon check`, and the affected `moon test`; for changes to complete parsing behavior, run `moon test`, and for changes to corpus manifests or keyword tables, also run the corresponding Python `--check` command.
4. For formatter changes, verify lossless printing, error-tree rejection, output idempotence, and reparsing behavior; for parser changes, verify diagnostic byte ranges, statement IDs, profile gates, and editor recovery behavior.
5. List the commands actually run and their results in the PR, and disclose any backends, external differential tools, or known corpus provenance gaps that were not run; do not present SQLGlot/FE advisory results as public compatibility commitments.

During review, focus especially on cross-package dependency direction, whether source bytes are copied or lost, whether error recovery exceeds resource limits, diagnostic stability, and whether tests protect real user-observable API contracts.

## Related Documentation

- [README.md](../README.md): project positioning, public API examples, package structure, and current verification entry points.
- [ARCHITECTURE.md](ARCHITECTURE.md): component relationships, data flow, key abstractions, and directory responsibilities.
- [CONFIGURATION.md](CONFIGURATION.md): complete configuration reference for `ParseOptions`, resource limits, and `FormatOptions`.
- `corpus/CORPUS-REPORT.md`: corpus coverage and known gaps organized by Doris profile and category.
- `corpus/tools/README.md`: development notes for the SQLGlot and Doris FE/Nereids differential tools.
