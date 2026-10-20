#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
installer="$repo/bin/claude-custom"
failures=0
sandboxes=""
remove_sandboxes() {
  local dir
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

new_sandbox() {
  sandbox="$(cd "$(mktemp -d)" && pwd -P)"
  sandboxes="$sandboxes $sandbox"
  export HOME="$sandbox/home"
  mkdir -p "$HOME" "$sandbox/stubbin"
  unset ZDOTDIR XDG_CONFIG_HOME CLAUDE_CONFIG_DIR STUB_OLLAMA_SHOW_EXIT STUB_OLLAMA_PULL_EXIT
  unset STUB_OLLAMA_PID STUB_OLLAMA_ENV STUB_CURL_EXIT STUB_OLLAMA_MISSING
  export SHELL=/bin/zsh
  export CLAUDE_OLLAMA_MANAGED_SETTINGS="$sandbox/managed-settings.json"
  cat > "$sandbox/stubbin/claude" <<EOF
#!/bin/sh
echo "ARGS: \$*"
echo "\${ANTHROPIC_MODEL-unset}" > "$sandbox/model-env"
echo "\${CLAUDE_CUSTOM_HOME-unset}" > "$sandbox/custom-home-env"
EOF
  cat > "$sandbox/stubbin/ollama" <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/ollama.log"
if [ "\$1" = show ]; then
  [ "\$2" = "\${STUB_OLLAMA_MISSING:-}" ] && exit 1
  exit "\${STUB_OLLAMA_SHOW_EXIT:-0}"
fi
if [ "\$1" = pull ]; then exit "\${STUB_OLLAMA_PULL_EXIT:-0}"; fi
exit 0
EOF
  cat > "$sandbox/stubbin/curl" <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/curl.log"
exit "\${STUB_CURL_EXIT:-0}"
EOF
  cat > "$sandbox/stubbin/python3" <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/python.log"
EOF
  cat > "$sandbox/stubbin/pgrep" <<'EOF'
#!/bin/sh
[ -n "${STUB_OLLAMA_PID:-}" ] && echo "$STUB_OLLAMA_PID"
EOF
  cat > "$sandbox/stubbin/ps" <<'EOF'
#!/bin/sh
echo "ollama serve ${STUB_OLLAMA_ENV:-}"
EOF
  chmod +x "$sandbox/stubbin/claude" "$sandbox/stubbin/ollama" "$sandbox/stubbin/curl" "$sandbox/stubbin/python3" "$sandbox/stubbin/pgrep" "$sandbox/stubbin/ps"
  link_system_tools
  export PATH="$sandbox/stubbin:$sandbox/sysbin"
}

link_system_tools() {
  local entry name
  mkdir -p "$sandbox/sysbin"
  for entry in /usr/bin/* /bin/*; do
    name="${entry##*/}"
    case "$name" in
      go|gofmt) continue ;;
    esac
    if [ -x "$entry" ] && [ ! -e "$sandbox/sysbin/$name" ]; then
      ln -s "$entry" "$sandbox/sysbin/$name"
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
check_that "claude-ollama passes claude args through" grep -qF -- "--tools Bash,Read,Edit,Write,Agent -p hi" "$sandbox/out"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama keeps the explicit size form" grep -qF -- "--tools Bash,Read,Edit,Write,Agent -p hi" "$sandbox/out"
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
check_that "claude-ollama 35b passes claude args through" grep -qF -- "--tools Bash,Read,Edit,Write,Agent -p hi" "$sandbox/out"
check_that "claude-ollama warms the main model" grep -q 'localhost:11434/api/generate' "$sandbox/curl.log"
check_that "claude-ollama warm-up names the model" grep -q '"model":"qwen3.6-35b-cc"' "$sandbox/curl.log"
check_that "claude-ollama warm-up sets keep_alive" grep -q '"keep_alive":"30m"' "$sandbox/curl.log"
rm -f "$sandbox/curl.log"
OLLAMA_HOST=http://box:1 run_capture "$repo/bin/claude-ollama" 35b -p hi
check_that "claude-ollama warm-up follows OLLAMA_HOST" grep -q 'box:1/api/generate' "$sandbox/curl.log"
check_not "claude-ollama 35b skips pull when the model exists" grep -sqE '^(pull|create) ' "$sandbox/ollama.log"
check_not "claude-ollama does not warn when the side model exists" grep -q 'side model' "$sandbox/err"
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
rm -f "$sandbox/stubbin/curl"
OLLAMA_HOST=http://127.0.0.1:9 run_capture "$repo/bin/claude-ollama" 35b -p hi
check_that "claude-ollama launches without curl" grep -q '^ARGS:' "$sandbox/out"
new_sandbox
STUB_OLLAMA_SHOW_EXIT=1 run_capture "$repo/bin/claude-ollama" 35b -p hi
check_that "claude-ollama 35b pulls a missing base model" grep -qxF "pull qwen3.6:35b-mlx" "$sandbox/ollama.log"
check_that "claude-ollama 35b creates the missing model" grep -qxF "create qwen3.6-35b-cc -f $repo/ollama/Modelfile.35b" "$sandbox/ollama.log"
check_that "claude-ollama 35b launches after pulling" grep -qF -- "--model qwen3.6-35b-cc --tools" "$sandbox/out"
settings_arg() { sed -n 's/^ARGS: --settings \([^ ]*\).*/\1/p' "$sandbox/out"; }
check_that "claude-ollama says subagents fall back to the main model" grep -qF "side model qwen3-4b-cc missing; subagents use qwen3.6-35b-cc this session" "$sandbox/err"
fallback_settings="$(settings_arg)"
check_not "claude-ollama passes a derived settings file" test "$fallback_settings" = "$repo/ollama/settings.35b.json"
check_eq "derived settings send subagents to the main model" "qwen3.6-35b-cc qwen3.6-35b-cc" \
  "$(jq -r '[.env.CLAUDE_CODE_SUBAGENT_MODEL, .env.ANTHROPIC_DEFAULT_HAIKU_MODEL] | join(" ")' "$fallback_settings")"
check_eq "derived settings map Haiku IDs to the main model" "qwen3.6-35b-cc qwen3.6-35b-cc" \
  "$(jq -r '[.modelOverrides["claude-haiku-5-5"], .modelOverrides["claude-haiku-4-5"]] | join(" ")' "$fallback_settings")"
check_eq "derived settings keep everything else" \
  "$(jq -S 'del(.env.CLAUDE_CODE_SUBAGENT_MODEL, .env.ANTHROPIC_DEFAULT_HAIKU_MODEL, .modelOverrides)' "$repo/ollama/settings.35b.json")" \
  "$(jq -S 'del(.env.CLAUDE_CODE_SUBAGENT_MODEL, .env.ANTHROPIC_DEFAULT_HAIKU_MODEL, .modelOverrides)' "$fallback_settings")"
STUB_OLLAMA_SHOW_EXIT=1 run_capture "$repo/bin/claude-ollama" 35b --require-side-model -p hi
check_eq "claude-ollama --require-side-model exit status" 1 "$?"
check_not "claude-ollama --require-side-model does not launch" grep -q '^ARGS:' "$sandbox/out"
run_capture "$repo/bin/claude-ollama" 35b -p hi
check_eq "claude-ollama uses the profile when the side model exists" "$repo/ollama/settings.35b.json" "$(settings_arg)"
check_not "claude-ollama does not pull the side model itself" grep -qxF "pull qwen3:4b" "$sandbox/ollama.log"
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
run_capture "$repo/bin/claude-ollama" --help
check_eq "claude-ollama help exit status" 0 "$?"
check_that "claude-ollama help lists sizes" grep -qxF "sizes: 27b-dirk 27b 35b-distill 35b-tiel 35b" "$sandbox/out"
check_not "claude-ollama help does not launch claude" grep -q '^ARGS:' "$sandbox/out"
run_capture "$repo/bin/claude-ollama" 28b -p hi </dev/null
check_that "claude-ollama unknown size without a tty falls back to 27b" grep -qF -- "$ollama_settings" "$sandbox/out"
check_not "claude-ollama drops an unknown size" grep -qF "28b" "$sandbox/out"
check_that "claude-ollama unknown size keeps claude args" grep -qF -- "Agent -p hi" "$sandbox/out"

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
check_that "claude-ollama help lists sizes from config" grep -qxF "sizes: 27b-dirk 27b 35b-distill 35b-tiel 35b 9b" "$sandbox/out"

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
run_capture "$installer" bogus
check_eq "unknown subcommand exit status" 2 "$?"
check_that "usage lists the new subcommands" grep -qF "install|update|uninstall|ollama|tools" "$sandbox/err"

new_sandbox
run_capture "$repo/bin/claude-ollama" --print-config 35b
check_eq "print-config exit status" 0 "$?"
check_not "print-config does not launch claude" grep -q '^ARGS:' "$sandbox/out"
check_not "print-config does not pull or create" grep -sqE '^(pull|create) ' "$sandbox/ollama.log"
check_that "print-config shows the size" grep -qxF "size: 35b" "$sandbox/out"
check_that "print-config shows the model" grep -qxF "model: qwen3.6-35b-cc" "$sandbox/out"
check_that "print-config shows the base model" grep -qxF "base: qwen3.6:35b-mlx" "$sandbox/out"
check_that "print-config shows the side model" grep -qxF "side model: qwen3-4b-cc" "$sandbox/out"
check_that "print-config shows the embedding model" grep -qxF "embedding model: qwen3-embedding:0.6b" "$sandbox/out"
check_that "print-config shows num_ctx" grep -qxF "num_ctx: 65536" "$sandbox/out"
check_that "print-config shows context tokens" grep -qxF "max context tokens: 65536" "$sandbox/out"
check_that "print-config shows the settings path" grep -qxF "settings: $repo/ollama/settings.35b.json" "$sandbox/out"
check_that "print-config shows the tools" grep -qxF "tools: Bash,Read,Edit,Write,Agent" "$sandbox/out"
check_that "print-config shows the command" grep -q '^command: claude --settings ' "$sandbox/out"
run_capture "$repo/bin/claude-ollama" --print-config </dev/null
check_that "print-config without a size uses the default" grep -qxF "size: 27b" "$sandbox/out"

new_sandbox
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m" run_capture "$repo/bin/claude-ollama" doctor 27b
check_eq "doctor healthy exit status" 0 "$?"
check_that "doctor reports jq" grep -qxF "ok   jq on PATH" "$sandbox/out"
check_that "doctor reports the main model" grep -qxF "ok   model qwen3.8-27b-cc" "$sandbox/out"
check_that "doctor reports the side model" grep -qxF "ok   side model qwen3-4b-cc" "$sandbox/out"
check_that "doctor reports the embedding model" grep -qxF "ok   embedding model qwen3-embedding:0.6b" "$sandbox/out"
check_that "doctor reports context sizes agree" grep -qxF "ok   num_ctx 65536 matches CLAUDE_CODE_MAX_CONTEXT_TOKENS" "$sandbox/out"
check_that "doctor reports hooks" grep -qxF "ok   hook stop-verify.py present" "$sandbox/out"
check_that "doctor reports reachability" grep -qxF "ok   ollama reachable at http://localhost:11434" "$sandbox/out"
check_that "doctor reports server env" grep -qxF "ok   server env OLLAMA_KV_CACHE_TYPE=q8_0" "$sandbox/out"
check_that "doctor reports no managed model allowlist" grep -qxF "ok   no managed availableModels restricts qwen3.8-27b-cc" "$sandbox/out"
check_not "doctor does not launch claude" grep -q '^ARGS:' "$sandbox/out"
check_not "doctor does not pull or create" grep -sqE '^(pull|create) ' "$sandbox/ollama.log"

new_sandbox
STUB_OLLAMA_SHOW_EXIT=1 STUB_OLLAMA_PID=42 run_capture "$repo/bin/claude-ollama" doctor 27b
check_eq "doctor with missing models exit status" 1 "$?"
check_that "doctor fails the main model" grep -qxF "fail model qwen3.8-27b-cc missing (run claude-ollama 27b to pull and create it)" "$sandbox/out"
check_that "doctor warns about the side model" grep -qxF "warn side model qwen3-4b-cc missing (pick 'Set up side model' in claude-ollama)" "$sandbox/out"
check_that "doctor fails the embedding model" grep -qxF "fail embedding model qwen3-embedding:0.6b missing (pick 'Set up embedding model' in claude-ollama)" "$sandbox/out"
check_that "doctor fails server env" grep -qxF "fail server env OLLAMA_FLASH_ATTENTION=1 not set on the running server" "$sandbox/out"

new_sandbox
STUB_OLLAMA_MISSING=qwen3-4b-cc STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m" run_capture "$repo/bin/claude-ollama" doctor 27b
check_eq "doctor with only the side model missing exits 0" 0 "$?"
check_that "doctor warns only about the side model" grep -qxF "warn side model qwen3-4b-cc missing (pick 'Set up side model' in claude-ollama)" "$sandbox/out"

new_sandbox
copy_repo "$sandbox/repo"
sed 's/num_ctx 65536/num_ctx 32768/' "$sandbox/repo/ollama/Modelfile.27b" > "$sandbox/Modelfile.27b"
mv "$sandbox/Modelfile.27b" "$sandbox/repo/ollama/Modelfile.27b"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m" run_capture "$sandbox/repo/bin/claude-ollama" doctor 27b
check_eq "doctor with mismatched context sizes exit status" 1 "$?"
check_that "doctor fails mismatched context sizes" grep -qxF "fail num_ctx 32768 differs from CLAUDE_CODE_MAX_CONTEXT_TOKENS 65536" "$sandbox/out"

new_sandbox
copy_repo "$sandbox/repo"
rm "$sandbox/repo/shared/hooks/edit-check.py"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m" run_capture "$sandbox/repo/bin/claude-ollama" doctor 27b
check_eq "doctor with a missing hook exit status" 1 "$?"
check_that "doctor fails a missing hook" grep -qxF "fail hook edit-check.py missing or not executable in shared/hooks" "$sandbox/out"

new_sandbox
echo '{"availableModels":["qwen3.8-27b-cc","opus"]}' > "$CLAUDE_OLLAMA_MANAGED_SETTINGS"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m" run_capture "$repo/bin/claude-ollama" doctor 27b
check_eq "doctor with the model in the managed allowlist exit status" 0 "$?"
check_that "doctor reports the managed allowlist allows the model" grep -qxF "ok   managed availableModels allows qwen3.8-27b-cc" "$sandbox/out"

new_sandbox
echo '{"availableModels":["opus"]}' > "$CLAUDE_OLLAMA_MANAGED_SETTINGS"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m" run_capture "$repo/bin/claude-ollama" doctor 27b
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

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
