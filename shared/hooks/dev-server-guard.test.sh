#!/usr/bin/env bash
set -u
guard="$(cd "$(dirname "$0")" && pwd)/dev-server-guard.py"
failures=0

decision_for() {
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
    | python3 "$guard" | grep -o '"permissionDecision": *"deny"' >/dev/null && echo deny || echo allow
}

expect() {
  local want="$1" command="$2" got
  got="$(decision_for "$command")"
  if [ "$got" != "$want" ]; then
    echo "FAIL: expected $want for: $command (got $got)"
    failures=$((failures + 1))
  fi
}

expect deny  'pnpm dev'
expect deny  'pnpm run dev'
expect deny  'npm run dev'
expect deny  'npm start'
expect deny  'yarn dev'
expect deny  'bun dev'
expect deny  'bun run dev'
expect deny  'next dev'
expect deny  'npx next dev --turbo'
expect deny  'vite'
expect deny  'vite dev --port 5174'
expect deny  'cd web/pr-review && pnpm dev'
expect deny  'pnpm --filter web dev'
expect deny  'pnpm -C web/pr-review dev'
expect deny  'PORT=3001 pnpm dev'
expect deny  'pnpm dev &'
expect allow 'pnpm build'
expect allow 'pnpm test'
expect allow 'pnpm run devtools'
expect allow 'npm run lint'
expect allow 'next build'
expect allow 'vitest run'
expect allow 'echo pnpm dev'
expect allow 'git commit -m "run pnpm dev"'
expect allow 'grep -n "next dev" package.json'
expect deny  'open http://localhost:4000'
expect deny  'open https://127.0.0.1:4000/x'
expect deny  'open "http://localhost:3000/settings"'
expect deny  'pnpm build && open http://localhost:3000'
expect deny  'xdg-open http://[::1]:5173/'
expect allow 'open README.md'
expect allow 'open https://github.com/anthropics/claude-code'
expect allow 'curl -sf http://localhost:4000/health'
expect allow 'echo open http://localhost:4000'

telemetry_dir="$(mktemp -d)"
trap 'rm -rf "$telemetry_dir"' EXIT
telemetry_log="$telemetry_dir/telemetry.jsonl"

telemetry_for() {
  printf '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
    | CLAUDE_TOOL_TELEMETRY="$telemetry_log" python3 "$guard" >/dev/null
}

recorded_lines() {
  if [ -f "$telemetry_log" ]; then wc -l < "$telemetry_log" | tr -d ' '; else echo 0; fi
}

expect_recorded_lines() {
  local want="$1" command="$2"
  rm -f "$telemetry_log"
  telemetry_for "$command"
  if [ "$(recorded_lines)" != "$want" ]; then
    echo "FAIL: expected $want telemetry line(s) for: $command"
    failures=$((failures + 1))
  fi
}

expect_recorded_lines 1 'pnpm dev'
expect_recorded_lines 0 'pnpm run lint'
rm -f "$telemetry_log"
telemetry_for 'pnpm dev'
if ! grep -qF '"kind": "deny", "hook": "dev-server-guard"' "$telemetry_log"; then
  echo "FAIL: denial line names the kind and hook"
  failures=$((failures + 1))
fi
rm -f "$telemetry_log"
printf '{"tool_name":"Bash","tool_input":{"command":"pnpm dev"}}' | env -u CLAUDE_TOOL_TELEMETRY python3 "$guard" >/dev/null
if [ -e "$telemetry_log" ]; then
  echo "FAIL: nothing is recorded when CLAUDE_TOOL_TELEMETRY is unset"
  failures=$((failures + 1))
fi

mkdir -p "$telemetry_dir/as-directory"
blocked_output="$(printf '{"tool_name":"Bash","tool_input":{"command":"pnpm dev"}}' | CLAUDE_TOOL_TELEMETRY="$telemetry_dir/as-directory" python3 "$guard")"
blocked_status=$?
if ! grep -qF '"permissionDecision": "deny"' <<<"$blocked_output" || [ "$blocked_status" -ne 0 ]; then
  echo "FAIL: a telemetry path that cannot be written still denies, with exit 0"
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
