#!/usr/bin/env bash
set -u
hook="$(dirname "$0")/tool-nudge.py"
failures=0
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export HOME="$sandbox/home"
mkdir -p "$HOME"

event() {
  local event_name="$1" tool_name="${2:-}" command="${3:-}"
  printf '{"session_id":"s1","hook_event_name":"%s","tool_name":"%s","tool_input":{"command":"%s"}}' \
    "$event_name" "$tool_name" "$command" | python3 "$hook" | python3 -c '
import json, sys
raw = sys.stdin.read()
print(json.loads(raw)["hookSpecificOutput"]["additionalContext"] if raw.strip() else "")'
}

tool() { event PostToolUse "$@"; }

expect_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label (want '$want', got '$got')"
    failures=$((failures + 1))
  fi
}

mentions() { grep -qi "$2" <<<"$1" && echo yes || echo no; }

reads() {
  local remaining="$1"
  while [ "$remaining" -gt 0 ]; do
    tool Read >/dev/null
    remaining=$((remaining - 1))
  done
}

event UserPromptSubmit >/dev/null
expect_eq "first text search is silent" "" "$(tool Bash 'grep -n foo src/a.py')"
expect_eq "second text search nudges semantic_search" yes "$(mentions "$(tool Bash 'rg foo')" semantic_search)"
expect_eq "third text search is silent again" "" "$(tool Bash 'git grep -n foo')"
expect_eq "non-search bash is never counted" "" "$(tool Bash 'ls -la')"

event UserPromptSubmit >/dev/null
tool Bash 'grep foo' >/dev/null
tool mcp__code-search__semantic_search >/dev/null
expect_eq "semantic_search resets the search count" "" "$(tool Bash 'grep bar')"
expect_eq "prompt submit resets the search nudge" yes "$(mentions "$(tool Bash 'find . -name x')" semantic_search)"

event UserPromptSubmit >/dev/null
reads 5
expect_eq "sixth read nudges Agent" yes "$(mentions "$(tool Read)" 'Agent')"
expect_eq "seventh read is silent" "" "$(tool Read)"

event UserPromptSubmit >/dev/null
reads 3
tool Agent >/dev/null
reads 3
expect_eq "Agent use resets the read count" "" "$(tool Read)"

event UserPromptSubmit >/dev/null
tool Read >/dev/null
tool Bash 'grep a' >/dev/null
reads 3
expect_eq "searches and reads count together for the Agent nudge" yes "$(mentions "$(tool Read)" 'Agent')"

expect_eq "prompt submit prints nothing" "" "$(event UserPromptSubmit)"

[ "$failures" -eq 0 ] && echo "all passed" && exit 0
exit 1
