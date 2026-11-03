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
causes_copy="$sandbox/web/console/src/lib/incident-causes.generated.json"
mkdir -p "${causes_copy%/*}"
cp "$repo/web/console/src/lib/incident-causes.generated.json" "$causes_copy"

generate() {
  CLAUDE_CUSTOM_REPO="$sandbox" "$gen" "$@"
}

exit_status_of() {
  generate "$@" >/dev/null 2>&1
  echo $?
}

check_eq "check passes on current files" 0 "$(exit_status_of --check)"
check_eq "the 27b Modelfile keeps the full context as num_ctx" "PARAMETER num_ctx 65536" "$(grep '^PARAMETER num_ctx' "$profiles/Modelfile.27b")"
check_eq "the 27b context tokens leave room for the output and the compaction summary" 53248 "$(jq -r .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS "$profiles/settings.27b.json")"
check_eq "the output tokens come from the size's output_tokens" 8192 "$(jq -r .env.CLAUDE_CODE_MAX_OUTPUT_TOKENS "$profiles/settings.27b.json")"
check_eq "the 27b Modelfile caps each reply at the size's output_tokens" "PARAMETER num_predict 8192" "$(grep '^PARAMETER num_predict' "$profiles/Modelfile.27b")"
check_eq "the 35b context tokens leave the same room" 86016 "$(jq -r .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS "$profiles/settings.35b.json")"

sed 's/53248/32768/' "$profiles/settings.27b.json" > "$sandbox/stale.json" && mv "$sandbox/stale.json" "$profiles/settings.27b.json"
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

check_eq "the console's cause list is the incidents cause list" "$(jq -cS . "$profiles/incidents/causes.json")" "$(jq -cS . "$causes_copy")"
jq '.melted = "error"' "$profiles/incidents/causes.json" > "$sandbox/causes.json" && mv "$sandbox/causes.json" "$profiles/incidents/causes.json"
check_eq "check fails when the console's cause list is stale" 1 "$(exit_status_of --check)"
check_that "check names the stale cause list" sh -c "CLAUDE_CUSTOM_REPO='$sandbox' '$gen' --check 2>&1 | grep -q 'incident-causes.generated.json'"
generate >/dev/null
check_eq "render copies a new cause to the console" error "$(jq -r .melted "$causes_copy")"
check_eq "render keeps the cause order" "$(jq -r 'keys_unsorted | join(" ")' "$profiles/incidents/causes.json")" "$(jq -r 'keys_unsorted | join(" ")' "$causes_copy")"
jq '{unknown} + .' "$causes_copy" > "$sandbox/reordered.json" && mv "$sandbox/reordered.json" "$causes_copy"
check_eq "check fails when the console's cause list is out of order" 1 "$(exit_status_of --check)"
rm "$causes_copy"
check_eq "check fails when the console's cause list is missing" 1 "$(exit_status_of --check)"
generate >/dev/null

sed 's/"timeout": 600/"timeout": 5/' "$sandbox/personal/settings.tokens.json" > "$sandbox/stale.json" && mv "$sandbox/stale.json" "$sandbox/personal/settings.tokens.json"
check_eq "check fails on a stale personal overlay" 1 "$(exit_status_of --check)"
generate >/dev/null

printf '{"27b":{"base":"qwen3.8:27b-mlx","model":"qwen3.8-27b-cc","context":65536},"9b":{"base":"qwen3.5:9b-mlx","model":"qwen3.5-9b-cc","context":16384},"9b-jinja":{"base":"hf.co/example/Qwen3.5-9B-GGUF:Q4_K_M","model":"qwen3.5-9b-jinja-cc","context":16384,"renderer":"qwen3.5"},"9b-parser":{"base":"./weights/qwen3.5-9b.gguf","model":"qwen3.5-9b-parser-cc","context":16384,"renderer":"qwen3.8","parser":"qwen3.5"},"9b-tuned":{"base":"qwen3.5:9b-mlx","model":"qwen3.5-9b-tuned-cc","context":16384,"renderer":"qwen3.5","parameters":{"top_k":20,"temperature":1}},"9b-short":{"base":"qwen3.5:9b-mlx","model":"qwen3.5-9b-short-cc","context":16384,"output_tokens":4096}}\n' > "$profiles/sizes.json"
generate >/dev/null
check_that "render creates a new size" test -f "$profiles/settings.9b.json"
check_eq "new size has its model" "qwen3.5-9b-cc" "$(jq -r .model "$profiles/settings.9b.json")"
check_eq "new size has its context" "4096" "$(jq -r .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS "$profiles/settings.9b.json")"
check_eq "new size Modelfile" "FROM qwen3.5:9b-mlx
PARAMETER num_ctx 16384
PARAMETER num_predict 8192" "$(cat "$profiles/Modelfile.9b")"
check_eq "a size without output_tokens takes the headroom default" 8192 "$(jq -r .env.CLAUDE_CODE_MAX_OUTPUT_TOKENS "$profiles/settings.9b.json")"
check_eq "a size's own output_tokens caps its replies" "PARAMETER num_predict 4096" "$(grep '^PARAMETER num_predict' "$profiles/Modelfile.9b-short")"
check_eq "a size's own output_tokens reaches its settings" 4096 "$(jq -r .env.CLAUDE_CODE_MAX_OUTPUT_TOKENS "$profiles/settings.9b-short.json")"
check_eq "a size's own output_tokens widens its context tokens" 8192 "$(jq -r .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS "$profiles/settings.9b-short.json")"
check_eq "size with a renderer uses Ollama's renderer and parser" "FROM hf.co/example/Qwen3.5-9B-GGUF:Q4_K_M
PARAMETER num_ctx 16384
PARAMETER num_predict 8192
RENDERER qwen3.5
PARSER qwen3.5" "$(cat "$profiles/Modelfile.9b-jinja")"
check_eq "a size with its own parser renders that parser" "FROM ./weights/qwen3.5-9b.gguf
PARAMETER num_ctx 16384
PARAMETER num_predict 8192
RENDERER qwen3.8
PARSER qwen3.5" "$(cat "$profiles/Modelfile.9b-parser")"
check_eq "a size's parameters render sorted by key" "FROM qwen3.5:9b-mlx
PARAMETER num_ctx 16384
PARAMETER num_predict 8192
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

sed 's/16384/8192/' "$profiles/Modelfile.9b" > "$sandbox/stale.Modelfile" && mv "$sandbox/stale.Modelfile" "$profiles/Modelfile.9b"
check_eq "check without prettier still fails on a stale Modelfile" 1 "$(bare_generate --check >/dev/null 2>&1; echo $?)"

rm -f "$profiles/Modelfile.9b"
check_eq "render without prettier fails" 1 "$(bare_generate >/dev/null 2>&1; echo $?)"
check_that "render without prettier says how to fix it" sh -c "CLAUDE_CUSTOM_REPO='$sandbox' '$bare_repo/bin/ollama-profiles' 2>&1 | grep -q 'pnpm install'"
check_not "render without prettier leaves files unwritten" test -f "$profiles/Modelfile.9b"
generate >/dev/null

printf '{"27b":{"base":"qwen3.8:27b-mlx","model":"qwen3.8-27b-cc","context":65536},"tiny":{"base":"qwen3.5:9b-mlx","model":"qwen3.5-tiny-cc","context":8192}}\n' > "$profiles/sizes.json"
check_eq "a context that leaves no room after the headroom is refused" 1 "$(exit_status_of)"
check_that "the refusal names the size" sh -c "CLAUDE_CUSTOM_REPO='$sandbox' '$gen' 2>&1 | grep -q 'size tiny has context 8192'"
if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
