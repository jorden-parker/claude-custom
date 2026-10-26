#!/usr/bin/env python3
import argparse
import json
import os
import socketserver
import subprocess
import tempfile
import threading
import time
from pathlib import Path

COMMAND_TIMEOUT_SECONDS = 120
DEFAULT_LIMIT = 20
MAX_LIMIT = 100
MAX_TEXT_LENGTH = 256
PR_FIELDS = "number,title,author,headRefName,isDraft,updatedAt"
PR_VIEW_FIELDS = (
    "number,title,body,state,author,headRefName,baseRefName,url,isDraft,reviewDecision,labels,files,comments,reviews"
)
PR_CHECK_FIELDS = "name,state,bucket,workflow,link"
ISSUE_FIELDS = "number,title,state,author,labels,updatedAt"
ISSUE_VIEW_FIELDS = "number,title,body,state,author,labels,url,comments"
RUN_FIELDS = "databaseId,displayTitle,workflowName,headBranch,status,conclusion,createdAt"
RUN_VIEW_FIELDS = "databaseId,displayTitle,workflowName,headBranch,status,conclusion,url,jobs"


class Refused(Exception):
    pass


class Arguments:
    def __init__(self, values, allowed):
        if not isinstance(values, dict):
            raise Refused("arguments must be an object")
        unknown = set(values) - set(allowed)
        if unknown:
            raise Refused(f"unknown arguments: {', '.join(sorted(unknown))}")
        self.values = values

    def number(self, name, default=None, maximum=None):
        value = self.values.get(name, default)
        if value is None:
            raise Refused(f"{name} is required")
        if isinstance(value, bool) or not isinstance(value, int) or value < 1:
            raise Refused(f"{name} must be a positive whole number")
        if maximum is not None and value > maximum:
            raise Refused(f"{name} must be at most {maximum}")
        return str(value)

    def limit(self):
        return self.number("limit", DEFAULT_LIMIT, MAX_LIMIT)

    def choice(self, name, options):
        value = self.values.get(name, options[0])
        if value not in options:
            raise Refused(f"{name} must be one of {', '.join(options)}")
        return value

    def switch(self, name):
        value = self.values.get(name, False)
        if not isinstance(value, bool):
            raise Refused(f"{name} must be true or false")
        return value

    def text_flag(self, name, flag):
        value = self.values.get(name)
        if value is None:
            return []
        if not isinstance(value, str) or len(value) > MAX_TEXT_LENGTH:
            raise Refused(f"{name} must be text of at most {MAX_TEXT_LENGTH} characters")
        return [f"{flag}={value}"]


def pr_list(values):
    args = Arguments(values, {"state", "limit", "author", "search"})
    state = args.choice("state", ("open", "closed", "merged", "all"))
    return [
        *["pr", "list", "--state", state, "--limit", args.limit(), "--json", PR_FIELDS],
        *args.text_flag("author", "--author"),
        *args.text_flag("search", "--search"),
    ]


def pr_view(values):
    return ["pr", "view", Arguments(values, {"number"}).number("number"), "--json", PR_VIEW_FIELDS]


def pr_diff(values):
    args = Arguments(values, {"number", "name_only"})
    return ["pr", "diff", args.number("number"), *(["--name-only"] if args.switch("name_only") else [])]


def pr_checks(values):
    return ["pr", "checks", Arguments(values, {"number"}).number("number"), "--json", PR_CHECK_FIELDS]


def issue_list(values):
    args = Arguments(values, {"state", "limit", "search"})
    state = args.choice("state", ("open", "closed", "all"))
    return [
        *["issue", "list", "--state", state, "--limit", args.limit(), "--json", ISSUE_FIELDS],
        *args.text_flag("search", "--search"),
    ]


def issue_view(values):
    return ["issue", "view", Arguments(values, {"number"}).number("number"), "--json", ISSUE_VIEW_FIELDS]


def run_list(values):
    args = Arguments(values, {"limit", "branch"})
    return ["run", "list", "--limit", args.limit(), "--json", RUN_FIELDS, *args.text_flag("branch", "--branch")]


def run_view(values):
    args = Arguments(values, {"run_id", "failed_logs"})
    run_id = args.number("run_id")
    if args.switch("failed_logs"):
        return ["run", "view", run_id, "--log-failed"]
    return ["run", "view", run_id, "--json", RUN_VIEW_FIELDS]


TOOLS = {
    "pr_list": pr_list,
    "pr_view": pr_view,
    "pr_diff": pr_diff,
    "pr_checks": pr_checks,
    "issue_list": issue_list,
    "issue_view": issue_view,
    "run_list": run_list,
    "run_view": run_view,
}


def gh_args(request):
    if not isinstance(request, dict):
        raise Refused("malformed request")
    build = TOOLS.get(request.get("tool"))
    if build is None:
        raise Refused(f"{request.get('tool')} is not a GitHub tool this session can use")
    return build(request.get("arguments", {}))


class Broker:
    def __init__(self, gh, repo, workdir):
        self.gh = gh
        self.workdir = workdir
        config_dir = Path(workdir, "gh-config")
        config_dir.mkdir()
        self.env = {
            **os.environ,
            "GH_HOST": "github.com",
            "GH_CONFIG_DIR": str(config_dir),
            "GH_PROMPT_DISABLED": "1",
            "GH_PAGER": "cat",
            "GH_NO_UPDATE_NOTIFIER": "1",
        }
        self.env.pop("GITHUB_TOKEN", None)
        if repo:
            self.env["GH_REPO"] = repo

    def handle(self, request):
        return reply_from(
            subprocess.run(
                [self.gh, *gh_args(request)],
                capture_output=True,
                text=True,
                cwd=self.workdir,
                env=self.env,
                stdin=subprocess.DEVNULL,
                timeout=COMMAND_TIMEOUT_SECONDS,
            )
        )


def reply_from(completed):
    return {"exit": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr}


def refusal(reason):
    return {"exit": 1, "stdout": "", "stderr": f"gh broker: {reason}\n"}


def answer(broker, line):
    try:
        return broker.handle(json.loads(line))
    except Refused as reason:
        return refusal(str(reason))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return refusal("malformed request")
    except subprocess.TimeoutExpired:
        return refusal("gh timed out")


def serve(broker, socket_path):
    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            reply = answer(broker, self.rfile.readline())
            self.wfile.write(json.dumps(reply).encode() + b"\n")

    Path(socket_path).unlink(missing_ok=True)
    os.umask(0o077)
    return socketserver.ThreadingUnixStreamServer(socket_path, Handler)


def process_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def exit_when_gone(pid, socket_path):
    while process_alive(pid):
        time.sleep(0.5)
    Path(socket_path).unlink(missing_ok=True)
    os._exit(0)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", required=True)
    parser.add_argument("--gh", required=True)
    parser.add_argument("--repo", default="")
    parser.add_argument("--watch-pid", type=int, required=True)
    options = parser.parse_args()
    with tempfile.TemporaryDirectory() as workdir:
        server = serve(Broker(options.gh, options.repo, workdir), options.socket)
        threading.Thread(
            target=exit_when_gone, args=(options.watch_pid, options.socket), daemon=True
        ).start()
        server.serve_forever()


if __name__ == "__main__":
    main()
