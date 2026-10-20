#!/usr/bin/env bash
set -u
hook="$(cd "$(dirname "$0")" && pwd)/stop-verify.py"
failures=0
sandbox="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$sandbox"' EXIT
export STOP_VERIFY_STATE_DIR="$sandbox/edits"

stubs="$sandbox/stubs"
mkdir -p "$stubs"
cat > "$stubs/npx" <<STUB
#!/bin/sh
echo "\$*" >> "$sandbox/npx.log"
echo "fallow says: unused export unusedHelper"
exit "\${FAKE_FALLOW_EXIT:-0}"
STUB
chmod +x "$stubs/npx"
for tool in make go pnpm; do
  cat > "$stubs/$tool" <<STUB
#!/bin/sh
echo "$tool \$*" >> "$sandbox/tools.log"
exit "\${FAKE_TEST_EXIT:-0}"
STUB
  chmod +x "$stubs/$tool"
done

new_repo() {
  local repo="$sandbox/$1"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  printf '%s' "$repo"
}

add_verify() {
  mkdir -p "$1/.claude"
  printf '#!/bin/sh\necho "verify ran with: $*" | tee "$(dirname "$0")/args"\nexit %s\n' "$2" > "$1/.claude/verify"
  chmod +x "$1/.claude/verify"
}

record_edit() {
  local file="$1" session="${2:-s1}"
  mkdir -p "$(dirname "$file")"
  printf 'edited\n' > "$file"
  printf '{"hook_event_name":"PostToolUse","session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$session" "$file" \
    | python3 "$hook"
}

run_hook() {
  local cwd="$1" active="${2:-false}" session="${3:-s1}"
  rm -f "$sandbox/npx.log" "$sandbox/tools.log"
  printf '{"hook_event_name":"Stop","session_id":"%s","cwd":"%s","stop_hook_active":%s}' "$session" "$cwd" "$active" \
    | PATH="$stubs:$PATH" python3 "$hook" >/dev/null 2>"$sandbox/stderr"
}

verdict() {
  if "$@"; then echo allow; else [ $? -eq 2 ] && echo block || echo error; fi
}

expect() {
  local want="$1" label="$2" got
  shift 2
  got="$(verdict "$@")"
  if [ "$got" != "$want" ]; then
    echo "FAIL: expected $want for: $label (got $got)"
    failures=$((failures + 1))
  fi
}

check() {
  local label="$1"
  shift
  "$@" || { echo "FAIL: $label"; failures=$((failures + 1)); }
}

plain="$(new_repo plain)"
record_edit "$plain/notes.txt"
expect allow 'no verify script, no js'   run_hook "$plain"
check 'fallow skipped outside js'        test ! -e "$sandbox/npx.log"

unedited="$(new_repo unedited)"
add_verify "$unedited" 1
printf '{}' > "$unedited/package.json"
expect allow 'no edits skips checks'     run_hook "$unedited"
check 'no edits skips fallow'            test ! -e "$sandbox/npx.log"

passing="$(new_repo passing)"
add_verify "$passing" 0
record_edit "$passing/src/a.sh"
record_edit "$passing/b.py"
record_edit "$passing/src/a.sh"
expect allow 'verify passes'             run_hook "$passing"
check 'verify gets edited files once'    grep -qxF 'verify ran with: b.py src/a.sh' "$passing/.claude/args"
rm "$passing/.claude/args"
expect allow 'pass clears the edits'     run_hook "$passing"
check 'cleared edits skip verify'        test ! -e "$passing/.claude/args"

failing="$(new_repo failing)"
add_verify "$failing" 1
record_edit "$failing/a.txt"
expect block 'verify fails'              run_hook "$failing"
check 'verify output reaches model'      grep -qF 'verify ran with: a.txt' "$sandbox/stderr"
expect allow 'stop_hook_active wins'     run_hook "$failing" true
expect block 'failure keeps the edits'   run_hook "$failing"
mkdir -p "$failing/sub"
expect block 'cwd below repo root'       run_hook "$failing/sub"
expect allow 'other session has no edits' run_hook "$failing" false s2

outside="$(new_repo outside)"
add_verify "$outside" 1
record_edit "$sandbox/elsewhere/a.txt"
expect allow 'edits outside the repo'    run_hook "$outside"

js="$(new_repo js)"
printf '{}' > "$js/package.json"
record_edit "$js/src/app.ts"
record_edit "$js/README.md"
expect allow 'clean js project'          run_hook "$js"
check 'fallow audits the edited file'    grep -qF 'fallow audit --base main --format json src/app.ts' "$sandbox/npx.log"
check 'fallow skips non-js edits'        test "$(wc -l < "$sandbox/npx.log")" -eq 1
check 'no project-wide fallow'           test -z "$(grep -F 'architecture' "$sandbox/npx.log")"

record_edit "$js/src/app.ts"
export FAKE_FALLOW_EXIT=1
expect block 'fallow findings'           run_hook "$js"
check 'block names fallow explain'       grep -qF 'fallow explain' "$sandbox/stderr"
check 'block shows the finding'          grep -qF 'unusedHelper' "$sandbox/stderr"
unset FAKE_FALLOW_EXIT

legacy="$sandbox/legacy"
mkdir -p "$legacy"
git -C "$legacy" init -q -b master
git -C "$legacy" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
printf '{}' > "$legacy/package.json"
record_edit "$legacy/index.js"
expect allow 'master-based js project'   run_hook "$legacy"
check 'audit is based on master'         grep -qF -- '--base master' "$sandbox/npx.log"

ts="$(new_repo ts)"
printf '{}' > "$ts/tsconfig.json"
record_edit "$ts/index.ts"
expect allow 'tsconfig marks js project' run_hook "$ts"
check 'fallow runs for tsconfig'         test -e "$sandbox/npx.log"

maked="$(new_repo maked)"
printf 'test:\n\ttrue\n' > "$maked/Makefile"
record_edit "$maked/a.c"
expect allow 'makefile test target passes'   run_hook "$maked"
check 'make test was run'                    grep -qxF 'make test' "$sandbox/tools.log"
record_edit "$maked/a.c"
FAKE_TEST_EXIT=1; export FAKE_TEST_EXIT
expect block 'makefile test target fails'    run_hook "$maked"
unset FAKE_TEST_EXIT

notarget="$(new_repo notarget)"
printf 'build:\n\ttrue\n' > "$notarget/Makefile"
record_edit "$notarget/a.c"
expect allow 'makefile without test target'  run_hook "$notarget"
check 'make not run without test target'     test ! -e "$sandbox/tools.log"

gomod="$(new_repo gomod)"
printf 'module m\n' > "$gomod/go.mod"
record_edit "$gomod/main.go"
expect allow 'go module passes'              run_hook "$gomod"
check 'go test was run'                      grep -qxF 'go test ./...' "$sandbox/tools.log"

pnpmjs="$(new_repo pnpmjs)"
printf '{"scripts":{"test":"vitest run"}}' > "$pnpmjs/package.json"
record_edit "$pnpmjs/README.md"
expect allow 'pnpm test script passes'       run_hook "$pnpmjs"
check 'pnpm test was run'                    grep -qxF 'pnpm test' "$sandbox/tools.log"

noscript="$(new_repo noscript)"
printf '{"scripts":{"build":"tsc"}}' > "$noscript/package.json"
record_edit "$noscript/README.md"
expect allow 'package.json without test script' run_hook "$noscript"
check 'pnpm not run without test script'     test ! -e "$sandbox/tools.log"

both="$(new_repo both)"
add_verify "$both" 1
printf 'test:\n\ttrue\n' > "$both/Makefile"
record_edit "$both/a.c"
expect block 'verify script wins over makefile' run_hook "$both"
check 'make skipped when verify exists'      test ! -e "$sandbox/tools.log"

optout="$(new_repo optout)"
printf 'test:\n\ttrue\n' > "$optout/Makefile"
mkdir -p "$optout/.claude" && printf '' > "$optout/.claude/no-verify"
record_edit "$optout/a.c"
expect allow 'no-verify file disables fallback' run_hook "$optout"
check 'make skipped with no-verify'          test ! -e "$sandbox/tools.log"

if [ "$failures" -eq 0 ]; then echo "all passed"; else echo "$failures failed"; exit 1; fi
