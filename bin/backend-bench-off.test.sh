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

mkdir -p "$sandbox/repo/bin" "$sandbox/stubbin" "$sandbox/logs" "$sandbox/tmp"
cp "$repo/bin/backend-bench-off" "$repo/bin/backend-bench-report" "$sandbox/repo/bin/"
script="$sandbox/repo/bin/backend-bench-off"
logs="$sandbox/logs"
export TMPDIR="$sandbox/tmp"

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
model=\$(echo "\$*" | sed -n 's/.*--model \([^ ]*\).*/\1/p')
cold=10000.0
warm=1.0
[ "\$model" = "\${STUB_SLOW_MODEL:-none}" ] && cold=5000.0
[ "\$model" = "\${STUB_FAST_MODEL:-none}" ] && warm=0.5
case "\$*" in
  *--jsonl*)
    echo "{\"type\": \"run\", \"prefix_tokens\": 20000, \"scenario\": \"cold\", \"input_tokens\": 20000, \"cache_read_tokens\": null, \"ttft_seconds\": 2.0, \"output_tokens\": 256, \"decode_seconds\": 5.0, \"prefill_tokens_per_second\": \$cold, \"decode_tokens_per_second\": 51.2}"
    echo "{\"type\": \"run\", \"prefix_tokens\": 20000, \"scenario\": \"warm\", \"input_tokens\": 20000, \"cache_read_tokens\": null, \"ttft_seconds\": \$warm, \"output_tokens\": 256, \"decode_seconds\": 5.0, \"prefill_tokens_per_second\": 20000.0, \"decode_tokens_per_second\": 51.2}"
    echo '{"type": "tool_calls", "parsed": 5, "trials": 5}'
    ;;
  *)
    if [ -n "\${STUB_TOOL_FAIL:-}" ]; then echo '{"tool_calls": {"parsed": 0, "trials": 1}}'; else echo '{"tool_calls": {"parsed": 1, "trials": 1}}'; fi
    ;;
esac
EOF
chmod +x "$sandbox/repo/bin/messages-bench"

cat >"$sandbox/repo/bin/prefix-ab" <<EOF
#!/bin/sh
echo "\$*" >> "$logs/prefix-ab.log"
[ -n "\${STUB_PREFIX_AB_FAIL:-}" ] && exit 1
echo '{"requests": [{}, {}, {}], "basis": "cached token count", "mean": {"verbatim": 87.5, "stabilized": 88.0}}'
EOF
chmod +x "$sandbox/repo/bin/prefix-ab"

cat >"$sandbox/repo/bin/extract-mtp-weights" <<EOF
#!/bin/sh
echo "\$*" >> "$logs/extract.log"
EOF
chmod +x "$sandbox/repo/bin/extract-mtp-weights"

stub hf <<EOF
echo "\$*" >> "$logs/hf.log"
dir=""
files=""
previous=""
for word in "\$@"; do
  [ "\$previous" = --local-dir ] && dir="\$word"
  case "\$word" in *.gguf) files="\$files \$word" ;; esac
  previous="\$word"
done
[ -n "\$dir" ] || exit 0
mkdir -p "\$dir/.cache/huggingface/download"
echo '{}' > "\$dir/config.json"
printf 'abc123\nmore\n' > "\$dir/.cache/huggingface/download/config.json.metadata"
for file in \$files; do
  mkdir -p "\$(dirname "\$dir/\$file")"
  : > "\$dir/\$file"
done
EOF
stub ollama <<EOF
echo "\$*" >> "$logs/ollama.log"
case "\$1" in
  --version) echo "ollama version is \${STUB_OLLAMA_VERSION:-0.19.0}" ;;
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
echo "\$*" >> "$logs/omlx.log"
echo "Speculative backend selected for $sandbox/models/qwen3.6-35b-mtp: Lightning MTP (model_type=qwen3_5_moe, active)"
echo "Lightning MTP is inactive for $sandbox/models/qwen3.8-27b-mtp"
$serve_until_stopped
EOF
stub vllm-mlx <<EOF
echo "\$*" >> "$logs/vllm.log"
$serve_until_stopped
EOF
stub llama-server <<EOF
[ "\$1" = --version ] && { echo 'version: 9216 (1ff0fc138)' >&2; exit 0; }
echo "\$0 \$*" >> "$logs/llama.log"
case "\$*" in
  *--spec-type*) echo 'draft acceptance rate = 0.75000 (   30 accepted /    40 generated)' ;;
esac
$serve_until_stopped
EOF
stub mtplx <<EOF
[ "\$1" = --version ] && { echo 'mtplx 2.12.2'; exit 0; }
echo "\$*" >> "$logs/mtplx.log"
$serve_until_stopped
EOF
stub rapid-mlx <<EOF
echo "\$*" >> "$logs/rapid.log"
$serve_until_stopped
EOF
stub optiq <<EOF
echo "\$*" >> "$logs/optiq.log"
$serve_until_stopped
EOF
stub curl <<EOF
echo "\$*" >> "$logs/curl.log"
[ -n "\${STUB_CURL_FAIL:-}" ] && exit 7
ids=''
for name in qwen3.6-35b qwen3.6-35b-mtp qwen3.8-27b qwen3.8-27b-mtp qwen3.6-35b-gguf qwen3.6-35b-gguf-mtp qwen3.8-27b-gguf qwen3.6-35b-mtplx qwen3.8-27b-mtplx qwen3.6-35b-rapid qwen3.8-27b-rapid; do
  ids="\$ids\${ids:+, }{\"id\": \"\$name\"}"
done
[ -n "\${STUB_MODEL_IDS:-}" ] && ids="\$STUB_MODEL_IDS"
previous=""
for word in "\$@"; do
  [ "\$previous" = -o ] && { : > "\$word"; exit 0; }
  previous="\$word"
done
case "\$*" in
  *huggingface.co/api/models/*GGUF*)
    echo '[{"type": "file", "path": "config.json", "size": 3}, {"type": "file", "path": "Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf", "size": 0}, {"type": "file", "path": "Qwen3.8-27B-UD-Q4_K_XL.gguf", "size": 0}, {"type": "directory", "path": "MTP"}, {"type": "file", "path": "MTP/mtp-Qwen3.8-27B-Q4_0.gguf", "size": 0}]' ;;
  *huggingface.co/api/models/*) echo "[{\"type\": \"file\", \"path\": \"config.json\", \"size\": \${STUB_HF_SIZE:-3}}]" ;;
  *"-X PUT"*)
    if [ -n "\${STUB_OMLX_REFUSE:-}" ]; then printf '%s\n%s' '{"detail": "no mtp tensors"}' 400; else printf '%s\n%s' '{}' 200; fi ;;
  */v1/status*) echo '{"mtp": {"enabled": true, "attempted": 100, "accepted": 80, "rejected": 20, "acceptance_rate": 0.8}}' ;;
  */health*) echo '{"generation_mode": "mtp", "mtp_enabled": true, "depth": 3}' ;;
  *:8000/*) exit 7 ;;
  */v1/messages*)
    answer=\$(printf '%s' "\$*" | sed -n 's/.*"model":"\([^"]*\)".*/\1/p')
    [ -n "\${STUB_ANSWER_MODEL:-}" ] && answer="\$STUB_ANSWER_MODEL"
    echo "{\"model\": \"\$answer\", \"content\": [{\"type\": \"text\", \"text\": \"ok\"}]}" ;;
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
stub pmset <<EOF
case "\$*" in
  "-g batt") echo "Now drawing from '\${STUB_POWER:-AC Power}'" ;;
  "-g therm")
    echo x >> "$logs/therm.log"
    calls=\$(wc -l < "$logs/therm.log" | tr -d ' ')
    if [ "\$calls" -le "\${STUB_THROTTLE_CALLS:-0}" ]; then echo 'CPU_Speed_Limit = 80'; else echo 'CPU_Speed_Limit = 100'; fi
    ;;
  "-g") echo ' lowpowermode         0' ;;
esac
EOF
stub df <<'EOF'
echo 'Filesystem 1024-blocks Used Available Capacity Mounted'
echo "/dev/disk1 999999999 0 ${STUB_DF_KB:-999999999} 1% /"
EOF
stub brew <<EOF
echo "\$*" >> "$logs/brew.log"
[ "\$1" = list ] && echo "omlx \${STUB_OMLX_VERSION:-0.7.3}"
exit 0
EOF
stub uv <<EOF
echo "\$*" >> "$logs/uv.log"
case "\$*" in
  "tool list") printf 'vllm-mlx v0.6.0\nmtplx v2.12.2\nrapid-mlx v1.0.1\nmlx-optiq v0.8.0\n' ;;
  *"pip show"*) printf 'Name: vllm-metal\nVersion: 0.33.0\n' ;;
esac
exit 0
EOF
stub git <<EOF
echo "\$*" >> "$logs/git.log"
EOF
stub cmake <<EOF
echo "\$*" >> "$logs/cmake.log"
EOF
stub tar <<EOF
echo "\$*" >> "$logs/tar.log"
EOF

export PATH="$sandbox/stubbin:$PATH"
export BENCH_MODELS="$sandbox/models"
export BENCH_RESULTS="$sandbox/results"
export BENCH_TOOLS="$sandbox/tools"
export BENCH_REPLAY_DIR="$sandbox/no-record"
export BENCH_POLL_SECONDS=0.1
export BENCH_THERMAL_POLL=0
export HF_HUB_CACHE="$sandbox/hf-hub"
unset OLLAMA_HOST VLLM_MLX_EXTRA_ARGS LLAMA_SERVER_EXTRA_ARGS BENCH_GATE_SECONDS BENCH_THERMAL_MAX

run() {
  "$script" "$@" >"$sandbox/out" 2>"$sandbox/err"
}

line_of() {
  jq -c --arg type "$2" 'select(.type == $type)' "$1"
}

end_mentions() {
  line_of "$1" end | jq -e --arg field "$2" --arg text "$3" '.[$field] | contains($text)' >/dev/null
}

unit_of() {
  echo "$BENCH_RESULTS/$1--$2--${3:-deep}.jsonl"
}

end_status() {
  line_of "$(unit_of "$@")" end | jq -r .status
}

has_line() {
  grep -qxF -- "$2" "$1"
}

mkdir -p "$BENCH_TOOLS/vllm-metal-0.33.0/bin" "$BENCH_TOOLS/llama.cpp-v0.8.0/build/bin" "$BENCH_TOOLS/mistralrs-v0.9.5/mistralrs-metal-aarch64-apple-darwin"
cp "$sandbox/stubbin/vllm-mlx" "$BENCH_TOOLS/vllm-metal-0.33.0/bin/vllm"
cp "$sandbox/stubbin/llama-server" "$BENCH_TOOLS/llama.cpp-v0.8.0/build/bin/llama-server"
cat >"$BENCH_TOOLS/mistralrs-v0.9.5/mistralrs-metal-aarch64-apple-darwin/mistralrs" <<EOF
#!/bin/sh
[ "\$1" = --version ] && { echo 'mistralrs 0.9.5'; exit 0; }
echo "\$*" >> "$logs/mistralrs.log"
$serve_until_stopped
EOF
chmod +x "$BENCH_TOOLS/mistralrs-v0.9.5/mistralrs-metal-aarch64-apple-darwin/mistralrs"

run install
check "install exits 0" test "$?" -eq 0
check "install taps and installs the pinned oMLX formula" has_line "$logs/brew.log" 'install jundot/omlx/omlx'
check "install pins vllm-mlx 0.6.0" grep -qF 'tool install --force vllm-mlx==0.6.0' "$logs/uv.log"
check "install pins MTPLX 2.12.2" grep -qF 'tool install --force mtplx==2.12.2' "$logs/uv.log"
check "install pins Rapid-MLX 1.0.1" grep -qF 'tool install --force rapid-mlx==1.0.1' "$logs/uv.log"
check "install pins mlx-optiq 0.8.0 on Python 3.12" grep -qF 'tool install --force --python 3.12 mlx-optiq==0.8.0' "$logs/uv.log"
check "install leaves an installed vllm-metal venv alone" test "$(grep -c 'venv' "$logs/uv.log")" -eq 0
check "install leaves a built llama.cpp alone" test ! -s "$logs/git.log"
check "install leaves an installed mistral.rs alone" test ! -s "$logs/tar.log"
check "install says how to get LM Studio without installing it" grep -qF 'lmstudio.ai' "$sandbox/err"
rm -rf "$BENCH_TOOLS/vllm-metal-0.33.0" "$BENCH_TOOLS/llama.cpp-v0.8.0" "$BENCH_TOOLS/mistralrs-v0.9.5"
: >"$logs/uv.log"
run install
check "install builds the vllm-metal venv on Python 3.12" grep -qF "venv --python 3.12 $BENCH_TOOLS/vllm-metal-0.33.0" "$logs/uv.log"
check "install puts both pinned vllm-metal wheels in it" \
  grep -qF "pip install --python $BENCH_TOOLS/vllm-metal-0.33.0/bin/python https://github.com/vllm-project/vllm/releases/download/v0.33.0rc3/vllm-0.33.0%2Bcpu-cp38-abi3-macosx_11_0_arm64.whl https://github.com/vllm-project/vllm-metal/releases/download/v0.33.0/vllm_metal-0.33.0-cp312-cp312-macosx_15_0_arm64.whl" "$logs/uv.log"
check "install clones llama.cpp at the pinned tag" \
  has_line "$logs/git.log" "clone --depth 1 --branch v0.8.0 https://github.com/ggml-org/llama.cpp $BENCH_TOOLS/llama.cpp-v0.8.0"
check "install builds llama.cpp with Metal in Release" \
  has_line "$logs/cmake.log" "-S $BENCH_TOOLS/llama.cpp-v0.8.0 -B $BENCH_TOOLS/llama.cpp-v0.8.0/build -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DLLAMA_BUILD_TESTS=OFF"
check "install downloads the mistral.rs v0.9.5 release binary, no script" \
  grep -qF "https://github.com/EricLBuehler/mistral.rs/releases/download/v0.9.5/mistralrs-metal-aarch64-apple-darwin.tar.gz" "$logs/curl.log"
check "install never pipes a script into a shell" test "$(grep -c 'install.sh' "$logs/curl.log")" -eq 0
STUB_OMLX_VERSION=0.6.3 run install
check "install exits 1 when a pinned version did not land" test "$?" -eq 1
check "install names the version it found" grep -qF 'omlx 0.6.3 installed, the bench pins 0.7.3' "$sandbox/err"
mkdir -p "$BENCH_TOOLS/vllm-metal-0.33.0/bin" "$BENCH_TOOLS/llama.cpp-v0.8.0/build/bin" "$BENCH_TOOLS/mistralrs-v0.9.5/mistralrs-metal-aarch64-apple-darwin"
cp "$sandbox/stubbin/vllm-mlx" "$BENCH_TOOLS/vllm-metal-0.33.0/bin/vllm"
cp "$sandbox/stubbin/llama-server" "$BENCH_TOOLS/llama.cpp-v0.8.0/build/bin/llama-server"
cat >"$BENCH_TOOLS/mistralrs-v0.9.5/mistralrs-metal-aarch64-apple-darwin/mistralrs" <<EOF
#!/bin/sh
[ "\$1" = --version ] && { echo 'mistralrs 0.9.5'; exit 0; }
echo "\$*" >> "$logs/mistralrs.log"
$serve_until_stopped
EOF
chmod +x "$BENCH_TOOLS/mistralrs-v0.9.5/mistralrs-metal-aarch64-apple-darwin/mistralrs"

stub lms <<EOF
echo "\$*" >> "$logs/lms.log"
case "\$1 \${2:-}" in
  "version ") echo 'lms version 0.4.2' ;;
  "server start") touch "$logs/serving" ;;
  "server stop") rm -f "$logs/serving" ;;
  "ps ") echo 'qwen3.6-35b  flash attention on  kv f16' ;;
esac
exit 0
EOF
run all
check "all before download exits 1" test "$?" -eq 1
check "all before download says to download" grep -qF 'backend-bench-off download' "$sandbox/err"

STUB_DF_KB=0 run download
check "download without room exits 1" test "$?" -eq 1
check "download without room says how much it needs" grep -qF 'download needs' "$sandbox/err"
check "download without room fetches nothing" test ! -s "$logs/hf.log"

run download
check "download exits 0" test "$?" -eq 0
check "download fetches the pinned stock 35B-A3B" has_line "$logs/hf.log" "download mlx-community/Qwen3.6-35B-A3B-4bit --revision 38740b847e4cb78f352aba30aa41c76e08e6eb46 --local-dir $BENCH_MODELS/qwen3.6-35b"
check "download fetches the 27B dense" has_line "$logs/hf.log" "download mlx-community/Qwen3.8-27B-4bit --local-dir $BENCH_MODELS/qwen3.8-27b"
check "download fetches the side model" has_line "$logs/hf.log" "download mlx-community/Qwen3-4B-4bit --local-dir $BENCH_MODELS/qwen3-4b-cc"
check "download fetches the 35B MTP weights" has_line "$logs/hf.log" "download Jundot/Qwen3.6-35B-A3B-oQ4e-mtp --local-dir $BENCH_MODELS/qwen3.6-35b-mtp"
check "download fetches the 27B MTP weights" has_line "$logs/hf.log" "download Jundot/Qwen3.8-27B-oQ4e-mtp --local-dir $BENCH_MODELS/qwen3.8-27b-mtp"
check "download fetches the pinned 27B GGUF with its MTP head" \
  has_line "$logs/hf.log" "download unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-UD-Q4_K_XL.gguf MTP/mtp-Qwen3.8-27B-Q4_0.gguf --revision 4ca720788d1e01f1bff70c033e0d0028fd02e502 --local-dir $BENCH_MODELS/qwen3.8-27b-gguf"
check "download fetches the pinned 35B-A3B GGUF" \
  has_line "$logs/hf.log" "download unsloth/Qwen3.6-35B-A3B-GGUF Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf --revision a483e9e6cbd595906af30beda3187c2663a1118c --local-dir $BENCH_MODELS/qwen3.6-35b-gguf"
check "download fetches the pinned 35B-A3B MTP GGUF" \
  has_line "$logs/hf.log" "download unsloth/Qwen3.6-35B-A3B-MTP-GGUF Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf --revision 5bc3e238d916f48a861bac2f8a1990a0e9b7e98d --local-dir $BENCH_MODELS/qwen3.6-35b-gguf-mtp"
check "download fetches the pinned MTPLX 35B pack" \
  has_line "$logs/hf.log" "download Youssofal/Qwen3.6-35B-A3B-MTPLX-Optimized-Speed --revision 95460516fbfe34c48f577f67c9ed191f5d61fbaf --local-dir $BENCH_MODELS/qwen3.6-35b-mtplx"
check "download fetches the pinned MTPLX 27B pack" \
  has_line "$logs/hf.log" "download Youssofal/Qwen3.8-27B-MTPLX-Optimized-Speed --revision 1d5087d2062c02b279180a53e4016cf9cd7a3d7e --local-dir $BENCH_MODELS/qwen3.8-27b-mtplx"
check "download fetches the pinned OptiQ 35B" \
  has_line "$logs/hf.log" "download mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit --revision 53b24f3debecbff48534245bc2b26d821147ad66 --local-dir $BENCH_MODELS/qwen3.6-35b-optiq"
check "download fetches the pinned OptiQ 27B" \
  has_line "$logs/hf.log" "download mlx-community/Qwen3.8-27B-OptiQ-4bit --revision a95c2908fa8ca27cbf29ed86da9a658d14093b63 --local-dir $BENCH_MODELS/qwen3.8-27b-optiq"
check "download fills the Hugging Face cache with the Rapid-MLX 35B alias and its drafter" \
  test "$(grep -cxE 'download mlx-community/Qwen3.6-35B-A3B-(4bit --revision 38740b847e4cb78f352aba30aa41c76e08e6eb46|MTP-4bit)' "$logs/hf.log")" -eq 2
check "download fills the Hugging Face cache with the Rapid-MLX 27B alias" \
  has_line "$logs/hf.log" "download rapid-mlx/Qwen3.8-27B-4bit-MTP-MLX --revision aa985c29ff5b334cbfdcbbc787d47e66e9d9e456"
check "download sizes each repo at its pinned revision" grep -qF 'huggingface.co/api/models/Youssofal/Qwen3.6-35B-A3B-MTPLX-Optimized-Speed/tree/95460516fbfe34c48f577f67c9ed191f5d61fbaf?recursive=true' "$logs/curl.log"
downloads="$(wc -l <"$logs/hf.log")"
run download
check "a second download skips what is there" test "$(wc -l <"$logs/hf.log")" -eq "$downloads"
rm -rf "$BENCH_MODELS/qwen3.8-27b-optiq"
STUB_HF_SIZE=7 run download
check "a download whose file sizes differ exits 1" test "$?" -eq 1
check "a download whose file sizes differ names the file" grep -qF 'qwen3.8-27b-optiq: config.json is 3 bytes, expected 7' "$sandbox/err"
rm -rf "$BENCH_MODELS/qwen3.8-27b-optiq"
run download

run run ollama qwen3.6-35b
check "run ollama exits 0" test "$?" -eq 0
unit="$(unit_of ollama qwen3.6-35b)"
check "ollama unloads models left loaded before it starts" has_line "$logs/ollama.log" 'stop other-model:latest'
check "ollama imports the downloaded weights" has_line "$logs/ollama.log" "FROM $BENCH_MODELS/qwen3.6-35b"
check "ollama import sets a 64k context" has_line "$logs/ollama.log" 'PARAMETER num_ctx 65536'
check "ollama import sets the server-side sampling defaults" \
  test "$(grep -cxE 'PARAMETER (min_p 0|presence_penalty 1.5|repeat_penalty 1.0)' "$logs/ollama.log")" -eq 3
check "the gate sends one short request with one tool call" \
  has_line "$logs/bench.log" '--base-url http://localhost:11434 --model bench-qwen3.6-35b --auth-token ollama --prefix-tokens 1000 --tool-trials 1 --json'
check "the gate checks which model answered" grep -qF '"model":"bench-qwen3.6-35b"' "$logs/curl.log"
check "the deep run streams jsonl at both prefixes" \
  has_line "$logs/bench.log" '--base-url http://localhost:11434 --model bench-qwen3.6-35b --auth-token ollama --prefix-tokens 20000 60000 --tool-trials 5 --jsonl'
check "ollama unloads its model afterwards" has_line "$logs/ollama.log" 'stop bench-qwen3.6-35b'
check "the unit starts with server, version, repo and stage" \
  test "$(line_of "$unit" meta | jq -r '[.server, .version, .model, .repo, .stage] | join(" ")')" = "ollama 0.19.0 qwen3.6-35b mlx-community/Qwen3.6-35B-A3B-4bit deep"
check "the unit records the weights revision, size and bench version" \
  test "$(line_of "$unit" meta | jq -r '[.weights_revision, (.weights_bytes | type), (.bench_version | type)] | join(" ")')" = "38740b847e4cb78f352aba30aa41c76e08e6eb46 number string"
check "the unit records power and memory before" \
  test "$(line_of "$unit" meta | jq -r '[.conditions.power, .conditions.low_power_mode, .conditions.memory_before_gb] | join(" ")')" = "AC Power false 26.2"
check "the unit records a passed gate" test "$(line_of "$unit" gate | jq -r '[.status, .reason, (.seconds | type)] | join(" ")')" = "passed  number"
check "the unit keeps every streamed measurement" test "$(line_of "$unit" run | wc -l)" -eq 2
check "the unit ends done with peak memory" test "$(line_of "$unit" end | jq -r '[.status, .peak_memory_gb] | join(" ")')" = "done 26.2"
check "a single run renders the page" test -s "$BENCH_RESULTS/bench-off.html"
check "an MTP-off run records mtp as null" test "$(line_of "$unit" end | jq -r 'has("mtp") and .mtp == null')" = true

run run ollama qwen3.8-27b
check "an unpinned download records the revision it got" \
  test "$(line_of "$(unit_of ollama qwen3.8-27b)" meta | jq -r .weights_revision)" = abc123

run run ollama-mtp qwen3.6-35b
check "run ollama-mtp exits 0" test "$?" -eq 0
unit="$(unit_of ollama-mtp qwen3.6-35b)"
check "ollama-mtp imports the MTP weights" has_line "$logs/ollama.log" "FROM $BENCH_MODELS/qwen3.6-35b-mtp"
check "ollama-mtp imports with draft_num_predict 4" has_line "$logs/ollama.log" 'PARAMETER draft_num_predict 4'
check "ollama-mtp records which weights it ran" test "$(line_of "$unit" meta | jq -r '[.weights, .repo] | join(" ")')" = "qwen3.6-35b-mtp Jundot/Qwen3.6-35B-A3B-oQ4e-mtp"
check "ollama-mtp reports MTP as unverified" test "$(line_of "$unit" end | jq -r .mtp.active)" = null

STUB_CREATE_FAIL=1 run run ollama qwen3.8-27b
check "a failed import exits 1" test "$?" -eq 1
failed="$(unit_of ollama qwen3.8-27b)"
check "a failed import ends failed with the step" test "$(line_of "$failed" end | jq -r '[.status, .error] | join(": ")')" = "failed: importing qwen3.8-27b into Ollama"
check "a failed import keeps the server's message" end_mentions "$failed" log_tail 'unsupported architecture'

STUB_CURL_FAIL=1 run run ollama qwen3.6-35b
check "unreachable ollama is a failed gate" test "$?" -eq 3
check "unreachable ollama ends gate-failed" test "$(end_status ollama qwen3.6-35b)" = gate-failed
check "unreachable ollama says how to start it" end_mentions "$(unit_of ollama qwen3.6-35b)" reason 'brew services start ollama'

STUB_TOOL_FAIL=1 run run llama-server qwen3.6-35b
check "a gate without a parsed tool call exits 3" test "$?" -eq 3
unit="$(unit_of llama-server qwen3.6-35b)"
check "a gate without a parsed tool call ends gate-failed" end_mentions "$unit" reason 'tool call'
check "a failed gate is recorded" test "$(line_of "$unit" gate | jq -r .status)" = failed
check "a failed gate measures nothing" test "$(line_of "$unit" run | wc -l)" -eq 0
check "a failed gate stops the server" test -z "$(pgrep -f "$sandbox/stubbin/llama-server" || true)"

STUB_ANSWER_MODEL=claude-sonnet run run llama-server qwen3.6-35b
check "a gate answered by another model exits 3" test "$?" -eq 3
check "a gate answered by another model names it" end_mentions "$unit" reason 'claude-sonnet'

STUB_POWER='Battery Power' run run omlx qwen3.6-35b
check "run omlx exits 0" test "$?" -eq 0
omlx_line="$(head -n 1 "$logs/omlx.log")"
check "omlx serves the models dir headless on its own port with one request at a time" \
  test "${omlx_line%% --base-path *}" = "serve --headless --model-dir $BENCH_MODELS --api-key local-bench --port 8100"
check "omlx keeps its settings and caches in a temp base path" \
  test "${omlx_line#* --base-path "$TMPDIR"/}" != "$omlx_line"
check "omlx limits concurrency and sizes the hot cache" \
  test "${omlx_line##* --base-path * --max}" = "-concurrent-requests 1 --hot-cache-max-size 6GB"
check "omlx removes its temp base path afterwards" test -z "$(find "$TMPDIR" -name 'bench-omlx*' -print -quit)"
check "omlx pins context, thinking, KV and MTP off per model" \
  grep -qF '{"max_context_window":65536,"enable_thinking":false,"turboquant_kv_enabled":false,"mtp_enabled":false}' "$logs/curl.log"
check "omlx runs the oQ4e weights with MTP off" grep -qF '/admin/api/models/qwen3.6-35b-mtp/settings' "$logs/curl.log"
check "omlx benches by directory name with the api key" \
  has_line "$logs/bench.log" '--base-url http://127.0.0.1:8100 --model qwen3.6-35b-mtp --auth-token local-bench --prefix-tokens 20000 60000 --tool-trials 5 --jsonl'
unit="$(unit_of omlx qwen3.6-35b)"
check "omlx records the brew version" test "$(line_of "$unit" meta | jq -r .version)" = 0.7.3
check "a run on battery is recorded" test "$(line_of "$unit" meta | jq -r .conditions.power)" = 'Battery Power'
check "omlx server is stopped afterwards" test -z "$(pgrep -f "$sandbox/stubbin/omlx" || true)"

: >"$logs/curl.log"
run run omlx-mtp qwen3.6-35b
check "run omlx-mtp exits 0" test "$?" -eq 0
check "omlx-mtp turns MTP on with a fixed depth of 3" grep -qF '"mtp_enabled":true,"mtp_fixed_depth":3}' "$logs/curl.log"
check "omlx-mtp reports MTP active from its server log" test "$(line_of "$(unit_of omlx-mtp qwen3.6-35b)" end | jq -r .mtp.active)" = true
run run omlx-mtp qwen3.8-27b
check "omlx-mtp reports MTP inactive per model" test "$(line_of "$(unit_of omlx-mtp qwen3.8-27b)" end | jq -r .mtp.active)" = false

STUB_OMLX_REFUSE=1 run run omlx-mtp qwen3.6-35b
check "omlx-mtp fails the gate when oMLX refuses its settings" test "$?" -eq 3
check "omlx-mtp says why oMLX refused" end_mentions "$(unit_of omlx-mtp qwen3.6-35b)" reason 'no mtp tensors'

STUB_MODEL_IDS='{"id": "other-model"}' run run omlx qwen3.6-35b
check "omlx without the model id fails the gate" test "$?" -eq 3
check "omlx lists the ids it found" end_mentions "$(unit_of omlx qwen3.6-35b)" reason other-model

vllm_flags="--continuous-batching --use-paged-cache --max-num-seqs 1 --cache-memory-mb 8192 --enable-auto-tool-choice --tool-call-parser qwen3_xml --reasoning-parser qwen3 --default-chat-template-kwargs {\"enable_thinking\":false} --max-request-tokens 65536"
VLLM_MLX_EXTRA_ARGS='--x 1' run run vllm-mlx qwen3.8-27b
check "run vllm-mlx exits 0" test "$?" -eq 0
check "vllm-mlx serves the oQ4e weights with the fair flags and extra args" \
  has_line "$logs/vllm.log" "serve $BENCH_MODELS/qwen3.8-27b-mtp --host 127.0.0.1 --port 8200 --served-model-name qwen3.8-27b-mtp $vllm_flags --x 1"
check "vllm-mlx records the uv tool version" test "$(line_of "$(unit_of vllm-mlx qwen3.8-27b)" meta | jq -r .version)" = v0.6.0

run run vllm-mlx-mtp qwen3.6-35b
check "run vllm-mlx-mtp exits 0" test "$?" -eq 0
check "vllm-mlx-mtp extracts the MTP head before serving" has_line "$logs/extract.log" "$BENCH_MODELS/qwen3.6-35b-mtp"
check "vllm-mlx-mtp adds three MTP draft tokens" \
  has_line "$logs/vllm.log" "serve $BENCH_MODELS/qwen3.6-35b-mtp --host 127.0.0.1 --port 8200 --served-model-name qwen3.6-35b-mtp $vllm_flags --enable-mtp --mtp-num-draft-tokens 3"
unit="$(unit_of vllm-mlx-mtp qwen3.6-35b)"
check "vllm-mlx-mtp reads acceptance from /v1/status" test "$(line_of "$unit" end | jq -r .mtp.detail)" = "accepted 80 of attempted 100 drafts, acceptance 80%"
check "vllm-mlx-mtp reports MTP active when drafts were accepted" test "$(line_of "$unit" end | jq -r .mtp.active)" = true

: >"$logs/vllm.log"
run run vllm-metal qwen3.6-35b
check "run vllm-metal exits 0" test "$?" -eq 0
check "vllm-metal serves the stock weights from its pinned venv" \
  has_line "$logs/vllm.log" "serve $BENCH_MODELS/qwen3.6-35b --host 127.0.0.1 --port 8400 --served-model-name qwen3.6-35b --max-model-len 65536 --max-num-seqs 1 --gpu-memory-utilization 0.85 --language-model-only --enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser qwen3 --default-chat-template-kwargs {\"enable_thinking\":false} --override-generation-config {\"min_p\":0,\"presence_penalty\":1.5,\"repetition_penalty\":1.0}"
check "vllm-metal records the wheel version" test "$(line_of "$(unit_of vllm-metal qwen3.6-35b)" meta | jq -r .version)" = 0.33.0

llama_flags="--host 127.0.0.1 --port 8300 -c 65536 -ngl 99 -fa on -b 2048 -ub 2048 -ctk f16 -ctv f16 -np 1 --jinja -rea off --cache-ram 8192 --ctx-checkpoints 128 --checkpoint-min-step 128 --cache-reuse 0 --min-p 0 --presence-penalty 1.5 --repeat-penalty 1.0 --metrics"
gguf35="-m $BENCH_MODELS/qwen3.6-35b-gguf/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf --alias qwen3.6-35b-gguf"
: >"$logs/llama.log"
LLAMA_SERVER_EXTRA_ARGS='--x 2' run run llama-server qwen3.6-35b
check "run llama-server exits 0" test "$?" -eq 0
check "llama-server serves the GGUF with f16 KV, thinking off and extra args" \
  has_line "$logs/llama.log" "$sandbox/stubbin/llama-server $gguf35 $llama_flags --x 2"
check "llama-server benches by its alias" \
  has_line "$logs/bench.log" '--base-url http://127.0.0.1:8300 --model qwen3.6-35b-gguf --auth-token local --prefix-tokens 20000 60000 --tool-trials 5 --jsonl'
unit="$(unit_of llama-server qwen3.6-35b)"
check "llama-server records its build" test "$(line_of "$unit" meta | jq -r .version)" = '9216 (1ff0fc138)'
check "llama-server records the GGUF repo and its pin" \
  test "$(line_of "$unit" meta | jq -r '[.repo, .weights_revision] | join(" ")')" = "unsloth/Qwen3.6-35B-A3B-GGUF a483e9e6cbd595906af30beda3187c2663a1118c"
check "llama-server is stopped afterwards" test -z "$(pgrep -f "$sandbox/stubbin/llama-server" || true)"
check "an MTP-off llama-server run records mtp as null" test "$(line_of "$unit" end | jq -r '.mtp == null')" = true

run run llama-server-q8kv qwen3.6-35b
check "llama-server-q8kv swaps only the KV type" \
  has_line "$logs/llama.log" "$sandbox/stubbin/llama-server $gguf35 ${llama_flags/-ctk f16 -ctv f16/-ctk q8_0 -ctv q8_0}"

run run llama-server-mtp qwen3.6-35b
check "run llama-server-mtp exits 0" test "$?" -eq 0
check "llama-server-mtp serves the MTP GGUF with draft-mtp" \
  has_line "$logs/llama.log" "$sandbox/stubbin/llama-server -m $BENCH_MODELS/qwen3.6-35b-gguf-mtp/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf --alias qwen3.6-35b-gguf-mtp $llama_flags --spec-type draft-mtp --spec-draft-n-max 2"
unit="$(unit_of llama-server-mtp qwen3.6-35b)"
check "llama-server-mtp reads acceptance from its log" test "$(line_of "$unit" end | jq -r .mtp.detail)" = "accepted 30 of 40 drafted tokens, acceptance 75%"
check "llama-server-mtp reports MTP active when drafts were accepted" test "$(line_of "$unit" end | jq -r .mtp.active)" = true

run run llama-server-mtp qwen3.8-27b
check "llama-server-mtp loads the 27B's separate MTP head" \
  has_line "$logs/llama.log" "$sandbox/stubbin/llama-server -m $BENCH_MODELS/qwen3.8-27b-gguf/Qwen3.8-27B-UD-Q4_K_XL.gguf --alias qwen3.8-27b-gguf $llama_flags --spec-type draft-mtp --spec-draft-n-max 2 --spec-draft-model $BENCH_MODELS/qwen3.8-27b-gguf/MTP/mtp-Qwen3.8-27B-Q4_0.gguf"

run run llama-server-ngram qwen3.6-35b
check "llama-server-ngram drafts with ngram-mod" \
  has_line "$logs/llama.log" "$sandbox/stubbin/llama-server $gguf35 $llama_flags --spec-type ngram-mod"
check "llama-server-ngram reads its draft acceptance" test "$(line_of "$(unit_of llama-server-ngram qwen3.6-35b)" end | jq -r .mtp.active)" = true

run run llama-server-src qwen3.6-35b
check "llama-server-src runs the pinned source build with the same flags" \
  has_line "$logs/llama.log" "$BENCH_TOOLS/llama.cpp-v0.8.0/build/bin/llama-server $gguf35 $llama_flags"

run run lmstudio-mlx qwen3.6-35b
check "run lmstudio-mlx exits 0" test "$?" -eq 0
check "lmstudio-mlx starts the daemon and the server on its port" \
  test "$(grep -E '^(daemon up|server start)' "$logs/lms.log" | tr '\n' ' ')" = "daemon up server start --port 8500 "
check "lmstudio-mlx loads the stock weights at 64k on the GPU" \
  has_line "$logs/lms.log" "load $BENCH_MODELS/qwen3.6-35b --context-length 65536 --gpu max --identifier qwen3.6-35b"
check "lmstudio-mlx records what it loaded" \
  test "$(line_of "$(unit_of lmstudio-mlx qwen3.6-35b)" settings | jq -r .detail)" = 'qwen3.6-35b  flash attention on  kv f16'
check "lmstudio-mlx unloads and stops its server afterwards" \
  test "$(grep -E '^(unload|server stop)' "$logs/lms.log" | tr '\n' ' ')" = "unload --all server stop "

mtplx_flags="--host 127.0.0.1 --port 8600 --no-auth --context-window 65536 --reasoning off --scheduler-mode serial --ssd-session-cache off --no-stats-footer --temperature 0.7 --top-p 0.8 --top-k 20"
run run mtplx qwen3.6-35b
check "run mtplx exits 0" test "$?" -eq 0
check "mtplx serves its pinned pack with the session cache off" \
  has_line "$logs/mtplx.log" "serve --model $BENCH_MODELS/qwen3.6-35b-mtplx --model-id qwen3.6-35b-mtplx $mtplx_flags"
check "mtplx reads MTP from /health" test "$(line_of "$(unit_of mtplx qwen3.6-35b)" end | jq -r '[.mtp.active, .mtp.detail] | join(" ")')" = "true MTPLX /health: mtp_enabled true, depth 3"
run run mtplx-nomtp qwen3.6-35b
check "mtplx-nomtp adds --no-mtp" has_line "$logs/mtplx.log" "serve --model $BENCH_MODELS/qwen3.6-35b-mtplx --model-id qwen3.6-35b-mtplx $mtplx_flags --no-mtp"
check "mtplx-nomtp records mtp as null" test "$(line_of "$(unit_of mtplx-nomtp qwen3.6-35b)" end | jq -r '.mtp == null')" = true

rapid_flags="--host 127.0.0.1 --port 8700 --served-model-name qwen3.8-27b-rapid --context-length 65536 --enable-auto-tool-choice --tool-call-parser qwen3_coder_xml --reasoning-parser qwen3 --hybrid-cache-entries 4 --max-num-seqs 1 --disable-disk-caches"
run run rapid-mlx qwen3.8-27b
check "run rapid-mlx exits 0" test "$?" -eq 0
check "rapid-mlx serves its pinned alias" has_line "$logs/rapid.log" "serve qwen3.8-27b-4bit $rapid_flags"
unit="$(unit_of rapid-mlx qwen3.8-27b)"
check "rapid-mlx records the alias's pinned repo" \
  test "$(line_of "$unit" meta | jq -r '[.repo, .weights_revision] | join(" ")')" = "rapid-mlx/Qwen3.8-27B-4bit-MTP-MLX aa985c29ff5b334cbfdcbbc787d47e66e9d9e456"
check "rapid-mlx records the uv tool version" test "$(line_of "$unit" meta | jq -r .version)" = v1.0.1
run run rapid-mlx-nomtp qwen3.8-27b
check "rapid-mlx-nomtp adds --no-spec-decode" has_line "$logs/rapid.log" "serve qwen3.8-27b-4bit $rapid_flags --no-spec-decode"

optiq_flags="--host 127.0.0.1 --port 8800 --max-concurrent 1 --prompt-cache-bytes 8000000000"
run run optiq qwen3.6-35b
check "run optiq exits 0" test "$?" -eq 0
check "optiq serves the pinned OptiQ weights" has_line "$logs/optiq.log" "serve --model $BENCH_MODELS/qwen3.6-35b-optiq $optiq_flags"
check "optiq turns thinking off through the model id" \
  grep -qF -- '--model mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit:no-think --auth-token local --prefix-tokens 20000 60000' "$logs/bench.log"
run run optiq-mtp qwen3.6-35b
check "optiq-mtp adds --mtp" has_line "$logs/optiq.log" "serve --model $BENCH_MODELS/qwen3.6-35b-optiq $optiq_flags --mtp"
run run optiq-ngram qwen3.6-35b
check "optiq-ngram adds a 16-token n-gram draft" has_line "$logs/optiq.log" "serve --model $BENCH_MODELS/qwen3.6-35b-optiq $optiq_flags --ngram-draft 16"

run run mistralrs qwen3.6-35b
check "run mistralrs exits 0" test "$?" -eq 0
check "mistralrs serves the GGUF on loopback with paged attention" \
  has_line "$logs/mistralrs.log" "serve -m $BENCH_MODELS/qwen3.6-35b-gguf -f Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf --host 127.0.0.1 -p 8900 --max-model-len 65536 --max-seqs 1 --paged-attn on"
check "mistralrs records its release" test "$(line_of "$(unit_of mistralrs qwen3.6-35b)" meta | jq -r .version)" = 0.9.5

rm "$BENCH_MODELS/qwen3.6-35b-gguf/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf"
run run llama-server qwen3.6-35b
check "llama-server without its GGUF exits 1" test "$?" -eq 1
check "llama-server without its GGUF says to download" end_mentions "$(unit_of llama-server qwen3.6-35b)" error 'backend-bench-off download'
run run ollama qwen3.6-35b
check "an MLX run does not need the GGUF weights" test "$?" -eq 0
run download

mkdir -p "$sandbox/record"
echo '{}' >"$sandbox/record/a.json"
: >"$logs/prefix-ab.log"
BENCH_REPLAY_DIR="$sandbox/record" run run llama-server qwen3.6-35b
check "a replay run exits 0" test "$?" -eq 0
check "llama-server replays the recorded bodies and clears its slots" \
  has_line "$logs/prefix-ab.log" "--record $sandbox/record --model qwen3.6-35b-gguf --base-url http://127.0.0.1:8300 --auth-token local --unload llama-slots --limit 30 --json"
check "the unit file records the replay" \
  test "$(line_of "$(unit_of llama-server qwen3.6-35b)" replay | jq -c '[.requests, .verbatim + 0, .stabilized + 0, .basis]')" = '[3,87.5,88,"cached token count"]'
BENCH_REPLAY_DIR="$sandbox/record" run run ollama qwen3.6-35b
check "ollama replays with its unload" \
  grep -qF -- "--model bench-qwen3.6-35b --base-url http://localhost:11434 --auth-token ollama --unload ollama --limit 30 --json" "$logs/prefix-ab.log"
BENCH_REPLAY_DIR="$sandbox/record" STUB_PREFIX_AB_FAIL=1 run run llama-server qwen3.6-35b
check "a failed replay still exits 0" test "$?" -eq 0
check "a failed replay leaves the unit done" test "$(end_status llama-server qwen3.6-35b)" = "done"
check "a failed replay is recorded as an error" \
  test "$(line_of "$(unit_of llama-server qwen3.6-35b)" replay | jq -r '.error | contains("prefix-ab failed")')" = true
: >"$logs/prefix-ab.log"
BENCH_REPLAY_DIR="$sandbox/record" run run llama-server qwen3.6-35b screen
check "the screen replays 10 bodies, verbatim only" \
  has_line "$logs/prefix-ab.log" "--record $sandbox/record --model qwen3.6-35b-gguf --base-url http://127.0.0.1:8300 --auth-token local --unload llama-slots --limit 10 --verbatim-only --json"
: >"$logs/prefix-ab.log"
BENCH_REPLAY_DIR="" run run llama-server qwen3.6-35b
check "an empty BENCH_REPLAY_DIR turns the replay off" test ! -s "$logs/prefix-ab.log"

: >"$logs/therm.log"
STUB_THROTTLE_CALLS=2 run ollama
check "a server run waits while the CPU is throttled" grep -qF 'CPU speed limit 80%' "$sandbox/err"
check "the thermal wait polls until the limit is back at 100" test "$(wc -l <"$logs/therm.log")" -eq 3
: >"$logs/therm.log"
STUB_THROTTLE_CALLS=99 BENCH_THERMAL_MAX=0 run ollama
check "the thermal wait gives up at its cap" grep -qF 'still throttled' "$sandbox/err"

: >"$sandbox/serve.out"
STUB_FAST_MODEL=none "$script" serve-only llama-server qwen3.6-35b >"$sandbox/serve.out" 2>"$sandbox/serve.err" &
serve_pid=$!
for _ in $(seq 1 100); do
  [ -s "$sandbox/serve.out" ] && break
  sleep 0.1
done
check "serve-only prints the server's url, model id and token" \
  test "$(jq -c . "$sandbox/serve.out")" = '{"url":"http://127.0.0.1:8300","model_id":"qwen3.6-35b-gguf","auth_token":"local"}'
check "serve-only keeps the server up" test -n "$(pgrep -f "$sandbox/stubbin/llama-server" || true)"
kill -TERM "$serve_pid"
wait "$serve_pid"
check "serve-only exits 0 on SIGTERM" test "$?" -eq 0
check "serve-only stops the server on SIGTERM" test -z "$(pgrep -f "$sandbox/stubbin/llama-server" || true)"
check "serve-only leaves the results page alone" test ! -e "$BENCH_RESULTS/llama-server--qwen3.6-35b--serve.jsonl"
STUB_TOOL_FAIL=1 "$script" serve-only llama-server qwen3.6-35b >"$sandbox/serve.out" 2>"$sandbox/serve.err"
check "serve-only exits 3 when the gate fails" test "$?" -eq 3
check "serve-only prints nothing on stdout when the gate fails" test ! -s "$sandbox/serve.out"

"$script" --help >"$sandbox/help"
check "help lists serve-only" grep -qE '^  serve-only SERVER MODEL' "$sandbox/help"

all_servers="ollama ollama-mtp omlx omlx-mtp vllm-mlx vllm-mlx-mtp vllm-metal llama-server llama-server-q8kv llama-server-mtp llama-server-ngram llama-server-src lmstudio-mlx mtplx mtplx-nomtp rapid-mlx rapid-mlx-nomtp optiq optiq-mtp optiq-ngram mistralrs"
rm -rf "$BENCH_RESULTS"
mkdir -p "$BENCH_RESULTS"
: >"$logs/bench.log"
echo stale >"$BENCH_RESULTS/old-server--old-model.jsonl"
STUB_SLOW_MODEL=qwen3.6-35b-mtplx STUB_FAST_MODEL=default run all
check "all exits 0 when every run passes" test "$?" -eq 0
check "all starts from a clean results dir" test ! -e "$BENCH_RESULTS/old-server--old-model.jsonl"
check "all writes a finished plan with both stages" \
  test "$(jq -r '[(.servers | join(",")), (.models | join(",")), (.stages | join(",")), .finished] | join(" ")' "$BENCH_RESULTS/plan.json")" = "${all_servers// /,} qwen3.6-35b,qwen3.8-27b screen,deep true"
check "all screens every server on the 35B only" \
  test "$(find "$BENCH_RESULTS" -maxdepth 1 -name '*--qwen3.6-35b--screen.jsonl' | wc -l | tr -d ' ') $(find "$BENCH_RESULTS" -maxdepth 1 -name '*--qwen3.8-27b--screen.jsonl' | wc -l | tr -d ' ')" = "21 0"
check "the screen runs the 20k prefix with 3 tool trials" \
  grep -qF -- '--model qwen3.6-35b-gguf --auth-token local --prefix-tokens 20000 --tool-trials 3 --jsonl' "$logs/bench.log"
check "a cell with a cold prefill over 1.5 times slower is lost" test "$(end_status mtplx qwen3.6-35b screen)" = lost
check "a lost cell says why" end_mentions "$(unit_of mtplx qwen3.6-35b screen)" reason 'slower'
check "the finalists are the three best screened cells" \
  test "$(jq -c .finalists "$BENCH_RESULTS/plan.json")" = '["mistralrs","ollama-mtp","omlx"]'
check "the deep stage runs the finalists and the baseline on both models" \
  test "$(find "$BENCH_RESULTS" -maxdepth 1 -name '*--deep.jsonl' | sed 's|.*/||' | LC_ALL=C sort | tr '\n' ' ')" = "mistralrs--qwen3.6-35b--deep.jsonl mistralrs--qwen3.8-27b--deep.jsonl ollama--qwen3.6-35b--deep.jsonl ollama--qwen3.8-27b--deep.jsonl ollama-mtp--qwen3.6-35b--deep.jsonl ollama-mtp--qwen3.8-27b--deep.jsonl omlx--qwen3.6-35b--deep.jsonl omlx--qwen3.8-27b--deep.jsonl "
check "the deep stage runs both prefixes with 5 tool trials" \
  grep -qF -- '--model bench-qwen3.8-27b --auth-token ollama --prefix-tokens 20000 60000 --tool-trials 5 --jsonl' "$logs/bench.log"
check "every unit records its stage" test "$(line_of "$(unit_of omlx qwen3.8-27b)" meta | jq -r .stage)" = deep
check "the final page is written" test -s "$BENCH_RESULTS/bench-off.html"

: >"$logs/bench.log"
STUB_SLOW_MODEL=qwen3.6-35b-mtplx STUB_FAST_MODEL=default run all
check "a rerun with nothing changed exits 0" test "$?" -eq 0
check "a rerun with nothing changed measures nothing" test "$(grep -c -- '--jsonl' "$logs/bench.log")" -eq 0
check "a rerun marks reused cells cached" test "$(end_status omlx qwen3.6-35b screen)" = cached
check "a cached cell keeps its previous rows" test "$(line_of "$(unit_of omlx qwen3.6-35b screen)" run | wc -l)" -eq 2
check "a cached cell can still be lost" test "$(end_status mtplx qwen3.6-35b screen)" = lost
STUB_OLLAMA_VERSION=0.20.0 STUB_SLOW_MODEL=qwen3.6-35b-mtplx STUB_FAST_MODEL=default run all
check "a new server version reruns only the cells on that server" \
  test "$(grep -- '--jsonl' "$logs/bench.log" | sed -n 's/.*--model \([^ ]*\).*/\1/p' | LC_ALL=C sort -u | tr '\n' ' ')" = "bench-qwen3.6-35b bench-qwen3.6-35b-mtp bench-qwen3.8-27b bench-qwen3.8-27b-mtp "
check "the rerun cell is done again" test "$(end_status ollama qwen3.6-35b screen)" = "done"

BENCH_ONLY_MODELS=qwen3.6-35b STUB_SLOW_MODEL=qwen3.6-35b-mtplx STUB_FAST_MODEL=default run all
check "BENCH_ONLY_MODELS exits 0" test "$?" -eq 0
check "BENCH_ONLY_MODELS plans only that model" test "$(jq -c .models "$BENCH_RESULTS/plan.json")" = '["qwen3.6-35b"]'
check "BENCH_ONLY_MODELS runs no deep cell on the other model" \
  test "$(find "$BENCH_RESULTS" -maxdepth 1 -name '*--qwen3.8-27b--*.jsonl' | wc -l | tr -d ' ')" -eq 0
BENCH_ONLY_MODELS=nonsense run all
check "BENCH_ONLY_MODELS with an unknown model exits 2" test "$?" -eq 2

mv "$BENCH_TOOLS/mistralrs-v0.9.5" "$BENCH_TOOLS/mistralrs-gone"
run all
check "all exits 1 when a run fails" test "$?" -eq 1
check "all names the failed runs" grep -qF 'failed: mistralrs/qwen3.6-35b/screen (logs' "$sandbox/err"
check "all still benches the other servers" test "$(end_status omlx qwen3.6-35b screen)" = cached
check "the failed run says what was missing" end_mentions "$(unit_of mistralrs qwen3.6-35b screen)" error 'mistralrs not found'
mv "$BENCH_TOOLS/mistralrs-gone" "$BENCH_TOOLS/mistralrs-v0.9.5"

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
