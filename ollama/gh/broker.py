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
READ_COMMANDS = {
    "pr": {"list", "view", "diff", "checks", "status"},
    "issue": {"list", "view", "status"},
    "run": {"list", "view"},
    "workflow": {"list", "view"},
    "repo": {"view"},
    "release": {"list", "view"},
    "search": {"issues", "prs", "repos", "commits", "code"},
}
BROWSER_FLAGS = {"--web", "-w"}
REFUSED_API_FLAGS = {"--raw-field", "--field", "--input", "--hostname"}
SHORT_FIELD_FLAGS = {"-f", "-F"}


class Refused(Exception):
    pass


def flag_name(arg):
    return arg.split("=", 1)[0]


def require_no_browser(args):
    for arg in args:
        if flag_name(arg) in BROWSER_FLAGS:
            raise Refused(f"{arg} would open a browser outside the sandbox")


def names_a_host(arg):
    return "://" in arg or arg.startswith("//")


def repo_values(args):
    values = [flag_value(args, at, "--repo", "-R") for at in range(len(args))]
    if args[:2] == ["repo", "view"] and len(args) > 2 and not args[2].startswith("-"):
        values.append(args[2])
    return [value for value in values if value is not None]


def require_github_only(args):
    for arg in args:
        if names_a_host(arg):
            raise Refused(f"{arg} is not allowed: gh may only reach github.com")
    for repo in repo_values(args):
        if repo.count("/") > 1:
            raise Refused(f"{repo} is not allowed: name a repo as OWNER/NAME on github.com")


def flag_value(args, at, long_flag, short_flag):
    arg = args[at]
    if arg in (long_flag, short_flag):
        return args[at + 1] if at + 1 < len(args) else ""
    if arg.startswith(f"{long_flag}="):
        return arg.split("=", 1)[1]
    if arg.startswith(short_flag):
        return arg[len(short_flag) :].removeprefix("=")
    return None


def refused_api_flag(arg):
    return flag_name(arg) in REFUSED_API_FLAGS or arg[:2] in SHORT_FIELD_FLAGS


def require_read_only_api(args):
    for at, arg in enumerate(args):
        if refused_api_flag(arg):
            raise Refused(f"api {arg} is not allowed: the session may only read")
        method = flag_value(args, at, "--method", "-X")
        if method is not None and method.upper() != "GET":
            raise Refused(f"api {method or 'without a method'} is not allowed: only GET")
        header = flag_value(args, at, "--header", "-H")
        if header is not None and not header.lower().startswith("accept:"):
            raise Refused("api headers other than Accept are not allowed")
        if arg == "graphql":
            raise Refused("api graphql is not allowed: only REST paths on github.com")


def require_read_command(args):
    if not args:
        raise Refused("a gh command is required")
    require_no_browser(args)
    require_github_only(args)
    if args[0] == "api":
        require_read_only_api(args[1:])
        return
    allowed = READ_COMMANDS.get(args[0], set())
    if len(args) < 2 or args[1] not in allowed:
        raise Refused(f"gh {' '.join(args[:2])} is not allowed: only read commands reach GitHub")


class Broker:
    def __init__(self, gh, repo, workdir):
        self.gh = gh
        self.workdir = workdir
        self.env = {**os.environ, "GH_PROMPT_DISABLED": "1", "GH_PAGER": "cat", "GH_NO_UPDATE_NOTIFIER": "1"}
        self.env.pop("GITHUB_TOKEN", None)
        if repo:
            self.env["GH_REPO"] = repo

    def handle(self, args):
        require_read_command(args)
        return reply_from(
            subprocess.run(
                [self.gh, *args],
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
        request = json.loads(line)
        return broker.handle([str(arg) for arg in request.get("args", [])])
    except Refused as reason:
        return refusal(str(reason))
    except (json.JSONDecodeError, AttributeError, TypeError):
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
