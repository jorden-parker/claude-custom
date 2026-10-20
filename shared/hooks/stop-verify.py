#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
from pathlib import Path

OUTPUT_LINE_LIMIT = 40
JS_PROJECT_MARKERS = ("package.json", "tsconfig.json")
JS_FILE = re.compile(r"\.(ts|tsx|js|jsx|mjs|cjs|mts|cts)$")
BASE_BRANCHES = ("main", "master", "HEAD")
FALLOW_ADVICE = ("Fallow found problems in your changes. Run `npx fallow explain <issue-type>` for any "
                 "finding you don't understand. Remove dead code instead of suppressing it.")
VERIFY_SCRIPT = Path(".claude") / "verify"
OPT_OUT_FILE = Path(".claude") / "no-verify"
EDITS_DIR = Path(os.environ.get("STOP_VERIFY_STATE_DIR") or Path.home() / ".cache" / "claude-custom" / "edited-files")


def edits_log(event):
    return EDITS_DIR / Path(event.get("session_id") or "unknown").name


def record_edit(event):
    path = event.get("tool_input", {}).get("file_path")
    if not path:
        return
    EDITS_DIR.mkdir(parents=True, exist_ok=True)
    with edits_log(event).open("a") as log:
        log.write(path + "\n")


def relative_to_root(path, root):
    try:
        return str(Path(path).resolve().relative_to(root))
    except ValueError:
        return None


def edited_files(event, root):
    log = edits_log(event)
    if not log.is_file():
        return []
    relative = (relative_to_root(path, root) for path in log.read_text().splitlines())
    return sorted({path for path in relative if path})


def project_root(cwd):
    result = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return Path(result.stdout.strip() if result.returncode == 0 else cwd).resolve()


def last_lines(text):
    return "\n".join(text.strip().splitlines()[-OUTPUT_LINE_LIMIT:])


def run_failing(command, root):
    result = subprocess.run(command, cwd=root, capture_output=True, text=True)
    if result.returncode == 0:
        return None
    return f"$ {' '.join(command)}\n{last_lines(result.stdout + result.stderr)}"


def base_branch(root):
    for branch in BASE_BRANCHES:
        if subprocess.run(["git", "-C", str(root), "rev-parse", "--verify", "-q", branch], capture_output=True).returncode == 0:
            return branch
    return None


def fallow_command(base, file):
    analysis = ["audit", "--base", base] if base else ["--fail-on-issues"]
    return ["npx", "--yes", "fallow", *analysis, "--format", "json", file]


def fallow_commands(root, files):
    base = base_branch(root)
    return [fallow_command(base, file)
            for file in files if JS_FILE.search(file) and (root / file).is_file()]


def fallow_failures(root, files):
    if not any((root / marker).exists() for marker in JS_PROJECT_MARKERS):
        return []
    failures = [run_failing(command, root) for command in fallow_commands(root, files)]
    failures = [failure for failure in failures if failure]
    return [FALLOW_ADVICE] + failures if failures else []


def makefile_has_test_target(root):
    makefile = root / "Makefile"
    return makefile.is_file() and re.search(r"^test\s*:", makefile.read_text(), re.MULTILINE) is not None


def package_json_has_test_script(root):
    package = root / "package.json"
    if not package.is_file():
        return False
    try:
        return "test" in json.loads(package.read_text()).get("scripts", {})
    except ValueError:
        return False


def discovered_test_command(root):
    if makefile_has_test_target(root):
        return ["make", "test"]
    if (root / "go.mod").is_file():
        return ["go", "test", "./..."]
    if package_json_has_test_script(root):
        return ["pnpm", "test"]
    return None


def test_command(root, files):
    script = root / VERIFY_SCRIPT
    if script.is_file():
        return [str(script), *files]
    if (root / OPT_OUT_FILE).exists():
        return None
    return discovered_test_command(root)


def verify_failures(root, files):
    command = test_command(root, files)
    if command is None:
        return []
    failure = run_failing(command, root)
    return [failure] if failure else []


def verify_edits(event):
    root = project_root(event.get("cwd", "."))
    files = edited_files(event, root)
    if not files:
        return
    failures = fallow_failures(root, files) + verify_failures(root, files)
    if failures:
        print("Not done yet: fix these, then finish.\n\n" + "\n\n".join(failures), file=sys.stderr)
        sys.exit(2)
    edits_log(event).unlink(missing_ok=True)


def main():
    event = json.load(sys.stdin)
    if event.get("hook_event_name") == "PostToolUse":
        record_edit(event)
    elif not event.get("stop_hook_active"):
        verify_edits(event)


main()
