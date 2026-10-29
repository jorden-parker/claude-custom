#!/usr/bin/env bash
set -u
umask 022
server="$(cd "$(dirname "$0")" && pwd)/dev-server.py"
tmp="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
failures=0

trap 'kill "${broker_pid:-}" 2>/dev/null; rm -rf "$tmp"' EXIT

export DEV_TEST_DIR="$tmp"
export FAKE_PORTS_LOG="$tmp/ports.log"

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "ok: $name"
  else
    echo "FAIL: $name"
    failures=$((failures + 1))
  fi
}

contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

lacks() {
  ! contains "$1" "$2"
}

error_with() {
  case "$1" in
    "ERROR "*"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

port_refuses() {
  ! curl --noproxy '*' -sf "http://localhost:$1/" >/dev/null
}

requested() {
  grep -qxF -- "$1" "$tmp/broker.log"
}

section() {
  awk -v name="$1" '$0 ~ ("^### [0-9]+ " name "$") { on = 1; next } /^### / { on = 0 } on' "$2"
}

mkdir -p "$tmp/project/app" "$tmp/bin" "$tmp/state"
printf '{"name":"root","private":true}\n' > "$tmp/project/package.json"
printf '{"name":"app","scripts":{"dev":"fake-server","dev:web":"fake-server","build":"next build"}}\n' > "$tmp/project/app/package.json"
git -C "$tmp/project" init -q
git -C "$tmp/project" add -A
git -C "$tmp/project" -c user.name=test -c user.email=test@example.test commit -qm init

cat > "$tmp/bin/npm" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DEV_TEST_DIR/npm.log"
case "$*" in
  "run dev" | "run dev:"*) exec python3 "$DEV_TEST_DIR/fake-next.py" ;;
esac
exit 1
SH

cat > "$tmp/broker.py" <<'PY'
import json
import os
import socketserver
import sys

socket_path, log_path, opened_flag = sys.argv[1:4]
CONSOLE_LINE = "[warn] If you do not provide a visible label, you must specify an aria-label or aria-labelledby attribute for accessibility"
ELEMENTS = '- button "Save" [ref=e1]\n- textbox "Name" [ref=e2]'


def answer(request):
    operation = request["page"]["op"]
    if operation == "open":
        open(opened_flag, "w").close()
        return {"ok": True, "result": {"url": request["page"]["url"], "errors": ["TypeError: x is undefined"], "console": [CONSOLE_LINE], "surface": "S-1"}}
    if not os.path.exists(opened_flag):
        return {"ok": False, "error": "call page_check first"}
    if operation == "snapshot":
        return {"ok": True, "result": {"elements": ELEMENTS}}
    return {"ok": True, "result": {"url": "http://localhost:1/settings", "errors": [], "console": [], "elements": ELEMENTS}}


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        request = json.loads(self.rfile.readline())
        with open(log_path, "a") as record:
            record.write(json.dumps(request) + "\n")
        self.wfile.write(json.dumps(answer(request)).encode() + b"\n")


if os.path.exists(socket_path):
    os.unlink(socket_path)
socketserver.UnixStreamServer(socket_path, Handler).serve_forever()
PY

chmod +x "$tmp/bin/npm"
: > "$tmp/broker.log"
python3 "$tmp/broker.py" "$tmp/broker.sock" "$tmp/broker.log" "$tmp/opened" &
broker_pid=$!
for _ in $(seq 50); do
  [ -S "$tmp/broker.sock" ] && break
  sleep 0.1
done

cat > "$tmp/fake-next.py" <<'PY'
import http.server
import json
import os
import socketserver

ports_log = os.environ["FAKE_PORTS_LOG"]
SSE_REPLY = 'event: message\ndata: {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"# Found errors in 1 browser session(s)\\nHydration failed"}]}}\n\n'


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_reply(200, "text/plain", "ok")

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path == "/_next/mcp":
            self.send_reply(200, "text/event-stream", SSE_REPLY)
        else:
            self.send_reply(404, "text/plain", "not found")

    def send_reply(self, status, kind, body):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


server = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Handler)
port = server.server_address[1]
os.makedirs(".next/dev", exist_ok=True)
with open(".next/dev/lock", "w") as lock:
    json.dump({"pid": os.getpid(), "port": port, "hostname": "localhost", "appUrl": "http://localhost:%d" % port, "startedAt": 0}, lock)
with open(ports_log, "a") as log:
    log.write("%d\n" % port)
print("   \x1b[1m- Local:\x1b[0m        http://localhost:%d%s" % (port, os.environ.get("FAKE_LOCAL_SUFFIX", "")), flush=True)
print("Error: Cannot find module './missing'", flush=True)
print("    at Object.<anonymous> (app/page.tsx:3:1)", flush=True)
server.serve_forever()
PY

cat > "$tmp/client.py" <<'PY'
import json
import subprocess
import sys

server, method = sys.argv[1:3]
arguments = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
messages = [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "test", "version": "0"}}},
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
]
if method == "list":
    messages.append({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
else:
    messages.append({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": method, "arguments": arguments}})
stdin = "".join(json.dumps(message) + "\n" for message in messages)
completed = subprocess.run([sys.executable, server], input=stdin, capture_output=True, text=True, timeout=120)
replies = {reply.get("id"): reply for reply in map(json.loads, completed.stdout.splitlines())}
result = replies[2]["result"]
if method == "list":
    print(" ".join(tool["name"] for tool in result["tools"]))
else:
    print(("ERROR " if result["isError"] else "") + "\n".join(item["text"] for item in result["content"]).rstrip("\n"))
PY

cat > "$tmp/session.py" <<'PY'
import json
import subprocess
import sys

server = sys.argv[1]
process = subprocess.Popen([sys.executable, server], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)


def send(message):
    process.stdin.write(json.dumps(message) + "\n")
    process.stdin.flush()
    return json.loads(process.stdout.readline())


send({"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}})
for number, step in enumerate(sys.argv[2:], start=1):
    if step.startswith("sh:"):
        subprocess.run(step[3:], shell=True, check=True)
        continue
    name, arguments = json.loads(step)
    result = send({"jsonrpc": "2.0", "id": number, "method": "tools/call", "params": {"name": name, "arguments": arguments}})["result"]
    print("### %d %s" % (number, name))
    print(("ERROR " if result["isError"] else "") + result["content"][0]["text"].rstrip("\n"))
process.stdin.close()
process.wait()
PY

run_in_project() {
  (
    cd "$tmp/project" || exit 1
    unset CLAUDE_OLLAMA_CMUX_BROKER
    if [ -n "${BROKER:-}" ]; then
      export CLAUDE_OLLAMA_CMUX_BROKER="$BROKER"
    fi
    PATH="$tmp/bin:$PATH"
    export PATH
    XDG_STATE_HOME="$tmp/state"
    export XDG_STATE_HOME
    "$@"
  )
}

call() {
  run_in_project python3 "$tmp/client.py" "$server" "$@"
}

session() {
  local out="$1"
  shift
  run_in_project python3 "$tmp/session.py" "$server" "$@" > "$out"
}

check "tools/list lists the eight dev tools" \
  [ "$(call list)" = "dev_status dev_start dev_logs dev_errors dev_stop page_check page_snapshot page_act" ]

status="$(call dev_status '{}')"
check "dev_status with nothing running says no dev server answers, naming the app dir" \
  contains "$status" "no dev server answers"
check "and lists app with its dev script" contains "$status" "app:"

start_out="$tmp/session-start.out"
session "$start_out" \
  '["dev_start",{"dir":"app"}]' \
  '["dev_status",{"dir":"app"}]' \
  '["dev_logs",{"dir":"app","errors_only":true}]' \
  '["dev_errors",{"dir":"app"}]' \
  '["dev_stop",{"dir":"app"}]' \
  "sh:if curl --noproxy '*' -sf \"http://localhost:\$(tail -n 1 \"\$DEV_TEST_DIR/ports.log\")/\" >/dev/null; then touch \"\$DEV_TEST_DIR/still-up\"; fi"
port="$(tail -n 1 "$tmp/ports.log")"
started="$(section dev_start "$start_out")"
check "dev_start returns the real URL and says ready" \
  contains "$started" "ready at http://localhost:$port"
check "dev_status reports the same URL, a pid and that it answers" \
  contains "$(section dev_status "$start_out")" "http://localhost:$port answers (HTTP 200), pid"
logs="$(section dev_logs "$start_out")"
check "dev_logs errors_only keeps the error line" contains "$logs" "Cannot find module"
check "and its stack line" contains "$logs" "at Object.<anonymous>"
check "and drops the Local line" lacks "$logs" "Local:"
check "dev_errors shows the Next.js error text" contains "$(section dev_errors "$start_out")" "Hydration failed"
check "dev_stop reports it stopped the server" contains "$(section dev_stop "$start_out")" "stopped app"
check "the stopped server refuses connections" [ ! -e "$tmp/still-up" ]

evil_out="$tmp/session-evil.out"
(export FAKE_LOCAL_SUFFIX="@evil.test/"; session "$evil_out" '["dev_start",{"dir":"app"}]' '["dev_stop",{"dir":"app"}]')
evil_port="$(tail -n 1 "$tmp/ports.log")"
check "a log URL with a userinfo host yields the port's localhost URL" \
  contains "$(section dev_start "$evil_out")" "ready at http://localhost:$evil_port "
check "and the log's host is never reported" lacks "$(cat "$evil_out")" "evil.test"

: > "$tmp/npm.log"
second_out="$tmp/session-second.out"
session "$second_out" \
  '["dev_start",{"dir":"app"}]' \
  '["dev_start",{"dir":"app"}]' \
  '["dev_stop",{"dir":"app"}]'
check "a second dev_start while one runs does not start another" \
  contains "$(section dev_start "$second_out")" "already running at http://localhost:$(tail -n 1 "$tmp/ports.log")"
check "and npm ran once" [ "$(wc -l < "$tmp/npm.log" | tr -d ' ')" = 1 ]

check "dev_start refuses a dir outside the repository" \
  error_with "$(call dev_start '{"dir":"../x"}')" "inside the repository"
check "dev_start refuses an absolute dir" \
  error_with "$(call dev_start '{"dir":"/tmp"}')" "inside the repository"
check "dev_start refuses a script name with shell characters" \
  error_with "$(call dev_start '{"dir":"app","script":"build; rm -rf ~"}')" "dev_start runs only dev, start or dev:*"
check "dev_start refuses a script that is not dev, start or dev:*" \
  error_with "$(call dev_start '{"dir":"app","script":"build"}')" "dev_start runs only dev, start or dev:*"
check "dev_start refuses a dev:* script missing from package.json" \
  error_with "$(call dev_start '{"dir":"app","script":"dev:missing"}')" 'no script "dev:missing"'
: > "$tmp/npm.log"
check "a refused script never reaches npm" [ ! -s "$tmp/npm.log" ]
check "dev_start accepts a dev:* script that exists" \
  contains "$(call dev_start '{"dir":"app","script":"dev:web"}')" "ready at"
check "dev_start refuses unknown arguments" \
  [ "$(call dev_start '{"dir":"app","oops":1}')" = "ERROR unknown arguments: oops" ]

session "$tmp/session-exit.out" '["dev_start",{"dir":"app"}]'
exit_port="$(tail -n 1 "$tmp/ports.log")"
sleep 2
check "servers a session started are gone when it ends" port_refuses "$exit_port"

rm -f "$tmp/opened"
check "page_snapshot before any page_check says to call page_check first" \
  error_with "$(BROKER="$tmp/broker.sock" call page_snapshot '{}')" "call page_check first"
check "page_act before any page_check says to call page_check first" \
  error_with "$(BROKER="$tmp/broker.sock" call page_act '{"action":"click","target":"e1"}')" "call page_check first"

check "page_check without the cmux broker says to launch from a cmux terminal" \
  error_with "$(BROKER='' call page_check '{"dir":"app","path":"/settings"}')" "cmux terminal"

: > "$tmp/broker.log"
browser_out="$tmp/session-browser.out"
BROKER="$tmp/broker.sock" session "$browser_out" \
  '["dev_start",{"dir":"app"}]' \
  '["page_check",{"dir":"app","path":"/settings"}]' \
  '["page_check",{"dir":"app","path":"/other"}]'
browser_port="$(tail -n 1 "$tmp/ports.log")"
page="$(section page_check "$browser_out")"
check "page_check reports browser errors" contains "$page" "Browser errors:"
check "and the TypeError from errors list" contains "$page" "TypeError: x is undefined"
check "and the console warning from console list" contains "$page" "aria-label"
check "and the Next.js error from get_errors" contains "$page" "Hydration failed"
check "page_check names the surface it uses" contains "$page" "Surface: S-1"
check "the first page_check asks the broker to open the page" \
  requested "{\"page\": {\"op\": \"open\", \"url\": \"http://localhost:$browser_port/settings\"}}"
check "a later page_check asks the broker to open its path on the same session" \
  requested "{\"page\": {\"op\": \"open\", \"url\": \"http://localhost:$browser_port/other\"}}"

act_out="$tmp/session-act.out"
BROKER="$tmp/broker.sock" session "$act_out" \
  '["dev_start",{"dir":"app"}]' \
  '["page_check",{"dir":"app","path":"/settings"}]' \
  '["page_snapshot",{}]' \
  '["page_act",{"action":"fill","target":"e2","text":"Ada"}]' \
  '["page_act",{"action":"press","text":"Enter"}]' \
  '["page_act",{"action":"scroll","text":"300"}]'
snapshot="$(section page_snapshot "$act_out")"
check "page_snapshot lists elements with refs" contains "$snapshot" "[ref=e1]"
check "page_snapshot asks the broker for the elements" requested '{"page": {"op": "snapshot"}}'
fill="$(section page_act "$act_out")"
check "page_act fill asks the broker to fill the ref with the text" \
  requested '{"page": {"op": "act", "action": "fill", "target": "e2", "text": "Ada"}}'
check "page_act reports the URL, browser errors, console and elements" \
  [ "$(printf '%s\n' "$fill" | grep -c -e '^URL now:' -e '^Browser errors:' -e '^Console:' -e '^Elements:')" -ge 4 ]
check "page_act press asks the broker for the key" \
  requested '{"page": {"op": "act", "action": "press", "text": "Enter"}}'
check "page_act scroll asks the broker for the pixels" \
  requested '{"page": {"op": "act", "action": "scroll", "text": "300"}}'
check "page_act click without a target is refused" \
  error_with "$(BROKER="$tmp/broker.sock" call page_act '{"action":"click"}')" "target is required"
BROKER="$tmp/broker.sock" call page_act '{"action":"click","target":"--surface x"}' >/dev/null
check "page_act click takes a target that looks like a flag, sent as data" \
  requested '{"page": {"op": "act", "action": "click", "target": "--surface x"}}'
check "page_act has no eval action" \
  error_with "$(BROKER="$tmp/broker.sock" call page_act '{"action":"eval","target":"x"}')" "action must be one of"

check "page_check rejects a path without a leading slash" \
  error_with "$(BROKER=x call page_check '{"dir":"app","path":"settings"}')" "path must start with a single /"
check "page_check rejects a protocol-relative path" \
  error_with "$(BROKER=x call page_check '{"dir":"app","path":"//evil.test/x"}')" "path must start with a single /"

start_fake_next() {
  local before
  before="$(wc -l < "$tmp/ports.log" | tr -d ' ')"
  (cd "$tmp/project/app" && exec python3 "$tmp/fake-next.py") >/dev/null 2>&1 &
  fake_pid=$!
  for _ in $(seq 1 40); do
    [ "$(wc -l < "$tmp/ports.log" | tr -d ' ')" -gt "$before" ] && break
    sleep 0.25
  done
  fake_port="$(tail -n 1 "$tmp/ports.log")"
}

stop_fake_next() {
  kill "$fake_pid" 2>/dev/null
  wait "$fake_pid" 2>/dev/null
}

start_fake_next
printf '{"pid":%s,"port":%s,"hostname":"localhost","appUrl":"http://evil.test:1/","startedAt":0}' "$fake_pid" "$fake_port" > "$tmp/project/app/.next/dev/lock"
lock_status="$(call dev_status '{"dir":"app"}')"
check "a lock's port is used and its appUrl is ignored" contains "$lock_status" "http://localhost:$fake_port answers"
check "and the lock's appUrl host is never reported" lacks "$lock_status" "evil.test"
printf '{"pid":%s,"port":"%s","hostname":"localhost","appUrl":"http://localhost:%s/","startedAt":0}' "$fake_pid" "$fake_port" "$fake_port" > "$tmp/project/app/.next/dev/lock"
check "a lock whose port is a string is ignored" contains "$(call dev_status '{"dir":"app"}')" "no dev server answers"
stop_fake_next

mkdir -p "$tmp/project/scratch"
printf '{"name":"scratch","scripts":{"dev":"fake-server"}}\n' > "$tmp/project/scratch/package.json"
check "dev_start refuses a package.json that is not an app dir in git" \
  contains "$(call dev_start '{"dir":"scratch"}')" "scratch is not an app dir"

mkdir -p "$tmp/elsewhere"
printf '{"name":"linked","scripts":{"dev":"fake-server"}}\n' > "$tmp/elsewhere/package.json"
ln -s "$tmp/elsewhere" "$tmp/project/linked"
check "dev_status refuses a dir that is a symlink out of the repository" \
  error_with "$(call dev_status '{"dir":"linked"}')" "inside the repository"
check "dev_start refuses a dir that is a symlink out of the repository" \
  error_with "$(call dev_start '{"dir":"linked"}')" "inside the repository"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
