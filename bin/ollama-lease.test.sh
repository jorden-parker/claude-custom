#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
lease="$repo/bin/ollama-lease"
tmp="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
failures=0
sleepers=""

stop_sleepers() {
  local pid
  for pid in $sleepers; do
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
  done
}

trap 'stop_sleepers; rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

check_eq() {
  [ "$2" = "$3" ] || fail "$1: expected [$2] got [$3]"
}

check_that() {
  local name="$1"
  shift
  "$@" || fail "$name"
}

check_not() {
  local name="$1"
  shift
  if "$@"; then fail "$name"; fi
}

pid_alive() {
  kill -0 "$1" 2>/dev/null
}

sleeper() {
  local pid
  sleep 60 >/dev/null 2>&1 &
  pid=$!
  sleepers="$sleepers $pid"
  echo "$pid"
}

mkdir -p "$tmp/stubbin"
cat > "$tmp/stubbin/pgrep" <<'EOF'
#!/bin/sh
[ -n "${STUB_OLLAMA_PID:-}" ] && echo "$STUB_OLLAMA_PID"
EOF
cat > "$tmp/stubbin/ps" <<'EOF'
#!/bin/sh
echo "ollama serve ${STUB_OLLAMA_ENV:-}"
EOF
cat > "$tmp/stubbin/curl" <<EOF
#!/bin/sh
echo "\$*" >> "$tmp/curl.log"
EOF
chmod +x "$tmp/stubbin/pgrep" "$tmp/stubbin/ps" "$tmp/stubbin/curl"
export PATH="$tmp/stubbin:/usr/bin:/bin"
export HOME="$tmp/home"
export CLAUDE_OLLAMA_LEASE_DIR="$tmp/lease"
export STUB_OLLAMA_PID=42

run() {
  "$@" >"$tmp/out" 2>"$tmp/err"
}

mode_of() {
  stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"
}

session_pid="$(sleeper)"
STUB_OLLAMA_ENV="OLLAMA_MAX_LOADED_MODELS=1" run "$lease" acquire session --model qwen3.8-27b-cc --pid "$session_pid" --num-ctx 65536
check_eq "acquire when free exits 0" 0 "$?"
check_that "acquire writes a lease file named by the pid" test -f "$tmp/lease/$session_pid.json"
check_eq "the lease dir is private" 700 "$(mode_of "$tmp/lease")"
check_eq "the lease file is private" 600 "$(mode_of "$tmp/lease/$session_pid.json")"
check_eq "the lease names the holder" session "$(jq -r .name "$tmp/lease/$session_pid.json")"
check_eq "the lease names the model" qwen3.8-27b-cc "$(jq -r .model "$tmp/lease/$session_pid.json")"
check_eq "the lease records num_ctx" 65536 "$(jq -r .num_ctx "$tmp/lease/$session_pid.json")"
check_eq "the lease starts with no rung" null "$(jq -r .rung "$tmp/lease/$session_pid.json")"
check_that "the lease records when it started" grep -qE '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' <<< "$(jq -r .started "$tmp/lease/$session_pid.json")"

review_pid="$(sleeper)"
STUB_OLLAMA_ENV="OLLAMA_MAX_LOADED_MODELS=1" run "$lease" acquire review --model qwen3.6-35b-cc --pid "$review_pid"
check_eq "a second model is refused when the server keeps one" 3 "$?"
check_eq "the refusal names the session holder" \
  "ollama lease: held by session (pid $session_pid, model qwen3.8-27b-cc); run after that session ends or set OLLAMA_MAX_LOADED_MODELS=2" "$(cat "$tmp/err")"
check_not "a refused acquire writes no lease" test -e "$tmp/lease/$review_pid.json"

STUB_OLLAMA_ENV="OLLAMA_MAX_LOADED_MODELS=1" run "$lease" acquire review --model qwen3.8-27b-cc --pid "$review_pid"
check_eq "the same model is accepted when the server keeps one" 0 "$?"
run "$lease" release review --pid "$review_pid"
check_eq "release exits 0" 0 "$?"
check_not "release removes the lease file" test -e "$tmp/lease/$review_pid.json"

STUB_OLLAMA_ENV="OLLAMA_MAX_LOADED_MODELS=2" run "$lease" acquire review --model qwen3.6-35b-cc --pid "$review_pid"
check_eq "a second model is accepted when the server keeps two" 0 "$?"
check_that "the second holder gets its own file" test -f "$tmp/lease/$review_pid.json"

third_pid="$(sleeper)"
STUB_OLLAMA_ENV="OLLAMA_MAX_LOADED_MODELS=2" run "$lease" acquire mock-spike --model granite4.2-3b-cc --pid "$third_pid"
check_eq "a third model is refused when the server keeps two" 3 "$?"

run env STUB_OLLAMA_PID= "$lease" acquire review --model qwen3.6-35b-cc --pid "$third_pid"
check_eq "without a running server a second model is refused" 3 "$?"

STUB_OLLAMA_ENV="OLLAMA_MAX_LOADED_MODELS=2" run "$lease" acquire speed-check --pid "$third_pid" --exclusive
check_eq "an exclusive acquire is refused while a session lease exists" 3 "$?"
check_that "the exclusive refusal names the session holder" grep -qF "held by session (pid $session_pid" "$tmp/err"

STUB_OLLAMA_ENV="OLLAMA_MAX_LOADED_MODELS=2" run "$lease" acquire session --model qwen3.8-27b-cc --pid "$session_pid" --rung context-down
check_eq "a holder may acquire again to record its rung" 0 "$?"
check_eq "the rung is recorded" context-down "$(jq -r .rung "$tmp/lease/$session_pid.json")"

run "$lease" holders
check_eq "holders exits 0" 0 "$?"
check_that "holders lists the session" grep -qxF "live session pid $session_pid model qwen3.8-27b-cc rung context-down" "$tmp/out"
check_that "holders lists the review" grep -qxF "live review pid $review_pid model qwen3.6-35b-cc rung -" "$tmp/out"

dead_pid="$(sleeper)"
kill "$dead_pid"
wait "$dead_pid" 2>/dev/null
printf '{"name":"session","model":"old","num_ctx":null,"rung":null,"started":"2026-01-01T00:00:00Z"}\n' > "$tmp/lease/$dead_pid.json"
run "$lease" holders
check_that "holders reports a lease whose pid is dead as stale" grep -qxF "stale session pid $dead_pid model old" "$tmp/out"
check_not "holders removes the stale lease" test -e "$tmp/lease/$dead_pid.json"
printf '{"name":"session","model":"old","num_ctx":null,"rung":null,"started":"2026-01-01T00:00:00Z"}\n' > "$tmp/lease/$dead_pid.json"
echo "not json" > "$tmp/lease/notes.json"
STUB_OLLAMA_ENV="OLLAMA_MAX_LOADED_MODELS=2" run "$lease" acquire mock-spike --model qwen3.8-27b-cc --pid "$third_pid"
check_eq "a dead holder never blocks an acquire" 0 "$?"
check_not "acquire removes the stale lease" test -e "$tmp/lease/$dead_pid.json"
check_that "a file that is not a pid is left alone" test -e "$tmp/lease/notes.json"
run "$lease" release mock-spike --pid "$third_pid"

waiting_pid="$(sleeper)"
STUB_OLLAMA_ENV="OLLAMA_MAX_LOADED_MODELS=2" CLAUDE_OLLAMA_LEASE_POLL=0.1 "$lease" acquire bench --model granite4.2-3b-cc --pid "$waiting_pid" --wait 5 >"$tmp/wait.out" 2>"$tmp/wait.err" &
waiter=$!
sleep 0.5
check_that "a waiting acquire holds no lease yet" test ! -e "$tmp/lease/$waiting_pid.json"
run "$lease" release review --pid "$review_pid"
wait "$waiter"
check_eq "a waiting acquire succeeds once a holder releases" 0 "$?"
check_that "the waiting acquire then holds its lease" test -f "$tmp/lease/$waiting_pid.json"
run "$lease" release bench --pid "$waiting_pid"

STUB_OLLAMA_ENV="OLLAMA_MAX_LOADED_MODELS=1" CLAUDE_OLLAMA_LEASE_POLL=0.1 run "$lease" acquire bench --model granite4.2-3b-cc --pid "$waiting_pid" --wait 0.3
check_eq "a waiting acquire gives up after its seconds" 3 "$?"
check_that "and prints the refusal once" grep -qxF "ollama lease: held by session (pid $session_pid, model qwen3.8-27b-cc); run after that session ends or set OLLAMA_MAX_LOADED_MODELS=2" "$tmp/err"
check_eq "the refusal is one line" 1 "$(wc -l < "$tmp/err" | tr -d ' ')"

watched_pid="$(sleeper)"
STUB_OLLAMA_ENV="OLLAMA_MAX_LOADED_MODELS=2" run "$lease" acquire session --model qwen3.6-35b-cc --pid "$watched_pid"
rm -f "$tmp/curl.log"
CLAUDE_OLLAMA_LEASE_HEARTBEAT=0.2 "$lease" heartbeat --watch-pid "$watched_pid" --fast-marker "$tmp/heartbeat-fast" >/dev/null 2>&1 &
heartbeat_pid=$!
for _ in $(seq 30); do [ -s "$tmp/curl.log" ] && break; sleep 0.1; done
check_that "the heartbeat sends a keep_alive request for the leased model" grep -q 'api/generate.*"model":"qwen3.6-35b-cc","keep_alive":"30m"' "$tmp/curl.log"
kill "$watched_pid"
wait "$watched_pid" 2>/dev/null
for _ in $(seq 30); do pid_alive "$heartbeat_pid" || break; sleep 0.1; done
check_not "the heartbeat stops when the watched pid dies" pid_alive "$heartbeat_pid"
rm -f "$tmp/curl.log"
: > "$tmp/heartbeat-fast"
fast_pid="$(sleeper)"
CLAUDE_OLLAMA_LEASE_HEARTBEAT=4 CLAUDE_OLLAMA_KEEP_ALIVE=5m "$lease" heartbeat --watch-pid "$fast_pid" --model qwen3.8-27b-cc --fast-marker "$tmp/heartbeat-fast" >/dev/null 2>&1 &
sleepers="$sleepers $!"
sleep 3
check_that "with the fast marker the heartbeat halves its interval" grep -q '"model":"qwen3.8-27b-cc","keep_alive":"5m"' "$tmp/curl.log"

run "$lease" acquire
check_eq "acquire without a name exits 2" 2 "$?"
run "$lease" bogus
check_eq "an unknown subcommand exits 2" 2 "$?"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
