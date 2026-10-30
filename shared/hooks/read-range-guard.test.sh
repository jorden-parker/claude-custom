#!/usr/bin/env bash
set -u
guard="$(dirname "$0")/read-range-guard.py"
tmp="$(mktemp -d)"
failures=0
trap 'rm -rf "$tmp"' EXIT

python3 -c 'print("\n".join(f"line {i}" for i in range(1, 1001)))' > "$tmp/big.py"
python3 -c 'print("\n".join(f"line {i}" for i in range(1, 301)))' > "$tmp/small.py"
printf 'PNG\0binary' > "$tmp/image.png"

decision_for() {
  python3 -c '
import json, sys
tool_input = json.loads(sys.argv[1])
print(json.dumps({"tool_name": "Read", "tool_input": tool_input}))' "$1" \
    | python3 "$guard" | grep -o '"permissionDecision": *"deny"' >/dev/null && echo deny || echo allow
}

reason_for() {
  printf '{"tool_name":"Read","tool_input":%s}' "$1" | python3 "$guard"
}

expect() {
  local want="$1" input="$2" got
  got="$(decision_for "$input")"
  if [ "$got" != "$want" ]; then
    echo "FAIL: expected $want for: $input (got $got)"
    failures=$((failures + 1))
  fi
}

expect deny  "{\"file_path\": \"$tmp/big.py\"}"
expect deny  "{\"file_path\": \"$tmp/big.py\", \"offset\": 100}"
expect deny  "{\"file_path\": \"$tmp/big.py\", \"offset\": 1, \"limit\": 301}"
expect allow "{\"file_path\": \"$tmp/big.py\", \"offset\": 400, \"limit\": 300}"
expect allow "{\"file_path\": \"$tmp/big.py\", \"limit\": 50}"
expect allow "{\"file_path\": \"$tmp/small.py\"}"
expect allow "{\"file_path\": \"$tmp/image.png\"}"
expect allow "{\"file_path\": \"$tmp/missing.py\"}"

reason="$(reason_for "{\"file_path\": \"$tmp/big.py\"}")"
for expected in "1000 lines" "semantic_search" "offset" "limit"; do
  if ! printf '%s' "$reason" | grep -qF -- "$expected"; then
    echo "FAIL: deny reason should mention: $expected"
    failures=$((failures + 1))
  fi
done

telemetry_log="$tmp/telemetry.jsonl"

telemetry_for() {
  printf '{"session_id":"s1","tool_name":"Read","tool_input":{"file_path":"%s"}}' "$1" \
    | CLAUDE_TOOL_TELEMETRY="$telemetry_log" python3 "$guard" >/dev/null
}

recorded_lines() {
  if [ -f "$telemetry_log" ]; then wc -l < "$telemetry_log" | tr -d ' '; else echo 0; fi
}

expect_recorded_lines() {
  local want="$1" path="$2"
  rm -f "$telemetry_log"
  telemetry_for "$path"
  if [ "$(recorded_lines)" != "$want" ]; then
    echo "FAIL: expected $want telemetry line(s) for: $path"
    failures=$((failures + 1))
  fi
}

expect_recorded_lines 1 "$tmp/big.py"
expect_recorded_lines 0 "$tmp/small.py"
rm -f "$telemetry_log"
telemetry_for "$tmp/big.py"
if ! grep -qF '"kind": "deny", "hook": "read-range-guard"' "$telemetry_log"; then
  echo "FAIL: denial line names the kind and hook"
  failures=$((failures + 1))
fi
rm -f "$telemetry_log"
printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$tmp/big.py" | env -u CLAUDE_TOOL_TELEMETRY python3 "$guard" >/dev/null
if [ -e "$telemetry_log" ]; then
  echo "FAIL: nothing is recorded when CLAUDE_TOOL_TELEMETRY is unset"
  failures=$((failures + 1))
fi

mkdir -p "$tmp/as-directory"
blocked_output="$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$tmp/big.py" | CLAUDE_TOOL_TELEMETRY="$tmp/as-directory" python3 "$guard")"
blocked_status=$?
if ! grep -qF '"permissionDecision": "deny"' <<<"$blocked_output" || [ "$blocked_status" -ne 0 ]; then
  echo "FAIL: a telemetry path that cannot be written still denies, with exit 0"
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
