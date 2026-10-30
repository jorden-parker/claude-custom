#!/usr/bin/env bash
set -u
umask 022
server="$(cd "$(dirname "$0")" && pwd)/dev-server.py"
tmp="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
failures=0

trap 'rm -rf "$tmp"' EXIT

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

commanded() {
  grep -qF -- "$1" "$tmp/cmux.log"
}

section() {
  awk -v name="$1" '$0 ~ ("^### [0-9]+ " name "$") { on = 1; next } /^### / { on = 0 } on' "$2"
}

mkdir -p "$tmp/project/app" "$tmp/bin" "$tmp/bin-nocmux" "$tmp/state"
ln -s "$(command -v python3)" "$tmp/bin-nocmux/python3"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -subj /CN=localhost -days 1 >/dev/null 2>&1
export FAKE_TLS_CERT="$tmp/cert.pem" FAKE_TLS_KEY="$tmp/key.pem"
printf '{"name":"root","private":true}\n' > "$tmp/project/package.json"
printf '{"name":"app","scripts":{"dev":"fake-server","dev:web":"fake-server","dev:https":"fake-server --experimental-https","build":"next build"}}\n' > "$tmp/project/app/package.json"
git -C "$tmp/project" init -q
git -C "$tmp/project" add -A
git -C "$tmp/project" -c user.name=test -c user.email=test@example.test commit -qm init

cat > "$tmp/bin/npm" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DEV_TEST_DIR/npm.log"
case "$*" in
  "run dev:https") FAKE_TLS=1 exec python3 "$DEV_TEST_DIR/fake-next.py" ;;
  "run dev" | "run dev:"*) exec python3 "$DEV_TEST_DIR/fake-next.py" ;;
esac
exit 1
SH

chmod +x "$tmp/bin/npm"
cat > "$tmp/bin/cmux" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DEV_TEST_DIR/cmux.log"
[ "$1" = "--json" ] && shift
[ "$1" = "browser" ] || exit 2
shift
surface=""
if [ "$1" = "--surface" ]; then
  surface="$2"
  shift 2
fi
verb="$1"
shift
state="$DEV_TEST_DIR/cmux.surface"
url_file="$DEV_TEST_DIR/cmux.url"
profile_file="$DEV_TEST_DIR/cmux.profile"
if [ "$verb" = "profiles" ]; then
  case "$1" in
    list)
      if [ -f "$profile_file" ]; then
        printf '{"profiles":[{"id":"profile-default","name":"Default","slug":"default"},{"id":"profile-cc","name":"claude-ollama","slug":"claude-ollama"}]}\n'
      else
        printf '{"profiles":[{"id":"profile-default","name":"Default","slug":"default"}]}\n'
      fi ;;
    add) : > "$profile_file"; printf '{"created":true,"profile":{"id":"profile-cc","name":"%s","slug":"%s"}}\n' "$2" "$2" ;;
    *) echo "Error: unknown profiles $1"; exit 1 ;;
  esac
  exit 0
fi
if [ "$verb" = "open-split" ]; then
  case "$*" in
    *"--profile profile-cc"*) ;;
    *) echo "Error: invalid_params: open-split needs the claude-ollama profile"; exit 1 ;;
  esac
  printf 'surface:7\n' > "$state"
  printf '%s\n' "$1" > "$url_file"
  printf '{"surface_ref":"surface:7","created_split":true}\n'
  exit 0
fi
if [ ! -f "$state" ] || [ "$surface" != "$(cat "$state")" ]; then
  echo "Error: invalid_params: Missing or invalid surface_id"
  exit 1
fi
case "$verb ${1:-}" in
  "goto "*) [ -n "${STUB_CMUX_STUCK:-}" ] || printf '%s\n' "$1" > "$url_file"; echo OK ;;
  "get url") cat "$url_file" ;;
  "console list") printf '{"count":2,"entries":[{"level":"warn","text":"If you do not provide a visible label, you must specify an aria-label or aria-labelledby attribute for accessibility"},{"level":"log","text":"noise"}]}\n' ;;
  "errors list") printf '{"count":1,"errors":[{"message":"TypeError: x is undefined","source":"http://localhost:1/x","line":3}]}\n' ;;
  "snapshot --interactive") printf -- '- document "App"\n  - button "Save" [ref=e1]\n  - textbox "Name" [ref=e2]\n' ;;
  "click "*)
    [ -z "${STUB_CMUX_LEAVE:-}" ] || printf 'https://example.com/\n' > "$url_file"
    echo OK ;;
  "wait "*|"console clear"|"errors clear"|"fill "*|"type "*|"press "*|"select "*|"scroll "*|"dblclick "*|"hover "*|"focus "*|"check "*|"uncheck "*) echo OK ;;
  *) echo "Error: unknown $verb ${1:-}"; exit 1 ;;
esac
SH
chmod +x "$tmp/bin/cmux"
cat > "$tmp/bin/lsof" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DEV_TEST_DIR/lsof.log"
[ -z "${STUB_LSOF_FAIL:-}" ] || exit 1
[ -f "$DEV_TEST_DIR/fake.cwd" ] || exit 1
pid="$(cat "$DEV_TEST_DIR/fake.pid")"
case "$*" in
  *LISTEN*) printf 'p%s\nf5\nn127.0.0.1:%s\np99999\nf3\nn*:1\n' "$pid" "$(tail -n 1 "$DEV_TEST_DIR/ports.log")" ;;
  *cwd*) printf 'p%s\nfcwd\nn%s\np99999\nfcwd\nn/elsewhere\n' "$pid" "$(cat "$DEV_TEST_DIR/fake.cwd")" ;;
esac
SH
chmod +x "$tmp/bin/lsof"
export CMUX="$tmp/cmux.sock"

cat > "$tmp/fake-next.py" <<'PY'
import http.server
import json
import os
import socketserver
import ssl

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
scheme = "https" if os.environ.get("FAKE_TLS") else "http"
if scheme == "https":
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(os.environ["FAKE_TLS_CERT"], os.environ["FAKE_TLS_KEY"])
    server.socket = context.wrap_socket(server.socket, server_side=True)
port = server.server_address[1]
os.makedirs(".next/dev", exist_ok=True)
with open(".next/dev/lock", "w") as lock:
    json.dump({"pid": os.getpid(), "port": port, "hostname": "localhost", "appUrl": "%s://localhost:%d" % (scheme, port), "startedAt": 0}, lock)
with open(ports_log, "a") as log:
    log.write("%d\n" % port)
print("   \x1b[1m- Local:\x1b[0m        %s://localhost:%d%s" % (scheme, port, os.environ.get("FAKE_LOCAL_SUFFIX", "")), flush=True)
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
    unset CLAUDE_OLLAMA_CMUX CMUX_SOCKET_PATH
    if [ -n "${CMUX_OFF_FOR_TEST:-}" ]; then
      export CLAUDE_OLLAMA_CMUX=0
    fi
    if [ -n "${CMUX:-}" ]; then
      export CMUX_SOCKET_PATH="$CMUX"
    fi
    PATH="$tmp/bin:$PATH"
    if [ -n "${PATH_WITHOUT_CMUX:-}" ]; then
      PATH="$tmp/bin-nocmux:/usr/bin:/bin"
    fi
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
https_out="$tmp/session-https.out"
session "$https_out" \
  '["dev_start",{"dir":"app","script":"dev:https"}]' \
  '["dev_status",{"dir":"app"}]' \
  '["dev_errors",{"dir":"app"}]' \
  '["dev_stop",{"dir":"app"}]'
https_port="$(tail -n 1 "$tmp/ports.log")"
check "dev_start keeps the https scheme the server printed" \
  contains "$(section dev_start "$https_out")" "ready at https://localhost:$https_port"
check "dev_status probes the https URL" \
  contains "$(section dev_status "$https_out")" "https://localhost:$https_port answers (HTTP 200), pid"
check "dev_errors reaches /_next/mcp over https" \
  contains "$(section dev_errors "$https_out")" "Hydration failed"
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
  error_with "$(call page_snapshot '{}')" "call page_check first"
check "page_act before any page_check says to call page_check first" \
  error_with "$(call page_act '{"action":"click","target":"e1"}')" "call page_check first"

check "page_check without CMUX_SOCKET_PATH says to launch from a cmux terminal" \
  error_with "$(CMUX='' call page_check '{"dir":"app","path":"/settings"}')" "cmux terminal"
check "page_check with CLAUDE_OLLAMA_CMUX=0 says the browser is off" \
  error_with "$(CMUX_OFF_FOR_TEST=1 call page_check '{"dir":"app","path":"/settings"}')" "is off"
check "page_check without a cmux command says to launch from a cmux terminal" \
  error_with "$(PATH_WITHOUT_CMUX=1 call page_check '{"dir":"app","path":"/settings"}')" "cmux terminal"

browser_out="$tmp/session-browser.out"
session "$browser_out" \
  '["dev_start",{"dir":"app"}]' \
  '["page_check",{"dir":"app","path":"/settings"}]' \
  '["page_check",{"dir":"app","path":"/other"}]'
browser_port="$(tail -n 1 "$tmp/ports.log")"
page="$(section page_check "$browser_out")"
check "page_check reports browser errors" contains "$page" "Browser errors:"
check "and the TypeError from errors list" contains "$page" "TypeError: x is undefined"
check "and the console warning from console list" contains "$page" "aria-label"
check "and the Next.js error from get_errors" contains "$page" "Hydration failed"
check "page_check names the surface it uses" contains "$page" "Surface: surface:7"
check "page_check adds the claude-ollama browser profile when the browser lacks it" commanded "browser profiles add claude-ollama"
check "and opens the page in that profile" commanded "--focus false --profile profile-cc"
check "the first page_check opens a browser split on the page without taking focus" \
  commanded "--json browser open-split http://localhost:$browser_port/settings --focus false"
check "a later page_check navigates the same surface" \
  commanded "browser --surface surface:7 goto http://localhost:$browser_port/other"
check "and clears the browser's console and errors first" commanded "browser --surface surface:7 errors clear"
check "page_check waits for the page to load" commanded "wait --load-state complete --timeout-ms 15000"
https_browser_out="$tmp/session-https-browser.out"
session "$https_browser_out" \
  '["dev_start",{"dir":"app","script":"dev:https"}]' \
  '["page_check",{"dir":"app","path":"/secure"}]'
https_browser_port="$(tail -n 1 "$tmp/ports.log")"
check "page_check opens the https URL" \
  commanded "open-split https://localhost:$https_browser_port/secure --focus false"
url_page="$(call page_check '{"url":"https://127.0.0.1:4000/settings"}')"
check "page_check with url opens that URL without probing" \
  commanded "open-split https://127.0.0.1:4000/settings --focus false"
check "and reports the page it opened" contains "$url_page" "Page: https://127.0.0.1:4000/settings"
check "and says the origin is not a Next.js server when nothing answers /_next/mcp" contains "$url_page" "not a Next.js 16+ dev server"
call page_check '{"url":"http://[::1]:5173/"}' >/dev/null
check "page_check with an IPv6 loopback url opens it" commanded "open-split http://[::1]:5173/ --focus false"
check "page_check refuses a url on another host" \
  error_with "$(call page_check '{"url":"https://evil.test/x"}')" "url must start with http:// or https://"
check "page_check refuses a url whose userinfo names localhost" \
  error_with "$(call page_check '{"url":"http://localhost@evil.test:4000/x"}')" "url must start with"
check "page_check refuses a url with a bad port" \
  error_with "$(call page_check '{"url":"http://localhost:port/x"}')" "url must start with"
check "page_check refuses a file url" \
  error_with "$(call page_check '{"url":"file:///etc/hosts"}')" "url must start with"

: > "$tmp/cmux.log"
act_out="$tmp/session-act.out"
session "$act_out" \
  '["dev_start",{"dir":"app"}]' \
  '["page_check",{"dir":"app","path":"/settings"}]' \
  '["page_snapshot",{}]' \
  '["page_act",{"action":"fill","target":"e2","text":"Ada"}]' \
  '["page_act",{"action":"press","text":"Enter"}]' \
  '["page_act",{"action":"scroll","text":"300"}]'
snapshot="$(section page_snapshot "$act_out")"
check "page_snapshot lists elements with refs" contains "$snapshot" "[ref=e1]"
check "page_snapshot asks the browser for the interactive elements" commanded "browser --surface surface:7 snapshot --interactive"
fill="$(section page_act "$act_out")"
check "page_act fill asks the browser to fill the ref with the text, in forms cmux cannot read as options" \
  commanded "browser --surface surface:7 fill --selector=e2 --text=Ada"
check "page_act reports the URL, browser errors, console and elements" \
  [ "$(printf '%s\n' "$fill" | grep -c -e '^URL now:' -e '^Browser errors:' -e '^Console:' -e '^Elements:')" -ge 4 ]
check "page_act press asks the browser for the key" commanded "press --key=Enter"
check "page_act scroll asks the browser for the pixels" commanded "scroll --dy=300"
check "a session with the profile already in the browser does not add it again" [ "$(grep -c 'browser profiles add' "$tmp/cmux.log")" = 0 ]
leave_out="$tmp/session-leave.out"
(export STUB_CMUX_LEAVE=1; session "$leave_out" '["dev_start",{"dir":"app"}]' '["page_check",{"dir":"app"}]' '["page_act",{"action":"click","target":"e3"}]')
left="$(section page_act "$leave_out")"
check "page_act that leaves the local server goes back and says so" \
  contains "$left" "left the local server for https://example.com/; went back to the local server"
check "and reports the local URL again" contains "$left" "URL now: http://localhost:"
check "and sent the browser to the dev server, not back in history" \
  commanded "browser --surface surface:7 goto http://localhost:$(tail -n 1 "$tmp/ports.log")"
away_out="$tmp/session-away.out"
session "$away_out" '["dev_start",{"dir":"app"}]' '["page_check",{"dir":"app"}]' \
  "sh:printf 'https://example.com/\\n' > \"\$DEV_TEST_DIR/cmux.url\"" '["page_snapshot",{}]'
away_snapshot="$(section page_snapshot "$away_out")"
check "page_snapshot on a page that left the local server goes back first and says so" \
  contains "$away_snapshot" "left the local server for https://example.com/; went back to the local server"
check "and still lists the elements" contains "$away_snapshot" "[ref=e1]"
stuck_out="$tmp/session-stuck.out"
(export STUB_CMUX_STUCK=1; session "$stuck_out" '["dev_start",{"dir":"app"}]' '["page_check",{"dir":"app"}]' \
  "sh:printf 'https://example.com/\\n' > \"\$DEV_TEST_DIR/cmux.url\"" '["page_snapshot",{}]' '["page_act",{"action":"click","target":"e1"}]')
check "page_snapshot on a page that will not come back is refused and names the page" \
  error_with "$(section page_snapshot "$stuck_out")" "the page is on https://example.com/, not the local server"
check "page_act on a page that will not come back is refused before acting" \
  error_with "$(section page_act "$stuck_out")" "not the local server"
check "and no click reached the browser" [ "$(grep -c 'click --selector=e1' "$tmp/cmux.log")" = 0 ]
: > "$tmp/cmux.log"
reopen_out="$tmp/session-reopen.out"
session "$reopen_out" '["dev_start",{"dir":"app"}]' '["page_check",{"dir":"app"}]' "sh:rm \"\$DEV_TEST_DIR/cmux.surface\"" '["page_check",{"dir":"app","path":"/again"}]'
check "a surface the user closed is opened again" [ "$(grep -c 'browser open-split' "$tmp/cmux.log")" = 2 ]
check "and the new page is opened on it" commanded "open-split http://localhost:$(tail -n 1 "$tmp/ports.log")/again --focus false"
check "page_act click without a target is refused" \
  error_with "$(call page_act '{"action":"click"}')" "target is required"
check "page_act before any page in this session says to call page_check first" \
  error_with "$(call page_act '{"action":"click","target":"--surface x"}')" "call page_check first"
dash_out="$tmp/session-dash.out"
session "$dash_out" '["dev_start",{"dir":"app"}]' '["page_check",{"dir":"app"}]' '["page_act",{"action":"click","target":"--snapshot-after"}]'
check "page_act passes a target that looks like an option as the selector value" \
  commanded "surface:7 click --selector=--snapshot-after"
check "page_act has no eval action" \
  error_with "$(call page_act '{"action":"eval","target":"x"}')" "action must be one of"

check "page_check rejects a path without a leading slash" \
  error_with "$(call page_check '{"dir":"app","path":"settings"}')" "path must start with a single /"
check "page_check rejects a protocol-relative path" \
  error_with "$(call page_check '{"dir":"app","path":"//evil.test/x"}')" "path must start with a single /"

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
  printf '%s' "$fake_pid" > "$tmp/fake.pid"
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
FAKE_TLS=1 start_fake_next
check "a lock whose appUrl is https gives an https candidate" \
  contains "$(call dev_status '{"dir":"app"}')" "https://localhost:$fake_port answers"
printf '{"pid":%s,"port":%s,"hostname":"localhost","appUrl":"http://localhost:%s/","startedAt":0}' "$fake_pid" "$fake_port" "$fake_port" > "$tmp/project/app/.next/dev/lock"
check "an https server with no https hint is found over https" \
  contains "$(call dev_status '{"dir":"app"}')" "https://localhost:$fake_port answers (HTTP 200)"
stop_fake_next
start_fake_next
printf '{"pid":%s,"port":%s,"hostname":"localhost","appUrl":"https://localhost:%s/","startedAt":0}' "$fake_pid" "$fake_port" "$fake_port" > "$tmp/project/app/.next/dev/lock"
check "an http server whose lock says https is found over http" \
  contains "$(call dev_status '{"dir":"app"}')" "http://localhost:$fake_port answers (HTTP 200)"
stop_fake_next
start_fake_next
rm -f "$tmp/project/app/.next/dev/lock"
(cd "$tmp/project/app" && pwd -P) > "$tmp/fake.cwd"
listening="$(call dev_status '{"dir":"app"}')"
check "a server listening from the app dir is found without a lock or port flag" \
  contains "$listening" "http://localhost:$fake_port answers (HTTP 200), pid $fake_pid, from a server listening from app"
check "the listener lookup asks lsof for the listening sockets' owners' folders" grep -q -- '-a -d cwd -p' "$tmp/lsof.log"
(cd "$tmp/project" && pwd -P) > "$tmp/fake.cwd"
check "a server listening from another folder is not reported" \
  contains "$(call dev_status '{"dir":"app"}')" "no dev server answers"
check "dev_status survives a failing lsof" \
  contains "$(STUB_LSOF_FAIL=1 call dev_status '{"dir":"app"}')" "no dev server answers"
rm -f "$tmp/fake.cwd"
stop_fake_next

cat > "$tmp/silent-port.py" <<'PY'
import socket
import sys
import time

listener = socket.socket()
listener.bind(("127.0.0.1", 0))
listener.listen(8)
with open(sys.argv[1], "w") as port_file:
    port_file.write(str(listener.getsockname()[1]))
time.sleep(120)
PY

start_silent_port() {
  rm -f "$tmp/silent.port"
  python3 "$tmp/silent-port.py" "$tmp/silent.port" &
  silent_pid=$!
  for _ in $(seq 1 40); do
    [ -s "$tmp/silent.port" ] && break
    sleep 0.1
  done
  silent_port="$(cat "$tmp/silent.port")"
}

use_held_script() {
  printf '{"name":"app","scripts":{"dev":"fake-server","dev:held":"fake-server --port %s"}}\n' "$1" > "$tmp/project/app/package.json"
}

launches_of_held_script() {
  grep -cxF "run dev:held" "$tmp/npm.log"
}

rm -f "$tmp/project/app/.next/dev/lock"
start_silent_port
use_held_script "$silent_port"
held_out="$(call dev_start '{"dir":"app","script":"dev:held"}')"
check "dev_start refuses a script's port that is held but silent" \
  contains "$held_out" "port $silent_port is in use (from the dev script)"
check "and it launches nothing over the held port" [ "$(launches_of_held_script)" = "0" ]
kill "$silent_pid" 2>/dev/null
wait "$silent_pid" 2>/dev/null

start_fake_next
rm -f "$tmp/project/app/.next/dev/lock"
use_held_script "$fake_port"
check "dev_start finds a server on the requested script's own port" \
  contains "$(call dev_start '{"dir":"app","script":"dev:held"}')" "already running at http://localhost:$fake_port"
check "and it launches nothing beside that server" [ "$(launches_of_held_script)" = "0" ]
stop_fake_next
printf '{"name":"app","scripts":{"dev":"fake-server","dev:web":"fake-server","dev:https":"fake-server --experimental-https","build":"next build"}}\n' > "$tmp/project/app/package.json"

cat > "$tmp/framework-port.py" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("dev_server", sys.argv[1])
dev_server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev_server)
dev_server.port_is_open = lambda url: True
print(dev_server.busy_candidate("app", "next dev"))
PY
check "a held framework default port does not block a start, since the framework moves on" \
  [ "$(PYTHONPATH="$(dirname "$server")" run_in_project python3 "$tmp/framework-port.py" "$server")" = "None" ]

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
