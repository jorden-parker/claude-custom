#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
sandbox="$(cd "$(mktemp -d)" && pwd -P)"
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

stub_messages_bench() {
  cat >"$sandbox/repo/bin/messages-bench" <<EOF
#!/bin/sh
echo "\$*" >> "$logs/bench.log"
cat <<'JSON'
{"base_url": "x", "model": "m", "runs": [{"prefix_tokens": 20000, "scenario": "cold", "input_tokens": 20000, "cache_read_tokens": null, "ttft_seconds": 2.0, "output_tokens": 256, "decode_seconds": 5.0, "prefill_tokens_per_second": 10000.0, "decode_tokens_per_second": 51.2}, {"prefix_tokens": 20000, "scenario": "warm", "input_tokens": 20000, "cache_read_tokens": null, "ttft_seconds": 1.0, "output_tokens": 256, "decode_seconds": 5.0, "prefill_tokens_per_second": 20000.0, "decode_tokens_per_second": 51.2}], "tool_calls": {"parsed": 5, "trials": 5}}
JSON
EOF
  chmod +x "$sandbox/repo/bin/messages-bench"
}

stub_messages_bench
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
  create) cat "\$4" >> "$logs/ollama.log" ;;
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
$serve_until_stopped
EOF
stub vllm-mlx <<EOF
echo "\$*" >> "$logs/vllm.log"
$serve_until_stopped
EOF
stub curl <<EOF
echo "\$*" >> "$logs/curl.log"
[ -n "\${STUB_CURL_FAIL:-}" ] && exit 7
ids='{"id": "tiel-coder-35b"}, {"id": "qwen3.8-27b-oq4e"}'
[ -n "\${STUB_MODEL_IDS:-}" ] && ids="\$STUB_MODEL_IDS"
case "\$*" in
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
unset OLLAMA_HOST VLLM_MLX_EXTRA_ARGS

run() {
  "$script" "$@" >"$sandbox/out" 2>"$sandbox/err"
}

run ollama
check "ollama before download exits 1" test "$?" -eq 1
check "ollama before download says to download" grep -qF 'backend-bench-off download' "$sandbox/err"

run download
check "download exits 0" test "$?" -eq 0
check "download fetches the 35B MoE" grep -qxF "download peculiar-ragdoll/Tiel-Coder-35B-A3B-MLX-oQ4e-MTP --local-dir $BENCH_MODELS/tiel-coder-35b" "$logs/hf.log"
check "download fetches the 27B dense" grep -qxF "download Jundot/Qwen3.8-27B-oQ4e-mtp --local-dir $BENCH_MODELS/qwen3.8-27b-oq4e" "$logs/hf.log"
check "download fetches the side model" grep -qxF "download mlx-community/Qwen3-4B-4bit --local-dir $BENCH_MODELS/qwen3-4b-cc" "$logs/hf.log"
run download
check "a second download skips what is there" test "$(wc -l <"$logs/hf.log")" -eq 3

run ollama
check "ollama exits 0" test "$?" -eq 0
check "ollama imports the downloaded weights" grep -qxF "FROM $BENCH_MODELS/tiel-coder-35b" "$logs/ollama.log"
check "ollama import sets a 64k context" grep -qxF 'PARAMETER num_ctx 65536' "$logs/ollama.log"
check "ollama benches each model twice" \
  test "$(grep -cF -- '--base-url http://localhost:11434 --model bench-tiel-coder-35b --auth-token ollama --json' "$logs/bench.log")" -eq 2
check "ollama unloads the model after its run" grep -qxF 'stop bench-qwen3.8-27b-oq4e' "$logs/ollama.log"
result="$BENCH_RESULTS/ollama--tiel-coder-35b.json"
check "ollama writes a result per model" test -s "$BENCH_RESULTS/ollama--qwen3.8-27b-oq4e.json"
check "result names server, version and repo" \
  test "$(jq -r '[.server, .version, .model, .repo] | join(" ")' "$result")" = "ollama 0.19.0 tiel-coder-35b peculiar-ragdoll/Tiel-Coder-35B-A3B-MLX-oQ4e-MTP"
check "result records peak memory from vm_stat" test "$(jq -r .peak_memory_gb "$result")" = 26.2
check "a plain result records mtp as null" test "$(jq -r 'has("mtp") and .mtp == null' "$result")" = true
check "result keeps the bench output" test "$(jq '.bench.tool_calls.parsed' "$result")" -eq 5

STUB_CURL_FAIL=1 run ollama
check "unreachable ollama exits 1" test "$?" -eq 1
check "unreachable ollama says how to start it" grep -qF 'brew services start ollama' "$sandbox/err"

: >"$logs/bench.log"
run omlx
check "omlx exits 0" test "$?" -eq 0
check "omlx serves the models dir headless on its own port" \
  grep -qxF "OMLX_PORT=8100 serve --headless --model-dir $BENCH_MODELS --api-key local-bench" "$logs/omlx.log"
check "omlx benches by directory name with the api key" \
  test "$(grep -cF -- '--base-url http://127.0.0.1:8100 --model qwen3.8-27b-oq4e --auth-token local-bench --json' "$logs/bench.log")" -eq 2
check "omlx records the brew version" test "$(jq -r .version "$BENCH_RESULTS/omlx--tiel-coder-35b.json")" = 0.6.3
check "omlx server is stopped afterwards" test -z "$(pgrep -f "$sandbox/stubbin/omlx" || true)"

STUB_MODEL_IDS='{"id": "other-model"}' run omlx
check "omlx without the model id exits 1" test "$?" -eq 1
check "omlx lists the ids it found" grep -qF 'other-model' "$sandbox/err"

: >"$logs/bench.log"
run vllm-mlx
check "vllm-mlx exits 0" test "$?" -eq 0
check "vllm-mlx serves one model with the qwen parsers" \
  grep -qxF "serve $BENCH_MODELS/tiel-coder-35b --host 127.0.0.1 --port 8200 --served-model-name tiel-coder-35b --continuous-batching --use-paged-cache --enable-auto-tool-choice --tool-call-parser qwen --reasoning-parser qwen3" "$logs/vllm.log"
check "vllm-mlx benches each model on its port" \
  test "$(grep -cF -- '--base-url http://127.0.0.1:8200 --model tiel-coder-35b' "$logs/bench.log")" -eq 2
check "vllm-mlx records the uv tool version" test "$(jq -r .version "$BENCH_RESULTS/vllm-mlx--qwen3.8-27b-oq4e.json")" = v0.4.1
VLLM_MLX_EXTRA_ARGS='--enable-mtp --x 1' run vllm-mlx
check "vllm-mlx appends extra args" grep -qF -- '--reasoning-parser qwen3 --enable-mtp --x 1' "$logs/vllm.log"

run report
check "report exits 0" test "$?" -eq 0
check "report writes one HTML file" test -s "$BENCH_RESULTS/bench-off.html"
check "report puts every server side by side" grep -qF '<th>ollama</th><th>omlx</th><th>vllm-mlx</th>' "$BENCH_RESULTS/bench-off.html"

rm "$sandbox/stubbin/omlx" "$BENCH_RESULTS"/*.json "$BENCH_RESULTS/bench-off.html"
run all
check "all exits 1 when a server fails" test "$?" -eq 1
check "all names the failed server" grep -qF 'failed: omlx' "$sandbox/err"
check "all still benches the other servers" test -s "$BENCH_RESULTS/vllm-mlx--tiel-coder-35b.json"
check "all still writes the report" test -s "$BENCH_RESULTS/bench-off.html"

run nonsense
check "unknown command exits 2" test "$?" -eq 2

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
