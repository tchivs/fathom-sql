# Phase 09 Deferred Items (09-04)

Items discovered during 09-04 execution that are out of scope for this
plan's tasks (pre-existing, not caused by 09-04 changes):

| Category | Item | Status |
|----------|------|--------|
| pre-existing | Bare `moon build --target native` (no --package) fails with `undefined reference to main` at link time. Verified pre-existing at de1aa8a (pre-rename HEAD) and at the 09-04 Task 2 commit; package-scoped builds (`--package fathom-sql`, `--package fathom-lsp`, `--package parity`, `--package test`, `--package api`) all pass. Likely a root/module default-target link quirk unrelated to the naming wave. 09-04 uses package-scoped builds for verification. | open — investigate in a later phase if bare builds are needed |
