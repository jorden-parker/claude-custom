#!/usr/bin/env bash
set -u
hook="$(cd "$(dirname "$0")" && pwd)/handoff-relaunch.py"
failures=0
sandbox="$(mktemp -d)"
export HOME="$sandbox/home"
repo="$sandbox/repo"
relaunch_dir="$sandbox/relaunch"
state_dir="$HOME/.claude/cache/context-budget"
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
  local session="$1"
  jq -cn --arg session "$session" --arg cwd "$repo" \
    '{session_id: $session, hook_event_name: "Stop", cwd: $cwd, stop_hook_active: false}' \
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

start_sleeper
nudged_state s1 "$(($(date +%s) - 60))"
echo '# Note' > "$notes/2026-11-02-1200-topic.md"
expect_eq "a fresh note after the nudge exits 0" "exit 0" "$(CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" stop_event s1)"
expect_eq "it writes the sentinel" yes "$(sentinel_state)"
expect_eq "the sentinel names the note" "$notes/2026-11-02-1200-topic.md" "$(cat "$relaunch_dir/relaunch")"
expect_eq "it terminates the pid the launcher wrote" no "$(sleeper_alive)"
rm -f "$relaunch_dir/relaunch"

start_sleeper
expect_eq "the same session never fires twice" "exit 0" "$(CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" stop_event s1)"
expect_eq "no second sentinel" no "$(sentinel_state)"
expect_eq "the process is left alone the second time" yes "$(sleeper_alive)"

nudged_state s2 "$(($(date +%s) + 3600))"
expect_eq "a note older than the nudge does not fire" "exit 0" "$(CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" stop_event s2)"
expect_eq "no sentinel for the old note" no "$(sentinel_state)"
expect_eq "the process stays for the old note" yes "$(sleeper_alive)"

expect_eq "a session that was never nudged does not fire" "exit 0" "$(CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" stop_event s3)"
expect_eq "no sentinel without a nudge" no "$(sentinel_state)"

nudged_state s4 "$(($(date +%s) - 60))"
expect_eq "no relaunch dir means nothing happens" "exit 0" "$(stop_event s4)"
expect_eq "no sentinel without a relaunch dir" no "$(sentinel_state)"
expect_eq "the process stays without a relaunch dir" yes "$(sleeper_alive)"

nudged_state s5 "$(($(date +%s) - 60))"
expect_eq "a pid that is not a claude process is not signalled" "exit 0" "$(STUB_PS_COMM=/bin/sleep CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" stop_event s5)"
expect_eq "but the sentinel is still written" yes "$(sentinel_state)"
expect_eq "the foreign process stays" yes "$(sleeper_alive)"
rm -f "$relaunch_dir/relaunch"

nudged_state s6 "$(($(date +%s) - 60))"
rm -f "$relaunch_dir/claude.pid"
expect_eq "a missing pid file never blocks the stop" "exit 0" "$(CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" stop_event s6)"
expect_eq "the sentinel is written without a pid file" yes "$(sentinel_state)"
rm -f "$relaunch_dir/relaunch"

nudged_state s7 "$(($(date +%s) - 60))"
expect_eq "a cwd outside a git repo exits 0" "exit 0" "$(jq -cn --arg cwd "$sandbox" '{session_id: "s7", hook_event_name: "Stop", cwd: $cwd}' | CLAUDE_OLLAMA_RELAUNCH_DIR="$relaunch_dir" python3 "$hook"; echo "exit $?")"
expect_eq "no sentinel outside a git repo" no "$(sentinel_state)"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
