#!/usr/bin/env python3
import json
import re
import sys

COMMAND_START = r"(?:^|[;&|(\n`]\s*)"
SEGMENT_BODY = r"[^;&|)\n`]*"
PIPED_TO_BOUNDED_FILTER = r"\|\s*(?:head|tail|wc|grep|sed\s+-n)\b"
NOT_PIPED_TO_BOUNDED_FILTER = "(?!" + SEGMENT_BODY + PIPED_TO_BOUNDED_FILTER + ")"
GIT_GLOBAL_OPTIONS = r"(?:(?:--no-pager|--paginate|-p|-P|-c\s+\S+|-C\s+\S+|--git-dir=\S+|--work-tree=\S+)\s+)*"
QUOTED_TEXT = re.compile(r"'[^']*'|\"(?:[^\"\\$`]|\\.)*\"")
QUOTED_SEPARATOR = re.compile(r"[;&|()\n`]")

LOCKFILES = (
    "package-lock.json",
    "pnpm-lock.yaml",
    "yarn.lock",
    "Cargo.lock",
    "poetry.lock",
    "Gemfile.lock",
    "composer.lock",
    "go.sum",
)


def needs_bounding_flag(command, bounding_flags, advice):
    bounded = "|".join(bounding_flags)
    pattern = re.compile(
        COMMAND_START + command + r"\b(?!" + SEGMENT_BODY + "(?:" + bounded + "|" + PIPED_TO_BOUNDED_FILTER + "))"
    )
    return pattern, advice


def must_not_open(commands, files, advice):
    names = "|".join(re.escape(name) for name in files)
    verbs = "|".join(commands)
    pattern = re.compile(
        COMMAND_START + "(?:" + verbs + r")\s" + SEGMENT_BODY + r"\b(?:" + names + r")\b" + NOT_PIPED_TO_BOUNDED_FILTER
    )
    return pattern, advice


def must_not_use_flag(command, flags, advice):
    alternatives = "|".join(flags)
    pattern = re.compile(
        COMMAND_START + command + r"\b" + SEGMENT_BODY + "(?:" + alternatives + r")\b" + NOT_PIPED_TO_BOUNDED_FILTER
    )
    return pattern, advice


UNBOUNDED_COMMANDS = [
    needs_bounding_flag(
        r"git\s+" + GIT_GLOBAL_OPTIONS + r"log",
        (r"\s-n\s*\d", r"\s-\d+", "--max-count"),
        "Unbounded git log. Use: git log --oneline -n 20",
    ),
    must_not_open(
        ("cat", "less", "more", "bat"),
        LOCKFILES,
        "Lockfiles are huge. Grep for the package you need instead.",
    ),
    must_not_use_flag(
        "ls",
        (r"\s-\w*R\w*", r"\s--recursive"),
        "Recursive ls floods context. Use Glob or: find . -maxdepth 2",
    ),
]


def blank_if_it_hides_a_separator(match):
    return "''" if QUOTED_SEPARATOR.search(match.group(0)) else match.group(0)


def without_quoted_text(command):
    return QUOTED_TEXT.sub(blank_if_it_hides_a_separator, command)


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
        if pattern.search(without_quoted_text(command)):
            print(json.dumps(deny(reason)))
            return


main()
