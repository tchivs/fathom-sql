# Architecture Research

**Domain:** Lossless Apache Doris SQL concrete-syntax-tree (CST) parser SDK and language-tooling adapters
**Researched:** 2026-08-03
**Confidence:** HIGH for the CST/parser boundaries; MEDIUM for MoonBit backend packaging details because the toolchain is evolving

## Standard Architecture

### System Overview

The proposed five-layer architecture is sound. The important refinement is that the CST is the source-of-truth syntax model, while a typed AST is a derived, semantic-less view or lowering product—not a replacement for the CST. This is the same separation documented by rust-analyzer: a lossless syntax layer, a parser that produces it, and a higher-level AST API; Roslyn independently documents immutable full-fidelity trees containing nodes, tokens, trivia, spans, and recoverable errors.

```
┌────────────────────────────────────────────────────────────────────┐
│ Application and analysis adapters                                  │
│ Native CLI │ LSP document store │ Wasm/JS API │ optional Analyzer  │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ stable, backend-neutral API
┌──────────────────────────────▼─────────────────────────────────────┐
│ Printer                                                            │
│ exact round-trip printer │ configurable formatter │ edit utilities │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ CST + formatting options
┌──────────────────────────────▼─────────────────────────────────────┐
│ CST / typed syntax views                                           │
│ immutable lossless tree │ tokens/trivia │ spans │ ERROR/missing     │
│ semantic-less typed AST views and optional lowering                │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ parser events / green-tree builder
┌──────────────────────────────▼─────────────────────────────────────┐
│ Handwritten parser                                                │
│ recursive descent for statements/clauses │ Pratt for expressions  │
│ diagnostics │ local recovery │ statement-level synchronization    │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ Token {kind, raw text, span}
┌──────────────────────────────▼─────────────────────────────────────┐
│ Trivia-preserving lexer                                            │
│ comments │ whitespace │ newlines │ literals │ contextual keywords  │
│ unknown/error tokens │ byte spans and line-index input             │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ immutable SourceText snapshot
┌──────────────────────────────▼─────────────────────────────────────┐
│ Input and platform boundary                                        │
│ UTF-8 bytes/text │ versioned edit ranges │ Native/Wasm/JS wrappers  │
└────────────────────────────────────────────────────────────────────┘
```

The core packages must remain pure and synchronous: source snapshot → lexed tokens → CST/diagnostics → optional typed views → printer output. CLI file I/O, LSP JSON-RPC, JavaScript object conversion, and catalog/network access belong above the core. The architecture therefore preserves the user's central choices without introducing a parser generator or a Doris FE dependency.

### Component Responsibilities

| Component | Responsibility | Boundary/API | Typical implementation |
|-----------|----------------|--------------|------------------------|
| `SourceText` / `LineIndex` | Own one immutable UTF-8 source snapshot, byte length, line starts, and version | `SourceId`, `Span { start_byte, end_byte }`, offset conversion | Immutable bytes plus a line-start index; expose UTF-8 byte spans internally and UTF-16 conversion only in LSP |
| Lexer | Classify all source characters, including comments/whitespace/newlines and unknown input, without discarding raw spelling | `lex(SourceText) -> TokenStream` | Handwritten state machine; contextual keyword classification; raw lexeme and span retained for every token |
| Parser | Recognize Doris statements, clauses, and expressions; build syntax events/tree; emit diagnostics and recovery nodes | `parse(TokenStream, ParseOptions) -> ParseResult` | Recursive descent for statement/DDL/DML productions; Pratt parser and explicit precedence table for expressions |
| CST core | Preserve exact token order/trivia/spans and represent incomplete or invalid input | `Document { source, root, diagnostics }`; immutable node/token traversal | Green tree (structural value) plus red/cursor views; `ERROR` and missing-token nodes; typed CST views by kind |
| AST/lowering views | Offer ergonomic semantic-less constructs without losing CST backreferences | `lower(root) -> AstView` or typed node wrappers with `span/node_id` | Lazy typed wrappers where possible; explicit lowering for normalized expressions or analyzer input |
| Analyzer (optional) | Resolve names/types only when a caller supplies catalog/context; never gate syntax parsing | `analyze(ast, Catalog) -> SemanticDiagnostics` | Separate package and cache keyed by document/version/catalog snapshot; no catalog means parser still works |
| Printer | Concatenate exact source for round-trip; format using CST-aware edits while retaining trivia and unknown/error content | `print_exact(document)` and `format(document, options)` | Exact mode is a leaf/token walk; format mode is deterministic CST traversal, not AST string reconstruction |
| CLI | Read/write files and expose parse/format/diagnostic commands | Process exit codes and stdout/stderr | Thin Native executable adapter around the public core |
| LSP | Maintain documents, apply text edits, publish diagnostics, later provide completion/hover/formatting | LSP 3.17 JSON-RPC types and UTF-16 positions | Document store over immutable snapshots; parser first, analyzer only for features requiring catalog/context |
| Wasm/JS SDK | Expose a small serializable API for browser/Monaco use | Explicit handles or JSON-friendly diagnostics/ranges; no backend-specific tree internals | Foreign-library wrapper with stable exported names; keep source/CST ownership in the core |

#### Source spans and text ownership

Use UTF-8 byte offsets (or a newtyped equivalent) as the canonical internal coordinate. Keep a `LineIndex` for line/column and LSP UTF-16 conversion. Do not make every internal node store a duplicated line/column pair. A token should retain its kind, raw spelling, and span; trivia must be ordinary ordered syntax elements or explicitly attached trivia with a documented ownership rule. A `SourceText` snapshot must outlive every node that refers to it. For synthetic missing tokens, store zero-width spans plus a synthetic expected kind/text; for skipped or unknown material, retain the original raw range.

The first implementation should favor correctness and a simple ownership model over a sophisticated rope. A green node can hold token text or a source-slice reference plus the immutable snapshot; if later measurements show token text duplication dominating memory, add interning or chunked source storage without changing parser APIs. Rowan demonstrates that immutable green nodes, full token text, interning, and structural sharing are compatible; Roslyn demonstrates a different valid trivia attachment model. Choose one convention and document it rather than mixing both.

### Recommended Project Structure

A concrete MoonBit module layout should keep the core backend-neutral and make adapters separate packages:

```
moon.mod
src/
├── source/             # SourceText, Span, LineIndex, versioned edits
├── token/              # TokenKind, keyword tables, Token, TokenStream
├── lexer/              # trivia-preserving scanner and lexical diagnostics
├── syntax/             # SyntaxKind, green nodes, cursors/red views, typed CST views
├── parser/             # recursive descent, Pratt precedence, recovery, ParseResult
├── ast/                # optional semantic-less typed lowering/views and node IDs
├── printer/            # exact printer, formatter, formatting options
├── analyzer/           # optional Catalog interface and semantic diagnostics
└── api/                # stable facade types shared by all targets
cmd/
├── doris-sql/          # Native CLI package; file/stdin I/O only here
└── doris-lsp/          # Native LSP JSON-RPC transport and document store
bindings/
└── js/                 # Wasm/JS wrapper, serialization and exported functions
corpus/
├── doris-2.1/          # versioned official-document examples
├── doris-3.0/
└── doris-4.0/
test/
├── lexer/ parser/      # focused unit tests
├── roundtrip/          # exact print and invalid-input tests
└── snapshots/          # CST/diagnostic golden fixtures
```

The exact top-level names may follow the eventual repository convention, but the dependency direction should remain one-way: `source` → `token` → `lexer/parser` → `syntax` → `ast/printer/analyzer` → adapters. The analyzer may depend on `ast` and stable span/node APIs, but the parser must not import it. The adapters may depend on all public layers but must not leak transport or catalog types into `syntax`.

### Data Flow

#### Parse and exact-print flow

```
bytes/text + ParseOptions
       │
       ▼
SourceText + LineIndex
       │
       ▼
Lexer ──► ordered tokens (trivia and unknown tokens included)
       │
       ▼
Parser ──► CST builder/events ──► immutable CST root
       │                              │
       └──────── diagnostics ◄────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    ▼                                   ▼
             exact printer                         typed AST view
          concatenate raw leaves                 (optional) + spans
                    │                                   │
                    ▼                                   ▼
                original text                 analyzer + Catalog (optional)
```

Exact printing must be a structural invariant: for a parsed source snapshot, walking all leaves in source order returns the original bytes, including comments, whitespace, newline style, malformed fragments, and EOF trivia. Missing tokens are zero-width and therefore do not alter exact output. Formatting is a separate operation that produces a deliberate edit/reprint result; it must not silently turn exact printing into normalization.

#### LSP edit flow

```
textDocument/didOpen or didChange
       │
       ▼
DocumentStore(uri, version, SourceText, ParseResult)
       │ apply validated range edits; update LineIndex
       ▼
reparse (initially whole document; later incremental boundary)
       │
       ├── diagnostics with byte spans
       ├── CST for syntax features
       └── optional analyzer query with catalog snapshot
       │
       ▼
UTF-16 range conversion → publishDiagnostics / completion / formatting
```

The LSP protocol's position encoding is an adapter concern. Internally, never conflate LSP UTF-16 positions with parser byte spans. Preserve the document version on every parse result so stale analyzer or formatting responses cannot overwrite a newer document.

#### Incremental parsing and recovery

A full-document parse is the appropriate first milestone and is often adequate for short SQL files. Nevertheless, design the immutable syntax model and APIs so incremental parsing can be added without a rewrite:

1. Apply an edit to the `SourceText` and identify the old token/green-tree interval.
2. Re-lex a bounded region with enough lexical context for quoted strings, comments, and dialect-sensitive literals.
3. Find the smallest enclosing reparsable unit (usually an expression, clause, or statement), reparse it, and reuse unaffected green subtrees.
4. Recompute ancestor text lengths/spans and invalidate only affected typed views/analysis cache entries.

Tree-sitter's documented `TSInputEdit`/old-tree API is direct evidence that edits must update ranges before reparsing and that immutable/shared substructure is a practical optimization. It also warns that individual trees are not thread-safe; the Doris implementation should publish immutable document snapshots and never mutate a shared tree in place.

Recovery should be explicit and layered:

- **Lexical:** consume an unknown character or unterminated literal as an error token while continuing, rather than throwing or dropping bytes.
- **Expression/clause:** on a missing operand, close delimiter, or unexpected operator, create an `ERROR` node and synchronize at a delimiter or known clause keyword.
- **Statement:** panic-mode synchronization at semicolon, end-of-input, or a statement-start keyword; retain skipped tokens in the CST.
- **Completion-friendly:** represent expected-but-missing delimiters/keywords as zero-width missing nodes and emit structured diagnostics separately.

Roslyn documents missing zero-width tokens and skipped-token trivia; rust-analyzer documents `ERROR` nodes, absent mandatory nodes, and diagnostics kept outside the syntax tree. These patterns preserve round-trip output while allowing an IDE to inspect partial SQL. Recovery policy must be tested against incomplete input (`SELECT`, open parentheses, trailing comma, unterminated string/comment) and invalid Doris-specific clauses.

## Architectural Patterns to Follow

### Pattern 1: Immutable lossless red/green syntax model

**What:** Store an immutable, compact green tree containing kinds, children, raw token/trivia text or source slices, and cumulative text lengths. Provide red/cursor nodes for parent/offset identity and typed CST views for ergonomic traversal. Keep diagnostics as a side channel.

**When to use:** Always for the core SDK. It supports exact round-trip, concurrent readers, structural sharing, and future editor edits.

**Trade-offs:** Full fidelity costs more memory than a normalized AST; red views may allocate cursors, and child lookup can be linear unless indexed. Start with a simple representation and optimize measured hot paths. Rowan specifically records text on every token, immutable green nodes, structural sharing, interning, and text-length based offsets. Roslyn's full-fidelity immutable tree is a second independent implementation of the same core guarantees.

**Example (illustrative MoonBit-like shape):**

```moonbit
struct Span { start_byte : Int, end_byte : Int }
enum LeafText { SourceSlice(SourceId, Span), Synthetic(String) }
struct Token { kind : TokenKind, text : LeafText, span : Span }
struct GreenNode { kind : SyntaxKind, children : Array[GreenChild], text_len : Int }
enum GreenChild { Node(GreenNode), Token(Token) }
```

Whether `LeafText` initially stores source slices or raw strings is an implementation choice, but it must be immutable and preserve every byte.

### Pattern 2: Parser-to-tree isolation through events or a narrow builder

**What:** The recursive-descent/Pratt parser depends on a small `CstBuilder`/event interface instead of reaching into concrete tree storage. The builder turns start/token/finish/error events into the immutable CST.

**When to use:** From the first parser milestone. It allows parser and tree optimizations to vary independently, enables test fixtures at the event level, and makes recovery nodes explicit.

**Trade-offs:** Events add an intermediate sequence and bookkeeping; direct construction is simpler for a tiny prototype. The isolation is worth keeping because rust-analyzer explicitly lists parser/syntax-tree independence as a design goal and separates parser, syntax wrapper, and generic rowan layers.

### Pattern 3: Recursive descent for grammatical regions plus Pratt expressions

**What:** Give each statement/clause family a clear parser function and use a single precedence/associativity table for binary, unary, postfix, cast, predicate, and dialect-specific operators. Keep keyword decisions contextual where Doris permits identifiers in non-keyword positions.

**When to use:** This is the selected core strategy. It matches the need for readable hand-controlled recovery and makes expression precedence changes local.

**Trade-offs:** More handwritten maintenance than a generated grammar and potential drift across Doris versions. Mitigate with version-tagged official-doc corpus tests, a centralized token/keyword table, and focused parse fixtures. Tree-sitter's grammar guidance independently warns that a grammar's structural shape should produce an intuitive analyzable tree rather than blindly mirroring specification indirection; its precedence discussion supports an explicit operator-precedence design even though the tool itself is not recommended as the parser here.

### Pattern 4: CST first, semantic analysis as an optional lowering/service

**What:** Parse syntax without a catalog. Expose an explicit `Catalog`/`NameResolver` interface to an analyzer that consumes typed syntax plus spans and returns semantic diagnostics. Keep analyzer caches keyed by document version and catalog identity.

**When to use:** Parser, formatter, LSP syntax diagnostics, and browser use cases where no Doris FE/catalog is available. Invoke analysis only for features requiring names, types, or lineage.

**Trade-offs:** Consumers must understand two diagnostic classes and analysis cannot be hidden inside parse calls. The separation avoids blocking pure syntax use on metadata and prevents analyzer changes from destabilizing the lossless CST. Rust-analyzer's documented syntax trees are explicitly semantic-less; that is the appropriate precedent.

### Pattern 5: One pure core, thin target adapters

**What:** Keep all parsing, CST, printing, and basic diagnostics in backend-neutral MoonBit packages. Native CLI/LSP and Wasm/JS packages provide I/O, protocol, serialization, and memory-lifetime wrappers only.

**When to use:** Required for the project's Native plus Wasm/JS promise. MoonBit's current documentation describes one module supporting native, `wasm`, `wasm-gc`, and `js` targets, and its build system supports target selection and conditional files.

**Trade-offs:** Cross-backend APIs must avoid filesystem, threads, sockets, host callbacks, and backend-specific object identities. Serialization can be expensive, especially for large CSTs. Expose narrow range/diagnostic/query APIs to JavaScript and add explicit tree handles only if profiling proves full JSON materialization unacceptable.

MoonBit's package docs currently support `foreign_library` exports with `#export_name` for generated Wasm/JavaScript/C output, but note that native currently does not support exporting a `foreign_library` package as a library artifact. Therefore the initial native boundary should be a MoonBit library plus a Native CLI/LSP executable; treat a stable native C ABI as a separate compatibility-tested deliverable, not an assumed consequence of the Wasm wrapper.

## Anti-Patterns

### Anti-Pattern 1: Normalize to AST and discard source details

**What people do:** Tokenize and immediately build a normalized AST, dropping comments, whitespace, spelling, newline style, unknown tokens, and exact spans.

**Why it's wrong:** Formatting cannot round-trip, diagnostics lose precise context, and editor edits become text heuristics. It directly violates the project's differentiator.

**Do this instead:** Make the lossless CST the durable parse result; derive AST views/lowerings with a back-reference to CST node IDs and spans.

### Anti-Pattern 2: Reconstruct formatted SQL from semantic nodes

**What people do:** Printer walks an AST and emits canonical SQL, treating the original CST as disposable.

**Why it's wrong:** Comments and malformed-but-preserved input disappear, vendor-specific spelling changes unexpectedly, and formatting becomes destructive.

**Do this instead:** Exact mode concatenates original leaves. Format mode applies explicit CST-aware transformations and has snapshot tests for comments, hints, spacing, and error nodes.

### Anti-Pattern 3: Couple parsing to a catalog or Doris FE

**What people do:** Require table/column metadata or FE services during parsing, or perform name/type resolution as parser side effects.

**Why it's wrong:** Browser/offline/CLI parsing becomes unavailable, parser latency and determinism depend on network state, and syntax coverage is constrained by semantic infrastructure.

**Do this instead:** Parser emits syntax diagnostics with no catalog. Analyzer receives optional interfaces and separate budgets/caches.

### Anti-Pattern 4: Treat malformed input as an exception or drop it

**What people do:** Abort at the first unexpected token, or skip text without representing it in the tree.

**Why it's wrong:** LSP cannot operate on half-written SQL, and exact round-trip becomes impossible precisely when users need diagnostics most.

**Do this instead:** Emit structured diagnostics plus `ERROR`, missing, unknown, and skipped-token representations; synchronize at documented SQL boundaries.

### Anti-Pattern 5: Use global mutable caches or mutable trees in adapters

**What people do:** Share a mutable token/tree cache between LSP requests or let one request mutate a document tree in place.

**Why it's wrong:** Race conditions and stale results appear under concurrent requests, and Wasm reentrancy/lifetime behavior becomes backend-dependent.

**Do this instead:** Immutable `Document` snapshots, explicit version checks, per-document/per-thread caches where needed, and atomic replacement in the document store. Copy or retain snapshots before handing work to another thread.

### Anti-Pattern 6: Mix offset units at the API boundary

**What people do:** Store UTF-16 line columns in the parser or interpret JavaScript/LSP offsets as UTF-8 bytes.

**Why it's wrong:** Non-ASCII SQL comments, identifiers, and literals produce incorrect diagnostics and edits.

**Do this instead:** Canonical byte spans internally; centralize byte ↔ line/column ↔ LSP UTF-16 conversion in `LineIndex`/adapter code with Unicode fixtures.

### Anti-Pattern 7: Duplicate parser implementations per backend

**What people do:** Maintain a Native parser and a separate JavaScript parser for convenience.

**Why it's wrong:** Grammar coverage, recovery, spans, and Doris-version behavior drift; users see different syntax in CLI and Web.

**Do this instead:** Compile the same core packages for each target, and keep only transport/serialization code conditional.

## Scaling Considerations

The parser is expected to be linear in input size for ordinary lexing and parsing (`O(n)` tokens, with bounded lookahead), while CST memory is also linear in retained source/tree material. Do not promise incremental parsing or million-file indexing in the first release; preserve the boundaries that make them possible and measure representative Doris workloads.

| Scale | Architecture adjustments |
|-------|--------------------------|
| One document / local CLI | Whole-document lex/parse; immutable CST and line index; exact printer. Optimize clarity and recovery before interning. |
| Interactive files up to typical editor sizes | Keep one current snapshot per open URI; reparse whole document first, then add edit-aware token windows and smallest-enclosing-statement reuse when latency measurements justify it. Cache syntax diagnostics separately from optional analyzer results. |
| Large SQL files or hundreds of open documents | Avoid duplicating source text in every token; use chunked source storage or interning only after profiling. Bound document/analyzer caches by bytes and document version. Publish immutable snapshots and process independent documents concurrently. |
| Repository-scale corpus/CI | Stream official-doc fixtures instead of retaining all CSTs; use bounded workers; persist compact pass/fail/diagnostic snapshots and Doris-version tags. Keep parser core independent of catalog/network services. |
| Very large workspace/LSP deployment | Add an indexed workspace/catalog service outside the parser, incremental analysis keyed by changed syntax ranges, and cancellation/version checks. Do not split the core into network microservices merely for theoretical scale. |

### Realistic performance priorities

1. **First bottleneck: allocations and retained text.** Full trivia fidelity creates many leaves. Use compact token kinds, byte spans/text lengths, small-string or source-slice storage, and structural sharing only where measurements support it.
2. **Second bottleneck: line/position conversion and serialization.** Maintain line-start indexes and avoid serializing the whole CST to JavaScript for every keystroke; return diagnostics and targeted queries by default.
3. **Third bottleneck: analyzer invalidation.** Semantic analysis and catalog lookups can dominate parse time. Cache by document version and catalog snapshot; keep parser diagnostics available without waiting for analysis.
4. **Concurrency boundary:** immutable trees are safe to read concurrently, but any mutable interner/cache or document store needs ownership or synchronization. Tree-sitter's documentation provides the useful operational warning that a tree instance itself is not thread-safe even though copies are cheap.

Benchmark at minimum: official Doris examples by version, malformed/incomplete editor snippets, large generated SELECT/DDL files, exact-print throughput, formatter throughput, allocation/peak memory, and Native vs Wasm/JS wrapper overhead. Compare against the project's stated sqlglot and ANTLR-JS baselines only after defining equal coverage and output contracts; parser speed without equivalent lossless/recovery behavior is not an apples-to-apples metric.

## Integration Points

### External and platform services

| Service/boundary | Integration pattern | Notes |
|------------------|---------------------|-------|
| Doris official SQL documentation | Versioned checked-in corpus and golden/snapshot tests | Treat 2.1/3.0/4.0 as data labels; docs are a coverage oracle, not a runtime dependency. The official 3.0 manual exposes organized SQL data-type and statement documentation. |
| Native filesystem/stdin/stdout | CLI adapter only | Core accepts text/bytes; adapter owns encoding errors, file paths, exit status, and atomic writes. |
| LSP 3.17 client | JSON-RPC transport + `DocumentStore` | LSP ranges use negotiated position encoding; convert at the boundary and reject stale document versions. |
| JavaScript/Monaco | Wasm/JS wrapper with explicit serialization/handles | Keep exported API small and stable; avoid exposing MoonBit internals or requiring JS to understand red/green implementation. |
| Optional Doris catalog/FE-like metadata | `Catalog` interface injected into analyzer | Never required by parser or exact formatter; network/FE adapters belong outside `analyzer` core. |

### Internal boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `source ↔ lexer` | immutable `SourceText` and spans | Lexer may read bytes but never mutate source; line index is shared. |
| `lexer ↔ parser` | ordered `TokenStream` with raw text and recovery tokens | Parser must not rescan source for trivia or spelling. |
| `parser ↔ syntax` | narrow builder/events | Keeps parser algorithm independent from green-tree storage and enables recovery nodes. |
| `syntax ↔ printer` | read-only CST traversal + source snapshot | Exact printer has no semantic dependencies; formatter options are explicit. |
| `syntax/ast ↔ analyzer` | typed views, node IDs, spans, optional catalog | Analyzer returns separate semantic diagnostics and cache entries. |
| `core ↔ CLI/LSP/Wasm` | stable `api` facade | Adapters convert I/O/protocol types; core remains target-neutral. |
| `document store ↔ worker` | immutable snapshot + version/cancellation token | A result may be committed only if its version is still current. |

## Build-Order Implications for the Four Milestones

1. **Milestone 1 — Kernel:** Establish `SourceText`/`Span`/`LineIndex`, trivia-preserving lexer, immutable CST representation, diagnostics, recursive descent + Pratt parser for industrial SELECT/CTE/JOIN/window/grouping expressions, and exact round-trip tests. Decide token/trivia ownership and byte-span semantics here; changing them later is a breaking API migration.
2. **Milestone 2 — Completeness:** Expand the same parser boundary across Doris DML, DDL, distribution, dynamic partition, materialized-view, and version-tagged syntax. Add statement/clause recovery, official-document corpus tests, and the semantic-less AST/Catalog interface. Keep analyzer optional and do not let coverage expansion regress round-trip or invalid-input recovery.
3. **Milestone 3 — Formatting:** Implement exact printer first as the invariant baseline, then configurable CST-aware formatting and edit operations, followed by the Native `doris-sql format` CLI. Formatting should operate on the CST and preserve comments/hints/error fragments; snapshot tests become the contract for style options.
4. **Milestone 4 — Ecosystem:** Freeze the public facade, package Native CLI/LSP and Wasm/JS wrappers, add the versioned LSP document store, and introduce incremental reparse/reuse where benchmarks justify it. Add analyzer-backed LSP features only after parser diagnostics and document-version handling are reliable. Publish target-specific artifacts from the one MoonBit core; do not fork grammar/parser code.

This order follows dependency edges rather than organizational layers: a trustworthy lossless tree and coordinate model are prerequisites for parser coverage, formatting, and LSP; a stable core API is a prerequisite for target packaging. Incremental parsing is an architectural constraint to preserve from Milestone 1, not a reason to delay the first usable whole-document parser.

## Sources

All sources below were read on 2026-08-03. Confidence reflects direct primary/official documentation; the rust-analyzer guide is a historical design guide (it identifies its described implementation state as 2020-01-09), while Rowan, Roslyn, Tree-sitter, MoonBit, LSP, and Doris links are current or version-pinned documentation.

- **HIGH:** rust-analyzer, “Syntax in rust-analyzer” — lossless/resilient/semantic-less trees, green/red/AST layers, parser/tree isolation, trivia alternatives, error nodes, immutable sharing: https://rust-analyzer.github.io/book/contributing/syntax.html
- **HIGH:** Rowan 0.17.0 API documentation — generic lossless syntax tree, immutable `GreenNode`, `GreenToken`, `NodeCache`, cursors, and text-based traversal: https://docs.rs/rowan/latest/rowan/
- **HIGH:** Microsoft Learn, “Use the .NET Compiler Platform SDK syntax model” — full fidelity, immutable/thread-safe syntax trees, nodes/tokens/trivia, `Span`/`FullSpan`, missing and skipped tokens: https://learn.microsoft.com/en-us/dotnet/csharp/roslyn-sdk/work-with-syntax
- **HIGH:** Tree-sitter, “Advanced Parsing” — edit ranges, reparsing with an old tree, structural sharing, included ranges, and concurrency caveat: https://tree-sitter.github.io/tree-sitter/using-parsers/3-advanced-parsing.html
- **HIGH:** Tree-sitter, “Writing the Grammar” — intuitive CST structure, grammar grouping, precedence, and corpus-test guidance: https://tree-sitter.github.io/tree-sitter/creating-parsers/3-writing-the-grammar.html
- **MEDIUM:** MoonBit Documentation v0.10.5 — supported `wasm`, `wasm-gc`, `js`, and `native` backends: https://docs.moonbitlang.com/en/latest/
- **MEDIUM:** MoonBit Package Configuration v0.10.5 — package types, `#export_name`, target exports, and the current native `foreign_library` limitation: https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html
- **MEDIUM:** MoonBit Build System Tutorial v0.10.5 — `preferred_target`, `supported_targets`, conditional files, package/module boundaries: https://docs.moonbitlang.com/en/latest/toolchain/moon/tutorial.html
- **MEDIUM:** MoonBit WebAssembly Integration v0.10.5 — component model and FFI/custom export boundary: https://docs.moonbitlang.com/en/latest/toolchain/wasm/index.html
- **HIGH:** Language Server Protocol 3.17 specification — document synchronization, language-server lifecycle, position/range protocol boundary: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/
- **HIGH:** Apache Doris 3.0 SQL manual index — official, versioned SQL documentation corpus organization: https://doris.apache.org/docs/3.0/sql-manual/basic-element/sql-data-types/

---
*Architecture research for: Doris SQL Parser SDK*
*Researched: 2026-08-03*

---

# v2 Analysis Features — Architecture Integration

**Researched:** 2026-08-05 (v2.0 milestone)
**Focus:** How ANAL-01/LINT-01/LINE-01/FING-01/EDIT-01 integrate with the existing lossless CST architecture
**Confidence:** HIGH (grounded in existing repo structure read this session: `analyzer/`, `formatter/`, `binding/schema.mbt`, `api/api.mbt`, parser CST shape)

## Guiding Boundaries (from v1, MUST be preserved)

- **D-21**: `parser/` never imports `analyzer/` — parser core stays syntax-only.
- **D-27**: `formatter/` consumes only `source/token/syntax` + core buffer — one-way dependency.
- **D-22**: `Catalog` is an open trait with `ColumnInfo`/`TableInfo`; `StaticCatalog` case-sensitive keys (documented).
- **D-33**: refusal is absolute for error/missing/skipped material — formatter/analysis must refuse unsafe transforms.
- **D-31**: advertise only linear Wasm; JS ESM + linear Wasm facades; serialized JSON schema (`inline-root-v1`) at the boundary.

## New / Modified Components

| Component | New or Extend | Dependency | Purpose |
|-----------|--------------|------------|---------|
| `analyzer/` resolution engine | **Extend** (exists, D-21/D-22/D-24) | `syntax` + optional `Catalog` | ANAL-01: scopes, table/column/function binding, star expansion, targeted type diagnostics |
| `lint/` package | **New** | CST + `formatter/` safe-edit path (D-27) | LINT-01: rule registry, severity config, safe autofix (reuse refuse-on-unsafe, D-33) |
| `lineage/` package | **New** | `analyzer/` (resolution) | LINE-01: column-level source→target graph with source spans |
| `fingerprint/` package | **New** | CST | FING-01: normalized canonical form + stable `UInt64` hash |
| `incremental/` (EDIT-01) | **New, benchmark-gated** | CST + `source` revisions | EDIT-01: bounded reparse reuse, span invalidation — only if `moon bench` justifies |
| `binding/` schema | **Extend** | serialized JSON (v2 schema bump) | New analysis result types: resolutions, lint findings, lineage edges, fingerprints |
| `api/` | **Extend** | all above | `analyze_text`, `lint_text`, `lineage_text`, `fingerprint_text` serialized entry points |

## Data Flow

```
parse_text/format_text (existing)  ──>  lossless CST
                                            │
        ┌───────────────────────────────────┼───────────────────────┐
        │                                   │                       │
   fingerprint/ (CST→canonical→UInt64)  lint/ (CST walk)     analyzer/ (CST + Catalog)
        │                                   │                       │
        │                                   │ (safe edits via       │ (resolution, spans)
        │                                   │  formatter path)      │
        │                                   │                       │
        └───────────────► api/ serialized results ◄────────────────┘
                                  │
                    binding/ JSON v2 ──► LSP / JS ESM / linear Wasm / CLI
```

## Key Architecture Decisions

1. **`lineage/` depends on `analyzer/`, not on parser** — keeps parser core syntax-only (D-21). Lineage edges reference resolved bindings + source spans.
2. **`lint/` autofix must go through the formatter-safe edit path** — never direct token surgery. Reuse the same refusal logic (D-33): if a fix would touch comments/trivia or sit on an error tree, emit a diagnostic without auto-edit.
3. **`fingerprint/` normalizes the CST, not the serialized JSON** — walk syntax nodes, fold whitespace/case of keywords (not identifiers), then hash a canonical byte form with `UInt64`. This keeps fingerprints stable and independent of schema-version drift.
4. **EDIT-01 lives behind a benchmark gate** — implement whole-document reparse first (already the v1 behavior), measure with `moon bench`, and only then design span-based invalidation over the lossless CST. The existing `source` revisions + LineIndex already provide the coordinate foundation.
5. **Analysis results serialize via a schema v2 bump** — `binding/schema.mbt` gains new result kinds; `api` exposes stable primitive entry points (bytes/JSON), preserving the FFI-stable boundary.

## Suggested Build Order

1. **Phase A (closeout + foundation):** ECO-07 human VS Code verification; linear-Wasm CI execution parity; extend `analyzer/` resolution engine (ANAL-01 core).
2. **Phase B:** FING-01 fingerprinting (independent) + LINT-01 rule engine (parallelizable).
3. **Phase C:** LINE-01 column lineage (requires ANAL-01).
4. **Phase D:** EDIT-01 incremental — benchmark first, adopt only if justified.

## Sources

- Existing repo: `analyzer/analyzer.mbt`, `formatter/`, `binding/schema.mbt`, `api/api.mbt`, `parser/parser.mbt` (read this session)
- v1 ARCHITECTURE.md (five-layer model, incremental deferral rationale)
- STATE.md decisions D-21/D-22/D-24/D-27/D-31/D-33

---
*Architecture research (v2 additions) for: Doris SQL Parser SDK — analysis features*
