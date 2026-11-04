#!/bin/bash
. "$(dirname "${BASH_SOURCE[0]}")/size-profile.sh"
ollama_url="${OLLAMA_HOST:-http://127.0.0.1:11434}"
case "$ollama_url" in http://*|https://*) ;; *) ollama_url="http://$ollama_url" ;; esac

installed_digest() {
  curl -sf -m 5 "$ollama_url/api/tags" |
    jq -r --arg name "$1" '.models[]? | select(.name == $name or .name == ($name + ":latest")) | .digest'
}

running_server_env() {
  local pid
  pid="$(pgrep -x ollama | head -n 1)" || true
  [ -n "$pid" ] || return 1
  if [ -r "/proc/$pid/environ" ]; then
    tr '\0' '\n' < "/proc/$pid/environ"
  else
    ps -Eo command -p "$pid" | tr ' ' '\n'
  fi
}

missing_server_env() {
  local env_lines wanted
  env_lines="$(running_server_env)" || return 1
  while IFS= read -r wanted; do
    [ -n "$wanted" ] || continue
    printf '%s\n' "$env_lines" | grep -qxF "$wanted" || printf '%s\n' "$wanted"
  done < "$profile_dir/server.env"
}

plist_log_path() {
  local plist="$HOME/Library/LaunchAgents/$1.plist"
  [ -f "$plist" ] || return 0
  sed -n 's|.*<key>StandardOutPath</key><string>\(.*\)</string>.*|\1|p' "$plist" | head -n 1
}

brew_log_path() {
  echo "${HOMEBREW_PREFIX:-/opt/homebrew}/var/log/ollama.log"
}

running_ollama_label() {
  command -v launchctl >/dev/null 2>&1 || return 0
  launchctl list 2>/dev/null | awk '$1 ~ /^[0-9]+$/ && ($3 == "local.ollama" || $3 == "sh.brew.ollama" || $3 == "homebrew.mxcl.ollama") { print $3; exit }'
}

running_log_path() {
  local label path
  label="$(running_ollama_label)"
  [ -n "$label" ] || return 0
  path="$(plist_log_path "$label")"
  if [ -z "$path" ] && [ "$label" != local.ollama ]; then
    path="$(brew_log_path)"
  fi
  echo "$path"
}

server_log_path() {
  local candidate
  for candidate in "$(running_log_path)" "$(plist_log_path local.ollama)" "$(brew_log_path)" "$HOME/.ollama/logs/server.log"; do
    if [ -n "$candidate" ] && [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}
