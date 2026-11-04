#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
eval_script="$repo/bin/task-eval"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
failures=0
mkdir -p "$sandbox/tmp" "$sandbox/stubs" "$sandbox/home"
export TMPDIR="$sandbox/tmp"
export STUB_DIR="$sandbox"
export HOME="$sandbox/home"
tasks="$sandbox/tasks"

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

cat > "$sandbox/stubs/pmset" <<'STUB'
#!/usr/bin/env bash
case "$2" in
  batt) echo "Now drawing from '${STUB_POWER:-AC Power}'" ;;
  therm) echo "CPU_Speed_Limit 	= ${STUB_CPU_LIMIT:-100}" ;;
esac
STUB

cat > "$sandbox/green" <<'STUB'
#!/usr/bin/env bash
{
  echo "args: $*"
  echo "cwd-is-repo: $(git rev-parse --is-inside-work-tree 2>/dev/null)"
  echo "clean-tree: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "beacon: ${CLAUDE_OLLAMA_BEACON:-unset}"
  echo "proxy: ${CLAUDE_OLLAMA_PROXY:-unset}"
  echo "telemetry-switch: ${CLAUDE_OLLAMA_TELEMETRY:-unset}"
  echo "external-url: ${CLAUDE_OLLAMA_EXTERNAL_URL:-unset}"
  echo "external-model: ${CLAUDE_OLLAMA_EXTERNAL_MODEL:-unset}"
  echo "external-token: ${CLAUDE_OLLAMA_EXTERNAL_TOKEN:-unset}"
  echo "proxy-record: ${CLAUDE_OLLAMA_PROXY_RECORD:-unset}"
  echo "proxy-record-dir: ${CLAUDE_OLLAMA_PROXY_RECORD_DIR:-unset}"
} >> "$STUB_DIR/launch.log"
for patch in "$STUB_TASKS_DIR"/*/solution.patch; do
  git apply "$patch" 2>/dev/null && break
done
{
  echo '{"time": 1, "session": "s", "tool": "Read", "bytes": 10, "lines": 1, "over_trim_limit": false}'
  echo '{"time": 2, "session": "s", "tool": "Edit", "bytes": 10, "lines": 1, "over_trim_limit": false}'
  echo '{"time": 3, "session": "s", "kind": "deny", "hook": "read-range-guard", "tool": "Read", "reason": "too long"}'
  echo '{"time": 4, "session": "s", "kind": "budget", "hook": "context-budget", "tool": "Bash", "reason": "70%"}'
  echo '{"time": 5, "session": "s", "tool": "Bash", "bytes": 10, "lines": 1, "over_trim_limit": false}'
} >> "$CLAUDE_TOOL_TELEMETRY"
echo "done: applied the fix"
STUB

printf '#!/usr/bin/env bash\necho "nothing"\n' > "$sandbox/red"
printf '#!/usr/bin/env bash\nsleep 5\n' > "$sandbox/slow"
chmod +x "$sandbox/stubs/pmset" "$sandbox/green" "$sandbox/red" "$sandbox/slow"
export PATH="$sandbox/stubs:$PATH"

mkdir -p "$tasks/tiny/fixture"
printf 'status=broken\n' > "$tasks/tiny/fixture/state.txt"
printf '#!/usr/bin/env bash\ngrep -q "status=fixed" "$(dirname "$0")/state.txt"\n' > "$tasks/tiny/fixture/check.sh"
chmod +x "$tasks/tiny/fixture/check.sh"
cat > "$tasks/tiny/task.json" <<'JSON'
{
  "prompt": "Set status to fixed in state.txt.",
  "test": "./check.sh",
  "timeout_seconds": 60,
  "language": "shell"
}
JSON
cat > "$tasks/tiny/solution.patch" <<'PATCH'
diff --git a/state.txt b/state.txt
--- a/state.txt
+++ b/state.txt
@@ -1 +1 @@
-status=broken
+status=fixed
PATCH

run_eval() {
  STUB_TASKS_DIR="$tasks" "$eval_script" --tasks "$tasks" --launcher "$sandbox/$1" "${@:2}"
}

rm -f "$sandbox/launch.log"
run_eval green 27b --runs 2 > "$sandbox/out.txt" 2> "$sandbox/err.txt"
status=$?
check "a green run exits 0" test "$status" -eq 0
check "the launcher gets the size, print mode and the prompt" grep -qxF 'args: 27b -p Set status to fixed in state.txt.' "$sandbox/launch.log"
check "the launcher runs inside a git repo" grep -qxF 'cwd-is-repo: true' "$sandbox/launch.log"
check "the fixture is committed before the launch" grep -qxF 'clean-tree: 0' "$sandbox/launch.log"
check "the launcher skips the beacon" grep -qxF 'beacon: 0' "$sandbox/launch.log"
check "the launcher skips the proxy" grep -qxF 'proxy: 0' "$sandbox/launch.log"
check "telemetry stays on for the run" grep -qxF 'telemetry-switch: 1' "$sandbox/launch.log"
check "the launcher ran twice" test "$(grep -c '^args:' "$sandbox/launch.log")" = 2
check "the scorecard has a header" grep -qE '^task +result +seconds +calls +denials$' "$sandbox/out.txt"
check "each run has a green line with its counts" test "$(grep -cE '^tiny +green +[0-9]+\.[0-9]s +3 +1$' "$sandbox/out.txt")" = 2
check "the total line counts green runs and timing" grep -qE '^total: 2/2 green, median seconds [0-9]+\.[0-9], p90 [0-9]+\.[0-9]$' "$sandbox/out.txt"
check "the paste block opens" grep -qxF 'Paste this block into Claude:' "$sandbox/out.txt"
check "the paste block names the eval" grep -qxF 'task-eval results' "$sandbox/out.txt"
check "the paste block names the model" grep -qxF 'model: qwen3.8-27b-cc' "$sandbox/out.txt"
check "progress reaches stderr" grep -qF 'task-eval: tiny run 1/2' "$sandbox/err.txt"
check "no temp repo is left behind" test -z "$(find "$sandbox/tmp" -name 'task-eval-*')"

run_eval red > "$sandbox/red.txt" 2>/dev/null
check "a red run still exits 0" test "$?" -eq 0
check "a red run is scored red with no calls" grep -qE '^tiny +red +[0-9]+\.[0-9]s +0 +0$' "$sandbox/red.txt"
check "a red total has no median" grep -qxF 'total: 0/1 green, median seconds -, p90 -' "$sandbox/red.txt"

slow_tasks="$sandbox/slow-tasks"
mkdir -p "$slow_tasks"
cp -R "$tasks/tiny" "$slow_tasks/tiny"
sed -i.bak 's/"timeout_seconds": 60/"timeout_seconds": 1/' "$slow_tasks/tiny/task.json" && rm -f "$slow_tasks/tiny/task.json.bak"
STUB_TASKS_DIR="$slow_tasks" "$eval_script" --tasks "$slow_tasks" --launcher "$sandbox/slow" > "$sandbox/slow.txt" 2>/dev/null
check "a launcher past the timeout is scored timeout" grep -qE '^tiny +timeout +[0-9]+\.[0-9]s +0 +0$' "$sandbox/slow.txt"
check "the timeout stops the launcher" test -z "$(pgrep -f "$sandbox/slow")"

STUB_POWER="Battery Power" STUB_CPU_LIMIT=60 run_eval green --model custom-model --json > "$sandbox/json.txt" 2> "$sandbox/json.err"
check "--json exits 0" test "$?" -eq 0
check "--model reaches the launcher after the prompt" grep -qxF 'args: 27b -p Set status to fixed in state.txt. --model custom-model' "$sandbox/launch.log"
check "json names the model" test "$(jq -r .model "$sandbox/json.txt")" = custom-model
check "json names the size" test "$(jq -r .size "$sandbox/json.txt")" = 27b
check "json total green" test "$(jq .total.green "$sandbox/json.txt")" = 1
check "json total runs" test "$(jq .total.runs "$sandbox/json.txt")" = 1
check "json median is a number" test "$(jq '.total.median_seconds | type' "$sandbox/json.txt")" = '"number"'
check "json p90 is a number" test "$(jq '.total.p90_seconds | type' "$sandbox/json.txt")" = '"number"'
check "json run task" test "$(jq -r '.runs[0].task' "$sandbox/json.txt")" = tiny
check "json run result" test "$(jq -r '.runs[0].result' "$sandbox/json.txt")" = green
check "json run calls" test "$(jq '.runs[0].calls' "$sandbox/json.txt")" = 3
check "json run denials" test "$(jq '.runs[0].denials' "$sandbox/json.txt")" = 1
check "json run nudges" test "$(jq '.runs[0].nudges' "$sandbox/json.txt")" = 1
check "json run output bytes" test "$(jq '.runs[0].output_bytes' "$sandbox/json.txt")" -gt 0
check "json power is battery" test "$(jq -r .environment.power "$sandbox/json.txt")" = battery
check "json cpu speed limit" test "$(jq .environment.cpu_speed_limit "$sandbox/json.txt")" = 60
report="$(ls "$HOME"/bench-results/task-eval-*.json 2>/dev/null | head -1)"
check "--json saves a report under bench-results" test -n "$report"
check "the saved report matches stdout" cmp -s "$report" "$sandbox/json.txt"
check "--json names the report on stderr" grep -qF "report: $report" "$sandbox/json.err"

check "without --external no backend reaches the launcher" grep -qxF 'external-url: unset' "$sandbox/launch.log"
check "without --record nothing is recorded" grep -qxF 'proxy-record: unset' "$sandbox/launch.log"
check "json without --external has no backend" test "$(jq -c .backend "$sandbox/json.txt")" = null

rm -f "$sandbox/launch.log"
run_eval green --external http://127.0.0.1:9999 mlx-model --external-token secret-bench-token --json > "$sandbox/external.txt" 2> "$sandbox/external.err"
check "--external exits 0" test "$?" -eq 0
check "--external passes the url" grep -qxF 'external-url: http://127.0.0.1:9999' "$sandbox/launch.log"
check "--external passes the model" grep -qxF 'external-model: mlx-model' "$sandbox/launch.log"
check "--external-token passes the token" grep -qxF 'external-token: secret-bench-token' "$sandbox/launch.log"
check "--external keeps --model off the launcher" grep -qxF 'args: 27b -p Set status to fixed in state.txt.' "$sandbox/launch.log"
check "json backend url" test "$(jq -r .backend.url "$sandbox/external.txt")" = http://127.0.0.1:9999
check "json backend model" test "$(jq -r .backend.model "$sandbox/external.txt")" = mlx-model
check "json model is the external model" test "$(jq -r .model "$sandbox/external.txt")" = mlx-model
check "the token stays out of the report" test -z "$(grep -l secret-bench-token "$sandbox/external.txt" "$sandbox/external.err" "$HOME"/bench-results/*.json)"

rm -f "$sandbox/launch.log"
run_eval green --external http://127.0.0.1:9999 mlx-model > /dev/null 2>&1
check "--external without a token sends none" grep -qxF 'external-token: unset' "$sandbox/launch.log"

rm -f "$sandbox/launch.log"
run_eval green --record "$sandbox/record" > /dev/null 2>&1
check "--record turns the proxy on" grep -qxF 'proxy: 1' "$sandbox/launch.log"
check "--record turns recording on" grep -qxF 'proxy-record: 1' "$sandbox/launch.log"
check "--record names the folder" grep -qxF "proxy-record-dir: $sandbox/record" "$sandbox/launch.log"

run_eval green --json > "$sandbox/ac.txt" 2>/dev/null
check "json power is ac on mains" test "$(jq -r .environment.power "$sandbox/ac.txt")" = ac

run_eval green --task nope > /dev/null 2> "$sandbox/unknown.err"
check "an unknown task exits 2" test "$?" -eq 2
check "an unknown task is named" grep -qF 'task-eval: no task nope' "$sandbox/unknown.err"

mkdir -p "$tasks/second/fixture"
cp "$tasks/tiny/task.json" "$tasks/second/task.json"
cp "$tasks/tiny/fixture/state.txt" "$tasks/second/fixture/state.txt"
cp "$tasks/tiny/fixture/check.sh" "$tasks/second/fixture/check.sh"
check "--task picks one" test "$(run_eval red --task second 2>/dev/null | grep -cE '^(tiny|second) ')" = 1
check "--task picks the named one" test "$(run_eval red --task second 2>/dev/null | grep -cE '^second ')" = 1
check "without --task every task runs" test "$(run_eval red 2>/dev/null | grep -cE '^(tiny|second) ')" = 2

real_tasks="$repo/eval/tasks"
expected_tasks="go-table python-impl read-then-edit rename-safely shell-fix"
check "the repo ships the expected tasks" test "$(ls "$real_tasks" | tr '\n' ' ' | sed 's/ $//')" = "$expected_tasks"
for task_dir in "$real_tasks"/*/; do
  name="$(basename "$task_dir")"
  check "$name has a prompt, test, timeout and language" jq -e '.prompt and .test and .timeout_seconds and .language' "$task_dir/task.json" >/dev/null
  check "$name fixture is small" test "$(find "$task_dir/fixture" -type f | wc -l)" -lt 30
done
STUB_TASKS_DIR="$real_tasks" "$eval_script" --tasks "$real_tasks" --launcher "$sandbox/red" > "$sandbox/real-red.txt" 2>/dev/null
check "every real task is red before its fix" grep -qxF 'total: 0/5 green, median seconds -, p90 -' "$sandbox/real-red.txt"
STUB_TASKS_DIR="$real_tasks" "$eval_script" --tasks "$real_tasks" --launcher "$sandbox/green" > "$sandbox/real-green.txt" 2>/dev/null
check "every real task is green after its solution patch" grep -qE '^total: 5/5 green, median seconds [0-9]+\.[0-9], p90 [0-9]+\.[0-9]$' "$sandbox/real-green.txt"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
