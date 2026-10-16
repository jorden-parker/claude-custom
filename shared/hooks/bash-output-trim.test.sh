#!/usr/bin/env bash
set -u
hook="$(dirname "$0")/bash-output-trim.py"
failures=0

run_hook() {
  python3 -c '
import json, sys
tool, stdout, stderr = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
    "hook_event_name": "PostToolUse",
    "tool_name": tool,
    "tool_input": {"command": "make test"},
    "tool_response": {"stdout": stdout, "stderr": stderr, "interrupted": False, "isImage": False},
}))' "$1" "$2" "$3" | python3 "$hook"
}

field() {
  python3 -c '
import json, sys
data = sys.stdin.read()
output = json.loads(data)["hookSpecificOutput"]["updatedToolOutput"] if data.strip() else {}
print(output.get(sys.argv[1], "<none>"))' "$1"
}

numbered_lines() {
  python3 -c 'import sys; print("\n".join(f"line {i}" for i in range(1, int(sys.argv[1]) + 1)))' "$1"
}

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

contains() { printf '%s' "$1" | grep -qF -- "$2"; }
has_line() { printf '%s\n' "$1" | grep -qxF -- "$2"; }
lacks_line() { ! has_line "$1" "$2"; }
line_count_at_most() { [ "$(printf '%s\n' "$1" | wc -l)" -le "$2" ]; }

short_output="$(run_hook Bash "ok" "")"
check "short output is left alone" [ -z "$short_output" ]

other_tool="$(run_hook Read "$(numbered_lines 1000)" "")"
check "other tools are left alone" [ -z "$other_tool" ]

long_stdout="$(numbered_lines 1000 | sed 's/^line 500$/--- FAIL: TestParse (0.01s)/')"
trimmed="$(run_hook Bash "$long_stdout" "warning only" | field stdout)"
check "long stdout keeps its first line" has_line "$trimmed" "line 1"
check "long stdout keeps its last line" has_line "$trimmed" "line 1000"
check "long stdout keeps failure lines from the middle" contains "$trimmed" "--- FAIL: TestParse"
check "long stdout drops ordinary middle lines" lacks_line "$trimmed" "line 300"
check "long stdout says how to see hidden lines" contains "$trimmed" "lines hidden"
check "long stdout fits the line budget" line_count_at_most "$trimmed" 140

untouched_stderr="$(run_hook Bash "$long_stdout" "warning only" | field stderr)"
check "short stderr is kept as is" [ "$untouched_stderr" = "warning only" ]

long_stderr="$(run_hook Bash "" "$(numbered_lines 400)" | field stderr)"
check "long stderr is trimmed too" contains "$long_stderr" "lines hidden"

interrupted="$(run_hook Bash "$long_stdout" "" | field interrupted)"
check "other response fields are preserved" [ "$interrupted" = "False" ]

wide_line="$(python3 -c 'print("x" * 5000)')"
clipped="$(run_hook Bash "$wide_line" "" | field stdout)"
check "very long lines are clipped" [ "${#clipped}" -lt 1000 ]
check "clipped lines say how much was cut" contains "$clipped" "chars hidden"

no_response="$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | python3 "$hook")"
check "missing tool_response is ignored" [ -z "$no_response" ]

[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
