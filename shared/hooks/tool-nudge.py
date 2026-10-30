#!/usr/bin/env python3
import json
import os
import re
import shlex
import sys
from pathlib import Path

from hook_telemetry import record_denial

TEXT_SEARCH_COMMANDS = {"grep", "rg", "ag", "ack"}
FIND_NAME_FILTERS = {"-name", "-iname", "-path", "-ipath", "-regex", "-iregex", "-wholename", "-iwholename"}
COMMAND_SEPARATOR = re.compile(r"&&|\|\||[;&\n()]")
SEMANTIC_SEARCH_TOOL = "mcp__code-search__semantic_search"
SEARCH_FIRST_DENY = (
    f"Text search refused: call {SEMANTIC_SEARCH_TOOL} first this turn with a plain-words "
    "query, Read only the ranges it returns, then use git grep -n for exact names if still needed. "
    "If it errors, text search is allowed for the rest of the turn."
)
EMPTY_STATE = {"semantic_searched": False}


def claude_config_dir():
    return Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")


def state_path(session_id):
    return claude_config_dir() / "cache" / "tool-nudge" / f"{session_id}.json"


def load_state(path):
    try:
        return {**EMPTY_STATE, **json.loads(path.read_text())}
    except (OSError, ValueError):
        return dict(EMPTY_STATE)


def save_state(path, state):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state))


def words_of(text):
    try:
        return shlex.split(text)
    except ValueError:
        return text.split()


def pipeline_heads(command):
    return [words_of(part.split("|")[0]) for part in COMMAND_SEPARATOR.split(command)]


def is_find_by_name(words):
    return words[0] == "find" and any(word in FIND_NAME_FILTERS for word in words[1:])


def is_search_words(words):
    if not words:
        return False
    return words[0] in TEXT_SEARCH_COMMANDS or words[:2] == ["git", "grep"] or is_find_by_name(words)


def runs_text_search(command):
    return any(is_search_words(words) for words in pipeline_heads(command))


def gate(state, tool_name, tool_input):
    if tool_name == SEMANTIC_SEARCH_TOOL:
        state["semantic_searched"] = True
        return None
    if state["semantic_searched"]:
        return None
    if tool_name == "Bash" and runs_text_search(tool_input.get("command", "")):
        return SEARCH_FIRST_DENY
    return None


def deny(reason):
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }


def handle(event, state):
    if event.get("hook_event_name") != "PreToolUse":
        return None
    reason = gate(state, event.get("tool_name", ""), event.get("tool_input") or {})
    return deny(reason) if reason else None


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
        record_denial("tool-nudge", event, output["hookSpecificOutput"]["permissionDecisionReason"])
        print(json.dumps(output))


if __name__ == "__main__":
    main()
