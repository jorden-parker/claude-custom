#!/usr/bin/env python3
import json
import os
import sys
import time

TRIM_LINE_LIMIT = 150


def text_fields(response):
    if isinstance(response, dict):
        return [value for value in response.values() if isinstance(value, str)]
    if isinstance(response, str):
        return [response]
    return []


def record(event):
    fields = text_fields(event.get("tool_response"))
    lines = max((len(field.split("\n")) for field in fields), default=0)
    return {
        "time": int(time.time()),
        "session": event.get("session_id", ""),
        "tool": event.get("tool_name", ""),
        "bytes": sum(len(field.encode("utf-8")) for field in fields),
        "lines": lines,
        "over_trim_limit": lines > TRIM_LINE_LIMIT,
    }


def main():
    log_path = os.environ.get("CLAUDE_TOOL_TELEMETRY")
    if not log_path:
        return
    event = json.load(sys.stdin)
    with open(log_path, "a", encoding="utf-8") as log:
        log.write(json.dumps(record(event)) + "\n")


main()
