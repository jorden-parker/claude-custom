import json
import os
import time

REASON_LIMIT = 300


def record_denial(hook, event, reason):
    log_path = os.environ.get("CLAUDE_TOOL_TELEMETRY")
    if not log_path:
        return
    entry = {
        "time": int(time.time()),
        "session": event.get("session_id", ""),
        "kind": "deny",
        "hook": hook,
        "tool": event.get("tool_name", ""),
        "reason": reason[:REASON_LIMIT],
    }
    with open(log_path, "a", encoding="utf-8") as log:
        log.write(json.dumps(entry) + "\n")
