#!/usr/bin/env bash
set -u
real_repo="$(cd "$(dirname "$0")/../.." && pwd)"
failures=0
sandbox="$(mktemp -d)"
hf_pid=""
. "$real_repo/shared/testing/stub-llama-lib.sh"
cleanup() {
  stop_stub_llama
  if [ -n "$hf_pid" ]; then
    kill "$hf_pid" 2>/dev/null
    wait "$hf_pid" 2>/dev/null
  fi
  rm -rf "$sandbox"
}
trap cleanup EXIT

check_eq() {
  if [ "$2" = "$3" ]; then return 0; fi
  echo "FAIL: $1"
  echo "  expected: $2"
  echo "  actual:   $3"
  failures=$((failures + 1))
}

outcome() {
  if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi
}

write_gguf() {
  python3 - "$1" "$2" <<'PY'
import struct
import sys

def string(text):
    data = text.encode()
    return struct.pack("<Q", len(data)) + data

magic = b"GGUF" if sys.argv[2] == "valid" else b"GGXF"
keyvalue = string("general.architecture") + struct.pack("<I", 8) + string("qwen3")
info = string("a") + struct.pack("<I", 1) + struct.pack("<Q", 4) + struct.pack("<IQ", 0, 0)
header = magic + struct.pack("<IQQ", 3, 1, 1) + keyvalue + info
header += b"\0" * (-len(header) % 32)
open(sys.argv[1], "wb").write(header + b"\0" * 32)
PY
}

sha_of() {
  shasum -a 256 "$1" | cut -d' ' -f1
}

repo="$sandbox/repo"
hf_root="$sandbox/hf"
mkdir -p "$repo/ollama" "$repo/bin" "$repo/shared" "$sandbox/home" "$hf_root/org/Tiny-GGUF/resolve/abc123" "$hf_root/org/Embed-GGUF/resolve/def456" "$hf_root/org/Bad-GGUF/resolve/0ff1ce"
ln -s "$real_repo/bin/gguf-inspect" "$repo/bin/gguf-inspect"
ln -s "$real_repo/shared/profile-overlay" "$repo/shared/profile-overlay"
write_gguf "$hf_root/org/Tiny-GGUF/resolve/abc123/tiny.gguf" valid
write_gguf "$hf_root/org/Embed-GGUF/resolve/def456/embed.gguf" valid
write_gguf "$hf_root/org/Bad-GGUF/resolve/0ff1ce/bad.gguf" bad
tiny_sha="$(sha_of "$hf_root/org/Tiny-GGUF/resolve/abc123/tiny.gguf")"
embed_sha="$(sha_of "$hf_root/org/Embed-GGUF/resolve/def456/embed.gguf")"
bad_sha="$(sha_of "$hf_root/org/Bad-GGUF/resolve/0ff1ce/bad.gguf")"
cat > "$repo/ollama/sizes.json" <<'EOF'
{
  "tiny": {"base": "org/Tiny-GGUF/tiny.gguf", "model": "tiny-cc", "context": 16384, "gguf": {"repo": "org/Tiny-GGUF", "revision": "abc123", "file": "tiny.gguf"}},
  "wrong": {"base": "org/Tiny-GGUF/tiny.gguf", "model": "wrong-cc", "context": 16384, "gguf": {"repo": "org/Tiny-GGUF", "revision": "abc123", "file": "wrong.gguf"}},
  "bad": {"base": "org/Bad-GGUF/bad.gguf", "model": "bad-cc", "context": 16384, "gguf": {"repo": "org/Bad-GGUF", "revision": "0ff1ce", "file": "bad.gguf"}}
}
EOF
cp "$hf_root/org/Tiny-GGUF/resolve/abc123/tiny.gguf" "$hf_root/org/Tiny-GGUF/resolve/abc123/wrong.gguf"
printf 'more bytes' >> "$hf_root/org/Tiny-GGUF/resolve/abc123/wrong.gguf"
cat > "$repo/ollama/embedding.json" <<'EOF'
{"model": "embed:0.6b", "gguf": {"repo": "org/Embed-GGUF", "revision": "def456", "file": "embed.gguf"}}
EOF
jq -n --arg tiny "$tiny_sha" --arg embed "$embed_sha" --arg bad "$bad_sha" \
  '{"org/Tiny-GGUF/tiny.gguf": $tiny, "org/Tiny-GGUF/wrong.gguf": $tiny, "org/Embed-GGUF/embed.gguf": $embed, "org/Bad-GGUF/bad.gguf": $bad}' > "$repo/ollama/model-digests.json"
printf '[*]\nn-gpu-layers = 99\ncache-ram = 8192\nflash-attn = on\n' > "$repo/ollama/server.ini"

cat > "$sandbox/hf.py" <<'PY'
import os
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

class Handler(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        with open(sys.argv[3], "a") as log:
            log.write(self.path + "\n")

class QuietServer(ThreadingHTTPServer):
    def handle_error(self, request, client_address):
        return

server = QuietServer(("127.0.0.1", 0), partial(Handler, directory=sys.argv[1]))
with open(sys.argv[2] + ".tmp", "w") as port:
    port.write(str(server.server_address[1]))
os.replace(sys.argv[2] + ".tmp", sys.argv[2])
server.serve_forever()
PY
python3 "$sandbox/hf.py" "$hf_root" "$sandbox/hf.port" "$sandbox/hf.log" &
hf_pid=$!
while [ ! -s "$sandbox/hf.port" ]; do sleep 0.05; done
touch "$sandbox/hf.log"

state="$sandbox/state.json"
cat > "$state" <<'EOF'
{
  "build": 11429,
  "models_max": 4,
  "models": {
    "tiny-cc": {"size": 4242},
    "embed-0.6b": {"aliases": ["embed:0.6b"], "size": 300, "embeddings": true}
  }
}
EOF

export HOME="$sandbox/home"
HF_ENDPOINT="http://127.0.0.1:$(cat "$sandbox/hf.port")"
export HF_ENDPOINT
export LLAMA_SERVER_PLIST="$sandbox/absent.plist"
unset LLAMA_SERVER_URL CLAUDE_OLLAMA_WEIGHTS_DIR MODEL_LOAD_TIMEOUT LLAMA_SERVER_BIN
repo_dir="$repo"
. "$real_repo/bin/lib/model-server.sh"

check_eq "server_url defaults to port 11435 on loopback" "http://127.0.0.1:11435" "$(server_url)"
check_eq "LLAMA_SERVER_URL overrides the server url" "http://127.0.0.1:9" "$(LLAMA_SERVER_URL=http://127.0.0.1:9 server_url)"
check_eq "server_up is false with no server" no "$(LLAMA_SERVER_URL=http://127.0.0.1:9 outcome server_up)"
printf '#!/bin/sh\necho "version: 0.6.0 (build 9876, commit abcdef0)"\necho "built with clang"\n' > "$sandbox/llama-server"
chmod +x "$sandbox/llama-server"
check_eq "server_build falls back to LLAMA_SERVER_BIN --version with no server" 9876 "$(LLAMA_SERVER_URL=http://127.0.0.1:9 LLAMA_SERVER_BIN="$sandbox/llama-server" server_build)"
check_eq "models_max defaults to 2 with no plist and no server" 2 "$(LLAMA_SERVER_URL=http://127.0.0.1:9 models_max)"

start_stub_llama "$state"
check_eq "server_up is true when /health answers 200" yes "$(outcome server_up)"
check_eq "server_build reads the build from /props" 11429 "$(server_build)"
check_eq "models_max reads the running router's max_instances" 4 "$(models_max)"
cat > "$sandbox/agent.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>ProgramArguments</key><array>
<string>/opt/homebrew/bin/llama-server</string>
<string>--models-preset</string>
<string>/x/models.ini</string>
<string>--models-max</string>
<string>3</string>
</array></dict></plist>
EOF
check_eq "models_max prefers the LaunchAgent's --models-max" 3 "$(LLAMA_SERVER_PLIST="$sandbox/agent.plist" models_max)"
check_eq "model_listed finds a preset by id" yes "$(outcome model_listed tiny-cc)"
check_eq "model_listed finds a preset by alias" yes "$(outcome model_listed embed:0.6b)"
check_eq "model_listed refuses an unknown id" no "$(outcome model_listed nope)"
check_eq "model_loaded is false before a load" no "$(outcome model_loaded tiny-cc)"
check_eq "model_resident_bytes fails for an unloaded model" no "$(outcome model_resident_bytes tiny-cc)"
jq '.load_polls = 2' "$state" > "$sandbox/next.json" && mv "$sandbox/next.json" "$state"
check_eq "model_load posts and waits until the model is loaded" yes "$(MODEL_LOAD_POLL=0.05 outcome model_load tiny-cc)"
check_eq "model_loaded is true after a load" yes "$(outcome model_loaded tiny-cc)"
check_eq "model_loaded is false for an alias whose preset is not loaded" no "$(outcome model_loaded embed:0.6b)"
check_eq "model_resident_bytes reports a loaded model's size" 4242 "$(model_resident_bytes tiny-cc)"
check_eq "model_load fails on an unknown model" "model-server: could not load nope" "$(model_load nope 2>&1 >/dev/null)"
jq '.load_polls = 100000' "$state" > "$sandbox/next.json" && mv "$sandbox/next.json" "$state"
check_eq "model_load gives up after MODEL_LOAD_TIMEOUT" "model-server: embed:0.6b did not load within 1s" "$(MODEL_LOAD_TIMEOUT=1 MODEL_LOAD_POLL=0.2 model_load embed:0.6b 2>&1 >/dev/null)"
jq '.load_polls = 0 | .loading = {}' "$state" > "$sandbox/next.json" && mv "$sandbox/next.json" "$state"
check_eq "model_unload unloads a loaded model" yes "$(outcome model_unload tiny-cc)"
check_eq "and it is no longer loaded" no "$(outcome model_loaded tiny-cc)"
check_eq "model_unload succeeds on a model that is not running" yes "$(outcome model_unload tiny-cc)"
check_eq "embedding_url is the server's /v1/embeddings" "$LLAMA_SERVER_URL/v1/embeddings" "$(embedding_url)"
jq '.health_status = 503' "$state" > "$sandbox/next.json" && mv "$sandbox/next.json" "$state"
check_eq "server_up is false while /health answers 503" no "$(outcome server_up)"
stop_stub_llama

check_eq "server_log_path is the LaunchAgent's log under ~/.claude-ollama" "$HOME/.claude-ollama/logs/llama-server.log" "$(server_log_path)"
check_eq "server_setting reads ollama/server.ini" 8192 "$(server_setting cache-ram)"
mkdir -p "$HOME/.claude-ollama/presets"
printf '[*]\ncache-ram = 4096\n\n[tiny-cc]\nflash-attn = off\n' > "$HOME/.claude-ollama/presets/models.ini"
check_eq "server_setting prefers [*] in the user preset file" 4096 "$(server_setting cache-ram)"
check_eq "server_setting reads only the [*] section of the user file" on "$(server_setting flash-attn)"
check_eq "server_setting fails on an unknown key" no "$(outcome server_setting nope)"

check_eq "weights_dir defaults under ~/.claude-ollama" "$HOME/.claude-ollama/weights" "$(weights_dir)"
export CLAUDE_OLLAMA_WEIGHTS_DIR="$sandbox/weights"
check_eq "CLAUDE_OLLAMA_WEIGHTS_DIR overrides it" "$sandbox/weights" "$(weights_dir)"
check_eq "weights_path names the size's GGUF file there" "$sandbox/weights/tiny.gguf" "$(weights_path tiny)"
check_eq "weights_ok is false before a download" no "$(outcome weights_ok tiny)"
check_eq "fetch_weights downloads, checks and keeps the file" yes "$(outcome fetch_weights tiny)"
check_eq "it asked for the pinned revision" "/org/Tiny-GGUF/resolve/abc123/tiny.gguf" "$(tail -n 1 "$sandbox/hf.log")"
check_eq "weights_ok is true after it" yes "$(outcome weights_ok tiny)"
check_eq "no .part file is left" no "$(outcome test -e "$sandbox/weights/tiny.gguf.part")"
requests="$(grep -c . "$sandbox/hf.log")"
check_eq "fetch_weights skips a file that already matches its pin" yes "$(outcome fetch_weights tiny)"
check_eq "and makes no request" "$requests" "$(grep -c . "$sandbox/hf.log")"
printf 'x' >> "$sandbox/weights/tiny.gguf"
check_eq "weights_ok is false when the bytes differ from the pin" no "$(outcome weights_ok tiny)"
wrong_sha="$(sha_of "$hf_root/org/Tiny-GGUF/resolve/abc123/wrong.gguf")"
check_eq "a bad sha256 names the expected and actual hashes" "model-server: wrong.gguf has sha256 $wrong_sha, but ollama/model-digests.json pins $tiny_sha; not keeping it" "$(fetch_weights wrong 2>&1 >/dev/null | tail -n 1)"
check_eq "and returns 1" no "$(outcome fetch_weights wrong)"
check_eq "and removes the .part file" no "$(outcome test -e "$sandbox/weights/wrong.gguf.part")"
check_eq "and keeps no file" no "$(outcome test -e "$sandbox/weights/wrong.gguf")"
check_eq "a file that fails gguf-inspect is not kept" no "$(outcome fetch_weights bad)"
check_eq "and is removed" no "$(outcome test -e "$sandbox/weights/bad.gguf")"
check_eq "fetch_weights refuses a size without a gguf block" "model-server: size nope has no pinned gguf in sizes.json" "$(fetch_weights nope 2>&1 >/dev/null)"
check_eq "fetch_embedding_weights fetches the embedding GGUF" yes "$(outcome fetch_embedding_weights)"
check_eq "and keeps it beside the size weights" yes "$(outcome test -f "$sandbox/weights/embed.gguf")"

printf '{"model": "tiny-cc"}\n' > "$repo/ollama/settings.tiny.json"
printf '[*]\nflash-attn = on\n\n[tiny-cc]\nmodel = @WEIGHTS@/tiny.gguf\nctx-size = 16384\nn-predict = 8192\ntemp = 0.7\nreasoning = off\n\n[tiny-cc@think]\nmodel = @WEIGHTS@/tiny.gguf\nctx-size = 16384\nreasoning = on\n' > "$repo/ollama/models.ini"
ln -s "$real_repo/ollama/preset-keys.json" "$repo/ollama/preset-keys.json"
use_size tiny
check_eq "preset_parameters prints the size's preset keys without the weights path" "ctx-size = 16384
n-predict = 8192
temp = 0.7
reasoning = off" "$(preset_parameters)"
check_eq "preset_ctx_size is the size's ctx-size" 16384 "$(preset_ctx_size)"
mkdir -p "$HOME/.config/claude-custom/profiles"
printf '{"context": 20480, "parameters": {"temperature": 0.3}}' > "$HOME/.config/claude-custom/profiles/ollama-tiny.json"
check_eq "preset_ctx_size follows a profile context" 20480 "$(preset_ctx_size)"
check_eq "preset_parameters applies the profile's parameters as preset keys" "temp = 0.3" "$(preset_parameters | grep '^temp')"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
