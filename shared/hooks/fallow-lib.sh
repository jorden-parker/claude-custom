#!/usr/bin/env bash
fallow_is_js_file() {
  grep -Eq '\.(ts|tsx|js|jsx|mjs|cjs|mts|cts)$' <<<"$1"
}

fallow_marker_dir() {
  printf '%s/cache/fallow-fix-preview' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
}

fallow_project_root() {
  local start="$1" top dir parent
  top="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null || true)"
  [ "$top" = "$HOME" ] && top=""
  dir="$start"
  while [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "$HOME" ]; do
    if [ -f "$dir/package.json" ]; then printf '%s\n' "$dir"; return 0; fi
    [ "$dir" = "$top" ] && break
    parent="$(dirname "$dir")"
    [ "$parent" = "$dir" ] && break
    dir="$parent"
  done
  return 1
}

fallow_runner() {
  if command -v fallow >/dev/null 2>&1; then echo "fallow"
  elif [ -x ./node_modules/.bin/fallow ]; then echo "./node_modules/.bin/fallow"
  else echo "npx -y fallow"; fi
}

fallow_report_filter() {
  cat <<'JQ'
"fallow audit: \(.verdict) (dead code \(.summary.dead_code_issues), complexity \(.summary.complexity_findings), duplication \(.summary.duplication_clone_groups))",
( .dead_code // {} | to_entries[] | select(.key != "workspace_diagnostics" and (.value|type) == "array") | .key as $k
  | .value[] | select(type == "object" and has("path") and (.introduced != false))
  | "  \($k|rtrimstr("s")) \(.path):\(.line // "?") \(.export_name // .name // .message // "")" ),
( .complexity.findings[]? | select(.introduced != false)
  | "  high-complexity \(.path):\(.line) \(.name) cyclomatic=\(.cyclomatic) cognitive=\(.cognitive)" ),
( .duplication.clone_groups[]? | "  duplication " + ([.instances[] | "\(.file):\(.start_line)-\(.end_line)"] | join(" = ")) ),
( .next_steps[]? | "  next: \(.command)" )
JQ
}

fallow_audit_report() {
  local path="${1:-}" json verdict runner
  read -ra runner <<<"$(fallow_runner)"
  json="$("${runner[@]}" audit --format json --quiet ${path:+"$path"} 2>/dev/null)"
  verdict="$(jq -r '.verdict // empty' <<<"$json" 2>/dev/null)"
  [ -z "$verdict" ] && return 2
  jq -r "$(fallow_report_filter)" <<<"$json" | head -60
  [ "$verdict" = "fail" ] && return 1
  return 0
}

fallow_command_segments() {
  python3 -I - "$1" <<'PY'
import bisect
import re
import shlex
import sys

SEPARATOR_CHARS = ";|&()\n"
SEPARATORS = re.compile(r"[;|&()\n]+")
HEREDOC_OPENER = re.compile(r"<<-?[ \t]*(?:(['\"])(\w+)\1|(\w+))")
WORD_LINE = re.compile(r"\w+")


def flatten(word):
    return word.replace("\t", " ").replace("\n", " ")


def is_separator(token):
    return set(token) <= set(SEPARATOR_CHARS)


def lex(command):
    lexer = shlex.shlex(command, posix=True, punctuation_chars=SEPARATOR_CHARS)
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    lexer.commenters = ""
    return lexer


def quoted_segments(command):
    segments = [[]]
    for token in lex(command):
        if is_separator(token):
            segments.append([])
        else:
            segments[-1].append(token)
    return segments


def plain_segments(command):
    return [segment.split() for segment in SEPARATORS.split(command)]


class PrefixNode:
    def __init__(self):
        self.children = {}
        self.lines = []


class TerminatorIndex:
    def __init__(self, lines, longest_word):
        self.root = PrefixNode()
        for number, line in enumerate(lines):
            content = line.strip(" \t")
            if len(content) <= longest_word and WORD_LINE.fullmatch(content):
                self.add(content, number)

    def add(self, content, number):
        node = self.root
        for char in content:
            if char not in node.children:
                node.children[char] = PrefixNode()
            node = node.children[char]
        node.lines.append(number)

    def find(self, word, quoted, opener_line):
        node = self.root
        deepest = None
        for depth, char in enumerate(word, 1):
            node = node.children.get(char)
            if node is None:
                break
            position = bisect.bisect_right(node.lines, opener_line)
            if position < len(node.lines):
                deepest = (depth, node.lines[position])
        if deepest is None or (quoted and deepest[0] != len(word)):
            return None
        return deepest[1]


def opener_word(opener):
    return opener.group(2) or opener.group(3)


def heredoc_terminator(line, number, index):
    opener = HEREDOC_OPENER.search(line)
    while opener is not None:
        quoted = opener.group(1) is not None
        terminator = index.find(opener_word(opener), quoted, number)
        if terminator is not None:
            return terminator
        opener = HEREDOC_OPENER.search(line, opener.start() + 1)
    return None


def strip_heredocs(command):
    lines = command.split("\n")
    openers = HEREDOC_OPENER.finditer(command)
    longest_word = max((len(opener_word(opener)) for opener in openers), default=0)
    index = TerminatorIndex(lines, longest_word)
    kept = []
    number = 0
    while number < len(lines):
        kept.append(lines[number])
        terminator = heredoc_terminator(lines[number], number, index)
        number = number + 1 if terminator is None else terminator + 1
    return "\n".join(kept)


def segments(command):
    without_heredocs = strip_heredocs(command)
    try:
        return quoted_segments(without_heredocs)
    except ValueError:
        return plain_segments(without_heredocs)


for words in segments(sys.argv[1]):
    if words:
        print("\t".join(flatten(word) for word in words))
PY
}
