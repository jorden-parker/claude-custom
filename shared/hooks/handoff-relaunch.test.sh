#!/usr/bin/env bash
set -u
hook="$(cd "$(dirname "$0")" && pwd)/handoff-relaunch.py"
failures=0
sandbox="$(mktemp -d)"
export HOME="$sandbox/home"
repo="$sandbox/repo"
relaunch_dir="$sandbox/relaunch"
state_dir="$HOME/.claude/cache/context-budget"
transcript="$sandbox/transcript.jsonl"
mkdir -p "$HOME" "$sandbox/stubbin" "$relaunch_dir" "$state_dir"
sleeper_pids=""
cleanup() {
  local pid
  for pid in $sleeper_pids; do kill "$pid" 2>/dev/null; done
  rm -rf "$sandbox"
}
trap cleanup EXIT

git -C "$sandbox" init -q "$repo"
notes="$repo/.git/handoff"
mkdir -p "$notes"

cat > "$sandbox/stubbin/ps" <<'EOF'
#!/bin/sh
echo "${STUB_PS_COMM:-/usr/local/bin/node}"
EOF
chmod +x "$sandbox/stubbin/ps"
export PATH="$sandbox/stubbin:$PATH"

cat > "$transcript" <<'EOF'
{"type":"user","message":{"role":"user","content":"<system-reminder>ignore me</system-reminder>"}}
{"type":"user","message":{"role":"user","content":"Fix the failing\nlauncher test"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"On it."}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<local-command-stdout>done</local-command-stdout>"}]}}
{"type":"user","message":{"role":"user","content":"/handoff save"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Saved."}]}}
EOF

start_sleeper() {
  sleeper_pid="$(sleep 60 >/dev/null 2>&1 & echo $!)"
  sleeper_pids="$sleeper_pids $sleeper_pid"
  echo "$sleeper_pid" > "$relaunch_dir/claude.pid"
}

sleeper_alive() {
  sleep 0.2
  kill -0 "$sleeper_pid" 2>/dev/null && echo yes || echo no
}

stop_event() {
  local session="$1" active="${2:-false}"
  jq -cn --arg session "$session" --arg cwd "$repo" --arg transcript "$transcript" --argjson active "$active" \
    '{session_id: $session, hook_event_name: "Stop", cwd: $cwd, transcript_path: $transcript, stop_hook_active: $active}' \
    | python3 "$hook"
  echo "exit $?"
}

nudged_state() {
  local session="$1" nudged_at="$2"
  printf '{"nudged_at": %s, "percent": 71}' "$nudged_at" > "$state_dir/$session.json"
}

expect_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label (want '$want', got '$got')"
    failures=$((failures + 1))
  fi
}

sentinel_state() { test -f "$relaunch_dir/relaunch" && echo yes || echo no; }
sentinel_field() { jq -r ".$1" "$relaunch_dir/relaunch"; }
block_line='{"decision": "block", "reason": "Context budget at 71%: call the handoff skill with save now, then stop."}'

start_sleeper
nudged_state s1 "$(($(date +%s) - 60))"
echo '# Note' > "$notes/2026-11-02-1200-topic.md"
expect_eq "a fresh note after the nudge exits 0" "exit 0" "$(CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" stop_event s1)"
expect_eq "it writes the sentinel" yes "$(sentinel_state)"
expect_eq "the sentinel names the note" "$notes/2026-11-02-1200-topic.md" "$(sentinel_field note)"
expect_eq "the sentinel carries the last real prompt with newlines collapsed" "Fix the failing launcher test" "$(sentinel_field prompt)"
expect_eq "the sentinel carries the percent" 71 "$(sentinel_field percent)"
expect_eq "it terminates the pid the launcher wrote" no "$(sleeper_alive)"
rm -f "$relaunch_dir/relaunch"

start_sleeper
expect_eq "the same session never fires twice" "exit 0" "$(CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" stop_event s1)"
expect_eq "no second sentinel" no "$(sentinel_state)"
expect_eq "the process is left alone the second time" yes "$(sleeper_alive)"

nudged_state s2 "$(($(date +%s) + 3600))"
expect_eq "a nudge without a fresh note blocks the stop once" "$block_line
exit 0" "$(CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" stop_event s2)"
expect_eq "the state remembers the block" true "$(jq .blocked_once "$state_dir/s2.json")"
expect_eq "no sentinel while blocking" no "$(sentinel_state)"
expect_eq "the process stays while blocking" yes "$(sleeper_alive)"
expect_eq "the second stop without a note is silent" "exit 0" "$(CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" stop_event s2)"
expect_eq "no sentinel for the old note" no "$(sentinel_state)"

rm -f "$notes/2026-11-02-1200-topic.md"
nudged_state s2b "$(($(date +%s) - 60))"
expect_eq "a blocked session with a fresh note still relaunches" "$block_line
exit 0" "$(CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" stop_event s2b)"
echo '# Note' > "$notes/2026-11-02-1300-later.md"
expect_eq "the fresh note after the block exits 0" "exit 0" "$(CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" stop_event s2b)"
expect_eq "and writes the sentinel" "$notes/2026-11-02-1300-later.md" "$(sentinel_field note)"
expect_eq "and terminates claude" no "$(sleeper_alive)"
rm -f "$relaunch_dir/relaunch" "$notes/2026-11-02-1300-later.md"
echo '# Note' > "$notes/2026-11-02-1200-topic.md"

start_sleeper
nudged_state s2c "$(($(date +%s) + 3600))"
expect_eq "stop_hook_active never blocks" "exit 0" "$(CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" stop_event s2c true)"
expect_eq "and leaves the state unblocked" null "$(jq .blocked_once "$state_dir/s2c.json")"

expect_eq "a session that was never nudged does not fire" "exit 0" "$(CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" stop_event s3)"
expect_eq "no sentinel without a nudge" no "$(sentinel_state)"

nudged_state s4 "$(($(date +%s) - 60))"
expect_eq "no relaunch dir means nothing happens" "exit 0" "$(stop_event s4)"
expect_eq "no sentinel without a relaunch dir" no "$(sentinel_state)"
expect_eq "the process stays without a relaunch dir" yes "$(sleeper_alive)"

nudged_state s7 "$(($(date +%s) - 60))"
expect_eq "a cwd outside a git repo blocks once and exits 0" "$block_line
exit 0" "$(jq -cn --arg cwd "$sandbox" '{session_id: "s7", hook_event_name: "Stop", cwd: $cwd}' | CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" python3 "$hook"; echo "exit $?")"
expect_eq "no sentinel outside a git repo" no "$(sentinel_state)"

nudged_state s8 "$(($(date +%s) - 60))"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"/handoff"}}' > "$sandbox/slash-only.jsonl"
expect_eq "a transcript with only skipped prompts gives an empty prompt" "exit 0" "$(jq -cn --arg cwd "$repo" --arg transcript "$sandbox/slash-only.jsonl" '{session_id: "s8", hook_event_name: "Stop", cwd: $cwd, transcript_path: $transcript}' | CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" python3 "$hook"; echo "exit $?")"
expect_eq "the sentinel prompt is empty" "" "$(sentinel_field prompt)"
rm -f "$relaunch_dir/relaunch"

nudged_state s9 "$(($(date +%s) - 60))"
expect_eq "a missing transcript gives an empty prompt" "exit 0" "$(jq -cn --arg cwd "$repo" '{session_id: "s9", hook_event_name: "Stop", cwd: $cwd}' | CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" python3 "$hook"; echo "exit $?")"
expect_eq "the sentinel prompt is empty without a transcript" "" "$(sentinel_field prompt)"
rm -f "$relaunch_dir/relaunch"

expect_eq "--inspect prints the prompt it would pick" "Fix the failing launcher test" "$(python3 "$hook" --inspect "$transcript")"
long_prompt="$(printf 'word %.0s' $(seq 60))"
printf '{"type":"user","message":{"role":"user","content":"%s"}}\n' "$long_prompt" > "$sandbox/long.jsonl"
expect_eq "--inspect clips the prompt to 200 characters" 200 "$(python3 "$hook" --inspect "$sandbox/long.jsonl" | tr -d '\n' | wc -c | tr -d ' ')"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
