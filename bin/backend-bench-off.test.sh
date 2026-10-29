#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
sandbox="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
trap 'pkill -f "$sandbox/stubbin" 2>/dev/null; rm -rf "$sandbox"' EXIT
failures=0

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

mkdir -p "$sandbox/repo/bin" "$sandbox/stubbin" "$sandbox/logs"
cp "$repo/bin/backend-bench-off" "$repo/bin/backend-bench-report" "$sandbox/repo/bin/"
script="$sandbox/repo/bin/backend-bench-off"
logs="$sandbox/logs"

stub() {
  {
    echo '#!/bin/sh'
    cat
  } >"$sandbox/stubbin/$1"
  chmod +x "$sandbox/stubbin/$1"
}

cat >"$sandbox/repo/bin/messages-bench" <<EOF
#!/bin/sh
echo "\$*" >> "$logs/bench.log"
snapshot=\$(wc -l < "$logs/bench.log" | tr -d ' ')
[ -f "\$BENCH_RESULTS/bench-off.html" ] && cp "\$BENCH_RESULTS/bench-off.html" "$logs/page.\$snapshot.html"
case "\$*" in
  *--jsonl*)
    echo '{"type": "run", "prefix_tokens": 20000, "scenario": "cold", "input_tokens": 20000, "cache_read_tokens": null, "ttft_seconds": 2.0, "output_tokens": 256, "decode_seconds": 5.0, "prefill_tokens_per_second": 10000.0, "decode_tokens_per_second": 51.2}'
    echo '{"type": "run", "prefix_tokens": 20000, "scenario": "warm", "input_tokens": 20000, "cache_read_tokens": null, "ttft_seconds": 1.0, "output_tokens": 256, "decode_seconds": 5.0, "prefill_tokens_per_second": 20000.0, "decode_tokens_per_second": 51.2}'
    echo '{"type": "tool_calls", "parsed": 5, "trials": 5}'
    ;;
  *) echo '{}' ;;
esac
EOF
chmod +x "$sandbox/repo/bin/messages-bench"

cat >"$sandbox/repo/bin/extract-mtp-weights" <<EOF
#!/bin/sh
echo "\$*" >> "$logs/extract.log"
EOF
chmod +x "$sandbox/repo/bin/extract-mtp-weights"

stub hf <<EOF
echo "\$*" >> "$logs/hf.log"
mkdir -p "\$4"
echo '{}' > "\$4/config.json"
EOF
stub ollama <<EOF
echo "\$*" >> "$logs/ollama.log"
case "\$1" in
  --version) echo 'ollama version is 0.19.0' ;;
  show) exit 1 ;;
  ps) printf 'NAME ID SIZE PROCESSOR UNTIL\nother-model:latest abc 20 GB 100%% GPU 4 minutes\n' ;;
  create)
    cat "\$4" >> "$logs/ollama.log"
    [ -n "\${STUB_CREATE_FAIL:-}" ] && { echo 'Error: unsupported architecture'; exit 1; }
    ;;
esac
exit 0
EOF
serve_until_stopped="trap 'rm -f \"$logs/serving\"; exit 0' TERM
touch \"$logs/serving\"
sleep 60 &
wait"
stub omlx <<EOF
echo "OMLX_PORT=\${OMLX_PORT:-} \$*" >> "$logs/omlx.log"
[ "\$2" = --help ] && exit 0
echo "Speculative backend selected for $sandbox/models/qwen3.6-35b-mtp: Lightning MTP (model_type=qwen3_5_moe, active)"
echo "Lightning MTP is inactive for $sandbox/models/qwen3.8-27b-mtp"
$serve_until_stopped
EOF
stub vllm-mlx <<EOF
echo "\$*" >> "$logs/vllm.log"
$serve_until_stopped
EOF
stub curl <<EOF
echo "\$*" >> "$logs/curl.log"
[ -n "\${STUB_CURL_FAIL:-}" ] && exit 7
ids='{"id": "qwen3.6-35b"}, {"id": "qwen3.6-35b-mtp"}, {"id": "qwen3.8-27b"}, {"id": "qwen3.8-27b-mtp"}'
[ -n "\${STUB_MODEL_IDS:-}" ] && ids="\$STUB_MODEL_IDS"
case "\$*" in
  *"-X PUT"*)
    if [ -n "\${STUB_OMLX_MTP_REFUSE:-}" ]; then printf '%s\n%s' '{"detail": "no mtp tensors"}' 400; else printf '%s\n%s' '{}' 200; fi ;;
  */v1/status*) echo '{"mtp": {"enabled": true, "attempted": 100, "accepted": 80, "rejected": 20, "acceptance_rate": 0.8}}' ;;
  *:8000/*) exit 7 ;;
  */v1/models*) [ -e "$logs/serving" ] || exit 7; echo "{\"data\": [\$ids]}" ;;
esac
exit 0
EOF
stub vm_stat <<'EOF'
echo 'Mach Virtual Memory Statistics: (page size of 16384 bytes)'
echo 'Pages active:                          1000000.'
echo 'Pages wired down:                       500000.'
echo 'Pages occupied by compressor:           100000.'
EOF
stub pmset <<'EOF'
case "$*" in
  "-g batt") echo "Now drawing from '${STUB_POWER:-AC Power}'" ;;
  "-g") echo ' lowpowermode         0' ;;
esac
EOF
stub brew <<'EOF'
[ "$1" = list ] && echo 'omlx 0.6.3'
exit 0
EOF
stub uv <<'EOF'
[ "$2" = list ] && echo 'vllm-mlx v0.4.1'
exit 0
EOF

export PATH="$sandbox/stubbin:$PATH"
export BENCH_MODELS="$sandbox/models"
export BENCH_RESULTS="$sandbox/results"
export BENCH_COOLDOWN=0
unset OLLAMA_HOST VLLM_MLX_EXTRA_ARGS

run() {
  "$script" "$@" >"$sandbox/out" 2>"$sandbox/err"
}

line_of() {
  jq -c --arg type "$2" 'select(.type == $type)' "$1"
}

end_mentions() {
  line_of "$1" end | jq -e --arg field "$2" --arg text "$3" '.[$field] | contains($text)' >/dev/null
}

run all
check "all before download exits 1" test "$?" -eq 1
check "all before download says to download" grep -qF 'backend-bench-off download' "$sandbox/err"

run download
check "download exits 0" test "$?" -eq 0
check "download fetches the stock 35B-A3B" grep -qxF "download mlx-community/Qwen3.6-35B-A3B-4bit --local-dir $BENCH_MODELS/qwen3.6-35b" "$logs/hf.log"
check "download fetches the 27B dense" grep -qxF "download mlx-community/Qwen3.8-27B-4bit --local-dir $BENCH_MODELS/qwen3.8-27b" "$logs/hf.log"
check "download fetches the side model" grep -qxF "download mlx-community/Qwen3-4B-4bit --local-dir $BENCH_MODELS/qwen3-4b-cc" "$logs/hf.log"
check "download fetches the 35B MTP weights" grep -qxF "download Jundot/Qwen3.6-35B-A3B-oQ4e-mtp --local-dir $BENCH_MODELS/qwen3.6-35b-mtp" "$logs/hf.log"
check "download fetches the 27B MTP weights" grep -qxF "download Jundot/Qwen3.8-27B-oQ4e-mtp --local-dir $BENCH_MODELS/qwen3.8-27b-mtp" "$logs/hf.log"
run download
check "a second download skips what is there" test "$(wc -l <"$logs/hf.log")" -eq 5

run run ollama qwen3.6-35b
check "run ollama exits 0" test "$?" -eq 0
unit="$BENCH_RESULTS/ollama--qwen3.6-35b.jsonl"
check "ollama unloads models left loaded before it starts" grep -qxF 'stop other-model:latest' "$logs/ollama.log"
check "ollama imports the downloaded weights" grep -qxF "FROM $BENCH_MODELS/qwen3.6-35b" "$logs/ollama.log"
check "ollama import sets a 64k context" grep -qxF 'PARAMETER num_ctx 65536' "$logs/ollama.log"
check "the warm-up is one short request" \
  grep -qxF -- '--base-url http://localhost:11434 --model bench-qwen3.6-35b --auth-token ollama --prefix-tokens 1000 --tool-trials 0 --json' "$logs/bench.log"
check "the measured run streams jsonl" \
  grep -qxF -- '--base-url http://localhost:11434 --model bench-qwen3.6-35b --auth-token ollama --prefix-tokens 20000 60000 --tool-trials 5 --jsonl' "$logs/bench.log"
check "ollama unloads its model afterwards" grep -qxF 'stop bench-qwen3.6-35b' "$logs/ollama.log"
check "the unit starts with server, version and repo" \
  test "$(line_of "$unit" meta | jq -r '[.server, .version, .model, .repo] | join(" ")')" = "ollama 0.19.0 qwen3.6-35b mlx-community/Qwen3.6-35B-A3B-4bit"
check "the unit records power and memory before" \
  test "$(line_of "$unit" meta | jq -r '[.conditions.power, .conditions.low_power_mode, .conditions.memory_before_gb] | join(" ")')" = "AC Power false 26.2"
check "the unit keeps every streamed measurement" test "$(line_of "$unit" run | wc -l)" -eq 2
check "the unit ends done with peak memory" test "$(line_of "$unit" end | jq -r '[.status, .peak_memory_gb] | join(" ")')" = "done 26.2"
check "a single run renders the page" test -s "$BENCH_RESULTS/bench-off.html"
check "an MTP-off run records mtp as null" test "$(line_of "$unit" end | jq -r 'has("mtp") and .mtp == null')" = true

run run ollama-mtp qwen3.6-35b
check "run ollama-mtp exits 0" test "$?" -eq 0
unit="$BENCH_RESULTS/ollama-mtp--qwen3.6-35b.jsonl"
check "ollama-mtp imports the MTP weights" grep -qxF "FROM $BENCH_MODELS/qwen3.6-35b-mtp" "$logs/ollama.log"
check "ollama-mtp imports with draft_num_predict 4" grep -qxF 'PARAMETER draft_num_predict 4' "$logs/ollama.log"
check "ollama-mtp benches the mtp model tag" grep -qF -- '--model bench-qwen3.6-35b-mtp --auth-token ollama --prefix-tokens 20000 60000' "$logs/bench.log"
check "ollama-mtp unloads its mtp model after the run" grep -qxF 'stop bench-qwen3.6-35b-mtp' "$logs/ollama.log"
check "ollama-mtp records which weights it ran" test "$(line_of "$unit" meta | jq -r '[.weights, .repo] | join(" ")')" = "qwen3.6-35b-mtp Jundot/Qwen3.6-35B-A3B-oQ4e-mtp"
check "ollama-mtp reports MTP as unverified" test "$(line_of "$unit" end | jq -r .mtp.active)" = null

STUB_CREATE_FAIL=1 run run ollama qwen3.8-27b
check "a failed import exits 1" test "$?" -eq 1
failed="$BENCH_RESULTS/ollama--qwen3.8-27b.jsonl"
check "a failed import ends failed with the step" test "$(line_of "$failed" end | jq -r '[.status, .error] | join(": ")')" = "failed: importing qwen3.8-27b into Ollama"
check "a failed import keeps the server's message" end_mentions "$failed" log_tail 'unsupported architecture'

STUB_CURL_FAIL=1 run run ollama qwen3.6-35b
check "unreachable ollama exits 1" test "$?" -eq 1
check "unreachable ollama says how to start it" end_mentions "$BENCH_RESULTS/ollama--qwen3.6-35b.jsonl" error 'brew services start ollama'

STUB_POWER='Battery Power' run run omlx qwen3.6-35b
check "run omlx exits 0" test "$?" -eq 0
check "omlx serves the models dir headless on its own port" \
  grep -qxF "OMLX_PORT=8100 serve --headless --model-dir $BENCH_MODELS --api-key local-bench" "$logs/omlx.log"
check "omlx benches by directory name with the api key" \
  grep -qxF -- '--base-url http://127.0.0.1:8100 --model qwen3.6-35b --auth-token local-bench --prefix-tokens 20000 60000 --tool-trials 5 --jsonl' "$logs/bench.log"
unit="$BENCH_RESULTS/omlx--qwen3.6-35b.jsonl"
check "omlx records the brew version" test "$(line_of "$unit" meta | jq -r .version)" = 0.6.3
check "a run on battery is recorded" test "$(line_of "$unit" meta | jq -r .conditions.power)" = 'Battery Power'
check "omlx server is stopped afterwards" test -z "$(pgrep -f "$sandbox/stubbin/omlx" || true)"

: >"$logs/curl.log"
run run omlx-mtp qwen3.6-35b
check "run omlx-mtp exits 0" test "$?" -eq 0
check "omlx-mtp turns MTP on before and off after the run" \
  test "$(grep -o 'mtp_enabled": [a-z]*' "$logs/curl.log" | tr '\n' ' ')" = 'mtp_enabled": true mtp_enabled": false '
check "omlx-mtp sets MTP on the MTP weights" grep -qF '/admin/api/models/qwen3.6-35b-mtp/settings' "$logs/curl.log"
check "omlx-mtp reports MTP active from its server log" test "$(line_of "$BENCH_RESULTS/omlx-mtp--qwen3.6-35b.jsonl" end | jq -r .mtp.active)" = true
run run omlx-mtp qwen3.8-27b
check "omlx-mtp reports MTP inactive per model" test "$(line_of "$BENCH_RESULTS/omlx-mtp--qwen3.8-27b.jsonl" end | jq -r .mtp.active)" = false

STUB_OMLX_MTP_REFUSE=1 run run omlx-mtp qwen3.6-35b
check "omlx-mtp exits 1 when oMLX refuses MTP" test "$?" -eq 1
check "omlx-mtp says why oMLX refused" end_mentions "$BENCH_RESULTS/omlx-mtp--qwen3.6-35b.jsonl" error 'no mtp tensors'

STUB_MODEL_IDS='{"id": "other-model"}' run run omlx qwen3.6-35b
check "omlx without the model id exits 1" test "$?" -eq 1
check "omlx lists the ids it found" end_mentions "$unit" error other-model

VLLM_MLX_EXTRA_ARGS='--enable-mtp --x 1' run run vllm-mlx qwen3.8-27b
check "run vllm-mlx exits 0" test "$?" -eq 0
check "vllm-mlx serves one model with the qwen parsers and extra args" \
  grep -qxF "serve $BENCH_MODELS/qwen3.8-27b --host 127.0.0.1 --port 8200 --served-model-name qwen3.8-27b --continuous-batching --use-paged-cache --enable-auto-tool-choice --tool-call-parser qwen --reasoning-parser qwen3 --enable-mtp --x 1" "$logs/vllm.log"
check "vllm-mlx records the uv tool version" \
  test "$(line_of "$BENCH_RESULTS/vllm-mlx--qwen3.8-27b.jsonl" meta | jq -r .version)" = v0.4.1

run run vllm-mlx-mtp qwen3.6-35b
check "run vllm-mlx-mtp exits 0" test "$?" -eq 0
check "vllm-mlx-mtp extracts the MTP head before serving" grep -qxF "$BENCH_MODELS/qwen3.6-35b-mtp" "$logs/extract.log"
check "vllm-mlx-mtp serves the MTP weights with --enable-mtp" \
  grep -qxF "serve $BENCH_MODELS/qwen3.6-35b-mtp --host 127.0.0.1 --port 8200 --served-model-name qwen3.6-35b-mtp --continuous-batching --use-paged-cache --enable-auto-tool-choice --tool-call-parser qwen --reasoning-parser qwen3 --enable-mtp" "$logs/vllm.log"
unit="$BENCH_RESULTS/vllm-mlx-mtp--qwen3.6-35b.jsonl"
check "vllm-mlx-mtp reads acceptance from /v1/status" \
  test "$(line_of "$unit" end | jq -r .mtp.detail)" = "accepted 80 of attempted 100 drafts, acceptance 80%"
check "vllm-mlx-mtp reports MTP active when drafts were accepted" test "$(line_of "$unit" end | jq -r .mtp.active)" = true

"$script" --help >"$sandbox/help"
check "help lists the MTP subcommands" test "$(grep -cE '^  (ollama-mtp|omlx-mtp|vllm-mlx-mtp) ' "$sandbox/help")" -eq 3

: >"$logs/bench.log"
echo stale >"$BENCH_RESULTS/old-server--old-model.jsonl"
run all
check "all exits 0 when every run passes" test "$?" -eq 0
check "all writes a finished plan" test "$(jq -r '[.servers, .models | join(",")] | join(" ")' "$BENCH_RESULTS/plan.json") $(jq -r .finished "$BENCH_RESULTS/plan.json")" = "ollama,ollama-mtp,omlx,omlx-mtp,vllm-mlx,vllm-mlx-mtp qwen3.6-35b,qwen3.8-27b true"
check "all benches model by model" \
  test "$(grep -- '--jsonl' "$logs/bench.log" | sed -n 's/.*--model \([^ ]*\).*/\1/p' | tr '\n' ' ')" = "bench-qwen3.6-35b bench-qwen3.6-35b-mtp qwen3.6-35b qwen3.6-35b-mtp qwen3.6-35b qwen3.6-35b-mtp bench-qwen3.8-27b bench-qwen3.8-27b-mtp qwen3.8-27b qwen3.8-27b-mtp qwen3.8-27b qwen3.8-27b-mtp "
check "all starts from a clean results dir" test ! -e "$BENCH_RESULTS/old-server--old-model.jsonl"
check "all streams progress into the page while it runs" grep -lqF 'Running: 1 of 12 runs done' "$logs"/page.*.html
check "the final page has every server side by side" \
  grep -qF '<th>ollama</th><th>ollama-mtp</th><th>omlx</th><th>omlx-mtp</th><th>vllm-mlx</th><th>vllm-mlx-mtp</th>' "$BENCH_RESULTS/bench-off.html"
check "the final page stops refreshing" test "$(grep -c 'http-equiv="refresh"' "$BENCH_RESULTS/bench-off.html")" -eq 0

rm "$sandbox/stubbin/omlx"
run all
check "all exits 1 when a run fails" test "$?" -eq 1
check "all names the failed runs" grep -qF 'failed: omlx/qwen3.6-35b omlx-mtp/qwen3.6-35b omlx/qwen3.8-27b omlx-mtp/qwen3.8-27b' "$sandbox/err"
check "all still benches the other servers" test "$(line_of "$BENCH_RESULTS/vllm-mlx--qwen3.8-27b.jsonl" end | jq -r .status)" = "done"
check "the failed run is on the page" grep -qF 'failed: omlx not found' "$BENCH_RESULTS/bench-off.html"

run nonsense
check "unknown command exits 2" test "$?" -eq 2
run run nonsense qwen3.6-35b
check "unknown server exits 2" test "$?" -eq 2

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
