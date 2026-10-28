#!/usr/bin/env bash
set -u
umask 022
here="$(cd "$(dirname "$0")" && pwd)"
broker="$here/broker.py"
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

cat > "$tmp/short" <<EOF
#!/bin/sh
printf '%s|' "\$@" >> "$tmp/short.log"
echo >> "$tmp/short.log"
pwd -P > "$tmp/short-cwd"
if [ -e "$tmp/leak" ]; then
  echo "Shortcut-Token: \$SHORTCUT_API_TOKEN"
  echo "config token cfgsecret-0000 again cfgsecret-0000" >&2
fi
echo "story 12"
echo "warning" >&2
exit 3
EOF
chmod +x "$tmp/short"

cat > "$tmp/approve" <<EOF
#!/bin/sh
cat > "$tmp/approve.in"
cat "$tmp/approve.answer"
EOF
chmod +x "$tmp/approve"
printf 'allow\n' > "$tmp/approve.answer"

sleep 600 &
session_pid=$!
socket="$tmp/broker.sock"
mkdir -p "$tmp/home/.config/shortcut-cli"
printf '{"token":"cfgsecret-0000"}\n' > "$tmp/home/.config/shortcut-cli/config.json"
HOME="$tmp/home" SHORTCUT_API_TOKEN=envsecret-1111 python3 "$broker" --socket "$socket" --short "$tmp/short" --watch-pid "$session_pid" \
  --rules "$tmp/rules" --approve-with "$tmp/approve" &
broker_pid=$!
for _ in $(seq 50); do
  [ -S "$socket" ] && break
  sleep 0.1
done

send_line() {
  : > "$tmp/short.log"
  python3 - "$socket" "$1" > "$tmp/reply" <<'PY'
import socket
import sys

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
    connection.connect(sys.argv[1])
    connection.sendall(sys.argv[2].encode() + b"\n")
    with connection.makefile("r") as replies:
        print(replies.readline(), end="")
PY
}

run_short() {
  send_line "$(python3 -c 'import json, sys; print(json.dumps({"argv": sys.argv[1:]}))' "$@")"
}

reply_field() {
  python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]], end="")' "$tmp/reply" "$1"
}

ran() {
  tr -d '\n' < "$tmp/short.log"
}

expect() {
  local label="$1" want="$2"
  shift 2
  run_short "$@"
  check_eq "$label" "$want" "$(ran)"
}

refused_reply() {
  [ "$(reply_field exit)" = 1 ] && [ ! -s "$tmp/short.log" ] && reply_field stderr | grep -q "short broker:"
}

stderr_contains() {
  printf '%s' "$(reply_field stderr)" | grep -qF "$1"
}

stderr_starts_with() {
  case "$(reply_field stderr)" in
    "$1"*) return 0 ;;
    *) return 1 ;;
  esac
}

run_asking() {
  rm -f "$tmp/approve.in"
  run_short "$@"
}

approve_with() {
  printf '%s\n' "$1" > "$tmp/approve.answer"
}

approver_ran() {
  [ -e "$tmp/approve.in" ]
}

refused() {
  run_short "$@"
  refused_reply
}

refused_line() {
  send_line "$1"
  refused_reply
}

run_short search owner:me
check_eq "the broker passes short's exit status back" 3 "$(reply_field exit)"
check_eq "and its stdout" "story 12" "$(reply_field stdout | tr -d '\n')"
check_eq "and its stderr" "warning" "$(reply_field stderr | tr -d '\n')"
check_eq "search passes its operators" "search|owner:me|" "$(ran)"
check_not "short never runs in the session's folder" grep -qF "$PWD" "$tmp/short-cwd"
expect "a short flag becomes its long form with its value attached" "search|--state=Done|--owner=jo|" search -s Done -o jo
expect "a long flag with = keeps its value" "search|--text=a b|" search --text="a b"
expect "a switch passes as its long form" "search|--archived|" search -a
expect "a value that looks like a flag stays a value" "story|12|--comment=--from-git|" story 12 -c --from-git
expect "story shows a story" "story|12|" story 12
expect "story updates go through" "story|12|--state=Done|--estimate=3|--owners=jo|--task=write tests|" \
  story 12 -s Done -e 3 -o jo --task "write tests"
expect "create makes a story" "create|--title=Fix it|--state=Ready|--idonly|" create -t "Fix it" -s Ready -I
expect "epic view" "epic|view|7|" epic view 7
expect "iteration stories" "iteration|stories|3|--format=%j|" iteration stories 3 -f %j
expect "members search" "members|--search=jo|" members -s jo
expect "doc view" "doc|view|5|--quiet|" doc view 5 -q

run_asking search owner:me
check_not "a search is not asked for approval" approver_ran
run_asking story 12
check_not "a story read is not asked for approval" approver_ran
check_eq "and the read runs" "story|12|" "$(ran)"
run_asking story 12 -f json
check_not "a story read with a format is not asked for approval" approver_ran
run_asking story 12 -c hello
check_that "a story edit is asked for approval" approver_ran
check_that "as a story-edit" grep -qF "rule: short story-edit workspace" "$tmp/approve.in"
check_that "the approver sees the comment" grep -qF "> hello" "$tmp/approve.in"
check_eq "an approved story edit runs" "story|12|--comment=hello|" "$(ran)"
run_asking create -t "New"
check_that "a create is asked for approval as a create" grep -qF "rule: short create workspace" "$tmp/approve.in"
check_eq "an approved create runs" "create|--title=New|" "$(ran)"

approve_with deny
run_asking story 12 -c Nope
check_that "a denied story edit is refused" refused_reply
check_eq "with the reason" "short broker: story-edit was not approved" "$(reply_field stderr | tr -d '\n')"
run_asking create -t "Denied"
check_that "a denied create is refused" refused_reply
check_eq "with its reason" "short broker: create was not approved" "$(reply_field stderr | tr -d '\n')"

approve_with allow
run_asking story 12 -c one -c two
check_that "a write that repeats a body flag is refused" refused_reply
check_not "before the approver is asked about it" approver_ran
long_state="$(head -c 300 /dev/zero | tr '\0' x)"
run_asking story 12 -s "$long_state"
check_that "a write with a flag the dialog cannot show in full is refused" refused_reply
check_not "before the approver is asked about that either" approver_ran
check_eq "naming the flag and the limit" "short broker: --state is longer than 200 characters; shorten it or put long text in a body field" "$(reply_field stderr | tr -d '\n')"

rm -f "$tmp/rules"
printf 'deny short create\n' > "$tmp/rules"
run_asking create -t "Blocked"
check_not "a create the rules deny is not asked for approval" approver_ran
check_that "and it is refused" refused_reply

rm -f "$tmp/rules"
approve_with allow-always
run_asking story 12 -s Done
check_that "allow-always stores the rule" grep -qxF "allow short story-edit workspace" "$tmp/rules"
approve_with deny
run_asking story 12 -c Again
check_not "the next story edit is not asked for approval" approver_ran
check_eq "and runs under the stored rule" "story|12|--comment=Again|" "$(ran)"
approve_with allow

check_that "install is refused" refused install
check_that "api is refused" refused api /stories
check_that "workspace is refused" refused workspace
check_that "a delete is refused" refused doc delete 5 --confirm
check_that "opening a browser is refused" refused story 12 -O
check_that "as is --open-epic" refused story 12 --oe
check_that "a git branch is refused" refused story 12 --git-branch
check_that "as is --from-git" refused story --from-git
check_that "a download is refused" refused story 12 -D --download-dir /tmp
check_that "saving a search is refused" refused search -S mine
check_that "a flag another command takes is refused" refused members --comment hi
check_that "a positional that starts like a flag is refused" refused search --archived -- -O
check_that "a flag missing its value is refused" refused story 12 -s
check_that "no command is refused" refused
check_that "argv that is not a list of text is refused" refused_line '{"argv": ["story", 12]}'
check_that "a request that is not JSON is refused" refused_line 'not json'
run_short install
check_that "a refused command lists the commands it can use" stderr_contains "commands: search, find, story, create, members, workflows, epics, epic view"
run_short story 12 -O
check_that "a refused flag lists that command's flags" stderr_contains "story takes: --archived, --comment, --deadline"

touch "$tmp/leak"
run_short search owner:me
check_not "the broker never returns the token short was given" grep -q envsecret-1111 "$tmp/reply"
check_not "nor the token in short's config" grep -q cfgsecret-0000 "$tmp/reply"
check_that "it says where it cut a token" grep -qF "Shortcut-Token: [Shortcut token removed]" "$tmp/reply"
rm "$tmp/leak"

mv "$tmp/short" "$tmp/short.moved"
run_short search owner:me
check_eq "a short that can't run is an error reply, not a dropped request" 1 "$(reply_field exit)"
check_that "that names the problem" stderr_starts_with "short broker: short could not run"
mv "$tmp/short.moved" "$tmp/short"

kill "$session_pid" && wait "$session_pid" 2>/dev/null
for _ in $(seq 50); do
  kill -0 "$broker_pid" 2>/dev/null || break
  sleep 0.1
done
check_not "the broker exits when the session ends" kill -0 "$broker_pid" 2>/dev/null
check_not "the broker removes its socket when it exits" test -e "$socket"
stop_broker

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
