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
  python3 -c 'import json, sys; rows = [json.loads(line) for line in sys.stdin if line.strip()]; print(*(row[sys.argv[1]] for row in rows if "kind" not in row))' "$1"
}

health_field() {
  python3 -c 'import json, sys; rows = [json.loads(line) for line in sys.stdin if line.strip()]; health = [row for row in rows if row.get("kind") == "health"]; print(json.dumps(health[-1][sys.argv[1]]) if health else "")' "$1"
}

health_rows() {
  grep -c '"kind": "health"' "$1" 2>/dev/null || echo 0
}

row_json() {
  sed -n "${1}p" "$2" | python3 -c "import json, sys; print($3)"
}

check_rules() {
  python3 "$watcher" --check-rules "$@" > "$tmp/check.out" 2>&1
  echo "$?"
}

run_once() {
  python3 "$watcher" --log "$1" --model qwen3.6:35b-cc --out "$2" --transcripts "$3" --once
}

out="$tmp/state/incidents/session.jsonl"
run_once "$fixtures/server-log.txt" "$out" "$fixtures/projects"
check "every cause is found in order, and a line naming the model without a rule is unknown" \
  equals "evicted aborted evicted evicted reprefilled truncated reprefilled unknown reprefilled compacted" "$(field cause < "$out")"
check "token counts come from the line, or are null" \
  equals "None None None None 13100 66000 65400 None 65450 61234" "$(field tokens < "$out")"
check "every row names the rule that matched it, none for unknown" \
  equals "evicted/runner-start aborted/context-canceled evicted/unload evicted/runner-start reprefilled/prompt-eval truncated/input-prompt reprefilled/prompt-eval None reprefilled/prompt-eval compacted/transcript" "$(field rule < "$out")"
check "a reprefill after an embed request says so" \
  equals embed "$(row_json 9 "$out" 'json.load(sys.stdin)["preceded_by"]["kind"]')"
check "a reprefill after a runner start says so, with the event time" \
  equals "load 2026-11-02T14:02:05.000Z" "$(row_json 5 "$out" '" ".join(json.load(sys.stdin)["preceded_by"].values())')"
check "other causes carry no preceded_by" equals False "$(row_json 2 "$out" '"preceded_by" in json.load(sys.stdin)')"
check "a once run ends with one health row" equals 1 "$(health_rows "$out")"
check "the health row counts the hits per rule" \
  equals '{"aborted/context-canceled": 1, "truncated/input-prompt": 1, "evicted/unload": 1, "evicted/runner-start": 2, "ignored/load-sequence": 3, "reprefilled/prompt-eval": 3, "compacted/transcript": 1}' "$(health_field rules < "$out")"
check "the health row counts the unmatched model lines" equals 1 "$(health_field unmatched < "$out")"
check "the health row counts the log lines seen" equals 36 "$(health_field lines < "$out")"
check "the timestamp comes from the log line" \
  equals "2026-11-02T14:01:30.100Z" "$(sed -n 2p "$out" | field ts)"
check "the compaction timestamp comes from the transcript" \
  equals "2026-11-02T14:05:00.000Z" "$(sed -n 10p "$out" | field ts)"
check "the detail keeps the line" contains "$(sed -n 2p "$out" | field detail)" 'error="context canceled"'
check "the unknown line is the one naming the model" contains "$(sed -n 8p "$out" | field detail)" "runner idle timer fired"
check "the incidents folder is private" equals 700 "$(mode_of "$tmp/state/incidents")"
check "the incidents file is private" equals 600 "$(mode_of "$out")"
check "the latest file holds the newest incident, never a health row" equals "$(tail -n 2 "$out" | head -n 1)" "$(cat "$out.latest")"
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
check "small prompts and other models produce no incident" equals "" "$(field cause < "$tmp/quiet.jsonl")"

check "the rule check passes on the fixture" equals 0 "$(check_rules --log "$fixtures/server-log.txt" --model qwen3.6:35b-cc)"
check "and prints each rule with its hits, then ok" \
  equals "aborted/context-canceled 1
truncated/input-prompt 1
evicted/unload 1
evicted/runner-start 2
ignored/load-sequence 3
reprefilled/prompt-eval 3
compacted/transcript 0
ok" "$(cat "$tmp/check.out")"
for i in $(seq 60); do
  printf 'time=2026-11-02T15:00:%02d.000Z level=INFO source=sched.go:1 msg="runner did a new thing" model=qwen3.6:35b-cc\n' "$((i % 60))"
done > "$tmp/blind.log"
check "the rule check is blind to 50 or more model lines no rule matches" equals 1 "$(check_rules --log "$tmp/blind.log" --model qwen3.6:35b-cc)"
check "and says so" equals blind "$(tail -n 1 "$tmp/check.out")"
check "a runner mention counts without a model name" equals 1 "$(check_rules --log "$tmp/blind.log")"
head -n 49 "$tmp/blind.log" > "$tmp/short.log"
check "fewer than 50 unmatched lines is not blind" equals 0 "$(check_rules --log "$tmp/short.log" --model qwen3.6:35b-cc)"
cat "$fixtures/server-log.txt" "$tmp/blind.log" > "$tmp/mixed.log"
check "the rule check replays only the last lines asked for" equals 1 "$(check_rules --log "$tmp/mixed.log" --model qwen3.6:35b-cc --lines 60)"
check "and 400 lines by default" equals 0 "$(check_rules --log "$tmp/mixed.log" --model qwen3.6:35b-cc)"
check "the rule check writes no incidents file" equals no "$([ -e "$tmp/check.jsonl" ] && echo yes || echo no)"

follow_log="$tmp/follow.log"
follow_out="$tmp/follow/incidents.jsonl"
printf 'time=2026-11-02T13:00:00.000Z level=INFO msg="request failed" error="context canceled"\n' > "$follow_log"
mkdir -p "$tmp/follow-projects/p"
printf '{"type":"system","subtype":"compact_boundary","timestamp":"2026-11-02T13:00:00.000Z","compactMetadata":{"preTokens":1}}\n' > "$tmp/follow-projects/p/old.jsonl"
sleep 600 &
watched_pid=$!
python3 "$watcher" --log "$follow_log" --model qwen3.6:35b-cc --out "$follow_out" \
  --transcripts "$tmp/follow-projects" --watch-pid "$watched_pid" --interval 0.1 --health-interval 0.3 &
watcher_pid=$!
sleep 0.5
check "following starts at the end of the log and the transcripts" equals "" "$(field cause < "$follow_out" 2>/dev/null)"
check "following writes a health row every interval" eventually sh -c "[ \"\$(grep -c '\"kind\": \"health\"' '$follow_out')\" -ge 2 ]"
printf 'time=2026-11-02T14:00:00.000Z level=WARN msg="truncating input prompt" limit=4096 prompt=5000 keep=4 new=4096\n' >> "$follow_log"
check "a new log line is an incident, classified" eventually causes_are truncated "$follow_out"
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
check "and writes a last health row" contains "$(tail -n 1 "$follow_out")" '"kind": "health"'
check "that counts the lines it followed" equals 2 "$(health_field lines < "$follow_out")"

stop_all

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
