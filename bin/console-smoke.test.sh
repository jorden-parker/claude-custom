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
  [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null
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
import os
import sys

port = int(sys.argv[1])
token = os.environ["STUB_TOKEN"]
fail_path = os.environ.get("STUB_FAIL_PATH", "")
open_gate = os.environ.get("STUB_OPEN_GATE") == "1"


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
        elif path.startswith("/api/"):
            self.respond(200, b"{}", "application/json")
        else:
            self.respond(200, b"<html></html>", "text/html")

    def do_POST(self):
        if self.headers.get("Origin", "") != "http://" + self.headers.get("Host", ""):
            self.respond(403, b"Forbidden")
        else:
            self.respond(401, b"Unauthorized")

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

case_all_pages_pass() {
  run_smoke pass 8791
  check "passing run exits 0" exits_with 0
  check "passing run prints all passed" output_has pass '^all passed$'
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

case_keep_leaves_running() {
  run_smoke keep 8794 --keep
  check "keep exits 0" exits_with 0
  check "keep prints the link" output_has keep 'http://127.0.0.1:8794/?token='
  check "keep leaves the server running" pid_alive "$sandbox/keep.pid"
  kill "$(cat "$sandbox/keep.pid")" 2>/dev/null
  check "keep server stops when told" pid_gone "$sandbox/keep.pid"
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
case_open_gate_fails
case_keep_leaves_running
case_busy_port_refused

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
