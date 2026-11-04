#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
smoke="$repo/bin/console-smoke"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
failures=0
status=0

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

pid_gone() {
  local pid
  pid="$(cat "$1" 2>/dev/null)"
  [ -n "$pid" ] || return 1
  for _ in $(seq 50); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done
  return 1
}

pid_alive() {
  local pid
  pid="$(cat "$1" 2>/dev/null)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

write_stubs() {
  cat > "$sandbox/launcher" <<'LAUNCHER'
#!/usr/bin/env bash
port=""
while [ $# -gt 0 ]; do
  case "$1" in
    --port) port="$2"; shift 2 ;;
    *) shift ;;
  esac
done
token="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
mkdir -p "$CLAUDE_CONSOLE_STATE_DIR/tokens"
printf '%s\n' "$token" > "$CLAUDE_CONSOLE_STATE_DIR/tokens/$port"
export STUB_TOKEN="$token"
echo "$$" > "$STUB_PID_FILE"
exec python3 "$STUB_SERVER" "$port"
LAUNCHER
  chmod +x "$sandbox/launcher"
  cat > "$sandbox/stub-server.py" <<'SERVER'
import http.server
import json
import os
import sys
import urllib.error
import urllib.request

port = int(sys.argv[1])
token = os.environ["STUB_TOKEN"]
fail_path = os.environ.get("STUB_FAIL_PATH", "")
open_gate = os.environ.get("STUB_OPEN_GATE") == "1"
model_server = os.environ.get("LLAMA_SERVER_URL", "")
url_file = os.environ.get("STUB_LLAMA_URL_FILE", "")
if url_file:
    with open(url_file, "w") as stream:
        stream.write(model_server)


def forward(method, route, body=None):
    request = urllib.request.Request(model_server + route, data=body, method=method, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status
    except (urllib.error.URLError, ValueError) as error:
        return getattr(error, "code", 502)


class Handler(http.server.BaseHTTPRequestHandler):
    def respond(self, status, body, content_type="text/plain"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authorized(self):
        if open_gate:
            return True
        cookie = self.headers.get("Cookie", "")
        return ("console_token=" + token) in cookie or ("token=" + token) in self.path

    def do_GET(self):
        if not self.authorized():
            self.respond(401, b"Unauthorized")
            return
        path = self.path.split("?")[0]
        if path == fail_path:
            self.respond(500, b"boom")
        elif path == "/api/server/ping":
            state = "up" if forward("GET", "/health") == 200 else "down"
            self.respond(200, json.dumps({"state": state}).encode(), "application/json")
        elif path.startswith("/api/"):
            self.respond(200, b"{}", "application/json")
        else:
            self.respond(200, b"<html></html>", "text/html")

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        path = self.path.split("?")[0]
        if self.headers.get("Origin", "") != "http://" + self.headers.get("Host", ""):
            self.respond(403, b"Forbidden")
        elif not self.authorized():
            self.respond(401, b"Unauthorized")
        elif path == fail_path:
            self.respond(500, b"boom")
        elif path in ("/api/models/load", "/api/models/unload"):
            status = forward("POST", path.replace("/api", "", 1), body)
            self.respond(status, b"{}", "application/json")
        else:
            self.respond(404, b"{}", "application/json")

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
SERVER
}

run_smoke() {
  local name="$1" port="$2"
  shift 2
  mkdir -p "$sandbox/$name.tmp"
  TMPDIR="$sandbox/$name.tmp" \
    CONSOLE_SMOKE_LAUNCHER="$sandbox/launcher" \
    STUB_SERVER="$sandbox/stub-server.py" \
    STUB_PID_FILE="$sandbox/$name.pid" \
    STUB_LLAMA_URL_FILE="$sandbox/$name.llama-url" \
    "$smoke" --port "$port" "$@" > "$sandbox/$name.out" 2>&1
  status=$?
}

output_has() {
  grep -q "$2" "$sandbox/$1.out"
}

exits_with() {
  [ "$status" -eq "$1" ]
}

empty_dir() {
  [ -z "$(ls -A "$1")" ]
}

model_server_answers() {
  local url
  url="$(cat "$sandbox/$1.llama-url" 2>/dev/null)"
  case "$url" in
    http://127.0.0.1:*) ;;
    *) return 1 ;;
  esac
  curl -s -o /dev/null --max-time 5 "$url/health"
}

model_server_gone() {
  ! model_server_answers "$1"
}

kept_stub_pid() {
  sed -n 's/^model server stub: .* (pid \([0-9]*\))$/\1/p' "$sandbox/keep.out"
}

case_all_pages_pass() {
  run_smoke pass 8791
  check "passing run exits 0" exits_with 0
  check "passing run prints all passed" output_has pass '^all passed$'
  check "passing run finds the model server up" output_has pass '^ok api /api/server/ping$'
  check "passing run loads a model" output_has pass '^ok api /api/models/load$'
  check "passing run unloads it" output_has pass '^ok api /api/models/unload$'
  check "passing run stops the stub model server" model_server_gone pass
  check "passing run stops the server" pid_gone "$sandbox/pass.pid"
  check "passing run removes its temp dir" empty_dir "$sandbox/pass.tmp"
}

case_failing_page_is_named() {
  export STUB_FAIL_PATH=/health
  run_smoke fail-page 8792
  unset STUB_FAIL_PATH
  check "failing page exits 1" exits_with 1
  check "failing page is named on a FAIL line" output_has fail-page '^FAIL: page /health '
  check "failing page run stops the server" pid_gone "$sandbox/fail-page.pid"
}

case_open_gate_fails() {
  export STUB_OPEN_GATE=1
  run_smoke open-gate 8793
  unset STUB_OPEN_GATE
  check "open gate exits 1" exits_with 1
  check "open gate reports the token gate" output_has open-gate '^FAIL: token gate'
}

case_failing_model_route_is_named() {
  export STUB_FAIL_PATH=/api/models/load
  run_smoke fail-load 8796
  unset STUB_FAIL_PATH
  check "failing load exits 1" exits_with 1
  check "failing load is named on a FAIL line" output_has fail-load '^FAIL: api /api/models/load (status 500)$'
  check "failing load run stops the stub model server" model_server_gone fail-load
}

case_keep_leaves_running() {
  run_smoke keep 8794 --keep
  check "keep exits 0" exits_with 0
  check "keep prints the link" output_has keep 'http://127.0.0.1:8794/?token='
  check "keep leaves the server running" pid_alive "$sandbox/keep.pid"
  check "keep leaves the stub model server running" model_server_answers keep
  kill "$(cat "$sandbox/keep.pid")" 2>/dev/null
  check "keep server stops when told" pid_gone "$sandbox/keep.pid"
  kill "$(kept_stub_pid)" 2>/dev/null
  check "kept stub model server stops when told" model_server_gone keep
}

case_busy_port_refused() {
  STUB_TOKEN=busy python3 "$sandbox/stub-server.py" 8795 >/dev/null 2>&1 &
  local busy_pid=$!
  local waited=0
  while ! nc -z 127.0.0.1 8795 2>/dev/null && [ "$waited" -lt 50 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done
  run_smoke busy 8795
  kill "$busy_pid" 2>/dev/null
  wait "$busy_pid" 2>/dev/null
  check "busy port exits 2" exits_with 2
  check "busy port says it is in use" output_has busy 'already in use'
}

write_stubs
case_all_pages_pass
case_failing_page_is_named
case_failing_model_route_is_named
case_open_gate_fails
case_keep_leaves_running
case_busy_port_refused

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
