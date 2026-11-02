#!/usr/bin/env bash
set -u
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
proxy="$repo_dir/bin/messages-proxy"
tmp="$(mktemp -d)"
failures=0
upstream_pid=""
proxy_pid=""
sleeper_pid=""
upstream_url=""
proxy_url=""
run_dir=""

trap 'stop_proxy; stop_upstream; stop_sleeper; rm -rf "$tmp"' EXIT

cat > "$tmp/upstream.py" <<'PY'
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

log_path, port_path = sys.argv[1:3]


def sse(kind, **fields):
    payload = dict(type=kind, **fields)
    return f"event: {kind}\ndata: {json.dumps(payload)}\n\n".encode("utf-8")


REPLY = [
    sse("message_start", message={"id": "msg_stub", "role": "assistant", "usage": {"input_tokens": 7}}),
    sse("content_block_start", index=0, content_block={"type": "text", "text": ""}),
    sse("content_block_delta", index=0, delta={"type": "text_delta", "text": "hello"}),
    sse("content_block_stop", index=0),
    sse("message_delta", delta={"stop_reason": "end_turn"}, usage={"output_tokens": 1}),
    sse("message_stop"),
]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        return

    def record(self, body):
        record = {
            "method": self.command,
            "path": self.path,
            "headers": {key.lower(): value for key, value in self.headers.items()},
            "body": body.decode("utf-8"),
        }
        with open(log_path, "a") as log:
            log.write(json.dumps(record) + "\n")

    def do_GET(self):
        if self.path != "/":
            self.record(b"")
        payload = json.dumps({"version": "stub"}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        self.record(body)
        if self.path != "/v1/messages":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        for chunk in REPLY:
            self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
            self.wfile.flush()
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()


server = HTTPServer(("127.0.0.1", 0), Handler)
Path(port_path).write_text(str(server.server_port))
server.serve_forever()
PY

cat > "$tmp/send.py" <<'PY'
import sys
import urllib.request

url, body_path, out_path = sys.argv[1:4]
body = open(body_path, "rb").read()
request = urllib.request.Request(url, data=body, method="POST")
request.add_header("Content-Type", "application/json")
request.add_header("x-api-key", "local")
request.add_header("anthropic-version", "2023-06-01")
with urllib.request.urlopen(request, timeout=10) as reply:
    open(out_path, "wb").write(reply.read())
PY

cat > "$tmp/body.py" <<'PY'
import json
import sys

date, last = sys.argv[1:3]
body = {
    "model": "stub",
    "max_tokens": 16,
    "stream": True,
    "system": [
        {"type": "text", "text": "You are a terse assistant."},
        {"type": "text", "text": f"Today is {date}."},
    ],
    "tools": [{"name": "read_file", "description": "Read a file.", "input_schema": {"type": "object"}}],
    "messages": [
        {"role": "user", "content": "first"},
        {"role": "assistant", "content": [{"type": "text", "text": "ok"}]},
        {"role": "user", "content": last},
    ],
}
sys.stdout.write(json.dumps(body, indent=1))
PY

cat > "$tmp/system_offset.py" <<'PY'
import json
import sys

old, new = (json.dumps(json.loads(open(path).read())["system"], sort_keys=True, separators=(",", ":")) for path in sys.argv[1:3])
print(next(index for index, (a, b) in enumerate(zip(old, new)) if a != b))
PY

start_upstream() {
  run_dir="$(mktemp -d "$tmp/run.XXXXXX")"
  python3 "$tmp/upstream.py" "$run_dir/upstream.log" "$run_dir/upstream.port" 2> "$run_dir/upstream.err" &
  upstream_pid=$!
  wait_for_file "$run_dir/upstream.port" || { echo "FAIL: upstream stub did not start"; cat "$run_dir/upstream.err"; failures=$((failures + 1)); return 1; }
  upstream_url="http://127.0.0.1:$(cat "$run_dir/upstream.port")"
}

stop_upstream() {
  [ -n "$upstream_pid" ] || return 0
  kill "$upstream_pid" 2>/dev/null
  wait "$upstream_pid" 2>/dev/null
  upstream_pid=""
}

free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'
}

start_proxy() {
  local port
  port="$(free_port)"
  proxy_url="http://127.0.0.1:$port"
  "$proxy" --upstream "$upstream_url" --port "$port" --log "$run_dir/proxy/requests.jsonl" "$@" 2> "$run_dir/proxy.err" &
  proxy_pid=$!
  wait_for_url "$proxy_url/" || { echo "FAIL: proxy did not start"; cat "$run_dir/proxy.err"; failures=$((failures + 1)); return 1; }
}

stop_proxy() {
  [ -n "$proxy_pid" ] || return 0
  kill "$proxy_pid" 2>/dev/null
  wait "$proxy_pid" 2>/dev/null
  proxy_pid=""
}

stop_sleeper() {
  [ -n "$sleeper_pid" ] || return 0
  kill "$sleeper_pid" 2>/dev/null
  wait "$sleeper_pid" 2>/dev/null
  sleeper_pid=""
}

wait_for_file() {
  for _ in $(seq 100); do
    [ -s "$1" ] && return 0
    sleep 0.05
  done
  return 1
}

wait_for_url() {
  for _ in $(seq 100); do
    curl -sf -o /dev/null "$1" && return 0
    sleep 0.05
  done
  return 1
}

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

send() {
  python3 "$tmp/send.py" "$proxy_url/v1/messages" "$1" "$2"
}

log_row() { sed -n "${1}p" "$run_dir/proxy/requests.jsonl"; }
upstream_row() { sed -n "${1}p" "$run_dir/upstream.log"; }
row_field() { printf '%s' "$1" | jq -r "$2"; }
row_count() { wc -l < "$run_dir/proxy/requests.jsonl" | tr -d ' '; }
upstream_body_is() { [ "$(printf '%s' "$(upstream_row "$1")" | jq -r .body)" = "$(cat "$2")" ]; }
mode_of() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
diff_has() { row_field "$(log_row "$1")" .diff | grep -q -- "$2"; }
lacks_text() { ! grep -q -- "$1" "$2"; }

start_upstream && start_proxy

python3 "$tmp/body.py" "Sunday 2026-11-01" "hello" > "$run_dir/first.json"
python3 "$tmp/body.py" "Monday 2026-11-02" "hello" > "$run_dir/second.json"
python3 "$tmp/body.py" "Monday 2026-11-02" "goodbye" > "$run_dir/third.json"

send "$run_dir/first.json" "$run_dir/first.out"
send "$run_dir/second.json" "$run_dir/second.out"
check "the first body reaches the upstream byte-for-byte" upstream_body_is 1 "$run_dir/first.json"
check "the second body reaches the upstream byte-for-byte" upstream_body_is 2 "$run_dir/second.json"
check "the forwarded request keeps the api key" [ "$(row_field "$(upstream_row 1)" '.headers["x-api-key"]')" = local ]
check "the forwarded request keeps the anthropic version" [ "$(row_field "$(upstream_row 1)" '.headers["anthropic-version"]')" = 2023-06-01 ]
check "the forwarded request carries the request id" [ "$(row_field "$(upstream_row 1)" '.headers["x-claude-ollama-request"]')" = "$(row_field "$(log_row 1)" .request_id)" ]
check "the first row has no divergence" [ "$(row_field "$(log_row 1)" .diverged_at)" = null ]
check "the first row has no stable sections" [ "$(row_field "$(log_row 1)" .stable_sections)" = 0 ]
check "the first row counts the sections" [ "$(row_field "$(log_row 1)" .sections)" = 5 ]
check "the first row records the body size" [ "$(row_field "$(log_row 1)" .prompt_bytes)" = "$(wc -c < "$run_dir/first.json" | tr -d ' ')" ]
check "a date change diverges at the system prompt" [ "$(row_field "$(log_row 2)" .diverged_at)" = system ]
check "the system divergence names the first differing byte" [ "$(row_field "$(log_row 2)" .offset)" = "$(python3 "$tmp/system_offset.py" "$run_dir/first.json" "$run_dir/second.json")" ]
check "the diff shows the new date" diff_has 2 "Monday 2026-11-02"
check "the diff stays short" [ "$(row_field "$(log_row 2)" '.diff | length')" -le 200 ]
check "a system change leaves no stable sections" [ "$(row_field "$(log_row 2)" .stable_sections)" = 0 ]
check "every row has a timestamp" [ "$(row_field "$(log_row 2)" .ts)" != null ]
check "the log never holds the whole prompt" lacks_text "terse assistant" "$run_dir/proxy/requests.jsonl"

send "$run_dir/third.json" "$run_dir/third.out"
check "a last-message change diverges at that message" [ "$(row_field "$(log_row 3)" .diverged_at)" = message:2 ]
check "everything before the last message stays stable" [ "$(row_field "$(log_row 3)" .stable_sections)" = 4 ]
check "the diff shows the new message text" diff_has 3 goodbye

send "$run_dir/third.json" "$run_dir/fourth.out"
check "an identical body has no divergence" [ "$(row_field "$(log_row 4)" .diverged_at)" = null ]
check "an identical body keeps every section stable" [ "$(row_field "$(log_row 4)" .stable_sections)" = 5 ]
check "an identical body has no offset" [ "$(row_field "$(log_row 4)" .offset)" = null ]

check "the SSE reply passes through intact" grep -q '^event: message_stop' "$run_dir/first.out"
check "the SSE reply keeps every delta" grep -q '"text": "hello"' "$run_dir/first.out"
check "the SSE reply carries the stream content type" sh -c "curl -s -D - -o /dev/null -X POST -H 'Content-Type: application/json' --data-binary @'$run_dir/first.json' '$proxy_url/v1/messages' | grep -qi '^content-type: text/event-stream'"

curl -sf "$proxy_url/api/version" > "$run_dir/version.out"
check "other paths forward to the upstream" grep -q '"version": "stub"' "$run_dir/version.out"
check "other paths write no log row" [ "$(row_count)" = 5 ]
check "the upstream saw the other path" [ "$(row_field "$(upstream_row 6)" .path)" = /api/version ]

check "the log file is private" [ "$(mode_of "$run_dir/proxy/requests.jsonl")" = 600 ]
check "the log folder is private" [ "$(mode_of "$run_dir/proxy")" = 700 ]

stop_proxy
"$proxy" --upstream "$upstream_url" --port 0 --port-file "$run_dir/proxy.port" --log "$run_dir/proxy/requests.jsonl" 2> "$run_dir/proxy.err" &
proxy_pid=$!
check "port 0 publishes the bound port" wait_for_file "$run_dir/proxy.port"
check "the published port answers" wait_for_url "http://127.0.0.1:$(cat "$run_dir/proxy.port" 2>/dev/null || echo 1)/"
check "the port file is private" [ "$(mode_of "$run_dir/proxy.port")" = 600 ]
stop_proxy
sleep 30 &
sleeper_pid=$!
start_proxy --watch-pid "$sleeper_pid"
stop_sleeper
for _ in $(seq 100); do
  kill -0 "$proxy_pid" 2>/dev/null || break
  sleep 0.1
done
check "the proxy exits when the watched pid dies" sh -c "! kill -0 $proxy_pid 2>/dev/null"
proxy_pid=""

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
