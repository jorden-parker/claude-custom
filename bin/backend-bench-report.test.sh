#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
report="$repo/bin/backend-bench-report"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
failures=0

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

meta_line() {
  printf '{"type": "meta", "server": "%s", "version": "1.0-%s", "model": "%s", "repo": "acme/%s-MLX", "conditions": {"power": "%s", "low_power_mode": false, "memory_before_gb": 9.5}}\n' \
    "$1" "$1" "$2" "$2" "${3:-AC Power}"
}

run_line() {
  printf '{"type": "run", "prefix_tokens": %s, "scenario": "%s", "input_tokens": %s, "cache_read_tokens": null, "ttft_seconds": %s, "output_tokens": 256, "decode_seconds": 5.0, "prefill_tokens_per_second": 1000.0, "decode_tokens_per_second": %s}\n' \
    "$1" "$2" "$1" "$3" "$4"
}

write_done() {
  local dir="$1" server="$2" model="$3" warm_ttft="$4" decode="$5" parsed="$6"
  {
    meta_line "$server" "$model" "${7:-AC Power}"
    run_line 20000 cold 20.0 "$decode"
    run_line 20000 warm "$warm_ttft" "$decode"
    run_line 60000 cold 70.0 "$decode"
    run_line 60000 warm "$warm_ttft" "$decode"
    printf '{"type": "tool_calls", "parsed": %s, "trials": 5}\n' "$parsed"
    printf '{"type": "end", "status": "done", "peak_memory_gb": 30.5, "mtp": %s}\n' "${8:-null}"
  } >"$dir/$server--$model.jsonl"
}

write_plan() {
  printf '{"servers": ["ollama", "omlx", "vllm-mlx"], "models": %s, "prefix_tokens": [20000, 60000], "tool_trials": 5, "finished": %s}\n' \
    "$2" "$3" >"$1/plan.json"
}

results="$sandbox/results"
mkdir "$results"
write_done "$results" ollama qwen3.6-35b 10.0 50.0 5
write_done "$results" omlx qwen3.6-35b 2.0 48.0 5
write_done "$results" vllm-mlx qwen3.6-35b 1.0 30.0 5
write_done "$results" vllm-mlx 'a<b' 1.0 30.0 5
write_plan "$results" '["qwen3.6-35b", "a<b"]' true

"$report" "$results" >"$sandbox/out" 2>"$sandbox/err"
check "report exits 0" test "$?" -eq 0
html="$results/bench-off.html"
check "report writes bench-off.html" test -s "$html"
check "report prints the HTML path" grep -qxF "$html" "$sandbox/out"
check "html is one page with a title" grep -qF '<title>Backend bench-off</title>' "$html"
check "servers are columns in plan order" \
  grep -qE '<th>ollama</th><th>omlx</th><th>vllm-mlx</th>' "$html"
check "omlx passes against the ollama baseline" grep -qF '<td class="pass">PASS' "$html"
check "vllm-mlx fails on decode" grep -qE '<td class="fail">FAIL[^<]*decode' "$html"
check "ollama is the baseline column" grep -qF '<td class="baseline">baseline' "$html"
check "headline recommends oMLX" grep -qF '<p class="headline">Switch to oMLX' "$html"
check "model names are escaped" grep -qF 'a&lt;b' "$html"
check "a planned run that never started shows as not run" grep -qF '<td class="waiting">not run</td>' "$html"
check "tool calls show parsed over trials" grep -qF '5/5' "$html"
check "rows name the prefix size" grep -qF 'Warm TTFT 60k' "$html"
check "fastest warm TTFT is highlighted" grep -qF '<td class="best">1.00</td>' "$html"
check "each run shows its server version" grep -qF '1.0-ollama' "$html"
check "each run shows its conditions" grep -qF 'AC Power, 9.5 GB in use' "$html"
check "a finished run does not refresh" test "$(grep -c 'http-equiv="refresh"' "$html")" -eq 0
check "html has no external resources" test "$(grep -cE '(src|href)="https?:' "$html")" -eq 0

live="$sandbox/live"
mkdir "$live"
write_done "$live" ollama qwen3.6-35b 10.0 50.0 5
{
  meta_line omlx qwen3.6-35b
  run_line 20000 cold 3.0 48.0
} >"$live/omlx--qwen3.6-35b.jsonl"
write_plan "$live" '["qwen3.6-35b"]' false
"$report" "$live" >/dev/null 2>&1
page="$live/bench-off.html"
check "a running bench refreshes itself" grep -qF '<meta http-equiv="refresh" content="5">' "$page"
check "a running bench says how far it is" grep -qF '<p class="headline">Running: 1 of 3 runs done' "$page"
check "a running cell shows its progress" grep -qF '<td class="running">running, 1 of 4 measurements</td>' "$page"
check "a running cell already shows its first value" grep -qF '<td class="best">3.00</td>' "$page"
check "a server not started yet is waiting" grep -qF '<td class="waiting">waiting</td>' "$page"
check "a running candidate has no verdict yet" grep -qF '<td class="waiting">–</td>' "$page"

failed="$sandbox/failed"
mkdir "$failed"
{
  meta_line ollama qwen3.6-35b
  printf '{"type": "end", "status": "failed", "peak_memory_gb": null, "error": "ollama create failed", "log_tail": "Error: unsupported <arch>"}\n'
} >"$failed/ollama--qwen3.6-35b.jsonl"
write_done "$failed" omlx qwen3.6-35b 2.0 48.0 5
"$report" "$failed" >/dev/null 2>&1
page="$failed/bench-off.html"
check "a failed run shows its error in the table" grep -qF '<td class="fail">failed: ollama create failed</td>' "$page"
check "a failed run shows its log tail, escaped" grep -qF 'Error: unsupported &lt;arch&gt;' "$page"
check "without a baseline the headline points at the errors" \
  grep -qF '<p class="headline">No Ollama baseline' "$page"
check "a candidate without a baseline says so" grep -qF 'no Ollama baseline' "$page"

slow="$sandbox/slow"
mkdir "$slow"
write_done "$slow" ollama qwen3.6-35b 10.0 50.0 5
write_done "$slow" omlx qwen3.6-35b 9.0 50.0 5 'Battery Power'
"$report" "$slow" >/dev/null 2>&1
page="$slow/bench-off.html"
check "headline stays on Ollama when no candidate passes" grep -qF '<p class="headline">Stay on Ollama' "$page"
check "a small TTFT gain fails the warm TTFT rule" grep -qE '<td class="fail">FAIL[^<]*warm TTFT' "$page"
check "a run on battery is flagged" grep -qF '<p class="warning">' "$page"

tools="$sandbox/tools"
mkdir "$tools"
write_done "$tools" ollama qwen3.6-35b 10.0 50.0 5
write_done "$tools" omlx qwen3.6-35b 2.0 50.0 4
"$report" "$tools" >/dev/null 2>&1
check "a dropped tool call fails the candidate" grep -qE '<td class="fail">FAIL[^<]*tool calls' "$tools/bench-off.html"

mtp="$sandbox/mtp"
mkdir "$mtp"
write_done "$mtp" ollama qwen3.6-35b 10.0 50.0 5
write_done "$mtp" ollama-mtp qwen3.6-35b 10.0 55.0 5 'AC Power' '{"active": null, "detail": "draft_num_predict 4"}'
write_done "$mtp" omlx qwen3.6-35b 2.0 48.0 5
write_done "$mtp" omlx-mtp qwen3.6-35b 2.0 60.0 5 'AC Power' '{"active": true, "detail": "oMLX log: Lightning MTP active"}'
"$report" "$mtp" >/dev/null 2>&1
page="$mtp/bench-off.html"
check "the servers header puts each MTP column beside its base" \
  grep -qF '<th>ollama</th><th>ollama-mtp</th><th>omlx</th><th>omlx-mtp</th>' "$page"
check "an MTP column shows its decode ratio over the base" grep -qF '<td>×1.25</td>' "$page"
check "the MTP summary gives each base's decode ratio" \
  grep -qF 'MTP decode: qwen3.6-35b: Ollama ×1.10, oMLX ×1.25' "$page"
check "the MTP active row says yes with its detail" grep -qF 'yes (oMLX log: Lightning MTP active)' "$page"
check "an unverified MTP run says so" grep -qF 'unverified (draft_num_predict 4)' "$page"
check "the ollama-mtp column is the baseline for MTP columns" \
  grep -qF '<td class="baseline">baseline for MTP columns</td>' "$page"
check "each column names the weights it ran" grep -qF 'acme/qwen3.6-35b-MLX' "$page"
check "an MTP candidate passes against ollama-mtp" test "$(grep -o '<td class="pass">PASS</td>' "$page" | wc -l)" -eq 2

inactive="$sandbox/inactive"
mkdir "$inactive"
write_done "$inactive" ollama qwen3.6-35b 10.0 50.0 5
write_done "$inactive" omlx-mtp qwen3.6-35b 2.0 60.0 5 'AC Power' '{"active": false, "detail": "x"}'
"$report" "$inactive" >/dev/null 2>&1
check "an MTP run that is not active fails" grep -qF '<td class="fail">FAIL: MTP not active</td>' "$inactive/bench-off.html"

only_mtp="$sandbox/only-mtp"
mkdir "$only_mtp"
write_done "$only_mtp" ollama qwen3.6-35b 10.0 50.0 5
write_done "$only_mtp" ollama-mtp qwen3.6-35b 10.0 50.0 5
write_done "$only_mtp" omlx qwen3.6-35b 2.0 40.0 5
write_done "$only_mtp" omlx-mtp qwen3.6-35b 2.0 60.0 5
"$report" "$only_mtp" >/dev/null 2>&1
check "the headline can switch to oMLX with MTP" grep -qF '<p class="headline">Switch to oMLX with MTP' "$only_mtp/bench-off.html"

no_mtp_baseline="$sandbox/no-mtp-baseline"
mkdir "$no_mtp_baseline"
write_done "$no_mtp_baseline" ollama qwen3.6-35b 10.0 50.0 5
write_done "$no_mtp_baseline" omlx-mtp qwen3.6-35b 2.0 60.0 5
"$report" "$no_mtp_baseline" >/dev/null 2>&1
check "an MTP candidate needs an ollama-mtp baseline on the same weights" \
  grep -qF '<td class="baseline">no Ollama MTP baseline</td>' "$no_mtp_baseline/bench-off.html"

"$report" "$results" --output "$sandbox/custom.html" >/dev/null 2>&1
check "--output picks the file" test -s "$sandbox/custom.html"

mkdir "$sandbox/empty"
"$report" "$sandbox/empty" >"$sandbox/out" 2>"$sandbox/err"
check "no results exits 1" test "$?" -eq 1
check "no results says why" grep -qF 'backend-bench-report: no results' "$sandbox/err"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
