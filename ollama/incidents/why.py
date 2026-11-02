#!/usr/bin/env python3
import argparse
import json
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

JOIN_WINDOW = timedelta(seconds=5)
TOP_SECTIONS = 3
DRIFT_SECTIONS = ("system", "tools")
EVICTION_EVENTS = ("embed", "load", "unload")


def parse_options(argv):
    parser = argparse.ArgumentParser(description="Name the most likely cause of the last bad claude-ollama run")
    parser.add_argument("--proxy-log", required=True)
    parser.add_argument("--incidents-dir", required=True)
    parser.add_argument("--since", type=int, metavar="MINUTES")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--now", metavar="ISO")
    return parser.parse_args(argv)


def parse_time(value):
    if not isinstance(value, str):
        return None
    try:
        moment = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)


def json_rows(path):
    try:
        lines = Path(path).read_text().splitlines()
    except OSError:
        return []
    rows = []
    for line in lines:
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if isinstance(row, dict) and parse_time(row.get("ts")) is not None:
            rows.append(row)
    return rows


def current_incidents_file(incidents_dir):
    folder = Path(incidents_dir).resolve()
    try:
        named = (folder / "current").read_text().strip()
    except OSError:
        return None
    resolved = (folder / named).resolve()
    inside = resolved.parent == folder and resolved.suffix == ".jsonl"
    return resolved if inside else None


def incident_rows(incidents_dir):
    current = current_incidents_file(incidents_dir)
    if current is None:
        return []
    rows = [row for row in json_rows(current) if "kind" not in row]
    seen = {json.dumps(row, sort_keys=True) for row in rows}
    for row in json_rows(f"{current}.latest"):
        if "kind" not in row and json.dumps(row, sort_keys=True) not in seen:
            rows.append(row)
    rows.sort(key=lambda row: parse_time(row["ts"]))
    return rows


def within(rows, since_minutes, now):
    if since_minutes is None:
        return rows
    cutoff = now - timedelta(minutes=since_minutes)
    return [row for row in rows if parse_time(row["ts"]) >= cutoff]


def joined_request(incident, requests):
    moment = parse_time(incident["ts"])
    for request in reversed(requests):
        gap = moment - parse_time(request["ts"])
        if timedelta(0) <= gap <= JOIN_WINDOW:
            return request, gap
    return None, None


def preceding_kind(incident):
    preceded = incident.get("preceded_by")
    return preceded.get("kind") if isinstance(preceded, dict) else None


def clock(row):
    return parse_time(row["ts"]).astimezone(timezone.utc).strftime("%H:%M:%S")


def requests_after_first(requests):
    return [row for row in requests if row.get("diverged_at") is not None or row.get("stable_sections", 0) > 0]


def stable_through_tools(request):
    diverged = request.get("diverged_at")
    return diverged is None or (isinstance(diverged, str) and diverged.startswith("message:"))


def prefix_rate(requests):
    counted = requests_after_first(requests)
    stable = sum(1 for row in counted if stable_through_tools(row))
    percent = round(100 * stable / len(counted)) if counted else 0
    return {"percent": percent, "stable": stable, "requests": len(counted)}


def section_rank(section):
    if section in DRIFT_SECTIONS:
        return (DRIFT_SECTIONS.index(section), 0)
    _, _, index = section.partition(":")
    return (len(DRIFT_SECTIONS), int(index) if index.isdigit() else 0)


def diverging_sections(requests):
    counts = Counter(row["diverged_at"] for row in requests if isinstance(row.get("diverged_at"), str))
    ordered = sorted(counts.items(), key=lambda entry: (-entry[1], section_rank(entry[0])))
    return [{"section": section, "count": count} for section, count in ordered[:TOP_SECTIONS]]


def join_note(incident, requests):
    request, gap = joined_request(incident, requests)
    if request is None:
        return "no request within 5s before it"
    seconds = int(gap.total_seconds())
    diverged = request.get("diverged_at") or "nothing"
    return f"the request {seconds}s before it diverged at {diverged}"


def count_phrase(count, cause):
    return f"{count} {cause}"


def last_of(rows):
    return rows[-1]


class Verdict:
    def __init__(self, cause, summary, evidence, fix):
        self.cause = cause
        self.summary = summary
        self.evidence = evidence
        self.fix = fix


def truncated_verdict(incidents, requests):
    rows = [row for row in incidents if row.get("cause") == "truncated"]
    if not rows:
        return None
    last = last_of(rows)
    tokens = last.get("tokens")
    size = f"; the last prompt was {tokens} tokens" if isinstance(tokens, int) else ""
    evidence = f"{count_phrase(len(rows), 'truncated')} at {clock(last)}{size}; {join_note(last, requests)}"
    return Verdict("truncated", "the prompt outgrew num_ctx and Ollama cut its head off", evidence,
                   "run bin/ollama-profiles so CLAUDE_CODE_MAX_CONTEXT_TOKENS fits num_ctx, then claude-ollama doctor")


def evicted_verdict(incidents, requests):
    evicted = [row for row in incidents if row.get("cause") == "evicted"]
    reprefilled = [row for row in incidents if row.get("cause") == "reprefilled" and preceding_kind(row) in EVICTION_EVENTS]
    if not evicted and not reprefilled:
        return None
    parts = []
    if evicted:
        parts.append(count_phrase(len(evicted), "evicted"))
    for kind, count in Counter(preceding_kind(row) for row in reprefilled).most_common():
        parts.append(f"{count} reprefilled after {kind}")
    last = last_of(sorted(evicted + reprefilled, key=lambda row: parse_time(row["ts"])))
    evidence = f"{', '.join(parts)}; last at {clock(last)}; {join_note(last, requests)}"
    return Verdict("evicted", "another model pushed the session's model out of memory and the prompt cache with it", evidence,
                   "set OLLAMA_MAX_LOADED_MODELS=2 in ollama/server.env and run ollama-agent -apply; a second session must wait for the lease (CLAUDE_OLLAMA_LEASE)")


def expired_verdict(incidents, requests):
    rows = [row for row in incidents if row.get("cause") == "reprefilled" and preceding_kind(row) == "expired"]
    if not rows:
        return None
    last = last_of(rows)
    evidence = f"{len(rows)} reprefilled after expired; last at {clock(last)}; {join_note(last, requests)}"
    return Verdict("reprefilled after expired", "the keep-alive ran out between turns and the whole prompt was prefilled again", evidence,
                   "raise OLLAMA_KEEP_ALIVE in ollama/server.env (ollama-agent -apply) or lower CLAUDE_OLLAMA_LEASE_HEARTBEAT")


def drifting_request(incidents, requests):
    drifting = [row for row in requests if row.get("diverged_at") in DRIFT_SECTIONS]
    if not drifting:
        return None, None
    for incident in reversed(incidents):
        joined, _ = joined_request(incident, requests)
        if joined in drifting:
            return joined, drifting
    return last_of(drifting), drifting


def drift_verdict(incidents, requests):
    request, drifting = drifting_request(incidents, requests)
    if request is None:
        return None
    section = request["diverged_at"]
    diff = request.get("diff") or ""
    evidence = f"{len(drifting)} of {len(requests_after_first(requests))} requests diverged before the messages; at {clock(request)} the {section} section changed at offset {request.get('offset')}: \"{diff}\""
    if incidents:
        evidence += f"; {count_phrase(len(incidents), 'incidents')}, {join_note(last_of(incidents), requests)}"
    return Verdict(f"prompt drift at {section}", "a volatile line early in the prompt breaks the cached prefix on every turn", evidence,
                   f"move the volatile line after the stable prefix: \"{diff}\"")


def compacted_verdict(incidents, requests):
    rows = [row for row in incidents if row.get("cause") == "compacted"]
    if not rows:
        return None
    last = last_of(rows)
    tokens = last.get("tokens")
    size = f" from {tokens} tokens" if isinstance(tokens, int) else ""
    evidence = f"{count_phrase(len(rows), 'compacted')}; last at {clock(last)}{size}; {join_note(last, requests)}"
    return Verdict("compacted", "Claude Code compacted the transcript, so the model lost its earlier context", evidence,
                   "lower CLAUDE_OLLAMA_HANDOFF_PCT so /handoff saves a note before compaction")


def degraded_verdict(incidents, requests):
    rows = [row for row in incidents if row.get("cause") == "degraded"]
    if not rows:
        return None
    last = last_of(rows)
    evidence = f"{count_phrase(len(rows), 'degraded')}; last at {clock(last)}: {last.get('detail', '')}"
    return Verdict("degraded", "the ladder already lowered the session to keep it running", evidence,
                   "fix the rung's cause; ollama/incidents/ladder.py --inspect FILE lists what fired")


def reprefilled_verdict(incidents, requests):
    rows = [row for row in incidents if row.get("cause") == "reprefilled"]
    if not rows:
        return None
    last = last_of(rows)
    evidence = f"{count_phrase(len(rows), 'reprefilled')} with no known event before them; last at {clock(last)}; {join_note(last, requests)}"
    return Verdict("reprefilled", "the whole prompt was prefilled again and the server log names no reason", evidence,
                   "run claude-ollama doctor and claude-ollama logs around that time")


PRIORITY = (
    truncated_verdict,
    evicted_verdict,
    expired_verdict,
    drift_verdict,
    compacted_verdict,
    degraded_verdict,
    reprefilled_verdict,
)


def decide(incidents, requests):
    for rule in PRIORITY:
        verdict = rule(incidents, requests)
        if verdict is not None:
            return verdict
    return Verdict("nothing wrong", "no incident and no prompt drift before the messages", f"{len(incidents)} incidents, {len(requests)} requests", "nothing to do")


def window_label(since_minutes):
    return f"last {since_minutes} minutes" if since_minutes is not None else "whole log"


def report(options, incidents, requests):
    verdict = decide(incidents, requests)
    return {
        "verdict": verdict.cause,
        "summary": verdict.summary,
        "evidence": verdict.evidence,
        "fix": verdict.fix,
        "prefix": prefix_rate(requests),
        "diverging": diverging_sections(requests),
        "incidents": dict(Counter(row.get("cause", "unknown") for row in incidents)),
        "window": window_label(options.since),
    }


def drift_line(sections):
    if not sections:
        return "none"
    return " · ".join(f"{entry['section']} {entry['count']}" for entry in sections)


def text_report(summary):
    prefix = summary["prefix"]
    return "\n".join([
        f"verdict: {summary['verdict']}: {summary['summary']} ({summary['window']})",
        f"evidence: {summary['evidence']}",
        f"fix: {summary['fix']}",
        f"prefix: {prefix['percent']}% of {prefix['requests']} requests stable through tools",
        f"drift: {drift_line(summary['diverging'])}",
    ])


def main(argv):
    options = parse_options(argv)
    now = parse_time(options.now) if options.now else datetime.now(timezone.utc)
    requests = within(json_rows(options.proxy_log), options.since, now)
    incidents = within(incident_rows(options.incidents_dir), options.since, now)
    summary = report(options, incidents, requests)
    if options.json:
        print(json.dumps(summary, indent=1))
    else:
        print(text_report(summary))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
