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
TOKEN_VARIABLES = ("SHORTCUT_API_TOKEN", "CLUBHOUSE_API_TOKEN")
TOKEN_REMOVED = "[Shortcut token removed]"
SWITCH = "switch"
VALUE = "value"


class Refused(Exception):
    pass


def flags(kind, *names):
    found = {}
    for name in names:
        short_name, _, long_name = name.rpartition(" ")
        found[long_name] = (long_name, kind)
        if short_name:
            found[short_name] = (long_name, kind)
    return found


FORMAT = flags(VALUE, "-f --format")
DETAILED = flags(SWITCH, "-d --detailed")
SEARCH_QUERY = flags(VALUE, "-s --search")
STORY_FIELDS = flags(
    VALUE,
    "-d --description",
    "--deadline",
    "-e --estimate",
    "--epic",
    "-i --iteration",
    "-l --label",
    "-o --owners",
    "-s --state",
    "-t --title",
    "-T --team",
    "-y --type",
)
SEARCH_OPTIONS = {
    **flags(SWITCH, "-a --archived", "-q --quiet"),
    **flags(
        VALUE,
        "-c --created",
        "-l --label",
        "-o --owner",
        "-p --project",
        "-s --state",
        "--epic",
        "-i --iteration",
        "-t --text",
        "-e --estimate",
        "-u --updated",
        "-y --type",
        "-r --sort",
    ),
    **FORMAT,
}
STORY_OPTIONS = {
    **STORY_FIELDS,
    **FORMAT,
    **flags(SWITCH, "-a --archived", "-I --idonly", "-q --quiet"),
    **flags(
        VALUE,
        "-c --comment",
        "--follower",
        "--move-after",
        "--move-before",
        "--move-down",
        "--move-up",
        "--external-link",
        "--requester",
        "--task",
        "--task-complete",
    ),
}
COMMANDS = {
    ("search",): SEARCH_OPTIONS,
    ("find",): SEARCH_OPTIONS,
    ("story",): STORY_OPTIONS,
    ("create",): {**STORY_FIELDS, **flags(VALUE, "-p --project"), **flags(SWITCH, "-I --idonly")},
    ("members",): {**SEARCH_QUERY, **flags(SWITCH, "-d --disabled")},
    ("workflows",): SEARCH_QUERY,
    ("epics",): {
        **flags(SWITCH, "-a --archived", "-c --completed", "-d --detailed", "-s --started"),
        **flags(VALUE, "-M --milestone", "--objectives", "-t --title"),
        **FORMAT,
    },
    ("epic", "view"): {},
    ("epic", "stories"): {**DETAILED, **FORMAT},
    ("iterations",): {
        **flags(VALUE, "-S --status", "-T --team", "-t --title"),
        **flags(SWITCH, "-C --current"),
        **DETAILED,
        **FORMAT,
    },
    ("iteration", "view"): {},
    ("iteration", "stories"): FORMAT,
    ("labels",): {**flags(SWITCH, "-a --archived"), **SEARCH_QUERY},
    ("label", "stories"): {**DETAILED, **FORMAT},
    ("label", "epics"): {},
    ("teams",): {**flags(SWITCH, "-a --archived"), **SEARCH_QUERY},
    ("team", "view"): {},
    ("team", "stories"): {**DETAILED, **FORMAT},
    ("docs",): {
        **flags(SWITCH, "-a --archived", "-m --mine", "-f --following", "-q --quiet", "-I --idonly"),
        **flags(VALUE, "-t --title"),
    },
    ("doc", "view"): flags(SWITCH, "--html", "-q --quiet"),
}


def command_of(argv):
    for length in (2, 1):
        if tuple(argv[:length]) in COMMANDS:
            return argv[:length]
    raise Refused(f"{' '.join(argv[:2]) or 'no command'} is not a short command this session can use")


def rebuilt(words, options):
    built = []
    remaining = iter(words)
    for word in remaining:
        if not word.startswith("-"):
            built.append(word)
            continue
        flag, equals, value = word.partition("=")
        if flag not in options:
            raise Refused(f"{flag} is not allowed here")
        long_name, kind = options[flag]
        if kind == SWITCH:
            built.append(long_name)
            continue
        if not equals:
            value = next(remaining, None)
            if value is None:
                raise Refused(f"{flag} needs a value")
        built.append(f"{long_name}={value}")
    return built


def short_args(request):
    argv = request.get("argv") if isinstance(request, dict) else None
    if not isinstance(argv, list) or not all(isinstance(word, str) for word in argv):
        raise Refused("argv must be a list of text")
    command = command_of(argv)
    return [*command, *rebuilt(argv[len(command) :], COMMANDS[tuple(command)])]


def shortcut_config_files():
    home = Path.home()
    folders = [
        Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config") / "shortcut-cli",
        home / ".config" / "shortcut-cli",
        home / ".config" / "clubhouse-cli",
        home / ".clubhouse-cli",
    ]
    if os.environ.get("XDG_DATA_HOME"):
        folders.append(Path(os.environ["XDG_DATA_HOME"]) / ".config" / "shortcut-cli")
    return [folder / "config.json" for folder in folders]


def configured_token(config_file):
    try:
        token = json.loads(config_file.read_text()).get("token")
    except (OSError, ValueError, AttributeError):
        return ""
    return token if isinstance(token, str) else ""


def known_tokens():
    tokens = [os.environ.get(name, "") for name in TOKEN_VARIABLES]
    tokens += [configured_token(config_file) for config_file in shortcut_config_files()]
    return sorted({token for token in tokens if token}, key=len, reverse=True)


def without_tokens(text, tokens):
    for token in tokens:
        text = text.replace(token, TOKEN_REMOVED)
    return text


class Broker:
    def __init__(self, short, workdir):
        self.short = short
        self.workdir = workdir

    def handle(self, request):
        return reply_from(
            subprocess.run(
                [self.short, *short_args(request)],
                capture_output=True,
                text=True,
                cwd=self.workdir,
                stdin=subprocess.DEVNULL,
                timeout=COMMAND_TIMEOUT_SECONDS,
                check=False,
            )
        )


def reply_from(completed):
    tokens = known_tokens()
    return {
        "exit": completed.returncode,
        "stdout": without_tokens(completed.stdout, tokens),
        "stderr": without_tokens(completed.stderr, tokens),
    }


def refusal(reason):
    return {"exit": 1, "stdout": "", "stderr": f"short broker: {reason}\n"}


def answer(broker, line):
    try:
        return broker.handle(json.loads(line))
    except Refused as reason:
        return refusal(str(reason))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return refusal("malformed request")
    except subprocess.TimeoutExpired:
        return refusal("short timed out")
    except OSError as problem:
        return refusal(f"short could not run: {problem.strerror}")


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
    parser.add_argument("--short", required=True)
    parser.add_argument("--watch-pid", type=int, required=True)
    options = parser.parse_args()
    with tempfile.TemporaryDirectory() as workdir:
        server = serve(Broker(options.short, workdir), options.socket)
        threading.Thread(target=exit_when_gone, args=(options.watch_pid, options.socket), daemon=True).start()
        server.serve_forever()


if __name__ == "__main__":
    main()
