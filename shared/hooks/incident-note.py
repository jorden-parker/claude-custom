#!/usr/bin/env python3
import json
import os
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hook_state

INCIDENTS_FILE_VARIABLE = "CLAUDE_OLLAMA_INCIDENTS_FILE"
CAUSE_ORDER = ("aborted", "evicted", "truncated", "reprefilled", "compacted", "relaunched", "unknown")


def reported_count(state):
    try:
        return int(state["reported"])
    except (ValueError, TypeError):
        return 0


def claim_unreported(path, total):
    if not path.exists():
        hook_state.prune("incident-note")
    with hook_state.update_state(path, {"reported": 0}) as state:
        if total <= reported_count(state):
            return False
        state["reported"] = total
        return True


def read_incidents(path):
    try:
        lines = Path(path).read_text().splitlines()
    except OSError:
        return []
    rows = []
    for line in lines:
        try:
            rows.append(json.loads(line))
        except ValueError:
            continue
    return [row for row in rows if "kind" not in row]


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
    if cause == "relaunched":
        return (
            f"resumed from a handoff note at {thousands(tokens)}"
            if has_count
            else "resumed from a handoff note"
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
    path = hook_state.state_path("incident-note", event.get("session_id", "nosession"))
    if not claim_unreported(path, len(incidents)):
        return
    print(json.dumps(reply(note(incidents))))


if __name__ == "__main__":
    main()
