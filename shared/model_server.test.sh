#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
failures=0
sandbox="$(mktemp -d)"
. "$here/testing/stub-llama-lib.sh"
cleanup() {
  stop_stub_llama
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

call() {
  python3 -I - "$here" "$@" <<'PY'
import json
import sys

sys.path.insert(0, sys.argv[1])
import model_server

name, *arguments = sys.argv[2:]
if name == "embed":
    arguments = [arguments[0], json.loads(arguments[1])]
try:
    print(json.dumps(getattr(model_server, name)(*arguments)))
except model_server.ModelServerError as error:
    print(f"error: {error}")
PY
}

unset LLAMA_SERVER_URL
check_eq "server_url defaults to port 11435 on loopback" '"http://127.0.0.1:11435"' "$(call server_url)"
check_eq "LLAMA_SERVER_URL overrides it" '"http://127.0.0.1:9"' "$(LLAMA_SERVER_URL=http://127.0.0.1:9 call server_url)"
check_eq "up is false with no server" false "$(LLAMA_SERVER_URL=http://127.0.0.1:9 call up)"
check_eq "listed is empty with no server" "[]" "$(LLAMA_SERVER_URL=http://127.0.0.1:9 call listed)"

cat > "$sandbox/state.json" <<'EOF'
{
  "models": {
    "chat-cc": {"size": 4242},
    "embed-0.6b": {"aliases": ["embed:0.6b"], "size": 300, "embeddings": true}
  },
  "embedding_dims": 3
}
EOF
start_stub_llama "$sandbox/state.json"
check_eq "up is true when /health answers 200" true "$(call up)"
check_eq "listed names every preset id and alias" '["chat-cc", "embed-0.6b", "embed:0.6b"]' "$(call listed)"
check_eq "loaded is false before a load" false "$(call loaded chat-cc)"
check_eq "resident_bytes is None for an unloaded model" null "$(call resident_bytes chat-cc)"
check_eq "load waits until the model is loaded" true "$(MODEL_LOAD_POLL=0.05 call load chat-cc)"
check_eq "loaded is true after it" true "$(call loaded chat-cc)"
check_eq "resident_bytes is the loaded model's size" 4242 "$(call resident_bytes chat-cc)"
check_eq "load of an unknown model raises" "error: could not load nope: HTTP 404" "$(call load nope)"
vectors="$(call embed embed:0.6b '["one", "two"]')"
check_eq "embed returns one vector per text" "2 3" "$(printf '%s' "$vectors" | jq -r '"\(length) \(.[0] | length)"')"
check_eq "embed sends the texts to /v1/embeddings" '{"model":"embed:0.6b","input":["one","two"]}' "$(jq -c 'select(.path == "/v1/embeddings") | .body' "$STUB_LLAMA_LOG")"
check_eq "embed of an unknown model raises" "error: could not embed with nope: HTTP 400" "$(call embed nope '["x"]')"
check_eq "loaded matches an alias" true "$(call loaded embed:0.6b)"
check_eq "unload unloads a loaded model" true "$(call unload chat-cc)"
check_eq "and it is unloaded" false "$(call loaded chat-cc)"
check_eq "unload of a model that is not running still succeeds" true "$(call unload chat-cc)"
jq '.load_polls = 100000' "$sandbox/state.json" > "$sandbox/next.json" && mv "$sandbox/next.json" "$sandbox/state.json"
check_eq "load gives up after MODEL_LOAD_TIMEOUT" "error: chat-cc did not load within 1s" "$(MODEL_LOAD_TIMEOUT=1 MODEL_LOAD_POLL=0.2 call load chat-cc)"
jq '.health_status = 503' "$sandbox/state.json" > "$sandbox/next.json" && mv "$sandbox/next.json" "$sandbox/state.json"
check_eq "up is false while /health answers 503" false "$(call up)"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
