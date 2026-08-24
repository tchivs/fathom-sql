<!-- GSD:generated -->
English | [简体中文](README.zh-CN.md)

[![GitHub Release](https://img.shields.io/github/v/release/tchivs/fathom-sql?include_prereleases&label=Release)](https://github.com/tchivs/fathom-sql/releases)
[![npm version](https://img.shields.io/npm/v/@fathom-sql/sql?label=npm)](https://www.npmjs.com/package/@fathom-sql/sql)
[![VS Code Marketplace](https://img.shields.io/badge/VS%20Code-fathom--sql.sql%20v1.0.3-0078d4?logo=visualstudiocode&logoColor=white)](https://marketplace.visualstudio.com/items?itemName=fathom-sql.sql)
[![CI](https://github.com/tchivs/fathom-sql/actions/workflows/ci.yml/badge.svg)](https://github.com/tchivs/fathom-sql/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/tchivs/fathom-sql?color=blue)](LICENSE)
[![MoonBit](https://img.shields.io/badge/MoonBit-0.1.20260819-2f80ed)](https://www.moonbitlang.com/)
[![Targets](https://img.shields.io/badge/targets-native%20%7C%20js%20%7C%20wasm-555555)](moon.mod)
[![Doris](https://img.shields.io/badge/Doris-2.1%20%7C%203.x%20%7C%204.x-blue)](https://doris.apache.org/)
[![Flink](https://img.shields.io/badge/Flink-1.20.5%20%7C%202.1.3%20%7C%202.3.0-blue)](https://flink.apache.org/)
[![Last Commit](https://img.shields.io/github/last-commit/tchivs/fathom-sql)](https://github.com/tchivs/fathom-sql/commits)
[![Repo Size](https://img.shields.io/github/repo-size/tchivs/fathom-sql)](https://github.com/tchivs/fathom-sql)
[![Stars](https://img.shields.io/github/stars/tchivs/fathom-sql?style=social)](https://github.com/tchivs/fathom-sql/stargazers)

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
- **Five distribution channels**: npm SDK for Node/browser, VS Code extension, JetBrains plugin (coming soon), prebuilt `fathom-lsp` binaries, and MoonBit library import — all from one MoonBit core.

## Installation

Fathom is available through five channels. Pick the one that matches your use case:

| Channel | Artifact | Audience | Link |
|---|---|---|---|
| **npm SDK** | `@fathom-sql/sql` | Node.js / browser / bundler | [![npm](https://img.shields.io/npm/v/@fathom-sql/sql?label=%20)](https://www.npmjs.com/package/@fathom-sql/sql) [npm/README.md](npm/README.md) |
| **VS Code Extension** | `fathom-sql.sql` | VS Code / Cursor / Windsurf users | [![Marketplace](https://img.shields.io/badge/install-fathom--sql.sql-0078d4?logo=visualstudiocode&logoColor=white)](https://marketplace.visualstudio.com/items?itemName=fathom-sql.sql) [vscode/README.md](vscode/README.md) |
| **JetBrains Plugin** | `fathom-sql-intellij` | IntelliJ IDEA / PyCharm / DataGrip | [jetbrains/README.md](jetbrains/README.md) (Marketplace pending) |
| **LSP Binary** | `fathom-lsp` | Any LSP-capable editor / CLI / CI | [![GitHub Release](https://img.shields.io/github/v/release/tchivs/fathom-sql?label=%20)](https://github.com/tchivs/fathom-sql/releases) [↓ see below](#install-fathom-lsp-from-github-release) |
| **MoonBit Library** | `fathom/sql/*` | MoonBit package consumers | [↑ from source](#moonbit-library) |

### npm SDK (Node.js / browser)

```bash
npm install @fathom-sql/sql
```

Full JS API reference and usage examples: [npm/README.md](npm/README.md)

```js
import { parse, format, fingerprint, withLineColumns } from '@fathom-sql/sql';

const result = parse('SELECT 1', 'doris', '4.x', 'strict');
console.log(result.valid);          // true

const fmt = format('select 1', 'doris', '4.x', 'strict', { keyword_case: 'upper' });
console.log(new TextDecoder().decode(new Uint8Array(fmt.formatted)));  // "SELECT 1\n"
```

### VS Code Extension

Install from the [VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=fathom-sql.sql) (search "Fathom SQL Language Client"), then:

1. Download `fathom-lsp` from [GitHub Releases](https://github.com/tchivs/fathom-sql/releases) (see [below](#install-fathom-lsp-from-github-release))
2. Set `fathom.serverPath` to the binary path
3. Set `fathom.dialect` (`doris` or `flink`) and `fathom.profile` (e.g. `4.x`)

Details: [vscode/README.md](vscode/README.md)

### JetBrains Plugin (IntelliJ IDEA / PyCharm / DataGrip)

Build from source or wait for Marketplace publication:

```bash
cd jetbrains
./gradlew buildPlugin   # → build/distributions/fathom-sql-intellij-*.zip
```

Install via **Settings → Plugins → ⚙ → Install Plugin from Disk**. Requires [LSP4IJ](https://plugins.jetbrains.com/plugin/23257-lsp4ij) 0.20.1+.

Details: [jetbrains/README.md](jetbrains/README.md)

### LSP Binary (any editor / CLI / CI)

Prebuilt `fathom-lsp` binaries for three platforms, with SHA-256 verification. See [↓ Install fathom-lsp](#install-fathom-lsp-from-github-release) below.

### MoonBit Library

Clone and build from source with the MoonBit toolchain (`moon 0.1.20260819`, content-locked):

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
matches the version you want (for example `v1.0.3`; the binary reports
`fathom-lsp 1.0.3` via `--version`).

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
curl -fLO https://github.com/tchivs/fathom-sql/releases/download/v1.0.3/fathom-lsp-linux-x86_64
curl -fLO https://github.com/tchivs/fathom-sql/releases/download/v1.0.3/fathom-lsp-manifest.json
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
fathom-lsp --version   # prints: fathom-lsp 1.0.3
```

## License

This project is licensed under the [Apache-2.0](LICENSE) license.
