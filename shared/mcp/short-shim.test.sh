#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
short="$here/../../ollama/shortcut/bin/short"
tmp="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
failures=0
broker_pid=""

stop_broker() {
  [ -n "$broker_pid" ] && kill "$broker_pid" 2>/dev/null && wait "$broker_pid" 2>/dev/null
  broker_pid=""
}

trap 'stop_broker; rm -rf "$tmp"' EXIT

check_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1: expected [$2] got [$3]"
    failures=$((failures + 1))
  fi
}

cat > "$tmp/broker.py" <<'PY'
import os
import socketserver
import sys

socket_path, log_path = sys.argv[1:3]


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        with open(log_path, "a") as log:
            log.write(self.rfile.readline().decode())
        self.wfile.write(b'{"exit": 3, "stdout": "story 12\\n", "stderr": "warning\\n"}\n')


if os.path.exists(socket_path):
    os.unlink(socket_path)
socketserver.UnixStreamServer(socket_path, Handler).serve_forever()
PY

socket="$tmp/broker.sock"
python3 "$tmp/broker.py" "$socket" "$tmp/broker.log" &
broker_pid=$!
for _ in $(seq 50); do
  [ -S "$socket" ] && break
  sleep 0.1
done

CLAUDE_OLLAMA_SHORTCUT_BROKER="$socket" "$short" search "owner:me" -s "In Progress" > "$tmp/stdout" 2> "$tmp/stderr"
check_eq "short returns the broker's exit status" 3 "$?"
check_eq "short sends its argv to the broker" '{"argv": ["search", "owner:me", "-s", "In Progress"]}' \
  "$(tr -d '\n' < "$tmp/broker.log")"
check_eq "short prints the broker's stdout" "story 12" "$(cat "$tmp/stdout")"
check_eq "short prints the broker's stderr" "warning" "$(cat "$tmp/stderr")"

CLAUDE_OLLAMA_SHORTCUT_BROKER="$tmp/missing.sock" "$short" search > "$tmp/stdout" 2> "$tmp/stderr"
check_eq "short fails without a broker" 1 "$?"
check_eq "and says how to fix it" \
  "short (claude-ollama): the Shortcut broker is not running; check short works outside the session, then relaunch" \
  "$(cat "$tmp/stderr")"

stop_broker
if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
