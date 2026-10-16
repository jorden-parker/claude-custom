#!/usr/bin/env bash
set -u
guard="$(dirname "$0")/bash-output-guard.py"
failures=0

decision_for() {
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
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

expect deny  'git log'
expect deny  'cd repo && git log --stat'
expect allow 'git log --oneline -n 20'
expect allow 'git log -5'
expect allow 'git log --max-count=10'
expect allow 'git commit -m "fix git log parsing"'
expect deny  'cat package-lock.json'
expect deny  'cat ./yarn.lock'
expect allow 'grep lodash package-lock.json'
expect deny  'ls -R'
expect deny  'ls -laR src'
expect allow 'ls -la'

[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
