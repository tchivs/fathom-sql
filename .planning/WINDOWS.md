---
schema_version: 1
open_count: 4
waived_count: 0
fixed_count: 0
total_count: 4
last_updated: 2026-08-06T15:11:55.105Z
---

# Broken Windows Ledger

> Cross-phase defect register. `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 04 | unrun-verify | .planning/phases/04-ecosystem-and-multi-target-delivery/04-03-PLAN.md | 34 | Task 1 export_smoke verification deferred to parent executor | open |  | 2026-08-04T15:27:35.657Z |  |
| 2 | 04 | unrun-verify | .planning/phases/04-ecosystem-and-multi-target-delivery/04-03-PLAN.md | 41 | Task 2 parity verification deferred to parent executor | open |  | 2026-08-04T15:27:36.129Z |  |
| 3 | 04 | unrun-verify | .planning/phases/04-ecosystem-and-multi-target-delivery/04-03-PLAN.md | 48 | Task 3 target build verification deferred to parent executor | open |  | 2026-08-04T15:27:36.647Z |  |
| 4 | 09 | deviation | parser/parser.mbt | 3449 | Empty Flink input yields a silent empty document (flagged-unverified probe DIALECT-03 empty): FATHOM-PARSE-008 fires only for non-empty segments because the single parse_segment router and the frozen Doris empty-document behavior are mutually exclusive for the empty case; resolution belongs to a later wave if the contract is confirmed | open |  | 2026-08-06T15:11:55.105Z |  |

````json
[
  {
    "id": 1,
    "kind": "unrun-verify",
    "phase": "04",
    "file": ".planning/phases/04-ecosystem-and-multi-target-delivery/04-03-PLAN.md",
    "line": 34,
    "description": "Task 1 export_smoke verification deferred to parent executor",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-04T15:27:35.657Z",
    "resolved_at": null
  },
  {
    "id": 2,
    "kind": "unrun-verify",
    "phase": "04",
    "file": ".planning/phases/04-ecosystem-and-multi-target-delivery/04-03-PLAN.md",
    "line": 41,
    "description": "Task 2 parity verification deferred to parent executor",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-04T15:27:36.129Z",
    "resolved_at": null
  },
  {
    "id": 3,
    "kind": "unrun-verify",
    "phase": "04",
    "file": ".planning/phases/04-ecosystem-and-multi-target-delivery/04-03-PLAN.md",
    "line": 48,
    "description": "Task 3 target build verification deferred to parent executor",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-04T15:27:36.647Z",
    "resolved_at": null
  },
  {
    "id": 4,
    "kind": "deviation",
    "phase": "09",
    "file": "parser/parser.mbt",
    "line": 3449,
    "description": "Empty Flink input yields a silent empty document (flagged-unverified probe DIALECT-03 empty): FATHOM-PARSE-008 fires only for non-empty segments because the single parse_segment router and the frozen Doris empty-document behavior are mutually exclusive for the empty case; resolution belongs to a later wave if the contract is confirmed",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-06T15:11:55.105Z",
    "resolved_at": null
  }
]
````
