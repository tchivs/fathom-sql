<!-- GSD:generated -->
English | [简体中文](zh-CN/CONFIGURATION.md)
# Configuration

Fathom is a Doris SQL parsing and formatting library implemented in MoonBit. It has no runtime service configuration or environment variables; configuration is passed explicitly through MoonBit module manifests and parsing, recovery, and formatting options in the `api` package.

## Environment Variables

The repository contains no `.env`, `.env.example`, or `.env.sample` files, and no reads of `process.env`, `os.environ`, `os.getenv`, `std::env::var`, or similar environment-variable APIs were found. The runtime library does not depend on environment variables, so there are no environment variables to set.

| Variable | Required | Default | Description |
|---|---|---|---|
| None | — | — | The parser and formatter are configured through API parameters. |

## Configuration File Format

The project uses MoonBit DSL manifests and does not use additional JSON, YAML, TOML, or deployment-platform configuration files.

### `moon.mod`

The root `moon.mod` defines the module identity and default build target:

```moonbit
name = "fathom/sql"
version = "1.0.4"
preferred_target = "native"
```

The current manifest also records a MoonBit toolchain policy comment: the project is maintained against the official MoonBit v0.10.5 documentation line and records the version information `moon 0.1.20260724 (5f1406a 2026-07-24)`. When modifying the toolchain, update the version record in this manifest and run build checks in the target environment.

### `moon.pkg`

Each MoonBit package declares its package type and dependency direction through the `moon.pkg` in the same directory. The root package and the `api/`, `analyzer/`, `formatter/`, `lexer/`, `parser/`, `printer/`, `source/`, `syntax/`, and `token/` packages are all library packages; `test/` declares the package imports required for tests through its `moon.pkg`. Package manifests do not accept environment-variable overrides; modify dependencies directly in the corresponding `moon.pkg`.

The root package's minimal configuration is:

```moonbit
pkgtype(kind: "library")
```

`preferred_target = "native"` in `moon.mod` only sets the default target; it does not restrict explicit selection of other supported MoonBit backends.

## Parsing Configuration

The parsing API is located in `api/api.mbt`. `api.parse` accepts raw `Bytes` and `ParseOptions`; `api.parse_with_ids` and `api.parse_with_metadata` provide string-ID entry points. Parsing configuration is scoped to each call and is not written to global state.

### Required Parsing Settings

Every `ParseOptions` construction must explicitly specify a dialect, a Doris profile, and parsing mode:

- **Dialect**: Only `doris` or `flink` are allowed; an unknown value returns `ParseError::UnknownDialect`. The Flink release profiles are pinned (Phase 10) and accepted for every toolchain surface.
- **Profile**: A profile is valid only under its own dialect — `doris` accepts `2.1`, `3.x`, or `4.x`; `flink` accepts `flink-2.3.0`, `flink-2.1.3`, or `flink-1.20.5`. An unknown or cross-dialect value returns `ParseError::UnknownProfile` and does not fall back to a generic dialect.
- **Mode**: Only `strict` or `editor` are allowed; an unknown value returns `ParseError::UnknownMode`.
- **Manifest metadata (optional entry point)**: When using `from_manifest`, `exact_release` and `feature_introduction` must exactly match the built-in metadata for the selected profile; otherwise, `ProfileMetadataMismatch` is returned. An unsupported feature introduction returns `UnsupportedFeatureIntroduction`.

The built-in metadata for the released profiles is:

| Profile ID | `exact_release` | `feature_introduction` |
|---|---|---|
| `2.1` | `2.1` | `2.1 baseline SELECT; DML/DDL released` |
| `3.x` | `3.x` | `2.1 baseline SELECT; DML/DDL released; 3.x window and QUALIFY` |
| `4.x` | `4.x` | `2.1 baseline SELECT; DML/DDL released; 4.x released SELECT` |
| `flink-2.3.0` | `flink-2.3.0` | `primary profile` |
| `flink-2.1.3` | `flink-2.1.3` | `flink-2.1.3 regression profile` |
| `flink-1.20.5` | `flink-1.20.5` | `flink-1.20.5 regression profile` |

Example:

```moonbit
let options = match @api.ParseOptions::new("doris", "4.x", "editor") {
  Ok(value) => value
  Err(error) => panic()
}
let result = @api.parse(b"SELECT * FROM orders", options)
```

### Resource Limits

`ParseLimits::default()` obtains the following default values from `parser.ParserLimits::default()`. To isolate untrusted or large inputs, pass custom limits through `ParseOptions::for_profile_with_limits`.

| Setting | Default | Purpose |
|---|---:|---|
| `max_bytes` | `8 * 1024 * 1024` (8 MiB) | Maximum byte length of the raw input; exceeding it returns `InputTooLarge`. |
| `max_tokens` | `1_000_000` | Maximum number of tokens allowed in a single parse. |
| `max_recursion_depth` | `128` | Maximum recursion depth for recursive descent and expression parsing. |
| `max_recovery_steps` | `10_000` | Maximum number of steps permitted for error recovery in Editor mode. |
| `max_diagnostics` | `100` | Maximum number of diagnostics retained for a single parse. |

All custom limits must be non-negative integers. `api.parse` and `api.format_text` validate the limits before beginning to process input; a negative value returns `ParseError::InvalidLimit` and is not silently corrected. Input whose byte length exceeds `max_bytes` returns `ParseError::InputTooLarge`.

## Formatting Settings

Formatting configuration is provided by `FormatOptions` in `formatter/options.mbt` and is used through `api.format_text`, `api.format_with_ids`, or `api.format_with_metadata`. The defaults of `FormatOptions::default()` are:

| Setting | Default | Allowed values or constraints |
|---|---|---|
| `keyword_case` | `Upper` | `Upper`, `Lower`; string IDs are `upper`, `lower`. |
| `indent` | `2` | A non-negative integer representing the number of indentation spaces. |
| `line_width` | `100` | A positive integer representing the target line width. |
| `comma_style` | `Trailing` | `Trailing`, `Leading`; string IDs are `trailing`, `leading`. |
| `newline_style` | `FollowInput` | `FollowInput`, `Lf`, `Crlf`; string IDs are `follow`, `lf`, `crlf`. |
| `trailing_newline` | `true` | Whether to retain a newline at the end of the output. |

`FormatOptions::new` rejects a negative `indent` (`InvalidIndent`) and a non-positive `line_width` (`InvalidLineWidth`) during construction. Unknown string enum IDs should be mapped to the corresponding enum by the caller; `KeywordCase::from_id`, `CommaStyle::from_id`, and `NewlineStyle::from_id` return `None` for unknown IDs.

Example:

```moonbit
let parse_options = match @api.ParseOptions::new("doris", "3.x", "strict") {
  Ok(value) => value
  Err(error) => panic()
}
let format_options = @formatter.FormatOptions::default()
let formatted = @api.format_text(b"select id, name from users", parse_options, format_options)
```

When the formatter encounters a syntax tree containing `error`, `missing`, or `skipped` material, it rejects the output and returns `accepted = false`, empty output, and a `FATHOM-FORMAT-001` diagnostic. This behavior cannot be disabled through environment variables.

## Required and Optional Settings

Fathom is a library rather than a resident application that requires startup configuration, so no setting causes the process to fail to start because configuration is missing. Required settings exist only at the API-call boundary:

1. Parsing and formatting must select a valid dialect, profile, and mode (no implicit fallback).
2. When using the manifest entry point, release and feature-introduction metadata must match the profile.
3. When custom `ParseLimits` are provided, all limits must be non-negative.
4. When custom `FormatOptions` are provided, `indent` must be non-negative and `line_width` must be greater than zero.

When custom limits or formatting options are not provided, the defaults listed above are used respectively. The parser does not infer a profile from the input or load configuration from external directories, databases, or Doris FE.

## Per-Environment Overrides

The repository contains no `.env.development`, `.env.production`, or `.env.test` files, and no `NODE_ENV` conditional branches or other environment-configuration loaders. Development, test, and release environments use the same source code and MoonBit manifests; differences should be supplied explicitly by the caller through `ParseOptions`, `ParseLimits`, and `FormatOptions`, or by explicitly selecting a target through the build command.

For example, an editor scenario can select `editor` mode and lower resource limits, while a batch scenario can select `strict` mode and use the default limits; these are call parameters, not environment-variable overrides.

## Editor Host and CLI Dialect/Profile Selection

The SDK ships editor hosts (VS Code, IntelliJ) and a Web demo that select a dialect and a released profile per workspace/session, exactly like the `api` package: an explicit `(dialect, profile)` pair with no implicit fallback. The host constants mirror the server's authoritative validation (`binding.validate_dialect_profile` / LSP `validate_selection`); a missing, unknown, or cross-dialect pair is an explicit configuration error, never a coerced default.

### Valid (dialect, profile) Pairs

| Dialect | Profiles |
|---|---|
| `doris` | `2.1`, `3.x`, `4.x` |
| `flink` | `flink-2.3.0`, `flink-2.1.3`, `flink-1.20.5` |

A profile is valid only under its own dialect: `flink` + `2.1` and `doris` + `flink-2.3.0` are both rejected. The server remains authoritative — a host that accepts a pair the server rejects is a server-side error, never a silent fallback.

### Per-Host Selection

| Host | Selection surface | Example flink selection |
|---|---|---|
| VS Code | `fathom.dialect` + `fathom.profile` settings (plus `fathom.serverPath` for the local `fathom-lsp` executable) | `fathom.dialect: "flink"`, `fathom.profile: "flink-2.3.0"` |
| IntelliJ | `FathomSettings` application settings — dialect and profile dropdowns; the profile list repopulates to the selected dialect's values | Dialect `flink`, profile `flink-2.3.0` |
| Web demo | `#dialect` and `#profile` selectors; the profile selector repopulates on dialect change | Dialect `flink`, profile `flink-2.3.0` |
| CLI | `fathom-sql parse|format|lsp --dialect <d> --profile <p>` | `--dialect flink --profile flink-2.3.0` |

The Web/VS Code/IntelliJ hosts keep static per-dialect profile maps (offline-first, PARITY-03); they never pull profiles dynamically and never share a cross-host JSON definition.

### Per-File LSP Override

In addition to the workspace/session default above, the LSP honors a per-file override through the `didOpen`/`didChange` extension fields `dialect` and `profile`. The precedence is document > workspace/session. No automatic detection and no file-extension guessing is performed — a flink file must carry the flink selection explicitly.

## Configuration-Related Files

| File | Purpose |
|---|---|
| `moon.mod` | Module name, version, and default target. |
| `moon.pkg` | Root package type. |
| `api/api.mbt` | `ParseOptions`, `ParseLimits`, parsing entry points, and formatting entry points. |
| `parser/parser.mbt` | Parsing resource limits, their defaults, and validation logic. |
| `formatter/options.mbt` | Formatting enums, `FormatOptions` defaults, and validation. |
| `moon.pkg` in each package directory | Package type and imports between packages. |
