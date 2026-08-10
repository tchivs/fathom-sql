# Requirements: Fathom SQL Parser SDK — v3.0 Analysis and Intelligence

**Defined:** 2026-08-05 (carried forward); activated 2026-08-10
**Milestone:** v3.0 Analysis and Intelligence
**Core Value:** 用户可以在同一套 MoonBit 无损 CST 内核上，对显式选择的 Doris 或 Flink SQL 进行高覆盖、精确诊断、无损 round-trip 和编辑器级工具链操作，并在语法层之上获得可审计的语义分析能力（catalog 名字解析、Lint、列级血缘、稳定指纹），而不依赖 Doris FE、Flink cluster、数据库或通用方言静默回退。

## v3.0 Requirements

Requirements for the v3.0 milestone (Analysis and Intelligence). Each maps to exactly one roadmap phase. The five analysis requirements are carried forward from the archived v1.0-REQUIREMENTS.md § v2 Requirements; the two closeout requirements fold in v1.0 deferred verification items (verified during v1.0/v2.0).

### Closeout (v1.0 收尾 — 已完成)

- [x] **CLOSE-01**: User can verify the shipped VS Code extension (ECO-07, 04-04 Task 4) on a machine with VS Code — the compiled extension connects to the Native LSP over the standard client protocol and exposes Doris diagnostics, comment-preserving formatting, and completion, with the documented position-encoding (single-string) behavior. — **VERIFIED 2026-08-06**: `vscode/scripts/host-verify.mjs` launched real VS Code 1.132.0 extension hosts; 3 modes passed (diagnostics/format/completion/4.x-merge, 2.1 MERGE profile propagation, unavailable-server fallback). Fixed the client's `LogOutputChannel` requirement bug. **[Phase 5 formalized]**: `vscode/scripts/host-verify.mjs` real extension-host, 4 isolated modes (functional doris-4.x / profile doris-2.1 / flink flink-2.3.0 / fallback); record in STATE.md Deferred Items.
- [x] **CLOSE-02**: Release gate includes a linear-Wasm runtime execution step in CI — the `--target wasm` build runs the parity fixture suite and produces byte-identical serialized output to the Native and JS targets (ECO-05 runtime parity, currently recommended-not-run). — **VERIFIED 2026-08-06**: `.github/workflows/ci.yml` + release gate run `moon test --target wasm --package parity` (12/12, linear-Wasm runtime execution) + native cross-check. **[Phase 5 formalized]**: ci.yml `linear-wasm-parity` job (`moon test --target wasm --package parity` + native/js cross-check + `scripts/compare_backends.py`); record in STATE.md Deferred Items.

### Analysis and Resolution

- [ ] **ANAL-01**: User receives catalog-backed name resolution and type diagnostics for Doris tables, columns, functions, and scopes (qualified/unqualified refs, aliases, CTEs, subqueries, star expansion with catalog), with case-insensitive identifier matching matching Doris semantics and source spans preserved on every binding.

### Lint

- [ ] **LINT-01**: User can run a Doris-specific lint rule set with configurable severity and safe autofixes (stable rule codes, per-rule enable/disable + severity; autofix preserves comments/trivia/formatting and refuses unsafe edits on error trees, per formatter D-33 refusal principle).

### Lineage

- [ ] **LINE-01**: User can inspect column-level data lineage across supported queries and views (SELECT/INSERT/CTE/set operations and view expansion), where unresolved refs and `*` expansion without catalog metadata produce explicit "requires catalog" gaps rather than fabricated edges.

### Fingerprint

- [ ] **FING-01**: User can generate stable SQL fingerprints and normalized forms for supported Doris statements (stable across whitespace, keyword case, and comment changes; preserves identifier spelling, literal content, and quote style; hash is `UInt64`-based so fingerprints are identical across Native, JS, and linear-Wasm targets).

### Incremental Editing

- [ ] **EDIT-01**: Editor can use bounded incremental parsing and targeted CST refactors without reparsing the full document — **only when `moon bench` benchmarks demonstrate whole-document reparse is a measurable latency bottleneck**; incremental output must be byte-identical to whole-document reparse on the same input (`print_lossless(parse_incremental(x)) == print_lossless(parse_full(x))`).

## Future Requirements

Deferred beyond v3.0. Tracked but not in the current roadmap.

### Analysis and Intelligence (extended)

- **ANAL-02**: User receives full Doris type inference and function/privilege validation equivalent to FE semantics (replaced by FE; out of scope for the parser SDK).
- **LINT-02**: Enterprise lint rule marketplace / rule plugins from outside the SDK.
- **LINE-02**: Cross-database / cross-catalog lineage federation.
- **EDIT-02**: Structural refactor operations beyond what EDIT-01's targeted edits cover (broad renames with cross-file updates).
- **WASM-GC**: Wasm GC target as a first-class supported backend.
- **DIALECT-FUTURE-01**: Third-party dialect/plugin marketplace and open runtime dialect registry.
- **TOOL-FUTURE-01**: Catalog-backed completion, hover, semantic tokens, symbols, and richer LSP intelligence beyond syntax-only candidates.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Full semantic/type/execution replacement for Doris FE (optimizer, `EXPLAIN` equivalence) | Requires engine runtime, catalog, session, privilege, optimizer semantics; not the parser SDK's core value |
| Runtime Doris FE / Flink cluster / database dependency | Breaks standalone Native/Wasm/JS portability and offline editor use |
| Automatic dialect detection / generic MySQL fallback | SQL syntax is ambiguous across dialects; silent selection makes diagnostics and formatting untrustworthy |
| Commercial GSP compatibility or redistribution | Closed-source; not an open compatibility contract |
| Lineage through `*` without catalog metadata (fabricated edges) | Unsound; must be reported as an explicit gap (LINE-01) |
| Incremental parsing without benchmark justification | Premature complexity that risks lossless CST fidelity (EDIT-01 gate) |

## Traceability

Populated during v3.0 roadmap creation. Each requirement maps to exactly one phase.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CLOSE-01 | Phase 5 | Complete — Phase 5 formalized (host-verify.mjs, 4 modes, record in STATE.md Deferred Items) |
| CLOSE-02 | Phase 5 | Complete — Phase 5 formalized (ci.yml linear-wasm-parity, record in STATE.md Deferred Items) |
| ANAL-01 | Phase 5 | In Progress — 05-02 foundation delivered (Catalog contract + SELECT tracer); 05-03 delivered the full SELECT analysis model (clause split, CTE/subquery scope stack, UNION chains, AS aliases, qualified names, table.* star expansion, case-insensitive matching + source span preservation); functions/DML/type diagnostics remain in 05-04 |
| LINT-01 | Phase 6 | Pending |
| FING-01 | Phase 6 | Pending |
| LINE-01 | Phase 7 | Pending |
| EDIT-01 | Phase 8 | Pending |

**Coverage:**

- v3.0 requirements: 7 total
- Mapped to phases: 7
- Unmapped: 0 ✓

---
*Requirements defined: 2026-08-05*
*Last updated: 2026-08-10 after v3.0 milestone start*
