#!/usr/bin/env bash
set -u
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
probe="$repo_dir/bin/ollama-cache-probe"
tmp="$(mktemp -d)"
failures=0
stub_pid=""
base_url=""
run_dir=""

trap 'stop_stub; rm -rf "$tmp"' EXIT

cat > "$tmp/stub.py" <<'PY'
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

config_path, log_path, port_path = sys.argv[1:4]
config = json.loads(Path(config_path).read_text())
pending = list(config["responses"])
loaded = set(config.get("loaded", []))


def model_entry(name):
    entry = {"id": name, "aliases": [], "source": "preset", "status": {"value": "loaded" if name in loaded else "unloaded"}}
    if name in loaded:
        entry["meta"] = {"n_ctx": config.get("n_ctx", 65536), "size": 1}
    return entry


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def reply(self, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/models":
            names = sorted(set(config.get("models", [])) | loaded)
            self.reply({"data": [model_entry(name) for name in names]})
        elif self.path == "/health":
            self.reply({"status": "ok"})
        else:
            self.send_error(404)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with open(log_path, "a") as log:
            log.write(json.dumps({"path": self.path, "body": body}, sort_keys=True) + "\n")
        if config.get("hangup"):
            return
        if self.path == "/models/load":
            loaded.add(body["model"])
            self.reply({"success": True})
        elif self.path == "/models/unload":
            loaded.discard(body["model"])
            self.reply({"success": True})
        elif self.path == "/v1/messages":
            loaded.add(body["model"])
            input_tokens, cached, seconds = pending.pop(0) if pending else [0, None, 0]
            time.sleep(seconds)
            self.reply({"type": "message", "content": [], "usage": {"input_tokens": input_tokens, "cache_read_input_tokens": cached, "output_tokens": 1}})
        else:
            self.send_error(404)


server = HTTPServer(("127.0.0.1", 0), Handler)
Path(port_path).write_text(str(server.server_port))
server.serve_forever()
PY

cat > "$tmp/first_difference.py" <<'PY'
import json
import sys
from pathlib import Path

log_path, first_line, second_line = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
lines = Path(log_path).read_text().splitlines()
first = json.loads(lines[first_line - 1])["body"]["messages"][0]["content"]
second = json.loads(lines[second_line - 1])["body"]["messages"][0]["content"]
print(next((index for index, (a, b) in enumerate(zip(first, second)) if a != b), min(len(first), len(second))))
PY

start_stub() {
  stop_stub
  run_dir="$(mktemp -d "$tmp/run.XXXXXX")"
  printf '%s' "$1" > "$run_dir/config.json"
  : > "$run_dir/requests.log"
  python3 "$tmp/stub.py" "$run_dir/config.json" "$run_dir/requests.log" "$run_dir/port" 2> "$run_dir/stub.err" &
  stub_pid=$!
  for _ in $(seq 600); do
    [ -s "$run_dir/port" ] && break
    sleep 0.05
  done
  if [ ! -s "$run_dir/port" ]; then
    echo "FAIL: probe stub did not start"
    cat "$run_dir/stub.err"
    failures=$((failures + 1))
    return 1
  fi
  base_url="http://127.0.0.1:$(cat "$run_dir/port")"
}

stop_stub() {
  if [ -n "$stub_pid" ]; then
    kill "$stub_pid" 2>/dev/null
    wait "$stub_pid" 2>/dev/null
    stub_pid=""
  fi
}

probe_output() {
  MODEL_LOAD_POLL=0.01 MODEL_LOAD_TIMEOUT=5 "$probe" --base-url "$base_url" "$@"
}

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

has_row() { printf '%s\n' "$1" | grep -Eq -- "$2"; }
lacks_row() { ! has_row "$1" "$2"; }
lacks_warning() { ! grep -q warning "$1"; }
lacks_text() { ! grep -qF -- "$2" "$1"; }
appears_after() {
  local first second
  first="$(printf '%s\n' "$1" | grep -nE -- "$2" | head -1 | cut -d: -f1)"
  second="$(printf '%s\n' "$1" | grep -nF -- "$3" | head -1 | cut -d: -f1)"
  [ -n "$first" ] && [ -n "$second" ] && [ "$second" -gt "$first" ]
}
request_has() { printf '%s\n' "$1" | grep -qF -- "$2"; }
request_at() { sed -n "${1}p" "$run_dir/requests.log"; }
path_at() { request_at "$1" | jq -r .path; }
first_difference() { python3 "$tmp/first_difference.py" "$run_dir/requests.log" "$1" "$2"; }
in_range() { [ "$1" -ge "$2" ] && [ "$1" -lt "$3" ]; }
json_check() {
  printf '%s' "$1" | python3 -c "import json, sys; data = json.load(sys.stdin); sys.exit(0 if ($2) else 1)"
}
prompt_under() {
  grep '"/v1/messages"' "$1" | head -1 | python3 -c "import json, sys; body = json.loads(sys.stdin.read())['body']; sys.exit(0 if max(len(m['content']) for m in body['messages']) < $2 else 1)"
}

model_27b="$(jq -r '.["27b"].model' "$repo_dir/ollama/sizes.json")"
table_config="{\"models\": [\"$model_27b\"], \"responses\": [[1000, 0, 0], [60, 964, 0], [40, 960, 0], [250, 750, 0], [1000, 0, 0], [1000, 0, 0], [5, 0, 0], [1000, 0, 0]]}"
start_stub "$table_config"
table="$(probe_output 2> "$tmp/table.err")"
check "table prints a header line" has_row "$table" "^scenario +prompt +evaluated +hit % +prefill s$"
check "table names the hit % basis" has_row "$table" "^hit % basis: uncached token count$"
check "cold row shows the full prefill" has_row "$table" "^Cold +1000 +1000 +0\.0 +[0-9]+\.[0-9]{2}$"
check "growing chat row estimates its own prompt total" has_row "$table" "^Growing chat +~1024 +60 +94\.1 "
check "same prefix row computes hit rate" has_row "$table" "^Same prefix +1000 +40 +96\.0 "
check "late edit row computes hit rate" has_row "$table" "^Late edit +1000 +250 +75\.0 "
check "early edit row shows no reuse" has_row "$table" "^Early edit +1000 +1000 +0\.0 "
check "eviction row shows no reuse" has_row "$table" "^Eviction +1000 +1000 +0\.0 "
check "there is no side model row" lacks_row "$table" "^Side model"
check "normal counts print no warnings" lacks_warning "$tmp/table.err"
check "progress names the first scenario on stderr" grep -qF "[1/6] Cold" "$tmp/table.err"
check "progress names the last scenario on stderr" grep -qF "[6/6] Eviction" "$tmp/table.err"
check "progress says the cold step reloads the model" grep -qF "unloading and reloading the model" "$tmp/table.err"
check "progress reports how long each step took" grep -qE "done in [0-9]+\.[0-9] s" "$tmp/table.err"
check "an unloaded model gets no loaded note" lacks_text "$tmp/table.err" "already loaded"
check "progress stays off stdout" lacks_row "$table" "^\[1/6\]"
check "the cold scenario loads the model before it asks" [ "$(path_at 1)" = /models/load ]
check "the default preset is the 27b's" [ "$(request_at 2 | jq -r .body.model)" = "$model_27b" ]
check "scenarios use the messages API" [ "$(path_at 2)" = /v1/messages ]
check "requests are not streamed" [ "$(request_at 2 | jq -r .body.stream)" = false ]
check "requests ask for one token" [ "$(request_at 2 | jq -r .body.max_tokens)" = 1 ]
check "no Ollama route is asked" lacks_text "$run_dir/requests.log" '"/api/'
check "the settings name the loaded context" has_row "$table" "n_ctx: 65536"
check "the settings name the server" has_row "$table" "^server: $base_url$"
check "growing chat sends an assistant turn" request_has "$(request_at 3)" '"role": "assistant"'
check "same prefix request follows the cold prefix" [ "$(first_difference 4 2)" -ge 80000 ]
late_at="$(first_difference 5 4)"
check "late edit changes the prompt after 70 percent" in_range "$late_at" 56000 80000
early_at="$(first_difference 6 4)"
check "early edit changes the first 10 percent" in_range "$early_at" 0 8000
check "verdict says the cache works" has_row "$table" "^Cache: works"
check "verdict says the growing chat is reused" has_row "$table" "^Growing chat: reused"
check "verdict says the eviction wiped the cache" has_row "$table" "^Eviction: .*wiped"
check "a failed eviction suggests more cache RAM after the table" appears_after "$table" "^Eviction +" "cache-ram"
check "no verdict names an Ollama variable" lacks_row "$table" "OLLAMA_"

start_stub "{\"models\": [\"$model_27b\"], \"loaded\": [\"$model_27b\"], \"responses\": []}"
probe_output > /dev/null 2> "$tmp/loaded.err"
check "a loaded model gets a note before the run" grep -qF "$model_27b is already loaded" "$tmp/loaded.err"
check "the loaded note says other requests make the probe wait" grep -qF "close other sessions" "$tmp/loaded.err"
check "the cold scenario unloads a loaded model" [ "$(path_at 1)" = /models/unload ]
check "and then loads it again" [ "$(path_at 2)" = /models/load ]

start_stub "$table_config"
json_output="$(probe_output --json 2>/dev/null)"
check "json output has six scenarios, basis and hit percent" json_check "$json_output" "len(data['scenarios']) == 6 and data['hit_basis'] == 'token_count' and data['scenarios'][2]['hit_percent'] == 96.0"
check "json marks the growing chat total as estimated" json_check "$json_output" "data['scenarios'][1]['prompt_tokens_estimated'] is True and data['scenarios'][1]['prompt_tokens'] == 1024"
check "json says whether the same prefix reused the cache" json_check "$json_output" "data['cache_reused'] is True"
check "json names the preset and its context" json_check "$json_output" "data['model'] == '$model_27b' and data['n_ctx'] == 65536"

start_stub "{\"models\": [\"$model_27b\"], \"responses\": [[1000, 0, 0], [60, 964, 0], [40, 960, 0], [250, 750, 0], [1000, 0, 0], [1000, 0, 0], [5, 0, 0], [40, 960, 0]]}"
kept_table="$(probe_output 2>/dev/null)"
check "a surviving eviction suggests nothing" lacks_row "$kept_table" "cache-ram"
check "a surviving eviction says the cache survived" has_row "$kept_table" "^Eviction: the cache survived"

start_stub "{\"models\": [\"$model_27b\"], \"responses\": [[1000, null, 0.4], [1000, null, 0.4], [1000, null, 0.04], [1000, null, 0.04], [1000, null, 0.4], [1000, null, 0.4], [5, null, 0], [1000, null, 0.4]]}"
time_table="$(probe_output 2> "$tmp/time.err")"
check "full counts switch the hit % basis to prefill time" has_row "$time_table" "^hit % basis: prefill time per token vs Cold$"
check "full counts are scored by prefill time per token" has_row "$time_table" "^Same prefix +1000 +1000 +[5-9][0-9]\.[0-9] "
check "full counts print a warning on stderr" grep -q "full prompt counts" "$tmp/time.err"

start_stub "{\"models\": [\"$model_27b\"], \"responses\": [[1000, 0, 0], [1000, 0, 0], [1000, 0, 0], [1000, 0, 0], [1000, 0, 0], [1000, 0, 0], [5, 0, 0], [1000, 0, 0]]}"
broken_table="$(probe_output 2>/dev/null)"
check "verdict says when the cache is not reused" has_row "$broken_table" "^Cache: NOT reused"
check "a broken cache names the server settings" has_row "$broken_table" "cache-reuse"
check "a broken cache no longer suggests a GGUF build" lacks_row "$broken_table" "GGUF"
check "verdict says when a growing chat is not reused" has_row "$broken_table" "^Growing chat: NOT reused"

start_stub "{\"models\": [\"$model_27b\"], \"responses\": [[1000, 0, 0], [2000, 0, 0], [40, 960, 0], [250, 750, 0], [1000, 0, 0], [1000, 0, 0], [5, 0, 0], [1000, 0, 0]]}"
negative_table="$(probe_output 2> "$tmp/negative.err")"
check "rows that evaluate more than their prompt show a negative hit" has_row "$negative_table" "^Growing chat +~1024 +2000 +-95\.3 "
check "negative hits print a warning on stderr" grep -q "hit % is negative" "$tmp/negative.err"

start_stub '{"models": ["custom-cc@32768"], "responses": []}'
probe_output custom-cc@32768 > /dev/null 2>&1
check "the argument is the preset id" [ "$(request_at 2 | jq -r .body.model)" = custom-cc@32768 ]

start_stub '{"models": [], "responses": []}'
probe_output --prefix-tokens 10 > /dev/null 2>&1
first_log="$(cat "$run_dir/requests.log")"
check "prefix-tokens sets a short prompt" prompt_under "$run_dir/requests.log" 200
start_stub '{"models": [], "responses": []}'
probe_output --prefix-tokens 10 > /dev/null 2>&1
second_log="$(cat "$run_dir/requests.log")"
check "identical runs send identical requests" [ "$first_log" = "$second_log" ]

start_stub '{"models": [], "responses": [], "hangup": true}'
hangup_status=0
probe_output > /dev/null 2> "$tmp/hangup.err" || hangup_status=$?
check "a dropped connection exits non-zero" [ "$hangup_status" -ne 0 ]
check "a dropped connection gets a clear message" grep -q "request to llama-server at" "$tmp/hangup.err"

unreachable_status=0
"$probe" --base-url http://127.0.0.1:9 > /dev/null 2> "$tmp/unreachable.err" || unreachable_status=$?
check "unreachable server exits non-zero" [ "$unreachable_status" -ne 0 ]
check "unreachable server gets a clear message" grep -q "cannot reach llama-server at http://127.0.0.1:9" "$tmp/unreachable.err"

LLAMA_SERVER_URL="$base_url" "$probe" --help > "$tmp/help.out" 2>&1
check "the default server is LLAMA_SERVER_URL" grep -qF "$base_url" "$tmp/help.out"
check "the help names a preset, not a size" grep -qF "preset" "$tmp/help.out"

cat > "$tmp/replay_dir.py" <<'PY'
import json
import os
import sys
from pathlib import Path

folder = Path(sys.argv[1])
folder.mkdir()
turns = [("zzz-first", 100, "first recorded turn"), ("aaa-second", 200, "second recorded turn"), ("mmm-third", 300, "third recorded turn")]
for name, age, turn in turns:
    path = folder / f"{name}.json"
    path.write_text(json.dumps({"model": "recorded", "max_tokens": 50, "stream": True, "system": "be terse", "messages": [{"role": "user", "content": turn}]}))
    os.utime(path, (1_700_000_000 + age, 1_700_000_000 + age))
PY
python3 "$tmp/replay_dir.py" "$tmp/replay"
replay_turns() { grep -o '"content": "[a-z]* recorded turn"' "$run_dir/requests.log" | tr '\n' ' '; }

replay_config="{\"models\": [\"$model_27b\"], \"loaded\": [\"$model_27b\"], \"responses\": [[1000, 0, 0], [110, 900, 0], [820, 200, 0]]}"
start_stub "$replay_config"
replay_table="$(probe_output --replay "$tmp/replay" 2> "$tmp/replay.err")"
replay_status=$?
check "--replay exits 0" [ "$replay_status" -eq 0 ]
check "--replay unloads the model before the first body" [ "$(path_at 1)" = /models/unload ]
check "--replay loads it again before the first body" [ "$(path_at 2)" = /models/load ]
check "--replay sends the bodies in ts order" [ "$(replay_turns)" = '"content": "first recorded turn" "content": "second recorded turn" "content": "third recorded turn" ' ]
check "--replay substitutes the preset" [ "$(request_at 3 | jq -r .body.model)" = "$model_27b" ]
check "--replay keeps the system prompt" [ "$(request_at 3 | jq -r .body.system)" = "be terse" ]
check "--replay asks for one token without streaming" [ "$(request_at 3 | jq -c '[.body.max_tokens, .body.stream]')" = '[1,false]' ]
check "--replay names the first body as the baseline" has_row "$replay_table" "^zzz-first +1000 +0 +- "
check "--replay scores each next body by its cached tokens" has_row "$replay_table" "^aaa-second +1010 +900 +89\.1 "
check "--replay scores a weak reuse" has_row "$replay_table" "^mmm-third +1020 +200 +19\.6 "
check "--replay prints a verdict" has_row "$replay_table" "^Replay: 1 of 2 consecutive requests reused the cache"

start_stub "$replay_config"
replay_json="$(probe_output --replay "$tmp/replay" --json 2>/dev/null)"
check "--replay --json lists one row per body" [ "$(printf '%s' "$replay_json" | jq '.replay | length')" = 3 ]
check "--replay --json carries the request id and hit" [ "$(printf '%s' "$replay_json" | jq -c '.replay[1] | [.request_id, .hit_percent]')" = '["aaa-second",89.1]' ]
check "--replay --json counts the reused pairs" [ "$(printf '%s' "$replay_json" | jq -c '[.reused_pairs, .pairs]')" = '[1,2]' ]

mkdir "$tmp/empty-replay"
empty_status=0
probe_output --replay "$tmp/empty-replay" > /dev/null 2> "$tmp/empty.err" || empty_status=$?
check "an empty replay dir exits 1" [ "$empty_status" -eq 1 ]
check "an empty replay dir says so" grep -q "no .json bodies" "$tmp/empty.err"

stop_stub
if [ "$failures" -ne 0 ]; then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
