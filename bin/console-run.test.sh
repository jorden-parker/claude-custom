#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
runner="$repo/bin/console-run"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
failures=0
run_id="20261026-101500-doctor-3fa9"
runs="$sandbox/fresh/runs"
first="$runs/first.jsonl"

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

run_child() {
  local log="$1"
  shift
  "$runner" --log "$log" --id "$run_id" --command doctor --label "Doctor (27b)" -- "$@"
}

has_event() {
  jq -e -s "any(.[]; $2)" "$1" >/dev/null
}

last_event_matches() {
  jq -e -s ".[-1] | $2" "$1" >/dev/null
}

first_event_matches() {
  jq -e -s ".[0] | $2" "$1" >/dev/null
}

mode_is() {
  [ -n "$(find "$1" -maxdepth 0 -perm "$2" 2>/dev/null)" ]
}

rejects_existing_log() {
  local log="$1"
  printf 'keep\n' >"$log"
  run_child "$log" bash -c 'exit 0' 2>/dev/null
  local status=$?
  [ "$status" -eq 2 ] && [ "$(cat "$log")" = keep ]
}

cancel_stops_child() {
  local log="$1"
  local waited=0
  "$runner" --log "$log" --id "$run_id" --command doctor --label "Doctor (27b)" -- bash -c 'echo $$; exec sleep 30' &
  local runner_pid=$!
  while ! grep -q '"kind":"line"' "$log" 2>/dev/null && [ "$waited" -lt 50 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done
  local child_pid
  child_pid="$(jq -r 'select(.kind=="line") | .text' "$log" 2>/dev/null | head -1)"
  kill -TERM "$runner_pid"
  wait "$runner_pid"
  [ -n "$child_pid" ] && ! kill -0 "$child_pid" 2>/dev/null
}

run_child "$first" bash -c 'echo out-line; echo err-line >&2'
check "stdout line is a line event" \
  has_event "$first" '.kind=="line" and .stream=="stdout" and .text=="out-line"'
check "stderr line is a line event" \
  has_event "$first" '.kind=="line" and .stream=="stderr" and .text=="err-line"'
check "log file is mode 0600" mode_is "$first" 600
check "log folder it created is mode 0700" mode_is "$runs" 700

progress_log="$sandbox/progress.jsonl"
run_child "$progress_log" bash -c "printf 'a 10%%\\rb 50%%\\rdone\\n'"
check "carriage-return segment is a progress event" \
  has_event "$progress_log" '.kind=="progress" and .text=="a 10%"'
check "second carriage-return segment is a progress event" \
  has_event "$progress_log" '.kind=="progress" and .text=="b 50%"'
check "newline-ended segment after carriage returns is a line" \
  has_event "$progress_log" '.kind=="line" and .text=="done"'

ansi_log="$sandbox/ansi.jsonl"
run_child "$ansi_log" bash -c 'printf "\033[32mgreen\033[0m\n"'
check "ANSI escapes are removed from line text" \
  has_event "$ansi_log" '.kind=="line" and .text=="green"'

long_log="$sandbox/long.jsonl"
run_child "$long_log" bash -c 'printf "%5000s\n" "" | tr " " x'
check "a 5000-character line is cut to 4000" \
  has_event "$long_log" '.kind=="line" and (.text|length)==4000'

exit_log="$sandbox/exit.jsonl"
run_child "$exit_log" bash -c 'exit 3'
check "exit 3 is recorded in the end event" \
  last_event_matches "$exit_log" '.kind=="end" and .code==3 and .cancelled==false'
check "first event is start with id, command, label, argv and pid" \
  first_event_matches "$exit_log" \
  '.kind=="start" and .id=="'"$run_id"'" and .command=="doctor" and .label=="Doctor (27b)" and .argv==["bash","-c","exit 3"] and (.pid|type)=="number"'

check "an existing log path exits 2 and is not touched" \
  rejects_existing_log "$sandbox/existing.jsonl"

cancel_log="$sandbox/cancel.jsonl"
check "cancel: SIGTERM to the runner stops the child" cancel_stops_child "$cancel_log"
check "cancel: end event says cancelled" \
  last_event_matches "$cancel_log" '.kind=="end" and .cancelled==true'

stdin_log="$sandbox/stdin.jsonl"
run_child "$stdin_log" bash -c 'read -r x || echo no-input'
check "child stdin is empty" \
  has_event "$stdin_log" '.kind=="line" and .text=="no-input"'

missing_log="$sandbox/missing.jsonl"
run_child "$missing_log" /nonexistent
check "missing program is reported on stderr" \
  has_event "$missing_log" \
  '.kind=="line" and .stream=="stderr" and (.text|startswith("console-run: cannot start /nonexistent: "))'
check "missing program ends with code 127" \
  last_event_matches "$missing_log" '.kind=="end" and .code==127'

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
