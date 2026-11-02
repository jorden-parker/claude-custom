#!/usr/bin/env python3
import difflib
import json
import os
import sys

from hook_telemetry import record_hook_event

HOOK_NAME = "edit-nudge"
EDIT_TOOLS = {"Edit", "Write", "MultiEdit"}
ECHO_LINE_LIMIT = 40
ECHO_CHAR_LIMIT = 1500
ECHO_CHANGED_FRACTION = 4
WRITE_LINE_LIMIT = 60
MULTI_EDIT_LIMIT = 8


def lines_of(text):
    return text.splitlines()


def changed_line_count(old_lines, new_lines):
    matcher = difflib.SequenceMatcher(None, old_lines, new_lines, autojunk=False)
    matched = sum(block.size for block in matcher.get_matching_blocks())
    return len(old_lines) - matched


def echoed_old_string(tool_input):
    old_string = tool_input.get("old_string") or ""
    old_lines = lines_of(old_string)
    if len(old_lines) <= ECHO_LINE_LIMIT and len(old_string) <= ECHO_CHAR_LIMIT:
        return None
    changed = changed_line_count(old_lines, lines_of(tool_input.get("new_string") or ""))
    if changed * ECHO_CHANGED_FRACTION >= len(old_lines):
        return None
    return (
        "edit/echoed-old-string",
        f"old_string echoes {len(old_lines)} lines to change {changed}; narrow it to the changed lines plus two of context.",
    )


def file_line_count(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return sum(1 for _ in handle)
    except OSError:
        return 0


def rewrites_file(tool_input):
    path = tool_input.get("file_path") or ""
    if not path:
        return None
    existing_lines = file_line_count(path)
    if existing_lines <= WRITE_LINE_LIMIT:
        return None
    return (
        "write/rewrites-file",
        f"Write rewrites {existing_lines} lines; use Edit for the changed span.",
    )


def too_many_edits(tool_input):
    count = len(tool_input.get("edits") or [])
    if count <= MULTI_EDIT_LIMIT:
        return None
    return (
        "multiedit/too-many-edits",
        f"MultiEdit carries {count} edits; split into turns of at most {MULTI_EDIT_LIMIT} edits so a failed one costs less.",
    )


RULES = {"Edit": echoed_old_string, "Write": rewrites_file, "MultiEdit": too_many_edits}


def handle(event):
    if event.get("hook_event_name") != "PreToolUse" or event.get("tool_name") not in EDIT_TOOLS:
        return None
    finding = RULES[event["tool_name"]](event.get("tool_input") or {})
    if finding is None:
        return None
    rule_id, text = finding
    record_hook_event(HOOK_NAME, event, "nudge", rule_id, {"rule": rule_id})
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": text}}


def main():
    if os.environ.get("CLAUDE_OLLAMA_EDIT_NUDGE") == "0":
        return
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    output = handle(event)
    if output:
        print(json.dumps(output))


if __name__ == "__main__":
    main()
