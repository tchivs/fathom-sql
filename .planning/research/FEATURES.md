# Feature Landscape

**Domain:** Apache Doris SQL parser, formatter, and editor SDK
**Researched:** 2026-08-03
**Overall confidence:** MEDIUM-HIGH

## Competitive and Ecosystem Baseline

The market is split between (1) general-purpose dialect libraries, (2) Doris's own frontend implementation, and (3) commercial parser products. None of the checked alternatives is a direct match for the requested combination of Doris coverage, lossless source representation, independent deployment, and Native plus Wasm/JavaScript targets.

* **SQLGlot is the closest open implementation reference, not a drop-in replacement.** Its current Doris dialect subclasses MySQL, installs a Doris-specific parser and generator, adds Doris functions/properties/partition syntax, and carries a large reserved-keyword set. SQLGlot's own README explicitly says that it parses to an AST, changes formatting/casing/quoting when regenerating SQL, preserves comments only on a best-effort basis, and is intentionally lenient rather than a validator. This makes it useful for interoperability and performance baselines, but it leaves a clear product gap for exact round-trip editing and IDE diagnostics. [HIGH confidence; source code and README checked]
* **Doris FE/g4 is the execution product's grammar source, not an independently consumable SDK contract.** The Apache Doris repository exposes ANTLR grammar artifacts under `fe/fe-core/src/main/antlr4/org/apache/doris/nereids/` (including `JavaLexer.g4` and `JavaParser.g4` in the checked tree); SQLGlot's Doris generator also links its keyword list to a Doris `DorisLexer.g4` revision. FE grammar/version coupling, generated parser/runtime assumptions, and FE semantic dependencies mean it should be treated as a coverage oracle and differential-test reference, not copied as the public API. [HIGH for repository facts; MEDIUM for the integration conclusion]
* **GSP demonstrates the commercial feature bar, while its public Doris evidence is bounded.** GSP documents a dedicated Doris grammar, AST access, formatting, syntax validation, and lineage. Its published Java 4.1.9 corpus measurement (2026-08-03) reports 38/46 constructs and 123/134 statements for Doris, including 17/21 SELECT statements and 16/17 DML statements. The same page says those percentages are only pass rates over its own vendor-documentation corpus, not the whole dialect. GSP also documents source-token re-emission for byte-preserving edits separately from normalised AST generation, and its licensing FAQ says external distribution needs a separate distribution license. These are useful expectations and trade-offs, not proof of undocumented capabilities. [HIGH for what GSP publicly states; MEDIUM for market comparison]
* **General SQL editor servers establish expected interactions but have weak Doris coverage.** The checked `sqls` server advertises completion, hover, signature help, formatting, diagnostics/code actions, and database-backed metadata, but its listed drivers are MySQL, PostgreSQL, SQLite3, MSSQL, H2, and Vertica and its README marks CREATE/ALTER TABLE completion as incomplete. `sql-language-server` advertises completion, warnings/errors, linting, a parser, VS Code/Monaco integration, and MySQL/PostgreSQL/SQLite3 support. Neither checked project lists Doris. The LSP specification provides the transport and feature vocabulary; the Doris SDK must supply dialect-aware semantics without requiring a live database for syntax diagnostics. [HIGH for listed capabilities; LOW for any claim that no other Doris LSP exists]
* **Lossless/incremental syntax trees are a recognized editor pattern.** Tree-sitter documents concrete syntax trees, useful results in the presence of syntax errors, edits that update node ranges, and reparsing that shares structure with the previous tree. The project need not adopt Tree-sitter or generated grammars, but its lossless CST and span/edit API should be judged against these editor expectations. [HIGH confidence]

## Table Stakes

These are the minimum capabilities users reasonably expect from a production parser SDK. A feature is not table stakes merely because an adjacent competitor claims it; it is table stakes when its absence makes a parser unsafe to embed in CI, a formatter, or an editor.

| Feature | Why Expected | Complexity | Dependencies | Version / corpus implications |
|---|---|---:|---|---|
| **Doris dialect lexer and parser API** (`parse`, `parse_many`, structured result) | Users need a library that can parse Doris without bringing up FE or guessing between MySQL dialects. | High | Lexer, recursive-descent statement parser, Pratt expression parser, public CST/diagnostic types | Define a version-tagged dialect profile (at least Doris 2.1, 3.x, 4.x/current). Never silently treat a later keyword as valid in an older profile. |
| **Lossless source model** retaining trivia, comments, token text, and byte/line/column spans | Formatter, refactoring, diagnostics, and editor edits must not discard user comments or unrelated whitespace. SQLGlot explicitly documents that AST regeneration changes cosmetic details; GSP documents token-list re-emission as a separate source-preserving path. | High | Trivia-preserving lexer, immutable CST nodes, source coordinate model, safe edit/replace operation | Golden corpus must include comments, mixed newline styles, quoted identifiers, Unicode, and semicolons. Define whether spans are byte offsets, UTF-16 positions, or both for LSP. |
| **Exact no-op round trip** (`print(parse(sql)) == sql`) | It is the trust boundary for tools that inspect or edit SQL. A parse-only operation must not rewrite a file. | Med-High | Lossless CST, token ownership rules, printer that can replay original tokens | Make this an invariant in every supported version profile; add snapshot tests for all official examples, not just SELECT. |
| **Core SELECT and expression coverage** | SELECT, joins, subqueries/CTEs, windows, grouping sets/rollup/cube, set operations, predicates, literals, functions, and Pratt precedence are the daily workload. Doris's 4.x SELECT documentation explicitly includes hints, `ALL EXCEPT`, partitions/tablets, sampling, grouping extensions, joins, UNION, and WITH. | High | Expression precedence table, clause parser, nested-scope CST shape, recovery points | Start with documented examples from 2.1/3.x/4.x and record feature introduction/removal versions. Avoid using MySQL compatibility as a coverage claim. |
| **DML and statement/script boundaries** | INSERT, INSERT OVERWRITE, UPDATE, DELETE, MERGE where supported, semicolon-separated scripts, and statements containing nested semicolons are needed for CI and migrations. Naive semicolon splitting corrupts procedure-like or nested constructs. | High | Statement dispatcher, delimiter-aware lexer/parser, recovery synchronization | Track support per Doris release; preserve statement-level spans even when one statement fails. |
| **Doris DDL and warehouse-specific clauses** | CREATE/ALTER/DROP table and view, CTAS/LIKE, keys and aggregation semantics, distribution, buckets, partitions/dynamic partitions, properties, indexes, and materialized views are what distinguish Doris from generic MySQL. The official 4.x CREATE TABLE page documents these forms and marks `ORDER BY` as supported since 4.1.0. | High | DDL CST nodes, property key/value representation, partition/distribution grammar, feature gates | Corpus must pin docs by release; current `4.x` pages are for an unreleased branch and should not be treated as 4.0 compatibility. Keep unsupported/new clauses as recoverable unknown nodes rather than accepting them in every version. |
| **Precise, machine-readable diagnostics** | Editors and CI need severity, code, message, token/span, expected syntax, and statement identity—not only a boolean. GSP publicly documents token, line/column, hint, error type, and per-statement errors. | High | Error type model, span mapping, parser context, diagnostics API | Diagnostics are a public compatibility surface; stable codes should include dialect/version context. Test malformed and half-written SQL, not only rejected complete SQL. |
| **Error recovery for incomplete SQL** | An editor must continue producing a tree and diagnostics after a missing expression, comma, quote, closing delimiter, or clause keyword. | High | Panic-mode at statement boundaries, clause-level recovery, explicit error/missing nodes | Recovery behavior must be snapshot-tested on editor-like prefixes/suffixes. Do not promise engine acceptance from a recoverable CST. |
| **Deterministic printer baseline** | Even before a configurable formatter, users need a stable canonical rendering for debugging, snapshots, and generated SQL. | Medium | CST/AST rendering rules, keyword and identifier policy | Canonical mode must be version-aware and documented as potentially changing only under a versioned printer contract. |
| **Embeddable, dependency-light core** | CI, build tools, web workers, and editor extensions cannot depend on a running Doris FE or a database connection for syntax-only work. | Medium | Pure MoonBit core, no FE runtime dependency, explicit analyzer boundary | Build the same semantic core for Native and Wasm/JS; avoid backend-specific parser forks. |
| **Coverage accounting and compatibility reporting** | Consumers need to know what “supported Doris” means and when a syntax gap is intentional. GSP's measured corpus and SQLGlot's source dialect implementation show that a named coverage corpus is more useful than an unqualified support badge. | Medium | Official-doc scraper/fixture process, version manifest, golden/snapshot runner | Report per release and feature category; include source URL and introduction version in each fixture. |

## Differentiators

These are high-value capabilities aligned with the stated opportunity. They should be built only after the table-stakes invariants are reliable; otherwise they turn into trust liabilities.

| Feature | Value Proposition | Complexity | Dependencies | Version / corpus implications |
|---|---|---:|---|---|
| **Lossless CST first-class API (not merely a token side channel)** | Enables safe range edits, comment-preserving formatting, semantic highlighting, and round-trip transformations without rebuilding the whole document. This is a stronger contract than SQLGlot's AST and more ergonomic than an opaque commercial token list. | High | Stable node IDs/spans, trivia ownership, edit API, printer | Node shape and span semantics need a compatibility policy before ecosystem release. Corpus must include trivia placement around every grammar boundary. |
| **Doris-specific semantic boundary with optional catalog injection** | Syntax validation works offline; later completion/hover/name resolution can consume table/column metadata without coupling the parser to FE execution semantics. This directly respects the project boundary against replacing `EXPLAIN` or full type inference. | High | CST-to-AST projection, scope model, `Catalog` interface, optional analyzer package | Fixtures should distinguish syntax-valid from catalog-dependent diagnostics. Keep engine-specific semantic behavior opt-in and versioned. |
| **Documentation-as-coverage-oracle pipeline** | Turns Doris documentation drift into an observable release task and makes claims auditable. GSP's corpus methodology is a useful precedent; the project can improve it by pinning 2.1/3.x/4.x, publishing fixtures, and running lossless snapshots. | Medium-High | Source manifest, fixture normalizer, golden runner, CI diff report | Official docs currently expose separate 2.1, 3.x, 4.x, and unreleased/current branches. Keep source URLs, page dates, and version labels in fixture metadata. |
| **Recoverable CST designed for LSP** | A single parse can power diagnostics, semantic tokens, folding, document symbols, and formatting while the user is typing. Tree-sitter documents error-tolerant and edit-aware trees; this project can offer a Doris-native API with the same outcome while retaining handwritten parser control. | High | Error/missing nodes, incremental/reparse strategy or bounded reparsing, span-to-LSP mapping | LSP uses UTF-16 positions in common clients; preserve lossless byte spans and provide conversion. Validate malformed prefixes from real editor workflows. |
| **Configurable, comment-preserving formatter** | Gives Doris users a trustworthy `doris-sql format` and library API: indentation, keyword case, comma style, line width, and dialect/version profile while preserving comments and untouched trivia. | High | CST printer, formatting policy, stable comment attachment, CLI | Require idempotence (`format(format(x)) == format(x)`) and explicit distinction between no-op replay and canonical formatting. New Doris clauses need formatting tests per profile. |
| **One MoonBit implementation across Native and Wasm/JS** | Avoids duplicated parser behavior and gives CLI/LSP, web tools, and Monaco the same diagnostics and CST semantics. Existing SQL LSP projects show that Monaco and multiple editor clients are practical, but they generally depend on a server/database stack. | High | Pure core modules, serialization boundary, Native/Wasm/JS packaging, UTF-16 conversion | Public API must avoid backend-specific types; publish capability matrix and bundle-size/performance budgets per target. |
| **Doris-aware syntax highlighting and semantic tokens without a database** | Makes the SDK immediately useful in web editors and offline IDEs, including incomplete SQL. | Medium | Lossless token/CST spans, LSP semantic-token mapper, versioned keyword classes | Keyword class changes are version-sensitive; fixtures must check quoted/unquoted identifiers and reserved/contextual keyword behavior. |
| **Stable JSON/JS facade and schema fixtures** | Lets web/Monaco users consume parse results without binding to MoonBit internals; generated schema fixtures also make cross-language compatibility testable. | Medium | Serializable CST/diagnostic schema, Wasm/JS wrapper, schema versioning | Version the wire schema separately from grammar profiles; include source spans and trivia explicitly rather than serializing only AST nodes. |
| **Differential validation against FE, SQLGlot, and documented examples** | FE is the execution authority, SQLGlot is an open parser baseline, and docs are the public syntax corpus. Triangulation helps locate unsupported/ambiguous syntax without making any one implementation the SDK contract. | Medium | Test harnesses, FE container or parser invocation where feasible, normalized outcomes | Record disagreements as fixtures with a reason and Doris-version label; never turn a MySQL/SQLGlot acceptance into proof of Doris validity. |

## Anti-Features

These should be explicitly excluded or deferred to protect scope and user trust. “Do not build” means do not make them part of the initial product promise; a later extension can be reconsidered after the four milestones.

| Anti-Feature | Why Avoid | What to Do Instead |
|---|---|---|
| **Claiming full Doris compatibility from SQLGlot, FE grammar, or a single benchmark** | SQLGlot documents lenient parsing and AST-only regeneration; FE is an implementation dependency; GSP's percentages are corpus-specific and self-published. A generic “100% Doris” badge would be misleading. | Publish per-version, per-category docs-corpus results, known gaps, and differential-test status. |
| **Silent MySQL fallback for unknown Doris syntax** | It converts unsupported constructs into false positives and can produce unsafe formatter/editor output. | Require an explicit Doris version/profile; emit a recoverable `UnknownDorisConstruct`/diagnostic with source span. |
| **Lossy AST-only public contract** | It makes no-op edits, comment preservation, and precise source mapping impossible or fragile—the core opportunity would disappear. | Make lossless CST the source of truth; provide a derived AST projection for analysis. |
| **Full semantic/type/execution replacement for Doris FE** | Function existence, complete type inference, privileges, optimizer behavior, and `EXPLAIN` semantics require catalog/runtime context and would expand into an engine rewrite. | Keep parser and optional catalog-backed analyzer separate; expose interfaces, not FE emulation. |
| **Enterprise lint, column lineage, SQL fingerprinting, and optimizer rewriting in the first four milestones** | These require a stable AST/CST, scope rules, catalog policy, and substantial compatibility semantics. Shipping them early weakens parser coverage and error recovery. | Reserve them for post-ecosystem extensions with explicit semantic contracts and opt-in packages. |
| **Bundling or embedding Doris FE as a runtime requirement** | Large Java/FE dependencies undermine Native/Wasm/JS portability, startup, licensing, and offline editor use. | Use FE for differential testing and execution integration only; keep core standalone. |
| **Naive semicolon splitting or regex-only statement parsing** | Semicolons can occur inside nested constructs and strings; this breaks scripts and diagnostics. | Let the lexer/parser own statement boundaries and preserve statement spans. |
| **Automatic SQL dialect detection as the default** | Plain SQL is ambiguous across MySQL-compatible dialects; first-success parsing can silently choose the wrong rules. | Require an explicit Doris profile; offer detection only as an opt-in diagnostic with ambiguity reporting. |
| **Formatter that always regenerates the whole document** | It causes comment movement and noisy diffs, undermining trust in editor save actions. | Offer no-op replay, targeted CST edits, and a canonical formatter with explicit user opt-in. |
| **Unbounded error recovery that accepts arbitrary text as valid SQL** | IDE tolerance can become CI false negatives and accidental acceptance of unsupported syntax. | Separate recoverable CST from validity status; preserve hard diagnostics and expose strict vs editor modes. |
| **Publishing Wasm/JS wrappers before the core schema is stable** | Early wrapper APIs freeze accidental MoonBit implementation details and create multi-backend drift. | Stabilize core node/span/diagnostic contracts first; then generate thin Native and Wasm/JS facades. |
| **Relying on closed-source GSP behavior as an undocumented compatibility target** | GSP is commercially licensed and its public pages do not establish every internal behavior; reverse engineering would create trust and legal ambiguity. | Use only public GSP claims as market evidence and maintain open, reproducible Doris fixtures. |

## Feature Dependencies

```text
Versioned Doris profile + keyword/trivia lexer
  -> lossless token stream and source spans
  -> recursive-descent statements + Pratt expressions
  -> recoverable CST + structured diagnostics
  -> SELECT/CTE/JOIN/window/grouping coverage
  -> DML and Doris DDL coverage
  -> AST projection + optional Catalog/analyzer boundary
  -> deterministic replay printer
  -> configurable comment-preserving formatter + CLI
  -> Native API and Wasm/JS schema facade
  -> LSP server (diagnostics, semantic tokens, symbols, formatting)
  -> editor/Monaco integrations

Official-doc corpus manifest + golden snapshots
  -> every grammar feature above
  -> release/version compatibility report
  -> FE/SQLGlot differential tests

CST edit API + stable spans
  -> targeted refactors and future lint/lineage/fingerprint packages
```

The first four milestones should be vertical enough to prove this chain without making later analysis a prerequisite:

1. **M1 — Core kernel:** lexer with trivia/spans, lossless CST, statement-level and clause-level recovery, Pratt expressions, industrial SELECT foundation, strict/no-op replay, and machine-readable diagnostics.
2. **M2 — Completeness:** documentation-driven expansion across DML/DDL and Doris-specific table, key, distribution, partition, dynamic partition, property, index, and materialized-view forms; versioned 2.1/3.x/4.x profiles and differential/golden reports.
3. **M3 — Formatting:** configurable canonical printer and `doris-sql format`, comment attachment rules, idempotence, line-width/indent/keyword policies, and safe targeted edits.
4. **M4 — Ecosystem:** Native CLI/LSP plus Wasm/JS SDK, LSP diagnostics and document synchronization first, then semantic tokens/symbols/formatting, and a minimal Monaco/web integration using the same core.

## MVP Recommendation

### Prioritize

1. **A trustworthy lossless kernel:** versioned Doris lexer, trivia/spans, CST, strict result plus recoverable editor result, and `parse(print(parse(x))) == x` for unchanged input. This is the differentiator and the prerequisite for every downstream feature.
2. **Industrial SELECT and expressions:** joins, subqueries, CTEs, windows, grouping sets/rollup/cube, set operations, hints, and Doris-specific SELECT clauses, driven by official 2.1/3.x/4.x examples rather than generic MySQL acceptance.
3. **A measured Doris coverage loop:** fixture metadata with source URLs and version labels, golden snapshots, negative/recovery cases, and FE/SQLGlot comparisons where their behavior is observable. Publish gaps instead of overclaiming.
4. **M2 DML/DDL breadth before editor polish:** INSERT/UPDATE/DELETE/INSERT OVERWRITE plus Doris CREATE/ALTER table and materialized-view syntax, distribution/partition/properties, because these are the features generic SQL tools routinely miss and Doris operators actually edit.
5. **M3 formatting only after replay is invariant:** provide a canonical and configurable formatter with comments preserved, plus CLI behavior suitable for CI and pre-commit use.
6. **M4 thin integrations:** expose the stable core to Native and Wasm/JS; implement LSP diagnostics/synchronization/formatting and basic semantic tokens before completion/hover that depend on optional catalog metadata.

### Defer

* Full semantic analysis, type inference, privilege/function validation, optimizer rewrites, and FE `EXPLAIN` equivalence: defer behind a catalog-backed analyzer interface.
* Enterprise lint rules, column-level lineage, SQL fingerprinting/normalization, and broad refactoring: defer until CST, scope, formatter, and schema contracts are stable.
* Multi-dialect support, automatic dialect detection, template languages, database execution, and FE embedding: avoid turning a Doris SDK into a generic SQL platform.

### MVP success signals

* Official examples pass by named Doris version and category, with failures visible and reproducible.
* Strict mode distinguishes invalid/unsupported SQL from editor-mode recoverable input.
* No-op parse/replay is byte-for-byte for comments, whitespace, casing, newline style, and spans.
* Canonical formatting is deterministic and idempotent, while targeted edits produce minimal source changes.
* The same fixtures and diagnostics pass on Native and Wasm/JS, and a minimal LSP client can receive diagnostics and formatting without a live Doris FE.

## Sources

### Primary ecosystem and competitor sources

- Apache Doris 4.x SQL statement index (versioned statement families): <https://doris.apache.org/docs/4.x/sql-manual/sql-statements/> (official docs; current index observed 2026-08-03)
- Apache Doris 4.x `SELECT` syntax and examples: <https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/> (official docs; last updated May 28, 2026)
- Apache Doris 4.x `CREATE TABLE` syntax, partition/distribution/properties, and `ORDER BY` version note: <https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/> (official docs; last updated June 14, 2026)
- Apache Doris FE ANTLR grammar directory: <https://github.com/apache/doris/tree/master/fe/fe-core/src/main/antlr4> and checked grammar files <https://raw.githubusercontent.com/apache/doris/master/fe/fe-core/src/main/antlr4/org/apache/doris/nereids/JavaLexer.g4>, <https://raw.githubusercontent.com/apache/doris/master/fe/fe-core/src/main/antlr4/org/apache/doris/nereids/JavaParser.g4>
- SQLGlot Doris dialect: <https://raw.githubusercontent.com/tobymao/sqlglot/main/sqlglot/dialects/doris.py>
- SQLGlot Doris parser: <https://raw.githubusercontent.com/tobymao/sqlglot/main/sqlglot/parsers/doris.py>
- SQLGlot Doris generator and Doris keyword-source reference: <https://raw.githubusercontent.com/tobymao/sqlglot/main/sqlglot/generators/doris.py>
- SQLGlot README (AST regeneration, best-effort comments, lenient validation, parser errors): <https://raw.githubusercontent.com/tobymao/sqlglot/main/README.md>
- SQLGlot AST primer (AST model and analysis scope): <https://raw.githubusercontent.com/tobymao/sqlglot/main/posts/ast_primer.md>
- GSP Doris syntax support and documented-corpus measurements: <https://docs.sqlparser.com/reference/sql-syntax/doris/>
- GSP machine-readable Doris capability record: <https://docs.sqlparser.com/capabilities/v1/dialects/doris.json>
- GSP advanced features (AST generation versus source-token re-emission): <https://docs.sqlparser.com/tutorials/advanced-features/>
- GSP error handling (structured diagnostics and per-statement reporting): <https://docs.sqlparser.com/how-to/error-handling/>
- GSP licensing FAQ (dialect licensing and external distribution): <https://docs.sqlparser.com/faq/licensing/>
- General SQL Parser architecture overview: <https://docs.sqlparser.com/explanation/architecture/>

### Editor and parser-tooling sources

- Language Server Protocol 3.18 specification: <https://microsoft.github.io/language-server-protocol/specifications/lsp/3.18/specification/>
- Tree-sitter introduction (concrete syntax tree, error tolerance, incremental parsing): <https://tree-sitter.github.io/tree-sitter/>
- Tree-sitter advanced parsing/editing API: <https://tree-sitter.github.io/tree-sitter/using-parsers/3-advanced-parsing.html>
- `sqls` SQL LSP README and supported drivers/features: <https://raw.githubusercontent.com/sqls-server/sqls/master/README.md>
- `sql-language-server` README, parser/linter/LSP/Monaco claims and supported databases: <https://raw.githubusercontent.com/joe-re/sql-language-server/master/README.md>
- SQLFluff README (dialect-flexible linting/auto-fix and Doris dialect listing): <https://raw.githubusercontent.com/sqlfluff/sqlfluff/main/README.md>

## Evidence and Uncertainty Notes

* “Current” means the public source/doc pages observed on 2026-08-03. SQLGlot source was read from `main` rather than a pinned release; use a release pin when benchmarking.
* GSP's detailed Doris percentages are vendor-published measurements against its own corpus. They are useful evidence of a commercial coverage-reporting pattern, but not an independent market-wide benchmark.
* The checked `sqls` and `sql-language-server` repositories do not list Doris. This supports the opportunity statement that Doris LSP support is underserved, but it is **not** proof that no other Doris editor plugin or private integration exists.
* The official Doris current docs identify the `dev`/current branch as unreleased and link separate 2.1, 3.x, and 4.x documentation. A roadmap should therefore treat documentation versioning and fixture provenance as product features, not release-note chores.

---

# v2 Analysis Features — Feature Landscape

**Researched:** 2026-08-05 (v2.0 milestone)
**Focus:** ANAL-01, LINT-01, LINE-01, FING-01, EDIT-01 + v1 closeout items
**Confidence:** MEDIUM-HIGH (ecosystem patterns verified against SQLFluff/SQLGlot docs this session; Doris-specific scope grounded in v1 validated capabilities)

## Table Stakes for a Doris SDK

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| ANAL-01 name resolution | Editors/analysts expect unresolved refs flagged; catalog injection already promised by ANLY-01 boundary | HIGH | Needs scopes (SELECT/CTE/subquery/alias), table+column+function binding, star expansion with catalog |
| LINT-01 lint rules | SQL tooling standard (SQLFluff model) | MEDIUM | Rule registry with stable codes + bundles; severity config; **safe autofix** (text edits must stay lossless — D-33 refusal principle) |
| LINE-01 column lineage | Analyst demand for data provenance | HIGH | Column-level source→target edges across SELECT/INSERT/CTE/set ops/views |
| FING-01 SQL fingerprints | Caching/diff/CI use cases | LOW-MEDIUM | Stable across whitespace/case/comment; normalized form + stable hash (`UInt64` cross-backend) |
| EDIT-01 incremental parsing | Editor latency at scale | VERY HIGH | **Benchmark-gated**: only adopt when whole-doc reparse measurably fails (v1 research explicitly deferred this) |

## Differentiators (Doris-specific)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| ANAL-01 | **Lossless** name resolution: every binding carries source spans and trivia-faithful refs, unlike SQLGlot's AST regeneration | HIGH | Profile-gated (2.1/3.x/4.x); case policy matches Doris (case-insensitive identifiers, `equal_ignore_ascii_case`) |
| LINT-01 | **Doris-aware rule set** with version gates + safe lossless autofix | MEDIUM-HIGH | Rules keyed to Doris profile; autofix reuses formatter-safe edit path (D-27/D-33) |
| LINE-01 | Column lineage **with source positions** and view/CTE expansion | HIGH | Builds on ANAL-01 resolution; Doris views/CTEs are first-class |
| FING-01 | Stable **cross-backend** fingerprint (same hash on Native/JS/Wasm) | LOW-MEDIUM | UInt64 hash; normalized CST→canonical form |
| EDIT-01 | Bounded incremental reuse of the **existing lossless CST** | VERY HIGH | Only after `moon bench` proves necessity |

## Anti-Features (Defer / Avoid in v2)

| Feature | Why Problematic | Alternative |
|---------|-----------------|-------------|
| Full type inference / optimizer equivalence | Replaces FE semantics; explodes scope; violates ANLY-01 boundary | ANAL-01 = resolution + targeted type diagnostics only |
| Lint rule engine without severity config | Team adoption blockers | SQLFluff-style per-rule severity + enable/disable |
| Autofix that touches comments/trivia | Violates lossless core value | Refuse unsafe transforms (D-33); only trivia-safe edits |
| Lineage through `*` without catalog | Unsound (cannot know expanded columns) | Require catalog; report unknown columns as explicit gaps |
| Fingerprint normalization that changes semantics | Case-folded quoted identifiers, string-literal folding break correctness | Normalize only syntactic trivia; preserve identifier spelling |
| EDIT-01 without benchmark evidence | Premature complexity (v1 research Pitfall 6) | `moon bench` gate first |

## Feature Dependencies

```
FING-01 (fingerprint) — independent of catalog
    └──requires──> stable CST (v1) ✓

ANAL-01 (name resolution)
    └──requires──> stable CST + analyzer boundary (v1 ANLY-01) ✓
                    └──enables──> LINE-01 (column lineage needs resolved refs)

LINT-01 (lint rules)
    └──requires──> CST traversal (v1) + formatter-safe edit path (v1 D-27/D-33)
                    └──autofix──> reuse formatter/refuse principles

LINE-01
    └──requires──> ANAL-01 (name resolution)
                    └──enhances──> LINT-01 (lineage-aware lint rules, optional later)

EDIT-01
    └──gated──> benchmark evidence (moon bench)
```

### Dependency Notes

- **LINE-01 depends on ANAL-01** — lineage edges need resolved column refs. Roadmap must order ANAL-01 before LINE-01.
- **LINT-01 and FING-01 are largely independent** of ANAL-01 and can proceed in parallel after CST/analyzer basics.
- **EDIT-01 is the riskiest and must be gated** on measurements; roadmap should treat it as a "benchmark then decide" phase, not a guaranteed deliverable.

## v1 Closeout Items (fold into v2 Phase 1)

| Item | Source | Acceptance |
|------|--------|------------|
| ECO-07 human-hosted VS Code launch (04-04 Task 4) | v1 milestone audit, `pending_human` | Run the compiled extension on a machine with VS Code; confirm diagnostics/formatting/positionEncoding |
| linear-Wasm CI runtime execution parity step | v1 milestone audit, `ci_recommendation` | Add CI job that builds `--target wasm` and executes the parity fixture suite, comparing byte output with Native/JS |

## Sources

- [SQLFluff Rules Reference](https://docs.sqlfluff.com/en/stable/reference/rules.html) — verified this session (rule registry, bundles, `core` group, per-rule config, `sqlfluff fix` compatibility)
- [SQLGlot API docs](https://sqlglot.com/sqlglot.html) — verified this session (`find_all`, `qualify`/`annotate_types` need schema, AST regeneration loses formatting)
- v1 FEATURES.md (baseline landscape, 2026-08-03)
- Project v1 milestone audit (ECO-07 pending, linear-Wasm CI recommendation)

---
*Feature research (v2 additions) for: Doris SQL Parser SDK — analysis features*
