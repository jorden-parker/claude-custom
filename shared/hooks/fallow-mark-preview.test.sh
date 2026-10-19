#!/usr/bin/env bash
set -u
. "$(dirname "$0")/fallow-test-lib.sh"
hook="$(hook_path fallow-mark-preview.sh)"
marker_dir="$HOME/.claude/cache/fallow-fix-preview"

run_hook() {
  printf '{"session_id":"%s","tool_input":{"command":%s}}' "$2" "$(json_string "$1")" | "$hook"
}

marker_exists() {
  [ -e "$marker_dir/$1" ] && echo yes || echo no
}

run_hook 'fallow audit --format json' audited
expect_eq "audit leaves no marker" no "$(marker_exists audited)"
run_hook 'fallow fix --dry-run --format json' previewed
expect_eq "dry-run fix leaves a marker" yes "$(marker_exists previewed)"
finish
