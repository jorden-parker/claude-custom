#!/usr/bin/env python3
import argparse
import json
import os
import re
import socketserver
import subprocess
import tempfile
import threading
import time
from pathlib import Path

COMMAND_TIMEOUT_SECONDS = 120
DEFAULT_LIMIT = 20
MAX_LIMIT = 100
MAX_TEXT_LENGTH = 256
SEARCH_QUALIFIER = re.compile(r"([A-Za-z_-]*):")
ALLOWED_QUALIFIERS = {
    "is",
    "in",
    "label",
    "author",
    "assignee",
    "mentions",
    "commenter",
    "involves",
    "state",
    "status",
    "created",
    "updated",
    "closed",
    "merged",
    "base",
    "head",
    "milestone",
    "no",
    "draft",
    "review",
    "reviewed-by",
    "review-requested",
    "type",
    "linked",
    "comments",
    "reactions",
    "sort",
}
GITHUB_LOGIN = re.compile(r"@me|[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})")
REPOSITORY = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_][A-Za-z0-9._-]{0,99}")
BRANCH = re.compile(r"[A-Za-z0-9_][A-Za-z0-9._/-]{0,254}")
PR_FIELDS = "number,title,author,headRefName,isDraft,updatedAt"
PR_VIEW_FIELDS = (
    "number,title,body,state,author,headRefName,baseRefName,url,isDraft,reviewDecision,labels,files,comments,reviews"
)
PR_VIEW_FIELD_CHOICES = {
    *PR_VIEW_FIELDS.split(","),
    "commits",
    "headRefOid",
    "baseRefOid",
    "additions",
    "deletions",
    "changedFiles",
    "createdAt",
    "updatedAt",
    "mergedAt",
    "closed",
    "assignees",
    "reviewRequests",
    "milestone",
}
PR_CHECK_FIELDS = "name,state,bucket,workflow,link"
PR_CHECK_FIELD_CHOICES = {*PR_CHECK_FIELDS.split(","), "description", "event", "startedAt", "completedAt"}
ISSUE_FIELDS = "number,title,state,author,labels,updatedAt"
ISSUE_VIEW_FIELDS = "number,title,body,state,author,labels,url,comments"
ISSUE_VIEW_FIELD_CHOICES = {*ISSUE_VIEW_FIELDS.split(","), "createdAt", "updatedAt", "closedAt", "assignees", "milestone"}
RUN_FIELDS = "databaseId,displayTitle,workflowName,headBranch,status,conclusion,createdAt"
RUN_VIEW_FIELDS = "databaseId,displayTitle,workflowName,headBranch,status,conclusion,url,jobs"
RUN_VIEW_FIELD_CHOICES = {*RUN_VIEW_FIELDS.split(","), "createdAt", "updatedAt", "event", "headSha"}


class Refused(Exception):
    pass


class Arguments:
    def __init__(self, values, allowed):
        if not isinstance(values, dict):
            raise Refused("arguments must be an object")
        unknown = set(values) - set(allowed) - {"repo"}
        if unknown:
            raise Refused(f"unknown arguments: {', '.join(sorted(unknown))}")
        self.values = values

    def number(self, name, default=None, maximum=None):
        value = self.values.get(name, default)
        if value is None:
            raise Refused(f"{name} is required")
        if isinstance(value, bool) or not isinstance(value, int) or value < 1:
            raise Refused(f"{name} must be a positive whole number")
        if maximum is not None and value > maximum:
            raise Refused(f"{name} must be at most {maximum}")
        return str(value)

    def limit(self):
        return self.number("limit", DEFAULT_LIMIT, MAX_LIMIT)

    def choice(self, name, options):
        value = self.values.get(name, options[0])
        if value not in options:
            raise Refused(f"{name} must be one of {', '.join(options)}")
        return value

    def switch(self, name):
        value = self.values.get(name, False)
        if not isinstance(value, bool):
            raise Refused(f"{name} must be true or false")
        return value

    def text(self, name):
        value = self.values.get(name)
        if value is not None and (not isinstance(value, str) or len(value) > MAX_TEXT_LENGTH):
            raise Refused(f"{name} must be text of at most {MAX_TEXT_LENGTH} characters")
        return value

    def text_flag(self, name, flag):
        value = self.text(name)
        return [] if value is None else [f"{flag}={value}"]

    def search_flag(self):
        value = self.text("search")
        if value is None:
            return []
        for qualifier in SEARCH_QUALIFIER.findall(value):
            if qualifier.lstrip("-").lower() not in ALLOWED_QUALIFIERS:
                allowed = ", ".join(sorted(ALLOWED_QUALIFIERS))
                raise Refused(f"search can't use the {qualifier}: qualifier; allowed: {allowed}")
        return [f"--search={value}"]

    def fields(self, default, choices):
        value = self.text("fields")
        if value is None:
            return default
        names = value.split(",")
        if not all(name in choices for name in names):
            raise Refused(f"fields must be a comma-separated list from: {', '.join(sorted(choices))}")
        return value

    def pull_request(self):
        branch = self.text("branch")
        if branch is None:
            return self.number("number")
        if "number" in self.values:
            raise Refused("give either number or branch, not both")
        if not BRANCH.fullmatch(branch):
            raise Refused("branch must be a branch name")
        return branch

    def author_flag(self):
        value = self.text("author")
        if value is None:
            return []
        if not GITHUB_LOGIN.fullmatch(value):
            raise Refused("author must be a GitHub login or @me")
        return [f"--author={value}"]


def pr_list(values):
    args = Arguments(values, {"state", "limit", "author", "search"})
    state = args.choice("state", ("open", "closed", "merged", "all"))
    return [
        *["pr", "list", "--state", state, "--limit", args.limit(), "--json", PR_FIELDS],
        *args.author_flag(),
        *args.search_flag(),
    ]


def pr_view(values):
    args = Arguments(values, {"number", "fields"})
    return ["pr", "view", args.number("number"), "--json", args.fields(PR_VIEW_FIELDS, PR_VIEW_FIELD_CHOICES)]


def pr_diff(values):
    args = Arguments(values, {"number", "branch", "name_only"})
    return ["pr", "diff", args.pull_request(), *(["--name-only"] if args.switch("name_only") else [])]


def pr_checks(values):
    args = Arguments(values, {"number", "fields"})
    return ["pr", "checks", args.number("number"), "--json", args.fields(PR_CHECK_FIELDS, PR_CHECK_FIELD_CHOICES)]


def pr_review_comments(values):
    number = Arguments(values, {"number"}).number("number")
    return ["api", f"repos/{{owner}}/{{repo}}/pulls/{number}/comments", "--paginate"]


def issue_list(values):
    args = Arguments(values, {"state", "limit", "search"})
    state = args.choice("state", ("open", "closed", "all"))
    return [
        *["issue", "list", "--state", state, "--limit", args.limit(), "--json", ISSUE_FIELDS],
        *args.search_flag(),
    ]


def issue_view(values):
    args = Arguments(values, {"number", "fields"})
    return ["issue", "view", args.number("number"), "--json", args.fields(ISSUE_VIEW_FIELDS, ISSUE_VIEW_FIELD_CHOICES)]


def run_list(values):
    args = Arguments(values, {"limit", "branch"})
    return ["run", "list", "--limit", args.limit(), "--json", RUN_FIELDS, *args.text_flag("branch", "--branch")]


def run_view(values):
    args = Arguments(values, {"run_id", "failed_logs", "fields"})
    run_id = args.number("run_id")
    if args.switch("failed_logs"):
        return ["run", "view", run_id, "--log-failed"]
    return ["run", "view", run_id, "--json", args.fields(RUN_VIEW_FIELDS, RUN_VIEW_FIELD_CHOICES)]


TOOLS = {
    "pr_list": pr_list,
    "pr_view": pr_view,
    "pr_diff": pr_diff,
    "pr_checks": pr_checks,
    "pr_review_comments": pr_review_comments,
    "issue_list": issue_list,
    "issue_view": issue_view,
    "run_list": run_list,
    "run_view": run_view,
}


def gh_args(request):
    if not isinstance(request, dict):
        raise Refused("malformed request")
    build = TOOLS.get(request.get("tool"))
    if build is None:
        raise Refused(f"{request.get('tool')} is not a GitHub tool this session can use")
    return build(request.get("arguments", {}))


def repository_allowed(repository, patterns):
    owner = repository.split("/")[0]
    return any(pattern.lower() in (repository.lower(), f"{owner.lower()}/*") for pattern in patterns)


class Broker:
    def __init__(self, gh, repo, workdir, allowed_repos=()):
        self.gh = gh
        self.repo = repo
        self.allowed_repos = (repo, *allowed_repos) if repo else tuple(allowed_repos)
        self.workdir = workdir
        config_dir = Path(workdir, "gh-config")
        config_dir.mkdir()
        self.env = {
            **os.environ,
            "GH_HOST": "github.com",
            "GH_CONFIG_DIR": str(config_dir),
            "GH_PROMPT_DISABLED": "1",
            "GH_PAGER": "cat",
            "GH_NO_UPDATE_NOTIFIER": "1",
        }
        self.env.pop("GITHUB_TOKEN", None)

    def repository_for(self, request):
        arguments = request.get("arguments") if isinstance(request, dict) else None
        named = arguments.get("repo") if isinstance(arguments, dict) else None
        if named is None:
            if not self.repo:
                raise Refused("this project has no GitHub origin, so name a repo")
            return self.repo
        if not isinstance(named, str) or not REPOSITORY.fullmatch(named):
            raise Refused("repo must be owner/name")
        if not repository_allowed(named, self.allowed_repos):
            raise Refused(f"{named} is not on this machine's gh-repos list (~/.config/claude-custom/gh-repos)")
        return named

    def handle(self, request):
        repository = self.repository_for(request)
        return reply_from(
            subprocess.run(
                [self.gh, *gh_args(request)],
                capture_output=True,
                text=True,
                cwd=self.workdir,
                env={**self.env, "GH_REPO": repository},
                stdin=subprocess.DEVNULL,
                timeout=COMMAND_TIMEOUT_SECONDS,
                check=False,
            )
        )


def reply_from(completed):
    return {"exit": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr}


def refusal(reason):
    return {"exit": 1, "stdout": "", "stderr": f"gh broker: {reason}\n"}


def answer(broker, line):
    try:
        return broker.handle(json.loads(line))
    except Refused as reason:
        return refusal(str(reason))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return refusal("malformed request")
    except subprocess.TimeoutExpired:
        return refusal("gh timed out")


def serve(broker, socket_path):
    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            reply = answer(broker, self.rfile.readline())
            self.wfile.write(json.dumps(reply).encode() + b"\n")

    Path(socket_path).unlink(missing_ok=True)
    os.umask(0o077)
    return socketserver.ThreadingUnixStreamServer(socket_path, Handler)


def process_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def exit_when_gone(pid, socket_path):
    while process_alive(pid):
        time.sleep(0.5)
    Path(socket_path).unlink(missing_ok=True)
    os._exit(0)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", required=True)
    parser.add_argument("--gh", required=True)
    parser.add_argument("--repo", default="")
    parser.add_argument("--allow-repo", action="append", default=[])
    parser.add_argument("--watch-pid", type=int, required=True)
    options = parser.parse_args()
    with tempfile.TemporaryDirectory() as workdir:
        server = serve(Broker(options.gh, options.repo, workdir, options.allow_repo), options.socket)
        threading.Thread(target=exit_when_gone, args=(options.watch_pid, options.socket), daemon=True).start()
        server.serve_forever()


if __name__ == "__main__":
    main()
