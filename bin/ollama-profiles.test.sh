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
cp -R "$repo/shared" "$sandbox/shared"
mkdir "$sandbox/personal"
cp "$repo/personal/settings.tokens.template.json" "$repo/personal/settings.tokens.json" "$sandbox/personal/"

generate() {
  CLAUDE_CUSTOM_REPO="$sandbox" "$gen" "$@"
}

exit_status_of() {
  generate "$@" >/dev/null 2>&1
  echo $?
}

check_eq "check passes on current files" 0 "$(exit_status_of --check)"

sed 's/65536/32768/' "$profiles/settings.27b.json" > "$sandbox/stale.json" && mv "$sandbox/stale.json" "$profiles/settings.27b.json"
check_eq "check fails on a stale file" 1 "$(exit_status_of --check)"
check_that "check names the stale file" sh -c "CLAUDE_CUSTOM_REPO='$sandbox' '$gen' --check 2>&1 | grep -q 'settings.27b.json'"

generate >/dev/null
check_that "render restores the stale file" cmp -s "$repo/ollama/settings.27b.json" "$profiles/settings.27b.json"

rm "$sandbox/personal/settings.tokens.json"
generate >/dev/null
check_that "render writes the personal overlay" test -f "$sandbox/personal/settings.tokens.json"
check_that "render writes the personal overlay unchanged" cmp -s "$repo/personal/settings.tokens.json" "$sandbox/personal/settings.tokens.json"
check_eq "personal overlay hooks come from the shared fragment" "$(jq -S . "$repo/shared/settings/hooks.json")" "$(jq -S .hooks "$sandbox/personal/settings.tokens.json")"
check_eq "personal overlay has no Ollama-only hook" 0 "$(jq '[.. | strings | select(contains("tool-nudge"))] | length' "$sandbox/personal/settings.tokens.json")"
check_eq "personal overlay keeps the five Read globs" 5 "$(jq '[.permissions.deny[] | select(startswith("Read("))] | length' "$sandbox/personal/settings.tokens.json")"
check_eq "personal overlay keeps its bare tool denies" 12 "$(jq '[.permissions.deny[] | select(startswith("Read(") | not)] | length' "$sandbox/personal/settings.tokens.json")"
check_eq "Read globs expand in place" "Read(**/dist/**)" "$(jq -r '.permissions.deny[0]' "$sandbox/ollama/settings.27b.json")"
check_eq "bare tool denies follow the globs" "Agent" "$(jq -r '.permissions.deny[5]' "$sandbox/ollama/settings.27b.json")"
check_eq "profile hooks add the tool-nudge entries" 2 "$(jq '[.. | strings | select(contains("tool-nudge"))] | length' "$sandbox/ollama/settings.27b.json")"
check_that "no placeholder survives" sh -c "! grep -q '{{' '$sandbox/ollama/settings.27b.json' '$sandbox/personal/settings.tokens.json'"

sed 's/"timeout": 600/"timeout": 5/' "$sandbox/personal/settings.tokens.json" > "$sandbox/stale.json" && mv "$sandbox/stale.json" "$sandbox/personal/settings.tokens.json"
check_eq "check fails on a stale personal overlay" 1 "$(exit_status_of --check)"
generate >/dev/null

printf '{"27b":{"base":"qwen3.8:27b-mlx","model":"qwen3.8-27b-cc","context":65536},"9b":{"base":"qwen3.5:9b-mlx","model":"qwen3.5-9b-cc","context":2048},"9b-jinja":{"base":"hf.co/example/Qwen3.5-9B-GGUF:Q4_K_M","model":"qwen3.5-9b-jinja-cc","context":2048,"renderer":"qwen3.5"},"9b-parser":{"base":"./weights/qwen3.5-9b.gguf","model":"qwen3.5-9b-parser-cc","context":2048,"renderer":"qwen3.8","parser":"qwen3.5"},"9b-tuned":{"base":"qwen3.5:9b-mlx","model":"qwen3.5-9b-tuned-cc","context":2048,"renderer":"qwen3.5","parameters":{"top_k":20,"temperature":1}}}\n' > "$profiles/sizes.json"
generate >/dev/null
check_that "render creates a new size" test -f "$profiles/settings.9b.json"
check_eq "new size has its model" "qwen3.5-9b-cc" "$(jq -r .model "$profiles/settings.9b.json")"
check_eq "new size has its context" "2048" "$(jq -r .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS "$profiles/settings.9b.json")"
check_eq "new size Modelfile" "FROM qwen3.5:9b-mlx
PARAMETER num_ctx 2048" "$(cat "$profiles/Modelfile.9b")"
check_eq "size with a renderer uses Ollama's renderer and parser" "FROM hf.co/example/Qwen3.5-9B-GGUF:Q4_K_M
PARAMETER num_ctx 2048
RENDERER qwen3.5
PARSER qwen3.5" "$(cat "$profiles/Modelfile.9b-jinja")"
check_eq "a size with its own parser renders that parser" "FROM ./weights/qwen3.5-9b.gguf
PARAMETER num_ctx 2048
RENDERER qwen3.8
PARSER qwen3.5" "$(cat "$profiles/Modelfile.9b-parser")"
check_eq "a size's parameters render sorted by key" "FROM qwen3.5:9b-mlx
PARAMETER num_ctx 2048
RENDERER qwen3.5
PARSER qwen3.5
PARAMETER temperature 1
PARAMETER top_k 20" "$(cat "$profiles/Modelfile.9b-tuned")"
check_not "render removes a size no longer listed" test -f "$profiles/settings.35b.json"
check_eq "check passes after a size is added" 0 "$(exit_status_of --check)"

bare_repo="$sandbox/bare-repo"
mkdir -p "$bare_repo/bin"
cp "$gen" "$bare_repo/bin/ollama-profiles"
bare_generate() {
  CLAUDE_CUSTOM_REPO="$sandbox" "$bare_repo/bin/ollama-profiles" "$@"
}

bare_generate >/dev/null 2>&1
check_eq "check passes without prettier installed" 0 "$(bare_generate --check >/dev/null 2>&1; echo $?)"
check_that "check ignores JSON formatting" sh -c "jq -c . '$profiles/settings.9b.json' > '$sandbox/compact.json' && mv '$sandbox/compact.json' '$profiles/settings.9b.json' && CLAUDE_CUSTOM_REPO='$sandbox' '$bare_repo/bin/ollama-profiles' --check"

sed 's/2048/1024/' "$profiles/Modelfile.9b" > "$sandbox/stale.Modelfile" && mv "$sandbox/stale.Modelfile" "$profiles/Modelfile.9b"
check_eq "check without prettier still fails on a stale Modelfile" 1 "$(bare_generate --check >/dev/null 2>&1; echo $?)"

rm -f "$profiles/Modelfile.9b"
check_eq "render without prettier fails" 1 "$(bare_generate >/dev/null 2>&1; echo $?)"
check_that "render without prettier says how to fix it" sh -c "CLAUDE_CUSTOM_REPO='$sandbox' '$bare_repo/bin/ollama-profiles' 2>&1 | grep -q 'pnpm install'"
check_not "render without prettier leaves files unwritten" test -f "$profiles/Modelfile.9b"
generate >/dev/null

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
