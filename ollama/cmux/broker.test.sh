#!/usr/bin/env bash
set -u
umask 022
here="$(cd "$(dirname "$0")" && pwd)"
broker="$here/broker.py"
client="$here/bin/cmux"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
failures=0
broker_pid=""
session_pid=""

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

cat > "$tmp/cmux" <<EOF
#!/bin/sh
echo "\$*" >> "$tmp/cmux.log"
case "\$*" in
  "browser profiles list") cat "$tmp/profiles" ;;
  "--json --id-format both browser open"*) echo '{"surface_ref":"surface:7","surface_id":"AAAA-7"}' ;;
  *screenshot*)
    while [ "\$#" -gt 0 ]; do
      [ "\$1" = --out ] && printf 'PNGDATA' > "\$2" && echo "\$2" > "$tmp/screenshot-path"
      shift
    done
    ;;
  *"get url") echo "http://localhost:3000/" ;;
  *) echo "ran" ;;
esac
EOF
chmod +x "$tmp/cmux"
printf 'Default\tDefault\t52B4 (default)\n' > "$tmp/profiles"

start_broker() {
  : > "$tmp/cmux.log"
  sleep 600 &
  session_pid=$!
  socket="$tmp/broker.sock"
  python3 "$broker" --socket "$socket" --cmux "$tmp/cmux" --watch-pid "$session_pid" &
  broker_pid=$!
  for _ in $(seq 50); do
    [ -S "$socket" ] && return 0
    sleep 0.1
  done
  echo "broker never listened" >&2
  exit 1
}

run_client() {
  (cd "$tmp/work" && CLAUDE_OLLAMA_CMUX_BROKER="$socket" "$client" "$@") >"$tmp/out" 2>"$tmp/err"
}

logged() {
  grep -qxF -- "$1" "$tmp/cmux.log"
}

ran_only_setup() {
  [ "$(grep -cv '^browser profiles ' "$tmp/cmux.log")" = 0 ]
}

mkdir -p "$tmp/work"
start_broker

check_that "the broker adds the claude-ollama browser profile when it is missing" logged "browser profiles add claude-ollama"

run_client browser open http://localhost:3000
check_eq "open on a loopback URL succeeds" 0 "$?"
check_that "open uses the claude-ollama profile without taking focus" \
  logged "--json --id-format both browser open http://localhost:3000/ --profile claude-ollama --focus false"
check_that "open prints the new surface" grep -qF '"surface_ref":"surface:7"' "$tmp/out"

run_client browser --surface surface:7 get url
check_eq "a surface the session opened answers" 0 "$?"
check_that "the broker targets that surface by its permanent id" logged "browser --surface AAAA-7 get url"
check_that "the broker passes cmux's output back" grep -qxF "http://localhost:3000/" "$tmp/out"

run_client browser AAAA-7 snapshot --interactive
check_that "a surface can be named by its id and as the first argument" logged "browser --surface AAAA-7 snapshot --interactive"

run_client --json browser surface:7 click e1
check_that "the global --json flag passes through" logged "--json browser --surface AAAA-7 click e1"

run_client browser surface:7 goto http://127.0.0.1:8765/
check_that "goto on a loopback URL passes" logged "browser --surface AAAA-7 goto http://127.0.0.1:8765/"
run_client browser surface:7 goto 'HTTP://LOCALHOST.:3000/a?b=1#c'
check_that "goto passes cmux the URL as the broker parsed it" logged "browser --surface AAAA-7 goto http://localhost:3000/a?b=1#c"

: > "$tmp/cmux.log"
refused() {
  : > "$tmp/cmux.log"
  run_client "$@"
  local status=$?
  [ "$status" = 1 ] && ran_only_setup && grep -q "cmux broker:" "$tmp/err"
}
check_that "open on a remote URL is refused" refused browser open https://example.com
check_that "a URL that hides a remote host behind userinfo is refused" refused browser open http://localhost@example.com/
check_that "open on a file URL is refused" refused browser open file:///etc/passwd
check_that "a --focus value other than true or false is refused" refused browser open http://localhost:3000 --focus --workspace=workspace:2
check_that "a backslash that browsers read as a path separator is refused" refused browser open 'http://example.com\@localhost/'
check_that "a URL with a space is refused" refused browser open 'http://localhost /x'
check_that "goto with a backslash URL is refused" refused browser surface:7 goto 'http://example.com\@127.0.0.1/'
check_that "open into another workspace is refused" refused browser open http://localhost:3000 --workspace workspace:2
check_that "a surface the session did not open is refused" refused browser --surface surface:1 get url
check_that "goto on a remote URL is refused" refused browser surface:7 goto https://example.com
check_that "navigate on a remote URL is refused" refused browser surface:7 navigate https://example.com
check_that "uploading host files is refused" refused browser surface:7 set-input-files --selector input --file /etc/passwd
check_that "saving browser state to a host path is refused" refused browser surface:7 state save /tmp/state.json
check_that "reading cookies is refused" refused browser surface:7 cookies get
check_that "downloads are refused" refused browser surface:7 download wait --path /tmp/x
check_that "retargeting a command at another surface is refused" refused browser surface:7 get url --surface surface:1
check_that "retargeting with --flag=value is refused" refused browser surface:7 get url --surface=surface:1
check_that "sending keys to terminals is refused" refused send "echo hi"
check_that "reading the workspace tree is refused" refused tree --all --json
check_that "a screenshot without --out is refused" refused browser surface:7 screenshot
check_that "an empty command is refused" refused

run_client browser surface:7 screenshot --out shots/page.png
check_eq "a screenshot with --out succeeds" 0 "$?"
check_eq "the client writes the screenshot inside the session's folder" PNGDATA "$(cat "$tmp/work/shots/page.png" 2>/dev/null)"
check_not "cmux never writes the session's chosen path" grep -qF "$tmp/work" "$tmp/screenshot-path"
check_not "the broker removes its temporary screenshot" test -e "$(cat "$tmp/screenshot-path")"

kill "$session_pid" && wait "$session_pid" 2>/dev/null
for _ in $(seq 50); do
  kill -0 "$broker_pid" 2>/dev/null || break
  sleep 0.1
done
check_not "the broker exits when the session ends" kill -0 "$broker_pid" 2>/dev/null
check_not "the broker removes its socket when it exits" test -e "$socket"
stop_broker

printf 'Default\tDefault\t52B4 (default)\nclaude-ollama\tclaude-ollama\tBBBB\n' > "$tmp/profiles"
start_broker
check_not "the broker keeps an existing claude-ollama profile" logged "browser profiles add claude-ollama"
stop_broker

CLAUDE_OLLAMA_CMUX_BROKER="$tmp/missing.sock" "$client" browser open http://localhost:3000 >/dev/null 2>"$tmp/err"
check_eq "the client fails when the broker is not running" 1 "$?"
check_that "the client says the broker is unreachable" grep -q "cmux broker: not running" "$tmp/err"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
