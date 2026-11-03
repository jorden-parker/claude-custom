#!/usr/bin/env python3
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hook_telemetry import record_hook_event
from profile_env import catalogue_default
from test_scope import expected_test_path, is_code, is_test, resolve_test, within

EDIT_TOOLS = {"Edit", "Write", "MultiEdit"}
HOST_ENV = Path(__file__).resolve().parents[1] / "host-env"
SEATBELT_PROFILE = Path(__file__).resolve().parents[2] / "ollama" / "qwen-sandbox.sb"
SEATBELT_PARAMS = ("HOME_DIR", "TARGET_DIR", "TMP_DIR", "CACHE_DIR", "QWEN_DIR", "RUNTIME_DIR")
PLATFORM = os.environ.get("TEST_AFTER_EDIT_PLATFORM") or sys.platform
CACHE_DIR = Path(os.environ.get("TEST_AFTER_EDIT_CACHE_DIR") or Path.home() / ".cache" / "claude-custom" / "test-after-edit")
TIMEOUT_SECONDS = int(os.environ.get("TEST_AFTER_EDIT_TIMEOUT") or 60)
OUTPUT_CAP = 2 * 1024 * 1024
LINE_LIMIT = 300
FAILURE_LINES = 4
FAILURE_SIGNAL = re.compile(r"FAIL|error|panic|traceback|exception|assert|not ok|expected", re.IGNORECASE)
MODES = {"suggest", "run"}


def session_record_path(session_id):
    config_dir = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
    return config_dir / "cache" / "test-after-edit" / f"{session_id}.json"


def identity_of(path):
    try:
        status = path.stat()
    except OSError:
        return None
    return [status.st_dev, status.st_ino]


def load_edited(record):
    if not record.exists():
        return []
    try:
        rows = json.loads(record.read_text())["edited"]
        return [row for row in rows if isinstance(row, dict)]
    except (OSError, ValueError, KeyError, TypeError):
        return None


def write_record(record, edited):
    record.parent.mkdir(parents=True, exist_ok=True)
    handle, staged = tempfile.mkstemp(dir=record.parent, prefix=".staged-")
    with os.fdopen(handle, "w", encoding="utf-8") as staged_file:
        json.dump({"edited": edited}, staged_file)
    os.replace(staged, record)


def remember_edited(record, edited, path):
    identity = identity_of(path) or [None, None]
    edited.append({"path": str(path), "dev": identity[0], "ino": identity[1]})
    write_record(record, edited)


def same_file(path, other):
    identity = identity_of(path)
    return identity is not None and identity == identity_of(other)


def edited_this_session(path, edited):
    identity = identity_of(path)
    return identity is not None and any([row.get("dev"), row.get("ino")] == identity for row in edited)


def sandbox_exec():
    override = os.environ.get("CLAUDE_OLLAMA_SANDBOX_EXEC")
    candidate = override if override is not None else shutil.which("sandbox-exec")
    return candidate if candidate and os.access(candidate, os.X_OK) else None


def refusal_reason(resolved, path, cwd, edited):
    if edited is None:
        return "session record unreadable"
    if PLATFORM != "darwin" or sandbox_exec() is None or not SEATBELT_PROFILE.is_file():
        return "no sandbox on this platform"
    if not within(path, cwd):
        return "outside the project"
    if is_test(path) or is_test(path.resolve()):
        return "edited file is a test"
    if same_file(path, resolved["test"]) or same_file(path, Path(resolved["argv"][0])):
        return "edited file is the program"
    if edited_this_session(resolved["test"], edited):
        return "test edited this session"
    return None


def mode_from_env():
    default_mode = catalogue_default("CLAUDE_OLLAMA_TEST_AFTER_EDIT")
    requested = os.environ.get("CLAUDE_OLLAMA_TEST_AFTER_EDIT", default_mode)
    if requested == "0":
        return None
    return requested if requested in MODES else default_mode


def content_key(edited, test):
    digest = hashlib.sha1(edited.read_bytes() + b"\0" + test.read_bytes()).hexdigest()
    return CACHE_DIR / f"{digest}-{edited.name}"


def remember_pass(key):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    key.touch()


def drain(stream, chunks):
    size = 0
    for chunk in iter(lambda: stream.read(65536), b""):
        if size < OUTPUT_CAP:
            chunks.append(chunk[: OUTPUT_CAP - size])
        size += len(chunk)


def seatbelt_values(project_dir, scratch_dir):
    home = str(Path.home())
    return {
        "HOME_DIR": home,
        "TARGET_DIR": str(project_dir),
        "TMP_DIR": scratch_dir,
        "CACHE_DIR": f"{home}/.cache/claude-sandbox",
        "QWEN_DIR": scratch_dir,
        "RUNTIME_DIR": scratch_dir,
    }


def render_profile(scratch_dir):
    rendered = Path(scratch_dir) / "test-after-edit.sb"
    rendered.write_bytes(SEATBELT_PROFILE.read_bytes())
    rendered.chmod(0o600)
    return rendered


def sandboxed_argv(argv, project_dir, scratch_dir):
    values = seatbelt_values(project_dir, scratch_dir)
    params = [word for name in SEATBELT_PARAMS for word in ("-D", f"{name}={values[name]}")]
    return [sandbox_exec(), "-f", str(render_profile(scratch_dir)), *params, str(HOST_ENV), *argv]


def run_capped(argv, cwd):
    with tempfile.TemporaryDirectory(prefix="test-after-edit.") as scratch_dir:
        return run_in_sandbox(sandboxed_argv(argv, cwd, scratch_dir), cwd)


def run_in_sandbox(argv, cwd):
    process = subprocess.Popen(
        argv, cwd=cwd, stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True,
    )
    chunks = []
    reader = threading.Thread(target=drain, args=(process.stdout, chunks))
    reader.start()
    try:
        process.wait(timeout=TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
        reader.join()
        return None, b""
    reader.join()
    return process.returncode, b"".join(chunks)


def failing_excerpt(output):
    lines = [line[:LINE_LIMIT] for line in output.decode("utf-8", errors="replace").splitlines() if line.strip()]
    start = next((index for index, line in enumerate(lines) if FAILURE_SIGNAL.search(line)), None)
    if start is None:
        return lines[-FAILURE_LINES:]
    return lines[start:start + FAILURE_LINES]


def run_outcome(resolved, edited):
    key = content_key(edited, resolved["test"]) if edited.is_file() else None
    if key is not None and key.exists():
        return "cached", f"tests: pass ({resolved['display']}, cached)", None
    started = time.monotonic()
    returncode, output = run_capped(resolved["argv"], resolved["cwd"])
    seconds = round(time.monotonic() - started, 1)
    if returncode is None:
        return "timeout", f"tests: timed out after {TIMEOUT_SECONDS}s ({resolved['display']}); run it yourself", seconds
    if returncode != 0:
        excerpt = "\n".join(failing_excerpt(output))
        return "fail", f"tests: FAIL ({resolved['display']}): {excerpt}", seconds
    if key is not None:
        remember_pass(key)
    return "pass", f"tests: pass ({resolved['display']}, {seconds}s)", seconds


def missing_test_line(path):
    return f"no test found beside {path.name}; write {expected_test_path(path)} first"


def context_for(mode, event, path, edited):
    cwd = Path(event.get("cwd") or os.getcwd()).resolve()
    resolved = resolve_test(path, cwd)
    if resolved is None:
        return missing_test_line(path), {"found": False, "result": None, "seconds": None}
    if mode == "suggest":
        return f"run now: {resolved['display']}", {"found": True, "result": None, "seconds": None}
    reason = refusal_reason(resolved, path, cwd, edited)
    if reason is not None:
        return f"run now: {resolved['display']} (not run: {reason})", {"found": True, "result": "refused", "seconds": None}
    result, line, seconds = run_outcome(resolved, path)
    return line, {"found": True, "result": result, "seconds": seconds}


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    tool_input = event.get("tool_input") or {}
    path = Path(tool_input.get("file_path") or "")
    if event.get("hook_event_name") != "PostToolUse" or event.get("tool_name") not in EDIT_TOOLS or not path.name:
        return
    record = session_record_path(event.get("session_id", "nosession"))
    edited = load_edited(record)
    if edited is not None:
        remember_edited(record, edited, path.resolve())
    mode = mode_from_env()
    if mode is None or not is_code(path, tool_input, event.get("tool_name")):
        return
    line, fields = context_for(mode, event, path.resolve(), edited)
    record_hook_event("test-after-edit", event, "test-after-edit", line.split("\n")[0], {"mode": mode, **fields})
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": line}}))


if __name__ == "__main__":
    main()
