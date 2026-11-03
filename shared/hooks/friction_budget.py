#!/usr/bin/env python3
import copy
import hashlib
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hook_state
from hook_telemetry import record_hook_event
from recovery_recipes import recovery_line

PLAIN_DENIALS = 3
READ_RANGE_BUCKET = 300
DESCRIPTION_LIMIT = 80
QUOTED_TEXT = re.compile(r"'[^']*'|\"[^\"]*\"")
PATH_WORD = re.compile(r"\S*/\S*")
DIGITS = re.compile(r"\d+")
EMPTY_STATE = {"denials": {}, "calls": {}, "call_count": 0}


def _state_path(session_id):
    return hook_state.state_path("friction", session_id)


def call_snapshot_dir(session_id):
    state_file = _state_path(session_id)
    return state_file.with_name(f"{state_file.stem}.snapshots")


def record_call(session_id, key, entry):
    with hook_state.update_state(_state_path(session_id), EMPTY_STATE) as state:
        state["call_count"] += 1
        state["calls"][key] = {**entry, "number": state["call_count"]}
        return state["call_count"]


def lookup_call(session_id, key):
    return hook_state.read_state(_state_path(session_id), EMPTY_STATE)["calls"].get(key)


def recorded_calls(session_id):
    return list(hook_state.read_state(_state_path(session_id), EMPTY_STATE)["calls"].values())


def reset(session_id):
    hook_state.prune("friction")
    with hook_state.update_state(_state_path(session_id), EMPTY_STATE) as state:
        state.clear()
        state.update(copy.deepcopy(EMPTY_STATE))


def enabled(path):
    return os.environ.get("CLAUDE_CUSTOM_FRICTION") != "0" and path.exists()


def without_last_path_segment(match):
    return match.group(0).rsplit("/", 1)[0] + "/"


def bash_fingerprint(command):
    text = QUOTED_TEXT.sub("", command)
    text = PATH_WORD.sub(without_last_path_segment, text)
    return " ".join(DIGITS.sub("", text).split())


def range_bucket(value):
    return value // READ_RANGE_BUCKET if isinstance(value, int) else 0


def read_fingerprint(tool_input):
    return json.dumps([tool_input.get("file_path", ""), range_bucket(tool_input.get("offset")), range_bucket(tool_input.get("limit"))])


def fingerprint(tool_name, tool_input):
    if tool_name == "Bash":
        return bash_fingerprint(tool_input.get("command", ""))
    if tool_name == "Read":
        return read_fingerprint(tool_input)
    return json.dumps(tool_input, sort_keys=True)


def fingerprint_hash(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def describe(tool_name, tool_input):
    if tool_name == "Bash":
        return tool_input.get("command", "")[:DESCRIPTION_LIMIT]
    if tool_name == "Read":
        return tool_input.get("file_path", "")
    return tool_name


def plan_reset(hook, count, tool_name, tool_input, alternative, reason):
    return (
        f"Stop retrying: {hook} has refused {count} near-identical {tool_name} calls this turn "
        f"({describe(tool_name, tool_input)}). The one allowed alternative: {alternative}. "
        "Do not try this again; do the alternative or move on." + recovery_line(hook, reason)
    )


def deny_reason(hook, event, reason, alternative):
    path = _state_path(event.get("session_id"))
    if not enabled(path):
        return reason
    tool_name = event.get("tool_name", "")
    tool_input = event.get("tool_input") or {}
    key = f"{hook}|{tool_name}|{fingerprint(tool_name, tool_input)}"
    with hook_state.update_state(path, EMPTY_STATE) as state:
        count = state["denials"].get(key, 0) + 1
        state["denials"][key] = count
    if count <= PLAIN_DENIALS:
        return reason
    trip = f"plan reset after {count} near-identical {tool_name} denials"
    record_hook_event(hook, event, "friction", trip, {"fingerprint": fingerprint_hash(key)})
    return plan_reset(hook, count, tool_name, tool_input, alternative, reason)


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    if event.get("hook_event_name") == "UserPromptSubmit":
        reset(event.get("session_id"))


if __name__ == "__main__":
    main()
