#!/usr/bin/env bash
set -u
hook="$(cd "$(dirname "$0")" && pwd)/stop-verify.py"
failures=0
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

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
  printf '#!/bin/sh\necho "verify ran"\nexit %s\n' "$2" > "$1/.claude/verify"
  chmod +x "$1/.claude/verify"
}

run_hook() {
  local cwd="$1" active="${2:-false}"
  rm -f "$sandbox/npx.log" "$sandbox/tools.log"
  printf '{"hook_event_name":"Stop","cwd":"%s","stop_hook_active":%s}' "$cwd" "$active" \
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
expect allow 'no verify script, no js'   run_hook "$plain"
check 'fallow skipped outside js'        test ! -e "$sandbox/npx.log"

passing="$(new_repo passing)"
add_verify "$passing" 0
expect allow 'verify passes'             run_hook "$passing"

failing="$(new_repo failing)"
add_verify "$failing" 1
expect block 'verify fails'              run_hook "$failing"
check 'verify output reaches model'      grep -qF 'verify ran' "$sandbox/stderr"
expect allow 'stop_hook_active wins'     run_hook "$failing" true

mkdir -p "$failing/sub"
expect block 'cwd below repo root'       run_hook "$failing/sub"

js="$(new_repo js)"
printf '{}' > "$js/package.json"
expect allow 'clean js project'          run_hook "$js"
check 'fallow audit runs'                grep -qF 'fallow audit' "$sandbox/npx.log"
check 'fallow architecture runs'         grep -qF 'fallow architecture' "$sandbox/npx.log"
check 'fallow uses json'                 grep -qF -- '--format json' "$sandbox/npx.log"
check 'audit is based on main'           grep -qF -- '--base main' "$sandbox/npx.log"

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
expect allow 'master-based js project'   run_hook "$legacy"
check 'audit is based on master'         grep -qF -- '--base master' "$sandbox/npx.log"

ts="$(new_repo ts)"
printf '{}' > "$ts/tsconfig.json"
expect allow 'tsconfig marks js project' run_hook "$ts"
check 'fallow runs for tsconfig'         test -e "$sandbox/npx.log"

maked="$(new_repo maked)"
printf 'test:\n\ttrue\n' > "$maked/Makefile"
expect allow 'makefile test target passes'   run_hook "$maked"
check 'make test was run'                    grep -qxF 'make test' "$sandbox/tools.log"
FAKE_TEST_EXIT=1; export FAKE_TEST_EXIT
expect block 'makefile test target fails'    run_hook "$maked"
unset FAKE_TEST_EXIT

notarget="$(new_repo notarget)"
printf 'build:\n\ttrue\n' > "$notarget/Makefile"
expect allow 'makefile without test target'  run_hook "$notarget"
check 'make not run without test target'     test ! -e "$sandbox/tools.log"

gomod="$(new_repo gomod)"
printf 'module m\n' > "$gomod/go.mod"
expect allow 'go module passes'              run_hook "$gomod"
check 'go test was run'                      grep -qxF 'go test ./...' "$sandbox/tools.log"

pnpmjs="$(new_repo pnpmjs)"
printf '{"scripts":{"test":"vitest run"}}' > "$pnpmjs/package.json"
expect allow 'pnpm test script passes'       run_hook "$pnpmjs"
check 'pnpm test was run'                    grep -qxF 'pnpm test' "$sandbox/tools.log"

noscript="$(new_repo noscript)"
printf '{"scripts":{"build":"tsc"}}' > "$noscript/package.json"
expect allow 'package.json without test script' run_hook "$noscript"
check 'pnpm not run without test script'     test ! -e "$sandbox/tools.log"

both="$(new_repo both)"
add_verify "$both" 1
printf 'test:\n\ttrue\n' > "$both/Makefile"
expect block 'verify script wins over makefile' run_hook "$both"
check 'make skipped when verify exists'      test ! -e "$sandbox/tools.log"

optout="$(new_repo optout)"
printf 'test:\n\ttrue\n' > "$optout/Makefile"
mkdir -p "$optout/.claude" && printf '' > "$optout/.claude/no-verify"
expect allow 'no-verify file disables fallback' run_hook "$optout"
check 'make skipped with no-verify'          test ! -e "$sandbox/tools.log"

if [ "$failures" -eq 0 ]; then echo "all passed"; else echo "$failures failed"; exit 1; fi
