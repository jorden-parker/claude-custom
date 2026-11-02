#!/usr/bin/env python3
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from friction_budget import load_state, save_state, state_path
from hook_telemetry import record_hook_event

HOOK = "repeat-call-cache"
GIT_STATUS_TOOL = "mcp__repo__git_status"
SEARCH_TOOL = "mcp__code-search__semantic_search"
CACHED_TOOLS = {"Read", GIT_STATUS_TOOL, SEARCH_TOOL}
ERROR_FLAGS = ("is_error", "isError")


def response_text(response):
    if isinstance(response, str):
        return response
    if isinstance(response, list):
        return "\n".join(response_text(block) for block in response)
    if isinstance(response, dict):
        if isinstance(response.get("file"), dict):
            return response_text(response["file"].get("content", ""))
        if "content" in response:
            return response_text(response["content"])
        if isinstance(response.get("text"), str):
            return response["text"]
        return "\n".join(value for value in response.values() if isinstance(value, str))
    return ""


def is_error(response):
    flagged = isinstance(response, dict) and any(response.get(flag) for flag in ERROR_FLAGS)
    return flagged or response_text(response).lstrip().startswith("Error")


def file_stamp(tool_input):
    try:
        return str(os.stat(tool_input.get("file_path", "")).st_mtime_ns)
    except OSError:
        return None


def git_output(cwd, *arguments):
    try:
        return subprocess.run(["git", *arguments], cwd=cwd, capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def git_stamp(cwd):
    head = git_output(cwd, "rev-parse", "HEAD")
    index_path = git_output(cwd, "rev-parse", "--git-path", "index")
    if head is None or index_path is None:
        return None
    try:
        return f"{head}:{os.stat(os.path.join(cwd, index_path)).st_mtime_ns}"
    except OSError:
        return None


def invalidation_stamp(event):
    tool_name = event.get("tool_name", "")
    if tool_name == "Read":
        return file_stamp(event.get("tool_input") or {})
    if tool_name == GIT_STATUS_TOOL:
        return git_stamp(event.get("cwd") or os.getcwd())
    return ""


def call_key(event):
    return f"{event.get('tool_name', '')}|{json.dumps(event.get('tool_input') or {}, sort_keys=True)}"


def record_call(state, event):
    response = event.get("tool_response")
    stamp = invalidation_stamp(event)
    if is_error(response) or stamp is None:
        return
    text = response_text(response)
    state["call_count"] += 1
    state["calls"][call_key(event)] = {
        "number": state["call_count"],
        "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        "bytes": len(text.encode("utf-8")),
        "stamp": stamp,
    }


def deny(reason):
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }


def repeat_of(state, event):
    earlier = state["calls"].get(call_key(event))
    if earlier and earlier["stamp"] == invalidation_stamp(event):
        return earlier
    return None


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    if event.get("tool_name") not in CACHED_TOOLS:
        return
    path = state_path(event.get("session_id"))
    state = load_state(path)
    if event.get("hook_event_name") == "PostToolUse":
        record_call(state, event)
        save_state(path, state)
        return
    earlier = repeat_of(state, event)
    if earlier is None:
        return
    reason = f"same result as call #{earlier['number']} this turn, unchanged since; use it"
    record_hook_event(HOOK, event, "friction", reason, {"saved_bytes": earlier["bytes"]})
    print(json.dumps(deny(reason)))


if __name__ == "__main__":
    main()
