---
phase: 04-ecosystem-and-multi-target-delivery
fixed_at: 2026-08-05T03:19:52Z
review_path: .planning/phases/04-ecosystem-and-multi-target-delivery/04-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 04: Code Review Fix Report

**Fixed at:** 2026-08-05T03:19:52Z
**Source review:** `.planning/phases/04-ecosystem-and-multi-target-delivery/04-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 4 (all Warnings; Info items out of scope per assignment)
- Fixed: 4
- Skipped: 0

**Verification environment:** All edits, builds, and tests ran in the main checkout
`/opt/source/Fathom` (`workflow.use_worktrees` is `false`), one sequential commit per
finding. MoonBit toolchain `moon 0.1.20260724` is fully cached offline; `mooncakes.io`
fetch is not required. `gsd-tools.cjs` is not installed in this environment, so commits
were made with plain `git commit` using the same `fix(04): …` conventional format
(no `--no-verify`; no custom hooks are present).

## Fixed Issues

### WR-01: Partial writes corrupt the LSP frame stream

**Files modified:** `lsp/framing.mbt`, `lsp/framing_test.mbt`
**Commit:** `dca4c92`
**Applied fix:** `write_frame` retried a partial write with the whole buffer
(`write_fd(1, output, output.length() - offset)`), so `#borrow(ptr)` re-sent the frame
prefix from byte 0 and a split write permanently desynced the stream. The loop is now
`write_all`, which passes the remainder slice (`output[offset:].to_owned()`) to the
writer so a retry resumes at the exact offset. Added two regression tests: a slow-consumer
mock that proves partial writes reassemble the original frame byte-for-byte, and a writer-
error abort test. `write_all` is `pub` only because `framing_test.mbt` is a black-box
(`*_test.mbt`) test file; the lsp package is an executable, so there is no external API
surface.

### WR-04: Header read is quadratic and syscall-per-byte (CPU DoS amplification)

**Files modified:** `lsp/framing.mbt`, `lsp/main.mbt`, `lsp/framing_wbtest.mbt` (new)
**Commit:** `0489a0f`
**Applied fix:** Replaced the byte-at-a-time header loop (one `read` syscall per byte plus
`header.to_bytes()` per iteration — O(n²) memcpy, ~128 MB per near-limit frame) with 4 KB
chunked reads capped at the historical 16 KB + 1 boundary. Two pure scan helpers reproduce
the exact first-terminator-wins semantics, including a terminator straddling a chunk
boundary: `first_terminator_end` and `header_end_in`. Because a chunk read can over-read
into the body — and under client pipelining into the next frame — `read_frame` now takes a
`FrameSource` whose `pending` buffer carries over-read bytes across calls, so no byte is
ever lost or re-read (the byte-at-a-time reader never over-read; the pushback preserves
that contract). `read_exact` consumes the over-read prefix before touching the pipe, and
`content_length`/`decimal` overflow safety is untouched. White-box tests
(`framing_wbtest.mbt`) cover boundary straddling (including at 16 KB scale), near-limit
header detection, and frame-limit overflow; an end-to-end smoke feeds three pipelined
frames in a single write to the native binary and decodes all three with a clean exit.

### WR-02: `positionEncoding` advertised as an array instead of a string

**Files modified:** `lsp/handlers.mbt`
**Commit:** `1335267`
**Applied fix:** LSP 3.17 requires `ServerCapabilities.positionEncoding` to be a single
`PositionEncodingKind` string. The initialize result now emits
`Json::string("utf-16")` instead of `Json::array([...])`. Verified over the wire in the
framed initialize response of the native lsp binary.

### WR-03: VS Code extension entry point cannot be loaded

**Files modified:** `vscode/package.json`, `vscode/package-lock.json`,
`vscode/tsconfig.json`, `vscode/src/vscode.d.ts` (new), `vscode/README.md`,
`vscode/scripts/launch-smoke.mjs`
**Commit:** `b3827ab`
**Applied fix:** The extension host loads `main` through a Node CommonJS require and cannot
execute `.ts`; the manifest pointed at `./src/extension.ts` with no compile step. Now:
`"main": "./dist/extension.js"`; scripts add `compile` (`tsc -p .`), `build`, and
`package` (`compile && vsce package`); `typescript@5.9.3` pinned as an exact devDependency.
Offline constraint verified: `npm install --offline --save-dev --save-exact typescript@5.9.3`
succeeded from the npm cache (5.9.3 tarball + packument present). `tsconfig.json` enables
`allowImportingTsExtensions` + `rewriteRelativeImportExtensions` (emitted CJS requires
`./extension-contract.js`), and excludes `*.test.ts` (no `@types/node` offline; the tests
keep running on TS sources via Node type stripping — `node --test vscode/src/extension.test.ts`
still passes 3/3). `src/vscode.d.ts` declares the host-provided `vscode` module ambiently
(`@types/vscode` is not cacheable offline). The launch smoke now asserts `main`/build wiring
and that `dist/extension.js` is compiled CJS; the 04-04 plan's Task 3 verification line now
includes `(cd vscode && npm run build)`.

## Skipped Issues

None — all in-scope findings were fixed.

---

## Verification (final, run in main checkout)

| Gate | Result |
|---|---|
| `moon test --target native test parity doris-sql lsp` | **188 passed, 0 failed** (baseline 181 + 7 new: 2 WR-01 + 4 WR-04 + 1 net package-count delta; zero regressions) |
| `moon check --target native` | **0 errors** (214 pre-existing style warnings) |
| `node --test web/src/main.test.ts vscode/src/extension.test.ts` | **7 passed, 0 failed** (web 4 + vscode 3) |
| `node web/scripts/offline-smoke.mjs --offline` | passed |
| `node vscode/scripts/launch-smoke.mjs --protocol` | passed (incl. new main/build/dist assertions) |
| `npm run build` (vscode, tsc offline) | passed — `dist/extension.js` + `dist/extension-contract.js` emitted |
| Native lsp pipelined-frames smoke | 3 frames in one write (initialize/shutdown/exit) → 2 correct responses, clean exit, `positionEncoding:"utf-16"` |

The lsp package grew from 12 to 18 tests (2 WR-01 + 4 WR-04 white-box); no existing test
was modified except adding new cases to `framing_test.mbt`.

## Kept Open

- All 5 Info findings (IN-01..IN-05) — out of scope per assignment; documented in
  `04-REVIEW.md` and intentionally unfixed.

---

_Fixed: 2026-08-05T03:19:52Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
