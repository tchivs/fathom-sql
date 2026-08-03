---
phase: 1
slug: core-kernel
status: approved
shadcn_initialized: false
preset: none
created: 2026-08-03
reviewed_at: 2026-08-03
---

# Phase 1 — UI Design Contract

> Visual and interaction contract for the editor-facing diagnostic surface implied by the parser core. This phase does not implement a browser, Monaco, VS Code, LSP, or other frontend surface.

---

## Phase Boundary

Phase 1 is a headless, offline MoonBit parser kernel. The UI contract is limited to the stable information an eventual SQL editor or host adapter must present: selected Doris profile, strict/editor result mode, parse status, lossless source spans, bounded recovery nodes, machine-readable diagnostics, and byte-to-line/UTF-16 mapping.

The contract is descriptive only. Source editor widgets, LSP transport, WebAssembly/JavaScript bindings, Monaco/VS Code integration, formatting controls, completion, semantic analysis, and network/database states belong to later phases. No frontend package, design-system package, or browser dependency is introduced here.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none (manual contract) |
| Preset | not applicable |
| Component library | none |
| Icon library | none; use text labels and accessible status symbols supplied by the host |
| Font | system UI sans-serif for chrome; system monospace for SQL source and code spans |

Design-system detection: no React/Next/Vite application, `components.json`, Tailwind configuration, PostCSS configuration, or existing component tree is present. Do not initialize shadcn or install packages for this phase.

---

## Visual Hierarchy

1. **Source surface (primary):** the SQL text remains the dominant surface. Preserve spelling, casing, whitespace, comments, newlines, unknown text, and error material visually; wrapping must never imply that source bytes changed.
2. **Parse status (secondary-high):** show the selected Doris profile and one explicit status label: `Valid SQL`, `SQL incomplete`, or `SQL has errors`. Status must include text and an icon/shape where available; color alone is insufficient.
3. **Diagnostic navigation (secondary):** show a statement-linked list of diagnostics with severity, stable code, message, expected syntax class, and source span. Selecting a row moves focus to its half-open byte range.
4. **Host controls (tertiary):** profile selection, strict/editor mode selection, and the host's `Parse SQL` action are compact controls and must not visually compete with source or diagnostics.

No decorative illustration, dashboard metric, semantic catalog result, or formatter preview is in scope.

---

## Spacing Scale

Declared values (must be multiples of 4):

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | Icon-to-label gaps, diagnostic marker inset, inline padding |
| sm | 8px | Compact control spacing, diagnostic row padding |
| md | 16px | Default control and panel spacing, editor gutter inset |
| lg | 24px | Panel and section padding |
| xl | 32px | Wide-layout column gaps and major editor regions |
| 2xl | 48px | Page-level or major surface separation |
| 3xl | 64px | Outer spacing in a standalone host page |

Exceptions: none. Minimum keyboard/pointer target is 48px high/wide for icon-only controls; spacing and target dimensions remain on the 4px grid.

---

## Typography

Use only the following four sizes and two weights. SQL source uses the Body size with the monospace family.

| Role | Size | Weight | Line Height |
|------|------|--------|-------------|
| Body / source | 14px | 400 | 1.5 |
| Label / diagnostic code | 12px | 600 | 1.5 |
| Heading / status | 16px | 600 | 1.25 |
| Display / page title | 20px | 600 | 1.2 |

Do not add a separate font size for inline errors, line numbers, or buttons. Long diagnostic messages wrap at word boundaries; source text may horizontally scroll rather than reflow its byte identity.

---

## Color

The palette is a manual accessible default for a later host; a consuming editor may map these roles to its own theme without changing semantic meaning.

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60%) | `#FFFFFF` | SQL editor background, diagnostic content background, empty state surface |
| Secondary (30%) | `#F3F4F6` | Profile/mode controls, panel chrome, line-number gutter, diagnostic list rows and separators |
| Accent (10%) | `#2563EB` | Selected Doris profile, keyboard focus ring, active diagnostic row, and the currently navigated source span only |
| Destructive | `#B91C1C` | Destructive host actions only; not a substitute for diagnostic semantics |
| Diagnostic error | `#991B1B` | Syntax-error markers and error severity text only; pair with a stable code and label |

Diagnostic severity is semantic, not decorative: errors use `#991B1B`, warnings use `#B45309`, and informational status uses `#2563EB`, each paired with a text label, stable code, or shape. A valid result uses neutral text; an incomplete result uses a warning label and missing-node indication. Maintain at least 4.5:1 contrast for normal text and 3:1 for large text and non-text focus/marker boundaries.

Accent reserved for: the selected profile value, the visible keyboard focus indicator, the active diagnostic list row, and the source range currently navigated from a diagnostic. Never use accent for every link, button, hover state, or parse result.

---

## Copywriting Contract

All copy is specific to syntax parsing and must not imply execution, catalog validation, or Doris FE access.

| Element | Copy |
|---------|------|
| Primary CTA | `Parse SQL` |
| Empty state heading | `No SQL to parse` |
| Empty state body | `Enter Doris SQL, choose a 2.1, 3.x, or 4.x profile, then select Parse SQL.` |
| Valid state | `Valid SQL` — `No syntax diagnostics for Doris {profile}.` |
| Incomplete state | `SQL incomplete` — `Complete the highlighted clause or token; editor mode preserved the partial tree.` |
| Error state | `SQL has errors` — `Review the highlighted spans and fix the listed syntax errors, or choose the intended Doris profile.` |
| Actionable diagnostic | `Expected {syntax class} at {line}:{column}. Fix the highlighted text, then parse again.` |
| Empty diagnostics | `No diagnostics` — `The selected Doris profile accepted this input syntactically.` |
| Destructive confirmation | No destructive action is owned by Phase 1. If a later host adds `Clear SQL`, confirm with: `Clear SQL? This removes the current editor text. Select Clear SQL to continue or Cancel to keep it.` |

Diagnostic messages must expose the stable code and expected syntax class alongside the human message. Do not use “query executed,” “database error,” “unknown database,” or generic “something went wrong” for parser results.

---

## Component and Surface Inventory

These are host-facing surfaces, not Phase 1 implementation tasks.

| Surface | Required content and behavior | Phase ownership |
|---------|-------------------------------|-----------------|
| Source editor surface | Immutable document revision, SQL text, visible line/column context, lossless source spelling, and navigable byte spans | Later editor/Web/LSP host; consumes Phase 1 result |
| Doris profile selector | Explicit `2.1`, `3.x`, or `4.x`; no automatic dialect detection or silent MySQL fallback | Later host; value is required by Phase 1 API |
| Result mode selector | Explicit `Strict` or `Editor`; strict invalidity must not be presented as valid, editor mode may show recoverable CST | Later host; semantics fixed by Phase 1 |
| Parse action/status | `Parse SQL` action and text status for valid, incomplete, and invalid results; associate result with source revision | Later host; status vocabulary fixed here |
| Inline diagnostic marker | Range marker at the diagnostic's byte span; missing nodes are zero-width and require a caret/virtual marker strategy | Later editor adapter |
| Diagnostic list/panel | Severity, stable code, message, expected syntax class, statement identity, and byte span; click/keyboard navigation | Later editor adapter |
| Coordinate adapter | Convert canonical UTF-8 half-open byte spans through one `LineIndex` to line/column and host/LSP UTF-16 positions | Later LSP/host adapter; never reimplement ad hoc |
| Empty/error surfaces | Use the copywriting rows above; preserve input and allow correction/reparse rather than replacing source | Later host |

---

## Interaction, Responsive, and Accessibility Contract

### Result states and interaction

- Every displayed result is tied to a source revision and explicit Doris profile. A stale result must not be shown as current after an edit.
- `Strict` mode reports invalidity and must not promote a recovered tree to valid. `Editor` mode may display a usable tree containing explicit `MISSING`, `ERROR`, and `SKIPPED` nodes while retaining the same diagnostics schema.
- Valid input shows `Valid SQL` and no error markers. Incomplete input shows `SQL incomplete`, preserves the partial source, and marks missing/error locations. Malformed input shows `SQL has errors`, retains unknown/error text, and lists bounded diagnostics in source order.
- A diagnostic row activation moves the caret to its half-open `[start_byte, end_byte)` span. For a zero-width missing span, place the caret at `start_byte` and announce the expected syntax class. Previous/next diagnostic navigation must be keyboard reachable.
- Recommended host keyboard contract: `Ctrl+Enter` (or `Cmd+Enter`) invokes `Parse SQL`; `Tab` follows profile, mode, parse action, source, and diagnostics in a stable order; Enter/Space activates a focused control. Do not require hover, color perception, or pointer precision to discover an error.
- Parser work is synchronous and offline at this phase. A host may expose a transient `Parsing…` status for a long-running adapter, but must retain the previous revision's result until the new revision is identified and must never fabricate a loading result in the core.

### Coordinate and source behavior

- Canonical spans are UTF-8 byte offsets over one immutable source snapshot and are half-open: `0 <= start_byte <= end_byte <= source.byte_length`.
- The host must use the centralized `LineIndex` to map bytes to line/column and then to LSP UTF-16 positions. Handle CRLF, non-ASCII text, and surrogate-pair boundaries consistently; do not perform per-component UTF-16 arithmetic.
- Diagnostics and source markers must reference statement identity and the same revision. Byte ranges, not rendered glyph positions, are the source of truth.

### Responsive editor behavior

- On wide layouts, place the source surface beside a diagnostic panel with a minimum 32px column gap; keep status/profile controls above the source.
- On narrow layouts, stack diagnostics below the source and keep the status/profile controls visible before the editor. The page must not horizontally scroll; the source surface may scroll horizontally and the diagnostic list may scroll vertically.
- Long SQL lines retain exact bytes and may scroll horizontally. Long diagnostic messages wrap; stable codes and severity remain visible without truncating the actionable text. Many diagnostics use a bounded scrollable list with a visible count.
- The eventual host should preserve cursor and scroll position when replacing a result, and should not rewrite source text merely to display diagnostics.

### Accessibility

- Use native labels for profile/mode controls and an accessible name for `Parse SQL`. Announce status changes through a polite live region; announce errors with severity, stable code, and location without relying on color.
- Error/warning markers need text, shape, or pattern distinctions and must meet contrast requirements. Focus rings use the Accent color and remain visible on both dominant and secondary surfaces.
- Keyboard users can reach every control, navigate diagnostic rows, activate a span, and return focus to the source. Focus order must remain deterministic in stacked and side-by-side layouts.
- Respect reduced-motion preferences; no essential parser feedback may depend on animation. Preserve readable zoom/reflow behavior and allow assistive technology to access the diagnostic text and source location.

---

## UI Considerations

Applicable state considerations resolved: 22 covered, 0 dismissed, 0 unresolved — auto-resolved from the explicit Phase 1 editor contract.

| Category | Element(s) | Status | Resolution / Reason |
|----------|------------|--------|---------------------|
| empty | source editor | ✅ covered | Show `No SQL to parse`; preserve the empty source revision and direct the host to enter Doris SQL, choose a 2.1/3.x/4.x profile, and use `Parse SQL`. |
| loading | source editor | ✅ covered | The Phase 1 core is synchronous and offline; a later host adapter may show `Parsing…` while retaining the previous revision until the new result is identified. |
| error | source editor | ✅ covered | Preserve source text, unknown/error material, and navigable ranges while showing `SQL has errors` and statement-linked diagnostics. |
| partial | source editor | ✅ covered | Show `SQL incomplete`, retain the partial source, and mark explicit missing/error/skipped nodes rather than replacing the document. |
| overflow | source editor | ✅ covered | Keep exact source bytes and allow horizontal source scrolling; the host surface must not reflow bytes or horizontally scroll the surrounding page. |
| long-text | source editor | ✅ covered | Long SQL may scroll horizontally; line wrapping must never imply a source-byte rewrite or hide the current diagnostic range. |
| empty | diagnostic list | ✅ covered | Show `No diagnostics` only when the selected profile accepted the input syntactically; keep the source and profile visible. |
| loading | diagnostic list | ✅ covered | Retain the prior revision's list while a host adapter parses; do not fabricate diagnostics or clear the list before the new revision is identified. |
| error | diagnostic list | ✅ covered | List syntax errors with severity, stable code, expected syntax class, statement identity, and a concrete repair instruction. |
| populated | diagnostic list | ✅ covered | Render diagnostics in source order with visible severity, code, message, expected class, and half-open byte span; clicking or keyboard activation navigates to the range. |
| partial | diagnostic list | ✅ covered | A partial parse lists bounded diagnostics for missing/error/skipped nodes and keeps the source revision navigable. |
| overflow | diagnostic list | ✅ covered | Use a bounded vertically scrollable list with a visible count; long messages wrap while code, severity, and actionable text remain visible. |
| zero-one-many | diagnostic list | ✅ covered | Zero rows use `No diagnostics`; one and many rows retain source order, visible count, and keyboard previous/next navigation. |
| empty | profile/mode controls | ✅ covered | Profile and mode controls remain explicit even with empty input; empty-state copy tells the host to choose a profile and enter SQL. |
| loading | profile/mode controls | ✅ covered | Controls may be disabled during adapter parsing, but the selected profile/mode and previous result remain visible and tied to the source revision. |
| error | profile/mode controls | ✅ covered | Error status uses `SQL has errors` and identifies the selected profile; it never implies execution, database, or FE failure. |
| partial | profile/mode controls | ✅ covered | Strict/editor mode remains explicit; editor mode exposes incomplete input without promoting it to `Valid SQL`. |
| long-text | profile/mode controls | ✅ covered | Labels and status copy wrap at word boundaries without truncating the profile, mode, status, or action name. |
| loading | source navigation | ✅ covered | Navigation retains the prior revision until the new result is ready, preventing stale span jumps during adapter work. |
| error | source navigation | ✅ covered | Diagnostic activation moves focus to `[start_byte, end_byte)`; zero-width missing spans place the caret at `start_byte` and announce the expected class. |
| overflow | source navigation | ✅ covered | Source ranges remain byte-based while the source surface scrolls; navigation must not depend on rendered glyph positions. |
| long-text | source navigation | ✅ covered | Long diagnostic messages wrap and keep stable code/severity/action visible; range navigation remains keyboard reachable. |

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| shadcn official | none | not applicable; shadcn is not initialized |
| Third-party registries | none | not applicable; no registry, block, package, or install introduced |

---

## Provenance and Defaults

| Source | Decisions Used |
|--------|---------------|
| `.planning/phases/01-core-kernel/01-CONTEXT.md` | Phase boundary; UTF-8 byte spans; centralized `LineIndex`; strict/editor modes; bounded recovery; immutable lossless CST; explicit 2.1/3.x/4.x profiles; later LSP/Web separation |
| `.planning/phases/01-core-kernel/01-RESEARCH.md` | Headless architecture; diagnostic fields; source-backed spans; editor state expectations; later host UTF-16 conversion; no frontend dependency |
| `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/STATE.md` | Core value, CORE-01–CORE-07, offline operation, phase success criteria, and deferred ecosystem scope |
| Repository scan | No application source, design tokens, component library, `components.json`, Tailwind, PostCSS, or project skill directory detected |
| Auto-mode defaults | 4px spacing scale; four-size/two-weight typography; neutral 60/30/10 palette; text-first diagnostic copy; keyboard and contrast requirements; no registry |

---

## Checker Sign-Off

- [x] Dimension 1 Copywriting: PASS
- [x] Dimension 2 Visuals: PASS
- [x] Dimension 3 Color: PASS
- [x] Dimension 4 Typography: PASS
- [x] Dimension 5 Spacing: PASS
- [x] Dimension 6 Registry Safety: PASS

**Approval:** approved by gsd-ui-checker on 2026-08-03
