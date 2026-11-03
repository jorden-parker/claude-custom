import contextlib
import os
import shutil
import sys
import tempfile
from pathlib import Path

HOOKS_DIR = Path(__file__).resolve().parent
PROFILE = HOOKS_DIR / "hook-sandbox.sb"
SANDBOX_ENV = HOOKS_DIR.parent / "sandbox-env"
DEFAULT_SANDBOX_EXEC = "/usr/bin/sandbox-exec"
ENV_ALLOWLIST = ("PATH", "HOME", "USER", "LOGNAME", "SHELL", "TERM", "LANG", "CLAUDE_CUSTOM_HOME")
NOTE = "(ran in the hook sandbox: writes only to the project, temp and ~/.cache/claude-sandbox; no network but localhost)"


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


def sandboxed_argv(argv, project_dir, temp_dir):
    home = str(Path.home())
    values = {
        "HOME_DIR": home,
        "TARGET_DIR": str(project_dir),
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
    with tempfile.TemporaryDirectory(prefix="hook-sandbox.") as raw_temp_dir:
        temp_dir = os.path.realpath(raw_temp_dir)
        yield sandboxed_argv(argv, project_dir, temp_dir), confined_env(temp_dir)
