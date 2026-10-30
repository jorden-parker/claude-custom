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
expect deny  $'echo start\ngit log'
expect deny  '(git log)'
expect deny  $'echo "$(git log)"'
expect deny  'git --no-pager log'
expect deny  'git -C . log'
expect allow 'git -C . log -n 5'
expect deny  'ls -la -R'
expect deny  'ls --recursive src'
expect allow 'ls -la --color'
expect allow 'echo "ls -R is slow"'
expect allow 'git log | head'
expect allow 'git log -n 5 --stat'
expect allow 'echo "cat package-lock.json"'
expect deny  'less go.sum'
expect allow 'ls -l -a'
expect deny  'find . | ls -R'
expect allow 'git log --oneline | head -20'
expect allow 'git log | wc -l'
expect allow 'git log | sed -n 1,20p'
expect allow 'cd r && git log --stat | tail -5'
expect allow 'ls -R src | head -50'
expect allow 'cat go.sum | grep foo'
expect deny  'git log | less'
expect deny  'git log | cat'
expect deny  'git log || true'
expect deny  'git log | sed s/a/b/'
expect deny  'git log | headless'
expect deny  'ls -R | sort'
expect allow "grep -n 'bash-output-guard\\|git log' CLAUDE.md"
expect allow 'grep -nE "x|git log" f'
expect allow "echo 'a; git log'"
expect deny  "echo \"\`git log\`\""
expect deny  'cat "go.sum"'
expect deny  "less 'pnpm-lock.yaml'"
expect deny  $'ls # it\'s fine\ngit log'

telemetry_dir="$(mktemp -d)"
trap 'rm -rf "$telemetry_dir"' EXIT
telemetry_log="$telemetry_dir/telemetry.jsonl"

telemetry_for() {
  printf '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
    | CLAUDE_TOOL_TELEMETRY="$telemetry_log" python3 "$guard" >/dev/null
}

recorded_lines() {
  if [ -f "$telemetry_log" ]; then wc -l < "$telemetry_log" | tr -d ' '; else echo 0; fi
}

expect_recorded_lines() {
  local want="$1" command="$2"
  rm -f "$telemetry_log"
  telemetry_for "$command"
  if [ "$(recorded_lines)" != "$want" ]; then
    echo "FAIL: expected $want telemetry line(s) for: $command"
    failures=$((failures + 1))
  fi
}

expect_recorded_lines 1 'git log'
expect_recorded_lines 0 'git log -n 5'
rm -f "$telemetry_log"
telemetry_for 'git log'
if ! grep -qF '"kind": "deny", "hook": "bash-output-guard"' "$telemetry_log"; then
  echo "FAIL: denial line names the kind and hook"
  failures=$((failures + 1))
fi
rm -f "$telemetry_log"
printf '{"tool_name":"Bash","tool_input":{"command":"git log"}}' | env -u CLAUDE_TOOL_TELEMETRY python3 "$guard" >/dev/null
if [ -e "$telemetry_log" ]; then
  echo "FAIL: nothing is recorded when CLAUDE_TOOL_TELEMETRY is unset"
  failures=$((failures + 1))
fi

mkdir -p "$telemetry_dir/as-directory"
blocked_output="$(printf '{"tool_name":"Bash","tool_input":{"command":"git log"}}' | CLAUDE_TOOL_TELEMETRY="$telemetry_dir/as-directory" python3 "$guard")"
blocked_status=$?
if ! grep -qF '"permissionDecision": "deny"' <<<"$blocked_output" || [ "$blocked_status" -ne 0 ]; then
  echo "FAIL: a telemetry path that cannot be written still denies, with exit 0"
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
