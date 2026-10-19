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

if [ "$failures" -ne 0 ]; then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
