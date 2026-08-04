---
phase: 04
slug: ecosystem-and-multi-target-delivery
status: approved
shadcn_initialized: false
preset: none
created: 2026-08-04
reviewed_at: 2026-08-04
---

# Phase 4 — UI Design Contract

> Visual and interaction contract for the offline Web/Monaco demonstration and the VS Code client. This contract covers ECO-06 and ECO-07 only; the parser, formatter, serialized schema, and LSP transport remain the implementation contracts of their respective adapters.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none — manual, static/ESM host UI |
| Preset | not applicable |
| Component library | none; use native HTML controls and existing Monaco/VS Code host primitives |
| Icon library | none; prefer text labels and 16px inline SVG symbols; no icon-only actions |
| Font | UI: system sans (`-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`); editor: `ui-monospace, SFMono-Regular, Menlo, Consolas, monospace` |

The repository has no existing frontend framework, package manifest, component registry, or design tokens. Do not introduce shadcn, a design-system dependency, or speculative product branding for this phase. The visual language is a restrained code-tool surface: neutral panels, a clear editor boundary, compact status metadata, and diagnostics that remain the primary feedback channel.

---

## Spacing Scale

Declared values (all multiples of 4):

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | Icon/text gap, diagnostic marker inset, compact inline padding |
| sm | 8px | Control gap, label-to-field spacing, diagnostic row padding |
| md | 16px | Default control padding, panel padding, editor-to-diagnostics gap |
| lg | 24px | Section padding, toolbar group separation |
| xl | 32px | Main layout gap and wide-screen outer padding |
| 2xl | 48px | Major empty-state vertical separation |
| 3xl | 64px | Page-level top/bottom breathing room on wide screens |

Exceptions: interactive controls use a minimum 44px height (or 44px square hit area) even when their visual content is smaller; Monaco's native line-height may follow the editor font metrics but must not reduce the surrounding control hit area.

---

## Typography

Use only the two weights below: regular 400 and semibold 600.

| Role | Size | Weight | Line Height |
|------|------|--------|-------------|
| Body | 14px | 400 | 1.5 |
| Label | 13px | 600 | 1.3 |
| Heading | 16px | 600 | 1.25 |
| Display | 20px | 600 | 1.2 |

The editor uses a 14px monospace face with a minimum 1.5 line-height. Diagnostic codes, byte spans, and profile metadata use the body size and monospace face; do not use smaller text for essential error information.

---

## Color

The default presentation is a light editor/tooling surface with explicit borders and non-color diagnostic cues.

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60%) | `#F6F8FA` | Page background, toolbar background, empty/loading surfaces |
| Secondary (30%) | `#FFFFFF` | Editor pane, diagnostics pane, cards, select controls |
| Accent (10%) | `#2563EB` | Explicit profile selector focus, `Format document` action, active diagnostic selection, keyboard focus ring |
| Destructive | `#B42318` | Error diagnostic rail/icon, artifact failure, formatting refusal, destructive confirmation only |
| Diagnostic warning | `#7A5A00` | Warning severity only; never used for actions or decoration |
| Border/text neutrals | `#D0D7DE` / `#1F2328` | Pane boundaries, dividers, primary text; maintain contrast independently of accent |

Accent reserved for: the selected profile control, the primary `Format document` button, the currently selected diagnostic row, and visible keyboard focus. It is not a general hover color and must not be applied to every interactive element. Diagnostic severity is never conveyed by color alone: pair the severity color with a text label, a distinct glyph/shape, and the diagnostic code.

---

## Copywriting Contract

| Element | Copy |
|---------|------|
| Primary CTA | `Format document` |
| Empty state heading | `No diagnostics` |
| Empty state body | `Type or paste Doris SQL to see diagnostics here.` |
| Error state | `The local parser artifact could not be loaded. Reload the demo; no network or database connection is required.` |
| Destructive confirmation | `None — this phase has no destructive action. Formatting never replaces source after a refusal.` |

Additional fixed UI copy:

- Profile label: `Doris profile`; selector options: `2.1`, `3.x`, `4.x`; there is no `Auto` or generic-dialect option.
- Editor status: `Parser ready`, `Loading parser artifact…`, `Parser unavailable`, or `Formatting…`.
- Diagnostic counts: `No diagnostics`, `1 diagnostic`, `{n} diagnostics`.
- Valid formatting result: `Formatted; comments and hints preserved.`
- Refusal result: `Formatting unavailable: resolve the reported syntax errors first.`
- VS Code server failure: `Doris language server unavailable. Check the local executable path and try again.`

Copy is sentence case, concise, and actionable. Never expose raw JSON-RPC, MoonBit type names, or backend-specific object layout in user-facing text.

---

## User Flows and Information Hierarchy

### Offline Web/Monaco demonstration (ECO-06)

1. **Load:** The static host imports the checked-in generated JS/Wasm artifact from a relative asset path. Show `Loading parser artifact…`; editor and formatting controls remain disabled until the artifact reports ready.
2. **Choose profile:** Present `Doris profile` as a required, visible select control with `2.1`, `3.x`, and `4.x`. The request always includes the selected profile; no silent default or dialect detection is allowed. The demo may start with an explicitly displayed `4.x` sample selection, but it must never hide the profile value.
3. **Edit:** The Monaco editor is the dominant surface. Parse after the editor's change settles (150ms debounce) and keep the source unchanged while results update. Preserve cursor and selection when diagnostics change.
4. **Inspect:** Show a diagnostics pane beside the editor on wide screens and below it on narrow screens. Each row contains severity label/glyph, stable code, message, and a source range. Selecting a row moves the editor to the UTF-16 display range; the byte span remains available in an accessible detail line or tooltip.
5. **Format:** `Format document` calls the shared formatting facade. While running, disable duplicate activation and expose `Formatting…`. On accepted output, apply the returned full-document edit and show `Formatted; comments and hints preserved.` On refusal/error, leave the editor bytes untouched, retain diagnostics, and show the refusal copy.
6. **Recover:** Incomplete SQL remains editable and is represented as a recoverable/partial state; never replace it with a blank document or a generic error page. Artifact failure has a `Reload demo` action that reloads local assets only.

### VS Code client presentation (ECO-07)

1. On extension activation, launch the Native Doris LSP locally over stdio using the standard VS Code LSP client. Do not add an HTTP endpoint, database connection, authentication flow, or custom remote transport.
2. Use the VS Code document selector/status affordances rather than a custom side panel. The configured Doris profile is visible in the extension status or command configuration and is passed explicitly to the server.
3. On open/change, publish standard LSP diagnostics: squiggles and Problems entries carry severity, stable code, message, and the correct UTF-16 range. Preserve editor content and cursor state on every update.
4. `Format Document` delegates to `textDocument/formatting`; apply returned edits through the normal VS Code edit path. Comments and hints must remain in their original source regions.
5. Completion is presented through the native suggestion widget for parser-known Doris keywords/clauses in incomplete SQL. Do not present catalog-backed table/column intelligence.
6. If the local server cannot start or exits, show the fixed actionable server-failure message in the standard VS Code notification/status surface and keep the document usable as plain text.

### Information priority

1. Source editing and cursor position.
2. Explicit Doris profile and parser/server readiness.
3. Diagnostics tied to exact source ranges.
4. Formatting action and result/refusal state.
5. Secondary metadata such as schema version, release family, byte span, and recovery status.

No marketing hero, dashboard, analytics, connection picker, or branded navigation is part of either surface.

---

## Artifact and Host Contract

- The Web demo is a static host around generated ESM JavaScript, with linear Wasm as an optional equivalent artifact. Assets are bundled or addressed by relative paths; no runtime service, database, Doris FE, network API, or authentication is required.
- The loading state must identify the artifact as local and must not imply that a remote parser is being contacted. A failed import/instantiation is a visible error with `Reload demo`; do not silently fall back to a different parser implementation.
- The host consumes only the versioned serialized envelope and primitive formatting result. UI code must not inspect MoonBit ADTs, backend-specific object layouts, or internal CST instances.
- Display source locations as line/character ranges using the documented UTF-16 policy. Keep UTF-8 byte offsets as the authoritative hidden/detail value for edit diagnostics; never recompute ranges from rendered text.
- VS Code uses the Native executable and standard LSP client protocol; Web and VS Code have separate host packaging and do not share Node-only runtime assumptions.

---

## UI Considerations

Applicable state considerations resolved: 12 covered, 2 backstop, 0 unresolved.

| Category | Element(s) | Status | Resolution / Reason |
|----------|------------|--------|---------------------|
| empty | diagnostics list, editor | ✅ covered | Empty editor keeps an editable blank surface; diagnostics shows the documented `No diagnostics` heading/body and changes to a singular/plural count when results exist. |
| loading | artifact status, format control | ✅ covered | Show `Loading parser artifact…`; disable parse-dependent controls and expose a non-color busy indicator until local JS/Wasm initialization completes. |
| error | artifact status, diagnostic list, format control, VS Code server status | ✅ covered | Artifact/server failure uses the documented actionable copy; parse errors include severity, code, message, and range; formatting refusal leaves source untouched. |
| populated | editor, diagnostics list | ✅ covered | Valid SQL remains the primary editor surface with an explicit profile and either `No diagnostics` or the complete diagnostic list. |
| partial | editor, diagnostics list | ✅ covered | Incomplete/recovered SQL stays editable; recovered status and diagnostics are shown without replacing the document or pretending it is valid. |
| overflow | diagnostics list, navigation/status controls | ✅ covered | Diagnostic rows wrap messages, the list scrolls independently, and panes never create page-level horizontal overflow; long source remains horizontally scrollable inside Monaco. |
| zero-one-many | diagnostics list | ✅ covered | Use exact `No diagnostics`, `1 diagnostic`, and `{n} diagnostics` copy; one row has normal padding and many rows become a bounded scrollable collection. |
| long-text | diagnostic message, server/artifact status, profile metadata | ✅ covered | Wrap long messages at word boundaries, retain the stable code, avoid ellipsis on essential error text, and allow metadata to wrap/reflow below the primary message. |
| loading | VS Code server status | ✅ covered | During local LSP startup, use the standard status/notification surface and keep the document editable; no custom blocking screen is shown. |
| populated | VS Code Problems and suggestion widgets | ✅ covered | Standard VS Code diagnostics and completion widgets carry the same severity/range semantics as the Web demo; no duplicate custom panel is added. |
| overflow | responsive two-pane layout | 🧪 backstop | Verify at 320px, 768px, and 1280px widths that toolbar controls wrap, panes stack below 768px, and all diagnostic text remains reachable without page overflow. |
| long-text | Monaco source and UTF-16 range detail | 🧪 backstop | Verify a long single-line statement and a multi-byte identifier; the editor scrolls horizontally and selecting a diagnostic lands on the correct UTF-16 character without byte-range drift. |
| partial | formatting action | ✅ covered | A recoverable/error tree never receives a partial format; the button reports the documented refusal state and preserves exact source bytes. |
| error | malformed JSON-RPC / malformed SQL | ✅ covered | Protocol-safe errors remain bounded and visible; malformed input cannot crash the host or erase later statements/diagnostics. |

---

## Responsive and Accessibility Contract

- Wide layout (at least 900px): top toolbar, then a two-pane workspace with editor taking roughly 2/3 width and diagnostics roughly 1/3; each pane has its own visible heading and border.
- Compact layout (768px to 899px): retain two panes only when each can remain at least 320px; otherwise stack them. Narrow layout (below 768px): toolbar groups wrap, editor appears first, diagnostics follows, and no diagnostic information is hidden behind hover.
- Keep editor height at least 360px on desktop and 280px on narrow screens. Diagnostics has a bounded scroll region so long lists do not push the editor off-screen.
- Every control has a visible text label or accessible name. Keyboard order is profile → editor → format action → diagnostics; diagnostic selection is keyboard reachable and moves focus to the corresponding editor range.
- Provide a visible 2px focus ring using the accent color with a non-accent fallback outline. Maintain at least WCAG AA contrast (4.5:1 for normal text, 3:1 for large text and controls) and never use color as the only severity/state signal.
- Monaco accessibility support remains enabled. Provide an accessible textual diagnostics list outside the canvas/editor surface, and announce parser/formatting status changes through a polite live region; announce artifact failure as an assertive error once.
- Respect `prefers-reduced-motion`: no required animation; loading uses a static label plus optional low-motion indicator. Do not rely on hover-only behavior, drag gestures, or a pointer-only affordance.
- The primary Web demo language is English for this phase; layout must tolerate long localized strings by wrapping rather than clipping, and all semantic structure must remain usable with zoom up to 200%.

---

## Measurable Verification Checkpoints

These checks are executable against the local artifact and Native LSP without any backend service:

1. **Offline load:** With network access unavailable, open the static demo, observe the local artifact loading state, then reach `Parser ready`; no database/FE/service endpoint is required. A deliberately missing artifact produces the documented error and `Reload demo` without a blank or silent fallback.
2. **Profile and parity surface:** Select each of `2.1`, `3.x`, and `4.x`, parse the same small fixture, and confirm the visible profile and serialized result metadata change together; no `Auto`/generic profile appears.
3. **Diagnostics:** Enter valid `SELECT` SQL and observe `No diagnostics`; enter incomplete SQL and observe a recoverable editor state plus a bounded diagnostic with severity, stable code, message, and source range; select the row and verify editor navigation.
4. **Formatting:** Enter a valid statement containing a comment/hint, activate `Format document`, and confirm the returned formatting edit preserves the comment/hint and reports the success copy. Enter malformed/incomplete SQL and confirm source bytes remain unchanged and the refusal copy is reachable.
5. **Responsive/accessibility:** Exercise keyboard-only navigation and a screen-reader-readable diagnostics list at 320px, 768px, and 1280px. Verify toolbar wrapping, stacked panes when needed, no page horizontal overflow, focus visibility, non-color severity labels, and long-message wrapping.
6. **VS Code lifecycle:** Launch the extension with the local server, open/change/close a document, observe standard Problems diagnostics and `Format Document` edits, then simulate an unavailable executable and confirm the actionable server-failure message while the document remains editable.
7. **Coordinate fidelity:** Use a fixture with non-ASCII text and comments, select a diagnostic, and confirm UTF-16 line/character navigation lands on the intended source while byte spans remain the edit authority.

---

## Explicit Non-Goals

- No redesign or reimplementation of lexer, parser, CST, formatter, serialized schema, coordinate conversion, or LSP transport internals.
- No hosted web service, HTTP/remote LSP transport, database, Doris FE connection, authentication, or network-dependent runtime.
- No second parser implementation, generic SQL/MySQL fallback, automatic dialect detection, or silent profile selection.
- No catalog-backed semantic completion, type information, lint rules, lineage, fingerprints, incremental parsing, or execution behavior.
- No custom VS Code dashboard, webview, analytics panel, marketing landing page, brand system, theme marketplace, or third-party component registry.
- Wasm GC compatibility is not promised by this UI contract; linear Wasm and generated JavaScript are the supported Web artifacts unless separately smoke-tested.

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| none | none | not applicable — no shadcn or third-party registry is initialized |

---

## Checker Sign-Off

- [x] Dimension 1 Copywriting: PASS
- [x] Dimension 2 Visuals: PASS
- [x] Dimension 3 Color: PASS
- [x] Dimension 4 Typography: PASS
- [x] Dimension 5 Spacing: PASS
- [x] Dimension 6 Registry Safety: PASS

**Approval:** PASS — UI contract verified for ECO-06/ECO-07; no blocking issues.
