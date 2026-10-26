#!/usr/bin/env python3
import hashlib
import http.client
import json
import os
import re
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections import namedtuple
from pathlib import Path, PurePath

from mcp_stdio import serve, tool_result

READY_TIMEOUT_SECONDS = 90
PROBE_TIMEOUT_SECONDS = 2
MCP_TIMEOUT_SECONDS = 10
CMUX_TIMEOUT_SECONDS = 60
STOP_TIMEOUT_SECONDS = 10
POLL_SECONDS = 0.5
SETTLE_SECONDS = 1
DEFAULT_LOG_LINES = 40
MAX_LOG_LINES = 200
READY_ERROR_LINES = 20
STILL_STARTING_LINES = 20
MAX_STACK_LINES = 5
MAX_APP_DIRS = 20
MAX_OUTPUT_CHARS = 20000
BROWSER_WAIT_MS = 15000
SCRIPT_PATTERN = re.compile(r"^dev:[A-Za-z0-9_.-]{1,48}$")
START_SCRIPT_NAMES = {"dev", "start"}
LOCAL_URL = re.compile(r"https?://(?:localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0):(\d+)\S*")
ANSI_CODES = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
ERROR_LINE = re.compile(r"error|warn|⨯|failed|unhandled|exception|cannot |EADDRINUSE|ELIFECYCLE", re.IGNORECASE)
STACK_LINE = re.compile(r"^\s+at ")
PORT_FLAG = re.compile(r"(?:-p|--port)[ =](\d+)")
FRAMEWORK_PORTS = {"next": 3000, "vite": 5173}
LOCKFILES = [("pnpm-lock.yaml", "pnpm"), ("yarn.lock", "yarn"), ("bun.lockb", "bun"), ("bun.lock", "bun")]
OUTSIDE_REPOSITORY = "paths must stay inside the repository"
SCRIPT_RULE = "dev_start runs only dev, start or dev:* scripts"
PATH_RULE = "path must start with a single /"
CMUX_OFF = "the cmux browser is off; launch claude-ollama from a cmux terminal without CLAUDE_OLLAMA_CMUX=0. dev_errors still works."
NO_SERVER = "no dev server answers for {}; call dev_status"
NOT_NEXT = "not a Next.js 16+ dev server"

NO_PROXY_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))
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
BROWSER = {"surface": None}


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
            return match.group(0).replace("0.0.0.0", "localhost")
    return None


def dir_candidates(dir_text):
    found = []
    server = STARTED.get(dir_text)
    if server is not None:
        url = log_url(server.log_path)
        if url is not None:
            found.append(Candidate(url, "started this session", server.process.pid))
    lock = read_lock(dir_text)
    lock_number = lock_port(lock) if lock is not None else None
    if lock_number is not None:
        pid = lock.get("pid")
        found.append(Candidate(f"http://localhost:{lock_number}", ".next/dev/lock", pid if isinstance(pid, int) else None))
    script = dev_script_text(dir_text)
    port = script_port(script)
    if port is not None:
        found.append(Candidate(f"http://localhost:{port}", "the dev script", None))
    fallback = framework_port(script)
    if fallback is not None:
        found.append(Candidate(f"http://localhost:{fallback}", "the framework default", None))
    return found


def http_status(url):
    try:
        with NO_PROXY_OPENER.open(url, timeout=PROBE_TIMEOUT_SECONDS) as reply:
            return reply.status
    except urllib.error.HTTPError as error:
        return error.code
    except (urllib.error.URLError, http.client.HTTPException, OSError, ValueError):
        return None


def probe_dir(dir_text):
    tried = []
    for candidate in dir_candidates(dir_text):
        if candidate.url in tried:
            continue
        tried.append(candidate.url)
        status = http_status(candidate.url)
        if status is not None:
            return candidate, status, tried
    return None, None, tried


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


def dev_start(arguments):
    dir_text = project_dir(arguments)
    script = arguments.text("script") or "dev"
    if not is_allowed_script(script):
        raise ToolError(SCRIPT_RULE)
    require_app_dir(dir_text)
    require_directory(dir_text)
    if script not in package_scripts(dir_text):
        raise ToolError(f'no script "{script}" in {dir_text}/package.json')
    candidate, _status, _tried = probe_dir(dir_text)
    if candidate is not None:
        return f"already running at {candidate.url}{pid_text(candidate.pid)}; not starting another. Use dev_status / page_check."
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


def run_cmux(*arguments):
    try:
        completed = subprocess.run(["cmux", *arguments], capture_output=True, text=True, timeout=CMUX_TIMEOUT_SECONDS)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ToolError(f"cmux failed: {error}")
    if completed.returncode != 0:
        raise ToolError(completed.stderr.strip() or f"cmux exited with code {completed.returncode}")
    return completed


def open_browser(url):
    completed = run_cmux("--json", "browser", "open", url)
    try:
        opened = json.loads(completed.stdout)
    except ValueError:
        raise ToolError("cmux did not report the opened surface")
    surface = opened.get("surface_id") or opened.get("surface_ref")
    if not surface:
        raise ToolError("cmux did not report the opened surface")
    return surface


def navigate_surface(surface, url):
    run_cmux("browser", "--surface", surface, "console", "clear")
    run_cmux("browser", "--surface", surface, "errors", "clear")
    run_cmux("browser", "--surface", surface, "navigate", url)


def browser_surface_for(url):
    surface = BROWSER["surface"]
    if surface is not None:
        try:
            navigate_surface(surface, url)
            return surface
        except ToolError:
            BROWSER["surface"] = None
    surface = open_browser(url)
    BROWSER["surface"] = surface
    return surface


def valid_path(path):
    return path.startswith("/") and not path.startswith("//") and "://" not in path


def page_check(arguments):
    dir_text = project_dir(arguments)
    path = arguments.text("path") or "/"
    if not valid_path(path):
        raise ToolError(PATH_RULE)
    if not os.environ.get("CLAUDE_OLLAMA_CMUX_BROKER"):
        raise ToolError(CMUX_OFF)
    candidate, _status, _tried = probe_dir(dir_text)
    if candidate is None:
        raise ToolError(NO_SERVER.format(dir_text))
    url = candidate.url + path
    surface = browser_surface_for(url)
    run_cmux("browser", "--surface", surface, "wait", "--load-state", "complete", "--timeout-ms", str(BROWSER_WAIT_MS))
    time.sleep(SETTLE_SECONDS)
    errors = run_cmux("browser", "--surface", surface, "errors", "list").stdout.rstrip("\n")
    console = run_cmux("browser", "--surface", surface, "console", "list").stdout.rstrip("\n")
    next_text = next_errors(candidate.url) or NOT_NEXT
    return "\n".join(
        [
            f"Page: {url}",
            "Browser errors:",
            errors or "(none)",
            "Console:",
            console or "(none)",
            "Next.js:",
            next_text,
        ]
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
        "Start a package.json script (default dev) in the background, wait until it serves, return its real URL and first errors. Refuses if one already answers.",
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
        "Open or reload a page of the running dev server in the cmux browser and return its browser errors, console warnings and Next.js errors. Run after every UI change.",
        {**DIR_PROPERTY, "path": text_property("Page path starting with a single / (default /)")},
    ),
]
TOOL_HANDLERS = {
    "dev_status": (dev_status, ("dir",)),
    "dev_start": (dev_start, ("dir", "script")),
    "dev_logs": (dev_logs, ("dir", "errors_only", "lines")),
    "dev_errors": (dev_errors, ("dir",)),
    "dev_stop": (dev_stop, ("dir",)),
    "page_check": (page_check, ("dir", "path")),
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
