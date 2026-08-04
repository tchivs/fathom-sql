---
phase: 04-ecosystem-and-multi-target-delivery
plan: 00
subsystem: ecosystem-harnesses
tags: [moonbit, lsp, schema, parity, web, vscode]
requires: [03-01, 03-04]
provides: [focused-schema-lsp-parity-harnesses, offline-web-smoke, vscode-protocol-smoke]
affects: [04-01, 04-02, 04-03, 04-04]
tech-stack:
  added: []
  patterns: [dependency-free deterministic fixtures, primitive versioned envelopes, protocol-only VS Code smoke]
key-files:
  created:
    - binding/schema_test.mbt
    - binding/coordinates_test.mbt
    - lsp/lifecycle_test.mbt
    - lsp/framing_test.mbt
    - lsp/diagnostics_formatting_test.mbt
    - binding/export_smoke_test.mbt
    - parity/parity_test.mbt
    - parity/run_native.mbt
    - parity/run_js.mbt
    - parity/run_wasm.mbt
    - web/src/main.test.ts
    - web/scripts/offline-smoke.mjs
    - vscode/src/extension.test.ts
    - vscode/scripts/launch-smoke.mjs
decisions:
  - Keep Wave 0 harnesses offline and dependency-free; no npm installs or local VS Code executable assumptions.
  - Assert serialized primitive field names and schema versions at the boundary, leaving implementation adapters to later plans.
metrics:
  duration: 10min
  completed: 2026-08-04
status: complete
actuals:
  tokens: 1400
  tasks: 2
  commits: 1
---

# Phase 4 Plan 0: Wave 0 Harnesses Summary

Deterministic MoonBit, Web, and VS Code host harnesses establish executable contract checks for schema, coordinates, LSP framing/lifecycle, formatting refusal, exports, parity, artifact loading, and protocol lifecycle before later implementation plans.

## Verification Status

Per assignment constraints, the plan verification commands were intentionally not run. The harness files and offline/protocol entrypoints were created without external package installation.

## Deviations from Plan

None — plan executed exactly as written.

## Remaining Risks

The MoonBit tests and parity runners are contract fixtures awaiting the production adapter packages from subsequent Phase 4 plans. Final host lifecycle validation remains human-hosted as specified by the plan.

## Self-Check: PASSED

All fourteen files listed by the plan exist, and the summary records the intentionally skipped validation commands.
