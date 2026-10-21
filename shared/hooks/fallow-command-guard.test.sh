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
expect_eq "pipe inside a quoted pattern" allow "$(decision 'grep -nE "a|fallow|b" README.md')"
expect_eq "semicolon inside a commit message" allow "$(decision 'git commit -m "x; fallow audit"')"
expect_eq "fallow after a newline" deny "$(decision $'echo x\nfallow audit')"
expect_eq "env assignment before fallow" deny "$(decision 'FOO=1 fallow audit')"
expect_eq "absolute npx" deny "$(decision '/opt/homebrew/bin/npx fallow audit')"
expect_eq "global option before fix" deny "$(decision 'fallow --root . fix --yes --format json')"
expect_eq "root option with explain" allow "$(decision 'fallow --root . explain unused-export')"
expect_eq "heredoc body line starting with fallow" allow "$(decision $'cat > f <<\'EOF\'\n- 001: fallow hook\nfallow audit\nEOF\ngit status')"
expect_eq "multi-line commit message with fallow line" allow "$(decision $'git commit -m "subject\n\nfallow line here"')"
expect_eq "apostrophe in a shell comment" deny "$(failing_decision $'grep -n "x" f # it\'s\ngit push')"
expect_eq "ansi-c quoted apostrophe" deny "$(failing_decision $'echo $\'it\\\'s\' && git push')"
expect_eq "fix --yes after an unlexable comment" deny "$(decision $'ls # don\'t\nfallow fix --yes --format json')"
expect_eq "unlexable command without a gated word" allow "$(failing_decision $'ls # it\'s fine')"
finish
