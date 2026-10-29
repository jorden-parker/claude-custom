#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
gh="$here/../../ollama/gh/bin/gh"
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

socket="$tmp/broker.sock"
reply() {
  printf '%s\n' "$1" > "$tmp/reply"
}
reply '{"exit":0,"stdout":"out\n","stderr":""}'
python3 "$tmp/broker.py" "$socket" "$tmp/broker.log" "$tmp/reply" &
broker_pid=$!
for _ in $(seq 50); do
  [ -S "$socket" ] && break
  sleep 0.1
done
export CLAUDE_OLLAMA_GH_BROKER="$socket"

sent() {
  : > "$tmp/broker.log"
  "$gh" "$@" > "$tmp/stdout" 2> "$tmp/stderr"
  echo $? > "$tmp/status"
  python3 -c 'import json, sys
line = open(sys.argv[1]).readline()
print(json.dumps(json.loads(line), sort_keys=True) if line else "nothing", end="")' "$tmp/broker.log"
}

expect() {
  local label="$1" want="$2"
  shift 2
  check_eq "$label" "$want" "$(sent "$@")"
}

expect "pr diff sends the number" '{"arguments": {"number": 12}, "tool": "pr_diff"}' pr diff 12
expect "pr diff --name-only" '{"arguments": {"name_only": true, "number": 12}, "tool": "pr_diff"}' pr diff 12 --name-only
expect "pr diff by branch" '{"arguments": {"branch": "feature/x"}, "tool": "pr_diff"}' pr diff feature/x
expect "pr diff by URL names the repo" '{"arguments": {"number": 7, "repo": "o/r"}, "tool": "pr_diff"}' \
  pr diff https://github.com/o/r/pull/7
expect "-R before the command" '{"arguments": {"number": 7, "repo": "o/r"}, "tool": "pr_diff"}' -R o/r pr diff 7
expect "--repo=VALUE after it" '{"arguments": {"number": 7, "repo": "o/r"}, "tool": "pr_diff"}' pr diff 7 --repo=o/r
expect "pr view sends the number" '{"arguments": {"number": 12}, "tool": "pr_view"}' pr view 12 --comments
expect "pr view --json picks fields" '{"arguments": {"fields": "title,body", "number": 12}, "tool": "pr_view"}' \
  pr view 12 --json title,body
expect "pr list flags, long and short" \
  '{"arguments": {"author": "@me", "limit": 5, "search": "fix in:title", "state": "merged"}, "tool": "pr_list"}' \
  pr list -s merged --limit 5 -A @me --search "fix in:title"
expect "pr checks" '{"arguments": {"fields": "name,bucket", "number": 3}, "tool": "pr_checks"}' pr checks 3 --json name,bucket
expect "issue view by URL" '{"arguments": {"number": 4, "repo": "o/r"}, "tool": "issue_view"}' \
  issue view https://github.com/o/r/issues/4
expect "issue list" '{"arguments": {"limit": 2, "state": "closed"}, "tool": "issue_list"}' issue list --state closed -L 2
expect "run list" '{"arguments": {"branch": "main"}, "tool": "run_list"}' run list -b main
expect "run view --log-failed" '{"arguments": {"failed_logs": true, "run_id": 99}, "tool": "run_view"}' run view 99 --log-failed
expect "api review comments with placeholders" '{"arguments": {"number": 12}, "tool": "pr_review_comments"}' \
  api 'repos/{owner}/{repo}/pulls/12/comments' --paginate
expect "api review comments of a named repo" '{"arguments": {"number": 12, "repo": "o/r"}, "tool": "pr_review_comments"}' \
  api repos/o/r/pulls/12/comments
expect "pr comment sends the number and body" '{"arguments": {"body": "Looks good", "number": 12}, "tool": "pr_comment"}' \
  pr comment 12 --body "Looks good"
expect "pr comment with the short body flag" '{"arguments": {"body": "text", "number": 12}, "tool": "pr_comment"}' pr comment 12 -b text
expect "pr comment by URL names the repo" '{"arguments": {"body": "t", "number": 12, "repo": "o/r"}, "tool": "pr_comment"}' \
  pr comment https://github.com/o/r/pull/12 --body=t
expect "issue comment" '{"arguments": {"body": "t", "number": 7}, "tool": "issue_comment"}' issue comment 7 --body t
expect "pr create with every field" \
  '{"arguments": {"base": "main", "body": "B", "draft": true, "head": "feature/x", "title": "T"}, "tool": "pr_create"}' \
  pr create --title T --body B --head feature/x --base main --draft

check_eq "gh prints the broker's stdout" "out" "$(sent pr diff 12 >/dev/null; cat "$tmp/stdout")"
reply '{"exit":8,"stdout":"partial\n","stderr":"pending\n"}'
sent pr checks 3 >/dev/null
check_eq "and its stderr" "pending" "$(cat "$tmp/stderr")"
check_eq "and exits with gh's status" 8 "$(cat "$tmp/status")"

reply '{"exit":0,"stdout":"{\"title\":\"Fix it\",\"number\":12}\n","stderr":""}'
sent pr view 12 --json title,number --jq .title >/dev/null
check_eq "--jq filters the JSON in the session, raw like gh" "Fix it" "$(cat "$tmp/stdout")"
reply '{"exit":1,"stdout":"","stderr":"gh broker: friend/x is not on this machine'"'"'s gh-repos list\n"}'
sent pr view 12 --json title --jq .title >/dev/null
check_eq "a refusal skips --jq and shows the reason" "gh broker: friend/x is not on this machine's gh-repos list" "$(cat "$tmp/stderr")"
check_eq "with the broker's status" 1 "$(cat "$tmp/status")"

refused() {
  local label="$1"
  shift
  check_eq "$label is refused before the broker" "nothing 1" "$(sent "$@") $(cat "$tmp/status")"
}
refused "pr merge" pr merge 12
refused "pr comment with a body file" pr comment 12 --body-file x
refused "pr comment with a hostname" pr comment 12 --hostname other.example
refused "pr create --fill" pr create --fill
refused "pr create --web" pr create --web
refused "pr create with a file body" pr create -F body=@/etc/passwd
refused "pr review" pr review 12 --approve
refused "issue create" issue create --title x
refused "pr checkout" pr checkout 12
refused "auth token" auth token
refused "api on another path" api repos/o/r/issues
refused "api with a method" api repos/o/r/pulls/12/comments -X POST
refused "an unknown flag" pr diff 12 --web
refused "pr view with no PR" pr view
refused "a flag missing its value" pr list --limit
refused "a text limit" pr list --limit ten
sent pr merge 12 >/dev/null
check_eq "the refusal names what works" "gh (claude-ollama): supported: pr list|view|diff|checks|comment|create, issue list|view|comment, run list|view, api repos/{owner}/{repo}/pulls/N/comments; writes ask you in a dialog" \
  "$(head -n 1 "$tmp/stderr")"

stop_broker
sent pr diff 12 >/dev/null
check_eq "without a broker gh says how to get one" \
  "gh (claude-ollama): the GitHub broker is not running; run gh auth login outside the session, then relaunch 1" \
  "$(cat "$tmp/stderr") $(cat "$tmp/status")"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
