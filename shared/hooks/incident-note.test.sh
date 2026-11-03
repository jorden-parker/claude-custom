#!/usr/bin/env bash
set -u
hook="$(dirname "$0")/incident-note.py"
failures=0
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export HOME="$sandbox/home"
export TZ=UTC
mkdir -p "$HOME"
incidents="$sandbox/incidents.jsonl"

prompt() {
  printf '{"session_id":"%s","hook_event_name":"UserPromptSubmit","prompt":"hi"}' "${1:-s1}" | python3 "$hook" | python3 -c '
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

unset CLAUDE_OLLAMA_INCIDENTS_FILE
expect_eq "without an incidents file the hook is silent" "" "$(prompt)"
export CLAUDE_OLLAMA_INCIDENTS_FILE="$incidents"
expect_eq "a missing incidents file keeps the hook silent" "" "$(prompt)"
: > "$incidents"
expect_eq "an empty incidents file keeps the hook silent" "" "$(prompt)"

printf '%s\n' '{"ts": "2026-11-02T14:01:30.100Z", "cause": "aborted", "detail": "error=\"context canceled\"", "tokens": null}' >> "$incidents"
expect_eq "the first incident is reported with its cause, time and counts" \
  "last incident: aborted at 14:01 (the request was cancelled mid-flight); since the session started: aborted 1" "$(prompt)"
expect_eq "the same incidents are not reported twice" "" "$(prompt)"

printf '%s\n' '{"ts": "2026-11-02T14:02:13.000Z", "cause": "evicted", "detail": "starting llama-server", "tokens": null}' >> "$incidents"
printf '%s\n' '{"ts": "2026-11-02T14:02:40.000Z", "cause": "reprefilled", "detail": "prompt eval time", "tokens": 61234}' >> "$incidents"
expect_eq "new incidents report the newest one and every count so far" \
  "last incident: reprefilled at 14:02 (re-prefilled 61k tokens); since the session started: aborted 1, evicted 1, reprefilled 1" "$(prompt)"

printf '%s\n' '{"ts": "2026-11-02T14:03:00.000Z", "cause": "truncated", "detail": "truncating input prompt", "tokens": 66000}' >> "$incidents"
expect_eq "a truncated prompt names its size" \
  "last incident: truncated at 14:03 (the prompt of 66k tokens was cut to fit); since the session started: aborted 1, evicted 1, truncated 1, reprefilled 1" "$(prompt)"

printf '%s\n' '{"ts": "2026-11-02T14:05:00.000Z", "cause": "compacted", "detail": "{\"subtype\":\"compact_boundary\"}", "tokens": 250598}' >> "$incidents"
expect_eq "a compaction names the token count it started from" \
  "last incident: compacted at 14:05 (compacted at 251k tokens); since the session started: aborted 1, evicted 1, truncated 1, reprefilled 1, compacted 1" "$(prompt)"

printf '%s\n' '{"ts": "2026-11-02T14:06:00.000Z", "cause": "unknown", "detail": "msg=\"runner idle timer fired\" model=qwen3.6:35b-cc", "tokens": null}' >> "$incidents"
expect_eq "an unknown incident shows the line" \
  "last incident: unknown at 14:06 (msg=\"runner idle timer fired\" model=qwen3.6:35b-cc); since the session started: aborted 1, evicted 1, truncated 1, reprefilled 1, compacted 1, unknown 1" "$(prompt)"

printf '%s
' '{"ts": "2026-11-02T14:07:00.000Z", "cause": "relaunched", "detail": "/repo/.git/handoff/2026-11-02-1406-tests.md", "tokens": 37806}' >> "$incidents"
expect_eq "a relaunch says it resumed from a handoff note and is counted" \
  "last incident: relaunched at 14:07 (resumed from a handoff note at 38k tokens); since the session started: aborted 1, evicted 1, truncated 1, reprefilled 1, compacted 1, relaunched 1, unknown 1" "$(prompt)"
printf '%s
' '{"ts": "2026-11-02T14:07:30.000Z", "kind": "health", "rules": {"aborted/context-canceled": 1}, "unmatched": 1, "lines": 36}' >> "$incidents"
expect_eq "a health row is not an incident" "" "$(prompt)"
printf '%s
' '{"ts": "2026-11-02T14:08:00.000Z", "cause": "aborted", "detail": "error=\"context canceled\"", "tokens": null, "rule": "aborted/context-canceled"}' >> "$incidents"
expect_eq "and is left out of the counts" \
  "last incident: aborted at 14:08 (the request was cancelled mid-flight); since the session started: aborted 2, evicted 1, truncated 1, reprefilled 1, compacted 1, relaunched 1, unknown 1" "$(prompt)"

starts_with() { case "$1" in "$2"*) echo yes ;; *) echo no ;; esac; }
expect_eq "another session has not seen the incidents yet" yes "$(starts_with "$(prompt s2)" "last incident: aborted")"
expect_eq "the state lives under the Claude config dir" yes "$([ -f "$HOME/.claude/cache/incident-note/s1.json" ] && echo yes || echo no)"
export CLAUDE_CONFIG_DIR="$sandbox/config"
expect_eq "CLAUDE_CONFIG_DIR moves the state" yes "$(prompt >/dev/null; [ -f "$sandbox/config/cache/incident-note/s1.json" ] && echo yes || echo no)"

stale_state="$sandbox/config/cache/incident-note/stale.json"
printf '{"reported": 1}' > "$stale_state"
touch -t 202001010000 "$stale_state"
prompt s9 >/dev/null
expect_eq "a new session's first report prunes week-old state" no "$([ -e "$stale_state" ] && echo yes || echo no)"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  exit 1
fi
