#!/usr/bin/env python3
import json
import re
import shlex
import sys
from pathlib import Path

TEXT_SEARCH_COMMANDS = {"grep", "rg", "ag", "ack"}
LOOKUP_NUDGE_AT = 6
DENY_LIMIT = 2
SEMANTIC_SEARCH_TOOL = "mcp__code-search__semantic_search"
SEARCH_FIRST_DENY = (
    f"Text search refused: call {SEMANTIC_SEARCH_TOOL} first this turn with a plain-words "
    "query, Read only the ranges it returns, then use git grep -n for exact names if still needed."
)
LOOKUP_NUDGE = (
    "Six reads and searches this turn. Delegate wide sweeps to Agent (subagent_type Explore) "
    "with a narrow brief and keep only its conclusion."
)
EMPTY_STATE = {"semantic_searched": False, "denies": 0, "lookups": 0, "lookup_nudged": False}


def state_path(session_id):
    return Path.home() / ".claude" / "cache" / "tool-nudge" / f"{session_id}.json"


def load_state(path):
    try:
        return {**EMPTY_STATE, **json.loads(path.read_text())}
    except (OSError, ValueError):
        return dict(EMPTY_STATE)


def save_state(path, state):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state))


def segments(command):
    return re.split(r"[;|&()]", command)


def first_words(segment):
    try:
        return shlex.split(segment)[:2]
    except ValueError:
        return segment.split()[:2]


def is_search_words(words):
    return bool(words) and (words[0] in TEXT_SEARCH_COMMANDS or words[:2] == ["git", "grep"])


def is_text_search(command):
    return any(is_search_words(first_words(segment)) for segment in segments(command))


def leading_words(command):
    for segment in segments(command):
        words = first_words(segment)
        if words:
            return words
    return []


def leads_with_text_search(command):
    return is_search_words(leading_words(command))


def gate(state, tool_name, tool_input):
    if tool_name == SEMANTIC_SEARCH_TOOL:
        state["semantic_searched"] = True
        return None
    if state["semantic_searched"] or state["denies"] >= DENY_LIMIT:
        return None
    if tool_name == "Bash" and leads_with_text_search(tool_input.get("command", "")):
        state["denies"] += 1
        return SEARCH_FIRST_DENY
    return None


def record(state, tool_name, tool_input):
    if tool_name == "Agent":
        state["lookups"] = 0
    elif tool_name == "Read":
        state["lookups"] += 1
    elif tool_name == "Bash" and is_text_search(tool_input.get("command", "")):
        state["lookups"] += 1


def due_nudge(state):
    if state["lookups"] >= LOOKUP_NUDGE_AT and not state["lookup_nudged"]:
        state["lookup_nudged"] = True
        return LOOKUP_NUDGE
    return None


def deny(reason):
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }


def context(text):
    return {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": text}}


def handle(event, state):
    tool_name = event.get("tool_name", "")
    tool_input = event.get("tool_input") or {}
    if event.get("hook_event_name") == "PreToolUse":
        reason = gate(state, tool_name, tool_input)
        return deny(reason) if reason else None
    record(state, tool_name, tool_input)
    nudge = due_nudge(state)
    return context(nudge) if nudge else None


def main():
    event = json.load(sys.stdin)
    path = state_path(event.get("session_id", "nosession"))
    if event.get("hook_event_name") == "UserPromptSubmit":
        save_state(path, dict(EMPTY_STATE))
        return
    state = load_state(path)
    output = handle(event, state)
    save_state(path, state)
    if output:
        print(json.dumps(output))


if __name__ == "__main__":
    main()
