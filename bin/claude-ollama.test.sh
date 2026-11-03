#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
installer="$repo/bin/claude-custom"
real_python3="$(command -v python3)"
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

record_installed_parameters() {
  local size model
  mkdir -p "$sandbox/parameters"
  jq -r 'to_entries[] | "\(.key) \(.value.model)"' "$repo/ollama/sizes.json" \
    | while read -r size model; do sed -n 's/^PARAMETER //p' "$repo/ollama/Modelfile.$size" > "$sandbox/parameters/$model"; done
}

pinned_tags() {
  jq '{models: [to_entries[] | {name: .key, digest: .value}]}' "$repo/ollama/model-digests.json"
}

new_sandbox() {
  sandbox="$(made="$(mktemp -d "${1:-${TMPDIR:-/tmp}}/claude-ollama-test.XXXXXX")" && cd "$made" && pwd -P)" || exit 1
  sandboxes="$sandboxes $sandbox"
  export HOME="$sandbox/home"
  mkdir -p "$HOME" "$sandbox/stubbin"
  unset NVM_DIR ZDOTDIR XDG_CONFIG_HOME CLAUDE_CONFIG_DIRSTUB_OLLAMA_SHOW_EXIT STUB_OLLAMA_PULL_EXIT
  unset STUB_OLLAMA_PID STUB_OLLAMA_ENV STUB_CURL_EXIT STUB_OLLAMA_NUM_CTX STUB_AGENT_EXIT CMUX_SOCKET_PATH CLAUDE_OLLAMA_CMUX
  unset STUB_SHASUM_DIGEST STUB_INSPECT_EXIT STUB_CLAUDE_STDERR CLAUDE_CONSOLE_STATE_DIR
  unset CLAUDE_TOOL_TELEMETRY CLAUDE_OLLAMA_TELEMETRY STUB_CLAUDE_RELAUNCH_ONCE STUB_CLAUDE_RELAUNCH_PROMPT STUB_CLAUDE_EXIT CLAUDE_OLLAMA_RELAUNCH
  unset STUB_CLAUDE_LADDER_ONCE STUB_CLAUDE_EMBED_OFF STUB_CLAUDE_SLEEP CLAUDE_OLLAMA_LEASE CLAUDE_OLLAMA_LADDER CLAUDE_OLLAMA_LEASE_HEARTBEAT
  unset STUB_CLAUDE_LADDER_UP STUB_CLAUDE_LADDER_UP_AFTER_LADDER STUB_CLAUDE_LADDER_UP_NO_HANDOFF STUB_MEMSIZE CLAUDE_OLLAMA_FIT
  export CLAUDE_OLLAMA_MEMINFO="$sandbox/no-meminfo"
  export SHELL=/bin/zsh
  record_installed_parameters
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
echo "\$\$" > "$sandbox/claude-pid"
echo "\$PPID" > "$sandbox/claude-ppid"
echo "\${CLAUDE_OLLAMA_RELAUNCH_DIR-unset}" > "$sandbox/relaunch-dir-env"
for arg; do echo "ARG: \$arg"; done
previous_arg=
for arg; do
  [ "\$previous_arg" != --settings ] || cp "\$arg" "$sandbox/settings-seen" 2>/dev/null || true
  [ "\$previous_arg" != --settings ] || stat -f '%Lp' "\$arg" > "$sandbox/settings-seen-mode" 2>/dev/null || stat -c '%a' "\$arg" > "$sandbox/settings-seen-mode" 2>/dev/null || true
  previous_arg=\$arg
done
if [ -n "\${CLAUDE_OLLAMA_RELAUNCH_DIR:-}" ]; then
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ "\$(cat "\$CLAUDE_OLLAMA_RELAUNCH_DIR/claude.pid" 2>/dev/null)" = "\$\$" ] && break; sleep 0.1; done
  cat "\$CLAUDE_OLLAMA_RELAUNCH_DIR/claude.pid" > "$sandbox/pid-file-seen" 2>/dev/null
fi
for lease_file in "$HOME/.claude-ollama/lease"/*.json; do [ -f "\$lease_file" ] && jq -c . "\$lease_file" >> "$sandbox/lease-seen"; done
[ -n "\${STUB_CLAUDE_SLEEP:-}" ] && sleep "\$STUB_CLAUDE_SLEEP"
ls "\${CLAUDE_OLLAMA_RELAUNCH_DIR:-/nonexistent}" 2>/dev/null | tr '\n' ' ' >> "$sandbox/relaunch-entries"
echo >> "$sandbox/relaunch-entries"
if [ -n "\${STUB_CLAUDE_LADDER_UP:-}" ] && [ ! -e "$sandbox/laddered-up" ] && { [ -z "\${STUB_CLAUDE_LADDER_UP_AFTER_LADDER:-}" ] || [ -e "$sandbox/laddered" ]; }; then
  : > "$sandbox/laddered-up"
  "$real_python3" "$repo/shared/relaunch_dir.py" request ladder-up "\$(jq -cn --arg rung "\$STUB_CLAUDE_LADDER_UP" '{rung: \$rung, reason: "20 minutes without an incident and the memory fits"}')"
  [ -n "\${STUB_CLAUDE_LADDER_UP_NO_HANDOFF:-}" ] || "$real_python3" "$repo/shared/relaunch_dir.py" request relaunch '{"note": "note.md", "prompt": "go on", "percent": 71}'
fi
if [ -n "\${STUB_CLAUDE_LADDER_ONCE:-}" ] && [ ! -e "$sandbox/laddered" ]; then
  : > "$sandbox/laddered"
  [ -z "\${STUB_CLAUDE_EMBED_OFF:-}" ] || "$real_python3" "$repo/shared/relaunch_dir.py" raise embed-off
  "$real_python3" "$repo/shared/relaunch_dir.py" request ladder '{"rung": "context-down", "context": 32768, "reason": "3 truncated prompts within 10 minutes"}'
fi
if [ -n "\${STUB_CLAUDE_LADDER_MALFORMED:-}" ] && [ ! -e "$sandbox/laddered-malformed" ]; then
  : > "$sandbox/laddered-malformed"
  echo '{}' > "\$CLAUDE_OLLAMA_RELAUNCH_DIR/ladder"
fi
if [ -n "\${STUB_CLAUDE_RELAUNCH_ONCE:-}" ] && [ ! -e "$sandbox/relaunched" ]; then
  : > "$sandbox/relaunched"
  "$real_python3" "$repo/shared/relaunch_dir.py" request relaunch "\$(jq -cn --arg prompt "\${STUB_CLAUDE_RELAUNCH_PROMPT:-}" '{note: "note.md", prompt: \$prompt, percent: 71}')"
fi
[ -n "\${STUB_CLAUDE_STDERR:-}" ] && echo "\$STUB_CLAUDE_STDERR" >&2
exit "\${STUB_CLAUDE_EXIT:-0}"
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
  if [ "\$3" = --parameters ]; then
    { cat "$sandbox/parameters/\$2" 2>/dev/null || echo "num_ctx 98304"; } \\
      | awk -v ctx="\$STUB_OLLAMA_NUM_CTX" -v temperature="\$STUB_OLLAMA_TEMPERATURE" \\
        '\$1 == "num_ctx" && ctx { \$2 = ctx } \$1 == "temperature" && temperature { \$2 = temperature } { print }'
  fi
  if [ "\$3" = --verbose ]; then cat "$sandbox/show-verbose" 2>/dev/null; fi
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
case "\$1" in
  */shared/relaunch_dir.py|*/ollama/incidents/incident_log.py) exec "$real_python3" "\$@" ;;
esac
echo "\$*" >> "$sandbox/python.log"
echo "\${CODE_SEARCH_EMBED-unset}" > "$sandbox/indexer-embed-env"
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
  cat > "$sandbox/stubbin/incident-watcher" <<EOF
#!/bin/sh
if [ "\$1" = --check-rules ]; then echo ok; exit 0; fi
printf '%s\n' "\$*" > "$sandbox/watcher-args"
EOF
  chmod +x "$sandbox/stubbin/incident-watcher"
  export CLAUDE_OLLAMA_INCIDENT_WATCHER="$sandbox/stubbin/incident-watcher"
  unset CLAUDE_OLLAMA_INCIDENTS CLAUDE_OLLAMA_INCIDENTS_FILE
  cat > "$sandbox/stubbin/messages-proxy" <<EOF
#!/bin/sh
printf '%s\n' "\$*" > "$sandbox/proxy-args"
while [ \$# -gt 0 ]; do
  [ "\$1" = --port-file ] && echo "\${STUB_PROXY_PORT:-48000}" > "\$2"
  shift
done
EOF
  chmod +x "$sandbox/stubbin/messages-proxy"
  export CLAUDE_OLLAMA_PROXY_BIN="$sandbox/stubbin/messages-proxy"
  export CLAUDE_OLLAMA_PROXY=0
  unset STUB_PROXY_PORT
  cat > "$sandbox/stubbin/ladder" <<EOF
#!/bin/sh
printf '%s\n' "\$*" > "$sandbox/ladder-args"
EOF
  chmod +x "$sandbox/stubbin/ladder"
  export CLAUDE_OLLAMA_LADDER_BIN="$sandbox/stubbin/ladder"
  export CLAUDE_OLLAMA_BEACON=0
}

file_mode() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

wait_for_file() {
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
    [ -s "$1" ] && return 0
    sleep 0.2
  done
  return 1
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
check_eq "claude-ollama keeps tool telemetry off by default" unset "$(cat "$sandbox/telemetry-env")"
run_capture env CLAUDE_OLLAMA_TELEMETRY=1 "$repo/bin/claude-ollama" 27b -p hi
check_eq "CLAUDE_OLLAMA_TELEMETRY=1 records tool telemetry under the session folder" "$HOME/.claude-ollama/telemetry/tool-calls.jsonl" "$(cat "$sandbox/telemetry-env")"
run_capture env CLAUDE_OLLAMA_TELEMETRY=0 "$repo/bin/claude-ollama" 27b -p hi
check_eq "CLAUDE_OLLAMA_TELEMETRY=0 turns tool telemetry off" unset "$(cat "$sandbox/telemetry-env")"
run_capture env CLAUDE_TOOL_TELEMETRY="$sandbox/mine.jsonl" "$repo/bin/claude-ollama" 27b -p hi
check_eq "CLAUDE_TOOL_TELEMETRY alone does not turn tool telemetry on" unset "$(cat "$sandbox/telemetry-env")"
run_capture env CLAUDE_OLLAMA_TELEMETRY=1 CLAUDE_TOOL_TELEMETRY="$sandbox/mine.jsonl" "$repo/bin/claude-ollama" 27b -p hi
check_eq "CLAUDE_TOOL_TELEMETRY overrides the telemetry file" "$sandbox/mine.jsonl" "$(cat "$sandbox/telemetry-env")"
check_eq "every launch points the package caches at the sandbox cache folder" "$HOME/.cache/claude-sandbox/go/mod" \
  "$(grep '^GOMODCACHE=' "$sandbox/claude-env" | cut -d= -f2-)"
check_eq "and names that folder in CLAUDE_SANDBOX_CACHE_DIR" "$HOME/.cache/claude-sandbox" \
  "$(grep '^CLAUDE_SANDBOX_CACHE_DIR=' "$sandbox/claude-env" | cut -d= -f2-)"
telemetry_dir="$HOME/.claude-ollama/telemetry"
mkdir -p "$telemetry_dir"
head -c 1048577 /dev/zero > "$telemetry_dir/tool-calls.jsonl"
run_capture env CLAUDE_OLLAMA_TELEMETRY=1 "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama rotates a telemetry file past 1 MiB" test -f "$telemetry_dir/tool-calls.jsonl.1"
new_sandbox
mkdir -p "$HOME/.claude-ollama" "$sandbox/elsewhere"
ln -s "$sandbox/elsewhere" "$HOME/.claude-ollama/telemetry"
run_capture env CLAUDE_OLLAMA_TELEMETRY=1 "$repo/bin/claude-ollama" 27b -p hi
check_eq "a symlinked telemetry folder turns telemetry off" unset "$(cat "$sandbox/telemetry-env")"
check_that "a symlinked telemetry folder is reported" grep -qF "claude-ollama: telemetry: $HOME/.claude-ollama/telemetry is a symlink or not a regular file; telemetry off" "$sandbox/err"
new_sandbox
mkdir -p "$HOME/.claude-ollama/telemetry" "$sandbox/elsewhere"
ln -s "$sandbox/elsewhere/tool-calls.jsonl" "$HOME/.claude-ollama/telemetry/tool-calls.jsonl"
run_capture env CLAUDE_OLLAMA_TELEMETRY=1 "$repo/bin/claude-ollama" 27b -p hi
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
check_that "claude-ollama starts the code-search, repo and dev MCP servers" grep -qF -- "--strict-mcp-config --mcp-config {\"mcpServers\":{\"code-search\":{\"command\":\"$repo/shared/host-env\",\"args\":[\"python3\",\"$repo/shared/mcp/code-search.py\"]},\"repo\":{\"command\":\"$repo/shared/host-env\",\"args\":[\"python3\",\"$repo/shared/mcp/repo-tools.py\"]},\"dev\":{\"command\":\"$repo/shared/host-env\",\"args\":[\"python3\",\"$repo/shared/mcp/dev-server.py\"]}}}" "$sandbox/out"
rm -f "$sandbox/python.log"
run_capture "$repo/bin/claude-ollama" 35b -p hi
sleep 1
check_that "claude-ollama starts the indexer tied to its own process" grep -qxE "$repo/shared/mcp/code-search.py --index --watch-pid [0-9]+" "$sandbox/python.log"
check_that "claude-ollama launches without waiting for the indexer" grep -q '^ARGS:' "$sandbox/out"
rm -f "$sandbox/python.log"
run_capture env CLAUDE_OLLAMA_NO_INDEX=1 "$repo/bin/claude-ollama" 35b -p hi
check_not "CLAUDE_OLLAMA_NO_INDEX skips the indexer" test -e "$sandbox/python.log"
new_sandbox
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=2 OLLAMA_NUM_PARALLEL=1" run_capture "$repo/bin/claude-ollama" 27b -p hi
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
check_that "claude-ollama says it recreates the model" grep -qF "recreating qwen3.8-27b-cc with num_ctx 65536 num_predict 8192 temperature 0.7 top_k 20 top_p 0.8" "$sandbox/err"
check_that "claude-ollama launches after recreating" grep -qF -- "--model qwen3.8-27b-cc --tools" "$sandbox/out"
new_sandbox
STUB_OLLAMA_TEMPERATURE=1 run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama recreates a model with a stale sampling parameter" grep -qE '^create qwen3.8-27b-cc -f ' "$sandbox/ollama.log"
check_that "the recreated model gets every profile parameter" grep -qxF "modelfile: PARAMETER temperature 0.7" "$sandbox/ollama.log"
check_that "the recreated model keeps the profile num_ctx" grep -qxF "modelfile: PARAMETER num_ctx 65536" "$sandbox/ollama.log"
new_sandbox
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_not "claude-ollama leaves a model whose parameters match alone" grep -q '^create ' "$sandbox/ollama.log"

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
ctx7_home="$HOME/.cache/claude-custom/ctx7"
mkdir -p "$ctx7_home/node_modules/.bin" "$ctx7_home/node_modules/ctx7"
printf '{"version":"0.8.2"}\n' > "$ctx7_home/node_modules/ctx7/package.json"
cp "$sandbox/repo/shared/ctx7/package-lock.json" "$ctx7_home/package-lock.json"
cat > "$ctx7_home/node_modules/.bin/ctx7" <<EOF
#!/bin/sh
printf '%s\n' "\$*" > "$sandbox/ctx7-args"
pwd > "$sandbox/ctx7-cwd"
env | sort > "$sandbox/ctx7-env"
seq 1 100
EOF
chmod +x "$ctx7_home/node_modules/.bin/ctx7"
run_capture env NODE_AUTH_TOKEN=secret-npm NPM_TOKEN=secret-npm2 GH_TOKEN=secret-gh GITHUB_TOKEN=secret-gh2 ANTHROPIC_API_KEY=secret-anthropic HTTPS_PROXY=http://proxy.example.test:3128 NO_PROXY=localhost CONTEXT7_API_KEY=ctx7-key-fixture SSL_CERT_FILE=/etc/certs.pem NODE_EXTRA_CA_CERTS=/etc/extra.pem "$sandbox/repo/bin/claude-custom" ctx7 library next "server actions"
check_eq "claude-custom ctx7 passes the lookup arguments to the installed CLI" "library next server actions" "$(cat "$sandbox/ctx7-args")"
check_eq "claude-custom ctx7 runs inside the install folder" "$ctx7_home" "$(cat "$sandbox/ctx7-cwd")"
check_eq "claude-custom ctx7 prints at most 80 lines" 80 "$(wc -l < "$sandbox/out" | tr -d ' ')"
check_eq "claude-custom ctx7 hands the CLI exactly the allowlisted variables it was given" 7 \
  "$(grep -c '^\(PATH\|HOME\|HTTPS_PROXY\|NO_PROXY\|CONTEXT7_API_KEY\|SSL_CERT_FILE\|NODE_EXTRA_CA_CERTS\)=' "$sandbox/ctx7-env")"
for credential in NODE_AUTH_TOKEN NPM_TOKEN GH_TOKEN GITHUB_TOKEN ANTHROPIC_API_KEY; do
  check_not "claude-custom ctx7 keeps $credential out of the CLI's environment" grep -q "^$credential=" "$sandbox/ctx7-env"
done
check_not "no secret value reaches the CLI" grep -qE 'secret-(npm|npm2|gh|gh2|anthropic)' "$sandbox/ctx7-env"
check_eq "the CLI keeps the real HOME" "$HOME" "$(sed -n 's/^HOME=//p' "$sandbox/ctx7-env")"
run_capture "$sandbox/repo/bin/claude-custom" ctx7 docs /vercel/next.js "app router" --language en
check_eq "claude-custom ctx7 passes the docs arguments through" "docs /vercel/next.js app router --language en" "$(cat "$sandbox/ctx7-args")"
rm -f "$sandbox/ctx7-args"
run_capture "$sandbox/repo/bin/claude-custom" ctx7 login
check_eq "claude-custom ctx7 refuses every other ctx7 command" 2 "$?"
check_that "claude-custom ctx7 names the two lookups it runs" grep -qF "claude-custom ctx7 library NAME QUERY" "$sandbox/err"
check_not "a refused ctx7 command never reaches the CLI" test -e "$sandbox/ctx7-args"
mkdir -p "$sandbox/empty-home"
HOME="$sandbox/empty-home" run_capture "$sandbox/repo/bin/claude-custom" ctx7 library react hooks
check_eq "claude-custom ctx7 without an install exits 1" 1 "$?"
check_eq "claude-custom ctx7 without an install says how to install" \
  "claude-custom ctx7: the Context7 CLI is not installed; run: claude-custom install" "$(cat "$sandbox/err")"
check_eq "claude-custom ctx7 without an install fetches nothing" 0 "$(find "$sandbox/empty-home" -name node_modules | wc -l | tr -d ' ')"
cat > "$ctx7_home/node_modules/.bin/ctx7" <<EOF
#!/bin/sh
echo "fetching"
echo "Error: request failed" >&2
echo "GET https://deploy:s3cret-token@api.example.test/v1" >&2
echo "authorization: Bearer eyJhbGciOiJIUzI1NiJ9.fixture" >&2
echo "ghp_fixture0123456 in the log" >&2
exit 1
EOF
chmod +x "$ctx7_home/node_modules/.bin/ctx7"
run_capture "$sandbox/repo/bin/claude-custom" ctx7 library next "server actions"
check_eq "a failing CLI keeps its exit status" 1 "$?"
check_eq "a failing CLI still prints what it wrote" "fetching" "$(cat "$sandbox/out")"
check_that "a failing CLI keeps its own error line" grep -qF "Error: request failed" "$sandbox/err"
check_that "the CLI's URL loses its user and token" grep -qF "GET https://api.example.test/v1" "$sandbox/err"
check_that "a bearer header in the CLI's output is masked" grep -qF "Bearer <redacted>" "$sandbox/err"
check_that "a GitHub token in the CLI's output is masked" grep -qF "<redacted> in the log" "$sandbox/err"
for secret in s3cret-token eyJhbGciOiJIUzI1NiJ9 ghp_fixture0123456; do
  check_not "no secret from the CLI's output reaches the model: $secret" grep -qF "$secret" "$sandbox/err"
done
check_not "a failing CLI never mentions npm" grep -qi npm "$sandbox/err"
cat > "$ctx7_home/node_modules/.bin/ctx7" <<EOF
#!/bin/sh
exit 3
EOF
chmod +x "$ctx7_home/node_modules/.bin/ctx7"
run_capture "$sandbox/repo/bin/claude-custom" ctx7 library next "server actions"
check_eq "claude-custom ctx7 keeps the CLI's exit status" 3 "$?"
check_not "the wrapper never runs npx" grep -q 'npx' "$sandbox/repo/bin/claude-custom"
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
check_that "print-config shows output tokens" grep -qxF "max output tokens: 8192" "$sandbox/out"
check_that "print-config shows where Claude Code compacts" grep -qxF "compacts at: 77112 tokens" "$sandbox/out"
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
cat > "$sandbox/stubbin/mock-spike" <<EOF
#!/bin/sh
echo "SPIKE: \$*"
EOF
chmod +x "$sandbox/stubbin/mock-spike"
export CLAUDE_OLLAMA_MOCK_SPIKE="$sandbox/stubbin/mock-spike"
run_capture "$repo/bin/claude-ollama" mock-spike 27b --runs 2 </dev/null
check_eq "mock-spike exit status" 0 "$?"
check_that "mock-spike runs the spike with the size's model and server" \
  grep -qxF "SPIKE: --model qwen3.8-27b-cc --base-url http://127.0.0.1:11434 --runs 2" "$sandbox/out"
unset CLAUDE_OLLAMA_MOCK_SPIKE
cat > "$sandbox/stubbin/task-eval" <<EOF
#!/bin/sh
echo "TASKS: \$*"
EOF
chmod +x "$sandbox/stubbin/task-eval"
export CLAUDE_OLLAMA_TASK_EVAL="$sandbox/stubbin/task-eval"
: > "$sandbox/curl.log"
run_capture "$repo/bin/claude-ollama" task-eval 27b --runs 2 --task shell-fix </dev/null
check_eq "task-eval exit status" 0 "$?"
check_that "task-eval runs the eval with the size and this launcher" \
  grep -qxF "TASKS: 27b --launcher $repo/bin/claude-ollama --runs 2 --task shell-fix" "$sandbox/out"
check_that "task-eval warms the model" warm_up_logged
check_not "task-eval does not launch claude itself" grep -q '^ARGS:' "$sandbox/out"
run_capture "$repo/bin/claude-ollama" task-eval --json </dev/null
check_that "task-eval without a size uses the default" grep -qxF "TASKS: 27b --launcher $repo/bin/claude-ollama --json" "$sandbox/out"
unset CLAUDE_OLLAMA_TASK_EVAL
cat > "$sandbox/stubbin/prefix-ab" <<EOF
#!/bin/sh
echo "AB: \$*"
EOF
chmod +x "$sandbox/stubbin/prefix-ab"
rm -f "$sandbox/proxy-args"
CLAUDE_OLLAMA_PREFIX_AB="$sandbox/stubbin/prefix-ab" run_capture "$repo/bin/claude-ollama" prefix-ab 27b --limit 3 </dev/null
check_eq "prefix-ab exit status" 0 "$?"
check_that "prefix-ab replays the session record dir with the size's model and server" \
  grep -qxF "AB: --record $HOME/.claude-ollama/proxy/record --model qwen3.8-27b-cc --base-url http://127.0.0.1:11434 --limit 3" "$sandbox/out"
check_not "prefix-ab does not launch claude" grep -q '^ARGS:' "$sandbox/out"
check_not "prefix-ab does not start the proxy" test -e "$sandbox/proxy-args"
CLAUDE_OLLAMA_PREFIX_AB="$sandbox/stubbin/prefix-ab" run_capture "$repo/bin/claude-ollama" prefix-ab </dev/null
check_that "prefix-ab without a size uses the default" grep -q 'AB: --record .* --model qwen3.8-27b-cc ' "$sandbox/out"
unset CLAUDE_OLLAMA_REVIEWER
run_capture "$repo/bin/claude-ollama" --help
check_that "claude-ollama help lists logs" grep -q '^logs \[-n LINES|--path\]: ' "$sandbox/out"
check_that "claude-ollama help lists task-eval" grep -q '^task-eval \[size\] \[--task NAME\]... \[--runs N\] \[--json\]: ' "$sandbox/out"

new_sandbox
healthy_server_env="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=2 OLLAMA_NUM_PARALLEL=1"
cat > "$sandbox/stubbin/doctor" <<'EOF'
#!/bin/sh
echo "DOCTOR: $*"
exit "${STUB_DOCTOR_EXIT:-0}"
EOF
chmod +x "$sandbox/stubbin/doctor"
STUB_DOCTOR_EXIT=1 run_capture env CLAUDE_OLLAMA_DOCTOR_BIN="$sandbox/stubbin/doctor" "$repo/bin/claude-ollama" doctor 27b
check_eq "claude-ollama doctor exits with the doctor's status" 1 "$?"
check_that "claude-ollama doctor runs bin/claude-ollama-doctor with the size" grep -qxF "DOCTOR: 27b" "$sandbox/out"
check_not "doctor does not launch claude" grep -q '^ARGS:' "$sandbox/out"
check_not "doctor does not pull or create" grep -sqE '^(pull|create) ' "$sandbox/ollama.log"
check_not "doctor does not apply server.env" grep -sqxF -- "-apply" "$sandbox/agent.log"
run_capture env CLAUDE_OLLAMA_DOCTOR_BIN="$sandbox/stubbin/doctor" "$repo/bin/claude-ollama" doctor </dev/null
check_that "claude-ollama doctor without a size uses the default" grep -qxF "DOCTOR: 27b" "$sandbox/out"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_server_env" run_capture "$repo/bin/claude-ollama" doctor 35b
check_that "claude-ollama doctor runs the real doctor by default" grep -qxF "ok   model qwen3.6-35b-cc" "$sandbox/out"

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

full_server_env="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=2 OLLAMA_NUM_PARALLEL=1"
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
check_that "ui gives the console no telemetry file by default" grep -qxF -- "TELEMETRY: unset" "$PNPM_LOG"
rm -f "$PNPM_LOG"
run_capture env CLAUDE_OLLAMA_TELEMETRY=1 "$repo/bin/claude-ollama" ui --port 9000
check_that "ui hands the console the default telemetry file when telemetry is on" grep -qxF -- "TELEMETRY: $HOME/.claude-ollama/telemetry/tool-calls.jsonl" "$PNPM_LOG"
mkdir -p "$HOME/.claude-ollama" "$sandbox/moved-telemetry"
rm -rf "$HOME/.claude-ollama/telemetry"
ln -s "$sandbox/moved-telemetry" "$HOME/.claude-ollama/telemetry"
rm -f "$PNPM_LOG"
run_capture env CLAUDE_OLLAMA_TELEMETRY=1 "$repo/bin/claude-ollama" ui --port 9000
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
mkdir -p "$HOME/.ollama/logs"
: > "$HOME/.ollama/logs/server.log"
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
check_eq "the drafts folder is private" 700 "$(stat -c %a "$session_config/drafts" 2>/dev/null || stat -f %Lp "$session_config/drafts")"
draft_opener_args="$(for _ in $(seq 25); do [ -s "$sandbox/opener-args" ] && break; sleep 0.2; done; cat "$sandbox/opener-args" 2>/dev/null)"
check_that "outside cmux each new draft opens with open" contains "$draft_opener_args" "--open /usr/bin/open"
check_that "the opener watches the session's drafts" contains "$draft_opener_args" "--drafts $session_config/drafts"
check_that "the opener reads the console token the session cannot" contains "$draft_opener_args" "--token-file $sandbox/home/.local/share/claude-custom/console/tokens/8765"
check_that "the opener's redirect pages sit where the session cannot read" contains "$draft_opener_args" "--pages $sandbox/home/.local/share/claude-custom/console/open-drafts"
check_that "the opener stops with the launch" contains "$draft_opener_args" "--watch-pid "
incidents_dir="$sandbox/home/.local/share/claude-custom/console/incidents"
incident_watcher_args="$(for _ in $(seq 25); do [ -s "$sandbox/watcher-args" ] && break; sleep 0.2; done; cat "$sandbox/watcher-args" 2>/dev/null)"
check_that "the incident watcher follows the Ollama server log" contains "$incident_watcher_args" "--log "
check_that "the incident watcher knows the session's model" contains "$incident_watcher_args" "--model $(jq -r .model "$repo/ollama/settings.27b.json")"
check_that "the incident watcher scans the session's transcripts for compactions" contains "$incident_watcher_args" "--transcripts $session_config/projects"
check_that "the incident watcher stops with the launch" contains "$incident_watcher_args" "--watch-pid "
check_that "the incident watcher writes a per-session file in the console state" contains "$incident_watcher_args" "--out $incidents_dir/"
check_eq "incidents/current names the session's incidents file" "$(cat "$incidents_dir/current")" "$(sed -n 's/.*--out \([^ ]*\).*/\1/p' "$sandbox/watcher-args")"
check_eq "the session is told where its incidents are" "$(cat "$incidents_dir/current")" "$(session_env CLAUDE_OLLAMA_INCIDENTS_FILE)"
check_eq "the incidents folder is private" 700 "$(stat -c %a "$incidents_dir" 2>/dev/null || stat -f %Lp "$incidents_dir")"
rm -f "$sandbox/watcher-args"
run_capture env CLAUDE_OLLAMA_INCIDENTS=0 "$repo/bin/claude-ollama" 27b -p hi
sleep 1
check_not "CLAUDE_OLLAMA_INCIDENTS=0 starts no watcher" test -e "$sandbox/watcher-args"
check_eq "and the session gets no incidents file" "" "$(session_env CLAUDE_OLLAMA_INCIDENTS_FILE)"
launch_base_url() {
  jq -r .env.ANTHROPIC_BASE_URL "$sandbox/settings-seen"
}
run_capture env -u CLAUDE_OLLAMA_PROXY "$repo/bin/claude-ollama" 27b -p hi
proxy_args="$(cat "$sandbox/proxy-args" 2>/dev/null)"
check_that "the messages proxy forwards to the profile's Ollama URL" contains "$proxy_args" "--upstream $(jq -r .env.ANTHROPIC_BASE_URL "$repo/ollama/settings.27b.json")"
check_that "the messages proxy picks a free loopback port" contains "$proxy_args" "--port 0 "
check_that "the messages proxy publishes its port" contains "$proxy_args" "--port-file $session_config/proxy.port"
check_that "the messages proxy logs under the default console state dir" contains "$proxy_args" "--log $HOME/.local/share/claude-custom/console/proxy/requests.jsonl"
check_that "the messages proxy stops with the launch" contains "$proxy_args" "--watch-pid "
check_eq "claude is pointed at the proxy" "http://127.0.0.1:48000" "$(launch_base_url)"
rm -f "$sandbox/proxy-args"
mkdir -p "$sandbox/console-state"
run_capture env -u CLAUDE_OLLAMA_PROXY CLAUDE_CONSOLE_STATE_DIR="$sandbox/console-state" STUB_PROXY_PORT=48001 "$repo/bin/claude-ollama" 27b -p hi
check_that "the messages proxy logs under CLAUDE_CONSOLE_STATE_DIR when it is set" contains "$(cat "$sandbox/proxy-args")" "--log $sandbox/console-state/proxy/requests.jsonl"
check_eq "claude is pointed at the proxy's published port" "http://127.0.0.1:48001" "$(launch_base_url)"
rm -f "$sandbox/proxy-args"
run_capture env CLAUDE_OLLAMA_PROXY=0 "$repo/bin/claude-ollama" 27b -p hi
check_not "CLAUDE_OLLAMA_PROXY=0 starts no proxy" test -e "$sandbox/proxy-args"
check_eq "and claude keeps the direct Ollama URL" "$(jq -r .env.ANTHROPIC_BASE_URL "$repo/ollama/settings.27b.json")" "$(launch_base_url)"
rm -f "$sandbox/proxy-args"
run_capture env -u CLAUDE_OLLAMA_PROXY CLAUDE_OLLAMA_PROXY_RECORD=1 "$repo/bin/claude-ollama" 27b -p hi
check_that "CLAUDE_OLLAMA_PROXY_RECORD=1 records bodies under the session proxy dir" contains "$(cat "$sandbox/proxy-args")" "--record $session_config/proxy/record"
check_not "without CLAUDE_OLLAMA_PROXY_STABILIZE the proxy only observes" contains "$(cat "$sandbox/proxy-args")" "--stabilize"
rm -f "$sandbox/proxy-args"
run_capture env -u CLAUDE_OLLAMA_PROXY CLAUDE_OLLAMA_PROXY_STABILIZE=1 "$repo/bin/claude-ollama" 27b -p hi
check_that "CLAUDE_OLLAMA_PROXY_STABILIZE=1 passes --stabilize to the proxy" contains "$(cat "$sandbox/proxy-args")" "--stabilize"
rm -f "$sandbox/proxy-args"
run_capture env -u CLAUDE_OLLAMA_PROXY "$repo/bin/claude-ollama" 27b -p hi
check_not "the proxy records nothing by default" contains "$(cat "$sandbox/proxy-args")" "--record"
cat > "$sandbox/stubbin/rescue" <<EOF
#!/bin/sh
printf '%s\n' "\$*" > "$sandbox/rescue-args"
while [ \$# -gt 0 ]; do
  [ "\$1" = --server-env ] && cp "\$2" "$sandbox/rescue-server-env"
  shift
done
echo "~/.claude-ollama/rescue/x.md"
EOF
chmod +x "$sandbox/stubbin/rescue"
rm -f "$sandbox/ollama.log"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_KEEP_ALIVE=30m" run_capture env CLAUDE_OLLAMA_RESCUE_BIN="$sandbox/stubbin/rescue" "$repo/bin/claude-ollama" rescue 27b --since 30 --out "$sandbox/rescue.md"
check_eq "rescue exit status" 0 "$?"
rescue_args="$(cat "$sandbox/rescue-args" 2>/dev/null)"
check_that "rescue hands the script the launcher" contains "$rescue_args" "/bin/claude-ollama --size 27b"
check_that "rescue hands the script the fingerprint tool" contains "$rescue_args" "/bin/sync-fingerprint"
check_that "rescue hands the script the lease tool" contains "$rescue_args" "--lease-bin "
check_that "rescue hands the script the session dir" contains "$rescue_args" "--session-dir $session_config"
check_that "rescue hands the script the console state dir" contains "$rescue_args" "--state-dir "
check_that "rescue hands the script the Ollama URL" contains "$rescue_args" "--ollama-url http://127.0.0.1:11434"
check_that "rescue passes its own flags through" contains "$rescue_args" "--since 30 --out $sandbox/rescue.md"
check_that "rescue hands over the running server env" grep -qx "OLLAMA_KEEP_ALIVE=30m" "$sandbox/rescue-server-env"
check_that "rescue prints the script's output" grep -q "rescue/x.md" "$sandbox/out"
check_not "rescue does not launch claude" grep -q '^ARGS:' "$sandbox/out"
check_not "rescue does not pull or create" grep -sqE '^(pull|create) ' "$sandbox/ollama.log"
rm -f "$sandbox/rescue-args"
run_capture env CLAUDE_OLLAMA_RESCUE_BIN="$sandbox/stubbin/rescue" "$repo/bin/claude-ollama" rescue
check_that "rescue without a size uses the default size" contains "$(cat "$sandbox/rescue-args" 2>/dev/null)" "--size 27b"
run_capture "$repo/bin/claude-ollama" --help
check_that "usage lists rescue" grep -q '^rescue ' "$sandbox/out"
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
check_eq "with CLAUDE_OLLAMA_CMUX=0 the appended prompt skips the cmux markdown rule" "$(cat "$repo/ollama/CLAUDE.local.md")" "$(cat "$session_config/append-prompt.md")"
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
check_eq "in a cmux terminal the appended prompt adds the cmux markdown rule" \
  "$(cat "$repo/ollama/CLAUDE.local.md" "$repo/ollama/CLAUDE.cmux.md")" "$(cat "$session_config/append-prompt.md")"
check_that "the session gets the cmux-markdown skill the rule names" test -f "$session_config/skills/cmux-markdown/SKILL.md"

mkdir -p "$HOME/.claude"
echo "@preferences" > "$HOME/.claude/CLAUDE.md"
echo '{"hasCompletedOnboarding":true,"theme":"light"}' > "$session_config/.claude.json"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "the session reads a copy of your CLAUDE.md" "@preferences" "$(cat "$session_config/CLAUDE.md")"
check_eq "an existing session config is kept" light "$(jq -r .theme "$session_config/.claude.json")"
check_that "without your skills the session still gets the vendored ones" test -f "$session_config/skills/tdd/SKILL.md"
check_that "the vendored skills include the ones the plugin leaves out" test -f "$session_config/skills/loop-me/SKILL.md"

mkdir -p "$HOME/.claude/skills/tidy" "$HOME/.claude/skills/tdd" "$sandbox/linked-skill"
echo "tidy skill" > "$HOME/.claude/skills/tidy/SKILL.md"
echo "your tdd" > "$HOME/.claude/skills/tdd/SKILL.md"
echo "linked skill" > "$sandbox/linked-skill/SKILL.md"
ln -s "$sandbox/linked-skill" "$HOME/.claude/skills/linked"
mkdir -p "$session_config/skills/retired"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "the session gets a copy of your skills" "tidy skill" "$(cat "$session_config/skills/tidy/SKILL.md")"
check_eq "a symlinked skill is copied as files, since the sandbox cannot read ~/.claude" "linked skill" \
  "$(cat "$session_config/skills/linked/SKILL.md")"
check_not "the copy is a plain folder, not a link" test -L "$session_config/skills/linked"
check_not "a skill you removed is gone from the copy" test -e "$session_config/skills/retired"
check_eq "your skill wins over a vendored one of the same name" "your tdd" "$(cat "$session_config/skills/tdd/SKILL.md")"
check_that "the vendored skills sit beside yours" test -f "$session_config/skills/grilling/SKILL.md"
for agent_only_skill in chief-of-staff claude-handoff code-review implement-spec research; do
  check_not "$agent_only_skill needs subagents or the web, so it is not vendored" test -e "$session_config/skills/$agent_only_skill"
done

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
fetch_settings_file="$sandbox/settings-seen"
settings_dir="$HOME/.claude-ollama/launch-settings"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "without a fetch list the launch keeps the base tools" grep -qF -- "--tools Bash,Read,Edit,Write,Skill,TaskStop -p hi" "$sandbox/out"
check_that "without a fetch list the launch keeps the profile settings" grep -qF -- "--settings $repo/ollama/settings.27b.json" "$sandbox/out"
check_eq "without a fetch list no derived settings are written" "" "$(ls "$settings_dir")"

new_sandbox
fetch_list="$HOME/.config/claude-custom/fetch-domains"
fetch_settings_file="$sandbox/settings-seen"
settings_dir="$HOME/.claude-ollama/launch-settings"
write_fetch_list '  \nlocalhost\n127.0.0.1\n*\nhttps://x.org/\nexample.com:8080\n'
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "a fetch list with only invalid lines keeps the base tools" grep -qF -- "--tools Bash,Read,Edit,Write,Skill,TaskStop -p hi" "$sandbox/out"
check_eq "a fetch list with only invalid lines writes no derived settings" "" "$(ls "$settings_dir")"
check_that "an invalid fetch line says why it is ignored" grep -qxF "claude-ollama: ignoring fetch domain 'localhost' (expected a hostname like docs.python.org)" "$sandbox/err"

new_sandbox
fetch_list="$HOME/.config/claude-custom/fetch-domains"
fetch_settings_file="$sandbox/settings-seen"
settings_dir="$HOME/.claude-ollama/launch-settings"
write_fetch_list '  Docs.Python.org \npkg.go.dev\npkg.go.dev\nbad_host\n'
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "a fetch list adds WebFetch to the tools" grep -qF -- "--tools Bash,Read,Edit,Write,Skill,TaskStop,WebFetch -p hi" "$sandbox/out"
check_that "a fetch list passes the derived settings" grep -qE -- "--settings $settings_dir/[0-9]+\.json" "$sandbox/out"
check_that "an invalid fetch line is ignored with a message" grep -qxF "claude-ollama: ignoring fetch domain 'bad_host' (expected a hostname like docs.python.org)" "$sandbox/err"
check_eq "a fetch list allows WebFetch for exactly the listed hosts" '["mcp__code-search__semantic_search","mcp__repo","mcp__dev__dev_status","mcp__dev__dev_logs","mcp__dev__dev_errors","mcp__dev__dev_deps","mcp__dev__page_check","mcp__dev__page_snapshot","mcp__dev__page_act","Skill(find-docs)","Bash(claude-custom ctx7 *)","WebFetch(domain:docs.python.org)","WebFetch(domain:pkg.go.dev)"]' "$(jq -c .permissions.allow "$fetch_settings_file")"
check_that "the derived settings lift the bare WebFetch deny" jq -e '.permissions.deny | index("WebFetch") == null' "$fetch_settings_file"
check_that "the derived settings keep WebSearch denied" jq -e '.permissions.deny | index("WebSearch") != null' "$fetch_settings_file"
check_eq "the derived settings deny loopback hosts for WebFetch" '["WebFetch(domain:localhost)","WebFetch(domain:127.0.0.1)","WebFetch(domain:0.0.0.0)","WebFetch(domain:[::1])"]' "$(jq -c '[.permissions.deny[] | select(startswith("WebFetch("))]' "$fetch_settings_file")"
check_eq "the derived settings skip Anthropic's WebFetch preflight" true "$(jq .skipWebFetchPreflight "$fetch_settings_file")"
check_eq "the derived settings keep the profile model" "$(jq -r .model "$repo/ollama/settings.27b.json")" "$(jq -r .model "$fetch_settings_file")"
rm -f "$fetch_list"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_not "removing the fetch list stops passing derived settings" grep -qF "$settings_dir" "$sandbox/out"
check_not "removing the fetch list removes WebFetch from the tools" grep -qF WebFetch "$sandbox/out"

new_sandbox
mkdir -p "$sandbox/xdg/claude-custom"
printf 'docs.rs\n' > "$sandbox/xdg/claude-custom/fetch-domains"
run_capture env XDG_CONFIG_HOME="$sandbox/xdg" "$repo/bin/claude-ollama" 27b -p hi
check_that "XDG_CONFIG_HOME moves the fetch list" grep -qF "WebFetch(domain:docs.rs)" "$sandbox/settings-seen"

new_sandbox
fetch_list="$HOME/.config/claude-custom/fetch-domains"
settings_dir="$HOME/.claude-ollama/launch-settings"
write_fetch_list 'docs.python.org\n'
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "a composed launch names a file per launcher pid" grep -qE -- "--settings $settings_dir/[0-9]+\.json" "$sandbox/out"
check_eq "the composed settings file is private" 600 "$(cat "$sandbox/settings-seen-mode")"
check_eq "the launch-settings folder is private" 700 "$(stat -f '%Lp' "$settings_dir" 2>/dev/null || stat -c '%a' "$settings_dir")"
check_eq "the composed settings file is removed when the launch ends" "" "$(ls "$settings_dir")"

sleep 30 &
live_pid=$!
printf '{"live":true}' > "$settings_dir/$live_pid.json"
printf '{"dead":true}' > "$settings_dir/99999999.json"
cp "$settings_dir/$live_pid.json" "$sandbox/live-before.json"
run_capture "$repo/bin/claude-ollama" --print-config 27b
check_eq "print-config leaves a live launch's settings alone" "$(cat "$sandbox/live-before.json")" "$(cat "$settings_dir/$live_pid.json")"
check_that "print-config names the base file and its layers" grep -qxF "settings: $repo/ollama/settings.27b.json + fetch-domain" "$sandbox/out"
check_not "print-config names no file under launch-settings in its settings line" grep -q "^settings: .*launch-settings" "$sandbox/out"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_not "the next launch removes a dead pid's settings file" test -e "$settings_dir/99999999.json"
check_that "the next launch keeps a live pid's settings file" test -e "$settings_dir/$live_pid.json"
kill "$live_pid" 2>/dev/null
wait "$live_pid" 2>/dev/null

run_capture "$repo/bin/claude-ollama" --print-config 27b
check_that "print-config lists the fetch domains" grep -qxF "fetch domains: docs.python.org" "$sandbox/out"
check_that "print-config shows WebFetch in the tools" grep -qxF "tools: Bash,Read,Edit,Write,Skill,TaskStop,WebFetch" "$sandbox/out"
rm -f "$fetch_list"
run_capture "$repo/bin/claude-ollama" --print-config 27b
check_that "print-config says when no fetch domains are listed" grep -qxF "fetch domains: none" "$sandbox/out"
check_that "print-config keeps the base tools without a fetch list" grep -qxF "tools: Bash,Read,Edit,Write,Skill,TaskStop" "$sandbox/out"

new_sandbox /tmp
qwen_project="$sandbox/qwen-project"
mkdir -p "$qwen_project"
qwen_return_dir="$(pwd -P)"
cd "$qwen_project" || exit 1
cat > "$sandbox/stubbin/qwen-script" <<'EOF'
#!/bin/sh
echo "QWEN SCRIPT: $*"
exit "${STUB_QWEN_SCRIPT_EXIT:-0}"
EOF
chmod +x "$sandbox/stubbin/qwen-script"
export CLAUDE_OLLAMA_QWEN_BIN="$sandbox/stubbin/qwen-script"
run_capture "$repo/bin/claude-ollama" qwen 27b -p hi
check_eq "claude-ollama qwen exit status" 0 "$?"
check_that "claude-ollama qwen hands the size and args to bin/claude-ollama-qwen" grep -qxF "QWEN SCRIPT: launch 27b -p hi" "$sandbox/out"
check_not "claude-ollama qwen never runs claude" grep -q '^ARGS:' "$sandbox/out"
check_that "claude-ollama qwen warms the model" warm_up_logged
launcher_log="$HOME/.local/share/claude-custom/console/launcher.log"
check_that "and the launcher log records the hand-off to qwen" wait_for_launcher_log "claude-ollama: starting qwen"
check_that "and names the program" grep -qxF "claude-ollama: starting qwen" "$sandbox/err"
run_capture "$repo/bin/claude-ollama" qwen -p hi </dev/null
check_that "claude-ollama qwen without a size uses the default" grep -qxF "QWEN SCRIPT: launch 27b -p hi" "$sandbox/out"
STUB_QWEN_SCRIPT_EXIT=1 run_capture "$repo/bin/claude-ollama" qwen doctor 35b
check_eq "claude-ollama qwen doctor exits with the qwen doctor's status" 1 "$?"
check_that "claude-ollama qwen doctor runs the qwen doctor" grep -qxF "QWEN SCRIPT: doctor 35b" "$sandbox/out"
check_not "qwen doctor never launches claude" grep -q '^ARGS:' "$sandbox/out"
run_capture "$repo/bin/claude-ollama" qwen --print-config 35b
check_that "claude-ollama qwen --print-config runs the qwen print-config" grep -qxF "QWEN SCRIPT: --print-config 35b" "$sandbox/out"
unset CLAUDE_OLLAMA_QWEN_BIN
CLAUDE_OLLAMA_SANDBOX_EXEC=/usr/bin/true run_capture "$repo/bin/claude-ollama" qwen 27b -p hi
check_that "claude-ollama qwen runs the real qwen script by default" grep -qF -- "-m qwen3.8-27b-cc --approval-mode auto-edit" "$sandbox/out"

rm -f "$sandbox/stubbin/qwen"
run_capture "$repo/bin/claude-ollama" qwen 27b -p hi
check_eq "claude-ollama qwen without qwen exits 1" 1 "$?"
check_that "and says how to install it" grep -qxF "claude-ollama: qwen is missing (brew install qwen-code)" "$sandbox/err"
check_not "and pulls no model first" grep -sqE '^(pull|create) ' "$sandbox/ollama.log"
cd "$qwen_return_dir" || exit 1

run_capture "$repo/bin/claude-ollama" --help
check_that "claude-ollama help lists qwen" grep -qF -- "qwen [size] [qwen args...]: launch Qwen Code" "$sandbox/out"
check_that "claude-ollama help lists qwen doctor" grep -qF -- "qwen doctor [size]: check qwen" "$sandbox/out"

new_sandbox
export XDG_CONFIG_HOME="$sandbox/xdg"
profiles="$XDG_CONFIG_HOME/claude-custom/profiles"
mkdir -p "$profiles"
printf '%s' '{"tools":{"Glob":"allow"},"mcp":{"dev":false},"env":{"CLAUDE_OLLAMA_TELEMETRY":"1"}}' > "$profiles/ollama-27b.json"
profile_settings="$sandbox/settings-seen"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "a profile adds its allowed tool to --tools" grep -qF -- "--tools Bash,Read,Edit,Write,Skill,TaskStop,Glob -p hi" "$sandbox/out"
check_that "a profile launches the settings it derives" grep -qE -- "--settings $HOME/.claude-ollama/launch-settings/[0-9]+\.json" "$sandbox/out"
check_that "the derived settings allow the tool" jq -e '.permissions.allow | index("Glob") != null' "$profile_settings"
check_that "the derived settings keep the profile model" jq -e '.model == "qwen3.8-27b-cc"' "$profile_settings"
check_not "a disabled MCP server drops out of --mcp-config" grep -qF '"dev":{' "$sandbox/out"
check_that "enabled MCP servers stay in --mcp-config" grep -qF '"repo":{' "$sandbox/out"
check_eq "a profile env value applies before the launch" "$HOME/.claude-ollama/telemetry/tool-calls.jsonl" "$(cat "$sandbox/telemetry-env")"

new_sandbox
export XDG_CONFIG_HOME="$sandbox/xdg"
profiles="$XDG_CONFIG_HOME/claude-custom/profiles"
mkdir -p "$profiles"
profile_settings="$sandbox/settings-seen"
printf '%s' '{"context":32768}' > "$profiles/ollama-27b.json"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "a context override recreates the model with its num_ctx" grep -qxF "modelfile: PARAMETER num_ctx 32768" "$sandbox/ollama.log"
check_that "the recreated model builds on the installed one" grep -qxF "modelfile: FROM qwen3.8-27b-cc" "$sandbox/ollama.log"
check_that "claude-ollama says it recreates with the merged parameters" grep -qF "recreating qwen3.8-27b-cc with num_ctx 32768 num_predict 8192 temperature 0.7 top_k 20 top_p 0.8" "$sandbox/err"
check_eq "the derived settings carry the override context" 32768 "$(jq -r '.env.CLAUDE_CODE_MAX_CONTEXT_TOKENS' "$profile_settings")"
check_that "the launch uses the derived settings" grep -qE -- "--settings $HOME/.claude-ollama/launch-settings/[0-9]+\.json" "$sandbox/out"

new_sandbox
export XDG_CONFIG_HOME="$sandbox/xdg"
profiles="$XDG_CONFIG_HOME/claude-custom/profiles"
mkdir -p "$profiles"
printf '%s' '{"tools":{"Glob":"allow"},"mcp":{"dev":false},"env":{"CLAUDE_OLLAMA_TELEMETRY":"0"}}' > "$profiles/ollama-27b.json"
run_capture "$repo/bin/claude-ollama" --print-config 27b
check_that "print-config shows the profile path" grep -qxF "profile: $profiles/ollama-27b.json" "$sandbox/out"
check_that "print-config shows the overrides in effect" grep -qxF "overrides: tools.Glob=allow, mcp.dev=false, env.CLAUDE_OLLAMA_TELEMETRY=0" "$sandbox/out"
check_that "print-config shows the profile tools" grep -qxF "tools: Bash,Read,Edit,Write,Skill,TaskStop,Glob" "$sandbox/out"
check_not "print-config shows no dev server with dev disabled" grep -qF '"dev":{' "$sandbox/out"

new_sandbox
export XDG_CONFIG_HOME="$sandbox/xdg"
profiles="$XDG_CONFIG_HOME/claude-custom/profiles"
mkdir -p "$profiles"
printf '{}' > "$sandbox/elsewhere.json"
ln -s "$sandbox/elsewhere.json" "$profiles/ollama-27b.json"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "a symlinked profile stops the launch" 1 "$?"
check_that "a symlinked profile says it is a symlink" grep -qF "is a symlink" "$sandbox/err"
check_not "a symlinked profile launches nothing" grep -q '^ARGS:' "$sandbox/out"

new_sandbox
relaunch_root="$HOME/.claude-ollama/relaunch"
incidents_dir="$sandbox/home/.local/share/claude-custom/console/incidents"
stale_pid="$(sleep 60 >/dev/null 2>&1 & echo $!)"
kill "$stale_pid"
wait "$stale_pid" 2>/dev/null
live_pid="$(sleep 60 >/dev/null 2>&1 & echo $!)"
mkdir -p "$relaunch_root/$stale_pid" "$relaunch_root/$live_pid" "$relaunch_root/notes"
run_capture env STUB_CLAUDE_RELAUNCH_ONCE=1 STUB_CLAUDE_RELAUNCH_PROMPT="finish the tests" "$repo/bin/claude-ollama" 27b "finish the tests"
launcher_pid="$(cat "$sandbox/claude-ppid")"
relaunch_dir="$relaunch_root/$launcher_pid"
check_eq "a relaunch sentinel starts claude a second time" 2 "$(grep -c '^ARGS:' "$sandbox/out")"
check_that "the second run ends with /handoff and the pending prompt as one word" grep -qxF -- "ARG: /handoff finish the tests" "$sandbox/out"
check_eq "the user's prompt reaches the first run and the handoff" 2 "$(grep -c '^ARGS:.*finish the tests' "$sandbox/out")"
check_that "the relaunch names the percent and the prompt on stderr" grep -qxF 'claude-ollama: context budget reached at 71%: handoff saved, resuming "finish the tests"' "$sandbox/err"
check_eq "the pid file holds claude's pid" "$(cat "$sandbox/claude-pid")" "$(cat "$sandbox/pid-file-seen")"
check_eq "claude is told a relaunch dir named after the launcher's pid" "$relaunch_dir" "$(cat "$sandbox/relaunch-dir-env")"
check_not "the launcher removes its relaunch dir on exit" test -e "$relaunch_dir"
check_eq "the relaunch root is private" 700 "$(stat -c %a "$relaunch_root" 2>/dev/null || stat -f %Lp "$relaunch_root")"
check_not "a sibling dir whose pid is dead is removed" test -e "$relaunch_root/$stale_pid"
check_that "a sibling dir whose pid runs is kept" test -d "$relaunch_root/$live_pid"
check_that "a sibling that is not a pid is kept" test -d "$relaunch_root/notes"
kill "$live_pid" 2>/dev/null
relaunch_incident="$(grep '"cause": "relaunched"' "$(cat "$incidents_dir/current")")"
check_eq "the relaunch writes one incident line" 1 "$(printf '%s\n' "$relaunch_incident" | grep -c relaunched)"
check_eq "the incident names the note" note.md "$(printf '%s\n' "$relaunch_incident" | jq -r .detail)"
check_eq "the incident derives the tokens from the percent" "$(( 71 * $(jq -r .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS "$repo/ollama/settings.27b.json") / 100 ))" "$(printf '%s\n' "$relaunch_incident" | jq -r .tokens)"
check_that "the incident has a UTC timestamp" grep -qE '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' <<< "$(printf '%s\n' "$relaunch_incident" | jq -r .ts)"
check_eq "the relaunch is also the latest incident" relaunched "$(jq -r .cause "$(cat "$incidents_dir/current").latest")"
check_eq "the incidents file is private" 600 "$(stat -c %a "$(cat "$incidents_dir/current")" 2>/dev/null || stat -f %Lp "$(cat "$incidents_dir/current")")"
rm -f "$sandbox/relaunched"
run_capture env STUB_CLAUDE_RELAUNCH_ONCE=1 "$repo/bin/claude-ollama" 27b --continue
check_that "flags stay and /handoff is appended when there was no prompt" grep -qF -- "--tools Bash,Read,Edit,Write,Skill,TaskStop --continue /handoff" "$sandbox/out"
check_that "the second run ends with a bare /handoff when the sentinel has no prompt" grep -qxF -- "ARG: /handoff" "$sandbox/out"
check_that "without a prompt the banner says relaunching" grep -qxF 'claude-ollama: context budget reached at 71%: handoff saved, relaunching claude' "$sandbox/err"
rm -f "$sandbox/relaunched"
run_capture env STUB_CLAUDE_RELAUNCH_ONCE=1 STUB_CLAUDE_RELAUNCH_PROMPT="-p hi" "$repo/bin/claude-ollama" 27b --permission-mode plan
check_that "a trailing option value is kept on relaunch" grep -qF -- "--tools Bash,Read,Edit,Write,Skill,TaskStop --permission-mode plan /handoff" "$sandbox/out"
check_that "a prompt that starts with a dash gives a bare /handoff" grep -qxF -- "ARG: /handoff" "$sandbox/out"
rm -f "$sandbox/relaunched"
run_capture env STUB_CLAUDE_RELAUNCH_ONCE=1 "$repo/bin/claude-ollama" 27b --permission-mode plan "finish the tests"
check_that "a prompt after an option value is replaced on relaunch" grep -qF -- "--tools Bash,Read,Edit,Write,Skill,TaskStop --permission-mode plan /handoff" "$sandbox/out"
run_capture env CLAUDE_OLLAMA_INCIDENTS=0 STUB_CLAUDE_RELAUNCH_ONCE=1 "$repo/bin/claude-ollama" 27b -p hi
check_eq "no incidents file means no incident line and no failure" 0 "$?"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "without a sentinel claude runs once" 1 "$(grep -c '^ARGS:' "$sandbox/out")"
check_not "and nothing says relaunching" grep -q relaunching "$sandbox/err"
run_capture env STUB_CLAUDE_EXIT=3 "$repo/bin/claude-ollama" 27b -p hi
check_eq "the launcher exits with claude's status" 3 "$?"
run_capture env CLAUDE_OLLAMA_RELAUNCH=0 "$repo/bin/claude-ollama" 27b -p hi
check_eq "CLAUDE_OLLAMA_RELAUNCH=0 execs claude in the launcher's place" "$$" "$(cat "$sandbox/claude-ppid")"
check_eq "and sets no relaunch dir" unset "$(cat "$sandbox/relaunch-dir-env")"

lease_dir="$HOME/.claude-ollama/lease"
healthy_two="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=2 OLLAMA_NUM_PARALLEL=1"
rm -rf "$lease_dir" "$sandbox/lease-seen" "$sandbox/ladder-args"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_two" run_capture env CLAUDE_OLLAMA_LEASE_HEARTBEAT=0.1 STUB_CLAUDE_SLEEP=0.5 "$repo/bin/claude-ollama" 27b -p hi
session_lease="$(grep '"name":"session"' "$sandbox/lease-seen" | head -n 1)"
check_eq "a launch holds a session lease while claude runs" session "$(printf '%s\n' "$session_lease" | jq -r .name)"
check_eq "the session lease names the model" qwen3.8-27b-cc "$(printf '%s\n' "$session_lease" | jq -r .model)"
check_eq "the session lease records the model's num_ctx" 65536 "$(printf '%s\n' "$session_lease" | jq -r .num_ctx)"
check_that "the indexer holds an embedding lease" grep -q '"name":"embedding","model":"qwen3-embedding:0.6b"' "$sandbox/lease-seen"
check_eq "the launcher releases the session lease on exit" "" "$(ls "$lease_dir"/*.json 2>/dev/null)"
check_that "a heartbeat keeps the model alive while claude runs" test "$(grep -c '"model":"qwen3.8-27b-cc","keep_alive":"30m"' "$sandbox/curl.log")" -ge 2
check_eq "the indexer may embed when the server keeps the session and the embedding model" 1 "$(cat "$sandbox/indexer-embed-env")"
ladder_args="$(for _ in $(seq 25); do [ -s "$sandbox/ladder-args" ] && break; sleep 0.2; done; cat "$sandbox/ladder-args" 2>/dev/null)"
check_that "the ladder follows the session's incidents file" contains "$ladder_args" "--incidents $(cat "$incidents_dir/current")"
check_that "the ladder knows the relaunch dir" contains "$ladder_args" "--relaunch-dir $relaunch_root/"
check_that "the ladder stops with the launch" contains "$ladder_args" "--watch-pid "
check_that "the ladder knows the model's context" contains "$ladder_args" "--context 65536"
rm -f "$sandbox/ladder-args"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_two" run_capture env CLAUDE_OLLAMA_LADDER=0 "$repo/bin/claude-ollama" 27b -p hi
sleep 1
check_not "CLAUDE_OLLAMA_LADDER=0 starts no ladder" test -e "$sandbox/ladder-args"

holder_pid="$(sleep 60 >/dev/null 2>&1 & echo $!)"
mkdir -p "$lease_dir"
printf '{"name":"review","model":"qwen3.6-35b-cc","num_ctx":null,"rung":null,"started":"2026-01-01T00:00:00Z"}\n' > "$lease_dir/$holder_pid.json"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_two" run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "a review lease on another model still lets a session launch when the server keeps two" grep -q '^ARGS:' "$sandbox/out"
check_eq "but the indexer runs words-only when the embedding model would be a third" 0 "$(cat "$sandbox/indexer-embed-env")"
printf '{"name":"session","model":"qwen3.6-35b-cc","num_ctx":null,"rung":null,"started":"2026-01-01T00:00:00Z"}\n' > "$lease_dir/$holder_pid.json"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=1" run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "a second session on another model is refused when the server keeps one" 3 "$?"
check_that "the refusal names the holder" grep -qxF "ollama lease: held by session (pid $holder_pid, model qwen3.6-35b-cc); run after that session ends or set OLLAMA_MAX_LOADED_MODELS=2" "$sandbox/err"
check_not "a refused launch does not start claude" grep -q '^ARGS:' "$sandbox/out"
CLAUDE_OLLAMA_SPEED_CHECK="$sandbox/stubbin/speed-check" STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_two" run_capture "$repo/bin/claude-ollama" speed-check
check_eq "speed-check is refused while a session lease exists" 3 "$?"
check_that "the speed-check refusal names the holder" grep -qF "ollama lease: held by session (pid $holder_pid" "$sandbox/err"
check_not "a refused speed-check never runs" grep -q 'speed-check args' "$sandbox/out"
printf '#!/bin/sh\necho "reviewer args: $*"\n' > "$sandbox/stubbin/reviewer"
chmod +x "$sandbox/stubbin/reviewer"
CLAUDE_OLLAMA_REVIEWER="$sandbox/stubbin/reviewer" STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_MAX_LOADED_MODELS=1" run_capture "$repo/bin/claude-ollama" review 27b 12
check_eq "a review on another model is refused when the server keeps one" 3 "$?"
check_not "a refused review never runs" grep -q 'reviewer args' "$sandbox/out"
CLAUDE_OLLAMA_REVIEWER="$sandbox/stubbin/reviewer" STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_two" run_capture "$repo/bin/claude-ollama" review 27b 12
check_that "a review runs when the server keeps two models" grep -q '^reviewer args' "$sandbox/out"
CLAUDE_OLLAMA_LEASE_DIR="$lease_dir" "$repo/bin/ollama-lease" holders >/dev/null
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_MAX_LOADED_MODELS=1" run_capture env CLAUDE_OLLAMA_LEASE=0 "$repo/bin/claude-ollama" 27b -p hi
check_that "CLAUDE_OLLAMA_LEASE=0 launches past a held lease" grep -q '^ARGS:' "$sandbox/out"
check_eq "CLAUDE_OLLAMA_LEASE=0 writes no lease" "$lease_dir/$holder_pid.json" "$(ls "$lease_dir"/*.json)"
kill "$holder_pid" 2>/dev/null
wait "$holder_pid" 2>/dev/null

rm -f "$sandbox/laddered" "$sandbox/lease-seen"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_two" run_capture env STUB_CLAUDE_LADDER_ONCE=1 STUB_CLAUDE_EMBED_OFF=1 "$repo/bin/claude-ollama" 27b "finish the tests"
check_eq "a ladder file starts claude a second time" 2 "$(grep -c '^ARGS:' "$sandbox/out")"
check_that "the ladder relaunch names the rung and the reason" grep -qxF "claude-ollama: ladder context-down: 3 truncated prompts within 10 minutes" "$sandbox/err"
ladder_settings="$(settings_arg | tail -n 1)"
check_that "the second run uses a per-launch settings file" contains "$ladder_settings" "$HOME/.claude-ollama/launch-settings/"
check_eq "the ladder settings lower the context budget" 32768 "$(jq -r .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS "$sandbox/settings-seen")"
check_that "the second run continues the conversation without the prompt" grep -qF -- "--tools Bash,Read,Edit,Write,Skill,TaskStop --continue" "$sandbox/out"
check_not "the second run drops the prompt" grep -qF -- "--continue finish the tests" "$sandbox/out"
check_eq "the lease records the rung after the relaunch" context-down "$(tail -n 1 "$sandbox/lease-seen" | jq -r .rung)"
check_eq "an embed-off file turns the search server's embeddings off on relaunch" 0 "$(cat "$sandbox/embed-env")"
check_not "the ladder file is consumed" test -e "$relaunch_root/$(cat "$sandbox/claude-ppid")/ladder"

new_sandbox
malformed_status=0
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_two" run_capture env STUB_CLAUDE_LADDER_MALFORMED=1 "$repo/bin/claude-ollama" 27b -p hi || malformed_status=$?
check_eq "a malformed ladder file does not end the launcher" 0 "$malformed_status"
check_eq "a malformed ladder file still lets claude run again" 2 "$(grep -c '^ARGS:' "$sandbox/out")"
check_that "a malformed ladder file is reported as dropped" grep -qF "dropped malformed ladder" "$sandbox/err"

new_sandbox
pinned_tags | jq '.models |= map(if .name == "qwen3-embedding:0.6b" then . + {size: 644245094} else . end) | .models += [{name: "qwen3.8-27b-cc", size: 17179869184}]' > "$sandbox/tags.json"
cat > "$sandbox/stubbin/sysctl" <<'EOF'
#!/bin/sh
echo "${STUB_MEMSIZE:-34359738368}"
EOF
cat > "$sandbox/stubbin/vm_stat" <<'EOF'
#!/bin/sh
printf 'Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages active:  100000.\nPages wired down: 100000.\n'
EOF
chmod +x "$sandbox/stubbin/sysctl" "$sandbox/stubbin/vm_stat"
printf '  Model\n    architecture        qwen3\n\n  Metadata\n    qwen3.attention.head_count_kv       8\n    qwen3.attention.key_length          128\n    qwen3.block_count                   64\n' > "$sandbox/show-verbose"
last_session_lease() { grep '"name":"session"' "$sandbox/lease-seen" | tail -n 1; }
fit_line="claude-ollama: memory fit: model 16.0 GiB + kv 8.0 GiB + embedding 0.6 GiB = 24.6 GiB of 28.9 GiB free"
incidents_dir="$sandbox/home/.local/share/claude-custom/console/incidents"
relaunch_root="$HOME/.claude-ollama/relaunch"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_two" run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "a launch prints the memory fit before claude starts" grep -qxF "$fit_line" "$sandbox/err"
check_eq "a fitting launch keeps the embeddings on" 1 "$(cat "$sandbox/embed-env")"
check_eq "a fitting launch holds its lease on no rung" null "$(last_session_lease | jq -r .rung)"
ladder_args="$(for _ in $(seq 25); do [ -s "$sandbox/ladder-args" ] && break; sleep 0.2; done; cat "$sandbox/ladder-args" 2>/dev/null)"
check_that "the ladder knows the model and the embedding model for its recovery fit" contains "$ladder_args" "--model qwen3.8-27b-cc --embedding qwen3-embedding:0.6b"
check_that "the ladder knows the lease script" contains "$ladder_args" "--lease-bin $repo/bin/ollama-lease"
check_not "a fitting launch names no rung to the ladder" contains "$ladder_args" "--rung"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_two" run_capture env CLAUDE_OLLAMA_FIT=0 "$repo/bin/claude-ollama" 27b -p hi
check_not "CLAUDE_OLLAMA_FIT=0 skips the memory fit" grep -q "memory fit" "$sandbox/err"
check_that "CLAUDE_OLLAMA_FIT=0 still launches" grep -q '^ARGS:' "$sandbox/out"

rm -f "$sandbox/lease-seen" "$sandbox/ladder-args"
STUB_MEMSIZE=29276800000 STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_two" run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "a launch short by the embedding model prints the fit" grep -qxF "claude-ollama: memory fit: model 16.0 GiB + kv 8.0 GiB + embedding 0.6 GiB = 24.6 GiB of 24.2 GiB free" "$sandbox/err"
check_that "and starts on the embeddings-off rung" grep -qxF "claude-ollama: ladder embeddings-off: does not fit with the embedding model (0.4 GiB short)" "$sandbox/err"
check_eq "the embeddings-off start turns the search embeddings off" 0 "$(cat "$sandbox/embed-env")"
check_eq "the indexer runs words only on the embeddings-off rung" 0 "$(cat "$sandbox/indexer-embed-env")"
check_eq "the lease records the embeddings-off rung" embeddings-off "$(last_session_lease | jq -r .rung)"
check_that "the embeddings-off start touches embed-off for the relaunch loop" grep -q "embed-off" "$sandbox/relaunch-entries"
ladder_args="$(for _ in $(seq 25); do [ -s "$sandbox/ladder-args" ] && break; sleep 0.2; done; cat "$sandbox/ladder-args" 2>/dev/null)"
check_that "the ladder is told the rung in effect" contains "$ladder_args" "--rung embeddings-off"
check_not "no context-down line when the rung above fits" grep -q "ladder context-down" "$sandbox/err"
check_eq "the embeddings-off start keeps the profile settings" "$repo/ollama/settings.27b.json" "$(settings_arg)"

rm -f "$sandbox/lease-seen" "$sandbox/ladder-args"
STUB_MEMSIZE=25276800000 STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_two" run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "a launch short by more than the embedding model steps to embeddings-off first" grep -qxF "claude-ollama: ladder embeddings-off: does not fit with the embedding model (4.1 GiB short)" "$sandbox/err"
check_that "then to the next lower context" grep -qxF "claude-ollama: ladder context-down: does not fit at num_ctx 65536 (3.5 GiB short); starting at 32768" "$sandbox/err"
check_that "the context-down start uses a per-launch settings file" contains "$(settings_arg)" "$HOME/.claude-ollama/launch-settings/"
check_eq "the ladder settings use the lower context" 32768 "$(jq -r .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS "$sandbox/settings-seen")"
check_eq "the lease records the context-down rung" context-down "$(last_session_lease | jq -r .rung)"
check_eq "the lease records the lower num_ctx" 32768 "$(last_session_lease | jq -r .num_ctx)"
ladder_args="$(for _ in $(seq 25); do [ -s "$sandbox/ladder-args" ] && break; sleep 0.2; done; cat "$sandbox/ladder-args" 2>/dev/null)"
check_that "the ladder is told both rungs in effect" contains "$ladder_args" "--rung embeddings-off --rung context-down"
check_that "the ladder keeps the full context as its recovery target" contains "$ladder_args" "--context 65536"
STUB_MEMSIZE=21276800000 STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_two" run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "a launch nothing fits warns and still starts" grep -qxF "claude-ollama: memory fit: still 3.2 GiB short at num_ctx 32768 with the embeddings off" "$sandbox/err"
check_that "the launch nothing fits still runs claude" grep -q '^ARGS:' "$sandbox/out"
rm -f "$sandbox/stubbin/sysctl"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_two" run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "a fit that cannot be computed is reported, not fatal" grep -qxF "claude-ollama: memory fit: unknown (ollama lease: cannot read the free memory)" "$sandbox/err"
check_that "and the launch goes on" grep -q '^ARGS:' "$sandbox/out"
cat > "$sandbox/stubbin/sysctl" <<'EOF'
#!/bin/sh
echo "${STUB_MEMSIZE:-34359738368}"
EOF
chmod +x "$sandbox/stubbin/sysctl"

rm -f "$sandbox/lease-seen" "$sandbox/laddered" "$sandbox/laddered-up" "$sandbox/relaunch-entries"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_two" run_capture env STUB_CLAUDE_LADDER_ONCE=1 STUB_CLAUDE_EMBED_OFF=1 STUB_CLAUDE_LADDER_UP=embeddings-off STUB_CLAUDE_LADDER_UP_AFTER_LADDER=1 "$repo/bin/claude-ollama" 27b "finish the tests"
check_eq "a ladder-up with a handoff sentinel starts claude a third time" 3 "$(grep -c '^ARGS:' "$sandbox/out")"
check_that "the handoff relaunch announces the recovered rung" grep -qxF "claude-ollama: ladder up: embeddings-off recovered (20 minutes without an incident and the memory fits)" "$sandbox/err"
check_eq "the recovered rung turns the search embeddings back on" 1 "$(cat "$sandbox/embed-env")"
check_not "the recovery removes embed-off" grep -q "embed-off" <<< "$(tail -n 1 "$sandbox/relaunch-entries")"
check_that "the recovery is recorded as an incident" grep -q '"cause": "recovered", "detail": "embeddings-off: 20 minutes without an incident and the memory fits", "tokens": null, "rule": "ladder/up"' "$(cat "$incidents_dir/current")"
check_eq "the lease keeps the context-down rung still in effect" context-down "$(last_session_lease | jq -r .rung)"
check_eq "the third run keeps the ladder settings file" "$(settings_arg | sed -n 2p)" "$(settings_arg | tail -n 1)"
check_that "the third run resumes the handoff" grep -qF -- "--tools Bash,Read,Edit,Write,Skill,TaskStop /handoff go on" "$sandbox/out"

rm -f "$sandbox/lease-seen" "$sandbox/laddered" "$sandbox/laddered-up" "$sandbox/relaunch-entries"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_two" run_capture env STUB_CLAUDE_LADDER_ONCE=1 STUB_CLAUDE_LADDER_UP=context-down STUB_CLAUDE_LADDER_UP_AFTER_LADDER=1 "$repo/bin/claude-ollama" 27b -p hi
check_that "a context-down recovery is announced" grep -qxF "claude-ollama: ladder up: context-down recovered (20 minutes without an incident and the memory fits)" "$sandbox/err"
check_eq "the recovered run returns to the profile settings" "$repo/ollama/settings.27b.json" "$(settings_arg | tail -n 1)"
check_eq "the lease is back on no rung" null "$(last_session_lease | jq -r .rung)"
check_eq "the lease is back on the full num_ctx" 65536 "$(last_session_lease | jq -r .num_ctx)"

rm -f "$sandbox/lease-seen" "$sandbox/laddered" "$sandbox/laddered-up" "$sandbox/relaunch-entries"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_two" run_capture env STUB_CLAUDE_LADDER_ONCE=1 STUB_CLAUDE_LADDER_UP=embeddings-off STUB_CLAUDE_LADDER_UP_NO_HANDOFF=1 "$repo/bin/claude-ollama" 27b -p hi
check_eq "a ladder relaunch alone starts claude twice" 2 "$(grep -c '^ARGS:' "$sandbox/out")"
check_not "a ladder-up is never honoured on a ladder relaunch" grep -q "ladder up" "$sandbox/err"
check_that "the ladder-up file waits for the next handoff relaunch" grep -q "ladder-up" <<< "$(tail -n 1 "$sandbox/relaunch-entries")"

new_sandbox
launch_beacon="$HOME/.local/share/claude-custom/console/beacon/$(hostname -s).json"
run_capture env CLAUDE_OLLAMA_BEACON= "$repo/bin/claude-ollama" 27b -p hi
check_that "a launch writes the beacon under the console state dir" wait_for_file "$launch_beacon"
check_eq "the beacon carries the repo commit" "$(git -C "$repo" rev-parse HEAD)" "$(jq -r .commit "$launch_beacon")"
check_eq "the beacon is 0600" 600 "$(file_mode "$launch_beacon")"
check_eq "the beacon folder is 0700" 700 "$(file_mode "$(dirname "$launch_beacon")")"
check_that "the launch does not wait for the beacon" grep -q '^ARGS:' "$sandbox/out"
rm -f "$launch_beacon"
run_capture env CLAUDE_OLLAMA_BEACON=0 "$repo/bin/claude-ollama" 27b -p hi
sleep 1
check_not "CLAUDE_OLLAMA_BEACON=0 writes no beacon" test -e "$launch_beacon"

new_sandbox
copy_repo "$sandbox/repo"
rm -f "$sandbox/stubbin/shasum"
git -C "$sandbox/repo" init -q
git -C "$sandbox/repo" add -A
git -C "$sandbox/repo" -c user.name=t -c user.email=t@t commit -qm initial
sync_beacon="$HOME/.config/claude-custom/beacon.json"
short_head="$(git -C "$sandbox/repo" rev-parse --short=7 HEAD)"
run_capture "$sandbox/repo/bin/claude-custom" sync-check
check_eq "sync-check without a beacon exits 2" 2 "$?"
check_that "sync-check prints the local commit" grep -qxF "commit: $short_head" "$sandbox/out"
check_that "sync-check prints a short hooks hash" grep -qE '^hooks: [0-9a-f]{12}$' "$sandbox/out"
check_that "sync-check names the missing beacon" grep -qF "no beacon at $sync_beacon" "$sandbox/err"
run_capture "$sandbox/repo/bin/claude-custom" sync-check --write
check_eq "sync-check --write exits 0" 0 "$?"
check_that "--write names the beacon" grep -qxF "beacon written: $sync_beacon" "$sandbox/out"
check_eq "--write writes a 0600 beacon" 600 "$(file_mode "$sync_beacon")"
check_eq "the written beacon carries the commit" "$(git -C "$sandbox/repo" rev-parse HEAD)" "$(jq -r .commit "$sync_beacon")"
run_capture "$sandbox/repo/bin/claude-custom" sync-check
check_eq "sync-check against an equal beacon exits 0" 0 "$?"
check_that "an equal beacon is reported with its host and age" grep -qE "^beacon matches \($(hostname -s), [0-9]+s\)$" "$sandbox/out"
zeros="$(printf '0%.0s' $(seq 64))"
ones="$(printf '1%.0s' $(seq 64))"
jq --arg zeros "$zeros" --arg ones "$ones" --arg ts "$(jq -rn 'now - 7200 | todate')" \
  '.host = "work-laptop" | .ts = $ts | .commit = "abc1234def5678" | .hooks["tdd-guard.py"] = $zeros | .hooks["only-there.sh"] = $ones
   | .models["27b"].digest = "sha256:theirs" | .server_env = {OLLAMA_KV_CACHE_TYPE: "f16"}' "$sync_beacon" > "$sandbox/theirs.json"
run_capture "$sandbox/repo/bin/claude-custom" sync-check --against "$sandbox/theirs.json"
check_eq "sync-check against a differing beacon exits 1" 1 "$?"
check_that "a differing commit is listed" grep -qxF "commit: local $short_head vs beacon abc1234 (work-laptop, 2h)" "$sandbox/out"
check_that "differing hooks are listed" grep -qE "^hooks: local [0-9a-f]{12} vs beacon [0-9a-f]{12} \(work-laptop, 2h\)$" "$sandbox/out"
check_that "the changed hook is named" grep -qxF "  tdd-guard.py: local $(shasum -a 256 "$repo/shared/hooks/tdd-guard.py" | cut -c1-12) vs beacon 000000000000" "$sandbox/out"
check_that "a hook only in the beacon is named" grep -qxF "  only-there.sh: local none vs beacon 111111111111" "$sandbox/out"
check_that "differing models are listed" grep -qE "^models: local [0-9a-f]{12} vs beacon [0-9a-f]{12} \(work-laptop, 2h\)$" "$sandbox/out"
check_that "the changed model is spelled out" grep -qxF "  27b: local qwen3.8-27b-cc missing vs beacon qwen3.8-27b-cc sha256:theirs" "$sandbox/out"
check_that "a differing server env is listed" grep -qE "^server_env: local [0-9a-f]{12} vs beacon [0-9a-f]{12} \(work-laptop, 2h\)$" "$sandbox/out"
check_not "an equal section is not listed" grep -q '^sandbox: local' "$sandbox/out"
check_not "an equal model is not spelled out" grep -q '^  35b:' "$sandbox/out"
run_capture "$sandbox/repo/bin/claude-custom" sync-check --against
check_eq "sync-check --against without a file exits 2" 2 "$?"
check_that "usage lists sync-check" grep -qF "sync-check" "$sandbox/err"

new_sandbox
cat > "$sandbox/stubbin/why" <<EOF
#!/bin/sh
printf '%s\n' "\$*" > "$sandbox/why-args"
echo "verdict: stub"
EOF
chmod +x "$sandbox/stubbin/why"
CLAUDE_OLLAMA_WHY_BIN="$sandbox/stubbin/why" run_capture "$repo/bin/claude-ollama" why --since 10 --json
check_eq "why exit status" 0 "$?"
check_that "why reads the console proxy log and the incidents folder and passes its flags" grep -qxF -- "--proxy-log $HOME/.local/share/claude-custom/console/proxy/requests.jsonl --incidents-dir $HOME/.local/share/claude-custom/console/incidents --since 10 --json" "$sandbox/why-args"
check_that "why prints the verdict" grep -qxF "verdict: stub" "$sandbox/out"
check_not "why does not launch claude" grep -q '^ARGS:' "$sandbox/out"
check_not "why does not start the proxy" test -e "$sandbox/proxy-args"
check_not "why does not start the watcher" test -e "$sandbox/watcher-args"
mkdir -p "$sandbox/state"
rm -f "$sandbox/why-args"
CLAUDE_CONSOLE_STATE_DIR="$sandbox/state" CLAUDE_OLLAMA_WHY_BIN="$sandbox/stubbin/why" run_capture "$repo/bin/claude-ollama" why
check_that "why reads the console state dir when it is set" grep -qxF -- "--proxy-log $sandbox/state/proxy/requests.jsonl --incidents-dir $sandbox/state/incidents" "$sandbox/why-args"
run_capture "$repo/bin/claude-ollama" --help
check_that "usage lists why" grep -q '^why \[--since MINUTES\] \[--json\]' "$sandbox/out"
check_that "usage lists prefix-ab" grep -q '^prefix-ab \[size\] \[--limit N\] \[--json\]' "$sandbox/out"
check_that "usage lists tool-budget" grep -q '^tool-budget \[--since DAYS\] \[--json\]' "$sandbox/out"

cat > "$sandbox/stubbin/tool-budget" <<EOF
#!/bin/sh
printf '%s\n' "\$*" > "$sandbox/budget-args"
echo "suggest: stub"
EOF
chmod +x "$sandbox/stubbin/tool-budget"
CLAUDE_OLLAMA_TOOL_BUDGET_BIN="$sandbox/stubbin/tool-budget" run_capture "$repo/bin/claude-ollama" tool-budget --since 7 --json
check_eq "tool-budget exit status" 0 "$?"
check_that "tool-budget reads the console proxy log and the telemetry log and passes its flags" grep -qxF -- "--proxy-log $HOME/.local/share/claude-custom/console/proxy/requests.jsonl --telemetry $HOME/.claude-ollama/telemetry/tool-calls.jsonl --since 7 --json" "$sandbox/budget-args"
check_that "tool-budget prints the report" grep -qxF "suggest: stub" "$sandbox/out"
check_not "tool-budget does not launch claude" grep -q '^ARGS:' "$sandbox/out"
check_not "tool-budget does not start the proxy" test -e "$sandbox/proxy-args"
rm -f "$sandbox/budget-args"
mkdir -p "$sandbox/state"
CLAUDE_CONSOLE_STATE_DIR="$sandbox/state" CLAUDE_TOOL_TELEMETRY="$sandbox/calls.jsonl" CLAUDE_OLLAMA_TOOL_BUDGET_BIN="$sandbox/stubbin/tool-budget" run_capture "$repo/bin/claude-ollama" tool-budget
check_that "tool-budget reads the console state dir and CLAUDE_TOOL_TELEMETRY when they are set" grep -qxF -- "--proxy-log $sandbox/state/proxy/requests.jsonl --telemetry $sandbox/calls.jsonl" "$sandbox/budget-args"
mkdir -p "$sandbox/realbin"
ln -sf "$real_python3" "$sandbox/realbin/python3"
PATH="$sandbox/realbin:$PATH" run_capture "$repo/bin/claude-ollama" tool-budget
check_eq "tool-budget with the real script exit status" 0 "$?"
check_that "tool-budget runs the real script by default" grep -q '^suggest: nothing to drop' "$sandbox/out"
mkdir -p "$sandbox/realbin"
ln -sf "$real_python3" "$sandbox/realbin/python3"
PATH="$sandbox/realbin:$PATH" run_capture "$repo/bin/claude-ollama" why
check_eq "why with the real script exit status" 0 "$?"
check_that "why runs the real script by default" grep -q '^verdict: nothing wrong' "$sandbox/out"

nvm_versions="$HOME/.nvm/versions/node"
for nvm_version in v20.11.0 v22.1.0 v22.9.0; do
  mkdir -p "$nvm_versions/$nvm_version/bin"
  printf '#!/bin/sh\necho %s\n' "$nvm_version" > "$nvm_versions/$nvm_version/bin/node"
  chmod +x "$nvm_versions/$nvm_version/bin/node"
done
mkdir -p "$sandbox/nvm-project/nested" "$HOME/.nvm/alias"
echo "20" > "$sandbox/nvm-project/.nvmrc"
session_path_head() { session_env PATH | cut -d: -f1; }
(cd "$sandbox/nvm-project/nested" && run_capture "$repo/bin/claude-ollama" 27b -p hi)
check_eq "a .nvmrc above the project folder puts that nvm node first on the session PATH" "$nvm_versions/v20.11.0/bin" "$(session_path_head)"
check_that "the launcher names the node it chose" grep -qxF "claude-ollama: node: $nvm_versions/v20.11.0/bin/node (nvm 20 from $sandbox/nvm-project/.nvmrc)" "$sandbox/err"
echo "lts/*" > "$HOME/.nvm/alias/default"
echo "v22.1.0" > "$HOME/.nvm/alias/pinned"
(cd "$sandbox" && run_capture "$repo/bin/claude-ollama" 27b -p hi)
check_eq "without a .nvmrc the default alias picks the newest installed node" "$nvm_versions/v22.9.0/bin" "$(session_path_head)"
check_that "the launcher names the default alias" grep -qxF "claude-ollama: node: $nvm_versions/v22.9.0/bin/node (nvm default)" "$sandbox/err"
echo "pinned" > "$HOME/.nvm/alias/default"
(cd "$sandbox" && run_capture "$repo/bin/claude-ollama" 27b -p hi)
check_eq "an alias that names another alias is followed" "$nvm_versions/v22.1.0/bin" "$(session_path_head)"
echo "18" > "$sandbox/nvm-project/.nvmrc"
(cd "$sandbox/nvm-project" && run_capture "$repo/bin/claude-ollama" 27b -p hi)
check_that "a version nvm has not installed leaves PATH alone and warns" grep -qxF "claude-ollama: node: nvm has no node 18 installed (from $sandbox/nvm-project/.nvmrc); using $(command -v node || echo none)" "$sandbox/err"
check_not "and puts no nvm folder on the session PATH" contains "$(session_path_head)" "$nvm_versions"
NVM_DIR="$sandbox/other-nvm" run_capture "$repo/bin/claude-ollama" 27b -p hi
check_not "without an nvm install the launcher says nothing about node" grep -q "claude-ollama: node:" "$sandbox/err"
check_not "and leaves PATH alone" contains "$(session_path_head)" "$nvm_versions"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
