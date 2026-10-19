#!/usr/bin/env python3
import json
import shutil
import subprocess
import sys
from pathlib import Path

OUTPUT_LINE_LIMIT = 40
EXTENSION_LANGUAGES = {
    ".go": "go",
    ".ts": "js", ".tsx": "js", ".js": "js", ".jsx": "js", ".mjs": "js", ".cjs": "js",
    ".py": "python",
    ".sh": "shell", ".bash": "shell",
}
SHELL_SHEBANGS = ("#!/bin/sh", "#!/bin/bash", "#!/usr/bin/env bash", "#!/usr/bin/env sh")
COMMENT_MARKERS = {"go": ("//", "/*"), "js": ("//", "/*"), "python": ("#",), "shell": ("#",)}
ALLOWED_DIRECTIVES = ("#!", "//go:", "/// <reference")
ESLINT_CONFIGS = ("eslint.config.js", "eslint.config.mjs", "eslint.config.cjs", "eslint.config.ts",
                  ".eslintrc", ".eslintrc.js", ".eslintrc.cjs", ".eslintrc.json", ".eslintrc.yml")


def language_of(path):
    if path.suffix in EXTENSION_LANGUAGES:
        return EXTENSION_LANGUAGES[path.suffix]
    if path.suffix == "" and path.is_file():
        with path.open(errors="ignore") as file:
            if file.readline().startswith(SHELL_SHEBANGS):
                return "shell"
    return None


def nearest_dir_with(path, marker):
    for directory in path.parents:
        if (directory / marker).exists():
            return directory
    return None


def on_path(tool):
    return shutil.which(tool) is not None


def go_checks(path):
    checks = []
    if on_path("gofmt"):
        checks.append((["gofmt", "-l", str(path)], path.parent, True))
    if on_path("go") and nearest_dir_with(path, "go.mod"):
        checks.append((["go", "vet", "."], path.parent, False))
    return checks


def js_checks(path):
    root = nearest_dir_with(path, "package.json")
    if root is None:
        return []
    bin_dir = root / "node_modules" / ".bin"
    checks = []
    if (bin_dir / "prettier").exists():
        checks.append(([str(bin_dir / "prettier"), "--check", str(path)], root, False))
    if (bin_dir / "eslint").exists() and any((root / name).exists() for name in ESLINT_CONFIGS):
        checks.append(([str(bin_dir / "eslint"), str(path)], root, False))
    return checks


def python_checks(path):
    if not on_path("ruff"):
        return []
    return [
        (["ruff", "format", "--check", str(path)], path.parent, False),
        (["ruff", "check", str(path)], path.parent, False),
    ]


def shell_checks(path):
    checks = [(["/bin/bash", "-n", str(path)], path.parent, False)]
    if on_path("shellcheck"):
        checks.append((["shellcheck", str(path)], path.parent, False))
    return checks


LANGUAGE_CHECKS = {"go": go_checks, "js": js_checks, "python": python_checks, "shell": shell_checks}


def first_lines(text):
    return "\n".join(text.strip().splitlines()[:OUTPUT_LINE_LIMIT])


def run_check(command, cwd, output_means_failure):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    failed = result.returncode != 0 or (output_means_failure and output)
    if not failed:
        return None
    tool = Path(command[0]).name
    return f"{tool}: $ {' '.join(command)}\n{first_lines(output)}"


def committed_text(path):
    result = subprocess.run(
        ["git", "-C", str(path.parent), "show", f"HEAD:./{path.name}"],
        capture_output=True, text=True,
    )
    return result.stdout if result.returncode == 0 else ""


def written_pairs(path, tool_input):
    if "edits" in tool_input:
        return [(edit.get("old_string", ""), edit.get("new_string", "")) for edit in tool_input["edits"]]
    if "new_string" in tool_input:
        return [(tool_input.get("old_string", ""), tool_input["new_string"])]
    return [(committed_text(path), tool_input.get("content", ""))]


def is_comment(line, markers):
    return line.startswith(markers) and not line.startswith(ALLOWED_DIRECTIVES)


def added_comments(path, tool_input, language):
    markers = COMMENT_MARKERS[language]
    comments = []
    for old, new in written_pairs(path, tool_input):
        existing = {line.strip() for line in old.splitlines()}
        comments += [line.strip() for line in new.splitlines()
                     if is_comment(line.strip(), markers) and line.strip() not in existing]
    return comments


def comment_failure(comments):
    if not comments:
        return None
    listed = "\n".join(comments[:OUTPUT_LINE_LIMIT])
    return ("New comments are not allowed (this includes lint suppressions). "
            "Rename or restructure the code so it explains itself, then remove:\n" + listed)


def failures_for(path, tool_input, language):
    failures = [comment_failure(added_comments(path, tool_input, language))]
    if path.is_file():
        failures += [run_check(*check) for check in LANGUAGE_CHECKS[language](path)]
    return [failure for failure in failures if failure]


def main():
    tool_input = json.load(sys.stdin).get("tool_input", {})
    path = Path(tool_input.get("file_path", "")).resolve()
    language = language_of(path)
    if language is None:
        return
    failures = failures_for(path, tool_input, language)
    if failures:
        print(f"Checks failed for {path}. Fix them before moving on.\n\n" + "\n\n".join(failures), file=sys.stderr)
        sys.exit(2)


main()
