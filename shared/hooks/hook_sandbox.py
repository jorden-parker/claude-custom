import contextlib
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HOOKS_DIR = Path(__file__).resolve().parent
PROFILE = HOOKS_DIR / "hook-sandbox.sb"
SANDBOX_ENV = HOOKS_DIR.parent / "sandbox-env"
DEFAULT_SANDBOX_EXEC = "/usr/bin/sandbox-exec"
ENV_ALLOWLIST = ("PATH", "HOME", "USER", "LOGNAME", "SHELL", "TERM", "LANG", "CLAUDE_CUSTOM_HOME")
GIT_QUERY_TIMEOUT_SECONDS = 5
NOTE = "(ran in the hook sandbox: writes only to the project, temp and ~/.cache/claude-sandbox; no network but localhost)"


class RefusedTarget(Exception):
    def __init__(self, project_dir):
        super().__init__(f"the project root {project_dir} is too broad for the hook sandbox")
        self.project_dir = project_dir


def enabled():
    return os.environ.get("CLAUDE_CUSTOM_HOOK_SANDBOX") == "1"


def sandbox_exec():
    override = os.environ.get("CLAUDE_OLLAMA_SANDBOX_EXEC")
    candidate = override or shutil.which("sandbox-exec") or DEFAULT_SANDBOX_EXEC
    return candidate if candidate and os.access(candidate, os.X_OK) else None


def available():
    platform = os.environ.get("HOOK_SANDBOX_PLATFORM") or sys.platform
    return platform == "darwin" and sandbox_exec() is not None and PROFILE.is_file()


def active():
    return enabled() and available()


def is_too_broad(project_dir):
    target = Path(os.path.realpath(project_dir))
    home = Path(os.path.realpath(Path.home()))
    return target == home or target in home.parents


def real_git_dir(project_dir):
    fallback = str(Path(project_dir) / ".git")
    try:
        result = subprocess.run(
            ["git", "-C", str(project_dir), "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, timeout=GIT_QUERY_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired):
        return fallback
    resolved = result.stdout.strip()
    return resolved if result.returncode == 0 and resolved else fallback


def sandboxed_argv(argv, project_dir, temp_dir):
    home = str(Path.home())
    values = {
        "HOME_DIR": home,
        "TARGET_DIR": str(project_dir),
        "GIT_DIR_REAL": real_git_dir(project_dir),
        "TMP_DIR": temp_dir,
        "CACHE_DIR": f"{home}/.cache/claude-sandbox",
    }
    profile_copy = Path(temp_dir) / "hook-sandbox.sb"
    profile_copy.write_bytes(PROFILE.read_bytes())
    profile_copy.chmod(0o600)
    params = [word for name, value in values.items() for word in ("-D", f"{name}={value}")]
    return [sandbox_exec(), "-f", str(profile_copy), *params, str(SANDBOX_ENV), *argv]


def confined_env(temp_dir):
    kept = {
        name: value
        for name, value in os.environ.items()
        if name in ENV_ALLOWLIST or name.startswith("LC_")
    }
    return {**kept, "TMPDIR": temp_dir}


@contextlib.contextmanager
def confined(argv, project_dir):
    if not active():
        yield list(argv), None
        return
    if is_too_broad(project_dir):
        raise RefusedTarget(project_dir)
    with tempfile.TemporaryDirectory(prefix="hook-sandbox.") as raw_temp_dir:
        temp_dir = os.path.realpath(raw_temp_dir)
        yield sandboxed_argv(argv, project_dir, temp_dir), confined_env(temp_dir)
