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

write_result() {
  local dir="$1" server="$2" model="$3" warm_ttft="$4" decode="$5" parsed="$6"
  cat >"$dir/$server--$model.json" <<JSON
{
  "server": "$server",
  "version": "1.0-$server",
  "model": "$model",
  "repo": "acme/$model-MLX",
  "peak_memory_gb": 30.5,
  "date": "2026-10-21T10:00:00Z",
  "mtp": ${7:-null},
  "bench": {
    "base_url": "http://127.0.0.1:1",
    "model": "$model",
    "runs": [
      {"prefix_tokens": 20000, "scenario": "cold", "input_tokens": 20000, "cache_read_tokens": null, "ttft_seconds": 20.0, "output_tokens": 256, "decode_seconds": 5.0, "prefill_tokens_per_second": 1000.0, "decode_tokens_per_second": $decode},
      {"prefix_tokens": 20000, "scenario": "warm", "input_tokens": 20000, "cache_read_tokens": null, "ttft_seconds": $warm_ttft, "output_tokens": 256, "decode_seconds": 5.0, "prefill_tokens_per_second": 1000.0, "decode_tokens_per_second": $decode},
      {"prefix_tokens": 60000, "scenario": "cold", "input_tokens": 60000, "cache_read_tokens": null, "ttft_seconds": 70.0, "output_tokens": 256, "decode_seconds": 5.0, "prefill_tokens_per_second": 857.1, "decode_tokens_per_second": $decode},
      {"prefix_tokens": 60000, "scenario": "warm", "input_tokens": 60000, "cache_read_tokens": null, "ttft_seconds": $warm_ttft, "output_tokens": 256, "decode_seconds": 5.0, "prefill_tokens_per_second": 900.0, "decode_tokens_per_second": $decode}
    ],
    "tool_calls": {"parsed": $parsed, "trials": 5}
  }
}
JSON
}

results="$sandbox/results"
mkdir "$results"
write_result "$results" ollama tiel-coder-35b 10.0 50.0 5
write_result "$results" omlx tiel-coder-35b 2.0 48.0 5
write_result "$results" vllm-mlx tiel-coder-35b 1.0 30.0 5
write_result "$results" vllm-mlx 'a<b' 1.0 30.0 5

"$report" "$results" >"$sandbox/out" 2>"$sandbox/err"
check "report exits 0" test "$?" -eq 0
html="$results/bench-off.html"
check "report writes bench-off.html" test -s "$html"
check "report prints the HTML path" grep -qxF "$html" "$sandbox/out"
check "html is one page with a title" grep -qF '<title>Backend bench-off</title>' "$html"
check "servers are columns in baseline-first order" \
  grep -qE '<th>ollama</th><th>omlx</th><th>vllm-mlx</th>' "$html"
check "omlx passes against the ollama baseline" grep -qF '<td class="pass">PASS' "$html"
check "vllm-mlx fails on decode" grep -qE '<td class="fail">FAIL[^<]*decode' "$html"
check "ollama is the baseline column" grep -qF '<td class="baseline">baseline' "$html"
check "headline recommends oMLX" grep -qF '<p class="headline">Switch to oMLX' "$html"
check "model names are escaped" grep -qF 'a&lt;b' "$html"
check "a model without an ollama run says so" grep -qF 'no Ollama baseline' "$html"
check "tool calls show parsed over trials" grep -qF '5/5' "$html"
check "rows name the prefix size" grep -qF 'Warm TTFT 60k' "$html"
check "fastest warm TTFT is highlighted" grep -qF '<td class="best">1.00</td>' "$html"
check "html has no external resources" test "$(grep -cE '(src|href)="https?:' "$html")" -eq 0

slow="$sandbox/slow"
mkdir "$slow"
write_result "$slow" ollama tiel-coder-35b 10.0 50.0 5
write_result "$slow" omlx tiel-coder-35b 9.0 50.0 5
"$report" "$slow" >/dev/null 2>&1
check "headline stays on Ollama when no candidate passes" \
  grep -qF '<p class="headline">Stay on Ollama' "$slow/bench-off.html"
check "a small TTFT gain fails the warm TTFT rule" grep -qE '<td class="fail">FAIL[^<]*warm TTFT' "$slow/bench-off.html"

tools="$sandbox/tools"
mkdir "$tools"
write_result "$tools" ollama tiel-coder-35b 10.0 50.0 5
write_result "$tools" omlx tiel-coder-35b 2.0 50.0 4
"$report" "$tools" >/dev/null 2>&1
check "a dropped tool call fails the candidate" grep -qE '<td class="fail">FAIL[^<]*tool calls' "$tools/bench-off.html"

"$report" "$results" --output "$sandbox/custom.html" >/dev/null 2>&1
check "--output picks the file" test -s "$sandbox/custom.html"

mkdir "$sandbox/empty"
"$report" "$sandbox/empty" >"$sandbox/out" 2>"$sandbox/err"
check "no results exits 1" test "$?" -eq 1
check "no results says why" grep -qF 'backend-bench-report: no results' "$sandbox/err"

mtp="$sandbox/mtp"
mkdir "$mtp"
write_result "$mtp" ollama tiel-coder-35b 10.0 50.0 5
write_result "$mtp" ollama-mtp tiel-coder-35b 10.0 55.0 5
write_result "$mtp" omlx tiel-coder-35b 2.0 48.0 5
write_result "$mtp" omlx-mtp tiel-coder-35b 2.0 60.0 5 '{"active": true, "detail": "oMLX log: Lightning MTP active"}'
"$report" "$mtp" >/dev/null 2>&1
check "the servers header puts each MTP column beside its base" \
  grep -qF '<th>ollama</th><th>ollama-mtp</th><th>omlx</th><th>omlx-mtp</th>' "$mtp/bench-off.html"
check "an MTP column shows its decode ratio over the base" grep -qF '<td>×1.25</td>' "$mtp/bench-off.html"
check "the MTP summary gives each base's decode ratio" \
  grep -qF 'MTP decode: tiel-coder-35b: Ollama ×1.10, oMLX ×1.25' "$mtp/bench-off.html"
check "the MTP active row says yes with its detail" grep -qF 'yes (oMLX log: Lightning MTP active)' "$mtp/bench-off.html"
check "the ollama-mtp column is the MTP variant of baseline" grep -qF '<td class="baseline">MTP variant of baseline</td>' "$mtp/bench-off.html"

inactive="$sandbox/inactive"
mkdir "$inactive"
write_result "$inactive" ollama tiel-coder-35b 10.0 50.0 5
write_result "$inactive" omlx-mtp tiel-coder-35b 2.0 60.0 5 '{"active": false, "detail": "x"}'
"$report" "$inactive" >/dev/null 2>&1
check "an MTP run that is not active fails" grep -qF '<td class="fail">FAIL: MTP not active</td>' "$inactive/bench-off.html"

only_mtp="$sandbox/only-mtp"
mkdir "$only_mtp"
write_result "$only_mtp" ollama tiel-coder-35b 10.0 50.0 5
write_result "$only_mtp" omlx tiel-coder-35b 2.0 40.0 5
write_result "$only_mtp" omlx-mtp tiel-coder-35b 2.0 60.0 5
"$report" "$only_mtp" >/dev/null 2>&1
check "the headline can switch to oMLX with MTP" grep -qF '<p class="headline">Switch to oMLX with MTP' "$only_mtp/bench-off.html"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
