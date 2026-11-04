#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
monitor="$repo/bin/model-monitor"
tmp="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
failures=0
server_pid=""
sleeper_pid=""

cleanup() {
  [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null
  [ -n "$sleeper_pid" ] && kill "$sleeper_pid" 2>/dev/null && wait "$sleeper_pid" 2>/dev/null
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

now_iso() {
  python3 -c 'import datetime,sys; print((datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(seconds=int(sys.argv[1]))).isoformat())' "$1"
}

mkdir -p "$tmp/api" "$tmp/lease" "$tmp/state/proxy" "$tmp/state/incidents"
cat >"$tmp/api/ps" <<JSON
{"models":[{"name":"qwen3.8:27b-cc","size":20000000000,"size_vram":20000000000,"context_length":65536,"expires_at":"$(now_iso 240)"},{"name":"qwen3-embedding:0.6b","size":600000000,"size_vram":0,"context_length":8192,"expires_at":"$(now_iso 30)"}]}
JSON
port_file="$tmp/port"
python3 -c '
import http.server, socketserver, sys, os
root = sys.argv[1]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = os.path.join(root, self.path.rsplit("/", 1)[-1])
        if not os.path.isfile(path):
            self.send_response(404); self.end_headers(); return
        body = open(path, "rb").read()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)
    def log_message(self, *args):
        pass
server = socketserver.TCPServer(("127.0.0.1", 0), Handler)
open(sys.argv[2], "w").write(str(server.server_address[1]))
server.serve_forever()
' "$tmp/api" "$port_file" &
server_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$port_file" ] && break; sleep 0.2; done
port="$(cat "$port_file")"

sleep 60 &
sleeper_pid=$!
printf '{"name":"session","model":"qwen3.8:27b-cc","num_ctx":65536,"rung":"","started":"%s"}\n' "$(now_iso -300)" >"$tmp/lease/$sleeper_pid.json"
printf '{"name":"review","model":"qwen3.8:27b-cc","num_ctx":65536,"rung":"","started":"x"}\n' >"$tmp/lease/999999.json"

printf '{"ts":"%s","diverged_at":"message:3","prompt_bytes":49376,"sections":6}\n' "$(now_iso -5)" >"$tmp/state/proxy/requests.jsonl"
printf '{"ts":"%s","cause":"evicted","detail":"unload qwen3.8"}\n{"kind":"health","ts":"x"}\n' "$(now_iso -60)" >"$tmp/state/incidents/one.jsonl"
printf '%s\n' "$tmp/state/incidents/one.jsonl" >"$tmp/state/incidents/current"

run_monitor() {
  OLLAMA_HOST="127.0.0.1:$port" CLAUDE_OLLAMA_LEASE_DIR="$tmp/lease" CLAUDE_CONSOLE_STATE_DIR="$tmp/state" \
    MODEL_MONITOR_PS="$tmp/ps-output" "$monitor" --once "$@"
}

printf '  PID  %%CPU   RSS COMMAND\n 4242  187.5 900000 /opt/ollama runner --model /x/blobs/sha --port 5555\n 4343  0.0 1000 /bin/zsh\n' >"$tmp/ps-output"

output="$(run_monitor)"
expect_line "main model listed" "$output" 'qwen3\.8:27b-cc +18\.6 GiB +100% GPU +65536 +[0-9]+m?[0-9]*s?'
expect_line "embedding on cpu" "$output" 'qwen3-embedding:0\.6b +0\.6 GiB +CPU'
expect_line "live session holder" "$output" "session +pid $sleeper_pid +qwen3\.8:27b-cc"
[ -z "$(printf '%s\n' "$output" | grep 'pid 999999')" ] || fail "dead holder shown"
expect_line "busy runner" "$output" 'runner pid 4242 +187\.5% CPU .* busy'
expect_line "last request" "$output" 'last request [0-9]+s ago: 49376 bytes, diverged at message:3'
expect_line "incident" "$output" 'evicted: unload qwen3\.8'
[ -z "$(printf '%s\n' "$output" | grep health)" ] || fail "health row shown"

kill "$server_pid" 2>/dev/null
wait "$server_pid" 2>/dev/null
server_pid=""
output="$(run_monitor)"
expect_line "server down" "$output" 'ollama: not answering'

if [ "$failures" -eq 0 ]; then echo "all passed"; else exit 1; fi
