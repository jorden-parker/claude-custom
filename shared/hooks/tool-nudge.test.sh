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

reads() {
  local remaining="$1"
  while [ "$remaining" -gt 0 ]; do
    post Read >/dev/null
    remaining=$((remaining - 1))
  done
}

event UserPromptSubmit >/dev/null
first_deny="$(pre Bash 'grep -n foo src/a.py')"
expect_eq "first text search of a turn is denied" yes "$(mentions "$first_deny" '^deny: ')"
expect_eq "deny reason names the full tool name" yes "$(mentions "$first_deny" 'mcp__code-search__semantic_search')"
expect_eq "second text search is still denied" yes "$(mentions "$(pre Bash 'rg foo')" '^deny: ')"
expect_eq "third text search passes so a broken server cannot lock the model out" "" "$(pre Bash 'git grep -n foo')"

event UserPromptSubmit >/dev/null
expect_eq "git grep leading a pipe is denied" yes "$(mentions "$(pre Bash 'git grep -n foo | head -30')" '^deny: ')"
expect_eq "grep after a pipe is a filter, not a search" "" "$(pre Bash 'go test ./... | grep FAIL')"
expect_eq "find is not gated" "" "$(pre Bash 'find . -name x')"
expect_eq "non-search bash is never gated" "" "$(pre Bash 'ls -la')"
expect_eq "Read is never gated" "" "$(pre Read)"

event UserPromptSubmit >/dev/null
expect_eq "semantic_search itself is allowed" "" "$(pre mcp__code-search__semantic_search)"
expect_eq "semantic_search unlocks text search for the turn" "" "$(pre Bash 'grep foo')"
expect_eq "and keeps it unlocked" "" "$(pre Bash 'rg bar')"

event UserPromptSubmit >/dev/null
expect_eq "a new prompt locks text search again" yes "$(mentions "$(pre Bash 'grep foo')" '^deny: ')"

event UserPromptSubmit >/dev/null
expect_eq "PostToolUse never denies a text search" "" "$(post Bash 'grep foo')"

event UserPromptSubmit >/dev/null
reads 5
expect_eq "sixth read nudges Agent" yes "$(mentions "$(post Read)" 'Agent')"
expect_eq "seventh read is silent" "" "$(post Read)"

event UserPromptSubmit >/dev/null
reads 3
post Agent >/dev/null
reads 3
expect_eq "Agent use resets the read count" "" "$(post Read)"

event UserPromptSubmit >/dev/null
post Read >/dev/null
post Bash 'grep a' >/dev/null
reads 3
expect_eq "searches and reads count together for the Agent nudge" yes "$(mentions "$(post Read)" 'Agent')"

expect_eq "prompt submit prints nothing" "" "$(event UserPromptSubmit)"

[ "$failures" -eq 0 ] && echo "all passed" && exit 0
exit 1
