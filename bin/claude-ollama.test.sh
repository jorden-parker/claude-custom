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

contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
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
  sandbox="$(made="$(mktemp -d "${1:-${TMPDIR:-/tmp}}/claude-ollama-test.XXXXXX")" && cd "$made" && pwd -P)" || exit 1
  sandboxes="$sandboxes $sandbox"
  export HOME="$sandbox/home"
  mkdir -p "$HOME" "$sandbox/stubbin"
  unset ZDOTDIR XDG_CONFIG_HOME CLAUDE_CONFIG_DIR STUB_OLLAMA_SHOW_EXIT STUB_OLLAMA_PULL_EXIT
  unset STUB_OLLAMA_PID STUB_OLLAMA_ENV STUB_CURL_EXIT STUB_OLLAMA_NUM_CTX STUB_AGENT_EXIT CMUX_SOCKET_PATH CLAUDE_OLLAMA_CMUX
  unset STUB_SHASUM_DIGEST STUB_INSPECT_EXIT STUB_CLAUDE_STDERR CLAUDE_CONSOLE_STATE_DIR
  unset CLAUDE_TOOL_TELEMETRY CLAUDE_OLLAMA_TELEMETRY
  export SHELL=/bin/zsh
  record_installed_num_ctx
  export CLAUDE_OLLAMA_MANAGED_SETTINGS="$sandbox/managed-settings.json"
  cat > "$sandbox/stubbin/claude" <<EOF
#!/bin/sh
echo "ARGS: \$*"
echo "\${ANTHROPIC_MODEL-unset}" > "$sandbox/model-env"
echo "\${CLAUDE_CUSTOM_HOME-unset}" > "$sandbox/custom-home-env"
echo "\${CLAUDE_TOOL_TELEMETRY-unset}" > "$sandbox/telemetry-env"
echo "\${CODE_SEARCH_EMBED-unset}" > "$sandbox/embed-env"
echo "\${CLAUDE_CONFIG_DIR-unset}" > "$sandbox/config-dir-env"
echo "\${CLAUDE_CODE_TMPDIR-unset}" > "$sandbox/tmpdir-env"
env > "$sandbox/claude-env"
[ -n "\${STUB_CLAUDE_STDERR:-}" ] && echo "\$STUB_CLAUDE_STDERR" >&2
exit 0
EOF
  cat > "$sandbox/stubbin/qwen" <<EOF
#!/bin/sh
echo "QWEN ARGS: \$*"
env > "$sandbox/qwen-env"
EOF
  cat > "$sandbox/stubbin/open" <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/open.log"
EOF
  chmod +x "$sandbox/stubbin/open"
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
arguments="\$*"
echo "\$arguments" >> "$sandbox/curl.log"
case "\$arguments" in */health*) [ -e "$sandbox/console-running" ] && exit 0; exit 7 ;; esac
output=""
while [ \$# -gt 0 ]; do
  [ "\$1" = -o ] && output="\$2"
  shift
done
case "\$arguments" in *api/tags*) cat "$sandbox/tags.json" ;; esac
case "\$arguments" in *huggingface.co*) printf 'stub weights' > "\$output"; exit "\${STUB_HF_CURL_EXIT:-0}" ;; esac
exit "\${STUB_CURL_EXIT:-0}"
EOF
  cat > "$sandbox/stubbin/shasum" <<'EOF'
#!/bin/sh
echo "${STUB_SHASUM_DIGEST:-0000000000000000000000000000000000000000000000000000000000000000}  $2"
EOF
  cat > "$sandbox/stubbin/gguf-inspect" <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/inspect.log"
exit "\${STUB_INSPECT_EXIT:-0}"
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
  export CLAUDE_OLLAMA_GGUF_INSPECT="$sandbox/stubbin/gguf-inspect"
  cat > "$sandbox/stubbin/pgrep" <<'EOF'
#!/bin/sh
[ -n "${STUB_OLLAMA_PID:-}" ] && echo "$STUB_OLLAMA_PID"
EOF
  cat > "$sandbox/stubbin/ps" <<'EOF'
#!/bin/sh
echo "ollama serve ${STUB_OLLAMA_ENV:-}"
EOF
  chmod +x "$sandbox/stubbin/claude" "$sandbox/stubbin/qwen" "$sandbox/stubbin/ollama" "$sandbox/stubbin/ollama-agent" "$sandbox/stubbin/curl" "$sandbox/stubbin/python3" "$sandbox/stubbin/pgrep" "$sandbox/stubbin/ps" "$sandbox/stubbin/shasum" "$sandbox/stubbin/gguf-inspect"
  link_system_tools
  export PATH="$sandbox/stubbin:$sandbox/sysbin"
  cat > "$sandbox/stubbin/draft-opener" <<EOF
#!/bin/sh
printf '%s\n' "\$*" > "$sandbox/opener-args"
EOF
  chmod +x "$sandbox/stubbin/draft-opener"
  export CLAUDE_OLLAMA_DRAFT_OPENER="$sandbox/stubbin/draft-opener"
  unset CLAUDE_OLLAMA_OPEN_DRAFTS CLAUDE_OLLAMA_DRAFTS_DIR
}

link_system_tools() {
  [ -n "$system_tools" ] || build_system_tools
  ln -s "$system_tools" "$sandbox/sysbin"
}

build_system_tools() {
  local entry name
  system_tools="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
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
check_that "claude-ollama passes claude args through" grep -qF -- "--tools Bash,Read,Edit,Write,Skill,TaskStop -p hi" "$sandbox/out"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama keeps the explicit size form" grep -qF -- "--tools Bash,Read,Edit,Write,Skill,TaskStop -p hi" "$sandbox/out"
check_that "claude-ollama 27b passes the 27b model" grep -qF -- "--model qwen3.8-27b-cc --tools" "$sandbox/out"
ANTHROPIC_MODEL=claude-opus-5-5 run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama 27b ignores ANTHROPIC_MODEL" grep -qF -- "--model qwen3.8-27b-cc --tools" "$sandbox/out"
check_that "claude-ollama unsets ANTHROPIC_MODEL" grep -qxF "unset" "$sandbox/model-env"
check_eq "claude-ollama exports CLAUDE_CUSTOM_HOME to claude" "$repo" "$(cat "$sandbox/custom-home-env")"
check_eq "claude-ollama records tool telemetry under the session folder by default" "$HOME/.claude-ollama/telemetry/tool-calls.jsonl" "$(cat "$sandbox/telemetry-env")"
run_capture env CLAUDE_OLLAMA_TELEMETRY=0 "$repo/bin/claude-ollama" 27b -p hi
check_eq "CLAUDE_OLLAMA_TELEMETRY=0 turns tool telemetry off" unset "$(cat "$sandbox/telemetry-env")"
run_capture env CLAUDE_TOOL_TELEMETRY="$sandbox/mine.jsonl" "$repo/bin/claude-ollama" 27b -p hi
check_eq "CLAUDE_TOOL_TELEMETRY overrides the telemetry file" "$sandbox/mine.jsonl" "$(cat "$sandbox/telemetry-env")"
telemetry_dir="$HOME/.claude-ollama/telemetry"
mkdir -p "$telemetry_dir"
head -c 1048577 /dev/zero > "$telemetry_dir/tool-calls.jsonl"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama rotates a telemetry file past 1 MiB" test -f "$telemetry_dir/tool-calls.jsonl.1"
new_sandbox
mkdir -p "$HOME/.claude-ollama" "$sandbox/elsewhere"
ln -s "$sandbox/elsewhere" "$HOME/.claude-ollama/telemetry"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "a symlinked telemetry folder turns telemetry off" unset "$(cat "$sandbox/telemetry-env")"
check_that "a symlinked telemetry folder is reported" grep -qF "claude-ollama: telemetry: $HOME/.claude-ollama/telemetry is a symlink or not a regular file; telemetry off" "$sandbox/err"
new_sandbox
mkdir -p "$HOME/.claude-ollama/telemetry" "$sandbox/elsewhere"
ln -s "$sandbox/elsewhere/tool-calls.jsonl" "$HOME/.claude-ollama/telemetry/tool-calls.jsonl"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "a symlinked tool-calls.jsonl turns telemetry off" unset "$(cat "$sandbox/telemetry-env")"
check_that "a symlinked tool-calls.jsonl is reported" grep -qF "claude-ollama: telemetry: $HOME/.claude-ollama/telemetry/tool-calls.jsonl is a symlink or not a regular file; telemetry off" "$sandbox/err"
run_capture "$repo/bin/claude-ollama" 35b -p hi
check_that "claude-ollama 35b uses the 35b settings" grep -qF -- "--settings $repo/ollama/settings.35b.json" "$sandbox/out"
check_that "claude-ollama 35b passes the 35b model" grep -qF -- "--model qwen3.6-35b-cc --tools" "$sandbox/out"
append_prompt="$HOME/.claude-ollama/append-prompt.md"
check_that "claude-ollama replaces the default system prompt and appends its own" \
  grep -qF -- "--system-prompt-file $repo/ollama/system-prompt.md --append-system-prompt-file $append_prompt" "$sandbox/out"
check_eq "the appended prompt is the shared local prompt" "$(cat "$repo/ollama/CLAUDE.local.md")" "$(cat "$append_prompt")"
check_that "claude-ollama 35b passes claude args through" grep -qF -- "--tools Bash,Read,Edit,Write,Skill,TaskStop -p hi" "$sandbox/out"
check_that "claude-ollama warms the main model" grep -q '127.0.0.1:11434/api/generate' "$sandbox/curl.log"
check_that "claude-ollama warm-up names the model" grep -q '"model":"qwen3.6-35b-cc"' "$sandbox/curl.log"
check_that "claude-ollama warm-up sets keep_alive" grep -q '"keep_alive":"30m"' "$sandbox/curl.log"
rm -f "$sandbox/curl.log"
OLLAMA_HOST=http://box:1 run_capture "$repo/bin/claude-ollama" 35b -p hi
check_that "claude-ollama warm-up follows OLLAMA_HOST" grep -q 'box:1/api/generate' "$sandbox/curl.log"
check_not "claude-ollama 35b skips pull when the model exists" grep -sqE '^(pull|create) ' "$sandbox/ollama.log"
check_that "claude-ollama starts the code-search, repo and dev MCP servers" grep -qF -- "--strict-mcp-config --mcp-config {\"mcpServers\":{\"code-search\":{\"command\":\"python3\",\"args\":[\"$repo/shared/mcp/code-search.py\"]},\"repo\":{\"command\":\"python3\",\"args\":[\"$repo/shared/mcp/repo-tools.py\"]},\"dev\":{\"command\":\"python3\",\"args\":[\"$repo/shared/mcp/dev-server.py\"]}}}" "$sandbox/out"
rm -f "$sandbox/python.log"
run_capture "$repo/bin/claude-ollama" 35b -p hi
sleep 1
check_that "claude-ollama starts the indexer tied to its own process" grep -qxE "$repo/shared/mcp/code-search.py --index --watch-pid [0-9]+" "$sandbox/python.log"
check_that "claude-ollama launches without waiting for the indexer" grep -q '^ARGS:' "$sandbox/out"
rm -f "$sandbox/python.log"
run_capture env CLAUDE_OLLAMA_NO_INDEX=1 "$repo/bin/claude-ollama" 35b -p hi
check_not "CLAUDE_OLLAMA_NO_INDEX skips the indexer" test -e "$sandbox/python.log"
new_sandbox
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=2" run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama warms the embedding model when the server keeps two models" grep -q '127.0.0.1:11434/api/embed' "$sandbox/curl.log"
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
launcher_log="$HOME/.local/share/claude-custom/console/launcher.log"

wait_for_launcher_log() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    grep -qF -- "$1" "$launcher_log" 2>/dev/null && return 0
    sleep 0.2
  done
  return 1
}

rm -f "$launcher_log"
STUB_CLAUDE_STDERR="claude own stderr" run_capture "$repo/bin/claude-ollama" 35b -p hi
check_that "a launch writes its start to the launcher log" wait_for_launcher_log "claude-ollama: launch 35b in $(pwd -P)"
check_that "the launcher log records the hand-off to claude" wait_for_launcher_log "claude-ollama: starting claude"
check_not "the launcher log leaves out claude's own stderr" grep -qF "claude own stderr" "$launcher_log"
check_that "claude's own stderr still reaches the terminal" grep -qxF "claude own stderr" "$sandbox/err"
check_that "launcher messages still reach the terminal" grep -qF "claude-ollama: launch 35b" "$sandbox/err"
check_eq "the launcher log is private" 600 "$(stat -c %a "$launcher_log" 2>/dev/null || stat -f %Lp "$launcher_log")"
head -c 1100000 /dev/zero | tr '\0' x > "$launcher_log"
run_capture "$repo/bin/claude-ollama" 35b -p hi
check_that "a launcher log over 1 MiB moves aside" test "$(wc -c < "$launcher_log.1")" -ge 1100000
check_that "the fresh launcher log starts with this launch" wait_for_launcher_log "claude-ollama: launch 35b"
check_that "the fresh launcher log is small" test "$(wc -c < "$launcher_log")" -lt 4096
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
STUB_SHASUM_DIGEST=3f227079003add2511437e5b1e94812e363385225bf6a9b47b0054a72bc8b01e STUB_OLLAMA_SHOW_EXIT=1 run_capture "$repo/bin/claude-ollama" 27b-gguf -p hi
check_eq "claude-ollama 27b-gguf imports after a matching digest" 0 "$?"
check_that "claude-ollama 27b-gguf downloads the pinned Hugging Face file" grep -qF "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/4ca720788d1e01f1bff70c033e0d0028fd02e502/Qwen3.8-27B-UD-Q4_K_XL.gguf" "$sandbox/curl.log"
check_that "claude-ollama 27b-gguf creates the model from its Modelfile" grep -qxF "create qwen3.8-27b-gguf-cc -f Modelfile.27b-gguf" "$sandbox/ollama.log"
check_not "claude-ollama 27b-gguf never pulls its weights" grep -q '^pull \./weights' "$sandbox/ollama.log"
check_that "claude-ollama 27b-gguf launches after importing" grep -qF -- "--model qwen3.8-27b-gguf-cc --tools" "$sandbox/out"
check_not "claude-ollama 27b-gguf removes the verified download" test -e "$repo/ollama/weights/Qwen3.8-27B-UD-Q4_K_XL.gguf"
check_not "claude-ollama 27b-gguf leaves no partial download" test -e "$repo/ollama/weights/Qwen3.8-27B-UD-Q4_K_XL.gguf.part"
new_sandbox
STUB_SHASUM_DIGEST=abc STUB_OLLAMA_SHOW_EXIT=1 run_capture "$repo/bin/claude-ollama" 27b-gguf -p hi
check_eq "claude-ollama 27b-gguf exits 1 on a wrong digest" 1 "$?"
check_that "claude-ollama 27b-gguf names the actual and pinned digests" grep -qF "sha256 abc, but ollama/model-digests.json pins 3f227079003add2511437e5b1e94812e363385225bf6a9b47b0054a72bc8b01e" "$sandbox/err"
check_not "claude-ollama 27b-gguf does not create after a wrong digest" grep -sq '^create ' "$sandbox/ollama.log"
check_not "claude-ollama 27b-gguf does not launch after a wrong digest" grep -q '^ARGS:' "$sandbox/out"
check_not "claude-ollama 27b-gguf removes the download after a wrong digest" test -e "$repo/ollama/weights/Qwen3.8-27B-UD-Q4_K_XL.gguf.part"
new_sandbox
STUB_SHASUM_DIGEST=3f227079003add2511437e5b1e94812e363385225bf6a9b47b0054a72bc8b01e STUB_INSPECT_EXIT=1 STUB_OLLAMA_SHOW_EXIT=1 run_capture "$repo/bin/claude-ollama" 27b-gguf -p hi
check_eq "claude-ollama 27b-gguf exits 1 when inspection fails" 1 "$?"
check_that "claude-ollama 27b-gguf says the file failed inspection" grep -qF "failed inspection; not importing" "$sandbox/err"
check_not "claude-ollama 27b-gguf does not create after failed inspection" grep -sq '^create ' "$sandbox/ollama.log"
check_not "claude-ollama 27b-gguf does not launch after failed inspection" grep -q '^ARGS:' "$sandbox/out"
check_not "claude-ollama 27b-gguf removes the download after failed inspection" test -e "$repo/ollama/weights/Qwen3.8-27B-UD-Q4_K_XL.gguf.part"
new_sandbox
run_capture "$repo/bin/claude-ollama" 27b-gguf -p hi
check_not "claude-ollama 27b-gguf does not download when the model is installed" grep -qF huggingface.co "$sandbox/curl.log"
new_sandbox
STUB_HF_CURL_EXIT=18 STUB_OLLAMA_SHOW_EXIT=1 run_capture "$repo/bin/claude-ollama" 27b-gguf -p hi
check_eq "claude-ollama 27b-gguf exits 1 when the download breaks off" 1 "$?"
check_that "claude-ollama 27b-gguf asks curl to resume a partial download" grep -qF -- "-C -" "$sandbox/curl.log"
check_that "claude-ollama 27b-gguf keeps a broken-off download so the next run resumes it" test -e "$repo/ollama/weights/Qwen3.8-27B-UD-Q4_K_XL.gguf.part"
check_not "claude-ollama 27b-gguf does not create after a broken-off download" grep -sq '^create ' "$sandbox/ollama.log"
rm -f "$repo/ollama/weights/Qwen3.8-27B-UD-Q4_K_XL.gguf.part"
new_sandbox
STUB_SHASUM_DIGEST=3f227079003add2511437e5b1e94812e363385225bf6a9b47b0054a72bc8b01e STUB_OLLAMA_SHOW_EXIT=1 run_capture "$repo/bin/claude-ollama" prepare 27b-gguf
check_eq "claude-ollama prepare exits 0 after importing" 0 "$?"
check_that "claude-ollama prepare creates a missing model" grep -qxF "create qwen3.8-27b-gguf-cc -f Modelfile.27b-gguf" "$sandbox/ollama.log"
check_not "claude-ollama prepare does not launch claude" grep -q '^ARGS:' "$sandbox/out"
new_sandbox
run_capture "$repo/bin/claude-ollama" prepare 27b
check_eq "claude-ollama prepare exits 0 when the model is installed" 0 "$?"
check_not "claude-ollama prepare leaves an installed model alone" grep -sq '^create ' "$sandbox/ollama.log"
check_not "claude-ollama prepare of an installed model does not launch claude" grep -q '^ARGS:' "$sandbox/out"

new_sandbox
STUB_OLLAMA_SHOW_EXIT=1 run_capture "$repo/bin/claude-ollama" prepare-embedding
check_eq "claude-ollama prepare-embedding exits 0 after pulling" 0 "$?"
check_that "claude-ollama prepare-embedding pulls the embedding model" grep -qxF "pull qwen3-embedding:0.6b" "$sandbox/ollama.log"
check_not "claude-ollama prepare-embedding does not launch claude" grep -q '^ARGS:' "$sandbox/out"

new_sandbox
run_capture "$repo/bin/claude-ollama" prepare-embedding
check_eq "claude-ollama prepare-embedding exits 0 when the model is installed" 0 "$?"
check_not "claude-ollama prepare-embedding pulls nothing when the model is installed" grep -sq '^pull ' "$sandbox/ollama.log"

new_sandbox
STUB_OLLAMA_SHOW_EXIT=1 STUB_OLLAMA_PULL_EXIT=1 run_capture "$repo/bin/claude-ollama" prepare-embedding
check_eq "claude-ollama prepare-embedding exits 1 when the pull fails" 1 "$?"
new_sandbox
printf '#!/bin/sh\necho "speed-check args: $*"\n' > "$sandbox/stubbin/speed-check"
chmod +x "$sandbox/stubbin/speed-check"
CLAUDE_OLLAMA_SPEED_CHECK="$sandbox/stubbin/speed-check" run_capture "$repo/bin/claude-ollama" speed-check --flag
check_that "claude-ollama speed-check runs the speed check with its arguments" grep -qxF "speed-check args: --flag" "$sandbox/out"
check_not "claude-ollama speed-check does not launch claude" grep -q '^ARGS:' "$sandbox/out"
CLAUDE_OLLAMA_SPEED_CHECK="$sandbox/stubbin/speed-check" run_capture "$repo/bin/claude-ollama" thinking-check
check_that "claude-ollama thinking-check runs the speed check's thinking-only mode" grep -qxF "speed-check args: --thinking-only" "$sandbox/out"
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
check_that "claude-ollama names the upgrade command when a base misses its pin" grep -qF "or run bin/model-upgrade SIZE to test the new base and print the pin command" "$sandbox/err"
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
check_that "claude-ollama help lists sizes" grep -qxF "sizes: 27b-gguf 27b 35b-coding 35b-gguf 35b 3b" "$sandbox/out"
check_not "claude-ollama help does not launch claude" grep -q '^ARGS:' "$sandbox/out"
check_that "claude-ollama help names speed-check" grep -q '^speed-check: ' "$sandbox/out"
check_that "claude-ollama help names thinking-check" grep -q '^thinking-check: ' "$sandbox/out"
check_that "claude-ollama help names prepare" grep -q '^prepare \[size\]: ' "$sandbox/out"
check_that "claude-ollama help names prepare-embedding" grep -q '^prepare-embedding: ' "$sandbox/out"
run_capture "$repo/bin/claude-ollama" 28b -p hi </dev/null
check_that "claude-ollama unknown size without a tty falls back to 27b" grep -qF -- "$ollama_settings" "$sandbox/out"
check_not "claude-ollama drops an unknown size" grep -qF "28b" "$sandbox/out"
check_that "claude-ollama unknown size keeps claude args" grep -qF -- "TaskStop -p hi" "$sandbox/out"

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
check_that "claude-ollama help lists sizes from config" grep -qxF "sizes: 27b-gguf 27b 35b-coding 35b-gguf 35b 3b 9b" "$sandbox/out"

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
(cd "$sandbox" && run_capture "$installer" qwen 27b -p hi)
check_that "claude-custom qwen runs claude-ollama qwen" grep -q '^QWEN ARGS: --auth-type openai' "$sandbox/out"

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
check_that "usage lists the new subcommands" grep -qF "install|update|uninstall|ollama|qwen|tools|agent" "$sandbox/err"

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
check_that "print-config shows the tools, Skill included so your skills load" grep -qxF "tools: Bash,Read,Edit,Write,Skill,TaskStop" "$sandbox/out"
check_not "print-config has no sandbox line" grep -q '^sandbox:' "$sandbox/out"
run_capture "$repo/bin/claude-ollama" --print-config </dev/null
check_that "print-config without a size uses the default" grep -qxF "size: 27b" "$sandbox/out"

cat > "$sandbox/stubbin/tail" <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/tail.log"
EOF
chmod +x "$sandbox/stubbin/tail"
cat > "$sandbox/stubbin/launchctl" <<EOF
#!/bin/sh
printf 'PID\tStatus\tLabel\n'
[ "\$1" = list ] && cat "$sandbox/launchctl-list" 2>/dev/null
exit 0
EOF
chmod +x "$sandbox/stubbin/launchctl"
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
rm -f "$sandbox/tail.log"
run_capture "$repo/bin/claude-ollama" logs --path
check_eq "logs --path exit status" 0 "$?"
check_that "logs --path prints only the chosen log path" test "$(cat "$sandbox/out")" = "$sandbox/agent-ollama.log"
check_not "logs --path does not tail the log" test -e "$sandbox/tail.log"
printf -- '-\t1\tlocal.ollama\n4242\t0\tsh.brew.ollama\n' > "$sandbox/launchctl-list"
HOMEBREW_PREFIX="$sandbox/brew" run_capture "$repo/bin/claude-ollama" logs --path
check_that "logs --path follows the running Homebrew service over a dead LaunchAgent" test "$(cat "$sandbox/out")" = "$sandbox/brew/var/log/ollama.log"
printf '<plist><dict>\n  <key>StandardOutPath</key><string>%s</string>\n</dict></plist>\n' "$sandbox/brew-custom.log" > "$HOME/Library/LaunchAgents/sh.brew.ollama.plist"
: > "$sandbox/brew-custom.log"
HOMEBREW_PREFIX="$sandbox/brew" run_capture "$repo/bin/claude-ollama" logs --path
check_that "logs --path reads the running service's own plist" test "$(cat "$sandbox/out")" = "$sandbox/brew-custom.log"
printf -- '4343\t0\tlocal.ollama\n-\t0\thomebrew.mxcl.ollama\n' > "$sandbox/launchctl-list"
HOMEBREW_PREFIX="$sandbox/brew" run_capture "$repo/bin/claude-ollama" logs --path
check_that "logs --path follows the running LaunchAgent" test "$(cat "$sandbox/out")" = "$sandbox/agent-ollama.log"
rm -f "$sandbox/launchctl-list"
HOME="$sandbox/bare-home" HOMEBREW_PREFIX="$sandbox/brew-none" run_capture "$repo/bin/claude-ollama" logs --path
check_eq "logs --path without a log file exits 1" 1 "$?"
check_that "logs --path without a log file says so" grep -q 'no Ollama log found' "$sandbox/err"
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
  grep -qxF "REVIEW: --model qwen3.8-27b-cc --base-url http://127.0.0.1:11434 123" "$sandbox/out"
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
  grep -qxF "REVIEW: --model qwen3.8-27b-cc --base-url http://127.0.0.1:11434 --post 45" "$sandbox/out"
run_capture "$repo/bin/claude-ollama" review 9 </dev/null
check_that "review without a size uses the default" grep -q 'REVIEW: --model qwen3.8-27b-cc ' "$sandbox/out"
unset CLAUDE_OLLAMA_REVIEWER
run_capture "$repo/bin/claude-ollama" --help
check_that "claude-ollama help lists logs" grep -q '^logs \[-n LINES|--path\]: ' "$sandbox/out"

new_sandbox
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=2" run_capture "$repo/bin/claude-ollama" doctor 27b
check_eq "doctor healthy exit status" 0 "$?"
check_that "doctor reports jq" grep -qxF "ok   jq on PATH" "$sandbox/out"
check_that "doctor reports the main model" grep -qxF "ok   model qwen3.8-27b-cc" "$sandbox/out"
check_not "doctor no longer checks a side model" grep -q "side model" "$sandbox/out"
check_that "doctor reports the embedding model" grep -qxF "ok   embedding model qwen3-embedding:0.6b" "$sandbox/out"
check_that "doctor reports context sizes agree" grep -qxF "ok   num_ctx 65536 matches CLAUDE_CODE_MAX_CONTEXT_TOKENS" "$sandbox/out"
check_that "doctor reports hooks" grep -qxF "ok   hook stop-verify.py present" "$sandbox/out"
check_that "doctor reports reachability" grep -qxF "ok   ollama reachable at http://127.0.0.1:11434" "$sandbox/out"
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
check_that "doctor fails when the server is unreachable" grep -qxF "fail ollama not reachable at http://127.0.0.1:11434 (brew services start ollama)" "$sandbox/out"
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
export CLAUDE_CONSOLE_STATE_DIR="$sandbox/console"
export CONSOLE_RUNNING_MARKER="$sandbox/console-running"
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
  install) mkdir -p "$2/node_modules" && touch "$2/node_modules/.modules.yaml" ;;
  exec)
    [ -z "${STUB_CONSOLE_RACE_LOST:-}" ] || touch "$CONSOLE_RUNNING_MARKER"
    cat "$PR_REVIEW_LOG_DIR/.web-url" >> "$PNPM_LOG" 2>/dev/null || true
    ls -l "$PR_REVIEW_LOG_DIR/.web-url" 2>/dev/null | cut -c1-10 >> "$PNPM_LOG"
    echo "TOKEN: ${PR_REVIEW_TOKEN:-unset}" >> "$PNPM_LOG"
    echo "TOKEN_FILE: ${CONSOLE_TOKEN_FILE:-unset}" >> "$PNPM_LOG"
    echo "TOKEN_FILE_MODE: $(ls -l "$CONSOLE_TOKEN_FILE" 2>/dev/null | cut -c1-10)" >> "$PNPM_LOG"
    echo "TOKEN_FILE_CONTENTS: $(cat "$CONSOLE_TOKEN_FILE" 2>/dev/null)" >> "$PNPM_LOG"
    echo "STATE_MODE: $(ls -ld "$(dirname "$CONSOLE_TOKEN_FILE")" 2>/dev/null | cut -c1-10)" >> "$PNPM_LOG"
    echo "CUSTOM_HOME: ${CLAUDE_CUSTOM_HOME:-unset}" >> "$PNPM_LOG"
    echo "RUN_STATE_DIR: ${CLAUDE_CONSOLE_STATE_DIR:-unset}" >> "$PNPM_LOG"
    echo "PROJECT: ${CONSOLE_PROJECT_DIR:-unset}" >> "$PNPM_LOG"
    echo "SOURCE: ${CLAUDE_CUSTOM_CHANGE_SOURCE:-unset}" >> "$PNPM_LOG"
    echo "TELEMETRY: ${CLAUDE_TOOL_TELEMETRY:-unset}" >> "$PNPM_LOG"
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
check_that ".web-url is owner-only while serving" grep -qxF -- "-rw-------" "$PNPM_LOG"
check_that "reviews prints its tokened URL" grep -qxF "claude-ollama: reviews at http://127.0.0.1:9000/reviews?token=$token" "$sandbox/out"
check_not "reviews removes .web-url after it exits" test -e "$PR_REVIEW_LOG_DIR/.web-url"
check_that "reviews hands the server its port's console token file" grep -qxF -- "TOKEN_FILE: $CLAUDE_CONSOLE_STATE_DIR/tokens/9000" "$PNPM_LOG"
check_that "the console token file is owner-only" grep -qxF -- "TOKEN_FILE_MODE: -rw-------" "$PNPM_LOG"
check_that "the console token folder is owner-only" grep -qxF -- "STATE_MODE: drwx------" "$PNPM_LOG"
check_that "the console token file holds the token from .web-url" grep -qxF -- "TOKEN_FILE_CONTENTS: $token" "$PNPM_LOG"
check_that "the server gets no token in its environment" grep -qxF -- "TOKEN: unset" "$PNPM_LOG"
check_not "reviews removes its console token file after it exits" test -e "$CLAUDE_CONSOLE_STATE_DIR/tokens/9000"
check_that "the console server gets the repo as CLAUDE_CUSTOM_HOME" grep -qxF -- "CUSTOM_HOME: $repo" "$PNPM_LOG"
check_that "the console server gets the console state dir" grep -qxF -- "RUN_STATE_DIR: $CLAUDE_CONSOLE_STATE_DIR" "$PNPM_LOG"
rm -f "$PNPM_LOG"
run_capture "$repo/bin/claude-ollama" ui --port 9000
check_that "ui serves the console on loopback at the port" grep -qxF -- "PNPM: --dir $web exec next start -H 127.0.0.1 -p 9000" "$PNPM_LOG"
check_that "the console marks its changes with its own source" grep -qxF -- "SOURCE: console" "$PNPM_LOG"
check_that "ui prints its tokened console URL" grep -qxE "claude-ollama: console at http://127\.0\.0\.1:9000/\?token=[0-9a-f]{48}" "$sandbox/out"
check_not "ui removes .web-url after it exits" test -e "$PR_REVIEW_LOG_DIR/.web-url"
rm -f "$PNPM_LOG"
run_capture "$repo/bin/claude-ollama" ui --port 9000
check_that "ui hands the console the default telemetry file" grep -qxF -- "TELEMETRY: $HOME/.claude-ollama/telemetry/tool-calls.jsonl" "$PNPM_LOG"
mkdir -p "$HOME/.claude-ollama" "$sandbox/moved-telemetry"
rm -rf "$HOME/.claude-ollama/telemetry"
ln -s "$sandbox/moved-telemetry" "$HOME/.claude-ollama/telemetry"
rm -f "$PNPM_LOG"
run_capture "$repo/bin/claude-ollama" ui --port 9000
check_that "ui gives the console no telemetry file when its folder is a symlink" grep -qxF -- "TELEMETRY: unset" "$PNPM_LOG"
check_that "ui warns when the telemetry folder is a symlink" grep -qF -- "claude-ollama: telemetry: $HOME/.claude-ollama/telemetry is a symlink or not a regular file; telemetry off" "$sandbox/err"
rm -f "$HOME/.claude-ollama/telemetry"
mkdir -p "$sandbox/started-here"
(cd "$sandbox/started-here" && run_capture "$repo/bin/claude-ollama" ui --port 9000)
check_that "ui hands the server the folder it was started from" grep -qxF -- "PROJECT: $sandbox/started-here" "$PNPM_LOG"
mkdir -p "$CLAUDE_CONSOLE_STATE_DIR/tokens"
printf 'other-console-token\n' > "$CLAUDE_CONSOLE_STATE_DIR/tokens/8812"
printf 'legacy-token\n' > "$CLAUDE_CONSOLE_STATE_DIR/token"
rm -f "$PNPM_LOG"
run_capture "$repo/bin/claude-ollama" ui --port 8811
check_that "ui hands the server a token file named for its port" grep -qxE -- "TOKEN_FILE: $CLAUDE_CONSOLE_STATE_DIR/tokens/8811" "$PNPM_LOG"
check_that "the port's console token file is owner-only" grep -qxF -- "TOKEN_FILE_MODE: -rw-------" "$PNPM_LOG"
check_that "the tokens folder is owner-only" grep -qxF -- "STATE_MODE: drwx------" "$PNPM_LOG"
check_not "ui removes its port's console token file after it exits" test -e "$CLAUDE_CONSOLE_STATE_DIR/tokens/8811"
check_that "ui leaves another console's token file alone" grep -qxF "other-console-token" "$CLAUDE_CONSOLE_STATE_DIR/tokens/8812"
check_not "ui removes the legacy shared token file" test -e "$CLAUDE_CONSOLE_STATE_DIR/token"
rm -f "$CONSOLE_RUNNING_MARKER" "$PNPM_LOG"
mkdir -p "$CLAUDE_CONSOLE_STATE_DIR/tokens"
printf 'running-token\n' > "$CLAUDE_CONSOLE_STATE_DIR/tokens/9001"
touch "$CONSOLE_RUNNING_MARKER"
run_capture "$repo/bin/claude-ollama" ui --port 9001
check_eq "a second ui exits 0 when a console already answers" 0 "$?"
check_not "a second ui starts no pnpm command" grep -q '^PNPM:' "$PNPM_LOG"
check_that "a second ui keeps the running console's token" grep -qxF "running-token" "$CLAUDE_CONSOLE_STATE_DIR/tokens/9001"
check_that "a second ui prints the running console's tokened link" grep -qF "http://127.0.0.1:9001/?token=running-token" "$sandbox/out"
rm -f "$PNPM_LOG"
run_capture "$repo/bin/claude-ollama" reviews --port 9001
check_eq "a second reviews exits 0 when a console already answers" 0 "$?"
check_that "a second reviews prints the running console's tokened reviews link" grep -qF "http://127.0.0.1:9001/reviews?token=running-token" "$sandbox/out"
rm -f "$CONSOLE_RUNNING_MARKER" "$CLAUDE_CONSOLE_STATE_DIR/tokens/9001"
touch "$CONSOLE_RUNNING_MARKER"
run_capture "$repo/bin/claude-ollama" ui --port 9001
check_eq "a lost token does not stop a second ui" 0 "$?"
check_that "a lost token is replaced by a 48-hex token" grep -qE '^[0-9a-f]{48}$' "$CLAUDE_CONSOLE_STATE_DIR/tokens/9001"
check_that "the replacement token file is owner-only" test -n "$(find "$CLAUDE_CONSOLE_STATE_DIR/tokens/9001" -perm 600)"
check_that "the replacement token is printed" grep -qF "$(cat "$CLAUDE_CONSOLE_STATE_DIR/tokens/9001")" "$sandbox/out"
rm -f "$CONSOLE_RUNNING_MARKER" "$CLAUDE_CONSOLE_STATE_DIR/tokens/9002" "$PNPM_LOG"
STUB_CONSOLE_RACE_LOST=1 run_capture "$repo/bin/claude-ollama" ui --port 9002
check_that "a start that loses the port race keeps the token file the running console reads" test -e "$CLAUDE_CONSOLE_STATE_DIR/tokens/9002"
rm -f "$CONSOLE_RUNNING_MARKER"
run_capture "$repo/bin/claude-ollama" ui --port abc
check_eq "ui rejects a port that is not a number" 2 "$?"
check_that "ui names itself when the port is not a number" grep -qxF "claude-ollama ui: --port needs a number" "$sandbox/err"
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
rm -f "$PNPM_LOG"
touch -t 202001010100 "$web/node_modules/.modules.yaml"
run_capture "$repo/bin/claude-ollama" reviews
check_that "reviews reinstalls when the lockfile is newer than node_modules" grep -qxF -- "PNPM: --dir $web install --frozen-lockfile" "$PNPM_LOG"
rm -f "$sandbox/stubbin/pnpm"
run_capture "$repo/bin/claude-ollama" reviews
check_eq "reviews without pnpm exits 1" 1 "$?"
check_that "reviews without pnpm says how to install it" grep -qxF "claude-ollama: pnpm is required for the reviews page (brew install pnpm)" "$sandbox/err"
unset CLAUDE_OLLAMA_WEB_DIR PR_REVIEW_LOG_DIR CLAUDE_CONSOLE_STATE_DIR PNPM_LOG
run_capture "$repo/bin/claude-ollama" --help
check_that "claude-ollama help lists reviews" grep -qF -- "reviews [--port N]: serve live and past reviews at http://127.0.0.1:8765/" "$sandbox/out"
check_that "claude-ollama help lists ui" grep -qF -- "ui [--port N]: serve the console (runs, health, logs, models, reviews) at http://127.0.0.1:8765/" "$sandbox/out"

new_sandbox /tmp
session_config="$HOME/.claude-ollama"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama runs claude directly, with no sandbox-runtime" grep -q '^ARGS: --settings' "$sandbox/out"
check_that "claude-ollama still passes claude args through" grep -qF -- "--tools Bash,Read,Edit,Write,Skill,TaskStop -p hi" "$sandbox/out"
check_eq "claude-ollama gives the session its own Claude config" "$session_config" "$(cat "$sandbox/config-dir-env")"
check_eq "a new session config skips first-run setup" true "$(jq -r .hasCompletedOnboarding "$session_config/.claude.json")"
check_eq "the session keeps its temp files in its own config" "$session_config/tmp" "$(cat "$sandbox/tmpdir-env")"
check_that "the session temp folder exists" test -d "$session_config/tmp"
session_env() {
  grep -x "$1=.*" "$sandbox/claude-env" | cut -d= -f2-
}
check_eq "the session saves drafts in its own config" "$session_config/drafts" "$(session_env CLAUDE_OLLAMA_DRAFTS_DIR)"
check_eq "the drafts folder is private" 700 "$(stat -f %Lp "$session_config/drafts" 2>/dev/null || stat -c %a "$session_config/drafts")"
draft_opener_args="$(for _ in $(seq 25); do [ -s "$sandbox/opener-args" ] && break; sleep 0.2; done; cat "$sandbox/opener-args" 2>/dev/null)"
check_that "outside cmux each new draft opens with open" contains "$draft_opener_args" "--open /usr/bin/open"
check_that "the opener watches the session's drafts" contains "$draft_opener_args" "--drafts $session_config/drafts"
check_that "the opener reads the console token the session cannot" contains "$draft_opener_args" "--token-file $sandbox/home/.local/share/claude-custom/console/tokens/8765"
check_that "the opener's redirect pages sit where the session cannot read" contains "$draft_opener_args" "--pages $sandbox/home/.local/share/claude-custom/console/open-drafts"
check_that "the opener stops with the launch" contains "$draft_opener_args" "--watch-pid "
cmux_socket="$sandbox/cmux.sock"
/usr/bin/python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$cmux_socket"
cat > "$sandbox/stubbin/cmux" <<'EOF'
#!/bin/sh
case "$*" in
  "browser repl "*)
    echo '"{\"allowed\":[\"localhost\",\"127.0.0.1\",\"[::1]\"]}"'
    echo '[ok | 1ms]'
    ;;
esac
EOF
chmod +x "$sandbox/stubbin/cmux"
run_capture env CMUX_SOCKET_PATH="$cmux_socket" CLAUDE_OLLAMA_CMUX=0 GH_TOKEN=t0ken "$repo/bin/claude-ollama" 27b -p hi
check_eq "the session sees the cmux socket path" "$cmux_socket" "$(session_env CMUX_SOCKET_PATH)"
check_eq "the session sees CLAUDE_OLLAMA_CMUX" 0 "$(session_env CLAUDE_OLLAMA_CMUX)"
check_eq "the session keeps GH_TOKEN for the repo server (the sandbox hides it from Bash)" t0ken "$(session_env GH_TOKEN)"
opener_args() {
  for _ in $(seq 25); do
    [ -s "$sandbox/opener-args" ] && break
    sleep 0.2
  done
  cat "$sandbox/opener-args" 2>/dev/null
}
check_that "inside cmux each new draft opens in a cmux browser split" contains "$(opener_args)" "--cmux "
rm -f "$sandbox/opener-args"
run_capture env CLAUDE_OLLAMA_OPEN_DRAFTS=0 CMUX_SOCKET_PATH="$cmux_socket" "$repo/bin/claude-ollama" 27b -p hi
sleep 1
check_not "CLAUDE_OLLAMA_OPEN_DRAFTS=0 opens no drafts" test -e "$sandbox/opener-args"

mkdir -p "$HOME/.claude"
echo "@preferences" > "$HOME/.claude/CLAUDE.md"
echo '{"hasCompletedOnboarding":true,"theme":"light"}' > "$session_config/.claude.json"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "the session reads a copy of your CLAUDE.md" "@preferences" "$(cat "$session_config/CLAUDE.md")"
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





run_capture "$repo/bin/claude-ollama" doctor 27b
check_that "doctor reports the browser tools" grep -q 'browser tools' "$sandbox/out"
check_not "doctor never mentions sandbox-runtime" grep -q 'sandbox-runtime' "$sandbox/out"

run_capture "$repo/bin/claude-ollama" --help
check_not "help no longer offers github-token" grep -q 'github-token' "$sandbox/out"
check_not "help no longer offers browser-check" grep -q 'browser-check' "$sandbox/out"

run_capture "$repo/bin/claude-ollama" --print-config 27b
check_not "print-config has no sandbox line" grep -q '^sandbox:' "$sandbox/out"
check_that "print-config prints the claude command" grep -qF "command: claude --settings " "$sandbox/out"


write_fetch_list() {
  mkdir -p "$(dirname "$fetch_list")"
  printf '%b' "$1" > "$fetch_list"
}

new_sandbox
fetch_list="$HOME/.config/claude-custom/fetch-domains"
fetch_settings_file="$HOME/.claude-ollama/fetch-settings.json"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "without a fetch list the launch keeps the base tools" grep -qF -- "--tools Bash,Read,Edit,Write,Skill,TaskStop -p hi" "$sandbox/out"
check_that "without a fetch list the launch keeps the profile settings" grep -qF -- "--settings $repo/ollama/settings.27b.json" "$sandbox/out"
check_not "without a fetch list no derived settings are written" test -e "$fetch_settings_file"

new_sandbox
fetch_list="$HOME/.config/claude-custom/fetch-domains"
fetch_settings_file="$HOME/.claude-ollama/fetch-settings.json"
write_fetch_list '  \nlocalhost\n127.0.0.1\n*\nhttps://x.org/\nexample.com:8080\n'
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "a fetch list with only invalid lines keeps the base tools" grep -qF -- "--tools Bash,Read,Edit,Write,Skill,TaskStop -p hi" "$sandbox/out"
check_not "a fetch list with only invalid lines writes no derived settings" test -e "$fetch_settings_file"
check_that "an invalid fetch line says why it is ignored" grep -qxF "claude-ollama: ignoring fetch domain 'localhost' (expected a hostname like docs.python.org)" "$sandbox/err"

new_sandbox
fetch_list="$HOME/.config/claude-custom/fetch-domains"
fetch_settings_file="$HOME/.claude-ollama/fetch-settings.json"
write_fetch_list '  Docs.Python.org \npkg.go.dev\npkg.go.dev\nbad_host\n'
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "a fetch list adds WebFetch to the tools" grep -qF -- "--tools Bash,Read,Edit,Write,Skill,TaskStop,WebFetch -p hi" "$sandbox/out"
check_that "a fetch list passes the derived settings" grep -qF -- "--settings $fetch_settings_file" "$sandbox/out"
check_that "an invalid fetch line is ignored with a message" grep -qxF "claude-ollama: ignoring fetch domain 'bad_host' (expected a hostname like docs.python.org)" "$sandbox/err"
check_eq "a fetch list allows WebFetch for exactly the listed hosts" '["mcp__code-search__semantic_search","mcp__repo","mcp__dev__dev_status","mcp__dev__dev_logs","mcp__dev__dev_errors","mcp__dev__page_check","mcp__dev__page_snapshot","mcp__dev__page_act","WebFetch(domain:docs.python.org)","WebFetch(domain:pkg.go.dev)"]' "$(jq -c .permissions.allow "$fetch_settings_file")"
check_that "the derived settings lift the bare WebFetch deny" jq -e '.permissions.deny | index("WebFetch") == null' "$fetch_settings_file"
check_that "the derived settings keep WebSearch denied" jq -e '.permissions.deny | index("WebSearch") != null' "$fetch_settings_file"
check_eq "the derived settings deny loopback hosts for WebFetch" '["WebFetch(domain:localhost)","WebFetch(domain:127.0.0.1)","WebFetch(domain:0.0.0.0)","WebFetch(domain:[::1])"]' "$(jq -c '[.permissions.deny[] | select(startswith("WebFetch("))]' "$fetch_settings_file")"
check_eq "the derived settings skip Anthropic's WebFetch preflight" true "$(jq .skipWebFetchPreflight "$fetch_settings_file")"
check_eq "the derived settings keep the profile model" "$(jq -r .model "$repo/ollama/settings.27b.json")" "$(jq -r .model "$fetch_settings_file")"
rm -f "$fetch_list"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_not "removing the fetch list removes the derived settings" test -e "$fetch_settings_file"
check_not "removing the fetch list removes WebFetch from the tools" grep -qF WebFetch "$sandbox/out"

new_sandbox
mkdir -p "$sandbox/xdg/claude-custom"
printf 'docs.rs\n' > "$sandbox/xdg/claude-custom/fetch-domains"
run_capture env XDG_CONFIG_HOME="$sandbox/xdg" "$repo/bin/claude-ollama" 27b -p hi
check_that "XDG_CONFIG_HOME moves the fetch list" test -e "$HOME/.claude-ollama/fetch-settings.json"

new_sandbox
fetch_list="$HOME/.config/claude-custom/fetch-domains"
write_fetch_list 'docs.python.org\n'
run_capture "$repo/bin/claude-ollama" --print-config 27b
check_that "print-config lists the fetch domains" grep -qxF "fetch domains: docs.python.org" "$sandbox/out"
check_that "print-config shows WebFetch in the tools" grep -qxF "tools: Bash,Read,Edit,Write,Skill,TaskStop,WebFetch" "$sandbox/out"
rm -f "$fetch_list"
run_capture "$repo/bin/claude-ollama" --print-config 27b
check_that "print-config says when no fetch domains are listed" grep -qxF "fetch domains: none" "$sandbox/out"
check_that "print-config keeps the base tools without a fetch list" grep -qxF "tools: Bash,Read,Edit,Write,Skill,TaskStop" "$sandbox/out"

write_fetch_list 'docs.python.org\n'
run_capture "$repo/bin/claude-ollama" doctor 27b
check_that "doctor says web fetch is on for the listed domains" grep -qxF "ok   web fetch on for: docs.python.org" "$sandbox/out"
rm -f "$fetch_list"
run_capture "$repo/bin/claude-ollama" doctor 27b
check_that "doctor says web fetch is off without a fetch list" grep -qxF "ok   web fetch off (no domains in $fetch_list)" "$sandbox/out"

new_sandbox /tmp
qwen_home="$HOME/.claude-ollama/qwen"
qwen_project="$sandbox/qwen-project"
mkdir -p "$qwen_project" && git -C "$qwen_project" init -q
qwen_return_dir="$(pwd -P)"
cd "$qwen_project" || exit 1
SANDBOX=outer CLAUDE_OLLAMA_SANDBOX_EXEC=/usr/bin/true GH_TOKEN=secret SHORTCUT_API_TOKEN=secret run_capture "$repo/bin/claude-ollama" qwen 27b -p hi
check_eq "claude-ollama qwen exit status" 0 "$?"
check_that "claude-ollama qwen passes the model and args to qwen" grep -qF -- "-m qwen3.8-27b-cc --approval-mode auto-edit" "$sandbox/out"
check_that "claude-ollama qwen passes the MCP servers and the user's args" grep -qF -- 'repo-tools.py"]}' "$sandbox/out"
check_that "and the user's args last" grep -q -- '-p hi$' "$sandbox/out"
check_not "claude-ollama qwen never runs claude" grep -q '^ARGS:' "$sandbox/out"
check_that "claude-ollama qwen warms the model" warm_up_logged
check_eq "claude-ollama qwen gives Qwen Code its own home under the session folder" "QWEN_HOME=$qwen_home" "$(grep '^QWEN_HOME=' "$sandbox/qwen-env")"
check_that "and turns usage statistics off" grep -qx 'QWEN_USAGE_STATISTICS_ENABLED=false' "$sandbox/qwen-env"
check_that "and the models.dev download" grep -qx 'QWEN_CODE_MODELS_DEV_REFRESH=off' "$sandbox/qwen-env"
for folder in skills agents extensions rules commands hooks; do
  check_that "claude-ollama qwen creates $folder under its home before the launch, since Qwen Code's startup mkdir is denied inside the sandbox" test -d "$qwen_home/$folder"
done
launcher_log="$HOME/.local/share/claude-custom/console/launcher.log"
check_that "and the launcher log records the hand-off to qwen" wait_for_launcher_log "claude-ollama: starting qwen"
check_not "an outer OPENAI_API_KEY never reaches the session" grep -q '^OPENAI_API_KEY=' "$sandbox/qwen-env"
check_eq "the rendered settings name the size's model" "qwen3.8-27b-cc qwen3.8-27b-cc" \
  "$(jq -r '[.model.name, .modelProviders.openai[0].id] | join(" ")' "$qwen_home/settings.json")"
check_eq "and point it at Ollama's OpenAI endpoint by address, since the sandbox resolves names only from /etc/hosts" "http://127.0.0.1:11434/v1" "$(jq -r '.modelProviders.openai[0].baseUrl' "$qwen_home/settings.json")"
check_eq "and carry the Modelfile's num_ctx as the context window" 65536 "$(jq -r '.modelProviders.openai[0].generationConfig.contextWindowSize' "$qwen_home/settings.json")"
check_eq "and ask Ollama for no thinking" none "$(jq -r '.modelProviders.openai[0].generationConfig.extra_body.reasoning_effort' "$qwen_home/settings.json")"
check_eq "and turn cross-session messaging off, whose socket the sandbox would refuse" false "$(jq -r '.agents.crossSessionMessaging' "$qwen_home/settings.json")"
check_that "the global QWEN.md starts with the preferences" \
  test "$(head -1 "$qwen_home/QWEN.md")" = "$(head -1 "$repo/shared/preferences/PREFERENCES.md")"
check_that "and carries the Qwen rules" grep -qF 'mcp__code-search__semantic_search answers' "$qwen_home/QWEN.md"
check_that "the rendered settings keep QWEN_SYSTEM_MD out of a project .env" \
  jq -e '.advanced.excludedEnvVars | index("QWEN_SYSTEM_MD")' "$qwen_home/settings.json"
check_that "claude-ollama qwen asks Qwen Code for its Seatbelt sandbox" grep -qx 'QWEN_SANDBOX=sandbox-exec' "$sandbox/qwen-env"
check_that "and names the repo's profile" grep -qx 'SEATBELT_PROFILE=claude-ollama' "$sandbox/qwen-env"
check_not "and never hands Qwen Code an outer SANDBOX, which would turn its sandbox off" grep -q '^SANDBOX=' "$sandbox/qwen-env"
check_that "claude-ollama qwen installs the profile where Qwen Code looks for it" \
  cmp -s "$repo/ollama/qwen-sandbox.sb" "$qwen_project/.qwen/sandbox-macos-claude-ollama.sb"
check_that "and keeps it out of the project's git status" grep -qxF '/.qwen/sandbox-macos-claude-ollama.sb' "$qwen_project/.git/info/exclude"
check_that "claude-ollama qwen says it runs in Seatbelt" grep -qF "qwen runs in macOS Seatbelt (profile claude-ollama)" "$sandbox/err"
check_not "an outer GH_TOKEN never reaches Qwen Code" grep -q '^GH_TOKEN=' "$sandbox/qwen-env"
check_not "an outer SHORTCUT_API_TOKEN never reaches Qwen Code" grep -q '^SHORTCUT_API_TOKEN=' "$sandbox/qwen-env"

OPENAI_API_KEY=outer run_capture "$repo/bin/claude-ollama" qwen 35b -p hi
check_that "claude-ollama qwen 35b uses the 35b model" grep -qF -- "-m qwen3.6-35b-cc" "$sandbox/out"
check_eq "and its context window" 98304 "$(jq -r '.modelProviders.openai[0].generationConfig.contextWindowSize' "$qwen_home/settings.json")"
check_not "an outer OPENAI_API_KEY is dropped" grep -q '^OPENAI_API_KEY=' "$sandbox/qwen-env"

run_capture "$repo/bin/claude-ollama" qwen -p hi </dev/null
check_that "claude-ollama qwen without a size uses the default" grep -qF -- "-m qwen3.8-27b-cc" "$sandbox/out"

CLAUDE_OLLAMA_SANDBOX_EXEC=/nonexistent/sandbox-exec run_capture "$repo/bin/claude-ollama" qwen 27b -p hi
check_that "claude-ollama qwen without sandbox-exec says its commands run as you" grep -qF "qwen runs without a sandbox: its commands run as you (sandbox-exec not found)" "$sandbox/err"
check_not "and sets no QWEN_SANDBOX" grep -q '^QWEN_SANDBOX=' "$sandbox/qwen-env"
check_that "and still names the program" grep -qxF "claude-ollama: starting qwen" "$sandbox/err"

run_capture "$repo/bin/claude-ollama" qwen --print-config 35b
check_eq "qwen print-config exit status" 0 "$?"
check_not "qwen print-config does not launch qwen" grep -q '^QWEN ARGS:' "$sandbox/out"
check_that "qwen print-config names the harness" grep -qxF "harness: qwen" "$sandbox/out"
check_that "qwen print-config shows the model" grep -qxF "model: qwen3.6-35b-cc" "$sandbox/out"
check_that "qwen print-config shows the context window" grep -qxF "context window: 98304" "$sandbox/out"
check_that "print-config names the Qwen sandbox" grep -q '^sandbox: ' "$sandbox/out"

QWEN_DOCTOR_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=2"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$QWEN_DOCTOR_ENV" run_capture "$repo/bin/claude-ollama" qwen doctor 27b
check_eq "claude-ollama qwen doctor exit status" 0 "$?"
check_that "qwen doctor reports qwen on PATH" grep -q '^ok   qwen on PATH' "$sandbox/out"
check_that "qwen doctor reports the main model" grep -qxF "ok   model qwen3.8-27b-cc" "$sandbox/out"
check_that "qwen doctor reports the settings template parses" grep -qxF "ok   qwen settings template parses" "$sandbox/out"
check_that "qwen doctor warns that no hooks are wired" grep -qxF "warn qwen hooks: none wired (docs/ollama.md)" "$sandbox/out"
check_not "qwen doctor skips the Claude hook check" grep -q '^ok   hook ' "$sandbox/out"
check_not "qwen doctor skips the Claude model allowlist check" grep -q 'availableModels' "$sandbox/out"
check_not "qwen doctor never launches qwen" grep -q '^QWEN ARGS:' "$sandbox/out"
check_not "qwen doctor never launches claude" grep -q '^ARGS:' "$sandbox/out"
check_that "qwen doctor reports the sandbox" grep -q 'qwen sandbox: ' "$sandbox/out"
mv "$sandbox/stubbin/qwen" "$sandbox/stubbin/qwen.off"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$QWEN_DOCTOR_ENV" run_capture "$repo/bin/claude-ollama" qwen doctor 27b
check_eq "qwen doctor without qwen exit status" 1 "$?"
check_that "qwen doctor fails a missing qwen" grep -q '^fail qwen missing' "$sandbox/out"
mv "$sandbox/stubbin/qwen.off" "$sandbox/stubbin/qwen"

rm -f "$sandbox/stubbin/qwen"
run_capture "$repo/bin/claude-ollama" qwen 27b -p hi
check_eq "claude-ollama qwen without qwen exits 1" 1 "$?"
check_that "and says how to install it" grep -qxF "claude-ollama: qwen is missing (brew install qwen-code)" "$sandbox/err"
check_not "and pulls no model first" grep -sqE '^(pull|create) ' "$sandbox/ollama.log"
cd "$qwen_return_dir" || exit 1

run_capture "$repo/bin/claude-ollama" --help
check_that "claude-ollama help lists qwen" grep -qF -- "qwen [size] [qwen args...]: launch Qwen Code" "$sandbox/out"
check_that "claude-ollama help lists qwen doctor" grep -qF -- "qwen doctor [size]: check qwen" "$sandbox/out"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
