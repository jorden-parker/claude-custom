#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

DETAIL_LENGTH = 200
REPREFILL_MARGIN_TOKENS = 300
REPREFILL_MIN_TOKENS = 1000
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

CAUSE_RULES = (
    (re.compile(r"context canceled"), "aborted"),
    (re.compile(r"truncating input prompt"), "truncated"),
    (
        re.compile(
            r"starting (?:llama-server|go runner|runner)\b|runner started|\bunload"
        ),
        "evicted",
    ),
    (re.compile(r"loaded runners|template selection"), IGNORED),
)


def parse_options(argv):
    parser = argparse.ArgumentParser(
        description="Record why a claude-ollama session lost context"
    )
    parser.add_argument("--log")
    parser.add_argument("--model", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--watch-pid", type=int)
    parser.add_argument("--transcripts")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--interval", type=float, default=1.0)
    options = parser.parse_args(argv)
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


def first_group(match):
    return next((int(group) for group in match.groups() if group is not None), None)


class LogClassifier:
    def __init__(self, model):
        self.model = model
        self.context_size = None
        self.previous_total = None

    def note_counts(self, line):
        context = CONTEXT_SIZE.search(line)
        if context:
            self.context_size = int(context.group(1))
        total = REQUEST_TOTAL.search(line)
        if total:
            self.previous_total = first_group(total)

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
        return self.model in line or RUNNER_MENTION.search(line) is not None

    def classify(self, line):
        self.note_counts(line)
        for pattern, cause in CAUSE_RULES:
            if pattern.search(line):
                return (
                    None
                    if cause == IGNORED
                    else incident(line, cause, self.tokens_of(line, cause))
                )
        prompt_eval = PROMPT_EVAL.search(line)
        if prompt_eval:
            tokens = first_group(prompt_eval)
            return (
                incident(line, "reprefilled", tokens)
                if self.is_reprefill(tokens)
                else None
            )
        if self.mentions_session(line):
            return incident(line, "unknown", None)
        return None

    @staticmethod
    def tokens_of(line, cause):
        if cause != "truncated":
            return None
        match = TRUNCATED_PROMPT.search(line)
        return int(match.group(1)) if match else None


def incident(line, cause, tokens, timestamp=None):
    match = LOG_TIME.search(line)
    return {
        "ts": timestamp or (match.group(1) if match else now_iso()),
        "cause": cause,
        "detail": line[:DETAIL_LENGTH],
        "tokens": tokens,
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
        with self.open_private(
            self.path, os.O_WRONLY | os.O_CREAT | os.O_APPEND
        ) as handle:
            handle.write(line + "\n")
        with self.open_private(
            self.latest, os.O_WRONLY | os.O_CREAT | os.O_TRUNC
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
            self.emit(compaction(line))

    def emit(self, entry):
        if entry is not None:
            self.out.record(entry)

    def run(self):
        self.out.prepare()
        self.poll()
        if self.options.once:
            return
        while process_alive(self.options.watch_pid):
            time.sleep(self.options.interval)
            self.poll()


if __name__ == "__main__":
    Watcher(parse_options(sys.argv[1:])).run()
