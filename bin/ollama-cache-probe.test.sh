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
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

config_path, log_path, port_path = sys.argv[1:4]
config = json.loads(Path(config_path).read_text())
pending = list(config["responses"])


def chat_reply(count, seconds):
    return {
        "model": "stub",
        "done": True,
        "message": {"role": "assistant", "content": ""},
        "prompt_eval_count": count,
        "prompt_eval_duration": int(seconds * 1000000000),
    }


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
        if self.path == "/api/tags":
            self.reply({"models": [{"name": name} for name in config["tags"]]})
        elif self.path == "/api/ps":
            self.reply({"models": []})
        else:
            self.send_error(404)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with open(log_path, "a") as log:
            log.write(json.dumps(body, sort_keys=True) + "\n")
        if config.get("hangup"):
            return
        if body.get("messages") == []:
            self.reply({"done": True})
        else:
            self.reply(chat_reply(*(pending.pop(0) if pending else [0, 0.0])))


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
first = json.loads(lines[first_line - 1])["messages"][0]["content"]
second = json.loads(lines[second_line - 1])["messages"][0]["content"]
print(next((index for index, (a, b) in enumerate(zip(first, second)) if a != b), min(len(first), len(second))))
PY

start_stub() {
  stop_stub
  run_dir="$(mktemp -d "$tmp/run.XXXXXX")"
  printf '%s' "$1" > "$run_dir/config.json"
  python3 "$tmp/stub.py" "$run_dir/config.json" "$run_dir/requests.log" "$run_dir/port" &
  stub_pid=$!
  for _ in $(seq 200); do
    [ -s "$run_dir/port" ] && break
    sleep 0.05
  done
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
  "$probe" --base-url "$base_url" "$@"
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
request_has() { printf '%s\n' "$1" | grep -qF -- "$2"; }
logged() { grep -qF -- "$1" "$run_dir/requests.log"; }
request_at() { sed -n "${1}p" "$run_dir/requests.log"; }
first_difference() { python3 "$tmp/first_difference.py" "$run_dir/requests.log" "$1" "$2"; }
in_range() { [ "$1" -ge "$2" ] && [ "$1" -lt "$3" ]; }
json_check() {
  printf '%s' "$1" | python3 -c "import json, sys; data = json.load(sys.stdin); sys.exit(0 if ($2) else 1)"
}
prompt_under() {
  printf '%s\n' "$1" | sed -n 2p | python3 -c "import json, sys; body = json.loads(sys.stdin.read()); sys.exit(0 if max(len(m['content']) for m in body['messages']) < $2 else 1)"
}

table_config='{"tags": ["qwen3.8-27b-cc", "qwen3.5:4b"], "responses": [[1000, 2.0], [60, 0.12], [40, 0.08], [250, 0.5], [1000, 2.0], [1000, 2.0], [5, 0.01], [1000, 2.0], [5, 0.01], [30, 0.06]]}'
start_stub "$table_config"
table="$(probe_output 27b 2> "$tmp/table.err")"
check "table prints a header line" has_row "$table" "^scenario +prompt +evaluated +hit % +prefill s$"
check "table names the hit % basis" has_row "$table" "^hit % basis: uncached token count$"
check "cold row shows the full prefill" has_row "$table" "^Cold +1000 +1000 +0\.0 +2\.00$"
check "growing chat row estimates its own prompt total" has_row "$table" "^Growing chat +~1024 +60 +94\.1 +0\.12$"
check "same prefix row computes hit rate" has_row "$table" "^Same prefix +1000 +40 +96\.0 +0\.08$"
check "late edit row computes hit rate" has_row "$table" "^Late edit +1000 +250 +75\.0 +0\.50$"
check "early edit row shows no reuse" has_row "$table" "^Early edit +1000 +1000 +0\.0 +2\.00$"
check "eviction row shows no reuse" has_row "$table" "^Eviction +1000 +1000 +0\.0 +2\.00$"
check "side model row computes hit rate" has_row "$table" "^Side model +1000 +30 +97\.0 +0\.06$"
check "normal counts print nothing on stderr" [ ! -s "$tmp/table.err" ]
check "cold scenario unloads the model first" logged '"keep_alive": 0'
check "requests use the -cc model from the size profile" logged '"model": "qwen3.8-27b-cc"'
check "requests are not streamed" logged '"stream": false'
check "requests set num_ctx" logged '"num_ctx": 65536'
check "growing chat sends an assistant turn" request_has "$(request_at 3)" '"role": "assistant"'
check "same prefix request follows the cold prefix" [ "$(first_difference 4 2)" -ge 80000 ]
late_at="$(first_difference 5 4)"
check "late edit changes the prompt after 70 percent" in_range "$late_at" 56000 80000
early_at="$(first_difference 6 4)"
check "early edit changes the first 10 percent" in_range "$early_at" 0 8000
check "reminds that OLLAMA_NUM_PARALLEL needs a restart" has_row "$table" "OLLAMA_NUM_PARALLEL"

start_stub "$table_config"
json_output="$(probe_output --json 27b)"
check "json output has seven scenarios, basis and hit percent" json_check "$json_output" "len(data['scenarios']) == 7 and data['hit_basis'] == 'token_count' and data['scenarios'][2]['hit_percent'] == 96.0"
check "json marks the growing chat total as estimated" json_check "$json_output" "data['scenarios'][1]['prompt_tokens_estimated'] is True and data['scenarios'][1]['prompt_tokens'] == 1024"

start_stub '{"tags": ["qwen3.8-27b-cc"], "responses": [[1000, 2.0], [60, 0.12], [40, 0.08], [250, 0.5], [1000, 2.0], [1000, 2.0], [5, 0.01], [1000, 2.0]]}'
no_side_table="$(probe_output 27b)"
check "side model row is skipped when the model is not pulled" [ "$(printf '%s\n' "$no_side_table" | grep -c '^Side model')" -eq 0 ]
check "skipping the side model still prints the cold row" has_row "$no_side_table" "^Cold +1000 +1000 +0\.0 +2\.00$"

start_stub '{"tags": ["qwen3.8-27b-cc"], "responses": [[1000, 2.0], [60, 0.12], [1000, 0.2], [1000, 0.2], [1000, 2.0], [1000, 2.0], [5, 0.01], [1000, 2.0]]}'
time_table="$(probe_output 27b 2> "$tmp/time.err")"
check "full counts switch the hit % basis to prefill time" has_row "$time_table" "^hit % basis: prefill time per token vs Cold$"
check "full counts are scored by prefill time per token" has_row "$time_table" "^Same prefix +1000 +1000 +90\.0 +0\.20$"
check "full counts print a warning on stderr" grep -q "full prompt counts" "$tmp/time.err"

start_stub '{"tags": ["qwen3.8-27b-cc"], "responses": [[1000, 2.0], [2000, 0.12], [40, 0.08], [250, 0.5], [1000, 2.0], [1000, 2.0], [5, 0.01], [1000, 2.0]]}'
negative_table="$(probe_output 27b 2> "$tmp/negative.err")"
check "rows that evaluate more than their prompt show a negative hit" has_row "$negative_table" "^Growing chat +~1024 +2000 +-95\.3 +0\.12$"
check "negative hits print a warning on stderr" grep -q "hit % is negative" "$tmp/negative.err"

start_stub '{"tags": ["fake-cc", "custom:tag"], "responses": []}'
fake="$tmp/fake"
mkdir -p "$fake/bin" "$fake/ollama"
cp "$probe" "$fake/bin/"
printf '{"model": "fake-cc"}' > "$fake/ollama/settings.xx.json"
printf 'FROM base\n' > "$fake/ollama/Modelfile.xx"
printf '{}' > "$fake/ollama/settings.yy.json"
printf 'FROM base\n' > "$fake/ollama/Modelfile.yy"
"$fake/bin/ollama-cache-probe" --base-url "$base_url" --side-model none xx > /dev/null
check "a configured size resolves through its settings file" logged '"model": "fake-cc"'

missing_status=0
"$fake/bin/ollama-cache-probe" --base-url "$base_url" --side-model none yy > /dev/null 2> "$tmp/missing.err" || missing_status=$?
check "a settings file without a model key exits non-zero" [ "$missing_status" -eq 1 ]
check "a settings file without a model key says so" grep -q 'has no "model" key' "$tmp/missing.err"

start_stub '{"tags": ["custom:tag"], "responses": []}'
"$probe" --base-url "$base_url" --side-model none custom:tag > /dev/null
check "an unknown argument is used as the model name" logged '"model": "custom:tag"'

start_stub '{"tags": [], "responses": []}'
"$probe" --base-url "$base_url" --side-model none --prefix-tokens 10 27b > /dev/null
first_log="$(cat "$run_dir/requests.log")"
start_stub '{"tags": [], "responses": []}'
"$probe" --base-url "$base_url" --side-model none --prefix-tokens 10 27b > /dev/null
second_log="$(cat "$run_dir/requests.log")"
check "identical runs send identical requests" [ "$first_log" = "$second_log" ]
check "prefix-tokens sets a short prompt" prompt_under "$first_log" 200

start_stub '{"tags": [], "responses": [], "hangup": true}'
hangup_status=0
probe_output 27b > /dev/null 2> "$tmp/hangup.err" || hangup_status=$?
check "a dropped connection exits non-zero" [ "$hangup_status" -ne 0 ]
check "a dropped connection gets a clear message" grep -q "request to Ollama at" "$tmp/hangup.err"

unreachable_status=0
"$probe" --base-url http://127.0.0.1:9 27b > /dev/null 2> "$tmp/unreachable.err" || unreachable_status=$?
check "unreachable server exits non-zero" [ "$unreachable_status" -ne 0 ]
check "unreachable server gets a clear message" grep -q "cannot reach Ollama" "$tmp/unreachable.err"

stop_stub
[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
