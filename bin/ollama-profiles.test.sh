#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
gen="$repo/bin/ollama-profiles"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

check_eq() {
  if [ "$2" != "$3" ]; then
    fail "$1: expected [$2] got [$3]"
  fi
}

check_that() {
  local name="$1"
  shift
  "$@" || fail "$name"
}

check_not() {
  local name="$1"
  shift
  if "$@"; then
    fail "$name"
  fi
}

profiles="$sandbox/ollama"
cp -R "$repo/ollama" "$profiles"

generate() {
  OLLAMA_PROFILE_DIR="$profiles" "$gen" "$@"
}

exit_status_of() {
  generate "$@" >/dev/null 2>&1
  echo $?
}

check_eq "check passes on current files" 0 "$(exit_status_of --check)"

sed 's/65536/32768/' "$profiles/settings.27b.json" > "$sandbox/stale.json" && mv "$sandbox/stale.json" "$profiles/settings.27b.json"
check_eq "check fails on a stale file" 1 "$(exit_status_of --check)"
check_that "check names the stale file" sh -c "OLLAMA_PROFILE_DIR='$profiles' '$gen' --check 2>&1 | grep -q 'settings.27b.json'"

generate >/dev/null
check_that "render restores the stale file" cmp -s "$repo/ollama/settings.27b.json" "$profiles/settings.27b.json"

printf '{"27b":{"base":"qwen3.8:27b-mlx","model":"qwen3.8-27b-cc","context":65536},"9b":{"base":"qwen3.5:9b-mlx","model":"qwen3.5-9b-cc","context":2048}}\n' > "$profiles/sizes.json"
generate >/dev/null
check_that "render creates a new size" test -f "$profiles/settings.9b.json"
check_eq "new size has its model" "qwen3.5-9b-cc" "$(jq -r .model "$profiles/settings.9b.json")"
check_eq "new size has its context" "2048" "$(jq -r .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS "$profiles/settings.9b.json")"
check_eq "new size Modelfile" "FROM qwen3.5:9b-mlx
PARAMETER num_ctx 2048" "$(cat "$profiles/Modelfile.9b")"
check_not "render removes a size no longer listed" test -f "$profiles/settings.35b.json"
check_eq "check passes after a size is added" 0 "$(exit_status_of --check)"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
