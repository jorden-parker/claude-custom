#!/usr/bin/env bash
set -u
hook="$(cd "$(dirname "$0")" && pwd)/context-budget.py"
failures=0
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export HOME="$sandbox/home"
mkdir -p "$HOME"
export CLAUDE_TOOL_TELEMETRY="$sandbox/telemetry.jsonl"

transcript_with() {
  local used="$1"
  local path="$sandbox/transcript-$used.jsonl"
  {
    printf '{"type":"user","message":{"role":"user","content":"hi"}}\n'
    printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"cache_creation_input_tokens":1,"cache_read_input_tokens":1,"output_tokens":5}}}\n'
    printf 'not json\n'
    printf '{"type":"assistant","message":{"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":120}}}\n' \
      "$((used - 30000))" 20000 10000
    printf '{"type":"progress","data":{}}\n'
  } > "$path"
  printf '%s' "$path"
}

reply_for() {
  local session="$1" transcript="$2"
  jq -cn --arg session "$session" --arg transcript "$transcript" \
    '{session_id: $session, hook_event_name: "PostToolUse", tool_name: "Edit", transcript_path: $transcript, tool_input: {}}' \
    | python3 "$hook" | python3 -c '
import json, sys
raw = sys.stdin.read()
print(json.loads(raw)["hookSpecificOutput"]["additionalContext"] if raw.strip() else "")'
}

expect_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label (want '$want', got '$got')"
    failures=$((failures + 1))
  fi
}

mentions() { grep -q "$2" <<<"$1" && echo yes || echo no; }

over="$(transcript_with 46000)"
under="$(transcript_with 30000)"

nudge="$(CLAUDE_CODE_MAX_CONTEXT_TOKENS=65536 reply_for s1 "$over")"
expect_eq "46000 of 65536 nudges toward the handoff skill" yes "$(mentions "$nudge" 'handoff')"
expect_eq "the nudge says to call the skill with save" yes "$(mentions "$nudge" 'save')"
expect_eq "the nudge names the percentage used" yes "$(mentions "$nudge" '70%')"
expect_eq "a second call in the same session prints nothing" "" "$(CLAUDE_CODE_MAX_CONTEXT_TOKENS=65536 reply_for s1 "$over")"
expect_eq "30000 of 65536 prints nothing" "" "$(CLAUDE_CODE_MAX_CONTEXT_TOKENS=65536 reply_for s2 "$under")"
expect_eq "an unset max prints nothing" "" "$(reply_for s3 "$over")"
expect_eq "an unparsable max prints nothing" "" "$(CLAUDE_CODE_MAX_CONTEXT_TOKENS=lots reply_for s3 "$over")"
expect_eq "a lower threshold nudges the smaller transcript" yes \
  "$(mentions "$(CLAUDE_CODE_MAX_CONTEXT_TOKENS=65536 CLAUDE_OLLAMA_HANDOFF_PCT=40 reply_for s4 "$under")" 'handoff')"
expect_eq "a missing transcript prints nothing" "" "$(CLAUDE_CODE_MAX_CONTEXT_TOKENS=65536 reply_for s5 "$sandbox/missing.jsonl")"

state="$HOME/.claude/cache/context-budget/s1.json"
expect_eq "the nudge is recorded in the session's state file" yes "$(mentions "$(cat "$state" 2>/dev/null)" '"nudged_at"')"
expect_eq "no state file is written without a nudge" no "$(test -e "$HOME/.claude/cache/context-budget/s2.json" && echo yes || echo no)"

expect_eq "each of the two nudges logs one budget telemetry line" 2 "$(grep -c '"kind": "budget"' "$CLAUDE_TOOL_TELEMETRY")"
expect_eq "the telemetry line names the hook" yes "$(mentions "$(cat "$CLAUDE_TOOL_TELEMETRY")" '"hook": "context-budget"')"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
