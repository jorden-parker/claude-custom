#!/usr/bin/env python3
import json
import sys
from pathlib import Path

MAX_LINES = 300


def line_count(path):
    try:
        data = path.read_bytes()
    except OSError:
        return 0
    if b"\0" in data[:8192]:
        return 0
    return data.count(b"\n") + (0 if data.endswith(b"\n") or not data else 1)


def asks_for_small_range(tool_input):
    limit = tool_input.get("limit")
    return isinstance(limit, int) and 0 < limit <= MAX_LINES


def deny(reason):
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }


def reason_for(path, lines):
    return (
        f"{path} has {lines} lines. Find the lines you need first (semantic_search, "
        f"Grep or `git grep -n`), then Read again with offset and limit "
        f"(limit {MAX_LINES} or less)."
    )


def main():
    tool_input = json.load(sys.stdin).get("tool_input", {})
    path = Path(tool_input.get("file_path", ""))
    if asks_for_small_range(tool_input):
        return
    lines = line_count(path)
    if lines > MAX_LINES:
        print(json.dumps(deny(reason_for(path, lines))))


main()
