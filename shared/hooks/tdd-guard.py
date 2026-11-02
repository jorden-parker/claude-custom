#!/usr/bin/env python3
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hook_telemetry import record_denial, record_hook_event
from recovery_recipes import recovery_line
from test_scope import expected_test_name, is_code, is_test, scope_of

EDIT_TOOLS = {"Edit", "Write", "MultiEdit"}
STRIKE_LIMIT = 2
EMPTY_STATE = {"counter": 0, "test_edits": {}, "test_run_at": 0, "strikes": {}}
SEGMENT_SPLIT = re.compile(r"\|\||&&|;|\|")
TEST_TARGET = re.compile(r"^(test|check|verify)")


def state_path(session_id):
    config_dir = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
    return config_dir / "cache" / "tdd-guard" / f"{session_id}.json"


def load_state(path):
    try:
        return {**EMPTY_STATE, **json.loads(path.read_text())}
    except (OSError, ValueError):
        return json.loads(json.dumps(EMPTY_STATE))


def save_state(path, state):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state))


def command_segments(command):
    for segment in SEGMENT_SPLIT.split(command):
        words = segment.strip().split()
        while words and ("=" in words[0] or words[0] in ("cd", "env", "sudo", "time")):
            words = words[2:] if words[0] == "cd" else words[1:]
        if words:
            yield words


def runs_tests(words):
    head = Path(words[0]).name
    if head == "go":
        return len(words) > 1 and words[1] == "test"
    if head == "make":
        return any(TEST_TARGET.match(word) for word in words[1:])
    if head in ("pnpm", "npm", "yarn", "bun", "npx"):
        return any(word in ("test", "vitest", "jest") for word in words[1:])
    if head == "python" or head == "python3":
        return "pytest" in words or "unittest" in words
    if head in ("vitest", "jest", "pytest", "bats"):
        return True
    return head.endswith(".test.sh") or head == "verify"


def is_test_run(command):
    return any(runs_tests(words) for words in command_segments(command))


def record_event(state, event):
    tool_name = event.get("tool_name", "")
    tool_input = event.get("tool_input") or {}
    if tool_name == "Bash":
        if is_test_run(tool_input.get("command", "")):
            state["counter"] += 1
            state["test_run_at"] = state["counter"]
            state["strikes"] = {}
        return
    if tool_name in EDIT_TOOLS:
        path = Path(tool_input.get("file_path") or "")
        if path.name and is_test(path):
            state["counter"] += 1
            state["test_edits"][scope_of(path)] = state["counter"]
            state["strikes"] = {}


def unlocked(state, scope):
    edited_at = state["test_edits"].get(scope, 0)
    return edited_at and state["test_run_at"] > edited_at


def deny_reason(state, path):
    test_name = expected_test_name(path)
    if state["test_edits"].get(scope_of(path)):
        return (
            f"TDD: {test_name} changed; run it (go test ./..., pnpm test, ./{test_name}) "
            f"and see the new case fail before editing {path.name}."
        )
    return (
        f"TDD: edit or add the test first. Write the failing case in {test_name} beside {path.name}, "
        f"run it (go test ./..., pnpm test, ./{test_name}) and see it fail, then edit {path.name}."
    )


def deny(reason):
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }


def strike_context(state, path):
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": (
                f"tdd-guard let {path.name} through after {STRIKE_LIMIT} refusals; its test is "
                f"{expected_test_name(path)}.{recovery_line('tdd-guard', deny_reason(state, path))}"
            ),
        }
    }


def gate(state, event):
    tool_name = event.get("tool_name", "")
    tool_input = event.get("tool_input") or {}
    path = Path(tool_input.get("file_path") or "")
    if tool_name not in EDIT_TOOLS or not path.name or not is_code(path, tool_input, tool_name) or is_test(path):
        return None
    if unlocked(state, scope_of(path)):
        return None
    strikes = state["strikes"].get(str(path), 0) + 1
    state["strikes"][str(path)] = strikes
    if strikes > STRIKE_LIMIT:
        record_hook_event("tdd-guard", event, "allow-after-strikes", str(path))
        return strike_context(state, path)
    return deny(deny_reason(state, path))


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    if os.environ.get("CLAUDE_CUSTOM_TDD") == "0":
        return
    path = state_path(event.get("session_id", "nosession"))
    state = load_state(path)
    hook_event = event.get("hook_event_name")
    output = None
    if hook_event == "PostToolUse":
        record_event(state, event)
    elif hook_event == "PreToolUse":
        output = gate(state, event)
    save_state(path, state)
    if output is None:
        return
    if "permissionDecisionReason" in output["hookSpecificOutput"]:
        record_denial("tdd-guard", event, output["hookSpecificOutput"]["permissionDecisionReason"])
    print(json.dumps(output))


if __name__ == "__main__":
    main()
