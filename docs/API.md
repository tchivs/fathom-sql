<!-- GSD:generated -->
English | [简体中文](zh-CN/API.md)
# API Reference

Fathom is a MoonBit library, not an HTTP service. The `api/` directory is the `fathom/sql/api` library package, providing a facade for parsing and formatting Doris SQL; callers pass source bytes, a Doris profile, mode, and limits through function parameters, so no server, Doris FE connection, or authentication credentials are required.

## Authentication

Not applicable. This repository has no HTTP service, middleware, API key, JWT, OAuth, session, or `Authorization` header handling. All APIs are synchronous in-process functions; callers only need to import the MoonBit package and pass arguments directly.

```moonbit
import {
  "fathom/sql/api" @api,
}
```

The parser also does not access a database or external catalog. Name resolution is provided independently by the `analyzer` package; the caller injects the catalog, and it does not change `ParseResult.valid` or syntax diagnostics.

## Endpoints Overview

This project has no HTTP endpoints, HTTP base URL, request routes, or deployment service. The “entry points” in the table below are library functions, not network endpoints.

| Entry point | Package | Purpose | Authentication |
|---|---|---|---|
| `parse` | `fathom/sql/api` | Parse raw SQL bytes using an already constructed `ParseOptions` | Not required |
| `parse_with_ids` | `fathom/sql/api` | Construct options from profile/mode strings and parse | Not required |
| `parse_with_metadata` | `fathom/sql/api` | Validate the profile’s release and feature metadata, then parse | Not required |
| `format_text` | `fathom/sql/api` | Parse and format SQL according to `FormatOptions` | Not required |
| `format_with_ids` | `fathom/sql/api` | Format using profile/mode strings as a shortcut | Not required |
| `format_with_metadata` | `fathom/sql/api` | Validate profile metadata, then format | Not required |
| `resolve_table_references` | `fathom/sql/analyzer` | Resolve target table names for supported DML/DDL using the caller’s catalog | Not required |
| `analyze` | `fathom/sql/analyzer` | Catalog name resolution and type diagnostics: resolved bindings plus analyzer-channel diagnostics | Not required |
| `lint_text` | `fathom/sql/api` | Run the Doris lint rule set over a parsed document; returns findings with candidate fixes | Not required |
| `fix_text` | `fathom/sql/api` | Apply safe lossless autofixes (minimal span edits); refuses error trees with `FATHOM-LINT-000` | Not required |
| `fingerprint_text` | `fathom/sql/api` | Produce a stable UInt64 SQL fingerprint plus the normalized canonical form | Not required |
| `lineage_text` | `fathom/sql/api` | Derive column-level lineage edges and honest gaps from a parsed document using the caller’s optional catalog | Not required |

## Request and Response Formats

### General Input Conventions

- SQL input is `Bytes`, not `String`. Source bytes are stored once at the result root; nodes and diagnostics refer to them through byte offsets.
- `start_byte` and `end_byte` are byte offsets in the half-open interval `[start_byte, end_byte)`, not Unicode character indexes; every span must fall within the input length.
- `dialect` must explicitly select `"doris"` or `"flink"`.
- `profile` must explicitly select `"2.1"`, `"3.x"`, or `"4.x"` (doris dialect); there is no silent fallback to a generic dialect.
- `mode` must be `"strict"` or `"editor"`. Both modes share the CST and diagnostic shapes; `editor` can generate `missing`, `error`, and `skipped` nodes to preserve incomplete input.

### Parse Options

```moonbit
pub(all) enum ParseMode {
  Strict
  Editor
}

pub struct ParseLimits {
  pub max_bytes : Int
  pub max_tokens : Int
  pub max_recursion_depth : Int
  pub max_recovery_steps : Int
  pub max_diagnostics : Int
}

pub struct ParseOptions {
  // profile/mode/limits are used through constructors and accessors
}
```

Constructors:

| Constructor | Description |
|---|---|
| `ParseOptions::new(dialect_id, profile_id, mode_id)` | Accepts `"doris"`/`"flink"`, `"2.1"`/`"3.x"`/`"4.x"`, and `"strict"`/`"editor"`, using default limits. |
| `ParseOptions::for_profile(profile, mode)` | Uses `@token.DorisProfile` and `ParseMode`, with default limits. |
| `ParseOptions::for_profile_with_limits(profile, mode, limits)` | Uses enum profile/mode values and caller-provided `ParseLimits`. |
| `ParseOptions::for_profile_with_metadata(profile, metadata, mode)` | Creates options after validating complete `ProfileMetadata`. |
| `ParseOptions::from_manifest(profile_id, exact_release, feature_introduction, mode_id)` | Creates options after validating profile metadata from manifest strings. |

Current values for `ParseLimits::default()`:

| Field | Default | Constraint |
|---|---:|---|
| `max_bytes` | `8 * 1024 * 1024` (8 MiB) | Non-negative; input exceeding it returns `InputTooLarge`. |
| `max_tokens` | `1_000_000` | Non-negative; limits tokens processed by one lex/parse operation. |
| `max_recursion_depth` | `128` | Non-negative; limits recursive-descent and expression recursion depth. |
| `max_recovery_steps` | `10_000` | Non-negative; limits recovery steps in editor mode. |
| `max_diagnostics` | `100` | Non-negative; limits the number of diagnostics retained in the result. |

### Parse Entry Points

#### `parse`

```moonbit
pub fn parse(
  raw : Bytes,
  options : ParseOptions,
) -> Result[ParseResult, ParseError]
```

This is the complete entry point: it validates limits and source size, runs the lexer/parser, checks CST span invariants, and returns the primitive result.

#### `parse_with_ids`

```moonbit
pub fn parse_with_ids(
  raw : Bytes,
  dialect_id : String,
  profile_id : String,
  mode_id_value : String,
) -> Result[ParseResult, ParseError]
```

Use this when the profile and mode come from configuration or CLI arguments. It is equivalent to calling `ParseOptions::new(dialect_id, profile_id, mode_id_value)` first and then calling `parse`.

#### `parse_with_metadata`

```moonbit
pub fn parse_with_metadata(
  raw : Bytes,
  dialect_id : String,
  profile_id : String,
  exact_release : String,
  feature_introduction : String,
  mode_id_value : String,
) -> Result[ParseResult, ParseError]
```

This entry point first calls `ParseOptions::from_manifest`. `exact_release` and `feature_introduction` must exactly match the metadata built into the profile; otherwise an error is returned before parsing.

### `ParseResult`

```moonbit
pub struct ParseResult {
  pub schema_version : String
  pub source_transport : String
  pub dialect : String
  pub profile : String
  pub exact_release : String
  pub feature_introduction : String
  pub mode : String
  pub valid : Bool
  pub recovered : Bool
  pub source_bytes : Bytes
  pub source_byte_length : Int
  pub root : PrimitiveNode
  pub diagnostics : Array[PrimitiveDiagnostic]
}
```

Current result protocol fields:

- `schema_version`: currently `"fathom.parse.v1"`.
- `source_transport`: currently `"inline-root-v1"`, meaning source bytes are embedded in the result root.
- `dialect`, `profile`, `exact_release`, `feature_introduction`, `mode`: the dialect, profile metadata, and mode actually used for this call.
- `valid`: whether the syntax result is valid. It is usually `false` when syntax, lexical, resource, or profile-feature diagnostics exist; editor recovery does not promote an erroneous result to valid.
- `recovered`: whether the editor recovery path generated a tree that can continue to be consumed.
- `source_bytes`, `source_byte_length`: the original source bytes and their length; comments, whitespace, line breaks, BOM, Unicode, and invalid bytes are retained as raw bytes.
- `root`: the `document` root `PrimitiveNode`.
- `diagnostics`: a structured diagnostic array ordered by source position.

Result methods:

| Method | Return value | Description |
|---|---|---|
| `has_root_only_source()` | `Bool` | Checks that source bytes are stored only once by the root result: `source_byte_length == source_bytes.length()`. |
| `statement(statement_id)` | `PrimitiveNode?` | Gets the statement for a zero-based statement ID; returns `None` when it does not exist. |
| `statement_diagnostics(statement_id)` | `Array[PrimitiveDiagnostic]` | Returns diagnostics for only the specified statement. |
| `all_spans_in_bounds()` | `Bool` | Recursively validates node spans, text lengths, and child ordering. |

### `PrimitiveNode`

```moonbit
pub struct PrimitiveNode {
  pub kind : String
  pub start_byte : Int
  pub end_byte : Int
  pub text_len : Int
  pub children : Array[PrimitiveNode]
}
```

`kind` is a stable string node identifier. The current implementation includes: `document`, `statement`, `select`, `insert`, `update`, `delete`, `merge`, `value_list`, `create_table`, `create_view`, `create_index`, `create_materialized_view`, `column_definition`, `key_clause`, `distribution_clause`, `partition_clause`, `property_list`, `expression`, `token`, `trivia`, `error`, `skipped`, and `missing`.

A `missing` node may have a zero-width span, so it does not fabricate bytes in lossless output; `error` and `skipped` nodes retain material that could not be parsed normally but belongs to the input.

### `PrimitiveDiagnostic`

```moonbit
pub struct PrimitiveDiagnostic {
  pub severity : String
  pub code : String
  pub message : String
  pub expected_class : String
  pub start_byte : Int
  pub end_byte : Int
  pub statement_id : UInt
}
```

`statement_id` is a statement identifier starting at `0U` and increasing in source order within the current input snapshot. It is not a database ID stable across calls; every parse renumbers statements from zero.

### Formatting Entry Points

The `api` facade re-exports formatter type aliases, so `FormatOptions`, `FormatResult`, `FormatDiagnostic`, `FormatError`, `KeywordCase`, `CommaStyle`, and `NewlineStyle` can be used from `@api`.

```moonbit
pub fn format_text(
  raw : Bytes,
  parse_options : ParseOptions,
  format_options : FormatOptions,
) -> Result[FormatResult, ParseError]

pub fn format_with_ids(
  raw : Bytes,
  dialect_id : String,
  profile_id : String,
  mode_id_value : String,
  format_options : FormatOptions,
) -> Result[FormatResult, ParseError]

pub fn format_with_metadata(
  raw : Bytes,
  dialect_id : String,
  profile_id : String,
  exact_release : String,
  feature_introduction : String,
  mode_id_value : String,
  format_options : FormatOptions,
) -> Result[FormatResult, ParseError]
```

Formatting entry points use the same parsing flow first, so parse-level `ParseError` is returned directly. Parse diagnostics are carried into `FormatResult.diagnostics`; if the CST contains `error`, `missing`, or `skipped` material, the formatter refuses partial output and returns `accepted = false` with an empty `output`.

`FormatOptions::default()`:

| Field | Default |
|---|---|
| `keyword_case` | `KeywordCase::Upper` |
| `indent` | `2` |
| `line_width` | `100` |
| `comma_style` | `CommaStyle::Trailing` |
| `newline_style` | `NewlineStyle::FollowInput` |
| `trailing_newline` | `true` |

`FormatOptions::new` rejects negative `indent` and non-positive `line_width`. String enum converters accept `KeywordCase::from_id("upper"/"lower")`, `CommaStyle::from_id("trailing"/"leading")`, and `NewlineStyle::from_id("follow"/"lf"/"crlf")`; unknown IDs return `None`.

```moonbit
pub(all) struct FormatResult {
  pub accepted : Bool
  pub output : Bytes
  pub diagnostics : Array[FormatDiagnostic]
  pub statement_offsets : Array[Int]
}
```

`statement_offsets` records the output byte offset where each statement's layout begins, in statement order. The inter-statement separator newline is part of the following statement's layout, so for statement N (N≥1) the recorded offset points at the separator byte (the end of statement N−1); statement 0's offset is the document start. When formatting is refused, both output and offsets are empty.

### Lint Entry Points

`fathom/sql/lint` is an independent library (D-01) that consumes only the syntax read views, the dialect keyword classification, and optionally an analyzer `AnalysisResult`. It is NOT part of the syntax-validity path. The `api` facade re-exports the lint types (`LintOptions`, `LintResult`, `LintFinding`, `LintEdit`, `LintDiagnostic`, `RuleOverride`, `LintSeverity`, `RuleSetting`) so they can be used from `@api`.

```moonbit
pub fn lint_text(raw : Bytes, parse_options : ParseOptions, lint_options : LintOptions) -> Result[LintResult, ParseError]

pub fn fix_text(raw : Bytes, parse_options : ParseOptions, lint_options : LintOptions) -> Result[LintResult, ParseError]
```

`lint_text` runs the configured rule set over a parsed document and returns the findings sorted by source order. `fix_text` applies safe lossless autofixes as minimal span edits; on a tree containing error/missing/skipped material it refuses (D-33) with `accepted=false`, empty output, and exactly one `FATHOM-LINT-000` diagnostic — never partial edits.

```moonbit
pub(all) struct LintOptions { overrides : Array[RuleOverride] }
pub(all) enum LintSeverity { Error, Warning, Info }
pub(all) enum RuleSetting { Disabled, Severity(LintSeverity) }
pub(all) struct RuleOverride { code : String, setting : RuleSetting }

pub(all) struct LintFinding {
  pub code : String
  pub severity : String        // "error" | "warning" | "info"
  pub message : String
  pub start_byte : Int
  pub end_byte : Int
  pub statement_id : UInt
  pub fix : LintEdit?          // candidate edit for fixable rules
}

pub(all) struct LintResult {
  pub accepted : Bool
  pub findings : Array[LintFinding]
  pub output : Bytes           // fixed source in fix mode, empty on refusal
  pub diagnostics : Array[LintDiagnostic]  // FATHOM-LINT-000 refusal, otherwise empty
}
```

`LintOptions::new` validates every override against the registry; an unknown rule code is a structured error (the CLI maps it to exit 2). `LintSeverity::from_id` accepts `"error"`/`"warning"`/`"info"` and returns `None` otherwise.

#### Rule registry (stable codes)

| Code | Name | Category | Default severity | Fixable |
|---|---|---|---|---|
| `FATHOM-LINT-001` | `unquoted-reserved-word` | style | warning | yes (backtick-quote) |
| `FATHOM-LINT-002` | `version-gated-syntax` | advisory | info | no |
| `FATHOM-LINT-003` | `select-star-without-limit` | safety | warning | no |
| `FATHOM-LINT-004` | `unknown-table` | correctness | error | no |
| `FATHOM-LINT-005` | `unknown-column` | correctness | error | no |
| `FATHOM-LINT-006` | `ambiguous-reference` | correctness | warning | no |
| `FATHOM-LINT-007` | `function-arity` | correctness | error | no |
| `FATHOM-LINT-008` | `deprecated-syntax` | deprecation | info | no |

Rules 004–007 are analyzer-enhanced: they only fire when a caller injects an `AnalysisResult` (i.e. provides a catalog). Without a catalog they are silently skipped (ANLY-01) — the wire and CLI surfaces (which have no catalog) therefore run only rules 001/002/003/008 and never fabricate semantic findings (Pitfall 6).

**Refusal code:** `FATHOM-LINT-000` is reserved for the engine-level autofix refusal (D-33): a tree containing error/missing/skipped material yields `accepted=false`, empty output, and exactly one `FATHOM-LINT-000` diagnostic — mirroring `FATHOM-FORMAT-001` for the formatter.

### Fingerprint Entry Points

`fathom/sql/fingerprint` is an independent library (D-01) that normalizes a parsed CST to a canonical byte form and hashes it with a local FNV-1a 64-bit implementation. The `api` facade exposes:

```moonbit
pub(all) struct FingerprintResult {
  pub fingerprint : UInt64
  pub normalized : Bytes
}

pub fn fingerprint_text(raw : Bytes, parse_options : ParseOptions) -> Result[FingerprintResult, ParseError]
```

Normalization folds only syntactic trivia (D-06): whitespace collapses to a single space, keyword case is ASCII-lowered via the dialect classification table, and comments are dropped. Identifier spelling and case, literal content, and quote style are **preserved** — two queries that differ only in those are guaranteed different fingerprints.

The fingerprint is stable across whitespace, keyword case, and comment changes, and is a **UInt64** (fixed 64-bit on Native, JS, and linear-Wasm) so the value is identical across all three targets (FING-01 SC4). The wire envelope serializes the fingerprint as a **decimal JSON string** — never a JSON number — to avoid 2^53 precision loss on JS hosts.

> **Non-cryptographic boundary:** FNV-1a is a public non-cryptographic hash. Fingerprints are identifiers for caching / diffing / CI — they are **not** MACs and must never be used for tamper-proofing, authentication, or collision resistance.

### Lineage Entry Points

`fathom/sql/lineage` is an independent library (D-21) that consumes the analyzer’s resolved bindings and the select-model structure to build column-level source→target lineage edges (LINE-01). It is NOT part of the syntax-validity path. The `api` facade re-exports the lineage types (`LineageResult`, `LineageEdge`, `LineageGap`, `StaticCatalog`) so they can be used from `@api`.

```moonbit
pub fn lineage_text(raw : Bytes, parse_options : ParseOptions, catalog : StaticCatalog?) -> Result[LineageResult, ParseError]
```

`lineage_text` parses `raw` under `parse_options`, resolves names through the optional `catalog`, and returns the lineage `edges` plus the honest `gaps`. The optional-catalog semantics follow SC2 (D-05): `Some(catalog)` injects caller-owned metadata so `*`/`table.*` expand to real edges and external views resolve; `None` derives with zero metadata so every unexpanded star/external view reports a `requires-catalog` gap — a gap is never a fabricated edge.

```moonbit
pub(all) struct LineageEdge {
  pub source_name : String
  pub source_resolved_to : String
  pub source_start_byte : Int
  pub source_end_byte : Int
  pub target_name : String
  pub target_start_byte : Int
  pub target_end_byte : Int
}

pub(all) struct LineageGap {
  pub code : String          // "requires-catalog" | "unresolved-reference" | "requires-complete-parse"
  pub message : String
  pub start_byte : Int
  pub end_byte : Int
}

pub(all) struct LineageResult {
  pub edges : Array[LineageEdge]
  pub gaps : Array[LineageGap]
}
```

Lineage edges follow the expression-passthrough model (D-01): every resolved column reference in a projection expression contributes one edge to that output column — `SELECT a + b AS x FROM t` yields `t.a→x` and `t.b→x`. Each edge carries flattened byte spans for its source reference and its target output column (D-01/D-06). Edge/gap ordering is deterministic (document statement order → model branch/CTE order → item order → refs order; star expansion follows catalog column order).

The `gaps` list is strictly separate from `edges` (D-06) — a gap is never a tagged edge:

| Gap code | Meaning |
|---|---|
| `requires-catalog` | A `*`/`table.*` projection or an external view cannot be expanded without catalog column metadata (SC2). |
| `unresolved-reference` | A table/column/function reference could not be resolved. |
| `requires-complete-parse` | The statement contains error/missing material (D-33 refusal philosophy). |

**Dialect gate (D-08):** lineage is **Doris-only** in this phase. A `flink` selection returns the structured `FATHOM-SCHEMA-003` error ("lineage is Doris-only") — never a silent empty result and never a Doris-policy lineage of a flink request.

### Lossless Printing

For exact input replay, use `fathom/sql/printer`:

```moonbit
import {
  "fathom/sql/api" @api,
  "fathom/sql/printer" @printer,
}

let parsed = @api.parse_with_ids(b"-- note\r\nselect 1", "doris", "4.x", "editor")
match parsed {
  Ok(result) => {
    let raw_again = @printer.print_result(result)
    // raw_again is exactly the same as the input bytes
  }
  Err(error) => println(error.to_string())
}
```

The printer also provides `print_transport(ParseResult)` (directly reads `source_bytes` from the root), `print_lossless(SyntaxNode, SourceText)`, and `print_bytes(SyntaxNode, SourceText)`. Printing does not format or modify the CST.

### Optional Name-Resolution API

`fathom/sql/analyzer` is not part of the syntax-validity path. It consumes only `syntax.SyntaxNode`, caller-provided source bytes, and a catalog:

```moonbit
pub(all) struct ColumnInfo {
  name : String
  data_type : String
}

pub(all) struct TableInfo {
  name : String
  columns : Array[ColumnInfo]
}

/// One catalog function signature (D-05): `min_arity` supports arity checks —
/// an argument count below `min_arity` or above `param_types.length()` is a
/// mismatch. Types are opaque strings (D-04).
pub(all) struct FunctionInfo {
  name : String
  param_types : Array[String]
  return_type : String
  min_arity : Int
}

pub(all) enum BindingKind {
  Table
  Column
  Function
  Cte
  Alias
}

/// One resolved name binding. `name` preserves the source spelling (D-03);
/// `resolved_to` is the catalog/scope display name; `data_type` carries the
/// column/function type (D-04) and is empty for Table/Cte/Alias. Spans are
/// flattened byte offsets (D-01/D-06).
pub(all) struct Binding {
  kind : BindingKind
  name : String
  resolved_to : String
  data_type : String
  start_byte : Int
  end_byte : Int
}

/// An analyzer-channel diagnostic (D-04): never enters the syntax-only
/// valid/diagnostic channel (ANLY-01). Codes are stable strings:
/// `unknown-table`, `unknown-column`, `unknown-function`,
/// `ambiguous-reference`, `function-arity`, `requires-complete-parse`.
pub(all) struct AnalysisDiagnostic {
  code : String
  message : String
  start_byte : Int
  end_byte : Int
}

/// The result of analyzing one parsed document (D-06): resolved bindings plus
/// analyzer-channel diagnostics.
pub(all) struct AnalysisResult {
  bindings : Array[Binding]
  diagnostics : Array[AnalysisDiagnostic]
}

pub(open) trait Catalog {
  table(Self, String) -> TableInfo?
  table_in_db(Self, db : String, name : String) -> TableInfo?
  function(Self, String) -> FunctionInfo?
}

pub fn StaticCatalog::new(entries : Array[TableInfo]) -> StaticCatalog
pub fn StaticCatalog::with_db(self : StaticCatalog, db : String, name : String, table : TableInfo) -> StaticCatalog
pub fn StaticCatalog::with_function(self : StaticCatalog, name : String, info : FunctionInfo) -> StaticCatalog
pub fn StaticCatalog::lookup(self : StaticCatalog, name : String) -> TableInfo?
pub fn[T : Catalog] resolve_table_references(
  node : @syntax.SyntaxNode,
  source_bytes : Bytes,
  catalog : T,
) -> Array[String]
pub fn[T : Catalog] analyze(
  node : @syntax.SyntaxNode,
  source_bytes : Bytes,
  catalog : T,
) -> AnalysisResult
```

`resolve_table_references` returns only target table names that exist in the catalog and belong to supported DML/DDL statements; missing table names are omitted, no parser diagnostics are generated, and no type inference or Doris FE execution-semantics analysis is performed. Since Phase 13 (D-03), the supported statement families include the Flink shapes for the same table-level kinds — `INSERT`/`UPSERT INTO` and `INSERT OVERWRITE` (the table name precedes the optional `PARTITION` spec), `UPDATE`, `DELETE`, `CREATE TABLE`, and `CREATE VIEW` — resolved through the same in-place walk with no separate Flink entry point.

`analyze` resolves Doris tables, columns, functions, and scopes against the injected catalog and returns an `AnalysisResult` with flattened byte spans (D-01/D-06): `start_byte`/`end_byte` are plain Ints, never `@source.Span`, so the analyzer package keeps its D-21 import contract (only `fathom/sql/syntax`). Bindings preserve the source spelling plus the catalog display name and a data type (D-03/D-04). Statement coverage follows D-02: SELECT (including CTEs, subqueries, aliases, qualified `db.table.col` references, and catalog-aware star expansion), plus column-level references in DML (`UPDATE ... SET`/`WHERE`, `DELETE ... WHERE`, `INSERT` column lists, `MERGE ... SET`) and the `CREATE VIEW` query body. The view name itself is a target table, not a reference, and is not resolved by `analyze`.

**Case policy (D-03).** Identifier matching is **case-insensitive** — parsing-time ASCII case-fold: catalog keys keep author casing, lookups fold ASCII case, and bindings preserve the source spelling and span. Quoted identifiers (backtick/`"`) match byte-exactly and keep exact case; they are never treated as keywords.

**Type-diagnostic scope (D-04).** Phase 5 (ANAL-01) delivers the name-resolution and type-diagnostic surface above; nothing here is deferred. Analyzer diagnostics live on their own channel and never enter the syntax valid/diagnostic channel (ANLY-01): parsing the same bytes without a catalog yields byte-identical syntax results. The emitted codes are `unknown-table`, `unknown-column`, `unknown-function`, `ambiguous-reference` (an unqualified column matching multiple visible tables), and `function-arity` (argument count outside `[min_arity, param_types.length()]`). There is no expression-level type unification, literal type propagation, or type inference — that is out of scope (ANAL-02). `StaticCatalog` table-name keys match case-insensitively at lookup time (D-03), and duplicate table names are overwritten by the last entry.

## Error Codes and Error Responses

### Call-Level `ParseError`

Call-level failures are returned as `Err(ParseError)` in the `Result`, and usually mean that the input has not entered a consumable parse result:

| Error constructor | Trigger condition |
|---|---|
| `UnknownProfile(profile_id~)` | The profile is not `2.1`, `3.x`, or `4.x`. |
| `UnknownMode(mode_id~)` | The mode is not `strict` or `editor`. |
| `ProfileMetadataMismatch(...)` | The release, profile identity, or feature introduction in the manifest or metadata does not match the built-in profile. |
| `UnsupportedFeatureIntroduction(feature_introduction~)` | The feature-introduction string is not in the currently supported metadata set. |
| `InputTooLarge(requested_bytes~, max_bytes~)` | Input bytes exceed `ParseLimits.max_bytes`. |
| `InvalidLimit(limit_name~, value~)` | Any parse limit is negative. |
| `InvalidSyntaxTree` | The CST generated by the parser failed span, text-length, or child-order invariant checks. |

### Parser Diagnostics in Results

When syntax can produce a `ParseResult`, errors are not returned as network status codes; they are placed in `result.diagnostics` while source bytes and the CST are retained:

| code | Meaning |
|---|---|
| `FATHOM-PARSE-001` | Unexpected trailing material exists at the end of a statement. |
| `FATHOM-PARSE-002` | General syntax error, such as a missing keyword, symbol, expression, identifier, or clause. |
| `FATHOM-PARSE-003` | Invalid source encoding or unterminated lexical material. |
| `FATHOM-PARSE-004` | A parser resource limit was reached, such as the token, recursion, recovery, or diagnostic budget. |
| `FATHOM-PARSE-006` | A Doris feature unsupported by the selected profile, such as `QUALIFY`, `TABLET`, or `MERGE` in an earlier profile. |
| `FATHOM-PARSE-007` | A statement not implemented or unsupported by the selected profile. |

Treat these codes as strings. Diagnostic messages and `expected_class` are for presentation and location; obtain the precise location through `start_byte`/`end_byte` and `statement_id`. Code `FATHOM-PARSE-005` is not currently generated as a public diagnostic by the parser implementation.

### Formatter Diagnostics and Errors

Parse-level failures from formatting entry points still use `ParseError`. When a `FormatResult` can be returned, formatter diagnostics use the same field shape as parser diagnostics:

```moonbit
pub(all) struct FormatDiagnostic {
  pub severity : String
  pub code : String
  pub message : String
  pub expected_class : String
  pub start_byte : Int
  pub end_byte : Int
  pub statement_id : UInt
}
```

The current formatter refusal code is:

| code | Meaning |
|---|---|
| `FATHOM-FORMAT-001` | The CST contains `error`, `missing`, or `skipped` material, so the formatter refuses to generate partial output. |

Direct use of the formatter package’s `FormatError` may also return: `InvalidIndent`, `InvalidLineWidth`, `UnknownKeywordCase`, `UnknownCommaStyle`, `UnknownNewlineStyle`, and `InvalidSyntaxTree`. When using `api.format_text`, construct format options first with valid enums and `FormatOptions::new`; parse-related errors are returned as the `ParseError` described above.

## Wire Exports (JS ESM / linear-Wasm)

The `binding` package (`fathom/sql/binding`) is a `foreign_library` facade exposing the stable primitive wire contract to JavaScript ESM and linear-Wasm hosts. Every export returns UTF-8 JSON `Bytes`; no MoonBit ADT, object handle, or host memory address crosses the boundary. All eight exports are registered in `binding/moon.pkg` `js`/`wasm` `exports` lists AND carry `#export_name` in `binding/exports.mbt` — a missing registration compiles but the built artifact silently lacks the symbol (Pitfall 3/8).

| Export | Signature | Result envelope |
|---|---|---|
| `fathom_parse_v1` | `(raw: Bytes, dialect: String, profile: String, mode: String) -> Bytes` | `fathom.parse.v1` |
| `fathom_format_v1` | `(raw, dialect, profile, mode, keyword_case, indent, line_width, comma_style, newline_style, trailing_newline) -> Bytes` | `fathom.format.v1` |
| `fathom_complete_v1` | `(raw: Bytes, dialect: String, profile: String, cursor_byte: Int) -> Bytes` | `fathom.complete.v1` |
| `fathom_lint_v1` | `(raw: Bytes, dialect: String, profile: String, mode: String, overrides: Bytes, fix: Bool) -> Bytes` | `fathom.lint.v1` |
| `fathom_fingerprint_v1` | `(raw: Bytes, dialect: String, profile: String, mode: String) -> Bytes` | `fathom.fingerprint.v1` |
| `fathom_lineage_v1` | `(raw: Bytes, dialect: String, profile: String, mode: String, catalog_json: Bytes) -> Bytes` | `fathom.lineage.v1` |
| `fathom_dialect_v1` | `(dialect: String) -> Bytes` | `fathom.dialect.v1` (metadata query) |
| `fathom_capabilities_v1` | `() -> Bytes` | `fathom.capabilities.v1` (metadata query) |

The A4 export order places `dialect` immediately after `raw` for the parse/format/complete/lint/fingerprint/lineage primitives, consistent with `ParseOptions::new` and the CLI. The schema v2 bump is **pure addition** (Pitfall V6): `fathom.lint.v1` and `fathom.fingerprint.v1` were added while the original five namespaces (`parse`/`format`/`complete`/`error`/`capabilities`) remain unchanged, so existing consumers are unaffected. `fathom.lineage.v1` is the 8th namespace (07-04) — the same pure addition: it appends while all seven prior namespaces keep their branches untouched.

`fathom_lineage_v1` takes a UTF-8 JSON `catalog_json` argument (D-05): empty bytes or `{}` means no catalog — every `*`/external view reports a `requires-catalog` gap (SC2); a malformed or shape-invalid catalog is a structured `fathom.error.v1` error with `FATHOM-SCHEMA-004` (never a silent fallback to the no-catalog behavior). Lineage is Doris-only this phase (D-08): a `flink` selection returns the structured `FATHOM-SCHEMA-003` error envelope with the explicit "lineage is Doris-only" message — never a silent empty result.

`fathom_lint_v1` takes a UTF-8 JSON `overrides` array of `{"code": "<FATHOM-LINT-0xx>", "setting": "off|error|warning|info"}` objects; `[]` or empty bytes is the default registry. Malformed JSON or an unknown code/severity is a structured `fathom.error.v1` error (never a silent fallback). With `fix=false` it reports findings; with `fix=true` it applies safe autofixes (a D-33 refusal yields `accepted=false` with exactly one `FATHOM-LINT-000`). `fathom_fingerprint_v1` returns the `fathom.fingerprint.v1` envelope whose `fingerprint` field is a **decimal JSON string** (never a number — 2^53 precision) and whose `normalized` field carries the canonical bytes.

### Completion envelope (`fathom.complete.v1`)

`fathom_complete_v1` returns bounded syntax completion candidates for an editor snapshot at a UTF-8 byte `cursor_byte`. The result envelope carries the same `dialect`/`profile` selection metadata as the parse/format envelopes plus the completion items:

```json
{
  "schema_version": "fathom.complete.v1",
  "source_transport": "inline-root-v1",
  "dialect": "flink",
  "profile": "flink-2.3.0",
  "is_incomplete": false,
  "items": [
    {
      "label": "FROM",
      "detail": "SQL syntax keyword",
      "start_byte": 7,
      "end_byte": 9,
      "new_text": "FROM"
    }
  ]
}
```

- `start_byte`/`end_byte` are half-open UTF-8 byte offsets; the replacement range `[start_byte, end_byte)` covers the typed prefix and `end_byte` equals the cursor byte.
- Item text is dialect-neutral (D-10/D-28): the `detail` is always `"SQL syntax keyword"` and no dialect name appears in item content — the dialect rides in the envelope metadata.
- Completion is bounded to `MAX_CANDIDATES = 32` items.

Completion error responses use the `fathom.error.v1` envelope:

| Code | Condition |
|---|---|
| `FATHOM-SCHEMA-003` | Unknown/unsupported `profile` (e.g. a Doris profile under `flink`). |
| `FATHOM-SCHEMA-007` | Unknown `dialect`. |
| `FATHOM-COMPLETE-001` | `cursor_byte` is outside `[0, raw.length()]` (`InvalidCursor`). |
| `FATHOM-COMPLETE-002` | Invalid source input. |
| `FATHOM-COMPLETE-003` | Input exceeds the 8 MiB source limit. |

## Rate Limits

There are no HTTP rate limits, connection quotas, or server-side windows. Fathom is a pure library, so callers decide concurrency and lifecycle.

To prevent a single untrusted input from consuming unlimited resources, the parser provides a **per-call resource budget**, not a network rate limit: `max_bytes`, `max_tokens`, `max_recursion_depth`, `max_recovery_steps`, and `max_diagnostics`. These must be non-negative integers. When a budget is exceeded, bounded error/skipped material is retained and `FATHOM-PARSE-004` is generated, rather than waiting for an external service or silently discarding source bytes.

## Complete Example

```moonbit
import {
  "fathom/sql/api" @api,
  "fathom/sql/formatter" @formatter,
  "fathom/sql/printer" @printer,
}

fn main {
  let raw = b"select id, name from users"
  let options = match @api.ParseOptions::new("doris", "4.x", "strict") {
    Ok(value) => value
    Err(error) => panic()
  }
  let parsed = match @api.parse(raw, options) {
    Ok(value) => value
    Err(error) => panic()
  }
  println(parsed.valid.to_string())
  println(parsed.diagnostics.length().to_string())

  let formatted = @api.format_text(
    raw,
    options,
    @formatter.FormatOptions::default(),
  )
  match formatted {
    Ok(result) if result.accepted => {
      println(result.output.to_string())
      assert_eq(@printer.print_result(parsed), raw)
    }
    Ok(result) => println(result.diagnostics[0].code)
    Err(error) => println(error.to_string())
  }
}
```

This example shows how the same source bytes first produce a diagnostic-bearing `ParseResult` and then a formatted result; exact replay of the original input is performed with `printer.print_result`, not by reading the formatted output.
