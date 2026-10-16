#!/usr/bin/env bash
set -u
hook="$(cd "$(dirname "$0")" && pwd)/stop-verify.py"
failures=0
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

stubs="$sandbox/stubs"
mkdir -p "$stubs"
printf '#!/bin/sh\necho "$*" >> "%s/npx.log"\necho "fallow says: unused export unusedHelper"\nexit "${FAKE_FALLOW_EXIT:-0}"\n' "$sandbox" > "$stubs/npx"
chmod +x "$stubs/npx"

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
  rm -f "$sandbox/npx.log"
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

[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
