#!/bin/bash
repo_dir="${repo_dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
profile_dir="$repo_dir/ollama"
profile_overlay="$repo_dir/shared/profile-overlay"
profiles_dir="${XDG_CONFIG_HOME:-$HOME/.config}/claude-custom/profiles"
session_config_dir="$HOME/.claude-ollama"
launch_settings_dir="$session_config_dir/launch-settings"
composed_settings="$launch_settings_dir/$$.json"
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

compaction_point() {
  local output window by_percent by_buffer
  output="$(profile_output_tokens)"
  [ "$output" -le 20000 ] || output=20000
  window=$(( $(profile_context_tokens) - output ))
  by_percent=$(( window * $(jq -r '.env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE // 100' "$launch_settings") / 100 ))
  by_buffer=$(( window - 13000 ))
  if [ "$by_percent" -lt "$by_buffer" ]; then echo "$by_percent"; else echo "$by_buffer"; fi
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

prepare_launch_settings_dir() {
  local file pid
  mkdir -p "$launch_settings_dir"
  chmod 700 "$launch_settings_dir"
  for file in "$launch_settings_dir"/*.json; do
    [ -e "$file" ] || continue
    pid="$(basename "$file" .json)"
    case "$pid" in
      *[!0-9]*) continue ;;
    esac
    kill -0 "$pid" 2>/dev/null || rm -f "$file"
  done
}

remove_composed_settings() {
  rm -f "$composed_settings"
}

use_throwaway_settings() {
  composed_settings="$(mktemp "${TMPDIR:-/tmp}/claude-ollama-settings.XXXXXX")"
  trap remove_composed_settings EXIT
}

settings_layer_labels() {
  settings_layers | awk '/^--/ { sub(/^--/, ""); if (!seen[$0]++) { printf "%s%s", separator, $0; separator = ", " } }'
}

external_backend_on() {
  [ -n "${CLAUDE_OLLAMA_EXTERNAL_URL:-}" ] && [ -n "${CLAUDE_OLLAMA_EXTERNAL_MODEL:-}" ]
}

external_backend_layer() {
  jq --arg proxy_url "${proxy_url:-}" '
    ($ENV.CLAUDE_OLLAMA_EXTERNAL_MODEL) as $model
    | .model = $model
    | .availableModels = [$model]
    | .env.ANTHROPIC_BASE_URL = (if $proxy_url != "" then $proxy_url else $ENV.CLAUDE_OLLAMA_EXTERNAL_URL end)
    | .env |= with_entries(if (.key | test("^ANTHROPIC_DEFAULT_.*_MODEL$")) then .value = $model else . end)
    | if ($ENV.CLAUDE_OLLAMA_EXTERNAL_TOKEN // "") != "" then .env.ANTHROPIC_AUTH_TOKEN = $ENV.CLAUDE_OLLAMA_EXTERNAL_TOKEN else . end'
}

apply_external_backend() {
  local external_settings
  external_settings="$(external_backend_layer < "$1")" || return 1
  (umask 077 && printf '%s\n' "$external_settings" > "$composed_settings")
}

compose_launch_settings() {
  local layers=() layer base_settings="$settings_file"
  while IFS= read -r layer; do layers+=("$layer"); done < <(settings_layers)
  remove_composed_settings
  if [ ${#layers[@]} -eq 0 ] && ! external_backend_on; then
    launch_settings="$settings_file"
    return 0
  fi
  if [ ${#layers[@]} -gt 0 ]; then
    "$profile_overlay" compose "$settings_file" "$composed_settings" "${layers[@]}"
    base_settings="$composed_settings"
  fi
  ! external_backend_on || apply_external_backend "$base_settings"
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
