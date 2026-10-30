#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
report="$repo/bin/tool-telemetry-report"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
log="$sandbox/telemetry.log"
failures=0

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

printf '%s\n' \
  '{"time":1781870400,"session":"a","tool":"Bash","bytes":1000,"lines":10,"over_trim_limit":false}' \
  '{"time":1781870460,"session":"a","tool":"Bash","bytes":3000,"lines":200,"over_trim_limit":true}' \
  '{"time":1781870520,"session":"b","tool":"Read","bytes":500,"lines":5,"over_trim_limit":false}' \
  '{"time":1781870580,"session":"a","kind":"deny","hook":"bash-output-guard","tool":"Bash","reason":"git log is unbounded"}' \
  'not json, written by a session' \
  '{"time":1781870640,"session":"b","kind":"deny","hook":"bash-output-guard","tool":"Bash","reason":"ls -R is unbounded"}' >"$log"

output="$("$report" "$log")"
check "Bash totals: 2 calls, 4000 bytes, 1 over the limit" \
  grep -Eq '^Bash +2 +4000 +2000 +3000 +1$' <<<"$output"
check "Read totals: 1 call, 500 bytes, 0 over the limit" \
  grep -Eq '^Read +1 +500 +500 +500 +0$' <<<"$output"
check "largest call is listed with its session" \
  grep -Eq '^ +3000 +Bash +a ' <<<"$output"
check "log path can come from CLAUDE_TOOL_TELEMETRY" \
  grep -Eq '^Read +1 +500 ' <<<"$(CLAUDE_TOOL_TELEMETRY="$log" "$report")"
check "denials are counted per hook" \
  grep -Eq '^bash-output-guard +2 ' <<<"$output"
check "the denials table names the most recent reason" \
  grep -Eq '^bash-output-guard +2 +ls -R is unbounded$' <<<"$output"
calls_only="$sandbox/calls-only.log"
head -n 1 "$log" >"$calls_only"
check "a log with no denials says so" \
  grep -qxF 'denials: none' <<<"$("$report" "$calls_only")"
check "missing log is an error" test "$("$report" "$sandbox/none.log" 2>/dev/null; echo $?)" != 0

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
