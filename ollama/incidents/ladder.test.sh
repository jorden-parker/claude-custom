#!/usr/bin/env bash
set -u
umask 022
here="$(cd "$(dirname "$0")" && pwd)"
ladder="$here/ladder.py"
sizes="$here/../sizes.json"
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

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "ok: $name"
  else
    echo "FAIL: $name"
    failures=$((failures + 1))
  fi
}

equals() {
  if [ "$1" != "$2" ]; then
    echo "  want: $1"
    echo "  got:  $2"
    return 1
  fi
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

terminated() {
  for _ in $(seq 50); do
    if ! pid_alive "$1" || [ "$(ps -o stat= -p "$1" | cut -c1)" = Z ]; then return 0; fi
    sleep 0.1
  done
  return 1
}

eventually() {
  for _ in $(seq 60); do
    "$@" && return 0
    sleep 0.1
  done
  return 1
}

row() {
  local cause="$1" ts="$2" preceded="${3:-}"
  if [ -n "$preceded" ]; then
    printf '{"ts": "%s", "cause": "%s", "detail": "d", "tokens": null, "rule": "r", "preceded_by": {"kind": "%s", "ts": "%s"}}\n' "$ts" "$cause" "$preceded" "$ts"
  else
    printf '{"ts": "%s", "cause": "%s", "detail": "d", "tokens": null, "rule": "r"}\n' "$ts" "$cause"
  fi
}

rows_with() {
  local field="$1" value="$2"
  python3 -c 'import json, sys; rows = [json.loads(line) for line in sys.stdin if line.strip()]; print(sum(1 for row in rows if row.get(sys.argv[1]) == sys.argv[2]))' "$field" "$value"
}

field_of_cause() {
  python3 -c 'import json, sys; rows = [json.loads(line) for line in sys.stdin if line.strip()]; print(*(row[sys.argv[2]] for row in rows if row.get("cause") == sys.argv[1]))' "$1" "$2"
}

new_session() {
  rm -rf "$tmp/relaunch" "$tmp/incidents.jsonl" "$tmp/incidents.jsonl.latest"
  mkdir -p "$tmp/relaunch"
  : > "$tmp/incidents.jsonl"
}

run_once() {
  python3 "$ladder" --once --incidents "$tmp/incidents.jsonl" --relaunch-dir "$tmp/relaunch" --context "${1:-65536}" --sizes "$sizes"
}

{
  row reprefilled 2026-05-01T10:00:00Z embed
  row reprefilled 2026-05-01T10:04:00Z embed
  row reprefilled 2026-05-01T10:09:00Z embed
} > "$tmp/embed.jsonl"
check "inspect names the embeddings-off rung for three re-prefills after an embed request within ten minutes" \
  equals "embeddings-off: 3 re-prefills after an embed request within 10 minutes" "$(python3 "$ladder" --inspect "$tmp/embed.jsonl")"

{
  row reprefilled 2026-05-01T10:00:00Z embed
  row reprefilled 2026-05-01T10:15:00Z embed
  row reprefilled 2026-05-01T10:30:00Z embed
} > "$tmp/spread.jsonl"
check "inspect fires nothing when the three are spread over half an hour" equals none "$(python3 "$ladder" --inspect "$tmp/spread.jsonl")"

{
  row reprefilled 2026-05-01T10:00:00Z load
  row reprefilled 2026-05-01T10:01:00Z
  row reprefilled 2026-05-01T10:02:00Z unload
  row aborted 2026-05-01T10:03:00Z
  row evicted 2026-05-01T10:04:00Z
} > "$tmp/unattributed.jsonl"
check "inspect fires nothing on rows no rung is bound to" equals none "$(python3 "$ladder" --inspect "$tmp/unattributed.jsonl")"

{
  row reprefilled 2026-05-01T10:00:00Z expired
  row reprefilled 2026-05-01T10:01:00Z expired
  row reprefilled 2026-05-01T10:02:00Z expired
  row truncated 2026-05-01T10:03:00Z
  row truncated 2026-05-01T10:04:00Z
  row truncated 2026-05-01T10:05:00Z
} > "$tmp/both.jsonl"
check "inspect lists every rung that would fire" equals "heartbeat: 3 re-prefills after a keep-alive expiry within 10 minutes
context-down: 3 truncated prompts within 10 minutes" "$(python3 "$ladder" --inspect "$tmp/both.jsonl")"

new_session
cat "$tmp/embed.jsonl" "$tmp/unattributed.jsonl" > "$tmp/incidents.jsonl"
row reprefilled 2026-05-01T10:10:00Z embed >> "$tmp/incidents.jsonl"
run_once
check "once mode exit status" equals 0 "$?"
check "embeddings-off writes the embed-off file the launcher and the search server read" test -e "$tmp/relaunch/embed-off"
check "embeddings-off appends one degraded row even with a fourth embed re-prefill" equals 1 "$(rows_with cause degraded < "$tmp/incidents.jsonl")"
check "the degraded row names the rung and the reason" equals "embeddings-off: 3 re-prefills after an embed request within 10 minutes" "$(field_of_cause degraded detail < "$tmp/incidents.jsonl")"
check "the degraded row carries the ladder rule" equals "ladder/embeddings-off" "$(field_of_cause degraded rule < "$tmp/incidents.jsonl")"
check "the degraded row is also the latest incident" grep -q '"cause": "degraded"' "$tmp/incidents.jsonl.latest"
check "a row no rung is bound to gets a ladder note" grep -q '"kind": "ladder"' "$tmp/incidents.jsonl"
check "the note says which rows were not bound" grep -q '"note": "reprefilled after load: no rung"' "$tmp/incidents.jsonl"
check "the same kind of row is noted once" equals 1 "$(grep -c 'reprefilled after load' "$tmp/incidents.jsonl")"
check "a row without a preceding event is noted as such" grep -q '"note": "reprefilled: no rung"' "$tmp/incidents.jsonl"
check "no heartbeat marker without expiry evidence" test ! -e "$tmp/relaunch/heartbeat-fast"
check "no ladder file without truncation evidence" test ! -e "$tmp/relaunch/ladder"

new_session
{
  row reprefilled 2026-05-01T10:00:00Z expired
  row reprefilled 2026-05-01T10:01:00Z expired
  row reprefilled 2026-05-01T10:02:00Z expired
} > "$tmp/incidents.jsonl"
run_once
check "heartbeat writes the marker that halves the heartbeat interval" test -e "$tmp/relaunch/heartbeat-fast"
check "heartbeat appends its degraded row" equals "ladder/heartbeat" "$(field_of_cause degraded rule < "$tmp/incidents.jsonl")"
check "heartbeat writes no embed-off file" test ! -e "$tmp/relaunch/embed-off"

mkdir -p "$tmp/stubbin"
cat > "$tmp/stubbin/ps" <<EOF
#!/bin/sh
cat "$tmp/ps-comm"
EOF
chmod +x "$tmp/stubbin/ps"
echo node > "$tmp/ps-comm"
new_session
claude_pid="$(sleeper)"
echo "$claude_pid" > "$tmp/relaunch/claude.pid"
{
  row truncated 2026-05-01T10:00:00Z
  row truncated 2026-05-01T10:01:00Z
  row truncated 2026-05-01T10:02:00Z
} > "$tmp/incidents.jsonl"
PATH="$tmp/stubbin:$PATH" run_once 65536
check "context-down writes the ladder file" test -e "$tmp/relaunch/ladder"
check "the ladder file names the rung" equals context-down "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["rung"])' "$tmp/relaunch/ladder")"
check "the ladder file lowers the context to the next configured size" equals 32768 "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["context"])' "$tmp/relaunch/ladder")"
check "the ladder file carries the reason" equals "3 truncated prompts within 10 minutes" "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["reason"])' "$tmp/relaunch/ladder")"
check "context-down terminates the claude process named in claude.pid" terminated "$claude_pid"
check "context-down appends its degraded row" equals "ladder/context-down" "$(field_of_cause degraded rule < "$tmp/incidents.jsonl")"

new_session
{
  row truncated 2026-05-01T10:00:00Z
  row truncated 2026-05-01T10:01:00Z
  row truncated 2026-05-01T10:02:00Z
} > "$tmp/incidents.jsonl"
run_once 32768
check "below the smallest size the context drops to three quarters rounded to 1024" equals 24576 "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["context"])' "$tmp/relaunch/ladder")"

echo sleep > "$tmp/ps-comm"
new_session
other_pid="$(sleeper)"
echo "$other_pid" > "$tmp/relaunch/claude.pid"
cp "$tmp/both.jsonl" "$tmp/incidents.jsonl"
PATH="$tmp/stubbin:$PATH" run_once
sleep 0.3
check "context-down never signals a pid that is not a claude process" pid_alive "$other_pid"
check "the ladder file is still written" test -e "$tmp/relaunch/ladder"

new_session
watched_pid="$(sleeper)"
python3 "$ladder" --incidents "$tmp/incidents.jsonl" --relaunch-dir "$tmp/relaunch" --context 65536 --sizes "$sizes" --watch-pid "$watched_pid" --interval 0.1 &
ladder_pid=$!
sleepers="$sleepers $ladder_pid"
sleep 0.3
row reprefilled 2026-05-01T10:00:00Z embed >> "$tmp/incidents.jsonl"
row reprefilled 2026-05-01T10:01:00Z embed >> "$tmp/incidents.jsonl"
sleep 0.3
check "follow mode waits for the third piece of evidence" test ! -e "$tmp/relaunch/embed-off"
row reprefilled 2026-05-01T10:02:00Z embed >> "$tmp/incidents.jsonl"
check "follow mode fires once the evidence arrives" eventually test -e "$tmp/relaunch/embed-off"
kill "$watched_pid"
wait "$watched_pid" 2>/dev/null
check "follow mode stops when the watched pid dies" terminated "$ladder_pid"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
