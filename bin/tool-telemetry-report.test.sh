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
  '{"time":1781870530,"session":"b","tool":"Edit","bytes":40,"lines":1,"over_trim_limit":false,"input_bytes":100}' \
  '{"time":1781870531,"session":"b","tool":"Edit","bytes":40,"lines":1,"over_trim_limit":false,"input_bytes":300}' \
  '{"time":1781870532,"session":"b","tool":"Edit","bytes":40,"lines":1,"over_trim_limit":false,"input_bytes":200}' \
  '{"time":1781870533,"session":"b","tool":"Edit","bytes":40,"lines":1,"over_trim_limit":false,"input_bytes":5000}' \
  '{"time":1781870534,"session":"b","tool":"Write","bytes":40,"lines":1,"over_trim_limit":false,"input_bytes":2400}' \
  '{"time":1781870535,"session":"b","kind":"nudge","hook":"edit-nudge","tool":"Edit","reason":"edit/echoed-old-string","rule":"edit/echoed-old-string"}' \
  '{"time":1781870536,"session":"b","kind":"nudge","hook":"edit-nudge","tool":"Edit","reason":"edit/echoed-old-string","rule":"edit/echoed-old-string"}' \
  '{"time":1781870537,"session":"b","kind":"nudge","hook":"edit-nudge","tool":"Write","reason":"write/rewrites-file","rule":"write/rewrites-file"}' \
  '{"time":1781870580,"session":"a","kind":"deny","hook":"bash-output-guard","tool":"Bash","reason":"git log is unbounded"}' \
  'not json, written by a session' \
  '{"time":1781870640,"session":"b","kind":"deny","hook":"bash-output-guard","tool":"Bash","reason":"ls -R is unbounded"}' \
  '{"time":1781870700,"session":"b","kind":"friction","hook":"bash-output-guard","tool":"Bash","reason":"plan reset after 4 near-identical Bash denials","fingerprint":"0123abcd"}' \
  '{"time":1781870760,"session":"b","kind":"friction","hook":"tool-nudge","tool":"Bash","reason":"plan reset after 4 near-identical Bash denials","fingerprint":"4567ef01"}' \
  '{"time":1781870820,"session":"b","kind":"friction","hook":"bash-output-guard","tool":"Bash","reason":"plan reset after 5 near-identical Bash denials","fingerprint":"0123abcd"}' \
  '{"time":1781870880,"session":"b","kind":"friction","hook":"repeat-call-cache","tool":"Read","reason":"same result as call #1 this turn, unchanged since; use it","saved_bytes":1200}' \
  '{"time":1781870940,"session":"b","kind":"friction","hook":"repeat-call-cache","tool":"mcp__repo__git_status","reason":"same result as call #3 this turn, unchanged since; use it","saved_bytes":300}' \
  '{"time":1781871000,"session":"b","kind":"test-after-edit","hook":"test-after-edit","tool":"Edit","reason":"run now: ./x.test.sh","mode":"suggest","found":true,"result":null,"seconds":null}' \
  '{"time":1781871060,"session":"b","kind":"test-after-edit","hook":"test-after-edit","tool":"Edit","reason":"tests: pass (./x.test.sh, 2.1s)","mode":"run","found":true,"result":"pass","seconds":2.1}' \
  '{"time":1781871120,"session":"b","kind":"test-after-edit","hook":"test-after-edit","tool":"Write","reason":"tests: FAIL (./x.test.sh): FAIL: x","mode":"run","found":true,"result":"fail","seconds":0.4}' \
  '{"time":1781871180,"session":"b","kind":"test-after-edit","hook":"test-after-edit","tool":"Edit","reason":"tests: pass (./x.test.sh, 3.1s)","mode":"run","found":true,"result":"pass","seconds":3.1}' \
  '{"time":1781871240,"session":"b","kind":"test-after-edit","hook":"test-after-edit","tool":"Edit","reason":"tests: timed out after 60s (./x.test.sh); run it yourself","mode":"run","found":true,"result":"timeout","seconds":60.0}' >"$log"

output="$("$report" "$log")"
check "Bash totals: 2 calls, 4000 bytes, 1 over the limit" \
  grep -Eq '^Bash +2 +4000 +2000 +3000 +1$' <<<"$output"
check "Read totals: 1 call, 500 bytes, 0 over the limit" \
  grep -Eq '^Read +1 +500 +500 +500 +0$' <<<"$output"
check "largest call is listed with its session" \
  grep -Eq '^ +3000 +Bash +a ' <<<"$output"
check "log path can come from CLAUDE_TOOL_TELEMETRY" \
  grep -Eq '^Read +1 +500 ' <<<"$(CLAUDE_TOOL_TELEMETRY="$log" "$report")"
check "the output section lists Edit input bytes with median and p90" \
  grep -Eq '^Edit +4 +250 +5000$' <<<"$output"
check "the output section lists Write input bytes" \
  grep -Eq '^Write +1 +2400 +2400$' <<<"$output"
check "nudges are counted per rule" \
  grep -qxF 'nudges: edit/echoed-old-string 2, write/rewrites-file 1' <<<"$output"
check "nudges are not counted as denials" test "$(grep -c '^edit-nudge' <<<"$output")" -eq 0
check "denials are counted per hook" \
  grep -Eq '^bash-output-guard +2 ' <<<"$output"
check "the denials table names the most recent reason" \
  grep -Eq '^bash-output-guard +2 +ls -R is unbounded$' <<<"$output"
check "friction trips are counted per hook" \
  grep -Eq '^bash-output-guard +2 trips$' <<<"$output"
check "a second hook's trips are listed" \
  grep -Eq '^tool-nudge +1 trip' <<<"$output"
check "cache hits and bytes saved are summed" \
  grep -qxF 'cache hits: 2, bytes saved: 1500' <<<"$output"
check "friction lines are not counted as denials" \
  grep -Eq '^bash-output-guard +2 +ls -R is unbounded$' <<<"$output"
check "the guards table counts denials and trips per hook with trips per 100 denials" \
  grep -Eq '^bash-output-guard +2 +2 +100$' <<<"$output"
check "a hook with trips and no denials shows no rate" \
  grep -Eq '^tool-nudge +0 +1 +-$' <<<"$output"
check "the tests line counts calls, passes, failures and timeouts with the median seconds" \
  grep -qxF 'tests: 5 calls, 2 pass, 1 fail, 1 timeout, median 2.6s' <<<"$output"
check "test-after-edit lines are not tool calls" test "$(grep -Ec '^Edit +[0-9]+ +[0-9]+ +[0-9]+ +[0-9]+ +[0-9]+$' <<<"$output")" -eq 0
check "cache hits are not guard trips" test "$(grep -c '^repeat-call-cache' <<<"$output")" -eq 0
check "a hook under 30 denials is never flagged" \
  grep -qxF 'lint: none flagged' <<<"$output"
strict_log="$sandbox/strict.log"
{
  for _ in $(seq 25); do echo '{"time":1781870400,"session":"c","kind":"deny","hook":"read-range-guard","tool":"Read","reason":"a.py has 900 lines"}'; done
  for _ in $(seq 10); do echo '{"time":1781870400,"session":"c","kind":"deny","hook":"read-range-guard","tool":"Read","reason":"b.py has 500 lines"}'; done
  for _ in $(seq 8); do echo '{"time":1781870400,"session":"c","kind":"friction","hook":"read-range-guard","tool":"Read","reason":"plan reset after 4 near-identical Read denials","fingerprint":"aa"}'; done
  for _ in $(seq 40); do echo '{"time":1781870400,"session":"c","kind":"deny","hook":"tool-nudge","tool":"Bash","reason":"Text search refused"}'; done
  for _ in $(seq 5); do echo '{"time":1781870400,"session":"c","kind":"friction","hook":"tool-nudge","tool":"Bash","reason":"plan reset after 4 near-identical Bash denials","fingerprint":"bb"}'; done
} >"$strict_log"
strict_output="$("$report" "$strict_log")"
check "trips per 100 denials is rounded" grep -Eq '^read-range-guard +35 +8 +23$' <<<"$strict_output"
check "a hook over 20 trips per 100 denials with 30 or more denials is flagged with its most common reason" \
  grep -qxF 'lint: read-range-guard: message unclear or rule too strict: a.py has 900 lines' <<<"$strict_output"
check "a hook under the rate is not flagged" test "$(grep -c '^lint: tool-nudge' <<<"$strict_output")" -eq 0
calls_only="$sandbox/calls-only.log"
head -n 1 "$log" >"$calls_only"
check "a log with no denials says so" \
  grep -qxF 'denials: none' <<<"$("$report" "$calls_only")"
check "a log with no friction says so" \
  grep -qxF 'friction: none' <<<"$("$report" "$calls_only")"
check "a log with no test runs says so" \
  grep -qxF 'tests: none' <<<"$("$report" "$calls_only")"
check "a log with no guard events says so" \
  grep -qxF 'guards: none' <<<"$("$report" "$calls_only")"
check "a log with no edits or nudges says so" \
  grep -qxF 'output: none' <<<"$("$report" "$calls_only")"
linked_log="$sandbox/linked.log"
ln -s "$log" "$linked_log"
linked_output="$("$report" "$linked_log" 2>"$sandbox/linked.err")"
linked_status=$?
check "a symlinked log is refused" test "$linked_status" -eq 1
check "a symlinked log prints no table" test -z "$linked_output"
check "a symlinked log names the refusal" grep -qF "telemetry log $linked_log is a symlink" "$sandbox/linked.err"
check "missing log is an error" test "$("$report" "$sandbox/none.log" 2>/dev/null; echo $?)" != 0

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
