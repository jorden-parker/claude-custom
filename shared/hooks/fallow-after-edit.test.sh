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

expect_eq "passing audit adds nothing" "" "$(context "$js_project/src/a.ts")"
expect_eq "non-js file adds nothing" "" "$(failing_context "$js_project/README.md")"
expect_eq "findings for the edited file are reported" yes \
  "$(failing_context "$js_project/src/a.ts" | grep -q 'src/a.ts:3 foo' && echo yes || echo no)"
expect_eq "findings for other files are not reported" "" "$(failing_context "$js_project/src/b.ts")"
finish
