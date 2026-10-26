#!/usr/bin/env python3
import argparse
import http.server
import json
import os
import re
import secrets
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from urllib.parse import urlsplit

COMMAND_TIMEOUT_SECONDS = 120
REPL_TIMEOUT_MS = 60000
TEXT_LIMIT = 1000
REPLY_TAIL_LINES = 20
LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1"}
LOCKED_HOSTS = ["localhost", "127.0.0.1", "[::1]"]
PAGE_PROGRAM = Path(__file__).resolve().with_name("page.js")
STATUS_LINE = re.compile(r"^\[(ok|error) \|.*\]$")
PAGE_OPS = {
    "open": {"url"},
    "snapshot": set(),
    "act": {"action", "target", "text"},
}
PAGE_ACTIONS = {"click", "dblclick", "hover", "focus", "fill", "type", "press", "select", "check", "uncheck", "scroll"}


class Refused(Exception):
    pass


class PageFailed(Exception):
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
    if not isinstance(url, str) or has_ambiguous_characters(url):
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


def checked_text(value, name):
    if not isinstance(value, str) or len(value) > TEXT_LIMIT:
        raise Refused(f"{name} must be text of at most {TEXT_LIMIT} characters")
    return value


def checked_act(page):
    action = page.get("action")
    if action not in PAGE_ACTIONS:
        raise Refused(f"action must be one of {', '.join(sorted(PAGE_ACTIONS))}")
    request = {"op": "act", "action": action}
    for name in ("target", "text"):
        if name in page:
            request[name] = checked_text(page[name], name)
    return request


def checked_page(request):
    if not isinstance(request, dict) or set(request) != {"page"} or not isinstance(request["page"], dict):
        raise Refused("this broker takes only page requests")
    page = request["page"]
    op = page.get("op")
    if op not in PAGE_OPS:
        raise Refused(f"unknown op {op!r}")
    unknown = set(page) - PAGE_OPS[op] - {"op"}
    if unknown:
        raise Refused(f"unknown keys: {', '.join(sorted(unknown))}")
    if op == "open":
        return {"op": "open", "url": require_loopback_url(page.get("url"))}
    if op == "act":
        return checked_act(page)
    return {"op": "snapshot"}


def loads_or_none(text):
    try:
        return json.loads(text)
    except ValueError:
        return None


def repl_result(output):
    lines = [line for line in output.splitlines() if not STATUS_LINE.match(line)]
    for line in reversed(lines):
        value = loads_or_none(line)
        if isinstance(value, str):
            value = loads_or_none(value)
        if isinstance(value, dict):
            return value
    return None


def tail_text(output):
    return "\n".join(output.splitlines()[-REPLY_TAIL_LINES:])


class Broker:
    def __init__(self, cmux):
        self.cmux = cmux
        self.session = f"claude-ollama-{secrets.token_hex(8)}"
        self.workdir = tempfile.TemporaryDirectory(prefix="claude-ollama-browser-")
        self.program = PAGE_PROGRAM.read_text()

    def close(self):
        self.workdir.cleanup()

    def run_repl(self, program):
        return subprocess.run(
            [self.cmux, "browser", "repl", "--session", self.session, "--timeout", str(REPL_TIMEOUT_MS), "--eval", "-"],
            input=program,
            capture_output=True,
            text=True,
            cwd=self.workdir.name,
            timeout=COMMAND_TIMEOUT_SECONDS,
        )

    def run_page(self, page):
        program = f"{self.program}\nawait __cc_run({json.dumps(page)})\n"
        completed = self.run_repl(program)
        result = repl_result(completed.stdout)
        if completed.returncode != 0 or result is None:
            raise PageFailed(tail_text(completed.stdout + completed.stderr))
        return result

    def prove_lock(self):
        result = self.run_page({"op": "lock"})
        if result.get("allowed") != LOCKED_HOSTS:
            raise PageFailed(f"the browser allows {result.get('allowed')}")

    def handle(self, request):
        page = checked_page(request)
        try:
            return {"ok": True, "result": self.run_page(page)}
        except PageFailed as failure:
            return {"ok": False, "error": str(failure)}


def answer(broker, line):
    try:
        return broker.handle(json.loads(line))
    except Refused as reason:
        return {"ok": False, "error": str(reason)}
    except ValueError:
        return {"ok": False, "error": "malformed request"}
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "cmux timed out"}


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


def exit_when_gone(pid, socket_path, cleanup):
    while process_alive(pid):
        time.sleep(0.5)
    Path(socket_path).unlink(missing_ok=True)
    cleanup()
    os._exit(0)


SELF_TEST_PAGE = "claude-ollama browser-check page"


class SelfTestPage(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"<html><body>{SELF_TEST_PAGE}</body></html>".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def self_test_checks(result):
    return [
        ("fetch to example.com blocked", result.get("fetch") == "blocked"),
        ("opening example.com in a tab blocked", result.get("open") == "blocked"),
        ("navigating to example.com blocked", result.get("goto") == "blocked"),
        ("browser locked to localhost", result.get("allowed") == LOCKED_HOSTS),
        ("localhost page loads through the proxy bypass", SELF_TEST_PAGE in str(result.get("local", ""))),
    ]


def run_self_test(cmux):
    page_server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), SelfTestPage)
    threading.Thread(target=page_server.serve_forever, daemon=True).start()
    broker = Broker(cmux)
    result = {}
    try:
        result = broker.run_page(
            {"op": "selftest", "localUrl": f"http://127.0.0.1:{page_server.server_address[1]}/"}
        )
    except (PageFailed, OSError, subprocess.TimeoutExpired) as failure:
        print(f"FAIL: the browser self-test did not finish: {failure}")
    finally:
        page_server.shutdown()
        broker.close()
    checks = self_test_checks(result)
    for name, passed in checks:
        print(f"{'ok' if passed else 'FAIL'}: {name}")
    if all(passed for _name, passed in checks):
        print("browser-check: passed")
        return 0
    print("browser-check: FAILED")
    return 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket")
    parser.add_argument("--cmux", required=True)
    parser.add_argument("--watch-pid", type=int)
    parser.add_argument("--self-test", action="store_true")
    options = parser.parse_args()
    if options.self_test:
        sys.exit(run_self_test(options.cmux))
    if options.socket is None or options.watch_pid is None:
        parser.error("--socket and --watch-pid are required")
    broker = Broker(options.cmux)
    try:
        broker.prove_lock()
    except (PageFailed, OSError, subprocess.TimeoutExpired) as failure:
        broker.close()
        print(f"cmux broker: could not lock the browser to localhost: {failure}", file=sys.stderr)
        sys.exit(1)
    server = serve(broker, options.socket)
    threading.Thread(
        target=exit_when_gone, args=(options.watch_pid, options.socket, broker.close), daemon=True
    ).start()
    server.serve_forever()


if __name__ == "__main__":
    main()
