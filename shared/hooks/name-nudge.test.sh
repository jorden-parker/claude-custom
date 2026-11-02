#!/usr/bin/env bash
set -u
nudge="$(dirname "$0")/name-nudge.py"
failures=0

output_for() {
  python3 -c '
import json, sys
print(json.dumps({"hook_event_name": "PreToolUse", "tool_name": sys.argv[1], "tool_input": json.loads(sys.argv[2])}))' "$1" "$2" \
    | python3 "$nudge"
}

expect() {
  local want="$1" tool="$2" input="$3" got
  if output_for "$tool" "$input" | grep -q additionalContext; then got=nudge; else got=quiet; fi
  if [ "$got" != "$want" ]; then
    echo "FAIL: expected $want for $tool $input (got $got)"
    failures=$((failures + 1))
  fi
}

expect_mentions() {
  local tool="$1" input="$2" output
  shift 2
  output="$(output_for "$tool" "$input")"
  for expected in "$@"; do
    if ! printf '%s' "$output" | grep -qF -- "$expected"; then
      echo "FAIL: nudge for $input should mention: $expected"
      failures=$((failures + 1))
    fi
  done
}

expect nudge Edit '{"file_path": "a.go", "new_string": "tmp := parse(x)\n"}'
expect nudge Edit '{"file_path": "a.go", "new_string": "var data2 []byte\n"}'
expect nudge Edit '{"file_path": "a.go", "new_string": "func handleStuff() {}\n"}'
expect nudge Edit '{"file_path": "a.ts", "new_string": "const obj = await load()\n"}'
expect nudge Edit '{"file_path": "a.ts", "new_string": "function doThing(input: string) {}\n"}'
expect nudge Edit '{"file_path": "a.ts", "new_string": "class ConfigHelper {}\n"}'
expect nudge Edit '{"file_path": "a.py", "new_string": "def process_stuff(rows):\n    pass\n"}'
expect nudge Edit '{"file_path": "a.py", "new_string": "result2 = compute()\n"}'
expect nudge Edit '{"file_path": "a.sh", "new_string": "local tmp\ntmp=1\n"}'
expect nudge Write '{"file_path": "src/utils.ts", "content": "export const retryCount = 3\n"}'
expect nudge Write '{"file_path": "misc.py", "content": "retry_count = 3\n"}'
expect nudge Write '{"file_path": "bin/report", "content": "#!/usr/bin/env bash\ntmp=1\n"}'
expect quiet Write '{"file_path": "bin/report", "content": "retries=3\n"}'
expect nudge MultiEdit '{"file_path": "a.go", "edits": [{"old_string": "a", "new_string": "retries := 3\n"}, {"old_string": "b", "new_string": "foo := 3\n"}]}'

expect quiet Edit '{"file_path": "a.go", "new_string": "parsedConfig := parse(raw)\n"}'
expect quiet Edit '{"file_path": "a.go", "new_string": "for i, row := range rows {\n"}'
expect quiet Edit '{"file_path": "a.go", "new_string": "func (s *Server) handleClick(w http.ResponseWriter, r *http.Request) {}\n"}'
expect quiet Edit '{"file_path": "a.ts", "new_string": "const utf8 = new TextDecoder()\nconst sha256 = hash(input)\n"}'
expect quiet Edit '{"file_path": "a.ts", "new_string": "const temperature = 0.2\nconst tmpDir = os.tmpdir()\n"}'
expect quiet Edit '{"file_path": "a.ts", "new_string": "return tmp.join(\",\")\n"}'
expect quiet Edit '{"file_path": "a.py", "new_string": "retry_count = compute()\n"}'
expect quiet Edit '{"file_path": "a.sh", "new_string": "retries=1\n"}'
expect quiet Edit '{"file_path": "a.md", "new_string": "tmp := parse(x)\n"}'
expect quiet Write '{"file_path": "src/profile-rules.ts", "content": "export const retryCount = 3\n"}'
expect quiet Write '{"file_path": "name-nudge.test.sh", "content": "retries=3\n"}'
expect quiet Read '{"file_path": "a.go"}'
expect quiet Edit '{"file_path": "a.go"}'

expect_mentions Edit '{"file_path": "a.go", "new_string": "tmp := parse(x)\nvar data2 []byte\n"}' "tmp" "data2" "what it holds or does"
expect_mentions Write '{"file_path": "src/utils.ts", "content": "export const retryCount = 3\n"}' "utils"

if printf '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"a.go","new_string":"tmp := 1\n"}}' | python3 "$nudge" | grep -q permissionDecision; then
  echo "FAIL: the nudge must never deny"
  failures=$((failures + 1))
fi

if ! printf 'not json' | python3 "$nudge" >/dev/null 2>&1; then
  echo "FAIL: bad input must exit 0"
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  exit 1
fi
