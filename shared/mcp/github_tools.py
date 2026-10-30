import os
import re
import subprocess
import tempfile
from pathlib import Path

DEFAULT_LIMIT = 20
MAX_LIMIT = 100
MAX_TEXT_LENGTH = 256
GH_TIMEOUT_SECONDS = 120
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
COMMENT_PREFIX = "#"
REPOSITORY = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_][A-Za-z0-9._-]{0,99}")
BRANCH = re.compile(r"[A-Za-z0-9_][A-Za-z0-9._/-]{0,254}")
ORIGIN_FORMS = (
    re.compile(r"^https://github\.com/([^/]+/[^/]+?)(?:\.git)?/?$"),
    re.compile(r"^git@github\.com:([^/]+/[^/]+?)(?:\.git)?$"),
)
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
GH_ENV = {"GH_HOST": "github.com", "GH_PROMPT_DISABLED": "1", "GH_PAGER": "cat", "GH_NO_UPDATE_NOTIFIER": "1"}


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


READ_TOOLS = {
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


def gh_args(name, arguments):
    build = READ_TOOLS.get(name)
    if build is None:
        raise Refused(f"{name} is not a GitHub tool this session can use")
    return build(arguments if isinstance(arguments, dict) else {})


def origin_repository(remote_url):
    for form in ORIGIN_FORMS:
        match = form.match(remote_url.strip())
        if match:
            return match.group(1)
    return None


def gh_repos_path():
    config_home = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(config_home) / "claude-custom" / "gh-repos"


def listed_repositories(path):
    try:
        lines = path.read_text().splitlines()
    except (OSError, ValueError):
        return set()
    names = (line.strip() for line in lines)
    return {name.lower() for name in names if name and not name.startswith(COMMENT_PREFIX) and REPOSITORY.fullmatch(name)}


def allowed_repositories(origin, path):
    allowed = listed_repositories(path)
    if origin is not None:
        allowed.add(origin.lower())
    return allowed


def repository_for(arguments, origin):
    path = gh_repos_path()
    repository = arguments.get("repo") if isinstance(arguments, dict) else None
    if repository is None:
        if origin is None:
            raise Refused(f"no GitHub origin; pass repo as owner/name listed in {path}")
        return origin
    if not isinstance(repository, str) or not REPOSITORY.fullmatch(repository):
        raise Refused("repo must be owner/name")
    if repository.lower() not in allowed_repositories(origin, path):
        raise Refused(f"repo {repository} is not this project's origin or a line of {path}")
    return repository


def run_gh(name, arguments, origin):
    argv = gh_args(name, arguments)
    repository = repository_for(arguments, origin)
    with tempfile.TemporaryDirectory(prefix="claude-ollama-gh-") as workdir:
        return subprocess.run(
            ["gh", *argv],
            cwd=workdir,
            env={**os.environ, **GH_ENV, "GH_REPO": repository},
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=GH_TIMEOUT_SECONDS,
            check=False,
        )
