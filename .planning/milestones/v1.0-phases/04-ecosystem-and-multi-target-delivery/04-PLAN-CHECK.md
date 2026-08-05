# Phase 4 Plan Check

**Status: PASS**
**Rechecked:** 2026-08-04
**Plans verified:** 5 (`04-00` through `04-04`)

## Prior blocker closure

1. **Research decisions — CLOSED.** `04-RESEARCH.md` has no unresolved `## Open Questions` section. Its `## Resolved Decisions and Execution Probes` section explicitly closes the five previously open decisions: linear-Wasm byte transport/ownership, the `doris.parse.v1`/`doris.format.v1` inline-root byte schema, the supported JS/linear-Wasm browser/runtime matrix, local VSIX/user-configured Native executable packaging, and the single full-document formatting edit. The section also assigns the remaining toolchain-specific ABI work to concrete Wave 0 probes rather than leaving a product decision unresolved.

2. **Real Wave 0 harnesses and dependencies — CLOSED.** `04-00-PLAN.md` is a real `wave: 0` plan with two executable tasks. Task 1 creates the schema, coordinate, LSP, export, and parity test/runners; Task 2 creates the Web and VS Code host smoke scripts. The later plans declare explicit dependencies on `04-00` (`04-01`, `04-02`, `04-03`, and `04-04` directly or transitively), and all formerly `MISSING` verification placeholders are now concrete commands. External editor packages remain behind the blocking dependency checkpoint in `04-04` Task 1.

3. **Single schema producer and decoded parity — CLOSED.** `04-01` Task 1 owns the versioned schema/coordinate contract, while `04-03` Task 1 explicitly imports the single authoritative `binding/schema.mbt` producer for Native LSP, Native, JS, and linear-Wasm. `04-00` Task 1 creates the decoded parity harness and all target runners; `04-03` Task 2 requires shared fixtures covering profiles, valid/recovered/error SQL, comments/hints, CRLF, non-ASCII input, formatting refusal, raw-byte transport, recursive nodes, trivia/error leaves, spans, diagnostics, and formatting output. This is an explicit cross-target decoded comparison, not a superficial build-only check.

4. **Independent VS Code human checkpoint — CLOSED.** `04-04` Task 4 is a separate blocking `checkpoint:human-verify`, independent of the Web task. It acknowledges that no local `code` executable exists and requires a host with VS Code and the configured local `doris-lsp`; its acceptance checks cover activation/initialization, `didOpen`/`didChange`/`didClose`, Problems diagnostics with stable code/severity/UTF-16 ranges, comment/hint-preserving Format Document, parser-known completion, unavailable/exiting-server fallback, document usability, and explicit profile propagation. The protocol harness remains in `04-00` Task 2 for deterministic non-VS-Code verification.

5. **Complete UI acceptance checkpoints — CLOSED.** `04-04` Task 2 action and `<done>` text now enumerate the approved UI contract: offline relative-artifact loading and reload failure, all `2.1`/`3.x`/`4.x` profiles, diagnostics and refusal behavior, comment/hint preservation, 320/768/1280 responsive checkpoints, keyboard-only flow, live-region announcements, non-color severity cues, and long UTF-16/multibyte coordinate cases. The plan-level verification also explicitly references the complete `04-UI-SPEC.md` checkpoint matrix.

## Coverage and plan integrity

| Requirement | Covering plans | Status |
|---|---|---|
| ECO-01 | 04-00, 04-01, 04-02 | Covered: Native lifecycle, synchronization, versioning, diagnostics, and protocol hardening |
| ECO-02 | 04-00, 04-01 | Covered: centralized byte/UTF-16 conversion and safe full-document formatting edits |
| ECO-03 | 04-00, 04-02, 04-04 | Covered: parser-owned syntax completion plus Native/VS Code host paths |
| ECO-04 | 04-00, 04-03, 04-04 | Covered: primitive JS/linear-Wasm facades and Web consumption |
| ECO-05 | 04-00, 04-01, 04-03 | Covered: versioned schema, source/trivia/error/span/diagnostic fields, and shared decoded parity |
| ECO-06 | 04-00, 04-03, 04-04 | Covered: offline Web/Monaco host and UI acceptance matrix |
| ECO-07 | 04-00, 04-04 | Covered: protocol harness plus independent human-hosted VS Code checkpoint |

- **Tasks:** Every `auto`/`tracer` task in `04-00`–`04-04` has files, a concrete action, an automated verification command, and measurable completion criteria. The two `checkpoint:human-verify` tasks in `04-04` intentionally use checkpoint fields instead of auto-task fields.
- **Dependencies:** `04-00` is Wave 0; `04-01` is Wave 1; `04-02` is Wave 2; `04-03` is Wave 3; and `04-04` is Wave 4. The graph is acyclic and the declared dependencies match this order.
- **Must-haves and links:** Each plan declares user-observable truths, artifacts, and key links. The critical links—API to schema serializer to LSP diagnostics, API formatter to TextEdit, shared schema to all target exports, decoded fixtures to all runners, and hosts to their facades/Native LSP—are present in task actions.
- **Context and architecture:** Locked Native stdio, primitive serialized boundaries, UTF-8 byte authority, linear Wasm, syntax-only completion, offline hosts, and no FE/database/network are honored. Tasks follow the research responsibility map and do not add deferred semantic or remote features.
- **Validation configuration:** Nyquist validation is explicitly disabled in `.planning/config.json`; the plans nevertheless provide focused executable commands and the required human checkpoints. No tests or formatters were run during this static plan review.
- **Scope advisory:** The calibrated estimate checks report 24k/36k/26k/34k/38k tokens for `04-00`–`04-04`, respectively, each below the 100k smart-zone budget. Confidence is low because no completed-phase actuals are available; this is an execution-monitoring advisory, not a plan-blocking defect.

## Conclusion

All prior blockers are closed with explicit evidence in the revised research and plan artifacts. Phase 4 plans are ready for execution via `/gsd-execute-phase 4`.
