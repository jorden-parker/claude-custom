#!/usr/bin/env python3
import json
import os
import re
import shlex
import sys
from pathlib import Path

from friction_budget import deny_reason
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
DOCS_SKILL = "find-docs"
FILE_LOOKUP_COMMANDS = {"cat", "head", "tail", "less", "more", "sed", "awk", "ls", "tree", "find", "jq"}
DOCS_FIRST_DENY = (
    "node_modules refused: to check whether a package is installed, call mcp__dev__dev_deps "
    "(packages: names) or Read node_modules/<name>/package.json; to install, call mcp__dev__dev_install. "
    "For library and framework docs, use the find-docs skill first (Skill find-docs, which runs "
    "claude-custom ctx7), even when a project file such as AGENTS.md points at node_modules/next/dist/docs. "
    "After one lookup this turn, node_modules opens for checking details."
)
ALTERNATIVES = {
    SEARCH_FIRST_DENY: "call semantic_search once, then grep",
    DOCS_FIRST_DENY: "call Skill find-docs once, then open node_modules",
}
EMPTY_STATE = {"semantic_searched": False, "docs_looked_up": False}


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


def runs_docs_lookup(command):
    return any(word.startswith("ctx7") for word in words_of(command))


def is_file_lookup(words):
    return bool(words) and (words[0] in FILE_LOOKUP_COMMANDS or is_search_words(words))


def is_package_manifest(path):
    parts = Path(path).parts
    if "node_modules" not in parts:
        return False
    inside = parts[parts.index("node_modules") + 1 :]
    return inside[-1:] == ("package.json",) and len(inside) == (3 if inside[0].startswith("@") else 2)


def is_docs_path(word):
    return "node_modules" in word and not is_package_manifest(word)


def reads_node_modules(command):
    return any(is_file_lookup(words) and any(is_docs_path(word) for word in words[1:]) for words in pipeline_heads(command))


def opens_node_modules(tool_name, tool_input):
    if tool_name == "Read":
        return is_docs_path(tool_input.get("file_path", ""))
    if tool_name == "Bash":
        return reads_node_modules(tool_input.get("command", ""))
    return False


def looks_up_docs(tool_name, tool_input):
    if tool_name == "Skill":
        return tool_input.get("skill") == DOCS_SKILL
    return tool_name == "Bash" and runs_docs_lookup(tool_input.get("command", ""))


def docs_gate(state, tool_name, tool_input):
    if looks_up_docs(tool_name, tool_input):
        state["docs_looked_up"] = True
    if not state["docs_looked_up"] and opens_node_modules(tool_name, tool_input):
        return DOCS_FIRST_DENY
    return None


def search_gate(state, tool_name, tool_input):
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
    tool_name = event.get("tool_name", "")
    tool_input = event.get("tool_input") or {}
    advice = docs_gate(state, tool_name, tool_input) or search_gate(state, tool_name, tool_input)
    if not advice:
        return None
    return deny(deny_reason("tool-nudge", event, advice, ALTERNATIVES[advice]))


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
