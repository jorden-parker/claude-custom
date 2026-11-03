#!/usr/bin/env bash
set -u
guard="$(cd "$(dirname "$0")" && pwd)/tdd-guard.py"
failures=0
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export CLAUDE_CONFIG_DIR="$sandbox/config"
export CLAUDE_TOOL_TELEMETRY="$sandbox/telemetry.jsonl"
project="$sandbox/project"
mkdir -p "$project/pkg" "$project/other" "$project/web/src/lib" "$project/web/src/app"
printf '{"name":"web"}' > "$project/web/package.json"
printf 'package pkg\n' > "$project/pkg/parse.go"

event() {
  local hook_event="$1" tool="$2" input="$3" session="${4:-s1}"
  printf '{"hook_event_name":"%s","session_id":"%s","tool_name":"%s","tool_input":%s}' "$hook_event" "$session" "$tool" "$input" \
    | python3 "$guard"
}

decision() {
  if event PreToolUse "$@" | grep -q '"permissionDecision": *"deny"'; then echo deny; else echo allow; fi
}

expect() {
  local want="$1" label="$2" got
  shift 2
  got="$(decision "$@")"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label: expected $want, got $got"
    failures=$((failures + 1))
  fi
}

expect_reason_has() {
  local label="$1" input="$2" output
  shift 2
  cp "$CLAUDE_CONFIG_DIR/cache/tdd-guard/s1.json" "$CLAUDE_CONFIG_DIR/cache/tdd-guard/probe.json"
  output="$(event PreToolUse Edit "$input" probe)"
  for expected in "$@"; do
    if ! printf '%s' "$output" | grep -qF -- "$expected"; then
      echo "FAIL: $label: reason lacks [$expected]"
      failures=$((failures + 1))
    fi
  done
}

after_edit() { event PostToolUse "$1" "$2" "${3:-s1}" >/dev/null; }
after_bash() { event PostToolUse Bash "{\"command\": \"$1\"}" "${2:-s1}" >/dev/null; }

go_source="{\"file_path\": \"$project/pkg/parse.go\", \"new_string\": \"x\"}"
go_test="{\"file_path\": \"$project/pkg/parse_test.go\", \"new_string\": \"x\"}"
other_source="{\"file_path\": \"$project/other/run.sh\", \"new_string\": \"x\"}"

expect deny  'source before any test edit' Edit "$go_source"
expect_reason_has 'reason names the test file and the cycle' "$go_source" "parse_test.go" "fail" "run"
expect allow 'test files always pass' Edit "$go_test"
expect allow 'markdown passes' Edit "{\"file_path\": \"$project/pkg/README.md\", \"new_string\": \"x\"}"
expect allow 'json passes' Write "{\"file_path\": \"$project/pkg/config.json\", \"content\": \"{}\"}"
expect allow 'a file under .claude passes' Edit "{\"file_path\": \"$project/.claude/verify\", \"new_string\": \"x\"}"
expect allow 'a tool config file passes' Write "{\"file_path\": \"$project/web/jest.config.ts\", \"content\": \"export default {}\"}"
expect allow 'a dotfile rc config passes' Write "{\"file_path\": \"$project/web/.eslintrc.cjs\", \"content\": \"module.exports = {}\"}"
expect deny  'a source file named like config still needs a test' Edit "{\"file_path\": \"$project/web/configure.ts\", \"new_string\": \"x\"}"

after_edit Edit "$go_test"
expect deny  'test edited but not run' Edit "$go_source"
expect_reason_has 'reason asks for the run' "$go_source" "run"
after_bash 'git status'
expect deny  'a non-test command is not a run' Edit "$go_source"
after_bash 'cd pkg && go test ./... | tail -20'
expect allow 'test edited and run unlocks the package' Edit "$go_source"
expect allow 'multi-edit too' MultiEdit "{\"file_path\": \"$project/pkg/parse.go\", \"edits\": [{\"old_string\": \"a\", \"new_string\": \"b\"}]}"
expect allow 'a new source file in the package' Write "{\"file_path\": \"$project/pkg/render.go\", \"content\": \"package pkg\"}"
expect deny  'another package stays locked' Edit "$other_source"

after_edit Edit "$go_test"
expect deny  'editing the test again relocks until the next run' Edit "$go_source"
after_bash './pkg/parse_test.go'
expect deny  'a non-runnable path is not a run' Edit "$go_source"
after_bash 'make test-go'
expect allow 'make test target counts' Edit "$go_source"

ts_test="{\"file_path\": \"$project/web/src/lib/rules.test.ts\", \"new_string\": \"x\"}"
ts_source="{\"file_path\": \"$project/web/src/app/page.tsx\", \"new_string\": \"x\"}"
expect deny  'ts source locked' Edit "$ts_source"
after_edit Edit "$ts_test"
after_bash 'pnpm --dir web test'
expect allow 'a package.json root is one scope' Edit "$ts_source"

shell_test="{\"file_path\": \"$project/other/run.test.sh\", \"content\": \"x\"}"
expect deny  'shell source locked' Edit "$other_source"
after_edit Write "$shell_test"
after_bash 'other/run.test.sh'
expect allow 'a .test.sh run counts' Edit "$other_source"

py_source="{\"file_path\": \"$project/other/serve.py\", \"new_string\": \"x\"}"
expect allow 'python shares the dir scope' Edit "$py_source"

expect deny  'another session starts locked' Edit "$go_source" s2
expect deny  'second strike' Edit "$go_source" s2
expect allow 'third strike lets the edit through' Edit "$go_source" s2
event PreToolUse Edit "$go_source" s2 >/dev/null
event PreToolUse Edit "$go_source" s2 >/dev/null
event PreToolUse Edit "$other_source" s2 >/dev/null
event PreToolUse Edit "$other_source" s2 >/dev/null
strike_output="$(event PreToolUse Edit "$other_source" s2)"
for expected in '"additionalContext"' 'Recovery: 1. ' 'run.test.sh' '2. run' '3. retry the edit'; do
  if ! printf '%s' "$strike_output" | grep -qF -- "$expected"; then
    echo "FAIL: the third strike names the recovery recipe: lacks [$expected]"
    failures=$((failures + 1))
  fi
done
if printf '%s' "$strike_output" | grep -q '"permissionDecision"'; then
  echo "FAIL: the third strike's context carries no permission decision"
  failures=$((failures + 1))
fi
if ! grep -q '"kind": "allow-after-strikes"' "$CLAUDE_TOOL_TELEMETRY"; then
  echo "FAIL: the third strike should be recorded"
  failures=$((failures + 1))
fi
if ! grep -q '"kind": "deny"' "$CLAUDE_TOOL_TELEMETRY"; then
  echo "FAIL: denials should be recorded"
  failures=$((failures + 1))
fi

got="$(CLAUDE_CUSTOM_TDD=0 decision Edit "$other_source" s3)"
if [ "$got" != allow ]; then
  echo "FAIL: CLAUDE_CUSTOM_TDD=0 should allow (got $got)"
  failures=$((failures + 1))
fi
got="$(decision Edit "$other_source" s4)"
if [ "$got" != deny ]; then
  echo "FAIL: a fresh session with the switch on should deny (got $got)"
  failures=$((failures + 1))
fi

stale_session="$CLAUDE_CONFIG_DIR/cache/tdd-guard/stale.json"
printf '{}' > "$stale_session"
touch -t 202001010000 "$stale_session"
after_bash "echo hi" fresh
if [ -e "$stale_session" ]; then
  echo "FAIL: a new session's first event prunes week-old state"
  failures=$((failures + 1))
fi

if printf 'not json' | python3 "$guard"; then :; else
  echo "FAIL: bad input must exit 0"
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  exit 1
fi
