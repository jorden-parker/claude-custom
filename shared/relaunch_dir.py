#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

ENV_VAR = "CLAUDE_OLLAMA_RELAUNCH_DIR"
DEFAULT_ROOT = Path.home() / ".claude-ollama" / "relaunch"
CLAUDE_PID_FILE = "claude.pid"
CLAUDE_PROCESS_NAMES = ("node", "claude")
REQUESTS = {
    "relaunch": {"note": (str,), "prompt": (str,), "percent": (int, type(None))},
    "ladder": {"rung": (str,), "context": (int,), "reason": (str,)},
    "ladder-up": {"rung": (str,), "reason": (str,)},
}
FLAGS = ("embed-off", "heartbeat-fast")
EXIT_ABSENT = 1
EXIT_USAGE = 2
EXIT_NO_FOLDER = 3


class SignalFileError(ValueError):
    pass


class MissingFolderError(OSError):
    pass


def schema_problem(name, fields):
    schema = REQUESTS.get(name)
    if schema is None:
        return f"{name} is not a request (requests: {', '.join(REQUESTS)})"
    if not isinstance(fields, dict):
        return f"{name} must be a JSON object"
    missing = [key for key in schema if key not in fields]
    unknown = [key for key in fields if key not in schema]
    if missing or unknown:
        return f"{name}: missing {missing or 'nothing'}, unknown {unknown or 'nothing'}"
    for key, kinds in schema.items():
        value = fields[key]
        if isinstance(value, bool) or not isinstance(value, kinds):
            return f"{name}: {key} has the wrong type"
    return None


def ordered(name, fields):
    return {key: fields[key] for key in REQUESTS[name]}


def is_claude_process(pid):
    try:
        comm = subprocess.run(["ps", "-o", "comm=", "-p", str(pid)], capture_output=True, text=True, check=False).stdout.strip()
    except OSError:
        return False
    return any(name in Path(comm).name for name in CLAUDE_PROCESS_NAMES)


def process_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def write_private(path, text):
    handle, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(handle, "w") as stream:
            stream.write(text)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise


class RelaunchDir:
    def __init__(self, path):
        self.path = Path(path)

    def __repr__(self):
        return f"RelaunchDir({str(self.path)!r})"

    @classmethod
    def from_env(cls):
        value = os.environ.get(ENV_VAR)
        return cls(value) if value else None

    @classmethod
    def for_pid(cls, pid, root=None):
        return cls(Path(root or DEFAULT_ROOT) / str(pid))

    def path_of(self, name):
        return self.path / name

    def request(self, name, fields):
        problem = schema_problem(name, fields)
        if problem:
            raise SignalFileError(problem)
        if not self.path.is_dir():
            raise MissingFolderError(f"no relaunch dir at {self.path}")
        write_private(self.path_of(name), json.dumps(ordered(name, fields)))

    def take(self, name):
        if name not in REQUESTS:
            raise SignalFileError(f"{name} is not a request")
        target = self.path_of(name)
        try:
            text = target.read_text()
        except FileNotFoundError:
            return None
        target.unlink(missing_ok=True)
        try:
            fields = json.loads(text)
        except ValueError:
            fields = None
        problem = schema_problem(name, fields)
        if problem:
            print(f"relaunch dir: dropped malformed {name}: {problem}", file=sys.stderr)
            return None
        return ordered(name, fields)

    def has(self, name):
        return self.path_of(name).exists()

    def raise_flag(self, name):
        self.require_flag(name)
        self.path_of(name).touch()

    def lower_flag(self, name):
        self.require_flag(name)
        self.path_of(name).unlink(missing_ok=True)

    def require_flag(self, name):
        if name not in FLAGS:
            raise SignalFileError(f"{name} is not a flag (flags: {', '.join(FLAGS)})")

    def record_claude_pid(self, pid):
        write_private(self.path_of(CLAUDE_PID_FILE), f"{int(pid)}\n")

    def terminate_claude(self):
        try:
            pid = int(self.path_of(CLAUDE_PID_FILE).read_text().strip())
        except (OSError, ValueError):
            return
        if pid <= 0 or not is_claude_process(pid):
            return
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            return


def remove_stale_siblings(root, own_pid):
    for sibling in root.iterdir():
        if not sibling.is_dir() or not sibling.name.isdigit() or sibling.name == str(own_pid):
            continue
        if not process_alive(int(sibling.name)):
            shutil.rmtree(sibling, ignore_errors=True)


def prepare(pid, root=None):
    root = Path(root or DEFAULT_ROOT)
    folder = RelaunchDir.for_pid(pid, root)
    folder.path.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(root, 0o700)
    os.chmod(folder.path, 0o700)
    for name in (*REQUESTS, *FLAGS):
        folder.path_of(name).unlink(missing_ok=True)
    remove_stale_siblings(root, pid)
    return folder


def parse_arguments(argv):
    folder_options = argparse.ArgumentParser(add_help=False)
    folder_options.add_argument("--dir", default=argparse.SUPPRESS)
    folder_options.add_argument("--root", default=argparse.SUPPRESS)
    folder_options.add_argument("--pid", type=int, default=argparse.SUPPRESS)
    parser = argparse.ArgumentParser(prog="relaunch_dir.py", parents=[folder_options])
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("prepare", parents=[folder_options])
    request = commands.add_parser("request", parents=[folder_options])
    request.add_argument("name")
    request.add_argument("fields")
    for command in ("take", "has", "raise", "lower", "path"):
        commands.add_parser(command, parents=[folder_options]).add_argument("name")
    commands.add_parser("claude-pid", parents=[folder_options]).add_argument("claude_pid", type=int)
    options = parser.parse_args(argv)
    for name in ("dir", "root", "pid"):
        setattr(options, name, getattr(options, name, None))
    return options


def chosen_folder(options):
    if options.dir:
        return RelaunchDir(options.dir)
    if options.pid is not None:
        return RelaunchDir.for_pid(options.pid, options.root)
    folder = RelaunchDir.from_env()
    if folder is None:
        raise SignalFileError(f"name the folder with --dir, --pid or {ENV_VAR}")
    return folder


def run_command(options):
    if options.command == "prepare":
        if options.pid is None:
            raise SignalFileError("prepare needs --pid")
        print(prepare(options.pid, options.root).path)
        return 0
    folder = chosen_folder(options)
    if options.command == "request":
        try:
            fields = json.loads(options.fields)
        except ValueError as error:
            raise SignalFileError(f"{options.name}: fields are not JSON ({error})") from error
        folder.request(options.name, fields)
        return 0
    if options.command == "take":
        fields = folder.take(options.name)
        if fields is None:
            return EXIT_ABSENT
        print(json.dumps(fields))
        return 0
    if options.command == "has":
        return 0 if folder.has(options.name) else EXIT_ABSENT
    if options.command == "raise":
        folder.raise_flag(options.name)
        return 0
    if options.command == "lower":
        folder.lower_flag(options.name)
        return 0
    if options.command == "path":
        print(folder.path_of(options.name))
        return 0
    folder.record_claude_pid(options.claude_pid)
    return 0


def main(argv):
    options = parse_arguments(argv)
    try:
        return run_command(options)
    except SignalFileError as error:
        print(f"relaunch dir: {error}", file=sys.stderr)
        return EXIT_USAGE
    except MissingFolderError as error:
        print(f"relaunch dir: {error}", file=sys.stderr)
        return EXIT_NO_FOLDER


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
