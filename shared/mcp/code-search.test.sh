#!/usr/bin/env bash
set -u
server="$(cd "$(dirname "$0")" && pwd)/code-search.py"
tmp="$(mktemp -d)"
failures=0
stub_pid=""

trap 'stop_stub; rm -rf "$tmp"' EXIT

cat > "$tmp/stub.py" <<'PY'
import hashlib
import json
import math
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

log_path, port_path = sys.argv[1:3]


def word_vector(text):
    vector = [0.0] * 1024
    for word in re.findall(r"[a-z]+", text.lower()):
        vector[int(hashlib.sha1(word.encode()).hexdigest(), 16) % 256] += 1.0
    norm = math.sqrt(sum(value * value for value in vector)) or 1.0
    return [value / norm for value in vector]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with open(log_path, "a") as log:
            log.write(json.dumps({"path": self.path, "model": body["model"], "inputs": len(body["input"])}) + "\n")
        payload = json.dumps({"embeddings": [word_vector(text) for text in body["input"]]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(port_path, "w") as port_file:
    port_file.write(str(server.server_port))
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
completed = subprocess.run([sys.executable, server], input=stdin, capture_output=True, text=True, timeout=60)
replies = [json.loads(line) for line in completed.stdout.splitlines() if line.strip()]
by_id = {reply.get("id"): reply for reply in replies}
print(json.dumps({"ids": sorted(by_id), "initialize": by_id.get(1), "reply": by_id.get(2), "stderr": completed.stderr}))
PY

start_stub() {
  rm -f "$tmp/port"
  python3 "$tmp/stub.py" "$tmp/embed.log" "$tmp/port" &
  stub_pid=$!
  while [ ! -s "$tmp/port" ]; do sleep 0.05; done
  CODE_SEARCH_OLLAMA_URL="http://127.0.0.1:$(cat "$tmp/port")"
  export CODE_SEARCH_OLLAMA_URL
}

stop_stub() {
  if [ -n "$stub_pid" ]; then
    kill "$stub_pid" 2>/dev/null
    wait "$stub_pid" 2>/dev/null
    stub_pid=""
  fi
}

call() {
  (cd "$repo" && python3 "$tmp/client.py" "$server" "$@")
}

reply_text() {
  python3 -c 'import json,sys; r=json.load(sys.stdin)["reply"]["result"]; print("\n".join(c["text"] for c in r["content"]))'
}

reply_is_error() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)["reply"]["result"].get("isError", False))'
}

embedded_inputs_last_call() {
  python3 -c 'import json,sys; lines=open(sys.argv[1]).read().splitlines(); print(sum(json.loads(l)["inputs"] for l in lines))' "$tmp/embed.log"
}

search() {
  rm -f "$tmp/embed.log"
  call semantic_search "{\"query\": \"$1\"}"
}

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

contains() { printf '%s' "$1" | grep -qF -- "$2"; }
lacks() { ! contains "$1" "$2"; }
first_line_starts_with() { case "${1%%$'\n'*}" in "$2"*) return 0 ;; esac; return 1; }

repo="$tmp/repo"
mkdir -p "$repo/src"
git -C "$repo" init -q
printf 'def check_password(user, password):\n    return verify_hash(user.password_hash, password)\n' > "$repo/src/auth.py"
printf '#!/usr/bin/env python3\ndef draw_chart(points):\n    return render_svg_axis(points)\n' > "$repo/src/chart.py"
printf '{"lockfileVersion": 3, "password": "password password"}\n' > "$repo/package-lock.json"
git -C "$repo" add -A

start_stub

listing="$(call list)"
check "server answers initialize and tools/list" contains "$listing" '"ids": [1, 2]'
check "tools/list offers semantic_search" contains "$listing" '"name": "semantic_search"'
check "initialize echoes the protocol version" contains "$listing" '"protocolVersion": "2025-06-18"'

first="$(search "password check")"
first_text="$(printf '%s' "$first" | reply_text)"
check "best match comes first" first_line_starts_with "$first_text" "src/auth.py:1-2"
check "results include other files ranked lower" contains "$first_text" "src/chart.py:1-3"
check "previews skip shebang lines" contains "$first_text" "def draw_chart(points)"
check "lockfiles are not indexed" lacks "$first_text" "package-lock.json"
check "results show a preview of the chunk" contains "$first_text" "def check_password"
check "first search embeds the two chunks and the query" [ "$(embedded_inputs_last_call)" = "3" ]
check "embeddings use qwen3-embedding:0.6b" grep -qF '"model": "qwen3-embedding:0.6b"' "$tmp/embed.log"
check "index is kept inside the git dir" test -f "$repo/.git/code-search/index.json"

search "password check" >/dev/null
check "unchanged files are not embedded again" [ "$(embedded_inputs_last_call)" = "1" ]

printf 'def draw_chart(points, password):\n    return render_svg_axis(points)\n' > "$repo/src/chart.py"
search "password check" >/dev/null
check "a changed file is embedded again on its own" [ "$(embedded_inputs_last_call)" = "2" ]

rm "$repo/src/auth.py"
gone="$(search "password check" | reply_text)"
check "deleted files drop out of results" lacks "$gone" "src/auth.py"

python3 -c 'print("\n".join(f"line {i} filler" for i in range(1, 101)))' > "$repo/src/long.py"
long="$(search "filler" | reply_text)"
check "long files are split into line ranges" contains "$long" "src/long.py:31-70"

limited="$(call semantic_search '{"query": "filler", "limit": 1}' | reply_text)"
check "limit caps the number of results" [ "$(printf '%s\n' "$limited" | grep -c '^src/')" = "1" ]

rm -f "$repo/.git/code-search/index.json"
(cd "$repo" && python3 "$server" --index >"$tmp/index.out" 2>&1)
check "index mode exit status" [ $? -eq 0 ]
check "index mode writes the index" test -f "$repo/.git/code-search/index.json"
check "index mode prints a summary" grep -qE '^indexed [0-9]+ files' "$tmp/index.out"
(cd "$tmp" && python3 "$server" --index >"$tmp/index-nogit.out" 2>&1)
check "index mode outside git exits 1" [ $? -eq 1 ]
check "index mode outside git says why" grep -q 'git repository' "$tmp/index-nogit.out"

stop_stub
down="$(search "password check")"
check "an unreachable Ollama is reported as a tool error" [ "$(printf '%s' "$down" | reply_is_error)" = "True" ]
check "the error says how to fix it" contains "$(printf '%s' "$down" | reply_text)" "ollama pull qwen3-embedding:0.6b"
check "the error names the picker row" contains "$(printf '%s' "$down" | reply_text)" "Set up embedding model"

outside="$(cd "$tmp" && python3 "$tmp/client.py" "$server" semantic_search '{"query": "x"}' | reply_text)"
check "outside a git repo the tool explains why it can't search" contains "$outside" "git repository"

if [ "$failures" -ne 0 ]; then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
