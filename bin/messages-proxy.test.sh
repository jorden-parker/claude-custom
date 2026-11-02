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

cat > "$tmp/volatile_body.py" <<'PY'
import json
import sys

layout, opening, date, big, tool_text, last = sys.argv[1:7]
lines = [opening, f"The session began on {date}.", big, "You are a terse assistant.", "Keep replies short."]
lines = [line for line in lines if line]
system = "\n".join(lines) if layout == "string" else [{"type": "text", "text": line} for line in lines]
body = {
    "model": "stub",
    "max_tokens": 16,
    "stream": True,
    "system": system,
    "tools": [{"name": "read_file", "description": tool_text, "input_schema": {"type": "object"}}],
    "messages": [{"role": "user", "content": last}],
}
sys.stdout.write(json.dumps(body, indent=1))
PY

cat > "$tmp/system_prefix.py" <<'PY'
import json
import sys

body = json.loads(open(sys.argv[1]).read())
system = body["system"]
text = system if isinstance(system, str) else "\n".join(block["text"] for block in system)
print(text.rsplit("\n", 1)[0])
PY

cat > "$tmp/system_offset_of.py" <<'PY'
import json
import sys

body = json.loads(open(sys.argv[1]).read())
canonical = json.dumps(body["system"], sort_keys=True, separators=(",", ":"))
print(len(canonical[: canonical.index(sys.argv[2])].encode("utf-8")))
PY

cat > "$tmp/hard_rule_timing.py" <<'PY'
import importlib.machinery
import importlib.util
import sys
import time

loader = importlib.machinery.SourceFileLoader("messages_proxy", sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
proxy = importlib.util.module_from_spec(spec)
loader.exec_module(proxy)
flood = ", " * 5120
started = time.perf_counter()
flooded = proxy.hard_volatile(flood)
elapsed = time.perf_counter() - started
long_date = "Today's date: 2026-11-02 " + "x" * 200
checks = {
    "flood is not volatile": flooded is False,
    "flood returns within a few milliseconds": elapsed < 0.02,
    "a line over 200 chars is skipped": proxy.hard_volatile(long_date) is False,
    "a date-only line still matches": proxy.hard_volatile("Monday, 2 November 2026") is True,
    "a slash date still matches": proxy.hard_volatile("11/02/2026 2:05 pm") is True,
    "a time-only line still matches": proxy.hard_volatile("14:05") is True,
    "a bare number is not a date": proxy.hard_volatile("42") is False,
    "a sentence with a date is not date-only": proxy.hard_volatile("Due on 2026-11-02 at noon") is False,
}
failed = [label for label, passed in checks.items() if not passed]
for label in failed:
    print(f"FAIL: {label} (elapsed {elapsed:.4f}s)")
sys.exit(1 if failed else 0)
PY

cat > "$tmp/section_bytes.py" <<'PY'
import json
import sys

body_path, section = sys.argv[1:3]
body = json.loads(open(body_path).read())
canonical = lambda value: len(json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8"))
if section == "tools":
    print(canonical(body["tools"][0]))
elif section == "messages":
    print(sum(canonical(message) for message in body["messages"]))
else:
    print(canonical(body[section]))
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
    curl -s -o /dev/null "$1" && return 0
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
check "without --stabilize a row has no stabilized key" [ "$(row_field "$(log_row 2)" 'has("stabilized")')" = false ]
check "the ledger prices the system prompt" [ "$(row_field "$(log_row 1)" .ledger.system)" = "$(python3 "$tmp/section_bytes.py" "$run_dir/first.json" system)" ]
check "the ledger prices each tool schema by name" [ "$(row_field "$(log_row 1)" .ledger.tools.read_file)" = "$(python3 "$tmp/section_bytes.py" "$run_dir/first.json" tools)" ]
check "the ledger lists only the request's tools" [ "$(row_field "$(log_row 1)" '.ledger.tools | keys | join(",")')" = read_file ]
check "the ledger prices the messages together" [ "$(row_field "$(log_row 1)" .ledger.messages)" = "$(python3 "$tmp/section_bytes.py" "$run_dir/first.json" messages)" ]
check "the ledger never holds a schema" lacks_text "Read a file" "$run_dir/proxy/requests.jsonl"

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

status_of() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
check "a loopback Host with a port is accepted" [ "$(status_of -H 'Host: localhost:4321' "$proxy_url/api/version")" = 200 ]
check "a bracketed IPv6 loopback Host is accepted" [ "$(status_of -H 'Host: [::1]:4321' "$proxy_url/api/version")" = 200 ]
check "a foreign Host is rejected" [ "$(status_of -H 'Host: evil.example:80' "$proxy_url/api/version")" = 403 ]
check "a foreign Origin is rejected" [ "$(status_of -H 'Origin: http://evil.example' "$proxy_url/api/version")" = 403 ]
check "a loopback Origin is accepted" [ "$(status_of -H 'Origin: http://localhost:3000' "$proxy_url/api/version")" = 200 ]
check "the Origin reaches the upstream untouched" [ "$(row_field "$(upstream_row 9)" '.headers.origin')" = http://localhost:3000 ]
check "a rejected request never reaches the upstream" [ "$(wc -l < "$run_dir/upstream.log" | tr -d ' ')" = 9 ]
check "an unknown path is refused" [ "$(status_of "$proxy_url/api/generate")" = 404 ]
check "an unknown method on a known path is refused" [ "$(status_of -X DELETE "$proxy_url/v1/messages")" = 404 ]
check "the model list is forwarded" [ "$(status_of "$proxy_url/v1/models")" = 200 ]
check "the tag list is forwarded" [ "$(status_of "$proxy_url/api/tags")" = 200 ]
check "refused requests write no log row" [ "$(row_count)" = 5 ]
check "the log file is private" [ "$(mode_of "$run_dir/proxy/requests.jsonl")" = 600 ]
check "the log folder is private" [ "$(mode_of "$run_dir/proxy")" = 700 ]

check "a proxy without --record saves no body" [ ! -e "$run_dir/record" ]
stop_proxy
start_proxy --record "$run_dir/record"
send "$run_dir/first.json" "$run_dir/recorded.out"
recorded="$run_dir/record/$(row_field "$(log_row 6)" .request_id).json"
check "--record saves the body under the request id" [ -f "$recorded" ]
check "the recorded body is the request byte-for-byte" cmp -s "$recorded" "$run_dir/first.json"
check "the recorded body is private" [ "$(mode_of "$recorded")" = 600 ]
check "the record folder is private" [ "$(mode_of "$run_dir/record")" = 700 ]
check "the recorded request still reaches the upstream" upstream_body_is 12 "$run_dir/first.json"
curl -sf "$proxy_url/api/version" > /dev/null
check "other routes record nothing" [ "$(find "$run_dir/record" -name '*.json' | wc -l | tr -d ' ')" = 1 ]

stop_proxy
stop_upstream
start_upstream && start_proxy --stabilize --record "$run_dir/record"
volatile_body() { python3 "$tmp/volatile_body.py" "$@"; }
upstream_body_file() { printf '%s' "$(upstream_row "$1")" | jq -r .body > "$run_dir/upstream-$1.json"; echo "$run_dir/upstream-$1.json"; }
upstream_system_texts() { jq -c '[.system[].text]' "$(upstream_body_file "$1")"; }
system_prefix_of() { python3 "$tmp/system_prefix.py" "$(upstream_body_file "$1")"; }
byte_length() { printf '%s' "$1" | wc -c | tr -d ' '; }
big_a="$(printf 'A%.0s' $(seq 500))"
big_b="$(printf 'B%.0s' $(seq 500))"
volatile_body array "" "Sunday 2026-11-01" "" "Read a file." hello > "$run_dir/v1.json"
volatile_body array "" "Monday 2026-11-02" "" "Read a file." hello > "$run_dir/v2.json"
volatile_body array "" "Tuesday 2026-11-03" "" "Read a file." hello > "$run_dir/v3.json"
volatile_body array "" "Wednesday 2026-11-04" "$big_a" "Read a file." hello > "$run_dir/v4.json"
volatile_body array "" "Wednesday 2026-11-04" "$big_b" "Read a file." hello > "$run_dir/v5.json"
volatile_body array "" "Wednesday 2026-11-04" "$big_b" "Read a file carefully." hello > "$run_dir/v6.json"

send "$run_dir/v1.json" "$run_dir/v1.out"
check "--stabilize forwards a first body byte-for-byte" upstream_body_is 1 "$run_dir/v1.json"
check "--stabilize rows list the moved lines" [ "$(row_field "$(log_row 1)" '.stabilized | length')" = 0 ]
check "--stabilize rows count the moved bytes" [ "$(row_field "$(log_row 1)" .moved_bytes)" = 0 ]

send "$run_dir/v2.json" "$run_dir/v2.out"
check "a short changed line is learned and moved to the tail of the system" [ "$(upstream_system_texts 2)" = '["You are a terse assistant.","Keep replies short.\nThe session began on Monday 2026-11-02."]' ]
check "the row names the moved line with its date masked" [ "$(row_field "$(log_row 2)" '.stabilized | join(",")')" = "The session began on <weekday> ####-##-##." ]
check "the row counts the moved bytes" [ "$(row_field "$(log_row 2)" .moved_bytes)" = "$(byte_length 'The session began on Monday 2026-11-02.')" ]

send "$run_dir/v3.json" "$run_dir/v3.out"
check "the next request keeps the moved line at the tail" [ "$(upstream_system_texts 3)" = '["You are a terse assistant.","Keep replies short.\nThe session began on Tuesday 2026-11-03."]' ]
check "the prefix before the moved line is byte-stable" [ "$(system_prefix_of 3)" = "$(system_prefix_of 2)" ]
check "the divergence is now at the tail" [ "$(row_field "$(log_row 3)" .offset)" -ge "$(python3 "$tmp/system_offset_of.py" "$run_dir/upstream-3.json" "The session began")" ]
check "the messages are never touched" [ "$(jq -c .messages "$run_dir/upstream-3.json")" = "$(jq -c .messages "$run_dir/v3.json")" ]
check "the tools are never touched" [ "$(jq -c .tools "$run_dir/upstream-3.json")" = "$(jq -c .tools "$run_dir/v3.json")" ]
check "--record keeps the original body, not the stabilized one" cmp -s "$run_dir/record/$(row_field "$(log_row 3)" .request_id).json" "$run_dir/v3.json"

send "$run_dir/v4.json" "$run_dir/v4.out"
send "$run_dir/v5.json" "$run_dir/v5.out"
check "a 500-byte change is not learned" [ "$(row_field "$(log_row 5)" '.stabilized | join(",")')" = "The session began on <weekday> ####-##-##." ]
check "the big line stays in place" [ "$(jq -r '.system[0].text' "$(upstream_body_file 5)")" = "$big_b" ]

send "$run_dir/v6.json" "$run_dir/v6.out"
check "a tools change is logged" [ "$(row_field "$(log_row 6)" .diverged_at)" = tools ]
check "a tools change is not moved" [ "$(jq -c .tools "$(upstream_body_file 6)")" = "$(jq -c .tools "$run_dir/v6.json")" ]

stop_proxy
stop_upstream
start_upstream && start_proxy --stabilize
volatile_body string "Today's date: 2026-11-02" "Sunday 2026-11-01" "" "Read a file." hello > "$run_dir/s1.json"
volatile_body string "Today's date: 2026-11-02" "Monday 2026-11-02" "" "Read a file." hello > "$run_dir/s2.json"
volatile_body string "14:05" "Monday 2026-11-02" "" "Read a file." hello > "$run_dir/s3.json"
send "$run_dir/s1.json" "$run_dir/s1.out"
check "a hard-rule date line moves on the first request" [ "$(jq -r .system "$(upstream_body_file 1)")" = "The session began on Sunday 2026-11-01.
You are a terse assistant.
Keep replies short.
Today's date: 2026-11-02" ]
check "the hard-rule row names the masked line" [ "$(row_field "$(log_row 1)" '.stabilized | join(",")')" = "Today's date: ####-##-##" ]
send "$run_dir/s2.json" "$run_dir/s2.out"
check "a string system gets its volatile lines appended in order" [ "$(jq -r .system "$(upstream_body_file 2)")" = "You are a terse assistant.
Keep replies short.
Today's date: 2026-11-02
The session began on Monday 2026-11-02." ]
send "$run_dir/s3.json" "$run_dir/s3.out"
check "a line that is only a time is volatile" [ "$(row_field "$(log_row 3)" '.stabilized | join(",")')" = "##:##,The session began on <weekday> ####-##-##." ]

check "the hard rules match in linear time and skip long lines" python3 "$tmp/hard_rule_timing.py" "$proxy"

stop_proxy
stop_upstream
start_upstream
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
