#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
qwen_script="$repo/bin/claude-ollama-qwen"
failures=0
sandboxes=""
system_tools=""
unset LLAMA_SERVER_URL

remove_sandboxes() {
  local dir
  local PATH=/usr/bin:/bin
  for dir in $sandboxes; do
    chmod -R u+w "$dir" 2>/dev/null
    rm -rf "$dir"
  done
}

trap remove_sandboxes EXIT

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

build_system_tools() {
  local entry name
  system_tools="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
  sandboxes="$sandboxes $system_tools"
  for entry in /usr/bin/* /bin/*; do
    name="${entry##*/}"
    if [ -x "$entry" ] && [ ! -e "$system_tools/$name" ]; then
      ln -s "$entry" "$system_tools/$name"
    fi
  done
}

write_stub() {
  cat > "$sandbox/stubbin/$1"
  chmod +x "$sandbox/stubbin/$1"
}

new_sandbox() {
  sandbox="$(made="$(mktemp -d /tmp/claude-ollama-qwen-test.XXXXXX)" && cd "$made" && pwd -P)" || exit 1
  sandboxes="$sandboxes $sandbox"
  export HOME="$sandbox/home"
  mkdir -p "$HOME" "$sandbox/stubbin"
  unset XDG_CONFIG_HOME CLAUDE_OLLAMA_SANDBOX_EXEC
  write_stub qwen <<EOF
#!/bin/sh
echo "QWEN ARGS: \$*"
env > "$sandbox/qwen-env"
EOF
  write_stub shasum <<EOF
#!/bin/sh
name="\${3##*/}"
echo "\$(jq -r --arg name "/\$name" 'to_entries[] | select(.key | endswith(\$name)) | .value' "$repo/ollama/model-digests.json" | head -n 1)  \$3"
EOF
  export CLAUDE_OLLAMA_WEIGHTS_DIR="$sandbox/weights"
  mkdir -p "$CLAUDE_OLLAMA_WEIGHTS_DIR"
  for weights_file in $(jq -r '.[] | .gguf.file // empty' "$repo/ollama/sizes.json"); do
    : > "$CLAUDE_OLLAMA_WEIGHTS_DIR/$weights_file"
  done
  [ -n "$system_tools" ] || build_system_tools
  export PATH="$sandbox/stubbin:$system_tools"
}

run_capture() {
  "$@" >"$sandbox/out" 2>"$sandbox/err"
}

new_project() {
  mkdir -p "$1" && git -C "$1" init -q
  cd "$1" || exit 1
}

new_sandbox
qwen_home="$HOME/.claude-ollama/qwen"
return_dir="$(pwd -P)"
new_project "$sandbox/qwen-project"
SANDBOX=outer OPENAI_API_KEY=outer CLAUDE_OLLAMA_SANDBOX_EXEC=/usr/bin/true GH_TOKEN=secret SHORTCUT_API_TOKEN=secret run_capture "$qwen_script" launch 27b -p hi
check_eq "qwen launch exit status" 0 "$?"
check_that "qwen launch passes the model and args to qwen" grep -qF -- "-m qwen3.8-27b-cc --approval-mode auto-edit" "$sandbox/out"
check_that "qwen launch passes the MCP servers" grep -qF -- 'repo-tools.py"]}' "$sandbox/out"
check_that "and the user's args last" grep -q -- '-p hi$' "$sandbox/out"
check_eq "qwen launch gives Qwen Code its own home under the session folder" "QWEN_HOME=$qwen_home" "$(grep '^QWEN_HOME=' "$sandbox/qwen-env")"
check_that "and turns usage statistics off" grep -qx 'QWEN_USAGE_STATISTICS_ENABLED=false' "$sandbox/qwen-env"
check_eq "and points its package caches at the sandbox cache folder" "$HOME/.cache/claude-sandbox/pnpm/cache" \
  "$(grep '^npm_config_cache_dir=' "$sandbox/qwen-env" | cut -d= -f2-)"
check_eq "but leaves pnpm's content store alone, so node_modules linked from it still match" "" \
  "$(grep '^npm_config_store_dir=' "$sandbox/qwen-env")"
check_that "and the models.dev download" grep -qx 'QWEN_CODE_MODELS_DEV_REFRESH=off' "$sandbox/qwen-env"
for folder in skills agents extensions rules commands hooks; do
  check_that "qwen launch creates $folder under its home before the launch, since Qwen Code's startup mkdir is denied inside the sandbox" test -d "$qwen_home/$folder"
done
check_not "an outer OPENAI_API_KEY never reaches the session" grep -q '^OPENAI_API_KEY=' "$sandbox/qwen-env"
check_eq "the rendered settings name the size's model" "qwen3.8-27b-cc qwen3.8-27b-cc" \
  "$(jq -r '[.model.name, .modelProviders.openai[0].id] | join(" ")' "$qwen_home/settings.json")"
check_eq "and point it at llama-server's OpenAI endpoint by address, since the sandbox resolves names only from /etc/hosts" "http://127.0.0.1:11435/v1" "$(jq -r '.modelProviders.openai[0].baseUrl' "$qwen_home/settings.json")"
check_eq "and carry the preset's ctx-size as the context window" 65536 "$(jq -r '.modelProviders.openai[0].generationConfig.contextWindowSize' "$qwen_home/settings.json")"
check_eq "and use a placeholder key that names no Ollama variable" "LLAMA_SERVER_API_KEY llama-server" \
  "$(jq -r '[.modelProviders.openai[0].envKey, .env.LLAMA_SERVER_API_KEY] | join(" ")' "$qwen_home/settings.json")"
check_eq "and ask llama-server for no thinking" none "$(jq -r '.modelProviders.openai[0].generationConfig.extra_body.reasoning_effort' "$qwen_home/settings.json")"
check_eq "and turn cross-session messaging off, whose socket the sandbox would refuse" false "$(jq -r '.agents.crossSessionMessaging' "$qwen_home/settings.json")"
check_that "the global QWEN.md starts with the preferences" \
  test "$(head -1 "$qwen_home/QWEN.md")" = "$(head -1 "$repo/shared/preferences/PREFERENCES.md")"
check_that "and carries the Qwen rules" grep -qF 'mcp__code-search__semantic_search answers' "$qwen_home/QWEN.md"
check_that "the rendered settings keep QWEN_SYSTEM_MD out of a project .env" \
  jq -e '.advanced.excludedEnvVars | index("QWEN_SYSTEM_MD")' "$qwen_home/settings.json"
check_that "qwen launch asks Qwen Code for its Seatbelt sandbox" grep -qx 'QWEN_SANDBOX=sandbox-exec' "$sandbox/qwen-env"
check_that "and names the repo's profile" grep -qx 'SEATBELT_PROFILE=claude-ollama' "$sandbox/qwen-env"
check_not "and never hands Qwen Code an outer SANDBOX, which would turn its sandbox off" grep -q '^SANDBOX=' "$sandbox/qwen-env"
check_that "qwen launch installs the profile where Qwen Code looks for it" \
  cmp -s "$repo/ollama/qwen-sandbox.sb" "$sandbox/qwen-project/.qwen/sandbox-macos-claude-ollama.sb"
check_that "and keeps it out of the project's git status" grep -qxF '/.qwen/sandbox-macos-claude-ollama.sb' "$sandbox/qwen-project/.git/info/exclude"
check_that "qwen launch says it runs in Seatbelt" grep -qF "qwen runs in macOS Seatbelt (profile claude-ollama)" "$sandbox/err"
check_not "an outer GH_TOKEN never reaches Qwen Code" grep -q '^GH_TOKEN=' "$sandbox/qwen-env"
check_not "an outer SHORTCUT_API_TOKEN never reaches Qwen Code" grep -q '^SHORTCUT_API_TOKEN=' "$sandbox/qwen-env"

run_capture "$qwen_script" launch 35b -p hi
check_that "qwen launch 35b uses the 35b model" grep -qF -- "-m qwen3.6-35b-cc" "$sandbox/out"
check_eq "and its context window" 98304 "$(jq -r '.modelProviders.openai[0].generationConfig.contextWindowSize' "$qwen_home/settings.json")"

CLAUDE_OLLAMA_SANDBOX_EXEC=/nonexistent/sandbox-exec run_capture "$qwen_script" launch 27b -p hi
check_that "qwen launch without sandbox-exec says its commands run as you" grep -qF "qwen runs without a sandbox: its commands run as you (sandbox-exec not found)" "$sandbox/err"
check_not "and sets no QWEN_SANDBOX" grep -q '^QWEN_SANDBOX=' "$sandbox/qwen-env"

mkdir -p "$sandbox/elsewhere"
new_project "$sandbox/qwen-link-project"
ln -s "$sandbox/elsewhere" .qwen
CLAUDE_OLLAMA_SANDBOX_EXEC=/usr/bin/true run_capture "$qwen_script" launch 27b -p hi
check_eq "qwen launch refuses a .qwen that is a symbolic link, which a session could point anywhere" 1 "$?"
check_that "and says so" grep -qF ".qwen is a symbolic link" "$sandbox/err"
check_not "and writes nothing through the link" test -e "$sandbox/elsewhere/sandbox-macos-claude-ollama.sb"
check_not "and never starts qwen" grep -q '^QWEN ARGS:' "$sandbox/out"

new_project "$sandbox/qwen-victim-project"
mkdir -p .qwen
echo keep > "$sandbox/elsewhere/victim"
ln -s "$sandbox/elsewhere/victim" .qwen/sandbox-macos-claude-ollama.sb
CLAUDE_OLLAMA_SANDBOX_EXEC=/usr/bin/true run_capture "$qwen_script" launch 27b -p hi
check_eq "a profile path that is a symbolic link is replaced, never written through" keep "$(cat "$sandbox/elsewhere/victim")"
check_not "and the profile is a plain file afterwards" test -L .qwen/sandbox-macos-claude-ollama.sb
check_that "with the profile's content" cmp -s "$repo/ollama/qwen-sandbox.sb" .qwen/sandbox-macos-claude-ollama.sb

new_project "$sandbox/qwen-exclude-project"
mkdir -p .git/info
rm -f .git/info/exclude && ln -s "$sandbox/elsewhere/victim" .git/info/exclude
CLAUDE_OLLAMA_SANDBOX_EXEC=/usr/bin/true run_capture "$qwen_script" launch 27b -p hi
check_eq "qwen launch refuses a .git/info/exclude that is a symbolic link" 1 "$?"
check_eq "and appends nothing through it" keep "$(cat "$sandbox/elsewhere/victim")"
cd "$return_dir" || exit 1

run_capture "$qwen_script" --print-config 35b
check_eq "qwen print-config exit status" 0 "$?"
check_not "qwen print-config does not launch qwen" grep -q '^QWEN ARGS:' "$sandbox/out"
check_that "qwen print-config names the harness" grep -qxF "harness: qwen" "$sandbox/out"
check_that "qwen print-config shows the model" grep -qxF "model: qwen3.6-35b-cc" "$sandbox/out"
check_that "qwen print-config shows the context window" grep -qxF "context window: 98304" "$sandbox/out"
check_that "qwen print-config shows the server" grep -qxF "server: http://127.0.0.1:11435" "$sandbox/out"
check_that "qwen print-config shows the weights" grep -qxF "weights: $CLAUDE_OLLAMA_WEIGHTS_DIR/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf" "$sandbox/out"
check_that "qwen print-config names the Qwen sandbox" grep -q '^sandbox: ' "$sandbox/out"
check_that "qwen print-config shows the qwen command" grep -q '^command: qwen --auth-type openai ' "$sandbox/out"

. "$repo/shared/testing/stub-llama-lib.sh"
stub_state="$sandbox/stub-state.json"
jq -n '{models_max: 2, models: {"qwen3.8-27b-cc": {}}}' > "$stub_state"
start_stub_llama "$stub_state" || exit 1
trap 'stop_stub_llama; remove_sandboxes' EXIT
run_capture "$qwen_script" doctor 27b
check_eq "qwen doctor exit status" 0 "$?"
check_that "qwen doctor reports qwen on PATH" grep -q '^ok   qwen on PATH' "$sandbox/out"
check_that "qwen doctor reports the server" grep -qxF "ok   llama-server build 11429 on ${LLAMA_SERVER_URL#http://}" "$sandbox/out"
check_that "qwen doctor reports the preset" grep -qxF "ok   preset qwen3.8-27b-cc listed" "$sandbox/out"
check_that "qwen doctor reports the weights" grep -qxF "ok   weights Qwen3.8-27B-UD-Q4_K_XL.gguf (sha256 matches)" "$sandbox/out"
check_that "qwen doctor reports the settings template parses" grep -qxF "ok   qwen settings template parses" "$sandbox/out"
check_that "qwen doctor warns that no hooks are wired" grep -qxF "warn qwen hooks: none wired (docs/ollama.md)" "$sandbox/out"
check_not "qwen doctor skips the Claude hook check" grep -q '^ok   hook ' "$sandbox/out"
check_not "qwen doctor skips the Claude model allowlist check" grep -q 'availableModels' "$sandbox/out"
check_not "qwen doctor never launches qwen" grep -q '^QWEN ARGS:' "$sandbox/out"
check_that "qwen doctor reports the sandbox" grep -q 'qwen sandbox: ' "$sandbox/out"
jq '.health_status = 503' "$stub_state" > "$stub_state.new" && mv "$stub_state.new" "$stub_state"
run_capture "$qwen_script" doctor 27b
check_eq "qwen doctor without a server exit status" 1 "$?"
check_that "qwen doctor fails a server that is not answering" grep -qxF "fail llama-server not answering at $LLAMA_SERVER_URL (claude-custom agent -apply, then claude-ollama logs)" "$sandbox/out"
jq '.health_status = 200' "$stub_state" > "$stub_state.new" && mv "$stub_state.new" "$stub_state"
rm -f "$sandbox/stubbin/qwen"
run_capture "$qwen_script" doctor 27b
check_eq "qwen doctor without qwen exit status" 1 "$?"
check_that "qwen doctor fails a missing qwen" grep -q '^fail qwen missing' "$sandbox/out"

run_capture "$qwen_script" doctor 9b
check_eq "an unknown size exit status" 2 "$?"
check_that "an unknown size names the sizes" grep -qF "claude-ollama-qwen: unknown size '9b' (sizes: " "$sandbox/err"
run_capture "$qwen_script" 27b
check_eq "a missing mode exit status" 2 "$?"
check_that "a missing mode prints the usage" grep -qF "usage: claude-ollama-qwen launch|--print-config|doctor SIZE" "$sandbox/err"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
