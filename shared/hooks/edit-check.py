#!/usr/bin/env python3
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import time
import tokenize
from collections import Counter
from pathlib import Path

OUTPUT_LINE_LIMIT = 40
CACHE_DIR = Path(os.environ.get("EDIT_CHECK_CACHE_DIR") or Path.home() / ".cache" / "claude-custom" / "edit-check")
CACHE_MAX_FILES = 500
CACHE_MAX_AGE_SECONDS = 7 * 24 * 60 * 60
EXTENSION_LANGUAGES = {
    ".go": "go",
    ".ts": "js", ".tsx": "js", ".js": "js", ".jsx": "js", ".mjs": "js", ".cjs": "js",
    ".py": "python",
    ".sh": "shell", ".bash": "shell",
}
SHELL_SHEBANGS = ("#!/bin/sh", "#!/bin/bash", "#!/usr/bin/env bash", "#!/usr/bin/env sh")
PYTHON_SHEBANGS = ("#!/usr/bin/env python", "#!/usr/bin/python")
COMMENT_MARKERS = {"go": ("//", "/*"), "js": ("//", "/*"), "python": ("#",), "shell": ("#",)}
ALLOWED_DIRECTIVES = ("#!", "//go:", "/// <reference")
QUOTES = "'\"`"
ESLINT_CONFIGS = ("eslint.config.js", "eslint.config.mjs", "eslint.config.cjs", "eslint.config.ts",
                  ".eslintrc", ".eslintrc.js", ".eslintrc.cjs", ".eslintrc.json", ".eslintrc.yml")


def shebang_language(first_line):
    if first_line.startswith(SHELL_SHEBANGS):
        return "shell"
    if first_line.startswith(PYTHON_SHEBANGS):
        return "python"
    return None


def language_of(path):
    if path.suffix in EXTENSION_LANGUAGES:
        return EXTENSION_LANGUAGES[path.suffix]
    if path.suffix == "" and path.is_file():
        with path.open(errors="ignore") as file:
            return shebang_language(file.readline())
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


def content_key(path):
    digest = hashlib.sha1(path.read_bytes()).hexdigest()
    return CACHE_DIR / f"{digest}-{path.name}"


def already_passed(path):
    return path.is_file() and content_key(path).exists()


def prune_cache():
    entries = list(CACHE_DIR.iterdir())
    if len(entries) <= CACHE_MAX_FILES:
        return
    cutoff = time.time() - CACHE_MAX_AGE_SECONDS
    for entry in entries:
        if entry.stat().st_mtime < cutoff:
            entry.unlink(missing_ok=True)


def remember_pass(path):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    content_key(path).touch()
    prune_cache()


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


def starts_comment(line, index, markers):
    at_word_start = index == 0 or line[index - 1].isspace()
    return at_word_start and line.startswith(markers, index)


def line_comment(line, markers):
    quote = None
    index = 0
    while index < len(line):
        char = line[index]
        if char == "\\":
            index += 2
            continue
        if quote:
            quote = None if char == quote else quote
        elif char in QUOTES:
            quote = char
        elif starts_comment(line, index, markers):
            return line[index:].strip()
        index += 1
    return None


def scanned_comments(text, markers):
    comments = (line_comment(line, markers) for line in text.splitlines())
    return [comment for comment in comments if comment]


def python_comments(text):
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, SyntaxError):
        return scanned_comments(text, COMMENT_MARKERS["python"])
    return [token.string.strip() for token in tokens if token.type == tokenize.COMMENT]


def comments_in(text, language):
    if language == "python":
        found = python_comments(text)
    else:
        found = scanned_comments(text, COMMENT_MARKERS[language])
    return [comment for comment in found if not comment.startswith(ALLOWED_DIRECTIVES)]


def new_comments(before, after, language):
    return list((Counter(comments_in(after, language)) - Counter(comments_in(before, language))).elements())


def edits_of(tool_input):
    if "edits" in tool_input:
        return tool_input["edits"]
    if "new_string" in tool_input:
        return [tool_input]
    return None


def reverted(text, edit):
    new = edit.get("new_string", "")
    if not new:
        return text
    return text.replace(new, edit.get("old_string", ""), -1 if edit.get("replace_all") else 1)


def text_before(after, edits):
    for edit in reversed(edits):
        after = reverted(after, edit)
    return after


def is_applied(after, edits):
    return all(edit.get("new_string", "") in after for edit in edits)


def written_pairs(path, tool_input):
    edits = edits_of(tool_input)
    if edits is None:
        return [(committed_text(path), tool_input.get("content", ""))]
    after = path.read_text(errors="ignore") if path.is_file() else ""
    if after and is_applied(after, edits):
        return [(text_before(after, edits), after)]
    return [(edit.get("old_string", ""), edit.get("new_string", "")) for edit in edits]


def added_comments(path, tool_input, language):
    comments = []
    for before, after in written_pairs(path, tool_input):
        comments += new_comments(before, after, language)
    return comments


def comment_failure(comments):
    if not comments:
        return None
    listed = "\n".join(comments[:OUTPUT_LINE_LIMIT])
    return ("New comments are not allowed (this includes lint suppressions). "
            "Rename or restructure the code so it explains itself, then remove:\n" + listed)


def failures_for(path, tool_input, language):
    failures = [comment_failure(added_comments(path, tool_input, language))]
    if path.is_file() and not already_passed(path):
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
    if path.is_file():
        remember_pass(path)


main()
