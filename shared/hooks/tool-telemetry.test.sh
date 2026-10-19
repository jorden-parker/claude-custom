#!/usr/bin/env bash
set -u
hook="$(dirname "$0")/tool-telemetry.py"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
log="$sandbox/telemetry.log"
failures=0

run_hook() {
  python3 -c '
import json, sys
tool, stdout, stderr, command = sys.argv[1:5]
print(json.dumps({
    "hook_event_name": "PostToolUse",
    "session_id": "s1",
    "tool_name": tool,
    "tool_input": {"command": command},
    "tool_response": {"stdout": stdout, "stderr": stderr, "interrupted": False, "isImage": False},
}))' "$1" "$2" "$3" "${4:-make test}" | python3 "$hook"
}

numbered_lines() {
  python3 -c 'import sys; print("\n".join(f"line {i}" for i in range(1, int(sys.argv[1]) + 1)))' "$1"
}

log_count() {
  wc -l < "$log" | tr -d ' '
}

last_field() {
  tail -n 1 "$log" | python3 -c 'import json, sys; print(json.loads(sys.stdin.read())[sys.argv[1]])' "$1"
}

missing_response() {
  printf '%s' '{"tool_name":"Bash","session_id":"s1"}' | CLAUDE_TOOL_TELEMETRY="$log" python3 "$hook"
}

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

unset CLAUDE_TOOL_TELEMETRY
off="$(run_hook Bash "some output" "")"
check "off by default: no output" [ -z "$off" ]
check "off by default: no log" test ! -e "$log"

export CLAUDE_TOOL_TELEMETRY="$log"
run_hook Bash "$(numbered_lines 200)" "err" "cat secret-marker-7731" >/dev/null
check "one line per call" [ "$(log_count)" = 1 ]
check "line has the tool" [ "$(last_field tool)" = Bash ]
check "line has the session" [ "$(last_field session)" = s1 ]
check "line has bytes" [ "$(last_field bytes)" -gt 1000 ]
check "line counts stdout lines" [ "$(last_field lines)" = 200 ]
check "line says trim would apply" [ "$(last_field over_trim_limit)" = True ]
check "tool input is never logged" test "$(grep -c secret-marker-7731 "$log")" = 0

run_hook Read "short" "" >/dev/null
check "non-bash tools are logged too" [ "$(log_count)" = 2 ]
check "short output is not over the limit" [ "$(last_field over_trim_limit)" = False ]
check "hook never prints" [ -z "$(run_hook Read "x" "")" ]
check "missing response is tolerated" missing_response
check "missing response logs zero bytes" [ "$(last_field bytes)" = 0 ]
check "missing response still logs a line" [ "$(log_count)" = 4 ]

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
