#!/usr/bin/env bash
set -u
hooks_dir="$(cd "$(dirname "$0")" && pwd)"
cache="$hooks_dir/repeat-call-cache.py"
budget="$hooks_dir/friction_budget.py"
failures=0
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export CLAUDE_CONFIG_DIR="$sandbox/config"
export CLAUDE_TOOL_TELEMETRY="$sandbox/telemetry.jsonl"
repo="$sandbox/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
printf 'alpha\nbeta\n' > "$repo/notes.txt"
touch -t 202401010000 "$repo/notes.txt"

new_turn() {
  printf '{"session_id":"s1","hook_event_name":"UserPromptSubmit"}' | python3 "$budget"
}

event() {
  local hook_event="$1" tool="$2" input="$3" response="${4:-null}"
  jq -cn --arg event "$hook_event" --arg tool "$tool" --argjson input "$input" --argjson response "$response" --arg cwd "$repo" \
    '{session_id: "s1", hook_event_name: $event, cwd: $cwd, tool_name: $tool, tool_input: $input, tool_response: $response}' \
    | python3 "$cache"
}

after() { event PostToolUse "$@" >/dev/null; }
before() { event PreToolUse "$1" "$2"; }
decision() { if before "$@" | grep -q '"permissionDecision": *"deny"'; then echo deny; else echo allow; fi; }

expect_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label (want '$want', got '$got')"
    failures=$((failures + 1))
  fi
}

mentions() { grep -qF -- "$2" <<<"$1" && echo yes || echo no; }

read_input="{\"file_path\":\"$repo/notes.txt\"}"
read_response="{\"type\":\"text\",\"file\":{\"filePath\":\"$repo/notes.txt\",\"content\":\"alpha\\nbeta\\n\",\"numLines\":2}}"

new_turn
expect_eq "a first Read passes" allow "$(decision Read "$read_input")"
after Read "$read_input" "$read_response"
expect_eq "the same Read of an unchanged file is denied" deny "$(decision Read "$read_input")"
expect_eq "the denial points at the earlier call" yes \
  "$(mentions "$(before Read "$read_input")" 'same result as call #1 this turn, unchanged since; use it')"
expect_eq "the hit writes a friction line with the bytes saved" yes \
  "$(mentions "$(cat "$CLAUDE_TOOL_TELEMETRY")" '"hook": "repeat-call-cache"')"
expect_eq "the saved bytes are the recorded output size" yes "$(mentions "$(cat "$CLAUDE_TOOL_TELEMETRY")" '"saved_bytes": 11')"
later_range_input="{\"file_path\":\"$repo/notes.txt\",\"offset\":2}"
expect_eq "a different range passes" allow "$(decision Read "$later_range_input")"
touch "$repo/notes.txt"
expect_eq "a changed mtime passes" allow "$(decision Read "$read_input")"

after Read "$read_input" "$read_response"
expect_eq "re-recorded after the change, it is denied again" deny "$(decision Read "$read_input")"
expect_eq "the pointer names the later call number" yes "$(mentions "$(before Read "$read_input")" 'call #2')"

error_input="{\"file_path\":\"$repo/missing.txt\"}"
after Read "$error_input" '"Error: file not found"'
expect_eq "an error result is never cached" allow "$(decision Read "$error_input")"
after Read "$error_input" '{"is_error":true,"content":"ok"}'
expect_eq "a tool error flag is never cached" allow "$(decision Read "$error_input")"

new_turn
expect_eq "a new prompt clears the cache" allow "$(decision Read "$read_input")"

after mcp__repo__git_status '{}' '[{"type":"text","text":"## main\n M notes.txt"}]'
expect_eq "a repeated git_status with the same HEAD and index is denied" deny "$(decision mcp__repo__git_status '{}')"
git -C "$repo" add notes.txt
expect_eq "a changed index passes" allow "$(decision mcp__repo__git_status '{}')"
after mcp__repo__git_status '{}' '[{"type":"text","text":"## main\nA notes.txt"}]'
expect_eq "denied again once recorded" deny "$(decision mcp__repo__git_status '{}')"
git -C "$repo" -c user.name=t -c user.email=t@t commit -q -m second
expect_eq "a new HEAD passes" allow "$(decision mcp__repo__git_status '{}')"

after mcp__code-search__semantic_search '{"query":"where is auth"}' '{"content":[{"type":"text","text":"src/auth.ts:1"}]}'
expect_eq "a repeated search is denied" deny "$(decision mcp__code-search__semantic_search '{"query":"where is auth"}')"
expect_eq "another query passes" allow "$(decision mcp__code-search__semantic_search '{"query":"where is billing"}')"

after Bash '{"command":"ls"}' '{"stdout":"a","stderr":""}'
expect_eq "a tool outside the list is never cached" allow "$(decision Bash '{"command":"ls"}')"

expect_eq "PostToolUse prints nothing" "" "$(event PostToolUse Read "$read_input" "$read_response")"
if printf 'not json' | python3 "$cache"; then :; else
  echo "FAIL: bad input must exit 0"
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
