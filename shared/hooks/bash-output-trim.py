#!/usr/bin/env python3
import json
import re
import sys

MAX_LINES = 150
HEAD_LINES = 30
TAIL_LINES = 60
MAX_SIGNAL_LINES = 40
MAX_LINE_CHARS = 400
SIGNAL = re.compile(r"error|fail|panic|traceback|exception|fatal|assert", re.IGNORECASE)
SUMMARY = re.compile(
    r"^(?:ok|PASS|FAIL)\b|\b\d+ (?:passed|failed|skipped|total)\b|^Tests:|^Test Suites:|^=+ .* =+$"
)
STREAMS = ("stdout", "stderr")


def is_signal(line):
    return bool(SIGNAL.search(line) or SUMMARY.search(line))


def clip_line(line):
    if len(line) <= MAX_LINE_CHARS:
        return line
    return f"{line[:MAX_LINE_CHARS]} … [{len(line) - MAX_LINE_CHARS} chars hidden]"


def hidden_marker(count, first, last):
    return (
        f"[bash-output-trim: {count} lines hidden from lines {first}-{last}; "
        "rerun piped through grep or sed -n to see them]"
    )


def trim_lines(lines):
    if len(lines) <= MAX_LINES:
        return lines
    middle = lines[HEAD_LINES:-TAIL_LINES]
    signals = [line for line in middle if is_signal(line)][:MAX_SIGNAL_LINES]
    marker = hidden_marker(len(middle) - len(signals), HEAD_LINES + 1, len(lines) - TAIL_LINES)
    return lines[:HEAD_LINES] + signals + [marker] + lines[-TAIL_LINES:]


def trim_text(text):
    return "\n".join(clip_line(line) for line in trim_lines(text.split("\n")))


def trimmed_response(response):
    trimmed = dict(response)
    for stream in STREAMS:
        if isinstance(response.get(stream), str):
            trimmed[stream] = trim_text(response[stream])
    return trimmed


def updated_output(response):
    return {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "updatedToolOutput": response,
        }
    }


def main():
    event = json.load(sys.stdin)
    response = event.get("tool_response")
    if event.get("tool_name") != "Bash" or not isinstance(response, dict):
        return
    trimmed = trimmed_response(response)
    if trimmed != response:
        print(json.dumps(updated_output(trimmed)))


main()
