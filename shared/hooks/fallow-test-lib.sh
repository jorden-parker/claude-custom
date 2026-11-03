#!/usr/bin/env bash
failures=0
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export HOME="$sandbox/home"
mkdir -p "$HOME"

stubs="$sandbox/stubs"
mkdir -p "$stubs"
cat > "$stubs/fallow" <<'STUB'
#!/bin/sh
echo "cwd=$(pwd) args=$*" >> "${FALLOW_STUB_LOG:-/dev/null}"
case " $* " in *" audit "*) cat "$FALLOW_STUB_REPORT" ;; esac
exit 0
STUB
chmod +x "$stubs/fallow"
export FALLOW_STUB_LOG="$sandbox/fallow-calls.log"
export path_without_fallow="$PATH"
export PATH="$stubs:$PATH"

npx_only_stubs="$sandbox/npx-only-stubs"
mkdir -p "$npx_only_stubs"
cat > "$npx_only_stubs/npx" <<'STUB'
#!/bin/sh
[ "$1" = -y ] && shift
name="$1"
shift
if [ -x "./node_modules/.bin/$name" ]; then exec "./node_modules/.bin/$name" "$@"; fi
exec "$FALLOW_STUB_BIN" "$@"
STUB
chmod +x "$npx_only_stubs/npx"
export FALLOW_STUB_BIN="$stubs/fallow"

make_planted_project() {
  local planted="$sandbox/planted"
  mkdir -p "$planted/src" "$planted/node_modules/.bin"
  printf '{}' > "$planted/package.json"
  git -C "$planted" init -q
  printf '#!/bin/sh\ntouch "%s/planted-ran"\nexit 0\n' "$sandbox" > "$planted/node_modules/.bin/fallow"
  chmod +x "$planted/node_modules/.bin/fallow"
  rm -f "$sandbox/planted-ran" "$FALLOW_STUB_LOG"
  printf '%s' "$planted"
}

js_project="$sandbox/js"
mkdir -p "$js_project/src"
printf '{}' > "$js_project/package.json"
git -C "$js_project" init -q

fail_report="$sandbox/fail.json"
pass_report="$sandbox/pass.json"
printf '%s' '{"verdict":"fail","summary":{"dead_code_issues":1,"complexity_findings":0,"duplication_clone_groups":0},"dead_code":{"unused_exports":[{"path":"src/a.ts","line":3,"export_name":"foo"}]}}' > "$fail_report"
printf '%s' '{"verdict":"pass","summary":{"dead_code_issues":0,"complexity_findings":0,"duplication_clone_groups":0}}' > "$pass_report"
export FALLOW_STUB_REPORT="$pass_report"

hook_path() {
  printf '%s/%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" "$1"
}

json_string() {
  printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'
}

expect_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label (want '$want', got '$got')"
    failures=$((failures + 1))
  fi
}

finish() {
  [ "$failures" -eq 0 ] && echo "all passed" && exit 0
  exit 1
}
