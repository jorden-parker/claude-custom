#!/usr/bin/env python3
import json
import re
import shlex
import sys
from pathlib import Path

SEARCH_COMMANDS = {"grep", "rg", "ag", "ack", "find"}
SEARCH_NUDGE_AT = 2
LOOKUP_NUDGE_AT = 6
SEMANTIC_SEARCH_TOOL = "mcp__code-search__semantic_search"
SEARCH_NUDGE = (
    "Two text searches this turn. For 'where is X' or 'how does Y work' questions call "
    "semantic_search first and Read only the line ranges it returns."
)
LOOKUP_NUDGE = (
    "Six reads and searches this turn. Delegate wide sweeps to Agent (subagent_type Explore) "
    "with a narrow brief and keep only its conclusion."
)
EMPTY_STATE = {"searches": 0, "lookups": 0, "search_nudged": False, "lookup_nudged": False}


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


def is_text_search(command):
    for segment in segments(command):
        words = first_words(segment)
        if not words:
            continue
        if words[0] in SEARCH_COMMANDS or words[:2] == ["git", "grep"]:
            return True
    return False


def record(state, tool_name, tool_input):
    if tool_name == SEMANTIC_SEARCH_TOOL:
        state["searches"] = 0
    elif tool_name == "Agent":
        state["lookups"] = 0
    elif tool_name == "Read":
        state["lookups"] += 1
    elif tool_name == "Bash" and is_text_search(tool_input.get("command", "")):
        state["searches"] += 1
        state["lookups"] += 1


def due_nudges(state):
    nudges = []
    if state["searches"] >= SEARCH_NUDGE_AT and not state["search_nudged"]:
        state["search_nudged"] = True
        nudges.append(SEARCH_NUDGE)
    if state["lookups"] >= LOOKUP_NUDGE_AT and not state["lookup_nudged"]:
        state["lookup_nudged"] = True
        nudges.append(LOOKUP_NUDGE)
    return nudges


def main():
    event = json.load(sys.stdin)
    path = state_path(event.get("session_id", "nosession"))
    if event.get("hook_event_name") == "UserPromptSubmit":
        save_state(path, dict(EMPTY_STATE))
        return
    state = load_state(path)
    record(state, event.get("tool_name", ""), event.get("tool_input") or {})
    nudges = due_nudges(state)
    save_state(path, state)
    if nudges:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "\n".join(nudges)}}))


if __name__ == "__main__":
    main()
