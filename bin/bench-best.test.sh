#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
sandbox="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
trap 'pkill -f "$sandbox/" 2>/dev/null; rm -rf "$sandbox"' EXIT
failures=0

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

mkdir -p "$sandbox/repo/bin" "$sandbox/stubbin" "$sandbox/logs" "$sandbox/home" "$sandbox/record"
cp "$repo/bin/bench-best" "$repo/bin/claude-custom" "$sandbox/repo/bin/"
script="$sandbox/repo/bin/bench-best"
logs="$sandbox/logs"
for task in alpha beta gamma; do
  mkdir -p "$sandbox/repo/eval/tasks/$task"
  echo '{"prompt": "p", "test": "true", "timeout_seconds": 60, "language": "sh"}' >"$sandbox/repo/eval/tasks/$task/task.json"
done

export HOME="$sandbox/home"
export BENCH_RESULTS="$sandbox/results"
export BENCH_REPLAY_DIR="$sandbox/record"
export PATH="$sandbox/stubbin:$PATH"
unset BENCH_ONLY_MODELS CLAUDE_OLLAMA_EXTERNAL_TOKEN CLAUDE_OLLAMA_LEASE_BIN

stub() {
  {
    echo '#!/bin/sh'
    cat
  } >"$1"
  chmod +x "$1"
}

stub "$sandbox/stubbin/pmset" <<'EOF'
case "$*" in
  "-g batt") echo "Now drawing from '${STUB_POWER:-AC Power}'" ;;
  "-g") echo " lowpowermode         ${STUB_LOW_POWER:-0}" ;;
esac
EOF

stub "$sandbox/stubbin/pgrep" <<'EOF'
[ -n "${STUB_PGREP:-}" ]
EOF

stub "$sandbox/repo/bin/ollama-lease" <<'EOF'
[ "$1" = holders ] && [ -n "${STUB_HOLDERS:-}" ] && echo "$STUB_HOLDERS"
exit 0
EOF

stub "$sandbox/repo/bin/backend-bench-off" <<EOF
echo "\$* only=\${BENCH_ONLY_MODELS:-}" >> "$logs/bench-off.log"
case "\$1" in
  all)
    mkdir -p "\$BENCH_RESULTS"
    rm -f "\$BENCH_RESULTS"/*.json
    echo '{"finished": true, "finalists": ["fast", "slow", "close"]}' > "\$BENCH_RESULTS/plan.json"
    ;;
  serve-only)
    cell="\$2"
    model="\$3"
    if [ -s "$logs/serving.pid" ] && kill -0 "\$(cat "$logs/serving.pid")" 2>/dev/null; then
      echo overlap >> "$logs/overlap.log"
    fi
    case " \${STUB_SERVE_FAIL:-} " in *" \$cell "*) exit 3 ;; esac
    echo \$\$ > "$logs/serving.pid"
    trap 'echo "stopped \$cell \$model" >> "$logs/serve.log"; rm -f "$logs/serving.pid"; exit 0' TERM INT
    echo "started \$cell \$model" >> "$logs/serve.log"
    echo "{\"url\": \"http://127.0.0.1:9/\$cell\", \"model_id\": \"\$model--\$cell\", \"auth_token\": \"secret-token-\$cell\"}"
    while :; do sleep 1; done
    ;;
esac
EOF

stub "$sandbox/repo/bin/task-eval" <<EOF
echo "\$*" >> "$logs/task-eval.log"
echo "\${CLAUDE_OLLAMA_EXTERNAL_TOKEN:-}" >> "$logs/token.log"
model_id=""
task=""
record=""
previous=""
for word in "\$@"; do
  [ "\$previous" = --external ] && url="\$word"
  case "\$previous" in
    --task) task="\$word" ;;
    --record) record="\$word" ;;
  esac
  case "\$previous" in http://*) model_id="\$word" ;; esac
  previous="\$word"
done
if [ -n "\$record" ]; then
  mkdir -p "\$record"
  echo '{}' > "\$record/body.json"
  exit 0
fi
[ -n "\${STUB_TASK_EVAL_HANG:-}" ] && { echo hang >> "$logs/hang.log"; while :; do sleep 1; done; }
cell="\${model_id##*--}"
seconds=100
result=green
case "\$cell" in
  fast) seconds=50 ;;
  slow) seconds=300 ;;
  close) seconds=95 ;;
esac
[ "\$cell:\$task" = "fast:\${STUB_TIMEOUT_TASK:-none}" ] && result=timeout
echo "{\"model\": \"\$model_id\", \"runs\": [{\"task\": \"\$task\", \"run\": 1, \"result\": \"\$result\", \"seconds\": \$seconds}], \"total\": {}}"
EOF

stub "$sandbox/repo/bin/backend-bench-report" <<EOF
echo "\$*" >> "$logs/report.log"
case "\$*" in
  *--headline*) echo "Switch to fast" ;;
esac
EOF

run() {
  "$script" "$@" >"$sandbox/out" 2>"$sandbox/err"
}

reset_logs() {
  rm -f "$logs"/*.log
}

finals() {
  jq -r "$1" "$BENCH_RESULTS/finals.json"
}

count_lines() {
  grep -c -- "$2" "$1" 2>/dev/null || true
}

echo '{}' >"$sandbox/record/body.json"

STUB_POWER="Battery Power" run
check "battery power exits 1" test "$?" -eq 1
check "battery power says to plug in" grep -qF 'AC power' "$sandbox/err"
check "battery power runs nothing" test ! -e "$logs/bench-off.log"

STUB_LOW_POWER=1 run
check "Low Power Mode exits 1" test "$?" -eq 1
check "Low Power Mode is named" grep -qF 'Low Power Mode' "$sandbox/err"

STUB_HOLDERS="live session pid 42 model qwen3.6-35b-cc rung -" run
check "a live session lease exits 1" test "$?" -eq 1
check "a live session lease is named" grep -qF 'claude-ollama session' "$sandbox/err"

STUB_PGREP=1 run
check "a running claude-ollama process exits 1" test "$?" -eq 1

mkdir -p "$sandbox/nojq"
ln -s "$(command -v python3)" "$sandbox/nojq/python3"
PATH="$sandbox/stubbin:$sandbox/nojq" "$script" >"$sandbox/out" 2>"$sandbox/err"
check "no jq exits 1" test "$?" -eq 1
check "no jq is named" grep -qF 'jq' "$sandbox/err"
check "preflight refusals run nothing" test ! -e "$logs/bench-off.log"

reset_logs
run
check "a full run exits 0" test "$?" -eq 0
check "record is skipped when bodies exist" test "$(count_lines "$logs/task-eval.log" '--record')" -eq 0
check "bench runs all on both models" grep -qxF 'all only=' "$logs/bench-off.log"
check "finals serve one cell at a time" test ! -e "$logs/overlap.log"
check "every served cell is stopped" test "$(count_lines "$logs/serve.log" '^started')" -eq "$(count_lines "$logs/serve.log" '^stopped')"
check "no serve-only process is left" test -z "$(/usr/bin/pgrep -f "$sandbox/repo/bin/backend-bench-off serve-only" || true)"
check "finals.json names the baseline" test "$(finals .baseline)" = ollama
check "finals cover both models" test "$(finals '.models | keys | join(",")')" = 'qwen3.6-35b,qwen3.8-27b'
check "finals cover the baseline and the finalists" \
  test "$(finals '.models["qwen3.6-35b"] | keys | join(",")')" = 'close,fast,ollama,slow'
check "a finals cell has the contract fields" \
  test "$(finals '.models["qwen3.6-35b"].fast | [.green, .runs, .median_seconds, .timeouts] | map(tostring) | join(" ")')" = '3 3 50 0'
check "task-eval runs the 35b size for the 35b model" grep -qF -- '35b --external http://127.0.0.1:9/fast qwen3.6-35b--fast --runs 1 --json --task alpha' "$logs/task-eval.log"
check "task-eval runs the 27b size for the 27b model" grep -qF -- '27b --external http://127.0.0.1:9/fast qwen3.8-27b--fast' "$logs/task-eval.log"
check "a challenger over 1.5x slower stops after two tasks" \
  test "$(finals '.models["qwen3.6-35b"].slow | [.lost, .runs, .green] | map(tostring) | join(" ")')" = 'true 2 2'
check "the lost challenger ran only two tasks" test "$(count_lines "$logs/task-eval.log" 'qwen3.6-35b--slow')" -eq 2
check "a close challenger gets three runs per task" test "$(finals '.models["qwen3.6-35b"].close.runs')" -eq 9
check "the baseline is topped up to three runs per task when a challenger is close" \
  test "$(finals '.models["qwen3.6-35b"].ollama.runs')" -eq 9
check "a clear winner gets one run per task" test "$(finals '.models["qwen3.8-27b"].fast.runs')" -eq 3
check "the token reaches task-eval through the environment" grep -qxF 'secret-token-fast' "$logs/token.log"
check "the token never lands in argv" test "$(count_lines "$logs/task-eval.log" 'secret-token')" -eq 0
check "the token never lands in the output" test "$(cat "$sandbox/out" "$sandbox/err" | grep -c 'secret-token')" -eq 0
check "the token never lands in the results" test -z "$(grep -rl 'secret-token' "$BENCH_RESULTS" || true)"
check "the report renders the page" grep -qxF "$BENCH_RESULTS" "$logs/report.log"
check "the headline comes from the report" grep -qxF "$BENCH_RESULTS --headline" "$logs/report.log"
check "best-backend.json holds the headline" test "$(jq -r .headline "$BENCH_RESULTS/best-backend.json")" = 'Switch to fast'
check "best-backend.json holds the finals" test "$(jq -r '.models["qwen3.6-35b"].fast.runs' "$BENCH_RESULTS/best-backend.json")" -eq 3
check "the output is one line" test "$(wc -l <"$sandbox/out" | tr -d ' ')" -eq 1
check "the line starts with the headline" grep -qE '^Switch to fast' "$sandbox/out"
check "the line names each model's green count and median" grep -qF 'qwen3.6-35b: ollama 9/9 green 100' "$sandbox/out"

reset_logs
run
check "a resume exits 0" test "$?" -eq 0
check "a resume serves no cell already in finals" test ! -e "$logs/serve.log"
check "a resume keeps the finals" test "$(finals '.models["qwen3.6-35b"].close.runs')" -eq 9

reset_logs
run --fresh
check "--fresh serves every cell again" grep -qxF 'started fast qwen3.6-35b' "$logs/serve.log"

reset_logs
rm -rf "$BENCH_RESULTS" "$sandbox/record"
run --quick
check "--quick exits 0" test "$?" -eq 0
check "record runs task-eval on the harness when no bodies exist" grep -qxF -- "35b --record $sandbox/record --runs 1" "$logs/task-eval.log"
check "--quick benches only the 35b" grep -qxF 'all only=qwen3.6-35b' "$logs/bench-off.log"
check "--quick runs finals on the 35b only" test "$(finals '.models | keys | join(",")')" = 'qwen3.6-35b'

reset_logs
rm -rf "$BENCH_RESULTS"
STUB_SERVE_FAIL=fast run --quick
check "a challenger that fails to serve is recorded with no runs" \
  test "$(finals '.models["qwen3.6-35b"].fast | [.runs, .green] | map(tostring) | join(" ")')" = '0 0'
check "the other challengers still run" test "$(finals '.models["qwen3.6-35b"].close.runs')" -ge 3

reset_logs
rm -rf "$BENCH_RESULTS"
STUB_TASK_EVAL_HANG=1 "$script" --quick >"$sandbox/out" 2>"$sandbox/err" &
best_pid=$!
for _ in $(seq 1 100); do
  [ -s "$logs/hang.log" ] && break
  sleep 0.1
done
kill -TERM "$best_pid"
wait "$best_pid"
check "SIGTERM exits nonzero" test "$?" -ne 0
check "SIGTERM stops the serve-only process it started" grep -qxF 'stopped ollama qwen3.6-35b' "$logs/serve.log"
check "SIGTERM leaves no serve-only process" test -z "$(/usr/bin/pgrep -f "$sandbox/repo/bin/backend-bench-off serve-only" || true)"
pkill -f "$sandbox/repo/bin/task-eval" 2>/dev/null

reset_logs
STUB_POWER="Battery Power" "$sandbox/repo/bin/claude-custom" bench-best --quick >"$sandbox/out" 2>"$sandbox/err"
check "claude-custom bench-best runs bench-best" grep -qF 'AC power' "$sandbox/err"

run --nonsense
check "an unknown option exits 2" test "$?" -eq 2

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
