#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
failures=0
sandbox="$(mktemp -d)"
. "$here/stub-llama-lib.sh"
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

get() {
  curl -s "$LLAMA_SERVER_URL$1"
}

post() {
  curl -s -X POST "$LLAMA_SERVER_URL$1" -H 'content-type: application/json' -d "$2"
}

status_of() {
  curl -s -o /dev/null -w '%{http_code}' -X "$1" "$LLAMA_SERVER_URL$2" -H 'content-type: application/json' ${3:+-d "$3"}
}

model_status() {
  get /models | jq -r --arg id "$1" '.data[] | select(.id == $id) | .status.value'
}

state="$sandbox/state.json"
cat > "$state" <<'EOF'
{
  "build": 11429,
  "commit": "d81235049",
  "models_max": 2,
  "models": {
    "chat-cc": {"size": 1000},
    "chat-cc@think": {"size": 1000},
    "embed-0.6b": {"aliases": ["embed:0.6b"], "size": 300, "embeddings": true}
  },
  "reply": {"text": "canned reply", "thinking": "canned thought"},
  "embedding_dims": 4
}
EOF
start_stub_llama "$state"

check_eq "the helper exports a loopback LLAMA_SERVER_URL" yes "$(printf '%s' "$LLAMA_SERVER_URL" | grep -qE '^http://127\.0\.0\.1:[0-9]+$' && echo yes)"
check_eq "/health answers ok" '{"status":"ok"}' "$(get /health)"
check_eq "/props names the build like a router" "router b11429-d81235049 2" "$(get /props | jq -r '"\(.role) \(.build_info) \(.max_instances)"')"
check_eq "/models lists every preset with its aliases, unloaded" "chat-cc unloaded [] preset
chat-cc@think unloaded [] preset
embed-0.6b unloaded [\"embed:0.6b\"] preset" "$(get /models | jq -r '.data[] | "\(.id) \(.status.value) \(.aliases | tojson) \(.source)"')"
check_eq "/models is a list object" list "$(get /models | jq -r .object)"
check_eq "/v1/models answers the same list" "chat-cc chat-cc@think embed-0.6b" "$(get /v1/models | jq -r '[.data[].id] | join(" ")')"
check_eq "an unloaded model carries no meta" null "$(get /models | jq -c '.data[0].meta')"

check_eq "loading a preset succeeds" '{"success":true}' "$(post /models/load '{"model":"chat-cc"}')"
check_eq "and it is loaded" loaded "$(model_status chat-cc)"
check_eq "a loaded model reports its weights size as meta.size" 1000 "$(get /models | jq -r '.data[] | select(.id == "chat-cc") | .meta.size')"
check_eq "loading an unknown model is a 404" 404 "$(status_of POST /models/load '{"model":"nope"}')"
check_eq "unloading a model that is not running is a 400" 400 "$(status_of POST /models/unload '{"model":"chat-cc@think"}')"
check_eq "the 400 says why" "model is not running" "$(post /models/unload '{"model":"chat-cc@think"}' | jq -r .error.message)"
check_eq "unloading a loaded model succeeds" '{"success":true}' "$(post /models/unload '{"model":"chat-cc"}')"
check_eq "and it is unloaded" unloaded "$(model_status chat-cc)"
check_eq "a model loads by its alias" '{"success":true}' "$(post /models/load '{"model":"embed:0.6b"}')"
check_eq "and the preset it names is loaded" loaded "$(model_status embed-0.6b)"

reply="$(post /v1/messages '{"model":"chat-cc","max_tokens":20,"messages":[{"role":"user","content":"hi"}]}')"
check_eq "/v1/messages answers with the canned text and no thinking block" "text:canned reply" "$(printf '%s' "$reply" | jq -r '[.content[] | "\(.type):\(.text // .thinking)"] | join(",")')"
check_eq "/v1/messages carries usage with the cache count" "true true true" "$(printf '%s' "$reply" | jq -r '.usage | "\(has("input_tokens")) \(has("output_tokens")) \(has("cache_read_input_tokens"))"')"
check_eq "/v1/messages names the model and ends the turn" "chat-cc end_turn message" "$(printf '%s' "$reply" | jq -r '"\(.model) \(.stop_reason) \(.type)"')"
check_eq "a request loads its model on demand" loaded "$(model_status chat-cc)"
think="$(post /v1/messages '{"model":"chat-cc@think","max_tokens":20,"messages":[{"role":"user","content":"hi"}]}')"
check_eq "an @think preset answers with a thinking block first" "thinking:canned thought,text:canned reply" "$(printf '%s' "$think" | jq -r '[.content[] | "\(.type):\(.text // .thinking)"] | join(",")')"
check_eq "loading a third model evicts the least recently used one" "chat-cc loaded, chat-cc@think loaded, embed-0.6b unloaded" \
  "$(get /models | jq -r '[.data[] | "\(.id) \(.status.value)"] | join(", ")')"
check_eq "/v1/messages on an unknown model is a 400" 400 "$(status_of POST /v1/messages '{"model":"nope","messages":[]}')"

stream="$(post /v1/messages '{"model":"chat-cc","stream":true,"max_tokens":20,"messages":[{"role":"user","content":"hi"}]}')"
check_eq "a streamed reply sends the Anthropic event sequence" "message_start content_block_start content_block_delta content_block_stop message_delta message_stop" \
  "$(printf '%s\n' "$stream" | sed -n 's/^event: //p' | tr '\n' ' ' | sed 's/ $//')"
check_eq "and its delta carries the canned text" "canned reply" "$(printf '%s\n' "$stream" | sed -n 's/^data: //p' | jq -r 'select(.type == "content_block_delta") | .delta.text')"

check_eq "count_tokens answers input_tokens" true "$(post /v1/messages/count_tokens '{"model":"chat-cc","messages":[{"role":"user","content":"hello there"}]}' | jq 'has("input_tokens")')"

embedded="$(post /v1/embeddings '{"model":"embed:0.6b","input":["one","two"]}')"
check_eq "/v1/embeddings returns one vector per input" "2 4 4" "$(printf '%s' "$embedded" | jq -r '"\(.data | length) \(.data[0].embedding | length) \(.data[1].embedding | length)"')"
check_eq "/v1/embeddings echoes the requested name and counts tokens" "embed:0.6b true" "$(printf '%s' "$embedded" | jq -r '"\(.model) \(.usage | has("prompt_tokens"))"')"
check_eq "the same text gets the same vector" "$(post /v1/embeddings '{"model":"embed:0.6b","input":"one"}' | jq -c '.data[0].embedding')" "$(printf '%s' "$embedded" | jq -c '.data[0].embedding')"
check_eq "/v1/embeddings on an unknown model is a 400" 400 "$(status_of POST /v1/embeddings '{"model":"nope","input":"x"}')"

check_eq "a slot erase without a model is a 400, as in router mode" 400 "$(status_of POST '/slots/0?action=erase' '{}')"
check_eq "a slot erase names the slot" 0 "$(post '/slots/0?action=erase&model=chat-cc' '{}' | jq -r .id_slot)"

check_eq "the state file counts requests by method and path" 3 "$(jq -r '.counters["POST /models/unload"]' "$state")"
check_eq "the state file records which models are loaded, least recently used first" '["chat-cc","embed-0.6b"]' "$(jq -c '.loaded' "$state")"
check_eq "the log has one JSON line per request with method, path and body" "POST /models/load chat-cc" "$(jq -r 'select(.path == "/models/load") | "\(.method) \(.path) \(.body.model)"' "$STUB_LLAMA_LOG" | head -n 1)"

jq '.health_status = 503' "$state" > "$sandbox/next.json" && mv "$sandbox/next.json" "$state"
check_eq "health_status makes /health answer 503" 503 "$(status_of GET /health)"
jq '.health_status = 200 | .fail_paths = ["/models/load"]' "$state" > "$sandbox/next.json" && mv "$sandbox/next.json" "$state"
check_eq "a path in fail_paths answers 500" 500 "$(status_of POST /models/load '{"model":"chat-cc"}')"
check_eq "other paths still answer" 200 "$(status_of GET /health)"
jq '.fail_paths = [] | .load_polls = 2' "$state" > "$sandbox/next.json" && mv "$sandbox/next.json" "$state"
post /models/unload '{"model":"chat-cc"}' >/dev/null
post /models/load '{"model":"chat-cc"}' >/dev/null
check_eq "load_polls keeps a model loading for that many /models reads" "loading loading loaded" "$(model_status chat-cc) $(model_status chat-cc) $(model_status chat-cc)"
check_eq "an unknown route is a 404" 404 "$(status_of GET /api/tags)"

stop_stub_llama
check_eq "stop_stub_llama stops the server" 000 "$(curl -s -o /dev/null -w '%{http_code}' -m 2 "$LLAMA_SERVER_URL/health")"

rm -f "$sandbox/fresh.json"
start_stub_llama "$sandbox/fresh.json"
check_eq "a missing state file starts with no models and build 11429" "0 b11429-d81235049" "$(get /models | jq -r '.data | length') $(get /props | jq -r .build_info)"
stop_stub_llama

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
