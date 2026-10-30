#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys

from hook_telemetry import record_denial

SEGMENT_SEPARATOR = re.compile(r"[;&|()\n`]")
QUOTED_TEXT = re.compile(r"'[^']*'|\"(?:[^\"\\$`]|\\.)*\"")
GIT_OPTIONS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
PUSH_OPTIONS_WITH_VALUE = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}
REWRITING_FLAGS = {"--force", "--force-with-lease", "--force-if-includes", "--delete", "--mirror", "--prune"}
REWRITING_SHORT_FLAGS = set("fd")
PROTECTED_BRANCHES = {"main", "master"}
REASON = (
    "claude-ollama does not let the model force-push, delete remote branches, mirror or prune, "
    "or push to main or master. Push your branch normally and open a pull request."
)


def segments(command):
    return SEGMENT_SEPARATOR.split(QUOTED_TEXT.sub("''", command))


def git_subcommand(words):
    if not words or words[0] != "git":
        return None, None, []
    index, directory = 1, None
    while index < len(words) and words[index].startswith("-"):
        option = words[index]
        if option in GIT_OPTIONS_WITH_VALUE:
            value = words[index + 1] if index + 1 < len(words) else ""
            if option == "-c" and value.startswith("alias."):
                return "alias", None, []
            if option == "-C":
                directory = value
            index += 2
        else:
            index += 1
    if index >= len(words):
        return None, None, []
    return words[index], directory, words[index + 1:]


def push_arguments(arguments):
    flags, positional, index = [], [], 0
    while index < len(arguments):
        word = arguments[index]
        if word in PUSH_OPTIONS_WITH_VALUE:
            index += 2
            continue
        (flags if word.startswith("-") else positional).append(word)
        index += 1
    return flags, positional


def rewrites_history(flag):
    if flag.split("=", 1)[0] in REWRITING_FLAGS:
        return True
    return not flag.startswith("--") and bool(REWRITING_SHORT_FLAGS & set(flag[1:]))


def current_branch(directory):
    result = subprocess.run(
        ["git", "-C", directory, "symbolic-ref", "--short", "-q", "HEAD"], capture_output=True, text=True
    )
    return result.stdout.strip()


def destination(refspec, directory):
    if refspec.startswith(("+", ":")):
        return None
    target = refspec.split(":", 1)[1] if ":" in refspec else refspec
    if target == "HEAD":
        target = current_branch(directory)
    return target.removeprefix("refs/heads/")


def push_is_refused(arguments, directory):
    flags, positional = push_arguments(arguments)
    if any(rewrites_history(flag) for flag in flags):
        return True
    refspecs = positional[1:] or ["HEAD"]
    return any(destination(refspec, directory) in PROTECTED_BRANCHES | {None} for refspec in refspecs)


def segment_is_refused(segment, cwd):
    subcommand, directory, arguments = git_subcommand(segment.split())
    if subcommand == "alias":
        return True
    if subcommand != "push":
        return False
    return push_is_refused(arguments, os.path.join(cwd, directory or "."))


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
    command = payload.get("tool_input", {}).get("command", "")
    cwd = payload.get("cwd") or os.getcwd()
    if any(segment_is_refused(segment, cwd) for segment in segments(command)):
        record_denial("git-push-guard", payload, REASON)
        print(json.dumps(deny(REASON)))


main()
