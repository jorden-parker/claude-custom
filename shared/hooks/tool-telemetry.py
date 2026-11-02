#!/usr/bin/env python3
import json
import os
import sys
import time

TRIM_LINE_LIMIT = 150
EDIT_TOOLS = {"Edit", "Write", "MultiEdit"}


def text_fields(response):
    if isinstance(response, dict):
        return [value for value in response.values() if isinstance(value, str)]
    if isinstance(response, str):
        return [response]
    return []


def written_texts(tool_name, tool_input):
    if tool_name == "Write":
        return [tool_input.get("content") or ""]
    if tool_name == "MultiEdit":
        edits = tool_input.get("edits") or []
        return [edit.get(key) or "" for edit in edits for key in ("old_string", "new_string")]
    return [tool_input.get(key) or "" for key in ("old_string", "new_string")]


def input_bytes(event):
    tool_name = event.get("tool_name", "")
    if tool_name not in EDIT_TOOLS:
        return {}
    texts = written_texts(tool_name, event.get("tool_input") or {})
    return {"input_bytes": sum(len(text.encode("utf-8")) for text in texts)}


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
        **input_bytes(event),
    }


def main():
    log_path = os.environ.get("CLAUDE_TOOL_TELEMETRY")
    if not log_path:
        return
    event = json.load(sys.stdin)
    with open(log_path, "a", encoding="utf-8") as log:
        log.write(json.dumps(record(event)) + "\n")


main()
