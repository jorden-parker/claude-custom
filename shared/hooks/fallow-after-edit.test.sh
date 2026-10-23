#!/usr/bin/env bash
set -u
. "$(dirname "$0")/fallow-test-lib.sh"
hook="$(hook_path fallow-after-edit.sh)"

context() {
  printf '{"tool_input":{"file_path":%s}}' "$(json_string "$1")" \
    | "$hook" | jq -r '.hookSpecificOutput.additionalContext // ""'
}

failing_context() {
  FALLOW_STUB_REPORT="$fail_report" context "$@"
}

mixed_report="$sandbox/mixed.json"
printf '%s' '{"verdict":"fail","summary":{"dead_code_issues":2,"complexity_findings":0,"duplication_clone_groups":0},"dead_code":{"unused_exports":[{"path":"src/a.ts","line":3,"export_name":"foo","introduced":true},{"path":"src/a.ts","line":9,"export_name":"old","introduced":false}]}}' > "$mixed_report"

mixed_context_keeps_only_introduced() {
  local text
  text="$(FALLOW_STUB_REPORT="$mixed_report" context "$js_project/src/a.ts")"
  case "$text" in *'src/a.ts:3 foo'*) ;; *) return 1 ;; esac
  case "$text" in *old*) return 1 ;; esac
  return 0
}

expect_eq "passing audit adds nothing" "" "$(context "$js_project/src/a.ts")"
expect_eq "non-js file adds nothing" "" "$(failing_context "$js_project/README.md")"
expect_eq "findings for the edited file are reported" yes \
  "$(failing_context "$js_project/src/a.ts" | grep -q 'src/a.ts:3 foo' && echo yes || echo no)"
expect_eq "findings for other files are not reported" "" "$(failing_context "$js_project/src/b.ts")"
expect_eq "findings the PR did not introduce are dropped" yes \
  "$(mixed_context_keeps_only_introduced && echo yes || echo no)"

bare_dir="$sandbox/bare"
mkdir -p "$bare_dir"

finishes_within_seconds() {
  local seconds="$1" input="$2" hook_pid watchdog expired
  "$hook" <<<"$input" >/dev/null 2>&1 &
  hook_pid=$!
  expired="$sandbox/expired-$hook_pid"
  { sleep "$seconds"; touch "$expired"; pkill -P "$hook_pid"; kill "$hook_pid"; } >/dev/null 2>&1 &
  watchdog=$!
  wait "$hook_pid" 2>/dev/null
  kill "$watchdog" >/dev/null 2>&1
  wait "$watchdog" 2>/dev/null
  [ ! -e "$expired" ]
}

relative_edit_without_project() {
  (cd "$bare_dir" && finishes_within_seconds 10 '{"tool_input":{"file_path":"src/a.ts"}}')
}

expect_eq "relative edit without a project finishes" yes \
  "$(relative_edit_without_project && echo yes || echo no)"
expect_eq "relative edit inside a js project is audited" yes \
  "$(cd "$js_project" && failing_context src/a.ts | grep -q 'src/a.ts:3 foo' && echo yes || echo no)"
finish
