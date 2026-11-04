#!/usr/bin/env bash
set -u
hooks_dir="$(cd "$(dirname "$0")" && pwd)"
budget="$hooks_dir/friction_budget.py"
failures=0
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export CLAUDE_CONFIG_DIR="$sandbox/config"
export CLAUDE_TOOL_TELEMETRY="$sandbox/telemetry.jsonl"
export HOOKS_DIR="$hooks_dir"

new_turn() {
  printf '{"session_id":"%s","hook_event_name":"UserPromptSubmit"}' "$1" | python3 "$budget"
}

deny_via() {
  python3 - "$@" <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["HOOKS_DIR"])
import friction_budget
session, hook, alternative, tool, tool_input, reason = sys.argv[1:7]
event = {"session_id": session, "tool_name": tool, "tool_input": json.loads(tool_input)}
print(friction_budget.deny_reason(hook, event, reason, alternative))
PY
}

fingerprint_of() {
  python3 - "$@" <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["HOOKS_DIR"])
import friction_budget
print(friction_budget.fingerprint(sys.argv[1], json.loads(sys.argv[2])))
PY
}

bash_deny() {
  deny_via "$1" bash-output-guard "add | head -50 or -n 20" Bash "{\"command\": $(printf '%s' "$2" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')}" "Unbounded git log."
}

expect_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label (want '$want', got '$got')"
    failures=$((failures + 1))
  fi
}

mentions() { grep -qF -- "$2" <<<"$1" && echo yes || echo no; }

new_turn s1
expect_eq "first denial keeps its reason" "Unbounded git log." "$(bash_deny s1 'git log src/a.py')"
expect_eq "second near-identical denial keeps its reason" "Unbounded git log." "$(bash_deny s1 'git log src/b.py')"
expect_eq "third keeps its reason" "Unbounded git log." "$(bash_deny s1 'git log src/c2.py')"
reset_line="$(bash_deny s1 'git log "x" src/d.py')"
expect_eq "fourth call with the same fingerprint gets a plan reset" no "$(mentions "$reset_line" 'Unbounded git log.')"
expect_eq "the reset is one line" 1 "$(printf '%s\n' "$reset_line" | wc -l | tr -d ' ')"
expect_eq "the reset names what the model keeps trying" yes "$(mentions "$reset_line" 'git log')"
expect_eq "the reset names the one allowed alternative" yes "$(mentions "$reset_line" 'add | head -50 or -n 20')"
expect_eq "the reset orders the model to stop retrying" yes "$(mentions "$reset_line" 'top retrying')"
expect_eq "a fifth call stays reset" yes "$(mentions "$(bash_deny s1 'git log src/e.py')" 'add | head -50')"
expect_eq "the reset ends with the matching recovery recipe, numbered" yes "$(mentions "$reset_line" 'Recovery: 1. ')"
expect_eq "the recipe names the bounded git log" yes "$(mentions "$reset_line" 'git log -n 20 --oneline')"
expect_eq "the recipe names no MCP tool" no "$(mentions "$reset_line" 'mcp__')"
expect_eq "the recipe has at most three steps" no "$(mentions "$reset_line" '4. ')"
new_turn s4
for _ in 1 2 3; do deny_via s4 bash-output-guard "add | head -50" Bash '{"command":"foo"}' "No recipe matches this." >/dev/null; done
unmatched_line="$(deny_via s4 bash-output-guard "add | head -50" Bash '{"command":"foo"}' "No recipe matches this.")"
expect_eq "an unmatched reason gets the plan reset alone" yes "$(mentions "$unmatched_line" 'Stop retrying')"
expect_eq "an unmatched reason gets no steps" no "$(mentions "$unmatched_line" 'Recovery:')"
expect_eq "every friction guard has a recipe file" "" "$(for hook in bash-output-guard read-range-guard tdd-guard; do [ -f "$hooks_dir/../../ollama/recipes/$hook.json" ] || echo "$hook"; done)"
expect_eq "numbered steps stop at three" "1. a; 2. b; 3. c" "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import recovery_recipes; print(recovery_recipes.numbered_steps(["a", "b", "c", "d"]))' "$hooks_dir")"
expect_eq "read-range-guard's recipe matches its reason" yes "$(mentions "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import recovery_recipes; print(recovery_recipes.recovery_line("read-range-guard", "/p/a.py has 900 lines. Find the lines you need first"))' "$hooks_dir")" 'offset')"
expect_eq "a different fingerprint in the same turn is not counted" "Unbounded git log." "$(bash_deny s1 'cat package-lock.json')"
expect_eq "another hook's denial of the same input is counted apart" "Original." \
  "$(deny_via s1 read-range-guard "pass limit 300 or less" Bash '{"command":"git log"}' "Original.")"

expect_eq "each trip writes one friction telemetry line" 3 "$(grep -c '"kind": "friction"' "$CLAUDE_TOOL_TELEMETRY")"
expect_eq "the trip line names the hook" yes "$(mentions "$(cat "$CLAUDE_TOOL_TELEMETRY")" '"hook": "bash-output-guard"')"
expect_eq "the trip line carries a fingerprint hash" yes "$(mentions "$(cat "$CLAUDE_TOOL_TELEMETRY")" '"fingerprint": "')"
expect_eq "the trip line never carries the command" no "$(mentions "$(cat "$CLAUDE_TOOL_TELEMETRY")" 'git log')"

new_turn s1
expect_eq "a new prompt resets the per-turn count" "Unbounded git log." "$(bash_deny s1 'git log')"
bash_deny s1 'git log' >/dev/null
bash_deny s1 'git log' >/dev/null
expect_eq "and the fourth after the reset trips again" yes "$(mentions "$(bash_deny s1 'git log')" 'add | head -50')"

new_turn s2
for _ in 1 2 3 4; do CLAUDE_CUSTOM_FRICTION=0 bash_deny s2 'git log' >/dev/null; done
expect_eq "CLAUDE_CUSTOM_FRICTION=0 always keeps the plain denial" "Unbounded git log." "$(CLAUDE_CUSTOM_FRICTION=0 bash_deny s2 'git log')"

for _ in 1 2 3 4; do bash_deny s9 'git log' >/dev/null; done
expect_eq "a session no prompt armed keeps the plain denial" "Unbounded git log." "$(bash_deny s9 'git log')"
expect_eq "and writes no state" no "$([ -e "$CLAUDE_CONFIG_DIR/cache/friction/s9.json" ] && echo yes || echo no)"

expect_eq "a Bash fingerprint ignores digits, quoted strings and the last path segment" \
  "$(fingerprint_of Bash '{"command":"sed -n 1,20p src/lib/a.ts | grep \"foo\""}')" \
  "$(fingerprint_of Bash '{"command":"sed -n 40,80p src/lib/b.ts | grep '"'"'bar'"'"'"}')"
expect_eq "a different command is a different fingerprint" no \
  "$([ "$(fingerprint_of Bash '{"command":"git log"}')" = "$(fingerprint_of Bash '{"command":"ls -R"}')" ] && echo yes || echo no)"
expect_eq "a Read fingerprint buckets nearby ranges together" \
  "$(fingerprint_of Read '{"file_path":"/p/a.py","offset":1,"limit":400}')" \
  "$(fingerprint_of Read '{"file_path":"/p/a.py","offset":20,"limit":450}')"
expect_eq "a Read with no range buckets with a small offset" \
  "$(fingerprint_of Read '{"file_path":"/p/a.py"}')" \
  "$(fingerprint_of Read '{"file_path":"/p/a.py","offset":40}')"
expect_eq "a Read of a far range is another fingerprint" no \
  "$([ "$(fingerprint_of Read '{"file_path":"/p/a.py","offset":1}')" = "$(fingerprint_of Read '{"file_path":"/p/a.py","offset":900}')" ] && echo yes || echo no)"
expect_eq "another tool's fingerprint is its sorted input" \
  "$(fingerprint_of Grep '{"pattern":"x","path":"/p"}')" \
  "$(fingerprint_of Grep '{"path":"/p","pattern":"x"}')"

call_cache() {
  python3 - "$@" <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["HOOKS_DIR"])
import friction_budget
operation, session = sys.argv[1:3]
if operation == "record":
    print(friction_budget.record_call(session, sys.argv[3], json.loads(sys.argv[4])))
elif operation == "lookup":
    print(json.dumps(friction_budget.lookup_call(session, sys.argv[3]), sort_keys=True))
elif operation == "recorded":
    print(json.dumps(sorted(entry["tag"] for entry in friction_budget.recorded_calls(session))))
elif operation == "snapshots":
    print(friction_budget.call_snapshot_dir(session))
PY
}

new_turn c1
expect_eq "an unrecorded call looks up as nothing" null "$(call_cache lookup c1 Read:a)"
expect_eq "the first recorded call is number 1" 1 "$(call_cache record c1 Read:a '{"tag":"a"}')"
expect_eq "the next recorded call is number 2" 2 "$(call_cache record c1 Read:b '{"tag":"b"}')"
expect_eq "a lookup returns the entry with its number" '{"number": 1, "tag": "a"}' "$(call_cache lookup c1 Read:a)"
expect_eq "recording a key again renumbers it" 3 "$(call_cache record c1 Read:a '{"tag":"a2"}')"
expect_eq "recorded calls lists every entry" '["a2", "b"]' "$(call_cache recorded c1)"
expect_eq "the snapshot folder sits beside the state file" \
  "$CLAUDE_CONFIG_DIR/cache/friction/c1.snapshots" "$(call_cache snapshots c1)"
new_turn c1
expect_eq "a new turn forgets recorded calls" null "$(call_cache lookup c1 Read:a)"
expect_eq "a new turn restarts the numbering" 1 "$(call_cache record c1 Read:a '{"tag":"a"}')"

expect_eq "prompt submit prints nothing" "" "$(new_turn s3)"
new_turn sparallel
for _ in 1 2 3 4 5 6 7 8 9 10; do
  deny_via sparallel bash-output-guard "alt" Bash '{"command": "git log"}' "r" > /dev/null &
done
wait
expect_eq "ten parallel denials of one key count ten" 10 "$(python3 -c "import json,sys; print(sum(json.load(open(sys.argv[1]))['denials'].values()))" "$CLAUDE_CONFIG_DIR/cache/friction/sparallel.json")"
if printf 'not json' | python3 "$budget"; then :; else
  echo "FAIL: bad input must exit 0"
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
