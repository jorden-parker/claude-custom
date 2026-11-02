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

tool_event() {
  local tool_name="$1" tool_input="$2"
  jq -cn --arg tool "$tool_name" --argjson input "$tool_input" \
    '{session_id: "s1", hook_event_name: "PreToolUse", tool_name: $tool, tool_input: $input}' | python3 "$hook"
}
tool_denied() { mentions "$(tool_event "$1" "$2")" '"permissionDecision": "deny"'; }

event UserPromptSubmit >/dev/null
pre mcp__code-search__semantic_search >/dev/null
node_modules_deny="$(pre Bash 'grep -rn useActionState node_modules/next/dist')"
expect_eq "a search inside node_modules is denied before find-docs" yes "$(mentions "$node_modules_deny" '^deny: ')"
expect_eq "the node_modules deny names find-docs" yes "$(mentions "$node_modules_deny" 'find-docs')"
expect_eq "the node_modules deny names dev_deps for install checks" yes "$(mentions "$node_modules_deny" 'mcp__dev__dev_deps')"
expect_eq "reading node_modules docs with cat is denied" yes "$(denied 'cat node_modules/next/dist/docs/index.md')"
expect_eq "listing node_modules is denied" yes "$(denied 'ls node_modules/next/dist/docs')"
expect_eq "find in node_modules is denied" yes "$(denied 'find node_modules/next -type f')"
expect_eq "Read of a node_modules file is denied" yes \
  "$(tool_denied Read '{"file_path":"/p/web/node_modules/next/dist/docs/a.md"}')"
expect_eq "Read of a project file passes" no "$(tool_denied Read '{"file_path":"/p/src/app.ts"}')"
expect_eq "removing node_modules is not a lookup" "" "$(pre Bash 'rm -rf node_modules')"
expect_eq "a package's own package.json is an install check, not docs" "" "$(pre Bash 'cat node_modules/zod/package.json')"
expect_eq "a scoped package's package.json too" "" "$(pre Bash 'jq .version web/console/node_modules/@types/node/package.json')"
expect_eq "Read of a package's package.json passes" no \
  "$(tool_denied Read '{"file_path":"/p/web/node_modules/zod/package.json"}')"
expect_eq "a package.json deeper inside a package is still docs" yes "$(denied 'cat node_modules/next/dist/package.json')"
expect_eq "a search outside node_modules passes" "" "$(pre Bash 'grep -rn foo src')"
expect_eq "another skill does not unlock node_modules" no "$(tool_denied Skill '{"skill":"tdd"}')"
expect_eq "still locked after another skill" yes "$(denied 'cat node_modules/next/dist/docs/index.md')"
expect_eq "the find-docs skill passes" no "$(tool_denied Skill '{"skill":"find-docs"}')"
expect_eq "find-docs unlocks node_modules for the turn" "" "$(pre Bash 'cat node_modules/next/package.json')"

event UserPromptSubmit >/dev/null
expect_eq "a new prompt locks node_modules again" yes "$(denied 'cat node_modules/next/dist/docs/index.md')"
expect_eq "a ctx7 lookup passes" "" "$(pre Bash 'npx ctx7@0.8.2 library next "server actions" | head -80')"
expect_eq "a wrapped ctx7 lookup passes" "" "$(pre Bash 'claude-custom ctx7 library next "server actions"')"
expect_eq "a ctx7 lookup unlocks node_modules" "" "$(pre Bash 'ls node_modules/next/dist/docs')"

export CLAUDE_CONFIG_DIR="$sandbox/session-config"
pre Bash 'grep a' >/dev/null
expect_eq "state follows CLAUDE_CONFIG_DIR" yes \
  "$([ -f "$CLAUDE_CONFIG_DIR/cache/tool-nudge/s1.json" ] && echo yes || echo no)"
unset CLAUDE_CONFIG_DIR

telemetry_log="$sandbox/telemetry.jsonl"

telemetry_for() {
  printf '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
    | CLAUDE_TOOL_TELEMETRY="$telemetry_log" python3 "$hook" >/dev/null
}

recorded_lines() {
  if [ -f "$telemetry_log" ]; then wc -l < "$telemetry_log" | tr -d ' '; else echo 0; fi
}

expect_recorded_lines() {
  local want="$1" command="$2"
  rm -f "$telemetry_log"
  telemetry_for "$command"
  expect_eq "telemetry lines for: $command" "$want" "$(recorded_lines)"
}

expect_recorded_lines 1 'grep -rn foo src'
expect_recorded_lines 0 'ls -la'
rm -f "$telemetry_log"
telemetry_for 'grep -rn foo src'
expect_eq "denial line names the kind and hook" yes "$(mentions "$(cat "$telemetry_log")" '"kind": "deny", "hook": "tool-nudge"')"
rm -f "$telemetry_log"
printf '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"grep -rn foo src"}}' \
  | env -u CLAUDE_TOOL_TELEMETRY python3 "$hook" >/dev/null
expect_eq "nothing is recorded when CLAUDE_TOOL_TELEMETRY is unset" no "$([ -e "$telemetry_log" ] && echo yes || echo no)"

printf '{"session_id":"s1","hook_event_name":"UserPromptSubmit"}' | python3 "$(dirname "$0")/friction_budget.py"
event UserPromptSubmit >/dev/null
rm -f "$telemetry_log"
for _ in 1 2 3; do telemetry_for 'grep -n foo src/a.py'; done
fourth_strike="$(printf '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"grep -n foo src/b.py"}}' | CLAUDE_TOOL_TELEMETRY="$telemetry_log" python3 "$hook")"
if ! grep -qF '"permissionDecision": "deny"' <<<"$fourth_strike" || ! grep -qF 'call semantic_search once, then grep' <<<"$fourth_strike"; then
  echo "FAIL: the fourth near-identical denial is a plan reset naming the alternative"
  failures=$((failures + 1))
fi
if ! grep -qF '"kind": "friction", "hook": "tool-nudge"' "$telemetry_log"; then
  echo "FAIL: the plan reset is recorded as friction"
  failures=$((failures + 1))
fi

mkdir -p "$sandbox/as-directory"
blocked_output="$(printf '%s' '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"grep -rn foo src"}}' | CLAUDE_TOOL_TELEMETRY="$sandbox/as-directory" python3 "$hook")"
blocked_status=$?
if ! grep -qF '"permissionDecision": "deny"' <<<"$blocked_output" || [ "$blocked_status" -ne 0 ]; then
  echo "FAIL: a telemetry path that cannot be written still denies, with exit 0"
  failures=$((failures + 1))
fi

[ "$failures" -eq 0 ] && echo "all passed" && exit 0
exit 1
