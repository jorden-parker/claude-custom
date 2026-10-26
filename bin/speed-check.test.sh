#!/usr/bin/env bash
set -u
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_script="$repo_dir/bin/speed-check"
tmp="$(mktemp -d)"
failures=0
trap 'rm -rf "$tmp"' EXIT

stubs="$tmp/stubs"
mkdir -p "$stubs"

cat > "$stubs/curl" <<'EOF'
#!/bin/sh
[ -n "${STUB_OLLAMA_DOWN:-}" ] && exit 7
echo '{"version":"0.40.8"}'
EOF

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

cat > "$stubs/ollama" <<'EOF'
#!/bin/sh
if [ "$1" = show ] && [ "${3:-}" = --modelfile ]; then
  echo "FROM ./weights/x.gguf"
  [ -n "${STUB_NO_RENDERER:-}" ] || { echo "RENDERER qwen3.8"; echo "PARSER qwen3.5"; }
  exit 0
fi
if [ "$1" = show ]; then
  case " ${STUB_MISSING_MODELS:-} " in *" $2 "*) exit 1 ;; esac
  exit 0
fi
exit 0
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
gguf = "gguf" in model
think = 0
if thinking == "claude-code" and not os.environ.get("STUB_NO_THINKING"):
    think = 500
ttft = 9.0 if gguf and os.environ.get("STUB_SLOW_GGUF") else (4.0 if gguf else 5.0)
runs = [
    {"prefix_tokens": prefix, "scenario": scenario, "ttft_seconds": ttft, "decode_tokens_per_second": 20.0, "thinking_chars": think}
    for prefix in (20000, 60000)
    for scenario in ("cold", "warm")
]
print(json.dumps({"runs": runs, "tool_calls": {"parsed": trials, "trials": trials}}))
EOF

cat > "$stubs/probe" <<'EOF'
#!/bin/sh
echo "probe $*" >> "$CALLS"
echo '{"cache_reused": true, "scenarios": []}'
EOF

chmod +x "$stubs"/*

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

run_check() {
  run_dir="$(mktemp -d "$tmp/run.XXXXXX")"
  export CALLS="$run_dir/calls.log"
  : > "$CALLS"
  env PATH="$stubs:$PATH" HOME="$run_dir/home" \
    SPEED_CHECK_LAUNCHER="$stubs/launcher" SPEED_CHECK_BENCH="$stubs/bench" SPEED_CHECK_PROBE="$stubs/probe" \
    "$@" "$check_script" > "$run_dir/out" 2> "$run_dir/err"
  status=$?
}

has() { grep -qF -- "$1" "$run_dir/$2"; }

run_check
[ "$status" -eq 0 ] || { fail "a healthy run exits 0 (got $status)"; cat "$run_dir/err"; }
order="$(sed 's/ .*//' "$CALLS" | uniq | tr '\n' ' ')"
[ "$order" = "launcher bench probe " ] || fail "stages run in order: prepare, benches, probes (got $order)"
[ "$(grep -c '^launcher prepare ' "$CALLS")" -eq 4 ] || fail "it prepares all four sizes"
grep -q '^launcher prepare 27b-gguf$' "$CALLS" || fail "it prepares 27b-gguf"
grep -q -- '--thinking claude-code' "$CALLS" || fail "it runs the thinking check in Claude Code's shape"
grep -q -- '--model qwen3.8-27b-gguf-cc --thinking disabled --tool-trials 5' "$CALLS" || fail "it benches the 27b GGUF model with thinking disabled"
first_mlx="$(grep -n -- '--model qwen3.8-27b-cc --thinking disabled --tool-trials 5' "$CALLS" | cut -d: -f1)"
first_gguf="$(grep -n -- '--model qwen3.8-27b-gguf-cc --thinking disabled --tool-trials 5' "$CALLS" | cut -d: -f1)"
[ "$((first_gguf - first_mlx))" -eq 1 ] || fail "the MLX and GGUF benches of a model run back to back"
grep -q '^probe 35b-gguf --json$' "$CALLS" || fail "it probes the 35b-gguf cache"
grep -q '^df ' "$CALLS" && fail "it skips the disk check when every model is imported"
has "[1/6]" out || fail "it numbers the stages"
has "Plan 066 (thinking off): PASS" out || fail "the verdict passes plan 066"
has "27b: GGUF is better" out || fail "the verdict says the faster GGUF is better"
has "Paste this block into Claude:" out || fail "it prints the paste block"
has "Next:" out || fail "it prints the next action"
ls "$run_dir/home/bench-results"/speed-check-*.json > /dev/null 2>&1 || fail "it saves the report under ~/bench-results"

run_check STUB_ON_BATTERY=1
[ "$status" -eq 1 ] || fail "on battery it exits 1"
has "plug in the charger" err || fail "on battery it says to plug in"
[ -s "$CALLS" ] && fail "on battery it runs nothing"

run_check STUB_LOW_POWER=1
has "Low Power Mode" err || fail "Low Power Mode stops the run with a fix line"
[ -s "$CALLS" ] && fail "Low Power Mode runs nothing"

run_check STUB_OTHER_SESSION=1
has "quit the other claude-ollama session" err || fail "another session stops the run with a fix line"

run_check STUB_OLLAMA_DOWN=1
has "Ollama is not answering" err || fail "a stopped Ollama stops the run with a fix line"

run_check STUB_MISSING_MODELS="qwen3.6-35b-gguf-cc" STUB_FREE_KB=1000
[ "$status" -eq 1 ] || fail "too little disk for a missing GGUF exits 1"
has "free up disk space" err || fail "too little disk says to free space"
grep -q '^launcher ' "$CALLS" && fail "too little disk imports nothing"

run_check STUB_MISSING_MODELS="qwen3.6-35b-gguf-cc"
grep -q '^df ' "$CALLS" || fail "a missing GGUF model triggers the disk check"

run_check STUB_NO_RENDERER=1
[ "$status" -eq 1 ] || fail "a GGUF model without RENDERER exits 1"
has "don't use 27b-gguf" err || fail "a missing RENDERER names the size not to use"
grep -q '^bench ' "$CALLS" && fail "a missing RENDERER stops before benching"

run_check STUB_NO_THINKING=1
[ "$status" -eq 0 ] || fail "a failed thinking check still finishes the run"
has "Plan 066 (thinking off): FAIL" out || fail "no thinking in Claude Code's shape fails plan 066"
grep -q '^probe ' "$CALLS" || fail "a failed thinking check still runs the probes"

run_check STUB_SLOW_GGUF=1
has "27b: GGUF is not better" out || fail "a slower GGUF is not better"
has "warm TTFT" out || fail "a slower GGUF names the TTFT condition"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
