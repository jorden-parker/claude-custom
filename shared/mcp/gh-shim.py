#!/usr/bin/env python3
import re
import subprocess
import sys

from gh_broker_client import BrokerMissing, ask_broker

PREFIX = "gh (claude-ollama): "
SUPPORTED = (
    "read-only; supported: pr list|view|diff|checks, issue list|view, run list|view, "
    "api repos/{owner}/{repo}/pulls/N/comments"
)
BROKER_MISSING = "the GitHub broker is not running; run gh auth login outside the session, then relaunch"
ITEM_URL = re.compile(r"https://github\.com/([^/]+/[^/]+)/(?:pull|issues)/(\d+)/?")
REVIEW_COMMENTS_PATH = re.compile(r"/?repos/(\{owner\}/\{repo\}|[^/]+/[^/]+)/pulls/(\d+)/comments")

SWITCH = "switch"
NUMBER = "number"
TEXT = "text"
JQ = "jq"
IGNORED = "ignored"


class Unsupported(Exception):
    pass


def option(name, kind, *flags):
    return {flag: (name, kind) for flag in flags}


STATE = option("state", TEXT, "--state", "-s")
LIMIT = option("limit", NUMBER, "--limit", "-L")
SEARCH = option("search", TEXT, "--search", "-S")
FIELDS = {**option("fields", TEXT, "--json"), **option("", JQ, "--jq", "-q")}
COMMENTS = option("", IGNORED, "--comments", "-c")

COMMANDS = {
    ("pr", "list"): ("pr_list", None, {**STATE, **LIMIT, **SEARCH, **option("author", TEXT, "--author", "-A")}),
    ("pr", "view"): ("pr_view", NUMBER, {**FIELDS, **COMMENTS}),
    ("pr", "diff"): ("pr_diff", "pull_request", option("name_only", SWITCH, "--name-only")),
    ("pr", "checks"): ("pr_checks", NUMBER, FIELDS),
    ("issue", "list"): ("issue_list", None, {**STATE, **LIMIT, **SEARCH}),
    ("issue", "view"): ("issue_view", NUMBER, {**FIELDS, **COMMENTS}),
    ("run", "list"): ("run_list", None, {**LIMIT, **option("branch", TEXT, "--branch", "-b")}),
    ("run", "view"): ("run_view", "run_id", {**FIELDS, **option("failed_logs", SWITCH, "--log-failed")}),
}
API_OPTIONS = {**option("", IGNORED, "--paginate"), **option("", JQ, "--jq", "-q")}


def split_flag(word):
    flag, equals, value = word.partition("=")
    return (flag, value) if equals and flag.startswith("-") else (word, None)


def whole_number(text):
    if not text.isdigit():
        raise Unsupported(f"expected a number, got {text}")
    return int(text)


class Request:
    def __init__(self):
        self.arguments = {}
        self.jq = None

    def take_repo(self, words):
        rest = []
        remaining = iter(words)
        for word in remaining:
            flag, value = split_flag(word)
            if flag in ("-R", "--repo"):
                self.arguments["repo"] = value if value is not None else next(remaining, "")
            else:
                rest.append(word)
        return rest

    def take_options(self, words, options):
        positional = []
        remaining = iter(words)
        for word in remaining:
            flag, value = split_flag(word)
            if not flag.startswith("-"):
                positional.append(word)
                continue
            if flag not in options:
                raise Unsupported(f"{flag} is not supported")
            name, kind = options[flag]
            if kind in (SWITCH, IGNORED):
                if kind == SWITCH:
                    self.arguments[name] = True
                continue
            value = value if value is not None else next(remaining, None)
            if value is None:
                raise Unsupported(f"{flag} needs a value")
            if kind == JQ:
                self.jq = value
            else:
                self.arguments[name] = whole_number(value) if kind == NUMBER else value
        return positional

    def take_target(self, kind, positional):
        if kind is None:
            if positional:
                raise Unsupported(f"unexpected {positional[0]}")
            return
        if len(positional) != 1:
            raise Unsupported("name one PR, issue or run")
        target = positional[0]
        url = ITEM_URL.fullmatch(target)
        if url:
            self.arguments["repo"], target = url.group(1), url.group(2)
        if kind == "run_id":
            self.arguments["run_id"] = whole_number(target)
        elif kind == "pull_request" and not target.isdigit():
            self.arguments["branch"] = target
        else:
            self.arguments["number"] = whole_number(target)


def parse(words):
    request = Request()
    words = request.take_repo(words)
    if words[:1] == ["api"]:
        return "pr_review_comments", parse_api(request, words[1:])
    tool, target, options = COMMANDS.get(tuple(words[:2]), (None, None, None))
    if tool is None:
        raise Unsupported(" ".join(words[:2]) or "no command")
    request.take_target(target, request.take_options(words[2:], options))
    return tool, request


def parse_api(request, words):
    positional = request.take_options(words, API_OPTIONS)
    path = REVIEW_COMMENTS_PATH.fullmatch(positional[0]) if len(positional) == 1 else None
    if path is None:
        raise Unsupported("api only reads repos/{owner}/{repo}/pulls/N/comments")
    if path.group(1) != "{owner}/{repo}":
        request.arguments["repo"] = path.group(1)
    request.arguments["number"] = int(path.group(2))
    return request


def filtered(stdout, jq):
    completed = subprocess.run(["jq", "-r", jq], input=stdout, capture_output=True, text=True, check=False)
    sys.stderr.write(completed.stderr)
    return completed.stdout, completed.returncode


def main():
    try:
        tool, request = parse(sys.argv[1:])
    except Unsupported as reason:
        sys.stderr.write(f"{PREFIX}{SUPPORTED}\n{PREFIX}{reason}\n")
        return 1
    try:
        reply = ask_broker(tool, request.arguments)
    except BrokerMissing:
        sys.stderr.write(f"{PREFIX}{BROKER_MISSING}\n")
        return 1
    stdout, status = reply.get("stdout", ""), reply.get("exit", 1)
    sys.stderr.write(reply.get("stderr", ""))
    if request.jq is not None and status == 0:
        stdout, status = filtered(stdout, request.jq)
    sys.stdout.write(stdout)
    return status


if __name__ == "__main__":
    sys.exit(main())
