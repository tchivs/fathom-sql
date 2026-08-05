# Phase 3 Discussion Log

**Gathered:** 2026-08-04
**Mode:** Autonomous smart discuss (batch table proposals, all areas accepted)

## Grey Areas

| Area | Questions | Result |
|------|-----------|--------|
| 1. 格式化 API 与配置形态 | 4 | Accept all (D-25..D-28) |
| 2. 默认格式与策略 | 4 | Accept all (D-29..D-32) |
| 3. 安全与幂等契约 | 4 | Accept all (D-33..D-36) |
| 4. CLI 交付 | 4 | Accept all (D-37..D-40) |

## Tooling Notes

- UI gate correctly returned `frontend: false` for Phase 3 (no UI tokens; no UI-SPEC generated — expected).
- assumption-delta detector fired (`chosen` signals: "choose exact source replay or … configurable canonical rendering"): resolved as add-alongside (print_lossless baseline preserved; formatter is a distinct operation per D-27).
- Edge probe (FMT-01..04) produced 4 unresolved items; all resolved into must_haves as flagged assumptions/truths (03-01 concurrency determinism, 03-02 comment attachment rule, 03-03 refusal assertions, 03-04 CLI determinism).
- plan-checker iteration 1: 1 BLOCKER (grep -c == 0 in 03-01 Task 1 verify — same class as 02-05) + 4 WARNINGs + 1 INFO, all fixed in commit 604537b; iteration 2 passed.
- Decision coverage gate initially flagged D-30/D-31 (referenced as range "D-29..D-32" in plans); exploded the range reference to explicit D-IDs in 03-01 → 16/16 passed.

## Deferred Ideas

None — LSP formatting edits, Wasm/JS format facade, comment reflow, and incremental formatting remain in Phase 4 / v2.

---

*Phase: 3-Formatting and Safe Edits*
*Log written: 2026-08-04*
