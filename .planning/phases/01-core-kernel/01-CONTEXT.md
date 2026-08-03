# Phase 1: Core Kernel - Context

**Gathered:** 2026-08-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 1 delivers the standalone Doris parsing kernel: an explicitly versioned 2.1/3.x/4.x parser that produces a lossless, recoverable CST with precise diagnostics and industrial SELECT/expression coverage. It includes source coordinates, trivia preservation, strict versus editor-mode results, and offline operation. DML/DDL breadth, corpus expansion, configurable formatting, CLI packaging, LSP, and WebAssembly/JavaScript integrations remain in later roadmap phases unless needed only as contracts for this core.

</domain>

<decisions>
## Implementation Decisions

### Source coordinates and public spans
- **D-01:** Use canonical UTF-8 byte offsets over an immutable source snapshot; derive line/column and LSP UTF-16 positions through one centralized `LineIndex` adapter — **Reversibility:** one-way — published span semantics and later LSP/foreign consumers depend on this coordinate contract.
- **D-02:** Expose versioned serialized results with primitive fields and byte spans; keep UTF-16 conversion at LSP/host adapters rather than in the parser core — **Reversibility:** costly — changing the wire schema would touch Native, JavaScript, Wasm, and later editor clients.

### Recovery contract
- **D-03:** Use one lossless CST shape with two explicit result modes: strict mode reports invalidity without accepting it, while editor mode preserves a usable tree with explicit missing/error/skipped nodes and the same diagnostics model — **Reversibility:** costly — parser callers and fixtures must distinguish validity from recoverability without maintaining two parsers.
- **D-04:** Require parser progress or an explicit error node; synchronize at clause and statement boundaries, preserve unknown/error text, and cap recovery work and diagnostic volume — **Reversibility:** reversible — recovery points can be refined while preserving the strict/editor contract.

### CST and AST boundary
- **D-05:** Make the immutable lossless CST the source of truth; typed semantic-less AST views may project from it and retain backreferences, while the optional analyzer remains a separate package — **Reversibility:** one-way — an AST-first public contract would make the project's lossless editing promise fragile or impossible to restore.
- **D-06:** Use immutable source-backed token/trivia leaves and immutable node structure; every node carries span/text length, and explicit ERROR, skipped, and missing nodes remain printable without copying the entire source into every node.

### Version profiles and validation gates
- **D-07:** Treat released official Doris documentation as the public grammar contract for explicit 2.1, 3.x, and 4.x profiles. Use FE/Nereids and SQLGlot only for differential investigation; current/dev documentation is discovery input, not silently accepted grammar — **Reversibility:** costly — compatibility reports and fixture provenance depend on this authority policy.
- **D-08:** Require versioned golden fixtures, byte-exact lossless replay checks, malformed/recovery cases, and keyword/context boundaries from the first grammar slice. Record FE/SQLGlot differential results as advisory evidence, not as a substitute for the public corpus.

### Claude's Discretion
- Parser function decomposition, event/builder mechanics, concrete MoonBit data structures, and performance optimizations remain open to the planner as long as the coordinate, CST, recovery, version, and validation contracts above are preserved.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project and scope
- `.planning/PROJECT.md` — core value, MoonBit constraint, lossless CST decision, parser/analyzer boundary, and four-milestone scope.
- `.planning/REQUIREMENTS.md` § Core Parsing — locked CORE-01 through CORE-07 acceptance requirements for this phase.
- `.planning/ROADMAP.md` § Phase 1: Core Kernel — phase goal, dependencies, requirements, and success criteria.
- `.planning/STATE.md` — current project position and accumulated cross-phase decisions.

### Research and technical evidence
- `.planning/research/SUMMARY.md` § Phase 1: Core Kernel — research-backed contracts, risks, and focused research flags.
- `.planning/research/STACK.md` — MoonBit v0.10.5 evidence, source-backed CST direction, testing commands, and cross-target boundary constraints.
- `.planning/research/ARCHITECTURE.md` — source/coordinate, lexer, parser, CST, recovery, and parser/analyzer component boundaries.
- `.planning/research/PITFALLS.md` — version drift, keyword classification, lossless spans, recovery cascades, and validation risks.
- `.planning/research/FEATURES.md` — table-stakes lossless source, diagnostics, recovery, SELECT, and coverage-accounting expectations.

No separate SPEC.md or ADR exists for Phase 1; the project and research documents above are the canonical requirements and evidence.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None. The repository is greenfield and contains no application source, package manifest, or existing parser implementation.

### Established Patterns
- No codebase maps or established implementation patterns exist yet.
- Planning conventions are established in the project documents: MoonBit as the sole core implementation, handwritten recursive descent plus Pratt expressions, immutable lossless CST, and versioned documentation fixtures.

### Integration Points
- The first implementation must create the MoonBit module/package structure under the repository root.
- Later Native, LSP, JavaScript, and Wasm adapters will consume the stable serialized primitive boundary defined here; Phase 1 should not create backend-specific parser forks.

</code_context>

<specifics>
## Specific Ideas

- Preserve the project's differentiator: `parse(print(parse(x))) == x` for unchanged source, including comments, whitespace, newline style, token spelling, unknown text, and error material.
- Treat incomplete SQL as a first-class editor input, not an exceptional test case.
- Prefer the official released Doris documentation corpus as the measurable public coverage authority; do not claim compatibility from generic MySQL behavior, a single FE grammar, or a commercial tool's corpus percentage.
- Keep syntax parsing useful without catalog metadata and leave semantic analysis behind an optional interface.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within the Phase 1 boundary. DML/DDL breadth, configurable formatting, CLI, LSP, Wasm/JavaScript packaging, lint, lineage, and fingerprinting remain in their roadmap phases or v2 scope.

</deferred>

---

*Phase: 1-Core Kernel*
*Context gathered: 2026-08-03*
