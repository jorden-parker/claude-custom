#!/bin/bash
. "$(dirname "${BASH_SOURCE[0]}")/model-server.sh"
minimum_server_build=9200

require_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  echo "claude-ollama: jq is required (brew install jq)" >&2
  exit 1
}

require_size() {
  is_configured_size "${1:-}" && return 0
  echo "$2: unknown size '${1:-}' (sizes: $(configured_sizes | tr '\n' ' ' | sed 's/ $//'))" >&2
  exit 2
}

report() {
  printf '%-4s %s\n' "$1" "$2"
  [ "$1" != fail ]
}

check_context_sizes() {
  local ctx tokens
  ctx="$(preset_ctx_size)"
  tokens="$(profile_context_tokens)"
  if [ "$ctx" -ge "$tokens" ]; then
    report ok "num_ctx $ctx matches CLAUDE_CODE_MAX_CONTEXT_TOKENS $tokens; Claude Code compacts at $(compaction_point) tokens"
  else
    report fail "num_ctx $ctx is below CLAUDE_CODE_MAX_CONTEXT_TOKENS $tokens (run bin/ollama-profiles)"
  fi
}

server_address() {
  local url
  url="$(server_url)"
  url="${url#*://}"
  printf '%s\n' "${url%%/*}"
}

check_server() {
  local build
  if ! server_up; then
    report fail "llama-server not answering at $(server_url) (claude-custom agent -apply, then claude-ollama logs)"
    return 1
  fi
  build="$(server_build || echo 0)"
  if [ "$build" -ge "$minimum_server_build" ] 2>/dev/null; then
    report ok "llama-server build $build on $(server_address)"
  else
    report warn "llama-server build $build on $(server_address) is below $minimum_server_build (brew upgrade llama.cpp)"
  fi
}

check_preset_listed() {
  server_up || return 0
  if model_listed "$1"; then
    report ok "preset $1 listed"
  else
    report fail "preset $1 not in llama-server's /models (claude-custom agent -apply)"
  fi
}

check_weights_file() {
  local label="$1" spec="$2" fix="$3" level="$4" file
  file="${spec##* }"
  if gguf_file_ok "$spec"; then
    report ok "$label $file (sha256 matches)"
  elif [ -f "$(weights_dir)/$file" ]; then
    report "$level" "$label $file does not match its pin ($fix)"
  else
    report "$level" "$label $file missing ($fix)"
  fi
}

check_weights() {
  local spec
  spec="$(size_gguf "$size")" || { report fail "size $size has no pinned gguf in ollama/sizes.json"; return 1; }
  check_weights_file weights "$spec" "claude-ollama prepare $size" fail
}

check_embedding_weights() {
  local spec
  spec="$(embedding_gguf)" || { report warn "ollama/embedding.json has no pinned gguf"; return 0; }
  check_weights_file "embedding weights" "$spec" "claude-ollama prepare-embedding" warn
}

check_user_presets() {
  if "$repo_dir/bin/ollama-profiles" --user-presets --check >/dev/null 2>&1; then
    report ok "user presets current"
  else
    report warn "user presets stale: run claude-custom agent -apply"
  fi
}

check_gh_login() {
  if command -v gh >/dev/null && gh auth token --hostname github.com >/dev/null 2>&1; then
    report ok "gh logged in to github.com (the session's GitHub tools run your gh)"
  else
    report warn "gh is not logged in to github.com (the session's GitHub tools will fail; run gh auth login)"
  fi
}
