#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/fallow-lib.sh"
command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat)"
CMD="$(jq -r '.tool_input.command // empty' <<<"$INPUT")"
SESSION="$(jq -r '.session_id // "nosession"' <<<"$INPUT")"
grep -Eq 'fallow[^;|&]*[[:space:]]fix([[:space:]][^;|&]*)?[[:space:]]--dry-run' <<<"$CMD" || exit 0
marker_dir="$(fallow_marker_dir)"
mkdir -p "$marker_dir"
find "$marker_dir" -type f -mtime +1 -delete 2>/dev/null
touch "$marker_dir/$SESSION"
exit 0
