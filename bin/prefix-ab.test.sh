#!/usr/bin/env bash
set -u
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
prefix_ab="$repo_dir/bin/prefix-ab"
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

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with open(log_path, "a") as log:
            log.write(json.dumps(body, sort_keys=True) + "\n")
        if self.path == "/v1/messages":
            input_tokens, cached = pending.pop(0) if pending else [0, None]
            self.reply({"usage": {"input_tokens": input_tokens, "cache_read_input_tokens": cached, "output_tokens": 1}})
        else:
            self.reply({"done": True})


server = HTTPServer(("127.0.0.1", 0), Handler)
Path(port_path).write_text(str(server.server_port))
server.serve_forever()
PY

cat > "$tmp/record_dir.py" <<'PY'
import json
import os
import sys
from pathlib import Path

folder = Path(sys.argv[1])
folder.mkdir()
turns = [("zzz-first", 100, "Sunday 2026-11-01", "first turn"), ("aaa-second", 200, "Monday 2026-11-02", "second turn"), ("mmm-third", 300, "Tuesday 2026-11-03", "third turn")]
for name, age, date, turn in turns:
    system = [
        {"type": "text", "text": f"The session began on {date}."},
        {"type": "text", "text": "You are a terse assistant."},
        {"type": "text", "text": "Keep replies short."},
    ]
    body = {"model": "recorded", "max_tokens": 50, "stream": True, "system": system, "messages": [{"role": "user", "content": turn}]}
    path = folder / f"{name}.json"
    path.write_text(json.dumps(body))
    os.utime(path, (1_700_000_000 + age, 1_700_000_000 + age))
PY
python3 "$tmp/record_dir.py" "$tmp/record"

start_stub() {
  stop_stub
  run_dir="$(mktemp -d "$tmp/run.XXXXXX")"
  printf '%s' "$1" > "$run_dir/config.json"
  python3 "$tmp/stub.py" "$run_dir/config.json" "$run_dir/requests.log" "$run_dir/port" 2> "$run_dir/stub.err" &
  stub_pid=$!
  for _ in $(seq 600); do
    [ -s "$run_dir/port" ] && break
    sleep 0.05
  done
  if [ ! -s "$run_dir/port" ]; then
    echo "FAIL: stub did not start"
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

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

has_row() { printf '%s\n' "$1" | grep -Eq -- "$2"; }
request_at() { sed -n "${1}p" "$run_dir/requests.log"; }
request_count() { wc -l < "$run_dir/requests.log" | tr -d ' '; }
system_texts_at() { request_at "$1" | jq -c '[.system[].text]'; }
run_ab() { "$prefix_ab" --record "$tmp/record" --model qwen3.8-27b-cc --base-url "$base_url" "$@"; }

original_system='["The session began on Monday 2026-11-02.","You are a terse assistant.","Keep replies short."]'
stabilized_system='["You are a terse assistant.","Keep replies short.\nThe session began on Monday 2026-11-02."]'

start_stub '{"responses": [[1000, 0], [1010, 100], [1020, 100], [1000, 0], [1010, 900], [1020, 950]]}'
table="$(run_ab 2> "$tmp/table.err")"
status=$?
check "exits 0" [ "$status" -eq 0 ]
check "sends an unload, three bodies, an unload and three bodies" [ "$(request_count)" = 8 ]
check "unloads the model before the verbatim pass" [ "$(request_at 1 | jq -r .keep_alive)" = 0 ]
check "unloads the model before the stabilized pass" [ "$(request_at 5 | jq -r .keep_alive)" = 0 ]
check "the verbatim pass sends the recorded system untouched" [ "$(system_texts_at 3)" = "$original_system" ]
check "the stabilized pass moves the volatile line after the stable prefix" [ "$(system_texts_at 7)" = "$stabilized_system" ]
check "the stabilized pass keeps the messages" [ "$(request_at 7 | jq -r '.messages[0].content')" = "second turn" ]
check "bodies go in ts order" [ "$(request_at 2 | jq -r '.messages[0].content')" = "first turn" ]
check "the model is substituted" [ "$(request_at 2 | jq -r .model)" = qwen3.8-27b-cc ]
check "one token without streaming" [ "$(request_at 2 | jq -c '[.max_tokens, .stream]')" = '[1,false]' ]
check "the table names the basis" has_row "$table" "^hit % basis: cached token count"
check "the table has a header" has_row "$table" "^request +verbatim +stabilized"
check "the first request is the baseline in both columns" has_row "$table" "^zzz-first +- +-"
check "each later request shows both hit rates" has_row "$table" "^aaa-second +9\.9 +89\.1"
check "the third request shows both hit rates" has_row "$table" "^mmm-third +9\.8 +93\.1"
check "the mean row averages the later requests" has_row "$table" "^mean +9\.9 +91\.1"
check "the verdict names the gain in points" has_row "$table" "^stabilize: worth it \(\+81 points mean hit rate\)"

start_stub '{"responses": [[1000, 0], [1010, 100], [1020, 100], [1000, 0], [1010, 900], [1020, 950]]}'
report="$(run_ab --json 2>/dev/null)"
check "--json lists one row per body" [ "$(printf '%s' "$report" | jq '.requests | length')" = 3 ]
check "--json carries both hit rates" [ "$(printf '%s' "$report" | jq -c '.requests[1] | [.request_id, .verbatim.hit_percent, .stabilized.hit_percent]')" = '["aaa-second",9.9,89.1]' ]
check "--json carries the means and the gain" [ "$(printf '%s' "$report" | jq -c '[.mean.verbatim, .mean.stabilized, .gain_points]')" = '[9.9,91.1,81]' ]
check "--json carries the verdict" [ "$(printf '%s' "$report" | jq -r .verdict)" = "stabilize: worth it (+81 points mean hit rate)" ]
check "--json names the model and the record dir" [ "$(printf '%s' "$report" | jq -r '[.model, .record_dir] | join(" ")')" = "qwen3.8-27b-cc $tmp/record" ]

start_stub '{"responses": [[1000, 0], [1010, 900], [1020, 900], [1000, 0], [1010, 900], [1020, 900]]}'
same="$(run_ab 2>/dev/null)"
check "equal hit rates are no gain" has_row "$same" "^stabilize: no gain"

start_stub '{"responses": [[1000, 0], [1010, 900], [1020, 900], [1000, 0], [1010, 880], [1020, 880]]}'
worse="$(run_ab 2>/dev/null)"
check "a lower stabilized hit rate is no gain" has_row "$worse" "^stabilize: no gain"

start_stub '{"responses": [[1000, 0], [1010, 100], [1000, 0], [1010, 900]]}'
limited="$(run_ab --limit 2 2>/dev/null)"
check "--limit replays only the first N bodies" [ "$(request_count)" = 6 ]
check "--limit keeps the ts order" [ "$(request_at 3 | jq -r '.messages[0].content')" = "second turn" ]
check "--limit still prints a verdict" has_row "$limited" "^stabilize: worth it"

start_stub '{"responses": [[1000, null], [1010, null], [1020, null], [1000, null], [1010, null], [1020, null]]}'
timed="$(run_ab 2>/dev/null)"
check "without cached counts the basis is prefill time" has_row "$timed" "^hit % basis: prefill time per token vs the first request"
check "without cached counts each later request still gets a number" has_row "$timed" "^aaa-second +-?[0-9]+\.[0-9] +-?[0-9]+\.[0-9]"

mkdir "$tmp/empty"
empty_status=0
run_ab --record "$tmp/empty" > /dev/null 2> "$tmp/empty.err" || empty_status=$?
check "an empty record dir exits 1" [ "$empty_status" -eq 1 ]
check "an empty record dir says so" grep -q "no .json bodies" "$tmp/empty.err"

unreachable_status=0
"$prefix_ab" --record "$tmp/record" --model m --base-url http://127.0.0.1:9 > /dev/null 2> "$tmp/unreachable.err" || unreachable_status=$?
check "an unreachable server exits 1" [ "$unreachable_status" -eq 1 ]
check "an unreachable server gets a clear message" grep -q "cannot reach Ollama" "$tmp/unreachable.err"

stop_stub
if [ "$failures" -ne 0 ]; then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
