#!/bin/bash
. "$(dirname "${BASH_SOURCE[0]}")/ollama-server.sh"

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

check_model_present() {
  local label="$1" name="$2" fix="$3" level="${4:-fail}"
  if ollama show "$name" >/dev/null 2>&1; then
    report ok "$label $name"
  else
    report "$level" "$label $name missing ($fix)"
  fi
}

check_digest() {
  local name="$1" actual pin
  actual="$(installed_digest "$name")"
  pin="$(pinned_digest "$name")"
  [ -n "$actual" ] && [ -n "$pin" ] || return 0
  if [ "$actual" = "$pin" ]; then
    report ok "digest $name matches its pin"
  else
    report fail "digest $name is $actual, not the pinned $pin (ollama rm $name, then relaunch)"
  fi
}

check_digests() {
  local name status=0
  for name in $(pinned_models); do
    check_digest "$name" || status=1
  done
  return "$status"
}

check_context_sizes() {
  local ctx tokens
  ctx="$(modelfile_num_ctx)"
  tokens="$(profile_context_tokens)"
  if [ "$ctx" -ge "$tokens" ]; then
    report ok "num_ctx $ctx matches CLAUDE_CODE_MAX_CONTEXT_TOKENS $tokens; Claude Code compacts at $(compaction_point) tokens"
  else
    report fail "num_ctx $ctx is below CLAUDE_CODE_MAX_CONTEXT_TOKENS $tokens (run bin/ollama-profiles)"
  fi
}

check_reachable() {
  if curl -sf -m 2 "$ollama_url/api/version" >/dev/null 2>&1; then
    report ok "ollama reachable at $ollama_url"
  else
    report fail "ollama not reachable at $ollama_url (brew services start ollama)"
  fi
}

check_server_env() {
  local missing wanted status=0
  if ! missing="$(missing_server_env)"; then
    report fail "ollama server not running (brew services start ollama)"
    return 1
  fi
  while IFS= read -r wanted; do
    [ -n "$wanted" ] || continue
    if printf '%s\n' "$missing" | grep -qxF "$wanted"; then
      report fail "server env $wanted not set on the running server"
      status=1
    else
      report ok "server env $wanted"
    fi
  done < "$profile_dir/server.env"
  [ "$status" -eq 0 ] || echo "     fix: claude-custom agent -apply"
  return "$status"
}

check_gh_login() {
  if command -v gh >/dev/null && gh auth token --hostname github.com >/dev/null 2>&1; then
    report ok "gh logged in to github.com (the session's GitHub tools run your gh)"
  else
    report warn "gh is not logged in to github.com (the session's GitHub tools will fail; run gh auth login)"
  fi
}
