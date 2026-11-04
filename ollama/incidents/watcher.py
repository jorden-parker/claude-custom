#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys
import time
from collections import deque, namedtuple
from pathlib import Path

from incident_log import IncidentLog, incident, now_iso

REPREFILL_MARGIN_TOKENS = 300
REPREFILL_MIN_TOKENS = 1000
BLIND_MIN_MENTIONS = 50
IGNORED = "ignored"

TRANSCRIPT_TIME = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?")
CONTEXT_SIZE = re.compile(r"\bn_ctx(?:_slot)?\s*=\s*(\d+)")
PROMPT_EVAL = re.compile(r"prompt eval time\s*=\s*[\d.]+ ms /\s*(\d+) tokens")
REQUEST_TOTAL = re.compile(
    r"total time\s*=\s*[\d.]+ ms /\s*(\d+) tokens|\bn_tokens\s*=\s*(\d+),\s*truncated\s*="
)
OVERFLOW_TOKENS = re.compile(r"(?:request|input) \((\d+) tokens\)")
CHILD_PORT = re.compile(r"^\[(\d+)\]")
SPAWN = re.compile(r"spawning server instance with name=(\S+) on port (\d+)")
INSTANCE_NAME = re.compile(r"\bname=(\S+)")
INSTANCE_MENTION = re.compile(r"\binstance\b")

Rule = namedtuple("Rule", "id pattern cause")


def rule(cause, name, pattern):
    return Rule(f"{cause}/{name}", re.compile(pattern), cause)


LOAD_SEQUENCE_RULE = f"{IGNORED}/load-sequence"
CAUSE_RULES = (
    rule("aborted", "cancelled", r"http client error: Canceled|cancelled while model name=|cancelling the pending request"),
    rule(
        "truncated",
        "context-overflow",
        r"exceeds the available context size|is larger than the max context size|Context size has been exceeded",
    ),
    rule("reprefilled", "full-reprocess", r"forcing full prompt re-processing"),
    rule("evicted", "unload", r"stopping model instance name=|evicting idle LRU name="),
    rule("evicted", "runner-start", SPAWN.pattern),
    rule(
        IGNORED,
        "load-sequence",
        r"\[\s*preset\]|spawning server instance with args|\bload: {3}|proxying request to model"
        r"|queued at position|joined the queue|ensure_model:|exited with status|exit command received"
        r"|monitoring thread started|models_max limit reached",
    ),
)
REPREFILL_RULE = "reprefilled/prompt-eval"
COMPACTION_RULE = "compacted/transcript"
RULE_IDS = tuple(each.id for each in CAUSE_RULES) + (REPREFILL_RULE, COMPACTION_RULE)

EVENT_PATTERNS = (
    ("embed", re.compile(r"proxying request to model \S*embed")),
    ("unload", re.compile(r"stopping model instance name=|evicting idle LRU name=")),
    ("load", re.compile(SPAWN.pattern + r"|loading model '")),
)


def parse_options(argv):
    parser = argparse.ArgumentParser(
        description="Record why a claude-ollama session lost context"
    )
    parser.add_argument("--log")
    parser.add_argument("--model")
    parser.add_argument("--out")
    parser.add_argument("--watch-pid", type=int)
    parser.add_argument("--transcripts")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--interval", type=float, default=1.0)
    parser.add_argument("--health-interval", type=float, default=60.0)
    parser.add_argument("--check-rules", action="store_true")
    parser.add_argument("--lines", type=int, default=400)
    options = parser.parse_args(argv)
    if options.check_rules:
        if options.log is None:
            parser.error("--check-rules needs --log")
        return options
    if options.model is None or options.out is None:
        parser.error("--model and --out are required")
    if not options.once and options.watch_pid is None:
        parser.error("--watch-pid is required unless --once is given")
    return options


def process_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def first_group(match):
    return next((int(group) for group in match.groups() if group is not None), None)


class RuleStats:
    def __init__(self):
        self.hits = dict.fromkeys(RULE_IDS, 0)
        self.unmatched = 0
        self.lines = 0
        self.mentions = 0

    def hit(self, rule_id):
        self.hits[rule_id] += 1

    def matched(self):
        return sum(self.hits.values())

    def blind(self):
        return self.mentions >= BLIND_MIN_MENTIONS and self.matched() == 0

    def health(self):
        return {
            "ts": now_iso(),
            "kind": "health",
            "rules": dict(self.hits),
            "unmatched": self.unmatched,
            "lines": self.lines,
        }


class ChildCounts:
    def __init__(self):
        self.context_size = None
        self.previous_total = None
        self.reprocessed = False


class LogClassifier:
    def __init__(self, model):
        self.model = model
        self.port_names = {}
        self.children = {}
        self.last_event = None
        self.stats = RuleStats()

    def child_of(self, line):
        port = CHILD_PORT.match(line)
        key = self.port_names.get(port.group(1), port.group(1)) if port else None
        return self.children.setdefault(key, ChildCounts())

    def note_counts(self, line, child):
        spawn = SPAWN.search(line)
        if spawn:
            self.port_names[spawn.group(2)] = spawn.group(1)
        context = CONTEXT_SIZE.search(line)
        if context:
            child.context_size = int(context.group(1))
        total = REQUEST_TOTAL.search(line)
        if total:
            child.previous_total = first_group(total)

    def note_event(self, line):
        for kind, pattern in EVENT_PATTERNS:
            if pattern.search(line):
                self.last_event = {"kind": kind, "ts": now_iso()}
                return

    @staticmethod
    def is_reprefill(child, tokens):
        if tokens < REPREFILL_MIN_TOKENS:
            return False
        near_context = (
            child.context_size is not None
            and tokens >= child.context_size - REPREFILL_MARGIN_TOKENS
        )
        near_previous = (
            child.previous_total is not None
            and abs(tokens - child.previous_total) <= REPREFILL_MARGIN_TOKENS
        )
        return near_context or near_previous

    def is_session_instance(self, name):
        return name == self.model or name.startswith(f"{self.model}@")

    def names_other_instance(self, line):
        name = INSTANCE_NAME.search(line)
        return self.model is not None and name is not None and not self.is_session_instance(name.group(1))

    def mentions_session(self, line):
        names_model = self.model is not None and self.model in line
        return names_model or INSTANCE_MENTION.search(line) is not None

    def classify(self, line):
        self.stats.lines += 1
        child = self.child_of(line)
        prompt_eval = PROMPT_EVAL.search(line)
        if prompt_eval:
            return self.reprefill(line, child, first_group(prompt_eval))
        self.note_counts(line, child)
        self.note_event(line)
        mentions = self.mentions_session(line)
        if mentions:
            self.stats.mentions += 1
        matched = self.matching_rule(line)
        if matched is not None:
            return self.ruled_incident(line, matched, child)
        if mentions:
            self.stats.unmatched += 1
            return line_incident(line, "unknown", None)
        return None

    @staticmethod
    def matching_rule(line):
        return next((each for each in CAUSE_RULES if each.pattern.search(line)), None)

    def ruled_incident(self, line, matched, child):
        if matched.cause == "evicted" and self.names_other_instance(line):
            matched = next(each for each in CAUSE_RULES if each.id == LOAD_SEQUENCE_RULE)
        self.stats.hit(matched.id)
        if matched.cause == IGNORED:
            return None
        if matched.cause == "reprefilled":
            child.reprocessed = True
            return line_incident(line, matched.cause, None, rule=matched.id, preceded_by=self.last_event)
        return line_incident(line, matched.cause, self.tokens_of(line, matched.cause), rule=matched.id)

    def reprefill(self, line, child, tokens):
        if child.reprocessed:
            child.reprocessed = False
            return None
        if not self.is_reprefill(child, tokens):
            return None
        self.stats.hit(REPREFILL_RULE)
        return line_incident(
            line, "reprefilled", tokens, rule=REPREFILL_RULE, preceded_by=self.last_event
        )

    @staticmethod
    def tokens_of(line, cause):
        if cause != "truncated":
            return None
        match = OVERFLOW_TOKENS.search(line)
        return int(match.group(1)) if match else None


def line_incident(line, cause, tokens, rule=None, preceded_by=None):
    return incident(now_iso(), cause, line, tokens, rule, preceded_by)


def compaction(line):
    if '"compact_boundary"' not in line:
        return None
    try:
        entry = json.loads(line)
    except ValueError:
        return None
    if entry.get("subtype") != "compact_boundary":
        return None
    metadata = entry.get("compactMetadata") or {}
    timestamp = (
        entry.get("timestamp")
        if TRANSCRIPT_TIME.fullmatch(str(entry.get("timestamp")))
        else None
    )
    tokens = metadata.get("preTokens")
    return incident(
        timestamp or now_iso(),
        "compacted",
        line,
        tokens if isinstance(tokens, int) else None,
        COMPACTION_RULE,
    )


class FileTail:
    def __init__(self, path, start_at_end):
        self.path = Path(path)
        self.offset = self.size() if start_at_end else 0

    def size(self):
        try:
            return self.path.stat().st_size
        except OSError:
            return 0

    def new_lines(self):
        if self.size() < self.offset:
            self.offset = 0
        try:
            with self.path.open("rb") as handle:
                handle.seek(self.offset)
                data = handle.read()
        except OSError:
            return []
        complete = data[: data.rfind(b"\n") + 1]
        self.offset += len(complete)
        return complete.decode("utf-8", "replace").splitlines()


class TranscriptScanner:
    def __init__(self, folder, start_at_end):
        self.folder = Path(folder) if folder else None
        self.tails = {}
        self.start_at_end = start_at_end

    def transcript_paths(self):
        if self.folder is None or not self.folder.is_dir():
            return []
        return sorted(self.folder.glob("*/*.jsonl"))

    def new_lines(self):
        for path in self.transcript_paths():
            if path not in self.tails:
                self.tails[path] = FileTail(path, self.start_at_end)
            yield from self.tails[path].new_lines()
        self.start_at_end = False


class Watcher:
    def __init__(self, options):
        self.options = options
        self.classifier = LogClassifier(options.model)
        self.log = FileTail(options.log, not options.once) if options.log else None
        self.transcripts = TranscriptScanner(options.transcripts, not options.once)
        self.out = IncidentLog(options.out)

    def poll(self):
        if self.log is not None:
            for line in self.log.new_lines():
                self.emit(self.classifier.classify(line))
        for line in self.transcripts.new_lines():
            entry = compaction(line)
            if entry is not None:
                self.classifier.stats.hit(COMPACTION_RULE)
            self.emit(entry)

    def emit(self, entry):
        if entry is not None:
            self.out.record(entry)

    def report_health(self):
        self.out.record_kind_row(self.classifier.stats.health())

    def run(self):
        self.out.prepare()
        self.poll()
        if not self.options.once:
            self.follow()
        self.report_health()

    def follow(self):
        next_health = time.monotonic() + self.options.health_interval
        while process_alive(self.options.watch_pid):
            time.sleep(self.options.interval)
            self.poll()
            if time.monotonic() >= next_health:
                self.report_health()
                next_health = time.monotonic() + self.options.health_interval


def last_lines(path, count):
    try:
        with open(path, "rb") as handle:
            kept = deque(handle, maxlen=count)
    except OSError:
        return []
    return [line.decode("utf-8", "replace").rstrip("\r\n") for line in kept]


def check_rules(options):
    classifier = LogClassifier(options.model)
    for line in last_lines(options.log, options.lines):
        classifier.classify(line)
    stats = classifier.stats
    for rule_id in RULE_IDS:
        print(f"{rule_id} {stats.hits[rule_id]}")
    print("blind" if stats.blind() else "ok")
    return 1 if stats.blind() else 0


def main(argv):
    options = parse_options(argv)
    if options.check_rules:
        return check_rules(options)
    Watcher(options).run()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
