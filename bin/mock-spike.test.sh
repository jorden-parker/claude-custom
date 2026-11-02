#!/bin/bash
set -u

repo="$(cd "$(dirname "$0")/.." && pwd -P)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
failures=0

check_eq() {
  if [ "$2" = "$3" ]; then return; fi
  echo "FAIL: $1 (expected '$2', got '$3')"
  failures=$((failures + 1))
}

check_that() {
  local name="$1"
  shift
  "$@" && return
  echo "FAIL: $name"
  failures=$((failures + 1))
}

mkdir -p "$sandbox/stubbin" "$sandbox/web/scripts"
cp "$repo/web/console/scripts/mock-spike.mts" "$sandbox/web/scripts/"
touch "$sandbox/web/pnpm-lock.yaml"
cat > "$sandbox/stubbin/node" <<EOF
#!/bin/sh
echo "NODE: \$*"
EOF
cat > "$sandbox/stubbin/pnpm" <<EOF
#!/bin/sh
echo "PNPM: \$*"
mkdir -p "$sandbox/web/node_modules"
touch "$sandbox/web/node_modules/.modules.yaml"
EOF
chmod +x "$sandbox/stubbin/node" "$sandbox/stubbin/pnpm"
export PATH="$sandbox/stubbin:$PATH"
export CLAUDE_OLLAMA_WEB_DIR="$sandbox/web"

out="$("$repo/bin/mock-spike" --model m --runs 2 2>"$sandbox/err")"
check_that "installs the console when node_modules is missing" grep -qxF "PNPM: --dir $sandbox/web install --frozen-lockfile" "$sandbox/err"
check_eq "runs the script with the arguments" "NODE: --no-warnings=MODULE_TYPELESS_PACKAGE_JSON $sandbox/web/scripts/mock-spike.mts --model m --runs 2" "$out"

"$repo/bin/mock-spike" --model m >/dev/null 2>"$sandbox/err"
check_that "skips the install when node_modules is current" test ! -s "$sandbox/err"

touch -t 203001010000 "$sandbox/web/pnpm-lock.yaml"
"$repo/bin/mock-spike" --model m >/dev/null 2>"$sandbox/err"
check_that "reinstalls when the lockfile is newer" grep -q '^PNPM:' "$sandbox/err"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  exit 1
fi
