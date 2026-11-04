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
mkdir -p "$sandbox/docs" "$sandbox/web/console/src/lib"
cp "$repo/docs/ollama.md" "$sandbox/docs/"
cp "$repo/web/console/src/lib/profile-env.generated.json" "$sandbox/web/console/src/lib/"
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

section() {
  awk -v id="[$2]" '$0 == id { on = 1; next } /^\[/ { on = 0 } on && NF' "$1"
}

check_eq "check passes on current files" 0 "$(exit_status_of --check)"
check_eq "the presets start with server.ini's [*] section" "$(section "$profiles/server.ini" '*')" "$(section "$profiles/models.ini" '*')"
check_eq "the 27b preset loads the pinned GGUF from the weights dir and its chat template from the templates dir, at the full context, with its sampling keys, thinking off" "model = @WEIGHTS@/Qwen3.8-27B-UD-Q4_K_XL.gguf
chat-template-file = @TEMPLATES@/qwen3.8-27b.jinja
ctx-size = 65536
n-predict = 8192
min-p = 0
presence-penalty = 0
repeat-penalty = 1
temp = 0.7
top-k = 20
top-p = 0.8
reasoning = off" "$(section "$profiles/models.ini" qwen3.8-27b-cc)"
check_eq "the 27b @think preset is the same with thinking on" "$(section "$profiles/models.ini" qwen3.8-27b-cc | sed 's/^reasoning = off$/reasoning = on/')" "$(section "$profiles/models.ini" qwen3.8-27b-cc@think)"
check_eq "the 27b ladder step is the next lower size's context" "$(section "$profiles/models.ini" qwen3.8-27b-cc | sed 's/^ctx-size = .*/ctx-size = 32768/')" "$(section "$profiles/models.ini" qwen3.8-27b-cc@32768)"
check_eq "the 35b ladder step is the 27b context" "ctx-size = 65536" "$(section "$profiles/models.ini" qwen3.6-35b-cc@65536 | grep '^ctx-size')"
check_not "a size without a chat_template keeps the GGUF's own template" sh -c "grep -q '^chat-template-file' <<'EOF'
$(section "$profiles/models.ini" qwen3.6-35b-cc)
EOF"
check_eq "the 35b keeps its presence penalty" "presence-penalty = 1.5" "$(section "$profiles/models.ini" qwen3.6-35b-cc | grep '^presence-penalty')"
check_eq "the smallest size steps down to 75% of its context" "ctx-size = 24576" "$(section "$profiles/models.ini" granite4.2-3b-cc@24576 | grep '^ctx-size')"
check_eq "the embedding preset is named without a colon and keeps the model name as its alias" "alias = qwen3-embedding:0.6b
model = @WEIGHTS@/Qwen3-Embedding-0.6B-Q8_0.gguf
ctx-size = 8192
embeddings = true
pooling = last" "$(section "$profiles/models.ini" qwen3-embedding-0.6b)"
check_eq "every chat section turns reasoning on or off" "$(grep -c '^\[.*-cc' "$profiles/models.ini")" "$(grep -cE '^reasoning = (on|off)$' "$profiles/models.ini")"
check_not "render writes no Modelfile" sh -c "ls '$profiles' | grep -q '^Modelfile'"
check_eq "the 27b context tokens are the full ctx-size, since Claude Code keeps the output and a margin under them itself" 65536 "$(jq -r .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS "$profiles/settings.27b.json")"
check_eq "the output tokens come from the size's output_tokens" 8192 "$(jq -r .env.CLAUDE_CODE_MAX_OUTPUT_TOKENS "$profiles/settings.27b.json")"
check_eq "the 35b context tokens are its full ctx-size too" 98304 "$(jq -r .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS "$profiles/settings.35b.json")"

sed 's/ctx-size = 65536/ctx-size = 1024/' "$profiles/models.ini" > "$sandbox/stale.ini" && mv "$sandbox/stale.ini" "$profiles/models.ini"
check_eq "check fails on stale presets" 1 "$(exit_status_of --check)"
check_that "check names the stale presets" sh -c "CLAUDE_CUSTOM_REPO='$sandbox' '$gen' --check 2>&1 | grep -q 'models.ini'"
generate >/dev/null
check_that "render restores the presets" cmp -s "$repo/ollama/models.ini" "$profiles/models.ini"

user_home="$sandbox/home"
user_profiles="$sandbox/user-profiles"
mkdir -p "$user_home" "$user_profiles"
user_presets() {
  HOME="$user_home" CLAUDE_OLLAMA_WEIGHTS_DIR="$sandbox/weights" CLAUDE_CUSTOM_REPO="$sandbox" "$gen" --user-presets --profiles-dir "$user_profiles" "$@"
}
user_file="$user_home/.claude-ollama/presets/models.ini"
check_eq "user presets report a first write as changed" changed "$(user_presets)"
check_eq "user presets are the repo presets with the weights and templates dirs filled in" "$(sed "s|@WEIGHTS@|$sandbox/weights|; s|@TEMPLATES@|$profiles/templates|" "$profiles/models.ini")" "$(cat "$user_file")"
check_eq "the user presets file is 0600" yes "$([ -n "$(find "$user_file" -perm 600)" ] && echo yes)"
check_eq "its folder is 0700" yes "$([ -n "$(find "${user_file%/*}" -prune -perm 700)" ] && echo yes)"
check_eq "a second write with nothing new reports unchanged" unchanged "$(user_presets)"
printf '%s' '{"context":40960}' > "$user_profiles/ollama-27b.json"
check_eq "a profile context that has no section changes the user presets" changed "$(user_presets)"
check_eq "it adds the base preset at that context" "$(section "$profiles/models.ini" qwen3.8-27b-cc | sed "s|@WEIGHTS@|$sandbox/weights|; s|@TEMPLATES@|$profiles/templates|; s/^ctx-size = .*/ctx-size = 40960/")" "$(section "$user_file" qwen3.8-27b-cc@40960)"
check_eq "and no second copy of the ladder step that already exists" 1 "$(grep -cxF '[qwen3.8-27b-cc@32768]' "$user_file")"
printf '%s' '{"context":30000}' > "$user_profiles/ollama-3b.json"
user_presets >/dev/null
check_eq "a profile context also gets its own ladder step" "ctx-size = 21504" "$(section "$user_file" granite4.2-3b-cc@21504 | grep '^ctx-size')"
printf '%s' '{"context":32768}' > "$user_profiles/ollama-3b.json"
user_presets >/dev/null
check_eq "a profile context equal to the size's own still gets an @<ctx> section" "ctx-size = 32768" "$(section "$user_file" granite4.2-3b-cc@32768 | grep '^ctx-size')"
rm "$user_profiles/ollama-3b.json"
printf '%s' '{"output_tokens":4096,"parameters":{"temperature":0.5}}' > "$user_profiles/ollama-35b.json"
user_presets >/dev/null
check_eq "output_tokens and parameters add an @profile section with them applied" "$(section "$profiles/models.ini" qwen3.6-35b-cc | sed "s|@WEIGHTS@|$sandbox/weights|; s|@TEMPLATES@|$profiles/templates|; s/^n-predict = .*/n-predict = 4096/; s/^temp = .*/temp = 0.5/")" "$(section "$user_file" qwen3.6-35b-cc@profile)"
printf '%s' '{"context":40960,"parameters":{"top_k":40}}' > "$user_profiles/ollama-27b.json"
user_presets >/dev/null
check_eq "an @profile section carries the profile's context too" "ctx-size = 40960 top-k = 40" "$(section "$user_file" qwen3.8-27b-cc@profile | grep -E '^(ctx-size|top-k)' | tr '\n' ' ' | sed 's/ $//')"
check_eq "a context-only profile adds no @profile section" 0 "$(printf '%s' '{"context":40960}' > "$user_profiles/ollama-27b.json"; user_presets >/dev/null; grep -c 'qwen3.8-27b-cc@profile' "$user_file")"
rm "$user_profiles/ollama-27b.json"
ln -s "$user_profiles/ollama-35b.json" "$user_profiles/ollama-27b.json"
check_eq "a symlinked profile is refused" 1 "$(user_presets >/dev/null 2>&1; echo $?)"
rm "$user_profiles/ollama-27b.json"
other_out="$sandbox/other/models.ini"
check_eq "--out writes elsewhere" changed "$(user_presets --out "$other_out")"
check_that "and that file exists" test -f "$other_out"
check_eq "an unknown option is a usage error" 2 "$(user_presets --colour red >/dev/null 2>&1; echo $?)"

check_that "the repo presets copy only the shared section of server.ini" sh -c "! grep -qE '^\[router\]|^models-max' '$profiles/models.ini'"
check_eq "the shared section of the user presets starts as server.ini's" "$(section "$profiles/models.ini" '*')" "$(section "$user_file" '*')"
printf '[*]\ncache-type-k = f16\nmlock = true\n\n[router]\nmodels-max = 3\n' > "$user_home/.claude-ollama/presets/server.local.ini"
check_eq "server.local.ini beside the user presets changes them" changed "$(user_presets)"
check_eq "its shared keys replace server.ini's values in place" "cache-type-k = f16" "$(section "$user_file" '*' | grep '^cache-type-k')"
check_eq "and a key server.ini lacks is added to the shared section" "mlock = true" "$(section "$user_file" '*' | grep '^mlock')"
check_eq "its router flag never reaches the presets" 0 "$(grep -c 'models-max' "$user_file")"
check_eq "the other shared keys stay" "n-gpu-layers = 99" "$(section "$user_file" '*' | grep '^n-gpu-layers')"
check_eq "--check passes on a current user presets file" 0 "$(user_presets --check >/dev/null 2>&1; echo $?)"
check_eq "--check prints current" current "$(user_presets --check)"
printf '[*]\ncache-type-k = q4_0\n' > "$user_home/.claude-ollama/presets/server.local.ini"
check_eq "--check fails once server.local.ini changed" 1 "$(user_presets --check >/dev/null 2>&1; echo $?)"
check_eq "--check prints stale" stale "$(user_presets --check)"
check_eq "--check writes nothing" "cache-type-k = f16" "$(section "$user_file" '*' | grep '^cache-type-k')"
rm "$user_home/.claude-ollama/presets/server.local.ini"
check_eq "--check fails on a missing user presets file" 1 "$(user_presets --check --out "$sandbox/missing/models.ini" >/dev/null 2>&1; echo $?)"

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
check_eq "personal overlay has no Ollama-only hook" 0 "$(jq '[.. | strings | select(contains("repeat-call-cache"))] | length' "$sandbox/personal/settings.tokens.json")"
check_eq "personal overlay keeps the five Read globs" 5 "$(jq '[.permissions.deny[] | select(startswith("Read("))] | length' "$sandbox/personal/settings.tokens.json")"
check_eq "personal overlay keeps its bare tool denies" 12 "$(jq '[.permissions.deny[] | select(startswith("Read(") | not)] | length' "$sandbox/personal/settings.tokens.json")"
check_eq "Read globs expand in place" "Read(**/dist/**)" "$(jq -r '.permissions.deny[0]' "$sandbox/ollama/settings.27b.json")"
check_eq "bare tool denies follow the globs" "Agent" "$(jq -r '.permissions.deny[5]' "$sandbox/ollama/settings.27b.json")"
check_eq "profile hooks add the repeat-call-cache entries" 2 "$(jq '[.. | strings | select(contains("repeat-call-cache"))] | length' "$sandbox/ollama/settings.27b.json")"
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

catalogue="$sandbox/shared/profile-env.json"
console_catalogue="$sandbox/web/console/src/lib/profile-env.generated.json"
env_docs="$sandbox/docs/ollama.md"
check_eq "the console's copy of the env catalogue has the catalogue's content" "$(jq -S . "$repo/shared/profile-env.json")" "$(jq -S . "$repo/web/console/src/lib/profile-env.generated.json")"
check_that "the docs table has a row per catalogue key" sh -c "grep -c '^| \`CLAUDE_' '$repo/docs/ollama.md' | grep -qx \"\$(jq length '$repo/shared/profile-env.json')\""
check_that "the docs table names an integer's range" grep -qF '| Hand off at (% of context), 30 to 85' "$repo/docs/ollama.md"
check_that "the docs table names a choice's values" grep -qF '| After each edit: suggest the test, or run it (`0`, `suggest`, `run`)' "$repo/docs/ollama.md"
jq '(.[] | select(.key == "CLAUDE_OLLAMA_CMUX") | .label) = "Drive the cmux browser"' "$repo/shared/profile-env.json" > "$catalogue"
check_eq "check fails when the env catalogue changed" 1 "$(exit_status_of --check)"
check_that "check names the console's stale copy" sh -c "CLAUDE_CUSTOM_REPO='$sandbox' '$gen' --check 2>&1 | grep -q 'profile-env.generated.json'"
check_that "check names the stale docs table" sh -c "CLAUDE_CUSTOM_REPO='$sandbox' '$gen' --check 2>&1 | grep -q 'docs/ollama.md'"
generate >/dev/null
check_eq "render copies the catalogue to the console" "Drive the cmux browser" "$(jq -r '.[] | select(.key == "CLAUDE_OLLAMA_CMUX") | .label' "$console_catalogue")"
check_that "render writes the new label into the docs table" grep -qF '| `CLAUDE_OLLAMA_CMUX`' "$env_docs"
check_that "the docs row carries the new label" sh -c "grep '^| \`CLAUDE_OLLAMA_CMUX\`' '$env_docs' | grep -qF 'Drive the cmux browser'"
check_eq "render leaves the docs outside the table alone" "$(sed '/profile-env:start/,/profile-env:end/d' "$repo/docs/ollama.md")" "$(sed '/profile-env:start/,/profile-env:end/d' "$env_docs")"
check_eq "check passes after the render" 0 "$(exit_status_of --check)"
cp "$repo/shared/profile-env.json" "$catalogue"
generate >/dev/null

gguf_size() {
  printf '{"base":"org/%s-GGUF/%s.gguf","model":"%s","context":%s,"gguf":{"repo":"org/%s-GGUF","revision":"abc","file":"%s.gguf"}}' "$1" "$1" "$2" "$3" "$1" "$1"
}
jq -n --argjson a "$(gguf_size big qwen3.8-27b-cc 65536)" --argjson b "$(gguf_size nine qwen3.5-9b-cc 16384)" --argjson c "$(gguf_size tuned qwen3.5-9b-tuned-cc 16384)" --argjson d "$(gguf_size short qwen3.5-9b-short-cc 16384)" \
  '{"27b": $a, "9b": $b, "9b-tuned": ($c + {parameters: {top_k: 20, temperature: 1}}), "9b-short": ($d + {output_tokens: 4096})}' > "$profiles/sizes.json"
generate >/dev/null
check_that "render creates a new size" test -f "$profiles/settings.9b.json"
check_eq "new size has its model" "qwen3.5-9b-cc" "$(jq -r .model "$profiles/settings.9b.json")"
check_eq "new size has its context" "16384" "$(jq -r .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS "$profiles/settings.9b.json")"
check_eq "new size preset" "model = @WEIGHTS@/nine.gguf
ctx-size = 16384
n-predict = 8192
reasoning = off" "$(section "$profiles/models.ini" qwen3.5-9b-cc)"
check_eq "a size without output_tokens takes the headroom default" 8192 "$(jq -r .env.CLAUDE_CODE_MAX_OUTPUT_TOKENS "$profiles/settings.9b.json")"
check_eq "a size's own output_tokens caps its replies" "n-predict = 4096" "$(section "$profiles/models.ini" qwen3.5-9b-short-cc | grep '^n-predict')"
check_eq "a size's own output_tokens reaches its settings" 4096 "$(jq -r .env.CLAUDE_CODE_MAX_OUTPUT_TOKENS "$profiles/settings.9b-short.json")"
check_eq "a size's own output_tokens leaves its context tokens at ctx-size" 16384 "$(jq -r .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS "$profiles/settings.9b-short.json")"
check_eq "a size's parameters render as preset keys, sorted" "model = @WEIGHTS@/tuned.gguf
ctx-size = 16384
n-predict = 8192
temp = 1
top-k = 20
reasoning = off" "$(section "$profiles/models.ini" qwen3.5-9b-tuned-cc)"
check_eq "a size at the minimum context steps down no further" "ctx-size = 16384" "$(section "$profiles/models.ini" qwen3.5-9b-cc@16384 | grep '^ctx-size')"
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

sed 's/16384/8192/' "$profiles/models.ini" > "$sandbox/stale.ini" && mv "$sandbox/stale.ini" "$profiles/models.ini"
check_eq "check without prettier still fails on stale presets" 1 "$(bare_generate --check >/dev/null 2>&1; echo $?)"

rm -f "$profiles/settings.9b.json"
check_eq "render without prettier fails" 1 "$(bare_generate >/dev/null 2>&1; echo $?)"
check_that "render without prettier says how to fix it" sh -c "CLAUDE_CUSTOM_REPO='$sandbox' '$bare_repo/bin/ollama-profiles' 2>&1 | grep -q 'pnpm install'"
check_not "render without prettier leaves files unwritten" test -f "$profiles/settings.9b.json"
generate >/dev/null

jq -n --argjson a "$(gguf_size big qwen3.8-27b-cc 65536)" --argjson b "$(gguf_size tiny qwen3.5-tiny-cc 8192)" '{"27b": $a, "tiny": $b}' > "$profiles/sizes.json"
check_eq "a context that leaves no room after the output tokens is refused" 1 "$(exit_status_of)"
check_that "the refusal names the size" sh -c "CLAUDE_CUSTOM_REPO='$sandbox' '$gen' 2>&1 | grep -q 'size tiny has context 8192'"
jq -n --argjson a "$(gguf_size big qwen3.8-27b-cc 65536)" '{"27b": $a, "plain": {"base": "qwen3.5:9b-mlx", "model": "qwen3.5-plain-cc", "context": 16384}}' > "$profiles/sizes.json"
check_eq "a size without a gguf block is refused" 1 "$(exit_status_of)"
check_that "the refusal names the size" sh -c "CLAUDE_CUSTOM_REPO='$sandbox' '$gen' 2>&1 | grep -q 'size plain has no gguf file'"
jq -n --argjson a "$(gguf_size big qwen3.8-27b-cc 65536)" '{"27b": ($a + {parameters: {mirostat: 2}})}' > "$profiles/sizes.json"
check_eq "a parameter with no preset key is refused" 1 "$(exit_status_of)"
if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
