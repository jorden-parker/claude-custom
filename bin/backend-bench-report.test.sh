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
  local server="$1" model="$2"
  printf '{"type": "meta", "server": "%s", "version": "1.0-%s", "model": "%s", "weights": "%s-weights", "repo": "acme/%s-MLX", "weights_bytes": %s, "weights_revision": "abc123", "stage": "%s", "bench_version": 3, "conditions": {"power": "%s", "low_power_mode": false, "memory_before_gb": 9.5}}\n' \
    "$server" "$server" "$model" "$server" "$model" "${WEIGHTS_BYTES:-20000000000}" "${STAGE:-screen}" "${POWER:-AC Power}"
}

run_line() {
  printf '{"type": "run", "prefix_tokens": %s, "scenario": "%s", "input_tokens": %s, "cache_read_tokens": null, "ttft_seconds": %s, "output_tokens": 256, "decode_seconds": 5.0, "prefill_tokens_per_second": 1000.0, "decode_tokens_per_second": %s, "thinking_leak": %s}\n' \
    "$1" "$2" "$1" "$3" "$4" "${LEAK:-false}"
}

unit_path() {
  printf '%s/%s--%s--%s.jsonl' "$1" "$2" "$3" "${STAGE:-screen}"
}

write_done() {
  local dir="$1" server="$2" model="$3" warm_ttft="$4" decode="$5" parsed="$6"
  {
    meta_line "$server" "$model"
    printf '{"type": "gate", "status": "passed", "reason": null, "seconds": 12.5}\n'
    run_line 20000 cold 20.0 "$decode"
    run_line 20000 warm "$warm_ttft" "$decode"
    run_line 60000 cold 70.0 "$decode"
    run_line 60000 warm "$warm_ttft" "$decode"
    printf '{"type": "tool_calls", "parsed": %s, "trials": 5}\n' "$parsed"
    printf '{"type": "end", "status": "%s", "reason": %s, "peak_memory_gb": 30.5, "mtp": %s}\n' \
      "${END_STATUS:-done}" "${END_REASON:-null}" "${MTP:-null}"
  } >"$(unit_path "$dir" "$server" "$model")"
}

write_stopped() {
  local dir="$1" server="$2" model="$3" status="$4" reason="$5" gate="$6"
  {
    meta_line "$server" "$model"
    printf '{"type": "gate", "status": "%s", "reason": "%s", "seconds": 120}\n' "$gate" "$reason"
    printf '{"type": "end", "status": "%s", "reason": "%s", "peak_memory_gb": null, "mtp": null, "log_tail": "boom <tail>"}\n' "$status" "$reason"
  } >"$(unit_path "$dir" "$server" "$model")"
}

add_replay() {
  printf '{"type": "replay", "requests": 10, "basis": "cached token count", "verbatim": %s, "stabilized": null}\n' "$2" >>"$1"
}

write_plan() {
  printf '{"servers": %s, "models": %s, "prefix_tokens": [20000, 60000], "tool_trials": 5, "finished": %s, "stages": ["screen", "deep"], "finalists": %s}\n' \
    "$2" "$3" "$4" "${5:-[]}" >"$1/plan.json"
}

render() {
  "$report" "$1" >/dev/null 2>&1
  page="$1/bench-off.html"
}

results="$sandbox/results"
mkdir "$results"
write_done "$results" ollama qwen3.6-35b 10.0 50.0 5
write_done "$results" omlx qwen3.6-35b 2.0 48.0 5
write_done "$results" vllm-mlx qwen3.6-35b 9.0 55.0 5
write_done "$results" mtplx qwen3.6-35b 9.0 70.0 5
write_done "$results" vllm-mlx 'a<b' 1.0 30.0 5
write_plan "$results" '["ollama", "omlx", "vllm-mlx", "mtplx"]' '["qwen3.6-35b", "a<b"]' true

"$report" "$results" >"$sandbox/out" 2>"$sandbox/err"
check "report exits 0" test "$?" -eq 0
html="$results/bench-off.html"
check "report writes bench-off.html" test -s "$html"
check "report prints the HTML path" grep -qxF "$html" "$sandbox/out"
check "html is one page with a title" grep -qF '<title>Backend bench-off</title>' "$html"
check "servers are columns in plan order" grep -qE '<th>ollama</th><th>omlx</th><th>vllm-mlx</th><th>mtplx</th>' "$html"
check "a much lower warm TTFT passes" grep -qF '<td class="pass">PASS' "$html"
check "a small TTFT gain with a small decode gain fails" grep -qE '<td class="fail">FAIL[^<]*warm TTFT' "$html"
check "a 20% decode gain with no worse TTFT passes" test "$(grep -o '<td class="pass">PASS</td>' "$html" | wc -l)" -eq 2
check "ollama is the baseline column" grep -qF '<td class="baseline">baseline' "$html"
check "without finals the headline names the finalists" grep -qF '<p class="headline">Finalists: omlx, mtplx' "$html"
check "each table names its model and stage" grep -qF '<h2>qwen3.6-35b · screen</h2>' "$html"
check "model names are escaped" grep -qF 'a&lt;b' "$html"
check "a planned run that never started shows as not run" grep -qF '<td class="waiting">not run</td>' "$html"
check "tool calls show parsed over trials" grep -qF '5/5' "$html"
check "rows name the prefix size" grep -qF 'Warm TTFT 60k' "$html"
check "fastest warm TTFT is highlighted" grep -qF '<td class="best">2.00</td>' "$html"
check "each run shows its server version" grep -qF '1.0-ollama' "$html"
check "each run shows its weights" grep -qF '<td>omlx-weights</td>' "$html"
check "each run shows its weights size in GB" grep -qF '<tr><td>Weights size (GB)</td><td>20.0</td>' "$html"
check "each run shows its gate" grep -qF '<td class="pass">passed in 12 s</td>' "$html"
check "each run shows no thinking leak" grep -qF '<tr><td>Thinking leak</td><td>no</td>' "$html"
check "each run shows its conditions" grep -qF 'AC Power, 9.5 GB in use' "$html"
check "a finished run does not refresh" test "$(grep -c 'http-equiv="refresh"' "$html")" -eq 0
check "html has no external resources" test "$(grep -cE '(src|href)="https?:' "$html")" -eq 0
check "no finals table without finals.json" test "$(grep -c '<h2>Finals</h2>' "$html")" -eq 0

families="$sandbox/families"
mkdir "$families"
write_done "$families" ollama qwen3.6-35b 10.0 50.0 5
write_plan "$families" '["ollama", "llama-server", "omlx", "llama-server-mtp", "ollama-mtp", "llama-server-q8kv", "mtplx-nomtp", "mtplx"]' '["qwen3.6-35b"]' false
render "$families"
check "columns group by server family in first-seen order" \
  grep -qF '<th>ollama</th><th>ollama-mtp</th><th>llama-server</th><th>llama-server-mtp</th><th>llama-server-q8kv</th><th>omlx</th><th>mtplx-nomtp</th><th>mtplx</th>' "$page"
check "a family row spans each family's columns" \
  grep -qF '<th></th><th colspan="2">ollama</th><th colspan="3">llama-server</th><th colspan="1">omlx</th><th colspan="2">mtplx</th>' "$page"

live="$sandbox/live"
mkdir "$live"
write_done "$live" ollama qwen3.6-35b 10.0 50.0 5
{
  meta_line omlx qwen3.6-35b
  run_line 20000 cold 3.0 48.0
} >"$(unit_path "$live" omlx qwen3.6-35b)"
write_plan "$live" '["ollama", "omlx", "vllm-mlx"]' '["qwen3.6-35b"]' false
render "$live"
check "a running bench refreshes itself" grep -qF '<meta http-equiv="refresh" content="5">' "$page"
check "a running bench says how far it is" grep -qF '<p class="headline">Running: 1 of 3 runs done' "$page"
check "a running cell shows its progress" grep -qF '<td class="running">running, 1 of 4 measurements</td>' "$page"
check "a running cell already shows its first value" grep -qF '<td class="best">3.00</td>' "$page"
check "a server not started yet is waiting" grep -qF '<td class="waiting">waiting</td>' "$page"
check "a running candidate has no verdict yet" grep -qF '<td class="waiting">–</td>' "$page"

stopped="$sandbox/stopped"
mkdir "$stopped"
write_done "$stopped" ollama qwen3.6-35b 10.0 50.0 5
write_stopped "$stopped" omlx qwen3.6-35b gate-failed 'served model id was claude-x' failed
write_stopped "$stopped" rapid-mlx qwen3.6-35b lost 'cold prefill 1.8x slower than ollama' passed
write_stopped "$stopped" optiq qwen3.6-35b failed 'server exited' passed
END_STATUS=cached END_REASON='"same version, weights and bench"' write_done "$stopped" vllm-mlx qwen3.6-35b 2.0 50.0 5
render "$stopped"
check "a gate failure shows its reason in the status" grep -qF '<td class="fail">gate-failed: served model id was claude-x</td>' "$page"
check "a gate failure shows in the gate row" grep -qF '<td class="fail">failed: served model id was claude-x</td>' "$page"
check "a gate failure fails the verdict" grep -qF '<td class="fail">FAIL: gate-failed</td>' "$page"
check "a lost cell shows why it stopped" grep -qF '<td class="fail">lost: cold prefill 1.8x slower than ollama</td>' "$page"
check "a lost cell fails the verdict" grep -qF '<td class="fail">FAIL: lost</td>' "$page"
check "a failed run shows its reason in the table" grep -qF '<td class="fail">failed: server exited</td>' "$page"
check "a failed run shows its log tail, escaped" grep -qF 'boom &lt;tail&gt;' "$page"
check "a cached cell says it was reused and why" grep -qF '<td class="done">cached: same version, weights and bench</td>' "$page"
check "a cached cell is judged like a finished one" grep -qF '<td class="pass">PASS</td>' "$page"
check "a cached finalist is named" grep -qF '<p class="headline">Finalists: vllm-mlx' "$page"

no_baseline="$sandbox/no-baseline"
mkdir "$no_baseline"
write_stopped "$no_baseline" ollama qwen3.6-35b failed 'ollama create failed' passed
write_done "$no_baseline" omlx qwen3.6-35b 2.0 48.0 5
render "$no_baseline"
check "without a baseline the headline points at the errors" grep -qF '<p class="headline">No Ollama baseline' "$page"
check "a candidate without a baseline says so" grep -qF '<td class="baseline">no Ollama baseline</td>' "$page"

guard="$sandbox/guard"
mkdir "$guard"
write_done "$guard" ollama qwen3.6-35b 10.0 50.0 5
WEIGHTS_BYTES=15000000000 write_done "$guard" optiq qwen3.6-35b 2.0 60.0 5
WEIGHTS_BYTES=18500000000 write_done "$guard" omlx qwen3.6-35b 2.0 60.0 5
render "$guard"
check "a candidate on much smaller weights gets no verdict" grep -qF '<td class="waiting">no verdict: smaller weights</td>' "$page"
check "a candidate within 90% of the weights is judged" grep -qF '<td class="pass">PASS</td>' "$page"
check "the weights size row shows the smaller weights" grep -qF '<td>15.0</td>' "$page"
check "the smaller weights are no finalist" grep -qF '<p class="headline">Finalists: omlx' "$page"

leak="$sandbox/leak"
mkdir "$leak"
write_done "$leak" ollama qwen3.6-35b 10.0 50.0 5
LEAK=true write_done "$leak" omlx qwen3.6-35b 2.0 60.0 5
render "$leak"
check "a thinking leak shows on the page" grep -qF '<tr><td>Thinking leak</td><td>no</td><td class="fail">yes</td></tr>' "$page"
check "a thinking leak fails the candidate" grep -qE '<td class="fail">FAIL[^<]*thinking leak' "$page"
check "with no finalist the headline stays on Ollama" grep -qF '<p class="headline">Stay on Ollama' "$page"

replay="$sandbox/replay"
mkdir "$replay"
write_done "$replay" ollama qwen3.6-35b 10.0 50.0 5
write_done "$replay" omlx qwen3.6-35b 2.0 50.0 5
write_done "$replay" vllm-mlx qwen3.6-35b 2.0 50.0 5
write_done "$replay" llama-server qwen3.6-35b 2.0 50.0 5
add_replay "$(unit_path "$replay" ollama qwen3.6-35b)" 80.0
add_replay "$(unit_path "$replay" omlx qwen3.6-35b)" 70.0
add_replay "$(unit_path "$replay" vllm-mlx qwen3.6-35b)" 76.0
echo '{"type": "replay", "error": "prefix-ab failed; see the unit log"}' >>"$(unit_path "$replay" llama-server qwen3.6-35b)"
render "$replay"
check "a replay hit rate over 5 points lower fails" grep -qE '<td class="fail">FAIL[^<]*replay cache hit 70.0% vs 80.0%' "$page"
check "a replay hit rate within 5 points passes, and a failed replay is not judged" \
  test "$(grep -o '<td class="pass">PASS</td>' "$page" | wc -l)" -eq 2
check "the replay row shows values and a failure" \
  grep -qF '<tr><td>Replay cache hit %</td><td>80.0 (10 requests)</td><td>failed</td><td>70.0 (10 requests)</td><td>76.0 (10 requests)</td></tr>' "$page"

tools="$sandbox/tools"
mkdir "$tools"
write_done "$tools" ollama qwen3.6-35b 10.0 50.0 5
write_done "$tools" omlx qwen3.6-35b 2.0 50.0 4
render "$tools"
check "a dropped tool call fails the candidate" grep -qE '<td class="fail">FAIL[^<]*tool calls' "$page"

battery="$sandbox/battery"
mkdir "$battery"
write_done "$battery" ollama qwen3.6-35b 10.0 50.0 5
POWER='Battery Power' write_done "$battery" omlx qwen3.6-35b 2.0 50.0 5
render "$battery"
check "a run on battery is flagged" grep -qF '<p class="warning">' "$page"

mtp="$sandbox/mtp"
mkdir "$mtp"
write_done "$mtp" ollama qwen3.6-35b 10.0 50.0 5
MTP='{"active": null, "detail": "draft_num_predict 4"}' write_done "$mtp" ollama-mtp qwen3.6-35b 10.0 55.0 5
write_done "$mtp" omlx qwen3.6-35b 2.0 48.0 5
MTP='{"active": true, "detail": "oMLX log: Lightning MTP active"}' write_done "$mtp" omlx-mtp qwen3.6-35b 2.0 60.0 5
write_done "$mtp" mtplx-nomtp qwen3.6-35b 10.0 40.0 5
MTP='{"active": false, "detail": "no draft head"}' write_done "$mtp" mtplx qwen3.6-35b 10.0 80.0 5
render "$mtp"
check "an MTP column shows its decode ratio over its MTP-off pair" grep -qF '<td>×1.25</td>' "$page"
check "a -nomtp column is the MTP-off pair" grep -qF '<td>×2.00</td>' "$page"
check "the MTP summary gives each pair's decode ratio" \
  grep -qF 'MTP decode: qwen3.6-35b · screen: ollama-mtp ×1.10, mtplx ×2.00, omlx-mtp ×1.25' "$page"
check "the MTP active row says yes with its detail" grep -qF 'yes (oMLX log: Lightning MTP active)' "$page"
check "an unverified MTP run says so" grep -qF 'unverified (draft_num_predict 4)' "$page"
check "an MTP run that is not active fails" grep -qE '<td class="fail">FAIL[^<]*MTP not active' "$page"

stages="$sandbox/stages"
mkdir "$stages"
write_done "$stages" ollama qwen3.6-35b 10.0 50.0 5
write_done "$stages" omlx qwen3.6-35b 2.0 50.0 5
write_done "$stages" vllm-mlx qwen3.6-35b 9.5 50.0 5
STAGE=deep write_done "$stages" ollama qwen3.6-35b 10.0 50.0 5
STAGE=deep write_done "$stages" omlx qwen3.6-35b 2.0 50.0 5
write_plan "$stages" '["ollama", "omlx", "vllm-mlx"]' '["qwen3.6-35b", "qwen3.8-27b"]' true '["omlx"]'
render "$stages"
check "the screen stage has its own table" grep -qF '<h2>qwen3.6-35b · screen</h2>' "$page"
check "the deep stage has its own table" grep -qF '<h2>qwen3.6-35b · deep</h2>' "$page"
check "the screen table lists every server" grep -qF '<th>ollama</th><th>omlx</th><th>vllm-mlx</th>' "$page"
check "the deep table lists the baseline and the finalists only" grep -qE '<th>ollama</th><th>omlx</th></tr>' "$page"
check "a model with no results yet gets no table" test "$(grep -c 'qwen3.8-27b · ' "$page")" -eq 0

legacy="$sandbox/legacy"
mkdir "$legacy"
{
  printf '{"type": "meta", "server": "ollama", "version": "0.9", "model": "qwen3.6-35b", "weights": "w", "repo": "r", "conditions": {}}\n'
  printf '{"type": "run", "prefix_tokens": 20000, "scenario": "warm", "input_tokens": 20000, "cache_read_tokens": null, "ttft_seconds": 4.0, "output_tokens": 256, "decode_seconds": 5.0, "prefill_tokens_per_second": 1000.0, "decode_tokens_per_second": 50.0}\n'
  printf '{"type": "end", "status": "done", "peak_memory_gb": 30.5, "mtp": null}\n'
} >"$legacy/ollama--qwen3.6-35b.jsonl"
"$report" "$legacy" >/dev/null 2>"$sandbox/legacy.err"
check "an old file without a stage still renders" test "$?" -eq 0
check "an old file shows its numbers" grep -qF '4.00' "$legacy/bench-off.html"

write_finals() {
  printf '%s\n' "$2" >"$1/finals.json"
}

finals_cell() {
  printf '{"green": %s, "runs": 5, "median_seconds": %s, "timeouts": %s}' "$1" "$2" "$3"
}

finals_dir() {
  local dir="$sandbox/$1"
  mkdir "$dir"
  write_done "$dir" ollama qwen3.6-35b 10.0 50.0 5
  write_done "$dir" omlx qwen3.6-35b 2.0 50.0 5
  printf '%s' "$dir"
}

win="$(finals_dir finals-win)"
write_finals "$win" "{\"baseline\": \"ollama\", \"models\": {
  \"qwen3.6-35b\": {\"ollama\": $(finals_cell 5 150 0), \"omlx\": $(finals_cell 5 100 0), \"vllm-mlx\": $(finals_cell 4 90 0)},
  \"qwen3.8-27b\": {\"ollama\": $(finals_cell 4 200 1), \"omlx\": $(finals_cell 5 160 1)}}}"
render "$win"
check "a challenger winning every model it ran on is the switch" grep -qF '<p class="headline">Switch to omlx</p>' "$page"
check "the finals table shows when finals.json exists" grep -qF '<h2>Finals</h2>' "$page"
check "the finals table marks each model's winner" grep -qF '<tr><td>qwen3.6-35b</td><td>omlx</td><td>5/5</td><td>100</td><td>0</td><td class="pass">winner</td></tr>' "$page"
check "fewer green runs never wins, however fast" grep -qF '<tr><td>qwen3.6-35b</td><td>vllm-mlx</td><td>4/5</td><td>90</td><td>0</td><td>–</td></tr>' "$page"

slow="$(finals_dir finals-slow)"
write_finals "$slow" "{\"baseline\": \"ollama\", \"models\": {\"qwen3.6-35b\": {\"ollama\": $(finals_cell 5 150 0), \"omlx\": $(finals_cell 5 140 0)}}}"
render "$slow"
check "a median under 15% faster stays on Ollama" grep -qF '<p class="headline">Stay on Ollama</p>' "$page"

timeouts="$(finals_dir finals-timeouts)"
write_finals "$timeouts" "{\"baseline\": \"ollama\", \"models\": {\"qwen3.6-35b\": {\"ollama\": $(finals_cell 5 150 0), \"omlx\": $(finals_cell 5 100 1)}}}"
render "$timeouts"
check "a timeout the baseline lacks stays on Ollama" grep -qF '<p class="headline">Stay on Ollama</p>' "$page"

split="$(finals_dir finals-split)"
write_finals "$split" "{\"baseline\": \"ollama\", \"models\": {
  \"qwen3.6-35b\": {\"ollama\": $(finals_cell 5 150 0), \"omlx\": $(finals_cell 5 100 0)},
  \"qwen3.8-27b\": {\"ollama\": $(finals_cell 5 150 0), \"omlx\": $(finals_cell 5 145 0)}}}"
render "$split"
check "a challenger winning one model of two gets per-model wording" \
  grep -qF '<p class="headline">Switch qwen3.6-35b to omlx; stay on Ollama for qwen3.8-27b</p>' "$page"

rm -f "$split/bench-off.html"
check "--headline prints only the headline" \
  test "$("$report" "$split" --headline)" = 'Switch qwen3.6-35b to omlx; stay on Ollama for qwen3.8-27b'
check "--headline writes no page" test ! -e "$split/bench-off.html"

broken="$(finals_dir finals-broken)"
printf 'not json' >"$broken/finals.json"
"$report" "$broken" >/dev/null 2>"$sandbox/broken.err"
check "a broken finals.json still renders the page" test "$?" -eq 0
check "a broken finals.json is reported" grep -qF 'finals.json' "$sandbox/broken.err"

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
