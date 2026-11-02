#!/usr/bin/env bash
set -u
nudge="$(dirname "$0")/edit-nudge.py"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
telemetry="$sandbox/telemetry.jsonl"
failures=0

numbered_lines() {
  python3 -c 'import sys; print("\n".join(f"line {i} of the span" for i in range(1, int(sys.argv[1]) + 1)))' "$1"
}

replaced_lines() {
  numbered_lines "$1" | sed "1,${2}s/^line/edited/"
}

long_lines() {
  python3 -c 'import sys; print("\n".join("x" * int(sys.argv[2]) for _ in range(int(sys.argv[1]))))' "$1" "$2"
}

edit_input() {
  python3 -c '
import json, sys
print(json.dumps({"file_path": "src/parser.py", "old_string": sys.argv[1], "new_string": sys.argv[2]}))' "$1" "$2"
}

multi_edit_input() {
  python3 -c '
import json, sys
count = int(sys.argv[1])
print(json.dumps({"file_path": "src/parser.py", "edits": [{"old_string": f"a{i}", "new_string": f"b{i}"} for i in range(count)]}))' "$1"
}

write_input() {
  python3 -c '
import json, sys
print(json.dumps({"file_path": sys.argv[1], "content": "retries = 3\n"}))' "$1"
}

output_for() {
  python3 -c '
import json, sys
print(json.dumps({"hook_event_name": sys.argv[3], "session_id": "s1", "tool_name": sys.argv[1], "tool_input": json.loads(sys.argv[2])}))' "$1" "$2" "${3:-PreToolUse}" \
    | python3 "$nudge"
}

expect() {
  local want="$1" tool="$2" input="$3" got
  if output_for "$tool" "$input" "${4:-PreToolUse}" | grep -q additionalContext; then got=nudge; else got=quiet; fi
  if [ "$got" != "$want" ]; then
    echo "FAIL: expected $want for $tool ${input:0:80}"
    failures=$((failures + 1))
  fi
}

expect_mentions() {
  local tool="$1" input="$2" output
  shift 2
  output="$(output_for "$tool" "$input")"
  for expected in "$@"; do
    if ! printf '%s' "$output" | grep -qF -- "$expected"; then
      echo "FAIL: nudge for $tool should mention: $expected (got $output)"
      failures=$((failures + 1))
    fi
  done
}

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

unset CLAUDE_OLLAMA_EDIT_NUDGE CLAUDE_TOOL_TELEMETRY

expect nudge Edit "$(edit_input "$(numbered_lines 50)" "$(replaced_lines 50 2)")"
expect_mentions Edit "$(edit_input "$(numbered_lines 50)" "$(replaced_lines 50 2)")" "old_string echoes 50 lines to change 2" "narrow it to the changed lines plus two of context"
expect quiet Edit "$(edit_input "$(numbered_lines 50)" "$(replaced_lines 50 13)")"
expect nudge Edit "$(edit_input "$(numbered_lines 50)" "$(replaced_lines 50 12)")"
expect quiet Edit "$(edit_input "$(numbered_lines 40)" "$(replaced_lines 40 1)")"
expect nudge Edit "$(edit_input "$(numbered_lines 41)" "$(replaced_lines 41 1)")"
expect nudge Edit "$(edit_input "$(long_lines 10 160)" "$(long_lines 10 160 | sed '1s/x/y/')")"
expect quiet Edit "$(edit_input "$(long_lines 10 149)" "$(long_lines 10 149 | sed '1s/x/y/')")"
expect quiet Edit "$(edit_input "$(numbered_lines 3)" "$(replaced_lines 3 1)")"
expect quiet Edit "$(edit_input "$(numbered_lines 50)" "")"
expect quiet Edit '{"file_path": "src/parser.py"}'

long_file="$sandbox/long.py"
numbered_lines 61 > "$long_file"
short_file="$sandbox/short.py"
numbered_lines 60 > "$short_file"
expect nudge Write "$(write_input "$long_file")"
expect_mentions Write "$(write_input "$long_file")" "Write rewrites 61 lines" "use Edit for the changed span"
expect quiet Write "$(write_input "$short_file")"
expect quiet Write "$(write_input "$sandbox/new.py")"
expect quiet Write '{"file_path": ""}'

expect nudge MultiEdit "$(multi_edit_input 9)"
expect_mentions MultiEdit "$(multi_edit_input 9)" "split into turns of at most 8 edits so a failed one costs less"
expect quiet MultiEdit "$(multi_edit_input 8)"

expect quiet Read '{"file_path": "src/parser.py"}'
expect quiet Edit "$(edit_input "$(numbered_lines 50)" "$(replaced_lines 50 2)")" PostToolUse

export CLAUDE_OLLAMA_EDIT_NUDGE=0
expect quiet Edit "$(edit_input "$(numbered_lines 50)" "$(replaced_lines 50 2)")"
expect quiet Write "$(write_input "$long_file")"
expect quiet MultiEdit "$(multi_edit_input 9)"
unset CLAUDE_OLLAMA_EDIT_NUDGE

check "the nudge must never deny" test "$(output_for Edit "$(edit_input "$(numbered_lines 50)" "$(replaced_lines 50 2)")" | grep -c permissionDecision)" -eq 0

export CLAUDE_TOOL_TELEMETRY="$telemetry"
output_for Edit "$(edit_input "$(numbered_lines 50)" "$(replaced_lines 50 2)")" >/dev/null
output_for Write "$(write_input "$long_file")" >/dev/null
output_for MultiEdit "$(multi_edit_input 9)" >/dev/null
output_for MultiEdit "$(multi_edit_input 2)" >/dev/null
check "each nudge writes one telemetry line" test "$(wc -l < "$telemetry" | tr -d ' ')" -eq 3
check "the telemetry line has the nudge kind" test "$(grep -c '"kind": "nudge"' "$telemetry")" -eq 3
check "the telemetry line names the hook" test "$(grep -c '"hook": "edit-nudge"' "$telemetry")" -eq 3
check "the telemetry lines carry the rule ids" grep -q '"rule": "edit/echoed-old-string"' "$telemetry"
check "the write rule has its id" grep -q '"rule": "write/rewrites-file"' "$telemetry"
check "the multi-edit rule has its id" grep -q '"rule": "multiedit/too-many-edits"' "$telemetry"
check "telemetry never holds the edited text" test "$(grep -c 'of the span' "$telemetry")" -eq 0
unset CLAUDE_TOOL_TELEMETRY

if ! printf 'not json' | python3 "$nudge" >/dev/null 2>&1; then
  echo "FAIL: bad input must exit 0"
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
