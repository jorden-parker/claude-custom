#!/usr/bin/env bash
set -u
umask 022
here="$(cd "$(dirname "$0")" && pwd)"
broker="$here/broker.py"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
failures=0
broker_pid=""
session_pid=""
socket="$tmp/broker.sock"
export BROKER_TEST_DIR="$tmp"

stop_broker() {
  [ -n "$broker_pid" ] && kill "$broker_pid" 2>/dev/null && wait "$broker_pid" 2>/dev/null
  [ -n "$session_pid" ] && kill "$session_pid" 2>/dev/null && wait "$session_pid" 2>/dev/null
  broker_pid=""
  session_pid=""
}

trap 'stop_broker; rm -rf "$tmp"' EXIT

check_that() {
  local name="$1"
  shift
  if "$@"; then
    echo "ok: $name"
  else
    echo "FAIL: $name"
    failures=$((failures + 1))
  fi
}

check_not() {
  local name="$1"
  shift
  if "$@"; then
    echo "FAIL: $name"
    failures=$((failures + 1))
  else
    echo "ok: $name"
  fi
}

check_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1: expected [$2] got [$3]"
    failures=$((failures + 1))
  fi
}

contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

cat > "$tmp/cmux" <<'SH'
#!/bin/sh
echo "$*" >> "$BROKER_TEST_DIR/cmux.log"
pwd >> "$BROKER_TEST_DIR/cwd.log"
case "$*" in
  "browser repl "*)
    cat > "$BROKER_TEST_DIR/stdin.last"
    cat "$BROKER_TEST_DIR/reply"
    exit "$(cat "$BROKER_TEST_DIR/status" 2>/dev/null || echo 0)"
    ;;
  *)
    echo "unexpected: $*" >&2
    exit 1
    ;;
esac
SH
chmod +x "$tmp/cmux"

cat > "$tmp/ask.py" <<'PY'
import socket
import sys

with socket.socket(socket.AF_UNIX) as connection:
    connection.connect(sys.argv[1])
    connection.sendall(sys.argv[2].encode() + b"\n")
    data = b""
    while True:
        chunk = connection.recv(65536)
        if not chunk:
            break
        data += chunk
print(data.decode().strip())
PY

set_reply() {
  printf '%s\n' "$1" > "$tmp/reply"
  printf '%s\n' "${2:-0}" > "$tmp/status"
}

start_broker() {
  : > "$tmp/cmux.log"
  : > "$tmp/cwd.log"
  sleep 600 &
  session_pid=$!
  python3 "$broker" --socket "$socket" --cmux "$tmp/cmux" --watch-pid "$session_pid" &
  broker_pid=$!
  for _ in $(seq 50); do
    [ -S "$socket" ] && return 0
    sleep 0.1
  done
  echo "broker never listened" >&2
  exit 1
}

ask() {
  python3 "$tmp/ask.py" "$socket" "$1"
}

logged() {
  grep -qF -- "$1" "$tmp/cmux.log"
}

ok_reply() {
  printf '%s\n' '"{\"url\":\"http://localhost:3000/\",\"errors\":[],\"console\":[],\"surface\":null}"' '[ok | 5ms]'
}

set_reply '"{\"allowed\":[\"localhost\",\"127.0.0.1\",\"[::1]\"]}"'
start_broker
check_that "the broker proves the localhost lock at startup" \
  contains "$(cat "$tmp/stdin.last")" 'await __cc_run({"op": "lock"})'
set_reply "$(ok_reply)"

check_that "a request without a page object is refused with the page-only message" \
  contains "$(ask '{"args":["browser","open","http://localhost:3000"]}')" "this broker takes only page requests"
check_that "a request with an extra top-level key is refused" \
  contains "$(ask '{"page":{"op":"snapshot"},"args":["x"]}')" "this broker takes only page requests"
check_that "an unknown op is refused" \
  contains "$(ask '{"page":{"op":"eval","code":"1"}}')" "unknown op"
check_that "an unknown key on a page request is refused" \
  contains "$(ask '{"page":{"op":"snapshot","code":"1"}}')" "unknown keys: code"
check_that "an unknown action is refused" \
  contains "$(ask '{"page":{"op":"act","action":"eval","target":"e1"}}')" "action"
check_that "a non-string target is refused" \
  contains "$(ask '{"page":{"op":"act","action":"click","target":5}}')" "target must be text"
check_that "a target over 1000 characters is refused" \
  contains "$(ask "{\"page\":{\"op\":\"act\",\"action\":\"click\",\"target\":\"$(printf 'x%.0s' $(seq 1001))\"}}")" "at most 1000 characters"

: > "$tmp/cmux.log"
refused_url() {
  local reply
  reply="$(ask "{\"page\":{\"op\":\"open\",\"url\":$1}}")"
  contains "$reply" '"ok": false' && ! grep -q 'browser repl' "$tmp/cmux.log"
}
check_that "open on a remote URL is refused" refused_url '"https://example.com/"'
check_that "open with userinfo that hides a remote host is refused" refused_url '"http://localhost@example.com/"'
check_that "open on a file URL is refused" refused_url '"file:///etc/passwd"'
check_that "open with a backslash is refused" refused_url '"http://example.com\\@localhost/"'
check_that "open with a space is refused" refused_url '"http://localhost /x"'
check_that "open with a non-text URL is refused" refused_url '5'

reply="$(ask '{"page":{"op":"open","url":"HTTP://LOCALHOST.:3000/a?b=1#c"}}')"
check_that "open on a loopback URL succeeds" contains "$reply" '"ok": true'
check_that "the URL reaches the program canonicalized" \
  contains "$(cat "$tmp/stdin.last")" 'await __cc_run({"op": "open", "url": "http://localhost:3000/a?b=1#c"})'
check_that "open returns the page result from the browser" contains "$reply" '"url": "http://localhost:3000/"'
check_that "the program routes the browser away from the user's profile" contains "$(cat "$tmp/stdin.last")" 'session.configure({ proxy: __CC_PROXY })'
check_that "the proxy is a closed local port that no page can use" contains "$(cat "$tmp/stdin.last")" 'server: "http://127.0.0.1:9"'
check_that "the program configures the proxy before it locks the session" \
  test "$(grep -bo 'session.configure' "$tmp/stdin.last" | head -n 1 | cut -d: -f1)" -lt "$(grep -bo 'session.allowedDomains' "$tmp/stdin.last" | head -n 1 | cut -d: -f1)"

reply="$(ask '{"page":{"op":"act","action":"fill","target":"zq-target-7","text":"zq-text-9"}}')"
check_that "act returns ok on success" contains "$reply" '"ok": true'
check_not "the target never reaches the command line" grep -q 'zq-target-7' "$tmp/cmux.log"
check_not "the text never reaches the command line" grep -q 'zq-text-9' "$tmp/cmux.log"
check_that "the target reaches the program as JSON" contains "$(cat "$tmp/stdin.last")" '"zq-target-7"'
check_that "the text reaches the program as JSON" contains "$(cat "$tmp/stdin.last")" '"zq-text-9"'
check_that "the program is page.js followed by the one run line" \
  contains "$(tail -n 1 "$tmp/stdin.last")" 'await __cc_run({"op": "act", "action": "fill", "target": "zq-target-7", "text": "zq-text-9"})'
check_that "the program defines the locked hosts" grep -qF '__CC_ALLOWED' "$tmp/stdin.last"
check_that "the program locks the session" grep -qF 'lock: true' "$tmp/stdin.last"

check_that "cmux runs the repl on a claude-ollama session with the fixed timeout and stdin program" \
  grep -Eq '^browser repl --session claude-ollama-[0-9a-f]{16} --timeout 60000 --eval -$' "$tmp/cmux.log"
check_that "cmux never runs from the repository" test "$(tail -n 1 "$tmp/cwd.log")" != "$here"

set_reply "$(printf '%s\n' 'boom at line 3' '[error | 2ms]')" 1
reply="$(ask '{"page":{"op":"snapshot"}}')"
check_that "a failing REPL call is ok false with its output" contains "$reply" "boom at line 3"

set_reply "$(printf 'noise-%02d\n' $(seq 1 25))" 1
reply="$(ask '{"page":{"op":"snapshot"}}')"
check_that "a failing REPL call keeps the last 20 output lines" contains "$reply" "noise-25"
check_not "and drops the lines before them" contains "$reply" "noise-05"

set_reply "$(printf '%s\n' 'no result here' '[ok | 1ms]')" 0
reply="$(ask '{"page":{"op":"snapshot"}}')"
check_that "a call with no result line is ok false" contains "$reply" '"ok": false'

set_reply "$(ok_reply)"
reply="$(ask '{"page":{"op":"snapshot"}}')"
check_that "snapshot returns the program's result" contains "$reply" '"url": "http://localhost:3000/"'

kill "$session_pid" && wait "$session_pid" 2>/dev/null
for _ in $(seq 50); do
  kill -0 "$broker_pid" 2>/dev/null || break
  sleep 0.1
done
check_not "the broker exits when the session ends" kill -0 "$broker_pid" 2>/dev/null
check_not "the broker removes its socket when it exits" test -e "$socket"
stop_broker

set_reply '"{\"allowed\":[\"localhost\",\"127.0.0.1\",\"[::1]\"]}"'
start_broker
rm -f "$socket"
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$socket"
kill "$session_pid" && wait "$session_pid" 2>/dev/null
for _ in $(seq 50); do
  kill -0 "$broker_pid" 2>/dev/null || break
  sleep 0.1
done
check_that "an exiting broker leaves the next session's socket in place" test -S "$socket"
stop_broker
rm -f "$socket"

: > "$tmp/cmux.log"
set_reply '"{\"allowed\":[\"*\"]}"'
rm -f "$socket"
python3 "$broker" --socket "$socket" --cmux "$tmp/cmux" --watch-pid $$ 2>"$tmp/lock-err"
check_eq "a broker whose browser is not locked to localhost exits 1" 1 "$?"
check_not "it never creates its socket when the lock is not proven" test -e "$socket"
check_that "it says the browser could not be locked" grep -q "could not lock the browser to localhost" "$tmp/lock-err"

selftest_reply() {
  set_reply "\"{\\\"fetch\\\":\\\"$1\\\",\\\"open\\\":\\\"blocked\\\",\\\"goto\\\":\\\"blocked\\\",\\\"allowed\\\":[\\\"localhost\\\",\\\"127.0.0.1\\\",\\\"[::1]\\\"],\\\"local\\\":\\\"claude-ollama browser-check page\\\"}\""
}

selftest_reply blocked
python3 "$broker" --self-test --cmux "$tmp/cmux" > "$tmp/selftest.out" 2>&1
check_eq "browser-check exits 0 when every check passes" 0 "$?"
check_that "browser-check reports the blocked fetch" grep -qxF "ok: fetch to example.com blocked" "$tmp/selftest.out"
check_that "browser-check reports the localhost page loads" grep -qxF "ok: localhost page loads through the proxy bypass" "$tmp/selftest.out"
check_that "browser-check reports passed" grep -qxF "browser-check: passed" "$tmp/selftest.out"
check_that "the self-test runs one selftest request that carries a localhost page" \
  contains "$(cat "$tmp/stdin.last")" 'await __cc_run({"op": "selftest", "localUrl": "http://127.0.0.1:'

selftest_reply reached
python3 "$broker" --self-test --cmux "$tmp/cmux" > "$tmp/selftest.out" 2>&1
check_eq "browser-check exits 1 when a check fails" 1 "$?"
check_that "browser-check names the failed check with what it expected and got" \
  grep -qxF 'FAIL: fetch to example.com blocked: expected "blocked", got "reached"' "$tmp/selftest.out"
check_that "browser-check reports failed" grep -qxF "browser-check: FAILED" "$tmp/selftest.out"

set_reply '"{\"fetch\":\"blocked\",\"open\":\"blocked\",\"goto\":\"blocked\",\"allowed\":[\"localhost\",\"127.0.0.1\",\"::1\"],\"local\":\"error: net::ERR_PROXY_CONNECTION_FAILED\"}"'
python3 "$broker" --self-test --cmux "$tmp/cmux" > "$tmp/selftest.out" 2>&1
check_that "browser-check shows the hosts the browser allowed" \
  grep -qxF 'FAIL: browser locked to localhost: expected ["localhost", "127.0.0.1", "[::1]"], got ["localhost", "127.0.0.1", "::1"]' "$tmp/selftest.out"
check_that "browser-check shows what the localhost page returned" \
  grep -qxF 'FAIL: localhost page loads through the proxy bypass: expected text containing "claude-ollama browser-check page", got "error: net::ERR_PROXY_CONNECTION_FAILED"' "$tmp/selftest.out"

set_reply "\"{\\\"fetch\\\":\\\"blocked\\\",\\\"open\\\":\\\"blocked\\\",\\\"goto\\\":\\\"blocked\\\",\\\"allowed\\\":[\\\"localhost\\\",\\\"127.0.0.1\\\",\\\"[::1]\\\"],\\\"local\\\":\\\"$(printf 'x%.0s' $(seq 1 400))\\\"}\""
python3 "$broker" --self-test --cmux "$tmp/cmux" > "$tmp/selftest.out" 2>&1
check_that "browser-check cuts a long value to 200 characters" \
  grep -qE '^FAIL: localhost page .*, got "x{199}\.\.\.$' "$tmp/selftest.out"

check_eq "the self-test page server never reverse-resolves its address, which stalls on some machines" "127.0.0.1" \
  "$(python3 -c 'import socket, sys
sys.path.insert(0, sys.argv[1])
import broker

def stalled(host):
    raise AssertionError("getfqdn called")

socket.getfqdn = stalled
server = broker.SelfTestPageServer(("127.0.0.1", 0), broker.SelfTestPage)
print(server.server_name)
server.server_close()' "$here")"

check_that "every tabs.use in page.js is awaited" \
  test -z "$(grep -n 'tabs.use(' "$here/page.js" | grep -v 'await tabs.use(')"

if command -v node >/dev/null 2>&1; then
  check_that "page.js is valid JavaScript" node --check "$here/page.js"
fi

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
