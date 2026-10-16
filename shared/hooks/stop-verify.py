#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

OUTPUT_LINE_LIMIT = 40
JS_PROJECT_MARKERS = ("package.json", "tsconfig.json")
BASE_BRANCHES = ("main", "master")
FALLOW_ADVICE = ("Fallow found problems in your changes. Run `npx fallow explain <issue-type>` for any "
                 "finding you don't understand. Remove dead code instead of suppressing it.")
VERIFY_SCRIPT = Path(".claude") / "verify"


def project_root(cwd):
    result = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return Path(result.stdout.strip() if result.returncode == 0 else cwd)


def last_lines(text):
    return "\n".join(text.strip().splitlines()[-OUTPUT_LINE_LIMIT:])


def run_failing(command, root):
    result = subprocess.run(command, cwd=root, capture_output=True, text=True)
    if result.returncode == 0:
        return None
    return f"$ {' '.join(command)}\n{last_lines(result.stdout + result.stderr)}"


def base_branch_args(root):
    for branch in BASE_BRANCHES:
        if subprocess.run(["git", "-C", str(root), "rev-parse", "--verify", "-q", branch], capture_output=True).returncode == 0:
            return ["--base", branch]
    return []


def fallow_commands(root):
    return (
        ["npx", "--yes", "fallow", "audit", *base_branch_args(root), "--format", "json"],
        ["npx", "--yes", "fallow", "architecture", "--format", "json"],
    )


def fallow_failures(root):
    if not any((root / marker).exists() for marker in JS_PROJECT_MARKERS):
        return []
    failures = [run_failing(command, root) for command in fallow_commands(root)]
    failures = [failure for failure in failures if failure]
    return [FALLOW_ADVICE] + failures if failures else []


def verify_failures(root):
    script = root / VERIFY_SCRIPT
    if not script.is_file():
        return []
    failure = run_failing([str(script)], root)
    return [failure] if failure else []


def main():
    event = json.load(sys.stdin)
    if event.get("stop_hook_active"):
        return
    root = project_root(event.get("cwd", "."))
    failures = fallow_failures(root) + verify_failures(root)
    if failures:
        print("Not done yet: fix these, then finish.\n\n" + "\n\n".join(failures), file=sys.stderr)
        sys.exit(2)


main()
