#!/usr/bin/env bash
set -u
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_script="$repo_dir/bin/speed-check"
. "$repo_dir/shared/testing/stub-llama-lib.sh"
tmp="$(mktemp -d)"
failures=0
trap 'stop_stub_llama; rm -rf "$tmp"' EXIT

stubs="$tmp/stubs"
mkdir -p "$stubs"

cat > "$stubs/pmset" <<'EOF'
#!/bin/sh
if [ "${1:-} ${2:-}" = "-g batt" ]; then
  if [ -n "${STUB_ON_BATTERY:-}" ]; then echo "Now drawing from 'Battery Power'"; else echo "Now drawing from 'AC Power'"; fi
  exit 0
fi
echo " lowpowermode         ${STUB_LOW_POWER:-0}"
EOF

cat > "$stubs/pgrep" <<'EOF'
#!/bin/sh
[ -n "${STUB_OTHER_SESSION:-}" ] && { echo 4242; exit 0; }
exit 1
EOF

cat > "$stubs/df" <<'EOF'
#!/bin/sh
echo "df $*" >> "$CALLS"
echo "Filesystem 1024-blocks Used Available Capacity Mounted"
echo "/dev/disk3 999999999 1 ${STUB_FREE_KB:-99999999} 1% /"
EOF

cat > "$stubs/launcher" <<'EOF'
#!/bin/sh
echo "launcher $*" >> "$CALLS"
EOF

cat > "$stubs/bench" <<'EOF'
#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ["CALLS"], "a") as log:
    log.write("bench " + " ".join(args) + "\n")
model = args[args.index("--model") + 1]
thinking = args[args.index("--thinking") + 1]
trials = int(args[args.index("--tool-trials") + 1])
think = 0
if thinking == "claude-code" and model.endswith("@think") and not os.environ.get("STUB_NO_THINKING"):
    think = 500
if thinking == "claude-code" and not model.endswith("@think") and os.environ.get("STUB_PLAIN_THINKS"):
    think = 40
parsed = trials - 1 if os.environ.get("STUB_MISSED_TOOL") and thinking == "disabled" else trials
runs = [
    {"prefix_tokens": prefix, "scenario": scenario, "ttft_seconds": 4.0, "decode_tokens_per_second": 20.0, "thinking_chars": think}
    for prefix in (20000, 60000)
    for scenario in ("cold", "warm")
]
print(json.dumps({"runs": runs, "tool_calls": {"parsed": parsed, "trials": trials}}))
EOF

cat > "$stubs/probe" <<'EOF'
#!/bin/sh
echo "probe $*" >> "$CALLS"
echo "{\"cache_reused\": ${STUB_CACHE_REUSED:-true}, \"scenarios\": []}"
EOF

chmod +x "$stubs"/*

printf '{"models": {}}\n' > "$tmp/stub-state.json"
start_stub_llama "$tmp/stub-state.json" || exit 1
server_url="$LLAMA_SERVER_URL"

weights_of() {
  jq -r --arg size "$1" '.[$size].gguf.file' "$repo_dir/ollama/sizes.json"
}

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

run_check() {
  run_dir="$(mktemp -d "$tmp/run.XXXXXX")"
  export CALLS="$run_dir/calls.log"
  : > "$CALLS"
  mkdir -p "$run_dir/weights"
  touch "$run_dir/weights/$(weights_of 27b)" "$run_dir/weights/$(weights_of 35b)"
  [ -z "${missing_size:-}" ] || rm -f "$run_dir/weights/$(weights_of "$missing_size")"
  env PATH="$stubs:$PATH" HOME="$run_dir/home" LLAMA_SERVER_URL="$server_url" \
    CLAUDE_OLLAMA_WEIGHTS_DIR="$run_dir/weights" \
    SPEED_CHECK_LAUNCHER="$stubs/launcher" SPEED_CHECK_BENCH="$stubs/bench" SPEED_CHECK_PROBE="$stubs/probe" \
    "$@" "$check_script" ${check_args[@]+"${check_args[@]}"} > "$run_dir/out" 2> "$run_dir/err"
  status=$?
}

check_args=()
missing_size=""

has() { grep -qF -- "$1" "$run_dir/$2"; }

run_check
[ "$status" -eq 0 ] || { fail "a healthy run exits 0 (got $status)"; cat "$run_dir/err"; }
order="$(sed 's/ .*//' "$CALLS" | uniq | tr '\n' ' ')"
[ "$order" = "launcher bench probe " ] || fail "stages run in order: prepare, benches, probes (got $order)"
[ "$(grep -c '^launcher prepare ' "$CALLS")" -eq 2 ] || fail "it prepares the two sizes"
grep -qx 'launcher prepare 27b' "$CALLS" || fail "it prepares the 27b"
grep -qx 'launcher prepare 35b' "$CALLS" || fail "it prepares the 35b"
grep -q -- "--model qwen3.8-27b-cc@think --thinking claude-code .*--base-url $server_url" "$CALLS" || fail "it checks the @think preset thinks on llama-server"
grep -q -- '--model qwen3.8-27b-cc --thinking claude-code' "$CALLS" || fail "it checks the plain preset in Claude Code's shape"
grep -q -- '--model qwen3.6-35b-cc --thinking disabled --tool-trials 5' "$CALLS" || fail "it benches the 35b preset with thinking disabled"
grep -qx 'probe qwen3.8-27b-cc --json' "$CALLS" || fail "it probes the 27b preset's cache"
grep -qx 'probe qwen3.6-35b-cc --json' "$CALLS" || fail "it probes the 35b preset's cache"
grep -q '^df ' "$CALLS" && fail "it skips the disk check when every weights file is there"
has "[1/5]" out || fail "it numbers the stages"
has "Thinking check: PASS (27b think 2000 -> 0, 35b think 2000 -> 0)" out || fail "the verdict passes the thinking check"
has "27b: ok (warm 60k: ttft 4.0s, decode 20.0 tok/s)" out || fail "the verdict gives each size its numbers"
has "Paste this block into Claude:" out || fail "it prints the paste block"
has "Next: nothing to change" out || fail "it prints the next action"
ls "$run_dir/home/bench-results"/speed-check-*.json > /dev/null 2>&1 || fail "it saves the report under ~/bench-results"
report="$(ls "$run_dir/home/bench-results"/speed-check-*.json 2>/dev/null | head -n 1)"
[ "$(jq -r '.verdict[0]' "$report" 2>/dev/null)" = "Thinking check: PASS (27b think 2000 -> 0, 35b think 2000 -> 0)" ] || fail "the report keeps the verdict lines"
[ "$(jq -r '.next' "$report" 2>/dev/null | cut -c1-5)" = "Next:" ] || fail "the report keeps the next action"

run_check STUB_ON_BATTERY=1
[ "$status" -eq 1 ] || fail "on battery it exits 1"
has "plug in the charger" err || fail "on battery it says to plug in"
[ -s "$CALLS" ] && fail "on battery it runs nothing"

run_check STUB_LOW_POWER=1
has "Low Power Mode" err || fail "Low Power Mode stops the run with a fix line"
[ -s "$CALLS" ] && fail "Low Power Mode runs nothing"

run_check STUB_OTHER_SESSION=1
has "quit the other claude-ollama session" err || fail "another session stops the run with a fix line"

run_check LLAMA_SERVER_URL=http://127.0.0.1:9
has "llama-server is not answering at http://127.0.0.1:9" err || fail "a stopped llama-server stops the run with a fix line"

missing_size=35b
run_check STUB_FREE_KB=1000
[ "$status" -eq 1 ] || fail "too little disk for missing weights exits 1"
has "free up disk space" err || fail "too little disk says to free space"
has "35b" err || fail "too little disk names the size to download"
grep -q '^launcher ' "$CALLS" && fail "too little disk downloads nothing"

run_check
grep -q '^df ' "$CALLS" || fail "a missing weights file triggers the disk check"
missing_size=""

run_check STUB_NO_THINKING=1
[ "$status" -eq 0 ] || fail "a failed thinking check still finishes the run"
has "Thinking check: FAIL" out || fail "an @think preset that never thinks fails the check"
grep -q '^probe ' "$CALLS" || fail "a failed thinking check still runs the probes"
has "thinking is still wrong" out || fail "a failed thinking check names it in the next action"

run_check STUB_PLAIN_THINKS=1
has "Thinking check: FAIL (27b think 2000 -> 160" out || fail "a plain preset that thinks fails the check"

run_check STUB_MISSED_TOOL=1 STUB_CACHE_REUSED=false
has "27b: needs a look (tool calls missed, prompt cache not reused)" out || fail "a size with missed tool calls and no cache reuse needs a look"
has "Next: paste the block below into Claude; a size needs a look." out || fail "a size that needs a look says so in the next action"

check_args=(--thinking-only)
run_check STUB_ON_BATTERY=1
[ "$status" -eq 0 ] || fail "a thinking-only run exits 0 when thinking is right (got $status)"
has "Thinking check: PASS" out || fail "a thinking-only run prints the thinking verdict"
grep -qx 'launcher prepare 27b' "$CALLS" || fail "a thinking-only run prepares the sizes"
grep -q -- '--tool-trials 5' "$CALLS" && fail "a thinking-only run skips the speed bench"
grep -q '^probe ' "$CALLS" && fail "a thinking-only run skips the cache probe"
has "Paste this block" out && fail "a thinking-only run prints no paste block"

run_check STUB_NO_THINKING=1
[ "$status" -eq 1 ] || fail "a thinking-only run exits 1 when the check fails"
has "Thinking check: FAIL" out || fail "a failed thinking-only run says FAIL"

check_args=(--thinking-only --model qwen3.8-27b-cc@next)
run_check
[ "$status" -eq 0 ] || fail "a named thinking-only run exits 0 when the preset does not think (got $status)"
grep -q -- '--model qwen3.8-27b-cc@next --thinking claude-code' "$CALLS" || fail "a named thinking-only run checks only that preset"
grep -q -- '@think' "$CALLS" && fail "a named thinking-only run checks no @think preset"
grep -q '^launcher ' "$CALLS" && fail "a named thinking-only run prepares no model"
has "Thinking check: PASS (qwen3.8-27b-cc@next think - -> 0)" out || fail "a named thinking-only run prints the thinking verdict"

run_check STUB_PLAIN_THINKS=1
[ "$status" -eq 1 ] || fail "a named preset that thinks fails (got $status)"

check_args=(--thinking-only --model)
run_check
[ "$status" -eq 1 ] || fail "--model without a name exits 1 (got $status)"
has "give --model a preset id" err || fail "--model without a name says what to give"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
