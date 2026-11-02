---
triggers:
  - path: shared/hooks/
---

shared/hooks: each hook `X.py` reads one JSON event on stdin and prints one JSON
object (PreToolUse: `hookSpecificOutput` with `permissionDecision` or
`additionalContext`; exit 2 with stderr to block). A denial goes through
`friction_budget.deny_reason` and `hook_telemetry.record_denial`. A new rule
needs a deny and an allow case in `X.test.sh`, which prints `all passed`.
