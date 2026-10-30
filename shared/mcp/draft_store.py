import json
import os
import re
import tempfile
import time
from pathlib import Path, PurePath

DRAFT_ID = re.compile(r"^\d{8}-\d{6}-(pr|review)-[a-z0-9-]{1,60}$")
LABELS = ("issue", "suggestion", "question", "nitpick", "praise", "todo", "chore", "thought")
DECORATIONS = ("blocking", "non-blocking", "if-minor", "security", "test")
EVENTS = ("COMMENT", "REQUEST_CHANGES", "APPROVE")
MAX_TITLE_CHARS = 256
MAX_HEADING_CHARS = 200
MAX_BODY_CHARS = 20000
MAX_ITEMS = 30
BRANCH_NAME = re.compile(r"^[A-Za-z0-9._/][A-Za-z0-9._/-]{0,199}$")
OUTSIDE_REPOSITORY = "paths must stay inside the repository"


class DraftRefused(Exception):
    pass


def text_property(description):
    return {"type": "string", "description": description}


SECTION = {
    "type": "object",
    "properties": {
        "heading": text_property("The template heading, without #"),
        "body": text_property("Markdown for this section"),
    },
    "required": ["heading", "body"],
}
COMMENT = {
    "type": "object",
    "properties": {
        "label": {"type": "string", "enum": list(LABELS)},
        "decorations": {"type": "array", "items": {"type": "string", "enum": list(DECORATIONS)}},
        "path": text_property("File the comment is about, relative to the repo root"),
        "line": {"type": "integer", "description": "Line in the PR's new version of path"},
        "body": text_property("Markdown: what and why"),
    },
    "required": ["label", "body"],
}
DRAFT_TOOLS = [
    {
        "name": "draft_pr",
        "description": "Save a pull request draft from the current branch for the user to edit and post in the console.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "title": text_property("One-line PR title"),
                "base": text_property("Branch to merge into, e.g. main"),
                "sections": {"type": "array", "items": SECTION, "description": "One per template heading, in order"},
            },
            "required": ["title", "base", "sections"],
        },
    },
    {
        "name": "draft_review",
        "description": "Save a review draft in Conventional Comments for the user to edit and post in the console.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "pr": {"type": "integer", "description": "Pull request number"},
                "event": {"type": "string", "enum": list(EVENTS)},
                "summary": text_property("Markdown overview of the review"),
                "comments": {"type": "array", "items": COMMENT},
            },
            "required": ["pr", "event", "summary", "comments"],
        },
    },
    {
        "name": "draft_open",
        "description": "Show a saved draft in the user's browser again. Use when the user says the page did not open. Never open a console URL yourself: it answers Unauthorized here.",
        "inputSchema": {
            "type": "object",
            "properties": {"id": text_property("The draft id from the save reply")},
            "required": ["id"],
        },
    },
]
DRAFT_TOOL_NAMES = {draft_tool["name"] for draft_tool in DRAFT_TOOLS}


def drafts_dir():
    return os.environ.get("CLAUDE_OLLAMA_DRAFTS_DIR")


def checked_object(values, allowed, what):
    if not isinstance(values, dict):
        raise DraftRefused(f"{what} must be an object")
    unknown = set(values) - set(allowed)
    if unknown:
        raise DraftRefused(f"unknown arguments: {', '.join(sorted(unknown))}")
    return values


def checked_text(values, name, limit):
    value = values.get(name)
    if not isinstance(value, str) or not value.strip():
        raise DraftRefused(f"{name} is required")
    if len(value) > limit or "\0" in value:
        raise DraftRefused(f"{name} must be at most {limit} characters of text")
    return value


def checked_line_of_text(values, name, limit):
    value = checked_text(values, name, limit)
    if "\n" in value or "\r" in value:
        raise DraftRefused(f"{name} must be one line")
    return value.strip()


def checked_list(values, name, minimum):
    value = values.get(name)
    if not isinstance(value, list) or not minimum <= len(value) <= MAX_ITEMS:
        raise DraftRefused(f"{name} must be a list of {minimum} to {MAX_ITEMS}")
    return value


def checked_positive_number(values, name):
    value = values.get(name)
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise DraftRefused(f"{name} must be a positive whole number")
    return value


def checked_branch(values, name):
    value = values.get(name)
    if not isinstance(value, str) or not BRANCH_NAME.match(value) or ".." in value:
        raise DraftRefused(f"{name} must be a branch name")
    return value


def checked_choice(value, name, choices):
    if value not in choices:
        raise DraftRefused(f"{name} must be one of {', '.join(choices)}")
    return value


def checked_section(values):
    section = checked_object(values, {"heading", "body"}, "a section")
    return {
        "heading": checked_line_of_text(section, "heading", MAX_HEADING_CHARS),
        "body": checked_text(section, "body", MAX_BODY_CHARS),
    }


def checked_decorations(values):
    decorations = values.get("decorations", [])
    if not isinstance(decorations, list) or any(item not in DECORATIONS for item in decorations):
        raise DraftRefused(f"decorations must be from {', '.join(DECORATIONS)}")
    return list(dict.fromkeys(decorations))


def checked_location(values):
    path, line = values.get("path"), values.get("line")
    if path is None:
        if line is not None:
            raise DraftRefused("line needs a path")
        return {}
    if not isinstance(path, str) or not path or PurePath(path).is_absolute() or ".." in PurePath(path).parts:
        raise DraftRefused(OUTSIDE_REPOSITORY)
    location = {"path": path}
    if line is not None:
        location["line"] = checked_positive_number(values, "line")
    return location


def checked_comment(values):
    comment = checked_object(values, {"label", "decorations", "path", "line", "body"}, "a comment")
    return {
        "label": checked_choice(comment.get("label"), "label", LABELS),
        "decorations": checked_decorations(comment),
        **checked_location(comment),
        "body": checked_text(comment, "body", MAX_BODY_CHARS),
    }


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:60] or "draft"


def draft_id(kind, name):
    return f"{time.strftime('%Y%m%d-%H%M%S')}-{kind}-{slug(name)}"


def write_private_json(folder, draft):
    os.makedirs(folder, mode=0o700, exist_ok=True)
    os.chmod(folder, 0o700)
    descriptor, temporary = tempfile.mkstemp(dir=folder, prefix=".draft-", suffix=".tmp")
    with os.fdopen(descriptor, "w") as handle:
        json.dump(draft, handle, indent=2)
        handle.write("\n")
    os.replace(temporary, Path(folder) / f"{draft['id']}.json")


def saved(draft):
    folder = drafts_dir()
    if not folder:
        raise DraftRefused("drafts are off in this session")
    write_private_json(folder, draft)
    return f"saved draft {draft['id']}; the page opens in the user's browser on its own. Share no console link: the console needs a token this session never holds."


def draft_open(values):
    args = checked_object(values, {"id"}, "arguments")
    folder = drafts_dir()
    if not folder:
        raise DraftRefused("drafts are off in this session")
    requested = args.get("id")
    if not isinstance(requested, str) or not DRAFT_ID.fullmatch(requested):
        raise DraftRefused("id must be a saved draft")
    if not (Path(folder) / f"{requested}.json").is_file():
        raise DraftRefused("id must be a saved draft")
    (Path(folder) / f"{requested}.open").touch(mode=0o600)
    return f"asked for draft {requested}; it opens in the user's browser in a few seconds. If it does not, the user can run claude-ollama ui and pick Drafts."


def created_now():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def draft_pr(values, project, head):
    args = checked_object(values, {"title", "base", "sections"}, "arguments")
    draft = {
        "kind": "pr",
        "id": draft_id("pr", head),
        "project": project,
        "base": checked_branch(args, "base"),
        "head": head,
        "title": checked_line_of_text(args, "title", MAX_TITLE_CHARS),
        "sections": [checked_section(section) for section in checked_list(args, "sections", 1)],
        "created": created_now(),
    }
    return saved(draft)


def draft_review(values, project):
    args = checked_object(values, {"pr", "event", "summary", "comments"}, "arguments")
    number = checked_positive_number(args, "pr")
    draft = {
        "kind": "review",
        "id": draft_id("review", str(number)),
        "project": project,
        "pr": number,
        "event": checked_choice(args.get("event"), "event", EVENTS),
        "summary": checked_text(args, "summary", MAX_BODY_CHARS),
        "comments": [checked_comment(comment) for comment in checked_list(args, "comments", 0)],
        "created": created_now(),
    }
    return saved(draft)
