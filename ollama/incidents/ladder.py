#!/usr/bin/env python3
import argparse
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

from watcher import FileTail, IncidentLog, now_iso, process_alive

EVIDENCE_COUNT = 3
EVIDENCE_WINDOW_SECONDS = 600
WINDOW_LABEL = "within 10 minutes"
CONTEXT_STEP = 1024
MIN_CONTEXT = 16384
LOWER_CONTEXT_SHARE = 0.75
CLAUDE_PROCESS_NAMES = ("node", "claude")
DEFAULT_SIZES = Path(__file__).resolve().parent.parent / "sizes.json"


def preceded_kind(row):
    preceded = row.get("preceded_by")
    return preceded.get("kind") if isinstance(preceded, dict) else None


def reprefilled_after(kind):
    return lambda row: row.get("cause") == "reprefilled" and preceded_kind(row) == kind


RUNGS = (
    ("embeddings-off", reprefilled_after("embed"), "re-prefills after an embed request"),
    ("heartbeat", reprefilled_after("expired"), "re-prefills after a keep-alive expiry"),
    ("context-down", lambda row: row.get("cause") == "truncated", "truncated prompts"),
)


def parse_options(argv):
    parser = argparse.ArgumentParser(prog="ladder.py", description="Degrade the session rung by rung on incident evidence")
    parser.add_argument("--incidents", default=os.environ.get("CLAUDE_OLLAMA_INCIDENTS_FILE"))
    parser.add_argument("--relaunch-dir", default=os.environ.get("CLAUDE_OLLAMA_RELAUNCH_DIR"))
    parser.add_argument("--watch-pid", type=int)
    parser.add_argument("--context", type=int)
    parser.add_argument("--sizes", default=str(DEFAULT_SIZES))
    parser.add_argument("--interval", type=float, default=1.0)
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--inspect", metavar="FILE")
    options = parser.parse_args(argv)
    if options.inspect:
        return options
    if not options.incidents or not options.relaunch_dir:
        parser.error("--incidents and --relaunch-dir are required (or their CLAUDE_OLLAMA_ variables)")
    if not options.once and options.watch_pid is None:
        parser.error("--watch-pid is required unless --once is given")
    return options


def row_time(row):
    try:
        return time.mktime(time.strptime(row.get("ts", ""), "%Y-%m-%dT%H:%M:%SZ"))
    except (TypeError, ValueError):
        return time.time()


def parse_rows(lines):
    for line in lines:
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if isinstance(row, dict) and "kind" not in row:
            yield row


def configured_contexts(sizes_path):
    try:
        sizes = json.loads(Path(sizes_path).read_text())
    except (OSError, ValueError):
        return []
    return [size["context"] for size in sizes.values() if isinstance(size, dict) and isinstance(size.get("context"), int)]


def lower_context(current, sizes_path):
    lower = [context for context in configured_contexts(sizes_path) if context < current]
    if lower:
        return max(lower)
    rounded = int(current * LOWER_CONTEXT_SHARE) // CONTEXT_STEP * CONTEXT_STEP
    return max(rounded, MIN_CONTEXT)


def is_claude_process(pid):
    try:
        comm = subprocess.run(["ps", "-o", "comm=", "-p", str(pid)], capture_output=True, text=True, check=False).stdout.strip()
    except OSError:
        return False
    return any(name in Path(comm).name for name in CLAUDE_PROCESS_NAMES)


def terminate_claude(relaunch_dir):
    try:
        pid = int((relaunch_dir / "claude.pid").read_text().strip())
    except (OSError, ValueError):
        return
    if pid > 0 and is_claude_process(pid):
        os.kill(pid, signal.SIGTERM)


class Evidence:
    def __init__(self):
        self.fired = {}
        self.times = {name: [] for name, _, _ in RUNGS}
        self.noted = set()

    def consider(self, row):
        matched = False
        for name, matches, description in RUNGS:
            if not matches(row):
                continue
            matched = True
            if name in self.fired:
                continue
            if self.gathered(name, row_time(row)):
                self.fired[name] = f"{EVIDENCE_COUNT} {description} {WINDOW_LABEL}"
                yield name, self.fired[name]
        if not matched and row.get("cause") != "degraded":
            note = self.note_for(row)
            if note:
                yield None, note

    def gathered(self, name, when):
        times = self.times[name]
        times.append(when)
        del times[:-EVIDENCE_COUNT]
        return len(times) == EVIDENCE_COUNT and max(times) - min(times) <= EVIDENCE_WINDOW_SECONDS

    def note_for(self, row):
        kind = preceded_kind(row)
        key = f"{row.get('cause')} after {kind}" if kind else str(row.get("cause"))
        if key in self.noted:
            return None
        self.noted.add(key)
        return f"{key}: no rung"


class Ladder:
    def __init__(self, options):
        self.options = options
        self.relaunch_dir = Path(options.relaunch_dir)
        self.log = IncidentLog(options.incidents)
        self.tail = FileTail(options.incidents, start_at_end=False)
        self.evidence = Evidence()

    def poll(self):
        for row in parse_rows(self.tail.new_lines()):
            for name, text in self.evidence.consider(row):
                if name is None:
                    self.log.record_health({"kind": "ladder", "ts": now_iso(), "note": text})
                else:
                    self.fire(name, text)

    def fire(self, name, reason):
        if name == "embeddings-off":
            (self.relaunch_dir / "embed-off").touch()
        elif name == "heartbeat":
            (self.relaunch_dir / "heartbeat-fast").touch()
        elif name == "context-down":
            self.lower_context(reason)
        self.log.record({"ts": now_iso(), "cause": "degraded", "detail": f"{name}: {reason}", "tokens": None, "rule": f"ladder/{name}"})

    def lower_context(self, reason):
        current = self.options.context or 0
        target = {"rung": "context-down", "context": lower_context(current, self.options.sizes), "reason": reason}
        (self.relaunch_dir / "ladder").write_text(json.dumps(target))
        terminate_claude(self.relaunch_dir)

    def run(self):
        if self.options.once:
            self.poll()
            return
        while process_alive(self.options.watch_pid):
            self.poll()
            time.sleep(self.options.interval)


def inspect(path):
    evidence = Evidence()
    lines = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        rows = list(parse_rows(handle))
    for row in rows:
        lines += [f"{name}: {text}" for name, text in evidence.consider(row) if name]
    print("\n".join(lines) if lines else "none")


def main(argv):
    options = parse_options(argv)
    if options.inspect:
        inspect(options.inspect)
        return 0
    Ladder(options).run()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
