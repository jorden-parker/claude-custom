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
  jq -cn --arg event "$event_name" --arg tool "$tool_name" --arg command "$command" \
    '{session_id: "s1", hook_event_name: $event, tool_name: $tool, tool_input: {command: $command}}' | python3 "$hook" | python3 -c '
import json, sys
raw = sys.stdin.read()
if not raw.strip():
    print("")
else:
    output = json.loads(raw)["hookSpecificOutput"]
    if output.get("permissionDecision") == "deny":
        print("deny: " + output["permissionDecisionReason"])
    else:
        print(output.get("additionalContext", ""))'
}

pre() { event PreToolUse "$@"; }
post() { event PostToolUse "$@"; }

expect_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label (want '$want', got '$got')"
    failures=$((failures + 1))
  fi
}

mentions() { grep -q "$2" <<<"$1" && echo yes || echo no; }
denied() { mentions "$(pre Bash "$1")" '^deny: '; }

event UserPromptSubmit >/dev/null
first_deny="$(pre Bash 'grep -n foo src/a.py')"
expect_eq "first text search of a turn is denied" yes "$(mentions "$first_deny" '^deny: ')"
expect_eq "deny reason names the full tool name" yes "$(mentions "$first_deny" 'mcp__code-search__semantic_search')"
expect_eq "second text search is still denied" yes "$(denied 'rg foo')"
expect_eq "every later text search stays denied until semantic_search runs" yes "$(denied 'git grep -n foo')"
expect_eq "and the fourth" yes "$(denied 'ag foo')"

event UserPromptSubmit >/dev/null
expect_eq "git grep leading a pipe is denied" yes "$(denied 'git grep -n foo | head -30')"
expect_eq "a search after cd && is denied" yes "$(denied 'cd src && grep -rn foo .')"
expect_eq "a search after ; is denied" yes "$(denied 'ls; ack foo')"
expect_eq "find by name is a search" yes "$(denied 'find . -name "*.py"')"
expect_eq "find by path is a search" yes "$(denied 'find src -ipath "*auth*"')"
expect_eq "grep after a pipe is a filter, not a search" "" "$(pre Bash 'go test ./... | grep FAIL')"
expect_eq "find without a name filter is not a search" "" "$(pre Bash 'find . -type f -newer x')"
expect_eq "non-search bash is never gated" "" "$(pre Bash 'ls -la')"
expect_eq "Read is never gated" "" "$(pre Read)"

event UserPromptSubmit >/dev/null
expect_eq "semantic_search itself is allowed" "" "$(pre mcp__code-search__semantic_search)"
expect_eq "semantic_search unlocks text search for the turn, even when the server failed" "" "$(pre Bash 'grep foo')"
expect_eq "and keeps it unlocked" "" "$(pre Bash 'rg bar')"

event UserPromptSubmit >/dev/null
expect_eq "a new prompt locks text search again" yes "$(denied 'grep foo')"

event UserPromptSubmit >/dev/null
expect_eq "PostToolUse never answers" "" "$(post Bash 'grep foo')"
expect_eq "reads never nudge toward Agent" "" "$(post Read)"

expect_eq "prompt submit prints nothing" "" "$(event UserPromptSubmit)"

export CLAUDE_CONFIG_DIR="$sandbox/session-config"
pre Bash 'grep a' >/dev/null
expect_eq "state follows CLAUDE_CONFIG_DIR" yes \
  "$([ -f "$CLAUDE_CONFIG_DIR/cache/tool-nudge/s1.json" ] && echo yes || echo no)"
unset CLAUDE_CONFIG_DIR

[ "$failures" -eq 0 ] && echo "all passed" && exit 0
exit 1
