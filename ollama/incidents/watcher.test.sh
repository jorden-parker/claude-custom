#!/usr/bin/env bash
set -u
umask 022
here="$(cd "$(dirname "$0")" && pwd)"
watcher="$here/watcher.py"
fixtures="$here/fixtures"
tmp="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
failures=0
watcher_pid=""
watched_pid=""

stop_all() {
  for pid in "$watcher_pid" "$watched_pid"; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null && wait "$pid" 2>/dev/null
  done
  watcher_pid=""
  watched_pid=""
}

trap 'stop_all; rm -rf "$tmp"' EXIT

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

contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

eventually() {
  for _ in $(seq 60); do
    "$@" && return 0
    sleep 0.1
  done
  return 1
}

causes_are() {
  [ "$(field cause < "$2" 2>/dev/null)" = "$1" ]
}

mode_of() {
  stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"
}

field() {
  python3 -c 'import json, sys; print(*(json.loads(line)[sys.argv[1]] for line in sys.stdin if line.strip()))' "$1"
}

run_once() {
  python3 "$watcher" --log "$1" --model qwen3.6:35b-cc --out "$2" --transcripts "$3" --once
}

out="$tmp/state/incidents/session.jsonl"
run_once "$fixtures/server-log.txt" "$out" "$fixtures/projects"
check "every cause is found in order, and a line naming the model without a rule is unknown" \
  equals "evicted aborted evicted evicted reprefilled truncated reprefilled unknown compacted" "$(field cause < "$out")"
check "token counts come from the line, or are null" \
  equals "None None None None 13100 66000 65400 None 61234" "$(field tokens < "$out")"
check "the timestamp comes from the log line" \
  equals "2026-11-02T14:01:30.100Z" "$(sed -n 2p "$out" | field ts)"
check "the compaction timestamp comes from the transcript" \
  equals "2026-11-02T14:05:00.000Z" "$(tail -n 1 "$out" | field ts)"
check "the detail keeps the line" contains "$(sed -n 2p "$out" | field detail)" 'error="context canceled"'
check "the unknown line is the one naming the model" contains "$(sed -n 8p "$out" | field detail)" "runner idle timer fired"
check "the incidents folder is private" equals 700 "$(mode_of "$tmp/state/incidents")"
check "the incidents file is private" equals 600 "$(mode_of "$out")"
check "the latest file holds the newest incident" equals "$(tail -n 1 "$out")" "$(cat "$out.latest")"
check "the latest file is private" equals 600 "$(mode_of "$out.latest")"

long_line="$(printf 'x%.0s' $(seq 400)) context canceled"
printf '%s\n' "$long_line" > "$tmp/long.log"
run_once "$tmp/long.log" "$tmp/long.jsonl" "$tmp/no-transcripts"
check "the detail is cut at 200 characters" equals 200 "$(field detail < "$tmp/long.jsonl" | tr -d '\n' | wc -c | tr -d ' ')"
check "a missing transcripts folder is fine" equals aborted "$(field cause < "$tmp/long.jsonl")"

cat > "$tmp/quiet.log" <<'EOF'
slot print_timing: id  0 | task 0 | prompt eval time = 100.00 ms / 400 tokens (0.25 ms per token, 4000.00 tokens per second)
slot print_timing: id  0 | task 0 |      total time = 500.00 ms / 450 tokens
slot print_timing: id  0 | task 1 | prompt eval time = 100.00 ms / 460 tokens (0.25 ms per token, 4000.00 tokens per second)
time=2026-11-02T14:04:01.000Z level=INFO source=sched.go:901 msg="embedding request" model=qwen3-embedding:0.6b
EOF
run_once "$tmp/quiet.log" "$tmp/quiet.jsonl" "$tmp/no-transcripts"
check "small prompts and other models produce no incident" equals "" "$(cat "$tmp/quiet.jsonl" 2>/dev/null)"

follow_log="$tmp/follow.log"
follow_out="$tmp/follow/incidents.jsonl"
printf 'time=2026-11-02T13:00:00.000Z level=INFO msg="request failed" error="context canceled"\n' > "$follow_log"
mkdir -p "$tmp/follow-projects/p"
printf '{"type":"system","subtype":"compact_boundary","timestamp":"2026-11-02T13:00:00.000Z","compactMetadata":{"preTokens":1}}\n' > "$tmp/follow-projects/p/old.jsonl"
sleep 600 &
watched_pid=$!
python3 "$watcher" --log "$follow_log" --model qwen3.6:35b-cc --out "$follow_out" \
  --transcripts "$tmp/follow-projects" --watch-pid "$watched_pid" --interval 0.1 &
watcher_pid=$!
sleep 0.5
check "following starts at the end of the log and the transcripts" test ! -e "$follow_out"
printf 'time=2026-11-02T14:00:00.000Z level=WARN msg="truncating input prompt" limit=4096 prompt=5000 keep=4 new=4096\n' >> "$follow_log"
check "a new log line is an incident" eventually test -s "$follow_out"
check "and it is classified" equals truncated "$(field cause < "$follow_out")"
printf '{"type":"system","subtype":"compact_boundary","timestamp":"2026-11-02T14:06:00.000Z","compactMetadata":{"preTokens":50000}}\n' > "$tmp/follow-projects/p/new.jsonl"
check "a compaction in a new transcript is an incident" eventually causes_are "truncated compacted" "$follow_out"
printf 'time=2026-11-02T14:07:00.000Z level=INFO msg="request failed" error="context canceled"\n' > "$follow_log"
check "a truncated log is read again from the top" eventually causes_are "truncated compacted aborted" "$follow_out"
kill "$watched_pid" 2>/dev/null
wait "$watched_pid" 2>/dev/null
watched_pid=""
check "the watcher exits when the session does" eventually sh -c "! kill -0 $watcher_pid 2>/dev/null"
wait "$watcher_pid" 2>/dev/null
watcher_pid=""

stop_all

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
