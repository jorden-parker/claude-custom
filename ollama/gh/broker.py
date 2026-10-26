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
REPO_FLAGS = {"--repo", "-R"}
API_SHORT_FLAGS = {"-q": "--jq", "-t": "--template", "-H": "--header", "-X": "--method", "-i": "--include"}
API_SWITCHES = {"--paginate", "--slurp", "--include", "--silent", "--verbose"}
API_VALUE_FLAGS = {"--jq", "--template", "--cache", "--header", "--method"}


class Refused(Exception):
    pass


def joins_short_flags(arg):
    return arg.startswith("-") and not arg.startswith("--") and len(arg) > 2


def require_separate_short_flags(args):
    for arg in args:
        if joins_short_flags(arg):
            raise Refused(f"{arg} is not allowed: give each short flag on its own")


def require_no_browser(args):
    for arg in args:
        if arg.partition("=")[0] in BROWSER_FLAGS:
            raise Refused(f"{arg} would open a browser outside the sandbox")


def names_a_host(arg):
    return "://" in arg or arg.startswith("//")


def following(args, at):
    return args[at + 1] if at + 1 < len(args) else ""


def repo_values(args):
    values = []
    for at, arg in enumerate(args):
        name, joined, value = arg.partition("=")
        if name in REPO_FLAGS:
            values.append(value if joined else following(args, at))
    if args[:2] == ["repo", "view"]:
        values += [arg for arg in args[2:] if not arg.startswith("-")]
    return values


def require_github_only(args):
    for arg in args:
        if names_a_host(arg):
            raise Refused(f"{arg} is not allowed: gh may only reach github.com")
    for repo in repo_values(args):
        if repo.count("/") > 1:
            raise Refused(f"{repo} is not allowed: name a repo as OWNER/NAME on github.com")


def require_read_only_api_value(flag, value):
    if flag == "--method" and value.upper() != "GET":
        raise Refused(f"api --method {value} is not allowed: only GET")
    if flag == "--header" and not value.lower().startswith("accept:"):
        raise Refused("api headers other than Accept are not allowed")


def require_read_only_api(args):
    at = 0
    while at < len(args):
        arg = args[at]
        if arg == "graphql":
            raise Refused("api graphql is not allowed: only REST paths on github.com")
        if arg.startswith("-"):
            name, joined, value = arg.partition("=")
            flag = API_SHORT_FLAGS.get(name, name)
            if flag in API_VALUE_FLAGS:
                if not joined:
                    value = following(args, at)
                    at += 1
                require_read_only_api_value(flag, value)
            elif flag not in API_SWITCHES:
                raise Refused(f"api {arg} is not allowed: the session may only read")
        at += 1


def require_read_command(args):
    if not args:
        raise Refused("a gh command is required")
    require_separate_short_flags(args)
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
