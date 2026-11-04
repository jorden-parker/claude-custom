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

mkdir -p "$tmp/stubbin"
cat > "$tmp/stubbin/ollama-lease" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$tmp/fit-args"
printf '{"fits": %s}\n' "\${STUB_FIT:-true}"
EOF
chmod +x "$tmp/stubbin/ollama-lease"

run_once() {
  python3 "$ladder" --once --incidents "$tmp/incidents.jsonl" --relaunch-dir "$tmp/relaunch" --context "${1:-65536}" --sizes "$sizes" \
    --model qwen3.8-27b-cc --embedding qwen3-embedding:0.6b --lease-bin "$tmp/stubbin/ollama-lease" "${@:2}"
}

ladder_up_field() {
  python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$tmp/relaunch/ladder-up" "$1"
}

recent_row() {
  row "$1" "$(date -u -v "+${2}S" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "+${2} seconds" +%Y-%m-%dT%H:%M:%SZ)" "${3:-}"
}

{
  row reprefilled 2026-05-01T10:00:00Z embed
  row reprefilled 2026-05-01T10:04:00Z embed
  row reprefilled 2026-05-01T10:09:00Z embed
} > "$tmp/embed.jsonl"
check "inspect names the embeddings-off rung for three re-prefills after an embed request within ten minutes, then its pending recovery" \
  equals "embeddings-off: 3 re-prefills after an embed request within 10 minutes
up embeddings-off: 20 minutes without re-prefills after an embed request" "$(python3 "$ladder" --inspect "$tmp/embed.jsonl")"

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
  row reprefilled 2026-05-01T10:00:00Z embed
  row reprefilled 2026-05-01T10:01:00Z embed
  row reprefilled 2026-05-01T10:02:00Z embed
  row reprefilled 2026-05-01T10:03:00Z expired
  row reprefilled 2026-05-01T10:04:00Z expired
  row reprefilled 2026-05-01T10:05:00Z expired
  row truncated 2026-05-01T10:06:00Z
  row truncated 2026-05-01T10:07:00Z
  row truncated 2026-05-01T10:08:00Z
} > "$tmp/both.jsonl"
check "inspect lists every rung that would fire and their pending recoveries, last rung first" equals "embeddings-off: 3 re-prefills after an embed request within 10 minutes
context-down: 3 truncated prompts within 10 minutes
up context-down: 20 minutes without truncated prompts
up embeddings-off: 20 minutes without re-prefills after an embed request" "$(python3 "$ladder" --inspect "$tmp/both.jsonl")"

{
  row reprefilled 2026-05-01T10:00:00Z expired
  row reprefilled 2026-05-01T10:01:00Z expired
  row reprefilled 2026-05-01T10:02:00Z expired
} > "$tmp/expired.jsonl"
check "inspect fires nothing on re-prefills after a keep-alive expiry" equals none "$(python3 "$ladder" --inspect "$tmp/expired.jsonl")"

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
check "no ladder file without truncation evidence" test ! -e "$tmp/relaunch/ladder"

new_session
cp "$tmp/expired.jsonl" "$tmp/incidents.jsonl"
run_once
check "expiry evidence appends no degraded row" equals 0 "$(rows_with cause degraded < "$tmp/incidents.jsonl")"
check "expiry evidence is noted as bound to no rung" grep -q '"note": "reprefilled after expired: no rung"' "$tmp/incidents.jsonl"
check "expiry evidence is noted once" equals 1 "$(grep -c 'reprefilled after expired' "$tmp/incidents.jsonl")"
check "expiry evidence raises no flag" equals "" "$(find "$tmp/relaunch" -mindepth 1 ! -name claude.pid)"
check "expiry evidence writes no ladder file" test ! -e "$tmp/relaunch/ladder"

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

new_session
cat "$tmp/embed.jsonl" > "$tmp/incidents.jsonl"
rm -f "$tmp/fit-args"
run_once
check "a rung quiet for 20 minutes with a passing fit writes the ladder-up file" test -e "$tmp/relaunch/ladder-up"
check "the ladder-up names the rung" equals embeddings-off "$(ladder_up_field rung)"
check "the ladder-up carries the reason" equals "20 minutes without re-prefills after an embed request, memory fits" "$(ladder_up_field reason)"
check "the recovery fit asks for the embedding model at the full context" equals "fit --model qwen3.8-27b-cc --num-ctx 65536 --embedding qwen3-embedding:0.6b" "$(cat "$tmp/fit-args")"
check "the recovery writes no degraded row of its own" equals 1 "$(rows_with cause degraded < "$tmp/incidents.jsonl")"

new_session
cat "$tmp/embed.jsonl" > "$tmp/incidents.jsonl"
STUB_FIT=false run_once
check "a failing fit writes no ladder-up" test ! -e "$tmp/relaunch/ladder-up"

for zone in America/Los_Angeles Asia/Tokyo; do
  new_session
  cat "$tmp/embed.jsonl" > "$tmp/incidents.jsonl"
  TZ=$zone run_once
  check "old rows are recovered under TZ=$zone" test -e "$tmp/relaunch/ladder-up"

  new_session
  {
    recent_row reprefilled 0 embed
    recent_row reprefilled 1 embed
    recent_row reprefilled 2 embed
  } > "$tmp/incidents.jsonl"
  TZ=$zone run_once
  check "fresh rows are not recovered under TZ=$zone" test ! -e "$tmp/relaunch/ladder-up"
done

new_session
{
  row reprefilled 2026-05-01T10:00:00.123Z embed
  row reprefilled 2026-05-01T10:04:00.456Z embed
  row reprefilled 2026-05-01T10:09:00.789Z embed
} > "$tmp/incidents.jsonl"
run_once
check "rows with milliseconds are read at their own time, not as now" test -e "$tmp/relaunch/ladder-up"

new_session
rm -f "$tmp/fit-args"
{
  recent_row reprefilled 0 embed
  recent_row reprefilled 1 embed
  recent_row reprefilled 2 embed
} > "$tmp/incidents.jsonl"
run_once
check "a rung with a fresh incident is not recovered yet" test ! -e "$tmp/relaunch/ladder-up"
check "and no fit runs before the quiet window" test ! -e "$tmp/fit-args"

new_session
rm -f "$tmp/fit-args"
{
  cat "$tmp/embed.jsonl"
  row truncated 2026-05-01T10:20:00Z
  row truncated 2026-05-01T10:21:00Z
  row truncated 2026-05-01T10:22:00Z
} > "$tmp/incidents.jsonl"
run_once
check "with two rungs fired the last one down is the first one up" equals context-down "$(ladder_up_field rung)"
check "the context-down fit keeps the embeddings off while that rung is still in effect" equals "fit --model qwen3.8-27b-cc --num-ctx 65536" "$(cat "$tmp/fit-args")"

new_session
rm -f "$tmp/fit-args"
run_once 65536 --rung context-down --rung embeddings-off --quiet-seconds 0
check "a rung in effect since launch is recovered once the quiet window passes" equals embeddings-off "$(ladder_up_field rung)"
check "the embeddings-off fit uses the lowered context while context-down is in effect" equals "fit --model qwen3.8-27b-cc --num-ctx 32768 --embedding qwen3-embedding:0.6b" "$(cat "$tmp/fit-args")"
check "a launch rung's reason names the quiet window" equals "0 minutes without re-prefills after an embed request, memory fits" "$(ladder_up_field reason)"

new_session
rm -f "$tmp/fit-args"
cat "$tmp/embed.jsonl" > "$tmp/incidents.jsonl"
row truncated 2026-05-01T10:20:00Z >> "$tmp/incidents.jsonl"
row truncated 2026-05-01T10:21:00Z >> "$tmp/incidents.jsonl"
row truncated 2026-05-01T10:22:00Z >> "$tmp/incidents.jsonl"
watched_pid="$(sleeper)"
python3 "$ladder" --incidents "$tmp/incidents.jsonl" --relaunch-dir "$tmp/relaunch" --context 65536 --sizes "$sizes" --watch-pid "$watched_pid" --interval 0.1 \
  --model qwen3.8-27b-cc --embedding qwen3-embedding:0.6b --lease-bin "$tmp/stubbin/ollama-lease" &
ladder_pid=$!
sleepers="$sleepers $ladder_pid"
check "follow mode proposes the first recovery" eventually test -e "$tmp/relaunch/ladder-up"
check "follow mode starts with the last rung down" equals context-down "$(ladder_up_field rung)"
sleep 0.5
check "follow mode proposes one rung per relaunch" equals 1 "$(wc -l < "$tmp/fit-args" | tr -d ' ')"
rm -f "$tmp/relaunch/ladder-up"
check "once the launcher took the file the next rung is proposed" eventually test -e "$tmp/relaunch/ladder-up"
check "the second recovery is the rung below" equals embeddings-off "$(ladder_up_field rung)"
check "the second fit asks for the embeddings at the recovered context" equals "fit --model qwen3.8-27b-cc --num-ctx 65536 --embedding qwen3-embedding:0.6b" "$(tail -n 1 "$tmp/fit-args")"
kill "$watched_pid"
wait "$watched_pid" 2>/dev/null
check "follow mode with recoveries stops when the watched pid dies" terminated "$ladder_pid"

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
