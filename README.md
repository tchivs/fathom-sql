<!-- GSD:generated -->
English | [简体中文](README.zh-CN.md)
[![MoonBit](https://img.shields.io/badge/MoonBit-0.1.20260724-2f80ed)](https://www.moonbitlang.com/)
[![Target](https://img.shields.io/badge/target-native-555555)](moon.mod)
[![Docs](https://img.shields.io/badge/docs-English%20%7C%20zh--CN-007ec6)](README.zh-CN.md)
# Fathom

Fathom is a MoonBit parser SDK for Apache Doris SQL, providing source-fidelity parsing, diagnostics, and formatting for editors, formatting tools, and automation pipelines.

## Features

- **Version-aware parsing**: Supports the `2.1`, `3.x`, and `4.x` Doris profiles, and validates version and feature-introduction information through profile metadata.
- **Two parsing modes**: `strict` performs strict validation, while `editor` provides error recovery for incomplete SQL.
- **Lossless syntax tree**: Parse results preserve byte ranges for tokens, trivia, errors, and skipped content; comments, whitespace, newlines, BOM, Unicode, and invalid bytes in the source can all be replayed by the printer.
- **Structured diagnostics**: Diagnostics include stable `DORIS-PARSE-*` codes, messages, severity levels, byte ranges, and statement IDs.
- **CST formatting**: The formatter supports keyword case, indentation, line width, comma style, newline style, and trailing-newline policy; when it encounters an error tree, it refuses to emit a partial result.
- **Optional name resolution**: The `analyzer` package resolves DML/DDL target tables through a caller-injected `Catalog`, keeping metadata dependencies out of syntax parsing.
- **Library and CLI**: Core parsing capabilities are provided as MoonBit library packages, while `fathom-sql/` contains the native CLI adapter; the repository has no deployment service.

## Installation

This repository contains no Node.js package manifest or other runtime dependencies; module metadata is defined in `moon.mod`, and the currently recorded MoonBit CLI version is `moon 0.1.20260724`. Install a MoonBit CLI compatible with this version line first (the installation source is outside the repository).<!-- VERIFY: The platform installation method for the MoonBit CLI must be confirmed against the external official release instructions. -->

Run the checks from the repository root:

```bash
moon version
moon check
```

The module has no additional MoonBit dependencies to download; `moon check` builds the current module and its library packages.

## Quick Start

1. Install the MoonBit CLI and confirm its version:

   ```bash
   moon version
   ```

2. Check the library code:

   ```bash
   moon check
   ```

3. Import `fathom/sql/api` into your own MoonBit package, then call `parse_with_ids` or `format_with_ids` (see the examples below).

## Usage Examples

### Parse Valid SQL

The `api` facade accepts raw `Bytes` and returns a `ParseResult` containing a primitive CST, profile metadata, and an array of diagnostics:

```moonbit
import {
  "fathom/sql/api" @api,
}

let parsed = @api.parse_with_ids(b"SELECT 1", "4.x", "strict")
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

let parsed = @api.parse_with_ids(b"SELECT 1 +", "4.x", "editor")
match parsed {
  Ok(result) => {
    // result.valid == false
    // result.recovered == true
    // result.root contains missing or error nodes
    // @printer.print_result(result) still replays the original bytes b"SELECT 1 +"
    println(result.diagnostics[0].code) // DORIS-PARSE-002
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
lexer/      Doris-profile-aware lexical analysis
token/      Token types, keyword classifications, and Doris profile metadata
parser/     Handwritten recursive-descent document parser and Pratt expression parsing path
syntax/     Lossless CST nodes, leaves, and error/missing structures
printer/    Precise replay of source bytes from a CST or ParseResult
formatter/  CST-based formatting layout and safe rejection logic
analyzer/   Minimal name-resolution layer based on a caller-provided Catalog
test/       MoonBit behavior tests, formatting tests, and corpus tests
corpus/     SQL fixtures, manifests, and coverage reports organized by Doris version
```

Public callers typically start with `api`; use the corresponding package when direct access to the CST, source snapshots, or analyzer is needed. `analyzer` does not participate in parser syntax validity or diagnostic results.

## Verification and Testing

- `moon check`: Verified to complete module checking (the current toolchain reports several deprecation/unused warnings).
- `moon test`: Runs test packages and corpus tests; test and snapshot status should be based on local command output; when a test fails, inspect the corresponding test file in `test/`.
- `python3 corpus/tools/generate_corpus_report.py --check`: Checks consistency among `corpus/manifest.tsv`, coverage, and the report.

Doris SQL support is defined by the fixtures and expected errors marked by profile in `corpus/manifest.tsv`, `corpus/coverage.tsv`, and `corpus/CORPUS-REPORT.md`; acceptance by an individual parser reference should not be treated as a public compatibility commitment.

## License

The repository currently does not include a `LICENSE` file; the license type and link are to be confirmed.
