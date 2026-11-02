#!/usr/bin/env python3
import json
import os
import sys
import time
from pathlib import Path

from hook_telemetry import record_hook_event

DEFAULT_THRESHOLD_PCT = 70
CONTEXT_TOKEN_KEYS = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")
HANDOFF_NUDGE = (
    "Context budget: {percent}% of the {max_tokens}-token window is used. Finish the current edit, "
    "then call the handoff skill with the argument save through the Skill tool (skill: handoff, args: save), "
    "then stop and tell the user a relaunch is coming: the launcher restarts claude on that note."
)


def claude_config_dir():
    return Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")


def state_path(session_id):
    return claude_config_dir() / "cache" / "context-budget" / f"{session_id}.json"


def positive_int(text):
    try:
        value = int(text)
    except (TypeError, ValueError):
        return None
    return value if value > 0 else None


def usage_of(line):
    try:
        entry = json.loads(line)
    except ValueError:
        return None
    if not isinstance(entry, dict) or entry.get("type") != "assistant":
        return None
    usage = (entry.get("message") or {}).get("usage")
    return usage if isinstance(usage, dict) else None


def last_context_tokens(transcript_path):
    try:
        lines = Path(transcript_path).read_text(encoding="utf-8").splitlines()
    except (OSError, TypeError):
        return None
    for line in reversed(lines):
        usage = usage_of(line)
        if usage is not None:
            return sum(usage.get(key) or 0 for key in CONTEXT_TOKEN_KEYS)
    return None


def percent_used(event):
    max_tokens = positive_int(os.environ.get("CLAUDE_CODE_MAX_CONTEXT_TOKENS"))
    used = last_context_tokens(event.get("transcript_path"))
    if max_tokens is None or used is None:
        return None, None
    return used * 100 // max_tokens, max_tokens


def nudge_reply(percent, max_tokens):
    return {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": HANDOFF_NUDGE.format(percent=percent, max_tokens=max_tokens),
        }
    }


def record_nudge(path, percent):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"nudged_at": time.time(), "percent": percent}))


def main():
    event = json.load(sys.stdin)
    if event.get("hook_event_name") != "PostToolUse":
        return
    path = state_path(event.get("session_id", "nosession"))
    if path.exists():
        return
    percent, max_tokens = percent_used(event)
    threshold = positive_int(os.environ.get("CLAUDE_OLLAMA_HANDOFF_PCT")) or DEFAULT_THRESHOLD_PCT
    if percent is None or percent < threshold:
        return
    record_nudge(path, percent)
    reply = nudge_reply(percent, max_tokens)
    record_hook_event("context-budget", event, "budget", reply["hookSpecificOutput"]["additionalContext"])
    print(json.dumps(reply))


if __name__ == "__main__":
    main()
