#!/usr/bin/env bash
set -u
umask 022
here="$(cd "$(dirname "$0")" && pwd)"
opener="$here/opener.py"
tmp="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
failures=0
opener_pid=""
console_pid=""
watched_pid=""
port_file="$tmp/port"
token="secret-token-123"

stop_all() {
  for pid in "$opener_pid" "$console_pid" "$watched_pid"; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null && wait "$pid" 2>/dev/null
  done
  opener_pid=""
  console_pid=""
  watched_pid=""
}

trap 'stop_all; rm -rf "$tmp"' EXIT

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

eventually() {
  for _ in $(seq 60); do
    "$@" && return 0
    sleep 0.1
  done
  return 1
}

line_count() {
  if [ -f "$1" ]; then
    wc -l < "$1" | tr -d ' '
  else
    echo 0
  fi
}

has_lines() {
  [ "$(line_count "$1")" = "$2" ]
}

cat > "$tmp/console.py" <<'PY'
import http.server
import sys

port_file = sys.argv[1]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(401)
        self.end_headers()

    def log_message(self, *args):
        pass


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w") as handle:
    handle.write(str(server.server_address[1]))
server.serve_forever()
PY

cat > "$tmp/open" <<SH
#!/bin/sh
printf '%s\n' "\$*" >> "$tmp/open.log"
for arg in "\$@"; do
  case "\$arg" in
    file://*) cat "\${arg#file://}" >> "$tmp/opened-pages" ;;
  esac
done
SH
cat > "$tmp/cmux" <<SH
#!/bin/sh
printf '%s\n' "\$*" >> "$tmp/cmux.log"
SH
cat > "$tmp/claude-ollama" <<SH
#!/bin/sh
printf '%s\n' "\$*" >> "$tmp/start.log"
exec python3 "$tmp/console.py" "$port_file"
SH
chmod +x "$tmp/open" "$tmp/cmux" "$tmp/claude-ollama"

start_console() {
  rm -f "$port_file"
  python3 "$tmp/console.py" "$port_file" &
  console_pid=$!
  eventually test -s "$port_file"
}

start_opener() {
  sleep 600 &
  watched_pid=$!
  python3 "$opener" --drafts "$tmp/drafts" --watch-pid "$watched_pid" \
    --console-url "http://127.0.0.1:$1" --token-file "$tmp/state/tokens/token" \
    --pages "$tmp/state/open" --start-console "$tmp/claude-ollama" \
    --interval 0.1 --min-gap "${MIN_GAP:-0}" --console-wait 10 "${@:2}" &
  opener_pid=$!
  sleep 0.5
}

write_draft() {
  printf '{"id":"%s"}\n' "$1" > "$tmp/drafts/$1.json"
}

reset() {
  stop_all
  rm -rf "$tmp/drafts" "$tmp/state" "$tmp"/*.log "$tmp/opened-pages"
  mkdir -p "$tmp/drafts" "$tmp/state/tokens"
  printf '%s\n' "$token" > "$tmp/state/tokens/token"
}

reset
write_draft 20261029-100000-pr-old
start_console
start_opener "$(cat "$port_file")" --open "$tmp/open"
write_draft 20261029-100001-pr-feature
check "a new draft opens in the browser" eventually has_lines "$tmp/open.log" 1
check "a draft that was there before the session is left alone" lacks "$(cat "$tmp/open.log")" "pr-old"
check "the page sends the browser to the draft with the console token" \
  contains "$(cat "$tmp/opened-pages")" "/drafts/20261029-100001-pr-feature?token=$token"
check "the token never reaches a command line" lacks "$(cat "$tmp/open.log")" "$token"
check "the redirect page is private" [ "$(stat -f %Lp "$tmp/state/open" 2>/dev/null || stat -c %a "$tmp/state/open")" = 700 ]
write_draft 20261029-100001-pr-feature
sleep 0.5
check "a draft opens once" has_lines "$tmp/open.log" 1
printf 'x' > "$tmp/drafts/not-a-draft.json"
printf 'x' > "$tmp/drafts/20261029-100002-pr-x;rm.json"
sleep 0.5
check "files that are not draft ids never open" has_lines "$tmp/open.log" 1
check "a running console is not started again" [ ! -e "$tmp/start.log" ]

reset
start_console
MIN_GAP=30 start_opener "$(cat "$port_file")" --open "$tmp/open"
write_draft 20261029-110000-review-1
write_draft 20261029-110001-review-2
write_draft 20261029-110002-review-3
sleep 1
check "a burst of drafts opens one page" has_lines "$tmp/open.log" 1
check "and it is the newest draft" contains "$(cat "$tmp/opened-pages")" "review-3"

reset
free_port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
start_opener "$free_port" --open "$tmp/open"
write_draft 20261029-120000-pr-cold
check "with the console down the opener starts it" eventually test -s "$tmp/start.log"
check "as claude-ollama ui" [ "$(head -n 1 "$tmp/start.log" 2>/dev/null)" = "ui --port $free_port" ]

reset
start_console
start_opener "$(cat "$port_file")" --cmux "$tmp/cmux"
write_draft 20261029-130000-pr-split
check "in a cmux terminal the draft opens in a browser split" eventually has_lines "$tmp/cmux.log" 1
check "through cmux browser open-split" contains "$(cat "$tmp/cmux.log")" "browser open-split file://"
check "and cmux never sees the token" lacks "$(cat "$tmp/cmux.log")" "$token"

reset
start_console
start_opener "$(cat "$port_file")" --open "$tmp/open"
kill "$watched_pid" 2>/dev/null
wait "$watched_pid" 2>/dev/null
watched_pid=""
check "the opener exits when the session does" eventually sh -c "! kill -0 $opener_pid 2>/dev/null"
wait "$opener_pid" 2>/dev/null
opener_pid=""
stop_all

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
