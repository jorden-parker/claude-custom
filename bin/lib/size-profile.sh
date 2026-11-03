#!/bin/bash
repo_dir="${repo_dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
profile_dir="$repo_dir/ollama"
profile_overlay="$repo_dir/shared/profile-overlay"
profiles_dir="${XDG_CONFIG_HOME:-$HOME/.config}/claude-custom/profiles"
session_config_dir="$HOME/.claude-ollama"
composed_settings="$session_config_dir/launch-settings.json"
embedding_model="${CODE_SEARCH_MODEL:-qwen3-embedding:0.6b}"
fetch_domains_file="${XDG_CONFIG_HOME:-$HOME/.config}/claude-custom/fetch-domains"
fetch_domain_pattern='^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z][a-z0-9-]*[a-z0-9]$'

configured_sizes() {
  local settings size
  for settings in "$profile_dir"/settings.*.json; do
    size="${settings##*/settings.}"
    size="${size%.json}"
    if is_configured_size "$size"; then
      printf '%s\n' "$size"
    fi
  done
}

is_configured_size() {
  [ -f "$profile_dir/settings.$1.json" ] && [ -f "$profile_dir/Modelfile.$1" ]
}

use_size() {
  size="$1"
  settings_file="$profile_dir/settings.$size.json"
  launch_settings="$settings_file"
  profile_file="$profiles_dir/ollama-$size.json"
}

size_model() {
  jq -r .model "$settings_file"
}

base_model() {
  sed -n 's/^FROM //p' "$profile_dir/Modelfile.$size"
}

modelfile_num_ctx() {
  modelfile_parameters | sed -n 's/^num_ctx //p'
}

modelfile_parameters() {
  sed -n 's/^PARAMETER //p' "$profile_dir/Modelfile.$size" | "$profile_overlay" parameters "$profile_file"
}

profile_context_tokens() {
  jq -r .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS "$launch_settings"
}

profile_output_tokens() {
  jq -r .env.CLAUDE_CODE_MAX_OUTPUT_TOKENS "$launch_settings"
}

summary_reserve() {
  jq -r .summary_reserve "$profile_dir/headroom.json"
}

context_headroom() {
  echo $(( $(modelfile_num_ctx) - $(profile_context_tokens) - $(profile_output_tokens) ))
}

profile_summary() {
  "$profile_overlay" summary "$profile_file"
}

load_profile() {
  "$profile_overlay" check "$profile_file" || exit 1
  eval "$("$profile_overlay" env "$profile_file")"
}

pinned_models() {
  printf '%s\n' "$(base_model)" "$embedding_model"
}

pinned_digest() {
  jq -r --arg name "$1" '.[$name] // empty' "$profile_dir/model-digests.json"
}

fetch_domains() {
  local line domain seen=" "
  [ -r "$fetch_domains_file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    domain="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$domain" ] || continue
    if [[ ! "$domain" =~ $fetch_domain_pattern ]]; then
      echo "claude-ollama: ignoring fetch domain '$domain' (expected a hostname like docs.python.org)" >&2
      continue
    fi
    case "$seen" in *" $domain "*) continue ;; esac
    seen="$seen$domain "
    printf '%s\n' "$domain"
  done < "$fetch_domains_file"
}

settings_layers() {
  local domain
  while IFS= read -r domain; do
    [ -z "$domain" ] || printf -- '--fetch-domain\n%s\n' "$domain"
  done <<< "${launch_fetch_domains:-}"
  [ ! -e "$profile_file" ] || printf -- '--profile\n%s\n' "$profile_file"
  [ -z "${ladder_context:-}" ] || printf -- '--context\n%s\n' "$ladder_context"
  [ -z "${proxy_url:-}" ] || printf -- '--proxy-url\n%s\n' "$proxy_url"
}

compose_launch_settings() {
  local layers=() layer
  while IFS= read -r layer; do layers+=("$layer"); done < <(settings_layers)
  mkdir -p "$session_config_dir"
  rm -f "$composed_settings"
  if [ ${#layers[@]} -eq 0 ]; then
    launch_settings="$settings_file"
    return 0
  fi
  "$profile_overlay" compose "$settings_file" "$composed_settings" "${layers[@]}"
  launch_settings="$composed_settings"
}

add_mcp_server() {
  [ "$("$profile_overlay" mcp "$profile_file" "$1")" = true ] || return 0
  servers="${servers:+$servers,}\"$1\":{\"command\":\"$2\",\"args\":[\"python3\",\"$3\"]}"
}

mcp_config() {
  servers=""
  add_mcp_server code-search "$repo_dir/shared/host-env" "$repo_dir/shared/mcp/code-search.py"
  add_mcp_server repo "$repo_dir/shared/host-env" "$repo_dir/shared/mcp/repo-tools.py"
  add_mcp_server dev "$repo_dir/shared/host-env" "$repo_dir/shared/mcp/dev-server.py"
  printf '{"mcpServers":{%s}}' "$servers"
}
