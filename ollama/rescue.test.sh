#!/usr/bin/env bash
set -u
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
rescue="$repo_dir/ollama/rescue.py"
tmp="$(mktemp -d)"
failures=0
ps_stub_pid=""

trap 'stop_ps_stub; rm -rf "$tmp"' EXIT

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
section() { awk -v heading="## $2" 'substr($0, 1, length(heading)) == heading {inside = 1; next} /^## / {inside = 0} inside' "$1"; }
section_has() { section "$1" "$2" | grep -q -- "$3"; }
section_lacks() { ! section "$1" "$2" | grep -q -- "$3"; }
section_lines() { section "$1" "$2" | grep -c -- "$3"; }
lacks_text() { ! grep -q -- "$1" "$2"; }

stop_ps_stub() {
  [ -n "$ps_stub_pid" ] || return 0
  kill "$ps_stub_pid" 2>/dev/null
  wait "$ps_stub_pid" 2>/dev/null
  ps_stub_pid=""
}

cat > "$tmp/ps_server.py" <<'PY'
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def do_GET(self):
        if self.path != "/api/ps":
            self.send_error(404)
            return
        payload = json.dumps({"models": [{"name": "qwen3.8-27b-cc", "size_vram": 17000000000, "context_length": 65536}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


server = HTTPServer(("127.0.0.1", 0), Handler)
Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
PY

python3 "$tmp/ps_server.py" "$tmp/ps.port" &
ps_stub_pid=$!
for _ in $(seq 100); do
  [ -s "$tmp/ps.port" ] && break
  sleep 0.05
done
ollama_url="http://127.0.0.1:$(cat "$tmp/ps.port")"

home="$tmp/home"
session="$home/.claude-ollama"
state="$home/state"
mkdir -p "$session/proxy/record" "$state/incidents" "$state/proxy" "$tmp/stubbin" "$tmp/project"
server_log="$tmp/ollama-server.log"
seq 1 100 | sed 's/^/server line /' > "$server_log"
seq 1 100 | sed 's/^/launcher line /' > "$state/launcher.log"
echo "launcher saw Bearer abcdefghijklmnop" >> "$state/launcher.log"

cat > "$tmp/stubbin/claude-ollama" <<EOF
#!/bin/sh
case "\$1" in
  doctor)
    echo "ok   jq on PATH"
    echo "ok   profile $home/.config/claude-custom/profiles/ollama-\$2.json: none"
    echo "warn token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcd seen"
    echo "fail server env OLLAMA_FLASH_ATTENTION=1 not set on the running server"
    exit 1 ;;
  --print-config)
    seq 1 120 | sed 's/^/config line /'
    exit 0 ;;
  logs)
    if [ -n "\${STUB_NO_SERVER_LOG:-}" ]; then exit 1; fi
    echo "$server_log" ;;
esac
EOF
cat > "$tmp/stubbin/sync-fingerprint" <<'EOF'
#!/bin/sh
echo '{"commit": "abc1234", "fingerprint": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", "host": "work-laptop"}'
EOF
cat > "$tmp/stubbin/ollama-lease" <<'EOF'
#!/bin/sh
[ "$1" = holders ] || exit 2
echo "live session pid 4242 model qwen3.8-27b-cc rung context-down"
echo "live embedding pid 4300 model qwen3-embedding:0.6b rung -"
EOF
chmod +x "$tmp/stubbin"/*
printf 'OLLAMA_KEEP_ALIVE=30m\nOLLAMA_MAX_LOADED_MODELS=2\nGITHUB_TOKEN=ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcd\n' > "$tmp/server.env"

incidents_file="$state/incidents/20261102-100000-7.jsonl"
python3 - "$incidents_file" <<'PY'
import json
import sys

rows = []
for index in range(60):
    cause = ["reprefilled", "truncated", "evicted"][index % 3]
    rows.append({"ts": f"2026-11-02T10:{index:02d}:00Z", "cause": cause, "detail": f"row {index} secret sk-abcdefghijklmnopqrstuvwxyz", "tokens": None, "rule": None})
rows.insert(30, {"kind": "health", "ts": "2026-11-02T10:30:30Z", "rules": {}, "unmatched": 0, "lines": 5})
with open(sys.argv[1], "w") as handle:
    for row in rows:
        handle.write(json.dumps(row) + "\n")
PY
printf '%s\n' "$incidents_file" > "$state/incidents/current"

python3 - "$state/proxy/requests.jsonl" <<'PY'
import json
import sys
from datetime import datetime, timedelta, timezone

now = datetime.now(timezone.utc)


def row(minutes_ago, diverged_at, stable, diff):
    ts = (now - timedelta(minutes=minutes_ago)).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    return {"ts": ts, "request_id": "r", "sections": 6, "stable_sections": stable, "diverged_at": diverged_at, "offset": 3, "diff": diff, "prompt_bytes": 100}


rows = [
    row(500, "system", 0, "old row outside the window"),
    row(50, "system", 0, "Today is Monday"),
    row(40, "system", 0, "Today is Tuesday"),
    row(30, "tools", 1, "tool list changed"),
    row(20, "message:5", 5, "newest user turn with token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcd"),
    row(10, None, 6, None),
    row(5, "message:2", 2, "an older turn changed"),
]
with open(sys.argv[1], "w") as handle:
    for entry in rows:
        handle.write(json.dumps(entry) + "\n")
PY
for name in a b c; do echo '{"model": "x"}' > "$session/proxy/record/$name.json"; done

git -C "$tmp/project" init -q
mkdir -p "$tmp/project/.git/handoff"
seq 1 40 | sed 's/^/older note line /' > "$tmp/project/.git/handoff/20261101-000000.md"
sleep 1
seq 1 40 | sed "s|^|newest note line $home/ |" > "$tmp/project/.git/handoff/20261102-000000.md"

run_rescue() {
  (cd "$tmp/project" && HOME="$home" python3 "$rescue" \
    --launcher "$tmp/stubbin/claude-ollama" --size 27b \
    --fingerprint-bin "$tmp/stubbin/sync-fingerprint" --lease-bin "$tmp/stubbin/ollama-lease" \
    --session-dir "$session" --state-dir "$state" --ollama-url "$ollama_url" --server-env "$tmp/server.env" "$@")
}

run_rescue > "$tmp/stdout" 2> "$tmp/stderr"
status=$?
check "a full run exits 0 even when doctor fails" [ "$status" -eq 0 ]
report="$(sed -n 1p "$tmp/stdout")"
report_path="${report/#\~/$home}"
check "the first stdout line is the report path" [ -f "$report_path" ]
check "the report path shows HOME as ~" [ "${report#\~/}" != "$report" ]
check "the report lives under the session rescue folder" [ "$(dirname "$report_path")" = "$session/rescue" ]
check "the report name is a utc time with .md" sh -c "basename '$report_path' | grep -Eq '^[0-9]{8}-[0-9]{6}Z?\.md$'"
check "stdout has the path plus five summary lines" [ "$(wc -l < "$tmp/stdout" | tr -d ' ')" -eq 6 ]
check "the summary names doctor" grep -q '^doctor:' "$tmp/stdout"
check "the summary names incidents" grep -q '^incidents:' "$tmp/stdout"
check "the summary names the proxy" grep -q '^proxy:' "$tmp/stdout"
check "the summary names the lease" grep -q '^lease:' "$tmp/stdout"
check "the summary names memory" grep -q '^memory:' "$tmp/stdout"
check "the rescue folder is private" [ "$(mode_of "$session/rescue")" = 700 ]
check "the report file is private" [ "$(mode_of "$report_path")" = 600 ]

for heading in "Doctor" "Print config" "Sync fingerprint" "Server env and runners" "Lease holders and rung" "Incidents" "Messages proxy" "Launcher log tail" "Ollama server log tail" "Newest handoff note" "Free memory"; do
  check "the report has a $heading section" grep -q "^## $heading" "$report_path"
done

check "doctor output is included" section_has "$report_path" "Doctor" "ok   jq on PATH"
check "doctor's exit status is noted" section_has "$report_path" "Doctor" "exit 1"
check "print-config output is capped" [ "$(section_lines "$report_path" "Print config" '^config line')" -le 80 ]
check "a capped section says how many lines were hidden" section_has "$report_path" "Print config" "more lines hidden"
check "the fingerprint host is included" section_has "$report_path" "Sync fingerprint" "work-laptop"
check "the server env is included" section_has "$report_path" "Server env and runners" "OLLAMA_KEEP_ALIVE=30m"
check "the loaded runners are included" section_has "$report_path" "Server env and runners" "qwen3.8-27b-cc"
check "the lease holders are included" section_has "$report_path" "Lease holders and rung" "live session pid 4242"
check "the current rung is named" section_has "$report_path" "Lease holders and rung" "rung: context-down"
check "the incidents keep the last 50 rows" [ "$(section_lines "$report_path" "Incidents" '"cause"')" -eq 50 ]
check "the newest incident row is kept" section_has "$report_path" "Incidents" "row 59 "
check "the oldest incident rows are dropped" section_lacks "$report_path" "Incidents" "row 9 "
check "health rows are skipped" section_lacks "$report_path" "Incidents" '"kind": "health"'
check "the incidents count per cause over the whole file" section_has "$report_path" "Incidents" "reprefilled: 20"
check "the proxy section counts the windowed requests" section_has "$report_path" "Messages proxy" "requests: 6"
check "the proxy section skips rows outside the window" section_lacks "$report_path" "Messages proxy" "outside the window"
check "the proxy section reports the prefix hit rate" section_has "$report_path" "Messages proxy" "prefix hit rate: 33% (2 of 6"
first_diverging="$(section "$report_path" "Messages proxy" | grep '^- ' | head -1)"
check "the top diverging section comes first" grep -q 'system: 2' <<< "$first_diverging"
check "a diverging section shows its diff" section_has "$report_path" "Messages proxy" "Today is Tuesday"
check "at most three diverging sections are listed" [ "$(section_lines "$report_path" "Messages proxy" '^- ')" -le 3 ]
check "the record dir and its count are named" section_has "$report_path" "Messages proxy" "record dir: ~/.claude-ollama/proxy/record (3 requests)"
check "the launcher log tail keeps 60 lines" [ "$(section_lines "$report_path" "Launcher log tail" 'launcher')" -eq 60 ]
check "the launcher log tail ends with the newest line" section_has "$report_path" "Launcher log tail" "launcher saw Bearer <redacted>"
check "the server log tail keeps 60 lines" [ "$(section_lines "$report_path" "Ollama server log tail" '^server line')" -eq 60 ]
check "the server log tail ends with the newest line" section_has "$report_path" "Ollama server log tail" "server line 100"
check "the newest handoff note is included" section_has "$report_path" "Newest handoff note" "newest note line"
check "the older handoff note is skipped" section_lacks "$report_path" "Newest handoff note" "older note line"
check "the handoff note keeps 20 lines" [ "$(section_lines "$report_path" "Newest handoff note" 'newest note line')" -eq 20 ]
check "the free memory section has a line" [ -n "$(section "$report_path" "Free memory" | grep -v -e '^```' -e '^$' | head -1)" ]

check "github tokens are redacted" lacks_text "ghp_" "$report_path"
check "sk- keys are redacted" lacks_text "sk-abc" "$report_path"
check "long hex strings are redacted" lacks_text "0123456789abcdef0123456789abcdef" "$report_path"
check "bearer tokens are redacted" lacks_text "Bearer abc" "$report_path"
check "redacted strings are marked" grep -q "<redacted>" "$report_path"
check "HOME is written as ~" lacks_text "$home" "$report_path"
check "the handoff note's HOME is written as ~" section_has "$report_path" "Newest handoff note" "newest note line ~/"

run_rescue --since 15 --out "$tmp/short.md" > "$tmp/short.out" 2>&1
check "--out writes the named file" [ -f "$tmp/short.md" ]
check "--out is the first stdout line" [ "$(sed -n 1p "$tmp/short.out")" = "$tmp/short.md" ]
check "--since narrows the proxy window" section_has "$tmp/short.md" "Messages proxy" "requests: 2"
check "the window is named in the heading" grep -q "^## Messages proxy (last 15 min)" "$tmp/short.md"

rm "$state/incidents/current"
STUB_NO_SERVER_LOG=1 run_rescue --launcher "$tmp/stubbin/claude-ollama" --out "$tmp/noserver.md" > /dev/null 2>&1
check "a missing server log becomes unavailable" section_has "$tmp/noserver.md" "Ollama server log tail" "^unavailable: "
check "a missing incidents file becomes unavailable" section_has "$tmp/noserver.md" "Incidents" "^unavailable: "

(cd "$tmp" && HOME="$home" python3 "$rescue" --launcher "$tmp/missing-launcher" --size 27b \
  --fingerprint-bin "$tmp/missing-fp" --lease-bin "$tmp/missing-lease" \
  --session-dir "$tmp/empty-session" --state-dir "$tmp/empty-state" --ollama-url http://127.0.0.1:9 \
  --server-env "$tmp/missing.env" --out "$tmp/bare.md" > "$tmp/bare.out" 2> "$tmp/bare.err")
check "a bare machine still exits 0" [ $? -eq 0 ]
check "a bare machine writes the report" [ -f "$tmp/bare.md" ]
check "a missing launcher makes doctor unavailable" section_has "$tmp/bare.md" "Doctor" "^unavailable: "
check "a missing fingerprint tool is unavailable" section_has "$tmp/bare.md" "Sync fingerprint" "^unavailable: "
check "a missing lease tool is unavailable" section_has "$tmp/bare.md" "Lease holders and rung" "^unavailable: "
check "an unreachable ollama is unavailable" section_has "$tmp/bare.md" "Server env and runners" "^unavailable: "
check "a missing proxy log is unavailable" section_has "$tmp/bare.md" "Messages proxy" "^unavailable: "
check "a missing launcher log is unavailable" section_has "$tmp/bare.md" "Launcher log tail" "^unavailable: "
check "no git repo makes the handoff note unavailable" section_has "$tmp/bare.md" "Newest handoff note" "^unavailable: "
check "a bare machine prints the summary" [ "$(wc -l < "$tmp/bare.out" | tr -d ' ')" -eq 6 ]

run_rescue --out "$tmp/no-such-dir/report.md" > /dev/null 2> "$tmp/unwritable.err"
check "an unwritable --out exits 1" [ $? -eq 1 ]
check "an unwritable --out says why" grep -q "rescue:" "$tmp/unwritable.err"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
