#!/usr/bin/env python3
import json
import os
import socket
import subprocess
from pathlib import PurePath

from mcp_stdio import serve, tool_result

GIT_TIMEOUT_SECONDS = 60
BROKER_TIMEOUT_SECONDS = 150
MAX_OUTPUT_CHARS = 20000
DEFAULT_LOG_LIMIT = 20
MAX_LOG_LIMIT = 100
MAX_PATHS = 50
GIT = ["git", "--no-pager", "-c", "color.ui=false", "-c", "core.fsmonitor=false"]
NO_DIFF_PROGRAMS = ["--no-ext-diff", "--no-textconv"]
OUTSIDE_REPOSITORY = "paths must stay inside the repository"
BROKER_MISSING = "the GitHub broker is not running; run claude-ollama github-token read, then relaunch"


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


LIMIT = number_property("How many (default 20, max 100)")
PR_NUMBER = {"number": number_property("Pull request number")}
GIT_TOOLS = [
    tool("git_status", "Current branch and changed files (git status --short --branch)."),
    tool(
        "git_diff",
        "Uncommitted changes, or staged ones, or the tree against a base revision.",
        {
            "staged": switch_property("Only staged changes"),
            "base": text_property("Compare against this revision, e.g. main or HEAD~3"),
            "paths": {"type": "array", "items": {"type": "string"}, "description": "Only these paths"},
            "stat": switch_property("Only a per-file summary"),
        },
    ),
    tool(
        "git_log",
        "Commits, newest first, one line each: hash, date, author, subject.",
        {
            "limit": LIMIT,
            "rev": text_property("Revision or range to start from, e.g. main..HEAD"),
            "path": text_property("Only commits touching this path"),
        },
    ),
    tool(
        "git_show",
        "One commit: its message and diff.",
        {"rev": text_property("Commit, e.g. HEAD or a hash"), "stat": switch_property("Only a per-file summary")},
        ["rev"],
    ),
]
GITHUB_TOOLS = [
    tool(
        "pr_list",
        "This repo's GitHub pull requests, as JSON.",
        {
            "state": {"type": "string", "enum": ["open", "closed", "merged", "all"]},
            "limit": LIMIT,
            "author": text_property("Login, or @me"),
            "search": text_property("GitHub search, e.g. 'fix in:title'"),
        },
    ),
    tool("pr_view", "One pull request with its files, comments and reviews, as JSON.", PR_NUMBER, ["number"]),
    tool(
        "pr_diff",
        "A pull request's diff.",
        {**PR_NUMBER, "name_only": switch_property("Only the changed file names")},
        ["number"],
    ),
    tool("pr_checks", "A pull request's CI checks, as JSON.", PR_NUMBER, ["number"]),
    tool(
        "issue_list",
        "This repo's GitHub issues, as JSON.",
        {"state": {"type": "string", "enum": ["open", "closed", "all"]}, "limit": LIMIT, "search": text_property("GitHub search")},
    ),
    tool("issue_view", "One issue with its comments, as JSON.", {"number": number_property("Issue number")}, ["number"]),
    tool("run_list", "Recent GitHub Actions runs, as JSON.", {"limit": LIMIT, "branch": text_property("Only this branch")}),
    tool(
        "run_view",
        "One Actions run and its jobs, as JSON.",
        {
            "run_id": number_property("Run ID (databaseId from run_list)"),
            "failed_logs": switch_property("Return the failed steps' logs instead"),
        },
        ["run_id"],
    ),
]
GITHUB_TOOL_NAMES = {github_tool["name"] for github_tool in GITHUB_TOOLS}


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

    def required_text(self, name):
        value = self.text(name)
        if not value:
            raise ToolError(f"{name} is required")
        return value

    def paths(self):
        value = self.values.get("paths", [])
        if not isinstance(value, list) or len(value) > MAX_PATHS or not all(isinstance(path, str) for path in value):
            raise ToolError(f"paths must be a list of at most {MAX_PATHS} paths")
        return [inside_repository(path) for path in value]

    def path(self):
        value = self.text("path")
        return [inside_repository(value)] if value else []

    def limit(self):
        value = self.values.get("limit", DEFAULT_LOG_LIMIT)
        if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= MAX_LOG_LIMIT:
            raise ToolError(f"limit must be a whole number from 1 to {MAX_LOG_LIMIT}")
        return value


def inside_repository(path):
    if PurePath(path).is_absolute() or ".." in PurePath(path).parts:
        raise ToolError(OUTSIDE_REPOSITORY)
    return path


def revision(rev):
    return ["--end-of-options", rev] if rev else []


def git_status(values):
    Arguments(values, set())
    return ["status", "--short", "--branch"]


def git_diff(values):
    args = Arguments(values, {"staged", "base", "paths", "stat"})
    staged = ["--staged"] if args.switch("staged") else []
    stat = ["--stat"] if args.switch("stat") else []
    return ["diff", *NO_DIFF_PROGRAMS, *staged, *stat, *revision(args.text("base")), "--", *args.paths()]


def git_log(values):
    args = Arguments(values, {"limit", "rev", "path"})
    command = ["log", f"--max-count={args.limit()}", "--format=%h %ad %an %s", "--date=short"]
    return [*command, *revision(args.text("rev")), "--", *args.path()]


def git_show(values):
    args = Arguments(values, {"rev", "stat"})
    stat = ["--stat"] if args.switch("stat") else []
    return ["show", *NO_DIFF_PROGRAMS, *stat, *revision(args.required_text("rev"))]


GIT_COMMANDS = {"git_status": git_status, "git_diff": git_diff, "git_log": git_log, "git_show": git_show}


def pinned_repository_env():
    located = subprocess.run(
        ["git", "rev-parse", "--show-toplevel", "--absolute-git-dir"], capture_output=True, text=True
    )
    if located.returncode != 0:
        return None
    work_tree, git_dir = located.stdout.splitlines()
    return {**os.environ, "GIT_DIR": git_dir, "GIT_WORK_TREE": work_tree}


PINNED_REPOSITORY_ENV = pinned_repository_env()


def run_git(command):
    if PINNED_REPOSITORY_ENV is None:
        raise ToolError("the session did not start inside a git repository")
    try:
        completed = subprocess.run(
            [*GIT, *command],
            capture_output=True,
            text=True,
            stdin=subprocess.DEVNULL,
            env=PINNED_REPOSITORY_ENV,
            timeout=GIT_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        raise ToolError("git timed out") from None
    if completed.returncode != 0:
        raise ToolError(completed.stderr.strip() or f"git exited with {completed.returncode}")
    return completed.stdout


def ask_broker(name, arguments):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(BROKER_TIMEOUT_SECONDS)
        try:
            connection.connect(os.environ.get("CLAUDE_OLLAMA_GH_BROKER", ""))
        except OSError:
            raise ToolError(BROKER_MISSING) from None
        connection.sendall(json.dumps({"tool": name, "arguments": arguments}).encode() + b"\n")
        with connection.makefile("rb") as replies:
            reply = json.loads(replies.readline())
    if reply.get("exit") != 0 and not reply.get("stdout", "").strip():
        raise ToolError(reply.get("stderr", "").strip() or "gh failed")
    return reply.get("stdout", "") + reply.get("stderr", "")


def run_tool(name, arguments):
    if name in GIT_COMMANDS:
        return run_git(GIT_COMMANDS[name](arguments))
    if name in GITHUB_TOOL_NAMES:
        return ask_broker(name, arguments)
    raise ToolError(f"unknown tool: {name}")


def truncated(text):
    if not text.strip():
        return "(no output)"
    if len(text) <= MAX_OUTPUT_CHARS:
        return text
    note = f"\n[truncated: showed {MAX_OUTPUT_CHARS} of {len(text)} characters; narrow it with paths, stat or name_only]"
    return text[:MAX_OUTPUT_CHARS] + note


def call_tool(params):
    try:
        return tool_result(truncated(run_tool(params.get("name"), params.get("arguments") or {})))
    except ToolError as error:
        return tool_result(str(error), True)


def list_tools():
    return GIT_TOOLS + (GITHUB_TOOLS if os.environ.get("CLAUDE_OLLAMA_GH_BROKER") else [])


serve("repo", list_tools, call_tool)
