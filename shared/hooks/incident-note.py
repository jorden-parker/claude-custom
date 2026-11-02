#!/usr/bin/env python3
import json
import os
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

INCIDENTS_FILE_VARIABLE = "CLAUDE_OLLAMA_INCIDENTS_FILE"
CAUSE_ORDER = ("aborted", "evicted", "truncated", "reprefilled", "compacted", "unknown")


def claude_config_dir():
    return Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")


def state_path(session_id):
    return claude_config_dir() / "cache" / "incident-note" / f"{session_id}.json"


def reported_count(path):
    try:
        return int(json.loads(path.read_text())["reported"])
    except (OSError, ValueError, KeyError, TypeError):
        return 0


def save_reported_count(path, count):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"reported": count}))


def read_incidents(path):
    try:
        lines = Path(path).read_text().splitlines()
    except OSError:
        return []
    incidents = []
    for line in lines:
        try:
            incidents.append(json.loads(line))
        except ValueError:
            continue
    return incidents


def local_clock(timestamp):
    try:
        moment = datetime.fromisoformat(str(timestamp))
    except ValueError:
        return "?"
    return moment.astimezone().strftime("%H:%M")


def thousands(tokens):
    return f"{round(tokens / 1000)}k tokens"


def explanation(incident):
    cause = incident.get("cause")
    tokens = incident.get("tokens")
    has_count = isinstance(tokens, int)
    if cause == "aborted":
        return "the request was cancelled mid-flight"
    if cause == "evicted":
        return "the model was unloaded and reloaded"
    if cause == "truncated":
        return (
            f"the prompt of {thousands(tokens)} was cut to fit"
            if has_count
            else "the prompt was cut to fit"
        )
    if cause == "reprefilled":
        return (
            f"re-prefilled {thousands(tokens)}"
            if has_count
            else "re-prefilled the whole prompt"
        )
    if cause == "compacted":
        return (
            f"compacted at {thousands(tokens)}"
            if has_count
            else "the context was compacted"
        )
    return str(incident.get("detail", ""))[:80]


def counts_line(incidents):
    counts = Counter(incident.get("cause", "unknown") for incident in incidents)
    return ", ".join(
        f"{cause} {counts[cause]}" for cause in CAUSE_ORDER if counts[cause]
    )


def note(incidents):
    last = incidents[-1]
    return (
        f"last incident: {last.get('cause', 'unknown')} at {local_clock(last.get('ts'))} "
        f"({explanation(last)}); since the session started: {counts_line(incidents)}"
    )


def reply(context):
    return {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": context,
        }
    }


def main():
    event = json.load(sys.stdin)
    incidents_file = os.environ.get(INCIDENTS_FILE_VARIABLE)
    if not incidents_file:
        return
    incidents = read_incidents(incidents_file)
    path = state_path(event.get("session_id", "nosession"))
    if len(incidents) <= reported_count(path):
        return
    save_reported_count(path, len(incidents))
    print(json.dumps(reply(note(incidents))))


if __name__ == "__main__":
    main()
