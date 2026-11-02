#!/usr/bin/env python3
import json
import os
import re
import shlex
import sys
from pathlib import Path

CONTEXT_CAP = 1200
FILE_TOOLS = {"Edit", "Write", "MultiEdit", "Read"}
TRIGGER_KINDS = ("path", "suffix", "command", "tool")
SPECIFICITY = {kind: rank for rank, kind in enumerate(reversed(TRIGGER_KINDS))}
FRONT_MATTER_FENCE = "---"
COMMAND_SEPARATOR = re.compile(r"&&|\|\||[;&\n()]")


class MalformedCard(ValueError):
    pass


def cards_dir():
    override = os.environ.get("CLAUDE_OLLAMA_RULE_CARDS_DIR")
    if override:
        return Path(override)
    home = os.environ.get("CLAUDE_CUSTOM_HOME")
    root = Path(home) if home else Path(__file__).resolve().parents[2]
    return root / "ollama" / "rule-cards"


def claude_config_dir():
    return Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")


def state_path(session_id):
    return claude_config_dir() / "cache" / "rule-cards" / f"{session_id}.json"


def load_delivered(path):
    try:
        return set(json.loads(path.read_text()).get("delivered", []))
    except (OSError, ValueError, AttributeError):
        return set()


def save_delivered(path, delivered):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"delivered": sorted(delivered)}))


def parse_trigger(line):
    kind, separator, value = line.lstrip("- ").partition(":")
    kind = kind.strip()
    values = [part.strip() for part in value.split(",") if part.strip()]
    if not separator or kind not in TRIGGER_KINDS or not values:
        raise MalformedCard(f"bad trigger line {line.strip()!r}")
    return kind, values


def split_front_matter(text):
    lines = text.splitlines()
    if not lines or lines[0].strip() != FRONT_MATTER_FENCE:
        raise MalformedCard("no front matter")
    try:
        end = lines.index(FRONT_MATTER_FENCE, 1)
    except ValueError:
        raise MalformedCard("unclosed front matter") from None
    return lines[1:end], "\n".join(lines[end + 1 :]).strip()


def parse_card(path):
    header, body = split_front_matter(path.read_text())
    if not any(line.strip() == "triggers:" for line in header):
        raise MalformedCard("no triggers")
    triggers = [parse_trigger(line) for line in header if line.strip().startswith("-")]
    if not triggers:
        raise MalformedCard("no triggers")
    if not body:
        raise MalformedCard("empty body")
    return {"id": path.stem, "triggers": triggers, "body": body}


def load_cards(directory):
    cards, problems = [], []
    for path in sorted(directory.glob("*.md")):
        try:
            cards.append(parse_card(path))
        except MalformedCard as reason:
            problems.append(f"{path.name}: {reason}")
    return cards, problems


def words_of(text):
    try:
        return shlex.split(text)
    except ValueError:
        return text.split()


def segment_heads(command):
    return [words_of(part.split("|")[0]) for part in COMMAND_SEPARATOR.split(command)]


def command_matches(command, value):
    wanted = value.split()
    return any(words[: len(wanted)] == wanted for words in segment_heads(command))


def relative_file_path(tool_input, cwd):
    raw = tool_input.get("file_path", "")
    if not raw:
        return ""
    path = Path(raw)
    if path.is_absolute() and cwd:
        try:
            return path.relative_to(cwd).as_posix()
        except ValueError:
            return path.as_posix()
    return path.as_posix()


def trigger_matches(kind, value, tool_name, tool_input, cwd):
    if kind == "tool":
        return tool_name == value
    if kind == "command":
        return tool_name == "Bash" and command_matches(tool_input.get("command", ""), value)
    if tool_name not in FILE_TOOLS:
        return False
    file_path = relative_file_path(tool_input, cwd)
    if kind == "suffix":
        return file_path.endswith(value)
    return file_path.startswith(value) or f"/{value}" in file_path


def best_match_rank(card, tool_name, tool_input, cwd):
    ranks = [
        SPECIFICITY[kind]
        for kind, values in card["triggers"]
        for value in values
        if trigger_matches(kind, value, tool_name, tool_input, cwd)
    ]
    return max(ranks) if ranks else None


def matching_cards(cards, tool_name, tool_input, cwd):
    ranked = []
    for card in cards:
        rank = best_match_rank(card, tool_name, tool_input, cwd)
        if rank is not None:
            ranked.append((-rank, card["id"], card))
    return [card for _, _, card in sorted(ranked, key=lambda item: item[:2])]


def within_cap(cards):
    chosen, used = [], 0
    for card in cards:
        cost = len(card["body"]) + (2 if chosen else 0)
        if used + cost > CONTEXT_CAP:
            break
        chosen.append(card)
        used += cost
    return chosen


def select(cards, delivered, tool_name, tool_input, cwd):
    pending = [card for card in matching_cards(cards, tool_name, tool_input, cwd) if card["id"] not in delivered]
    return within_cap(pending)


def report_problems(problems):
    for problem in problems:
        print(f"rule-cards: skipping {problem}", file=sys.stderr)


def describe(card):
    triggers = ", ".join(f"{kind} {value}" for kind, values in card["triggers"] for value in values)
    return f"{card['id']}: {triggers}"


def list_cards():
    cards, problems = load_cards(cards_dir())
    report_problems(problems)
    for card in cards:
        print(describe(card))
    return 1 if problems else 0


def match_cards(tool_name, raw_input):
    cards, problems = load_cards(cards_dir())
    report_problems(problems)
    for card in select(cards, set(), tool_name, json.loads(raw_input), os.getcwd()):
        print(card["id"])
    return 0


def switched_off():
    return os.environ.get("CLAUDE_OLLAMA_RULE_CARDS") == "0"


def handle_event(event):
    if switched_off() or event.get("hook_event_name") != "PreToolUse":
        return 0
    cards, problems = load_cards(cards_dir())
    report_problems(problems)
    path = state_path(event.get("session_id", "nosession"))
    delivered = load_delivered(path)
    chosen = select(cards, delivered, event.get("tool_name", ""), event.get("tool_input") or {}, event.get("cwd", ""))
    if not chosen:
        return 0
    save_delivered(path, delivered | {card["id"] for card in chosen})
    context = "\n\n".join(card["body"] for card in chosen)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": context}}))
    return 0


def main(argv):
    if argv[:1] == ["--list"]:
        return list_cards()
    if argv[:1] == ["--match"] and len(argv) == 3:
        return match_cards(argv[1], argv[2])
    if argv:
        print("usage: rule-cards.py [--list | --match TOOL JSON]", file=sys.stderr)
        return 2
    return handle_event(json.load(sys.stdin))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
