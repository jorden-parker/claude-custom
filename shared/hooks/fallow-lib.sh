#!/usr/bin/env bash
fallow_is_js_file() {
  grep -Eq '\.(ts|tsx|js|jsx|mjs|cjs|mts|cts)$' <<<"$1"
}

fallow_marker_dir() {
  printf '%s/.claude/cache/fallow-fix-preview' "$HOME"
}

fallow_project_root() {
  local start="$1" top dir
  top="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null || true)"
  [ "$top" = "$HOME" ] && top=""
  dir="$start"
  while [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "$HOME" ]; do
    if [ -f "$dir/package.json" ]; then printf '%s\n' "$dir"; return 0; fi
    [ "$dir" = "$top" ] && break
    dir="$(dirname "$dir")"
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
  | .value[] | select(type == "object" and has("path") and (.introduced // true))
  | "  \($k|rtrimstr("s")) \(.path):\(.line // "?") \(.export_name // .name // .message // "")" ),
( .complexity.findings[]? | select(.introduced // true)
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
import re
import shlex
import sys

SEPARATOR_CHARS = ";|&()\n"
SEPARATORS = re.compile(r"[;|&()\n]+")
HEREDOC_BODY = re.compile(r"(<<-?[ \t]*(['\"]?)(\w+)\2[^\n]*)\n.*?^[ \t]*\3[ \t]*$", re.S | re.M)


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


def segments(command):
    without_heredocs = HEREDOC_BODY.sub(r"\1", command)
    try:
        return quoted_segments(without_heredocs)
    except ValueError:
        return plain_segments(without_heredocs)


for words in segments(sys.argv[1]):
    if words:
        print("\t".join(flatten(word) for word in words))
PY
}
