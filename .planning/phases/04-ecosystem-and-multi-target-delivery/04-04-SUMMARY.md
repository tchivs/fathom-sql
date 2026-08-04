---
phase: 04-ecosystem-and-multi-target-delivery
plan: 04
subsystem: web-monaco-and-vscode-hosts
tags: [monaco, web, offline, vscode, lsp, stdio, accessibility]
requires:
  - phase: 04-03
    provides: generated JS/linear-Wasm primitive facade and parity schema
  - phase: 04-02
    provides: Native LSP completion, lifecycle, diagnostics, formatting, and UTF-16 contracts
provides:
  - offline Web/Monaco host with relative generated-artifact loading
  - accessible diagnostics, profile, debounce, formatting, refusal, and responsive UI contract
  - standard VS Code LanguageClient stdio host with explicit profile and local executable configuration
  - pinned host package manifests/lockfiles and deterministic host smoke assertions
affects: [ECO-06, ECO-07]
tech-stack:
  added:
    - monaco-editor@0.56.0
    - vscode-languageclient@10.1.0
    - '@vscode/vsce@3.9.2 (development/release only)'
  patterns:
    - relative local JS facade import with UTF-8 byte-authoritative diagnostic conversion
    - full-document formatting edits only on accepted serialized results
    - standard vscode-languageclient stdio lifecycle with plain-text fallback
key-files:
  created:
    - web/package.json
    - web/package-lock.json
    - web/index.html
    - web/src/main.ts
    - web/src/monaco-adapter.ts
    - web/src/styles.css
    - web/scripts/serve.mjs
    - vscode/package.json
    - vscode/package-lock.json
    - vscode/src/extension.ts
    - vscode/src/extension-contract.ts
    - vscode/tsconfig.json
    - vscode/language-configuration.json
    - vscode/README.md
  modified:
    - web/src/main.test.ts
    - web/scripts/offline-smoke.mjs
    - vscode/src/extension.test.ts
    - vscode/scripts/launch-smoke.mjs
    - .gitignore
decisions:
  - "User-approved dependency checkpoint was accepted for monaco-editor 0.56.0, vscode-languageclient 10.1.0, and @vscode/vsce 3.9.2; no other npm packages were added directly."
  - "The browser host imports only the generated repository-relative JS facade; UI code consumes serialized envelopes and never exposes MoonBit ADTs or raw JSON-RPC."
  - "The VS Code client passes profile through initializationOptions and launches only the configured local doris-lsp executable over stdio."
requirements-completed: [ECO-06, ECO-07]
metrics:
  duration: implementation session
  completed: 2026-08-05
  status: complete
actuals:
  tokens: 45102
  tasks: 3
  commits: 3
status: complete
---

# Phase 4 Plan 4: Web/Monaco and VS Code Host Summary

**Offline Web/Monaco diagnostics and formatting plus a standard local-stdio VS Code Doris SQL client, with explicit profile propagation and accessible refusal/fallback states.**

## Accomplishments

- Added an offline Web host using `monaco-editor@0.56.0`, a repository-relative generated JS facade URL, and a dependency-free local static host that serves `.ts` modules and generated Wasm MIME types without a runtime service.
- Implemented visible required Doris profiles `2.1`, `3.x`, and `4.x` only; 150 ms parse debounce; local loading/ready/error/reload states; Monaco markers; UTF-16 navigation derived from UTF-8 byte spans; recoverable/incomplete SQL handling; full-document formatting; and source-byte-preserving formatting refusal.
- Implemented the approved UI contract: exact copy, accessible textual diagnostic rows with glyph/severity/code/message/range/byte detail, keyboard-reachable selection, polite/assertive live-region updates, focus styles, reduced-motion behavior, bounded diagnostic scrolling, and 320/768/1280 responsive layouts.
- Added a standard `vscode-languageclient@10.1.0` extension host with configured local executable path, `TransportKind.stdio`, explicit profile initialization options, Doris document selector, activation/deactivation lifecycle, native diagnostics/formatting/completion delegation, status visibility, and the fixed actionable unavailable-server fallback. `@vscode/vsce@3.9.2` is development/release-only.
- Replaced the original Web/VS Code tautological tests and smoke scripts with serialized boundary, coordinate, profile, dependency, stdio, lifecycle, and refusal assertions.

## Requirement Coverage

| Requirement | Evidence | Status |
|---|---|---|
| ECO-06 | `web/index.html`, `web/src/main.ts`, `web/src/monaco-adapter.ts`, `web/src/styles.css`, and `web/scripts/serve.mjs` provide a relative-artifact offline Monaco host with diagnostics, formatting, profile selection, refusal preservation, reload error, and accessibility/responsive states. | Implemented; 4 Web tests, offline smoke, and real browser checks passed. |
| ECO-07 | `vscode/package.json`, `vscode/src/extension.ts`, `vscode/src/extension-contract.ts`, and `vscode/README.md` provide standard LanguageClient stdio startup, explicit profile propagation, Doris selector, lifecycle, native feature delegation, and unavailable-server plain-text fallback. | Implemented; 3 VS Code tests and protocol smoke passed; final human-hosted VS Code checkpoint remains pending. |

## Dependency Approval

The dependency checkpoint was explicitly approved by the user before installation. Only these direct packages were installed and pinned:

- `web/`: `monaco-editor@0.56.0` runtime.
- `vscode/`: `vscode-languageclient@10.1.0` runtime.
- `vscode/`: `@vscode/vsce@3.9.2` development/release dependency only.

No package was installed into parser-core, Native, or other MoonBit packages. Transitive lockfile entries are package-manager dependencies of the approved direct packages.

## Verification Status

- `node --test web/src/main.test.ts`: 4 passed, 0 failed.
- `node web/scripts/offline-smoke.mjs --offline`: local artifact/profile/refusal contracts passed.
- `node --test vscode/src/extension.test.ts`: 3 passed, 0 failed.
- `node vscode/scripts/launch-smoke.mjs --protocol`: pinned client/stdio/profile/lifecycle/fallback contracts passed.
- Real Chromium browser check via local `web/scripts/serve.mjs`: Parser ready, relative JS artifact loaded, no console errors, incomplete SQL showed recoverable diagnostics, accepted formatting preserved `SET_VAR` hint, refusal left source unchanged, profiles were exactly 2.1/3.x/4.x, and page overflow was false at 320/768/1280 widths.
- Browser responsive/accessibility assertions verified visible Format document control, `role=status`, diagnostic heading association, and UTF-8 byte detail alongside UTF-16 ranges.
- No local VS Code executable was available; host-only activation checkpoint remains explicitly pending.

## Final Human VS Code Checkpoint

**Status: NOT PASSED / PENDING HUMAN HOST.** This environment does not provide a VS Code executable. On a host with VS Code and a local `doris-lsp`, the parent/human must verify activation and initialization, didOpen/didChange/didClose, UTF-16 Problems ranges, comment/hint-preserving `Format Document`, parser-known completion, explicit profile propagation, and unavailable/exiting-server fallback while the document remains editable. This summary deliberately makes no claim that the host-only checkpoint passed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Critical host packaging] Added a local static host launcher**
- **Found during:** Web host implementation.
- **Issue:** The source host uses extension-preserving `.ts` modules without introducing an unapproved bundler; generic static servers may return a non-JavaScript MIME type.
- **Fix:** Added `web/scripts/serve.mjs`, a dependency-free repository-relative local host that serves `.ts` as JavaScript and `.wasm` as Wasm while rejecting path traversal.
- **Files modified:** `web/scripts/serve.mjs`, `web/package.json`.
- **Commit:** `504182b`.
No parser, formatter, CST, schema, LSP transport, database, FE, network, authentication, or second-parser changes were made.

**2. [Rule 2 - Critical host packaging] Served Monaco CSS side-effect imports as local JavaScript modules**
- **Found during:** Parent real browser smoke.
- **Issue:** Monaco ESM imports CSS side effects as module scripts; a generic CSS response caused a strict MIME error and left the UI in `Loading parser artifact…`.
- **Fix:** `serve.mjs` returns a local JS side-effect module that injects the exact CSS text only when `Sec-Fetch-Dest: script`; ordinary stylesheet requests remain `text/css`.
- **Files modified:** `web/scripts/serve.mjs`
- **Commit:** `bc6db54`

**3. [Rule 1 - Bug] Imported the Web UTF-8 byte helper**
- **Found during:** Parent real browser smoke after Parser ready.
- **Issue:** `parseNow` referenced `utf8Bytes` without importing it, causing a page error on the first scheduled parse.
- **Fix:** Added the missing `utf8Bytes` import from `monaco-adapter.ts`.
- **Files modified:** `web/src/main.ts`
- **Commit:** `15cbea5`

## Risks

- Automated Web/VS Code tests, offline/protocol smoke, and real browser UI checks passed. The final VS Code host checkpoint remains environment-dependent; TypeScript source still needs normal extension packaging before VSIX publication.
- The VS Code package keeps TypeScript source and `tsconfig.json` separate from the Native executable; a release pipeline must compile/package the extension for the target VS Code host before publishing a VSIX.
- Linear Wasm remains the Wave 3 compatibility artifact; this Web UI uses the primary generated JS facade and does not introduce a Wasm GC claim.

## Known Stubs

None in the implemented plan surface. The final human VS Code checkpoint is a required environment-dependent verification, not a stub or fallback implementation.

## Self-Check: PASSED

- Web and VS Code package manifests/lockfiles contain the approved pinned direct dependencies.
- Web and VS Code host implementation, tests, smoke scripts, README, language configuration, and local launcher are present.
- Task commits `8540148`, `175f45e`, `504182b`, `bc6db54`, and `15cbea5` exist in repository history.
- Automated host checks and real browser checks passed; the human VS Code checkpoint is explicitly pending and unclaimed.
