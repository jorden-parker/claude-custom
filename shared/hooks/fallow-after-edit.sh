#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/fallow-lib.sh"
command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat)"
FILE="$(jq -r '.tool_input.file_path // empty' <<<"$INPUT")"
[ -n "$FILE" ] || exit 0
fallow_is_js_file "$FILE" || exit 0
case "$FILE" in */node_modules/*) exit 0 ;; esac
ROOT="$(fallow_project_root "$(dirname "$FILE")")" || exit 0
cd "$ROOT" || exit 0
REL="${FILE#"$ROOT"/}"
REPORT="$(fallow_audit_report "$REL" | grep -F -- "$REL")"
[ -n "$REPORT" ] || exit 0
jq -n --arg c "Fallow findings in $REL after this edit (fix or remove, do not suppress):
$REPORT" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
exit 0
