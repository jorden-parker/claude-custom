#!/usr/bin/env bash
set -u
hooks_dir="$(cd "$(dirname "$0")" && pwd)"
hook="$hooks_dir/test-after-edit.py"
failures=0
sandbox="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$sandbox"' EXIT
export CLAUDE_TOOL_TELEMETRY="$sandbox/telemetry.jsonl"
export CLAUDE_CONFIG_DIR="$sandbox/config"
export TEST_AFTER_EDIT_CACHE_DIR="$sandbox/cache"
export TEST_AFTER_EDIT_TIMEOUT=5
export TEST_AFTER_EDIT_PLATFORM=darwin
export SANDBOX_PROFILE_SOURCE="$hooks_dir/../../ollama/qwen-sandbox.sb"
project="$sandbox/project"
mkdir -p "$project/.git" "$project/.claude" "$project/shared/hooks" "$project/go/internal/parse" "$project/web/src/lib" "$project/py" "$project/other" "$sandbox/lonely" "$sandbox/bin"
printf '#!/bin/sh\necho verify "$@" >> "%s"\n' "$sandbox/verify.log" > "$project/.claude/verify"
chmod +x "$project/.claude/verify"
printf 'module example\n' > "$project/go/go.mod"
printf '{"name":"web"}' > "$project/web/package.json"
printf 'print(1)\n' > "$project/shared/hooks/tool.py"
cat > "$project/shared/hooks/tool.test.sh" <<'SCRIPT'
#!/bin/sh
echo "run $$" >> "$STUB_LOG"
echo "GOMODCACHE=${GOMODCACHE:-unset}" >> "$STUB_LOG"
if [ "${STUB_OUTCOME:-pass}" = fail ]; then
  echo "line one"
  echo "FAIL: tool prints the wrong thing: expected 1, got 2"
  echo "  at step two"
  echo "  at step three"
  echo "  at step four"
  echo "  at step five"
  exit 1
fi
if [ "${STUB_OUTCOME:-pass}" = hang ]; then
  sleep 12
fi
echo "all passed"
SCRIPT
chmod +x "$project/shared/hooks/tool.test.sh"
touch "$project/go/internal/parse/parse.go" "$project/go/internal/parse/parse_test.go" \
  "$project/web/src/lib/rules.ts" "$project/web/src/lib/rules.test.ts" \
  "$project/py/serve.py" "$project/py/test_serve.py" "$project/other/run.sh" "$sandbox/lonely/thing.sh"
for stub in go pnpm pytest; do
  cat > "$sandbox/bin/$stub" <<SCRIPT
#!/bin/sh
echo "$stub \$*" >> "\$STUB_LOG"
echo "stub ran"
exit "\${STUB_EXIT:-0}"
SCRIPT
  chmod +x "$sandbox/bin/$stub"
done
cat > "$sandbox/bin/sandbox-exec" <<'SCRIPT'
#!/bin/sh
echo "sandbox-exec $*" >> "$STUB_LOG"
while [ "$1" = -f ] || [ "$1" = -D ]; do
  if [ "$1" = -f ]; then
    echo "profile_mode=$(stat -f %Lp "$2" 2>/dev/null || stat -c %a "$2")" >> "$STUB_LOG"
    if cmp -s "$2" "$SANDBOX_PROFILE_SOURCE"; then echo "profile_same=yes" >> "$STUB_LOG"; else echo "profile_same=no" >> "$STUB_LOG"; fi
  fi
  shift 2
done
exec "$@"
SCRIPT
chmod +x "$sandbox/bin/sandbox-exec"
export PATH="$sandbox/bin:$PATH"
export STUB_LOG="$sandbox/stub.log"

event() {
  local tool="$1" file="$2" hook_event="${3:-PostToolUse}"
  printf '{"hook_event_name":"%s","session_id":"%s","cwd":"%s","tool_name":"%s","tool_input":{"file_path":"%s","new_string":"x"}}' "$hook_event" "${SESSION:-s1}" "${CWD:-$project}" "$tool" "$file" \
    | python3 "$hook"
}

context_of() {
  event "$@" | python3 -c 'import json,sys; raw=sys.stdin.read(); print(json.loads(raw)["hookSpecificOutput"]["additionalContext"] if raw.strip() else "")'
}

expect_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label: expected [$want], got [$got]"
    failures=$((failures + 1))
  fi
}

expect_has() {
  local label="$1" text="$2"
  shift 2
  for expected in "$@"; do
    if ! printf '%s' "$text" | grep -qF -- "$expected"; then
      echo "FAIL: $label: lacks [$expected] in [$text]"
      failures=$((failures + 1))
    fi
  done
}

expect_lacks() {
  local label="$1" text="$2" unwanted="$3"
  if printf '%s' "$text" | grep -qF -- "$unwanted"; then
    echo "FAIL: $label: has [$unwanted] in [$text]"
    failures=$((failures + 1))
  fi
}

expect_eq 'suggest mode names the sibling test' 'run now: ./shared/hooks/tool.test.sh' "$(context_of Edit "$project/shared/hooks/tool.py")"
expect_eq 'suggest mode names the Go package test' 'run now: cd go && go test ./internal/parse' "$(context_of Write "$project/go/internal/parse/parse.go")"
expect_eq 'suggest mode names the vitest file' 'run now: pnpm -C web exec vitest run src/lib/rules.test.ts' "$(context_of MultiEdit "$project/web/src/lib/rules.ts")"
expect_eq 'suggest mode names the pytest file' 'run now: pytest py/test_serve.py' "$(context_of Edit "$project/py/serve.py")"
expect_eq 'suggest mode falls back to the project verify script' 'run now: .claude/verify other/run.sh' "$(context_of Edit "$project/other/run.sh")"
expect_eq 'suggest mode asks for the missing test' "no test found beside thing.sh; write $sandbox/lonely/thing.test.sh first" "$(context_of Edit "$sandbox/lonely/thing.sh")"
expect_eq 'editing a test suggests running it' 'run now: ./shared/hooks/tool.test.sh' "$(context_of Edit "$project/shared/hooks/tool.test.sh")"
expect_eq 'a non-code file gets nothing' '' "$(context_of Edit "$project/README.md")"
expect_eq 'another tool gets nothing' '' "$(context_of Read "$project/shared/hooks/tool.py")"
expect_eq 'a PreToolUse event gets nothing' '' "$(context_of Edit "$project/shared/hooks/tool.py" PreToolUse)"
expect_eq 'suggest mode runs nothing' 'missing' "$([ -e "$STUB_LOG" ] && echo present || echo missing)"
expect_eq 'the switch turns it off' '' "$(CLAUDE_OLLAMA_TEST_AFTER_EDIT=0 context_of Edit "$project/shared/hooks/tool.py")"
expect_eq 'an unknown mode suggests' 'run now: ./shared/hooks/tool.test.sh' "$(CLAUDE_OLLAMA_TEST_AFTER_EDIT=maybe context_of Edit "$project/shared/hooks/tool.py")"

export CLAUDE_OLLAMA_TEST_AFTER_EDIT=run
export SESSION=run
pass_line="$(CLAUDE_SANDBOX_CACHE_DIR=/tmp/sandbox-cache GOMODCACHE=/tmp/sandbox-cache/go context_of Edit "$project/shared/hooks/tool.py")"
expect_has 'run mode reports a pass with the command and the seconds' "$pass_line" 'tests: pass (./shared/hooks/tool.test.sh, ' 's)'
expect_lacks 'run mode never returns the output' "$pass_line" 'all passed'
sandbox_line="$(grep '^sandbox-exec ' "$STUB_LOG")"
expect_has 'run mode runs the command under sandbox-exec with the rendered profile and the Seatbelt params' "$sandbox_line" \
  'sandbox-exec -f ' "-D TARGET_DIR=$project " "-D HOME_DIR=$HOME " "-D CACHE_DIR=$HOME/.cache/claude-sandbox " '-D TMP_DIR=' '-D QWEN_DIR=' '-D RUNTIME_DIR=' "/shared/host-env $project/shared/hooks/tool.test.sh"
expect_eq 'the rendered profile is a 0600 temp file' 'profile_mode=600' "$(grep profile_mode= "$STUB_LOG")"
expect_eq 'the rendered profile is the qwen Seatbelt profile' 'profile_same=yes' "$(grep profile_same= "$STUB_LOG")"
expect_eq 'the rendered profile and its scratch folder are removed after the run' 0 "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'test-after-edit.*' | wc -l | tr -d ' ')"
expect_eq 'run mode ran the test once' 1 "$(grep -c '^run ' "$STUB_LOG")"
expect_eq 'run mode goes through host-env, so the sandbox cache never leaks into the test' 'GOMODCACHE=unset' "$(grep GOMODCACHE "$STUB_LOG")"
cached_line="$(context_of Edit "$project/shared/hooks/tool.py")"
expect_eq 'an unchanged file and test hit the cache' 'tests: pass (./shared/hooks/tool.test.sh, cached)' "$cached_line"
expect_eq 'a cache hit runs nothing' 1 "$(grep -c '^run ' "$STUB_LOG")"
printf 'print(2)\n' > "$project/shared/hooks/tool.py"
context_of Edit "$project/shared/hooks/tool.py" >/dev/null
expect_eq 'a changed file runs the test again' 2 "$(grep -c '^run ' "$STUB_LOG")"
printf '\n' >> "$project/shared/hooks/tool.test.sh"
context_of Edit "$project/shared/hooks/tool.py" >/dev/null
expect_eq 'a changed test runs it again' 3 "$(grep -c '^run ' "$STUB_LOG")"

printf 'print(3)\n' > "$project/shared/hooks/tool.py"
fail_line="$(STUB_OUTCOME=fail context_of Edit "$project/shared/hooks/tool.py")"
expect_eq 'run mode reports the first failing line plus the next three' \
  "tests: FAIL (./shared/hooks/tool.test.sh): FAIL: tool prints the wrong thing: expected 1, got 2
  at step two
  at step three
  at step four" "$fail_line"
expect_lacks 'a failure keeps nothing before the failing line' "$fail_line" 'line one'
expect_eq 'a failure is never cached' 5 "$(STUB_OUTCOME=fail context_of Edit "$project/shared/hooks/tool.py" >/dev/null; grep -c '^run ' "$STUB_LOG")"

printf 'print(4)\n' > "$project/shared/hooks/tool.py"
expect_eq 'run mode reports a timeout' \
  'tests: timed out after 5s (./shared/hooks/tool.test.sh); run it yourself' \
  "$(STUB_OUTCOME=hang context_of Edit "$project/shared/hooks/tool.py")"

expect_has 'run mode runs the Go test from the module root' "$(context_of Edit "$project/go/internal/parse/parse.go")" 'tests: pass (cd go && go test ./internal/parse, '
expect_eq 'the go stub saw the package' 'go test ./internal/parse' "$(grep '^go ' "$STUB_LOG")"
expect_has 'run mode reports a stub failure without an assertion line as its tail' "$(STUB_EXIT=1 context_of Edit "$project/py/serve.py")" 'tests: FAIL (pytest py/test_serve.py): stub ran'
expect_has 'run mode runs the verify fallback' "$(context_of Edit "$project/other/run.sh")" 'tests: pass (.claude/verify other/run.sh, '
expect_eq 'the verify script saw the edited file' "verify $project/other/run.sh" "$(cat "$sandbox/verify.log")"
expect_eq 'run mode still asks for a missing test' "no test found beside thing.sh; write $sandbox/lonely/thing.test.sh first" "$(context_of Edit "$sandbox/lonely/thing.sh")"
expect_eq 'run mode never runs an edited test file, it suggests with the reason' \
  'run now: ./shared/hooks/tool.test.sh (not run: edited file is a test)' \
  "$(SESSION=guard1 context_of Edit "$project/shared/hooks/tool.test.sh")"
expect_eq 'run mode never runs a test edited earlier in the session' \
  'run now: ./shared/hooks/tool.test.sh (not run: test edited this session)' \
  "$(SESSION=guard1 context_of Edit "$project/shared/hooks/tool.py")"
expect_has 'another session still runs it' "$(SESSION=guard2 context_of Edit "$project/shared/hooks/tool.py")" 'tests: pass (./shared/hooks/tool.test.sh, '
runs_before="$(grep -c '^run ' "$STUB_LOG")"
expect_eq 'another platform only suggests' \
  'run now: ./shared/hooks/tool.test.sh (not run: no sandbox on this platform)' \
  "$(TEST_AFTER_EDIT_PLATFORM=linux SESSION=guard2 context_of Edit "$project/shared/hooks/tool.py")"
expect_eq 'a missing sandbox-exec only suggests' \
  'run now: ./shared/hooks/tool.test.sh (not run: no sandbox on this platform)' \
  "$(CLAUDE_OLLAMA_SANDBOX_EXEC=/nonexistent/sandbox-exec SESSION=guard2 context_of Edit "$project/shared/hooks/tool.py")"
mkdir -p "$CLAUDE_CONFIG_DIR/cache/test-after-edit"
printf 'not json' > "$CLAUDE_CONFIG_DIR/cache/test-after-edit/guard5.json"
expect_eq 'an unreadable session record refuses to run' \
  'run now: ./shared/hooks/tool.test.sh (not run: session record unreadable)' \
  "$(SESSION=guard5 context_of Edit "$project/shared/hooks/tool.py")"
expect_eq 'an unreadable record is left as it is, so the session keeps refusing' 'not json' "$(cat "$CLAUDE_CONFIG_DIR/cache/test-after-edit/guard5.json")"
ln -s "$project/shared/hooks/tool.test.sh" "$project/shared/hooks/link-to-test.sh"
SESSION=guard6 context_of Edit "$project/shared/hooks/link-to-test.sh" >/dev/null
expect_eq 'a test edited through another name is still the same file' \
  'run now: ./shared/hooks/tool.test.sh (not run: test edited this session)' \
  "$(SESSION=guard6 context_of Edit "$project/shared/hooks/tool.py")"
expect_eq 'a test edited through a link that hides its name is still a test' \
  'run now: ./shared/hooks/tool.test.sh (not run: edited file is a test)' \
  "$(SESSION=guard7 context_of Edit "$project/shared/hooks/link-to-test.sh")"
record_identity="$(python3 -c 'import json,sys; rows=json.load(open(sys.argv[1]))["edited"]; print(all(isinstance(row.get("dev"), int) and isinstance(row.get("ino"), int) for row in rows), len(rows) > 0)' "$CLAUDE_CONFIG_DIR/cache/test-after-edit/guard6.json")"
expect_eq 'the session record stores each edited path with its device and inode' 'True True' "$record_identity"
expect_eq 'no staged temp file is left beside the record' 0 "$(find "$CLAUDE_CONFIG_DIR/cache/test-after-edit" -name '.staged-*' | wc -l | tr -d ' ')"
SESSION=guard3 context_of Write "$project/.claude/verify" >/dev/null
expect_eq 'run mode never runs a verify script edited this session' \
  'run now: .claude/verify other/run.sh (not run: test edited this session)' \
  "$(SESSION=guard3 context_of Edit "$project/other/run.sh")"
expect_eq 'run mode never runs for a file outside the session root' \
  "run now: $project/shared/hooks/tool.test.sh (not run: outside the project)" \
  "$(CWD="$project/other" SESSION=guard4 context_of Edit "$project/shared/hooks/tool.py")"
expect_eq 'the refusals ran nothing' "$runs_before" "$(grep -c '^run ' "$STUB_LOG")"
expect_eq 'run mode never blocks: a failure exits 0' 0 "$(STUB_OUTCOME=fail event Edit "$project/shared/hooks/tool.py" >/dev/null; echo $?)"

telemetry_kinds() {
  python3 -c 'import json,sys
for line in open(sys.argv[1]):
    row = json.loads(line)
    if row.get("kind") == "test-after-edit":
        print(row["mode"], row["found"], row.get("result"), "seconds" in row and row["seconds"] is not None, "all passed" in json.dumps(row))' "$CLAUDE_TOOL_TELEMETRY" | sort | uniq -c | sed 's/^ *//'
}
telemetry="$(telemetry_kinds)"
expect_has 'telemetry records suggest calls with and without a test' "$telemetry" 'suggest True None False False' 'suggest False None False False'
expect_has 'telemetry records run results and seconds, never the output' "$telemetry" 'run True pass True False' 'run True fail True False' 'run True timeout True False' 'run True cached False False' 'run True refused False False' 'run False None False False'
expect_eq 'the off switch records nothing' 0 "$(grep -c '"mode": "0"' "$CLAUDE_TOOL_TELEMETRY")"

if printf 'not json' | python3 "$hook"; then :; else
  echo "FAIL: bad input must exit 0"
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  exit 1
fi
