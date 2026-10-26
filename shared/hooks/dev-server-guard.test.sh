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

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
