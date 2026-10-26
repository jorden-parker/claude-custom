#!/usr/bin/env bash
set -u
umask 022
server="$(cd "$(dirname "$0")" && pwd)/code-search.py"
tmp="$(mktemp -d)"
failures=0
stub_pid=""

trap 'stop_server; stop_stub; rm -rf "$tmp"' EXIT

cat > "$tmp/stub.py" <<'PY'
import hashlib
import json
import math
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

log_path, port_path, flag_path = sys.argv[1:4]


def word_vector(text):
    vector = [0.0] * 1024
    for word in re.findall(r"[a-z]+", text.lower()):
        vector[int(hashlib.sha1(word.encode()).hexdigest(), 16) % 256] += 1.0
    norm = math.sqrt(sum(value * value for value in vector)) or 1.0
    return [value / norm for value in vector]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def do_GET(self):
        if self.path != "/api/ps":
            self.send_response(404)
            self.end_headers()
            return
        models = [{"name": "qwen3-embedding:0.6b", "model": "qwen3-embedding:0.6b"}] if os.path.exists(flag_path) else []
        payload = json.dumps({"models": models}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with open(log_path, "a") as log:
            log.write(json.dumps({"path": self.path, "model": body["model"], "inputs": len(body["input"]), "keep_alive": body.get("keep_alive")}) + "\n")
        if body["model"] == "missing-model":
            payload = json.dumps({"error": 'model "missing-model" not found, try pulling it first'}).encode()
            self.send_response(404)
        else:
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

cat > "$tmp/index-peak.py" <<'PY'
import os
import runpy
import sys
import tracemalloc

server, repo = sys.argv[1:3]
os.chdir(repo)
sys.argv = [server, "--index"]
tracemalloc.start()
runpy.run_path(server, run_name="__main__")
print(tracemalloc.get_traced_memory()[1])
PY

start_stub() {
  rm -f "$tmp/port"
  python3 "$tmp/stub.py" "$tmp/embed.log" "$tmp/port" "$tmp/loaded" &
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

mode_of() {
  python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$1"
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
model_loaded() { touch "$tmp/loaded"; }
model_unloaded() { rm -f "$tmp/loaded"; }
index_with_stub() { rm -f "$tmp/embed.log"; (cd "$repo" && python3 "$server" --index >"$tmp/index.out" 2>&1); }
server_pid=""
start_server() {
  rm -f "$tmp/in" "$tmp/out"
  mkfifo "$tmp/in" "$tmp/out"
  (cd "$repo" && python3 "$server" < "$tmp/in" > "$tmp/out") &
  server_pid=$!
  exec 3> "$tmp/in" 4< "$tmp/out"
  send '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}' >/dev/null
}
send() {
  local reply
  printf '%s\n' "$1" >&3
  IFS= read -r reply <&4
  printf '%s' "$reply"
}
live_search() {
  rm -f "$tmp/embed.log"
  send "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"semantic_search\",\"arguments\":{\"query\":\"$1\"}}}" |
    python3 -c 'import json,sys; r=json.load(sys.stdin)["result"]; print("\n".join(c["text"] for c in r["content"]))'
}
stop_server() {
  if [ -n "$server_pid" ]; then
    exec 3>&- 4<&-
    wait "$server_pid" 2>/dev/null
    server_pid=""
  fi
}

repo="$tmp/repo"
mkdir -p "$repo/src"
git -C "$repo" init -q
printf 'def check_password(user, password):\n    return verify_hash(user.password_hash, password)\n' > "$repo/src/auth.py"
printf '#!/usr/bin/env python3\ndef draw_chart(points):\n    return render_svg_axis(points)\n' > "$repo/src/chart.py"
printf 'def save_index(path):\n    return write_atomic(path)\n' > "$repo/src/store.py"
printf '{"lockfileVersion": 3, "password": "password password"}\n' > "$repo/package-lock.json"
git -C "$repo" add -A

start_stub

listing="$(call list)"
check "server answers initialize and tools/list" contains "$listing" '"ids": [1, 2]'
check "tools/list offers semantic_search" contains "$listing" '"name": "semantic_search"'
check "initialize echoes the protocol version" contains "$listing" '"protocolVersion": "2025-06-18"'

model_loaded
index_with_stub
check "index mode embeds every chunk once while the model is loaded" [ "$(embedded_inputs_last_call)" = "3" ]
check "the index directory is private to its owner" [ "$(mode_of "$repo/.git/code-search")" = "0o700" ]
check "the index file is private to its owner" [ "$(mode_of "$repo/.git/code-search/index.json")" = "0o600" ]
check "index entries carry words and counts" grep -q '"terms": {' "$repo/.git/code-search/index.json"
check "index entries carry a version key" grep -q '"version": 2' "$repo/.git/code-search/index.json"

first="$(search "password check")"
first_text="$(printf '%s' "$first" | reply_text)"
check "best match comes first" first_line_starts_with "$first_text" "src/auth.py:1-2"
check "the best match scores 1.00" contains "$first_text" "src/auth.py:1-2  1.00  "
check "files with no matching word are left out" lacks "$first_text" "src/chart.py"
check "lockfiles are not indexed" lacks "$first_text" "package-lock.json"
check "a search embeds only the query" [ "$(embedded_inputs_last_call)" = "1" ]
check "the query embedding keeps the model alive" grep -q '"keep_alive": "30m"' "$tmp/embed.log"
check "no words-only note while the model is loaded" lacks "$first_text" "words only"

svg="$(search "svg axis" | reply_text)"
check "camelCase and snake_case identifiers are split into words" first_line_starts_with "$svg" "src/chart.py:1-3"
check "previews skip shebang lines" contains "$svg" "def draw_chart(points)"
check "plural and inflected query words match the code's form" first_line_starts_with "$(search "checking passwords" | reply_text)" "src/auth.py:1-2"
check "a past-tense query word matches the code's base form" first_line_starts_with "$(search "saved index" | reply_text)" "src/store.py:1-2"
check "english function words do not count" first_line_starts_with "$(search "where is the password" | reply_text)" "src/auth.py:1-2"

printf 'def draw_chart(points, password):\n    return render_svg_axis(points)\n' > "$repo/src/chart.py"
changed="$(search "password" | reply_text)"
check "a changed file is searchable by its new words at once" contains "$changed" "src/chart.py:1-2"
check "a search embeds the query but never a changed file" [ "$(embedded_inputs_last_call)" = "1" ]
check "a search does not write the index" lacks "$(cat "$repo/.git/code-search/index.json")" '"end": 2, "preview": "def draw_chart(points, password)'

index_with_stub
check "index mode embeds only the changed file" [ "$(embedded_inputs_last_call)" = "1" ]

model_unloaded
plain="$(search "password check" | reply_text)"
check "without the model the search still finds the words" first_line_starts_with "$plain" "src/auth.py:1-2"
check "without the model nothing is embedded" [ ! -e "$tmp/embed.log" ]
check "without the model the reply says words only" contains "$plain" "words only"
check "a query of only function words finds nothing" contains "$(search "where is the" | reply_text)" "No matching code."

allowed="$(CODE_SEARCH_EMBED=1 search "password check" | reply_text)"
check "with embeddings allowed the query is embedded even when the model is not loaded" [ "$(embedded_inputs_last_call)" = "1" ]
check "with embeddings allowed there is no words-only note" lacks "$allowed" "words only"

chmod 000 "$repo/src/chart.py"
still="$(search "chart" | reply_text)"
chmod 644 "$repo/src/chart.py"
check "an unchanged file is served from the index without being read" contains "$still" "src/chart.py"

rm "$repo/src/auth.py"
gone="$(search "password check" | reply_text)"
check "deleted files drop out of results" lacks "$gone" "src/auth.py"

python3 -c 'print("\n".join(f"line {i} filler" for i in range(1, 101)))' > "$repo/src/long.py"
long="$(search "filler" | reply_text)"
check "long files are split into line ranges" contains "$long" "src/long.py:31-70"

limited="$(call semantic_search '{"query": "filler", "limit": 1}' | reply_text)"
check "limit caps the number of results" [ "$(printf '%s\n' "$limited" | grep -c '^src/')" = "1" ]

model_unloaded
rm -f "$repo/.git/code-search/index.json"
index_with_stub
check "index mode exit status" [ $? -eq 0 ]
check "index mode writes the index" test -f "$repo/.git/code-search/index.json"
check "index mode prints a summary" grep -qE '^indexed [0-9]+ files' "$tmp/index.out"
check "index mode without the model writes no vectors" lacks "$(cat "$repo/.git/code-search/index.json")" '"vector"'
check "index mode without the model embeds nothing" [ ! -e "$tmp/embed.log" ]

big="$tmp/huge-repo"
mkdir -p "$big"
git -C "$big" init -q
printf 'def small():\n    return 1\n' > "$big/small.py"
dd if=/dev/zero of="$big/huge.bin" bs=1 count=0 seek=67108864 2>/dev/null
head -c 200000 /dev/zero | tr '\0' a > "$big/exact.txt"
head -c 200001 /dev/zero | tr '\0' a > "$big/over.txt"
index_peak_bytes() { python3 "$tmp/index-peak.py" "$server" "$big" | tail -n 1; }
check "indexing never holds a file over the size limit in memory" [ "$(index_peak_bytes)" -lt 16777216 ]
check "a file exactly at the size limit is indexed" contains "$(cat "$big/.git/code-search/index.json")" '"exact.txt": {'
check "a file one byte over the size limit is not indexed" lacks "$(cat "$big/.git/code-search/index.json")" '"over.txt"'
rm -f "$tmp/embed.log"
(cd "$repo" && CODE_SEARCH_EMBED=1 python3 "$server" --index >"$tmp/index.out" 2>&1)
check "index mode with embeddings allowed embeds the chunks" [ "$(embedded_inputs_last_call)" -ge 1 ]
check "index mode with embeddings allowed writes vectors" contains "$(cat "$repo/.git/code-search/index.json")" '"vector"'
(cd "$tmp" && python3 "$server" --index >"$tmp/index-nogit.out" 2>&1)
check "index mode outside git exits 1" [ $? -eq 1 ]
check "index mode outside git says why" grep -q 'git repository' "$tmp/index-nogit.out"

printf 'x = 1\n' > "$repo/src/x.py"
start_server
check "a running server answers" first_line_starts_with "$(live_search "filler")" "src/long.py:"
rm -f "$repo/.git/code-search/index.json"
check "the server answers from memory after the index file is deleted" first_line_starts_with "$(live_search "filler")" "src/long.py:"
check "single letters are not words" contains "$(live_search "x")" "No matching code."
model_loaded
index_with_stub
check "a newer index file is reloaded by the running server" first_line_starts_with "$(live_search "x")" "src/x.py:1-1"
stop_server

stop_stub
down="$(search "filler")"
check "an unreachable Ollama still answers from the word index" [ "$(printf '%s' "$down" | reply_is_error)" = "False" ]
check "an unreachable Ollama is reported as words only" contains "$(printf '%s' "$down" | reply_text)" "words only"
down_allowed="$(CODE_SEARCH_EMBED=1 search "filler")"
check "an unreachable Ollama with embeddings allowed is not a tool error" [ "$(printf '%s' "$down_allowed" | reply_is_error)" = "False" ]
check "an unreachable Ollama with embeddings allowed says words only and why" contains "$(printf '%s' "$down_allowed" | reply_text)" "words only: Embedding request to"

outside="$(cd "$tmp" && python3 "$tmp/client.py" "$server" semantic_search '{"query": "x"}' | reply_text)"
check "outside a git repo the tool explains why it can't search" contains "$outside" "git repository"

start_stub
raw="$(printf '%s\n' 'not json' '{"jsonrpc":"2.0","id":7,"method":"initialize","params":[1]}' '{"jsonrpc":"2.0","id":8,"method":"ping"}' | python3 "$server" 2>"$tmp/raw-stderr"; echo "exit=$?")"
check "a malformed line does not kill the server" contains "$raw" '"id": 8'
check "a non-object params gets an error reply, not a crash" contains "$raw" '"id": 7, "error"'
check "the server exits 0 at end of input" contains "$raw" 'exit=0'

python3 -c 'print("{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"ping\",\"params\":" + "[" * 1000000 + "]" * 1000000 + "}")' > "$tmp/too-deep.jsonl"
python3 -c 'print("{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"initialize\",\"params\":{\"protocolVersion\":" + "[" * 120000 + "]" * 120000 + "}}")' > "$tmp/too-deep-echo.jsonl"
too_deep="$({ cat "$tmp/too-deep.jsonl"; printf '%s\n' '{"jsonrpc":"2.0","id":8,"method":"ping"}'; } | python3 "$server"; echo "exit=$?")"
check "a line nested too deep to parse does not kill the server" contains "$too_deep" '"id": 8'
too_deep_echo="$({ cat "$tmp/too-deep-echo.jsonl"; printf '%s\n' '{"jsonrpc":"2.0","id":8,"method":"ping"}'; } | python3 "$server"; echo "exit=$?")"
check "a reply too deep to serialize does not kill the server" contains "$too_deep_echo" '"id": 8'
unhashable="$(printf '%s\n' '{"jsonrpc":"2.0","id":9,"method":["ping"]}' '{"jsonrpc":"2.0","id":10,"method":{"name":"ping"}}' '{"jsonrpc":"2.0","id":8,"method":"ping"}' | python3 "$server"; echo "exit=$?")"
check "a list method gets a method-not-found reply, not a crash" contains "$unhashable" '"id": 9, "error"'
check "a dict method gets a method-not-found reply, not a crash" contains "$unhashable" '"id": 10, "error"'
check "unhashable methods do not kill the server" contains "$unhashable" '"id": 8'

ln -s /etc/hosts "$repo/src/link-out"
printf 'secret = 1\n' > "$repo/src/locked.py"
chmod 000 "$repo/src/locked.py"
survived="$(search "filler")"
chmod 644 "$repo/src/locked.py"
check "an unreadable file is skipped, not fatal" [ "$(printf '%s' "$survived" | reply_is_error)" = "False" ]
check "symlinks are not indexed" lacks "$(printf '%s' "$survived" | reply_text)" "src/link-out"

missing="$(CODE_SEARCH_EMBED=1 CODE_SEARCH_MODEL=missing-model search "filler" | reply_text)"
check "an Ollama error reply is shown with its reason" contains "$missing" 'model "missing-model" not found, try pulling it first'

stub_host="${CODE_SEARCH_OLLAMA_URL#http://}"
rm -f "$tmp/embed.log"
(cd "$repo" && env -u CODE_SEARCH_OLLAMA_URL OLLAMA_HOST="$stub_host" CODE_SEARCH_EMBED=1 python3 "$tmp/client.py" "$server" semantic_search '{"query": "filler"}' >/dev/null)
check "OLLAMA_HOST picks the Ollama server when CODE_SEARCH_OLLAMA_URL is unset" [ -s "$tmp/embed.log" ]

if [ "$failures" -ne 0 ]; then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
