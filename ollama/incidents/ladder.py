#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
from relaunch_dir import RelaunchDir
from incident_log import IncidentLog, incident, incident_rows, now_iso
from watcher import FileTail, process_alive

EVIDENCE_COUNT = 3
EVIDENCE_WINDOW_SECONDS = 600
WINDOW_LABEL = "within 10 minutes"
CONTEXT_STEP = 1024
MIN_CONTEXT = 16384
LOWER_CONTEXT_SHARE = 0.75
DEFAULT_SIZES = Path(__file__).resolve().parent.parent / "sizes.json"
DEFAULT_LEASE_BIN = Path(__file__).resolve().parent.parent.parent / "bin" / "ollama-lease"
RECOVERY_QUIET_SECONDS = 1200
FIT_RETRY_SECONDS = 60
RECOVERABLE_RUNGS = ("embeddings-off", "context-down")
LAUNCH_RUNG_REASON = "did not fit at launch"


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
DESCRIPTIONS = {name: description for name, _, description in RUNGS}


def parse_options(argv):
    parser = argparse.ArgumentParser(prog="ladder.py", description="Degrade the session rung by rung on incident evidence")
    parser.add_argument("--incidents", default=os.environ.get("CLAUDE_OLLAMA_INCIDENTS_FILE"))
    parser.add_argument("--relaunch-dir", default=os.environ.get("CLAUDE_OLLAMA_RELAUNCH_DIR"))
    parser.add_argument("--watch-pid", type=int)
    parser.add_argument("--context", type=int)
    parser.add_argument("--sizes", default=str(DEFAULT_SIZES))
    parser.add_argument("--interval", type=float, default=1.0)
    parser.add_argument("--model")
    parser.add_argument("--embedding")
    parser.add_argument("--lease-bin", default=os.environ.get("CLAUDE_OLLAMA_LEASE_BIN", str(DEFAULT_LEASE_BIN)))
    parser.add_argument("--rung", action="append", default=[], choices=RECOVERABLE_RUNGS)
    parser.add_argument("--quiet-seconds", type=float, default=RECOVERY_QUIET_SECONDS)
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
        moment = datetime.fromisoformat(row.get("ts", "").replace("Z", "+00:00"))
    except (AttributeError, TypeError, ValueError):
        return time.time()
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.timestamp()


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


class Evidence:
    def __init__(self):
        self.fired = {}
        self.fired_order = []
        self.last_seen = {}
        self.times = {name: [] for name, _, _ in RUNGS}
        self.noted = set()

    def mark_fired(self, name, reason, when):
        self.fired[name] = reason
        self.fired_order.append(name)
        self.last_seen[name] = when

    def recover(self, name):
        self.fired.pop(name, None)
        self.fired_order.remove(name)
        self.last_seen.pop(name, None)
        self.times[name] = []

    def in_effect(self, name):
        return name in self.fired

    def quiet_rungs(self, now, quiet_seconds):
        for name in reversed(self.fired_order):
            if name in RECOVERABLE_RUNGS and now - self.last_seen[name] >= quiet_seconds:
                yield name

    def consider(self, row):
        matched = False
        for name, matches, description in RUNGS:
            if not matches(row):
                continue
            matched = True
            if name in self.fired:
                self.last_seen[name] = max(self.last_seen[name], row_time(row))
                continue
            if self.gathered(name, row_time(row)):
                self.mark_fired(name, f"{EVIDENCE_COUNT} {description} {WINDOW_LABEL}", row_time(row))
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


def quiet_label(quiet_seconds):
    return f"{int(quiet_seconds // 60)} minutes without"


def recovery_reason(name, quiet_seconds):
    return f"{quiet_label(quiet_seconds)} {DESCRIPTIONS[name]}, memory fits"


class Recovery:
    def __init__(self, options, evidence):
        self.options = options
        self.evidence = evidence
        self.folder = RelaunchDir(options.relaunch_dir)
        self.proposed = None
        self.next_fit_at = 0.0
        for name in options.rung:
            evidence.mark_fired(name, LAUNCH_RUNG_REASON, time.time())

    def poll(self):
        if self.proposed is not None:
            if self.folder.has("ladder-up"):
                return
            self.evidence.recover(self.proposed)
            self.proposed = None
            self.next_fit_at = 0.0
        now = time.time()
        for name in self.evidence.quiet_rungs(now, self.options.quiet_seconds):
            if now < self.next_fit_at:
                return
            self.next_fit_at = now + FIT_RETRY_SECONDS
            if self.fit_passes(name):
                self.propose(name)
            return

    def propose(self, name):
        reason = recovery_reason(name, self.options.quiet_seconds)
        self.folder.request("ladder-up", {"rung": name, "reason": reason})
        self.proposed = name

    def fit_context(self, name):
        lowered = name != "context-down" and self.evidence.in_effect("context-down")
        return lower_context(self.options.context, self.options.sizes) if lowered else self.options.context

    def fit_arguments(self, name):
        arguments = [self.options.lease_bin, "fit", "--model", self.options.model, "--num-ctx", str(self.fit_context(name))]
        embeddings_on = name == "embeddings-off" or not self.evidence.in_effect("embeddings-off")
        if self.options.embedding and embeddings_on:
            arguments += ["--embedding", self.options.embedding]
        return arguments

    def fit_passes(self, name):
        if not self.options.model or not self.options.context:
            return False
        try:
            output = subprocess.run(self.fit_arguments(name), capture_output=True, text=True, check=False).stdout
            return json.loads(output).get("fits") is True
        except (OSError, ValueError, AttributeError):
            return False


class Ladder:
    def __init__(self, options):
        self.options = options
        self.folder = RelaunchDir(options.relaunch_dir)
        self.log = IncidentLog(options.incidents)
        self.tail = FileTail(options.incidents, start_at_end=False)
        self.evidence = Evidence()
        self.recovery = Recovery(options, self.evidence)

    def poll(self):
        for row in incident_rows(self.tail.new_lines()):
            for name, text in self.evidence.consider(row):
                if name is None:
                    self.log.record_kind_row({"kind": "ladder", "ts": now_iso(), "note": text})
                else:
                    self.fire(name, text)
        self.recovery.poll()

    def fire(self, name, reason):
        if name == "embeddings-off":
            self.folder.raise_flag("embed-off")
        elif name == "heartbeat":
            self.folder.raise_flag("heartbeat-fast")
        elif name == "context-down":
            self.lower_context(reason)
        self.log.record(incident(now_iso(), "degraded", f"{name}: {reason}", rule=f"ladder/{name}"))

    def lower_context(self, reason):
        current = self.options.context or 0
        target = {"rung": "context-down", "context": lower_context(current, self.options.sizes), "reason": reason}
        self.folder.request("ladder", target)
        self.folder.terminate_claude()

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
        rows = list(incident_rows(handle))
    for row in rows:
        lines += [f"{name}: {text}" for name, text in evidence.consider(row) if name]
    for name in evidence.quiet_rungs(time.time(), RECOVERY_QUIET_SECONDS):
        lines.append(f"up {name}: {quiet_label(RECOVERY_QUIET_SECONDS)} {DESCRIPTIONS[name]}")
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
