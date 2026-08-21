<!-- GSD:generated -->
English | [简体中文](README.zh-CN.md)
[![MoonBit](https://img.shields.io/badge/MoonBit-0.1.20260819-2f80ed)](https://www.moonbitlang.com/)
[![Target](https://img.shields.io/badge/target-native-555555)](moon.mod)
[![Docs](https://img.shields.io/badge/docs-English%20%7C%20zh--CN-007ec6)](README.zh-CN.md)
# Fathom SQL Parser SDK

Fathom is a MoonBit parser SDK for Apache Doris and Flink SQL, providing source-fidelity parsing, diagnostics, formatting, and toolchain capabilities for editors, Web tools, and automation pipelines. **Repository:** https://github.com/tchivs/fathom-sql


## Features

- **Dual-dialect parsing**: Doris profiles `2.1`, `3.x`, `4.x` and Flink profiles `flink-2.3.0`, `flink-2.1.3`, `flink-1.20.5` — version-aware keyword classification and feature-introduction gating per dialect.
- **Two parsing modes**: `strict` performs strict validation, while `editor` provides error recovery for incomplete SQL.
- **Lossless syntax tree**: Parse results preserve byte ranges for tokens, trivia, errors, and skipped content; comments, whitespace, newlines, BOM, Unicode, and invalid bytes in the source can all be replayed by the printer.
- **Structured diagnostics**: Diagnostics include stable `FATHOM-PARSE-*` codes, messages, severity levels, byte ranges, and statement IDs.
- **CST formatting**: The formatter supports keyword case, indentation, line width, comma style, newline style, and trailing-newline policy; when it encounters an error tree, it refuses to emit a partial result.
- **SQL fingerprinting**: Deterministic content-normalized fingerprints for query caching and deduplication.
- **Column-level lineage**: Trace input/output columns from DML/DDL through a caller-injected `Catalog` (Doris only).
- **Optional name resolution**: The `analyzer` package resolves DML/DDL target tables through a caller-injected `Catalog`, keeping metadata dependencies out of syntax parsing.
- **Three distribution channels**: npm package `@fathom-sql/sql` for Node/browser, prebuilt `fathom-lsp` binaries from GitHub Releases, and MoonBit library import — all from one MoonBit core.

## Installation

Fathom is available as three independent artifacts:

1. **npm package** (`@fathom-sql/sql`) — for Node.js and browser consumers:

   ```bash
   npm install @fathom-sql/sql
   ```

   See [npm/README.md](npm/README.md) for the JS API and usage examples.

2. **Prebuilt `fathom-lsp` binary** — from [GitHub Releases](https://github.com/tchivs/fathom-sql/releases); see [Install fathom-lsp](#install-fathom-lsp-from-github-release) below.

3. **MoonBit library** — clone this repository and build from source with the MoonBit toolchain (`moon 0.1.20260819`, content-locked via `.github/moonbit-toolchain.json`):

   ```bash
   git clone https://github.com/tchivs/fathom-sql.git
   cd fathom-sql
   moon version   # confirm: moon 0.1.20260819 (fc2a4ee 2026-08-19)
   moon check
   ```

   Import `fathom/sql/api` into your own MoonBit package to call `parse_with_ids` or `format_with_ids` (see [Usage Examples](#usage-examples) below).

## Quick Start (MoonBit library)

After [installation](#installation) (option 3, MoonBit library), import `fathom/sql/api` and call `parse_with_ids` or `format_with_ids`:

## Usage Examples

### Parse Valid SQL

The `api` facade accepts raw `Bytes` and returns a `ParseResult` containing a primitive CST, profile metadata, and an array of diagnostics:

```moonbit
import {
  "fathom/sql/api" @api,
}

let parsed = @api.parse_with_ids(b"SELECT 1", "doris", "4.x", "strict")
match parsed {
  Ok(result) => {
    // result.valid == true
    // result.diagnostics.length() == 0
    println(result.root.kind) // document
  }
  Err(error) => {
    println(error.to_string())
  }
}
```

`ParseResult` also provides `statement(statement_id)`, `statement_diagnostics(statement_id)`, and `all_spans_in_bounds()`, making it convenient to consume the CST and diagnostics statement by statement.

### Recover Incomplete SQL in Editor Mode

For expressions that have not yet been completed, use `editor` mode to preserve the input and generate recovery nodes and diagnostics:

```moonbit
import {
  "fathom/sql/api" @api,
  "fathom/sql/printer" @printer,
}

let parsed = @api.parse_with_ids(b"SELECT 1 +", "doris", "4.x", "editor")
match parsed {
  Ok(result) => {
    // result.valid == false
    // result.recovered == true
    // result.root contains missing or error nodes
    // @printer.print_result(result) still replays the original bytes b"SELECT 1 +"
    println(result.diagnostics[0].code) // FATHOM-PARSE-002
  }
  Err(error) => {
    println(error.to_string())
  }
}
```

### Format While Preserving Comments and Newline Policy

The default formatting options are uppercase keywords, 2-space indentation, a 100-column line width, the input's newline style, and an appended trailing newline:

```moonbit
import {
  "fathom/sql/api" @api,
  "fathom/sql/formatter" @formatter,
}

let options = @formatter.FormatOptions::default()
let formatted = @api.format_with_ids(
  b"select 1; select 2",
  "doris",
  "4.x",
  "strict",
  options,
)
match formatted {
  Ok(result) => {
    // result.accepted == true
    // result.output == b"SELECT 1;\nSELECT 2\n"
    println(result.output.to_string())
  }
  Err(error) => {
    println(error.to_string())
  }
}
```

The formatting result contains `accepted`, output bytes, formatting/parsing diagnostics, and statement offsets. For error, missing, or skipped nodes, the formatter returns a rejected result with empty output instead of producing partially formatted text.

## Package Structure

```text
api/        Caller-facing parse/format facade, options, result, and diagnostic types
source/     Source snapshots, byte Spans, and line indexes
lexer/      Dialect-aware lexical analysis
token/      Token types, keyword classifications, and dialect profile metadata
parser/     Handwritten recursive-descent document parser and Pratt expression parsing path
syntax/     Lossless CST nodes, leaves, and error/missing structures
printer/    Precise replay of source bytes from a CST or ParseResult
formatter/  CST-based formatting layout and safe rejection logic
analyzer/   Minimal name-resolution layer based on a caller-provided Catalog
test/       MoonBit behavior tests, formatting tests, and corpus tests
corpus/     SQL fixtures, manifests, and coverage reports organized by Doris version
```


## Verification and Testing

- `moon check`: Verified to complete module checking (the current toolchain reports several deprecation/unused warnings).
- `moon test`: Runs test packages and corpus tests; test and snapshot status should be based on local command output; when a test fails, inspect the corresponding test file in `test/`.
- `python3 corpus/tools/generate_corpus_report.py --check`: Checks consistency among `corpus/manifest.tsv`, coverage, and the report.

Doris SQL support is defined by the fixtures and expected errors marked by profile in `corpus/manifest.tsv`, `corpus/coverage.tsv`, and `corpus/CORPUS-REPORT.md`; acceptance by an individual parser reference should not be treated as a public compatibility commitment.

## Install `fathom-lsp` from GitHub Release

Prebuilt `fathom-lsp` binaries are published with each GitHub Release
(<https://github.com/tchivs/fathom-sql/releases>). Pick the release tag that
matches the version you want (for example `v1.0.0`; the binary reports
`fathom-lsp 1.0.0` via `--version`).

### Per-platform assets

| Platform | Asset |
|----------|-------|
| Linux x86_64 | `fathom-lsp-linux-x86_64` |
| macOS (Apple Silicon) | `fathom-lsp-macos-aarch64` |
| Windows x86_64 | `fathom-lsp-windows-x86_64.exe` |

### Verify SHA-256

Download `fathom-lsp-manifest.json` from the same release and compare the
digest of your asset against its `assets` entry (per-platform `sha256`):

```bash
# Linux/macOS
curl -fLO https://github.com/tchivs/fathom-sql/releases/download/v1.0.0/fathom-lsp-linux-x86_64
curl -fLO https://github.com/tchivs/fathom-sql/releases/download/v1.0.0/fathom-lsp-manifest.json
python3 - <<'PY'
import hashlib, json
m = json.load(open("fathom-lsp-manifest.json"))
a = m["assets"]["linux-x86_64"]
got = hashlib.sha256(open(a["name"], "rb").read()).hexdigest()
assert got == a["sha256"], f"MISMATCH {got} != {a['sha256']}"
print("SHA-256 OK")
PY
```

### Install

```bash
mkdir -p ~/.fathom/bin
mv fathom-lsp-linux-x86_64 ~/.fathom/bin/fathom-lsp
chmod +x ~/.fathom/bin/fathom-lsp
export PATH="$HOME/.fathom/bin:$PATH"   # add this line to your shell profile
```

On Windows, move `fathom-lsp-windows-x86_64.exe` to your chosen directory and
add it to `PATH` (PowerShell: `Move-Item`).

### Verify the installation

```bash
fathom-lsp --version   # prints: fathom-lsp 1.0.0
```

## License

This project is licensed under the [Apache-2.0](LICENSE) license.
