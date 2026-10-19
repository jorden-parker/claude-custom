#!/usr/bin/env python3
import json
import re
import sys

COMMAND_START = r"(?:^|[;&|(\n`]\s*)"
SEGMENT_BODY = r"[^;&|)\n`]*"
GIT_GLOBAL_OPTIONS = r"(?:(?:--no-pager|--paginate|-p|-P|-c\s+\S+|-C\s+\S+|--git-dir=\S+|--work-tree=\S+)\s+)*"

UNBOUNDED_COMMANDS = [
    (
        re.compile(COMMAND_START + r"git\s+" + GIT_GLOBAL_OPTIONS + r"log\b(?!" + SEGMENT_BODY + r"(?:\s-n\s*\d|\s-\d+|--max-count))"),
        "Unbounded git log. Use: git log --oneline -n 20",
    ),
    (
        re.compile(COMMAND_START + r"(?:cat|less|more|bat)\s" + SEGMENT_BODY + r"\b(?:package-lock\.json|pnpm-lock\.yaml|yarn\.lock|Cargo\.lock|poetry\.lock|Gemfile\.lock|composer\.lock|go\.sum)\b"),
        "Lockfiles are huge. Grep for the package you need instead.",
    ),
    (
        re.compile(COMMAND_START + r"ls\b" + SEGMENT_BODY + r"(?:\s-\w*R\w*|\s--recursive)\b"),
        "Recursive ls floods context. Use Glob or: find . -maxdepth 2",
    ),
]


def deny(reason):
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }


def main():
    command = json.load(sys.stdin).get("tool_input", {}).get("command", "")
    for pattern, reason in UNBOUNDED_COMMANDS:
        if pattern.search(command):
            print(json.dumps(deny(reason)))
            return


main()
