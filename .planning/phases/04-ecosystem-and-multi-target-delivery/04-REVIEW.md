---
phase: 04-ecosystem-and-multi-target-delivery
reviewed: 2026-08-05T00:00:00Z
depth: standard
files_reviewed: 38
files_reviewed_list:
  - lsp/main.mbt
  - lsp/protocol.mbt
  - lsp/framing.mbt
  - lsp/documents.mbt
  - lsp/handlers.mbt
  - lsp/coordinates.mbt
  - lsp/framing_test.mbt
  - lsp/protocol_test.mbt
  - lsp/lifecycle_test.mbt
  - lsp/completion_test.mbt
  - lsp/diagnostics_formatting_test.mbt
  - lsp/moon.pkg
  - binding/exports.mbt
  - binding/schema.mbt
  - binding/json.mbt
  - binding/coordinates.mbt
  - binding/moon.pkg
  - parity/parity_test.mbt
  - parity/run_native.mbt
  - parity/run_js.mbt
  - parity/run_wasm.mbt
  - parity/coordinates_test.mbt
  - parity/schema_test.mbt
  - parity/export_smoke_test.mbt
  - parity/moon.pkg
  - parity/fixtures/corpus.json
  - parity/fixtures/target-matrix.json
  - completion/completion.mbt
  - completion/moon.pkg
  - web/index.html
  - web/src/main.ts
  - web/src/monaco-adapter.ts
  - web/src/main.test.ts
  - web/src/styles.css
  - web/scripts/serve.mjs
  - web/scripts/offline-smoke.mjs
  - web/package.json
  - vscode/src/extension.ts
  - vscode/src/extension-contract.ts
  - vscode/src/extension.test.ts
  - vscode/scripts/launch-smoke.mjs
  - vscode/package.json
  - vscode/tsconfig.json
  - vscode/language-configuration.json
  - vscode/README.md
  - .gitignore
findings:
  critical: 0
  warning: 4
  info: 5
  total: 9
status: clean
---

# Phase 04: Code Review Report

**Reviewed:** 2026-08-05
**Depth:** standard
**Files Reviewed:** 38
**Status:** issues_found

## Summary

Reviewed the Phase 04 ecosystem deliverables: the Native LSP server (`lsp/`), the JS/Wasm binding facade (`binding/`), cross-target parity harness (`parity/`), parser-owned syntax completion (`completion/`), the offline Monaco web host (`web/`), and the VS Code stdio client (`vscode/`). The user's unrelated IntelliJ plugin commits (`quick-260805-*`, `jetbrains/`) were excluded.

The security-relevant foundations are sound and verified by reading:

- **LSP framing** is bounded: `MAX_HEADER_BYTES` (16 KB) and `MAX_FRAME_BYTES` (8 MB) are checked before allocation; `decimal()` is overflow-safe; huge/negative Content-Length values yield `FrameTooLarge`; EOF mid-header/mid-body terminates cleanly; header size is enforced while reading; parser/lexer limits (8 MB bytes, 1M tokens, 10K recovery steps, 100 diagnostics) bound the work per frame. No crash or unbounded-allocation path found on malformed frames.
- **UTF-16 coordinates** are correct for multibyte content: 4-byte UTF-8 sequences count as 2 UTF-16 units, CRLF counts as a single line break, `position_to_byte` is the consistent inverse, and dedicated tests cover emoji/CRLF/round-trips. Invalid UTF-8 is handled conservatively and cannot reach the native adapter through the JSON boundary.
- **Binding ABI** is primitive-only: `doris_*_v1` take `Bytes`/primitives and return UTF-8 JSON bytes; no MoonBit ADT, handle, or address crosses the boundary; every failure maps to a stable `doris.error.v1` envelope code; exports are pinned in `binding/moon.pkg` for both JS and Wasm.
- **Completion** is bounded (max 32 candidates, two-pass preference, lexer capped at 1M tokens, parse runs under the shared resource limits) and cannot panic on partial input — the lexer emits `Error` tokens for unterminated/invalid material rather than panicking.
- **Web host** uses relative assets only (no `http(s)` URLs), an explicit `4.x` default with no "Auto" profile, `textContent` for diagnostic messages, and an actionable offline artifact-failure banner.
- **VS Code client** uses stdio transport only, a `file`-scheme document selector with no remote fallback, an actionable failure message, and stops the client on `deactivate`.
- **npm supply chain** verified against the live registry: `monaco-editor@0.55.1`, `vscode-languageclient@10.1.0`, and `@vscode/vsce@3.9.2` (dev-only) all exist on registry.npmjs.org and are exact-pinned in `package-lock.json` files.

Four warnings and five info items were found; none are exploitable security vulnerabilities, but the `write_frame` partial-write bug (WR-01) and the unloadable VS Code entry point (WR-03) should be fixed before these components are relied upon.

Note: `moon test` could not be executed in this environment (toolchain cache absent; network fetch to mooncakes.io hangs). Static review was performed against the committed sources; the in-repo test suite covers the framing, coordinate, lifecycle, completion, and parity contracts described above.

**Fix status:** All 4 warnings resolved (WR-01 `dca4c92`, WR-04 `0489a0f`, WR-02 `1335267`, WR-03 `b3827ab`); the 5 info items remain open. The fixer executed the full verification suite in the main checkout: `moon test --target native test parity doris-sql lsp` 188/188 passed, `moon check --target native` 0 errors, `node --test web/src/main.test.ts vscode/src/extension.test.ts` 7/7 passed, web offline smoke passed, vscode protocol smoke passed, `npm run build` (tsc) passed, and a pipelined-frames smoke against the native lsp binary passed.

## Warnings

### WR-01: Partial writes corrupt the LSP frame stream

**File:** `lsp/framing.mbt:148-156`
**Issue:** `write_frame` retries a partial write by calling `write_fd(1, output, output.length() - offset)` with the *whole* buffer. `#borrow(ptr)` passes a pointer to byte 0 of `output`, so the retry re-sends the frame prefix (`Content-Length: …\r\n\r\n` plus leading body bytes) instead of resuming at `offset`. Any partial write — which is realistic for frames near the 8 MB limit (Linux pipe buffer is 64 KB) whenever the client drains slowly — permanently desyncs the byte stream: the client parses a duplicated header + truncated/garbled body and the connection stays broken until the server restarts. The `read_exact` loop has the same pattern but correctly slices `chunk[0:got]`, so it is not affected.
**Fix:**
```moonbit
let written = write_fd(1, output[offset:], output.length() - offset)
```
(Slicing copies the remainder, which is acceptable at this frequency; alternatively accumulate into a dedicated writer that tracks its own cursor.)

**Resolved:** `dca4c92` — `write_frame` now delegates to `write_all`, which passes the remainder slice (`output[offset:].to_owned()`) to the writer so a retry resumes at the exact offset and never re-sends the frame prefix. Added regression tests proving partial writes reassemble the original frame and that writer errors abort the loop (lsp 18/18, full native suite 188/188).

### WR-02: `positionEncoding` advertised as an array instead of a string

**File:** `lsp/handlers.mbt:158`
**Issue:** LSP 3.17 defines `ServerCapabilities.positionEncoding` as a single `PositionEncodingKind` *string* (`"utf-8" | "utf-16" | "utf-32"`). The server sends `Json::array([Json::string("utf-16")])`. Strict clients reject or ignore the malformed capability; `vscode-languageclient` ignores it and falls back to its `utf-16` default, which happens to match the server's internal conversion — so the impact is benign today, but the advertised capability is protocol-incorrect and a stricter client could assume `utf-8` (LSP default) or refuse negotiation.
**Fix:** `"positionEncoding": Json::string("utf-16")`

**Resolved:** `1335267` — the initialize result now advertises the single string `"utf-16"`; verified over the wire in the framed initialize response of the native lsp binary.

### WR-03: VS Code extension entry point cannot be loaded

**File:** `vscode/package.json:9` (with `vscode/tsconfig.json`)
**Issue:** `"main": "./src/extension.ts"` points at a TypeScript source file, and the package has no compile/build script (`"scripts"` contains only `vsce package`). The VS Code extension host loads the `main` entry through a Node CommonJS require; it cannot execute `.ts` (the bundled VS Code runtime predates Node type stripping, and the extension host does not use it). `vsce package` therefore produces an extension whose `activate` throws on load. The phase README correctly flags the host checkpoint as pending, but as committed the extension is structurally unrunnable, not merely unverified.
**Fix:** add a compile step (e.g. `tsc` with the existing `tsconfig.json`, which already emits to `dist/`) and set `"main": "./dist/extension.js"`, e.g.:
```json
"scripts": { "compile": "tsc -p .", "package": "npm run compile && vsce package" },
"main": "./dist/extension.js"
```
Add `typescript` as a devDependency (exact-pinned, matching the supply-chain policy).

**Resolved:** `b3827ab` — `"main"` points at `./dist/extension.js`; scripts add `compile` (`tsc -p .`), `build`, and `package` (compile + `vsce package`); `typescript@5.9.3` is an exact devDependency resolvable offline from the npm cache. `tsconfig.json` enables `allowImportingTsExtensions` + `rewriteRelativeImportExtensions` (the emitted CJS requires `./extension-contract.js`) and excludes test files; the `vscode` module is declared ambiently because the extension host provides it at runtime (`@types/vscode` is not cacheable offline). The launch smoke now asserts `main`/build wiring and that `dist/extension.js` is compiled CJS. `node --test vscode/src/extension.test.ts` still runs the TS sources directly (3/3 pass).

### WR-04: Header read is quadratic and syscall-per-byte (CPU DoS amplification)

**File:** `lsp/framing.mbt:120-141`
**Issue:** `read_frame` reads the header one byte at a time (one `read` syscall per byte, up to `MAX_HEADER_BYTES` = 16 KB) and calls `header.to_bytes()` on every iteration, copying the entire accumulated buffer — O(n²) ≈ 128 MB of memcpy plus 16 K syscalls per frame. Memory is bounded (the security requirement is met), but a client streaming near-limit headers that never terminate can consume tens of milliseconds of CPU per frame, an avoidable local DoS amplification. Legitimate small headers are unaffected.
**Fix:** track `header_length` as a counter and inspect only the trailing 4 bytes (`header.to_bytes()[length-4:]` only when `length >= 4`), or read the header into a fixed 16 KB buffer in chunks instead of one byte at a time.

**Resolved:** `0489a0f` — the header is assembled from 4 KB chunk reads capped at the historical 16 KB + 1 boundary, with pure scan helpers (`first_terminator_end`, `header_end_in`) that detect the first terminator either fully inside a chunk or straddling a chunk boundary. Because a chunk read can over-read into the body — and under client pipelining into the next frame — `read_frame` now takes a `FrameSource` whose pending buffer carries those bytes across calls, so no byte is lost or re-read (verified by an end-to-end smoke feeding three pipelined frames in a single write). Overflow-safe decimal parsing is unchanged; white-box tests cover boundary straddling, near-limit headers, and frame-limit overflow.

## Info

### IN-01: `innerHTML` with interpolated values in diagnostics rendering

**File:** `web/src/main.ts:122`
**Issue:** `button.innerHTML` interpolates `${glyph}`, `${label}`, `${diagnostic.code}`, and numeric ranges. `glyph`/`label` come from a fixed set and the ranges are numbers, but `diagnostic.code` is injected into the HTML string. Today this is not exploitable — parser/format diagnostic codes are hardcoded constants (`DORIS-PARSE-002`, `DORIS-FORMAT-001`, …) and the user-influenced `message` is correctly applied via `textContent` afterward — but the pattern is a latent stored-XSS trap if the wire schema ever allows codes derived from input.
**Fix:** build the row with `document.createElement`/`textContent` (as is already done for `.diagnostic-message`), or escape the interpolated values.

### IN-02: Content-Length header match is case-sensitive

**File:** `lsp/framing.mbt:42-75`
**Issue:** `content_length` matches the literal prefix `b"Content-Length: "`. RFC field names are case-insensitive; a well-behaved client sending `content-length:` is rejected with `MissingContentLength`. The LSP spec's canonical form is `Content-Length`, so this works with all mainstream clients, but a case-insensitive comparison would be strictly more robust at negligible cost.

### IN-03: Duplicate Content-Length headers — last one wins

**File:** `lsp/framing.mbt:42-75`
**Issue:** if a header block contains two `Content-Length` lines with different values, `found` is silently overwritten and the last value is used. RFC 9110 requires rejecting duplicates with differing values. Same-single-value duplicates are also accepted. Low practical risk (framing is a private channel), but cheap to harden.

### IN-04: Dev server serves the whole repository root; unhandled stream errors

**File:** `web/scripts/serve.mjs:23-39`
**Issue:** the docroot is `repositoryRoot` (the entire repo), so `http://127.0.0.1:4173/.planning/…` or any other repo file is readable by any local process/browser page while the demo runs; the traversal guard only blocks paths *outside* the repo. Additionally, `createReadStream(file).pipe(response)` has no error handler — if a file is deleted mid-serve, the unhandled `'error'` event crashes the dev server.
**Fix:** resolve the docroot to `web/` instead of the repository root (still serving `/web/index.html` at `/`), and attach `stream.on('error', () => response.destroy())`.

### IN-05: LanguageClient accumulates in `context.subscriptions` across restarts

**File:** `vscode/src/extension.ts:60-62`
**Issue:** every invocation of `start()` (including `doris.restartLanguageServer`) pushes the newly created `LanguageClient` into `context.subscriptions` after `stopClient()` already stopped the previous one. Repeated restarts accumulate disposed clients that are only released when the host deactivates. `vscode-languageclient` tolerates the double `stop()`/`dispose()`, so this is a minor resource-accumulation wart, not a functional break.
**Fix:** subscribe the client once (e.g., keep a single `current` reference and `context.subscriptions.push(client)` only when it is first created), or track and remove the previous subscription on restart.

---

_Reviewed: 2026-08-05_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
