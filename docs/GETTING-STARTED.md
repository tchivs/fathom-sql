<!-- GSD:generated -->
English | [简体中文](zh-CN/GETTING-STARTED.md)
# Getting Started with Fathom

Fathom is a MoonBit parser SDK for Apache Doris SQL, providing source-byte preservation, diagnostics, and formatting capabilities for editors, formatting tools, and automation pipelines. The current repository provides library packages and a `fathom-sql/` native CLI adapter; it does not provide an HTTP service that needs to be started.

## Prerequisites

- **Git**: Required to obtain the source code.
- **MoonBit CLI**: The repository pins `moon 0.1.20260819` via `.github/moonbit-toolchain.json` (official SHA-256 sidecars, content-locked). Install the MoonBit CLI from the official channel and confirm with `moon version`; installation depends on the operating system and official distribution channel.<!-- VERIFY: MoonBit CLI platform installation steps and download address must be confirmed against the official release notes. -->
- **Python 3**: Required only for running corpus report or differential tools under `corpus/`. The parser itself does not require a Python runtime.
- **Optional Python dependencies**: `corpus/requirements.txt` pins the differential comparison tool `sqlglot==30.14.0`; install it only when using that differential tool.

The repository's core packages are MoonBit-only, but a standalone npm package (`@fathom-sql/sql`) is available for Node.js and browser consumers — see [npm/README.md](../../npm/README.md). For MoonBit library development, there are no Node.js runtime dependencies, no database, no `.env` file, and no deployment service. The MoonBit module identity and preferred build target are recorded in the root `moon.mod`: the module name is `fathom/sql`, the version is `1.0.5`, and the preferred target is `native`.

## Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/tchivs/fathom-sql.git Fathom
   cd Fathom
   ```

2. Confirm the MoonBit CLI version:

   ```bash
   moon version
   ```

   The output should match the version line recorded in the prerequisites. The repository's packages are managed through `moon.mod` and the `moon.pkg` files in each directory; no additional runtime dependency download is required.

3. (Optional) Install Python dependencies for the corpus differential tool:

   ```bash
   python3 -m pip install -r corpus/requirements.txt
   ```

## First Run

Run the module check from the project root to complete a working build verification:

```bash
moon check
```

This command checks the root package and library packages such as `api`, `parser`, `lexer`, `syntax`, `printer`, `formatter`, and `analyzer`. In the current repository, `moon check` has been verified to complete successfully; it may emit warnings about deprecations, redundant modifiers, or unused items. These warnings do not indicate that the check failed.

Fathom currently has no HTTP service, but it provides the `fathom-sql/` native CLI adapter. Library callers can import `fathom/sql/api` from their own MoonBit package. The CLI entry point is `fathom-sql/main.mbt`; for the shortest library example, see the “Usage examples” section of [README.md](../README.md).

## Common Setup Issues

### MoonBit version mismatch

If `moon version` does not match the toolchain version line recorded in `moon.mod`, switch to or install a matching MoonBit CLI and run again:

```bash
moon version
moon check
```

Do not use environment variables as a substitute for switching versions; the repository has no environment-variable configuration entry point. See [CONFIGURATION.md](CONFIGURATION.md) for the full parsing profile, mode, resource-limit, and formatting defaults.

### Starting the library as a service or CLI

The repository has no HTTP service, but it includes an executable `fathom-sql` package. To run the CLI, use the package's `format` entry point. To use the library API, import `fathom/sql/api` from the caller's MoonBit package. The parsing entry point requires an explicit Doris profile (`2.1`, `3.x`, or `4.x`) and mode (`strict` or `editor`).

### `moon test` reports snapshot placeholders or fails

The test command is:

```bash
moon test
```

The current repository has no `PLACEHOLDER` snapshot assertions in formatting tests. If `moon test` fails, inspect the relevant test file and implementation based on the actual error. This reflects the current test state, not a missing installation dependency. When first confirming the environment, prefer the already-verified `moon check`; when handling a test failure, first review the “Validation and testing” section of [README.md](../README.md) and the corresponding test files under `test/`.

### The corpus report check lacks Python or the report is outdated

The corpus consistency check uses the Python 3 standard library:

```bash
python3 corpus/tools/generate_corpus_report.py --check
```

If `python3` cannot be found, install Python 3. If the command reports that `CORPUS-REPORT.md` is outdated relative to the manifest or coverage, review the changes and then run the script without `--check` to regenerate the report. If you run the differential comparison tool, also confirm that the pinned `sqlglot==30.14.0` from `corpus/requirements.txt` is installed.

## Next Steps

- To install the prebuilt `fathom-lsp` binary from a GitHub Release, see the "Install `fathom-lsp` from GitHub Release" section of [README.md](../README.md).
- Read [README.md](../README.md) to learn the basics of `parse_with_ids`, `format_with_ids`, and `printer`.
- Read [ARCHITECTURE.md](ARCHITECTURE.md) to understand the `source → lexer → parser → syntax` data flow and package boundaries.
- Read [CONFIGURATION.md](CONFIGURATION.md) to choose the Doris profile, parsing mode, resource limits, and formatting options.
- Continue with [DEVELOPMENT.md](DEVELOPMENT.md) for local development commands, and [TESTING.md](TESTING.md) for test organization and execution.
