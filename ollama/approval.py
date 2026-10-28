import re
import subprocess
import unicodedata
from pathlib import Path

SAFE_FIELD = re.compile(r"[A-Za-z0-9._/-]+")
UNSAFE_CATEGORIES = {"Cc", "Cf", "Zl", "Zp"}
BODY_PREVIEW_CHARS = 1500
MAX_WORD_CHARS = 200


class Unshowable(Exception):
    pass
ALLOW = "allow"
DENY = "deny"
ALWAYS = "allow-always"
RULE_VERDICTS = (ALLOW, DENY)
DEFAULT_TIMEOUT_SECONDS = 90
RULE_FIELD_COUNTS = (3, 4)


def parse_rule(line):
    fields = line.split()
    if not fields or fields[0].startswith("#"):
        return None
    if len(fields) not in RULE_FIELD_COUNTS or fields[0] not in RULE_VERDICTS:
        return None
    verdict, program, action, *scope = fields
    return verdict, program, action, scope[0].lower() if scope else None


def read_rules(rules_path):
    try:
        lines = rules_path.read_text().splitlines()
    except FileNotFoundError:
        return []
    return [rule for rule in map(parse_rule, lines) if rule is not None]


def verdict_from_rules(rules, program, action, scope):
    verdicts = {
        verdict
        for verdict, rule_program, rule_action, rule_scope in rules
        if rule_program == program and rule_action == action and rule_scope in (None, scope.lower())
    }
    if DENY in verdicts:
        return DENY
    return ALLOW if ALLOW in verdicts else None


def storable(*fields):
    return all(SAFE_FIELD.fullmatch(field) for field in fields)


def remember(rules_path, program, action, scope):
    rules_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with rules_path.open("a") as rules_file:
        rules_file.write(f"{ALLOW} {program} {action} {scope}\n")


def first_line(text):
    lines = text.splitlines()
    return lines[0].strip() if lines else ""


class Approver:
    def __init__(self, rules_path, dialog_command, timeout_seconds=DEFAULT_TIMEOUT_SECONDS):
        self.rules_path = Path(rules_path)
        self.dialog_command = list(dialog_command)
        self.timeout_seconds = timeout_seconds

    def decide(self, program, action, scope, summary):
        verdict = verdict_from_rules(read_rules(self.rules_path), program, action, scope)
        if verdict is not None:
            return verdict == ALLOW
        answer = self.ask(summary)
        if answer == ALWAYS:
            if storable(program, action, scope):
                remember(self.rules_path, program, action, scope)
            return True
        return answer == ALLOW

    def ask(self, summary):
        try:
            completed = subprocess.run(
                self.dialog_command,
                input=summary,
                capture_output=True,
                text=True,
                timeout=self.timeout_seconds,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            return DENY
        if completed.returncode != 0:
            return DENY
        return first_line(completed.stdout)


def summary_for(program, action, argv, scope, body_fields):
    elided = [elide(word, body_fields) for word in argv]
    command = printable(" ".join([program, *elided]))
    rule = f"rule: {program} {action} {printable(scope)}"
    text = f"{command}   (repo {printable(scope)})\n{rule}\n"
    for name, value in body_fields.items():
        text += body_section(name, value)
    return f"{text}{rule}\n"


def body_section(name, value):
    shown = value[:BODY_PREVIEW_CHARS]
    lines = quoted_lines(shown)
    if len(value) > BODY_PREVIEW_CHARS:
        lines += f"\n> [... {len(value) - BODY_PREVIEW_CHARS} more characters]"
    return f"\n----- {name} -----\n{lines}\n"


def quoted_lines(value):
    return "\n".join(f"> {escape_unsafe(line)}" for line in (value.splitlines() or [""]))


def is_unsafe(character):
    return character == "\x7f" or unicodedata.category(character) in UNSAFE_CATEGORIES


def escape_unsafe(text):
    return "".join(
        character.encode("unicode_escape").decode("ascii") if is_unsafe(character) else character
        for character in text
    )


def printable(text):
    return "".join(
        character if " " <= character <= "~" and character != "\\" else character.encode("unicode_escape").decode("ascii")
        for character in text
    )


def elide(word, body_fields):
    for name in body_fields:
        if word.startswith(f"--{name}="):
            return f"--{name}=..."
    if len(word) > MAX_WORD_CHARS:
        raise Unshowable(word.partition("=")[0])
    return word
