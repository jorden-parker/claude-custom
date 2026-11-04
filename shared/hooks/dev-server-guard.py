#!/usr/bin/env python3
import json
import re
import shlex
import sys

from hook_telemetry import record_denial

SEGMENT_SEPARATOR = re.compile(r"[;&|()\n`]")
QUOTED_TEXT = re.compile(r"'[^']*'|\"(?:[^\"\\$`]|\\.)*\"")
ENV_ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
PACKAGE_MANAGERS = {"npm", "pnpm", "yarn", "bun"}
PACKAGE_OPTIONS_WITH_VALUE = {"-C", "--dir", "--filter", "-F", "--prefix", "--cwd"}
START_SCRIPTS = {"dev", "start"}
VITE_SUBCOMMANDS = {"dev", "serve"}
PNPM_ARBITRARY_CODE = {"exec", "dlx", "x", "create"}
BROWSER_OPENERS = {"open", "xdg-open", "start"}
LOOPBACK_URL = re.compile(r"^https?://(?:localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0)(?::\d+)?(?:/|$)")
REASON = (
    "A dev server never exits, so a foreground start hangs the Bash tool: rerun the same command "
    "with run_in_background: true, then read its output for the URL and errors."
)
PNPM_REASON = (
    "pnpm runs outside the sandbox only as one plain command: write `pnpm -C DIR SCRIPT ...` "
    "with no `cd &&`, pipe, `;` or `&`, so its store is never corrupted by a sandbox EPERM."
)
PNPM_EXEC_REASON = (
    "pnpm runs outside the sandbox, so `pnpm exec`, `dlx`, `x` and `create` are refused: "
    "run the project's own scripts with `pnpm -C DIR SCRIPT`, or run the binary with npx inside the sandbox."
)
OPEN_REASON = (
    "Open local pages in the cmux browser: call the /cmux-browser skill and use "
    "`cmux browser open URL`, then read the page's console and errors there."
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


def runs_pnpm(segment):
    words = without_environment(segment.split())
    return words[:1] == ["pnpm"]


def shell_words(segment):
    try:
        return shlex.split(segment)
    except ValueError:
        return None


def runs_arbitrary_pnpm_code(segment):
    if not runs_pnpm(segment):
        return False
    words = shell_words(segment)
    if words is None:
        return True
    if "--" not in words:
        return any(word in PNPM_ARBITRARY_CODE for word in words)
    boundary = words.index("--")
    before_script_arguments, first_script_argument = words[:boundary], words[boundary + 1 : boundary + 2]
    if not package_script_words(without_environment(before_script_arguments)):
        return True
    return any(word in PNPM_ARBITRARY_CODE for word in before_script_arguments + first_script_argument)


def pnpm_shares_the_line(command):
    parts = [segment for segment in segments(command) if segment.strip()]
    return len(parts) > 1 and any(runs_pnpm(segment) for segment in parts)


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


def starts_foreground_dev_server(tool_input, command):
    if tool_input.get("run_in_background") is True:
        return False
    return any(starts_dev_server(segment) for segment in segments(command))


def main():
    payload = json.load(sys.stdin)
    tool_input = payload.get("tool_input") or {}
    command = tool_input.get("command") or ""
    if starts_foreground_dev_server(tool_input, command):
        record_denial("dev-server-guard", payload, REASON)
        print(json.dumps(deny(REASON)))
    elif any(runs_arbitrary_pnpm_code(segment) for segment in segments_with_quoted_words(command)):
        record_denial("dev-server-guard", payload, PNPM_EXEC_REASON)
        print(json.dumps(deny(PNPM_EXEC_REASON)))
    elif pnpm_shares_the_line(command):
        record_denial("dev-server-guard", payload, PNPM_REASON)
        print(json.dumps(deny(PNPM_REASON)))
    elif any(opens_local_url(segment) for segment in segments_with_quoted_words(command)):
        print(json.dumps(deny(OPEN_REASON)))


if __name__ == "__main__":
    main()
