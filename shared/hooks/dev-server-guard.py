#!/usr/bin/env python3
import json
import re
import sys

SEGMENT_SEPARATOR = re.compile(r"[;&|()\n`]")
QUOTED_TEXT = re.compile(r"'[^']*'|\"(?:[^\"\\$`]|\\.)*\"")
ENV_ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
PACKAGE_MANAGERS = {"npm", "pnpm", "yarn", "bun"}
PACKAGE_OPTIONS_WITH_VALUE = {"-C", "--dir", "--filter", "-F", "--prefix", "--cwd"}
START_SCRIPTS = {"dev", "start"}
VITE_SUBCOMMANDS = {"dev", "serve"}
BROWSER_OPENERS = {"open", "xdg-open", "start"}
LOOPBACK_URL = re.compile(r"^https?://(?:localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0)(?::\d+)?(?:/|$)")
REASON = (
    "Start dev servers with mcp__dev__dev_start: it runs the server in the background, "
    "returns the real URL and keeps the log. Check one with mcp__dev__dev_status; "
    "read errors with mcp__dev__dev_errors or mcp__dev__page_check."
)
OPEN_REASON = (
    "Open local pages with mcp__dev__page_check (pass url for a full URL such as "
    "https://127.0.0.1:4000/): it uses the cmux browser and returns the page's errors. "
    "Then mcp__dev__page_snapshot lists its elements and mcp__dev__page_act drives them."
)


def segments(command):
    return SEGMENT_SEPARATOR.split(QUOTED_TEXT.sub("''", command))


def unquoted(match):
    return SEGMENT_SEPARATOR.sub(" ", match.group(0)[1:-1])


def segments_with_quoted_words(command):
    return SEGMENT_SEPARATOR.split(QUOTED_TEXT.sub(unquoted, command))


def without_environment(words):
    while words and ENV_ASSIGNMENT.match(words[0]):
        words = words[1:]
    return words


def without_leading_options(words):
    while words and words[0].startswith("-"):
        words = words[1:]
    return words


def unwrapped(words):
    if words[:1] in (["npx"], ["bunx"]):
        return without_leading_options(words[1:])
    if words[:2] == ["pnpm", "exec"]:
        return without_leading_options(words[2:])
    return words


def package_script_words(words):
    remaining, index = [], 1
    while index < len(words):
        word = words[index]
        if word in PACKAGE_OPTIONS_WITH_VALUE:
            index += 2
            continue
        if not word.startswith("-"):
            remaining.append(word)
        index += 1
    return remaining


def is_package_dev_start(words):
    if words[:1] == ["run"]:
        words = words[1:]
    return words[:1] != [] and words[0] in START_SCRIPTS


def is_framework_server(words):
    if words[:1] == ["next"]:
        return words[1:2] == ["dev"]
    if words[:1] == ["vite"]:
        return len(words) == 1 or words[1] in VITE_SUBCOMMANDS or words[1].startswith("-")
    return False


def starts_dev_server(segment):
    words = unwrapped(without_environment(segment.split()))
    if not words:
        return False
    if words[0] in PACKAGE_MANAGERS:
        return is_package_dev_start(package_script_words(words))
    return is_framework_server(words)


def opens_local_url(segment):
    words = without_environment(segment.split())
    if not words or words[0] not in BROWSER_OPENERS:
        return False
    return any(LOOPBACK_URL.match(word) for word in words[1:])


def deny(reason):
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }


def main():
    payload = json.load(sys.stdin)
    command = (payload.get("tool_input") or {}).get("command") or ""
    if any(starts_dev_server(segment) for segment in segments(command)):
        print(json.dumps(deny(REASON)))
    elif any(opens_local_url(segment) for segment in segments_with_quoted_words(command)):
        print(json.dumps(deny(OPEN_REASON)))


if __name__ == "__main__":
    main()
