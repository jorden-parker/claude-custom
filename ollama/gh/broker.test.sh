#!/usr/bin/env bash
set -u
umask 022
here="$(cd "$(dirname "$0")" && pwd)"
broker="$here/broker.py"
client="$here/bin/gh"
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
  GH_TOKEN=readsecret GITHUB_TOKEN=outer python3 "$broker" --socket "$socket" --gh "$tmp/gh" \
    --repo "$1" --watch-pid "$session_pid" &
  broker_pid=$!
  for _ in $(seq 50); do
    [ -S "$socket" ] && return 0
    sleep 0.1
  done
  echo "broker never listened" >&2
  exit 1
}

run_client() {
  (cd "$tmp/work" && CLAUDE_OLLAMA_GH_BROKER="$socket" "$client" "$@") >"$tmp/out" 2>"$tmp/err"
}

logged() {
  grep -qxF -- "$1" "$tmp/gh.log"
}

mkdir -p "$tmp/work"
start_broker owner/project

run_client pr list --state open
check_eq "the client exits with gh's status" 3 "$?"
check_that "pr list reaches gh with its arguments" logged "pr list --state open"
check_eq "the client prints gh's stdout" listed "$(cat "$tmp/out")"
check_eq "and gh's stderr" warning "$(cat "$tmp/err")"
check_eq "gh gets the read-only token and the project's repo, never prompting and no outer GITHUB_TOKEN" \
  "readsecret owner/project 1 unset" "$(cat "$tmp/gh-env")"
check_not "gh never runs in the session's folder, so it reads no git config the session wrote" \
  grep -qF "$tmp/work" "$tmp/gh-cwd"

check_eq "gh only ever talks to github.com" github.com "$(cat "$tmp/gh-host")"
check_not "gh never reads your own gh config and its saved logins" grep -qF "$HOME" "$tmp/gh-config-dir"
check_eq "gh starts from an empty config" "" "$(cat "$tmp/gh-config-listing")"

run_client pr view 12 --comments
check_that "pr view passes" logged "pr view 12 --comments"
run_client pr diff 12
check_that "pr diff passes" logged "pr diff 12"
run_client pr checks 12
check_that "pr checks passes" logged "pr checks 12"
run_client issue view 3 -R other/repo
check_that "another repo can be named with -R" logged "issue view 3 -R other/repo"
run_client run view 99 --log
check_that "run view passes" logged "run view 99 --log"
run_client search prs --author me
check_that "search passes" logged "search prs --author me"
run_client api repos/owner/project/pulls
check_that "api GET passes" logged "api repos/owner/project/pulls"
run_client pr list --json number,title
check_that "--json passes, so the session filters with its own jq" logged "pr list --json number,title"
run_client api -X GET repos/owner/project/issues
check_that "api with an explicit GET passes" logged "api -X GET repos/owner/project/issues"
run_client api -H 'Accept: application/vnd.github.diff' repos/owner/project/pulls/1
check_that "api with an Accept header passes" logged "api -H Accept: application/vnd.github.diff repos/owner/project/pulls/1"
run_client api --paginate --include repos/owner/project/branches
check_that "api output switches pass" logged "api --paginate --include repos/owner/project/branches"

refused() {
  : > "$tmp/gh.log"
  run_client "$@"
  local status=$?
  [ "$status" = 1 ] && [ ! -s "$tmp/gh.log" ] && grep -q "gh broker:" "$tmp/err"
}
check_that "pr create is refused" refused pr create --title x
check_that "pr merge is refused" refused pr merge 12
check_that "pr comment is refused" refused pr comment 12 --body x
check_that "pr checkout is refused" refused pr checkout 12
check_that "issue create is refused" refused issue create --title x
check_that "run rerun is refused" refused run rerun 99
check_that "run download is refused" refused run download 99
check_that "repo delete is refused" refused repo delete owner/project
check_that "auth is refused" refused auth token
check_that "an extension or alias is refused" refused my-extension
check_that "opening the browser is refused" refused pr view 12 --web
check_that "the short browser flag is refused" refused pr view 12 -w
check_that "api with POST is refused" refused api -X POST repos/owner/project/issues
check_that "api with a joined POST is refused" refused api -XPOST repos/owner/project/issues
check_that "api with --method=PATCH is refused" refused api --method=PATCH repos/owner/project
check_that "api fields, which switch gh to POST, are refused" refused api repos/owner/project/issues -f title=x
check_that "api typed fields, which read host files with @, are refused" refused api repos/x/y -F body=@/etc/passwd
check_that "api --input is refused" refused api repos/x/y --input /etc/passwd
check_that "api graphql, which can run mutations, is refused" refused api graphql -f query=x
check_that "api on a full URL is refused" refused api https://example.com/x
check_that "api to another host is refused" refused api --hostname example.com repos/x/y
check_that "api with a non-Accept header is refused" refused api -H 'X-HTTP-Method-Override: POST' repos/x/y
check_that "an empty command is refused" refused
check_that "api --jq, which can read the token from gh's environment, is refused" refused api repos/x/y --jq '$ENV.GH_TOKEN'
check_that "api -q is refused" refused api repos/x/y -q env
check_that "--jq on other commands is refused" refused pr list --json title --jq '$ENV'
check_that "--jq= is refused" refused pr list --json title --jq=env
check_that "--template is refused" refused pr view 12 --json title --template '{{.title}}'
check_that "-t is refused" refused issue list --json title -t x
check_that "api --cache is refused" refused api --cache 1h repos/x/y
check_that "api with POST joined into short flags is refused" refused api -iXPOST repos/owner/project/issues
check_that "api with a field joined into short flags is refused" refused api -pF body=@/etc/passwd repos/x/y
check_that "api flags outside the allowlist are refused" refused api --unknown repos/x/y
check_that "the browser flag joined into short flags is refused" refused pr view 12 -cw
check_that "a joined -R on another host is refused" refused issue list -Revil.example/o/r
check_that "repo view on another host after other flags is refused" refused repo view --branch main evil.example/o/r
check_that "a PR URL, which could point gh at any host, is refused" refused pr view https://evil.example/o/r/pull/1
check_that "a repo on another host is refused" refused issue list -R evil.example/o/r
check_that "a repo on another host given with --repo= is refused" refused issue list --repo=evil.example/o/r
check_that "repo view on another host is refused" refused repo view evil.example/o/r
check_that "api on a protocol-relative path is refused" refused api //evil.example/x
stop_broker

start_broker ""
run_client pr list
check_eq "without a GitHub origin gh gets no default repo" "readsecret unset 1 unset" "$(cat "$tmp/gh-env")"

kill "$session_pid" && wait "$session_pid" 2>/dev/null
for _ in $(seq 50); do
  kill -0 "$broker_pid" 2>/dev/null || break
  sleep 0.1
done
check_not "the broker exits when the session ends" kill -0 "$broker_pid" 2>/dev/null
check_not "the broker removes its socket when it exits" test -e "$socket"
stop_broker

CLAUDE_OLLAMA_GH_BROKER="$tmp/missing.sock" "$client" pr list >/dev/null 2>"$tmp/err"
check_eq "the client fails when the broker is not running" 1 "$?"
check_that "the client says how to get one" grep -qF "gh broker: not running; run claude-ollama github-token read" "$tmp/err"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
