#!/usr/bin/env bash
set -u
hook="$(cd "$(dirname "$0")" && pwd)/edit-check.py"
failures=0
sandbox="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$sandbox"' EXIT

stubs="$sandbox/stubs"
mkdir -p "$stubs"
make_stub() {
  printf '#!/bin/sh\n%s\n' "$2" > "$stubs/$1"
  chmod +x "$stubs/$1"
}
make_stub gofmt 'grep -l UNFORMATTED "$2" || true'
make_stub go 'grep -q VETFAIL *.go && { echo "vet: VETFAIL found"; exit 1; }; exit 0'
make_stub shellcheck 'grep -q SHELLCHECKFAIL "$1" && { echo "SC2086: SHELLCHECKFAIL"; exit 1; }; exit 0'
make_stub ruff 'grep -q RUFFFAIL "$3" && { echo "ruff: RUFFFAIL"; exit 1; }; exit 0'

js_project="$sandbox/js"
mkdir -p "$js_project/node_modules/.bin" "$js_project/src"
printf '{}' > "$js_project/package.json"
printf 'export default [];\n' > "$js_project/eslint.config.js"
printf '#!/bin/sh\ngrep -q PRETTIERFAIL "$2" && { echo "[warn] $2"; exit 1; }; exit 0\n' > "$js_project/node_modules/.bin/prettier"
printf '#!/bin/sh\ngrep -q ESLINTFAIL "$1" && { echo "error no-unused-vars"; exit 1; }; exit 0\n' > "$js_project/node_modules/.bin/eslint"
cat > "$js_project/node_modules/.bin/tsc" <<'STUB'
#!/bin/sh
echo "$*" >> tsc.log
grep -q TSCFAIL src/a.ts && { echo "src/a.ts(1,14): error TS2304: Cannot find name 'TSCFAIL'."; echo "src/other.ts(2,1): error TS2322: unrelated"; exit 2; }
grep -q OTHERFAIL src/a.ts && { echo "src/other.ts(2,1): error TS2322: unrelated"; exit 2; }
exit 0
STUB
chmod +x "$js_project/node_modules/.bin/"*

json_string() {
  printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'
}

run_write() {
  local file="$1" content="$2"
  mkdir -p "$(dirname "$file")"
  printf '%s' "$content" > "$file"
  printf '{"tool_name":"Write","tool_input":{"file_path":%s,"content":%s}}' \
    "$(json_string "$file")" "$(json_string "$content")" \
    | PATH="$stubs:$PATH" EDIT_CHECK_CACHE_DIR="$sandbox/cache" python3 "$hook" >/dev/null 2>"$sandbox/stderr"
}

run_edit() {
  local file="$1" old="$2" new="$3"
  printf '{"tool_name":"Edit","tool_input":{"file_path":%s,"old_string":%s,"new_string":%s}}' \
    "$(json_string "$file")" "$(json_string "$old")" "$(json_string "$new")" \
    | PATH="$stubs:$PATH" EDIT_CHECK_CACHE_DIR="$sandbox/cache" python3 "$hook" >/dev/null 2>"$sandbox/stderr"
}

verdict() {
  if "$@"; then echo allow; else [ $? -eq 2 ] && echo deny || echo error; fi
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

expect_stderr_has() {
  grep -qF -- "$2" "$sandbox/stderr" || {
    echo "FAIL: $1: stderr lacks [$2]"
    failures=$((failures + 1))
  }
}

mkdir -p "$sandbox/go" && printf "module m\n" > "$sandbox/go/go.mod"
expect allow 'clean go'            run_write "$sandbox/go/main.go" $'package main\n\nfunc main() {}\n'
expect deny  'unformatted go'      run_write "$sandbox/go/main.go" $'package main\n\nvar UNFORMATTED = 1\n'
expect_stderr_has 'unformatted go' 'gofmt'
expect_stderr_has 'unformatted go names the tool' 'gofmt: '
expect deny  'go vet failure'      run_write "$sandbox/go/main.go" $'package main\n\nvar VETFAIL = 1\n'
expect_stderr_has 'go vet names the tool' 'go: '
expect deny  'new go comment'      run_write "$sandbox/go/main.go" $'package main\n\n// explains main\nfunc main() {}\n'
expect_stderr_has 'new go comment' 'explains main'
expect allow 'go build directive'  run_write "$sandbox/go/main.go" $'//go:build linux\n\npackage main\n'

printf 'package main\n\n// kept\nfunc main() {}\n' > "$sandbox/go/main.go"
expect allow 'edit keeps existing comment' run_edit "$sandbox/go/main.go" $'// kept\nfunc main() {}' $'// kept\nfunc main() { run() }'

mkdir -p "$sandbox/tracked" && git -C "$sandbox/tracked" init -q
printf 'x = 1\n# kept by user\ny = 2\n' > "$sandbox/tracked/a.py"
git -C "$sandbox/tracked" add a.py
git -C "$sandbox/tracked" -c user.name=t -c user.email=t@t commit -qm init
expect allow 'write keeps committed comment' run_write "$sandbox/tracked/a.py" $'x = 1\n# kept by user\ny = 3\n'
expect deny  'write adds a comment to a tracked file' run_write "$sandbox/tracked/a.py" $'x = 1\n# kept by user\n# brand new\ny = 3\n'
expect_stderr_has 'write adds a comment to a tracked file' 'brand new'

expect allow 'clean ts'            run_write "$js_project/src/a.ts" $'export const a = 1;\n'
expect deny  'prettier failure'    run_write "$js_project/src/a.ts" $'export const PRETTIERFAIL = 1;\n'
expect_stderr_has 'prettier names the tool' 'prettier: '
expect deny  'eslint failure'      run_write "$js_project/src/a.ts" $'export const ESLINTFAIL = 1;\n'
expect deny  'block comment in ts' run_write "$js_project/src/a.ts" $'/* why */\nexport const a = 1;\n'
expect deny  'eslint-disable'      run_write "$js_project/src/a.ts" $'// eslint-disable-next-line\nexport const a = 1;\n'
expect allow 'ts without tsconfig skips tsc' run_write "$js_project/src/a.ts" $'export const TSCFAIL = 1;\n'
printf '{}' > "$js_project/tsconfig.json"
expect deny  'tsc unknown name'    run_write "$js_project/src/a.ts" $'export const b = TSCFAIL;\n'
expect_stderr_has 'tsc keeps only the edited file' "Cannot find name 'TSCFAIL'"
if grep -q 'src/other.ts' "$sandbox/stderr"; then echo "FAIL: tsc output should drop other files"; failures=$((failures + 1)); fi
if ! grep -q -- '--noEmit' "$js_project/tsc.log"; then echo "FAIL: tsc should run with --noEmit"; failures=$((failures + 1)); fi
expect allow 'tsc errors elsewhere pass' run_write "$js_project/src/a.ts" $'export const b = OTHERFAIL;\n'
expect allow 'js skips tsc'        run_write "$js_project/src/c.js" $'export const b = TSCFAIL;\n'
expect allow 'ts outside project skips linters' run_write "$sandbox/loose/b.ts" $'export const PRETTIERFAIL = 1;\n'

expect deny  'python ruff failure' run_write "$sandbox/py/a.py" $'RUFFFAIL = 1\n'
expect deny  'python comment'      run_write "$sandbox/py/a.py" $'# note\nx = 1\n'
expect allow 'python shebang'      run_write "$sandbox/py/a.py" $'#!/usr/bin/env python3\nx = 1\n'

expect deny  'shellcheck failure'  run_write "$sandbox/sh/a.sh" $'#!/bin/sh\necho $SHELLCHECKFAIL\n'
expect deny  'bash syntax error'   run_write "$sandbox/sh/a.sh" $'#!/bin/sh\nif then\n'
expect deny  'extensionless bash'  run_write "$sandbox/bin/tool" $'#!/usr/bin/env bash\necho $SHELLCHECKFAIL\n'
expect deny  'extensionless python comment' run_write "$sandbox/bin/pytool" $'#!/usr/bin/env python3\n# note\nx = 1\n'
expect deny  'extensionless python ruff'    run_write "$sandbox/bin/pytool" $'#!/usr/bin/env python3\nRUFFFAIL = 1\n'
expect allow 'extensionless python clean'   run_write "$sandbox/bin/pytool" $'#!/usr/bin/env python3\nx = 1\n'
expect allow 'extensionless unknown'        run_write "$sandbox/bin/data" $'#!/usr/bin/env node\n// note\n'

expect allow 'markdown headings'   run_write "$sandbox/doc/README.md" $'# Title\n\n## Section\n'
expect allow 'yaml is not checked' run_write "$sandbox/doc/a.yml" $'# comment\nkey: 1\n'

expect deny  'trailing python noqa'      run_write "$sandbox/py/a.py" $'import os  # noqa: F401\n'
expect deny  'trailing go nolint'        run_write "$sandbox/go/main.go" $'package main\n\nfunc main() {} //nolint:all\n'
expect deny  'trailing ts eslint'        run_write "$js_project/src/a.ts" $'export const a = 1; // eslint-disable-line\n'
expect deny  'trailing shell comment'    run_write "$sandbox/sh/a.sh" $'#!/bin/sh\nrm -rf x  # careful\n'
expect allow 'hash inside python string' run_write "$sandbox/py/a.py" $'CSS = """\n  color: #fff;\n"""\nURL = "http://x/#y"\n'
expect allow 'slashes inside go string'  run_write "$sandbox/go/main.go" $'package main\n\nvar u = "https://example.com"\n'
expect allow 'shell parameter hashes'    run_write "$sandbox/sh/a.sh" $'#!/bin/sh\necho "$#" ${#x} ${f#"$r"/}\n'
expect allow 'python floor division'     run_write "$sandbox/py/a.py" $'x = 7 // 2\n'
printf 'x = 2  # kept\n' > "$sandbox/py/b.py"
expect allow 'edit keeps trailing comment' run_edit "$sandbox/py/b.py" 'x = 1' 'x = 2'
printf 'x = 2  # added\n' > "$sandbox/py/c.py"
expect deny  'edit adds trailing comment' run_edit "$sandbox/py/c.py" 'x = 1' 'x = 2  # added'
expect_stderr_has 'edit adds trailing comment' '# added'

rm -rf "$sandbox/cache"
rm -f "$sandbox/go/main.go"
expect allow 'first clean write runs gofmt' run_write "$sandbox/go/main.go" $'package main\n\nfunc main() {}\n'
printf '' > "$sandbox/gofmt.log"
make_stub gofmt 'echo "$2" >> "'"$sandbox"'/gofmt.log"; grep -l UNFORMATTED "$2" || true'
expect allow 'same content again is allowed' run_write "$sandbox/go/main.go" $'package main\n\nfunc main() {}\n'
check_eq_lines() { [ "$(wc -l < "$1" | tr -d ' ')" = "$2" ] || { echo "FAIL: $3"; failures=$((failures + 1)); }; }
check_eq_lines "$sandbox/gofmt.log" 0 'unchanged content skips gofmt'
expect allow 'changed content runs gofmt' run_write "$sandbox/go/main.go" $'package main\n\nfunc main() { run() }\n'
check_eq_lines "$sandbox/gofmt.log" 1 'changed content runs gofmt once'
expect deny  'failure is never cached' run_write "$sandbox/go/main.go" $'package main\n\nvar UNFORMATTED = 1\n'
expect deny  'failure is re-run next time' run_write "$sandbox/go/main.go" $'package main\n\nvar UNFORMATTED = 1\n'

make_stub sandbox-exec 'echo "$*" >> "'"$sandbox"'/sandbox-exec.log"; while [ "$1" = -f ] || [ "$1" = -D ]; do shift 2; done; exec "$@"'
export CLAUDE_SANDBOX_CACHE_DIR="$sandbox/sandbox-cache"
export CLAUDE_OLLAMA_SANDBOX_EXEC="$stubs/sandbox-exec"
export HOOK_SANDBOX_PLATFORM=darwin
rm -rf "$sandbox/cache" "$sandbox/sandbox-exec.log"
expect allow 'clean js write without the switch' run_write "$js_project/src/sandboxed.ts" $'export const sandboxed = 1;\n'
[ ! -e "$sandbox/sandbox-exec.log" ] || { echo "FAIL: unconfined without the switch"; failures=$((failures + 1)); }
rm -rf "$sandbox/cache"
export CLAUDE_CUSTOM_HOOK_SANDBOX=1
expect allow 'clean js write with the switch' run_write "$js_project/src/sandboxed.ts" $'export const sandboxed = 1;\n'
grep -qF "TARGET_DIR=$js_project" "$sandbox/sandbox-exec.log" 2>/dev/null || { echo "FAIL: project not the sandbox target"; failures=$((failures + 1)); }
grep -qF "node_modules/.bin/prettier" "$sandbox/sandbox-exec.log" 2>/dev/null || { echo "FAIL: prettier not run through sandbox-exec"; failures=$((failures + 1)); }
expect deny 'prettier failure still denies when confined' run_write "$js_project/src/sandboxed.ts" $'export const PRETTIERFAIL = 1;\n'
expect_stderr_has 'confined failure names the sandbox' 'ran in the hook sandbox'
rm -rf "$sandbox/cache" "$sandbox/sandbox-exec.log"
home_project="$sandbox/fakehome"
mkdir -p "$home_project/node_modules/.bin" "$home_project/src"
printf '{}' > "$home_project/package.json"
printf '#!/bin/sh\necho prettier-ran >> "%s/home-prettier.log"\nexit 1\n' "$sandbox" > "$home_project/node_modules/.bin/prettier"
chmod +x "$home_project/node_modules/.bin/prettier"
HOME="$home_project" expect allow 'package root at home is not checked' run_write "$home_project/src/broad.ts" $'export const broad = 1;\n'
[ ! -e "$sandbox/sandbox-exec.log" ] || { echo "FAIL: home-dir root ran through the sandbox"; failures=$((failures + 1)); }
[ ! -e "$sandbox/home-prettier.log" ] || { echo "FAIL: home-dir root ran unconfined"; failures=$((failures + 1)); }
git -C "$js_project" init -q
git -C "$js_project" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
mkdir -p "$js_project/src/deep"
rm -rf "$sandbox/cache"
expect allow 'git toplevel write' run_write "$js_project/src/deep/inner.ts" $'export const inner = 1;\n'
grep -qF "TARGET_DIR=$js_project " "$sandbox/sandbox-exec.log" 2>/dev/null || { echo "FAIL: git toplevel not the sandbox target"; failures=$((failures + 1)); }
unset CLAUDE_CUSTOM_HOOK_SANDBOX CLAUDE_OLLAMA_SANDBOX_EXEC HOOK_SANDBOX_PLATFORM CLAUDE_SANDBOX_CACHE_DIR

[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
