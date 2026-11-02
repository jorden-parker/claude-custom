#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

EDIT_TOOLS = {"Edit", "Write", "MultiEdit"}
CODE_SUFFIXES = {
    ".go",
    ".ts",
    ".tsx",
    ".js",
    ".jsx",
    ".mjs",
    ".cjs",
    ".py",
    ".sh",
    ".bash",
    ".zsh",
}
PLACEHOLDER_NAMES = {
    "tmp",
    "temp",
    "data",
    "obj",
    "val",
    "stuff",
    "thing",
    "things",
    "foo",
    "bar",
    "baz",
    "misc",
    "info",
    "dummy",
    "res",
    "ret",
    "retval",
    "arr",
    "util",
    "utils",
    "helper",
    "helpers",
    "new",
    "old",
}
VAGUE_OBJECTS = {"stuff", "thing", "things", "it", "misc", "obj"}
VAGUE_SUFFIXES = {"helper", "helpers", "util", "utils", "misc", "stuff", "thing"}
NUMBERED_STEMS_ALLOWED = {
    "utf",
    "int",
    "uint",
    "float",
    "vec",
    "mat",
    "ipv",
    "base",
    "complex",
    "win",
    "mp",
    "ec",
}
DECLARATION_PATTERNS = [
    re.compile(
        r"\b(?:var|const|let|func|function|class|type|def|local|readonly|export)\s+([A-Za-z_]\w*)"
    ),
    re.compile(r"\bfunc\s*\([^)]*\)\s*([A-Za-z_]\w*)"),
    re.compile(r"^\s*([A-Za-z_]\w*)\s*:=", re.MULTILINE),
    re.compile(r"^\s*([A-Za-z_]\w*)\s*=[^=]", re.MULTILINE),
    re.compile(r"^\s*(?:function\s+)?([A-Za-z_]\w*)\s*\(\)\s*\{", re.MULTILINE),
]
WORD_SPLIT = re.compile(r"[A-Z]?[a-z]+|[A-Z]+(?![a-z])|\d+")
NUMBERED = re.compile(r"^([a-z]{3,})[2-9]$")


def words_of(name):
    return [word.lower() for word in WORD_SPLIT.findall(name)]


def says_nothing(name):
    lowered = name.lower().strip("_")
    if lowered in PLACEHOLDER_NAMES:
        return True
    numbered = NUMBERED.match(lowered)
    if numbered and numbered.group(1) not in NUMBERED_STEMS_ALLOWED:
        return True
    words = words_of(name)
    if len(words) < 2:
        return False
    if words[-1] in VAGUE_SUFFIXES:
        return True
    return all(word in VAGUE_OBJECTS for word in words[1:])


def declared_names(text):
    found = []
    for pattern in DECLARATION_PATTERNS:
        for name in pattern.findall(text):
            if name not in found:
                found.append(name)
    return found


def written_texts(tool_name, tool_input):
    if tool_name == "Write":
        return [tool_input.get("content") or ""]
    if tool_name == "MultiEdit":
        return [edit.get("new_string") or "" for edit in tool_input.get("edits") or []]
    return [tool_input.get("new_string") or ""]


def first_line_of_file(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.readline()
    except OSError:
        return ""


def is_code(path, texts, tool_name):
    if path.suffix in CODE_SUFFIXES:
        return True
    if path.suffix:
        return False
    first_line = texts[0] if tool_name == "Write" else first_line_of_file(path)
    return first_line.startswith("#!")


def file_stem(path):
    return path.name.split(".")[0]


def vague_file_name(path):
    stem = file_stem(path)
    if says_nothing(stem):
        return stem
    words = [word for word in re.split(r"[-_]", stem) if word]
    if words and all(word in PLACEHOLDER_NAMES for word in words):
        return stem
    return None


def nudge_text(names, file_name):
    parts = []
    if names:
        parts.append(
            "Names in this write say nothing about what they hold or do: "
            + ", ".join(names)
            + ". Rename each for what it holds or does (parsedConfig, retryCount, closeIdleSockets) in your next edit."
        )
    if file_name:
        parts.append(
            f"File name {file_name} says nothing: name the file for what it holds."
        )
    return " ".join(parts)


def handle(event):
    if (
        event.get("hook_event_name") != "PreToolUse"
        or event.get("tool_name") not in EDIT_TOOLS
    ):
        return None
    tool_name = event["tool_name"]
    tool_input = event.get("tool_input") or {}
    path = Path(tool_input.get("file_path") or "")
    texts = written_texts(tool_name, tool_input)
    if not path.name or not is_code(path, texts, tool_name):
        return None
    names = [name for name in declared_names("\n".join(texts)) if says_nothing(name)]
    file_name = vague_file_name(path) if tool_name == "Write" else None
    if not names and not file_name:
        return None
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": nudge_text(names, file_name),
        }
    }


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    output = handle(event)
    if output:
        print(json.dumps(output))


if __name__ == "__main__":
    main()
