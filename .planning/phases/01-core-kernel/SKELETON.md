# Walking Skeleton — Doris SQL Parser SDK

**Phase:** 1  
**Generated:** 2026-08-03

## Capability Proven End-to-End

A caller supplies UTF-8 Doris SQL plus an explicit 2.1, 3.x, or 4.x profile and strict/editor mode, receives a diagnostic-bearing immutable lossless CST, and replays the unchanged input byte-for-byte through the same offline MoonBit core.

This is the parser equivalent of a walking skeleton: it exercises source ownership, coordinates, trivia-preserving lexing, SELECT/Pratt parsing, CST construction, primitive result serialization, diagnostics, and exact replay. It is not a web application and has no network or execution path.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Framework/runtime | MoonBit module using the pinned repository toolchain; current `moon.mod`/`moon.pkg` DSL | One backend-neutral parser implementation can later serve Native and host adapters without creating a runtime-specific parser (CORE-07). |
| Data layer | None; immutable `SourceText`, `Span`, `LineIndex`, token/trivia leaves, CST nodes, and in-memory primitive results | Syntax parsing is pure and offline. Git-tracked corpus fixtures are test inputs, not database state. |
| Auth/session | Not applicable to this headless parser product | The kernel has no users, credentials, sessions, or privileged operations. |
| Routing/transport | Not applicable; direct library call from `api.parse` | Phase 1 is not an HTTP app or LSP server. Later hosts own transport. |
| UI/editor | Not applicable; `01-UI-SPEC.md` is a descriptive future host contract only | The kernel publishes spans, modes, statuses, and diagnostics; it does not initialize a browser, Monaco, VS Code, shadcn, or design system. |
| Deployment target | Not applicable to the parser core; local proof is `moon check --target native && moon test` | There is no server or service to deploy. Later Native/JS/Wasm packaging consumes the stable primitive boundary. |
| Directory layout | `source → token → lexer/parser → syntax → api/printer`, with `test/` and released `corpus/doris-2.1`, `corpus/doris-3.x`, `corpus/doris-4.x` | One-way ownership keeps coordinates and source bytes upstream, CST as source of truth, and printers/API downstream. |
| Coordinates | Canonical UTF-8 byte offsets over one immutable snapshot; one `LineIndex` derives line/column; host adapters later derive UTF-16 | D-01 and D-02 prevent divergent Unicode arithmetic and unstable foreign ABI spans. |
| Recovery | One immutable CST shape with strict/editor result modes, progress-or-error, clause/statement synchronization, explicit MISSING/ERROR/SKIPPED nodes, and finite caps | D-03/D-04 preserve editor usefulness without presenting recovered syntax as valid. |
| Grammar authority | Released official Doris 2.1, 3.x, and 4.x documentation; FE/Nereids and SQLGlot are advisory differential references | D-07/D-08 make support claims reproducible and prevent current/dev or generic MySQL leakage. |

## Stack Touched in Phase 1

- [x] Project scaffold (MoonBit module/package manifests and native build/test command)
- [x] Source/coordinate, lexer, parser, CST, API, printer, diagnostics, and focused tests
- [x] Released-profile seed and industrial fixture records in Git
- [ ] Routing — not applicable to a headless library
- [ ] Database — not applicable; no catalog or persistence is needed for syntax parsing
- [ ] Auth/session — not applicable; no identity boundary exists
- [ ] UI/browser/editor — not applicable; the approved UI contract is descriptive for later hosts
- [ ] Network/Doris FE — explicitly excluded; parsing is offline
- [ ] Deployment — not applicable; the local native check/test command is the product-boundary smoke run

## Out of Scope (Deferred to Later Slices)

- DML/DDL breadth, warehouse-specific table/view/distribution/partition/property/index/materialized-view syntax
- Canonical formatting, formatting options, and `doris-sql format`
- Native CLI/LSP transport, JSON-RPC, UTF-16 host conversion, and editor protocol behavior
- JavaScript/Wasm wrappers, browser/Monaco, VS Code, and cross-target parity packaging
- Catalog-backed analyzer, semantic/type/execution behavior, Doris FE/database access
- Lint, lineage, fingerprinting, normalization, incremental parsing, and unrelated multi-dialect support

These exclusions preserve the Phase 1 parser boundary; they are not placeholders inside the tracer.

- Plan 01: Prove the pinned source → explicit-profile token/trivia lexer tracer, including raw-byte and invalid-UTF-8 preservation.
- Plan 02: Prove the CST → SELECT/Pratt parser → primitive API → exact replay tracer with root-only source payload and stable diagnostic fields.
- Plan 03: Expand one CST into bounded strict/editor recovery with explicit missing/error/skipped nodes, stable diagnostics, and replay tests.
- Plan 04: Expand the released 2.1/3.x/4.x industrial SELECT slice and manifest-driven versioned fixtures, goldens, coverage, and advisory differential records.
- Phase 2: Add Doris DML/DDL and complete official corpus/analyzer boundary.
- Phase 3: Add canonical formatting and safe-edit CLI while preserving exact replay.
- Phase 4: Add Native LSP, serialized JS/Wasm facades, and editor/web integrations.
