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
[ -n "\${FAKE_FALLOW_JSON:-}" ] && cat "\$FAKE_FALLOW_JSON"
exit "\${FAKE_FALLOW_EXIT:-0}"
STUB
chmod +x "$stubs/npx"

cat > "$sandbox/audit.json" <<'JSON'
{"kind":"audit","verdict":"fail","summary":{"dead_code_issues":3},
 "dead_code":{"total_issues":3,"entry_points":{"total":1},
  "unused_exports":[
   {"path":"src/app.ts","export_name":"unusedHelper","line":3,"finding_id":"dc1:unused-export:aaa","introduced":true,
    "actions":[{"type":"remove-export","note":"NOTE_SENTINEL long advice paragraph"}]},
   {"path":"src/app.ts","export_name":"inheritedHelper","line":9,"finding_id":"dc1:unused-export:bbb","introduced":false}],
  "unused_class_members":[
   {"path":"src/app.ts","parent_name":"Store","member_name":"scroll","line":12,"finding_id":"dc1:unused-class-member:ccc"}],
  "workspace_diagnostics":[{"path":"node_modules","kind":"node-modules-missing","message":"DIAGNOSTIC_SENTINEL"}]},
 "complexity":{"findings":[{"path":"src/app.ts","line":20,"name":"render","cyclomatic":25,"cognitive":30,"introduced":true}]},
 "duplication":{"clone_groups":[{"instances":[{"file":"src/app.ts","start_line":1,"end_line":9},{"file":"src/b.ts","start_line":4,"end_line":12}]}]},
 "next_steps":[{"command":"fallow schema","reason":"NEXT_STEP_SENTINEL"}]}
JSON
printf '%s\n' '{"kind":"combined","check":{"unused_files":[{"path":"index.js","finding_id":"dc1:unused-file:ddd"}]}}' > "$sandbox/combined.json"
printf '%s\n' '{"error":true,"message":"could not detect base branch","exit_code":2}' > "$sandbox/error.json"
printf '%s\n' 'npm ERR! network request failed' > "$sandbox/garbage.txt"
python3 -c 'import json; print(json.dumps({"kind": "audit", "verdict": "fail", "dead_code": {"unused_exports": [{"path": "src/app.ts", "export_name": f"helper{i}", "line": i + 1, "finding_id": "dc1:unused-export:x"} for i in range(30)]}}))' > "$sandbox/many.json"
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
  printf "#!/bin/sh\necho \"verify ran with: \$*\" | tee \"\$(dirname \"\$0\")/args\"\nexit %s\n" "$2" > "$1/.claude/verify"
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
record_edit "$js/src/other.ts"
export FAKE_FALLOW_EXIT=1 FAKE_FALLOW_JSON="$sandbox/audit.json"
expect block 'fallow findings'           run_hook "$js"
check 'block names fallow explain'       grep -qF 'fallow explain' "$sandbox/stderr"
check 'one line per export finding'      grep -qxF '  unused-export src/app.ts:3 unusedHelper' "$sandbox/stderr"
check 'class member uses member_name'    grep -qxF '  unused-class-member src/app.ts:12 scroll' "$sandbox/stderr"
check 'complexity finding listed'        grep -qxF '  high-complexity src/app.ts:20 render cyclomatic=25 cognitive=30' "$sandbox/stderr"
check 'duplication finding listed'       grep -qxF '  duplication src/app.ts:1-9 = src/b.ts:4-12' "$sandbox/stderr"
check 'findings deduped across files'    test "$(grep -cF 'unusedHelper' "$sandbox/stderr")" -eq 1
check 'inherited finding dropped'        test -z "$(grep -F 'inheritedHelper' "$sandbox/stderr")"
check 'no raw json'                      test -z "$(grep -F -e finding_id -e NOTE_SENTINEL -e '{' "$sandbox/stderr")"
check 'no workspace diagnostics'         test -z "$(grep -F 'DIAGNOSTIC_SENTINEL' "$sandbox/stderr")"
check 'no next steps'                    test -z "$(grep -F 'NEXT_STEP_SENTINEL' "$sandbox/stderr")"
check 'fallow block is short'            test "$(wc -c < "$sandbox/stderr")" -lt 1000

export FAKE_FALLOW_JSON="$sandbox/many.json"
expect block 'many fallow findings'      run_hook "$js"
check 'findings capped at 20'            grep -qxF '  [10 more findings hidden]' "$sandbox/stderr"
check 'twentieth finding shown'          grep -qw 'helper19' "$sandbox/stderr"
check 'twenty-first finding hidden'      test -z "$(grep -w 'helper20' "$sandbox/stderr")"

export FAKE_FALLOW_EXIT=2 FAKE_FALLOW_JSON="$sandbox/error.json"
expect allow 'fallow tool error'         run_hook "$js"
record_edit "$js/src/app.ts"
export FAKE_FALLOW_EXIT=1 FAKE_FALLOW_JSON="$sandbox/garbage.txt"
expect allow 'fallow output not json'    run_hook "$js"
unset FAKE_FALLOW_EXIT FAKE_FALLOW_JSON

legacy="$sandbox/legacy"
mkdir -p "$legacy"
git -C "$legacy" init -q -b master
git -C "$legacy" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
printf '{}' > "$legacy/package.json"
record_edit "$legacy/index.js"
expect allow 'master-based js project'   run_hook "$legacy"
check 'audit is based on master'         grep -qF -- '--base master' "$sandbox/npx.log"

trunk="$sandbox/trunk"
mkdir -p "$trunk"
git -C "$trunk" init -q -b trunk
git -C "$trunk" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
printf '{}' > "$trunk/package.json"
record_edit "$trunk/index.js"
expect allow 'other default branch'      run_hook "$trunk"
check 'audit is based on HEAD'           grep -qF -- '--base HEAD' "$sandbox/npx.log"

nogit="$sandbox/nogit"
mkdir -p "$nogit"
printf '{}' > "$nogit/package.json"
record_edit "$nogit/index.js"
expect allow 'js project outside git'    run_hook "$nogit"
check 'whole-file fallow without git'    grep -qF 'fallow --fail-on-issues --format json index.js' "$sandbox/npx.log"
record_edit "$nogit/index.js"
export FAKE_FALLOW_EXIT=1 FAKE_FALLOW_JSON="$sandbox/combined.json"
expect block 'findings outside git'      run_hook "$nogit"
check 'combined report finding listed'   grep -qxF '  unused-file index.js' "$sandbox/stderr"
unset FAKE_FALLOW_EXIT FAKE_FALLOW_JSON

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

noisy="$(new_repo noisy)"
mkdir -p "$noisy/.claude"
cat > "$noisy/.claude/verify" <<'SCRIPT'
#!/bin/sh
i=0
while [ "$i" -lt 300 ]; do echo "ok early $i"; i=$((i + 1)); done
echo "FAIL: widget renders"
echo "FAIL: widget renders"
i=0
while [ "$i" -lt 300 ]; do echo "ok late $i"; i=$((i + 1)); done
python3 -c 'print("x" * 5000)'
echo "to stderr" >&2
echo "last line"
exit 1
SCRIPT
chmod +x "$noisy/.claude/verify"
record_edit "$noisy/a.txt"
expect block 'noisy verify fails'        run_hook "$noisy"
check 'failure line kept'                grep -qxF 'FAIL: widget renders' "$sandbox/stderr"
check 'failure line deduped'             test "$(grep -cxF 'FAIL: widget renders' "$sandbox/stderr")" -eq 1
check 'tail kept'                        grep -qxF 'last line' "$sandbox/stderr"
check 'hidden lines counted'             grep -qE '^\[[0-9]+ more lines hidden\]$' "$sandbox/stderr"
check 'early noise dropped'              test -z "$(grep -xF 'ok early 5' "$sandbox/stderr")"
check 'long line clipped'                grep -qF 'chars hidden]' "$sandbox/stderr"
check 'no line over 400 chars'           test "$(awk '{ if (length > m) m = length } END { print m + 0 }' "$sandbox/stderr")" -lt 400
check 'verify block is short'            test "$(wc -l < "$sandbox/stderr")" -le 45
check 'stderr stays in order'            test "$(grep -nxF 'to stderr' "$sandbox/stderr" | cut -d: -f1)" -lt "$(grep -nxF 'last line' "$sandbox/stderr" | cut -d: -f1)"

if [ "$failures" -eq 0 ]; then echo "all passed"; else echo "$failures failed"; exit 1; fi
