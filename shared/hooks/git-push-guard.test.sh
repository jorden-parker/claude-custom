#!/usr/bin/env bash
set -u
guard="$(cd "$(dirname "$0")" && pwd)/git-push-guard.py"
failures=0
repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT

git -C "$repo" init -q -b feature
git -C "$repo" -c user.name=t -c user.email=t@example.test commit -q --allow-empty -m start

decision_for() {
  printf '{"tool_name":"Bash","cwd":%s,"tool_input":{"command":%s}}' \
    "$(printf '%s' "$repo" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
    "$(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
    | python3 "$guard" | grep -o '"permissionDecision": *"deny"' >/dev/null && echo deny || echo allow
}

expect() {
  local want="$1" command="$2" got
  got="$(decision_for "$command")"
  if [ "$got" != "$want" ]; then
    echo "FAIL: expected $want for: $command (got $got)"
    failures=$((failures + 1))
  fi
}

expect allow 'git push'
expect allow 'git push origin feature'
expect allow 'git push -u origin HEAD'
expect allow 'git status && git push origin feature:feature'
expect allow 'git commit -m "never git push --force"'
expect allow 'echo git push --force'
expect deny  'git push --force'
expect deny  'git push -f origin feature'
expect deny  'git push origin feature --force-with-lease'
expect deny  'git push --force-if-includes origin feature'
expect deny  'git push origin +feature'
expect deny  'git push origin --delete feature'
expect deny  'git push origin -d feature'
expect deny  'git push origin :feature'
expect deny  'git push --mirror'
expect deny  'git push --prune origin'
expect deny  'git push origin main'
expect deny  'git push origin feature:main'
expect deny  'git push origin HEAD:refs/heads/master'
expect deny  'git status; git push -f'
expect deny  'git -C . push --force'
expect deny  'git -c alias.ship=push ship'

git -C "$repo" switch -q -c main
expect deny  'git push'
expect deny  'git push origin HEAD'

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  exit 1
fi
