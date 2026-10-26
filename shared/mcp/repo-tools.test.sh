#!/usr/bin/env bash
set -u
umask 022
server="$(cd "$(dirname "$0")" && pwd)/repo-tools.py"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
failures=0
broker_pid=""

stop_broker() {
  [ -n "$broker_pid" ] && kill "$broker_pid" 2>/dev/null && wait "$broker_pid" 2>/dev/null
  broker_pid=""
}

trap 'stop_broker; rm -rf "$tmp"' EXIT

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
    kind, _, rest = step.partition(":")
    if kind == "sh":
        subprocess.run(rest, shell=True, check=True)
        continue
    name, _, arguments = rest.partition(":")
    result = send({"jsonrpc": "2.0", "id": number, "method": "tools/call", "params": {"name": name, "arguments": json.loads(arguments or "{}")}})["result"]
    print(("ERROR " if result["isError"] else "") + result["content"][0]["text"].rstrip("\n"))
process.stdin.close()
process.wait()
PY

cat > "$tmp/broker.py" <<'PY'
import json
import os
import socketserver
import sys

socket_path, log_path, reply_path = sys.argv[1:4]


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        with open(log_path, "a") as log:
            log.write(self.rfile.readline().decode())
        with open(reply_path) as reply:
            self.wfile.write(reply.read().encode())


if os.path.exists(socket_path):
    os.unlink(socket_path)
socketserver.UnixStreamServer(socket_path, Handler).serve_forever()
PY

repo="$tmp/repo"
git init -q -b main "$repo"
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Tester
printf 'one\n' > "$repo/notes.txt"
printf 'alpha\n' > "$repo/other.txt"
git -C "$repo" add .
git -C "$repo" commit -q -m "first commit"
printf 'one\ntwo\n' > "$repo/notes.txt"
git -C "$repo" commit -q -am "second commit"
first="$(git -C "$repo" rev-parse --short HEAD~1)"
from_first="{\"base\":\"$first\"}"
stat_from_first="{\"base\":\"$first\",\"stat\":true}"
other_from_first="{\"base\":\"$first\",\"paths\":[\"other.txt\"]}"
at_first="{\"rev\":\"$first\"}"
option_rev="{\"rev\":\"--output=$tmp/written\"}"
option_base="{\"base\":\"--output=$tmp/written\"}"

call() {
  (cd "$repo" && python3 "$tmp/client.py" "$server" "$@")
}

check "without the GitHub broker only the git tools are listed" \
  [ "$(call list)" = "git_status git_diff git_log git_show" ]

printf 'one\ntwo\nthree\n' > "$repo/notes.txt"
status="$(call git_status)"
check "git_status names the branch" contains "$status" "## main"
check "git_status lists a changed file" contains "$status" " M notes.txt"

diff="$(call git_diff)"
check "git_diff shows unstaged changes" contains "$diff" "+three"
check "git_diff of staged changes is empty before staging" [ "$(call git_diff '{"staged":true}')" = "(no output)" ]
git -C "$repo" add notes.txt
check "git_diff shows staged changes" contains "$(call git_diff '{"staged":true}')" "+three"
check "git_diff compares against a base revision" contains "$(call git_diff "$from_first")" "+two"
check "git_diff --stat summarises" contains "$(call git_diff "$stat_from_first")" "notes.txt | 2 ++"
check "git_diff limits to paths" [ "$(call git_diff "$other_from_first")" = "(no output)" ]

log="$(call git_log)"
check "git_log lists commits newest first, one line each" contains "$log" "Tester second commit"
check "git_log shows short hashes" contains "$log" "$first "
check "git_log limit caps the commits" [ "$(call git_log '{"limit":1}' | wc -l | tr -d ' ')" = 1 ]
check "git_log follows a path" lacks "$(call git_log '{"path":"other.txt"}')" "second commit"
check "git_log starts from a revision" lacks "$(call git_log "$at_first")" "second commit"

shown="$(call git_show "$at_first")"
check "git_show shows the commit message" contains "$shown" "first commit"
check "git_show shows the diff" contains "$shown" "+alpha"
check "git_show --stat summarises" contains "$(call git_show '{"rev":"HEAD","stat":true}')" "notes.txt | 1 +"

check "a revision that looks like an option is never read as one" \
  contains "$(call git_show "$option_rev")" "ERROR"
check "so git writes no file" [ ! -e "$tmp/written" ]
check "a diff base that looks like an option is refused by git" \
  contains "$(call git_diff "$option_base")" "ERROR"
check "and writes no file either" [ ! -e "$tmp/written" ]

printf '#!/bin/sh\ntouch %s/external-ran\n' "$tmp" > "$tmp/external.sh"
chmod +x "$tmp/external.sh"
git -C "$repo" config diff.external "$tmp/external.sh"
git -C "$repo" config diff.conv.textconv "$tmp/external.sh"
printf '*.txt diff=conv\n' > "$repo/.gitattributes"
call git_diff '{"staged":true}' >/dev/null
call git_show '{"rev":"HEAD"}' >/dev/null
check "git tools never run external diff or textconv programs" [ ! -e "$tmp/external-ran" ]
git -C "$repo" config --unset diff.external
rm "$repo/.gitattributes"

outside_paths='{"paths":["/etc/hosts","/etc/hosts"]}'
check "git_diff refuses absolute paths, which would make git compare any two files" \
  contains "$(call git_diff "$outside_paths")" "ERROR paths must stay inside the repository"
check "git_diff refuses paths that climb out of the repository" \
  contains "$(call git_diff '{"paths":["../x"]}')" "ERROR paths must stay inside the repository"
check "git_log refuses a path outside the repository" \
  contains "$(call git_log '{"path":"/etc"}')" "ERROR paths must stay inside the repository"

mkdir -p "$repo/sub"
planted="$(cd "$repo/sub" && python3 "$tmp/session.py" "$server" \
  "call:git_log:{\"limit\":1}" \
  "sh:git init -q $repo/sub && git -C $repo/sub -c user.email=x@y -c user.name=Planter commit -q --allow-empty -m planted" \
  "call:git_log:{\"limit\":1}")"
check "a .git planted after the server started is never used" lacks "$planted" "planted"
rm -rf "$repo/sub"
mkdir -p "$tmp/not-a-repo"
outside="$(cd "$tmp/not-a-repo" && python3 "$tmp/client.py" "$server" git_status)"
check "outside a git repository the git tools say so" [ "$outside" = "ERROR the session did not start inside a git repository" ]

check "an unknown argument is an error" contains "$(call git_log '{"since":"yesterday"}')" "ERROR unknown arguments: since"
check "a limit over 100 is an error" contains "$(call git_log '{"limit":500}')" "ERROR"
check "a revision that is not text is an error" contains "$(call git_show '{"rev":5}')" "ERROR"
check "git_show needs a revision" contains "$(call git_show)" "ERROR rev is required"
check "paths must be a list of text" contains "$(call git_diff '{"paths":"notes.txt"}')" "ERROR"
check "an unknown tool is an error" contains "$(call git_push)" "ERROR"
check "a GitHub tool without the broker says how to get it" \
  contains "$(call pr_list)" "ERROR the GitHub broker is not running; run claude-ollama github-token read, then relaunch"

head -c 30000 /dev/zero | tr '\0' x > "$repo/big.txt"
git -C "$repo" add big.txt
big="$(call git_diff '{"staged":true,"paths":["big.txt"]}')"
check "long output is cut to stay inside the model's context" [ "${#big}" -lt 21000 ]
check "and says how to narrow it" contains "$big" "[truncated: showed 20000 of"

socket="$tmp/b.sock"
printf '%s\n' '{"exit":0,"stdout":"[{\"number\":12}]\n","stderr":""}' > "$tmp/broker-reply"
python3 "$tmp/broker.py" "$socket" "$tmp/broker.log" "$tmp/broker-reply" &
broker_pid=$!
for _ in $(seq 50); do
  [ -S "$socket" ] && break
  sleep 0.1
done
export CLAUDE_OLLAMA_GH_BROKER="$socket"
check "with the GitHub broker the GitHub tools are listed too" \
  [ "$(call list)" = "git_status git_diff git_log git_show pr_list pr_view pr_diff pr_checks issue_list issue_view run_list run_view" ]
check "a GitHub tool returns the broker's output" [ "$(call pr_view '{"number":12}')" = '[{"number":12}]' ]
check "and sends the broker the tool and its arguments" \
  [ "$(tail -n 1 "$tmp/broker.log")" = '{"tool": "pr_view", "arguments": {"number": 12}}' ]
printf '%s\n' '{"exit":1,"stdout":"","stderr":"gh broker: number must be a positive whole number\n"}' > "$tmp/broker-reply"
check "a refusal from the broker is an error with its reason" \
  [ "$(call pr_view '{"number":-1}')" = "ERROR gh broker: number must be a positive whole number" ]
printf '%s\n' '{"exit":8,"stdout":"[{\"bucket\":\"pending\"}]\n","stderr":""}' > "$tmp/broker-reply"
check "output from gh that exits non-zero, like pending checks, is still a result" \
  [ "$(call pr_checks '{"number":12}')" = '[{"bucket":"pending"}]' ]
stop_broker

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
