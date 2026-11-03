#!/usr/bin/env python3
import argparse
import json
import os
import sys
import time
from pathlib import Path

DETAIL_LENGTH = 200
CAUSES_FILE = Path(__file__).resolve().parent / "causes.json"
CAUSES = tuple(json.loads(CAUSES_FILE.read_text()))
PRECEDED_CAUSE = "reprefilled"


def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def require_cause(cause):
    if cause not in CAUSES:
        raise ValueError(f"unknown incident cause {cause!r}; known: {', '.join(CAUSES)}")


def incident(ts, cause, detail, tokens=None, rule=None, preceded_by=None):
    require_cause(cause)
    entry = {"ts": ts, "cause": cause, "detail": detail[:DETAIL_LENGTH], "tokens": tokens, "rule": rule}
    if cause == PRECEDED_CAUSE:
        entry["preceded_by"] = preceded_by
    return entry


def incident_rows(lines):
    for line in lines:
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if isinstance(row, dict) and "kind" not in row:
            yield row


class IncidentLog:
    def __init__(self, path):
        self.path = Path(path)
        self.latest = Path(f"{path}.latest")

    def prepare(self):
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.path.parent.chmod(0o700)

    def record(self, entry):
        require_cause(entry.get("cause"))
        line = json.dumps(entry)
        self.append(line)
        with self.open_private(self.latest, os.O_WRONLY | os.O_CREAT | os.O_TRUNC) as handle:
            handle.write(line + "\n")

    def record_kind_row(self, entry):
        if "kind" not in entry:
            raise ValueError("a kind row needs a kind")
        self.append(json.dumps(entry))

    def append(self, line):
        with self.open_private(self.path, os.O_WRONLY | os.O_CREAT | os.O_APPEND) as handle:
            handle.write(line + "\n")

    @staticmethod
    def open_private(path, flags):
        return os.fdopen(os.open(path, flags, 0o600), "w")


def parse_options(argv):
    parser = argparse.ArgumentParser(description="Append one incident to a claude-ollama incidents file")
    commands = parser.add_subparsers(dest="command", required=True)
    append = commands.add_parser("append")
    append.add_argument("--file", required=True)
    append.add_argument("--cause", required=True, choices=CAUSES)
    append.add_argument("--detail", required=True)
    append.add_argument("--tokens", type=int)
    append.add_argument("--rule")
    return parser.parse_args(argv)


def main(argv):
    options = parse_options(argv)
    entry = incident(now_iso(), options.cause, options.detail, options.tokens, options.rule)
    IncidentLog(options.file).record(entry)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
