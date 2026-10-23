#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
installer="$repo/bin/claude-custom"
failures=0
sandboxes=""
system_tools=""
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

record_installed_num_ctx() {
  local model context
  mkdir -p "$sandbox/num-ctx"
  jq -r 'to_entries[] | "\(.value.model) \(.value.context)"' "$repo/ollama/sizes.json" \
    | while read -r model context; do printf '%s\n' "$context" > "$sandbox/num-ctx/$model"; done
}

pinned_tags() {
  jq '{models: [to_entries[] | {name: .key, digest: .value}]}' "$repo/ollama/model-digests.json"
}

new_sandbox() {
  sandbox="$(cd "$(mktemp -d)" && pwd -P)"
  sandboxes="$sandboxes $sandbox"
  export HOME="$sandbox/home"
  mkdir -p "$HOME" "$sandbox/stubbin"
  unset ZDOTDIR XDG_CONFIG_HOME CLAUDE_CONFIG_DIR STUB_OLLAMA_SHOW_EXIT STUB_OLLAMA_PULL_EXIT
  unset STUB_OLLAMA_PID STUB_OLLAMA_ENV STUB_CURL_EXIT STUB_OLLAMA_NUM_CTX STUB_AGENT_EXIT CMUX_SOCKET_PATH CLAUDE_OLLAMA_CMUX
  export SHELL=/bin/zsh
  record_installed_num_ctx
  export CLAUDE_OLLAMA_MANAGED_SETTINGS="$sandbox/managed-settings.json"
  cat > "$sandbox/stubbin/claude" <<EOF
#!/bin/sh
echo "ARGS: \$*"
echo "\${ANTHROPIC_MODEL-unset}" > "$sandbox/model-env"
echo "\${CLAUDE_CUSTOM_HOME-unset}" > "$sandbox/custom-home-env"
echo "\${CODE_SEARCH_EMBED-unset}" > "$sandbox/embed-env"
echo "\${CLAUDE_CONFIG_DIR-unset}" > "$sandbox/config-dir-env"
echo "\${CLAUDE_CODE_TMPDIR-unset}" > "$sandbox/tmpdir-env"
echo "\${GIT_CONFIG_COUNT-unset} \${GIT_CONFIG_KEY_0-unset} \${GIT_CONFIG_VALUE_0-unset}" > "$sandbox/git-config-env"
env > "$sandbox/claude-env"
EOF
  install_sandbox_runtime_stub
  cat > "$sandbox/stubbin/getconf" <<EOF
#!/bin/sh
[ "\$1" = DARWIN_USER_TEMP_DIR ] && echo "$sandbox/darwin-temp/"
EOF
  chmod +x "$sandbox/stubbin/getconf"
  cat > "$sandbox/stubbin/security" <<'EOF'
#!/bin/sh
[ -n "${STUB_GITHUB_TOKEN:-}" ] || exit 44
printf '%s\n' "$STUB_GITHUB_TOKEN"
EOF
  chmod +x "$sandbox/stubbin/security"
  cat > "$sandbox/stubbin/ollama" <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/ollama.log"
if [ "\$1" = show ]; then
  [ "\$3" = --parameters ] && echo "num_ctx                        \${STUB_OLLAMA_NUM_CTX:-\$(cat "$sandbox/num-ctx/\$2" 2>/dev/null || echo 98304)}"
  exit "\${STUB_OLLAMA_SHOW_EXIT:-0}"
fi
if [ "\$1" = create ]; then sed 's/^/modelfile: /' "\$4" >> "$sandbox/ollama.log"; fi
if [ "\$1" = pull ]; then exit "\${STUB_OLLAMA_PULL_EXIT:-0}"; fi
exit 0
EOF
  cat > "$sandbox/stubbin/curl" <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/curl.log"
case "\$*" in *api/tags*) cat "$sandbox/tags.json" ;; esac
exit "\${STUB_CURL_EXIT:-0}"
EOF
  pinned_tags > "$sandbox/tags.json"
  cat > "$sandbox/stubbin/python3" <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/python.log"
EOF
  cat > "$sandbox/stubbin/ollama-agent" <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/agent.log"
exit "\${STUB_AGENT_EXIT:-0}"
EOF
  export CLAUDE_OLLAMA_AGENT="$sandbox/stubbin/ollama-agent"
  cat > "$sandbox/stubbin/pgrep" <<'EOF'
#!/bin/sh
[ -n "${STUB_OLLAMA_PID:-}" ] && echo "$STUB_OLLAMA_PID"
EOF
  cat > "$sandbox/stubbin/ps" <<'EOF'
#!/bin/sh
echo "ollama serve ${STUB_OLLAMA_ENV:-}"
EOF
  chmod +x "$sandbox/stubbin/claude" "$sandbox/stubbin/ollama" "$sandbox/stubbin/ollama-agent" "$sandbox/stubbin/curl" "$sandbox/stubbin/python3" "$sandbox/stubbin/pgrep" "$sandbox/stubbin/ps"
  link_system_tools
  export PATH="$sandbox/stubbin:$sandbox/sysbin"
}

sandbox_runtime_path() {
  echo "$HOME/.local/share/claude-custom/sandbox-runtime/node_modules/.bin/srt"
}

install_sandbox_runtime_stub() {
  local runtime
  runtime="$(sandbox_runtime_path)"
  mkdir -p "$(dirname "$runtime")"
  cat > "$runtime" <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/srt.log"
[ "\$1" = -s ] && cp "\$2" "$sandbox/policy.json"
shift 2
[ "\$1" = -- ] && shift
exec "\$@"
EOF
  chmod +x "$runtime"
}

link_system_tools() {
  [ -n "$system_tools" ] || build_system_tools
  ln -s "$system_tools" "$sandbox/sysbin"
}

build_system_tools() {
  local entry name
  system_tools="$(cd "$(mktemp -d)" && pwd -P)"
  sandboxes="$sandboxes $system_tools"
  for entry in /usr/bin/* /bin/*; do
    name="${entry##*/}"
    case "$name" in
      go|gofmt) continue ;;
    esac
    if [ -x "$entry" ] && [ ! -e "$system_tools/$name" ]; then
      ln -s "$entry" "$system_tools/$name"
    fi
  done
}

run_capture() {
  "$@" >"$sandbox/out" 2>"$sandbox/err"
}

with_tty() {
  if script -q -c true /dev/null >/dev/null 2>&1; then
    script -q -c "$(printf '%q ' "$@")" /dev/null
  else
    script -q /dev/null "$@"
  fi
}

copy_repo() {
  mkdir -p "$1"
  cp -R "$repo/bin" "$repo/personal" "$repo/shared" "$repo/ollama" "$repo/go" "$1/"
}

new_sandbox
ollama_settings="--settings $repo/ollama/settings.27b.json"
run_capture "$repo/bin/claude-ollama" -p hi
check_that "claude-ollama defaults to 27b" grep -qF -- "$ollama_settings" "$sandbox/out"
check_that "claude-ollama passes claude args through" grep -qF -- "--tools Bash,Read,Edit,Write,Skill -p hi" "$sandbox/out"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama keeps the explicit size form" grep -qF -- "--tools Bash,Read,Edit,Write,Skill -p hi" "$sandbox/out"
check_that "claude-ollama 27b passes the 27b model" grep -qF -- "--model qwen3.8-27b-cc --tools" "$sandbox/out"
ANTHROPIC_MODEL=claude-opus-5-5 run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama 27b ignores ANTHROPIC_MODEL" grep -qF -- "--model qwen3.8-27b-cc --tools" "$sandbox/out"
check_that "claude-ollama unsets ANTHROPIC_MODEL" grep -qxF "unset" "$sandbox/model-env"
check_eq "claude-ollama exports CLAUDE_CUSTOM_HOME to claude" "$repo" "$(cat "$sandbox/custom-home-env")"
run_capture "$repo/bin/claude-ollama" 35b -p hi
check_that "claude-ollama 35b uses the 35b settings" grep -qF -- "--settings $repo/ollama/settings.35b.json" "$sandbox/out"
check_that "claude-ollama 35b passes the 35b model" grep -qF -- "--model qwen3.6-35b-cc --tools" "$sandbox/out"
check_that "claude-ollama 35b uses the shared prompt" grep -qF -- "--append-system-prompt-file $repo/ollama/CLAUDE.local.md" "$sandbox/out"
check_that "claude-ollama replaces the default system prompt" grep -qF -- "--system-prompt-file $repo/ollama/system-prompt.md --append-system-prompt-file $repo/ollama/CLAUDE.local.md" "$sandbox/out"
check_that "claude-ollama 35b passes claude args through" grep -qF -- "--tools Bash,Read,Edit,Write,Skill -p hi" "$sandbox/out"
check_that "claude-ollama warms the main model" grep -q 'localhost:11434/api/generate' "$sandbox/curl.log"
check_that "claude-ollama warm-up names the model" grep -q '"model":"qwen3.6-35b-cc"' "$sandbox/curl.log"
check_that "claude-ollama warm-up sets keep_alive" grep -q '"keep_alive":"30m"' "$sandbox/curl.log"
rm -f "$sandbox/curl.log"
OLLAMA_HOST=http://box:1 run_capture "$repo/bin/claude-ollama" 35b -p hi
check_that "claude-ollama warm-up follows OLLAMA_HOST" grep -q 'box:1/api/generate' "$sandbox/curl.log"
check_not "claude-ollama 35b skips pull when the model exists" grep -sqE '^(pull|create) ' "$sandbox/ollama.log"
check_that "claude-ollama starts the code-search MCP server" grep -qF -- "--strict-mcp-config --mcp-config {\"mcpServers\":{\"code-search\":{\"command\":\"python3\",\"args\":[\"$repo/shared/mcp/code-search.py\"]}}}" "$sandbox/out"
rm -f "$sandbox/python.log"
run_capture "$repo/bin/claude-ollama" 35b -p hi
sleep 1
check_that "claude-ollama starts the indexer" grep -qxF "$repo/shared/mcp/code-search.py --index" "$sandbox/python.log"
check_that "claude-ollama launches without waiting for the indexer" grep -q '^ARGS:' "$sandbox/out"
rm -f "$sandbox/python.log"
run_capture env CLAUDE_OLLAMA_NO_INDEX=1 "$repo/bin/claude-ollama" 35b -p hi
check_not "CLAUDE_OLLAMA_NO_INDEX skips the indexer" test -e "$sandbox/python.log"
new_sandbox
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=2" run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama warms the embedding model when the server keeps two models" grep -q 'localhost:11434/api/embed' "$sandbox/curl.log"
check_that "the embedding warm-up names the model and keeps it alive" grep -q '"model":"qwen3-embedding:0.6b","input":"warm up","keep_alive":"30m"' "$sandbox/curl.log"
check_eq "claude-ollama allows the search server to load embeddings when the server keeps two models" 1 "$(cat "$sandbox/embed-env")"
rm -f "$sandbox/curl.log"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=1" run_capture "$repo/bin/claude-ollama" 27b -p hi
check_not "claude-ollama skips the embedding warm-up when the server keeps one model" grep -q 'api/embed' "$sandbox/curl.log"
check_that "claude-ollama does not allow embeddings when the server keeps one model" grep -qxF unset "$sandbox/embed-env"
rm -f "$sandbox/curl.log"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_not "claude-ollama skips the embedding warm-up when no server is running" grep -q 'api/embed' "$sandbox/curl.log"
new_sandbox
rm -f "$sandbox/stubbin/curl"
OLLAMA_HOST=http://127.0.0.1:9 run_capture "$repo/bin/claude-ollama" 35b -p hi
check_that "claude-ollama launches without curl" grep -q '^ARGS:' "$sandbox/out"
new_sandbox
STUB_OLLAMA_SHOW_EXIT=1 run_capture "$repo/bin/claude-ollama" 35b -p hi
check_that "claude-ollama 35b pulls a missing base model" grep -qxF "pull qwen3.6:35b-mlx" "$sandbox/ollama.log"
check_that "claude-ollama 35b creates the missing model" grep -qxF "create qwen3.6-35b-cc -f $repo/ollama/Modelfile.35b" "$sandbox/ollama.log"
check_that "claude-ollama 35b launches after pulling" grep -qF -- "--model qwen3.6-35b-cc --tools" "$sandbox/out"
settings_arg() { sed -n 's/^ARGS: --settings \([^ ]*\).*/\1/p' "$sandbox/out"; }
check_eq "claude-ollama always passes the profile itself" "$repo/ollama/settings.35b.json" "$(settings_arg)"
check_not "claude-ollama never creates a side model" grep -q '^create qwen3-4b-cc' "$sandbox/ollama.log"
check_that "claude-ollama pulls a missing embedding model" grep -qxF "pull qwen3-embedding:0.6b" "$sandbox/ollama.log"
rm -f "$sandbox/ollama.log"
CODE_SEARCH_MODEL=nomic-embed-text STUB_OLLAMA_SHOW_EXIT=1 run_capture "$repo/bin/claude-ollama" 35b -p hi
check_that "claude-ollama pulls the CODE_SEARCH_MODEL override" grep -qxF "pull nomic-embed-text" "$sandbox/ollama.log"
rm -f "$sandbox/ollama.log"
STUB_OLLAMA_SHOW_EXIT=1 STUB_OLLAMA_PULL_EXIT=1 run_capture "$repo/bin/claude-ollama" 35b -p hi
check_eq "claude-ollama 35b failed pull exit status" 1 "$?"
check_not "claude-ollama 35b failed pull does not create" grep -sq '^create ' "$sandbox/ollama.log"
check_not "claude-ollama 35b failed pull does not launch claude" grep -q '^ARGS:' "$sandbox/out"
rm -f "$sandbox/ollama.log"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_not "claude-ollama 27b skips pull when the model exists" grep -sqE '^(pull|create) ' "$sandbox/ollama.log"
STUB_OLLAMA_SHOW_EXIT=1 run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama 27b pulls a missing base model" grep -qxF "pull qwen3.8:27b-mlx" "$sandbox/ollama.log"
check_that "claude-ollama 27b creates the missing model" grep -qxF "create qwen3.8-27b-cc -f $repo/ollama/Modelfile.27b" "$sandbox/ollama.log"
check_that "claude-ollama 27b launches after pulling" grep -qF -- "--model qwen3.8-27b-cc --tools" "$sandbox/out"
rm -f "$sandbox/ollama.log"
STUB_OLLAMA_SHOW_EXIT=1 STUB_OLLAMA_PULL_EXIT=1 run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "claude-ollama 27b failed pull exit status" 1 "$?"
check_not "claude-ollama 27b failed pull does not create" grep -sq '^create ' "$sandbox/ollama.log"
check_not "claude-ollama 27b failed pull does not launch claude" grep -q '^ARGS:' "$sandbox/out"
new_sandbox
STUB_OLLAMA_NUM_CTX=16384 run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama recreates a model with a stale num_ctx" grep -qE '^create qwen3.8-27b-cc -f ' "$sandbox/ollama.log"
check_that "the recreated model builds on the installed one" grep -qxF "modelfile: FROM qwen3.8-27b-cc" "$sandbox/ollama.log"
check_that "the recreated model gets the profile num_ctx" grep -qxF "modelfile: PARAMETER num_ctx 65536" "$sandbox/ollama.log"
check_not "a stale num_ctx does not pull the base model" grep -q '^pull ' "$sandbox/ollama.log"
check_that "claude-ollama says it recreates the model" grep -qF "recreating qwen3.8-27b-cc with num_ctx 65536" "$sandbox/err"
check_that "claude-ollama launches after recreating" grep -qF -- "--model qwen3.8-27b-cc --tools" "$sandbox/out"

new_sandbox
jq '.models[0].digest = "0000"' "$sandbox/tags.json" > "$sandbox/tags.new" && mv "$sandbox/tags.new" "$sandbox/tags.json"
STUB_OLLAMA_SHOW_EXIT=1 run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "claude-ollama exits when a pulled base misses its pin" 1 "$?"
check_that "claude-ollama names the base that misses its pin" grep -qF "qwen3.8:27b-mlx has digest 0000" "$sandbox/err"
check_not "claude-ollama does not create from a base that misses its pin" grep -sq '^create ' "$sandbox/ollama.log"
check_not "claude-ollama does not launch with a base that misses its pin" grep -q '^ARGS:' "$sandbox/out"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "claude-ollama exits when an installed base misses its pin" 1 "$?"
check_not "claude-ollama does not launch with an installed base that misses its pin" grep -q '^ARGS:' "$sandbox/out"
new_sandbox
jq '.models |= map(if .name == "qwen3-embedding:0.6b" then .digest = "0000" else . end)' "$sandbox/tags.json" > "$sandbox/tags.new" && mv "$sandbox/tags.new" "$sandbox/tags.json"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "claude-ollama exits when the embedding model misses its pin" 1 "$?"
check_that "claude-ollama names the embedding model that misses its pin" grep -qF "qwen3-embedding:0.6b has digest 0000" "$sandbox/err"
new_sandbox
jq '.models |= map(select(.name != "qwen3-embedding:0.6b"))' "$sandbox/tags.json" > "$sandbox/tags.new" && mv "$sandbox/tags.new" "$sandbox/tags.json"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama launches when a pinned model is not installed" grep -q '^ARGS:' "$sandbox/out"
STUB_OLLAMA_SHOW_EXIT=1 run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama creates from a base that matches its pin" grep -qxF "create qwen3.8-27b-cc -f $repo/ollama/Modelfile.27b" "$sandbox/ollama.log"

new_sandbox
run_capture "$repo/bin/claude-ollama" --help
check_eq "claude-ollama help exit status" 0 "$?"
check_that "claude-ollama help lists sizes" grep -qxF "sizes: 27b 35b-coding 35b" "$sandbox/out"
check_not "claude-ollama help does not launch claude" grep -q '^ARGS:' "$sandbox/out"
run_capture "$repo/bin/claude-ollama" 28b -p hi </dev/null
check_that "claude-ollama unknown size without a tty falls back to 27b" grep -qF -- "$ollama_settings" "$sandbox/out"
check_not "claude-ollama drops an unknown size" grep -qF "28b" "$sandbox/out"
check_that "claude-ollama unknown size keeps claude args" grep -qF -- "Skill -p hi" "$sandbox/out"

new_sandbox
copy_repo "$sandbox/repo"
cp "$sandbox/repo/ollama/settings.27b.json" "$sandbox/repo/ollama/settings.9b.json"
cp "$sandbox/repo/ollama/Modelfile.27b" "$sandbox/repo/ollama/Modelfile.9b"
jq '. + {"9b": .["27b"]}' "$sandbox/repo/ollama/sizes.json" > "$sandbox/sizes.json" && mv "$sandbox/sizes.json" "$sandbox/repo/ollama/sizes.json"
cp "$sandbox/repo/ollama/settings.27b.json" "$sandbox/repo/ollama/settings.70b.json"
run_capture "$sandbox/repo/bin/claude-ollama" 9b -p hi
check_that "claude-ollama accepts a newly configured size" grep -qF -- "--settings $sandbox/repo/ollama/settings.9b.json" "$sandbox/out"
check_not "claude-ollama does not pass a configured size to claude" grep -qF -- "Write 9b" "$sandbox/out"
run_capture "$sandbox/repo/bin/claude-ollama" --help
check_that "claude-ollama help lists sizes from config" grep -qxF "sizes: 27b 35b-coding 35b 9b" "$sandbox/out"

cat > "$sandbox/stubbin/go" <<'STUB'
#!/bin/sh
printf '#!/bin/sh\necho 35b\n' > "$3"
chmod +x "$3"
STUB
chmod +x "$sandbox/stubbin/go"
with_tty "$sandbox/repo/bin/claude-ollama" -p hi >"$sandbox/out" 2>&1 </dev/null
check_that "claude-ollama with a tty and no size launches the picked size" grep -qF -- "--settings $sandbox/repo/ollama/settings.35b.json" "$sandbox/out"
with_tty "$sandbox/repo/bin/claude-ollama" 28b >"$sandbox/out" 2>&1 </dev/null
check_that "claude-ollama with a tty and an unknown size launches the picked size" grep -qF -- "--settings $sandbox/repo/ollama/settings.35b.json" "$sandbox/out"
cat > "$sandbox/stubbin/go" <<'STUB'
#!/bin/sh
printf '#!/bin/sh\nexit 1\n' > "$3"
chmod +x "$3"
STUB
rm -f "$sandbox/repo/go/cmd/model-picker/model-picker"
with_tty "$sandbox/repo/bin/claude-ollama" >"$sandbox/out" 2>&1 </dev/null
check_not "claude-ollama cancelled picker does not launch claude" grep -q 'ARGS:' "$sandbox/out"
run_capture "$installer" ollama -p hi
check_that "claude-custom ollama runs claude-ollama" grep -qF -- "$ollama_settings" "$sandbox/out"

new_sandbox
copy_repo "$sandbox/repo"
rm -f "$sandbox/repo/go/cmd/claude-tools/claude-tools"
run_capture "$sandbox/repo/bin/claude-tools" local
check_eq "claude-tools without go exit status" 1 "$?"
check_that "claude-tools without go message" grep -qF "claude-tools: needs Go 1.26+" "$sandbox/err"
run_capture "$sandbox/repo/bin/claude-custom" tools
check_that "claude-custom tools runs claude-tools" grep -qF "claude-tools: needs Go 1.26+" "$sandbox/err"
rm -f "$sandbox/repo/go/cmd/ollama-agent/ollama-agent"
run_capture "$sandbox/repo/bin/ollama-agent"
check_eq "ollama-agent without go exit status" 1 "$?"
check_that "ollama-agent without go message" grep -qF "ollama-agent: needs Go 1.26+" "$sandbox/err"
run_capture "$sandbox/repo/bin/claude-custom" agent
check_that "claude-custom agent runs ollama-agent" grep -qF "ollama-agent: needs Go 1.26+" "$sandbox/err"
run_capture "$installer" bogus
check_eq "unknown subcommand exit status" 2 "$?"
check_that "usage lists the new subcommands" grep -qF "install|update|uninstall|ollama|tools|agent" "$sandbox/err"

new_sandbox
run_capture "$repo/bin/claude-ollama" --print-config 35b
check_eq "print-config exit status" 0 "$?"
check_not "print-config does not launch claude" grep -q '^ARGS:' "$sandbox/out"
check_not "print-config does not pull or create" grep -sqE '^(pull|create) ' "$sandbox/ollama.log"
check_that "print-config shows the size" grep -qxF "size: 35b" "$sandbox/out"
check_that "print-config shows the model" grep -qxF "model: qwen3.6-35b-cc" "$sandbox/out"
check_that "print-config shows the base model" grep -qxF "base: qwen3.6:35b-mlx" "$sandbox/out"
check_not "print-config has no side model" grep -q "^side model:" "$sandbox/out"
check_that "print-config shows the embedding model" grep -qxF "embedding model: qwen3-embedding:0.6b" "$sandbox/out"
check_that "print-config shows num_ctx" grep -qxF "num_ctx: 98304" "$sandbox/out"
check_that "print-config shows context tokens" grep -qxF "max context tokens: 98304" "$sandbox/out"
check_that "print-config shows the settings path" grep -qxF "settings: $repo/ollama/settings.35b.json" "$sandbox/out"
check_that "print-config shows the tools, Skill included so your skills load" grep -qxF "tools: Bash,Read,Edit,Write,Skill" "$sandbox/out"
check_that "print-config shows the sandboxed command" \
  grep -qF "command: $HOME/.local/share/claude-custom/sandbox-runtime/node_modules/.bin/srt -s $HOME/.claude-ollama/sandbox-policy.json -- $repo/ollama/sandbox-entry claude --settings " "$sandbox/out"
run_capture "$repo/bin/claude-ollama" --print-config </dev/null
check_that "print-config without a size uses the default" grep -qxF "size: 27b" "$sandbox/out"

cat > "$sandbox/stubbin/tail" <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/tail.log"
EOF
chmod +x "$sandbox/stubbin/tail"
HOMEBREW_PREFIX="$sandbox/brew" run_capture "$repo/bin/claude-ollama" logs
check_eq "logs without a log file exits 1" 1 "$?"
check_that "logs without a log file says so" grep -q 'no Ollama log found' "$sandbox/err"
mkdir -p "$HOME/.ollama/logs"
: > "$HOME/.ollama/logs/server.log"
HOMEBREW_PREFIX="$sandbox/brew" run_capture "$repo/bin/claude-ollama" logs
check_eq "logs exit status" 0 "$?"
check_that "logs follows the app log when nothing else exists" grep -qxF -- "-n 50 -F $HOME/.ollama/logs/server.log" "$sandbox/tail.log"
check_that "logs names the file it follows" grep -qxF "claude-ollama: following $HOME/.ollama/logs/server.log" "$sandbox/err"
check_not "logs does not launch claude" grep -q '^ARGS:' "$sandbox/out"
mkdir -p "$sandbox/brew/var/log"
: > "$sandbox/brew/var/log/ollama.log"
rm -f "$sandbox/tail.log"
HOMEBREW_PREFIX="$sandbox/brew" run_capture "$repo/bin/claude-ollama" logs -n 200
check_that "logs prefers the Homebrew service log and passes the line count" grep -qxF -- "-n 200 -F $sandbox/brew/var/log/ollama.log" "$sandbox/tail.log"
mkdir -p "$HOME/Library/LaunchAgents"
printf '<plist><dict>\n  <key>Label</key><string>local.ollama</string>\n  <key>StandardOutPath</key><string>%s</string>\n  <key>StandardErrorPath</key><string>%s</string>\n</dict></plist>\n' "$sandbox/agent-ollama.log" "$sandbox/agent-ollama.log" > "$HOME/Library/LaunchAgents/local.ollama.plist"
: > "$sandbox/agent-ollama.log"
rm -f "$sandbox/tail.log"
HOMEBREW_PREFIX="$sandbox/brew" run_capture "$repo/bin/claude-ollama" logs
check_that "logs prefers the LaunchAgent log" grep -qxF -- "-n 50 -F $sandbox/agent-ollama.log" "$sandbox/tail.log"
new_sandbox
cat > "$sandbox/stubbin/pr-review-local" <<EOF
#!/bin/sh
echo "REVIEW: \$*"
EOF
chmod +x "$sandbox/stubbin/pr-review-local"
export CLAUDE_OLLAMA_REVIEWER="$sandbox/stubbin/pr-review-local"
run_capture "$repo/bin/claude-ollama" review
check_eq "review without a target exits 2" 2 "$?"
check_that "review without a target says so" grep -q 'pull request number, URL or branch is required' "$sandbox/err"
run_capture "$repo/bin/claude-ollama" review 27b 123 </dev/null
check_eq "review exit status" 0 "$?"
check_that "review runs the reviewer with the size's model and server" \
  grep -qxF "REVIEW: --model qwen3.8-27b-cc --base-url http://localhost:11434 123" "$sandbox/out"
warm_up_logged() {
  for _ in $(seq 50); do
    grep -q 'api/generate' "$sandbox/curl.log" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}
check_that "review warms the model" warm_up_logged
check_not "review does not launch claude" grep -q '^ARGS:' "$sandbox/out"
run_capture "$repo/bin/claude-ollama" review 27b --post 45 </dev/null
check_that "review passes its own flags before the target" \
  grep -qxF "REVIEW: --model qwen3.8-27b-cc --base-url http://localhost:11434 --post 45" "$sandbox/out"
run_capture "$repo/bin/claude-ollama" review 9 </dev/null
check_that "review without a size uses the default" grep -q 'REVIEW: --model qwen3.8-27b-cc ' "$sandbox/out"
unset CLAUDE_OLLAMA_REVIEWER
run_capture "$repo/bin/claude-ollama" --help
check_that "claude-ollama help lists logs" grep -q '^logs \[-n LINES\]' "$sandbox/out"

new_sandbox
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=2" run_capture "$repo/bin/claude-ollama" doctor 27b
check_eq "doctor healthy exit status" 0 "$?"
check_that "doctor reports jq" grep -qxF "ok   jq on PATH" "$sandbox/out"
check_that "doctor reports the main model" grep -qxF "ok   model qwen3.8-27b-cc" "$sandbox/out"
check_not "doctor no longer checks a side model" grep -q "side model" "$sandbox/out"
check_that "doctor reports the embedding model" grep -qxF "ok   embedding model qwen3-embedding:0.6b" "$sandbox/out"
check_that "doctor reports context sizes agree" grep -qxF "ok   num_ctx 65536 matches CLAUDE_CODE_MAX_CONTEXT_TOKENS" "$sandbox/out"
check_that "doctor reports hooks" grep -qxF "ok   hook stop-verify.py present" "$sandbox/out"
check_that "doctor reports reachability" grep -qxF "ok   ollama reachable at http://localhost:11434" "$sandbox/out"
check_that "doctor reports server env" grep -qxF "ok   server env OLLAMA_KV_CACHE_TYPE=q8_0" "$sandbox/out"
check_that "doctor reports no managed model allowlist" grep -qxF "ok   no managed availableModels restricts qwen3.8-27b-cc" "$sandbox/out"
check_not "doctor does not launch claude" grep -q '^ARGS:' "$sandbox/out"
check_that "doctor reports a base that matches its pin" grep -qxF "ok   digest qwen3.8:27b-mlx matches its pin" "$sandbox/out"
jq '.models[0].digest = "0000"' "$sandbox/tags.json" > "$sandbox/tags.new" && mv "$sandbox/tags.new" "$sandbox/tags.json"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=2" run_capture "$repo/bin/claude-ollama" doctor 27b
check_eq "doctor with a base that misses its pin exit status" 1 "$?"
check_that "doctor fails a base that misses its pin" grep -qF "fail digest qwen3.8:27b-mlx is 0000, not the pinned" "$sandbox/out"
pinned_tags > "$sandbox/tags.json"
check_not "doctor does not pull or create" grep -sqE '^(pull|create) ' "$sandbox/ollama.log"

new_sandbox
STUB_OLLAMA_SHOW_EXIT=1 STUB_OLLAMA_PID=42 run_capture "$repo/bin/claude-ollama" doctor 27b
check_eq "doctor with missing models exit status" 1 "$?"
check_that "doctor fails the main model" grep -qxF "fail model qwen3.8-27b-cc missing (run claude-ollama 27b to pull and create it)" "$sandbox/out"
check_that "doctor fails the embedding model" grep -qxF "fail embedding model qwen3-embedding:0.6b missing (pick 'Set up embedding model' in claude-ollama)" "$sandbox/out"
check_that "doctor fails server env" grep -qxF "fail server env OLLAMA_FLASH_ATTENTION=1 not set on the running server" "$sandbox/out"

new_sandbox
copy_repo "$sandbox/repo"
sed 's/num_ctx 65536/num_ctx 32768/' "$sandbox/repo/ollama/Modelfile.27b" > "$sandbox/Modelfile.27b"
mv "$sandbox/Modelfile.27b" "$sandbox/repo/ollama/Modelfile.27b"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=2" run_capture "$sandbox/repo/bin/claude-ollama" doctor 27b
check_eq "doctor with mismatched context sizes exit status" 1 "$?"
check_that "doctor fails mismatched context sizes" grep -qxF "fail num_ctx 32768 differs from CLAUDE_CODE_MAX_CONTEXT_TOKENS 65536" "$sandbox/out"

new_sandbox
copy_repo "$sandbox/repo"
rm "$sandbox/repo/shared/hooks/edit-check.py"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=2" run_capture "$sandbox/repo/bin/claude-ollama" doctor 27b
check_eq "doctor with a missing hook exit status" 1 "$?"
check_that "doctor fails a missing hook" grep -qxF "fail hook edit-check.py missing or not executable in shared/hooks" "$sandbox/out"

new_sandbox
echo '{"availableModels":["qwen3.8-27b-cc","opus"]}' > "$CLAUDE_OLLAMA_MANAGED_SETTINGS"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=2" run_capture "$repo/bin/claude-ollama" doctor 27b
check_eq "doctor with the model in the managed allowlist exit status" 0 "$?"
check_that "doctor reports the managed allowlist allows the model" grep -qxF "ok   managed availableModels allows qwen3.8-27b-cc" "$sandbox/out"

new_sandbox
echo '{"availableModels":["opus"]}' > "$CLAUDE_OLLAMA_MANAGED_SETTINGS"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=2" run_capture "$repo/bin/claude-ollama" doctor 27b
check_eq "doctor with the model missing from the managed allowlist exits 0" 0 "$?"
check_that "doctor warns the managed allowlist lacks the model" grep -qxF "warn managed availableModels lacks qwen3.8-27b-cc (ask your admin to add it; Claude Code substitutes a [1m] variant)" "$sandbox/out"

new_sandbox
STUB_CURL_EXIT=7 run_capture "$repo/bin/claude-ollama" doctor 27b
check_eq "doctor with no server exit status" 1 "$?"
check_that "doctor fails when the server is unreachable" grep -qxF "fail ollama not reachable at http://localhost:11434 (brew services start ollama)" "$sandbox/out"
check_that "doctor fails when no server process runs" grep -qxF "fail ollama server not running (brew services start ollama)" "$sandbox/out"

new_sandbox
nojq="$sandbox/nojq"
mkdir -p "$nojq"
for tool in /usr/bin/* /bin/*; do
  [ "${tool##*/}" = jq ] || ln -sf "$tool" "$nojq/"
done
PATH="$sandbox/stubbin:$nojq" run_capture "$repo/bin/claude-ollama" doctor 27b
check_eq "doctor without jq exit status" 1 "$?"
check_that "doctor without jq says jq is required" grep -qxF "claude-ollama: jq is required (brew install jq)" "$sandbox/err"
check_not "doctor without jq does not launch claude" grep -q '^ARGS:' "$sandbox/out"

full_server_env="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=2"
new_sandbox
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$full_server_env" run_capture "$repo/bin/claude-ollama" 27b -p hi
check_not "a server with every server.env value is left alone" test -e "$sandbox/agent.log"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_KEEP_ALIVE=30m" run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "a server missing server.env values gets them applied" grep -qxF -- "-apply" "$sandbox/agent.log"
check_that "claude-ollama says it applies server.env" grep -qF "applying them" "$sandbox/err"
check_that "claude-ollama launches after applying server.env" grep -qF -- "--model qwen3.8-27b-cc --tools" "$sandbox/out"
rm -f "$sandbox/agent.log"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "a stopped server gets server.env applied" grep -qxF -- "-apply" "$sandbox/agent.log"
STUB_AGENT_EXIT=1 STUB_OLLAMA_PID=42 run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "a failed apply says how to fix it" grep -qF "claude-custom agent" "$sandbox/err"
check_that "claude-ollama still launches after a failed apply" grep -qF -- "--model qwen3.8-27b-cc --tools" "$sandbox/out"
rm -f "$sandbox/agent.log"
STUB_OLLAMA_PID=42 run_capture "$repo/bin/claude-ollama" doctor 27b
check_that "doctor names the fix for missing server env" grep -qF "claude-custom agent -apply" "$sandbox/out"
check_not "doctor does not apply server.env" grep -sqxF -- "-apply" "$sandbox/agent.log"

export PNPM_LOG="$sandbox/pnpm.log"
export PR_REVIEW_LOG_DIR="$sandbox/reviews"
web="$sandbox/web"
mkdir -p "$web/src"
printf '{}\n' > "$web/package.json"
: > "$web/pnpm-lock.yaml"
: > "$web/src/page.tsx"
touch -t 202001010200 "$web/src" "$web/src/page.tsx" "$web/package.json" "$web/pnpm-lock.yaml"
cat > "$sandbox/stubbin/pnpm" <<'EOF'
#!/bin/sh
echo "PNPM: $*" >> "$PNPM_LOG"
case "$3" in
  build) mkdir -p "$2/.next" && touch "$2/.next/BUILD_ID" ;;
  install) mkdir -p "$2/node_modules" ;;
  exec)
    cat "$PR_REVIEW_LOG_DIR/.web-url" >> "$PNPM_LOG" 2>/dev/null || true
    ls -l "$PR_REVIEW_LOG_DIR/.web-url" 2>/dev/null | cut -c1-10 >> "$PNPM_LOG"
    echo "TOKEN: ${PR_REVIEW_TOKEN:-unset}" >> "$PNPM_LOG"
    ;;
esac
EOF
chmod +x "$sandbox/stubbin/pnpm"
export CLAUDE_OLLAMA_WEB_DIR="$web"
rm -f "$PNPM_LOG"
run_capture "$repo/bin/claude-ollama" reviews --port 9000
check_eq "reviews exit status" 0 "$?"
check_that "reviews installs when node_modules is missing" grep -qxF -- "PNPM: --dir $web install --frozen-lockfile" "$PNPM_LOG"
check_that "reviews builds when BUILD_ID is missing" grep -qxF -- "PNPM: --dir $web build" "$PNPM_LOG"
check_that "reviews serves on loopback at the port" grep -qxF -- "PNPM: --dir $web exec next start -H 127.0.0.1 -p 9000" "$PNPM_LOG"
token="$(sed -n 's#^http://127\.0\.0\.1:9000/?token=##p' "$PNPM_LOG")"
check_that "reviews writes a tokened .web-url while serving" grep -qxE 'http://127\.0\.0\.1:9000/\?token=[0-9a-f]{48}' "$PNPM_LOG"
check_that "reviews gives the server the token in .web-url" grep -qxF "TOKEN: $token" "$PNPM_LOG"
check_that ".web-url is owner-only while serving" grep -qxF -- "-rw-------" "$PNPM_LOG"
check_that "reviews prints its tokened URL" grep -qxF "claude-ollama: reviews at http://127.0.0.1:9000/?token=$token" "$sandbox/out"
check_not "reviews removes .web-url after it exits" test -e "$PR_REVIEW_LOG_DIR/.web-url"
rm -f "$PNPM_LOG"
run_capture "$repo/bin/claude-ollama" reviews --port 9000
check_not "each reviews launch gets a new token" grep -qxF "http://127.0.0.1:9000/?token=$token" "$PNPM_LOG"
check_not "reviews does not launch claude" grep -q '^ARGS:' "$sandbox/out"
rm -f "$PNPM_LOG"
mkdir -p "$web/.next"
touch -t 202001010100 "$web/.next/BUILD_ID"
run_capture "$repo/bin/claude-ollama" reviews
check_that "reviews rebuilds when a source is newer than BUILD_ID" grep -qxF -- "PNPM: --dir $web build" "$PNPM_LOG"
rm -f "$PNPM_LOG"
touch -t 202001010300 "$web/.next/BUILD_ID"
run_capture "$repo/bin/claude-ollama" reviews
check_not "reviews skips the build when BUILD_ID is newer than every source" grep -qxF -- "PNPM: --dir $web build" "$PNPM_LOG"
check_not "reviews skips the install when node_modules exists" grep -qxF -- "PNPM: --dir $web install --frozen-lockfile" "$PNPM_LOG"
rm -f "$sandbox/stubbin/pnpm"
run_capture "$repo/bin/claude-ollama" reviews
check_eq "reviews without pnpm exits 1" 1 "$?"
check_that "reviews without pnpm says how to install it" grep -qxF "claude-ollama: pnpm is required for the reviews page (brew install pnpm)" "$sandbox/err"
unset CLAUDE_OLLAMA_WEB_DIR PR_REVIEW_LOG_DIR PNPM_LOG
run_capture "$repo/bin/claude-ollama" --help
check_that "claude-ollama help lists reviews" grep -qF -- "reviews [--port N]: serve live and past reviews at http://127.0.0.1:8765/" "$sandbox/out"

policy_lists() {
  jq -e --arg entry "$2" ".filesystem.$1 | index(\$entry) != null" "$sandbox/policy.json" >/dev/null
}

new_sandbox
session_config="$HOME/.claude-ollama"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama runs claude inside sandbox-runtime" \
  grep -qF -- "-s $session_config/sandbox-policy.json -- $repo/ollama/sandbox-entry claude --settings" "$sandbox/srt.log"
check_that "claude-ollama still passes claude args through the sandbox" grep -qF -- "--tools Bash,Read,Edit,Write,Skill -p hi" "$sandbox/out"
check_that "the sandbox lets the session write the project" policy_lists allowWrite .
check_that "the sandbox never writes claude-custom" policy_lists denyWrite "$repo"
check_that "the sandbox never rewrites its own policy" policy_lists denyWrite "$session_config/sandbox-policy.json"
home_in_policy='~'
check_that "the sandbox hides SSH keys" policy_lists denyRead "$home_in_policy/.ssh"
check_that "the sandbox hides the normal Claude config" policy_lists denyRead "$home_in_policy/.claude"
check_eq "claude-ollama gives the session its own Claude config" "$session_config" "$(cat "$sandbox/config-dir-env")"
check_eq "a new session config skips first-run setup" true "$(jq -r .hasCompletedOnboarding "$session_config/.claude.json")"
check_eq "the session keeps its temp files in its own config" "$session_config/tmp" "$(cat "$sandbox/tmpdir-env")"
check_that "the session temp folder exists" test -d "$session_config/tmp"
check_not "the sandbox never writes the shared /private/tmp" policy_lists allowWrite /private/tmp
check_eq "the sandbox writes only the project, the session config and the macOS item-replacement folder" \
  "[\".\",\"$session_config\",\"$sandbox/darwin-temp/TemporaryItems\"]" "$(jq -c '[.filesystem.allowWrite[] | select(endswith("/.git") | not)]' "$sandbox/policy.json")"
session_env() {
  grep -x "$1=.*" "$sandbox/claude-env" | cut -d= -f2-
}
check_eq "the session's temp dir is its own" "$session_config/tmp" "$(session_env TMPDIR)"
for variable in XDG_CACHE_HOME XDG_STATE_HOME XDG_DATA_HOME npm_config_cache GOCACHE GOMODCACHE EDIT_CHECK_CACHE_DIR STOP_VERIFY_STATE_DIR; do
  check_that "the session keeps $variable inside its own config" test "$(session_env "$variable" | cut -c1-${#session_config})" = "$session_config"
done
check_eq "the session never auto-updates the shared Claude Code install" 1 "$(session_env DISABLE_AUTOUPDATER)"
check_eq "outside cmux the sandbox allows no Unix sockets" null "$(jq -c .network.allowUnixSockets "$sandbox/policy.json")"
cmux_socket="$sandbox/cmux.sock"
/usr/bin/python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$cmux_socket"
run_capture env CMUX_SOCKET_PATH="$cmux_socket" "$repo/bin/claude-ollama" 27b -p hi
check_eq "inside cmux the sandbox allows no Unix sockets unless asked" null "$(jq -c .network.allowUnixSockets "$sandbox/policy.json")"
run_capture env CLAUDE_OLLAMA_CMUX=1 CMUX_SOCKET_PATH="$cmux_socket" "$repo/bin/claude-ollama" 27b -p hi
check_eq "CLAUDE_OLLAMA_CMUX=1 allows only the cmux socket" "[\"$cmux_socket\"]" "$(jq -c .network.allowUnixSockets "$sandbox/policy.json")"
run_capture env CLAUDE_OLLAMA_CMUX=1 CMUX_SOCKET_PATH="$sandbox/not-a-socket" "$repo/bin/claude-ollama" 27b -p hi
check_eq "CLAUDE_OLLAMA_CMUX=1 ignores a path that is not a socket" null "$(jq -c .network.allowUnixSockets "$sandbox/policy.json")"
run_capture env CLAUDE_OLLAMA_CMUX=1 CMUX_SOCKET_PATH="cmux.sock" "$repo/bin/claude-ollama" 27b -p hi
check_eq "CLAUDE_OLLAMA_CMUX=1 ignores a relative socket path" null "$(jq -c .network.allowUnixSockets "$sandbox/policy.json")"
check_eq "without a GitHub token git gets no auth header" "unset unset unset" "$(cat "$sandbox/git-config-env")"
check_not "without a terminal claude-ollama leaves the terminal mode alone" test -e "$sandbox/stty.log"
if [ "$(uname)" = Darwin ]; then
  cat > "$sandbox/stubbin/stty" <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/stty.log"
[ "\$1" = -g ] && echo saved-mode
exit 0
EOF
  chmod +x "$sandbox/stubbin/stty"
  /bin/sleep 3 | /usr/bin/script -q /dev/null "$repo/bin/claude-ollama" 27b -p hi >/dev/null 2>&1
  check_eq "on a terminal claude-ollama sets raw mode for the sandbox, which cannot, and restores it after" \
    "-g|-brkint -icrnl -inpck -istrip -ixon cs8 -echo -icanon -iexten -isig min 1 time 0|saved-mode" \
    "$(paste -sd'|' "$sandbox/stty.log")"
  rm -f "$sandbox/stubbin/stty"
fi

mkdir -p "$HOME/.claude"
echo "@preferences" > "$HOME/.claude/CLAUDE.md"
echo '{"hasCompletedOnboarding":true,"theme":"light"}' > "$session_config/.claude.json"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "the session reads a copy of your CLAUDE.md" "@preferences" "$(cat "$session_config/CLAUDE.md")"
check_that "the sandbox never rewrites that copy" policy_lists denyWrite "$session_config/CLAUDE.md"
check_eq "an existing session config is kept" light "$(jq -r .theme "$session_config/.claude.json")"
check_not "without your skills the session gets none" test -e "$session_config/skills"

mkdir -p "$HOME/.claude/skills/tidy" "$sandbox/linked-skill"
echo "tidy skill" > "$HOME/.claude/skills/tidy/SKILL.md"
echo "linked skill" > "$sandbox/linked-skill/SKILL.md"
ln -s "$sandbox/linked-skill" "$HOME/.claude/skills/linked"
mkdir -p "$session_config/skills/retired"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "the session gets a copy of your skills" "tidy skill" "$(cat "$session_config/skills/tidy/SKILL.md")"
check_eq "a symlinked skill is copied as files, since the sandbox cannot read ~/.claude" "linked skill" \
  "$(cat "$session_config/skills/linked/SKILL.md")"
check_not "the copy is a plain folder, not a link" test -L "$session_config/skills/linked"
check_not "a skill you removed is gone from the copy" test -e "$session_config/skills/retired"
check_that "the sandbox never rewrites the skills copy" policy_lists denyWrite "$session_config/skills"
for source in settings.json settings.local.json commands agents plugins rules output-styles keybindings.json .config.json; do
  check_that "the session never writes its own $source, which could pre-approve tools" policy_lists denyWrite "$session_config/$source"
done

jq '.projects = {"/some/project": {"allowedTools": ["Bash"], "hasTrustDialogAccepted": true, "mcpServers": {"planted": {}}, "enabledMcpjsonServers": ["planted"]}}
  | .mcpServers = {"planted": {}} | .bypassPermissionsModeAccepted = true | .customApiKeyResponses = {"approved": ["planted"]}' \
  "$session_config/.claude.json" > "$sandbox/claude.json.new" && mv "$sandbox/claude.json.new" "$session_config/.claude.json"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "each launch rebuilds .claude.json from known-safe keys only, without trust for other folders" \
  '{"hasCompletedOnboarding":true,"theme":"light"}' "$(jq -c . "$session_config/.claude.json")"
launch_root="$(git rev-parse --show-toplevel)"
jq --arg root "$launch_root" '.projects = {($root): {"hasTrustDialogAccepted": true, "allowedTools": ["Bash"]}, "/some/project": {"hasTrustDialogAccepted": true}}' \
  "$session_config/.claude.json" > "$sandbox/claude.json.new" && mv "$sandbox/claude.json.new" "$session_config/.claude.json"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "trust survives only for the folder being launched, so a session cannot pre-trust another repo" \
  "{\"$launch_root\":{\"hasTrustDialogAccepted\":true}}" "$(jq -c .projects "$session_config/.claude.json")"

echo '{"keep": "me"}' > "$sandbox/outside-target.json"
rm "$session_config/.claude.json"
ln -s "$sandbox/outside-target.json" "$session_config/.claude.json"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "the launcher never writes through a .claude.json symlink the session planted" '{"keep": "me"}' "$(cat "$sandbox/outside-target.json")"
check_not "and replaces the symlink with a plain file" test -L "$session_config/.claude.json"
check_eq "a replaced .claude.json starts from first-run state" true "$(jq -r .hasCompletedOnboarding "$session_config/.claude.json")"

echo 'not json {' > "$session_config/.claude.json"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "an unreadable .claude.json is reset, so nothing unchecked survives" '{"hasCompletedOnboarding":true}' \
  "$(jq -c . "$session_config/.claude.json")"

STUB_GITHUB_TOKEN=secret run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "a keychain GitHub token reaches git as a ready-encoded header" \
  "1 http.https://github.com/.extraHeader Authorization: Basic $(printf 'x-access-token:secret' | base64)" \
  "$(cat "$sandbox/git-config-env")"

project="$sandbox/project"
git init -q "$project"
(cd "$project" && run_capture "$repo/bin/claude-ollama" 27b -p hi)
check_that "the sandbox lets the session commit to the project's git directory" policy_lists allowWrite "$project/.git"
check_that "the sandbox never writes git hooks" policy_lists denyWrite "$project/.git/hooks"
check_that "the sandbox never writes the repo's git config" policy_lists denyWrite "$project/.git/config"
mkdir -p "$project/src/deep"
ln -s "$project" "$sandbox/project-link"
(cd "$sandbox/project-link/src/deep" && run_capture "$repo/bin/claude-ollama" 27b -p hi)
check_that "from a subfolder the session still never writes the repo root's .claude" policy_lists denyWrite "$project/**/.claude"
check_that "nor anything inside any .claude in the repo" policy_lists denyWrite "$project/**/.claude/**"
outside="$sandbox/outside"
mkdir -p "$outside"
(cd "$outside" && run_capture "$repo/bin/claude-ollama" 27b -p hi)
check_that "outside a repo the current folder's .claude is protected" policy_lists denyWrite "$outside/**/.claude"
check_eq "the root's own .claude is also denied as a literal path, whatever glob matching does" true \
  "$(jq --arg path "$outside/.claude" '.filesystem.denyWrite | any(. == {path: $path, literal: true})' "$sandbox/policy.json")"
globbed="$sandbox/odd[ab]dir"
mkdir -p "$globbed"
(cd "$globbed" && run_capture "$repo/bin/claude-ollama" 27b -p hi)
check_eq "claude-ollama refuses a project path with glob characters" 1 "$?"
check_that "and says why" grep -qF "claude-ollama: $globbed has glob characters (*?[]), which would break the sandbox's write rules" "$sandbox/err"
check_not "and never runs claude there" grep -q '^ARGS:' "$sandbox/out"

rm "$(sandbox_runtime_path)"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "claude-ollama without sandbox-runtime exits 1" 1 "$?"
check_that "claude-ollama without sandbox-runtime says how to install it" \
  grep -qxF "claude-ollama: sandbox-runtime is missing; run claude-custom install" "$sandbox/err"
check_not "claude-ollama never runs claude unsandboxed" grep -q "^ARGS:" "$sandbox/out"
run_capture "$repo/bin/claude-ollama" doctor 27b
check_that "doctor reports a missing sandbox-runtime" grep -qxF "fail sandbox-runtime missing (run claude-custom install)" "$sandbox/out"
check_that "doctor warns when no GitHub token is stored" \
  grep -qxF "warn no GitHub token in the keychain item claude-ollama-github (git push from the session will fail; see docs/ollama.md)" "$sandbox/out"
install_sandbox_runtime_stub
STUB_GITHUB_TOKEN=secret run_capture "$repo/bin/claude-ollama" doctor 27b
check_that "doctor reports sandbox-runtime" grep -qxF "ok   sandbox-runtime installed" "$sandbox/out"
check_that "doctor reports a stored GitHub token" grep -qxF "ok   GitHub token in the keychain item claude-ollama-github" "$sandbox/out"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
