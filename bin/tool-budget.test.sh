#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
budget="$repo/bin/tool-budget"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
proxy_log="$sandbox/requests.jsonl"
telemetry_log="$sandbox/tool-calls.jsonl"
failures=0

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

check_not() {
  local label="$1"
  shift
  if "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

iso_days_ago() {
  python3 -c 'import sys; from datetime import datetime, timedelta, timezone; print((datetime.now(timezone.utc) - timedelta(days=float(sys.argv[1]))).isoformat(timespec="milliseconds").replace("+00:00", "Z"))' "$1"
}

epoch_days_ago() {
  python3 -c 'import sys, time; print(int(time.time() - float(sys.argv[1]) * 86400))' "$1"
}

proxy_row() {
  printf '{"ts":"%s","request_id":"r","sections":3,"stable_sections":3,"diverged_at":null,"offset":null,"diff":null,"prompt_bytes":10,"ledger":{"system":100,"tools":%s,"messages":5}}\n' "$1" "$2"
}

telemetry_row() {
  printf '{"time":%s,"session":"s","tool":"%s","bytes":10,"lines":1,"over_trim_limit":false}\n' "$1" "$2"
}

{
  for _ in $(seq 25); do
    proxy_row "$(iso_days_ago 1)" '{"Bash":1500,"Read":900,"WebFetch":2048,"TaskStop":150,"Edit":700,"mcp__repo__pr_view":1024}'
  done
  proxy_row "$(iso_days_ago 2)" '{"Bash":1400,"Read":900,"WebFetch":2000,"TaskStop":150,"Edit":700,"mcp__repo__pr_view":1024,"NotebookEdit":5000}'
  for _ in $(seq 30); do
    proxy_row "$(iso_days_ago 20)" '{"Bash":1500,"Read":900,"WebSearch":3000}'
  done
} >"$proxy_log"

{
  for _ in $(seq 4); do telemetry_row "$(epoch_days_ago 1)" Bash; done
  telemetry_row "$(epoch_days_ago 1)" Read
  telemetry_row "$(epoch_days_ago 1)" mcp__repo__pr_view
  telemetry_row "$(epoch_days_ago 1)" Grep
  telemetry_row "$(epoch_days_ago 20)" WebFetch
  printf '{"time":%s,"session":"s","kind":"deny","hook":"bash-output-guard","tool":"WebFetch","reason":"x"}\n' "$(epoch_days_ago 1)"
  echo 'not json'
} >"$telemetry_log"

output="$("$budget" --proxy-log "$proxy_log" --telemetry "$telemetry_log")"
check "the script exits 0" test "$?" -eq 0
check "Bash row: latest schema bytes, 26 requests, bytes per session, 4 calls, bytes per call" \
  grep -Eq '^Bash +1500 +26 +39000 +4 +9750 bytes per call$' <<<"$output"
check "WebFetch is never called inside the window (the deny row and the old call do not count)" \
  grep -Eq '^WebFetch +2048 +26 +53248 +0 +never called$' <<<"$output"
check "rows are sorted by bytes per session, largest first" \
  test "$(grep -E '^(WebFetch|Bash|Read) ' <<<"$output" | awk '{print $1}' | tr '\n' ' ')" = "WebFetch Bash Read "
check "a tool only the telemetry knows gets a row with no schema" \
  grep -Eq '^Grep +0 +0 +0 +1 +0 bytes per call$' <<<"$output"
check_not "requests older than the window are left out" \
  grep -q '^WebSearch ' <<<"$output"
check_not "a tool under 20 requests is not suggested" \
  grep -Eq '^suggest: drop: .*NotebookEdit' <<<"$output"
check_not "a tool under 200 schema bytes is not suggested" \
  grep -Eq '^suggest: drop: .*TaskStop' <<<"$output"
check_not "the protected harness tools are never suggested" \
  grep -Eq '^suggest: drop: .*Edit' <<<"$output"
check "the suggestion names the drops and the KiB saved per request" \
  grep -qxF 'suggest: drop: WebFetch (saves 2.0 KiB per request)' <<<"$output"
check "the keep line lists the rest" \
  grep -qxF 'keep: Bash, mcp__repo__pr_view, Read, Edit, NotebookEdit, TaskStop, Grep' <<<"$output"
check "the protected list says where it comes from" \
  grep -qxF 'protected (built-in list in bin/tool-budget): Bash, Read, Edit, Write, Skill' <<<"$output"
check "the window is named" \
  grep -qxF 'window: last 14 days, 26 requests' <<<"$output"

wide="$("$budget" --proxy-log "$proxy_log" --telemetry "$telemetry_log" --since 30)"
check "--since widens the window" \
  grep -Eq '^WebSearch +3000 +30 +90000 +0 +never called$' <<<"$wide"
check "a wider window counts the old call" \
  grep -Eq '^WebFetch +2048 +26 +53248 +1 ' <<<"$wide"
check "with the old requests inside the window WebSearch is suggested too" \
  grep -qxF 'suggest: drop: WebSearch (saves 2.9 KiB per request)' <<<"$wide"

empty="$("$budget" --proxy-log "$sandbox/missing.jsonl" --telemetry "$sandbox/missing2.jsonl")"
check "missing logs exit 0" test "$?" -eq 0
check "missing logs print an empty window" grep -qxF 'window: last 14 days, 0 requests' <<<"$empty"
check "missing logs suggest nothing" grep -qxF 'suggest: nothing to drop' <<<"$empty"

json="$("$budget" --proxy-log "$proxy_log" --telemetry "$telemetry_log" --json)"
check "--json prints the rows" \
  python3 -c 'import json, sys; report = json.load(sys.stdin); rows = {row["tool"]: row for row in report["rows"]}; sys.exit(0 if rows["WebFetch"] == {"tool": "WebFetch", "schema_bytes": 2048, "requests": 26, "session_bytes": 53248, "calls": 0, "bytes_per_call": None} and rows["Bash"]["bytes_per_call"] == 9750 else 1)' <<<"$json"
check "--json prints the suggestion and the protected list" \
  python3 -c 'import json, sys; report = json.load(sys.stdin); sys.exit(0 if report["suggest"] == {"drop": ["WebFetch"], "keep": ["Bash", "mcp__repo__pr_view", "Read", "Edit", "NotebookEdit", "TaskStop", "Grep"], "saves_bytes": 2048} and report["protected"][0] == "Bash" and report["protected_source"] == "built-in list in bin/tool-budget" and report["since_days"] == 14 and report["requests"] == 26 else 1)' <<<"$json"

if "$budget" --proxy-log "$proxy_log" --telemetry "$telemetry_log" --since 0 >/dev/null 2>"$sandbox/err"; then
  check "--since 0 is refused" false
fi
check "--since 0 names the problem" grep -q 'since' "$sandbox/err"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  exit 1
fi
