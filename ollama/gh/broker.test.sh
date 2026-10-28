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

cat > "$tmp/gh" <<EOF
#!/bin/sh
echo "\$*" >> "$tmp/gh.log"
echo "\${GH_TOKEN-unset} \${GH_REPO-unset} \${GH_PROMPT_DISABLED-unset} \${GITHUB_TOKEN-unset}" > "$tmp/gh-env"
pwd -P > "$tmp/gh-cwd"
echo "\${GH_HOST-unset}" > "$tmp/gh-host"
echo "\${GH_CONFIG_DIR-unset}" > "$tmp/gh-config-dir"
ls -A "\${GH_CONFIG_DIR:-/nonexistent}" > "$tmp/gh-config-listing" 2>&1
[ -e "$tmp/echo-token" ] && echo "\$GH_TOKEN"
echo "listed"
echo "warning" >&2
exit 3
EOF
chmod +x "$tmp/gh"

start_broker() {
  : > "$tmp/gh.log"
  sleep 600 &
  session_pid=$!
  socket="$tmp/broker.sock"
  rm -f "$socket"
  local repo="$1"
  shift
  GH_TOKEN=readsecret GITHUB_TOKEN=outer python3 "$broker" --socket "$socket" --gh "$tmp/gh" \
    --repo "$repo" --watch-pid "$session_pid" "$@" &
  broker_pid=$!
  for _ in $(seq 50); do
    [ -S "$socket" ] && return 0
    sleep 0.1
  done
  echo "broker never listened" >&2
  exit 1
}

send_line() {
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

ask() {
  local arguments="${2:-}"
  [ -n "$arguments" ] || arguments='{}'
  send_line "{\"tool\":\"$1\",\"arguments\":$arguments}"
}

reply_field() {
  python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]], end="")' "$tmp/reply" "$1"
}

logged() {
  grep -qxF -- "$1" "$tmp/gh.log"
}

pr_fields="number,title,author,headRefName,isDraft,updatedAt"
pr_view_fields="number,title,body,state,author,headRefName,baseRefName,url,isDraft,reviewDecision,labels,files,comments,reviews"
issue_fields="number,title,state,author,labels,updatedAt"
issue_view_fields="number,title,body,state,author,labels,url,comments"
run_fields="databaseId,displayTitle,workflowName,headBranch,status,conclusion,createdAt"
run_view_fields="databaseId,displayTitle,workflowName,headBranch,status,conclusion,url,jobs"

start_broker owner/project --allow-repo friend/tool --allow-repo team/*

ask pr_list
check_eq "the broker passes gh's exit status back" 3 "$(reply_field exit)"
check_that "pr_list lists open PRs as JSON" logged "pr list --state open --limit 20 --json $pr_fields"
check_eq "the broker passes gh's stdout back" "listed" "$(reply_field stdout | tr -d '\n')"
check_eq "and gh's stderr" "warning" "$(reply_field stderr | tr -d '\n')"
check_eq "gh gets the read-only token and the project's repo, never prompting and no outer GITHUB_TOKEN" \
  "readsecret owner/project 1 unset" "$(cat "$tmp/gh-env")"
check_eq "gh only ever talks to github.com" github.com "$(cat "$tmp/gh-host")"
check_not "gh never reads your own gh config and its saved logins" grep -qF "$HOME" "$tmp/gh-config-dir"
check_eq "gh starts from an empty config" "" "$(cat "$tmp/gh-config-listing")"
check_not "gh never runs in the session's folder, so it reads no git config the session wrote" \
  grep -qF "$PWD" "$tmp/gh-cwd"

ask pr_list '{"state":"merged","limit":5,"author":"me","search":"--web in:title"}'
check_that "pr_list passes text as --flag=value, so a value never becomes a flag" \
  logged "pr list --state merged --limit 5 --json $pr_fields --author=me --search=--web in:title"
ask pr_view '{"number":12}'
check_that "pr_view asks for the PR as JSON" logged "pr view 12 --json $pr_view_fields"
ask pr_diff '{"number":12}'
check_that "pr_diff passes" logged "pr diff 12"
ask pr_diff '{"number":12,"name_only":true}'
check_that "pr_diff can list only file names" logged "pr diff 12 --name-only"
ask pr_checks '{"number":12}'
check_that "pr_checks asks for the checks as JSON" logged "pr checks 12 --json name,state,bucket,workflow,link"
ask issue_list '{"state":"closed","search":"crash"}'
check_that "issue_list passes" logged "issue list --state closed --limit 20 --json $issue_fields --search=crash"
ask issue_view '{"number":3}'
check_that "issue_view passes" logged "issue view 3 --json $issue_view_fields"
ask run_list '{"branch":"main","limit":3}'
check_that "run_list passes" logged "run list --limit 3 --json $run_fields --branch=main"
ask run_view '{"run_id":99}'
check_that "run_view asks for the run and its jobs as JSON" logged "run view 99 --json $run_view_fields"
ask run_view '{"run_id":99,"failed_logs":true}'
check_that "run_view can fetch the failed steps' logs" logged "run view 99 --log-failed"

refused() {
  : > "$tmp/gh.log"
  "$@"
  [ "$(reply_field exit)" = 1 ] && [ ! -s "$tmp/gh.log" ] && reply_field stderr | grep -q "gh broker:"
}

not_refused() {
  : > "$tmp/gh.log"
  "$@"
  [ -s "$tmp/gh.log" ]
}
check_that "a tool that is not on the list is refused" refused ask pr_merge '{"number":12}'
check_that "a request without a tool is refused" refused send_line '{"arguments":{}}'
check_that "a malformed request is refused" refused send_line 'not json'
check_that "arguments that are not an object are refused" refused ask pr_list '["--web"]'
check_that "an argument the tool does not take is refused" refused ask pr_view '{"number":12,"web":true}'
check_that "a repo on another host is refused" refused ask pr_view '{"number":12,"repo":"evil.example/o/r"}'
check_that "a missing PR number is refused" refused ask pr_view
check_that "a PR number given as text is refused" refused ask pr_view '{"number":"12 --web"}'
check_that "a PR number of true is refused" refused ask pr_view '{"number":true}'
check_that "a negative PR number is refused" refused ask pr_view '{"number":-1}'
check_that "a state outside the list is refused" refused ask pr_list '{"state":"draft"}'
check_that "a limit over 100 is refused" refused ask pr_list '{"limit":1000}'
check_that "a limit of 0 is refused" refused ask issue_list '{"limit":0}'
check_that "text that is not a string is refused" refused ask pr_list '{"author":["me"]}'
check_that "text over 256 characters is refused" refused ask issue_list "{\"search\":\"$(printf 'x%.0s' $(seq 300))\"}"
check_that "a search that names another repo is refused" refused ask pr_list '{"search":"fix repo:other/project"}'
check_that "as is one that names an org, whatever the case" refused ask issue_list '{"search":"ORG:other"}'
check_that "or a user, even negated" refused ask issue_list '{"search":"-user:other"}'
check_that "or an owner inside parentheses" refused ask pr_list '{"search":"(owner:other)"}'
check_that "a qualifier hidden after a comma is refused" refused ask pr_list '{"search":"fix,repo:other/project"}'
check_that "any qualifier off the allowed list is refused" refused ask issue_list '{"search":"enterprise:other"}'
check_that "allowed qualifiers pass" not_refused ask issue_list '{"search":"is:open label:bug -author:bot in:title"}'
check_that "an author must be a GitHub login" refused ask pr_list '{"author":"me repo:other/project"}'
check_that "or @me" not_refused ask pr_list '{"author":"@me"}'
check_that "a switch that is not a boolean is refused" refused ask pr_diff '{"number":12,"name_only":"yes"}'

gh_repo_used() {
  : > "$tmp/gh.log"
  ask "$1" "$2"
  [ "$(cut -d' ' -f2 "$tmp/gh-env")" = "$3" ]
}
check_that "a request may name the project's own repo" gh_repo_used pr_diff '{"number":4,"repo":"owner/project"}' owner/project
check_that "or a repo on the allow list" gh_repo_used pr_diff '{"number":4,"repo":"friend/tool"}' friend/tool
check_that "whatever its case" gh_repo_used pr_list '{"repo":"Friend/Tool"}' Friend/Tool
check_that "or any repo of an owner allowed with owner/*" gh_repo_used issue_view '{"number":1,"repo":"team/anything"}' team/anything
check_that "a repo off the allow list is refused" refused ask pr_diff '{"number":4,"repo":"stranger/secret"}'
check_that "as is another repo of an owner allowed only for one" refused ask pr_diff '{"number":4,"repo":"friend/other"}'
check_that "a repo that is not owner/name is refused" refused ask pr_diff '{"number":4,"repo":"team/../x"}'
check_that "or one that starts like a flag" refused ask pr_diff '{"number":4,"repo":"-R/x"}'
check_that "the next request goes back to the project's repo" gh_repo_used pr_list '{}' owner/project

ask pr_view '{"number":12,"fields":"number,headRefOid,commits"}'
check_that "pr_view can ask for fewer or extra allowed fields" logged "pr view 12 --json number,headRefOid,commits"
check_that "a field off pr_view's list is refused" refused ask pr_view '{"number":12,"fields":"number,--web"}'
check_that "an empty field list is refused" refused ask pr_view '{"number":12,"fields":""}'
ask pr_checks '{"number":12,"fields":"name,bucket,link"}'
check_that "pr_checks takes fields" logged "pr checks 12 --json name,bucket,link"
ask issue_view '{"number":3,"fields":"title,body"}'
check_that "issue_view takes fields" logged "issue view 3 --json title,body"
ask run_view '{"run_id":99,"fields":"status,conclusion"}'
check_that "run_view takes fields" logged "run view 99 --json status,conclusion"
ask pr_review_comments '{"number":12}'
check_that "pr_review_comments reads the PR's review comments" logged "api repos/{owner}/{repo}/pulls/12/comments --paginate"
ask pr_diff '{"branch":"feature/x-1.2"}'
check_that "pr_diff finds a PR by its branch" logged "pr diff feature/x-1.2"
check_that "a branch that starts like a flag is refused" refused ask pr_diff '{"branch":"--web"}'
check_that "a branch with spaces is refused" refused ask pr_diff '{"branch":"a b"}'
check_that "a number and a branch together are refused" refused ask pr_diff '{"number":1,"branch":"main"}'
check_that "pr_diff needs a number or a branch" refused ask pr_diff
stop_broker

cat > "$tmp/approve" <<EOF
#!/bin/sh
cat > "$tmp/approve.in"
cat "$tmp/approve.answer"
EOF
chmod +x "$tmp/approve"
approve_with() {
  printf '%s\n' "$1" > "$tmp/approve.answer"
  rm -f "$tmp/approve.in"
  : > "$tmp/gh.log"
}
approver_ran() {
  [ -e "$tmp/approve.in" ]
}

start_broker owner/project --allow-repo friend/tool --allow-repo team/* --rules "$tmp/rules" --approve-with "$tmp/approve"

rm -f "$tmp/rules"
approve_with allow
ask pr_comment '{"number":12,"body":"Looks good"}'
check_that "an approved pr_comment runs with the body as one --body= argument" logged "pr comment 12 --body=Looks good"
check_that "the approver saw the body" grep -qF "Looks good" "$tmp/approve.in"
check_that "and the repo the write goes to" grep -qF "(repo owner/project)" "$tmp/approve.in"

approve_with deny
ask pr_comment '{"number":12,"body":"Nope"}'
check_eq "a denied pr_comment is refused" "1" "$(reply_field exit)"
check_eq "and gh never runs" "" "$(cat "$tmp/gh.log")"
check_eq "with the reason" "gh broker: pr comment on owner/project was not approved" "$(reply_field stderr | tr -d '\n')"

rm -f "$tmp/rules"
approve_with allow-always
ask pr_comment '{"number":13,"body":"Again"}'
check_that "allow-always writes a rule for this repo" grep -qxF "allow gh pr_comment owner/project" "$tmp/rules"
approve_with deny
ask pr_comment '{"number":14,"body":"Again"}'
check_that "the next identical write runs without the approver" logged "pr comment 14 --body=Again"
check_that "and the approver is not asked" test ! -e "$tmp/approve.in"

printf 'deny gh pr_create\n' > "$tmp/rules"
approve_with allow
check_that "a rule that denies pr_create refuses it without the approver" refused ask pr_create '{"title":"T","body":"B","head":"feature/x"}'
check_that "and the approver is not asked" test ! -e "$tmp/approve.in"

rm -f "$tmp/rules"
approve_with allow
long_body="$(head -c 20001 /dev/zero | tr '\0' x)"
check_that "a body over 20000 characters is refused" refused ask issue_comment "{\"number\":7,\"body\":\"$long_body\"}"
check_eq "with the limit named" "gh broker: body must be at most 20000 characters" "$(reply_field stderr | tr -d '\n')"
check_that "an empty body is refused" refused ask issue_comment '{"number":7,"body":"   "}'
check_that "a missing body is refused" refused ask pr_comment '{"number":7}'

approve_with allow
ask issue_comment '{"number":7,"body":"Thanks"}'
check_that "an approved issue_comment runs" logged "issue comment 7 --body=Thanks"

approve_with allow
ask pr_create '{"title":"T","body":"B","head":"feature/x","base":"main","draft":true}'
check_that "pr_create passes title, body, head, base and draft as flags" \
  logged "pr create --title=T --body=B --head=feature/x --base=main --draft"
check_that "without head pr_create is refused" refused ask pr_create '{"title":"T","body":"B"}'
check_eq "naming the missing field" "gh broker: head is required" "$(reply_field stderr | tr -d '\n')"

approve_with allow
ask pr_comment '{"number":12,"body":"--hostname=evil"}'
check_eq "a body that looks like a flag is one argument" "pr comment 12 --body=--hostname=evil" "$(tail -n 1 "$tmp/gh.log")"

approve_with deny
ask pr_view '{"number":12}'
check_that "a read never asks the approver" test ! -e "$tmp/approve.in"

touch "$tmp/echo-token"
ask pr_view '{"number":12}'
check_eq "gh's output has the token scrubbed" "[GitHub token removed]" "$(reply_field stdout | head -n 1)"
rm -f "$tmp/echo-token"

approve_with allow
check_that "a repo off the allow list is refused" refused ask pr_comment '{"number":12,"body":"x","repo":"stranger/secret"}'
check_that "before the approver runs" test ! -e "$tmp/approve.in"

start_broker "" --allow-repo friend/tool
check_that "without a GitHub origin a request that names no repo is refused" refused ask pr_list
check_that "but one that names an allowed repo passes" not_refused ask pr_list '{"repo":"friend/tool"}'

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
