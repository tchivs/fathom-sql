# Phase 1: Core Kernel — Research

**Researched:** 2026-08-03  
**Domain:** MoonBit lossless Doris SQL parser kernel  
**Confidence:** MEDIUM-HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Use canonical UTF-8 byte offsets over an immutable source snapshot; derive line/column and LSP UTF-16 positions through one centralized `LineIndex` adapter — **Reversibility:** one-way — published span semantics and later LSP/foreign consumers depend on this coordinate contract.
- **D-02:** Expose versioned serialized results with primitive fields and byte spans; keep UTF-16 conversion at LSP/host adapters rather than in the parser core — **Reversibility:** costly — changing the wire schema would touch Native, JavaScript, Wasm, and later editor clients.
- **D-03:** Use one lossless CST shape with two explicit result modes: strict mode reports invalidity without accepting it, while editor mode preserves a usable tree with explicit missing/error/skipped nodes and the same diagnostics model — **Reversibility:** costly — parser callers and fixtures must distinguish validity from recoverability without maintaining two parsers.
- **D-04:** Require parser progress or an explicit error node; synchronize at clause and statement boundaries, preserve unknown/error text, and cap recovery work and diagnostic volume — **Reversibility:** reversible — recovery points can be refined while preserving the strict/editor contract.
- **D-05:** Make the immutable lossless CST the source of truth; typed semantic-less AST views may project from it and retain backreferences, while the optional analyzer remains a separate package — **Reversibility:** one-way — an AST-first public contract would make the project's lossless editing promise fragile or impossible to restore.
- **D-06:** Use immutable source-backed token/trivia leaves and immutable node structure; every node carries span/text length, and explicit ERROR, skipped, and missing nodes remain printable without copying the entire source into every node.
- **D-07:** Treat released official Doris documentation as the public grammar contract for explicit 2.1, 3.x, and 4.x profiles. Use FE/Nereids and SQLGlot only for differential investigation; current/dev documentation is discovery input, not silently accepted grammar — **Reversibility:** costly — compatibility reports and fixture provenance depend on this authority policy.
- **D-08:** Require versioned golden fixtures, byte-exact lossless replay checks, malformed/recovery cases, and keyword/context boundaries from the first grammar slice. Record FE/SQLGlot differential results as advisory evidence, not as a substitute for the public corpus.

### Claude's Discretion

- Parser function decomposition, event/builder mechanics, concrete MoonBit data structures, and performance optimizations remain open to the planner as long as the coordinate, CST, recovery, version, and validation contracts above are preserved.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within the Phase 1 boundary. DML/DDL breadth, corpus expansion, configurable formatting, CLI, LSP, Wasm/JavaScript packaging, lint, lineage, and fingerprinting remain in their roadmap phases or v2 scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CORE-01 | Consumer can select an explicit Doris version profile (2.1, 3.x, or 4.x) when parsing SQL, and the parser never silently falls back to a generic MySQL dialect. | Use a required `DorisProfile` input and version-gated keyword/production tables; released 2.1/3.x/4.x docs are the authority and current/dev is explicitly unreleased. |
| CORE-02 | Consumer can traverse a lossless CST that retains source bytes, token spelling, comments, whitespace, newlines, trivia, and source spans for every parsed fragment. | Use immutable source-backed leaves, ordered trivia, byte spans, and a CST builder isolated from recursive-descent parser functions. |
| CORE-03 | Consumer can replay an unchanged parsed document byte-for-byte, including comments, casing, quoting, whitespace, newline style, unknown text, and error material. | Make `print_lossless(parse(input)) == input` a byte-level invariant; unknown/error/skipped leaves are retained and missing nodes are zero-width. |
| CORE-04 | User can parse documented Doris SELECT statements and expressions covering joins, subqueries, CTEs, windows, predicates, functions, set operations, grouping sets/ROLLUP/CUBE, hints, and Doris-specific SELECT clauses. | Official SELECT pages for 2.1, 3.x, and 4.x document the clause order, hints, partition/tablet/sample clauses, grouping extensions, joins, UNION, and WITH; use recursive descent plus Pratt expressions. |
| CORE-05 | Consumer receives machine-readable diagnostics containing severity, stable code, message, expected syntax class, source span, and statement identity. | Define a versioned diagnostic record alongside `ParseResult`; keep diagnostics separate from CST while attaching statement identity and byte spans. |
| CORE-06 | Editor can parse incomplete or malformed SQL into a bounded recoverable CST with explicit missing/error/skipped nodes while retaining diagnostics for invalid syntax. | Use strict/editor modes over one CST, progress-or-error invariants, layered synchronization, zero-width missing tokens, retained skipped text, and explicit resource caps. |
| CORE-07 | Application can use the parser core offline without starting Doris FE, a database connection, or a runtime-specific parser implementation. | Keep source, lexer, parser, CST, diagnostics, and exact replay pure and synchronous; put I/O, catalog analysis, and target adapters outside the core. |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- `你始终回复中文` (always respond in Chinese). This is the only actionable directive in `.claude/CLAUDE.md` [VERIFIED: .claude/CLAUDE.md:1-2].
- The repository is greenfield with no application source, package manifest, or parser implementation [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:59-71].
- The implementation must use one MoonBit core for Native and Wasm/JavaScript, preserve source trivia/spans, use handwritten recursive descent plus Pratt expressions, use official Doris documentation as the coverage authority, and keep parser/analyzer separate [VERIFIED: .claude/CLAUDE.md:13-20].
- This document is research only: create no source code, UI specification, plan, or unrelated artifact [VERIFIED: user assignment; phase boundary is also stated in .planning/phases/01-core-kernel/01-CONTEXT.md:6-10].

## Summary

Phase 1 should establish a pure, backend-neutral MoonBit kernel whose public result is a lossless immutable CST plus structured diagnostics. The source snapshot and canonical UTF-8 byte spans are upstream of lexing, parsing, recovery, replay, and all later host adapters; therefore `SourceText`, `Span`, and `LineIndex` must be designed before grammar breadth. [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:16-30; .planning/research/ARCHITECTURE.md:50-69]

Use a trivia-preserving handwritten lexer, recursive descent for statements and clauses, and one Pratt expression parser with explicit precedence. Build one CST in both strict and editor modes. Strict mode must report invalidity; editor mode may produce a usable tree, but both modes must share token ownership, diagnostics, spans, and exact replay. [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:20-26; .planning/research/ARCHITECTURE.md:154-172]

The public grammar contract is not “whatever MySQL or the current FE accepts.” Require a selected Doris 2.1, 3.x, or 4.x profile, freeze fixture provenance to released official documentation, and use FE/Nereids or SQLGlot only to investigate disagreements. The official 2.1, 3.x, and 4.x SELECT pages expose a common industrial shape—hints, projection modifiers, FROM partition/tablet/sample options, predicates, grouping extensions, HAVING, ORDER BY, LIMIT, joins, UNION, and WITH—while the current/dev site explicitly says it is unreleased. [CITED: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-query/SELECT/; https://doris.apache.org/docs/3.x/sql-manual/sql-statements/data-query/SELECT/; https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/; https://doris.apache.org/docs/dev/getting-started/what-is-apache-doris/]

**Primary recommendation:** Create a small `doris-sql` MoonBit module with `source`, `token`, `lexer`, `syntax`, `parser`, `api`, and test/corpus packages; lock byte-based source ownership, explicit profiles, bounded recovery, and exact replay before adding more grammar. [VERIFIED: .planning/research/ARCHITECTURE.md:71-102; [ASSUMED] package names are a prescriptive layout for this greenfield repository]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Immutable UTF-8 source snapshot, byte spans, and line index | API / Backend (pure core) | — | Every lexer token, CST leaf, and diagnostic needs one canonical source coordinate model; host coordinate conversion is downstream. [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:16-18; .planning/research/ARCHITECTURE.md:50-69] |
| Trivia-preserving lexical classification | API / Backend (pure core) | — | Comments, whitespace, newlines, literals, unknown text, and contextual keyword candidates must survive parsing and replay. [VERIFIED: .planning/research/ARCHITECTURE.md:52-57] |
| SELECT/clause and Pratt expression parsing | API / Backend (pure core) | — | Syntax parsing must work offline and without catalog/FE access; this is the Phase 1 vertical slice. [VERIFIED: .planning/ROADMAP.md:16-25; .planning/REQUIREMENTS.md:12-18] |
| Lossless CST and strict/editor result modes | API / Backend (pure core) | — | The CST is the source of truth and both result modes must share one tree shape. [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:20-26] |
| Diagnostics and recovery budgets | API / Backend (pure core) | — | Machine-readable syntax diagnostics and bounded recovery are parser contracts, not transport behavior. [VERIFIED: .planning/REQUIREMENTS.md:16-18; .planning/research/PITFALLS.md:141-169] |
| Versioned Doris grammar metadata and golden fixtures | Database / Storage (Git fixtures) | API / Backend | Versioned docs and fixtures are persisted source-of-truth inputs for grammar gates; they are not runtime database state. [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:28-30; .planning/research/STACK.md:95-105] |
| Serialized primitive result boundary | API / Backend | Browser / Client, Frontend Server | Phase 1 defines the schema contract for later Native/JS/Wasm adapters; internal MoonBit ADTs must not become the foreign ABI. [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:16-18; https://docs.moonbitlang.com/en/latest/language/ffi.html] |
| LSP UTF-16 coordinate conversion | Browser / Client or Frontend Server adapter | API / Backend `LineIndex` | LSP positions belong at the host boundary; the core publishes byte spans and the later adapter converts them. [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:16-18; https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/] |
| Doris semantic analysis | API / Backend optional package | Database / Storage catalog | Analyzer is explicitly outside parser ownership and may consume catalog metadata later; Phase 1 must not require it. [VERIFIED: .claude/CLAUDE.md:19; .planning/REQUIREMENTS.md:34-36] |

## Standard Stack

### Core

| Technology | Version / evidence | Purpose | Recommendation |
|------------|--------------------|---------|----------------|
| MoonBit `moon`/`moonc` | Official docs page is titled MoonBit v0.10.5; local executable reports `moon 0.1.20260724 (5f1406a 2026-07-24)` [VERIFIED: https://docs.moonbitlang.com/en/latest/; environment probe 2026-08-03] | One implementation and build/test toolchain | Pin the exact executable revision in CI and record `moon version`; resolve the local/docs version mismatch before implementation commits. |
| `moon.mod` and `moon.pkg` | New DSL documented in v0.10.5; JSON forms are deprecated since v0.10.4 [CITED: https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html; https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html] | Module and package metadata | Use only the new DSL in the greenfield module; do not create `moon.mod.json` or `moon.pkg.json`. |
| `moonbitlang/core` | Standard-library package documented by MoonBit; an observed registry version is `0.1.20260728+5e7afb0c0` [VERIFIED: https://docs.moonbitlang.com/en/latest/; .planning/research/STACK.md:14-18] | Bytes, arrays, strings, options, and basic immutable data | Keep it as the only mandatory runtime dependency; verify package legitimacy and the exact lock entry before adding it to `moon.mod`. |
| Handwritten lexer + recursive descent + Pratt | Locked project decision, no external version [VERIFIED: .claude/CLAUDE.md:17; .planning/phases/01-core-kernel/01-CONTEXT.md:32-34] | Doris tokenization, clauses, expressions, and recovery | Implement locally; do not introduce a parser-generator runtime in Phase 1. |

### Supporting

| Technology | Version / evidence | Purpose | When to use |
|------------|--------------------|---------|-------------|
| MoonBit inline tests and `_wbtest.mbt`/`_test.mbt` | MoonBit v0.10.5 test docs [CITED: https://docs.moonbitlang.com/en/latest/language/tests.html] | Kernel invariants, white-box parser tests, public API tests | Create tests with the module-root path assumption and keep fixture loading deterministic. |
| MoonBit snapshots | `moon test --update`, `debug_inspect`, JSON snapshots, and `@test.T::snapshot` are documented [CITED: https://docs.moonbitlang.com/en/latest/language/tests.html] | CST/diagnostic golden views and whole-process output | Snapshot normalized structure and diagnostics, but always pair snapshots with byte-exact replay assertions. |
| Git-tracked official-Doris fixture manifest | Project contract, not an external library [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:28-30; .planning/REQUIREMENTS.md:27-32] | Version/category/provenance accounting | Every fixture records release family, URL, source revision/retrieval date, category, and expected status. |
| LSP 3.17 schema as a later adapter baseline | Official specification [CITED: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/] | Later lifecycle, synchronization, diagnostics, and UTF-16 host mapping | Do not build LSP in Phase 1; only preserve byte spans and revision-aware APIs needed by the later adapter. |

### Installation and toolchain setup

Use the official project bootstrap and pinning workflow. `moon new <PATH>` creates a module and package files, and `moon.mod`/`moon.pkg` are the current configuration formats [CITED: https://docs.moonbitlang.com/en/latest/toolchain/moon/package-manage-tour.html; https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html; https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html]. The planner should create the module manually or with `moon new .`, then remove any irrelevant template files; no source exists today [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:59-71].

```bash
moon version                         # record exact output in CI
moon new .                            # only if the empty repository needs bootstrap
moon check --target native            # core smoke check
moon build --target native --release  # release smoke check
moon test                             # focused tests after implementation
```

The commands and target values `wasm`, `wasm-gc`, `js`, `native`, `llvm`, and `all` are documented by MoonBit; Phase 1 should at least keep the core backend-neutral and run the native check, while cross-target parity belongs to the later ecosystem phase [CITED: https://docs.moonbitlang.com/en/latest/toolchain/moon/commands.html].

### Alternatives considered

The following are explicitly rejected for Phase 1 rather than open alternatives: generated parser runtimes, AST-only SQL libraries, silent MySQL fallback, runtime Doris FE, and a separate parser per backend. These choices are locked by D-01–D-08 and the project constraints; FE/Nereids and SQLGlot may only provide advisory differential evidence [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:16-30; .claude/CLAUDE.md:13-20].

## Architecture Patterns

### System architecture diagram

```text
selected DorisProfile + UTF-8 bytes
                |
                v
      immutable SourceText + LineIndex
                |
                v
 trivia-preserving lexer
 (raw lexemes, comments, whitespace, unknown/error tokens)
                |
                v
 recursive-descent statements/clauses + Pratt expressions
                |                         |
                |                         +--> structured diagnostics
                v
 immutable lossless CST
 (tokens/trivia, byte spans, text lengths, ERROR/skipped/missing)
                |
        +-------+--------+
        |                |
        v                v
 exact lossless      optional semantic-less
 replay              typed CST/AST view
                             |
                             v
                  later optional analyzer/catalog

released Doris docs --> versioned fixtures --> strict/editor golden gates
```

This data flow keeps the parser core pure and synchronous; file I/O, JSON-RPC, catalog access, and target-specific serialization belong above it [VERIFIED: .planning/research/ARCHITECTURE.md:42-63]. The official LSP 3.17 specification is consulted only at the later protocol edge, while its position model reinforces the need not to confuse host coordinates with internal byte spans [CITED: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/].

### Recommended project structure

The repository has no existing source tree or manifest, so the planner should create this one-way dependency layout [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:59-71; .planning/research/ARCHITECTURE.md:71-102]. Directory/package names below are recommendations for this greenfield project [ASSUMED].

```text
moon.mod
moon.pkg
source/
├── moon.pkg                 # SourceText, Span, LineIndex, revision/edit primitives
└── source.mbt
 token/
├── moon.pkg                 # TokenKind, keyword/profile tables, Token, TokenStream
└── token.mbt
lexer/
├── moon.pkg                 # trivia-preserving scanner
└── lexer.mbt
syntax/
├── moon.pkg                 # immutable CST, SyntaxKind, leaves/cursors
└── syntax.mbt
parser/
├── moon.pkg                 # recursive descent, Pratt, recovery, ParseResult
└── parser.mbt
api/
├── moon.pkg                 # versioned primitive result schema and public parse entry point
└── api.mbt
printer/
├── moon.pkg                 # exact replay only in this phase; canonical formatting later
└── printer.mbt
test/
├── moon.pkg                 # focused unit/property/snapshot test support
├── source_test.mbt
├── lexer_test.mbt
├── parser_test.mbt
└── recovery_test.mbt
corpus/
├── doris-2.1/               # released official-document fixtures
├── doris-3.x/
└── doris-4.x/
```

Keep dependency direction `source -> token -> lexer/parser -> syntax -> api/printer`; parser must not import analyzer, FE, filesystem, network, or host-specific packages [VERIFIED: .planning/research/ARCHITECTURE.md:102-103; .claude/CLAUDE.md:19]. A later CLI/LSP/bindings layout belongs to later phases and should not be created now [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:6-10,85-88].

### Pattern 1: Source-backed immutable CST

**What:** Store one immutable source snapshot and represent token/trivia leaves by source spans; keep synthetic missing tokens zero-width and retain unknown/error/skipped source ranges. Every node stores its text length/span without copying the full source [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:24-26; .planning/research/ARCHITECTURE.md:65-69].

**When to use:** Always, including malformed/editor input. Exact replay walks leaves in source order and therefore does not normalize bytes [VERIFIED: .planning/research/ARCHITECTURE.md:104-131].

**Example (project design, MoonBit-like pseudocode):**

```moonbit
struct Span {
  start_byte : Int
  end_byte : Int
}

enum LeafText {
  SourceSlice(Span)
  Synthetic(String)
}

struct Token {
  kind : TokenKind
  text : LeafText
  span : Span
}

struct GreenNode {
  kind : SyntaxKind
  children : Array[GreenChild]
  text_len : Int
}
```

The exact MoonBit representation, ownership, interning, and cursor API remain planner discretion; the non-negotiable behavior is immutable source-backed ownership and byte-complete replay [ASSUMED implementation sketch; locked behavior verified by D-05/D-06].

### Pattern 2: Centralized coordinates

**What:** `SourceText` owns immutable UTF-8 bytes; `LineIndex` records line starts and converts byte offsets to line/column. UTF-16 conversion is a host/LSP adapter operation, never a second parser coordinate system [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:16-18; .planning/research/ARCHITECTURE.md:65-69].

**When to use:** Every diagnostic, token, CST node, edit, and future serialized result. Do not let callers perform ad-hoc UTF-8/UTF-16 math [VERIFIED: .planning/research/PITFALLS.md:109-137].

**Required invariants:** spans are half-open byte intervals; `0 <= start <= end <= source.byte_length`; source slicing by a span returns exactly the original bytes; line index conversion round-trips valid boundaries; later host conversion receives the document revision [ASSUMED contract details to lock in tests].

### Pattern 3: Handwritten recursive descent plus Pratt expressions

**What:** Use explicit functions for document/statement/SELECT/CTE/FROM/JOIN/GROUP/HAVING/ORDER/LIMIT regions and one precedence table for prefix, infix, postfix, predicate, and dialect-specific operators [VERIFIED: .claude/CLAUDE.md:17; .planning/research/ARCHITECTURE.md:204-210].

**When to use:** The Phase 1 industrial SELECT slice. The official SELECT grammar places clauses in a strict order and documents joins, UNION, and WITH, so each clause should have a synchronization set and a version gate [CITED: https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-query/SELECT/; https://doris.apache.org/docs/3.x/sql-manual/sql-statements/data-query/SELECT/; https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/].

```text
parse_document
  -> parse_statement_list
     -> parse_with_clause (optional)
     -> parse_select
        -> parse_hints / projection modifier / select list
        -> parse_from + table references + joins
        -> parse_where
        -> parse_group_by + grouping sets/rollup/cube
        -> parse_having
        -> parse_order_by
        -> parse_limit / into outfile
     -> parse_set_operation (UNION [ALL|DISTINCT] ...)

parse_expression(min_precedence)
  -> prefix operand
  -> repeatedly consume an operator whose precedence >= min_precedence
  -> parse RHS with associativity-adjusted threshold
```

### Pattern 4: Progress-or-error and layered recovery

Every parser routine must either consume input, return a valid node, or emit an explicit error node while advancing. Synchronize expressions at delimiters, clauses at known clause keywords, and statements at semicolon/EOF; preserve skipped bytes. Missing expected tokens are synthetic zero-width nodes, not source text [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:20-22; .planning/research/ARCHITECTURE.md:165-172].

Strict mode returns `valid = false` for invalid input and does not silently promote a recovered result to valid. Editor mode returns the same CST shape with explicit `ERROR`, `SKIPPED`, and `MISSING` nodes and the same diagnostic record types [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:20-22]. Resource caps must stop pathological recovery rather than dropping source or looping [VERIFIED: .planning/research/PITFALLS.md:141-169].

### Pattern 5: CST-first derived views and serialized boundary

Typed semantic-less views may provide ergonomic access to SELECT fields and expressions, but each view retains a CST node/span backreference. The analyzer remains a separate package with an optional catalog interface [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:24-26; .planning/REQUIREMENTS.md:34-36].

The serialized API should expose primitive fields only: profile identifier, validity/recovery status, byte spans, node kind identifiers, trivia/source slices or a source reference, diagnostics, and stable schema version. MoonBit's FFI documentation states that types not listed in its ABI tables do not have stable representation, and its package docs scope exports to the producing package; therefore do not export internal CST structs/ADTs as a foreign ABI [CITED: https://docs.moonbitlang.com/en/latest/language/ffi.html; https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html].

## Don't Hand-Roll

| Problem | Don't build | Use instead | Why |
|---------|-------------|-------------|-----|
| Cross-backend source coordinate semantics | Separate byte/line/UTF-16 calculations in each consumer | One `LineIndex` over canonical UTF-8 bytes [VERIFIED: D-01; .planning/research/ARCHITECTURE.md:65-69] | Independent conversions drift on CJK, surrogate pairs, CRLF, and edits. |
| Lossless source retention | AST-only nodes plus a side-channel comment list | Immutable source-backed token/trivia leaves and CST [VERIFIED: D-05/D-06] | A side channel cannot reliably own repeated whitespace, unknown text, error material, and exact ordering. |
| SQL expression precedence | Ad-hoc recursive conditionals per operator | One Pratt precedence/associativity table [VERIFIED: .claude/CLAUDE.md:17; .planning/research/ARCHITECTURE.md:204-210] | Duplicated precedence rules create inconsistent nesting and recovery. |
| Error recovery | Regex scanning, “skip until semicolon” only, or exception abort | Layered synchronization with explicit error/skipped/missing nodes [VERIFIED: D-04; .planning/research/ARCHITECTURE.md:165-172] | Statement-only recovery loses clause locality and can swallow later statements. |
| Doris compatibility oracle | Runtime Doris FE or generic MySQL acceptance | Released official 2.1/3.x/4.x fixture manifest; FE/SQLGlot only advisory [VERIFIED: D-07/D-08] | Runtime coupling breaks offline use and current/dev acceptance pollutes version promises. |
| Foreign ABI | Exporting MoonBit ADTs/structs directly | Thin primitive/serialized wrappers later [CITED: https://docs.moonbitlang.com/en/latest/language/ffi.html] | Unlisted MoonBit types do not have a stable ABI. |
| Test confidence | Snapshot-only or parse-success-only checks | Byte equality, token/trivia/span invariants, diagnostics, strict/editor negatives, and version fixtures [VERIFIED: D-08; .planning/research/PITFALLS.md:205-233] | A single snapshot can lock in a lossy or falsely accepting parser. |

**Key insight:** Phase 1 is a source-fidelity and trust boundary, not merely a grammar exercise. Any shortcut that discards bytes or conflates recovered structure with valid syntax forces later formatter/LSP/API rewrites [VERIFIED: .planning/ROADMAP.md:67-72; .planning/research/SUMMARY.md:84-93].

## Common Pitfalls

### Pitfall 1: Current/dev grammar silently enters released profiles

**What goes wrong:** A current-only syntax is accepted under 2.1, 3.x, or 4.x, or the same fixture changes with the moving docs site. [VERIFIED: .planning/research/PITFALLS.md:13-41]

**How to avoid:** Require profile selection at every parse entry point; tag every keyword/production/fixture with release family and status; treat the dev site as discovery only. The official overview explicitly labels dev/current documentation unreleased and links released 2.1, 3.x, and 4.x docs [CITED: https://doris.apache.org/docs/dev/getting-started/what-is-apache-doris/].

**Warning signs:** No profile field in `ParseOptions`, fixture URLs without a version path, or acceptance changing after a docs refresh [VERIFIED: .planning/research/PITFALLS.md:30-35].

### Pitfall 2: MySQL keyword table replaces Doris contextual rules

**What goes wrong:** Valid identifiers are rejected or unknown Doris syntax is accepted as a generic identifier [VERIFIED: .planning/research/PITFALLS.md:45-73]. Doris describes its SQL interface as MySQL-protocol-compatible and ANSI SQL syntax, but that statement is not a complete versioned keyword contract [CITED: https://doris.apache.org/docs/dev/getting-started/what-is-apache-doris/].

**How to avoid:** Keep raw spelling and candidate token in the lexer; apply profile/context classification in parser positions; test each important word as keyword, unquoted identifier, quoted identifier, function name, alias, and property key [VERIFIED: .planning/research/PITFALLS.md:55-60].

### Pitfall 3: Official examples are mistaken for executable, version-neutral SQL

**What goes wrong:** Shell prompts, output, placeholders, setup statements, and examples requiring catalog/session context contaminate goldens [VERIFIED: .planning/research/PITFALLS.md:77-105].

**How to avoid:** Record URL, source revision, heading, code fence language, line range, release family, category, and expected support status. Separate `parse-only`, `requires-session`, `requires-catalog`, `executable`, `expected-error`, and `not-sql` [VERIFIED: .planning/research/PITFALLS.md:87-92].

### Pitfall 4: Trivia is retained nominally but replay loses bytes

**What goes wrong:** Comments, CRLF/BOM, non-ASCII text, unknown tokens, string escapes, or EOF trivia disappear or spans drift [VERIFIED: .planning/research/PITFALLS.md:109-137].

**How to avoid:** Make the source snapshot authoritative, include every lexer output in the CST, preserve raw spans, and assert `print_lossless(parse(x)) == x` byte-for-byte across empty input, mixed newline input, non-ASCII comments/identifiers, quoted literals, and malformed text [VERIFIED: D-06/D-08; .planning/research/ARCHITECTURE.md:104-131].

### Pitfall 5: Recovery cascades or loops

**What goes wrong:** A missing delimiter or operand causes an infinite loop, stack overflow, diagnostic explosion, or loss of later statements [VERIFIED: .planning/research/PITFALLS.md:141-169].

**How to avoid:** Enforce progress-or-error per routine, bound recursion/recovery/diagnostic counts, define clause and statement synchronization sets, and retain skipped text. Fuzz prefixes such as `SELECT`, `SELECT 1,`, open parentheses, unterminated strings/comments, and malformed CTEs [VERIFIED: .planning/research/PITFALLS.md:151-167].

### Pitfall 6: Recovered trees are treated as valid semantic trees

**What goes wrong:** Formatter/analyzer code guesses through missing/error nodes and silently changes or validates malformed SQL [VERIFIED: D-03/D-04; .planning/research/ARCHITECTURE.md:165-172].

**How to avoid:** Carry explicit validity/recovery status; keep syntax diagnostics separate from optional semantic diagnostics; make Phase 1 exact replay safe for error trees but defer canonical formatting to Phase 3 [VERIFIED: .planning/ROADMAP.md:42-52; .planning/REQUIREMENTS.md:40-43].

### Pitfall 7: Golden updates hide regressions

**What goes wrong:** Bulk snapshot updates accept dropped trivia, changed spans, false acceptance, or version drift [VERIFIED: .planning/research/PITFALLS.md:205-233].

**How to avoid:** Layer oracles: bytes first, then token/trivia/span, CST shape, diagnostics, strict/editor status, and version acceptance. Require reviewed fixture provenance and never update snapshots without inspecting the diff [VERIFIED: D-08; .planning/research/STACK.md:83-93].

### Pitfall 8: Foreign/host ABI leaks into the kernel

**What goes wrong:** Native behavior differs from JS/Wasm or wrappers depend on unstable MoonBit object representations [VERIFIED: .planning/research/PITFALLS.md:237-265].

**How to avoid:** Phase 1 keeps the parser pure; define only a serialized primitive contract and postpone backend wrappers. MoonBit documents five backends and warns that unlisted types have no stable ABI [CITED: https://docs.moonbitlang.com/en/latest/language/ffi.html].

### Pitfall 9: Byte, line, and UTF-16 coordinates are mixed

**What goes wrong:** Diagnostics and later LSP edits land at the wrong location for Unicode or CRLF input [VERIFIED: .planning/research/PITFALLS.md:269-297].

**How to avoid:** Keep byte spans in the core and centralize all conversion in `LineIndex`/host adapters. The LSP 3.17 specification is the later protocol contract, not a reason to store UTF-16 columns in CST nodes [CITED: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/; VERIFIED: D-01/D-02].

## Code Examples

### MoonBit module and package configuration

The official module docs define the current `moon.mod` DSL and the package docs define `pkgtype`; use these exact forms as the starting shape, replacing placeholder metadata with the project’s chosen module name [CITED: https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html; https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html].

```moonbit
// moon.mod
name = "yourname/doris-sql"
version = "0.1.0"
preferred_target = "native"
```

```moonbit
// moon.pkg
pkgtype(kind: "library")
```

`yourname/doris-sql` and `0.1.0` are placeholders, not locked project values [ASSUMED]. Do not use the deprecated JSON configuration formats [CITED: https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html; https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html].

### MoonBit test block

MoonBit’s official test documentation supports inline test blocks and identifies `moon test` as the runner [CITED: https://docs.moonbitlang.com/en/latest/language/tests.html].

```moonbit
test "lossless_replay" {
  let source = "SELECT /* keep */ 1\r\n"
  let result = @api.parse(source, profile=DorisProfile::V4, mode=ParseMode::Strict)
  assert_eq(@printer.print_lossless(result.document), source)
}
```

The function and enum names are the proposed Phase 1 API, not existing code [ASSUMED]; the observable contract is locked by CORE-03 and D-03/D-08 [VERIFIED: .planning/REQUIREMENTS.md:14-18; .planning/phases/01-core-kernel/01-CONTEXT.md:20-30].

### Public primitive result shape

```text
ParseOptions {
  profile: "doris-2.1" | "doris-3.x" | "doris-4.x"
  mode: "strict" | "editor"
  limits: { max_bytes, max_tokens, max_depth, max_diagnostics, max_recovery_steps }
}

ParseResult {
  schema_version: Int
  profile: String
  valid: Bool
  recovered: Bool
  source_byte_length: Int
  root: { kind: String, start_byte: Int, end_byte: Int, text_len: Int, children: [...] }
  diagnostics: [{ severity, code, message, expected_class, start_byte, end_byte, statement_id }]
}
```

This is a planning skeleton, not a frozen wire schema [ASSUMED]. It deliberately uses primitive fields and byte spans in accordance with D-02; final field names and enum encodings require a focused API review before Phase 4 wrappers [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:16-18].

### Parser progress skeleton

```text
parse_one(rule, sync_set):
  start = cursor.position
  node = rule()
  if cursor.position == start:
    if cursor.at_end() or cursor.in(sync_set):
      return MissingOrError(rule.expected_kind)
    skipped = cursor.consume_one()
    return ErrorNode(skipped)
  return node
```

This skeleton expresses the required progress-or-error invariant and must be adapted to MoonBit’s concrete builder and diagnostics types [ASSUMED; required behavior verified by D-04 and .planning/research/PITFALLS.md:151-156].

### Exact replay invariant

```text
for every fixture source:
  parsed = parse(source, profile, mode)
  replayed = print_lossless(parsed.document)
  assert bytes(replayed) == bytes(source)
```

Run this for valid examples, unknown text, incomplete input, and malformed input; missing nodes must be zero-width so they never manufacture bytes [VERIFIED: D-03/D-04/D-06/D-08; .planning/research/ARCHITECTURE.md:131].

## Environment Availability

The required local probes were run on 2026-08-03. MoonBit is installed, but its executable version differs from the v0.10.5 documentation title; the planner must pin and reconcile this before relying on syntax/toolchain behavior [VERIFIED: environment probes; https://docs.moonbitlang.com/en/latest/].

| Dependency | Required by | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| MoonBit `moon` | Module creation, check, build, tests | Yes | `moon 0.1.20260724 (5f1406a 2026-07-24)` | No fallback for implementation; pin/upgrade the toolchain. |
| MoonBit documentation | Toolchain/package/API research | Yes | Page title v0.10.5 | Re-read official docs when the pinned compiler changes. |
| Git | Fixture provenance and required research commit | Yes | `git version 2.47.3` | None needed. |
| Node.js | Not required by Phase 1 core | Yes | `v25.2.0` | Do not add Node runtime dependency. |
| npm | Not required by Phase 1 core | Yes | `11.6.2` | Do not add npm package dependency. |
| Doris FE/database | Explicitly not required | Not probed/needed | — | Offline parser must remain usable without it. |

No package manifest or tests exist yet, so the plan needs a Wave 0 module/package/test scaffold before implementation [VERIFIED: .planning/phases/01-core-kernel/01-CONTEXT.md:59-71]. Nyquist validation is explicitly disabled in `.planning/config.json`, so this research intentionally omits a Validation Architecture section [VERIFIED: .planning/config.json:20-29].

## Security Domain

OWASP describes ASVS as a basis for testing technical security controls and secure development [CITED: https://owasp.org/www-project-application-security-verification-standard/]. The project config enables security enforcement at ASVS level 1 [VERIFIED: .planning/config.json:47-50]. A parser accepts untrusted SQL text, so Phase 1 must treat resource exhaustion and output safety as security requirements even though it does not execute SQL [ASSUMED engineering application of ASVS to this parser].

### Applicable ASVS categories

| ASVS category | Applies | Phase 1 control |
|---------------|---------|-----------------|
| V2 Authentication | No for pure parser core | No credentials or user sessions in core; keep auth outside parser adapters [ASSUMED]. |
| V3 Session Management | No for pure parser core | No session state; document revisions are parser input metadata, not authentication [ASSUMED]. |
| V4 Access Control | Limited | No filesystem/network/catalog access from parser core; adapters enforce caller policy [ASSUMED]. |
| V5 Input Validation | Yes | Validate UTF-8/byte length, profile identifier, mode, edits, and serialized input before lexing; reject or explicitly preserve invalid bytes rather than executing them [ASSUMED; resource concern supported by .planning/research/PITFALLS.md:109-124]. |
| V6 Cryptography | No | Do not invent cryptography; Phase 1 has no secrets or cryptographic operation [ASSUMED]. |

### Resource and abuse limits

Implement a configurable `ParseLimits` object with finite defaults and a hard stop path that retains the unconsumed source as an error/skipped node while emitting one stable resource diagnostic [ASSUMED recommendation]. Recommended initial values for a first benchmark pass are `max_bytes = 8 MiB`, `max_tokens = 2,000,000`, `max_recursion_depth = 256`, `max_recovery_steps = 100,000`, and `max_diagnostics = 1,000`; treat these as starting hypotheses, not public compatibility commitments [ASSUMED].

Required controls:

1. Check input size before allocation and avoid copying the entire source into every token/node [ASSUMED; D-06 requires source-backed leaves].
2. Bound lexer loops for unterminated strings/comments and ensure every recovery branch advances or terminates [VERIFIED: D-04; .planning/research/PITFALLS.md:141-167].
3. Bound parser recursion, recovery steps, and diagnostic count; after a cap, preserve the remaining byte range in one `SKIPPED`/`ERROR` node and stop [ASSUMED implementation policy].
4. Never execute SQL, access a database, invoke Doris FE, read arbitrary files, or load network resources from the core [VERIFIED: CORE-07; .claude/CLAUDE.md:19].
5. Bound serialized output and avoid exposing internal object identity or pointers across a future FFI boundary [CITED: https://docs.moonbitlang.com/en/latest/language/ffi.html].
6. Add adversarial fixtures for deeply nested parentheses, long identifiers/literals, repeated malformed operators, huge comments, invalid UTF-8 input representation, and many independent statements [ASSUMED test recommendations].

### Known threat patterns

| Pattern | STRIDE | Mitigation |
|---------|--------|------------|
| Deep nesting causes stack exhaustion | Denial of Service | Explicit recursion depth and iterative recovery; return bounded diagnostic [ASSUMED]. |
| Repeated malformed tokens cause recovery loop | Denial of Service | Progress invariant plus recovery-step cap [VERIFIED: D-04; .planning/research/PITFALLS.md:151-156]. |
| Huge input creates memory blow-up | Denial of Service | Pre-parse byte cap, source-backed leaves, output cap [ASSUMED]. |
| Untrusted SQL reaches execution or filesystem | Tampering / Elevation | Pure syntax-only core; no FE, DB, file, or network imports [VERIFIED: CORE-07]. |
| Byte/UTF-16 confusion corrupts later edits | Tampering | Canonical byte spans and one centralized adapter [VERIFIED: D-01/D-02; LSP 3.17 specification]. |

## State of the Art

| Older approach | Phase 1 approach | Impact |
|---------------|------------------|--------|
| Normalize SQL directly into an AST | Preserve immutable lossless CST, then project typed semantic-less views | Exact replay, comments, unknown text, and diagnostics remain possible [VERIFIED: D-05/D-06; .planning/research/ARCHITECTURE.md:7-12]. |
| Treat malformed SQL as parser failure | One CST with strict and editor modes plus explicit recovery nodes | Editors can inspect incomplete input without making recovery equal validity [VERIFIED: D-03/D-04]. |
| Use current/dev docs as “latest truth” | Released 2.1/3.x/4.x profile fixtures; dev is discovery only | Version compatibility claims become reproducible [CITED: https://doris.apache.org/docs/dev/getting-started/what-is-apache-doris/]. |
| Publish internal runtime objects | Primitive serialized result boundary | Later Native/JS/Wasm clients avoid unstable MoonBit ABI [CITED: https://docs.moonbitlang.com/en/latest/language/ffi.html]. |
| Put UTF-16 positions in parser nodes | Byte spans internally, UTF-16 only at host adapters | One coordinate contract supports exact source slicing and future LSP [VERIFIED: D-01/D-02; https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/]. |

## Assumptions Log

| # | Assumed claim | Section | Risk if wrong |
|---|---------------|---------|---------------|
| A1 | The recommended package names (`source`, `token`, `lexer`, `syntax`, `parser`, `api`, `printer`) are the best initial MoonBit layout. | Architecture Patterns | Planner may need to rename packages before implementation; dependency direction must remain. |
| A2 | The illustrative MoonBit struct/enum syntax and proposed API names compile after adaptation. | Code Examples | The planner must type-check the actual MoonBit syntax before adopting it. |
| A3 | Half-open byte spans, the listed serialized fields, and the proposed primitive encodings are suitable defaults. | Code Examples | A schema change would affect future adapters; freeze only after a focused design review. |
| A4 | The initial resource values (8 MiB, 2,000,000 tokens, depth 256, 100,000 recovery steps, 1,000 diagnostics) are suitable starting points. | Security Domain | Poor limits could reject legitimate SQL or fail to stop abuse; benchmark and tune before public API freeze. |
| A5 | Applying ASVS input-validation/DoS thinking to an offline parser is appropriate even though the core has no web authentication/session surface. | Security Domain | Security review may refine category mapping while preserving resource controls. |
| A6 | The repository should use `yourname/doris-sql` and version `0.1.0` as placeholders only. | Code Examples | Actual module identity must be chosen before creating `moon.mod`. |
| A7 | Exact SELECT clause support can be implemented uniformly across the three released profile families until a fixture demonstrates a version-specific difference. | Summary / Architecture | Version gates may require finer 2.1/3.x/4.x production metadata. |

## Open Questions (RESOLVED)

1. **Q1 — Which exact MoonBit compiler revision is the Phase 1 pin?**
   - **RESOLVED:** Pin the official MoonBit v0.10.5 toolchain line. Record the exact `moon version` output in CI and release metadata for every reproducible artifact; never use floating `latest`. If `moon` is absent locally, make the pinned-toolchain prerequisite explicit and use the official installer/setup path without inventing a package dependency.
   - **Rationale:** The official documentation line is v0.10.5, while the observed local executable is a separate environment fact. Reproducibility requires recording the executable output rather than silently accepting either a moving channel or an unrecorded local binary.

2. **Q2 — What exact Doris profile granularity is needed inside `3.x` and `4.x`?**
   - **RESOLVED:** The public profiles are exactly `2.1`, `3.x`, and `4.x`. Fixtures carry exact source release/minor metadata, and feature-introduction metadata is retained so minor-release distinctions remain auditable. Unsupported or version-invalid syntax is rejected with a version-aware diagnostic rather than silently accepted. Phase 1 implements only its documented SELECT slice; DML/DDL is out of scope.
   - **Rationale:** This satisfies the public CORE-01 profile contract while preserving enough release/minor provenance to prevent current/dev or family-level assumptions from widening acceptance.

3. **Q3 — How should invalid UTF-8 be represented at the public boundary?**
   - **RESOLVED:** The public core accepts raw UTF-8 bytes. Valid UTF-8 is decoded for lexical classification; invalid byte runs are preserved as source-backed `ERROR`/unknown tokens with a stable encoding diagnostic, and lossless replay emits the original bytes exactly. Text wrappers may reject or diagnose invalid UTF-8, but they must not reinterpret the bytes.
   - **Rationale:** Byte offsets and exact replay remain well-defined for every input, including malformed encoding, without replacing, normalizing, or losing caller-owned bytes.

4. **Q4 — Which diagnostic code namespace and statement identity scheme are stable?**
   - **RESOLVED:** Diagnostic codes use the stable string namespace `DORIS-PARSE-###`, reserving three decimal digits for the initial catalog. Every parse result carries a zero-based monotonic `statement_id: u32` per parse snapshot. Code, span, and statement identity are stable in serialized output.
   - **Rationale:** A documented string namespace leaves room for a durable catalog, while snapshot-local monotonic identities are deterministic, compact, and independent of mutable node addresses or parser execution order.

5. **Q5 — Should the serialized CST include source slices or only spans plus the original source?**
   - **RESOLVED:** Serialized parse results carry the original source bytes exactly once at the result root, together with span-based nodes and trivia. Nodes never duplicate the source payload. Host adapters may retain the input and omit the duplicate root payload only through an explicitly versioned transport option; they must never make node spans unusable.
   - **Rationale:** One root payload preserves standalone replay and makes source-backed spans usable without per-node copies; an explicitly versioned host optimization cannot silently change the core wire contract.
 
 ## Sources

### Primary (HIGH confidence)

- [MoonBit documentation home](https://docs.moonbitlang.com/en/latest/) — v0.10.5 title, Native/JavaScript/Wasm/Wasm-GC targets, and mixed-backend modules.
- [MoonBit module configuration](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html) — `moon.mod`, imports, preferred targets, and deprecation of JSON configuration.
- [MoonBit package configuration](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html) — `moon.pkg`, package kinds, test imports, and `#export_name`/ABI boundaries.
- [MoonBit command reference](https://docs.moonbitlang.com/en/latest/toolchain/moon/commands.html) — `moon new`, `check`, `build`, `test`, target values, and version command.
- [MoonBit tests](https://docs.moonbitlang.com/en/latest/language/tests.html) — inline, white-box, black-box, and snapshot tests.
- [MoonBit FFI](https://docs.moonbitlang.com/en/latest/language/ffi.html) — backend list, host dependencies, primitive ABI tables, and unstable unlisted types.
- [MoonBit package tour](https://docs.moonbitlang.com/en/latest/toolchain/moon/package-manage-tour.html) — greenfield module/package layout and `moon new` workflow.
- [MoonBit WebAssembly integration](https://docs.moonbitlang.com/en/latest/toolchain/wasm/index.html) — custom export/import boundary and host portability warning.
- [Apache Doris 2.1 SELECT](https://doris.apache.org/docs/2.1/sql-manual/sql-statements/data-query/SELECT/) — released 2.1 SELECT grammar and examples.
- [Apache Doris 3.x SELECT](https://doris.apache.org/docs/3.x/sql-manual/sql-statements/data-query/SELECT/) — released 3.x SELECT grammar and examples.
- [Apache Doris 4.x SELECT](https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/) — 4.x SELECT grammar and examples, with page metadata identifying the version tree.
- [Apache Doris current overview](https://doris.apache.org/docs/dev/getting-started/what-is-apache-doris/) — explicit unreleased warning and links to 2.1/3.x/4.x documentation.
- [Language Server Protocol 3.17 specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/) — protocol baseline, lifecycle, synchronization, and positions for the later adapter.
- [OWASP ASVS project](https://owasp.org/www-project-application-security-verification-standard/) — purpose as a security-control verification basis.

### Local project evidence (read this session)

- `.planning/phases/01-core-kernel/01-CONTEXT.md` — locked D-01 through D-08, phase boundary, greenfield status, and deferred scope.
- `.planning/REQUIREMENTS.md` — exact CORE-01 through CORE-07 acceptance requirements.
- `.planning/PROJECT.md`, `.planning/ROADMAP.md`, `.planning/STATE.md` — core value, phase goal, ordering, and current planning position.
- `.planning/research/SUMMARY.md` — consolidated phase implications and confidence notes.
- `.planning/research/STACK.md` — MoonBit version/toolchain evidence, package layout, FFI constraints, test patterns, and Doris source policy.
- `.planning/research/ARCHITECTURE.md` — source/lexer/parser/CST boundaries, recovery patterns, and recommended structure.
- `.planning/research/PITFALLS.md` — version drift, keyword, lossless, recovery, snapshot, ABI, and coordinate risks.
- `.planning/research/FEATURES.md` — SELECT table stakes and explicit anti-features.
- `.claude/CLAUDE.md` and `.planning/config.json` — project instruction and workflow/security settings.

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH for official MoonBit capabilities and command/configuration concepts; MEDIUM for the exact installed compiler pin because local `moon version` differs from the docs title.
- Architecture: HIGH for the locked source/CST/parser/recovery boundaries; MEDIUM for exact MoonBit package names and serialized fields because this is a greenfield design.
- Doris grammar: HIGH for the documented SELECT clause shapes and unreleased-dev warning; MEDIUM for fine-grained 2.1/3.x/4.x differences because a full versioned corpus is not yet created.
- Security/resource limits: MEDIUM-LOW; controls are prescriptive engineering recommendations and initial limits, not verified Doris or MoonBit requirements.

**Research date:** 2026-08-03  
**Valid until:** 2026-08-10 for MoonBit toolchain details and current Doris documentation; stable architectural decisions remain useful longer, but must be rechecked when the pinned compiler or released Doris corpus changes.
