#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
stopper="$repo/bin/model-stop"
tmp="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
failures=0
server_pid=""
sleepers=""

cleanup() {
  local pid
  for pid in $server_pid $sleepers; do
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
  done
  rm -rf "$tmp"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

expect_line() {
  printf '%s\n' "$2" | grep -qE -- "$3" || fail "$1: no line matching [$3] in:
$2"
}

alive() {
  kill -0 "$1" 2>/dev/null && [ "$(ps -o stat= -p "$1" 2>/dev/null | cut -c1)" != Z ]
}

start_named() {
  bash -c "exec -a '$1' sleep 300" &
  last_pid=$!
  disown "$last_pid"
  sleepers="$sleepers $last_pid"
}

mkdir -p "$tmp/bin" "$tmp/api"
cat >"$tmp/bin/launchctl" <<'SH'
#!/bin/sh
echo "launchctl $*" >>"$STUB_LOG"
if [ "$1" = list ]; then printf 'PID\tStatus\tLabel\n4321\t0\tlocal.ollama\n'; fi
SH
cat >"$tmp/bin/brew" <<'SH'
#!/bin/sh
echo "brew $*" >>"$STUB_LOG"
SH
chmod +x "$tmp/bin/launchctl" "$tmp/bin/brew"
printf '{"models":[{"name":"qwen3.8:27b-cc"},{"name":"qwen3-embedding:0.6b"}]}' >"$tmp/api/ps"

port_file="$tmp/port"
python3 -c '
import http.server, socketserver, sys, os, json
root, port_file, posts = sys.argv[1:4]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = open(os.path.join(root, "ps"), "rb").read()
        self.send_response(200); self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with open(posts, "a") as handle:
            handle.write(self.path + " " + payload["model"] + " " + str(payload.get("keep_alive")) + "\n")
        if self.path == "/api/generate" and "embedding" in payload["model"]:
            self.send_response(400); self.end_headers(); self.wfile.write(b"{\"error\":\"does not support generate\"}"); return
        self.send_response(200); self.end_headers(); self.wfile.write(b"{}")
    def log_message(self, *args):
        pass
server = socketserver.TCPServer(("127.0.0.1", 0), Handler)
open(port_file, "w").write(str(server.server_address[1]))
server.serve_forever()
' "$tmp/api" "$port_file" "$tmp/posts" &
server_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$port_file" ] && break; sleep 0.2; done
port="$(cat "$port_file")"

start_named "python3 /x/bin/messages-proxy --upstream http://127.0.0.1:11434 --port 0"
proxy_pid=$last_pid
start_named "python3 /x/ollama/incidents/watcher.py --watch-pid 1"
watcher_pid=$last_pid
start_named "/opt/llama.cpp/llama-server --port 8300"
bench_pid=$last_pid
start_named "bash /x/bin/claude-ollama 27b"
session_pid=$last_pid
start_named "unrelated-monitor-proxy"
bystander_pid=$last_pid
sleep 0.3

run_stop() {
  PATH="$tmp/bin:$PATH" STUB_LOG="$tmp/calls" OLLAMA_HOST="127.0.0.1:$port" "$stopper" "$@"
}

output="$(run_stop --dry-run)"
expect_line "dry run names proxy" "$output" "would stop pid $proxy_pid .*messages-proxy"
expect_line "dry run names models" "$output" 'would unload qwen3\.8:27b-cc'
alive "$proxy_pid" || fail "dry run stopped the proxy"
[ ! -e "$tmp/posts" ] || fail "dry run unloaded a model"
[ -e "$tmp/calls" ] && grep -q bootout "$tmp/calls" && fail "dry run touched launchd"

output="$(run_stop --keep-ollama)"
sleep 0.3
alive "$proxy_pid" && fail "proxy still running"
alive "$watcher_pid" && fail "watcher still running"
alive "$bench_pid" && fail "bench server still running"
alive "$session_pid" || fail "session stopped without --sessions"
alive "$bystander_pid" || fail "bystander stopped"
grep -q '^/api/generate qwen3.8:27b-cc 0$' "$tmp/posts" || fail "main model not unloaded"
grep -q '^/api/embed qwen3-embedding:0.6b 0$' "$tmp/posts" || fail "embedding model not unloaded through embed"
expect_line "reports unload" "$output" 'unloaded qwen3-embedding:0\.6b'
[ -e "$tmp/calls" ] && grep -q bootout "$tmp/calls" && fail "--keep-ollama stopped the server"

output="$(run_stop --sessions)"
sleep 0.3
alive "$session_pid" && fail "session still running with --sessions"
alive "$bystander_pid" || fail "bystander stopped"
grep -q "launchctl bootout gui/$(id -u)/local.ollama" "$tmp/calls" || fail "ollama launch agent not booted out"
expect_line "reports server stop" "$output" 'stopped ollama \(local\.ollama\)'

if [ "$failures" -eq 0 ]; then echo "all passed"; else exit 1; fi
