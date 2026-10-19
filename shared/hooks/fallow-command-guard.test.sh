#!/usr/bin/env bash
set -u
. "$(dirname "$0")/fallow-test-lib.sh"
hook="$(hook_path fallow-command-guard.sh)"

decision() {
  local command="$1" session="${2:-s1}" cwd="${3:-$js_project}"
  local output
  output="$(printf '{"session_id":"%s","cwd":%s,"tool_input":{"command":%s}}' \
    "$session" "$(json_string "$cwd")" "$(json_string "$command")" | "$hook")"
  [ -n "$output" ] || { echo allow; return; }
  jq -r '.hookSpecificOutput.permissionDecision' <<<"$output"
}

failing_decision() {
  FALLOW_STUB_REPORT="$fail_report" decision "$@"
}

expect_eq "audit without json format" deny "$(decision 'fallow audit')"
expect_eq "audit with json format" allow "$(decision 'fallow audit --format json')"
expect_eq "npx audit without json format" deny "$(decision 'npx -y fallow audit')"
expect_eq "explain needs no format" allow "$(decision 'fallow explain unused-export')"
expect_eq "tool name inside an argument" allow "$(decision 'grep -n fallow README.md')"
expect_eq "audit after a pipe" deny "$(decision 'echo x | fallow audit')"
expect_eq "fix without preview" deny "$(decision 'fallow fix --yes --format json')"
mkdir -p "$HOME/.claude/cache/fallow-fix-preview"
touch "$HOME/.claude/cache/fallow-fix-preview/previewed"
expect_eq "fix after preview" allow "$(decision 'fallow fix --yes --format json' previewed)"
expect_eq "git status" allow "$(decision 'git status')"
expect_eq "git commit with passing audit" allow "$(decision 'git commit -m x')"
expect_eq "git commit with failing audit" deny "$(failing_decision 'git commit -m x')"
expect_eq "git push with failing audit" deny "$(failing_decision 'git -C . push')"
expect_eq "git inside an argument" allow "$(failing_decision 'echo git commit')"
expect_eq "git commit outside a js project" allow "$(failing_decision 'git commit' s1 "$sandbox")"
finish
