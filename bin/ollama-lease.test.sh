#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
lease="$repo/bin/ollama-lease"
tmp="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
failures=0
sleepers=""

stop_sleepers() {
  local pid
  for pid in $sleepers; do
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
  done
}


fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

check_eq() {
  [ "$2" = "$3" ] || fail "$1: expected [$2] got [$3]"
}

check_that() {
  local name="$1"
  shift
  "$@" || fail "$name"
}

check_not() {
  local name="$1"
  shift
  if "$@"; then fail "$name"; fi
}

pid_alive() {
  kill -0 "$1" 2>/dev/null
}

sleeper() {
  local pid
  sleep 60 >/dev/null 2>&1 &
  pid=$!
  sleepers="$sleepers $pid"
  echo "$pid"
}

mkdir -p "$tmp/stubbin" "$tmp/weights" "$tmp/home/.claude-ollama/presets"
. "$repo/shared/testing/stub-llama-lib.sh"
trap 'stop_sleepers; stop_stub_llama; rm -rf "$tmp"' EXIT
jq_dir="$(dirname "$(command -v jq)")"
export PATH="$tmp/stubbin:/usr/bin:/bin:$jq_dir"
export HOME="$tmp/home"
export CLAUDE_OLLAMA_LEASE_DIR="$tmp/lease"
export LLAMA_SERVER_PLIST="$tmp/no-agent.plist"
state="$tmp/stub-state.json"

server_keeps() {
  jq -n --argjson max "$1" '{models_max: $max, models: {}}' > "$state"
}

server_keeps 1
start_stub_llama "$state" || exit 1

run() {
  "$@" >"$tmp/out" 2>"$tmp/err"
}

mode_of() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

session_pid="$(sleeper)"
run "$lease" acquire session --model qwen3.8-27b-cc --pid "$session_pid" --num-ctx 65536
check_eq "acquire when free exits 0" 0 "$?"
check_that "acquire writes a lease file named by the pid" test -f "$tmp/lease/$session_pid.json"
check_eq "the lease dir is private" 700 "$(mode_of "$tmp/lease")"
check_eq "the lease file is private" 600 "$(mode_of "$tmp/lease/$session_pid.json")"
check_eq "the lease names the holder" session "$(jq -r .name "$tmp/lease/$session_pid.json")"
check_eq "the lease names the model" qwen3.8-27b-cc "$(jq -r .model "$tmp/lease/$session_pid.json")"
check_eq "the lease records num_ctx" 65536 "$(jq -r .num_ctx "$tmp/lease/$session_pid.json")"
check_eq "the lease starts with no rung" null "$(jq -r .rung "$tmp/lease/$session_pid.json")"
check_that "the lease records when it started" grep -qE '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' <<< "$(jq -r .started "$tmp/lease/$session_pid.json")"

review_pid="$(sleeper)"
run "$lease" acquire review --model qwen3.6-35b-cc --pid "$review_pid"
check_eq "a second model is refused when the router keeps one" 3 "$?"
check_eq "the refusal names the session holder" \
  "ollama lease: held by session (pid $session_pid, model qwen3.8-27b-cc); run after that session ends or run claude-custom agent -set models-max=2" "$(cat "$tmp/err")"
check_not "a refused acquire writes no lease" test -e "$tmp/lease/$review_pid.json"

run "$lease" acquire review --model qwen3.8-27b-cc --pid "$review_pid"
check_eq "the same model is accepted when the router keeps one" 0 "$?"
run "$lease" release review --pid "$review_pid"
check_eq "release exits 0" 0 "$?"
check_not "release removes the lease file" test -e "$tmp/lease/$review_pid.json"

server_keeps 2
run "$lease" acquire review --model qwen3.6-35b-cc --pid "$review_pid"
check_eq "a second model is accepted when the router keeps two" 0 "$?"
check_that "the second holder gets its own file" test -f "$tmp/lease/$review_pid.json"

third_pid="$(sleeper)"
run "$lease" acquire mock-spike --model granite4.2-3b-cc --pid "$third_pid"
check_eq "a third model is refused when the router keeps two" 3 "$?"

printf '<plist><dict><key>ProgramArguments</key><array>\n<string>llama-server</string>\n<string>--models-max</string>\n<string>3</string>\n</array></dict></plist>\n' > "$LLAMA_SERVER_PLIST"
run "$lease" acquire mock-spike --model granite4.2-3b-cc --pid "$third_pid"
check_eq "the LaunchAgent's --models-max wins over the running router" 0 "$?"
run "$lease" release mock-spike --pid "$third_pid"
rm -f "$LLAMA_SERVER_PLIST"

run "$lease" acquire speed-check --pid "$third_pid" --exclusive
check_eq "an exclusive acquire is refused while a session lease exists" 3 "$?"
check_that "the exclusive refusal names the session holder" grep -qF "held by session (pid $session_pid" "$tmp/err"

run "$lease" acquire session --model qwen3.8-27b-cc --pid "$session_pid" --rung context-down
check_eq "a holder may acquire again to record its rung" 0 "$?"
check_eq "the rung is recorded" context-down "$(jq -r .rung "$tmp/lease/$session_pid.json")"

run "$lease" holders
check_eq "holders exits 0" 0 "$?"
check_that "holders lists the session" grep -qxF "live session pid $session_pid model qwen3.8-27b-cc rung context-down" "$tmp/out"
check_that "holders lists the review" grep -qxF "live review pid $review_pid model qwen3.6-35b-cc rung -" "$tmp/out"

dead_pid="$(sleeper)"
kill "$dead_pid"
wait "$dead_pid" 2>/dev/null
printf '{"name":"session","model":"old","num_ctx":null,"rung":null,"started":"2026-01-01T00:00:00Z"}\n' > "$tmp/lease/$dead_pid.json"
run "$lease" holders
check_that "holders reports a lease whose pid is dead as stale" grep -qxF "stale session pid $dead_pid model old" "$tmp/out"
check_not "holders removes the stale lease" test -e "$tmp/lease/$dead_pid.json"
printf '{"name":"session","model":"old","num_ctx":null,"rung":null,"started":"2026-01-01T00:00:00Z"}\n' > "$tmp/lease/$dead_pid.json"
echo "not json" > "$tmp/lease/notes.json"
run "$lease" acquire mock-spike --model qwen3.8-27b-cc --pid "$third_pid"
check_eq "a dead holder never blocks an acquire" 0 "$?"
check_not "acquire removes the stale lease" test -e "$tmp/lease/$dead_pid.json"
check_that "a file that is not a pid is left alone" test -e "$tmp/lease/notes.json"
run "$lease" release mock-spike --pid "$third_pid"

waiting_pid="$(sleeper)"
CLAUDE_OLLAMA_LEASE_POLL=0.1 "$lease" acquire bench --model granite4.2-3b-cc --pid "$waiting_pid" --wait 5 >"$tmp/wait.out" 2>"$tmp/wait.err" &
waiter=$!
sleep 0.5
check_that "a waiting acquire holds no lease yet" test ! -e "$tmp/lease/$waiting_pid.json"
run "$lease" release review --pid "$review_pid"
wait "$waiter"
check_eq "a waiting acquire succeeds once a holder releases" 0 "$?"
check_that "the waiting acquire then holds its lease" test -f "$tmp/lease/$waiting_pid.json"
run "$lease" release bench --pid "$waiting_pid"

server_keeps 1
CLAUDE_OLLAMA_LEASE_POLL=0.1 run "$lease" acquire bench --model granite4.2-3b-cc --pid "$waiting_pid" --wait 0.3
check_eq "a waiting acquire gives up after its seconds" 3 "$?"
check_that "and prints the refusal once" grep -qxF "ollama lease: held by session (pid $session_pid, model qwen3.8-27b-cc); run after that session ends or run claude-custom agent -set models-max=2" "$tmp/err"
check_eq "the refusal is one line" 1 "$(wc -l < "$tmp/err" | tr -d ' ')"

run "$lease" heartbeat --watch-pid "$session_pid"
check_eq "the heartbeat is gone, since the router never unloads an idle model" 2 "$?"

cat > "$tmp/make-gguf.py" <<'PY'
import json
import struct
import sys

def string(text):
    data = text.encode()
    return struct.pack("<Q", len(data)) + data

def keyvalue(key, value):
    if isinstance(value, list):
        return string(key) + struct.pack("<IIQ", 9, 4, len(value)) + b"".join(struct.pack("<I", item) for item in value)
    if isinstance(value, str):
        return string(key) + struct.pack("<I", 8) + string(value)
    return string(key) + struct.pack("<II", 4, value)

path, size, metadata = sys.argv[1], int(sys.argv[2]), json.loads(sys.argv[3])
pairs = [keyvalue("general.architecture", "qwen3")] + [keyvalue("qwen3." + key, value) for key, value in metadata.items()]
header = b"GGUF" + struct.pack("<IQQ", 3, 0, len(pairs)) + b"".join(pairs)
header += b"\0" * (-len(header) % 32)
with open(path, "wb") as handle:
    handle.write(header)
    handle.truncate(size)
PY
make_gguf() {
  python3 "$tmp/make-gguf.py" "$tmp/weights/$1" "$2" "$3"
}
make_gguf dense.gguf 17179869184 '{"block_count": 64, "attention.head_count_kv": 8, "attention.key_length": 128, "attention.value_length": 128}'
make_gguf hybrid.gguf 17179869184 '{"block_count": 64, "attention.head_count_kv": 8, "attention.key_length": 128, "attention.value_length": 128, "full_attention_interval": 4}'
layer_heads="$(jq -cn '[range(64) | if . % 4 == 3 then 8 else 0 end]')"
make_gguf layers.gguf 17179869184 "{\"block_count\": 64, \"attention.head_count_kv\": $layer_heads, \"attention.key_length\": 128}"
make_gguf bare.gguf 17179869184 '{"block_count": 64}'
make_gguf embed.gguf 644245094 '{"block_count": 28}'
presets="$HOME/.claude-ollama/presets/models.ini"
write_presets() {
  printf '[*]\ncache-type-k = %s\n\n' "$1" > "$presets"
  printf '[%s]\nmodel = %s\n\n' dense-cc "$tmp/weights/dense.gguf" hybrid-cc "$tmp/weights/hybrid.gguf" \
    layers-cc "$tmp/weights/layers.gguf" bare-cc "$tmp/weights/bare.gguf" gone-cc "$tmp/weights/gone.gguf" >> "$presets"
  printf '[qwen3-embedding-0.6b]\nalias = qwen3-embedding:0.6b\nmodel = %s\n' "$tmp/weights/embed.gguf" >> "$presets"
}
write_presets q8_0
cat > "$tmp/stubbin/sysctl" <<'SH'
#!/bin/sh
echo "${STUB_MEMSIZE:-34359738368}"
SH
cat > "$tmp/stubbin/vm_stat" <<'SH'
#!/bin/sh
printf 'Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages free:    1000.\nPages active:  %s.\nPages inactive: 50000.\nPages wired down: %s.\n' "${STUB_ACTIVE_PAGES:-100000}" "${STUB_WIRED_PAGES:-100000}"
SH
chmod +x "$tmp/stubbin/sysctl" "$tmp/stubbin/vm_stat"
fit_field() {
  jq -r ".$1" "$tmp/out"
}

server_keeps 2
run "$lease" fit --model dense-cc --num-ctx 65536 --embedding qwen3-embedding:0.6b
check_eq "fit exits 0 when the models fit" 0 "$?"
check_eq "fit reads the model bytes from the preset's weights file" 17179869184 "$(fit_field model_bytes)"
check_eq "fit counts the KV cache from layers, kv heads, key and value lengths and cache type" 8589934592 "$(fit_field kv_bytes)"
check_eq "fit finds the embedding preset by its alias and reads its weights" 644245094 "$(fit_field embedding_bytes)"
check_eq "fit sums the three" 26414048870 "$(fit_field total_bytes)"
check_eq "fit takes the free bytes as memsize minus wired and active pages" 31082938368 "$(fit_field free_bytes)"
check_eq "fit says it fits" true "$(fit_field fits)"
check_eq "fit prints the margin" 4668889498 "$(fit_field margin_bytes)"
check_eq "fit names the estimate exact when every field is known" exact "$(fit_field estimate)"

run "$lease" fit --model hybrid-cc --num-ctx 65536
check_eq "a hybrid model counts only every fourth layer's KV cache" 2147483648 "$(fit_field kv_bytes)"
check_eq "and is still exact" exact "$(fit_field estimate)"
run "$lease" fit --model layers-cc --num-ctx 65536
check_eq "a per-layer head count counts the layers with KV heads, the value length defaulting to the key length" 2147483648 "$(fit_field kv_bytes)"

write_presets f16
run "$lease" fit --model dense-cc --num-ctx 65536
check_eq "an f16 cache doubles the KV bytes" 17179869184 "$(fit_field kv_bytes)"
check_eq "without --embedding the embedding bytes are 0" 0 "$(fit_field embedding_bytes)"
write_presets q4_0
run "$lease" fit --model dense-cc --num-ctx 65536
check_eq "a q4_0 cache halves the q8_0 KV bytes" 4294967296 "$(fit_field kv_bytes)"
write_presets q8_0

STUB_MEMSIZE=17179869184 STUB_ACTIVE_PAGES=0 STUB_WIRED_PAGES=0 run "$lease" fit --model dense-cc --num-ctx 65536 --embedding qwen3-embedding:0.6b
check_eq "fit exits 0 when the models do not fit" 0 "$?"
check_eq "fit says it does not fit" false "$(fit_field fits)"
check_eq "the margin goes negative by the shortfall" -9234179686 "$(fit_field margin_bytes)"

run "$lease" fit --model bare-cc --num-ctx 65536
check_eq "without the metadata fields the KV cache is a quarter of the model" 4294967296 "$(fit_field kv_bytes)"
check_eq "and the estimate is rough" rough "$(fit_field estimate)"
run "$lease" fit --model bare-cc --num-ctx 32768
check_eq "the rough KV cache shrinks with num_ctx" 2147483648 "$(fit_field kv_bytes)"

jq -n '{models_max: 2, models: {"dense-cc": {}, "other-cc": {}, "qwen3-embedding-0.6b": {aliases: ["qwen3-embedding:0.6b"]}}, loaded: ["dense-cc", "other-cc", "qwen3-embedding-0.6b"]}' > "$state"
run "$lease" fit --model dense-cc --num-ctx 65536 --embedding qwen3-embedding:0.6b
check_eq "a loaded model and embedding count their weights files as free memory, since the router's /models reports no size" $((31082938368 + 17179869184 + 644245094)) "$(fit_field free_bytes)"
server_keeps 2

mkdir -p "$tmp/proc"
printf 'MemTotal:       65536000 kB\nMemFree:         1000000 kB\nMemAvailable:   30000000 kB\n' > "$tmp/proc/meminfo"
CLAUDE_OLLAMA_MEMINFO="$tmp/proc/meminfo" run "$lease" fit --model dense-cc --num-ctx 65536
check_eq "on Linux the free bytes are MemAvailable" 30720000000 "$(fit_field free_bytes)"

run "$lease" fit --model missing-cc --num-ctx 65536
check_eq "fit exits 1 for a preset the presets file lacks" 1 "$?"
check_eq "and names the preset and the file" "ollama lease: no preset missing-cc in $presets" "$(cat "$tmp/err")"
run "$lease" fit --model gone-cc --num-ctx 65536
check_eq "fit exits 1 when the weights are not downloaded" 1 "$?"
check_eq "and says how to get them" "ollama lease: $tmp/weights/gone.gguf is missing (run claude-ollama prepare)" "$(cat "$tmp/err")"
run "$lease" fit --model dense-cc
check_eq "fit without --num-ctx exits 2" 2 "$?"

run "$lease" acquire
check_eq "acquire without a name exits 2" 2 "$?"
run "$lease" bogus
check_eq "an unknown subcommand exits 2" 2 "$?"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
