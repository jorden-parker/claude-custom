#!/usr/bin/env python3
import hashlib
import http.client
import json
import os
import re
import secrets
import shutil
import signal
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import namedtuple
from pathlib import Path, PurePath
from urllib.parse import urlsplit

from mcp_stdio import serve, tool_result

READY_TIMEOUT_SECONDS = 90
PROBE_TIMEOUT_SECONDS = 2
MCP_TIMEOUT_SECONDS = 10
STOP_TIMEOUT_SECONDS = 10
POLL_SECONDS = 0.5
DEFAULT_LOG_LINES = 40
MAX_LOG_LINES = 200
READY_ERROR_LINES = 20
STILL_STARTING_LINES = 20
MAX_STACK_LINES = 5
MAX_APP_DIRS = 20
MAX_OUTPUT_CHARS = 20000
SCRIPT_PATTERN = re.compile(r"^dev:[A-Za-z0-9_.-]{1,48}$")
START_SCRIPT_NAMES = {"dev", "start"}
LOCAL_URL = re.compile(r"(https?)://(?:localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0):(\d+)\S*")
HTTPS_FLAG = re.compile(r"--(?:experimental-)?https\b")
ANSI_CODES = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
ERROR_LINE = re.compile(r"error|warn|⨯|failed|unhandled|exception|cannot |EADDRINUSE|ELIFECYCLE", re.IGNORECASE)
STACK_LINE = re.compile(r"^\s+at ")
PORT_FLAG = re.compile(r"(?:-p|--port)[ =](\d+)")
FRAMEWORK_PORTS = {"next": 3000, "vite": 5173}
FRAMEWORK_DEFAULT = "the framework default"
LOCKFILES = [("pnpm-lock.yaml", "pnpm"), ("yarn.lock", "yarn"), ("bun.lockb", "bun"), ("bun.lock", "bun")]
OUTSIDE_REPOSITORY = "paths must stay inside the repository"
SCRIPT_RULE = "dev_start runs only dev, start or dev:* scripts"
PATH_RULE = "path must start with a single /"
URL_RULE = "url must start with http:// or https:// and name localhost, 127.0.0.1 or [::1]"
LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1"}
CMUX_OFF = "the cmux browser is off (CLAUDE_OLLAMA_CMUX=0); relaunch without it. dev_errors still works."
NO_CMUX = "no cmux browser: launch claude-ollama from a cmux terminal (cmux on PATH and CMUX_SOCKET_PATH set). dev_errors still works."
REPL_TIMEOUT_MS = 60000
COMMAND_TIMEOUT_SECONDS = 120
REPLY_TAIL_LINES = 20
STATUS_LINE = re.compile(r"^\[(ok|error) \|.*\]$")
PAGE_PROGRAM = Path(__file__).resolve().with_name("page.js")
NO_SERVER = "no dev server answers for {}; call dev_status"
NOT_NEXT = "not a Next.js 16+ dev server"
NO_PAGE_ORIGIN = "unknown: this session has not run page_check"


def loopback_tls_context():
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    return context


NO_PROXY_OPENER = urllib.request.build_opener(
    urllib.request.ProxyHandler({}), urllib.request.HTTPSHandler(context=loopback_tls_context())
)
DEV_SERVER_ENV = {"NO_COLOR": "1", "FORCE_COLOR": "0", "CI": ""}

Candidate = namedtuple("Candidate", "url source pid")
DevServer = namedtuple("DevServer", "process log_path")


def text_property(description):
    return {"type": "string", "description": description}


def number_property(description):
    return {"type": "integer", "description": description}


def switch_property(description):
    return {"type": "boolean", "description": description}


def tool(name, description, properties=None, required=()):
    schema = {"type": "object", "properties": properties or {}}
    if required:
        schema["required"] = list(required)
    return {"name": name, "description": description, "inputSchema": schema}


class ToolError(Exception):
    pass


class Arguments:
    def __init__(self, values, allowed):
        if not isinstance(values, dict):
            raise ToolError("arguments must be an object")
        unknown = set(values) - set(allowed)
        if unknown:
            raise ToolError(f"unknown arguments: {', '.join(sorted(unknown))}")
        self.values = values

    def switch(self, name):
        value = self.values.get(name, False)
        if not isinstance(value, bool):
            raise ToolError(f"{name} must be true or false")
        return value

    def text(self, name):
        value = self.values.get(name)
        if value is not None and not isinstance(value, str):
            raise ToolError(f"{name} must be text")
        return value

    def choice(self, name, options):
        value = self.values.get(name)
        if not isinstance(value, str) or value not in options:
            raise ToolError(f"{name} must be one of {', '.join(sorted(options))}")
        return value

    def whole_number(self, name, default, maximum):
        value = self.values.get(name, default)
        if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= maximum:
            raise ToolError(f"{name} must be a whole number from 1 to {maximum}")
        return value


def inside_repository(path):
    if PurePath(path).is_absolute() or ".." in PurePath(path).parts:
        raise ToolError(OUTSIDE_REPOSITORY)
    return path


def git_root():
    try:
        completed = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    except OSError:
        return Path.cwd().resolve()
    if completed.returncode != 0:
        return Path.cwd().resolve()
    return Path(completed.stdout.strip()).resolve()


ROOT = git_root()
STARTED = {}
BROWSER = {"origin": None, "session": f"claude-ollama-{secrets.token_hex(8)}", "workdir": None}
PAGE_ACTIONS = {"click", "dblclick", "hover", "focus", "fill", "type", "press", "select", "check", "uncheck", "scroll"}


def is_inside_root(path):
    resolved = os.path.realpath(path)
    root = os.path.realpath(ROOT)
    return resolved == root or resolved.startswith(root + os.sep)


def project_dir(arguments):
    text = arguments.text("dir") or "."
    inside_repository(text)
    dir_text = str(PurePath(text))
    if not is_inside_root(ROOT / dir_text):
        raise ToolError(OUTSIDE_REPOSITORY)
    return dir_text


def require_app_dir(dir_text):
    if dir_text not in app_dirs():
        raise ToolError(f"{dir_text} is not an app dir; dev_status lists them")


def require_directory(dir_text):
    if not (ROOT / dir_text).is_dir():
        raise ToolError(f"no directory {dir_text}")


def run_git(arguments):
    try:
        return subprocess.run(["git", *arguments], cwd=ROOT, capture_output=True, text=True)
    except OSError:
        return subprocess.CompletedProcess(arguments, 1, "", "")


def tracked_package_files():
    completed = run_git(["ls-files", "-z", "--", "package.json", "*/package.json"])
    if completed.returncode != 0:
        return ["package.json"] if (ROOT / "package.json").is_file() else []
    return [name for name in completed.stdout.split("\0") if name]


def package_scripts(dir_text):
    try:
        data = json.loads((ROOT / dir_text / "package.json").read_text())
    except (OSError, ValueError):
        return {}
    scripts = data.get("scripts") if isinstance(data, dict) else None
    return scripts if isinstance(scripts, dict) else {}


def app_dirs():
    dirs = []
    for name in tracked_package_files():
        parts = PurePath(name).parts
        if "node_modules" in parts:
            continue
        directory = str(PurePath(name).parent)
        scripts = package_scripts(directory)
        if "dev" in scripts or "start" in scripts:
            dirs.append(directory)
    return dirs[:MAX_APP_DIRS]


def dev_script_text(dir_text):
    scripts = package_scripts(dir_text)
    return scripts.get("dev") or scripts.get("start") or ""


def script_port(script_text):
    match = PORT_FLAG.search(script_text)
    return int(match.group(1)) if match else None


def framework_port(script_text):
    for name, port in FRAMEWORK_PORTS.items():
        if re.search(rf"\b{name}\b", script_text):
            return port
    return None


def read_lock(dir_text):
    try:
        data = json.loads((ROOT / dir_text / ".next" / "dev" / "lock").read_text())
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def lock_port(lock):
    port = lock.get("port")
    if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
        return None
    return port


def clean_lines(log_path):
    try:
        text = log_path.read_text(errors="replace")
    except OSError:
        return []
    return [ANSI_CODES.sub("", line) for line in text.splitlines()]


def log_url(log_path):
    for line in clean_lines(log_path):
        match = LOCAL_URL.search(line)
        if match:
            return url_for_port(match.group(2), match.group(1))
    return None


def loopback_url(scheme, port):
    return f"{scheme}://localhost:{port}"


def url_for_port(text, scheme):
    port = int(text)
    return loopback_url(scheme, port) if 1 <= port <= 65535 else None


def script_scheme(script_text):
    return "https" if HTTPS_FLAG.search(script_text or "") else "http"


def lock_scheme(lock, script_text):
    app_url = lock.get("appUrl")
    if isinstance(app_url, str) and app_url.startswith("https://"):
        return "https"
    return script_scheme(script_text)


def dir_candidates(dir_text, script_text):
    found = []
    scheme = script_scheme(script_text)
    server = STARTED.get(dir_text)
    if server is not None:
        url = log_url(server.log_path)
        if url is not None:
            found.append(Candidate(url, "started this session", server.process.pid))
    lock = read_lock(dir_text)
    lock_number = lock_port(lock) if lock is not None else None
    if lock_number is not None:
        pid = lock.get("pid")
        found.append(Candidate(loopback_url(lock_scheme(lock, script_text), lock_number), ".next/dev/lock", pid if isinstance(pid, int) else None))
    port = script_port(script_text)
    if port is not None:
        found.append(Candidate(loopback_url(scheme, port), "the dev script", None))
    fallback = framework_port(script_text)
    if fallback is not None:
        found.append(Candidate(loopback_url(scheme, fallback), FRAMEWORK_DEFAULT, None))
    return found


def http_status(url):
    try:
        with NO_PROXY_OPENER.open(url, timeout=PROBE_TIMEOUT_SECONDS) as reply:
            return reply.status
    except urllib.error.HTTPError as error:
        return error.code
    except (urllib.error.URLError, http.client.HTTPException, OSError, ValueError):
        return None


def other_scheme(url):
    if url.startswith("https://"):
        return "http://" + url[len("https://"):]
    return "https://" + url[len("http://"):]


def either_scheme(candidate):
    yield candidate
    yield candidate._replace(url=other_scheme(candidate.url))


def probe_dir(dir_text, script_text=None):
    tried = []
    for listed in dir_candidates(dir_text, script_text or dev_script_text(dir_text)):
        for candidate in either_scheme(listed):
            if candidate.url in tried:
                continue
            tried.append(candidate.url)
            status = http_status(candidate.url)
            if status is not None:
                return candidate, status, tried
    return None, None, tried


def port_is_open(url):
    parts = urlsplit(url)
    try:
        with socket.create_connection((parts.hostname, parts.port), timeout=PROBE_TIMEOUT_SECONDS):
            return True
    except OSError:
        return False


def busy_candidate(dir_text, script_text):
    for candidate in dir_candidates(dir_text, script_text):
        if candidate.source != FRAMEWORK_DEFAULT and port_is_open(candidate.url):
            return candidate
    return None


def pid_text(pid):
    return f" (pid {pid})" if pid is not None else ""


def status_line(dir_text):
    candidate, status, tried = probe_dir(dir_text)
    if candidate is None:
        tried_text = ", ".join(tried) if tried else "no URL known"
        hint = 'start it with dev_start {"dir":"%s"}' % dir_text
        return f"{dir_text}: no dev server answers (tried {tried_text}); {hint}"
    pid = f", pid {candidate.pid}" if candidate.pid is not None else ""
    return f"{dir_text}: {candidate.url} answers (HTTP {status}){pid}, from {candidate.source}"


def dev_status(arguments):
    if arguments.text("dir") is not None:
        return status_line(project_dir(arguments))
    dirs = app_dirs()
    if not dirs:
        return "no app dirs: no tracked package.json has a dev or start script; no dev server answers"
    return "\n".join(status_line(dir_text) for dir_text in dirs)


def log_path_for(dir_text):
    state_home = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    directory = Path(state_home) / "claude-custom" / "dev-server"
    directory.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha1(str((ROOT / dir_text).resolve()).encode()).hexdigest()[:12]
    return directory / f"{digest}.log"


def package_manager_for(dir_text):
    for folder in [(ROOT / dir_text).resolve(), *(ROOT / dir_text).resolve().parents]:
        for lockfile, manager in LOCKFILES:
            if (folder / lockfile).is_file():
                return manager
        if folder == ROOT:
            break
    return "npm"


def launch_dev_server(dir_text, script):
    log_path = log_path_for(dir_text)
    with open(log_path, "w") as log:
        try:
            process = subprocess.Popen(
                [package_manager_for(dir_text), "run", script],
                cwd=ROOT / dir_text,
                stdin=subprocess.DEVNULL,
                stdout=log,
                stderr=subprocess.STDOUT,
                start_new_session=True,
                env={**os.environ, **DEV_SERVER_ENV},
            )
        except OSError as error:
            raise ToolError(f"cannot start the dev server: {error}")
    return DevServer(process, log_path)


def error_block(lines):
    block = []
    stack_budget = 0
    for line in lines:
        if ERROR_LINE.search(line):
            block.append(line)
            stack_budget = MAX_STACK_LINES
        elif stack_budget and STACK_LINE.match(line):
            block.append(line)
            stack_budget -= 1
        else:
            stack_budget = 0
    return block


def tail(lines, count):
    return lines[-count:] if count else []


def wait_until_ready(dir_text, server):
    deadline = time.monotonic() + READY_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        exit_code = server.process.poll()
        if exit_code is not None:
            STARTED.pop(dir_text, None)
            lines = clean_lines(server.log_path)
            raise ToolError(f"dev server exited with code {exit_code}:\n" + "\n".join(tail(lines, DEFAULT_LOG_LINES)))
        url = log_url(server.log_path)
        if url is not None and http_status(url) is not None:
            return ready_text(url, server, clean_lines(server.log_path))
        time.sleep(POLL_SECONDS)
    lines = clean_lines(server.log_path)
    return (
        f"still starting after {READY_TIMEOUT_SECONDS}s (pid {server.process.pid}); call dev_status later.\n"
        + "\n".join(tail(lines, STILL_STARTING_LINES))
    )


def ready_text(url, server, lines):
    text = f"ready at {url} (pid {server.process.pid}, log {server.log_path})"
    errors = error_block(lines)[-READY_ERROR_LINES:]
    return "\n".join([text, *errors])


def is_allowed_script(script):
    return script in START_SCRIPT_NAMES or SCRIPT_PATTERN.match(script) is not None


def held_port_text(candidate):
    port = urlsplit(candidate.url).port
    return (
        f"port {port} is in use (from {candidate.source}){pid_text(candidate.pid)} "
        f"but gave no HTTP reply within {PROBE_TIMEOUT_SECONDS}s; not starting another. "
        "Call dev_status shortly, or free the port."
    )


def dev_start(arguments):
    dir_text = project_dir(arguments)
    script = arguments.text("script") or "dev"
    if not is_allowed_script(script):
        raise ToolError(SCRIPT_RULE)
    require_app_dir(dir_text)
    require_directory(dir_text)
    scripts = package_scripts(dir_text)
    if script not in scripts:
        raise ToolError(f'no script "{script}" in {dir_text}/package.json')
    candidate, _status, _tried = probe_dir(dir_text, scripts[script])
    if candidate is not None:
        return f"already running at {candidate.url}{pid_text(candidate.pid)}; not starting another. Use dev_status / page_check."
    held = busy_candidate(dir_text, scripts[script])
    if held is not None:
        return held_port_text(held)
    server = launch_dev_server(dir_text, script)
    STARTED[dir_text] = server
    return wait_until_ready(dir_text, server)


def dev_logs(arguments):
    dir_text = project_dir(arguments)
    count = arguments.whole_number("lines", DEFAULT_LOG_LINES, MAX_LOG_LINES)
    server = STARTED.get(dir_text)
    if server is None:
        return f"no log: this session did not start a dev server for {dir_text}"
    lines = clean_lines(server.log_path)
    if arguments.switch("errors_only"):
        selected = error_block(lines)
        if not selected:
            return f"no error lines in the last {count} lines"
        return "\n".join(tail(selected, count))
    return "\n".join(tail(lines, count))


def mcp_content(payload):
    raw_messages = [line[len("data:"):] for line in payload.splitlines() if line.startswith("data:")] or [payload]
    for raw in raw_messages:
        try:
            result = json.loads(raw).get("result")
        except (ValueError, AttributeError):
            continue
        if isinstance(result, dict) and isinstance(result.get("content"), list):
            texts = [item.get("text", "") for item in result["content"] if isinstance(item, dict)]
            return "\n".join(texts)
    return None


def next_errors(url):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "get_errors", "arguments": {}}}).encode()
    request = urllib.request.Request(
        url.rstrip("/") + "/_next/mcp",
        data=body,
        headers={"Content-Type": "application/json", "Accept": "application/json, text/event-stream"},
        method="POST",
    )
    try:
        with NO_PROXY_OPENER.open(request, timeout=MCP_TIMEOUT_SECONDS) as reply:
            payload = reply.read().decode("utf-8", "replace")
    except (urllib.error.URLError, http.client.HTTPException, OSError, ValueError):
        return None
    return mcp_content(payload)


def server_log_block(dir_text):
    server = STARTED.get(dir_text)
    if server is None:
        return ""
    errors = error_block(clean_lines(server.log_path))
    return "Server log:\n" + ("\n".join(errors) if errors else "(no error lines)")


def dev_errors(arguments):
    dir_text = project_dir(arguments)
    candidate, _status, _tried = probe_dir(dir_text)
    if candidate is None:
        raise ToolError(NO_SERVER.format(dir_text))
    text = next_errors(candidate.url)
    if text is None:
        fallback = server_log_block(dir_text) or f"no log: this session did not start a dev server for {dir_text}"
        return f"{NOT_NEXT} (no /_next/mcp); showing log errors instead:\n{fallback}"
    block = server_log_block(dir_text)
    return "\n".join(part for part in [text, block] if part)


def dev_stop(arguments):
    dir_text = project_dir(arguments)
    server = STARTED.pop(dir_text, None)
    if server is None:
        return f"this session did not start a dev server for {dir_text}; stop it where it was started"
    pid = server.process.pid
    stop_process(server.process)
    return f"stopped {dir_text} (pid {pid})"


def signal_group(process, signum):
    try:
        os.killpg(process.pid, signum)
    except ProcessLookupError:
        pass


def stop_process(process):
    signal_group(process, signal.SIGTERM)
    try:
        process.wait(timeout=STOP_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        signal_group(process, signal.SIGKILL)
        process.wait()


def cmux_command():
    if os.environ.get("CLAUDE_OLLAMA_CMUX") == "0":
        raise ToolError(CMUX_OFF)
    cmux = shutil.which("cmux")
    if cmux is None or not os.environ.get("CMUX_SOCKET_PATH"):
        raise ToolError(NO_CMUX)
    return cmux


def browser_workdir():
    if BROWSER["workdir"] is None:
        BROWSER["workdir"] = tempfile.TemporaryDirectory(prefix="claude-ollama-browser-")
    return BROWSER["workdir"].name


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
    return "\n".join(output.strip().splitlines()[-REPLY_TAIL_LINES:])


def ask_browser(request):
    cmux = cmux_command()
    program = PAGE_PROGRAM.read_text() + f"\nawait __cc_run({json.dumps(request)})\n"
    argv = [cmux, "browser", "repl", "--session", BROWSER["session"], "--timeout", str(REPL_TIMEOUT_MS), "--eval", "-"]
    try:
        completed = subprocess.run(argv, input=program, cwd=browser_workdir(), capture_output=True, text=True, timeout=COMMAND_TIMEOUT_SECONDS, check=False)
    except subprocess.TimeoutExpired:
        raise ToolError("the cmux browser did not answer in time") from None
    result = repl_result(completed.stdout)
    if completed.returncode != 0 or result is None:
        raise ToolError(tail_text(completed.stderr + completed.stdout) or "the cmux browser failed")
    return result


def valid_path(path):
    return path.startswith("/") and not path.startswith("//") and "://" not in path


def port_is_valid(parts):
    try:
        return parts.port is None or 1 <= parts.port <= 65535
    except ValueError:
        return False


def loopback_origin(url_text):
    parts = urllib.parse.urlsplit(url_text)
    if parts.scheme not in ("http", "https") or parts.hostname not in LOOPBACK_HOSTS or "@" in parts.netloc:
        return None
    return f"{parts.scheme}://{parts.netloc}" if port_is_valid(parts) else None


def page_target(arguments, dir_text):
    url_text = arguments.text("url")
    if url_text is not None:
        origin = loopback_origin(url_text)
        if origin is None:
            raise ToolError(URL_RULE)
        return origin, url_text
    path = arguments.text("path") or "/"
    if not valid_path(path):
        raise ToolError(PATH_RULE)
    candidate, _status, _tried = probe_dir(dir_text)
    if candidate is None:
        raise ToolError(NO_SERVER.format(dir_text))
    return candidate.url, candidate.url + path


def listing(items):
    return "\n".join(items) if items else "(none)"


def next_errors_text(origin):
    if origin is None:
        return NO_PAGE_ORIGIN
    return next_errors(origin) or NOT_NEXT


def browser_sections(page, origin):
    return [
        "Browser errors:",
        listing(page.get("errors")),
        "Console:",
        listing(page.get("console")),
        "Next.js:",
        next_errors_text(origin),
    ]


def surface_lines(page):
    return [f"Surface: {page['surface']}"] if page.get("surface") else []


def page_check(arguments):
    dir_text = project_dir(arguments)
    cmux_command()
    origin, url = page_target(arguments, dir_text)
    BROWSER["origin"] = origin
    page = ask_browser({"op": "open", "url": url})
    return "\n".join([f"Page: {url}", *surface_lines(page), *browser_sections(page, origin)])


def page_snapshot(arguments):
    return ask_browser({"op": "snapshot"})["elements"]


def required_text(text, meaning):
    if not text:
        raise ToolError(f"text is required: {meaning}")
    return text


def scroll_request(target, text):
    request = {"op": "act", "action": "scroll"}
    if target:
        request["target"] = target
    if text is not None:
        if not text.isdigit():
            raise ToolError("text must be a whole number of pixels for scroll")
        request["text"] = text
    return request


def action_request(action, target, text):
    if action == "press":
        return {"op": "act", "action": action, "text": required_text(text, "the key, e.g. Enter")}
    if action == "scroll":
        return scroll_request(target, text)
    if not target:
        raise ToolError("target is required for this action (a ref like e3, or a CSS selector)")
    request = {"op": "act", "action": action, "target": target}
    if action in ("type", "select"):
        request["text"] = required_text(text, "the text or value")
    elif action == "fill" and text is not None:
        request["text"] = text
    return request


def page_act(arguments):
    action = arguments.choice("action", PAGE_ACTIONS)
    page = ask_browser(action_request(action, arguments.text("target"), arguments.text("text")))
    return "\n".join(
        [f"URL now: {page.get('url', '')}", *browser_sections(page, BROWSER["origin"]), "Elements:", page.get("elements", "")]
    )


def truncated(text):
    if not text.strip():
        return "(no output)"
    if len(text) <= MAX_OUTPUT_CHARS:
        return text
    note = f"\n[truncated: showed {MAX_OUTPUT_CHARS} of {len(text)} characters; narrow it with lines or errors_only]"
    return text[:MAX_OUTPUT_CHARS] + note


DIR_PROPERTY = {"dir": text_property("Project folder, relative to the repository root (default .)")}
TOOLS = [
    tool(
        "dev_status",
        "Which dev servers answer, at which URL and pid. Call this before opening a URL or starting a server; never guess a port.",
        DIR_PROPERTY,
    ),
    tool(
        "dev_start",
        "Start a package.json script (default dev) in the background, wait until it serves, return its real URL and first errors. Refuses if one already answers or its port is held.",
        {**DIR_PROPERTY, "script": text_property("package.json script to run (default dev)")},
    ),
    tool(
        "dev_logs",
        "The dev server's output from this session; errors_only keeps error and warning lines with their stack.",
        {
            **DIR_PROPERTY,
            "errors_only": switch_property("Only error and warning lines, with their stack"),
            "lines": number_property("How many lines to return (default 40, max 200)"),
        },
    ),
    tool(
        "dev_errors",
        "Current build, runtime and config errors from a Next.js 16+ dev server (its /_next/mcp get_errors), else the log's error lines.",
        DIR_PROPERTY,
    ),
    tool("dev_stop", "Stop a dev server this session started.", DIR_PROPERTY),
    tool(
        "page_check",
        "Open or reload a page of the running dev server in the cmux browser and return its browser errors, console warnings and Next.js errors. Run after every UI change. Use this, never Bash open, for local URLs.",
        {
            **DIR_PROPERTY,
            "path": text_property("Page path starting with a single / (default /)"),
            "url": text_property("Full local URL to open instead, such as https://127.0.0.1:4000/x, when dev_status does not find the server"),
        },
    ),
    tool(
        "page_snapshot",
        "Interactive elements of the open page with refs (e1, e2…) to use in page_act. Refs change after the page changes; snapshot again.",
    ),
    tool(
        "page_act",
        "Click, fill, type, press, select, check or scroll on the open page (target by ref from page_snapshot), then return the errors and console messages it caused and the new elements.",
        {
            "action": {"type": "string", "enum": sorted(PAGE_ACTIONS), "description": "What to do"},
            "target": text_property("Element ref such as e3, or a CSS selector (not for press)"),
            "text": text_property("Text to type or fill, the value to select, the key to press, or scroll pixels"),
        },
        ["action"],
    ),
]
TOOL_HANDLERS = {
    "dev_status": (dev_status, ("dir",)),
    "dev_start": (dev_start, ("dir", "script")),
    "dev_logs": (dev_logs, ("dir", "errors_only", "lines")),
    "dev_errors": (dev_errors, ("dir",)),
    "dev_stop": (dev_stop, ("dir",)),
    "page_check": (page_check, ("dir", "path", "url")),
    "page_snapshot": (page_snapshot, ()),
    "page_act": (page_act, ("action", "target", "text")),
}


def run_tool(name, values):
    if name not in TOOL_HANDLERS:
        raise ToolError(f"unknown tool: {name}")
    handler, allowed = TOOL_HANDLERS[name]
    return handler(Arguments(values, allowed))


def call_tool(params):
    try:
        return tool_result(truncated(run_tool(params.get("name"), params.get("arguments") or {})))
    except ToolError as error:
        return tool_result(str(error), True)


def list_tools():
    return TOOLS


def stop_all_started():
    for server in list(STARTED.values()):
        stop_process(server.process)
    STARTED.clear()


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))
    try:
        serve("dev", list_tools, call_tool)
    finally:
        stop_all_started()
