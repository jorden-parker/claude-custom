#!/usr/bin/env python3
import hashlib
import json
import os
import subprocess
import sys
from difflib import SequenceMatcher
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from friction_budget import call_snapshot_dir, lookup_call, record_call, recorded_calls
from hook_telemetry import record_hook_event

HOOK = "repeat-call-cache"
GIT_STATUS_TOOL = "mcp__repo__git_status"
SEARCH_TOOL = "mcp__code-search__semantic_search"
CACHED_TOOLS = {"Read", GIT_STATUS_TOOL, SEARCH_TOOL}
ERROR_FLAGS = ("is_error", "isError")
SNAPSHOT_BYTE_LIMIT = 64 * 1024
NARROWING_MARGIN = 3
NARROWED_LINE_LIMIT = 300


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


def snapshot_name(key):
    return hashlib.sha256(key.encode("utf-8")).hexdigest()[:16]


def save_snapshot(directory, name, text):
    directory.mkdir(parents=True, exist_ok=True)
    os.chmod(directory, 0o700)
    descriptor = os.open(directory / name, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as snapshot:
        snapshot.write(text)


def prune_snapshots(directory, session_id):
    kept = {call.get("snapshot") for call in recorded_calls(session_id)}
    if not directory.is_dir():
        return
    for snapshot in directory.iterdir():
        if snapshot.name not in kept:
            snapshot.unlink()


def remember_result(session_id, event):
    response = event.get("tool_response")
    stamp = invalidation_stamp(event)
    if is_error(response) or stamp is None:
        return
    text = response_text(response)
    size = len(text.encode("utf-8"))
    key = call_key(event)
    entry = {"sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(), "bytes": size, "stamp": stamp}
    snapshots = call_snapshot_dir(session_id)
    if event.get("tool_name") == "Read" and size <= SNAPSHOT_BYTE_LIMIT:
        entry["snapshot"] = snapshot_name(key)
        entry["realpath"] = os.path.realpath((event.get("tool_input") or {}).get("file_path", ""))
        save_snapshot(snapshots, snapshot_name(key), text)
    record_call(session_id, key, entry)
    prune_snapshots(snapshots, session_id)


def deny(reason):
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }


def narrowed(reason, tool_input, offset, limit):
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": {"file_path": tool_input.get("file_path", ""), "offset": offset, "limit": limit},
            "additionalContext": reason,
        }
    }


def read_lines(path):
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return None


def served_slice(lines, tool_input):
    start = max(tool_input.get("offset") or 1, 1) - 1
    limit = tool_input.get("limit")
    return lines[start:] if limit is None else lines[start : start + limit]


def changed_span(old_lines, new_lines):
    changed = []
    for tag, _, _, new_start, new_end in SequenceMatcher(None, old_lines, new_lines, autojunk=False).get_opcodes():
        if tag != "equal":
            changed.extend((new_start, max(new_start, new_end - 1)))
    if not changed:
        return None
    return min(changed), max(changed)


def narrowing_reason(number, changed, shown):
    span = f"lines {changed[0]}-{changed[1]} changed since call #{number}"
    if shown[1] >= changed[1]:
        return f"{span}; showing only them"
    return f"{span}; showing only {shown[0]}-{shown[1]} (read on from {shown[1] + 1} for the rest)"


def narrowed_read(earlier, event, snapshots):
    tool_input = event.get("tool_input") or {}
    snapshot = snapshots / earlier.get("snapshot", "")
    file_path = tool_input.get("file_path", "")
    if not earlier.get("snapshot") or not snapshot.is_file() or os.path.realpath(file_path) != earlier.get("realpath"):
        return None
    current = read_lines(file_path)
    if current is None:
        return None
    old_lines = snapshot.read_text(encoding="utf-8").splitlines()
    span = changed_span(old_lines, served_slice(current, tool_input))
    if span is None:
        return deny(pointer(earlier))
    base = max(tool_input.get("offset") or 1, 1)
    changed = (base + span[0], base + span[1])
    first = max(1, changed[0] - NARROWING_MARGIN)
    last = min(max(len(current), 1), changed[1] + NARROWING_MARGIN, first + NARROWED_LINE_LIMIT - 1)
    return narrowed(narrowing_reason(earlier["number"], changed, (first, last)), tool_input, first, last - first + 1)


def pointer(earlier):
    return f"same result as call #{earlier['number']} this turn, unchanged since; use it"


def repeat_decision(session_id, event):
    earlier = lookup_call(session_id, call_key(event))
    if earlier is None:
        return None
    if earlier["stamp"] == invalidation_stamp(event):
        reason = pointer(earlier)
        record_hook_event(HOOK, event, "friction", reason, {"saved_bytes": earlier["bytes"]})
        return deny(reason)
    if event.get("tool_name") == "Read":
        return narrowed_read(earlier, event, call_snapshot_dir(session_id))
    return None


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    if event.get("tool_name") not in CACHED_TOOLS:
        return
    session_id = event.get("session_id")
    if event.get("hook_event_name") == "PostToolUse":
        remember_result(session_id, event)
        return
    output = repeat_decision(session_id, event)
    if output is not None:
        print(json.dumps(output))


if __name__ == "__main__":
    main()
