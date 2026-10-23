#!/usr/bin/env python3
import argparse
import base64
import json
import os
import socketserver
import subprocess
import tempfile
import threading
import time
from pathlib import Path
from urllib.parse import urlsplit

PROFILE = "claude-ollama"
COMMAND_TIMEOUT_SECONDS = 120
OPEN_VERBS = {"open", "open-split", "new"}
NAVIGATE_VERBS = {"goto", "navigate"}
SURFACE_VERBS = NAVIGATE_VERBS | {
    "back",
    "forward",
    "reload",
    "url",
    "get-url",
    "snapshot",
    "eval",
    "wait",
    "click",
    "dblclick",
    "hover",
    "focus",
    "check",
    "uncheck",
    "scroll-into-view",
    "type",
    "fill",
    "press",
    "key",
    "keydown",
    "keyup",
    "select",
    "scroll",
    "screenshot",
    "get",
    "is",
    "find",
    "frame",
    "dialog",
    "console",
    "errors",
    "highlight",
    "viewport",
}
TARGETING_FLAGS = {"--surface", "--workspace", "--window", "--profile", "--out", "--path", "--file"}
LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1"}


class Refused(Exception):
    pass


def has_ambiguous_characters(url):
    return any(char in "\\@" or char.isspace() or not char.isprintable() for char in url)


def loopback_host(parts):
    host = (parts.hostname or "").rstrip(".")
    return host if host in LOOPBACK_HOSTS else None


def canonical_url(parts, host, port):
    netloc = f"[{host}]" if ":" in host else host
    if port:
        netloc += f":{port}"
    query = f"?{parts.query}" if parts.query else ""
    fragment = f"#{parts.fragment}" if parts.fragment else ""
    return f"{parts.scheme.lower()}://{netloc}{parts.path or '/'}{query}{fragment}"


def require_loopback_url(url):
    refusal = Refused(f"only http(s) URLs on localhost are allowed, not {url}")
    if has_ambiguous_characters(url):
        raise refusal
    try:
        parts = urlsplit(url)
        host = loopback_host(parts)
        port = parts.port
    except ValueError:
        raise refusal from None
    if parts.scheme.lower() not in ("http", "https") or host is None:
        raise refusal
    return canonical_url(parts, host, port)


def require_no_targeting_flags(args):
    for arg in args:
        if arg.split("=", 1)[0] in TARGETING_FLAGS:
            raise Refused(f"{arg} is not allowed from this session")


def split_global_flags(args):
    if args[:1] == ["--json"]:
        return ["--json"], args[1:]
    return [], args


def split_surface(args):
    if args[:1] == ["--surface"]:
        return args[1:2], args[2:]
    return args[:1], args[1:]


def with_canonical_url(args):
    for at, arg in enumerate(args):
        if not arg.startswith("-"):
            return [*args[:at], require_loopback_url(arg), *args[at + 1 :]]
    raise Refused("navigation needs a URL")


def parse_open_args(args):
    urls = []
    focus = "false"
    remaining = list(args)
    while remaining:
        arg = remaining.pop(0)
        if arg == "--focus" and remaining[:1] in (["true"], ["false"]):
            focus = remaining.pop(0)
        elif arg.startswith("-"):
            raise Refused(f"{arg} is not allowed on open")
        else:
            urls.append(arg)
    if len(urls) > 1:
        raise Refused("open takes at most one URL")
    return [require_loopback_url(url) for url in urls], focus


class Broker:
    def __init__(self, cmux):
        self.cmux = cmux
        self.surface_ids = {}

    def run_cmux(self, args):
        return subprocess.run(
            [self.cmux, *args], capture_output=True, text=True, timeout=COMMAND_TIMEOUT_SECONDS
        )

    def ensure_profile(self):
        listing = self.run_cmux(["browser", "profiles", "list"]).stdout
        names = {line.split("\t", 1)[0] for line in listing.splitlines()}
        if PROFILE not in names:
            self.run_cmux(["browser", "profiles", "add", PROFILE])

    def handle(self, args, wants_file):
        global_flags, command = split_global_flags(args)
        if command[:1] != ["browser"]:
            raise Refused("only `cmux browser` commands reach cmux from this session")
        browser_args = command[1:]
        if browser_args[:1] and browser_args[0] in OPEN_VERBS:
            return self.open(browser_args[0], browser_args[1:])
        return self.run_on_surface(global_flags, browser_args, wants_file)

    def open(self, verb, args):
        urls, focus = parse_open_args(args)
        completed = self.run_cmux(
            [
                "--json",
                "--id-format",
                "both",
                "browser",
                verb,
                *urls,
                "--profile",
                PROFILE,
                "--focus",
                focus,
            ]
        )
        self.remember_surface(completed.stdout)
        return reply_from(completed)

    def remember_surface(self, stdout):
        try:
            opened = json.loads(stdout)
        except json.JSONDecodeError:
            return
        surface_id = opened.get("surface_id")
        if not surface_id:
            return
        self.surface_ids[surface_id] = surface_id
        if opened.get("surface_ref"):
            self.surface_ids[opened["surface_ref"]] = surface_id

    def run_on_surface(self, global_flags, args, wants_file):
        surface, rest = split_surface(args)
        surface_id = self.surface_ids.get(surface[0]) if surface else None
        if not surface_id:
            raise Refused("only browser surfaces this session opened can be used")
        verb, verb_args = (rest[0], rest[1:]) if rest else (None, [])
        if verb not in SURFACE_VERBS:
            raise Refused(f"browser {verb} is not allowed from this session")
        require_no_targeting_flags(verb_args)
        if verb in NAVIGATE_VERBS:
            verb_args = with_canonical_url(verb_args)
        command = [*global_flags, "browser", "--surface", surface_id, verb, *verb_args]
        if verb == "screenshot":
            return self.screenshot(command, wants_file)
        return reply_from(self.run_cmux(command))

    def screenshot(self, command, wants_file):
        if not wants_file:
            raise Refused("screenshot needs --out PATH")
        with tempfile.TemporaryDirectory() as folder:
            image = Path(folder) / "screenshot.png"
            reply = reply_from(self.run_cmux([*command, "--out", str(image)]))
            if image.exists():
                reply["file"] = base64.b64encode(image.read_bytes()).decode()
        return reply


def reply_from(completed):
    return {"exit": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr}


def refusal(reason):
    return {"exit": 1, "stdout": "", "stderr": f"cmux broker: {reason}\n"}


def answer(broker, line):
    try:
        request = json.loads(line)
        return broker.handle(list(request.get("args", [])), bool(request.get("out")))
    except Refused as reason:
        return refusal(str(reason))
    except (json.JSONDecodeError, AttributeError, TypeError):
        return refusal("malformed request")
    except subprocess.TimeoutExpired:
        return refusal("cmux timed out")


def serve(broker, socket_path):
    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            reply = answer(broker, self.rfile.readline())
            self.wfile.write(json.dumps(reply).encode() + b"\n")

    Path(socket_path).unlink(missing_ok=True)
    os.umask(0o077)
    return socketserver.UnixStreamServer(socket_path, Handler)


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
    parser.add_argument("--cmux", required=True)
    parser.add_argument("--watch-pid", type=int, required=True)
    options = parser.parse_args()
    broker = Broker(options.cmux)
    broker.ensure_profile()
    server = serve(broker, options.socket)
    threading.Thread(
        target=exit_when_gone, args=(options.watch_pid, options.socket), daemon=True
    ).start()
    server.serve_forever()


if __name__ == "__main__":
    main()
