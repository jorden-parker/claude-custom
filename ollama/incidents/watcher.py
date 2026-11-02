#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys
import time
from collections import deque, namedtuple
from pathlib import Path

DETAIL_LENGTH = 200
REPREFILL_MARGIN_TOKENS = 300
REPREFILL_MIN_TOKENS = 1000
BLIND_MIN_MENTIONS = 50
IGNORED = "ignored"

LOG_TIME = re.compile(r"\btime=(\S+)")
TRANSCRIPT_TIME = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?")
CONTEXT_SIZE = re.compile(r"\bn_ctx(?:_slot)?\s*=\s*(\d+)")
PROMPT_EVAL = re.compile(
    r"prompt eval time\s*=\s*[\d.]+ ms /\s*(\d+) tokens|\bn_prompt_tokens\s*=\s*(\d+)|\bprompt_eval_count[=:]\s*(\d+)"
)
REQUEST_TOTAL = re.compile(
    r"total time\s*=\s*[\d.]+ ms /\s*(\d+) tokens|\bn_tokens\s*=\s*(\d+),\s*truncated\s*="
)
TRUNCATED_PROMPT = re.compile(r"\bprompt=(\d+)")
RUNNER_MENTION = re.compile(r"\brunners?\b")
RUNNER_START = r"starting (?:llama-server|go runner|runner)\b|runner started"

Rule = namedtuple("Rule", "id pattern cause")


def rule(cause, name, pattern):
    return Rule(f"{cause}/{name}", re.compile(pattern), cause)


CAUSE_RULES = (
    rule("aborted", "context-canceled", r"context canceled"),
    rule("truncated", "input-prompt", r"truncating input prompt"),
    rule("evicted", "unload", r"\bunload"),
    rule("evicted", "runner-start", RUNNER_START),
    rule(IGNORED, "load-sequence", r"loaded runners|template selection"),
)
REPREFILL_RULE = "reprefilled/prompt-eval"
COMPACTION_RULE = "compacted/transcript"
RULE_IDS = tuple(each.id for each in CAUSE_RULES) + (REPREFILL_RULE, COMPACTION_RULE)

EVENT_PATTERNS = (
    ("embed", re.compile(r"/api/embed")),
    ("expired", re.compile(r"\bexpired\b|expiring to unload")),
    ("unload", re.compile(r"\bunload")),
    ("load", re.compile(RUNNER_START + r"|loading model")),
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


def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def line_time(line):
    match = LOG_TIME.search(line)
    return match.group(1) if match else now_iso()


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


class LogClassifier:
    def __init__(self, model):
        self.model = model
        self.context_size = None
        self.previous_total = None
        self.last_event = None
        self.stats = RuleStats()

    def note_counts(self, line):
        context = CONTEXT_SIZE.search(line)
        if context:
            self.context_size = int(context.group(1))
        total = REQUEST_TOTAL.search(line)
        if total:
            self.previous_total = first_group(total)

    def note_event(self, line):
        for kind, pattern in EVENT_PATTERNS:
            if pattern.search(line):
                self.last_event = {"kind": kind, "ts": line_time(line)}
                return

    def is_reprefill(self, tokens):
        if tokens < REPREFILL_MIN_TOKENS:
            return False
        near_context = (
            self.context_size is not None
            and tokens >= self.context_size - REPREFILL_MARGIN_TOKENS
        )
        near_previous = (
            self.previous_total is not None
            and abs(tokens - self.previous_total) <= REPREFILL_MARGIN_TOKENS
        )
        return near_context or near_previous

    def mentions_session(self, line):
        names_model = self.model is not None and self.model in line
        return names_model or RUNNER_MENTION.search(line) is not None

    def classify(self, line):
        self.stats.lines += 1
        self.note_counts(line)
        self.note_event(line)
        mentions = self.mentions_session(line)
        if mentions:
            self.stats.mentions += 1
        matched = self.matching_rule(line)
        if matched is not None:
            return self.ruled_incident(line, matched)
        prompt_eval = PROMPT_EVAL.search(line)
        if prompt_eval:
            return self.reprefill(line, first_group(prompt_eval))
        if mentions:
            self.stats.unmatched += 1
            return incident(line, "unknown", None)
        return None

    @staticmethod
    def matching_rule(line):
        return next((each for each in CAUSE_RULES if each.pattern.search(line)), None)

    def ruled_incident(self, line, matched):
        self.stats.hit(matched.id)
        if matched.cause == IGNORED:
            return None
        return incident(
            line, matched.cause, self.tokens_of(line, matched.cause), rule=matched.id
        )

    def reprefill(self, line, tokens):
        if not self.is_reprefill(tokens):
            return None
        self.stats.hit(REPREFILL_RULE)
        entry = incident(line, "reprefilled", tokens, rule=REPREFILL_RULE)
        entry["preceded_by"] = self.last_event
        return entry

    @staticmethod
    def tokens_of(line, cause):
        if cause != "truncated":
            return None
        match = TRUNCATED_PROMPT.search(line)
        return int(match.group(1)) if match else None


def incident(line, cause, tokens, timestamp=None, rule=None):
    return {
        "ts": timestamp or line_time(line),
        "cause": cause,
        "detail": line[:DETAIL_LENGTH],
        "tokens": tokens,
        "rule": rule,
    }


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
        line,
        "compacted",
        tokens if isinstance(tokens, int) else None,
        timestamp or now_iso(),
        rule=COMPACTION_RULE,
    )


class IncidentLog:
    def __init__(self, path):
        self.path = Path(path)
        self.latest = Path(f"{path}.latest")

    def prepare(self):
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.path.parent.chmod(0o700)

    def record(self, entry):
        line = json.dumps(entry)
        self.append(line)
        with self.open_private(
            self.latest, os.O_WRONLY | os.O_CREAT | os.O_TRUNC
        ) as handle:
            handle.write(line + "\n")

    def record_health(self, entry):
        self.append(json.dumps(entry))

    def append(self, line):
        with self.open_private(
            self.path, os.O_WRONLY | os.O_CREAT | os.O_APPEND
        ) as handle:
            handle.write(line + "\n")

    @staticmethod
    def open_private(path, flags):
        return os.fdopen(os.open(path, flags, 0o600), "w")


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
        self.out.record_health(self.classifier.stats.health())

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
