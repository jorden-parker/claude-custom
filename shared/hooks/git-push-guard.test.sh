#!/usr/bin/env bash
set -u
guard="$(cd "$(dirname "$0")" && pwd)/git-push-guard.py"
failures=0
repo="$(mktemp -d)"
telemetry_log="$repo.telemetry.jsonl"
trap 'rm -rf "$repo" "$telemetry_log"' EXIT

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
expect deny  'git -C . push origin feature'
expect deny  'git --git-dir=.git push origin feature'
expect deny  '/usr/bin/git push origin feature'
expect allow 'git -C . status'
expect allow '/usr/bin/git status'

git -C "$repo" switch -q -c main
expect deny  'git push'
expect deny  'git push origin HEAD'

telemetry_for() {
  printf '{"session_id":"s1","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' "$repo" \
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

expect_recorded_lines 1 'git push'
expect_recorded_lines 0 'git status'
rm -f "$telemetry_log"
telemetry_for 'git push'
if ! grep -qF '"kind": "deny", "hook": "git-push-guard"' "$telemetry_log"; then
  echo "FAIL: denial line names the kind and hook"
  failures=$((failures + 1))
fi
rm -f "$telemetry_log"
printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"git push"}}' "$repo" \
  | env -u CLAUDE_TOOL_TELEMETRY python3 "$guard" >/dev/null
if [ -e "$telemetry_log" ]; then
  echo "FAIL: nothing is recorded when CLAUDE_TOOL_TELEMETRY is unset"
  failures=$((failures + 1))
fi

mkdir -p "$telemetry_log"
blocked_output="$(printf '{"tool_name":"Bash","session_id":"s1","cwd":"%s","tool_input":{"command":"git push"}}' "$repo" | CLAUDE_TOOL_TELEMETRY="$telemetry_log" python3 "$guard")"
blocked_status=$?
if ! grep -qF '"permissionDecision": "deny"' <<<"$blocked_output" || [ "$blocked_status" -ne 0 ]; then
  echo "FAIL: a telemetry path that cannot be written still denies, with exit 0"
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  exit 1
fi
