# Phase 4: Ecosystem and Multi-Target Delivery - Context

**Gathered:** 2026-08-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the same Doris SQL parser through a Native LSP/CLI boundary and stable JavaScript/Wasm facades, with shared serialized results and coordinate semantics, then provide an offline Web/Monaco demonstration and a VS Code client integration. The phase is limited to ECO-01 through ECO-07. It does not add semantic analysis, linting, lineage, fingerprinting, database connectivity, Doris FE integration, or a second parser implementation.

</domain>

<decisions>
## Implementation Decisions

### Public boundary and implementation ownership
- **D-01:** Keep `api/` as the shared core facade. Native LSP, JavaScript, Wasm, Web/Monaco, and VS Code code must be adapters around the existing parser and formatter APIs; parser and formatter packages remain free of host-specific transport or FFI code.
- **D-02:** Reuse `api.parse_with_ids`/`api.parse_with_metadata` and `api.format_with_ids`/`api.format_with_metadata` as the Phase 4 core entrypoints. The Phase 3 `statement_offsets` contract is the source for formatting edit ranges.
- **D-03:** Native LSP uses JSON-RPC over stdio, not a network service. It must operate offline and must not start or connect to Doris FE, a database, or an HTTP server.

### Serialized schema and coordinates
- **D-04:** Expose a versioned serialized result envelope derived from the existing `ParseResult`, `PrimitiveNode`, `PrimitiveDiagnostic`, and `FormatResult` shapes. Do not expose MoonBit ADTs or backend-specific object layouts. Schema evolution is explicit and must reject or report unsupported versions rather than silently changing shape — **Reversibility:** one-way — Native, JavaScript, Wasm, and editor consumers will depend on the published field and version contract.
- **D-05:** Preserve source spans as UTF-8 byte offsets in the shared schema. LSP-facing positions additionally use a documented UTF-16 line/character conversion derived from the original source bytes; byte offsets remain the lossless/editing authority — **Reversibility:** one-way — changing coordinate units after editor integrations ship would invalidate ranges and parity fixtures.
- **D-06:** Raw source fidelity, including non-UTF-8 bytes supported by the parser, must not be lost at a host boundary. The implementation may choose the concrete JSON/string/byte encoding after research, but every target must round-trip the same source bytes or explicitly represent their transport encoding in the schema.
- **D-07:** Native, JavaScript, and linear-Wasm wrappers share one parity fixture set and compare serialized output, diagnostics, spans, profile metadata, and formatting edits byte-for-byte where the target contract permits. Wasm GC is not a Phase 4 compatibility promise unless the exact runtime smoke test is added without weakening the linear-Wasm contract.

### LSP and editor behavior
- **D-08:** The Native LSP vertical slice is ordered around initialize/shutdown/exit, document open/change/close, diagnostics publication, document formatting, and completion for incomplete SQL. Malformed JSON-RPC and malformed/incomplete SQL must produce bounded protocol-safe errors rather than crash the process.
- **D-09:** Completion is syntax-aware and parser-known: suggestions come from Doris keyword/clause/profile information already owned by the parser/token packages. Catalog-backed semantic completion is out of scope.
- **D-10:** Formatting edits preserve comments and hints through the existing formatter contract and map `statement_offsets`/source byte spans to documented LSP ranges. The LSP does not reimplement formatting.

### Distribution and demonstrations
- **D-11:** Keep Native LSP and CLI packaging separate from browser host code. The JS wrapper is the primary browser surface; linear Wasm is an additional portable artifact. Exact MoonBit package/export syntax and npm packaging are implementation details for research/planning, not reasons to add Node dependencies to parser-core.
- **D-12:** The Web/Monaco demonstration runs offline with the generated JS/Wasm artifact and does not require a service, database, or authentication. The VS Code extension uses the standard LSP client protocol and launches/connects to the Native server locally.
- **D-13:** Implement in vertical order: (1) shared serialized/coordinate contract and Native LSP diagnostics/formatting tracer, (2) completion and protocol hardening, (3) JS/Wasm exports plus parity fixtures, (4) offline Web/Monaco and VS Code packaging. Each slice must be executable and independently smoke-tested before expansion.

### Claude's Discretion
- Exact local JSON-RPC codec implementation and message framing details, provided they obey LSP 3.17 framing and bounded-error behavior.
- Exact package directory names, MoonBit `moon.pkg` target options, export annotations, byte encoding (base64 versus byte arrays), and npm/VS Code build tooling after verifying the current MoonBit toolchain.
- Which minimal LSP completion contexts and which representative parity fixtures best cover the locked requirements without inventing a broader language service.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Scope and requirements
- `.planning/ROADMAP.md` §Phase 4 — goal, ECO-01 through ECO-07 scope, success criteria, and dependency on Phase 3.
- `.planning/REQUIREMENTS.md` §Ecosystem Delivery — exact acceptance requirements ECO-01 through ECO-07.
- `.planning/PROJECT.md` — single MoonBit core, lossless CST, Native/Wasm/JavaScript target constraints, and parser/analyzer boundary.
- `.planning/research/STACK.md` §Backend and Public-API Boundary — recommended Native, JavaScript, Wasm, serialized primitive, LSP, and package choices.

### Existing Phase 3 contracts
- `.planning/phases/03-formatting-and-safe-edits/03-VERIFICATION.md` — verified Phase 3 goal and FMT-01 through FMT-04 evidence.
- `.planning/phases/03-formatting-and-safe-edits/03-01-SUMMARY.md` — formatter API, refusal diagnostics, and `api.format_text`/`statement_offsets` contract.
- `.planning/phases/03-formatting-and-safe-edits/03-04-SUMMARY.md` — Native executable adapter, exit-code behavior, and reuse of `api.format_with_ids`.

### Code integration points
- `moon.mod` — module identity, pinned toolchain note, and preferred Native target.
- `api/moon.pkg` — current facade dependency boundary.
- `api/api.mbt` — `ParseResult`, primitive CST/diagnostic shapes, parse/format entrypoints, schema metadata, and statement helpers.
- `formatter/options.mbt` — six format options and string-id mappings.
- `formatter/format.mbt` — canonical formatter output and statement offsets.
- `doris-sql/moon.pkg` — current executable package and host-only dependency boundary.
- `doris-sql/main.mbt` — thin Native argv/stdio/exit wiring pattern.
- `doris-sql/args.mbt` — explicit CLI profile and option parsing conventions.
- `doris-sql/run.mbt` — pure adapter pattern and diagnostic rendering.

### External protocol references
- `https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/` — LSP 3.17 lifecycle, text synchronization, diagnostics, formatting, completion, and UTF-16 position semantics.
- `https://docs.moonbitlang.com/en/latest/language/ffi.html` — target/FFI portability constraints.
- `https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html` — package kinds, exports, and backend link configuration.
- `https://docs.moonbitlang.com/en/latest/toolchain/moon/commands.html` — cross-target build/test commands.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `api.ParseResult` already carries schema metadata, source bytes, recursive primitive nodes, diagnostics, profile metadata, and byte spans.
- `api.format_text` and its ID/metadata wrappers already provide the shared formatting path; `formatter.FormatResult.statement_offsets` is available for edit ranges.
- `doris-sql/run.mbt` demonstrates a pure adapter core separated from Native process wiring in `main.mbt` and `ffi.mbt`.
- `token/` owns Doris profile and keyword classification data, which is the source for parser-known completion.

### Established Patterns
- Core packages are library-only and backend-neutral; Native libc FFI is confined to `doris-sql/`.
- Source fidelity is byte-based and spans are half-open; diagnostics carry stable codes and statement IDs.
- Configuration is explicit through API arguments; no environment-dependent behavior or runtime service is expected.
- Formatter refusal is absolute for error/missing/skipped material, while parse diagnostics are preserved and prepended.

### Integration Points
- Add adapter packages around `api/`, not imports from `api` back into parser/formatter.
- Reuse the Native executable package conventions for stdio and exit behavior, but keep JSON-RPC framing and LSP document state in a dedicated LSP adapter.
- Add cross-target fixtures at the public serialization boundary; do not compare internal MoonBit values.
- Put browser/editor host scheduling, Monaco wiring, and VS Code activation outside the parser core and document their offline artifact flow.

</code_context>

<specifics>
## Specific Ideas

The existing project research already recommends LSP 3.17, ESM JavaScript wrappers, linear Wasm, primitive serialized results, and a thin Native adapter. Phase 4 should turn those recommendations into a small end-to-end tracer before broadening the surface.

</specifics>

<deferred>
## Deferred Ideas

- Wasm GC compatibility beyond the explicitly tested linear-Wasm artifact.
- Catalog-backed semantic completion, type information, linting, lineage, fingerprints, and incremental parsing; these belong to later requirements or future phases.
- Runtime HTTP service, remote LSP transport, database/FE integration, and server deployment.

</deferred>

---

*Phase: 04-ecosystem-and-multi-target-delivery*
*Context gathered: 2026-08-04*
